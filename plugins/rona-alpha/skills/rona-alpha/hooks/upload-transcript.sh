#!/usr/bin/env bash
# rona-alpha skill-scoped 트랜스크립트 업로드 훅 — 임직원 동의 수집.
#
# 이 스크립트는 rona-alpha 런처 SKILL.md frontmatter 의 SessionEnd + PostToolUse hook
# 으로 등록돼, 런처가 활성인 세션(=로나 실습 진행 중)에만 발동한다. stdin 으로 받은 hook
# JSON 의 transcript_path(현 세션 jsonl)를 gzip 해 서버로 올린다.
#
#   발동  SessionEnd(세션 종료 시 최종 1회) + PostToolUse(마지막 시도 후 10분 경과 시
#         재업로드 — 세션이 곱게 안 끝나도 근사 회수). 스로틀은 마커 mtime 으로 판정.
#   전제  ①install_token 마커 존재 ②transcript_path 가 허용 경로의 실제 파일
#         ③동의 마커 ~/.rona/transcript-consent 존재. ①② 불충족은 조용히 종료.
#   서버  handshake(게이트 3종 preflight) 통과 시에만 upload. 서버가 본 방어선 — 이 훅은
#         마커/스로틀/압축만 담당하고, 계정 임직원·consent 판정은 전적으로 서버가 한다.
#
#   결과  매 시도의 끝을 결과 마커(<session>.transcript-result)에 남긴다. 백그라운드라
#         사용자가 성패를 알 길이 없어서 — 런처가 이 파일을 읽어 "보냈습니다 / 동의가
#         없어 못 보냅니다"를 전한다. 수동 전송은 스로틀 마커를 지우는 것으로 깨운다.
#
#   크기  gzip 을 *먼저* 하고 압축 후 크기로 판정한다(서버 바디 캡이 압축 후 기준이라
#         raw 로 재는 건 무의미). 한도 초과면 업로드 대신 handshake 에 skip_reason 을
#         실어 **결손을 서버에 기록**한다 — 조용히 종료하면 무흔적이라 어드민에서
#         "놓친 게 없는 것"과 구분되지 않는다.
#
# 보안 (open-and-track.sh 원칙 준수):
#   W4 검증      install_token 은 UUID 정규식 통과분만 URL 조립·POST.
#   W5 세션 격리 session_id 없으면 마커 안 쓰고 업로드도 안 함(토큰/스로틀 bleed 방지).
#   W6 권한      마커 파일 600 / 디렉토리 700.
#   경로 제한    transcript_path 는 $HOME/.claude/ 하위 .jsonl 만 허용(.. 포함 시 거부).
#                훅 입력이 가리키는 임의 파일을 서버로 보내지 않기 위함.
#   주입 차단    URL 에는 sanitize 된 session_id(영숫자·_-) 와 UUID 토큰·정수 크기만 실린다.
#                transcript_path 는 로컬 파일 인자로만 쓰고(서버로 안 보냄) tool_response 도
#                파싱하지 않는다. DRYRUN 출력에도 토큰을 찍지 않는다.
#
# 원칙: best-effort. 업로드 실패가 사용자 도구 실행 흐름을 절대 막지 않는다 → 모든 경로 exit 0.

# ── 0. 킬스위치 ─────────────────────────────────────────────────────────────
if [ -n "$RONA_TRANSCRIPT_HOOK_DISABLED" ]; then
  exit 0
fi

# 필수 바이너리 없으면 조용히 종료(best-effort).
command -v curl >/dev/null 2>&1 || exit 0
command -v gzip >/dev/null 2>&1 || exit 0

# stdin 의 hook JSON 을 읽는다 (없으면 조용히 종료)
INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

# tool_response(도구 출력)는 파싱 범위에서 제외(폴백 파서 오염 방지). jq 경로는 정밀 추출.
SAFE="${INPUT%%\"tool_response\"*}"

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
is_uuid() { printf '%s' "$1" | grep -qE "^${UUID_RE}$"; }

