#!/usr/bin/env bash
# upload-transcript.sh 회귀 테스트 — 코칭 단위 동의 게이트 + floor 산술 + 결손 보고.
#
# 실행: bash plugins/rona-alpha/skills/rona-alpha/hooks/__tests__/upload-transcript.test.sh
#
# 두 가지 방식으로 돌린다.
#   ① RONA_HOOK_DRYRUN=1 — 네트워크 없이 훅의 판정·산술만 관찰(§A~K).
#   ② curl 스텁 — PATH 앞에 가짜 curl 을 심어 http_code 를 우리가 정한다. 응답 코드에
#      따라 갈리는 실제 분기(프로브 200/403, 결손 보고 200/400, 게이트 403)를 관찰(§L).
# HOME 을 임시 디렉토리로 갈아끼워 실제 ~/.rona 와 ~/.claude 를 건드리지 않는다(훅이 두
# 경로를 전부 $HOME 기준으로 계산하므로 이 치환 하나로 격리가 끝난다).
#
# 반드시 지켜야 하는 두 단언(이게 깨지면 "동의 이후만 수집"이 정반대로 뒤집힌다):
#   ① 첫 전송은 offset=0 으로 나간다   (서버 append 조건은 행이 있을 때만 성립)
#   ② 409 복구 후 재전송 시작점 == FLOOR (파일 처음으로 내려가지 않는다)

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/upload-transcript.sh"
TESTHOME="$(mktemp -d 2>/dev/null)"
trap 'rm -rf "$TESTHOME"' EXIT

TOK="11111111-2222-3333-4444-555555555555"
TOK_B="99999999-8888-7777-6666-555555555555"
PROJ="$TESTHOME/.claude/projects/p"

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n     ---- 실제 ----\n%s\n     --------------\n' "$1" "$2"; }

has()            { printf '%s' "$1" | grep -qF -- "$2"; }
assert_has()     { if has "$2" "$3"; then ok "$1"; else bad "$1 (기대: $3)" "$2"; fi; }
assert_lacks()   { if has "$2" "$3"; then bad "$1 (없어야 함: $3)" "$2"; else ok "$1"; fi; }
assert_empty()   { if [ -z "$2" ]; then ok "$1"; else bad "$1 (출력이 없어야 함)" "$2"; fi; }
assert_file()    { if [ -e "$2" ]; then ok "$1"; else bad "$1 (없음: $2)" ""; fi; }
assert_no_file() { if [ -e "$2" ]; then bad "$1 (있으면 안 됨: $2)" "$(cat "$2" 2>/dev/null)"; else ok "$1"; fi; }
assert_eq()      { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3', 실제 '$2')" ""; fi; }

# ── 헬퍼 ────────────────────────────────────────────────────────────────────
hook_json() {  # $1=session_id $2=transcript_path $3=event
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"%s","tool_name":"Bash"}' "$1" "$2" "$3"
}

# 훅 1회 발사(dryrun). 기본 이벤트는 SessionEnd — 스로틀 면제라 케이스마다 2분을 안 기다린다.
fire() {  # $1=session_id $2=transcript_path [$3=event]
  hook_json "$1" "$2" "${3:-SessionEnd}" \
    | HOME="$TESTHOME" RONA_HOOK_DRYRUN=1 bash "$HOOK" 2>/dev/null
}

sess_new() {  # $1=session_id [$2=token] — 토큰 마커를 붙인 세션 준비
  mkdir -p "$TESTHOME/.rona/session"
  printf '%s' "${2:-$TOK}" > "$TESTHOME/.rona/session/$1.token"
}

consent_on()  { mkdir -p "$TESTHOME/.rona/consent"; : > "$TESTHOME/.rona/consent/${1:-$TOK}"; }
consent_off() { rm -f "$TESTHOME/.rona/consent/${1:-$TOK}"; }

grow() {  # $1=파일 $2=바이트 수
  mkdir -p "$(dirname "$1")"
  : > "$1"
  head -c "$2" /dev/zero 2>/dev/null | tr '\0' 'x' >> "$1"
}

