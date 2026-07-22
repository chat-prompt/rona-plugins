#!/usr/bin/env bash
# rona-alpha SessionStart 훅 — 플러그인이 stale 이면 "모델 컨텍스트에만" 업데이트 안내를
# 주입한다. 서버(/api/launcher-version)가 stale 판정·문구·JSON 이스케이프까지 처리하므로,
# 이 훅은 로컬 plugin.json 버전을 보내고 받은 응답을 파싱 없이 그대로 통과만 한다.
#
# 서버가 반환하는 hookSpecificOutput.additionalContext 는 모델 컨텍스트에만 들어가고
# 사용자·도구결과 패널엔 안 뜬다(무패널 안내). 최신이거나 실패면 아무것도 출력하지 않는다.
# best-effort: 어떤 실패도 조용히 exit 0 — 세션 시작을 절대 막지 않는다.

PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# plugin.json 의 "version": "0.2.24" 에서 숫자만 뽑는다(jq 의존 없이).
VER="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" 2>/dev/null \
  | head -1 | grep -o '[0-9][0-9.]*' | head -1)"
[ -n "$VER" ] || exit 0

OUT="$(curl -fsS --max-time 5 \
  "https://rona.so/api/launcher-version?launcher=alpha&have=alpha-${VER}&event=SessionStart" \
  2>/dev/null || true)"

# stale 이면 서버가 hookSpecificOutput JSON 을, 최신이면 {} 를 준다 — 전자만 그대로 emit.
case "$OUT" in
  *hookSpecificOutput*) printf '%s\n' "$OUT" ;;
  *) exit 0 ;;
esac
