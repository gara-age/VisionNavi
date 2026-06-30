# VisionNavi 통합 개발 역사 문서

## 1. 문서 목적

이 문서는 VisionNavi 프로젝트의 개발 역사, 제품 목표, 구현 방향, 현재 상태, 전략적 판단을 하나의 파일 안에 정리한 통합 문서다.

이 문서의 독자는 다음과 같다.

- 현재 VisionNavi를 직접 개발하고 있는 개발자
- 앞으로 이 프로젝트에 합류할 개발자 또는 협업자
- BrowserUse / ComputerUse류 외부 agent runtime 통합 방향을 빠르게 이해해야 하는 사람

이 문서 하나만 읽어도 다음 질문에 답할 수 있어야 한다.

- VisionNavi는 어떤 프로젝트인가?
- 왜 JSON step 기반 자동화를 넘어서려 했는가?
- Runtime Binding은 무엇이고 왜 한계를 느꼈는가?
- 왜 Continuous LLM-guided runtime 방향으로 갔는가?
- internal / external backend는 각각 무엇인가?
- 현재 어디까지 구현되었는가?
- 왜 아직 external-only 운영 단계가 아닌가?
- 앞으로 무엇을 external 중심으로 개발해야 하는가?

즉, 이 문서는 단순한 회고 문서가 아니라 VisionNavi의 현재를 설명하는 프로젝트 전체 설명서이기도 하다.

## 2. VisionNavi란 무엇인가

VisionNavi는 사용자의 자연어 명령을 해석하고, 그것을 실행 가능한 자동화 작업으로 바꿔 실제 브라우저나 Windows 데스크톱 환경에서 수행하는 시스템이다.

입력은 텍스트 또는 음성 명령을 전제로 하며, 최종적으로는 다음 두 환경을 다루는 것을 목표로 한다.

- 웹 브라우저 자동화
- Windows 데스크톱 앱 자동화

VisionNavi의 핵심은 단순히 “정해진 명령을 실행하는 도구”가 아니라, 사용자의 목표를 이해하고 현재 화면 상태를 반영하면서 작업을 끝까지 수행하려는 orchestration layer라는 점이다.

장기적으로 VisionNavi가 지향하는 최종 모습은 다음과 같다.

- 상위 레이어는 사용자의 목표를 canonical command로 정리한다.
- 실행 중에는 현재 화면 상태, 브라우저 상태, 데스크톱 상태, trace를 기반으로 다음 행동을 선택한다.
- 필요하다면 BrowserUse / ComputerUse류 오픈소스 agent runtime을 VisionNavi 안에서 통합적으로 운용한다.
- 사용자는 하나의 명령 인터페이스를 쓰고, 내부 실행기와 외부 agent runtime은 VisionNavi가 관리한다.

즉 VisionNavi는 “로컬 브라우저/데스크톱 자동화 도구”이면서 동시에 “agent runtime orchestrator”를 지향하는 프로젝트다.

## 3. 왜 이 프로젝트가 생겼는가

기존의 UI 자동화는 보통 다음 중 하나의 형태를 갖는다.

- 고정된 절차를 미리 정의해 두고 그대로 실행하는 방식
- 상위 planner가 전체 step 계획을 만든 뒤 executor가 그것을 따라가는 방식

이 방식은 명확하고 디버깅이 쉽다는 장점이 있지만, 실제 사용자 환경에서는 여러 한계를 가진다.

대표적인 한계는 다음과 같다.

- 화면 구조가 조금만 달라져도 계획이 쉽게 깨진다.
- 중간에 예상하지 못한 UI branch가 나오면 복구가 어렵다.
- “정답 selector”가 하나로 고정되지 않는 화면에서는 유연성이 부족하다.
- 사용자의 목표가 단순 클릭 순서보다 더 의미 중심적일 때 대응이 어렵다.

사용자가 실제로 기대하는 것은 “이 버튼 다음엔 저 버튼을 누르는 고정 절차”가 아니라, “상황을 보면서 내가 원한 작업을 끝까지 해주는 자동화”에 가깝다.

이 문제의식 때문에 VisionNavi는 단순 executor를 넘어서 agent형 orchestrator 방향으로 발전하게 되었다.

## 4. 개발 역사

VisionNavi의 개발 역사는 크게 네 단계로 나눌 수 있다.

### 4-1. 초기 단계: JSON step 기반 자동화

초기 단계의 자동화는 전형적인 JSON step 기반 구조에 가까웠다.

