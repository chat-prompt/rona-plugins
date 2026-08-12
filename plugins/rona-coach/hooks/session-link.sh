#!/usr/bin/env bash
set -u

# 상태를 바꾸지 않는 재개 힌트다. 식별자나 경로는 출력하지 않는다.
PLAN="${PWD}/.rona/plan.json"
OUTBOX="${PWD}/.rona/coach-outbox.json"
if [ -f "$PLAN" ] || [ -f "$OUTBOX" ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"이 작업공간에 로나 코칭 재개 상태가 있습니다. /rona-coach가 활성화되면 로컬 계획을 읽고 서버 상태를 확인하세요. 내부 식별자는 사용자에게 보여주지 마세요."}}'
fi
exit 0
