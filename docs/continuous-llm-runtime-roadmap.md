# Continuous LLM Runtime 로드맵

## 목적

이 문서는 [continuous-llm-runtime.md](/C:/Users/USER/Documents/VisionNavi/docs/continuous-llm-runtime.md) 에 정리한 목표 아키텍처를, 현재 VisionNavi 코드베이스 기준의 실제 구현 작업으로 내려 쓴 로드맵이다.

핵심 목적은 이상적인 구조를 추상적으로 설명하는 것이 아니라, 현재 코드에서 어디가 아직 `one-shot planner` 중심인지 짚고, 이를 `Continuous LLM-guided Runtime Loop`로 옮기기 위한 다음 작업 순서를 명확히 하는 것이다.

## 현재 상태 진단

### 이미 갖춰진 기반

현재 VisionNavi에는 아래와 같은 기반이 이미 존재한다.

- canonical command 생성
- task domain 라우팅
- browser / desktop executor 분리
- session timeline 및 debug trace
- observe / plan / act / verify / recover 형태의 루프
- 일부 작업에 대한 deterministic verification

관련 주요 모듈:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/services/model_client.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/automation/desktop/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)

### 아직 one-shot planner 성격이 강한 지점

현재 구현은 여전히 몇 군데에서 `한 번 계획하고 그대로 실행하는 구조`에 가깝다.

1. `ActionPlanRequest`가 batch 중심이다
   - planner는 한 번의 observation, prior_steps, last_result를 받고
   - 한 번에 전체 action plan을 반환한다

2. `RemoteModelClient.plan_action_steps()`가 full-plan 반환 구조다
   - 프롬프트가 `steps` 배열 전체를 한 번에 만들도록 유도한다
   - 따라서 모델이 너무 이른 시점에 절차 전체를 확정해버리기 쉽다

3. `AgentLoop._plan_actions()`가 single-pass 구조다
   - 계획은 한 번 세우고
   - normalize도 한 번 하고
   - 이후에는 그 계획을 그대로 실행한다
   - 중간 상태 변화에 따른 재계획이 step 단위로 일어나지 않는다

4. `BrowserExecutor.execute_action_plan()`이 순차 실행 중심이다
   - 주어진 step list를 끝까지 밀어붙이는 구조다
   - 중간에 모델이 “다음엔 이걸 해야 한다”고 다시 판단하는 구조가 아니다

5. `observe()`가 runtime reasoning 관점에서는 아직 얕다
   - 현재 browser observation은 query나 route slot 위주다
   - candidate target, page region, ambiguity 같은 정보를 모델 친화적으로 충분히 드러내지 못한다

6. trace가 아직 step 중심이다
   - `planned_steps`, `executed_steps`는 보이지만
   - 어떤 후보를 봤고 왜 그 대상을 골랐는지는 1급 정보가 아니다

7. recovery가 대부분 deterministic fallback 중심이다
   - 내부 템플릿이나 retry는 있지만
   - “현재 상태를 다시 해석해서 다른 경로를 선택하자”는 LLM 보조 recovery는 아직 없다

## 현재 구조와 목표 구조의 차이

현재 시스템은 가장 정확히 말하면 다음에 가깝다.

- LLM-assisted canonicalization
- optional one-shot action planning
- deterministic execution
- deterministic verification

목표 시스템은 다음이어야 한다.

- LLM-assisted canonicalization
- iterative runtime observation
- LLM-guided next-action choice
- deterministic execution
- deterministic + model-assisted verification
- deterministic + LLM-guided recovery

즉 중심축이

- `plan once, execute many`

에서

- `observe, decide one step, execute, verify, repeat`

로 옮겨가야 한다.

## 목표 루프

현재 `AgentLoop`가 장기적으로 지향해야 할 실행 패턴은 아래와 같다.

1. 현재 상태를 관찰한다
2. 모델에 전달할 runtime context를 만든다
3. 전체 계획이 아니라 `다음 한 단계`를 모델에게 묻는다
4. 그 한 단계를 deterministic executor로 실행한다
5. 실제로 의도한 변화가 일어났는지 검증한다
6. 계속 진행할지, recovery할지, 종료할지 판단한다

이 루프를 작업 완료 시점까지 반복하는 구조가 목표다.

## 권장 마일스톤

### 마일스톤 1. Trace-First 리팩터링

목표:
실행 로직을 크게 바꾸기 전에, runtime reasoning을 추적 가능하게 만든다.

작업 항목:

1. browser observation payload 확장
   - page title
   - URL
   - visible summary
   - lightweight candidate inventory
2. trace 구조 확장
   - `observation`
   - `candidate_set`
   - `chosen_target`
   - `choice_reason`
   - `verification_result`
   - `recovery_reason`
3. 기존 `planned_steps`는 호환성 때문에 유지
   - 다만 앞으로 iterative loop에서도 쓸 수 있는 runtime trace 필드를 같이 추가

주요 파일:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)

완료 기준:

- trace만 봐도 시스템이 무엇을 봤는지 알 수 있다
- trace만 봐도 왜 그 대상을 골랐는지 알 수 있다
- trace만 봐도 실제 목표가 완료됐는지 판단 근거를 볼 수 있다

### 마일스톤 2. Next-Action API 도입

목표:
전체 step plan 반환 방식 대신, 모델이 `다음 한 단계`만 반환하도록 바꾼다.

작업 항목:

1. runtime decision 전용 request 모델 추가
   - 예시 필드:
     - `command`
     - `observation`
     - `candidate_targets`
     - `history`
     - `last_result`
