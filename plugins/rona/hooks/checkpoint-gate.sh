#!/usr/bin/env bash
# Rona 맞춤 실습 진행 게이트 (Stop hook) — F2a spike STUB.
#
# 현재는 항상 no-op(exit 0)한다. draft/미머지 상태에서 프로덕션에 영향 0.
# F2b 에서 아래 [F2b] 블록의 실제 게이트 로직을 채운다.
#
# F2a 실측으로 확정된 계약(전부 PASS):
#   - stdin JSON: transcript_path, stop_hook_active, cwd, last_assistant_message 제공.
#   - 토큰: env $CLAUDE_PLUGIN_OPTION_PRACTICE_TOKEN 또는 arg1(${user_config.practice_token}).
#   - 영속 상태: $CLAUDE_PLUGIN_DATA (plugin별 쓰기 가능 디렉토리).
#   - transcript grep: '"name":"[^"]*(submit_progress|log_event)"' 로 MCP 호출 판별 가능.
#   - block: stdout 에 {"decision":"block","reason":"..."} → Claude 재턴 강제(실측 num_turns=13).
#   - 무한루프 가드: stop_hook_active==true 면 반드시 허용(exit 0). + 파일 카운터 2중.
set -u

TOKEN="${CLAUDE_PLUGIN_OPTION_PRACTICE_TOKEN:-${1:-}}"

# --- STUB: 실로직 미구현. 항상 종료 허용. ---
exit 0

# ===================== [F2b] 실제 게이트 로직 (미활성) =====================
# INPUT="$(cat)"
# # 1. 활성 게이트: 토큰 없으면(=B/OAuth 루트) no-op
# [ -z "$TOKEN" ] && exit 0
# # 2. 무한루프 가드
# STOP_ACTIVE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("stop_hook_active"))' 2>/dev/null)"
# [ "$STOP_ACTIVE" = "True" ] && exit 0
# SID="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("session_id",""))')"
# GUARD="${CLAUDE_PLUGIN_DATA:-/tmp}/${SID}.blocked"
# [ -f "$GUARD" ] && exit 0
# # 3. 전송 due 판정 (v1: 세션 전체 진행/완료 호출 0건)
# TP="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("transcript_path",""))')"
# CALLS=0
# [ -f "$TP" ] && CALLS="$(grep -cE '"name":"[^"]*(submit_progress|log_event)"' "$TP" 2>/dev/null || echo 0)"
# if [ "$CALLS" -eq 0 ]; then
#   mkdir -p "$(dirname "$GUARD")"; touch "$GUARD"
#   printf '{"decision":"block","reason":"이번 실습의 진행/완료가 아직 기록되지 않았습니다. rona MCP의 submit_progress 를 installToken=\"%s\" 로 호출해 현재까지의 진행을 남긴 뒤 마무리하세요."}' "$TOKEN"
#   exit 0
# fi
# exit 0
# =========================================================================
