# VisionNavi 프로젝트 안내서

> 이 문서는 중간발표용 요약본이 아니라, VisionNavi의 현재 구조와 동작 방식, 한계, 사용 기술을 이해하기 위한 기술/Q&A 기준 문서입니다.
>
> 발표용 정리본은 별도 문서인 [visionnavi-midterm-presentation.md](/C:/Users/USER/Documents/VisionNavi/docs/visionnavi-midterm-presentation.md) 와 [visionnavi-midterm-slides.md](/C:/Users/USER/Documents/VisionNavi/docs/visionnavi-midterm-slides.md) 를 사용합니다.

## 1. 이 문서는 무엇을 위한 문서인가

이 문서는 VisionNavi를 처음 접한 사람이 현재 프로젝트를 빠르게 이해할 수 있도록 만든 통합 안내서입니다.

이 문서만 읽어도 다음 내용을 이해할 수 있도록 작성했습니다.

- VisionNavi가 어떤 프로젝트인지
- 현재 어떤 구조로 동작하는지
- 어떤 라이브러리와 런타임을 쓰는지
- 지금 연결된 LLM, VLM, STT, wakeword가 무엇인지
- 현재 지원하는 intent가 몇 개이고 각각 어떻게 실행되는지
- 어디까지가 하드코딩이고, 어디서부터 LLM이 실제로 선택하는지
- VLM이 실제로 얼마나 영향력이 있는지
- 현재 안정적인 부분과 아직 실험적인 부분이 무엇인지

이 문서는 제품 소개 문서이면서 동시에 개발자용 현재 상태 문서입니다.

---

## 2. VisionNavi란 무엇인가

VisionNavi는 사용자의 음성 또는 텍스트 자연어 명령을 받아서, 실제 웹 브라우저나 Windows 데스크톱에서 작업을 대신 수행하는 로컬 에이전트형 자동화 시스템입니다.

간단히 말하면 다음과 같은 흐름을 목표로 합니다.

1. 사용자가 말하거나 입력합니다.
2. 시스템이 그 문장을 이해해서 `canonical command`로 정리합니다.
3. 그 명령을 웹 작업인지, 데스크톱 작업인지 판단합니다.
4. 적절한 실행기나 외부 agent runtime을 선택합니다.
5. 실제 브라우저 또는 Windows 앱을 조작합니다.
6. 결과를 확인하고, 사용자에게 상태나 결과를 알려줍니다.

이 프로젝트의 핵심은 단순한 "매크로 실행기"가 아니라, 사용자 목표를 이해하고 실제 환경을 보며 끝까지 수행하려는 `orchestrator`라는 점입니다.

---

## 3. 프로젝트가 만들어진 배경

VisionNavi는 원래의 고정 step 기반 자동화가 가진 한계를 넘기 위해 발전해 왔습니다.

초기 자동화는 보통 이런 방식입니다.

- 먼저 전체 계획을 JSON step으로 만듭니다.
- 그다음 Python executor가 그 순서를 그대로 실행합니다.

이 방식은 디버깅은 쉽지만, 실제 화면이 조금만 달라져도 잘 깨집니다.

예를 들어:

- 버튼 위치가 바뀜
- 자동완성 후보가 다르게 뜸
- 사이트 구조가 변경됨
- 로그인 여부나 팝업 때문에 중간 상태가 달라짐

이런 상황에서는 "처음에 만든 계획"이 실제 화면과 맞지 않게 됩니다.

그래서 VisionNavi는 다음 방향으로 발전했습니다.

- 처음부터 모든 step을 완전히 고정하지 않는다
- 실행 시점의 화면 상태를 더 많이 반영한다
- 필요하면 실행 중에도 다음 행동을 다시 판단한다
- 최종적으로는 BrowserUse / ComputerUse류 오픈소스 agent runtime과 결합한다

즉, VisionNavi의 본질적인 목표는 "정해진 step 재생"이 아니라 "상황을 보며 목표를 끝까지 수행하는 자동화"입니다.

---

## 4. 현재 프로젝트의 큰 구조

