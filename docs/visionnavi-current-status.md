# VisionNavi 현재 상태 통합 문서

## 1. 문서 목적

이 문서는 2026년 7월 초 기준 VisionNavi의 현재 상태를 한 파일에서 이해할 수 있도록 정리한 통합 문서다.

이 문서가 답하려는 질문은 다음과 같다.

- VisionNavi는 어떤 프로젝트인가
- 지금까지 무엇을 구현했는가
- 현재 실제로 동작하는 기능과 아직 불안정한 기능은 무엇인가
- external-first 방향 전환 이후 구조는 어떻게 되어 있는가
- 현재 가장 큰 기술적 리스크는 무엇인가
- 다음 개발 우선순위는 무엇인가

이 문서는 과거의 기획 배경, 현재 코드 구조, 기능별 구현 수준, 미구현 사항, 최근 확인된 장애 요인까지 포함한 상태 보고서 성격을 가진다.

## 2. 프로젝트 한 줄 설명

VisionNavi는 사용자의 음성 또는 텍스트 자연어 명령을 받아, 웹 브라우저와 Windows 데스크톱 환경에서 실제 작업을 수행하는 접근성 중심 자동화 오케스트레이터다.

장기적으로는 BrowserUse / ComputerUse 계열의 오픈소스 agent runtime을 VisionNavi 내부에서 통합 운용하는 것이 목표다.

## 3. 제품 목표

### 3-1. 사용자 목표

VisionNavi의 주 사용자 가정은 한국과 일본의 고령자다.

의도하는 주요 사용 시나리오는 다음과 같다.

- 복지 정보 탐색
- 일반 웹 검색 및 간단한 정보 읽기
- 길찾기와 같은 생활형 웹 작업
- 메모 작성, 파일 열기 같은 간단한 데스크톱 작업
- 향후 서드파티 앱 자동화

### 3-2. 기술 목표

VisionNavi가 지향하는 기술적 목표는 다음과 같다.

- 자연어 명령을 안전하게 해석하고 canonical command로 정규화
- 브라우저와 데스크톱 환경에 대해 실제 자동화 수행
- 실행 결과와 실패 원인을 trace로 남겨 관측 가능성 확보
- internal deterministic executor와 external agent runtime을 같은 orchestrator 아래에서 운용
- 최종적으로는 external agent runtime 중심으로 발전

## 4. 개발 방향의 역사

### 4-1. 초기 단계: JSON step 기반 자동화

처음에는 상위 planner 또는 LLM이 전체 JSON step 계획을 한 번에 만들고, Python executor가 그 순서를 따라 실행하는 구조였다.

장점:

- 디버깅이 쉬움
- 재현성이 높음
- 명시적인 step 추적 가능

한계:

- 실제 화면이 바뀌면 취약
- 중간 복구가 어려움
- UI 절차를 미리 다 정의해야 해서 범용성이 낮음

### 4-2. Runtime Binding 단계

그 다음에는 상위 레이어가 intent, slots, target 정도만 정리하고, 실행 시점 binder가 화면 상태를 보고 대상을 고르는 방식으로 발전했다.

장점:

- 고정 step보다 유연함
- 실행 시점 상태 반영이 가능

한계:

- heuristic과 handcrafted policy 의존이 큼
- semantic ambiguity에 약함
- 복구도 결국 rule 기반 재시도에 머무름

### 4-3. Continuous LLM-guided runtime 지향

이후 목표는 LLM이 처음 계획만 하는 것이 아니라, 실행 중에도 observe / decide / act / verify / recover 루프에 지속 관여하도록 넓어졌다.

이 방향은 다음 문제의식에서 나왔다.

- 화면은 계속 바뀐다
- 버튼을 누르는 것 자체보다 목표 달성이 중요하다
- 복구와 타겟 선택은 현재 화면 맥락이 중요하다

### 4-4. 현재 단계: internal / external 공존, 개발 방향은 external-first

