# 인터뷰 설계 — 학술 근거 + 사이클 예시 + 회고 항목

> SKILL.md STEP 3의 보조 참조. 인터뷰 문구 조정·응답 분포 이상·파일럿 회고 시 사용.
> 원본 리서치 정본: [`docs/research/interview-design-2026-05-20.md`](../../../../docs/research/interview-design-2026-05-20.md)

---

## 1. 왜 2단계로 나누나

**자기기입(STAGE 1)은 의식한 것만 잡힌다** — 파트너가 인지·언어화한 ①②③④.
**AI 보강(STAGE 2)은 사람이 놓친 부분을 캐는 도구** — 자동 추출 로그와 자기기입을 대조해 (a) 자기기입에 없는 우회, (b) 자기기입에 있는데 로그에 없는 세션 외 행동, (c) 무의식적 도구 선택을 한 문항으로 표적 회수.

두 인풋이 따로일 때 **세 인풋(자기기입·자동 추출·보강 응답)의 불일치 자체가 신호**가 된다. 이 신호를 STEP 6 메타 코멘트의 `discrepancies` 배열에 보존하는 이유다.

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
- 자기기입은 1건 단위 (그날 1개 작업).
- 보강은 자동 추출에서 임팩트 상위 **1건만** drill-down + ③② 보강 통합 (1문항).

**근거**: Krosnick (1991) satisficing; Galesic & Bosnjak (2009) survey length effect; Portigal (2013) Interviewing Users.

### 이슈 4 — 사후 합리화

**적용**:
- 자기기입 ①②③④는 **"행동·결과·평가" 중심**. "왜"는 안 묻는다.
- 보강의 STAGE 2 drill은 "*어떻게 찾아가셨어요?*"라는 **행동 anchor 질문**으로 confabulation 회피.
- "왜?"는 직전 인정 행동에 묶일 때만 follow-up 1회.

**근거**: Nisbett & Wilson (1977) "Telling more than we can know"; Flanagan Critical Incident Technique (1954); Christensen et al. Switch Interview (2016).

### 이슈 5 — 부담 vs 깊이 균형

**적용**:
- STAGE 1 = Tier A 4축 강제 (④①②③).
- STAGE 2 = Tier A 1문항 통합(drill + ③② 보강) + Tier B 1문항(하고 싶은 말).
- 진행률 노출 ([1/4], [2/4], [1/1] …).
- 본문 5문항, 4~5분 envelope. Tier B 포함 5~6분.

**근거**: Krosnick & Presser (2010); Czaja & Blair skip logic (2005); Young (2015) Practical Empathy.

---

## 3. 사이클 예시 — 마케터 가상 페르소나

가정: 파트너 #07 콘텐츠 마케터, 어제 14:00~14:35 (35분 세션) "신제품 출시 블로그 초안" 작업 후 오늘 06:00에 `/rona-review` 실행.

### STAGE 1 (3~4분, 자기기입)

```
[1/4 ④ 맞춤 정렬]
> 2. 일부만 맞았어요. 톤 학습이 안 되어 있는 느낌이고, 통계 자료가 옛날 거였어요.
   글 구조는 맞았어요.

[2/4 ①] > 톤이 격식체로 잡혀서 우리 회사 캐주얼 톤이 안 나왔어요.
           통계 인용도 옛날 자료만 가져옴.

[3/4 ②] > 2, 3, 4, 5, 6
           (AI 안 추가 리서치 / 다른 AI / 외부 자료 / 사람 / 직접 작성)

[4/4 ③] > 외부 블로그 3개 — "스타트업 캐주얼 톤 가이드" 검색.
           ChatGPT o3로 톤 재학습 시도.
           동료 김OO 슬랙 검토.
```

### STAGE 2 (1분, AI 보강 1문항)