# 최상위 스칼라 문자열 필드 (jq=정밀, 폴백=SAFE 범위에서만)
json_top() {
  local key="$1"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$SAFE" \
      | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

EVENT_NAME="$(json_top hook_event_name)"
TRANSCRIPT_PATH="$(json_top transcript_path)"
# W5: session_id 정화. 비면 세션 격리 불가 → 마커·업로드 모두 skip(bleed 방지).
SESSION_ID="$(json_top session_id | tr -cd 'A-Za-z0-9_-' | cut -c1-100)"
[ -n "$SESSION_ID" ] || exit 0

SESS_DIR="$HOME/.rona/session"
CONSENT_MARKER="$HOME/.rona/transcript-consent"
TOKEN_MARKER="$SESS_DIR/${SESSION_ID}.token"
UPLOAD_MARKER="$SESS_DIR/${SESSION_ID}.transcript"          # mtime = 마지막 시도 시각(스로틀)
RESULT_MARKER="$SESS_DIR/${SESSION_ID}.transcript-result"   # 런처가 읽어 사용자에게 전할 결과
EXCLUDE_MARKER="$SESS_DIR/${SESSION_ID}.no-send"            # 있으면 이 세션만 전송 제외(계정 동의와 별개)
OFFSET_MARKER="$SESS_DIR/${SESSION_ID}.offset"             # 마지막으로 서버에 보낸 raw 바이트(증분 전송 시작점)

# 결과 1줄 기록(런처가 읽는 유일한 표면). 값은 전부 우리가 만든 토큰·정수뿐.
write_result() {
  {
    printf 'status=%s session=%s at=%s' \
      "$1" "$(printf '%s' "$SESSION_ID" | cut -c1-8)" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    [ -n "$2" ] && printf ' %s' "$2"
    printf '\n'
  } > "$RESULT_MARKER" 2>/dev/null
  chmod 600 "$RESULT_MARKER" 2>/dev/null
}

# ── 전제 게이트 ─────────────────────────────────────────────────────────────
[ -f "$TOKEN_MARKER" ] || exit 0                    # install_token 마커(open-and-track.sh 가 조달)
[ -n "$TRANSCRIPT_PATH" ] || exit 0

# 세션 제외: 이 세션만 빼달라(민감 세션)는 표시. 계정 동의(granted)와 별개로, 이 세션은
# 절대 보내지 않는다. 스로틀 선점보다 앞에 둬 exclude 세션은 마커도 안 남기고 조용히
# 빠진다. 결과는 남겨 런처가 "이 세션은 제외됨"을 확인할 수 있게 한다.
if [ -f "$EXCLUDE_MARKER" ]; then
  write_result "excluded"
  exit 0
fi

# 경로 제한: $HOME/.claude/ 하위 .jsonl 만. 상위 탈출(..) 은 무조건 거부.
case "$TRANSCRIPT_PATH" in
  *..*) exit 0 ;;