현재 VisionNavi는 크게 4개 층으로 볼 수 있습니다.

1. Flutter 프론트엔드
2. FastAPI 오케스트레이터
3. internal 실행기
4. external agent runtime adapter

### 4-1. Flutter 프론트엔드

경로:

- [frontend/lib/main.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/main.dart)
- [frontend/lib/app/vision_navi_app.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/app/vision_navi_app.dart)
- [frontend/lib/features/home/presentation/home_screen.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)

역할:

- 사용자 입력 UI
- 음성/텍스트 입력 흐름 관리
- 세션 상태 표시
- 사용자 모드 / 디버그 정보 표시
- 설정 UI
- wakeword / STT 상태 표시
- 실행 결과 팝업 표시

현재 UI는 고령자 친화형 메인 화면으로 개편 중이며, 개발자용 trace도 함께 제공하는 형태입니다.

### 4-2. FastAPI 오케스트레이터

경로:

- [orchestrator/app/api/routes/pipeline.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)

역할:

- 명령 intake
- canonicalization
- intent routing
- risk / confirmation 판단
- backend 선택
- 세션 생성 및 이벤트 관리
- external/internal 실행기 호출

이 레이어가 VisionNavi의 중심입니다.

### 4-3. internal 실행기

경로:

- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/automation/desktop/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)

역할:

- Playwright 기반 브라우저 자동화
- pywinauto 기반 데스크톱 자동화
- deterministic fallback
- 일부 LLM action plan 실행

### 4-4. external agent adapter

경로:

- [orchestrator/app/automation/browser/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)
- [orchestrator/app/automation/desktop/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)

역할:

- external browser agent를 VisionNavi 형식으로 감싸기
- external desktop agent를 VisionNavi 형식으로 감싸기
- raw trace와 normalized trace 남기기
- 실패 시 internal fallback과 연결하기

현재 개발 방향은 명확히 `external-first`입니다.

즉:

- 새 기능의 중심은 external
- internal은 fallback과 baseline
- route 같은 일부 시나리오는 당분간 internal 유지

---

## 5. 현재 사용 중인 핵심 라이브러리와 런타임

### 5-1. 프론트엔드

경로:

- [frontend/pubspec.yaml](/C:/Users/USER/Documents/VisionNavi/frontend/pubspec.yaml)

주요 라이브러리:

- `flutter`
- `http`
- `file_selector`
- `record`
- `speech_to_text`
- `window_manager`
- `Pretendard` 폰트 자산

의미:

- `record`: 로컬 녹음
- `speech_to_text`: Windows 음성 인식 연동 시도
- `file_selector`: 음성 파일 첨부
- `window_manager`: 데스크톱 창 크기/고정 제어

### 5-2. 오케스트레이터 백엔드

경로:

- [orchestrator/requirements.txt](/C:/Users/USER/Documents/VisionNavi/orchestrator/requirements.txt)

주요 라이브러리:

- `fastapi`
- `uvicorn`
- `pydantic`
- `httpx`
- `playwright`
- `pywinauto`
- `pywin32`
- `browser-use[core]`
- `faster-whisper`
- `livekit-wakeword[listener]`

의미:

- `playwright`: internal 브라우저 실행기
- `pywinauto`: internal 데스크톱 실행기
- `browser-use`: external browser agent
- `faster-whisper`: 로컬 STT
- `livekit-wakeword`: wakeword 감지

### 5-3. external desktop bridge

경로:

- [runtime/external_agents/ui_tars_bridge/package.json](/C:/Users/USER/Documents/VisionNavi/runtime/external_agents/ui_tars_bridge/package.json)
- [runtime/external_agents/ui_tars_bridge/run_ui_tars.js](/C:/Users/USER/Documents/VisionNavi/runtime/external_agents/ui_tars_bridge/run_ui_tars.js)

주요 Node 의존성:

- `@ui-tars/sdk`
- `@ui-tars/operator-nut-js`
- `uuid`

즉 external desktop 쪽은 Python에서 직접 multimodal agent를 구현한 것이 아니라, Node bridge를 통해 UI-TARS 계열 런타임을 호출하는 구조입니다.

