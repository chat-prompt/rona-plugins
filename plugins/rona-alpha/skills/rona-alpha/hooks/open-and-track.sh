#!/usr/bin/env bash
# rona-alpha skill-scoped PostToolUse hook — DEV-4091 Track A (CLI 전용)
#
# 이 스크립트는 rona-alpha 런처 SKILL.md frontmatter 의 PostToolUse hook 으로 등록돼,
# 런처가 활성인 세션(=로나 실습 진행 중)에만 발동한다. 도구 실행 "직후" stdin 으로
# PostToolUse JSON 을 받아 tool_name/tool_input 을 분기한다.
#
#   #1 진행표 자동열기 — submit_progress(주경로) / progress POST(폴백) → progress-live open (멱등)
#   #2 tool_used 추적  — install curl 에서 토큰 마커 조달 → 작업 도구마다 REST log_event
#
# 원칙: best-effort. 추적/열기가 실패해도 사용자 도구 실행 흐름을 절대 막지 않는다 → 모든 경로 exit 0.

# ── 0. 킬스위치 (사고 시 env 로 즉시 무력화) ────────────────────────────────
#   RONA_PROGRESS_HOOK_DISABLED = 이 task 의 정식 이름
#   RONA_ALPHA_HOOK_DISABLED    = 아키텍처 문서(B_architecture_dev4091 §8)가 쓰는 이름 — 둘 다 존중
if [ -n "$RONA_PROGRESS_HOOK_DISABLED" ] || [ -n "$RONA_ALPHA_HOOK_DISABLED" ]; then
  exit 0
fi

# stdin 의 PostToolUse JSON 을 읽는다 (없으면 조용히 종료)
INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

# ── JSON 추출: jq 우선, 없으면 grep/sed 폴백 (환경에 jq 가 없을 수 있음) ──────
HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# 최상위 문자열 필드 하나를 꺼낸다 (예: json_top tool_name)
json_top() {
  local key="$1"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    # "key" : "value" 의 첫 매치 (value 에 escaped quote 없다고 가정 — top-level 은 단순 스칼라)
    printf '%s' "$INPUT" \
      | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

TOOL_NAME="$(json_top tool_name)"
SESSION_ID="$(json_top session_id)"
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# UUID(=install_token) 정규식
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

SESS_DIR="$HOME/.rona/session"
TOKEN_MARKER="$SESS_DIR/${SESSION_ID}.token"
OPENED_MARKER="$SESS_DIR/${SESSION_ID}.opened"

# ── open 함수: progress-live 를 OS 브라우저로 조용히 1회 연다 (멱등) ──────────
open_progress() {
  local token="$1"
  [ -z "$token" ] && return 0
  [ -f "$OPENED_MARKER" ] && return 0          # 멱등: 세션당 1회만
  mkdir -p "$SESS_DIR" 2>/dev/null
  local url="https://rona.so/skill/api/install/${token}?type=progress-live"

  if [ -n "$RONA_HOOK_DRYRUN" ]; then
    echo "OPEN $url"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin*)              open "$url" >/dev/null 2>&1 & ;;
      Linux*)               xdg-open "$url" >/dev/null 2>&1 & ;;
      MINGW*|MSYS*|CYGWIN*) ( start "" "$url" >/dev/null 2>&1 || cmd.exe /c start "" "$url" >/dev/null 2>&1 ) & ;;
      *)                    ( start "" "$url" >/dev/null 2>&1 ) & ;;
    esac
  fi
  touch "$OPENED_MARKER" 2>/dev/null           # 실패해도 무시
  return 0
}

# ── REST log_event(tool_used): 마커 토큰이 있을 때만 best-effort 발신 ─────────
log_tool_used() {
  local tool="$1" label="$2"
  [ -f "$TOKEN_MARKER" ] || return 0            # 토큰 없음 → skip (graceful, 무토큰 오발신 금지)
  local token
  token="$(cat "$TOKEN_MARKER" 2>/dev/null | tr -d '[:space:]')"
  [ -z "$token" ] && return 0

  # label 정화 (JSON/로그 안전): 따옴표·역슬래시·제어문자 제거 후 40자 컷
  label="$(printf '%s' "$label" | tr -d '"\\' | tr -d '\000-\037' | cut -c1-40)"

  local body
  if [ "$HAVE_JQ" -eq 1 ]; then
    body="$(jq -cn --arg t "$tool" --arg l "$label" \
      '{event_type:"tool_used",payload:{tool:$t,label:$l}}' 2>/dev/null)"
  else
    body="$(printf '{"event_type":"tool_used","payload":{"tool":"%s","label":"%s"}}' "$tool" "$label")"
  fi

  if [ -n "$RONA_HOOK_DRYRUN" ]; then
    echo "POST https://rona.so/skill/api/log/${token} BODY=${body}"
  else
    curl -fsS -m 5 -X POST \
      -H 'Content-Type: application/json' \
      -d "$body" \
      "https://rona.so/skill/api/log/${token}" >/dev/null 2>&1 &
  fi
  return 0
}

