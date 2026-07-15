#!/usr/bin/env bash
# rona-alpha skill-scoped 트랜스크립트 업로드 훅 — 임직원 동의 수집.
#
# 이 스크립트는 rona-alpha 런처 SKILL.md frontmatter 의 SessionEnd + PostToolUse hook
# 으로 등록돼, 런처가 활성인 세션(=로나 실습 진행 중)에만 발동한다. stdin 으로 받은 hook
# JSON 의 transcript_path(현 세션 jsonl)를 gzip 해 서버로 올린다.
#
#   발동  SessionEnd(세션 종료 시 최종 1회) + PostToolUse(마지막 업로드 후 10분 경과 시
#         재업로드 — 세션이 곱게 안 끝나도 근사 회수). 스로틀은 마커 mtime 으로 판정.
#   전제  ①동의 마커 ~/.rona/transcript-consent 존재 ②install_token 마커 존재
#         ③transcript_path 가 실제 파일. 하나라도 없으면 조용히 종료.
#   서버  handshake(게이트 3종 preflight) 통과 시에만 upload. 서버가 본 방어선 — 이 훅은
#         마커/스로틀만 담당하고, 계정 임직원·consent 판정은 전적으로 서버가 한다.
#
# 보안 (open-and-track.sh 원칙 준수):
#   W4 검증      install_token 은 UUID 정규식 통과분만 URL 조립·POST.
#   W5 세션 격리 session_id 없으면 마커 안 쓰고 업로드도 안 함(토큰/스로틀 bleed 방지).
#   W6 권한      마커 파일 600 / 디렉토리 700.
#   주입 차단    URL 에는 sanitize 된 session_id(영숫자·_-) 와 UUID 토큰·정수 bytes 만 실린다.
#                transcript_path 는 로컬 파일 인자로만 쓰고(서버로 안 보냄) tool_response 도
#                파싱하지 않는다.
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
UPLOAD_MARKER="$SESS_DIR/${SESSION_ID}.transcript"   # mtime = 마지막 업로드 시각(스로틀)

# ── 전제 게이트 (하나라도 불충족이면 조용히 종료) ───────────────────────────
[ -f "$CONSENT_MARKER" ] || exit 0                    # ① 동의 마커
[ -f "$TOKEN_MARKER" ]   || exit 0                    # ② install_token 마커(open-and-track.sh 가 조달)
[ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || exit 0   # ③ 세션 jsonl 실재

# 세션 종료 이벤트는 최종 1회라 스로틀을 건너뛴다. 그 외(PostToolUse)는 마지막 업로드
# 후 10분 안이면 skip — find -mmin 은 mac/linux 공통.
if [ "$EVENT_NAME" != "SessionEnd" ]; then
  if find "$UPLOAD_MARKER" -mmin -10 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# 크기 상한 50MB — 초과분은 skip(대형 세션은 안 올림).
BYTES="$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -cd '0-9')"
[ -n "$BYTES" ] || exit 0
if [ "$BYTES" -gt 52428800 ]; then
  exit 0
fi

TOKEN="$(cat "$TOKEN_MARKER" 2>/dev/null | tr -d '[:space:]')"
is_uuid "$TOKEN" || exit 0                             # W4: 마커 토큰 재검증

# W6: 마커 디렉토리 권한 최소화 후, 스로틀 창을 지금 선점(마커 mtime=now). 백그라운드
# 업로드 전에 선점해야 rapid PostToolUse 가 동시에 중복 업로드를 띄우지 않는다. 업로드가
# 실패하면 이 창(10분)은 놓치지만 다음 창·SessionEnd(강제)가 백스톱 — 멱등이라 재업로드 안전.
mkdir -p "$SESS_DIR" 2>/dev/null
chmod 700 "$HOME/.rona" "$SESS_DIR" 2>/dev/null
: > "$UPLOAD_MARKER" 2>/dev/null
chmod 600 "$UPLOAD_MARKER" 2>/dev/null

BASE="https://rona.so/skill/api/transcript/${TOKEN}"

if [ -n "$RONA_HOOK_DRYRUN" ]; then
  echo "HANDSHAKE POST ${BASE}/handshake BODY={\"session_id\":\"${SESSION_ID}\",\"bytes\":${BYTES}}"
  echo "UPLOAD PUT ${BASE}/upload?session_id=${SESSION_ID} (gzip ${TRANSCRIPT_PATH})"
  exit 0
fi

# ── 백그라운드 업로드 (도구 흐름 비차단) ────────────────────────────────────
#   1) handshake preflight — 서버 게이트(install_token·@gpters.org·consent) 통과(200)만 진행.
#   2) gzip → PUT. 실패는 전부 삼킨다(best-effort). 임시 gz 는 항상 정리.
(
  code="$(curl -fsS -m 10 -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":${BYTES}}" \
    "${BASE}/handshake" 2>/dev/null)"
  if [ "$code" = "200" ]; then
    tmp_gz="$(mktemp 2>/dev/null)" || exit 0
    if gzip -c "$TRANSCRIPT_PATH" > "$tmp_gz" 2>/dev/null; then
      curl -fsS -m 60 -o /dev/null \
        -X PUT -H 'Content-Type: application/gzip' \
        --data-binary "@${tmp_gz}" \
        "${BASE}/upload?session_id=${SESSION_ID}" >/dev/null 2>&1
    fi
    rm -f "$tmp_gz" 2>/dev/null
  fi
) &

exit 0