### 5-4. 로컬 LLM / VLM 런타임

경로:

- [orchestrator/app/core/settings.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/core/settings.py)

현재 기본 설정:

- `OLLAMA_MODEL = qwen2.5:14b`
- `OLLAMA_PLANNER_MODEL = qwen2.5:7b`
- `OLLAMA_VISION_MODEL = qwen2.5vl:3b`

즉 현재 기본 구조는:

- canonicalization / popup summary: `qwen2.5:14b`
- planner / next action: `qwen2.5:7b`
- vision / desktop external model: `qwen2.5vl:3b`

---

## 6. 현재 지원하는 intent는 몇 개인가

현재 코드 기준으로 실질 intent는 6개입니다.

경로:

- [orchestrator/app/services/intent_router.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/intent_router.py)
- [orchestrator/app/api/routes/pipeline.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)

현재 intent 목록:

1. `search_and_read`
2. `find_map_route`
3. `open_notepad_and_type`
4. `inspect_workspace_files`
5. `change_system_setting`
6. `general_assistance`

### 6-1. `search_and_read`

의미:

- 검색 엔진이나 사이트에서 검색하고
- 결과를 읽거나 요약하는 작업

예:

- "네이버에서 청년 월세 지원 정보 찾아줘"
- "구글에서 유튜브 검색해줘"

### 6-2. `find_map_route`

의미:

- 지도 서비스에서 출발지/도착지/교통수단 기반으로 길찾기 수행

예:

- "네이버 지도에서 서울역에서 송내역 가는 길 찾아줘"
- "카카오맵에서 버스 경로 찾아줘"

### 6-3. `open_notepad_and_type`

의미:

- 메모장을 열고
- 텍스트를 입력하고
- 저장하는 작업

### 6-4. `inspect_workspace_files`

의미:

- 파일 탐색기나 안전한 workspace 안에서 파일/폴더를 확인하는 작업

### 6-5. `change_system_setting`

의미:

- 현재는 주로 다크 모드 같은 시스템 설정 변경

### 6-6. `general_assistance`

의미:

- 위 규칙들로 명확히 떨어지지 않는 명령
- 사실상 fallback intent

이 intent는 아직 범용 agent처럼 완성된 intent가 아니라, "아직 무엇을 해야 할지 구조적으로 정리되지 않은 요청"에 가까운 성격입니다.

---

## 7. intent는 어떻게 정해지는가

여기가 VisionNavi에서 매우 중요한 부분입니다.

현재 intent 결정은 `완전 LLM 전용`도 아니고, `완전 규칙 기반`도 아닙니다.

정확히는 다음 구조입니다.

1. 먼저 LLM canonicalization을 시도
2. 실패하면 rule-based router로 fallback
3. 마지막으로 harmonization rule로 보정

경로:

- [orchestrator/app/api/routes/pipeline.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
- [orchestrator/app/services/model_client.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
- [orchestrator/app/services/intent_router.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/intent_router.py)

### 7-1. 1단계: LLM canonicalization

먼저 `qwen2.5:14b` 기반 canonicalization을 시도합니다.

LLM은 다음 값을 돌려줍니다.

- `normalized_text`
- `task_domain`
- `intent`
- `target_app`
- `notes`

즉 첫 해석 자체는 LLM이 꽤 많이 관여합니다.

### 7-2. 2단계: rule-based fallback

LLM이 실패하면 `IntentRouter.route()`가 키워드 규칙으로 intent를 정합니다.

예:

- `map`, `길찾기`, `경로` → `find_map_route`
- `google`, `naver`, `youtube`, `검색` → `search_and_read`
- `folder`, `file`, `드라이브`, `탐색기` → `inspect_workspace_files`
- `notepad`, `메모장` → `open_notepad_and_type`

즉 LLM이 죽거나 흔들려도 최소한의 분류는 rule로 유지됩니다.

### 7-3. 3단계: harmonization rule

분류 후에도 다시 보정합니다.

예:

- `search_and_read`는 무조건 `task_domain=web`, `target_app=browser`
- `find_map_route`는 무조건 `task_domain=web`, `target_app=naver_map 또는 kakao_map`
- `open_notepad_and_type`는 `desktop/notepad`

또한 `general_assistance`여도 신호가 명확하면 다시 `find_map_route`, `search_and_read`, `inspect_workspace_files`로 바뀔 수 있습니다.

### 7-4. 결론

현재 intent 분류는 다음처럼 보는 것이 가장 정확합니다.

- "LLM first"
- "rule fallback"
- "final safety harmonization"

즉 초해석은 LLM이 하지만, 최종 라우팅은 꽤 강한 규칙 보정이 들어갑니다.

---

## 8. 현재 동작 흐름 전체

실제 실행 흐름은 대략 다음과 같습니다.

### 8-1. 사용자 입력

입력 방식:

- 텍스트 직접 입력
- 음성 파일 첨부 후 STT
- 실시간 음성 입력
- wakeword 감지 후 음성 입력

### 8-2. canonical command 생성

생성되는 중심 객체:

- [orchestrator/app/models/canonical_command.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/canonical_command.py)

필드:

- `input_mode`
- `raw_text`
- `normalized_text`
- `task_domain`
- `intent`
- `risk_level`
- `requires_confirmation`
- `target_app`
- `notes`

이 객체가 VisionNavi 내부의 기준 명령입니다.

### 8-3. AgentLoop 계획

경로:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)

이 단계에서:

- 세션 시작
- phase 이벤트 생성
- observation
- planning
- execution
- verification

이 순서로 진행됩니다.

### 8-4. backend 선택

현재 backend 타입:

- `internal_browser`
- `external_browser_agent`
- `internal_desktop`
- `external_desktop_agent`

기본값은 external-first입니다.

하지만 intent가 external에서 아직 지원되지 않으면 internal로 내려갑니다.

예:

- `external_browser_agent`는 현재 사실상 `search_and_read`만 안정적으로 연결
- `external_desktop_agent`는 현재 사실상 `open_notepad_and_type`만 지원
- `find_map_route`는 지금도 internal 소유

### 8-5. 실행 후 결과 정리

결과에는 다음 정보가 붙습니다.

- `execution_backend`
- `requested_backend`
- `fallback_backend`
- `failure_reason`
- `raw_agent_trace`
- `normalized_agent_trace`
- `execution_summary`

즉 "무엇이 실행됐는지"뿐 아니라 "어느 경로로 실행됐는지"를 남기는 구조입니다.

---

## 9. intent별 현재 실제 동작 방식

여기서부터가 가장 중요합니다.

아래는 각 intent가 "실제로 얼마나 LLM 주도인지"를 설명한 부분입니다.

## 9-1. `search_and_read`

### 요약

현재 `search_and_read`는 VisionNavi에서 가장 external 중심에 가까운 시나리오입니다.

### 실행 경로

- 기본값: `external_browser_agent`
- fallback: `internal_browser`

### external에서의 실제 동작

경로:

- [orchestrator/app/automation/browser/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)

구조:

1. VisionNavi가 검색 대상과 쿼리를 추출
2. browser-use에 작업 지시문을 만듦
3. 기존 Chrome 디버그 세션에 CDP attach
4. browser-use가 step을 스스로 선택하며 실행
5. VisionNavi가 결과 요약과 방문 URL을 검증
6. off-target면 실패로 분류

즉 이 시나리오는 실제 행동 선택을 external browser agent가 주도합니다.

하지만 완전 무제한은 아닙니다.

VisionNavi가 다음을 하드하게 감쌉니다.

- 시작 URL 강제
- 요청한 검색 엔진/사이트 유지 요구
- 불필요한 기사 진입 금지 규칙
- 결과 요약 validation
- off-target taxonomy 분류

### internal에서의 실제 동작

internal browser는 두 가지 성격이 섞여 있습니다.

1. `action plan` 기반
2. `iterative-next-action` 기반

하지만 현재 설정상 `iterative_browser_loop_enabled`는 기본 `false`입니다.

즉 일반적으로는:

- LLM action plan을 시도
- 없으면 deterministic fallback plan 사용

fallback plan 예:

- `search_web`
- `verify_page_loaded`
- `extract_top_result`
- 경우에 따라 `click_search_result`
- `summarize_page` 또는 `read_page_summary`

### 결론

`search_and_read`는 현재 이렇게 이해하면 됩니다.

- external 경로: 실제 agent성이 가장 강함
- internal 경로: LLM 보조 + deterministic 보정

즉 완전히 하드코딩도 아니고, 완전히 자유 agent도 아닙니다.

현재 제품 방향상 주력은 external입니다.

---

## 9-2. `find_map_route`

### 요약

현재 `find_map_route`는 아직 external-first가 아닙니다.

이 intent는 지금도 실질적으로 internal deterministic baseline 중심입니다.

### 실행 경로

- 기본 실동작: `internal_browser`
- external browser agent로는 아직 정식 이관되지 않음

### 실제 동작

경로:

- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/services/map_route_parser.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/map_route_parser.py)