marker() { cat "$TESTHOME/.rona/session/$1" 2>/dev/null; }
mpath()  { printf '%s' "$TESTHOME/.rona/session/$1"; }

mkdir -p "$PROJ" "$TESTHOME/.rona/session"

echo "=== A. 무흔적 게이트 (토큰 마커) ==="
JSONL_A="$PROJ/a.jsonl"; grow "$JSONL_A" 100
OUT="$(fire "sA" "$JSONL_A")"
assert_empty "A1. 토큰 마커 없는 세션 → 출력 없음" "$OUT"
assert_no_file "A2. 토큰 마커 없는 세션 → 결과 마커도 안 남김(설계상 보고할 주소 없음)" \
  "$(mpath sA.transcript-result)"

echo "=== B. 동의 게이트 (코칭 단위) ==="
sess_new "sB"; consent_off
JSONL_B="$PROJ/b.jsonl"; grow "$JSONL_B" 100
OUT="$(fire "sB" "$JSONL_B")"
assert_has   "B1. 동의 마커 없음 + 프로브 이력 없음 → 서버에 프로브" "$OUT" "PROBE POST"
assert_lacks "B2. 프로브 단계에서 전송으로 넘어가지 않음"            "$OUT" "UPLOAD PUT"
assert_no_file "B3. 동의 전에는 floor 를 잡지 않는다(거절 후 재부여 시점이 floor)" \
  "$(mpath "sB.$TOK.floor")"

: > "$(mpath sB.probe)"
OUT="$(fire "sB" "$JSONL_B")"
assert_has   "B4. 프로브 이력 있음(403 받았던 세션) → no_consent 결과" "$OUT" "RESULT status=no_consent"
assert_lacks "B5. 세션당 프로브 1회 — 재발사에 프로브 없음"           "$OUT" "PROBE POST"

sess_new "sB2"; consent_on
JSONL_B2="$PROJ/b2.jsonl"; grow "$JSONL_B2" 100
: > "$(mpath sB2.probe)"
OUT="$(fire "sB2" "$JSONL_B2")"
assert_lacks "B6. 동의 마커가 있으면 프로브 이력을 무시하고 통과" "$OUT" "no_consent"

echo "=== C. floor 선점 + 첫 전송 ==="
sess_new "sC"; consent_on
JSONL_C="$PROJ/c.jsonl"; grow "$JSONL_C" 100
OUT="$(fire "sC" "$JSONL_C")"
assert_eq    "C1. 첫 통과 시 floor = 그 순간 파일 크기(이전 대화 차단)" "$(marker "sC.$TOK.floor")" "100"
assert_empty "C2. 동의 이후 새로 붙은 게 없으면 전송 안 함"            "$OUT"

grow "$JSONL_C" 250
OUT="$(fire "sC" "$JSONL_C")"
assert_has "C3. floor 이후분만 delta 로 잡힌다" "$OUT" \
  "DELTA floor=100 offset=0 start=100 bytes=250 delta_raw=150"
assert_has "C4. ★단언① 첫 전송은 offset=0 (서버 리셋 경로 → 행 생성)" "$OUT" "&offset=0"
assert_has "C5. 리셋 전송엔 잘라낸 앞부분 길이(start)를 함께 알린다"   "$OUT" "&start=100"
assert_has "C6. 잘라 보내는 시작 바이트가 floor+1"                     "$OUT" "gzip tail +101"

# 업로드 성공 시 훅이 하는 일: .offset = BYTES - FLOOR
printf '150' > "$(mpath "sC.$TOK.offset")"
grow "$JSONL_C" 400
OUT="$(fire "sC" "$JSONL_C")"
assert_has   "C7. 두 번째 전송은 서버 저장 bytes 를 offset 으로 이어붙인다" "$OUT" \
  "DELTA floor=100 offset=150 start=250 bytes=400 delta_raw=150"
