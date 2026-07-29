#!/usr/bin/env bash
# upload-transcript.sh 회귀 테스트 — 코칭 단위 동의 게이트 + floor 산술 + 결손 보고.
#
# 실행: bash plugins/rona-alpha/skills/rona-alpha/hooks/__tests__/upload-transcript.test.sh
#
# RONA_HOOK_DRYRUN=1 로 네트워크를 타지 않고 훅의 판정·산술만 관찰한다. HOME 을 임시
# 디렉토리로 갈아끼워 실제 ~/.rona 와 ~/.claude 를 건드리지 않는다(훅이 두 경로를 전부
# $HOME 기준으로 계산하므로 이 치환 하나로 격리가 끝난다).
#
# 반드시 지켜야 하는 두 단언(이게 깨지면 "동의 이후만 수집"이 정반대로 뒤집힌다):
#   ① 첫 전송은 offset=0 으로 나간다   (서버 append 조건은 행이 있을 때만 성립)
#   ② 409 복구 후 재전송 시작점 == FLOOR (파일 처음으로 내려가지 않는다)

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/upload-transcript.sh"
TESTHOME="$(mktemp -d 2>/dev/null)"
trap 'rm -rf "$TESTHOME"' EXIT

TOKEN="11111111-2222-3333-4444-555555555555"
PROJ="$TESTHOME/.claude/projects/p"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n     ---- 실제 출력 ----\n%s\n     -------------------\n' "$1" "$2"; }

has()    { printf '%s' "$1" | grep -qF -- "$2"; }
assert_has()     { if has "$2" "$3"; then ok "$1"; else bad "$1 (기대: $3)" "$2"; fi; }
assert_lacks()   { if has "$2" "$3"; then bad "$1 (없어야 함: $3)" "$2"; else ok "$1"; fi; }
assert_empty()   { if [ -z "$2" ]; then ok "$1"; else bad "$1 (출력이 없어야 함)" "$2"; fi; }
assert_file()    { if [ -f "$2" ]; then ok "$1"; else bad "$1 (파일 없음: $2)" ""; fi; }
assert_no_file() { if [ -f "$2" ]; then bad "$1 (파일이 있으면 안 됨: $2)" "$(cat "$2" 2>/dev/null)"; else ok "$1"; fi; }
assert_eq()      { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3', 실제 '$2')" ""; fi; }

# ── 헬퍼 ────────────────────────────────────────────────────────────────────
hook_json() {  # $1=session_id $2=transcript_path $3=event
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"%s","tool_name":"Bash"}' "$1" "$2" "$3"
}

# 훅 1회 발사. 기본 이벤트는 SessionEnd — 스로틀 면제라 케이스마다 2분을 기다리지 않는다.
fire() {  # $1=session_id $2=transcript_path [$3=event]
  hook_json "$1" "$2" "${3:-SessionEnd}" \
    | HOME="$TESTHOME" RONA_HOOK_DRYRUN=1 bash "$HOOK" 2>/dev/null
}

sess_new() {  # $1=session_id — 토큰 마커를 붙인 새 세션 준비
  mkdir -p "$TESTHOME/.rona/session"
  printf '%s' "$TOKEN" > "$TESTHOME/.rona/session/$1.token"
}

consent_on()  { mkdir -p "$TESTHOME/.rona/consent"; : > "$TESTHOME/.rona/consent/$TOKEN"; }
consent_off() { rm -f "$TESTHOME/.rona/consent/$TOKEN"; }

grow() {  # $1=파일 $2=바이트 수 — 파일을 정확히 그 크기로 만든다
  mkdir -p "$(dirname "$1")"
  : > "$1"
  local i=0
  while [ "$i" -lt "$2" ]; do printf 'x' >> "$1"; i=$((i + 1)); done
}

marker() { cat "$TESTHOME/.rona/session/$1" 2>/dev/null; }

mkdir -p "$PROJ" "$TESTHOME/.rona/session"

echo "=== A. 무흔적 게이트 (토큰 마커) ==="
JSONL_A="$PROJ/a.jsonl"; grow "$JSONL_A" 100
OUT="$(fire "sA" "$JSONL_A")"
assert_empty "A1. 토큰 마커 없는 세션 → 출력 없음" "$OUT"
assert_no_file "A2. 토큰 마커 없는 세션 → 결과 마커도 안 남김(설계상 보고할 주소 없음)" \
  "$TESTHOME/.rona/session/sA.transcript-result"

