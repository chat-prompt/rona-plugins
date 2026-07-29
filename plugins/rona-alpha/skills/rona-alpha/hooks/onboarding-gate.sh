#!/usr/bin/env bash
# rona-alpha skill-scoped 온보딩 게이트 훅 — DEV-4146 (PreToolUse)
#
# 코칭을 받아온(claim_topic) 뒤 온보딩(정체성·무엇을 배우나·개념 지도)을 한 글자도
# 보여주지 않은 채로 질문·산출물 작성으로 직행하는 것을 막는다.
#
#   근거  전사 원문 26세션 실측 — fable-5 3세션(김태현·맹미나·김현철)이 온보딩을 통째로
#         스킵. 김태현 세션은 claim_topic 이후 27턴 연속 assistant 텍스트 0자(도구만 실행)
#         였고 사용자가 두 번 제지한 뒤에야 온보딩이 나왔다. 같은 사용자·같은 코칭을
#         opus-4-8 로 돌린 대조군은 첫 발화 738자 온보딩 정상 출력.
#         SKILL.md 에는 이미 온보딩 우선 지시가 5곳 이상 있으므로(그중 하나는 이 현상을
#         정확히 금지) 지시 부재가 아니라 지시 무시다 → 산문 강화가 아닌 훅으로 강제한다.
#
#   게이트 조건 (셋 다 만족할 때만 deny)
#     ① 이 세션 전사에 claim_topic 도구 호출이 이미 있다.
#        (claim 전 = 주제 탐색·선택 구간. 온보딩 원문은 claim 으로 받아오는 SKILL.md 안에
#         있으니 claim 전에는 출력할 온보딩 자체가 존재하지 않는다 → 게이트 대상 아님.)
#     ② claim_topic **이후** assistant text 블록 누적 글자수(공백 제외)가 임계 미만.
#     ③ 지금 호출하려는 도구가 AskUserQuestion / Write / Edit.
#
#   허용(절대 차단하지 않음)  Bash·Read·Glob·Grep 과 모든 mcp__* (log_event·submit_progress·
#         claim_topic 포함). claim 직후 번들 설치(Bash)·SKILL.md 읽기(Read)·진행표 초기
#         골격 전송(submit_progress)은 온보딩보다 먼저 와야 하는 정당한 준비 동작이다.
#         이걸 막으면 정상 플로우가 깨진다. 실제 차단은 SKILL.md frontmatter 의 matcher
#         가 1차로, 아래 case 문이 2차로 건다.
#
# 보안 (open-and-track.sh·upload-transcript.sh 원칙 준수):
#   경로 제한    transcript_path 는 $HOME/.claude/ 하위 .jsonl 만 허용(.. 포함 시 거부).
#   tool_response 훅 입력의 도구 출력은 파싱하지 않는다(PreToolUse 엔 애초에 없다).
#   전사 파싱    전사 각 줄은 fromjson? 로만 읽고, 판정에 쓰는 값은 우리가 만든 불리언·정수뿐.
#
# 원칙: best-effort. 판정 입력이 없거나(빈 stdin·transcript_path 부재·파일 없음) 파싱이
#       실패하면 조용히 통과(exit 0). 훅 오작동이 사용자 흐름을 막으면 안 된다 —
#       deny 는 조건이 확실히 성립할 때만.

# ── 0. 킬스위치 (사고 시 env 로 즉시 무력화) ────────────────────────────────
if [ -n "$RONA_ONBOARDING_GATE_DISABLED" ]; then
  exit 0
fi

# 온보딩으로 인정하는 최소 글자수(공백 제외). 실측 분포가 0자(스킵) vs 700자+(정상
# 온보딩)로 양극단이라 그 사이 어디를 잡아도 안전하다. 120 자는 스킵 쪽에 충분히 붙여
# "한두 문장 예고만 하고 직행"까지 걸리되, 정상 온보딩을 오탐할 여지는 남기지 않는 값.
MIN_ONBOARDING_CHARS=120