assert_has   "C8. append 전송 쿼리 offset=150"        "$OUT" "&offset=150"
assert_lacks "C9. append 전송엔 start 를 붙이지 않음" "$OUT" "&start="

echo "=== D. 409 자가복구 ==="
# 409 핸들러가 하는 일 = .offset 을 0 으로 리셋. 그 다음 발사를 관찰한다.
printf '0' > "$(mpath "sC.$TOK.offset")"
OUT="$(fire "sC" "$JSONL_C")"
assert_has "D1. ★단언② 409 후 재전송 시작점 == FLOOR (파일 처음으로 안 내려감)" "$OUT" \
  "DELTA floor=100 offset=0 start=100 bytes=400 delta_raw=300"
assert_has "D2. 409 복구 전송도 start=FLOOR 를 실어 보낸다" "$OUT" "&start=100"

echo "=== E. floor 없이 이어받은 0.2.x 세션 (1회 이관) ==="
sess_new "sE"; consent_on
JSONL_E="$PROJ/e.jsonl"; grow "$JSONL_E" 300
printf '50' > "$(mpath sE.offset)"   # 0.2.x 의 세션 단위 offset(= 파일 절대 위치)
OUT="$(fire "sE" "$JSONL_E")"
assert_has     "E1. 세션 단위 offset 만 있으면 floor=0 — 서버 저장분과 갭 없이 이어진다" "$OUT" \
  "DELTA floor=0 offset=50 start=50 bytes=300 delta_raw=250"
assert_eq      "E2. 옛 offset 이 이 코칭 키로 이관된다" "$(marker "sE.$TOK.offset")" "50"
assert_no_file "E3. 이관 후 옛 마커는 제거(다음 코칭이 물려받지 않게)" "$(mpath sE.offset)"

echo "=== F. 파일 축소·회전 ==="
sess_new "sF"; consent_on
JSONL_F="$PROJ/f.jsonl"; grow "$JSONL_F" 250
printf '1000' > "$(mpath "sF.$TOK.floor")"
printf '40'   > "$(mpath "sF.$TOK.offset")"
OUT="$(fire "sF" "$JSONL_F")"
assert_eq    "F1. floor 가 파일보다 크면 지금 끝을 새 기준으로(0 으로 되돌리지 않는다)" \
  "$(marker "sF.$TOK.floor")" "250"
assert_empty "F2. 새 기준 == 파일 끝이라 이번엔 보낼 게 없다" "$OUT"
assert_eq    "F3. offset 도 리셋" "$(marker "sF.$TOK.offset")" "0"
grow "$JSONL_F" 400
OUT="$(fire "sF" "$JSONL_F")"
assert_has   "F4. 회전 후 새로 쌓인 분만 전송" "$OUT" \
  "DELTA floor=250 offset=0 start=250 bytes=400 delta_raw=150"

echo "=== G. 결손 3종 (무흔적 종료 제거) ==="
sess_new "sG1"; consent_on
OUT="$(fire "sG1" "" SessionEnd)"
assert_has "G1a. transcript_path 부재 → 결과 마커"       "$OUT" "RESULT status=no_transcript_path"
assert_has "G1b. transcript_path 부재 → 서버에 결손 보고" "$OUT" '"skip_reason":"no_transcript_path"'

sess_new "sG2"; consent_on
OUT="$(fire "sG2" "/tmp/evil.jsonl")"
assert_has "G2a. 허용 밖 경로 → 결과 마커"       "$OUT" "RESULT status=path_not_allowed"
assert_has "G2b. 허용 밖 경로 → 서버에 결손 보고" "$OUT" '"skip_reason":"path_not_allowed"'

sess_new "sG3"; consent_on
OUT="$(fire "sG3" "$TESTHOME/.claude/../etc/x.jsonl")"
assert_has "G3. 상위 탈출(..) 경로도 path_not_allowed" "$OUT" "RESULT status=path_not_allowed"