- 상위 planner 또는 LLM이 작업 시작 시점에 전체 JSON step 계획을 반환한다.
- Python 기반 executor가 그 계획을 순서대로 실행한다.
- 실행기는 step에 적힌 selector, 입력값, 대기 조건을 그대로 수행한다.

이 구조의 장점은 분명했다.

- 행동이 명확하다.
- 디버깅이 쉽다.
- 재현성이 높다.
- 어느 단계에서 실패했는지 확인하기 쉽다.

하지만 한계도 빨리 드러났다.

- 실제 화면 상태가 계획과 조금만 달라져도 취약하다.
- 계획을 처음에 한 번에 만들기 때문에 중간 수정이 어렵다.
- 복구가 필요해지면 결국 처음 계획 전체를 다시 짜야 하는 경우가 많다.
- UI 절차를 너무 많이 upfront로 정의해야 해서 범용성이 낮다.

이 단계는 “정확히 알 수 있는 시나리오를 재현하는 데는 강하지만, 살아 있는 UI를 상대하는 데는 약한 구조”였다.

### 4-2. 개선 시도: Runtime Binding

이 한계를 완화하기 위해 Runtime Binding 방식이 등장했다.

Runtime Binding의 핵심 아이디어는 다음과 같다.

- 상위 레이어는 intent, task_type, slots 같은 중간 수준 정보만 제공한다.
- 로컬 엔진이 실제 실행 흐름을 구성한다.
- binder는 실행 시점의 snapshot을 보고 실제 대상을 고른다.
- 즉, low-level target 선택을 실행 시점으로 미룬다.

이 방식이 도입된 이유는 분명했다.

- 전체 low-level step plan을 미리 고정하지 않기 위해
- 현재 화면 상태를 더 많이 반영하기 위해
- 복구를 상위 planner 재호출 없이 로컬에서 처리하기 위해

Runtime Binding은 JSON step 기반보다 분명히 유연했다.

- 고정 step보다 화면 변화에 더 잘 적응했다.
- 같은 intent여도 실행 시점에 target을 다시 선택할 수 있었다.
- 브라우저나 데스크톱의 live snapshot을 조금 더 활용할 수 있었다.

하지만 이 구조도 실전에서는 한계를 드러냈다.

- target 선택이 heuristic, rule, handcrafted score에 의존했다.
- semantic ambiguity가 있는 화면에서는 단순 score만으로 올바른 선택이 어려웠다.
- 복구가 가능하긴 했지만, 결국 정책 기반 재시도 수준에 머무는 경우가 많았다.
- 상황 해석 자체가 필요한 지점에서는 binder 로직만으로는 부족했다.

즉 Runtime Binding은 “실행 시점 상태를 반영한다”는 점에서 의미 있는 진전이었지만, “상황을 이해하는 agent” 수준은 아니었다.

### 4-3. 방향 전환: Continuous LLM-guided Runtime

Runtime Binding의 한계를 느끼면서 VisionNavi는 한 단계 더 나아간 방향을 고민하게 됐다.

그 방향이 바로 Continuous LLM-guided Runtime이다.

핵심 발상은 단순하다.

- LLM은 처음 명령 해석에만 쓰는 것이 아니다.
- 실행 중에도 계속 현재 상태를 해석하는 데 도움을 줄 수 있어야 한다.
- “처음 한 번 계획을 세우는 모델”이 아니라, “실행 중에도 계속 판단을 돕는 모델”이 필요하다.

이 방향은 다음과 같은 실행 루프를 지향한다.

1. observe
2. decide next action
3. act
4. verify
5. recover
6. repeat

이 구조가 필요한 이유는 다음과 같다.

- 화면은 계속 바뀐다.
- 적절한 target 선택은 현재 의도와 화면 맥락에 따라 달라진다.
- 복구는 고정 정책만으로 충분하지 않은 경우가 많다.
- 어떤 작업은 “local interaction success”와 “task completion”이 다르다.

예를 들어 버튼을 눌렀다는 사실 자체는 성공일 수 있지만, 사용자의 목표가 끝난 것은 아닐 수 있다. 반대로 화면이 살짝 달라져도 의미상 같은 target을 고를 수 있다면 작업은 계속 진행되어야 한다.

이 단계에서 VisionNavi는 단순 executor가 아니라 “LLM이 실행 중에도 관여하는 hybrid runtime”을 목표로 하게 되었다.

### 4-4. 현재 단계: internal / external backend 공존

현재 VisionNavi는 internal 실행기와 external agent runtime을 같은 orchestrator 안에 공존시키는 단계에 와 있다.