특징:

1. 먼저 `map_route_parser`가 출발지/도착지/교통수단/provider를 파싱
2. provider가 네이버지도인지 카카오맵인지 분기
3. 해당 지도 서비스용 deterministic step을 구성
4. 실행 중 일부 관찰과 next-action 판단을 할 수 있음
5. 하지만 핵심 골격은 시나리오 종속형 로직

즉 이 intent는 현재 상당 부분 하드코딩입니다.

특히 다음은 구조적으로 코드 중심입니다.

- 지도 서비스 분기
- 출발지/도착지 정규화
- route step 시퀀스
- verify / retry 규칙

### LLM은 어느 정도 개입하는가

개입은 있습니다.

예:

- canonicalization
- planner trace
- iterative loop에서 next-action 시도

하지만 현재 route 시나리오의 실질 성공 여부는 대부분 deterministic executor 품질에 좌우됩니다.

즉 이 시나리오를 "LLM이 자율적으로 지도 서비스를 다루는 구조"라고 보기는 어렵습니다.

### 결론

`find_map_route`는 현재 VisionNavi에서 가장 대표적인 `LLM 보조 + 하드코딩 중심` 시나리오입니다.

---

## 9-3. `open_notepad_and_type`

### 요약

현재 `open_notepad_and_type`는 external desktop agent의 대표 PoC 시나리오입니다.

### 실행 경로

- 기본값: `external_desktop_agent`
- fallback: `internal_desktop`

### external에서의 실제 동작

경로:

- [orchestrator/app/automation/desktop/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)
- [runtime/external_agents/ui_tars_bridge/run_ui_tars.js](/C:/Users/USER/Documents/VisionNavi/runtime/external_agents/ui_tars_bridge/run_ui_tars.js)

구조:

1. VisionNavi가 명령에서 메모장에 적을 텍스트 추출
2. 저장할 txt 파일 path를 준비
3. 필요시 메모장을 미리 열어둠
4. UI-TARS bridge에 "메모장에 정확히 이 텍스트를 쓰고 저장하라"는 지시 전달
5. UI-TARS가 실제 화면을 보고 입력/저장 수행
6. VisionNavi가 저장된 파일 내용을 다시 읽어 검증

즉 여기서는 실제 클릭/입력 순서를 external desktop agent가 선택합니다.

하지만 주변은 하드코딩입니다.

- 파일 경로 준비
- 메모장 pre-open
- instruction framing
- 저장 결과 검증
- retry 정책

### internal에서의 실제 동작

internal desktop는 다음처럼 훨씬 고정적입니다.

- `open_app`
- `focus_window`
- `type_text`
- `save_file`
- `verify_file_contains_text`

즉 internal 데스크톱은 거의 명시적 step 실행기입니다.

### 결론

`open_notepad_and_type`는 현재 external agent를 실제로 가장 잘 시험하고 있는 데스크톱 시나리오입니다.

