#!/usr/bin/env bash
# rona-alpha skill-scoped 트랜스크립트 업로드 훅 — 코칭 단위 동의 수집.
#
# 이 스크립트는 두 곳에 등록된다. stdin 으로 받은 hook JSON 의 transcript_path(현 세션
# jsonl)를 gzip 해 서버로 올린다.
#
#   등록  ①플러그인 루트 hooks/hooks.json → SessionEnd (세션 생명주기, 스코프 무관)
#         ②런처 SKILL.md frontmatter → Stop + PostToolUse (런처 활성 구간)
#
#   발동  SessionEnd(세션 종료 시 최종 1회, 스로틀 면제) + Stop(응답 1턴 끝날 때마다)
#         + PostToolUse(도구 실행 후). 뒤 둘은 마지막 시도 후 2분 경과 시에만 재업로드
#         하고, 스로틀은 마커 mtime 으로 판정한다.
#
#         SessionEnd 를 스킬 frontmatter 에 두면 안 된다 — 스킬 스코프 훅은 스킬이 활성인
#         동안만 등록되고 세션 종료 시점엔 이미 해제돼 **한 번도 발동하지 않는다**
#         (2026-07-22 통제 실험: 같은 세션에서 settings/플러그인 레벨은 발동, 스킬 레벨은
#         미발동). 그래서 백스톱이 없는 채로 굴러갔고, 세션 3/3 에서 마지막 훅 실행이 세션
#         종료보다 앞섰다(간극 3분31초~19분50초). 2026-07-21 실측 누락 7분25초·1분.
#
#         스코프는 이 스크립트의 토큰 마커 게이트가 잡는다 — 로나와 무관한 세션은 마커가
#         없어 즉시 종료하므로, 플러그인 레벨에 둬도 남의 세션에 손대지 않는다.
#
#         Stop 을 함께 두는 이유: 도구를 안 쓰고 대화만 이어간 구간도 회수하기 위함
#         (PostToolUse matcher 는 Bash·Edit·Write 등에만 걸려 대화만 하면 안 뜬다).
#         스로틀 2분은 급사 시 손실 상한 — 전송이 증분(delta)이라 좁혀도 부담이 없다.
#
#   동의  **코칭 1건 단위**다(install_token ↔ 코칭 1:1). 계정 단위가 아니다 — 한 번의
#         동의가 그 코칭에서 파생된 모든 세션을 덮고, 다음 주제를 받으면 다시 묻는다.
#         그래서 동의 마커도 토큰으로 키잉한다: ~/.rona/consent/<install_token>.
#         훅은 <sid>.token 으로 install_token 을 이미 알기 때문에, 같은 코칭의 두 번째·
#         세 번째 세션이 마커를 다시 만들 필요가 없다(모델에게 재생성을 시키지 않는다).
#         all-or-nothing — 거절한 코칭은 한 바이트도 보내지 않고, 중간 철회는 없다.
#
#   프로브 로컬 마커는 **캐시일 뿐 판정이 아니다.** 마커가 없어도 조용히 죽지 않고
#         handshake 프로브를 한 번 때려 서버에 물어본다 — 200 이면 마커를 스스로 만들고
#         통과(self-heal), 403 이면 결과를 남기고 <sid>.probe 로 이 세션의 재질문을 막는다.
#         마커 유실·머신 교체·다른 머신에서 준 동의가 전부 "조용한 미수집"이 되던 구멍을
#         닫는다. 프로브는 bytes=0·gz_bytes=0·skip_reason 없음이라 서버는 로그만 남기고
#         DB 를 건드리지 않는다(유령 행이 생기지 않는다).
#
#   범위  **동의 시점 이후만 보낸다.** 동의 게이트를 처음 통과한 순간의 파일 크기를
#         <sid>.floor 에 박고(선점) 그 앞은 영원히 보내지 않는다 — 로나를 부르기 전
#         하던 딴 작업 대화가 통째로 올라가던 것을 막는다.
#
#         산술: START = FLOOR + OFFSET / 전송 = tail -c +$((START+1)) / 쿼리 offset=OFFSET.
#         OFFSET 은 파일 절대 위치가 아니라 **서버가 저장한 바이트**다. 그래서 첫 전송이
#         항상 offset=0 으로 나가 서버 리셋 경로(행 생성)를 타고, 이후로도 append 조건
#         (저장 bytes === offset)이 계속 맞는다. floor 를 .offset 에 직접 선점하면 첫
#         전송이 offset>0 인데 행이 없어 **영구 409** 이고, 409 복구가 offset=0(파일 처음
#         부터 전체)이라 "동의 이후만" 이 정확히 반대로 깨진다 — floor 분리가 그 덫을
#         통째로 피한다. 409 가 나도 재전송 시작점은 FLOOR 라 floor 이전으로는 절대 못
#         내려간다. 리셋 전송에는 start=<FLOOR> 를 실어 서버가 "앞부분 제외"를 안다.
#
#   결손  못 보낸 이유를 남긴다 — 무흔적 종료는 "안 돈 것"과 구분되지 않아 재발 시 로컬
#         에서도 판정이 불가능하다(2026-07-29 진단이 여기서 막혔다). transcript_path 부재·
#         허용 밖 경로·파일 없음 3종은 결과 마커 + handshake skip_reason 으로 서버에도
#         기록한다. 사유별 <sid>.skip-<reason> 일회성 마커로 도구 호출마다의 폭주를 막는다.
#         토큰 마커 게이트만은 무흔적을 유지한다 — 그 자리 역할은 남의 세션 보호이고,
#         토큰이 없으면 보고할 주소 자체가 없다(설계상 남길 수 없는 것이지 누락이 아니다).
#
#   전제  ①install_token 마커 존재(불충족 시 무흔적 종료) ②그 코칭에 대한 동의
#         ③transcript_path 가 허용 경로의 실제 파일.
#   서버  handshake(게이트 preflight) 통과 시에만 upload. 서버가 본 방어선 — 이 훅은
#         마커/스로틀/압축만 담당하고, 계정 임직원·consent 판정은 전적으로 서버가 한다.
#
#   결과  매 시도의 끝을 결과 마커(<session>.transcript-result)에 남긴다. 백그라운드라
#         사용자가 성패를 알 길이 없어서 — 런처가 이 파일을 읽어 "보냈습니다 / 동의가
#         없어 못 보냅니다"를 전한다. 수동 전송은 스로틀 마커를 지우는 것으로 깨운다.
#
#   크기  gzip 을 *먼저* 하고 압축 후 크기로 판정한다(서버 바디 캡이 압축 후 기준이라
#         raw 로 재는 건 무의미). 한도 초과면 업로드 대신 handshake 에 skip_reason 을
#         실어 **결손을 서버에 기록**한다.
#
# 보안 (open-and-track.sh 원칙 준수):
#   W4 검증      install_token 은 UUID 정규식 통과분만 URL·마커 경로 조립에 쓴다.
#   W5 세션 격리 session_id 없으면 마커 안 쓰고 업로드도 안 함(토큰/스로틀 bleed 방지).
#   W6 권한      마커 파일 600 / 디렉토리 700.
#   경로 제한    transcript_path 는 $HOME/.claude/ 하위 .jsonl 만 허용(.. 포함 시 거부).
#                훅 입력이 가리키는 임의 파일을 서버로 보내지 않기 위함.
#   주입 차단    URL 에는 sanitize 된 session_id(영숫자·_-) 와 UUID 토큰·정수 크기만 실린다.
#                transcript_path 는 로컬 파일 인자로만 쓰고(서버로 안 보냄) tool_response 도
#                파싱하지 않는다. DRYRUN 출력에도 토큰을 찍지 않는다.
#
# 원칙: best-effort. 업로드 실패가 사용자 도구 실행 흐름을 절대 막지 않는다 → 모든 경로 exit 0.

