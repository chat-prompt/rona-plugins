---
name: rona-review
description: 로나 맞춤 코칭을 실제 업무에 적용한 직후, 그 경험을 4차원(사용 도구·외부 출처·시도와 실패·로나 코칭의 부족한 점)으로 정리하고 셀프 인터뷰로 노력 간극을 보강한 뒤 마스킹된 후기를 로나에 제출한다. 사용자가 "/rona-review", "코칭 후기", "스킬 후기", "리뷰 보낼게", "피드백 보낼게", "코칭 다 썼어", "스킬 다 썼어", "후기 남길게" 같은 표현을 쓰면 반드시 이 스킬을 발동한다. 다른 스킬과 헷갈리지 말 것 — 이 스킬은 로나 install 스킬을 써본 직후 회수용이다.
allowed-tools: [Read, Write, Bash, Glob]
---

# rona-review — 로나 맞춤 코칭 후기 회수

파트너가 로나 맞춤 코칭을 실제 업무에 적용한 직후, 그 경험을 정밀하게 회수해 로나 DB에 전송한다.

## 핵심 수집 대상

**"로나 코칭이 부족해서 사람이 직접 채운 노력의 정밀한 지도"**

- 로나 코칭만으로 안 됐던 지점
- 사람이 그걸 채우려 한 시도·실패·전환
- 그 과정에서 끌어온 외부 도구·검색·동료·다른 LLM
- 결과적으로 자동화 가능한 부분 (다음 코칭 개선 + 지불 가치 신호)

`아쉬운 점` 같은 정성 평가는 부산물이다. 본질은 **노력 간극의 형태·크기·원인**.

> **리뷰 모드 불변식 (리뷰는 리뷰만).** 이 스킬이 도는 동안에는 **원래 작업을 재개하거나
> 구현하지 않는다.** 파트너가 후기에 "이건 아쉬웠다 / 이걸 더 했어야 한다" 같은 *작업성*
> 피드백을 남겨도, 그 자리에서 고치거나 작업을 이어가지 말고 후기 항목(narrative)으로만
> 기록한다. 리뷰 세션의 유일한 산출은 후기다. (이어서 할 일이 있으면 STEP 6 발송 *이후*
> 딱 한 번 제안한다 — 아래 STEP 6 참조.)

---

## 사용 시점 (파트너 안내용)

> **로나 맞춤 코칭 작업을 마친 직후 같은 세션에서 `/rona-review`를 실행하세요.**
> 며칠 지나면 회상 정확도가 떨어집니다. 작업 종료 후 5분 안에 시작하는 게 가장 좋습니다.

---

## STEP 1. 마커 파일 탐지 — 어느 스킬에 대한 리뷰인가

로나 install 패키지에는 식별용 마커 파일 `.rona-skill.json`이 같이 들어 있다.

```json
{
  "practice_id": "uuid",
  "student_token": "...",
  "title": "스킬 제목",
  "installed_at": "ISO8601"
}
```

### 탐지 로직

1. 현재 작업 디렉토리(`pwd`) 기준으로 `.rona-skill.json` 글로빙:
   ```bash
   find . -maxdepth 4 -name '.rona-skill.json' \
     -not -path '*/node_modules/*' \
     -not -path '*/.git/*' \
     -not -path '*/.next/*' 2>/dev/null
   ```
2. 발견 개수에 따라 분기:
   - **0개**: 파트너에게 안내 — *"이 폴더에서 로나 스킬을 찾을 수 없어요. 로나 스킬을 install한 폴더에서 다시 실행해주세요."* → 종료
   - **1개**: 자동으로 그 스킬 선택, `practice_id` + `student_token` + `title` 추출
   - **여러 개**: 파트너에게 리스트 제시 — *"어느 스킬에 대한 리뷰인가요?"* + 번호 선택
3. 선택된 스킬의 `practice_id`, `student_token`, `title`을 메모리에 보관 — 이후 STEP에서 사용

---

## STEP 2. 세션 jsonl 자동 추출 — 4차원 중 1·2·3번

### 2-1. 세션 디렉토리 찾기

```bash
# 현재 프로젝트 경로를 -로 치환
PROJECT_KEY=$(pwd | sed 's|/|-|g')
SESSION_DIR="$HOME/.claude/projects/$PROJECT_KEY"
```

### 2-2. 최신 세션 jsonl 선택

- `$SESSION_DIR/*.jsonl` 중 `mtime` 기준 가장 최신 파일
- `agent-*.jsonl` 제외
- 크기 0 제외

```bash
LATEST=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null \
  | grep -v '/agent-' \
  | head -1)
```

### 2-3. 4차원 중 자동 추출 가능한 3개

#### (1) 사용한 도구·스킬·방법론

**출처**: `tool_use` 블록 자동 집계

