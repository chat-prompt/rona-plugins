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
# 보안 (codex 리뷰 수리):
#   B1 시크릿 유출 — label 은 명령의 basename 만 쓰고 KEY=VALUE 환경 대입 토큰은 스킵(값 미노출).
#   W2 인젝션      — 폴백 파서는 tool_response(도구 출력)를 절대 파싱하지 않는다(그 이전 stdin 범위만).
#   W4 검증        — install_token 은 마커 저장·URL 조립·POST 전 UUID 정규식으로 검증(양 경로).
#   W5 세션 격리   — session_id 없으면 마커를 안 써서 토큰 bleed 를 만들지 않는다.
#   W6 권한        — 토큰 마커 파일 600 / 디렉토리 700.
#
# 원칙: best-effort. 추적/열기 실패가 사용자 도구 실행 흐름을 절대 막지 않는다 → 모든 경로 exit 0.

# ── 0. 킬스위치 (사고 시 env 로 즉시 무력화) ────────────────────────────────
#   RONA_PROGRESS_HOOK_DISABLED = 이 task 의 정식 이름
#   RONA_ALPHA_HOOK_DISABLED    = 아키텍처 문서(B_architecture_dev4091 §8)가 쓰는 이름 — 둘 다 존중
if [ -n "$RONA_PROGRESS_HOOK_DISABLED" ] || [ -n "$RONA_ALPHA_HOOK_DISABLED" ]; then
  exit 0
fi

# stdin 의 PostToolUse JSON 을 읽는다 (없으면 조용히 종료)
INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

# W2: 폴백(grep/sed) 파서가 도구 출력을 신뢰하지 않도록, 첫 "tool_response" 이전까지만 스캔 범위로.
#     (jq 경로는 .tool_input 만 정밀 추출하므로 애초에 tool_response 를 건드리지 않는다.)
SAFE="${INPUT%%\"tool_response\"*}"

# ── JSON 추출: jq 우선, 없으면 grep/sed 폴백 (환경에 jq 가 없을 수 있음) ──────
HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# install_token 형식 = UUID
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
is_uuid() { printf '%s' "$1" | grep -qE "^${UUID_RE}$"; }

# 최상위 스칼라 문자열 필드 하나 (jq=정밀, 폴백=SAFE 범위에서만)
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

TOOL_NAME="$(json_top tool_name)"
# W5: session_id 를 안전 파일명 문자로 정화. 비면 세션 격리 불가로 보고 마커를 아예 안 쓴다(토큰 bleed 방지).
SESSION_ID="$(json_top session_id | tr -cd 'A-Za-z0-9_-' | cut -c1-100)"

SESS_DIR="$HOME/.rona/session"
if [ -n "$SESSION_ID" ]; then
  TOKEN_MARKER="$SESS_DIR/${SESSION_ID}.token"
  OPENED_MARKER="$SESS_DIR/${SESSION_ID}.opened"
else
  TOKEN_MARKER=""
  OPENED_MARKER=""
fi

# W6: 마커 디렉토리 권한 최소화 (world-readable 금지)
ensure_sess_dir() {
  mkdir -p "$SESS_DIR" 2>/dev/null
  chmod 700 "$HOME/.rona" 2>/dev/null
  chmod 700 "$SESS_DIR" 2>/dev/null
}

# 검증된 UUID 를 토큰 마커에 저장 (600)
save_token() {
  [ -n "$TOKEN_MARKER" ] || return 0
  is_uuid "$1" || return 0
  ensure_sess_dir
  printf '%s' "$1" > "$TOKEN_MARKER" 2>/dev/null
  chmod 600 "$TOKEN_MARKER" 2>/dev/null
  return 0
}

# ── open: progress-live 를 조용히 1회 (멱등; 세션 없으면 멱등마커 없이 열되 bleed 없음) ──
open_progress() {
  local token="$1"
  is_uuid "$token" || return 0                       # W4: UUID 아니면 절대 안 연다(404/오치환 차단)
  if [ -n "$OPENED_MARKER" ] && [ -f "$OPENED_MARKER" ]; then
    return 0                                          # 멱등: 세션당 1회
  fi
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
  if [ -n "$OPENED_MARKER" ]; then
    ensure_sess_dir
    : > "$OPENED_MARKER" 2>/dev/null
    chmod 600 "$OPENED_MARKER" 2>/dev/null
  fi
  return 0
}

