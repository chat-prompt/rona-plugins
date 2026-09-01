---
name: rona-review
description: 완료한 Rona 코칭의 경험을 3문항과 조건부 보강으로 회수해 마스킹된 후기로 제출한다. 사용자가 /rona-review, 코칭 후기, 리뷰 남길게, 피드백 보낼게라고 하면 사용한다.
---

# 로나 코칭 후기

완료한 코칭의 후기만 남긴다. 후기 중 작업성 피드백이 나와도 원래 작업을 재개하거나 결과물을 수정하지 않는다.

1. 직전 `rona-coach` 흐름에서 넘어왔다면 그 `coachingId`를 그대로 쓴다.
2. 별도로 실행됐다면 현재 작업 폴더의 `.rona/plan.json`에서 `coachingId`를 확인한다. 파일이 없거나 완료한 코칭이 여러 개라 특정할 수 없을 때만 사용자에게 어느 코칭인지 한 번 묻는다.
3. `get_coaching_state`로 본인 코칭이며 `status: completed`인지 확인한다. 완료되지 않았거나 찾을 수 없으면 후기를 시작하지 않는다.
4. 형제 스킬 `../rona-coach/references/review.md`를 처음부터 끝까지 읽고, 확인한 `coachingId`로 그 절차를 그대로 따른다.

후기 생략·실패는 이미 완료된 코칭 상태를 바꾸지 않는다. `.rona/plan.json`이나 결과물은 수정하지 않는다.