```bash
jq -r 'select(.type == "assistant") | .message.content[]?
  | select(.type == "tool_use") | .name' "$LATEST" \
  | sort | uniq -c | sort -rn
```

**정리 형식**:
```markdown
## 사용한 도구·스킬

- WebSearch (5회) — 외부 사례 검색
- mcp__context7 (2회) — Vercel AI SDK 문서 조회
- Bash (12회) — 파일 조작, 로컬 테스트
- mcp__playwright (3회) — 브라우저 자동화 시도
```

각 도구마다 "주요 용도" 한 줄을 Claude가 추론해 붙인다 (tool_use input 샘플 보고 판단).

#### (2) 외부 출처

**출처**: `WebSearch` / `WebFetch` 결과 + 사용자 메시지에 등장한 URL/문서 인용

```bash
# 사용자 메시지에서 URL 추출
jq -r 'select(.type == "user") | .message.content[]?
  | select(.type == "text") | .text' "$LATEST" \
  | grep -oE 'https?://[^ )]+' | sort -u

# WebFetch 호출 URL
jq -r 'select(.type == "assistant") | .message.content[]?
  | select(.type == "tool_use" and .name == "WebFetch") | .input.url' "$LATEST"
```

**정리 형식**:
```markdown
## 외부 출처

- https://vercel.com/docs/ai-sdk — useStream 옵션 확인
- https://github.com/anthropics/sdk — 토큰 카운팅 예시
- (사용자 메시지에서 발견된 사내 위키 등은 마스킹 대상)
```

#### (3) 시도·실패·전환

**출처**: 같은 작업의 반복 호출 + 에러 메시지 + "안 되네", "다시 해보자", "다른 방법" 같은 사용자 신호

자동 추출은 **휴리스틱**: 시간 순으로 묶어 "처음 시도 → 막힘 → 우회"의 3단 시나리오 N개를 만든다.

```bash
# 에러를 포함한 toolResult 블록
jq -r 'select(.type == "user") | .message.content[]?
  | select(.type == "tool_result" and (.content // "" | tostring | test("error|Error|ERROR|failed|Failed")))
  | {timestamp: ., text: .content}' "$LATEST" | head -20
```

**정리 형식**:
```markdown
## 시도·실패·전환 (자동 추출)

[1] 초기 generateObject Pro 시도 → schema 검증 실패 → Flash로 전환 (총 12분)
[2] WebSearch 키워드 X로 5회 검색 → 적절한 답 못 찾음 → 키워드 Y로 재검색 (총 18분)
[3] tool_use 결과 파싱 실패 → 정규식 3차례 수정 → 통과 (총 8분)
```

- 각 시나리오에 **소요 시간** 추정 (관련 메시지의 timestamp 차이)
- 최대 5개. 더 많으면 임팩트 큰 순서로 절단

### 2-4. 출력 — 중간 산출물

위 3개를 묶어 `./.rona-review-auto.md` 임시 파일로 저장 (다음 STEP에서 인터뷰 보강용).

---

## STEP 3. 인터뷰 — 자기기입 + 조건부 AI 보강 2단계

> 인터뷰는 **두 단계로 끊김 없이** 진행한다. STAGE 1은 **3문항**으로 짧게 — "안 막혔으면 빨리 끝, 막혔으면 그 부분만 더". STAGE 2는 **조건부** — 로그에 우회·재시도 흔적이 있거나 [2/3]에 막힘이 적혔을 때만 1회 drill, 흔적이 전혀 없으면 skip. 안 막힌 사람은 2~3분, 막힌 사람만 4~5분.

### 3-0. 동작 원칙 (반드시 준수)

- **AskUserQuestion 도구 사용 금지.** 텍스트로 한 문항씩 순서대로 묻는다. 한 응답이 들어오기 전에는 다음 문항을 던지지 않는다.
- **인터뷰 문항은 내가 절대 대신 답하지 않는다.** 각 문항은 출력한 뒤 멈춰 **사용자의 실제 응답을 기다린다.** 세션에서 이미 답을 안다고 요약해 채우거나 그럴듯한 답을 지어내지 말 것 — 내가 값을 만들어 넣고 다음 STEP(마스킹·발송)으로 넘어가면 그건 위반이다. 사용자가 답하지 않으면 그 필드는 빈 값/`null` 이지, 내가 지어낸 한 줄이 아니다. (특히 STAGE 2 Q4 `automation_value` 는 세션 내내 도운 직후라 confabulation 고위험 — 반드시 사용자 입으로 받는다.)
- 빈 응답·"패스"·"모름"·Enter-only는 valid 신호. 다음 문항으로 진행한다.
- **척도 라벨은 코드블록 안의 문자 그대로 완성된 문장으로 출력한다.** "1. 잘 맞" 처럼 종결어미를 자르거나 단축하지 말 것 — 파트너가 "말을 하다 마는데?" 같은 인상을 받으면 응답 품질이 떨어진다.
- **"왜?" 질문은 직전 인정 행동에 묶일 때만** — 무의식적 도구 선택은 confabulation 위험 (Nisbett & Wilson 1977).
- **1~10점·만족도 평가·stated preference 척도 금지** — 정본 §목표 "탐색, 합/불 아님". "쓸 거예요?" "통하나요?" 같은 미래 가정 척도는 답정너로 수렴 — 모든 문항은 *행동·사실 회수*에만 집중.
- STAGE 1 입력 전에 STEP 2 자동 추출 결과를 보여주지 않는다 — cue가 들어가면 episodic recall이 오염 (Tulving 1973).
- **불변식 — 설문 단축 여부는 사람 답이 아니라 로그로 판단한다.** [2/3]에 파트너가 "없음 / 괜찮았어요"라고 답해도, STEP 2 자동 추출 로그에 우회·재시도·다른 도구 흔적이 있으면 **무조건 STAGE 2 drill을 1회 한다**. '괜찮았다'는 자기보고를 그대로 믿고 STAGE 2를 건너뛰면 안 된다 (만족도와 실제 노력의 갭 = 핵심 신호). 로그가 깨끗할 때만 skip한다.

