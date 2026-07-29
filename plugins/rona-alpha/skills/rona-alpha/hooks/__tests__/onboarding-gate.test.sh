#!/usr/bin/env bash
# onboarding-gate.sh 회귀 테스트 — 합성 전사 픽스처로 게이트 판정 4케이스 + 킬스위치.
#
# 실행: bash plugins/rona-alpha/skills/rona-alpha/hooks/__tests__/onboarding-gate.test.sh
#
# 훅은 transcript_path 를 $HOME/.claude/ 하위 .jsonl 로 제한하므로, 픽스처도 그 아래
# 임시 디렉토리에 만들고 끝나면 지운다.

set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/onboarding-gate.sh"
FIXTURE_DIR="$(mktemp -d "$HOME/.claude/rona-gate-test.XXXXXX")"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

PASS=0
FAIL=0

# ── 전사 줄 생성기 ──────────────────────────────────────────────────────────
line_claim() {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"mcp__plugin_rona-alpha_rona-alpha__claim_topic","input":{"slug":"x"}}]}}\n'
}
line_text() {  # $1 = 텍스트
  jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'
}
line_user() {
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"주제 골라줘"}]}}\n'
}
line_skill_mention() {  # SKILL.md 본문이 실린 user 항목 — "claim_topic" 낱말 오탐 방지 확인용
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"rona MCP의 claim_topic 을 호출한다."}]}}\n'
}

# ── 실행 헬퍼 ───────────────────────────────────────────────────────────────
# $1 = 케이스명, $2 = 픽스처 파일, $3 = tool_name, $4 = expect(allow|deny)
run_case() {
  local name="$1" fixture="$2" tool="$3" expect="$4"
  local out verdict
  out="$(jq -cn --arg tp "$fixture" --arg tn "$tool" \
          '{session_id:"s1",transcript_path:$tp,hook_event_name:"PreToolUse",tool_name:$tn,tool_input:{}}' \
        | bash "$HOOK" 2>/dev/null)"

  if [ -z "$out" ]; then
    verdict="allow"
  elif printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    verdict="deny"
  else
    verdict="unexpected:$out"
  fi

  if [ "$verdict" = "$expect" ]; then
    PASS=$((PASS + 1))
    printf 'PASS  %-58s tool=%-16s -> %s\n' "$name" "$tool" "$verdict"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-58s tool=%-16s -> %s (expected %s)\n' "$name" "$tool" "$verdict" "$expect"
  fi
}

# ── 픽스처 ──────────────────────────────────────────────────────────────────
# A. claim 없음 (주제 탐색·선택 구간). SKILL.md 본문의 "claim_topic" 낱말은 있다.
A="$FIXTURE_DIR/a-no-claim.jsonl"
{ line_user; line_skill_mention; line_text "어떤 주제로 진행할까요?"; } > "$A"

# B. claim 있음 + 이후 텍스트 0자 (fable-5 실측 패턴: 도구만 실행)
B="$FIXTURE_DIR/b-claim-silent.jsonl"
{ line_user; line_claim; } > "$B"

# C. claim 있음 + 이후 텍스트 700자 (정상 온보딩)
C="$FIXTURE_DIR/c-claim-onboarded.jsonl"
ONBOARD="$(printf '온보딩입니다. %.0s' $(seq 1 100))"   # 공백 제외 700자 이상
{ line_user; line_claim; line_text "$ONBOARD"; } > "$C"

# 길이 전제 검증(픽스처가 임계값을 확실히 넘는지)
ONBOARD_LEN="$(printf '%s' "$ONBOARD" | tr -d '[:space:]' | wc -m | tr -cd '0-9')"
printf -- '--- 픽스처 온보딩 텍스트 길이(공백 제외): %s자 (임계 120자) ---\n' "$ONBOARD_LEN"

# ── 케이스 ──────────────────────────────────────────────────────────────────
echo "=== 게이트 판정 ==="
run_case "1. claim 없음 + AskUserQuestion (주제 선택 구간)"    "$A" "AskUserQuestion" "allow"
run_case "2. claim + 텍스트 0자 + AskUserQuestion"             "$B" "AskUserQuestion" "deny"
run_case "2b. claim + 텍스트 0자 + Write"                      "$B" "Write"           "deny"
run_case "2c. claim + 텍스트 0자 + Edit"                       "$B" "Edit"            "deny"
run_case "3. claim + 텍스트 0자 + Bash (설치)"                 "$B" "Bash"            "allow"
run_case "3b. claim + 텍스트 0자 + Read (SKILL.md 읽기)"       "$B" "Read"            "allow"
run_case "3c. claim + 텍스트 0자 + submit_progress (초기 골격)" "$B" \
         "mcp__plugin_rona-alpha_rona-alpha__submit_progress" "allow"
run_case "3d. claim + 텍스트 0자 + Glob"                       "$B" "Glob"            "allow"
run_case "3e. claim + 텍스트 0자 + Grep"                       "$B" "Grep"            "allow"
run_case "4. claim + 온보딩 700자 + AskUserQuestion"           "$C" "AskUserQuestion" "allow"

echo "=== best-effort 통과 (판정 입력 없음) ==="
run_case "5. 전사 파일 없음"                                    "$FIXTURE_DIR/nope.jsonl" "AskUserQuestion" "allow"
run_case "6. 허용 경로 밖 transcript_path"                      "/tmp/evil.jsonl"         "AskUserQuestion" "allow"

# 빈 stdin
if [ -z "$(printf '' | bash "$HOOK" 2>/dev/null)" ]; then
  PASS=$((PASS + 1)); echo "PASS  7. 빈 stdin                                            -> allow"
else
  FAIL=$((FAIL + 1)); echo "FAIL  7. 빈 stdin                                            -> deny (expected allow)"
fi

echo "=== 킬스위치 ==="
KS_OUT="$(jq -cn --arg tp "$B" '{session_id:"s1",transcript_path:$tp,hook_event_name:"PreToolUse",tool_name:"AskUserQuestion",tool_input:{}}' \
          | RONA_ONBOARDING_GATE_DISABLED=1 bash "$HOOK" 2>/dev/null)"
if [ -z "$KS_OUT" ]; then
  PASS=$((PASS + 1)); echo "PASS  8. RONA_ONBOARDING_GATE_DISABLED=1 (deny 케이스)      -> allow"
else
  FAIL=$((FAIL + 1)); echo "FAIL  8. RONA_ONBOARDING_GATE_DISABLED=1 (deny 케이스)      -> $KS_OUT"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
