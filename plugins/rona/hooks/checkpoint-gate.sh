#!/usr/bin/env bash
# Rona 맞춤 실습 진행 게이트 (Stop hook).
#
# 턴 종료 시 진행/완료 전송(rona MCP submit_progress·log_event) 누락을 검사해, A루트 실습
# 세션(설치 토큰 있음)에서 진행 기록을 유도한다. 전송 자체는 LLM이 rona MCP로 수행 —
# 이 hook 은 검사 + block 만 하고, 절대 직접 네트워크 전송하지 않는다.
#
# 게이트 2종:
#   (1) 0건 게이트: 세션에 진행/완료 전송이 0건이면 block.
#   (2) recency 게이트: 전송이 있어도 마지막 기록 이후 assistant 턴이 K(기본 6) 이상 쌓이면 block
#       — 스텝별 체크포인트 누락(예: 5스텝 중 1개만 기록)을 근사 커버. 새 전송 시 기준점 자동 재무장.
#
# 안전 원칙(최우선): 어떤 예외에서도 유저 세션을 영구 차단하지 않는다.
#   fail-open = 표준출력 없이 exit 0 (= 종료 허용). 모든 오류·미해소 경로는 fail-open.
# 무한/과다 block 방지(3중): (1) 내장 stop_hook_active, (2) 세션당 최대 3회 cap,
#   (3) 직전 block 후 K턴 미경과 시 재block 금지(연타 방지). cap/연타 카운터는 CLAUDE_PLUGIN_DATA 파일.
# 의존성: POSIX 셸 + grep/sed/tail 만. jq/python 미사용 (macOS bash 3.2 · Windows Git Bash 호환).

set -u

# 재block 임계 턴 수 K (기본 6). env 오버라이드 허용, 숫자 아니면 기본값.
K="${CLAUDE_PLUGIN_OPTION_GATE_TURN_THRESHOLD:-6}"
case "$K" in ''|*[!0-9]*) K=6 ;; esac

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

# --- 2b. 세션 카운터 파일 경로 해소. 미해소면 cap/연타 추적 불가 → 아래 block 직전에 fail-open. ---
SID="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//; s/"$//')"
DATA_DIR="${CLAUDE_PLUGIN_DATA:-}"
GUARD=""
if [ -n "$DATA_DIR" ] && [ -n "$SID" ]; then
  GUARD="$DATA_DIR/gate-blocked-$SID"
fi

# --- 3. transcript 경로 파싱. 없거나 파일이 없으면 no-op(fail-open). ---
TP="$(printf '%s' "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/.*"transcript_path":"//; s/"$//')"
# JSON 이스케이프 원복 (Windows 경로의 \\ 및 \/).
TP="$(printf '%s' "$TP" | sed 's/\\\\/\//g; s/\\\//\//g')"
[ -z "$TP" ] && exit 0
[ ! -f "$TP" ] && exit 0

# --- 4. 세션 스코프: 로나 MCP 호출 흔적이 0건이면 로나 실습 세션이 아님 → 개입 금지(fail-open). ---
# 플러그인은 user-scope 설치라 로나와 무관한 세션에도 로드됨. 로나 도구 사용 흔적이 있어야만 게이트한다.
RONA_CALLS="$(grep -cE '"name":"mcp__plugin_rona_rona__[^"]*"' "$TP" 2>/dev/null)"
[ -z "$RONA_CALLS" ] && RONA_CALLS=0
[ "$RONA_CALLS" -gt 0 ] 2>/dev/null || exit 0

# --- 5. due 판정: 진행/완료 전송(submit_progress·log_event)의 유무·최신성으로 결정. ---
CALLS="$(grep -cE '"name":"[^"]*(submit_progress|log_event)"' "$TP" 2>/dev/null)"
[ -z "$CALLS" ] && CALLS=0
REASON=""
if [ "$CALLS" -eq 0 ] 2>/dev/null; then
  # (1) 0건 게이트: 아직 아무 진행도 기록 안 함.
  REASON="이번 실습의 진행 상황이 아직 기록되지 않았어요. 마무리하기 전에 지금까지 한 내용을 rona 도구 submit_progress 로 먼저 기록해 주세요. 아직 시작 단계라면 첫 단계를 마친 뒤에 기록해도 괜찮습니다."
else
  # (2) recency 게이트: 마지막 전송 라인 이후 assistant 턴 수가 K 이상이면 스텝 누락 의심.
  LAST_LINE="$(grep -nE '"name":"[^"]*(submit_progress|log_event)"' "$TP" 2>/dev/null | tail -1 | cut -d: -f1)"
  case "$LAST_LINE" in ''|*[!0-9]*) LAST_LINE=0 ;; esac
  TURNS_AFTER="$(tail -n +"$((LAST_LINE + 1))" "$TP" 2>/dev/null | grep -cE '"type":"assistant"' 2>/dev/null)"
  [ -z "$TURNS_AFTER" ] && TURNS_AFTER=0
  if [ "$TURNS_AFTER" -ge "$K" ] 2>/dev/null; then
    REASON="마지막으로 진행을 기록한 뒤 대화가 꽤 진행됐어요. 지금까지 진행한 단계를 rona 도구 submit_progress 로 갱신하고 마무리해 주세요."
  else
    exit 0   # 최근에 기록함 → 통과.
  fi
fi

# --- 6. block. 단, cap(세션당 3회) + 연타 방지(직전 block 후 K턴 미경과 시 skip). ---
# GUARD 미해소면 cap/연타 카운터를 못 세움 → 넛지 포기 = fail-open (헤더 계약).
[ -z "$GUARD" ] && exit 0
BLOCK_COUNT=0; LAST_BLOCK_TURNS=0
if [ -f "$GUARD" ]; then
  read -r BLOCK_COUNT LAST_BLOCK_TURNS < "$GUARD" 2>/dev/null || true
  case "$BLOCK_COUNT" in ''|*[!0-9]*) BLOCK_COUNT=0 ;; esac
  case "$LAST_BLOCK_TURNS" in ''|*[!0-9]*) LAST_BLOCK_TURNS=0 ;; esac
fi
# 세션당 최대 3회.
[ "$BLOCK_COUNT" -ge 3 ] 2>/dev/null && exit 0
# 연타 방지 기준점: 총 assistant 턴 수.
TOTAL_TURNS="$(grep -cE '"type":"assistant"' "$TP" 2>/dev/null)"
[ -z "$TOTAL_TURNS" ] && TOTAL_TURNS=0
# 직전 block 이후 K턴 미경과면 재block 금지(첫 block 은 예외).
if [ "$BLOCK_COUNT" -gt 0 ] 2>/dev/null; then
  [ "$((TOTAL_TURNS - LAST_BLOCK_TURNS))" -lt "$K" ] 2>/dev/null && exit 0
fi
# 카운터 갱신 후 block. (쓰기 실패해도 다음 fire 는 stop_hook_active 가 막으므로 fail-open.)
mkdir -p "$DATA_DIR" 2>/dev/null || true
printf '%s %s\n' "$((BLOCK_COUNT + 1))" "$TOTAL_TURNS" > "$GUARD" 2>/dev/null || true
printf '{"decision":"block","reason":"%s"}' "$REASON"
exit 0
