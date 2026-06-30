# VisionNavi External-First 안정화 계획

## 목적
이 문서는 VisionNavi를 `external-first` 실행축으로 안정화하기 위한 단기 개발 계획이다.

현재 상태는 다음과 같다.

- 브라우저 기본 실행축은 `external_browser_agent`
- 데스크톱 기본 실행축은 `external_desktop_agent`
- 내부 실행기는 fallback과 baseline 역할로 유지
- `find_map_route`는 당분간 internal baseline 소유

문제는 “연결은 되었지만 반복적으로 믿고 쓸 수 있는가”가 아직 완전히 검증되지 않았다는 점이다.  
따라서 지금부터의 목표는 기능 확장보다도 `재현성`, `측정 가능성`, `실패 분류`, `UI 관측성`을 먼저 확보하는 것이다.

## 핵심 목표

### 1. external browser를 회귀검증 가능한 상태로 고정
대상 시나리오:

- `search_and_read`

완료 기준:

- 대표 명령 5~10개를 고정 benchmark 세트로 정의
- 각 명령을 반복 실행했을 때 다음 필드가 자동 수집됨
  - `success`
  - `failure_reason`
  - `duration_ms`
  - `step_count`
  - `visited_domains`
  - `final_domain`
  - `matched_tokens`
  - `query_tokens`
- `off_target_navigation`, `off_target_summary`, `timeout`, `empty_summary`가 구분되어 집계됨
- 1회 성공이 아니라 반복 성공률 기준으로 판단 가능해야 함

의미:

- “이번엔 됐다”가 아니라 “같은 명령을 여러 번 돌려도 어느 수준으로 되는지”를 수치로 볼 수 있어야 한다.

### 2. external desktop를 반복 검증 가능한 상태로 고정
대상 시나리오:

- `open_notepad_and_type`

완료 기준:

- 대표 명령 2~3개를 고정 검증 세트로 정의
- 각 명령 반복 실행 시 다음 필드가 자동 수집됨
  - `success`
  - `failure_reason`
  - `duration_ms`
  - `step_count`
  - `attempt_count`
  - `expected_text`
  - `observed_text`
  - `exact_match`
  - `contains_expected_text`
- `timeout`, `agent_incomplete`, `partial_text_saved`, `verification_failed`, `no_output`가 구분되어 집계됨

의미:

- 외부 desktop agent가 “실행했는가”가 아니라 “정확한 텍스트를 저장했는가”를 기준으로 평가해야 한다.

### 3. UI trace를 디버깅 친화적으로 정리
완료 기준:

- `Requested Backend`, `Effective Backend`, `Fallback Backend`, `Failure Reason`이 상단에 더 명확히 노출됨
- `Canonical Review`, `Agent Trace`, `Event Timeline`이 좁은 폭에서도 깨지지 않음
- trace export는 benchmark 결과와 비교 가능한 구조를 유지

의미:

- 수동 검증 중에도 사용자가 “왜 실패했는지”를 UI에서 바로 읽을 수 있어야 한다.

세부 체크리스트:

1. 상단 요약 블록에 backend 정보와 failure reason을 고정 노출
2. `Canonical Review` 버튼 행이 제목을 밀어내지 않도록 제목/버튼 영역 분리
3. 카드 본문은 모두 스크롤 가능하고 텍스트 선택 가능 상태 유지
4. 좁은 폭에서는 2열이 아니라 1열 stack으로 강제 전환
5. `validation`, `attempt_count`, `final_domain` 같은 benchmark 핵심 필드를 숨기지 않고 바로 보이게 조정
6. export JSON과 화면 표시 필드 이름을 최대한 일치시켜 사용자가 trace 해석 시 혼동하지 않게 유지

### 4. route external 이전 판단 기준을 먼저 고정
완료 기준:

- `find_map_route`를 external로 옮기기 전에 확인할 조건을 문서화
- 브라우저/데스크톱 기준 benchmark가 안정화되기 전에는 route를 external 주 개발축으로 확대하지 않음

의미:

- route는 디버깅 축이 너무 많기 때문에, 현재는 옮길지 여부를 판단하는 기준부터 명확히 해야 한다.

이전 판단 체크리스트:

1. browser benchmark 대표 명령에서 반복 성공률이 충분히 안정적일 것
2. off-target taxonomy가 실제 실패 원인을 잘 분리하고 있을 것
3. desktop benchmark에서도 retry 없이 성공하는 케이스가 일정 비율 이상 확보될 것
4. UI trace만으로 external 실패 이유를 빠르게 읽을 수 있을 것
5. route 이전 전에는 “site drift”, “query drift”, “summary hallucination” 문제가 search 시나리오에서 먼저 통제될 것
6. 위 조건을 만족하기 전에는 route를 external 주개발축으로 확대하지 않을 것

## 작업 순서

### Phase 1. benchmark 체계 만들기
산출물:

- browser benchmark 명령셋
- desktop benchmark 명령셋
- 반복 실행 스크립트
- JSON 결과 저장 형식

완료 조건:

- 수동 실행 없이도 반복 검증이 가능
- 실행 결과를 나중에 비교할 수 있게 파일로 남김

### Phase 2. failure taxonomy 검증
산출물:

- browser taxonomy 검증 결과
- desktop taxonomy 검증 결과
- false success / false failure 목록

완료 조건:

- 같은 문제를 매번 trace를 눈으로 읽지 않고도 분류할 수 있음

### Phase 3. UI trace 개선
산출물:

- 상단 상태 요약 재배치
- 실패 사유 시각 강조
- 좁은 폭 레이아웃 보정

완료 조건:

- 사용자가 benchmark 결과를 앱 UI만 보고도 추적 가능

### Phase 4. route 이전 판단
산출물:

- route external 이전 체크리스트
- 내부 유지 여부 판단 메모

완료 조건:

- route를 옮길지 말지를 감이 아니라 기준으로 판단

## 측정 항목

### Browser 공통 측정 항목

- `command`
- `session_id`
- `requested_backend`
- `effective_backend`
- `fallback_backend`
- `success`
- `failure_reason`
- `duration_ms`
- `step_count`
- `matched_tokens`
- `query_tokens`
- `visited_domains`
- `final_domain`

### Desktop 공통 측정 항목

- `command`
- `session_id`
- `requested_backend`
- `effective_backend`
- `fallback_backend`
- `success`
- `failure_reason`
- `duration_ms`
- `step_count`
- `attempt_count`
- `expected_text`
- `observed_text`
- `exact_match`
- `contains_expected_text`

## 초기 benchmark 세트

### Browser

1. `Search Naver for VisionNavi and read a short summary.`
2. `Search Naver for Incheon youth monthly rent support and read the conditions.`
3. `Search Google for YouTube and summarize the results page.`
4. `Search Naver for Seoul youth housing support and read the eligibility conditions.`
5. `Search Google for OpenAI Codex and summarize the results page.`

### Desktop

1. `Open Notepad and type exactly VisionNavi external desktop verification, then save the file.`
2. `Open Notepad and type exactly External desktop benchmark line one, then save the file.`
3. `Open Notepad and type exactly VisionNavi retry taxonomy check, then save the file.`

## 성공 판단 방식

### Browser

- 성공은 단순히 `status=success`가 아니다.
- 다음이 모두 맞아야 성공으로 본다.
  - `effective_backend=external_browser_agent`
  - `validation.ok=true`
  - `final_domain`이 의도한 엔진/사이트와 일치
  - query grounding이 유지됨

### Desktop

- 성공은 단순히 파일이 생긴 것이 아니다.
- 다음이 모두 맞아야 성공으로 본다.
  - `effective_backend=external_desktop_agent`
  - `observed_text == expected_text`
  - `exact_match=true`

## 현재 판단

지금 시점의 1순위는 기능 확장이 아니라 benchmark 자동화다.  
그 이유는 다음과 같다.

- browser external은 성공과 실패가 모두 나오고 있으며, drift 문제를 taxonomy로 잡는 단계에 들어왔다.
- desktop external은 retry/taxonomy는 붙었지만 반복 성공률을 아직 수치로 모른다.
- UI는 개선 중이지만 benchmark 기준이 없으면 무엇을 얼마나 개선했는지 판단하기 어렵다.

따라서 현재 공식 우선순위는 다음과 같다.

1. browser benchmark 자동화
2. desktop benchmark 자동화
3. UI trace 가독성 마무리
4. route external 이전 판단
