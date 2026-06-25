# 인터뷰 설계 — 학술 근거 + 사이클 예시 + 회고 항목

> SKILL.md STEP 3의 보조 참조. 인터뷰 문구 조정·응답 분포 이상·파일럿 회고 시 사용.
> 원본 리서치 정본: [`docs/research/interview-design-2026-05-20.md`](../../../../docs/research/interview-design-2026-05-20.md)

---

## 0. v4 구조 (3문항 + 조건부 drill)

v3(STAGE 1 4문항 + STAGE 2 1문항 = 5문항 강제)에서 v4(STAGE 1 3문항 + STAGE 2 조건부)로 줄였다. 핵심 의도: **"안 막혔으면 2~3문항으로 빨리 끝, 막혔으면 그 부분만 더"**.

- **STAGE 1 3문항**: [1/3] 맞춤 정렬(유지) · [2/3] 막힘+직접 손봄(막힘=`regret`, 해결 행동=`regret_resolution` 분리) · [3/3] 다음 사람 메모(`next_person_memo`, v3 '뭐가 부족했나'를 비판→건설 프레이밍으로 전환).
- **STAGE 2 조건부**: 로그에 우회·재시도·다른 도구 흔적이 있거나 [2/3]에 막힘이 적혔으면 drill 1회, 흔적이 전혀 없으면 skip(`drill_skipped=true` + `drill_skip_reason`). 마지막에 Q4(선택) `automation_value` 한 줄.
- **삭제**: v3의 [3/4] 8지선다 '채운 노력' 다중선택, [4/4] 출처 문항, Tier B 자유 한 줄 섹션. 출처는 로그 자동 + drill로 회수, 자유 한 줄은 Q4가 흡수.
- **신규 META 키 5종** (전부 gap-source 미소비라 개선 루프 안전): `regret_resolution`, `next_person_memo`, `actions_method`, `drill_skipped`/`drill_skip_reason`, `automation_value`.

### v4 설계의 백테스트 발견 3건 (32건 후기 분석)

1. **'괜찮았다'를 그대로 믿으면 안 된다** — [2/3] "없음/괜찮았어요"라 답해도 로그에 재시도·우회 흔적이 있는 케이스가 다수. → **설문 단축 여부는 사람 답이 아니라 로그로 판단**한다는 불변식(§3-0). 로그 흔적 있으면 drill 강제.
2. **1번 문항(맞춤 정렬)은 유지** — 입력↔결과 정렬은 자동 추출로 대체 불가한 유일한 자기보고 신호(파트너의 처음 의도는 로그에 안 남음). Initiative #3 KR 분석의 핵심 축이라 v4에서도 [1/3]로 보존.
3. **출처는 로그가 거의 다 잡는다** — v3 [4/4] 출처 문항의 응답 대부분이 STEP 2 자동 추출(WebFetch URL·WebSearch)과 중복. → 출처 문항을 사람에게 안 묻고 로그 자동 + drill 보강으로 대체(`sources_raw`는 자동 도출).

---

## 1. 왜 2단계로 나누나

**자기기입(STAGE 1)은 의식한 것만 잡힌다** — 파트너가 인지·언어화한 ④①②.
**AI 보강(STAGE 2)은 사람이 놓친 부분을 캐는 도구** — 자동 추출 로그와 자기기입을 대조해 (a) 자기기입에 없는 우회, (b) drill에서 나온 세션 외 행동(다른 LLM·사람·외부 도구), (c) 무의식적 도구 선택을 조건부 1문항으로 표적 회수.

두 인풋이 따로일 때 **세 인풋(자기기입·자동 추출·보강 응답)의 불일치 자체가 신호**가 된다. 이 신호를 STEP 6 메타 코멘트의 `discrepancies` 배열에 보존하는 이유다. 특히 [2/3] "없음"인데 로그에 재시도 흔적이 풍부한 패턴은 drill skip 금지 신호(만족도-노력 갭).

---

## 2. 5가지 인터뷰 설계 이슈 + 학술 근거

### 이슈 1 — 회상 편향 (recall bias)