echo "=== B. 동의 게이트 (코칭 단위) ==="
sess_new "sB"; consent_off
JSONL_B="$PROJ/b.jsonl"; grow "$JSONL_B" 100
OUT="$(fire "sB" "$JSONL_B")"
assert_has  "B1. 동의 마커 없음 + 프로브 이력 없음 → 서버에 프로브" "$OUT" "PROBE POST"
assert_lacks "B2. 프로브 단계에서 전송으로 넘어가지 않음"           "$OUT" "UPLOAD PUT"
assert_no_file "B3. 동의 전에는 floor 를 잡지 않는다(거절 후 재부여 시점이 floor)" \
  "$TESTHOME/.rona/session/sB.floor"

: > "$TESTHOME/.rona/session/sB.probe"
OUT="$(fire "sB" "$JSONL_B")"
assert_has  "B4. 프로브 이력 있음(403 받았던 세션) → no_consent 결과" "$OUT" "RESULT status=no_consent"
assert_lacks "B5. 세션당 프로브 1회 — 재발사에 프로브 없음"          "$OUT" "PROBE POST"

sess_new "sB2"; consent_on
JSONL_B2="$PROJ/b2.jsonl"; grow "$JSONL_B2" 100
: > "$TESTHOME/.rona/session/sB2.probe"
OUT="$(fire "sB2" "$JSONL_B2")"
assert_lacks "B6. 동의 마커가 있으면 프로브 이력을 무시하고 통과" "$OUT" "no_consent"

echo "=== C. floor 선점 + 첫 전송 ==="
sess_new "sC"; consent_on
JSONL_C="$PROJ/c.jsonl"; grow "$JSONL_C" 100
OUT="$(fire "sC" "$JSONL_C")"
assert_eq   "C1. 첫 통과 시 floor = 그 순간 파일 크기(이전 대화 차단)" "$(marker sC.floor)" "100"
assert_empty "C2. 동의 이후 새로 붙은 게 없으면 전송 안 함"           "$OUT"

grow "$JSONL_C" 250
OUT="$(fire "sC" "$JSONL_C")"
assert_has "C3. floor 이후분만 delta 로 잡힌다" "$OUT" \
  "DELTA floor=100 offset=0 start=100 bytes=250 delta_raw=150"
assert_has "C4. ★단언① 첫 전송은 offset=0 (서버 리셋 경로 → 행 생성)" "$OUT" "&offset=0"
assert_has "C5. 리셋 전송엔 잘라낸 앞부분 길이(start)를 함께 알린다"   "$OUT" "&start=100"
assert_has "C6. 잘라 보내는 시작 바이트가 floor+1"                     "$OUT" "gzip tail +101"

# 업로드 성공 시 훅이 하는 일: .offset = BYTES - FLOOR
printf '150' > "$TESTHOME/.rona/session/sC.offset"
grow "$JSONL_C" 400
OUT="$(fire "sC" "$JSONL_C")"
assert_has   "C7. 두 번째 전송은 서버 저장 bytes 를 offset 으로 이어붙인다" "$OUT" \
  "DELTA floor=100 offset=150 start=250 bytes=400 delta_raw=150"
assert_has   "C8. append 전송 쿼리 offset=150"        "$OUT" "&offset=150"
assert_lacks "C9. append 전송엔 start 를 붙이지 않음" "$OUT" "&start="

echo "=== D. 409 자가복구 ==="
# 409 핸들러가 하는 일 = .offset 을 0 으로 리셋. 그 다음 발사를 관찰한다.
printf '0' > "$TESTHOME/.rona/session/sC.offset"
OUT="$(fire "sC" "$JSONL_C")"
assert_has "D1. ★단언② 409 후 재전송 시작점 == FLOOR (파일 처음으로 안 내려감)" "$OUT" \
  "DELTA floor=100 offset=0 start=100 bytes=400 delta_raw=300"
assert_has "D2. 409 복구 전송도 start=FLOOR 를 실어 보낸다" "$OUT" "&start=100"

echo "=== E. floor 없이 이어받은 구버전 세션 ==="
sess_new "sE"; consent_on
JSONL_E="$PROJ/e.jsonl"; grow "$JSONL_E" 300
printf '50' > "$TESTHOME/.rona/session/sE.offset"   # 구버전 .offset = 파일 절대 위치
OUT="$(fire "sE" "$JSONL_E")"
assert_has "E1. .offset 만 있으면 floor=0 — 서버 저장분과 갭 없이 이어진다" "$OUT" \
  "DELTA floor=0 offset=50 start=50 bytes=300 delta_raw=250"

echo "=== F. 파일 축소·회전 ==="
sess_new "sF"; consent_on
JSONL_F="$PROJ/f.jsonl"; grow "$JSONL_F" 250
printf '1000' > "$TESTHOME/.rona/session/sF.floor"
printf '40'   > "$TESTHOME/.rona/session/sF.offset"
OUT="$(fire "sF" "$JSONL_F")"
assert_has "F1. floor 가 파일보다 크면 기준을 처음부터 다시 잡는다" "$OUT" \
  "DELTA floor=0 offset=0 start=0 bytes=250 delta_raw=250"
