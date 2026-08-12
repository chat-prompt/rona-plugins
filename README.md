# Rona Claude Code Plugins

- `rona`: 기존 맞춤 코칭 생성·실행 런처
- `rona-alpha`: 기존 고정 주제 코칭 런처
- `rona-coach`: 사용자의 실제 업무 결과물을 만들고 검증하는 네이티브 실행 코칭

세 플러그인은 독립적으로 설치되며 서로의 명령, 설정, 파일을 덮어쓰지 않습니다. `rona-coach`는 원격 MCP의 OAuth 연결을 사용하고, 결과물 원문이나 로컬 경로 대신 목표·방향·결과물 요약·검증 증거만 서버에 저장합니다.

Support 번들과 핵심 행동 계약이 맞는지 확인하려면 Rona 저장소들이 같은 상위 폴더에 있을 때 다음을 실행합니다.

```sh
node scripts/verify-rona-coach-parity.mjs
```