# ── 0. 킬스위치 ─────────────────────────────────────────────────────────────
if [ -n "$RONA_TRANSCRIPT_HOOK_DISABLED" ]; then
  exit 0
fi

# 필수 바이너리 없으면 조용히 종료(best-effort).
command -v curl >/dev/null 2>&1 || exit 0
command -v gzip >/dev/null 2>&1 || exit 0

# stdin 의 hook JSON 을 읽는다 (없으면 조용히 종료)
INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

# tool_response(도구 출력)는 파싱 범위에서 제외(폴백 파서 오염 방지). jq 경로는 정밀 추출.
SAFE="${INPUT%%\"tool_response\"*}"

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
is_uuid() { printf '%s' "$1" | grep -qE "^${UUID_RE}$"; }

# 최상위 스칼라 문자열 필드 (jq=정밀, 폴백=SAFE 범위에서만)
json_top() {
  local key="$1"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$INPUT" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$SAFE" \
      | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -n1 \
      | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"
  fi
}

EVENT_NAME="$(json_top hook_event_name)"
TRANSCRIPT_PATH="$(json_top transcript_path)"
# W5: session_id 정화. 비면 세션 격리 불가 → 마커·업로드 모두 skip(bleed 방지).
SESSION_ID="$(json_top session_id | tr -cd 'A-Za-z0-9_-' | cut -c1-100)"
[ -n "$SESSION_ID" ] || exit 0