현재 VisionNavi는 internal executor와 external agent adapter가 함께 있는 구조다.

다만 전략적으로는 이미 external-first로 정리된 상태다.

의미:

- 신규 기능의 주 개발축은 `external_browser_agent`, `external_desktop_agent`
- internal은 신규 기능 주축이 아니라 baseline, fallback, route 임시 유지 역할
- 아직은 external-only 운영 단계는 아님

## 5. 현재 아키텍처

### 5-1. 프론트엔드

경로:

- `frontend/lib/main.dart`
- `frontend/lib/app/vision_navi_app.dart`
- `frontend/lib/features/home/presentation/home_screen.dart`

구현 개요:

- Flutter 기반 Windows 데스크톱 앱
- 사용자 모드 중심 UI
- Pretendard 폰트 적용
- 한국어 / 일본어 UI 문구 전환
- 음성 입력 버튼, 음성 파일 첨부, 설정 다이얼로그, 실행 채널 선택 포함
- 디버깅용 trace 영역과 사용자용 생활형 상태 문구 공존

주요 기능:

- 텍스트 명령 입력
- 음성 파일 업로드 후 STT
- 실시간 음성 입력 시도
- wakeword 상태 표시
- 실행 결과 팝업 표시
- 설정 저장
- canonical review / agent trace / event timeline export

### 5-2. 오케스트레이터

경로:

- `orchestrator/app/main.py`
- `orchestrator/app/api/routes/pipeline.py`
- `orchestrator/app/agent/loop.py`

구현 개요:

- FastAPI 기반 로컬 서버
- 세션 생성, canonicalization, intent routing, 안전성 분류, 실행 backend 선택 담당
- 프론트엔드와 HTTP 및 세션 상태 전파 연결

### 5-3. 모델 및 서비스 계층

경로:

- `orchestrator/app/services/model_client.py`
- `orchestrator/app/services/command_normalizer.py`
- `orchestrator/app/services/intent_router.py`
- `orchestrator/app/services/audio_transcription_service.py`
- `orchestrator/app/services/wakeword_service.py`

구현 개요:

- Ollama 기반 로컬 LLM 사용
- canonical command 보정
- popup 요약 생성
- STT
- wakeword 상태 관리

### 5-4. 브라우저 자동화 계층

경로:

- `orchestrator/app/automation/browser/executor.py`
- `orchestrator/app/automation/browser/external_agent_adapter.py`

구현 개요:

- internal browser executor
- external browser agent adapter
- Chrome CDP attach 및 기존 디버그 세션 재사용

### 5-5. 데스크톱 자동화 계층

경로:

- `orchestrator/app/automation/desktop/executor.py`
- `orchestrator/app/automation/desktop/external_agent_adapter.py`

구현 개요:

- internal desktop executor
- external desktop agent adapter
- Notepad 중심 baseline과 외부 agent PoC 공존

## 6. 실행 채널과 backend 전략

### 6-1. ExecutionBackend 개념

현재 코드상 지원 backend는 다음 네 가지다.

- `internal_browser`
- `external_browser_agent`
- `internal_desktop`
- `external_desktop_agent`

관련 코드:

- `orchestrator/app/models/execution_backend.py`
- `orchestrator/app/agent/loop.py`
- `orchestrator/app/core/settings.py`

### 6-2. 기본값

현재 기본 backend는 external-first다.

- `default_browser_execution_backend = external_browser_agent`
- `default_desktop_execution_backend = external_desktop_agent`

관련 코드:

- `orchestrator/app/core/settings.py`

### 6-3. 실제 의미

이 상태의 의미는 다음과 같다.

- 브라우저 일반 검색/읽기 작업은 external browser agent를 우선 사용
- 데스크톱 일반 작업은 external desktop agent를 우선 사용
- 지원되지 않거나 불안정한 intent는 internal fallback 또는 internal 소유 경로로 유지

