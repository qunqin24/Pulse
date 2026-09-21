<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>가볍고 우아한, 화면 가장자리에 두는 macOS용 AI 코딩 한도 모니터.</b><br>
  Claude Code, Codex, Cursor, GitHub Copilot, Antigravity, Grok 등의 한도와 남은 사용량을 실시간으로 확인하세요.
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="최신 릴리스"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="CI 빌드"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="라이선스"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?color=black" alt="GitHub 스타"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?color=black" alt="다운로드 수"></a>
  <a href="https://github.com/qunqin24/Pulse/issues"><img src="https://img.shields.io/github/issues/qunqin24/Pulse?color=black" alt="열린 이슈"></a>
  <a href="https://github.com/qunqin24/Pulse/commits/main"><img src="https://img.shields.io/github/last-commit/qunqin24/Pulse?color=black" alt="마지막 커밋"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 이상</b> · Apple Silicon 및 Intel 유니버설 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <a href="README.ja.md"><b>日本語</b></a> · <b>한국어</b></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="화면 가장자리에 붙어 있는 Pulse 플로팅 레일">
</p>

Pulse는 화면 가장자리에 깔끔하게 자리 잡는, 눈에 띄지 않는 플로팅 모니터입니다. 각 서비스가 보고하는 남은 한도를 그대로 보여 줍니다——사용하는 것은 그 제품 자체의 클라이언트 경로이고 Pulse 서버가 아닙니다——이미 가지고 있는 로그인을 그대로 사용하며, 무엇도 되돌려 보내지 않습니다. 화면에 보이는 사용률은 모두 서비스가 직접 보고한 숫자입니다.