**적용**:
- 자기기입은 작업 *직후* 회수 (jsonl 세션 종료 트리거 — 회상 거리 0).
- 보강 인터뷰는 자동 추출 요약을 **STAGE 2 [1/1]에서 자연어 한 줄로 인라인 박아** cue reinstatement.

**근거**: Tulving & Thomson (1973) encoding specificity; Geiselman et al. Cognitive Interview (1985); Bolger·Davis·Rafaeli diary (2003).

### 이슈 2 — stated preference 회피

**적용**:
- "쓸 거예요?" "통하나요?" 같은 미래 가정 척도는 *모두 제거*. acquiescence bias + stated vs revealed gap.
- 자동화 가치·일반화 신호는 *행동 데이터로 계산* — ②③ raw material이 합집합 자동화에 직접 기여, Week4 리텐션은 실제 재방문 데이터.
- 절대 시간 자유 입력도 제거 (telescoping). base rate 비교 척도도 *우리 맥락에서 신호 약함* — AI로 추가 리서치하면 더 걸리는 게 당연하므로 측정 무의미.

**근거**: Krosnick & Presser (2010) acquiescence; Loftus & Marburger (1983) telescoping; Schwarz et al. (1985) scale anchoring; LaPiere (1934) stated vs revealed gap.

### 이슈 3 — 단계별 vs 종합 구조

**적용**:
- 자기기입은 1건 단위 (그날 1개 작업), STAGE 1 3문항으로 압축.
- 보강은 **조건부** — 로그 흔적/막힘이 있을 때만 임팩트 상위 1건 drill-down (1문항). 흔적 없으면 skip해 안 막힌 사람의 부담을 0으로.

**근거**: Krosnick (1991) satisficing; Galesic & Bosnjak (2009) survey length effect; Portigal (2013) Interviewing Users.

### 이슈 4 — 사후 합리화

**적용**:
- 자기기입 [1/3][2/3][3/3]은 **"행동·결과" 중심**. "왜"는 안 묻는다. [3/3]은 비판이 아닌 **건설 프레이밍**("다음 사람에게 더 도움되려면")으로 자기방어 반응을 줄인다.
- 보강의 STAGE 2 drill은 "*어떻게 찾아가셨어요?*"라는 **행동 anchor 질문**으로 confabulation 회피.
- "왜?"는 직전 인정 행동에 묶일 때만 follow-up 1회.

**근거**: Nisbett & Wilson (1977) "Telling more than we can know"; Flanagan Critical Incident Technique (1954); Christensen et al. Switch Interview (2016).

### 이슈 5 — 부담 vs 깊이 균형

**적용**:
- STAGE 1 = 3문항 (④ 맞춤정렬 · ①② 막힘+해결 · 다음 사람 메모).
- STAGE 2 = **조건부** drill 1문항(로그/막힘 있을 때만) + Q4 선택(로나 차별 가치 한 줄). 안 막혔으면 STAGE 2 거의 비어 2~3분 종료.
- 진행률 노출 ([1/3], [2/3], [3/3]).
- 안 막힌 사람 2~3분, 막힌 사람만 4~5분 envelope.

**근거**: Krosnick & Presser (2010); Czaja & Blair skip logic (2005); Young (2015) Practical Empathy.

---

## 3. 사이클 예시 (v4) — 마케터 가상 페르소나

가정: 파트너 #07 콘텐츠 마케터, 어제 14:00~14:35 (35분 세션) "신제품 출시 블로그 초안" 작업 후 오늘 06:00에 `/rona-review` 실행.

### STAGE 1 (2~3분, 자기기입 3문항)

```
[1/3 ④ 맞춤 정렬]
> 2. 일부만 맞았어요. 톤 학습이 안 되어 있는 느낌이고, 통계 자료가 옛날 거였어요.
   글 구조는 맞았어요.

[2/3 ①② 막힘+직접 손봄]
> 톤이 격식체로 잡혀서 우리 회사 캐주얼 톤이 안 나왔어요. 통계도 옛날 자료만 가져와서,
  외부 블로그 3개 보고 톤 잡고 ChatGPT o3로 최신 통계 다시 받아서 직접 고쳤어요.

[3/3 다음 사람 메모]
> 회사 톤 샘플을 처음에 한 번 물어봐주면 좋겠어요.
```

