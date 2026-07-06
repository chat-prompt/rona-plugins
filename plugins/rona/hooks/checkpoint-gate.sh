#!/usr/bin/env bash
# Rona 맞춤 실습 진행 게이트 (Stop hook).
#
# 턴 종료 시 진행/완료 전송(rona MCP submit_progress·log_event) 누락을 검사해, A루트 실습
# 세션(설치 토큰 있음)에서 세션당 1회만 재턴을 유도한다. 전송 자체는 LLM이 rona MCP로 수행 —
# 이 hook 은 검사 + block 만 하고, 절대 직접 네트워크 전송하지 않는다.
#
# 안전 원칙(최우선): 어떤 예외에서도 유저 세션을 영구 차단하지 않는다.
#   fail-open = 표준출력 없이 exit 0 (= 종료 허용). 모든 오류·미해소 경로는 fail-open.
# 무한 block 방지(2중): (1) 내장 stop_hook_active, (2) 세션 파일 카운터(세션당 1회).
# 의존성: POSIX 셸 + grep/sed 만. jq/python 미사용 (macOS · Windows Git Bash 호환).

set -u

# stdin 의 Stop hook JSON 전체(파싱은 grep/sed 로만).
INPUT="$(cat 2>/dev/null || true)"

# --- 1. 활성 게이트: A루트(설치 토큰 있음)에서만. 토큰 없으면(B/OAuth) no-op. ---
TOKEN="${CLAUDE_PLUGIN_OPTION_PRACTICE_TOKEN:-}"
[ -z "$TOKEN" ] && TOKEN="${1:-}"
[ -z "$TOKEN" ] && exit 0

# --- 2a. 무한 block 방지 (내장 플래그): 이미 이 stop-cycle 에서 block 했으면 무조건 허용. ---
case "$INPUT" in
  *'"stop_hook_active":true'*) exit 0 ;;
esac

# --- 2b. 무한 block 방지 (세션 파일 카운터): 세션당 1회. 쓰기 실패해도 fail-open. ---
SID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//; s/"$//')"
DATA_DIR="${CLAUDE_PLUGIN_DATA:-}"
GUARD=""
if [ -n "$DATA_DIR" ] && [ -n "$SID" ]; then
  GUARD="$DATA_DIR/gate-blocked-$SID"
  [ -f "$GUARD" ] && exit 0
fi

# --- 3. transcript 경로 파싱. 없거나 파일이 없으면 no-op(fail-open). ---
TP="$(printf '%s' "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/.*"transcript_path":"//; s/"$//')"
# JSON 이스케이프 원복 (Windows 경로의 \\ 및 \/).
TP="$(printf '%s' "$TP" | sed 's/\\\\/\//g; s/\\\//\//g')"
[ -z "$TP" ] && exit 0
[ ! -f "$TP" ] && exit 0

# --- 4. 전송 due 판정 (v1): 진행/완료 MCP 호출이 세션에 0건이면 due. ---
# tool_use 의 name 필드로 판별. plugin/connector 경로 모두 커버하도록 bare 도구명 substring.
CALLS="$(grep -cE '"name":"[^"]*(submit_progress|log_event)"' "$TP" 2>/dev/null)"
[ -z "$CALLS" ] && CALLS=0
if [ "$CALLS" -gt 0 ] 2>/dev/null; then
  exit 0   # 이미 진행/완료가 기록됨 → 통과.
fi

# --- 5. block 1회 (전송 미완). ---
# 카운터를 먼저 세운다. (쓰기 실패해도 다음 fire 는 stop_hook_active 가 막으므로 fail-open.)
if [ -n "$GUARD" ]; then
  mkdir -p "$DATA_DIR" 2>/dev/null || true
  : > "$GUARD" 2>/dev/null || true
fi
printf '%s' '{"decision":"block","reason":"이번 실습의 진행 상황이 아직 기록되지 않았어요. 마무리하기 전에 지금까지 한 내용을 rona 도구 submit_progress 로 먼저 기록해 주세요. 아직 시작 단계라면 첫 단계를 마친 뒤에 기록해도 괜찮습니다."}'
exit 0