**1.2.0의 새로운 기능:** 제공자 로고 대신 사용할 수 있는 애니메이션 마크. 해당 계정의 상태에 반응하는 작은 봇이며 성격, 모양, 색상을 지정할 수 있습니다. [릴리스 노트](https://github.com/qunqin24/Pulse/releases/tag/v1.2.0).

<p align="center">
  <img src="Docs/bot-mark.gif" width="340" alt="Pulse 애니메이션 마크: 각 링의 봇이 해당 계정의 상태에 반응합니다">
</p>

---

## 주요 기능

### 한눈에 보는 상태 링
- **사용량에 반응하는 색상**: 링은 사용률에 따라 부드럽게 색이 바뀌며(초록 → 노랑 → 빨강 → 다 쓰면 짙은 빨강), 계정마다 고유한 강조 색을 지정할 수도 있습니다.
- **활성 턴 표시**: 링 가장자리를 도는 작은 점이 에이전트가 지금 실시간으로 응답을 생성 중인지 보여 줍니다(Claude Code와 Codex).
- **경과 창 호**: 선택 사항인 바깥쪽 보조 호가 현재 한도 창에서 얼마나 시간이 지났는지 보여 줍니다.
- **카운트다운 모드**: 사용한 비율(`75% used`)과 남은 양(`25% left`)을 전환할 수 있습니다.

### 호버 상세와 스마트 예측
- **한도 전체 내역**: 링 위에 포인터를 올리면 보고된 모든 한도 풀, 초기화 카운트다운, 현재 창 상태를 담은 상세 카드가 열립니다.
- **소진 속도 예측(선택 사항)**: 켜면 지금 속도로 이번 한도 창을 버틸 수 있을지 추정하고, 위험이 감지되면 예상 소진 시각(ETA)을 보여 줍니다. 기본값은 꺼짐입니다.
- **주요 창 고정**: 가장 중요한 한도를 링에 고정하거나, 소진에 가장 가까운 한도를 Pulse가 자동으로 따라가게 할 수 있습니다.

### 네이티브하고 매끄럽고 방해되지 않게
- **자유로운 가장자리 도킹**: 화면 왼쪽, 오른쪽, 위쪽(메뉴 막대 위)에 도킹하거나 어디든 자유롭게 띄울 수 있습니다.
- **다중 모니터 지원**: Pulse를 아무 보조 디스플레이로나 끌어다 놓을 수 있고, 화면 위치를 기억하며 연결이 끊기면 자연스럽게 돌아옵니다. **활성 디스플레이 따라가기**를 켜면 하나뿐인 레일이 포인터가 있는 화면으로 스스로 옮겨 갑니다.
- **자동 접기**: 유휴 상태에서는 아주 가느다란 선으로 접혀 방해하지 않으며, 한도가 심각하게 부족할 때만 붉게 빛납니다.
- **선택적 알림**: 알리기를 원하는 것만 골라서 켭니다. 한도가 75/80/90/95%를 넘을 때, 제공업체가 다 썼다고 보고할 때, 경고했던 창이 돌아올 때, 검사가 여러 번 연달아 실패해(패널이 조용히 오래된 숫자를 보여 줄 때), 그리고 선불 잔액이 설정한 금액 아래로 떨어질 때 알려 줍니다. 각각 한 번만 말합니다: 이 기능을 켤 때 이미 선을 넘은 한도는 곧바로 한 번 알리고, 그 뒤로는 초기화될 때, 또는 더 나빠질 때 다시 알립니다.
- **Spaces에 친화적**: 기본적으로 지금 작업 중인 Space에 머무르며, 전체 화면 앱은 그대로 둡니다.
- **macOS 미학**: 차분한 무광 블랙 표면, 또는 macOS 26+의 네이티브 **Liquid Glass**.
- **애니메이션 마크(선택)**: 제공자 로고를 해당 계정의 상태에 반응하는 작은 봇으로 바꿉니다. 작업 중, 조회 중, 소진, 대기 상태를 나타냅니다. 기본값은 꺼짐이며 계정별로 켤 수 있고, 8가지 성격과 18가지 모양, 원하는 색상을 지정할 수 있습니다.
- **레일 메뉴와 단축키**: 플로팅 레일——또는 접힌 가느다란 선——을 오른쪽 클릭하면(Control 키를 누른 채 클릭해도 됩니다) 설정과 종료가 있는 메뉴가 열립니다. **설정 › 일반 › 단축키**에서 **설정 열기**와 **패널 표시 전환**에 전역 단축키를 선택적으로 지정할 수 있으며, 둘 다 지정하기 전까지는 비어 있습니다.
- **다섯 가지 인터페이스 언어**: 영어, 중국어 간체, 중국어 번체, 일본어, 한국어를 지원하며, 언어에 맞는 큰 수 단위를 씁니다: 각각 K/M/B, 万/亿, 萬/億, 万/億, 만/억.

### 다중 계정과 로컬 원장
- **다중 계정 지원**: 같은 제공업체의 여러 구독(Claude Code, Codex, Grok, Grok Bot)을 나란히 모니터링하고 라벨을 붙일 수 있습니다.
- **토큰 지출(설정에서만)**: 기본값은 꺼짐입니다. 페이지 상단에서 켜면 로컬 기록을 읽기 시작하며, 끄면 스캔을 중단합니다. **54개 클라이언트 소스**의 로컬 로그, 데이터베이스, 내보내기 파일을 지원합니다. Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot 등이 포함됩니다. Cursor, Trae 및 기타 내보내기 소스는 사전 내보내기나 캡처가 필요합니다. 이는 레일의 19개 할당량 제공업체와는 다르며, 지원 범위와 실제 클라이언트 검증 여부는 소스마다 다릅니다. [소스와 지원 범위](Docs/token-spend-sources.md).
- **명확한 사용량 추정**: 기본적으로 최근 7일을 보여 주며 선택한 기간을 기억합니다. 비용은 공개된 API 가격으로 계산한 추정치이며 구독 청구액이 아닙니다. 가격을 알 수 없거나 집계가 불완전한 경우, 세부 시간 정보가 없는 경우에는 이를 표시합니다. 토큰 수 정보가 없는 소스는 그대로 표시합니다.
- **모델 상세와 차트**: 모델을 열면 입력/출력/캐시 수치와 추정 비용, 기록이 뒷받침하는 일별·시간별 차트, 에이전트별 기여, 정렬과 페이지 이동이 가능한 상세 표를 볼 수 있습니다. 차트를 가리키면 해당 날짜나 시간과 토큰 수를 읽을 수 있습니다. 제공되지 않는 일별·시간별 상세는 0이 아니라 사용할 수 없음으로 표시됩니다.
- **스무 개 제공업체**: Claude Code, Codex, Kiro, Antigravity, Cursor, GitHub Copilot, Grok, Grok Bot, OpenCode Go, Kimi Code, Ollama Cloud, z.ai, Zhipu, MiniMax(국제 및 중국 본토), Volcengine, Command Code, DeepSeek, Devin, Xiaomi Coding Plan.
- **스크립트 가능**: `Pulse --json`이 마지막으로 읽은 값——플랜, 모든 한도, 초기화 시각, 숫자가 얼마나 오래됐는지——을 출력합니다. tmux, sketchybar, Raycast, 셸 프롬프트에 쓰세요. 캐시만 읽으므로 폴링 비용이 들지 않습니다.
- **개발자 통합**: 설정에서 Raycast 확장과 바로 설정할 수 있는 tmux, sketchybar, 셸 스크립트를 내보냅니다. 계정 링크는 해당 패널을 바로 엽니다. [설정 가이드](Docs/integrations.md).
- **연결 진단**: 실제 읽기 출처, 캐시 사용, 최근 검사와 대체 결과를 확인합니다. 상황에 맞는 작업으로 다시 연결, 다시 로그인, 자격 증명 수정을 할 수 있고, 계정 정보나 비밀 없는 진단 보고서를 복사할 수 있습니다.
- **개인정보 우선**: Pulse는 여러분의 Mac에서, 여러분 자신의 로그인으로 동작합니다. 연결하는 곳은 세 가지뿐이며 여기 적은 것이 전부입니다 — 이미 사용 중인 제공업체, 토큰 지출 패널의 공개 모델 가격을 가져오는 [models.dev](https://models.dev), 그리고 앱 업데이트를 확인하는 GitHub/Sparkle. 제공업체 요청, 로그인 토큰 교환, models.dev에는 설정 › 일반 › 네트워크에서 선택한 프록시가 사용되며, 수동 프록시는 지원되는 도우미 프로세스에도 전달됩니다. Sparkle 업데이트 확인은 항상 macOS 시스템 프록시 설정을 따릅니다.

<p align="center">
  <img src="Docs/panel.webp" height="300" alt="레일 옆에 열리는 사용량 상세 카드">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.webp" height="300" alt="Pulse 설정">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="계정 패널: 보고된 모든 한도, 사용한 만큼의 추정 가치, 로컬 기록">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="또 다른 계정 패널: 플랜, 크레딧 잔액, 보고된 한도 초기화 쿠폰">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="토큰 지출: 합계, 종류별 토큰, 일별 패턴">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="토큰 지출: 일별, 월별, 에이전트별">
</p>

<p align="center">
  <img src="Docs/spend-agent.webp" height="290" alt="에이전트 하나의 지출">
  &nbsp;&nbsp;
  <img src="Docs/spend-model.webp" height="290" alt="모델 하나의 지출, 토큰 종류별 가격 계산">
</p>

---

## 지원 제공업체와 데이터 경로

Pulse는 각 서비스가 보고하는 숫자를 그대로 보여 줍니다. 화면의 사용률은 그 응답 자체에 담긴 숫자입니다. 경로는 제품마다 다릅니다(문서화된 클라이언트 API, 편집기 로그인, 로컬 language server, 붙여 넣은 키)——모든 행에 공개된 공식 할당량 API가 있는 것은 아닙니다. 기여자를 위한 세부 사항: [Docs/providers/README.md](Docs/providers/README.md).

| 제공업체 | 데이터 경로와 인증 방식 | 비고 |
|---|---|---|
| **Claude Code** | 계정 OAuth 사용량 엔드포인트. Claude 데스크톱 세션과 상태 표시줄로 자동 대체 | 기존 CLI/데스크톱 세션을 읽고 매끄럽게 자동 대체 |
| **Codex** | 클라이언트 사용량 엔드포인트. `codex app-server`로 대체 | 로컬 Codex 자격 증명을 직접 읽음 |
| **Kiro** | Kiro CLI 네이티브 ACP 사용량 메서드 | Kiro CLI에 로그인된 세션을 사용. Pulse는 Kiro 자격 증명을 읽거나 저장하지 않음([자세히](Docs/providers/kiro.md)) |
| **Antigravity** | 로컬 Language Server(LSP) | Antigravity 편집기가 실행 중일 때만 유효 |
| **Cursor** | Cursor 계정 사용량 요약 API | 기존 편집기 로그인에서 fast와 slow 요청 풀을 표시 |
| **Grok** | Grok Build CLI 프록시(`cli-chat-proxy.grok.com`) | 모든 Grok 제품이 공유하는 단일 주간 풀 |
| **Grok Bot** | Cursor 대시보드 API | Cursor 구독에 포함된 xAI 한도 |
| **GitHub Copilot** | GitHub Device Code 인증 | 최소한의 `read:user` 범위만 요청하고 저장소에는 접근하지 않음 |
| **OpenCode Go** | API 키 또는 기존 OpenCode CLI 자격 증명 | 설정에서 완전히 구성 가능 |
| **Kimi Code** | API 키 직접 입력 | 설정에서 구성 |
| **z.ai** | API 키 직접 입력 | 국제 스토어(`api.z.ai`) |
| **Zhipu** | API 키 직접 입력 또는 저장된 GLM 도구 자격 증명 | 중국 본토 스토어(`open.bigmodel.cn`) |
| **MiniMax / MiniMax CN** | API 키 직접 입력 | 국제(`minimax.io`)와 중국 본토(`minimaxi.com`) 지원 |
| **Ollama Cloud** | 브라우저 세션 쿠키 | 브라우저에서 로컬로 읽음. [Docs/ollama-cloud.md](Docs/ollama-cloud.md) 참고 |
| **Volcengine** | `arkcli` 로그인, 없으면 붙여 넣은 액세스 키 쌍(Top OpenAPI 서명) | Ark Coding 및 Agent 플랜. 자동에서는 CLI보다 붙여 넣은 키를 우선 |
| **Command Code** | 붙여 넣은 키, 없으면 `cmd auth login`이 이미 저장한 로그인 | 달러 단위 크레딧 잔액. 월간 플랜 행은 **추정**으로 표시 |
| **DeepSeek** | 붙여 넣은 키. 문서화된 `GET /user/balance` | 선불 잔액만 있고 한도는 없음. 링이 무엇을 기준으로 삼을지는 사용자가 선택 |
| **Devin** | 입력할 것이 없음——브라우저 세션을 읽고 키체인 프롬프트도 없음 | Devin이 보고하는 일간·주간 한도. 브라우저 세션이나 붙여 넣은 자격 증명이 없으면 앱이 저장한 날짜별 플랜을 읽음. 엔드포인트 실패 시 일치하는 엔드포인트 캐시만 사용해 계정과 조직 경계를 유지([Docs/providers/devin.md](Docs/providers/devin.md)) |
| **Xiaomi Coding Plan** | 입력할 것이 없음——로그인된 브라우저 세션을 읽음. `Cookie:` 헤더를 붙여 넣을 수도 있음 | Xiaomi MiMo 콘솔의 월간 토큰 한도. 기간 종료가 보고되면 함께 표시. 선불 잔액은 카드에 한 줄로 덧붙음. 플랜이 없는 계정은 0%를 그리지 않고 그렇다고 알림([Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)) |

---

## 설치 및 빠른 시작

1. [Releases](https://github.com/qunqin24/Pulse/releases/latest)에서 최신 **`Pulse-x.y.z.dmg`**를 내려받습니다.
2. 디스크 이미지를 열고 **Pulse**를 `Applications` 폴더로 끌어다 놓습니다.
3. 처음 실행하면 모니터링할 서비스를 선택합니다. 처음에는 모두 선택되지 않으며, **완료**를 누른 뒤에만 선택한 서비스의 인증 정보를 읽고 사용량을 확인합니다. 선택 창을 닫으면 모니터링을 시작하지 않습니다. 설정에서 서비스를 켜도 됩니다. 업데이트 후에도 기존 선택은 유지되며, 새로 지원하는 서비스가 Mac에서 발견되면 한 번만 추가 여부를 묻습니다.
4. Pulse는 메뉴 막대에 있습니다. 메뉴 막대가 복잡하다면 플로팅 레일——또는 접힌 가느다란 선——을 오른쪽 클릭해 **설정…**을 고르세요. **설정 › 일반 › 단축키**에서 전역 단축키를 지정할 수도 있습니다.

> [!NOTE]
> **macOS 첫 실행(Gatekeeper)**:<br>
> Pulse는 Apple Developer 인증서가 없는 오픈 소스 프로젝트입니다. 첫 실행 시 macOS가 앱을 막을 수 있습니다:
> - **방법 1(GUI)**: Pulse를 실행하고 경고를 닫은 뒤, **시스템 설정 → 개인정보 보호 및 보안**을 열고 **그래도 열기**를 클릭합니다.
> - **방법 2(터미널)**:
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
>   *업데이트는 앱 안에서 Sparkle로 제공됩니다. 업데이트 후 macOS가 브라우저 키체인 접근을 다시 요청할 수 있습니다.*

---

## 개인정보와 보안

Pulse는 엄격한 로컬 우선 보안 원칙으로 설계되었습니다:
- **Pulse 백엔드 없음**: 여러분의 Mac이 여러분 자신의 로그인으로 이미 사용 중인 제공업체에 연결합니다. 또한 토큰 지출 패널을 위해 [models.dev](https://models.dev)에서 공개 모델 가격을 가져오고 GitHub/Sparkle에서 앱 업데이트를 확인합니다. 제공업체 요청, 로그인 토큰 교환, models.dev에는 설정 › 일반 › 네트워크에서 선택한 프록시가 사용되며, 수동 프록시는 지원되는 도우미 프로세스에도 전달됩니다. Sparkle 업데이트 확인은 항상 macOS 시스템 프록시 설정을 따릅니다.
- **로컬 자격 증명**: 제품이 그렇게 동작하는 경우, 개발 도구가 이미 로컬에 저장한 자격 증명(`~/.claude`, `~/.codex`, Cursor 저장소 등)을 읽습니다. 일부 제공업체는 설정에서 입력하는 키나 로그인이 필요합니다.
- **암호화된 로컬 저장**: 직접 입력한 API 키와 세션 토큰은 암호화되어 Pulse의 로컬 애플리케이션 디렉터리에 소유자 전용 권한으로만 저장됩니다.
- **로컬 사용량 기록**: Pulse는 토큰 수와 제목, 작업 디렉터리 같은 세션 메타데이터를 얻기 위해 대화 기록, 데이터베이스, 내보내기 파일을 읽습니다. 이 기록에는 대화 텍스트가 들어 있을 수 있으며, 처리는 여러분의 Mac에서만 이루어지고 기록도 그대로 남습니다. Pulse가 읽는 것은 이 기록들뿐입니다.

---

## 소스에서 빌드

Pulse는 네이티브 Swift와 SwiftUI로 빌드됩니다. 현재 소스를 빌드하려면 전체 **Xcode**(Command Line Tools가 아님)와 **macOS 26 SDK**가 필요하며, 앱은 **macOS 14+**에서 실행됩니다.

```bash
# 저장소 복제
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# 앱 번들 빌드
./Scripts/bundle.sh

# 실행
open build.noindex/Pulse.app
```

`swift run Pulse`는 번들 없이 빠르게 빌드하고 실행하는 방법이지만, 알림과 앱 내 업데이트는 번들 앱에서만 동작합니다. 툴체인 설정은 [Docs/build-from-source.md](Docs/build-from-source.md)를 참고하세요. 릴리스 배포: [Docs/releasing.md](Docs/releasing.md).

---

## 기여

저장소 문서가 어떻게 조직되는지, 무엇이 퇴행하면 안 되는지, 올바른 페이지를 어떻게 갱신하는지: [CONTRIBUTING.md](CONTRIBUTING.md). 주제별 문서 지도: [Docs/README.md](Docs/README.md).

---

## 디자인 출처

Pulse는 2026년 8월 [**Vinz**(@hivinz_)](https://x.com/hivinz_/status/2092996055248126353)가 X에 공유한 UI 콘셉트에서 영감을 받았습니다. Pulse는 독립적인 구현이며, 인터랙션, 기능, 애니메이션, 시각적 디테일은 모두 자체적으로 만든 것입니다. Vinz는 Pulse와 아무런 제휴 관계가 없으며 책임지지 않습니다.

---

## 라이선스

[Apache 2.0](LICENSE)에 따라 라이선스됩니다. 함께 포함된 서드파티 자산은 각자의 라이선스를 유지합니다. 자세한 내용은 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요.

---

## Star 추이

<a href="https://star-history.com/#qunqin24/Pulse&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
  </picture>
</a>
