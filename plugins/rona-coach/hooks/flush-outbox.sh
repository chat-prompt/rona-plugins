#!/usr/bin/env bash
set -u

# Stop은 완료 신호가 아니다. 보류 파일이 있다면 다음 세션이 재시도하도록 마커만 보존한다.
OUTBOX="${PWD}/.rona/coach-outbox.json"
if [ -s "$OUTBOX" ]; then
  mkdir -p "${PWD}/.rona" 2>/dev/null || true
  : > "${PWD}/.rona/coach-outbox.pending" 2>/dev/null || true
fi
exit 0