SESS_DIR="$HOME/.rona/session"
CONSENT_DIR="$HOME/.rona/consent"                          # 코칭(install_token) 단위 동의 마커
TOKEN_MARKER="$SESS_DIR/${SESSION_ID}.token"
UPLOAD_MARKER="$SESS_DIR/${SESSION_ID}.transcript"          # mtime = 마지막 시도 시각(스로틀)
RESULT_MARKER="$SESS_DIR/${SESSION_ID}.transcript-result"   # 런처가 읽어 사용자에게 전할 결과
PROBE_MARKER="$SESS_DIR/${SESSION_ID}.probe"                # 이 세션에서 서버에 이미 물어봤다
OFFSET_MARKER="$SESS_DIR/${SESSION_ID}.offset"             # 서버가 저장한 raw 바이트(누적 전송량)
FLOOR_MARKER="$SESS_DIR/${SESSION_ID}.floor"               # 보내도 되는 첫 바이트(동의 시점 선점)

# 결과 1줄 기록(런처가 읽는 유일한 표면). 값은 전부 우리가 만든 토큰·정수뿐.
# DRYRUN 에서는 검증용으로 같은 줄을 stdout 에도 찍는다(파일은 그대로 남긴다).
write_result() {
  {
    printf 'status=%s session=%s at=%s' \
      "$1" "$(printf '%s' "$SESSION_ID" | cut -c1-8)" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    [ -n "$2" ] && printf ' %s' "$2"
    printf '\n'
  } > "$RESULT_MARKER" 2>/dev/null
  chmod 600 "$RESULT_MARKER" 2>/dev/null
  if [ -n "$RONA_HOOK_DRYRUN" ]; then
    printf 'RESULT status=%s' "$1"
    [ -n "$2" ] && printf ' %s' "$2"
    printf '\n'
  fi
}

# ── 전제 게이트 ─────────────────────────────────────────────────────────────
# 토큰 마커 부재 = 로나와 무관한 세션. 여기만 무흔적을 유지한다(보고할 주소가 없다).
[ -f "$TOKEN_MARKER" ] || exit 0
TOKEN="$(cat "$TOKEN_MARKER" 2>/dev/null | tr -d '[:space:]')"
is_uuid "$TOKEN" || exit 0                             # W4: 마커 토큰 재검증

BASE="https://rona.so/skill/api/transcript/${TOKEN}"
CONSENT_MARKER="$CONSENT_DIR/${TOKEN}"

# 세션 종료 이벤트는 최종 1회라 스로틀을 건너뛴다. 그 외(Stop·PostToolUse)는 마지막
# 시도 후 2분 안이면 skip — find -mmin 은 mac/linux 공통.
#   수동 전송("지금 보내줘")은 이 마커를 지우는 것으로 창을 연다 — rm 실행 자체가
#   PostToolUse 를 깨우므로 별도 트리거가 필요 없다.
if [ "$EVENT_NAME" != "SessionEnd" ]; then
  if find "$UPLOAD_MARKER" -mmin -2 2>/dev/null | grep -q .; then
    exit 0
  fi
fi