### 3-1. 회수 5축 — 인터뷰가 무엇을 모으는가

| 축 | 무엇 | 어디서 회수 | 4차원 병합 |
|---|---|---|---|
| ④ 맞춤 정렬 | 입력 vs 실제 스킬 정렬 | STAGE 1 [1/3] | 신규 (Initiative #3) |
| ① 아쉬운 점(갭) | 로나 코칭 부족분 | STAGE 1 [2/3] 앞부분 → `regret` | 4차원 4번 |
| ② 채운 노력 | 갭을 메우려 한 행동 | STAGE 1 [2/3] 뒷부분 + drill + 로그 → AI 추출 `actions`, 서사는 `regret_resolution` | 4차원 3번 |
| ③ 방법·출처 | URL·도구·사람 | STEP 2 로그 자동 + STAGE 2 drill → `sources_raw` | 4차원 2번 |
| 다음 사람 메모 | 로나가 더 해주면 좋을 것 | STAGE 1 [3/3] → `next_person_memo` | 4차원 4번 (건설 프레이밍) |
| 놓친 행동 | 자동 추출에 있는데 자기기입에 없는 우회 | STAGE 2 drill | 4차원 3번 보강 |

> ⑤ 일반화·⑥ 자동화 가치(stated preference)는 *행동 데이터로 계산* — Week4 리텐션 base는 실제 재방문 데이터, 자동화 가치는 ②③ raw material로 합집합 자동화에 직접 기여. 단 "클로드코드보다 로나라서 도움된 점"은 STAGE 2 Q4(선택)에서 *행동 사실*로만 한 줄 회수한다 (척도 아님).

### 3-2. STAGE 1 — 자기기입 (2~3분, 3문항)

STEP 2 자동 추출(`./.rona-review-auto.md`) 저장 직후, 결과는 보여주지 말고 곧장 STAGE 1로 들어간다.

**[자기기입 1/3] 맞춤 정렬 ④** — 다음 문구를 그대로 파트너에게 출력하고 응답 대기:

```
잠깐 2~3분만 같이 정리할게요. 첫 번째 —

1/3. 처음 "이런 거 해보고 싶다"고 적으신 거랑, 받은 스킬이 잘 맞던가요?

  1. 잘 맞았어요
  2. 일부만 맞았어요 — 어디가 빗나갔어요?
  3. 거의 안 맞았어요 — 어디가요?

  (2·3 선택 시 한 줄로 어디가 빗나갔는지 같이 적어주세요)
```

**[자기기입 2/3] 막힘 + 직접 손봄 ①②**:

```
2/3. 막혔거나, 코칭 결과를 직접 더 손본 데가 있었나요?
     없으면 "없음", 있으면 그 지점만 짧게 적어주세요.
     (예: "영상 파일을 못 구해줘서 직접 유튜브에서 받아서 넣었어요")
```

> 이 문항은 **막힘(갭)** 과 **메우려 한 행동(해결)** 을 한 번에 받는다. 둘은 META에서 분리한다 (STEP 6 — `regret` vs `regret_resolution`). 여기서 막힘을 적으면 [3/3] 후 STAGE 2 drill 대상이 된다.

**[자기기입 3/3] 다음 사람 메모 (건설 프레이밍)**:

```
3/3. 다음에 같은 코칭을 쓸 사람에게 더 도움이 되려면,
     로나가 뭘 더 해주면 좋을까요? (한 줄)
     (떠오르는 게 없으면 Enter)
```

응답 3건을 받으면 STAGE 2 진입 여부를 판정한다.

### 3-3. STAGE 2 — 조건부 AI 보강

STAGE 1 [2/3] 응답 + STEP 2 자동 추출을 대조해 **drill 실행/skip을 판정**하고, 실행 시 사람이 놓친 행동·출처를 한 문항으로 회수한다.

#### drill 실행/skip 판정 (불변식 §3-0 적용)

**drill을 한다 (`drill_skipped=false`)** — 둘 중 하나라도 참이면:
- (a) STAGE 1 [2/3]에 막힘·직접 손본 지점이 적혔다 (비어있지 않음), **또는**
- (b) [2/3]가 "없음"이어도 STEP 2 자동 추출 로그에 **우회·재시도·다른 도구 흔적**이 있다 — 같은 작업 반복 호출, 에러 후 재시도, WebSearch 폭주(정상치 2~3배), 외부 LLM 언급, 도구 전환 등. (만족도와 실제 노력의 갭은 핵심 신호 — '괜찮았다'를 그대로 믿지 않는다.)

**skip한다 (`drill_skipped=true`)** — 다음을 *모두* 만족할 때만:
- [2/3]가 비었거나 "없음"이고, **그리고** 자동 추출 로그에 우회·재시도·다른 도구 흔적이 전혀 없다.
- skip하면 `drill_skip_reason`에 사유를 한 줄로 적는다 (예: "막힘 없음 + 로그에 재시도·우회·외부도구 흔적 없음"). `drill_response`는 null.

자동 추출 시나리오 선별 우선순위(여러 흔적 중 무엇을 인라인 박을지): 재시도 횟수 > 외부 리서치 도구 폭주 > 외부 LLM 언급 > 우회 존재 > 도구 전환 횟수.

#### drill 문항 (실행 시에만)

자기기입 단계에서 보여주지 않았던 자동 추출 결과를 *이 문항 안에 자연어 한 줄*로 인라인 박는다. 메타 용어("임팩트 상위 시나리오", "WebSearch", "context7" 등)는 한국어로 풀어쓴다 — "**웹 검색 N번 / 외부 블로그 N개 정독에 N분**" 같이.

```
로그를 봤더니, 이번 작업에서 [웹 검색 8번 / 외부 블로그 3개 정독에 25분]쯤
쓰셨더라고요.

그 25분 동안 뭘 찾아가셨는지, 기억나는 범위에서 단계별로 꼼꼼하게
풀어주세요. 한두 줄 요약 말고, 1·2·3… 순서대로 적어주시면 됩니다.

  예)
  1. 처음에 ___ 키워드로 검색 → 결과가 어색
  2. ___ 로 바꿔서 다시 검색 → ___ 블로그 발견
  3. 그걸 보고 "아, 이렇게 만들면 되겠다" 방향 잡힘
  ...

아까 안 적은 행동·출처(다른 LLM·동료·문서)도 함께 알려주세요.
```

- "어떻게 찾아가셨어요?" — *방법* 회수가 핵심. narrative 깊이를 받는다.
- 응답에 "왜 그렇게 됐는지"가 자연스럽게 드러나지 않으면 **한 번만** follow-up 가능. 두 번 이상 캐묻지 않는다 (Nisbett & Wilson confabulation 회피).
- [2/3]가 이미 풍부하고 자동 추출 결과와 큰 갭이 없으면 follow-up 없이 종료 가능.

#### Q4 — 로나 차별 가치 (선택, 행동 사실 1줄)

drill 실행/skip과 무관하게, 마지막에 한 줄 선택 문항:

```
마지막으로 — 클로드코드만 썼을 때보다 로나라서 도움이 된 점이 있다면
한 줄로 알려주세요. (없으면 Enter)
```

- 응답 → `stage2_ai_probe.automation_value`. 없으면 null.
- **이 한 줄은 반드시 사용자가 답한다 — 내가 대신 채우지 않는다.** 세션에서 "도움된 점"을 내가 요약해 넣으면 가짜 차별가치 신호로 측정이 오염된다. 문항을 출력하고 멈춰 응답을 기다리고, Enter·빈 응답이면 `null` — 지어낸 한 줄을 절대 넣지 않는다.
- **stated preference 아님** — "쓸 거예요?"가 아니라 "이번에 도움이 됐던 사실"만 받는다. 미래 가정·만족도 척도 금지.

> v3의 Tier B 자유 한 줄 섹션은 제거됐다. 자유 한 줄은 Q4가 흡수한다. META의 `tier_b_wish`는 항상 null.

### 3-4. 절대 묻지 말 것 (학술 근거)

- ❌ **"왜 그 우회가 필요했나요?"** — 무의식적 도구 선택의 confabulation 위험 (Nisbett & Wilson 1977).
- ❌ **"이 코칭을 1~10점으로 평가하면?"** — 정본 §목표 "탐색, 합/불 아님".
- ❌ **"몇 분 걸렸나요?" 단독 자유 입력** — telescoping (Loftus & Marburger 1983).
- ❌ **"이 부분이 어떻게 개선됐으면 좋을까요?"를 비판 프레이밍으로 필수** — Young 분당 수율 최저. [3/3]은 "다음 사람에게 더 도움되려면"이라는 *건설 프레이밍*으로만 묻는다.
- ❌ **"자동화되면 쓰실 거예요?" "비슷한 일에 통하나요?" stated preference 척도** — acquiescence bias + stated vs revealed gap. 행동 데이터로 *계산*한다. (Q4도 미래 가정이 아니라 *이번 작업의 사실*만 받는다.)

### 3-5. 자기기입 ↔ 자동 추출 ↔ 보강 응답 3-way 대조 — 보존 규칙

이 인터뷰의 진짜 가치는 **세 인풋의 불일치**에 있다. 분석 단계에서 잡기 위해 STEP 4 마스킹 전에 다음을 보존한다:

| 불일치 패턴 | 의미 | 보존 방식 |
|---|---|---|
| STAGE 1 [2/3]에 없는 행동이 자동 추출 로그에 있음 | 의식하지 못한 채우기 작업 | STAGE 2 drill 응답에 그대로 기록 |
| STAGE 2 drill에 나온 출처가 자동 추출 로그에 없음 | 세션 외 행동 (다른 LLM·사람·외부 도구) | STAGE 2 drill 응답에 그대로 기록 |
| STAGE 1 [2/3] "없음"인데 로그에 재시도·우회 흔적 풍부 | 만족도와 실제 노력의 갭 — "AI 가독성" 신호. **drill skip 금지** | drill 강제 + 응답 전체 보존 |
| STAGE 1 [1/3] "잘 맞"인데 [2/3] "막힘 있음" | 정렬 만족과 부족분의 비대칭 — 입력↔결과 갭과 스킬 자체 한계 분리 단서 | 응답 전체 보존 |

불일치는 **제거하지 말고 메타 코멘트에 그대로 남긴다** (STEP 6).

### 3-6. 학술 근거 + 사이클 예시

설계 근거 5가지 이슈(회상 편향·노력 간극·단계별 vs 종합·사후 합리화·부담 vs 깊이)와 학술 출처, v4 3문항+조건부 drill 사이클 입출력 예시, 첫 2~3 사이클 파일럿 회고 항목은 [`references/interview-design.md`](references/interview-design.md)에 정리. STEP 3 동작 중 인터뷰 문구 조정이 필요하거나, 응답 분포가 이상하게 쏠릴 때 참조한다.

### 3-7. 인터뷰 결과 → 4차원 + 5축 병합

STAGE 1 + STAGE 2 응답을 종합해 STEP 2의 자동 추출 md를 다음 구조로 갱신한다:

- **4차원 1번 (사용 도구·스킬)**: 자동 추출 그대로
- **4차원 2번 (외부 출처)**: STEP 2 로그 자동 + STAGE 2 drill 보강 → `sources_raw`
- **4차원 3번 (시도·실패·전환)**: 자동 추출 + STAGE 1 [2/3] 해결 행동(`regret_resolution`) + STAGE 2 drill에서 **AI가 추출한 행동 배열** → `actions` (`actions_method="ai_extracted"`)
- **4차원 4번 (못 미친 지점)**: STAGE 1 [2/3] 막힘(`regret`) + [3/3] 다음 사람 메모(`next_person_memo`)
- **5축 ④ 맞춤 정렬**: STAGE 1 [1/3] — 4차원과 별개로 메타 코멘트(STEP 6)에 구조화 보존 — Initiative KR 분석용

---

## STEP 4. 민감 정보 마스킹

LLM(스킬을 실행하는 Claude 자신)이 직접 판단해 마스킹한다. 외부 API 호출 없음.

### 마스킹 카테고리

| 카테고리 | 치환 |
|---|---|
| 이메일 | `[EMAIL_MASKED]` |
| 전화번호 | `[PHONE_MASKED]` |
| API 키 (sk-, ghp_, xoxb-, AKIA 등) | `[API_KEY_MASKED]` |
| IP 주소 | `[IP_MASKED]` |
| 주민등록번호 | `[ID_MASKED]` |
| 사내 프로젝트명 / 코드명 | `[INTERNAL_PROJECT_MASKED]` |
| 고객명 / 거래처명 (개인·회사) | `[CUSTOMER_MASKED]` |
| 내부 URL (사내망·VPN·관리자 페이지) | `[INTERNAL_URL_MASKED]` |
| 금액·매출 등 영업 비밀로 보이는 수치 | `[FIGURE_MASKED]` |

### 판단 원칙

- 외부에 공유되면 곤란할 가능성이 조금이라도 있으면 **마스킹 우선**
- 공개된 URL (vercel.com, github.com, docs 사이트)은 그대로 유지
- 모호하면 `[REDACTED: 사유]` 형태로 사유 명시
- **마스킹 토큰 옆에 원본을 함께 표시·설명·로그하지 말 것.** 치환은 완전 치환이지 비교 텍스트가 아니다. (예: `[EMAIL_MASKED] (원본: foo@bar.com)` 같은 표기 절대 금지)

### 절차

1. STEP 2 + STEP 3에서 합쳐진 md 전체를 검토
2. 카테고리별로 치환
3. 결과를 `./rona-review-preview.md`로 저장
4. **정규식 사후 가드 (반드시 실행)** — LLM 마스킹이 누락한 정형 패턴(이메일/전화/API키/IP/주민번호)을 결정론적으로 한 번 더 훑는다:

```python
python3 -c "
import re
md = open('./rona-review-preview.md').read()
# 가드 설계:
# 1) 긴 토큰(API 키)을 먼저 처리 — sk- 키 내부의 우연한 숫자 시퀀스를 PHONE이
#    부분 매칭하지 못하도록 (예: sk-...7890123456789 가 두 토큰으로 쪼개지는 버그).
# 2) PHONE/IP/ID는 (?<!\\d)...(?!\\d) 숫자 경계로 가드. \\b는 Python unicode 모드에서
#    한글도 word character로 보기 때문에 '010-1234-5678입니다'·'192.168.1.1과' 같은
#    한국어 인접 케이스를 못 잡음 — 숫자 경계가 한글·영문·공백 어디든 안전.
patterns = [
  (r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[EMAIL_MASKED]'),
  (r'(sk-|ghp_|xoxb-|AKIA)[A-Za-z0-9_-]{20,}', '[API_KEY_MASKED]'),
  (r'(?<!\d)01[0-9]-?[0-9]{3,4}-?[0-9]{4}(?!\d)', '[PHONE_MASKED]'),
  (r'(?<!\d)[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(?!\d)', '[IP_MASKED]'),
  (r'(?<!\d)[0-9]{6}-[1-4][0-9]{6}(?!\d)', '[ID_MASKED]'),
]
for p, t in patterns: md = re.sub(p, t, md)
open('./rona-review-preview.md', 'w').write(md)
print('PII regex sweep done')
"
```

- 이 단계는 **건너뛸 수 없음**. LLM 변덕에도 정형 패턴은 100% 잡힘
- 사내 단어·고객명·내부 URL 같은 LLM 판단 영역은 정규식이 못 잡으므로, **파트너 컨펌 미리보기가 최종 안전망**

---

## STEP 5. 미리보기 + 파트너 컨펌

> 발송이 종착지다. 취소 옵션은 두지 않는다 — 마스킹이 미덥지 않으면 파일을 직접 고치고, 만족하면 발송한다. 파트너가 검토할 시간은 충분히 보장하되, "안 보내고 도망갈 길"을 제도화하지는 않는다.

### 출력

```
마스킹된 후기를 ./rona-review-preview.md 에 저장했어요.
파일을 열어 확인해주세요. 민감 정보가 남아 있으면 직접 편집해도 됩니다.

요약:
- 코칭: <title>
- 사용 도구: N개
- 외부 출처: N개
- 시도·실패·전환: N개 시나리오
- 인터뷰: STAGE 1 3문항 + STAGE 2 조건부 drill(실행/건너뜀) + Q4 답변 완료

발송 준비됐어요. 어떻게 하실래요?
  [1] 발송
  [2] 수정 (파일 직접 편집 후 '준비됨' 입력)
```

### 분기

- **[1] 발송**: STEP 6 진행
- **[2] 수정**: 파트너가 `./rona-review-preview.md` 편집 → "준비됨" 입력 → Read로 다시 읽기 → 미리보기 요약 재제시 → 다시 [1] or [2]. 만족할 때까지 무한 수정 가능하지만 **종착지는 항상 발송**이다.

---

## STEP 6. 로나에 전송

전용 엔드포인트 `POST /api/skill-reviews` 사용. 파트너 자문단 리뷰는 `rona.partner_skill_reviews` 테이블에 적재된다. (이전에는 v1 `/api/devlogs` 에 기생했으나, ID 공간 어긋남 + 의미 충돌로 분리됨.)

### 메타데이터 HTML 코멘트 삽입

마스킹된 md 맨 위에 다음 코멘트를 박는다 (v1 파서는 HTML 코멘트 무시 → 회귀 0):

```html
<!-- RONA_REVIEW_META
{
  "version": "rona-review-v4-3q",
  "skill_title": "<title>",
  "stage1_self_report": {
    "fit_alignment": {
      "score_1_to_3":  2,
      "what_missed":   "STAGE 1 [1/3] free-text (2·3 선택 시)"
    },
    "regret":            "STAGE 1 [2/3]에서 막힌/부족한 '갭'만 (해결 행동 절대 섞지 말 것)",
    "regret_resolution": "STAGE 1 [2/3]에서 그 갭을 메우려 한 '해결 행동' 서사 (신규)",
    "next_person_memo":  "STAGE 1 [3/3] — 다음 사람 위해 로나가 더 해줬으면 하는 것 (신규)",
    "actions":           ["AI가 추출한 행동 배열 ([2/3] 해결서사 + drill + 로그)"],
    "actions_method":    "ai_extracted",
    "sources_raw":       "로그 + drill 자동 도출 출처 (사람에게 안 물음). 없으면 null"
  },
  "stage2_ai_probe": {
    "scenario_summary":  "AI가 보여준 자동 추출 자연어 한 줄",
    "drill_response":    "STAGE 2 drill 응답 또는 null (skip 시)",
    "drill_skipped":     false,
    "drill_skip_reason": "skip 사유 또는 null (신규)",
    "automation_value":  "Q4(선택) — 클로드코드보다 로나라서 도움된 점 또는 null (신규)",
    "tier_b_wish":       null
  },
  "axis_summary": {
    "axis4_fit":        "...",
    "axis1_regret":     "갭(막힘)만 — 해결 행동은 axis2_actions로",
    "axis2_actions":    "갭을 메우려 한 행동·해결 요약",
    "axis3_sources":    "..."
  },
  "discrepancies": [
    "예: STAGE 1 [2/3]에 없는 행동이 자동 추출에 있음 — 웹 검색 8회",
    "예: STAGE 2 drill의 'ChatGPT o3'가 세션 로그에 없음"
  ],
  "session_file": "<basename>",
  "masked_count": N,
  "submitted_at": "ISO8601",
  "completion_source": {
    "source": "closing",
    "trigger_shown": false,
    "dropout_reason": null
  }
}
-->
```

> **⚠️ 데이터 오염 방지 (절대 위반 금지) — `regret`·`axis1_regret` 은 갭만, 해결 행동은 분리.**
> [2/3]는 막힘과 해결 행동을 한 문장으로 받는다. 이를 META로 옮길 때:
> - `regret` 과 `axis_summary.axis1_regret`(요약된 아쉬운 점) 에는 **막힌/부족한 '갭' 만** 넣는다. 해결 서사("직접 ~해서 해결", "~를 받아서 넣음")는 **절대 넣지 않는다.**
> - 그 해결 행동 서사는 `regret_resolution` 과 `axis_summary.axis2_actions` 에 따로 넣는다.
> - 한 문장에 갭과 해결이 교차돼 있으면 **절(節) 단위로 갈라** 갭 절만 `regret`/`axis1_regret`에, 해결 절만 `regret_resolution`/`axis2_actions`에 넣는다.
> - 예1: 입력 "영상 파일을 못 구해줘서 직접 유튜브에서 받아서 넣었어요" →
>   `regret`/`axis1_regret`="스킬이 분석할 영상 파일을 못 구해줌", `regret_resolution`/`axis2_actions`="직접 유튜브에서 받아서 해결".
> - 예2(교차): 입력 "결과 톤이 안 맞아서 ChatGPT로 다시 받아 직접 고쳤어요" →
>   `regret`/`axis1_regret`="결과 톤이 기대와 안 맞음"(갭 절만), `regret_resolution`/`axis2_actions`="ChatGPT로 다시 받아 직접 수정"(해결 절만).
> 개선 루프(`gap-source`)는 `regret` **과 `axis_summary.axis1_regret`** 을 '제품 갭 신호'로 읽는다(둘 다 갭 채널). 게다가 `axis1_regret` 은 `ingest-review` 가 후기 → feedbacks triage 의 제품 개선 신호(severity/priority/group)로도 쓴다. 해결 행동(성공 서사)을 `regret`이나 `axis1_regret`에 합치면 그게 갭으로 오분류돼 개선 제안과 triage 를 동시에 오염시킨다. `actions`/`next_person_memo`/`automation_value`/`regret_resolution`/`drill_skip_reason` 은 gap-source가 읽지 않으므로 안전하다.

### 전송 절차

1. `./rona-review-preview.md`를 Write로 그대로 저장 (heredoc 금지)
2. **STEP 1에서 추출한 마커의 `practice_id` 값을 `install_token` 으로 박아 넣어** Python으로 POST:

```bash
# 예시 — STEP 1에서 읽은 마커 파일의 practice_id 값(실제는 install_token)을 직접 박는다
python3 -c "
import json, urllib.request
md = open('./rona-review-preview.md').read()
data = json.dumps({
  'install_token': '<STEP_1_INSTALL_TOKEN>',
  'tool_used': 'rona-review',
  'markdown_content': md
}).encode()
req = urllib.request.Request('https://rona.so/api/skill-reviews',
  data=data, headers={'Content-Type': 'application/json'})
res = urllib.request.urlopen(req)
print(res.read().decode())
"
```

- API URL은 production 고정: `https://rona.so/api/skill-reviews`
- 마커 파일의 키 이름은 호환을 위해 `practice_id` 그대로 유지 — 값은 실제 `install_token` 이며 엔드포인트는 `install_token`/`practice_id` 둘 다 받음
- `student_token` 필드는 보내지 않는다 — 파트너 자문단 리뷰는 사람 식별이 목적이 아니라 코칭에 대한 피드백이므로
- Windows에서 `python3`이 없으면 `python` 또는 `py`로 대체

### 성공 시

```
발송 완료. 로나에 안전하게 도착했어요. 고맙습니다.
```

발송이 200 OK 로 확인된 *그다음*, 파트너가 리뷰 중에 작업성 피드백(미완 작업·더 했어야 할
것)을 남겼다면 **딱 한 번** "원래 작업을 이어서 도와드릴까요?" 하고 별도로 제안한다. 파트너가
원할 때만 원래 흐름으로 복귀하고, 묻지 않은 채 임의로 작업을 재개하지 않는다. (작업성
피드백이 없었으면 이 제안도 생략하고 깔끔히 마친다.)

### 실패 시 fallback

```
발송에 실패했어요. 수동 업로드 URL로 보내주세요:
https://rona.so/upload?install_token=<STEP_1_INSTALL_TOKEN>

위 URL에서 ./rona-review-preview.md 파일을 업로드하면 됩니다.
```

(업로드 페이지가 `install_token` 쿼리를 아직 처리하지 않으면 운영자가 Neon Console에서 수동 적재.)

---

## 데이터 흐름 — 다운스트림 없음 (수집 전용)

`POST /api/skill-reviews` 는 `rona.partner_skill_reviews` 테이블에 row 만 적재한다.
v1 devlogs 의 후속 플로우(체크포인트 동기화, 챌린지 인증, Mixpanel `devlog_upload`, Slack `## 소감` 알림)는 **호출되지 않는다** — 파트너 자문단 리뷰는 학생 진도가 아니라 코칭 자체에 대한 피드백이므로 의도된 격리. 분석은 운영자가 Neon Console 직접 조회 또는 추후 신설될 `/admin/skill-reviews` 페이지에서 수행.

RONA_REVIEW_META HTML 코멘트는 엔드포인트에서 파싱되어 `stage1_self_report` / `stage2_ai_probe` / `axis_summary` / `discrepancies` / `session_file` / `masked_count` / `submitted_at` / `completion_source` 컬럼으로 분해 저장된다. 파싱 실패 시에도 `markdown_content` 는 무손실 보존.

`completion_source` 는 이 후기가 어디서 왔는지를 호출 맥락으로 판정해 채운다. 끝까지 가지 않고 중간에 마친 흐름(설치 스킬의 "이거면 됐어요 / 다른 방식으로 갈게요" 종료 후 회수)에서 호출됐으면 `source` 를 `"stopword"` 로 두고, 들은 이탈사유 한 줄을 `dropout_reason` 에 담고 `trigger_shown` 을 `true` 로 둔다. 정상적으로 완주하고 마무리 후기로 넘어온 흐름이면 `source` 를 `"closing"`, `trigger_shown` 을 `false`, `dropout_reason` 을 `null` 로 둔다. 이 필드는 출처 분류 1개만 채우며, 설문 4축(사용 도구 / 외부 출처 / 시도와 실패 / 아쉬운 점) 내용은 손대지 않는다.

`dropout_reason` 한 줄은 META 가 in-band JSON 이라는 점을 지켜 안전하게 적는다. 큰따옴표(`"`)·개행은 한 줄 평문으로 풀어 쓰고(필요하면 작은따옴표나 풀어쓴 표현으로 바꾼다), JSON 종결자와 겹치는 `-->` 같은 문자열은 넣지 않는다. JSON 문자열로 안전히 이스케이프된 한 줄이라야 META 전체가 깨지지 않고 후기 구조화 필드가 보존된다.

---

## 주의사항

- 파트너 컨펌 미리보기는 협상 불가능 — "발송" 명시 전에는 절대 API 호출 안 함
- 마스킹 누락 사후 발견 시 운영자가 Neon Console에서 `UPDATE rona.devlogs SET raw_markdown = '[REDACTED — partner request]' WHERE id = '...'`로 수동 처리
- 인터뷰 답변은 파트너가 비워도 됨 (선택 가능)
- 같은 폴더에 여러 로나 스킬이 install된 경우 마커 파일로 구분 — 파트너가 선택
- bash heredoc(`cat << EOF`) 사용 금지 (Windows 비호환)
- `AskUserQuestion` 도구 사용 금지 — 텍스트로 한 문항씩 순서대로 묻는다