# ══ 분기 ═══════════════════════════════════════════════════════════════════

# [#1 주경로] rona-alpha submit_progress → 진행표 open
if [ "$TOOL_NAME" = "mcp__plugin_rona-alpha_rona-alpha__submit_progress" ]; then
  if [ "$HAVE_JQ" -eq 1 ]; then
    PTOKEN="$(printf '%s' "$INPUT" | jq -r '.tool_input.install_token // empty' 2>/dev/null)"
  else
    PTOKEN="$(printf '%s' "$INPUT" \
      | grep -oE "\"install_token\"[[:space:]]*:[[:space:]]*\"${UUID_RE}\"" \
      | grep -oE "$UUID_RE" | head -n1)"
  fi
  # install curl 를 놓친 폴백 설치(get_practice) 대비: 토큰 마커가 없으면 여기서 조달해 둔다 [#2 분모 보강]
  if [ -n "$PTOKEN" ] && [ ! -f "$TOKEN_MARKER" ]; then
    mkdir -p "$SESS_DIR" 2>/dev/null
    printf '%s' "$PTOKEN" > "$TOKEN_MARKER" 2>/dev/null
  fi
  open_progress "$PTOKEN"
  exit 0
fi

# 그 밖의 모든 MCP 도구(rona log_event/get_progress/claim_topic/list_topics/... 포함) → 무시.
# 추적 채널·판단 이벤트를 tool_used 로 재계수하면 double-count 이 된다.
case "$TOOL_NAME" in
  mcp__*) exit 0 ;;
esac

# [Bash 분기]
if [ "$TOOL_NAME" = "Bash" ]; then
  if [ "$HAVE_JQ" -eq 1 ]; then
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  else
    CMD=""
  fi
  SCAN="$CMD"
  [ -z "$SCAN" ] && SCAN="$INPUT"   # jq 없으면 raw INPUT 을 URL 스캔 대상으로

  # (a) install curl (…/skill/api/install/<UUID>?…launcher=alpha…) → 토큰 마커 조달 [#2]
  if printf '%s' "$SCAN" | grep -qE "/skill/api/install/${UUID_RE}" \
     && printf '%s' "$SCAN" | grep -q "launcher=alpha"; then
    ITOKEN="$(printf '%s' "$SCAN" | grep -oE "/skill/api/install/${UUID_RE}" \
              | head -n1 | grep -oE "$UUID_RE" | head -n1)"
    if [ -n "$ITOKEN" ]; then
      mkdir -p "$SESS_DIR" 2>/dev/null
      printf '%s' "$ITOKEN" > "$TOKEN_MARKER" 2>/dev/null
    fi
    exit 0

  # (b) progress POST (…/skill/api/progress/<UUID>) → 진행표 open (모델이 MCP 대신 curl 쓴 경우) [#1 폴백]
  elif printf '%s' "$SCAN" | grep -qE "/skill/api/progress/${UUID_RE}"; then
    PTOKEN="$(printf '%s' "$SCAN" | grep -oE "/skill/api/progress/${UUID_RE}" \
              | head -n1 | grep -oE "$UUID_RE" | head -n1)"
    open_progress "$PTOKEN"
    exit 0

  # (c) 그 외 일반 Bash → tool_used [#2]
  else
    LABEL="$(printf '%s' "$CMD" | awk 'NR==1{print $1}')"
    log_tool_used "Bash" "$LABEL"
    exit 0
  fi
fi

# [작업 도구 분기] WebFetch/Edit/Write/Read/Glob/Grep/... → tool_used [#2]
#   (위에서 mcp__* 와 Bash 는 이미 처리·소거됨. 남은 건 순수 작업 도구뿐이다.)
log_tool_used "$TOOL_NAME" ""
exit 0