sess_new "sG4"; consent_on
OUT="$(fire "sG4" "$PROJ/nope.jsonl")"
assert_has "G4a. 파일 없음 → 결과 마커"       "$OUT" "RESULT status=file_missing"
assert_has "G4b. 파일 없음 → 서버에 결손 보고" "$OUT" '"skip_reason":"file_missing"'

OUT="$(fire "sG4" "$PROJ/nope.jsonl")"
assert_has   "G5a. 같은 사유 재발사도 결과 마커는 갱신"      "$OUT" "RESULT status=file_missing"
assert_lacks "G5b. 결손 보고는 세션당 사유당 1회(폭주 차단)" "$OUT" "SKIP POST"

echo "=== H. 스로틀 / 킬스위치 ==="
sess_new "sH"; consent_on
JSONL_H="$PROJ/h.jsonl"; grow "$JSONL_H" 100
fire "sH" "$JSONL_H" >/dev/null            # floor 선점
grow "$JSONL_H" 200
rm -f "$(mpath sH.transcript)"             # 수동 전송 = 스로틀 마커를 지워 창을 여는 경로
OUT="$(fire "sH" "$JSONL_H" Stop)"
assert_has   "H1. Stop 이벤트 정상 전송" "$OUT" "UPLOAD PUT"
OUT="$(fire "sH" "$JSONL_H" Stop)"
assert_empty "H2. 2분 스로틀 — 직후 Stop 재발사는 조용히 skip" "$OUT"
OUT="$(fire "sH" "$JSONL_H" SessionEnd)"
assert_has   "H3. SessionEnd 는 스로틀 면제" "$OUT" "DELTA"

OUT="$(hook_json "sH" "$JSONL_H" SessionEnd \
  | HOME="$TESTHOME" RONA_HOOK_DRYRUN=1 RONA_TRANSCRIPT_HOOK_DISABLED=1 bash "$HOOK" 2>/dev/null)"
assert_empty "H4. RONA_TRANSCRIPT_HOOK_DISABLED=1 → 전면 무력화" "$OUT"

echo "=== I. 제거된 경로 (회귀) ==="
sess_new "sI"; consent_on
JSONL_I="$PROJ/i.jsonl"; grow "$JSONL_I" 100
fire "sI" "$JSONL_I" >/dev/null
grow "$JSONL_I" 200
: > "$(mpath sI.no-send)"                         # 옛 '이 세션만 빼기' 마커
OUT="$(fire "sI" "$JSONL_I")"
assert_lacks "I1. .no-send 마커는 더 이상 아무 효과가 없다" "$OUT" "excluded"
assert_has   "I2. .no-send 가 있어도 정상 전송"             "$OUT" "UPLOAD PUT"

sess_new "sI2"; consent_off
: > "$TESTHOME/.rona/transcript-consent"          # 옛 계정 단위 동의 마커
JSONL_I2="$PROJ/i2.jsonl"; grow "$JSONL_I2" 100
OUT="$(fire "sI2" "$JSONL_I2")"
assert_has "I3. 계정 단위 동의 마커로는 통과하지 못한다(코칭 단위로 다시 묻는다)" "$OUT" "PROBE POST"

echo "=== J. 한 세션에서 주제 두 개 (토큰 교체) ==="
# open-and-track.sh 의 save_token 은 새 install 마다 <sid>.token 을 덮어쓴다. floor/offset 이
# 세션 키면 앞 코칭(A) 구간이 뒤 코칭(B) 행에 실린다 — 토큰 키잉이 그걸 막는지 본다.
sess_new "sJ" "$TOK"; consent_on "$TOK"; consent_on "$TOK_B"
JSONL_J="$PROJ/j.jsonl"; grow "$JSONL_J" 100
fire "sJ" "$JSONL_J" >/dev/null                    # A: floor=100 선점
grow "$JSONL_J" 300
OUT="$(fire "sJ" "$JSONL_J")"
assert_has "J1. 코칭 A 는 floor=100 에서 전송" "$OUT" \
  "DELTA floor=100 offset=0 start=100 bytes=300 delta_raw=200"