다만 여전히 "과업 framing과 검증은 VisionNavi", "세부 행동 선택은 external agent"라는 구조입니다.

---

## 9-4. `inspect_workspace_files`

### 요약

현재는 mostly internal 시나리오입니다.

### 실제 동작

경로:

- [orchestrator/app/automation/desktop/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)

기본 흐름:

- `open_explorer`
- `list_directory`

즉 이 intent는 아직 agent형이라기보다 안전한 workspace 내 파일 확인 도구에 가깝습니다.

LLM이 아주 강하게 개입하는 구조는 아닙니다.

---

## 9-5. `change_system_setting`

현재는 사실상 다크 모드 같은 일부 설정 작업 중심입니다.

이 intent도 아직 deterministic 성격이 강합니다.

즉 범용 "Windows 설정 agent" 수준은 아닙니다.

---

## 9-6. `general_assistance`

이 intent는 현재 "무엇을 해야 할지 정확히 구조화되지 않은 요청"을 담는 fallback에 가깝습니다.

아직 이 intent가 범용 agent로 잘 풀리는 상태는 아닙니다.

그래서 실제 제품 관점에서는 `general_assistance`가 많아질수록 아직 미완성 영역이라고 보는 편이 맞습니다.

---

## 10. 현재 어디까지가 하드코딩인가

이 질문은 매우 중요합니다.

VisionNavi는 지금 "완전 agent 시스템"도 아니고, "완전 규칙 기반 자동화"도 아닙니다.

현재를 정확히 표현하면 다음과 같습니다.

### 10-1. 하드코딩이 강한 부분

- intent harmonization
- map provider 분기
- route slot parsing
- internal desktop action sequence
- internal browser fallback steps
- external runtime을 감싸는 검증 규칙
- failure taxonomy
- retry 조건

### 10-2. LLM이 실제로 선택하는 부분

- canonical command 초해석
- action plan 생성
- iterative next action 선택
- external browser agent의 실제 브라우저 조작
- external desktop agent의 실제 UI 조작
- popup summary 문장 생성

### 10-3. 지금 상태를 한 줄로 정리하면

현재 VisionNavi는:

- "입력 해석"은 LLM 비중이 큼
- "search_and_read external"은 agent성이 큼
- "open_notepad_and_type external"은 부분 agent형
- "find_map_route"는 아직 deterministic 비중이 큼

즉 프로젝트 전체가 모두 같은 수준의 agent autonomy를 가지는 것은 아닙니다.

---

## 11. VLM은 현재 얼마나 중요한가

결론부터 말하면, 현재 VLM의 영향력은 `부분적`이고, 전체 시스템을 좌우할 정도로 크지는 않습니다.

### 11-1. 설정상 현재 상태

경로:

- [orchestrator/app/core/settings.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/core/settings.py)

중요 설정:

- `ollama_vision_model = qwen2.5vl:3b`
- `ollama_vision_enabled = false`
- `external_browser_agent_use_vision = false`
- `external_desktop_agent_model = qwen2.5vl:3b`

### 11-2. browser 쪽 VLM 영향

browser 쪽은 현재 기본적으로 vision이 강하게 켜져 있지 않습니다.

특히 external browser agent는:

- `browser-use`
- `external_browser_agent_use_vision = false`

기본값이라서, 현재 browser external은 텍스트 기반 browser-use 실행이 중심입니다.

internal browser 쪽 vision은 route 시나리오에서만 제한적으로 들어가고, 그것도 `ollama_vision_enabled`가 꺼져 있으면 사실상 동작하지 않습니다.

즉 현재 browser VLM 영향은 낮습니다.

### 11-3. desktop 쪽 VLM 영향

desktop external은 다릅니다.

- external desktop model 자체가 `qwen2.5vl:3b`
- UI-TARS가 화면을 보고 행동하는 구조

즉 external desktop agent에서는 VLM이 실제 행동 선택에 꽤 중요합니다.

### 11-4. 정리

현재 VLM 영향도를 현실적으로 정리하면:

- 브라우저 전체 시스템 관점: 낮음 또는 제한적
- 데스크톱 external agent 관점: 중간 이상
- route internal baseline 관점: 실험적, 아직 제한적