assert_eq  "F2. floor 마커도 0 으로 갱신" "$(marker sF.floor)" "0"

echo "=== G. 결손 3종 (무흔적 종료 제거) ==="
sess_new "sG1"; consent_on
OUT="$(fire "sG1" "" SessionEnd)"
assert_has  "G1a. transcript_path 부재 → 결과 마커"   "$OUT" "RESULT status=no_transcript_path"
assert_has  "G1b. transcript_path 부재 → 서버에 결손 보고" "$OUT" '"skip_reason":"no_transcript_path"'

sess_new "sG2"; consent_on
OUT="$(fire "sG2" "/tmp/evil.jsonl")"
assert_has  "G2a. 허용 밖 경로 → 결과 마커"      "$OUT" "RESULT status=path_not_allowed"
assert_has  "G2b. 허용 밖 경로 → 서버에 결손 보고" "$OUT" '"skip_reason":"path_not_allowed"'

sess_new "sG3"; consent_on
OUT="$(fire "sG3" "$TESTHOME/.claude/../etc/x.jsonl")"
assert_has  "G3. 상위 탈출(..) 경로도 path_not_allowed" "$OUT" "RESULT status=path_not_allowed"

sess_new "sG4"; consent_on
OUT="$(fire "sG4" "$PROJ/nope.jsonl")"
assert_has  "G4a. 파일 없음 → 결과 마커"      "$OUT" "RESULT status=file_missing"
assert_has  "G4b. 파일 없음 → 서버에 결손 보고" "$OUT" '"skip_reason":"file_missing"'

OUT="$(fire "sG4" "$PROJ/nope.jsonl")"
assert_has   "G5a. 같은 사유 재발사도 결과 마커는 갱신" "$OUT" "RESULT status=file_missing"
assert_lacks "G5b. 결손 보고는 세션당 사유당 1회(폭주 차단)" "$OUT" "SKIP POST"

echo "=== H. 스로틀 / 킬스위치 ==="
sess_new "sH"; consent_on
JSONL_H="$PROJ/h.jsonl"; grow "$JSONL_H" 100
fire "sH" "$JSONL_H" >/dev/null            # floor 선점
grow "$JSONL_H" 200
rm -f "$TESTHOME/.rona/session/sH.transcript"   # 수동 전송 = 스로틀 마커를 지워 창을 여는 경로
OUT="$(fire "sH" "$JSONL_H" Stop)"
assert_has  "H1. Stop 이벤트 정상 전송" "$OUT" "UPLOAD PUT"
OUT="$(fire "sH" "$JSONL_H" Stop)"
assert_empty "H2. 2분 스로틀 — 직후 Stop 재발사는 조용히 skip" "$OUT"
OUT="$(fire "sH" "$JSONL_H" SessionEnd)"
assert_has  "H3. SessionEnd 는 스로틀 면제" "$OUT" "DELTA"

OUT="$(hook_json "sH" "$JSONL_H" SessionEnd \
  | HOME="$TESTHOME" RONA_HOOK_DRYRUN=1 RONA_TRANSCRIPT_HOOK_DISABLED=1 bash "$HOOK" 2>/dev/null)"
assert_empty "H4. RONA_TRANSCRIPT_HOOK_DISABLED=1 → 전면 무력화" "$OUT"

echo "=== I. 제거된 경로 (회귀) ==="
sess_new "sI"; consent_on
JSONL_I="$PROJ/i.jsonl"; grow "$JSONL_I" 100
fire "sI" "$JSONL_I" >/dev/null
grow "$JSONL_I" 200
: > "$TESTHOME/.rona/session/sI.no-send"          # 옛 '이 세션만 빼기' 마커
OUT="$(fire "sI" "$JSONL_I")"
assert_lacks "I1. .no-send 마커는 더 이상 아무 효과가 없다" "$OUT" "excluded"
assert_has   "I2. .no-send 가 있어도 정상 전송"             "$OUT" "UPLOAD PUT"

sess_new "sI2"; consent_off
: > "$TESTHOME/.rona/transcript-consent"          # 옛 계정 단위 동의 마커
JSONL_I2="$PROJ/i2.jsonl"; grow "$JSONL_I2" 100
OUT="$(fire "sI2" "$JSONL_I2")"
assert_has "I3. 계정 단위 동의 마커로는 통과하지 못한다(코칭 단위로 다시 묻는다)" "$OUT" "PROBE POST"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