printf '200' > "$(mpath "sJ.$TOK.offset")"         # A 가 서버에 200바이트 담은 상태

printf '%s' "$TOK_B" > "$(mpath sJ.token)"         # ← 같은 세션에서 주제 B 발급
grow "$JSONL_J" 500
OUT="$(fire "sJ" "$JSONL_J")"
assert_eq    "J2. ★코칭 B 는 자기 floor 를 새로 잡는다(발급 시점 = 500)" \
  "$(marker "sJ.$TOK_B.floor")" "500"
assert_empty "J3. ★B 첫 발사에 A 구간(100..500)이 실리지 않는다" "$OUT"
assert_eq    "J4. ★A 의 offset 이 B 로 새지 않는다" "$(marker "sJ.$TOK_B.offset")" ""
assert_eq    "J5. A 의 마커는 그대로 보존"          "$(marker "sJ.$TOK.offset")" "200"
grow "$JSONL_J" 620
OUT="$(fire "sJ" "$JSONL_J")"
assert_has   "J6. B 는 자기 발급 시점 이후만 보낸다" "$OUT" \
  "DELTA floor=500 offset=0 start=500 bytes=620 delta_raw=120"

echo "=== K. floor 쓰기 실패 (무흔적 0 수집 차단) ==="
sess_new "sK"; consent_on
JSONL_K="$PROJ/k.jsonl"; grow "$JSONL_K" 100
mkdir -p "$(mpath "sK.$TOK.floor")"                # 파일 자리를 디렉토리로 막아 쓰기 실패 유도
OUT="$(fire "sK" "$JSONL_K")"
assert_has "K1. floor 를 못 쓰면 조용히 죽지 않고 사유를 남긴다" "$OUT" "RESULT status=failed step=floor"
ERROUT="$(hook_json "sK" "$JSONL_K" SessionEnd \
  | HOME="$TESTHOME" RONA_HOOK_DRYRUN=1 bash "$HOOK" 2>&1 >/dev/null)"
assert_empty "K2. 쓰기 실패 메시지가 stderr 로 새지 않는다(훅은 무출력 원칙)" "$ERROUT"

echo "=== L. 응답 코드별 실제 분기 (curl 스텁) ==="
STUB="$TESTHOME/stub"
mkdir -p "$STUB"
cat > "$STUB/curl" <<'STUBEOF'
#!/usr/bin/env bash
# 테스트용 curl 스텁 — 호출을 로그에 적고 $CURL_STUB_CODE 를 http_code 로 돌려준다.
code="${CURL_STUB_CODE:-200}"
body=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) body="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf 'CURL code=%s url=%s body=%s\n' "$code" "$url" "$body" >> "${CURL_STUB_LOG:-/dev/null}"
printf '%s' "$code"
STUBEOF
chmod +x "$STUB/curl"

# 실발사(dryrun 아님). 업로드 경로는 백그라운드라 그냥 부르면 검사와 경합한다 — 명령치환
# 으로 감싸면 백그라운드가 물고 있는 stdout 이 닫힐 때까지(= 끝날 때까지) 기다린다.
fire_real() {  # $1=session_id $2=transcript_path $3=http_code
  local _ignored
  _ignored="$(hook_json "$1" "$2" "SessionEnd" \
    | HOME="$TESTHOME" PATH="$STUB:$PATH" CURL_STUB_CODE="$3" CURL_STUB_LOG="$TESTHOME/curl.log" \
      bash "$HOOK" 2>/dev/null)"
}
result_of() { cat "$(mpath "$1.transcript-result")" 2>/dev/null; }

# L-a. 프로브 403 → no_consent + .probe (마커 자가생성 안 함)
sess_new "sLa"; consent_off
JSONL_LA="$PROJ/la.jsonl"; grow "$JSONL_LA" 100
fire_real "sLa" "$JSONL_LA" 403
assert_has     "La1. 프로브 403 → no_consent 결과" "$(result_of sLa)" "status=no_consent"
assert_file    "La2. 프로브 403 → .probe 로 세션 내 재질문 차단" "$(mpath sLa.probe)"
assert_no_file "La3. 프로브 403 → 동의 마커를 만들지 않는다" "$TESTHOME/.rona/consent/$TOK"