# W6: 마커 디렉토리 권한 최소화 후, 스로틀 창을 지금 선점(마커 mtime=now). 백그라운드
# 작업 전에 선점해야 rapid PostToolUse 가 동시에 중복 업로드를 띄우지 않는다. 실패하면
# 이 창(2분)은 놓치지만 다음 창·SessionEnd(강제)가 백스톱 — 멱등이라 재업로드 안전.
# 동의 게이트보다 앞에 두는 이유: 미동의 세션이 매 도구 호출마다 프로브를 띄우지 않게.
mkdir -p "$SESS_DIR" 2>/dev/null
chmod 700 "$HOME/.rona" "$SESS_DIR" 2>/dev/null
: > "$UPLOAD_MARKER" 2>/dev/null
chmod 600 "$UPLOAD_MARKER" 2>/dev/null

# 결손 보고: 결과 마커 + 서버 skip_reason(사유당 세션 1회). 서버가 미동의로 403 을 주면
# 기록은 안 되지만 로컬 결과는 남는다 — 그쪽은 어드민의 동의 상태 컬럼으로 드러난다.
report_skip() {
  local reason="$1"
  local guard="$SESS_DIR/${SESSION_ID}.skip-${reason}"
  write_result "$reason"
  [ -f "$guard" ] && return 0
  : > "$guard" 2>/dev/null
  chmod 600 "$guard" 2>/dev/null
  if [ -n "$RONA_HOOK_DRYRUN" ]; then
    echo "SKIP POST ${BASE%/*}/<token>/handshake BODY={\"session_id\":\"${SESSION_ID}\",\"bytes\":0,\"gz_bytes\":0,\"skip_reason\":\"${reason}\"}"
    return 0
  fi
  curl -fsS -m 10 -o /dev/null \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":0,\"gz_bytes\":0,\"skip_reason\":\"${reason}\"}" \
    "${BASE}/handshake" >/dev/null 2>&1 &
}

# ── 동의 게이트 (코칭 단위) ─────────────────────────────────────────────────
# 마커는 캐시다. 없으면 서버에 한 번 물어보고(프로브) 그 답으로 스스로 고친다.
if [ ! -f "$CONSENT_MARKER" ]; then
  if [ -f "$PROBE_MARKER" ]; then
    write_result "no_consent"
    exit 0
  fi
  if [ -n "$RONA_HOOK_DRYRUN" ]; then
    echo "PROBE POST ${BASE%/*}/<token>/handshake BODY={\"session_id\":\"${SESSION_ID}\",\"bytes\":0,\"gz_bytes\":0}"
    exit 0
  fi
  probe_code="$(curl -fsS -m 5 -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":0,\"gz_bytes\":0}" \
    "${BASE}/handshake" 2>/dev/null)"
  if [ "$probe_code" = "200" ]; then
    # 서버가 동의를 인정한다 → 로컬 마커 자가복구 후 통과.
    mkdir -p "$CONSENT_DIR" 2>/dev/null
    chmod 700 "$CONSENT_DIR" 2>/dev/null
    : > "$CONSENT_MARKER" 2>/dev/null
    chmod 600 "$CONSENT_MARKER" 2>/dev/null
  elif [ "$probe_code" = "403" ]; then
    write_result "no_consent"
    : > "$PROBE_MARKER" 2>/dev/null
    chmod 600 "$PROBE_MARKER" 2>/dev/null
    exit 0
  else
    # 네트워크·서버 장애 — 판정 불가. 마커도 세우지 않아 다음 창에서 다시 물어본다.
    write_result "failed" "step=probe"
    exit 0
  fi
fi

# ── 대상 파일 확인 (결손 3종) ───────────────────────────────────────────────
if [ -z "$TRANSCRIPT_PATH" ]; then
  report_skip "no_transcript_path"
  exit 0
fi
# 경로 제한: $HOME/.claude/ 하위 .jsonl 만. 상위 탈출(..) 은 무조건 거부.
case "$TRANSCRIPT_PATH" in
  *..*) report_skip "path_not_allowed"; exit 0 ;;
