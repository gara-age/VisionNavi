# VisionNavi Reading Order Guide

## 1. 이 문서의 목적

이 문서는 VisionNavi 저장소를 처음 여는 사람이 실제로 어떤 순서로 파일을 읽어야 하는지 안내하는 문서입니다.

기존 [docs/MustRead/visionnavi-complete-system-guide.md](C:/Users/USER/Documents/VisionNavi/docs/MustRead/visionnavi-complete-system-guide.md)가 “전체 설명서”라면, 이 문서는 아래 2가지를 더 강하게 제공합니다.

- 실제 코드 읽기 순서
- 와이어프레임처럼 보는 디렉터리 계층도

즉, 이 문서는 “무슨 파일이 있지?”보다 “어떤 파일부터 열어야 길을 잃지 않는지”에 집중합니다.

---

## 2. 가장 먼저 알아야 할 한 줄 구조

VisionNavi는 크게 4개 층으로 나뉩니다.

1. `frontend/`
   사용자 화면과 입력
2. `orchestrator/`
   명령 해석, 세션 관리, 실행 백엔드 선택
3. `runtime/`
   wakeword, TTS, external agent, 모델 자산
4. `scripts/`
   실행, 재시작, 빌드, 학습, 상태 추적

처음 읽는 사람은 이 4개를 한 번에 다 보려고 하면 복잡합니다.

추천 방식은:

- 먼저 “한 번의 사용자 요청이 어떻게 흐르는지” 읽고
- 그 다음에 “기능별 세부 축”으로 들어가는 것입니다.

---

## 3. 최상위 디렉터리 와이어프레임

```text
VisionNavi/
├─ README.md
├─ contracts/
│  └─ canonical_command.schema.json
├─ data/
│  └─ voxcpm/
│     └─ VoxCPM2/
├─ docs/
│  ├─ MustRead/
│  │  ├─ visionnavi-complete-system-guide.md
│  │  └─ visionnavi-reading-order-guide.md
│  ├─ visionnavi-project-guide.md
│  ├─ visionnavi-development-history.md
│  ├─ visionnavi-current-status.md
│  ├─ visionnavi-midterm-presentation.md
│  ├─ visionnavi-midterm-slides.md
│  ├─ external-first-stabilization-plan.md
│  ├─ continuous-llm-runtime.md
│  ├─ continuous-llm-runtime-roadmap.md
│  ├─ livekit-wakeword-setup.md
│  ├─ architecture.md
│  ├─ mvp-roadmap.md
│  └─ next-scenario-expansion-guide.md
├─ frontend/
│  └─ lib/
├─ logs/
│  ├─ orchestrator-stdout.log
│  ├─ orchestrator-stderr.log
│  └─ benchmarks/
├─ orchestrator/
│  └─ app/
├─ outputs/
│  └─ visionnavi-midterm-presentation.*
├─ runtime/
│  ├─ external_agents/
│  ├─ tts_output/
│  └─ wakewords/
└─ scripts/
```

### 어떻게 해석하면 좋은가

- `frontend/`와 `orchestrator/`는 “실행 코드”
- `runtime/`은 “실행 코드가 의존하는 외부 자산과 보조 런타임”
- `scripts/`는 “운영 도구”
- `docs/`는 “설계/상태/발표 문서”

---

## 4. 가장 추천하는 읽기 순서

### 4.1 10분 안에 전체 감 잡기

아래 순서대로 읽으면 “VisionNavi가 대체 뭔지”를 빠르게 이해할 수 있습니다.