# L-b. 프로브 200 → 마커 self-heal 후 통과
sess_new "sLb"; consent_off
JSONL_LB="$PROJ/lb.jsonl"; grow "$JSONL_LB" 100
fire_real "sLb" "$JSONL_LB" 200
assert_file    "Lb1. 프로브 200 → 동의 마커 자가복구" "$TESTHOME/.rona/consent/$TOK"
assert_no_file "Lb2. 프로브 200 → .probe 는 세우지 않는다" "$(mpath sLb.probe)"

# L-c. 게이트 403(마커는 있는 상태) → 낡은 마커 제거 + no_consent (denied 아님)
sess_new "sLc"; consent_on
JSONL_LC="$PROJ/lc.jsonl"; grow "$JSONL_LC" 100
fire_real "sLc" "$JSONL_LC" 403         # floor 선점만 하고 끝
rm -f "$(mpath sLc.transcript)"
grow "$JSONL_LC" 300
fire_real "sLc" "$JSONL_LC" 403
assert_has     "Lc1. ★게이트 403 → denied 가 아니라 no_consent" "$(result_of sLc)" "status=no_consent"
assert_lacks   "Lc2. ★거절한 사용자에게 '권한 없음'으로 옮겨질 denied 를 안 쓴다" "$(result_of sLc)" "denied"
assert_no_file "Lc3. 낡은 동의 마커 제거 → 다음 발사가 프로브로 재판정" "$TESTHOME/.rona/consent/$TOK"

# L-d. 결손 보고 400(서버가 아직 신규 사유를 모름) → 가드 안 세움 → 다음 창에 재시도
sess_new "sLd"; consent_on
fire_real "sLd" "$PROJ/nope.jsonl" 400
assert_has     "Ld1. 결손 400 이어도 로컬 결과는 남는다" "$(result_of sLd)" "status=file_missing"
assert_no_file "Ld2. ★서버가 안 받았으면 일회성 가드를 세우지 않는다(영구 억제 차단)" \
  "$(mpath sLd.skip-file_missing)"
rm -f "$(mpath sLd.transcript)"
: > "$TESTHOME/curl.log"
fire_real "sLd" "$PROJ/nope.jsonl" 200
assert_has  "Ld3. ★서버 업그레이드 후 같은 세션에서 재시도된다" \
  "$(cat "$TESTHOME/curl.log" 2>/dev/null)" '"skip_reason":"file_missing"'
assert_file "Ld4. 200 으로 받았으면 그때 가드를 세운다" "$(mpath sLd.skip-file_missing)"

echo "=== M. 훅 등록 위치 (양쪽 교차 확인) ==="
# 가장 위험한 실수: SKILL.md 에서 Stop 을 빼놓고 hooks.json 에 안 넣으면 훅이 통째로 사라진다.
# 한쪽만 보면 그걸 못 잡으므로 두 파일을 같이 본다.
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$HOOKS_DIR/../SKILL.md"
PLUGIN_HOOKS="$HOOKS_DIR/../../../hooks/hooks.json"
FM="$(awk '/^---$/{n++; next} n==1' "$SKILL_MD" | grep -v '^[[:space:]]*#')"   # 주석 제외 frontmatter

assert_eq "M1. hooks.json 에 Stop 이 등록돼 있다" \
  "$(jq -r '.hooks | has("Stop")' "$PLUGIN_HOOKS")" "true"
assert_has "M2. Stop 이 upload-transcript.sh 를 부른다" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN_HOOKS")" "upload-transcript.sh"
assert_eq "M3. Stop 은 async (0.2.25 실측대로 안전)" \
  "$(jq -r '.hooks.Stop[0].hooks[0].async' "$PLUGIN_HOOKS")" "true"