즉 "VisionNavi 전체가 VLM 중심으로 돌아간다"고 보기는 어렵고, "일부 시나리오에서 VLM이 개입한다"가 더 정확합니다.

---

## 12. STT와 wakeword는 어떻게 구성되어 있는가

## 12-1. STT

경로:

- [orchestrator/app/services/audio_transcription_service.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/audio_transcription_service.py)

현재 백엔드 STT:

- `faster-whisper`
- 기본 모델: `medium`
- `beam_size = 8`
- `vad_filter = true`

특징:

- 로컬 음성 파일 전사 가능
- 한국어/일본어 힌트 처리 가능
- GPU 오류 시 CPU fallback

즉 STT는 OpenAI API 같은 외부 전사 서비스가 아니라 로컬 전사 기반입니다.

## 12-2. wakeword

경로:

- [orchestrator/app/services/wakeword_service.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/wakeword_service.py)
- [runtime/wakewords/manifest.json](/C:/Users/USER/Documents/VisionNavi/runtime/wakewords/manifest.json)

현재 backend:

- `livekit-wakeword`

현재 구조:

- manifest에 등록된 wakeword model을 로드
- 선택된 언어와 profile 기준으로 listener 실행
- threshold와 debounce 적용
- 감지되면 pending detection 상태 설정

현재 프로젝트에 등록된 호출어는 한국어/일본어 프로필 기반으로 관리됩니다.

다만 일본어 wakeword는 아직 학습 안정화와 운영 적용이 진행 중인 상태입니다.

---

## 13. backend 정책은 어떻게 되어 있는가

현재 backend 정책은 `external-first`입니다.

경로:

- [orchestrator/app/core/settings.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/core/settings.py)
- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)

현재 기본값:

- browser 기본: `external_browser_agent`
- desktop 기본: `external_desktop_agent`

하지만 이 말이 "모든 작업이 external에서 바로 해결된다"는 뜻은 아닙니다.

실제 정책은 다음과 같습니다.

- external에서 지원하는 intent면 external 우선
- external에서 아직 지원하지 않는 intent면 internal로 downgrade
- external 실패 시 설정상 internal fallback 가능

즉 개발 방향은 external-first이지만, 운영 안정망은 internal fallback입니다.

---

## 14. 지금 상태에서 external은 어디까지 실제로 동작하는가

### 14-1. external browser

현재 상태:

- 연결 완료
- browser-use 실제 호출
- CDP attach로 실제 Chrome 세션 사용
- search_and_read 시나리오에서 반복 테스트 가능

하지만 남은 문제:

- 요청과 무관한 페이지로 흐를 수 있음
- 요약 품질이 흔들릴 수 있음
- off-target 검증이 필요함

즉 "쓸 수는 있지만 아직 production-grade라고 부르기는 이른 상태"입니다.

### 14-2. external desktop

현재 상태:

- 연결 완료
- UI-TARS bridge 동작
- Notepad 시나리오 중심 검증

하지만 남은 문제:

- timeout 가능성
- 저장 성공률 변동
- 시나리오 확장 전 검증 필요

즉 desktop external도 "실동작 PoC는 됨, 완성형은 아님"이 가장 정확합니다.

---

## 15. 현재 가장 안정적인 시나리오와 가장 불안정한 시나리오

### 상대적으로 안정적인 쪽

- `search_and_read` external
- `open_notepad_and_type` internal
- `change_system_setting` 일부

### 중간 단계

- `open_notepad_and_type` external
- `inspect_workspace_files`

### 아직 불안정하거나 구조적으로 과도기인 쪽

- `find_map_route`
- `general_assistance`
- 일본어 wakeword 운영 품질

---

## 16. 이 프로젝트를 한 문장으로 소개하면

VisionNavi는 고령자를 주요 사용자로 두고, 음성 또는 자연어 명령을 웹과 Windows 데스크톱 작업으로 연결하는 로컬 에이전트형 자동화 플랫폼이며, 현재는 internal baseline 위에 BrowserUse / ComputerUse 계열 external runtime을 점진적으로 통합하는 과도기 단계에 있습니다.