현재 구조는 다음 네 backend를 중심으로 한다.

- `internal_browser`
- `external_browser_agent`
- `internal_desktop`
- `external_desktop_agent`

이 구조의 의미는 단순하지 않다.

- internal backend는 현재 baseline, fallback, deterministic execution을 담당한다.
- external backend는 BrowserUse / ComputerUse류 agent runtime 통합의 실험축이자 미래 주 실행축이다.

현재 external 통합 대상으로는 다음 계열이 연결되어 있다.

- browser-use 계열 브라우저 agent
- UI-TARS 계열 데스크톱 agent

즉, VisionNavi는 지금 “내부 baseline을 유지하면서 외부 agent runtime 통합 가능성을 현실적으로 시험하는 단계”에 있다.

## 5. VisionNavi의 현재 구조

현재 VisionNavi의 구조는 크게 frontend, local orchestrator, agent loop, internal executors, external agent adapters, model layer로 나뉜다.

### 5-1. Frontend

프런트엔드는 Flutter 기반 데스크톱 UI로 구성되어 있다.

현재 프런트엔드가 담당하는 주요 기능은 다음과 같다.

- 텍스트 명령 입력
- 세션 상태 표시
- canonical review 표시
- agent trace / event timeline 표시
- trace 복사 / export
- 실행 채널 선택

프런트엔드는 단순한 입력창이 아니라, 현재 agent가 어떤 상태인지 사용자에게 보여주는 디버깅 및 제어 인터페이스 역할도 한다.

### 5-2. Local Orchestrator

로컬 orchestrator는 FastAPI 기반으로 구성되어 있다.

역할은 다음과 같다.

- command intake
- canonicalization
- intent routing
- safety classification
- session lifecycle management
- WebSocket 또는 polling 기반 상태 전달

즉, 사용자의 입력이 실제 실행으로 이어지기 전까지의 모든 intake pipeline을 책임진다.

### 5-3. Agent Loop

Agent Loop는 VisionNavi의 핵심 조정 레이어다.

핵심 루프는 다음 단계로 요약할 수 있다.

- observe
- plan / decide
- act
- verify
- recover

여기서 중요한 점은 internal과 external backend를 고르는 분기점도 Agent Loop에 있다는 것이다. 또한 세션 결과와 trace를 정규화하는 중심 레이어이기도 하다.

### 5-4. Internal Executors

#### Browser executor

internal browser executor는 Playwright 기반이다.

현재 다음 특성을 가진다.

- Playwright first execution
- iterative next-action runtime loop
- deterministic fallback
- map route handling
- runtime trace, decision trace, performance summary 기록

즉, internal browser는 현재 VisionNavi에서 가장 많은 실전 로직이 들어간 실행기다.

#### Desktop executor

internal desktop executor는 deterministic flow 중심이다.

현재 대표 시나리오는 다음과 같다.

- Notepad 열기 및 텍스트 입력
- workspace file inspection
- 일부 시스템 설정 변경

이 경로는 상대적으로 구조화된 데스크톱 작업을 안정적으로 처리하기 위한 baseline 역할을 한다.

### 5-5. External Agent Adapters

#### `external_browser_agent`

이 adapter는 browser-use runtime을 VisionNavi의 adapter contract에 맞게 감싼다.

주요 특징은 다음과 같다.

- browser-use 호출
- CDP attach 기반 크롬 세션 재사용
- raw / normalized trace 반환
- adapter 결과를 VisionNavi 세션 결과로 변환

즉, 외부 브라우저 agent runtime을 VisionNavi 안에서 실험 가능한 backend로 만든 것이다.

#### `external_desktop_agent`

이 adapter는 UI-TARS bridge를 통해 multimodal desktop agent를 실행한다.

주요 특징은 다음과 같다.

- Node bridge를 통한 UI-TARS 호출
- Notepad pre-open 지원
- raw / normalized trace 수집
- 파일 저장 결과 검증 시도

현재는 Notepad 시나리오 중심으로만 연결되어 있다.

### 5-6. Model Layer

VisionNavi는 canonicalization, planning, next action, vision observation 등 여러 단계에서 오픈소스 LLM을 활용한다.

현재 모델 레이어의 특징은 다음과 같다.

- 로컬 Ollama 기반
- Qwen 계열 모델 중심
- planner model, vision model, external agent model이 분리될 수 있음

즉, 한 모델이 모든 역할을 담당하는 구조가 아니라, 용도에 따라 모델을 나눌 수 있는 형태다.