assert_eq "M4. ★SessionEnd 는 sync 유지 (async 필드 없음 — 종료 경합 미검증)" \
  "$(jq -r '.hooks.SessionEnd[0].hooks[0].async // "none"' "$PLUGIN_HOOKS")" "none"
assert_eq "M5. ★SKILL.md frontmatter 에는 Stop 이 없다(중복 발사 방지)" \
  "$(printf '%s' "$FM" | grep -c '^  Stop:')" "0"
assert_eq "M6. PostToolUse 는 스킬 스코프에 그대로 남는다" \
  "$(printf '%s' "$FM" | grep -c '^  PostToolUse:')" "1"
assert_eq "M7. ★open-and-track.sh 는 승격하지 않는다(matcher 가 넓어 전역이면 전 세션 스폰)" \
  "$(grep -c 'open-and-track' "$PLUGIN_HOOKS")" "0"

echo "=== N. 동의 직후 스로틀 면제 (2026-07-29 실측 시나리오 재현) ==="
# 15:27:05 프로브가 스로틀 창 선점 → 15:27:51 동의 → 15:27:58 발사가 53초밖에 안 지나
# 스로틀에 걸려 floor 미확정 → 다음 유효 발사(15:46)까지 18분 공백. 그걸 재현한다.
sess_new "sN"; consent_off
JSONL_N="$PROJ/n.jsonl"; grow "$JSONL_N" 1000
OUT="$(fire "sN" "$JSONL_N" Stop)"                 # ← 15:27:05 프로브 (스로틀 마커 선점)
assert_has  "N1. 미동의 발사가 프로브를 띄우고 스로틀 창을 선점" "$OUT" "PROBE POST"
assert_file "N2. 스로틀 마커가 선점됐다" "$(mpath sN.transcript)"

OUT="$(fire "sN" "$JSONL_N" Stop)"                 # 아직 미동의 → 스로틀 그대로 걸려야 한다
assert_empty "N3. 미동의 구간은 스로틀 유지(거절한 코칭이 매 도구 호출마다 결과를 쓰지 않게)" "$OUT"

consent_on                                          # ← 15:27:51 사용자 동의(런처가 마커 생성)
OUT="$(fire "sN" "$JSONL_N" Stop)"                 # ← 15:27:58, 53초 경과 (스로틀 창 안)
assert_eq   "N4. ★동의 직후 발사가 스로틀을 통과해 시작점을 바로 잡는다(18분 공백 제거)" \
  "$(marker "sN.$TOK.floor")" "1000"

grow "$JSONL_N" 1200
OUT="$(fire "sN" "$JSONL_N" Stop)"
assert_empty "N5. floor 가 잡히면 면제가 닫히고 스로틀이 다시 걸린다(면제는 최대 1회)" "$OUT"

rm -f "$(mpath sN.transcript)"
OUT="$(fire "sN" "$JSONL_N" Stop)"
assert_has "N6. 스로틀 창이 열리면 동의 이후분만 전송" "$OUT" \
  "DELTA floor=1000 offset=0 start=1000 bytes=1200 delta_raw=200"

# SessionEnd 면제 회귀 — 위 N5 와 같은 조건(스로틀 창 안)에서도 SessionEnd 는 통과해야 한다.
sess_new "sN2"; consent_on
JSONL_N2="$PROJ/n2.jsonl"; grow "$JSONL_N2" 100
fire "sN2" "$JSONL_N2" Stop >/dev/null             # floor 선점 + 스로틀 마커 선점
grow "$JSONL_N2" 300
OUT="$(fire "sN2" "$JSONL_N2" Stop)"
assert_empty "N7. floor 확정 후 Stop 은 스로틀에 걸린다" "$OUT"
OUT="$(fire "sN2" "$JSONL_N2" SessionEnd)"
assert_has   "N8. ★SessionEnd 는 여전히 스로틀 면제(최종 백스톱)" "$OUT" "DELTA floor=100"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