esac
case "$TRANSCRIPT_PATH" in
  "$HOME"/.claude/*.jsonl) ;;
  *) exit 0 ;;
esac
[ -f "$TRANSCRIPT_PATH" ] || exit 0

# 세션 종료 이벤트는 최종 1회라 스로틀을 건너뛴다. 그 외(PostToolUse)는 마지막 시도
# 후 10분 안이면 skip — find -mmin 은 mac/linux 공통.
#   수동 전송("지금 보내줘")은 이 마커를 지우는 것으로 창을 연다 — rm 실행 자체가
#   PostToolUse 를 깨우므로 별도 트리거가 필요 없다.
if [ "$EVENT_NAME" != "SessionEnd" ]; then
  if find "$UPLOAD_MARKER" -mmin -10 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# W6: 마커 디렉토리 권한 최소화 후, 스로틀 창을 지금 선점(마커 mtime=now). 백그라운드
# 작업 전에 선점해야 rapid PostToolUse 가 동시에 중복 업로드를 띄우지 않는다. 실패하면
# 이 창(10분)은 놓치지만 다음 창·SessionEnd(강제)가 백스톱 — 멱등이라 재업로드 안전.
# 동의 게이트보다 앞에 두는 이유: 미동의 세션이 매 도구 호출마다 결과 파일을 쓰지 않게.
mkdir -p "$SESS_DIR" 2>/dev/null
chmod 700 "$HOME/.rona" "$SESS_DIR" 2>/dev/null
: > "$UPLOAD_MARKER" 2>/dev/null
chmod 600 "$UPLOAD_MARKER" 2>/dev/null

# 동의 마커 없음 = 보낼 수 없음. 조용히 죽지 않고 사유를 남긴다(런처가 전할 수 있게).
if [ ! -f "$CONSENT_MARKER" ]; then
  write_result "no_consent"
  exit 0
fi

# 현재 파일 전체 크기(raw).
BYTES="$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -cd '0-9')"
[ -n "$BYTES" ] || exit 0

# ── 증분(delta) 시작점 계산 ─────────────────────────────────────────────────
# OFFSET = 지난번에 서버로 보낸 raw 바이트(= 서버 저장 bytes). 세션 jsonl 은 뒤로만
# 자라므로 OFFSET 이후 새로 붙은 부분만 보낸다. 마커가 없으면 0(첫 전송=전체 리셋).
OFFSET="$(cat "$OFFSET_MARKER" 2>/dev/null | tr -cd '0-9')"
[ -n "$OFFSET" ] || OFFSET=0
# 파일이 offset 보다 작아졌으면(축소·회전) 처음부터 다시 — 리셋으로 복구.
[ "$OFFSET" -gt "$BYTES" ] 2>/dev/null && OFFSET=0
# 새로 붙은 게 없으면(=이미 다 보냄) 조용히 끝낸다 — 빈 전송 안 한다.
[ "$OFFSET" -eq "$BYTES" ] 2>/dev/null && exit 0
# 이 조각(delta)의 raw 크기.
DELTA_RAW=$((BYTES - OFFSET))

TOKEN="$(cat "$TOKEN_MARKER" 2>/dev/null | tr -d '[:space:]')"
is_uuid "$TOKEN" || exit 0                             # W4: 마커 토큰 재검증

BASE="https://rona.so/skill/api/transcript/${TOKEN}"

# gzip 후 상한 4.5MB — 서버 바디 캡과 같은 값. 이제 조각(delta) 하나당 상한이라 긴
# 세션도 여기 안 걸린다(전체가 아니라 새로 붙은 부분만 보내므로).
MAX_GZ=4718592

if [ -n "$RONA_HOOK_DRYRUN" ]; then
  # 토큰은 찍지 않는다(로그·화면 유출 차단) — 경로는 자리표시자로.
  echo "DELTA offset=${OFFSET} bytes=${BYTES} delta_raw=${DELTA_RAW}"
  echo "HANDSHAKE POST ${BASE%/*}/<token>/handshake BODY={\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":<gz>}"
  echo "UPLOAD PUT ${BASE%/*}/<token>/upload?session_id=${SESSION_ID}&bytes=${DELTA_RAW}&offset=${OFFSET} (gzip tail +${OFFSET} ${TRANSCRIPT_PATH})"
  exit 0
fi

# ── 백그라운드 (도구 흐름 비차단) ───────────────────────────────────────────
#   1) OFFSET 이후 새 부분만 잘라 gzip → 조각 크기로 한도 판정.
#   2) 조각이 상한 초과면(드묾) handshake 에 skip_reason 만 실어 결손 기록.
#   3) 아니면 handshake preflight(200) 통과 시에만 PUT(offset 실어).
#   4) 200 → OFFSET_MARKER 를 BYTES 로 갱신(다음 시작점). 409(offset 불일치) →
#      OFFSET_MARKER=0 리셋(다음 발사 때 전체 재전송으로 자가복구).
#   실패는 전부 삼키되 결과 마커에는 남긴다. 임시 gz 는 항상 정리.
(
  tmp_gz="$(mktemp 2>/dev/null)" || exit 0
  # OFFSET 이후만 잘라 gzip. tail -c +N 은 N 번째 바이트부터(1-기반)라 +$((OFFSET+1)).
  if ! tail -c "+$((OFFSET + 1))" "$TRANSCRIPT_PATH" 2>/dev/null | gzip -c > "$tmp_gz" 2>/dev/null; then
    rm -f "$tmp_gz" 2>/dev/null
    write_result "failed" "step=gzip"
    exit 0
  fi
  GZ_BYTES="$(wc -c < "$tmp_gz" 2>/dev/null | tr -cd '0-9')"
  if [ -z "$GZ_BYTES" ]; then
    rm -f "$tmp_gz" 2>/dev/null
    write_result "failed" "step=size"
    exit 0
  fi

  if [ "$GZ_BYTES" -gt "$MAX_GZ" ]; then
    curl -fsS -m 10 -o /dev/null \
      -X POST -H 'Content-Type: application/json' \
      -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":${GZ_BYTES},\"skip_reason\":\"too_large\"}" \
      "${BASE}/handshake" >/dev/null 2>&1
    rm -f "$tmp_gz" 2>/dev/null
    write_result "too_large" "gz_bytes=${GZ_BYTES} limit=${MAX_GZ}"
    exit 0
  fi

  code="$(curl -fsS -m 10 -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":${GZ_BYTES}}" \
    "${BASE}/handshake" 2>/dev/null)"
  if [ "$code" = "200" ]; then
    up_code="$(curl -fsS -m 60 -o /dev/null -w '%{http_code}' \
      -X PUT -H 'Content-Type: application/gzip' \
      --data-binary "@${tmp_gz}" \
      "${BASE}/upload?session_id=${SESSION_ID}&bytes=${DELTA_RAW}&offset=${OFFSET}" 2>/dev/null)"
    if [ "$up_code" = "200" ]; then
      # 다음 전송 시작점을 현재 파일 끝으로. 이 조각까지 서버에 담겼다.
      printf '%s' "$BYTES" > "$OFFSET_MARKER" 2>/dev/null
      chmod 600 "$OFFSET_MARKER" 2>/dev/null
      write_result "sent" "gz_bytes=${GZ_BYTES} offset=${OFFSET}"
    elif [ "$up_code" = "409" ]; then
      # offset 불일치(서버 행 삭제·재claim 드리프트) → 다음엔 전체 리셋으로 복구.
      printf '0' > "$OFFSET_MARKER" 2>/dev/null
      chmod 600 "$OFFSET_MARKER" 2>/dev/null
      write_result "retry" "reason=offset_mismatch"
    else
      write_result "failed" "step=upload"
    fi
  elif [ "$code" = "403" ]; then
    # 서버 게이트 거부(미동의·비임직원·토큰 무효 — 사유는 서버가 안 알려준다).
    write_result "denied"
  else
    write_result "failed" "step=handshake"
  fi
  rm -f "$tmp_gz" 2>/dev/null
) &

exit 0