단, 실제 안정성은 시나리오별로 크게 다르다.

## 7. 현재 연결된 주요 기술 스택

### 7-1. LLM

현재 대화와 코드 기준으로 사용 중인 주요 LLM 계열은 다음과 같다.

- Ollama 서버
- Qwen 계열 모델
- 브라우저 planner / popup summary / canonicalization 등에 로컬 모델 사용

추가로 external browser agent나 desktop agent의 내부 모델 설정은 별도 runtime에서 달라질 수 있다.

### 7-2. 브라우저 자동화

- Playwright
- Chrome 원격 디버그 포트 attach
- external browser-use 계열 runtime adapter

### 7-3. 데스크톱 자동화

- internal deterministic desktop executor
- external UI-TARS 계열 adapter

### 7-4. STT

- 프론트: `speech_to_text`
- 백엔드: `audio_transcription_service.py`
- 음성 파일 전사 API: `/pipeline/transcribe-audio`

### 7-5. 웨이크워드

- `livekit-wakeword`
- custom wakeword manifest 기반
- 한국어 / 일본어 프로필 선택 구조

### 7-6. 팝업

- 작업 완료 / 실패에 대한 taskbar popup
- LLM 기반 popup summary 생성 API 존재

## 8. 기능별 현재 구현 정도

아래 표는 현재 VisionNavi의 핵심 기능을 완료 / 제한적 동작 / 진행중 / 미구현 기준으로 정리한 것이다.

| 영역 | 상태 | 현재 설명 |
|---|---|---|
| 텍스트 명령 입력 | 완료 | 프론트에서 입력하고 오케스트레이터로 전달 가능 |
| canonicalization / intent routing | 완료 | LLM 보조 + 규칙 보정 구조 존재 |
| execution channel 선택 UI | 완료 | Auto / Internal / External 선택 가능 |
| external-first 기본값 | 완료 | browser/desktop 기본 backend가 external로 설정됨 |
| trace / export | 완료 | Canonical Review, Agent Trace, Event Timeline 복사 및 export 가능 |
| 작업 완료 팝업 | 완료 | 작업 완료/실패 팝업과 LLM popup summary 흐름 존재 |
| 다국어 UI 전환 | 완료 | 한국어 / 일본어 전환 구조 있음 |
| 설정 저장 | 완료 | 큰 글씨, 고대비, 다크 모드, 언어, 음성 관련 설정 저장 가능 |
| Pretendard 적용 | 완료 | Flutter 앱 폰트 자산 연결됨 |
| STT 음성 파일 업로드 | 제한적 동작 | 백엔드 전사 API는 있으나 정확도와 환경 의존성 이슈 있음 |
| 실시간 STT 버튼 | 제한적 동작 | 일부 환경에서 동작하지만 speech_to_text 제약이 큼 |
| wakeword UI / 상태 표시 | 완료 | 상태 표시, 입력 장치 진단, 레벨 미터, threshold UI 존재 |
| wakeword 실제 감지 | 진행중 | 리스너 코드와 UI 연결은 있으나 학습 모델 안정화 미완 |
| wakeword 학습 파이프라인 | 진행중 | D 드라이브 기반 학습 구조, monitor cmd, config 존재하나 현재 1455로 막힘 |
| internal search_and_read | 완료 | baseline 동작 가능 |
| external search_and_read | 제한적 동작 | browser-use 연결 및 trace는 되나 품질/grounding 불안정 |
| internal open_notepad_and_type | 완료 | deterministic executor 존재 |
| external open_notepad_and_type | 제한적 동작 | UI-TARS adapter 연결, 성공률/검증 안정성 미완 |
| dark mode 전환 | 완료 | Windows 다크 모드 executor 구현됨 |
| 파일 탐색기 / 디렉터리 작업 | 부분 구현 | action vocabulary는 있으나 사용자 관점 실동작 검증 부족 |
| internal find_map_route | 진행중 | Naver/Kakao route parsing과 retry 강화 중 |
| external find_map_route | 미구현 | 아직 external browser agent 대상 아님 |
| 고령자용 생활형 홈 UI | 진행중 | 사용자 모드로 많이 전환됐으나 레이아웃 완성도 개선 필요 |
| benchmark / 비교 체계 | 부분 구현 | trace와 결과 요약은 있으나 자동 집계는 약함 |