# ── B1: 명령에서 안전한 label 산출 ──────────────────────────────────────────
#   KEY=VALUE 환경 대입 토큰(시크릿 인라인 대입 관용구)을 스킵하고, 실제 커맨드의 basename 만.
#   예: "OPENAI_API_KEY=sk-xxx python app.py" → "python"  (값은 절대 발신 안 됨)
cmd_label() {
  printf '%s' "$1" | awk '
    {
      for (i = 1; i <= NF; i++) {
        t = $i
        if (index(t, "=") > 0) continue    # KEY=VALUE 대입 스킵 (시크릿 차단)
        n = split(t, p, "/")               # 경로면 basename 만 (경로 노출 최소화)
        print p[n]
        exit
      }
    }'
}

# ── REST log_event(tool_used): 마커 토큰 있을 때만 best-effort ──
log_tool_used() {
  local tool="$1" label="$2"
  [ -n "$TOKEN_MARKER" ] || return 0                  # W5: 세션 없으면 발신 안 함(bleed 방지)
  [ -f "$TOKEN_MARKER" ] || return 0                  # 토큰 없음 → skip (무토큰 오발신 금지)
  local token
  token="$(cat "$TOKEN_MARKER" 2>/dev/null | tr -d '[:space:]')"
  is_uuid "$token" || return 0                        # W4: 마커 토큰도 재검증

  # label 정화(2차 방어): 보수적 화이트리스트 문자만(영숫자·. _ -) 남기고 40자 컷.
  # '='·따옴표·공백·제어문자 전부 제거 → 시크릿·인젝션 문자 잔류 불가.
  label="$(printf '%s' "$label" | tr -cd 'A-Za-z0-9._-' | cut -c1-40)"

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
    PTOKEN="$(printf '%s' "$SAFE" \
      | grep -oE "\"install_token\"[[:space:]]*:[[:space:]]*\"${UUID_RE}\"" \
      | grep -oE "$UUID_RE" | head -n1)"
  fi
  is_uuid "$PTOKEN" || exit 0                          # W4: 형식 불일치면 이 경로 skip
  # install curl 를 놓친 폴백 설치(get_practice) 대비: 토큰 마커가 없으면 여기서 조달 [#2 분모 보강]
  if [ -n "$TOKEN_MARKER" ] && [ ! -f "$TOKEN_MARKER" ]; then
    save_token "$PTOKEN"
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
    SCAN="$CMD"
  else
    CMD=""
    SCAN="$SAFE"   # W2: tool_response(도구 출력) 제외한 stdin 범위만 스캔
  fi

  # (a) install curl (…/skill/api/install/<UUID>?…launcher=alpha…) → 토큰 마커 조달 [#2]
  if printf '%s' "$SCAN" | grep -qE "/skill/api/install/${UUID_RE}" \
     && printf '%s' "$SCAN" | grep -q "launcher=alpha"; then
    ITOKEN="$(printf '%s' "$SCAN" | grep -oE "/skill/api/install/${UUID_RE}" \
              | head -n1 | grep -oE "$UUID_RE" | head -n1)"
    save_token "$ITOKEN"   # W4: 내부에서 UUID 재검증 후 600 저장
    exit 0

  # (b) progress POST (…/skill/api/progress/<UUID>) → 진행표 open (모델이 MCP 대신 curl 쓴 경우) [#1 폴백]
  elif printf '%s' "$SCAN" | grep -qE "/skill/api/progress/${UUID_RE}"; then
    PTOKEN="$(printf '%s' "$SCAN" | grep -oE "/skill/api/progress/${UUID_RE}" \
              | head -n1 | grep -oE "$UUID_RE" | head -n1)"
    open_progress "$PTOKEN"   # is_uuid 내부 검증
    exit 0

  # (c) 그 외 일반 Bash → tool_used [#2] (B1: env 대입 스킵 + basename label)
  else
    LABEL="$(cmd_label "$CMD")"
    log_tool_used "Bash" "$LABEL"
    exit 0
  fi
fi

# [작업 도구 분기] WebFetch/Edit/Write/Read/Glob/Grep/... → tool_used [#2]
#   (위에서 mcp__* 와 Bash 는 이미 처리·소거됨. 남은 건 순수 작업 도구뿐이다.)
log_tool_used "$TOOL_NAME" ""
exit 0