## 6. 핵심 타입과 실행 계약

VisionNavi를 이해하려면 몇 가지 중심 타입과 실행 계약을 이해해야 한다.

### `CanonicalCommand`

`CanonicalCommand`는 사용자 명령을 정규화한 중심 객체다.

이 객체에는 보통 다음 정보가 담긴다.

- `task_domain`
- `intent`
- `risk_level`
- `target_app`
- `notes`

즉, 자유로운 자연어 명령을 실제 실행 가능한 공통 표현으로 바꾸는 기준점이다.

### `ExecutionBackend`

`ExecutionBackend`는 현재 어떤 실행 채널을 사용할지를 나타내는 값이다.

현재 값은 다음 네 가지다.

- `internal_browser`
- `external_browser_agent`
- `internal_desktop`
- `external_desktop_agent`

이 값은 단순 라벨이 아니라, 실제 실행 경로와 trace 해석 기준을 결정한다.

### `AgentAdapterRequest`

`AgentAdapterRequest`는 external runtime에 전달되는 공통 입력 객체다.

핵심 내용은 다음과 같다.

- canonical command
- observation
- policy flags

즉, external runtime이 현재 명령과 관측 상태를 이해할 수 있게 해주는 최소 계약이다.

### `AgentAdapterResponse`

`AgentAdapterResponse`는 external runtime의 결과를 VisionNavi가 받아들이는 표준 형식이다.

보통 다음 필드를 포함한다.

- `status`
- `result`
- `raw_agent_trace`
- `normalized_agent_trace`
- `blocked_reason`

즉, external runtime의 자유로운 출력을 VisionNavi 세션 계약으로 끌어오는 역할을 한다.

### Session result

현재 세션 결과에는 backend와 trace 관련 정보가 포함된다.

주요 필드는 다음과 같다.

- `execution_backend`
- `raw_agent_trace`
- `normalized_agent_trace`
- `execution_summary`

특히 `execution_summary`는 backend, success, duration, step count, failure reason을 공통 형식으로 정리하기 위한 요약 정보다.

### Internal browser runtime trace

internal browser runtime은 보다 세밀한 trace를 남긴다.

대표 필드는 다음과 같다.

- `runtime_trace`
- `decision_trace`
- `performance_summary`

이 덕분에 내부 browser loop에서는 “무슨 action이 실행되었는가”뿐 아니라 “왜 fallback이 개입했는가”, “어떤 성능 비용이 들었는가”까지 추적 가능하다.

## 7. 현재 구현 상태

현재 구현 상태를 영역별로 정리하면 다음과 같다.

| 영역 | 상태 | 설명 |
|---|---|---|
| canonicalization / intent routing | 완료 | LLM 보조 + rule fallback 구조 존재 |
| search_and_read internal | 완료 | Playwright 기반 baseline 존재 |
| search_and_read external | 제한적 지원 | browser-use 연결 완료, 품질 및 grounding 불안정 |
| open_notepad_and_type internal | 완료 | deterministic executor 존재 |
| open_notepad_and_type external | 제한적 지원 | UI-TARS bridge 연결 완료, 저장 검증 안정화 미완 |
| find_map_route internal | 진행중 | provider 분기, parsing, verify/retry 강화 중 |
| find_map_route external | 미구현 | 아직 external browser agent 대상 아님 |
| trace / export | 완료 | 세션 trace, raw/normalized trace, export 지원 |
| frontend 채널 선택 | 완료 | auto/internal/external 선택과 backend 표시 지원 |
| backend 비교 실험 구조 | 진행중 | 공통 execution summary는 있으나 benchmark 체계는 미완 |

이 표에서 중요한 점은 “external integration이 존재한다”와 “external이 production-grade다”는 다른 말이라는 점이다. 현재 external backend는 연결은 되어 있지만, 아직 제한적 지원 상태다.

## 8. 현재 상황 상세 분석

### 8-1. External browser

현재 external browser는 실제 browser-use runtime이 연결되어 있다.

장점은 분명하다.

- 실제 browser-use step trace를 남길 수 있다.
- CDP attach 기반으로 로컬 크롬 세션과 연결할 수 있다.
- VisionNavi의 backend 실험축으로 실제 사용 가능하다.

그러나 현재 문제도 명확하다.

- 모델이 의도와 무관한 방향으로 흐를 수 있다.
- 검색어나 요약이 hallucination될 수 있다.
- step trace는 남아도 사용자 목표에 충실하지 않을 수 있다.
- 즉, 실행은 했지만 grounding 품질이 약한 경우가 존재한다.