1. [README.md](C:/Users/USER/Documents/VisionNavi/README.md)
2. [docs/MustRead/visionnavi-complete-system-guide.md](C:/Users/USER/Documents/VisionNavi/docs/MustRead/visionnavi-complete-system-guide.md)
3. [frontend/lib/features/home/presentation/home_screen.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)
4. [frontend/lib/services/orchestrator_client.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/services/orchestrator_client.dart)
5. [orchestrator/app/api/routes/pipeline.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
6. [orchestrator/app/agent/loop.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)

이 6개만 보면:

- UI에서 어떤 요청을 만드는지
- 그 요청이 어떤 API로 가는지
- canonical command가 어떻게 만들어지는지
- backend가 어떻게 골라지는지

를 빠르게 알 수 있습니다.

### 4.2 실제 개발에 들어가기 전 필수 읽기

다음 파일까지 보면 구조를 “대충”이 아니라 “실제 수정 가능한 수준”으로 이해하게 됩니다.

7. [orchestrator/app/services/command_constraint_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/command_constraint_service.py)
8. [orchestrator/app/services/model_client.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
9. [orchestrator/app/automation/browser/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)
10. [orchestrator/app/automation/browser/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
11. [orchestrator/app/automation/desktop/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)
12. [orchestrator/app/automation/desktop/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)

이 시점부터는:

- 어떤 부분이 external-first인지
- 어떤 부분이 아직 internal baseline인지
- 어디서 drift를 막고 있는지
- 어떤 부분이 deterministic인지

를 명확히 볼 수 있습니다.

---

## 5. 추천 읽기 경로 A: “사용자 요청 1건” 따라가기

이 경로는 가장 추천하는 입문 방식입니다.

### 5.1 1단계: 홈 화면에서 요청이 만들어지는 지점

가장 먼저 볼 파일:

- [frontend/lib/features/home/presentation/home_screen.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)

이 파일에서 확인할 것:

- 텍스트 입력 상태
- 음성 녹음 상태
- wakeword 상태
- 세션 상태 구독
- 실행 버튼 / 요청하기 버튼
- canonicalize / run 호출 시점

이 파일은 프론트의 거의 모든 상호작용이 모여 있는 중심 파일입니다.

### 5.2 2단계: 프론트가 어떤 API를 호출하는지 보기

다음 파일:

- [frontend/lib/services/orchestrator_client.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/services/orchestrator_client.dart)

이 파일에서 보면 좋은 메서드:

- `canonicalizeCommand`
- `runCommand`
- `runCanonicalCommand`
- `transcribeAudioFile`
- `generatePopupSummary`
- `fetchWakeWordStatus`
- `startWakeWord`
- `stopWakeWord`

즉 VisionNavi 프론트에서 백엔드로 나가는 모든 공식 통로가 여기에 있습니다.

### 5.3 3단계: 백엔드 API 진입점 보기

다음 파일:

- [orchestrator/app/api/routes/pipeline.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)

이 파일이 중요한 이유:

- frontend가 호출하는 실제 API가 여기서 정의됨
- canonical command 생성도 여기서 시작됨
- STT, wakeword, popup summary, TTS API도 여기에 연결됨

가장 먼저 찾아볼 함수:

- `build_canonical_command`
- `build_canonical_command_with_trace`

### 5.4 4단계: canonical command가 어떤 구조인지 보기

다음 파일:

- [orchestrator/app/models/canonical_command.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/canonical_command.py)
- [orchestrator/app/models/command_constraint.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/command_constraint.py)

이 두 파일은 VisionNavi 해석 계층의 중심입니다.

여기서 이해해야 하는 핵심:

- raw text가 바로 실행되지 않는다
- 중간에 canonical command가 있다
- command constraint가 provider/query/language를 붙잡는다

### 5.5 5단계: 세션과 agent loop 보기

다음 파일:

- [orchestrator/app/agent/loop.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
- [orchestrator/app/models/session.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/session.py)
- [orchestrator/app/services/session_store.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/session_store.py)

이 지점에서 알 수 있는 것:

- phase가 어떻게 변하는지
- session event가 어떻게 쌓이는지
- requested backend와 effective backend가 어떻게 갈릴 수 있는지

### 5.6 6단계: 실제 executor 진입점 보기

브라우저:

- [orchestrator/app/automation/browser/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
- [orchestrator/app/automation/browser/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)

데스크톱:

- [orchestrator/app/automation/desktop/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)
- [orchestrator/app/automation/desktop/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)

여기까지 보면 한 요청이 실제로 어디까지 흘러가는지 거의 다 보입니다.

---

## 6. 추천 읽기 경로 B: “UI부터 이해하기”

UI를 먼저 만질 사람에게는 아래 순서를 추천합니다.

### 6.1 프론트엔드 디렉터리 와이어프레임

```text
frontend/lib/
├─ main.dart
├─ app/
│  ├─ vision_navi_app.dart
│  └─ theme/
│     ├─ app_theme.dart
│     ├─ colors.dart
│     └─ typography.dart
├─ features/
│  └─ home/
│     ├─ models/
│     │  └─ home_user_settings.dart
│     ├─ presentation/
│     │  ├─ home_screen.dart
│     │  └─ widgets/
│     │     ├─ action_panel.dart
│     │     ├─ home_settings_dialog.dart
│     │     ├─ status_card.dart
│     │     └─ text_command_composer.dart
│     └─ services/
│        └─ home_settings_store.dart
├─ models/
│  └─ session_models.dart
└─ services/
   ├─ orchestrator_client.dart
   ├─ result_tts_service.dart
   └─ taskbar_popup_service.dart
```

### 6.2 UI를 읽는 실제 순서

1. [frontend/lib/main.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/main.dart)
2. [frontend/lib/app/vision_navi_app.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/app/vision_navi_app.dart)
3. [frontend/lib/features/home/presentation/home_screen.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)
4. [frontend/lib/features/home/presentation/widgets/text_command_composer.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/widgets/text_command_composer.dart)
5. [frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart)
6. [frontend/lib/features/home/models/home_user_settings.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/models/home_user_settings.dart)
7. [frontend/lib/features/home/services/home_settings_store.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/services/home_settings_store.dart)
8. [frontend/lib/app/theme/app_theme.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/app/theme/app_theme.dart)
9. [frontend/lib/app/theme/colors.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/app/theme/colors.dart)

### 6.3 UI 파일별 역할

| 파일 | 읽는 이유 |
|---|---|
| `main.dart` | 앱 시작점 |
| `vision_navi_app.dart` | 전역 테마, 라우팅, 앱 골격 |
| `home_screen.dart` | 메인 동작 상태 대부분이 여기에 있음 |
| `text_command_composer.dart` | 텍스트 입력 모드 UI |
| `home_settings_dialog.dart` | 설정 화면, 언어/테마/TTS/wakeword 설정 UI |
| `home_user_settings.dart` | 설정 데이터 구조 |
| `home_settings_store.dart` | 설정 저장/로딩 |
| `app_theme.dart` | 다크/고대비/기본 테마 연결점 |
| `colors.dart` | 실제 색상 충돌 디버깅 포인트 |

### 6.4 UI를 수정할 때 가장 먼저 보는 곳

- 레이아웃 깨짐: `home_screen.dart`
- 설정창 깨짐: `home_settings_dialog.dart`
- 테마 적용 이상: `app_theme.dart`, `colors.dart`
- 텍스트 입력 UX: `text_command_composer.dart`
- 팝업/TTS 연동: `taskbar_popup_service.dart`, `result_tts_service.dart`

---

## 7. 추천 읽기 경로 C: “오케스트레이터부터 이해하기”

백엔드 구조를 먼저 보고 싶은 사람에게는 아래 순서를 추천합니다.

### 7.1 orchestrator 디렉터리 와이어프레임

```text
orchestrator/app/
├─ main.py
├─ agent/
│  └─ loop.py
├─ api/
│  └─ routes/
│     ├─ health.py
│     └─ pipeline.py
├─ automation/
│  ├─ browser/
│  │  ├─ executor.py
│  │  └─ external_agent_adapter.py
│  └─ desktop/
│     ├─ executor.py
│     └─ external_agent_adapter.py
├─ core/
│  ├─ build_info.py
│  └─ settings.py
├─ models/
│  ├─ action_step.py
│  ├─ agent_adapter.py
│  ├─ canonical_command.py
│  ├─ command_constraint.py
│  ├─ execution_backend.py
│  ├─ map_route.py
│  ├─ model_api.py
│  ├─ requests.py
│  └─ session.py
└─ services/
   ├─ audio_diagnostics_service.py
   ├─ audio_transcription_service.py
   ├─ command_constraint_service.py
   ├─ command_normalizer.py
   ├─ guidance_tts_service.py
   ├─ intent_router.py
   ├─ map_route_parser.py
   ├─ model_client.py
   ├─ safety_classifier.py
   ├─ session_store.py
   └─ wakeword_service.py
```

### 7.2 백엔드 읽기 순서

1. [orchestrator/app/main.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/main.py)
2. [orchestrator/app/api/routes/pipeline.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
3. [orchestrator/app/core/settings.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/core/settings.py)
4. [orchestrator/app/models/canonical_command.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/canonical_command.py)
5. [orchestrator/app/models/command_constraint.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/models/command_constraint.py)
6. [orchestrator/app/services/intent_router.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/intent_router.py)
7. [orchestrator/app/services/command_constraint_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/command_constraint_service.py)
8. [orchestrator/app/services/model_client.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
9. [orchestrator/app/agent/loop.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
10. browser/desktop executor 및 adapter

### 7.3 이 순서가 좋은 이유

이 순서대로 보면:

- 설정값이 전체 구조를 어떻게 바꾸는지
- canonical command가 어디서 만들어지는지
- constraint가 언제 붙는지
- LLM 호출은 어디서 일어나는지
- backend는 어디서 갈라지는지

가 자연스럽게 이어집니다.

---

## 8. 추천 읽기 경로 D: “브라우저 자동화만 집중해서 보기”

브라우저 문제를 잡는 사람이면 이 경로가 가장 효율적입니다.

### 8.1 브라우저 관련 파일 계층

```text
orchestrator/app/automation/browser/
├─ executor.py
└─ external_agent_adapter.py

orchestrator/app/services/
├─ command_constraint_service.py
├─ map_route_parser.py
└─ model_client.py
```

### 8.2 읽기 순서

1. [orchestrator/app/services/intent_router.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/intent_router.py)
2. [orchestrator/app/services/map_route_parser.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/map_route_parser.py)
3. [orchestrator/app/services/command_constraint_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/command_constraint_service.py)
4. [orchestrator/app/automation/browser/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)
5. [orchestrator/app/automation/browser/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
6. [scripts/run_external_browser_benchmark.py](C:/Users/USER/Documents/VisionNavi/scripts/run_external_browser_benchmark.py)

### 8.3 이 축에서 반드시 이해해야 하는 것

- `search_and_read`는 external-first
- `find_map_route`는 아직 internal baseline 비중 큼
- provider/query/language drift는 모델보다 constraint 구조로 먼저 막으려는 중
- external browser 실패 시에도 cross-provider fallback은 금지 방향

---

## 9. 추천 읽기 경로 E: “데스크톱 자동화만 집중해서 보기”

### 9.1 데스크톱 관련 파일 계층

```text
orchestrator/app/automation/desktop/
├─ executor.py
└─ external_agent_adapter.py

runtime/external_agents/ui_tars_bridge/
├─ package.json
├─ package-lock.json
└─ run_ui_tars.js
```

### 9.2 읽기 순서

1. [orchestrator/app/automation/desktop/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/executor.py)
2. [orchestrator/app/automation/desktop/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/desktop/external_agent_adapter.py)
3. [runtime/external_agents/ui_tars_bridge/run_ui_tars.js](C:/Users/USER/Documents/VisionNavi/runtime/external_agents/ui_tars_bridge/run_ui_tars.js)
4. [scripts/run_external_desktop_benchmark.py](C:/Users/USER/Documents/VisionNavi/scripts/run_external_desktop_benchmark.py)

### 9.3 여기서 체크할 포인트

- internal Notepad flow가 얼마나 deterministic인지
- external desktop agent가 어디서 retry하는지
- 검증은 어떤 기준으로 success/fail을 내는지
- bridge가 실제로 어떤 payload를 받는지

---

## 10. 추천 읽기 경로 F: “음성 기능만 집중해서 보기”

이 경로는 STT, wakeword, TTS를 한 덩어리로 보는 순서입니다.

### 10.1 음성 관련 디렉터리 와이어프레임

```text
frontend/lib/services/
├─ orchestrator_client.dart
├─ result_tts_service.dart
└─ taskbar_popup_service.dart

frontend/lib/features/home/presentation/
└─ home_screen.dart

orchestrator/app/services/
├─ audio_diagnostics_service.py
├─ audio_transcription_service.py
├─ guidance_tts_service.py
└─ wakeword_service.py

runtime/external_agents/
├─ edge_tts_worker/
│  └─ server.py
└─ ui_tars_bridge/

runtime/wakewords/
├─ manifest.json
├─ configs/
├─ models/
└─ logs/
```

### 10.2 읽기 순서

1. [frontend/lib/features/home/presentation/home_screen.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)
2. [frontend/lib/services/orchestrator_client.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/services/orchestrator_client.dart)
3. [orchestrator/app/services/audio_transcription_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/audio_transcription_service.py)
4. [orchestrator/app/services/wakeword_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/wakeword_service.py)
5. [runtime/wakewords/manifest.json](C:/Users/USER/Documents/VisionNavi/runtime/wakewords/manifest.json)
6. [orchestrator/app/services/guidance_tts_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/guidance_tts_service.py)
7. [runtime/external_agents/edge_tts_worker/server.py](C:/Users/USER/Documents/VisionNavi/runtime/external_agents/edge_tts_worker/server.py)
8. [frontend/lib/services/result_tts_service.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/services/result_tts_service.dart)

### 10.3 음성 기능 디버깅 시 빨리 봐야 할 곳

| 문제 | 먼저 볼 파일 |
|---|---|
| 파일 STT 실패 | `audio_transcription_service.py` |
| wakeword 감지 안 됨 | `wakeword_service.py`, `runtime/wakewords/manifest.json` |
| 한국어만 감지되고 일본어만 안 됨 | 일본어 `yaml`, `onnx`, 학습 로그 |
| TTS 재생 느림 | `result_tts_service.dart`, `edge_tts_worker/server.py` |
| TTS 재생 안 됨 | `guidance_tts_service.py`, `runtime/tts_output/` |

---

## 11. runtime 폴더 읽는 법

많은 사람이 `runtime/`을 “부수 파일 모음”으로 생각하는데, VisionNavi에서는 그렇지 않습니다.

이 폴더는 실제 실행 품질과 직접 연결된 자산 폴더입니다.

### 11.1 runtime 디렉터리 와이어프레임

```text
runtime/
├─ external_agents/
│  ├─ edge_tts_worker/
│  │  └─ server.py
│  └─ ui_tars_bridge/
│     ├─ package.json
│     ├─ package-lock.json
│     └─ run_ui_tars.js
├─ tts_output/
│  └─ *.mp3 / *.wav
└─ wakewords/
   ├─ manifest.example.json
   ├─ manifest.json
   ├─ configs/
   ├─ logs/
   └─ models/
```

### 11.2 각 하위 폴더 의미

| 경로 | 의미 |
|---|---|
| `runtime/external_agents/edge_tts_worker` | Edge TTS 전용 서버 |
| `runtime/external_agents/ui_tars_bridge` | desktop external agent bridge |
| `runtime/tts_output` | 합성된 음성 파일 출력 |
| `runtime/wakewords/configs` | wakeword 학습 설정 |
| `runtime/wakewords/models` | 실제 추론에 쓰는 ONNX 모델 |
| `runtime/wakewords/logs` | 학습 로그 |

---

## 12. scripts 폴더 읽는 법

실행과 운영을 이해하고 싶으면 `scripts/`도 꼭 봐야 합니다.

### 12.1 scripts 디렉터리 와이어프레임

```text
scripts/
├─ resolve_orchestrator_python.ps1
├─ setup_orchestrator_env.ps1
├─ run_orchestrator.ps1
├─ run_orchestrator_ollama.ps1
├─ restart_orchestrator.ps1
├─ restart_orchestrator_and_build.ps1
├─ restart_orchestrator_and_build.cmd
├─ run_chrome_debug.ps1
├─ start_tts_worker.ps1
├─ render_guidance_tts.ps1
├─ show_taskbar_popup.ps1
├─ run_external_browser_benchmark.py
├─ run_external_desktop_benchmark.py
├─ start_wakeword_training_*.ps1
├─ watch_wakeword_*.ps1
├─ watch_wakeword_*.cmd
└─ popup_icons/
```

### 12.2 읽기 순서

1. [scripts/setup_orchestrator_env.ps1](C:/Users/USER/Documents/VisionNavi/scripts/setup_orchestrator_env.ps1)
2. [scripts/resolve_orchestrator_python.ps1](C:/Users/USER/Documents/VisionNavi/scripts/resolve_orchestrator_python.ps1)
3. [scripts/run_orchestrator.ps1](C:/Users/USER/Documents/VisionNavi/scripts/run_orchestrator.ps1)
4. [scripts/restart_orchestrator.ps1](C:/Users/USER/Documents/VisionNavi/scripts/restart_orchestrator.ps1)
5. [scripts/restart_orchestrator_and_build.ps1](C:/Users/USER/Documents/VisionNavi/scripts/restart_orchestrator_and_build.ps1)
6. [scripts/start_tts_worker.ps1](C:/Users/USER/Documents/VisionNavi/scripts/start_tts_worker.ps1)
7. 필요 시 wakeword training/watch 스크립트

### 12.3 왜 중요하나

VisionNavi는 단일 프로세스 앱이 아닙니다.

운영에 필요한 것이 나뉘어 있습니다.

- Flutter app
- FastAPI orchestrator
- Ollama
- TTS worker
- Chrome debug session
- wakeword training environment

그래서 스크립트를 보면 “실제로 어떻게 운영하는 시스템인지”가 보입니다.

---

## 13. 외부 폴더까지 포함한 전체 운영 계층도

VisionNavi는 저장소 안 코드만으로 끝나지 않으므로, 외부 폴더까지 포함해 보는 것이 좋습니다.

```text
C:\Users\USER\Documents\VisionNavi
├─ frontend/
├─ orchestrator/
├─ runtime/
│  └─ wakewords/
├─ scripts/
└─ docs/

D:\VisionNaviRuntime
└─ orchestrator-venv/

D:\VisionNaviWakeword
├─ data/
├─ logs/
├─ output/
├─ pip-cache/
└─ temp/
```

### 해석

- `C:\Users\USER\Documents\VisionNavi`는 코드 저장소
- `D:\VisionNaviRuntime`는 실제 Python 런타임
- `D:\VisionNaviWakeword`는 wakeword 학습 작업장

즉 저장소만 복사해도 시스템이 완전 재현되지는 않습니다.

---

## 14. 처음 보는 사람이 실제로 따라 하면 좋은 읽기 시나리오

### 시나리오 1: “UI 버그를 고쳐야 한다”

추천 순서:

1. `home_screen.dart`
2. `text_command_composer.dart`
3. `home_settings_dialog.dart`
4. `app_theme.dart`
5. `colors.dart`

### 시나리오 2: “브라우저가 왜 다른 검색엔진으로 가는지 봐야 한다”

추천 순서:

1. `intent_router.py`
2. `command_constraint_service.py`
3. `pipeline.py`
4. `external_agent_adapter.py`
5. `browser executor.py`
6. `run_external_browser_benchmark.py`

### 시나리오 3: “웨이크워드가 왜 안 잡히는지 봐야 한다”

추천 순서:

1. `home_screen.dart`
2. `orchestrator_client.dart`
3. `wakeword_service.py`
4. `runtime/wakewords/manifest.json`
5. `runtime/wakewords/configs/*.yaml`
6. `runtime/wakewords/logs/*.log`
7. `D:\VisionNaviWakeword\logs\*.log`

### 시나리오 4: “TTS가 왜 안 들리는지 봐야 한다”

추천 순서:

1. `result_tts_service.dart`
2. `edge_tts_worker/server.py`
3. `guidance_tts_service.py`
4. `scripts/start_tts_worker.ps1`
5. `runtime/tts_output/`

---

## 15. 파일/폴더별 상세 역할 요약

### 15.1 frontend

- 사용자와 가장 가까운 계층
- “무엇을 눌렀는가”와 “지금 어떤 상태를 보여주는가”를 담당
- UI/UX, 텍스트 입력, 음성 시작, 결과 재생

### 15.2 orchestrator

- VisionNavi의 두뇌
- 명령을 canonical command로 바꾸고
- constraint를 붙이고
- 어떤 백엔드로 실행할지 결정

### 15.3 runtime

- 실제 기능 품질을 좌우하는 실행 자산 폴더
- wakeword 모델, TTS worker, external bridge가 모두 여기에 있음

### 15.4 scripts

- 운영 도구
- 수동 실행 실수를 줄이고 개발 루프를 빠르게 함

### 15.5 docs

- 개발 배경, 현재 상태, 발표, 전략 판단 문서
- 코드만 읽어서는 놓치기 쉬운 설계 의도를 보완

### 15.6 contracts

- 프론트와 백엔드 사이의 해석 기준
- canonical command를 시스템 공통 언어로 만드는 층

### 15.7 logs / outputs / data

- `logs`: 품질 분석과 디버깅
- `outputs`: 발표/시연 산출물
- `data`: wakeword와 보조 런타임용 외부 데이터

---

## 16. 가장 중요한 파일 15개

정말 시간이 없을 때는 아래 15개만 봐도 됩니다.

1. [README.md](C:/Users/USER/Documents/VisionNavi/README.md)
2. [docs/MustRead/visionnavi-complete-system-guide.md](C:/Users/USER/Documents/VisionNavi/docs/MustRead/visionnavi-complete-system-guide.md)
3. [frontend/lib/features/home/presentation/home_screen.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/home_screen.dart)
4. [frontend/lib/services/orchestrator_client.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/services/orchestrator_client.dart)
5. [frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/features/home/presentation/widgets/home_settings_dialog.dart)
6. [frontend/lib/app/theme/app_theme.dart](C:/Users/USER/Documents/VisionNavi/frontend/lib/app/theme/app_theme.dart)
7. [orchestrator/app/api/routes/pipeline.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/api/routes/pipeline.py)
8. [orchestrator/app/agent/loop.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/agent/loop.py)
9. [orchestrator/app/services/command_constraint_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/command_constraint_service.py)
10. [orchestrator/app/services/model_client.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/model_client.py)
11. [orchestrator/app/automation/browser/external_agent_adapter.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/external_agent_adapter.py)
12. [orchestrator/app/automation/browser/executor.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/automation/browser/executor.py)
13. [orchestrator/app/services/audio_transcription_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/audio_transcription_service.py)
14. [orchestrator/app/services/wakeword_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/wakeword_service.py)
15. [orchestrator/app/services/guidance_tts_service.py](C:/Users/USER/Documents/VisionNavi/orchestrator/app/services/guidance_tts_service.py)

---

## 17. 처음 읽을 때 주의할 점

### 17.1 “현재 코드에 있는 것”과 “최종 목표”를 구분해서 봐야 한다

VisionNavi는 목표가 큽니다.

- BrowserUse / ComputerUse류 통합
- 고령자용 UX
- 한국어 / 일본어
- wakeword / STT / TTS

하지만 모든 부분이 동일한 완성도는 아닙니다.

예:

- `search_and_read`는 external-first에 가까움
- `find_map_route`는 아직 internal baseline 비중 큼
- 한국어 wakeword는 비교적 앞섬
- 일본어 wakeword는 뒤처짐

### 17.2 “external-first”와 “external-only”는 다르다

현재 방향은 external-first이지만,

- 아직 일부는 internal fallback 또는 internal baseline이 필요합니다.

즉 읽을 때:

- 정책 문구만 보지 말고
- 실제 `supports`, `routing`, `fallback` 코드를 함께 봐야 합니다.

### 17.3 trace와 UI 문구는 완전히 같은 상태머신이 아니다

사용자가 계속 지적했던 부분처럼,

- 내부 세션 phase
- UI 제목
- 버튼 상태
- wakeword 대기 문구

가 완전히 정리되어 있지 않은 구간이 있습니다.

따라서 UX 문제를 볼 때는 프론트 상태 변수와 세션 이벤트를 같이 봐야 합니다.

---

## 18. 다음에 이 문서를 어떻게 쓰면 좋은가

이 문서는 아래 상황에서 기준 문서로 쓰기 좋습니다.

- 새 개발자 온보딩
- 발표/Q&A 준비 전 코드 구조 정리
- 특정 축만 집중 디버깅하기 전 사전 길잡이
- 리팩터링 범위 파악

추천 조합:

- 전체 설명은 [docs/MustRead/visionnavi-complete-system-guide.md](C:/Users/USER/Documents/VisionNavi/docs/MustRead/visionnavi-complete-system-guide.md)
- 실제 읽기 순서는 이 문서

즉:

- complete guide = “무엇을 만들고 있는가”
- reading order guide = “어디서부터 읽을 것인가”