```
[1/1 로그 기반 drill + 보강]
  로그를 봤더니, 이번 작업에서 웹 검색 8번 / 외부 블로그 3개 정독에 25분쯤
  쓰셨더라고요.

  그 25분 동안 뭘 찾으려 하셨고, 어떻게 찾아가셨어요?
  그리고 아까 안 적은 행동·출처가 있으면 같이 알려주세요.

> 우리 회사 톤이 정확히 뭔지 외부 사례 보면서 머릿속에 잡으려고 했어요.
  3개 글 읽고서야 "이 정도 캐주얼" 감이 잡혔어요. Threads에서도 비슷한
  스타트업 블로그 사례 몇 개 스크롤했고요. 통계는 ChatGPT o3에 "2025년
  SaaS 마케팅 통계" 다시 시켜서 받았는데 출처 검증은 동료한테 맡겼어요.

[Tier B] > 톤 학습 + 최신 통계 DB 연결되면 좋겠어요.
```

### 자동 추출 → 5축 병합 결과

```
파트너 #07 / 마케터 / 스타트업
스킬: 회사-블로그-초안-스킬 v2
작업: 신제품 출시 블로그 초안

④ 맞춤 정렬: 2. 일부만 — 톤 학습 + 통계 자료 빗나감 / 글 구조 OK
① 아쉬운 점: 톤 격식체 + 통계 옛날 자료
② 채운 노력: 외부 블로그 3개 정독(25분) + ChatGPT + 동료 검증 + 직접 재작성
③ 방법·출처: "스타트업 캐주얼 톤" 검색 8회, 외부 블로그 3개, ChatGPT o3,
              동료 김OO 슬랙, Threads 스크롤
바람: 톤 학습 + 최신 통계 DB

discrepancies:
- STAGE 1 [3/4]에 없는 "AI 가이드 재시도(1번)"가 로그에는 Write 4회 = v1~v4 재시도
- STAGE 1 [4/4] "Threads 스크롤"이 자동 추출 로그에 없음 (세션 외 행동)
- STAGE 1 [4/4] "ChatGPT o3 톤 재학습" → STAGE 2에서 "통계도 ChatGPT o3"로 추가 회수
```

총 소요: STAGE 1 약 3.5분 + STAGE 2 약 1.5분 + Tier B 30초 = 5.5분.

---

## 4. 첫 2~3 사이클 파일럿 회고 항목

각 사이클 종료 후 다음을 빠르게 체크해 인터뷰 자체를 튜닝한다:

| 회고 항목 | 신호 | 조치 |
|---|---|---|
| STAGE 1 완료율 | 4문항 모두 채워졌나? | "없음"·빈 응답 비율이 50%↑이면 문구 재설계 |
| 평균 글자수 (STAGE 1) | ① 한두 줄, ④ 빗나간 부분 한 줄, ③ URL 1개↑ | 너무 짧으면 예시 보강, 너무 길면 한도 명시 |
| STAGE 2 1분 envelope 준수 | drill에서 길어지는 경향 | follow-up 1회 제한 강조 |
| 자기기입 ↔ 자동 추출 불일치 빈도 | 매 사이클 1건↑ | **불일치 0이면 보강 인터뷰가 무의미해진 신호** — 자기기입이 모든 걸 잡고 있다는 뜻이라 STAGE 2를 줄일지 검토 |
| [3/4] ② 다중선택 분포 | 8번 "다른 것" 의존이 30%↑ | 1~7 카테고리 fine-grained 부족 — 신규 카테고리 추가 검토 |
| [1/4] ④ "거의 안 맞았다" 비율 | 30%↑ | **맞춤 입력 화면 3문항부터 재설계** — 정본 §리스크의 "맞춤 입력 빈약 교란" |
| [1/4] ④ "잘 맞" 응답이 60%↑ | acquiescence 의심 | [2/4] 부족분과 짝지어 비대칭 패턴 확인 — "잘 맞 + 부족함 있음"이 정상 |
| Tier B 응답률 | 60%↓는 정상 | 0%이면 "여기까지면 충분해요" 문구가 너무 단호한지 확인 |

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