현재 external browser는 “기술적 연결은 됐지만, task fidelity는 아직 불안정한 상태”라고 표현하는 것이 정확하다.

### 8-2. External desktop

external desktop은 UI-TARS bridge 자체는 연결되어 있다.

현재 가능한 것:

- instruction 전달
- screenshot 관측 이벤트 수집
- trace 기록
- 파일 저장 결과 검증 시도

그러나 현재 문제는 다음과 같다.

- 실제 입력/저장 완료율이 낮다.
- timeout과 task completion failure가 남아 있다.
- usable backend라고 부르기에는 아직 PoC 성격이 강하다.

즉, bridge plumbing은 됐지만 과업 완수율이 아직 부족하다.

### 8-3. Internal map route

길찾기 시나리오는 현재 internal baseline 중심이다.

현재 특징은 다음과 같다.

- iterative runtime loop가 존재한다.
- deterministic fallback이 존재한다.
- provider 분기, origin/destination parsing, route kind handling이 들어 있다.
- `llm_returned_no_step` 상황에서는 fallback이 자주 개입한다.

이는 곧, 현재 map route는 “완전 agent autonomy”보다는 “LLM 보조 + 시나리오 종속 실행기”에 가깝다는 뜻이다.

즉 VisionNavi가 지향하는 최종 방향과 완전히 같지는 않지만, 현재 가장 실용적인 baseline 역할을 한다.

### 8-4. Trace와 관측성

과거와 비교하면 현재 trace는 훨씬 좋아졌다.

현재는 다음을 남길 수 있다.

- 실패 원인
- backend 정보
- raw trace
- normalized trace
- runtime trace
- decision trace
- performance summary

그러나 benchmark 관점의 자동 집계는 아직 부족하다.

- 어떤 backend가 더 낫다고 결론 내릴 수 있는 자동 비교 체계는 미완이다.
- trace는 많아졌지만, 그것이 곧바로 성능 데이터셋이 되는 단계는 아니다.

즉, 디버깅 관측성은 많이 개선되었지만, 제품 판단용 계량 체계는 아직 발전 중이다.

## 9. 지금까지의 주요 구현 포인트

현재까지 VisionNavi에서 의미 있게 들어간 구현 포인트를 정리하면 다음과 같다.

- canonical command pipeline 구축
- session timeline / event streaming 구축
- browser / desktop executor 분리
- iterative browser runtime loop 도입
- map provider parsing과 route slot parsing 강화
- `execution_backend` 개념 도입
- external browser agent adapter 연결
- external desktop agent adapter 연결
- trace export와 frontend viewer 강화
- backend별 공통 `execution_summary` 정규화

이 목록은 VisionNavi가 단순 MVP 단계를 넘어, 실험 가능한 runtime orchestration 플랫폼으로 가는 중이라는 것을 보여준다.

## 10. 전략적 판단

현재 VisionNavi가 가장 많이 고민하는 문제는 “internal만 갈 것인가, external만 갈 것인가, 둘 다 계속 개발할 것인가”다.

### 10-1. internal-only의 의미

internal-only는 단기 안정성 측면에서는 가장 유리하다.

- 지금 당장 되는 기능이 많다.
- 현재 디버깅 맥락이 익숙하다.
- route 같은 시나리오도 이미 어느 정도 맞춰져 있다.

하지만 치명적인 문제가 있다.

- 결국 우리가 BrowserUse / ComputerUse를 다시 직접 구현하는 셈이 된다.
- 장기 목표와 어긋난다.
- 범용성 확대 비용이 계속 커진다.

즉 internal-only는 단기적으로 편할 수 있지만 전략적으로는 비효율적이다.

### 10-2. external-only의 의미

external-only는 최종 방향과 가장 잘 맞는다.

- 이미 구현된 외부 runtime을 도입한다.
- 개발의 중심축을 agent runtime integration에 집중할 수 있다.
- 장기적으로 범용성과 확장성이 높다.

그러나 현재 코드 현실상 즉시 external-only로 가기 어려운 이유도 명확하다.

- `find_map_route`는 아직 external browser agent 대상이 아니다.
- external desktop은 completion 안정성이 부족하다.
- external browser는 grounding 품질이 아직 흔들린다.

즉 external-only는 방향으로는 맞지만, 지금 당장 운영 축으로 완전 단일화하기에는 이르다.

### 10-3. 양쪽 모두 동등 개발의 문제