---

## 17. 현재 상태를 가장 솔직하게 요약하면

현재 VisionNavi는 다음처럼 보는 것이 가장 정확합니다.

- UI와 사용자 흐름은 빠르게 제품형으로 발전 중이다.
- 오케스트레이터, 세션, trace 구조는 이미 꽤 잘 잡혀 있다.
- intent 분류는 LLM first + rule fallback + harmonization 구조다.
- `search_and_read`는 external browser agent 중심으로 가장 앞서 있다.
- `open_notepad_and_type`는 external desktop agent의 대표 검증 시나리오다.
- `find_map_route`는 아직 deterministic internal baseline 비중이 크다.
- VLM은 전체 시스템의 중심이 아니라 일부 시나리오에서만 실질 영향력이 있다.
- STT와 wakeword는 모두 로컬 중심이며, 제품 경험 쪽 개선이 계속 진행 중이다.
- 개발 방향은 분명히 external-first지만, 운영 안정성을 위해 internal fallback을 아직 유지한다.

---

## 18. 앞으로 이 문서를 읽는 사람이 꼭 기억해야 할 핵심

1. VisionNavi는 단순 매크로가 아니라 orchestrator다.
2. 모든 intent가 같은 수준의 agent autonomy를 가지지는 않는다.
3. 현재 가장 중요한 축은 external runtime 성숙화다.
4. route는 아직 완전 agent형이 아니라 internal baseline 중심이다.
5. VLM은 일부 구간에서만 중요하고, 전체 시스템을 지배하지는 않는다.
6. 현재 구조는 "external-only 완성판"이 아니라 "external-first 과도기"다.

---

## 19. 관련 핵심 코드 경로 모음

### 프론트엔드

- [frontend/lib/features/home/presentation/home_screen.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)
- [frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart)
- [frontend/lib/services/orchestrator_client.dart](/C:/Users/USER/Documents/VisionNavi/frontend/lib/services/orchestrator_client.dart)

### 오케스트레이터

- [orchestrator/app/api/routes/pipeline.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
- [orchestrator/app/agent/loop.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/core/settings.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/core/settings.py)

### 모델 / 라우팅

- [orchestrator/app/services/model_client.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
- [orchestrator/app/services/intent_router.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/intent_router.py)
- [orchestrator/app/models/model_api.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/model_api.py)
- [orchestrator/app/models/canonical_command.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/canonical_command.py)

### 브라우저 / 데스크톱 실행기

- [orchestrator/app/automation/browser/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/automation/browser/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)
- [orchestrator/app/automation/desktop/executor.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)
- [orchestrator/app/automation/desktop/external_agent_adapter.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)

### 음성 / wakeword

- [orchestrator/app/services/audio_transcription_service.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/audio_transcription_service.py)
- [orchestrator/app/services/wakeword_service.py](/C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/wakeword_service.py)
- [runtime/wakewords/manifest.json](/C:/Users/USER/Documents/VisionNavi/runtime/wakewords/manifest.json)

---

## 20. 마무리

VisionNavi는 현재 "완성된 범용 에이전트"라기보다, 고령자 친화형 음성 인터페이스 위에 local STT, wakeword, LLM, external browser/desktop agent를 점진적으로 결합해 가는 실전형 프로젝트입니다.

이미 단순 데모 수준은 넘어섰지만, 모든 시나리오가 동일한 수준으로 agent화된 것은 아닙니다.

따라서 현재 이 프로젝트를 이해할 때 가장 중요한 관점은 다음입니다.

- 어떤 시나리오는 이미 external agent 중심이다.
- 어떤 시나리오는 아직 internal deterministic baseline 중심이다.
- 전체 프로젝트는 그 둘을 같은 orchestrator 안에서 연결하고 비교할 수 있도록 설계되어 있다.

이 점을 기준으로 보면 현재 VisionNavi의 구조와 방향이 훨씬 명확하게 보입니다.