# stdin 의 PreToolUse JSON (없으면 조용히 종료)
INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

# jq 없으면 판정 불가 → 통과. 전사는 줄마다 JSON 이라 폴백 파서로는 신뢰할 수 있게
# 셀 수 없고, 잘못 세면 정상 흐름을 막는다.
command -v jq >/dev/null 2>&1 || exit 0

# ── 1. 차단 대상 도구인가 (③) ───────────────────────────────────────────────
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$TOOL_NAME" in
  AskUserQuestion|Write|Edit) ;;
  *) exit 0 ;;
esac

# ── 2. 전사 경로 확보 ───────────────────────────────────────────────────────
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$TRANSCRIPT_PATH" ] || exit 0
case "$TRANSCRIPT_PATH" in
  *..*) exit 0 ;;
esac
case "$TRANSCRIPT_PATH" in
  "$HOME"/.claude/*.jsonl) ;;
  *) exit 0 ;;
esac
[ -f "$TRANSCRIPT_PATH" ] || exit 0

# ── 3. 전사 1회 스캔 → "<claimed> <chars>" (①②) ────────────────────────────
#   claim_topic tool_use 를 만나면 claimed=true 로 켜고 카운터를 0 으로 리셋한다
#   (두 번째 주제를 받으면 그 코칭의 온보딩을 다시 보여줘야 하므로 마지막 claim 기준).
#   그 뒤로 나오는 assistant text 블록의 공백 제외 글자수를 누적한다.
#   - thinking 블록은 사용자에게 안 보이므로 세지 않는다(text 만).
#   - isSidechain(서브에이전트) 항목도 사용자 화면 밖이라 제외.
#   - 도구 이름은 tool_use 블록의 name 으로만 본다. 본문 문자열 매칭을 쓰면 SKILL.md
#     본문에 적힌 "claim_topic" 이라는 낱말에 걸려 claim 전에도 참이 돼버린다.
SCAN="$(jq -Rrn '
  reduce (inputs | fromjson? // empty) as $e (
    {claimed: false, chars: 0};
    if ($e.type == "assistant") and (($e.isSidechain // false) | not) then
      reduce ($e.message.content[]? | select(type == "object")) as $b (.;
        if ($b.type == "tool_use") and ((($b.name // "") | test("claim_topic"))) then
          {claimed: true, chars: 0}
        elif .claimed and ($b.type == "text") then
          .chars += (($b.text // "") | gsub("\\s"; "") | length)
        else . end
      )
    else . end
  ) | "\(.claimed) \(.chars)"
' < "$TRANSCRIPT_PATH" 2>/dev/null)"

[ -n "$SCAN" ] || exit 0
CLAIMED="${SCAN%% *}"
CHARS="${SCAN##* }"

[ "$CLAIMED" = "true" ] || exit 0                    # ① claim 전 = 게이트 대상 아님
case "$CHARS" in
  ''|*[!0-9]*) exit 0 ;;                             # 파싱 실패 → 통과
esac
[ "$CHARS" -lt "$MIN_ONBOARDING_CHARS" ] || exit 0    # ② 이미 온보딩을 보여줬다

# ── 4. deny ─────────────────────────────────────────────────────────────────
# 이 문구는 사용자 화면에 노출될 수 있는 경로다 — 내부 티켓번호·코드 섹션기호를 쓰지 않고
# 평범한 말로 쓴다. 내용은 모델에게 주는 지시(다음에 뭘 해야 하는지)다.
REASON='온보딩을 아직 사용자에게 보여주지 않았습니다. 받아온 코칭 SKILL.md 의 정체성 소개와 「무엇을 배우나」를 먼저 사용자에게 출력하세요 — 도입 서술 문단은 요약·압축하지 말고 그대로 펼치고, 개념 지도 표까지 보여준 뒤 「여기까지 이해되셨어요?」를 한 번 확인합니다. 그다음에 이 도구를 다시 호출하세요.'

jq -cn --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