internal과 external을 동등한 비중으로 계속 개발하는 전략은 겉보기엔 안전해 보인다.

하지만 실제로는 가장 비효율적이다.

- 집중도가 분산된다.
- 개발비용이 증가한다.
- 일정 예측이 더 어려워진다.
- 전략적 방향이 흐려진다.

결국 internal도 키우고 external도 키우면, 어느 쪽도 충분히 빨리 성숙하지 못할 가능성이 높다.

### 10-4. 현재 추천 방향

현재 가장 현실적인 전략은 다음과 같다.

- 개발 방향은 `external-first`
- internal은 신규 기능 주 개발축이 아니라 fallback / baseline / 비교 대상 용도로 유지

즉 구체적으로는 다음을 의미한다.

- 적극적인 기능 확장과 실험은 external에 집중
- internal은 fallback 유지와 route 임시 보존에 한정
- “양쪽 모두 적극 개발”은 지양

이 전략은 단기 일정과 장기 목표를 동시에 고려했을 때 가장 타당하다.

## 11. 왜 아직 external-only 운영으로 바로 못 가는가

이 부분은 프로젝트 판단에서 가장 중요하다.

현재 external-only 운영이 어려운 이유는 다음과 같다.

- `external_browser_agent`는 현재 `search_and_read` 중심이다.
- `external_desktop_agent`는 현재 `open_notepad_and_type` 중심이다.
- `find_map_route`는 아직 external runtime으로 이관되지 않았다.
- external desktop은 저장 검증 통과율이 안정적이지 않다.
- external browser는 task grounding이 아직 흔들린다.

따라서 현재 시점의 가장 정직한 표현은 다음과 같다.

- external integration은 “도입 완료”가 아니다.
- external integration은 “실동작 PoC 연결 완료” 상태다.

이 표현이 중요한 이유는, 기술적으로 연결했다고 해서 곧바로 주 실행축으로 쓸 수 있는 것은 아니기 때문이다.

## 12. 단기 목표

현재 VisionNavi의 단기 목표는 다음과 같다.

- external browser `search_and_read`를 반복 검증 가능한 수준으로 안정화
- external desktop `open_notepad_and_type`를 저장 검증까지 통과시키기
- backend별 success / duration / step count / failure reason 공통 집계
- internal route baseline trace 강화
- frontend에서 requested / effective backend를 더 명확히 보여주기

즉 단기 목표는 “더 많은 기능을 붙이는 것”보다 “이미 붙인 external backend를 실험 가능한 수준으로 안정화하는 것”에 가깝다.

## 13. 중기 목표

중기 목표는 다음과 같다.

- external browser 안정화 후 route task로 확장 가능성 평가
- external desktop 성공 후 third-party desktop app으로 범위 확대
- internal fallback이 실제로 얼마나 필요한지 benchmark로 판단
- 장기적으로 internal 의존 축소 여부 결정

즉 중기 단계에서야 비로소 “internal을 얼마나 줄일 수 있는가”를 데이터로 판단할 수 있게 된다.

## 14. 의사결정 기준

앞으로 internal과 external 중 어느 쪽을 더 밀어야 하는지, 또는 internal fallback을 언제 줄일 수 있는지를 판단하려면 기준이 필요하다.

현재 VisionNavi가 봐야 할 핵심 기준은 다음과 같다.

- 동일 명령 반복 성공률
- 평균 수행 시간
- 실패 시 복구 가능성
- trace 해석 가능성
- local model resource usage
- unsupported intent 비율
- fallback 개입 빈도

이 기준들이 충분히 축적되어야만 “external-only 운영으로 갈 수 있는가” 같은 결정을 신뢰성 있게 내릴 수 있다.

## 15. 현재 결론

현재 시점의 공식적인 프로젝트 판단은 다음과 같이 정리할 수 있다.

- VisionNavi는 단순 JSON step executor에서 agent형 runtime으로 진화 중이다.
- 현재는 internal / external 공존 단계다.
- 최종 방향은 external agent runtime 중심이다.
- 그러나 지금 당장은 external-only 운영 단계가 아니다.

따라서 현재 가장 타당한 전략은 다음과 같다.

- **external-first development**
- **internal fallback retention**
- **route baseline temporary internal ownership**

즉, VisionNavi는 지금 “외부 agent runtime으로 완전히 넘어가기 직전의 과도기”에 있으며, 이 과도기를 짧고 명확하게 통과하는 것이 앞으로의 핵심 과제다.