## 9. 현재 실제로 강한 영역

### 9-1. 프론트 구조와 사용자 모드 전환

현재 프론트는 단순 개발자용 데모를 넘어, 사용자 모드, 언어 전환, 설정 저장, 팝업 안내까지 포함하는 실제 제품형 껍데기를 갖췄다.

강점:

- Pretendard 기반 글꼴 적용
- 큰 글씨 / 고대비 / 다크 모드 설정
- 한국어 / 일본어 UI 문구
- 음성 요청 영역과 설정 다이얼로그
- 팝업 결과 안내

### 9-2. 세션 관측성과 trace

VisionNavi는 현재 trace가 비교적 강하다.

남기는 정보:

- canonical review
- agent trace
- event timeline
- execution backend
- raw / normalized trace
- failure reason

이 부분은 이후 external runtime 안정화에 매우 중요한 기반이다.

### 9-3. external-first 구조 전환 자체

전략적으로는 이미 중요한 결정을 끝냈다.

- internal과 external을 동등 개발하는 방향이 아니라
- external을 주 실행축으로 두고
- internal은 fallback / baseline / route 임시 유지로 좁히는 방향이 코드와 설정에 반영되어 있다

## 10. 현재 불안정하거나 막혀 있는 영역

### 10-1. external browser 안정성

`external_browser_agent`는 실제 연결되어 있으며 실행 trace도 남길 수 있다.

하지만 아직 남은 문제:

- 검색 의도와 무관한 페이지로 흐를 수 있음
- off-target navigation 또는 off-target summary 발생
- 결과 요약 grounding이 약함
- 반복 성공률이 완전히 안정적이지 않음

현재 평가는 다음이 맞다.

- 연결됨: 예
- 주 실행 경로로 사용할 수 있음: 부분적으로 예
- production-grade 안정성: 아직 아님

### 10-2. external desktop 안정성

`external_desktop_agent`는 UI-TARS bridge가 연결되어 있다.

하지만 아직 남은 문제:

- Notepad 시나리오의 반복 성공률 부족
- 저장 검증 안정성 부족
- timeout과 partial completion 구분은 되지만 usable 수준까지는 미완

즉, plumbing은 되어 있지만 성숙도는 아직 PoC에 가깝다.

### 10-3. find_map_route

길찾기 시나리오는 여전히 internal browser baseline 중심이다.

현재 상태:

- Naver Map / Kakao Map provider 분기
- 출발지 / 도착지 / 교통수단 분리 보강
- verify / retry 로직 보강

하지만 한계:

- 완전 범용 agent형이라기보다 시나리오 종속 실행기 성격이 남아 있음
- external browser runtime으로는 아직 이관되지 않음
- 고난도 UI 분기에서 안정성이 완전히 확보되진 않음

### 10-4. STT와 음성 흐름

현재 음성 쪽은 기능 골격은 많이 들어갔지만 환경 제약이 크다.

현재 확인된 문제:

- `speech_to_text` 기반 실시간 인식이 Windows 환경에 따라 불안정
- 원격 개발 환경과 실제 로컬 장치 환경 차이 존재
- 음성 파일 전사는 가능하지만 정확도 개선 필요
- 일본어 STT 정확도는 아직 부족

### 10-5. wakeword 학습과 배포

이 영역이 현재 가장 큰 blocker다.

현재까지 들어간 것:

- `livekit-wakeword` 기반 리스너 구조
- wakeword manifest
- 한국어/일본어 프로필 선택 구조
- 마이크 레벨 미터
- threshold 조절 UI
- 상태 진단 API
- D 드라이브 기반 학습 경로
- 학습 재시작 / 모니터링 스크립트