### STAGE 2 (조건부 drill — 로그 흔적 있어 실행 + Q4)

[2/3]에 막힘이 적혔고 로그에도 재시도 흔적이 있으므로 `drill_skipped=false`, drill 실행:

```
[drill 로그 기반]
  로그를 봤더니, 이번 작업에서 웹 검색 8번 / 외부 블로그 3개 정독에 25분쯤
  쓰셨더라고요. 그 25분 동안 뭘 찾으려 하셨고, 어떻게 찾아가셨어요?
  아까 안 적은 행동·출처가 있으면 같이 알려주세요.

> 우리 회사 톤이 정확히 뭔지 외부 사례 보면서 머릿속에 잡으려고 했어요.
  3개 글 읽고서야 "이 정도 캐주얼" 감이 잡혔어요. Threads에서도 비슷한
  스타트업 블로그 사례 몇 개 스크롤했고요. 통계 출처 검증은 동료한테 맡겼어요.

[Q4 로나 차별 가치 (선택)]
> 클로드코드면 톤 샘플을 매번 붙여야 했을 텐데, 로나 스킬이 글 구조는 잡아줘서
  톤·통계만 손보면 됐어요.
```

> **drill skip 예시**: [2/3] "없음"이고 로그에도 재시도·우회·외부도구 흔적이 전혀 없으면
> `drill_skipped=true`, `drill_skip_reason="막힘 없음 + 로그에 재시도·우회·외부도구 흔적 없음"`,
> `drill_response=null`. 이 경우 STAGE 2는 Q4 한 줄만 받고 종료(총 2~3분).

### 자동 추출 → META 병합 결과 (regret / regret_resolution 분리)

```
파트너 #07 / 마케터 / 스타트업
스킬: 회사-블로그-초안-스킬 v2
작업: 신제품 출시 블로그 초안

regret (갭만):            톤이 격식체로 잡혀 캐주얼 톤 안 나옴 + 통계가 옛날 자료
regret_resolution (해결): 외부 블로그 3개로 톤 잡고 ChatGPT o3로 최신 통계 재수집해 직접 수정
next_person_memo:         회사 톤 샘플을 처음에 한 번 물어봐주면 좋겠음
actions (AI 추출):        ["외부 블로그 3개 정독", "ChatGPT o3 최신 통계 재요청",
                           "동료에게 출처 검증 위임", "직접 톤·통계 수정"]
actions_method:           ai_extracted
sources_raw (로그 자동):  "스타트업 캐주얼 톤" 검색 8회, 외부 블로그 3개, ChatGPT o3, Threads
automation_value:         글 구조는 로나가 잡아줘서 톤·통계만 손봄
④ 맞춤 정렬: 2. 일부만 — 톤 학습 + 통계 자료 빗나감 / 글 구조 OK

discrepancies:
- STAGE 1 [2/3]에 없는 "Threads 스크롤"이 STAGE 2 drill에서 회수됨 (세션 외 행동)
- 로그 Write 4회(v1~v4 재시도)가 자기기입엔 없음 — 의식하지 못한 채우기 작업
```

> ⚠️ 위 병합에서 **`regret`에는 갭만, 해결 행동은 `regret_resolution`로 분리**된 점에 주목. "외부 블로그로
> 톤 잡고 통계 재수집해 수정"이라는 성공 서사를 `regret`에 합치면 개선 루프(gap-source)가 갭으로 오분류한다.

총 소요: 안 막힌 사람 STAGE 1 약 2분 + Q4 = 2~3분. 위 막힌 케이스는 STAGE 1 2분 + drill 1.5분 + Q4 = 4분.

---

## 4. 첫 2~3 사이클 파일럿 회고 항목

각 사이클 종료 후 다음을 빠르게 체크해 인터뷰 자체를 튜닝한다:

| 회고 항목 | 신호 | 조치 |
|---|---|---|
| STAGE 1 완료율 | 3문항 모두 채워졌나? | "없음"·빈 응답 비율이 50%↑이면 문구 재설계 |
| 평균 글자수 (STAGE 1) | [2/3] 막힘 한두 줄, [3/3] 메모 한 줄 | 너무 짧으면 예시 보강, 너무 길면 한도 명시 |
| drill 1문항 envelope 준수 | drill에서 길어지는 경향 | follow-up 1회 제한 강조 |
| drill skip 판정 정확도 | [2/3] "없음"인데 로그에 재시도 흔적 → drill 했나? | **skip 했으면 회귀** — §3-0 불변식(로그로 판단) 위반. 로그 흔적 있으면 무조건 drill |
| regret / regret_resolution 분리 | `regret`에 해결 서사("직접 ~함")가 섞였나? | 섞였으면 **개선 루프 오염 회귀** — gap-source가 성공 서사를 갭으로 오분류. STEP 6 분리 지시 강화 |
| 자기기입 ↔ 자동 추출 불일치 빈도 | 매 사이클 1건↑ | **불일치 0이면 보강 drill이 무의미해진 신호** — 자기기입이 모든 걸 잡고 있다는 뜻이라 drill 조건을 좁힐지 검토 |
| [1/3] ④ "거의 안 맞았다" 비율 | 30%↑ | **맞춤 입력 화면 3문항부터 재설계** — 정본 §리스크의 "맞춤 입력 빈약 교란" |
| [1/3] ④ "잘 맞" 응답이 60%↑ | acquiescence 의심 | [2/3] 막힘과 짝지어 비대칭 패턴 확인 — "잘 맞 + 막힘 있음"이 정상 |
| Q4 `automation_value` 응답률 | 60%↓는 정상 | 0%이면 문구가 너무 단호한지 확인 |

---

## 5. 출처 (학술)

- Bolger, Davis & Rafaeli (2003) — *Annual Review of Psychology* 54.
- Buehler, Griffin & Ross (1994) — *J. Personality and Social Psychology* 67(3).
- Christensen, Hall, Dillon & Duncan (2016) — *Competing Against Luck*.
- Czaja & Blair (2005) — *Designing Surveys* (2nd ed.).
- Flanagan (1954) — *Psychological Bulletin* 51(4).
- Galesic & Bosnjak (2009) — *Public Opinion Quarterly* 73(2).
- Geiselman, Fisher, MacKinnon & Holland (1985) — *J. Applied Psychology* 70(2).
- Krosnick (1991) — *Applied Cognitive Psychology* 5(3).
- Krosnick & Presser (2010) — *Handbook of Survey Research* (2nd ed.).
- LaPiere (1934) — *Social Forces* 13(2). [stated vs revealed gap]
- Loftus & Marburger (1983) — *Memory & Cognition* 11(1).
- Nisbett & Wilson (1977) — *Psychological Review* 84(3).
- Portigal (2013) — *Interviewing Users*.
- Schwarz, Hippler, Deutsch & Strack (1985) — *Public Opinion Quarterly* 49(3).
- Tulving & Thomson (1973) — *Psychological Review* 80(5).
- Young (2015) — *Practical Empathy*.

---

## 6. 알려진 한계

1. **외부 + 폼 only → 맞춤 입력 빈약이 빈 곳을 교란**. ④ 맞춤 정렬이 이 교란을 사후 검출. ④ "거의 안 맞았다"가 30%↑면 맞춤 입력 화면부터 재설계.
2. **부호화 특수성 연구는 실험실 기억 패러다임 중심** — 코딩/마케팅/AI-assisted 업무에 대한 ecological validity는 추론. 첫 2~3 사이클로 파일럿.
3. **Nisbett & Wilson confabulation 경계 조건** — 의식적 우회 설명은 신뢰 가능, 무의식적 도구 선택 설명은 위험. STAGE 2 drill에서 "왜?" follow-up은 1회 제한.
4. **N=5~7 통계적 한계** — Nielsen 85% surface rule을 따르지만, 정성 신호 → 다음 베타에서 양적 검증.
5. **stated preference 신호 부재** — 자동화 가치(⑥)·일반화(⑤) 척도를 제거했기 때문에, "자동화 후 재방문 의향" 같은 지불·리텐션 신호는 *실제 행동 데이터*로 잡아야 함. 메타 코멘트의 행동 raw material을 합집합 자동화에 직접 기여시키는 것이 본 인터뷰의 가치 proposition.