2. next-action 전용 response 모델 추가
   - 예시 필드:
     - `action`
     - `target_hint`
     - `text`
     - `reasoning`
     - `done`
     - `needs_recovery`
3. 기존 `plan_action_steps()` 경로는 당분간 유지
   - 기존 흐름을 깨지 않기 위한 호환 경로로 남김
4. `RemoteModelClient.decide_next_action()` 추가

주요 파일:

- [orchestrator/app/models/model_api.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/model_api.py)
- [orchestrator/app/services/model_client.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)

완료 기준:

- 모델이 전체 절차가 아니라 `다음 액션 하나`를 대답할 수 있다
- orchestrator가 기존 기능을 깨지 않고 이 API를 호출할 수 있다

### 마일스톤 3. Iterative Browser Loop 전환

목표:
브라우저 작업을 one-shot plan 실행이 아니라 iterative runtime loop로 전환한다.

작업 항목:

1. `AgentLoop`에 browser 전용 iterative loop 추가
2. 각 browser action 이후:
   - fresh observation 수집
   - candidate target 수집
   - 모델에게 다음 action 질의
3. 종료 조건 정의:
   - verification이 완료를 판정
   - 모델이 `done`을 반환
   - 안전/재시도 제한 도달
4. 기존 deterministic route/search flow는 제거하지 않고 backup으로 유지

주요 파일:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)

완료 기준:

- 브라우저 작업이 중간 상태 변화마다 다시 판단할 수 있다
- 더 이상 전체 browser plan을 선확정하지 않아도 된다

### 마일스톤 4. Candidate-Aware Observation

목표:
모델이 raw screen state만 보는 것이 아니라, 구조화된 후보 집합을 함께 보게 만든다.

작업 항목:

1. browser candidate inventory 추출
   - clickable controls
   - input-like controls
   - result-like regions
2. 한 세션 내에서 stable candidate ID 부여
3. 가능하면 모델이 selector가 아니라 candidate ID를 선택하도록 유도
4. candidate score와 choice reason을 trace에 저장

주요 파일:

- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)

완료 기준:

- 프롬프트가 자유 텍스트 selector보다 candidate 기반으로 바뀐다
- trace에서 어떤 후보들이 있었고 무엇이 선택됐는지 보인다

### 마일스톤 5. LLM-Guided Recovery

목표:
deterministic fallback에서 한 단계 더 나아가, 막혔을 때 모델이 현재 상태를 다시 해석하도록 한다.

작업 항목:

1. runtime stall 조건 정의
   - low-confidence choice 반복
   - same-page no-op action 반복
   - verification failure 반복
2. recovery decision용 모델 호출 추가
3. 모델이 아래 중 하나를 선택할 수 있도록 설계
   - 다른 target으로 retry
   - backtrack
   - 검색 전략 변경
   - 사용자 확인 요청
   - 구조화된 실패로 종료

주요 파일:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/services/model_client.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)

완료 기준:

- recovery가 static fallback이 아니라 현재 runtime state 기반으로 동작한다

### 마일스톤 6. Hybrid Verification

목표:
“버튼이 눌렸다”가 아니라 “작업 목표가 달성됐다”를 판단하는 검증 체계로 전환한다.

작업 항목:

1. deterministic verification이 강한 곳은 유지
2. 애매한 작업에는 model-assisted completion check 추가
3. trace에서 아래 상태를 구분해 남김
   - action success but task incomplete
   - task complete
   - task blocked
   - task ambiguous

주요 파일:

- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)

완료 기준:

- local UI interaction 성공과 task 성공을 동일시하지 않는다

## 권장 구현 순서

권장 순서는 다음과 같다.

1. Trace-First 리팩터링
2. Next-Action API 도입
3. Iterative Browser Loop 전환
4. Candidate-Aware Observation
5. LLM-Guided Recovery
6. Hybrid Verification

이 순서를 권장하는 이유는, 실행 구조를 바꾸기 전에 먼저 관측성과 추적성을 확보하는 것이 위험을 크게 줄여주기 때문이다.

## 지금 바로 할 수 있는 근거리 작업

현재 리포지토리에서 가장 현실적으로 바로 들어갈 수 있는 작업은 다음과 같다.

1. `NextActionRequest`, `NextActionResponse` 추가
2. `RemoteModelClient.decide_next_action()` 추가
3. browser candidate inventory 추출
4. trace에 `chosen_target`, `choice_reason` 추가
5. feature flag 뒤에서 iterative browser loop 구현
6. `search_and_read`를 첫 번째 이행 대상로 전환
7. `find_map_route`를 두 번째 이행 대상로 전환

## 지금 하면 안 되는 방향

아래 방향은 현재 목표와 맞지 않는다.

- 하드코딩된 browser step template를 먼저 많이 늘리는 것
- full-plan 프롬프트 의존도를 더 높이는 것
- planner를 더 길고 복잡하게 만드는 것
- selector 성공을 task 성공으로 간주하는 것

## 진행 판단 기준

VisionNavi가 올바른 방향으로 가고 있다는 신호는 아래와 같다.

- 모델이 전체 절차보다 `다음 결정`을 더 자주 맡는다
- 브라우저 실행이 각 step 뒤 fresh observation에 반응한다
- trace에 target 선택 이유가 남는다
- recovery가 static fallback보다 current state를 더 많이 반영한다
- task 완료 판정이 action level이 아니라 goal level에서 이뤄진다
