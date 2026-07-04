# VisionNavi LiveKit WakeWord 설정

VisionNavi는 이제 `livekit-wakeword` 기반 웨이크워드 엔진을 사용할 수 있도록 백엔드 API와 프론트 연동 골격이 들어가 있습니다.

## 현재 포함된 항목

- 오케스트레이터 API
  - `GET /pipeline/wakeword/status`
  - `POST /pipeline/wakeword/start`
  - `POST /pipeline/wakeword/stop`
  - `POST /pipeline/wakeword/acknowledge`
- 프론트엔드 사용자 모드 연동
  - 설정에서 웨이크워드 사용 여부 저장
  - 홈 화면에서 호출어 대기 시작/종료
  - 감지되면 웨이크워드 리스너를 멈추고 실제 음성 명령 녹음으로 전환
- 런타임 manifest
  - `runtime/wakewords/manifest.json`
- 기본 학습 설정
  - `runtime/wakewords/configs/ko_nabiya.yaml`
  - `runtime/wakewords/configs/ko_hey_nabi.yaml`
  - `runtime/wakewords/configs/ja_nee_navi.yaml`
  - `runtime/wakewords/configs/ja_navisan.yaml`

## 아직 필요한 것

현재 저장소에는 실제 ONNX 모델 파일이 들어 있지 않습니다.

아래 경로에 모델을 준비해야 실제 감지가 동작합니다.

- `runtime/wakewords/models/ko_nabiya.onnx`
- `runtime/wakewords/models/ko_hey_nabi.onnx`
- `runtime/wakewords/models/ja_nee_navi.onnx`
- `runtime/wakewords/models/ja_navisan.onnx`

## 설치

오케스트레이터 가상환경에서 다음 패키지가 필요합니다.

```powershell
cd C:\Users\USER\Documents\VisionNavi\orchestrator
.venv\Scripts\activate
pip install -r requirements.txt
```

`livekit-wakeword` 학습까지 하려면 공식 문서 기준으로 추가 도구가 필요합니다.

- `eSpeak-NG`
- `ffmpeg`
- `sox`

Windows 예시:

```powershell
winget install eSpeak-NG.eSpeak-NG
winget install Gyan.FFmpeg
winget install ChrisBagwell.SoX
```

## 학습 예시

한국어 `나비야` 모델 학습 예시:

```powershell
cd C:\Users\USER\Documents\VisionNavi\orchestrator
.venv\Scripts\activate
pip install "livekit-wakeword[train,eval,export,voxcpm]"
livekit-wakeword setup --config ..\runtime\wakewords\configs\ko_nabiya.yaml
livekit-wakeword run ..\runtime\wakewords\configs\ko_nabiya.yaml
```

학습 결과로 나온 ONNX 파일을 아래처럼 복사합니다.

```powershell
Copy-Item .\artifacts\ko_nabiya\export\ko_nabiya.onnx ..\runtime\wakewords\models\ko_nabiya.onnx
```

일본어 모델도 같은 방식으로 진행합니다.

## 운영 방식

- 한국어 UI일 때는 한국어 호출어 profile을 사용
- 일본어 UI일 때는 일본어 호출어 profile을 사용
- 호출어가 감지되면:
  1. 백엔드 wakeword listener 감지
  2. 프론트가 status polling으로 감지 확인
  3. 프론트가 detection acknowledge
  4. 백엔드 listener 중지
  5. 프론트가 실제 명령 녹음 시작

## 주의

- `ナビ`처럼 너무 짧은 호출어는 오탐 가능성이 높아 기본 세트에서 제외했습니다.
- 사용자 설정에서 완전히 새로운 호출어를 즉시 반영하는 구조는 아닙니다.
- 새로운 호출어를 쓰려면 해당 호출어용 ONNX 모델을 추가 학습해야 합니다.