esac
case "$TRANSCRIPT_PATH" in
  "$HOME"/.claude/*.jsonl) ;;
  *) report_skip "path_not_allowed"; exit 0 ;;
esac
if [ ! -f "$TRANSCRIPT_PATH" ]; then
  report_skip "file_missing"
  exit 0
fi

# 현재 파일 전체 크기(raw).
BYTES="$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -cd '0-9')"
[ -n "$BYTES" ] || exit 0

# ── floor: 보내도 되는 첫 바이트 ────────────────────────────────────────────
# 동의 게이트를 통과한 *직후* 한 번만 잡는다(거절 후 재부여도 그 시점이 floor 가 된다).
#   .floor 없음 + .offset 있음 → 0. 구버전에서 이어받은 세션이라 서버 저장분과 갭이
#                                 생기면 안 된다(offset 이 파일 절대 위치였다).
#   .floor 없음 + .offset 없음 → 지금 파일 끝. 동의 이전 대화를 잘라낸다.
FLOOR="$(cat "$FLOOR_MARKER" 2>/dev/null | tr -cd '0-9')"
if [ -z "$FLOOR" ]; then
  if [ -f "$OFFSET_MARKER" ]; then
    FLOOR=0
  else
    FLOOR="$BYTES"
  fi
  printf '%s' "$FLOOR" > "$FLOOR_MARKER" 2>/dev/null
  chmod 600 "$FLOOR_MARKER" 2>/dev/null
fi

# 파일이 floor 보다 작아졌으면(축소·회전) 이 세션의 기준을 처음부터 다시 잡는다.
if [ "$FLOOR" -gt "$BYTES" ] 2>/dev/null; then
  FLOOR=0
  printf '0' > "$FLOOR_MARKER" 2>/dev/null
  chmod 600 "$FLOOR_MARKER" 2>/dev/null
  printf '0' > "$OFFSET_MARKER" 2>/dev/null
  chmod 600 "$OFFSET_MARKER" 2>/dev/null
fi

# ── 증분(delta) 시작점 계산 ─────────────────────────────────────────────────
# OFFSET = 서버가 저장한 raw 바이트(= floor 이후 누적 전송량). 첫 전송은 항상 0 이라
# 서버 리셋 경로로 행이 생기고, 이후엔 append 조건(저장 bytes === offset)이 맞는다.
OFFSET="$(cat "$OFFSET_MARKER" 2>/dev/null | tr -cd '0-9')"
[ -n "$OFFSET" ] || OFFSET=0
START=$((FLOOR + OFFSET))
# 서버가 아는 것보다 파일이 작아졌으면(드리프트) floor 부터 다시 — floor 아래로는 안 간다.
if [ "$START" -gt "$BYTES" ] 2>/dev/null; then
  OFFSET=0
  START="$FLOOR"
fi
# 새로 붙은 게 없으면(=이미 다 보냄) 조용히 끝낸다 — 빈 전송 안 한다.
[ "$START" -eq "$BYTES" ] 2>/dev/null && exit 0
# 이 조각(delta)의 raw 크기.
DELTA_RAW=$((BYTES - START))

# gzip 후 상한 4.5MB — 서버 바디 캡과 같은 값. 이제 조각(delta) 하나당 상한이라 긴
# 세션도 여기 안 걸린다(전체가 아니라 새로 붙은 부분만 보내므로).
MAX_GZ=4718592

# 리셋 전송(offset=0)에는 잘라낸 앞부분 길이를 함께 알린다 — 어드민이 "전문"으로 오독
# 하지 않도록. append 전송엔 붙이지 않는다(서버가 이미 아는 값이라 무의미).
UPLOAD_QS="session_id=${SESSION_ID}&bytes=${DELTA_RAW}&offset=${OFFSET}"
if [ "$OFFSET" -eq 0 ] 2>/dev/null; then
  UPLOAD_QS="${UPLOAD_QS}&start=${FLOOR}"
fi

if [ -n "$RONA_HOOK_DRYRUN" ]; then
  # 토큰은 찍지 않는다(로그·화면 유출 차단) — 경로는 자리표시자로.
  echo "DELTA floor=${FLOOR} offset=${OFFSET} start=${START} bytes=${BYTES} delta_raw=${DELTA_RAW}"
  echo "HANDSHAKE POST ${BASE%/*}/<token>/handshake BODY={\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":<gz>}"
  echo "UPLOAD PUT ${BASE%/*}/<token>/upload?${UPLOAD_QS} (gzip tail +$((START + 1)) ${TRANSCRIPT_PATH})"
  exit 0
fi

# ── 백그라운드 (도구 흐름 비차단) ───────────────────────────────────────────
#   1) START 이후 새 부분만 잘라 gzip → 조각 크기로 한도 판정.
#   2) 조각이 상한 초과면(드묾) handshake 에 skip_reason 만 실어 결손 기록.
#   3) 아니면 handshake preflight(200) 통과 시에만 PUT(offset 실어).
#   4) 200 → OFFSET_MARKER 를 BYTES-FLOOR 로 갱신(= 서버 저장 bytes). 409(offset 불일치)
#      → OFFSET_MARKER=0 리셋(다음 발사 때 FLOOR 부터 재전송으로 자가복구).
#   실패는 전부 삼키되 결과 마커에는 남긴다. 임시 gz 는 항상 정리.
(
  tmp_gz="$(mktemp 2>/dev/null)" || exit 0
  # START 이후만 잘라 gzip. tail -c +N 은 N 번째 바이트부터(1-기반)라 +$((START+1)).
  if ! tail -c "+$((START + 1))" "$TRANSCRIPT_PATH" 2>/dev/null | gzip -c > "$tmp_gz" 2>/dev/null; then
    rm -f "$tmp_gz" 2>/dev/null
    write_result "failed" "step=gzip"
    exit 0
  fi
  GZ_BYTES="$(wc -c < "$tmp_gz" 2>/dev/null | tr -cd '0-9')"
  if [ -z "$GZ_BYTES" ]; then
    rm -f "$tmp_gz" 2>/dev/null
    write_result "failed" "step=size"
    exit 0
  fi

  if [ "$GZ_BYTES" -gt "$MAX_GZ" ]; then
    curl -fsS -m 10 -o /dev/null \
      -X POST -H 'Content-Type: application/json' \
      -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":${GZ_BYTES},\"skip_reason\":\"too_large\"}" \
      "${BASE}/handshake" >/dev/null 2>&1
    rm -f "$tmp_gz" 2>/dev/null
    write_result "too_large" "gz_bytes=${GZ_BYTES} limit=${MAX_GZ}"
    exit 0
  fi

  code="$(curl -fsS -m 10 -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"${SESSION_ID}\",\"bytes\":${DELTA_RAW},\"gz_bytes\":${GZ_BYTES}}" \
    "${BASE}/handshake" 2>/dev/null)"
  if [ "$code" = "200" ]; then
    up_code="$(curl -fsS -m 60 -o /dev/null -w '%{http_code}' \
      -X PUT -H 'Content-Type: application/gzip' \
      --data-binary "@${tmp_gz}" \
      "${BASE}/upload?${UPLOAD_QS}" 2>/dev/null)"
    if [ "$up_code" = "200" ]; then
      # 다음 전송 시작점 = 서버가 저장한 누적 바이트(floor 이후분).
      printf '%s' "$((BYTES - FLOOR))" > "$OFFSET_MARKER" 2>/dev/null
      chmod 600 "$OFFSET_MARKER" 2>/dev/null
      write_result "sent" "gz_bytes=${GZ_BYTES} offset=${OFFSET}"
    elif [ "$up_code" = "409" ]; then
      # offset 불일치(서버 행 삭제·재claim 드리프트) → 다음엔 FLOOR 부터 리셋 재전송.
      printf '0' > "$OFFSET_MARKER" 2>/dev/null
      chmod 600 "$OFFSET_MARKER" 2>/dev/null
      write_result "retry" "reason=offset_mismatch"
    else
      write_result "failed" "step=upload"
    fi
  elif [ "$code" = "403" ]; then
    # 서버 게이트 거부(미동의·비임직원·토큰 무효 — 사유는 서버가 안 알려준다).
    write_result "denied"
  else
    write_result "failed" "step=handshake"
  fi
  rm -f "$tmp_gz" 2>/dev/null
) &

exit 0