현재 blocker:

- `ko_hey_nabi`, `ja_nee_navi`, `ja_navisan` 학습이 `VoxCPM` 로딩 중 `OSError 1455`로 실패
- 문제는 D 드라이브 저장공간이 아니라, 현재 Windows 페이지 파일이 `C:\pagefile.sys` 2GB만 잡혀 있는 점
- 즉 학습 데이터 저장은 D에 하지만, 메모리 부족 시 쓰는 가상메모리는 C 설정에 묶여 있음

현재 상태를 한 줄로 정리하면:

- wakeword 리스너 제품 구조는 있음
- 실제 운영용 모델 학습과 안정 배포는 아직 막혀 있음

## 11. 사용자 모드 관점의 현재 상태

### 11-1. 이미 제품처럼 보이는 부분

- 한국어 / 일본어 전환
- 시니어 홈 형태의 메인 화면
- 생활형 문구
- 큰 글씨 / 고대비 / 다크 모드 설정
- 팝업 결과 안내
- 음성 요청 영역

### 11-2. 아직 디버깅 제품에 가까운 부분

- trace 영역의 레이아웃과 스크롤 경험이 여전히 거칠다
- 사용자가 보지 않아도 되는 개발자용 정보가 많다
- 일부 영역은 공간을 많이 차지하면서 가독성이 떨어진다

정리하면 사용자 모드의 방향은 맞지만, 아직 완전한 시니어 친화 제품 UI로 다듬는 작업은 남아 있다.

## 12. 코드 기준 현재 확인 가능한 주요 엔드포인트와 기능

주요 API:

- `/pipeline/canonicalize`
- `/pipeline/sessions`
- `/pipeline/transcribe-audio`
- `/pipeline/popup-summary`
- `/pipeline/wakeword/status`
- `/pipeline/wakeword/start`
- `/pipeline/wakeword/stop`
- `/pipeline/wakeword/acknowledge`

관련 코드:

- `orchestrator/app/api/routes/pipeline.py`

## 13. 현재 설정과 런타임 관련 사실

### 13-1. backend 기본값

- browser 기본: `external_browser_agent`
- desktop 기본: `external_desktop_agent`

### 13-2. Ollama 모델 저장 위치

현재 환경 변수 기준 Ollama 모델 경로는 `D:\OllamaModels`다.

즉 C 드라이브가 가득 찬 원인은 현재 사용하는 Ollama 모델 blob 자체라기보다, 업데이트 캐시나 다른 로컬 잔재일 가능성이 높다.

### 13-3. 페이지 파일 현황

현재 페이지 파일은 `C:\pagefile.sys` 하나만 보이며, 크기는 약 2GB 수준이다.

이것이 wakeword 학습 실패의 핵심 원인 중 하나로 확인되었다.

## 14. 현재 문서화가 필요한 핵심 리스크

### 14-1. 인코딩 및 문서 유지 리스크

기존 `docs/visionnavi-development-history.md`는 현재 환경에서 한글이 깨져 보이는 문제가 확인됐다.

따라서 문서 체계는 다음처럼 재정비하는 것이 좋다.

- 이 문서를 현재 상태 기준 정본으로 사용
- 기존 개발 역사 문서는 추후 UTF-8로 다시 정리

### 14-2. C 드라이브 공간 리스크

최근 실제로 발생한 문제:

- C 드라이브 공간 부족으로 YAML 설정 파일이 0바이트로 깨짐
- Flutter build cache와 로컬 `.venv`, Ollama update cache 정리 후 복구

즉 현재 개발 환경은 C 드라이브 여유 공간 관리가 매우 중요하다.

### 14-3. wakeword 학습 리스크

현재 wakeword는 코드가 아니라 운영 환경 제약 때문에 막히는 면이 크다.

주요 리스크:

- 페이지 파일 설정 미흡
- 대형 TTS 모델 로딩의 Windows 안정성
- 학습 성공 후 실제 탐지율 검증 미완

## 15. 미구현 또는 부분 구현 항목

다음 항목들은 아직 미구현이거나 부분 구현 상태다.

### 15-1. 외부 agent 확장

- external browser의 `find_map_route` 이관
- external desktop의 third-party app 확장
- BrowserUse / ComputerUse 완전 운영 전환

### 15-2. 음성

- wakeword 운영용 모델 완료
- wakeword 감지 후 자동 녹음 + 자동 STT + 자동 명령 확인의 완전한 안정화
- 일본어 STT 정확도 개선
- 실시간 STT의 Windows 환경 안정화

### 15-3. UI

- 디버그 영역과 사용자 영역 완전 분리
- 시니어 친화형 카드/스크롤 구조 재정리
- 운영 모드에서 trace 영역 축소 또는 숨김

### 15-4. 자동화 시나리오

- 파일 탐색기 시나리오 실사용 수준 검증
- 서드파티 앱 자동화
- 브라우저 외부 agent의 반복 benchmark 체계 강화

## 16. 현재 개발 정도 요약

아래는 전체 개발 정도를 거칠게 요약한 표다.

| 영역 | 개발 정도 |
|---|---|
| 제품 방향 정리 | 높음 |
| 오케스트레이터 구조 | 높음 |
| 프론트 제품화 | 중상 |
| trace / 관측성 | 높음 |
| internal baseline | 중상 |
| external browser | 중 |
| external desktop | 중하 |
| STT | 중 |
| wakeword runtime | 중 |
| wakeword 운영 배포 | 낮음 |
| map route 안정성 | 중 |

## 17. 지금 당장의 실제 상태 판단

가장 정직한 현재 평가는 다음과 같다.

1. VisionNavi는 더 이상 단순 데모 수준 프로젝트는 아니다.
2. external-first 구조, 프론트 사용자 모드, trace, popup, STT/wakeword 골격까지 포함한 상당한 통합이 이미 되어 있다.
3. 하지만 외부 agent의 반복 안정성, wakeword 운영 모델, route 완성도는 아직 미완이다.
4. 특히 현재 가장 큰 blocker는 wakeword 학습 환경과 external backend의 반복 성공률이다.

## 18. 다음 우선순위

### 18-1. 최우선

- Windows 페이지 파일을 D 드라이브까지 포함해 재설정
- wakeword 학습 재시도
- 운영용 wakeword 모델 최소 1개 성공 배포

### 18-2. 그 다음

- external browser benchmark 반복 측정
- external desktop Notepad 저장 검증 반복 개선
- 사용자 모드에서 디버그 UI 더 축소

### 18-3. 이후

- external browser의 route 시나리오 확대 여부 판단
- 서드파티 데스크톱 앱 자동화 확장
- 완전한 external-only 전환 가능성 재평가

## 19. 결론

VisionNavi는 현재 다음 문장으로 요약할 수 있다.

VisionNavi는 자연어 기반 브라우저/데스크톱 접근성 자동화를 목표로 하는 orchestrator이며, internal deterministic executor에서 external agent runtime 중심 구조로 넘어가는 전환 단계에 있다.

이미 구현된 기반은 충분히 크다.

- external-first backend 구조
- 사용자 모드 프론트
- STT / wakeword 골격
- popup 결과 요약
- trace / export
- internal / external 분리

하지만 아직 남아 있는 핵심 미완 요소도 분명하다.

- external runtime 반복 안정성
- wakeword 운영용 모델 학습 성공
- 길찾기와 복합 UI 시나리오의 안정화

따라서 현재 VisionNavi는 “방향이 정리된 통합형 접근성 자동화 프로젝트”이며, 다음 단계의 승부처는 기능 추가보다 외부 runtime 안정화와 음성 진입점 완성에 있다.
