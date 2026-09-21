<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>輕巧優雅的 macOS 螢幕邊緣 AI 編碼額度監視器。</b><br>
  即時掌握 Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Grok 等多平台的剩餘額度與速率限制。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="建置狀態"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/授權-Apache%202.0-blue" alt="開源授權"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?label=%E6%98%9F%E6%A8%99&color=black" alt="GitHub 星標"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?label=%E4%B8%8B%E8%BC%89%E6%AC%A1%E6%95%B8&color=black" alt="下載次數"></a>
  <a href="https://github.com/qunqin24/Pulse/issues"><img src="https://img.shields.io/github/issues/qunqin24/Pulse?label=%E5%95%8F%E9%A1%8C&color=black" alt="待處理問題"></a>
  <a href="https://github.com/qunqin24/Pulse/commits/main"><img src="https://img.shields.io/github/last-commit/qunqin24/Pulse?label=%E6%9C%80%E8%BF%91%E6%8F%90%E4%BA%A4&color=black" alt="最近提交"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或以上版本</b> · Apple 晶片與 Intel 通用 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <b>繁體中文</b> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="貼在螢幕邊緣的 Pulse 浮動膠囊">
</p>

Pulse 是一個停靠在螢幕邊緣的小巧懸浮監視器。它顯示各服務自己回報的剩餘額度——走的是該產品自己的用戶端通道，而不是 Pulse 的伺服器——用你已有的登入狀態，不回傳任何東西。畫面上的每個百分比，都來自服務商自己回報的數字。

**1.2.0 新功能：** 可選的動畫標記——用一個會隨該帳號狀態反應的小機器人取代供應商圖示，人格、形狀與顏色都可以自行設定。[版本說明](https://github.com/qunqin24/Pulse/releases/tag/v1.2.0)。

<p align="center">
  <img src="Docs/bot-mark.gif" width="340" alt="Pulse 動畫標記：每個環裡的小機器人會隨該帳號的狀態反應">
</p>

---

## 核心特色

### 一目了然的狀態圓環
- **用量感知配色**：動態漸層會從綠色轉為琥珀、紅色，用盡時轉為深紅——也可依帳號自訂強調色。
- **即時工作狀態指示**：圓環邊緣帶有緩慢旋轉的光點，即時顯示 agent 是否正在產生回應（Claude Code 與 Codex）。
- **時間視窗進度弧**：可選的外層副弧線，呈現目前速率限制視窗已經過的時間比例。
- **倒數模式**：可在顯示已消耗額度（`75% used`）或剩餘額度（`25% left`）之間切換。

### 懸停詳情與智慧預測
- **完整額度明細**：將指標移到任一圓環上，即會展開詳情卡，列出所有回報的額度池、重設倒數與目前視窗狀態。
- **消耗速率與用盡預測（可選）**：開啟後會推估目前的使用節奏能否撐過本輪額度視窗，並在偵測到風險時顯示預估耗盡時間（ETA）。預設關閉。
- **釘選主要視窗**：可將最在意的額度釘在圓環上，或讓 Pulse 自動追蹤最接近用盡的那一條。

### 原生流暢、安靜不打擾
- **多位置隨心停靠**：可停靠於螢幕左緣、右緣或頂部（選單列之上），也可自由懸浮於任何位置。
- **多螢幕原生支援**：可將 Pulse 拖到任何外接螢幕；它會記住螢幕位置，螢幕中斷時也能優雅返回。開啟**跟隨使用中的螢幕**後，唯一的那條膠囊會自動移動到指標所在的螢幕。
- **自動收起**：閒置時自動收成極細的一條，消除干擾；只有在額度嚴重不足時，才泛紅發光。
- **可選的系統通知**：預設全部關閉，直到你開啟。額度越過 75/80/90/95%、服務商回報用盡、先前提醒過的視窗重新恢復、連續多次檢查失敗（面板正悄悄顯示較舊的數字），以及預付額度跌破你設定的金額時，都會收到通知。每件事只說一次：開啟此功能時已經越線的額度會立刻告知一次，之後不再重複，直到它重設或變得更糟。
- **全螢幕空間相容**：預設只留在你目前工作的 Space，全螢幕應用那邊交給它自己。
- **macOS 質感**：經典沉穩的純黑底板，或在 macOS 26+ 上使用原生 **Liquid Glass**。
- **動畫標記（可選）**：把供應商圖示換成一個會隨該帳號狀態反應的小機器人——正在工作、正在取數、額度用盡或閒置。預設關閉，逐個帳號開啟；八種人格、十八種形狀，顏色也可自行指定。
- **浮動膠囊選單與快速鍵**：右鍵點按浮動膠囊——或收合後的細條，按住 Control 點按同樣有效——可開啟含「設定…」與「結束 Pulse」的選單。在 **設定 › 一般 › 快速鍵** 中，可選擇將全域快速鍵指派給**開啟設定**與**顯示或隱藏面板**；兩者在你指定之前都保持空白。
- **五種介面語言**：英文、簡體中文、繁體中文、日文與韓文；大數單位會隨語言調整，分別為 K/M/B、万/亿、萬/億、万/億 與 만/억。

### 多帳號與本機帳本
- **多帳號支援**：可同時監看同一服務商的多個訂閱（Claude Code、Codex、Grok、Grok Bot），並排顯示並自訂標籤。
- **Token 用量支出（僅限設定）**：預設關閉，在頁面頂端開啟後才讀取本機記錄，關閉即可停止掃描。支援本機日誌、資料庫與匯出檔，來源目錄涵蓋 **54 個用戶端來源**，包括 Gemini CLI、Cline、Roo Code、OpenClaw 與 GitHub Copilot。Cursor、Trae 等來源需要事先匯出或擷取記錄。這些來源與浮動膠囊上的 19 個配額服務商不同；各來源的支援程度與真實用戶端驗證情形不一。[來源與涵蓋範圍](Docs/token-spend-sources.md)。
- **清楚的用量估算**：預設開啟最近 7 天，並記住你選擇的區間。費用採用公開的 API 價格，而非訂閱費用。未知價格會保留為不可用，計數不完整或時間粒度較粗者會明確標示；沒有 token 計數器的來源會如實標示為不可用。
- **模型詳情與圖表**：點開單一模型可查看輸入／輸出／快取用量與估算費用、記錄足以支撐時的每日與每小時圖表、各 agent 的貢獻，以及可排序、分頁的明細表。將指標移到圖表上，即可讀取對應日期或小時及其 token 數量。無法取得的每日或每小時明細會標註為不可用。
- **二十個服務商**：Claude Code、Codex、Kiro、Antigravity、Cursor、GitHub Copilot、Grok、Grok Bot、OpenCode Go、Kimi Code、Ollama Cloud、z.ai、Zhipu、MiniMax（國際與中國大陸）、Volcengine、Command Code、DeepSeek、Devin 與小米 Coding Plan。
- **可腳本化**：`Pulse --json` 印出最近一次讀數——方案、每一條額度、重設時間，以及數字有多舊——可接 tmux、sketchybar、Raycast 或 shell 提示字元。它只讀快取，所以高頻輪詢幾乎沒有成本。
- **開發者整合**：在設定中匯出 Raycast 擴充功能，以及可直接設定的 tmux、sketchybar 與 shell 指令碼。帳號連結會直接開啟對應頁面。[設定指南](Docs/integrations.md)。
- **連線診斷**：查看實際的讀取來源、快取使用情形、最近一次檢查與備援結果。情境化操作可協助重新連線、重新登入或修正憑證；可複製不含帳號資訊與金鑰的診斷報告。
- **隱私優先**：Pulse 跑在你自己的 Mac 上，用你自己的登入狀態。它只發起三類連線，這裡列的就是全部——你原本就在使用的服務商、為 Token 用量支出頁取得公開模型價格的 [models.dev](https://models.dev)，以及檢查更新的 GitHub/Sparkle。服務商請求、登入時的權杖交換與 models.dev 會使用「設定 › 一般 › 網路」中選擇的代理，Pulse 也會把手動代理傳給支援的輔助程序。Sparkle 的更新檢查一律跟隨 macOS 系統代理設定。

<p align="center">
  <img src="Docs/panel.webp" height="300" alt="膠囊旁的用量詳情卡">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.webp" height="300" alt="Pulse 設定">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="帳號頁：每一條回報的額度、已用額度的估算價值，以及本機歷史">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="另一個帳號頁：方案、額度餘額與額度重設券">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="Token 用量支出：總計、依類型的 token 與每日規律">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="Token 用量支出：逐日、逐月、依 agent">
</p>

<p align="center">
  <img src="Docs/spend-agent.webp" height="290" alt="單一 agent 的支出">
  &nbsp;&nbsp;
  <img src="Docs/spend-model.webp" height="290" alt="單一模型的支出，依 token 類型計價">
</p>

---

## 支援的服務商與資料通道

Pulse 只呈現各服務回報的數字，每個百分比都來自那份回覆本身。各產品的通道不同（已文件化的用戶端 API、編輯器登入、本機 language server、貼上的金鑰）——並不是每一行都有公開的官方額度 API。貢獻者細節見 [Docs/providers/README.md](Docs/providers/README.md)。

| 服務商 | 資料通道與驗證方式 | 說明 |
|---|---|---|
| **Claude Code** | 帳號 OAuth 用量端點；自動備援至 Claude 桌面版工作階段與狀態列 | 讀取現有的 CLI／桌面版工作階段；無縫自動備援 |
| **Codex** | 用戶端用量端點；備援至 `codex app-server` | 直接讀取本機 Codex 憑證 |
| **Kiro** | Kiro CLI 原生 ACP 用量方法 | 沿用 Kiro CLI 已登入的工作階段；Pulse 從不讀取或保存 Kiro 憑證（[詳情](Docs/providers/kiro.md)） |
| **Antigravity** | 本機 Language Server（LSP） | 僅在 Antigravity 編輯器執行期間有效 |
| **Cursor** | Cursor 帳號用量摘要 API | 以現有編輯器登入顯示 fast 與 slow 兩個請求池 |
| **Grok** | Grok Build CLI 代理（`cli-chat-proxy.grok.com`） | 所有 Grok 產品共用一個統一的每週額度池 |
| **Grok Bot** | Cursor 儀表板 API | Cursor 訂閱內含的 xAI 額度 |
| **GitHub Copilot** | GitHub Device Code 驗證 | 只請求 `read:user` 這一項權限 |
| **OpenCode Go** | API 金鑰，或現有的 OpenCode CLI 憑證 | 可在設定中完整設定 |
| **Kimi Code** | 直接使用 API 金鑰 | 在設定中設定 |
| **z.ai** | 直接使用 API 金鑰 | 國際站（`api.z.ai`） |
| **Zhipu** | 直接使用 API 金鑰，或已儲存的 GLM 工具憑證 | 中國大陸站（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | 直接使用 API 金鑰 | 支援國際站（`minimax.io`）與中國大陸站（`minimaxi.com`） |
| **Ollama Cloud** | 瀏覽器工作階段 cookie | 從瀏覽器本機讀取。詳見 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine（火山引擎）** | `arkcli` 登入，否則使用貼上的 access-key 組（簽署 Top OpenAPI） | Ark Coding 與 Agent 方案；自動模式偏好貼上的金鑰而非 CLI |
| **Command Code** | 貼上的金鑰，否則使用 `cmd auth login` 已儲存的登入 | 以美元計價的額度餘額；每月方案列標示為**估算** |
| **DeepSeek** | 貼上的金鑰；官方文件化的 `GET /user/balance` | 僅有預付餘額、沒有額度；圓環要對照什麼由你決定 |
| **Devin** | 無需輸入——讀取你的瀏覽器工作階段，無需鑰匙圈授權 | Devin 回報的每日與每週額度。沒有瀏覽器工作階段或貼上的憑證時，讀取應用程式存下的帶日期方案。端點失敗時只使用相符的端點快取，保留帳號與組織界線（[Docs/providers/devin.md](Docs/providers/devin.md)） |
| **小米 Coding Plan** | 無需輸入——讀取瀏覽器中已登入的工作階段，也可以手動貼上 `Cookie:` 標頭 | 小米 MiMo 主控台上的月度 token 額度，有結束時間就一併顯示。預付餘額會附在卡片上。帳號上沒有 Coding Plan 時會直接說明，而不是畫一個 0%（[Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)） |

---

## 安裝

1. 從 [Releases](https://github.com/qunqin24/Pulse/releases/latest) 下載最新的 **`Pulse-x.y.z.dmg`**。
2. 開啟磁碟映像，將 **Pulse** 拖進你的 `Applications` 資料夾。
3. 首次啟動時，先選擇要監控的服務，預設全部不勾選。按 **「完成」** 後，Pulse 才會讀取所選服務的憑證並查詢用量。關閉選擇視窗會保持未啟用監控；也可以在設定中開啟任一服務。升級會保留原有選擇，對新支援且在這部 Mac 上找到的服務只詢問一次。
4. Pulse 常駐選單列。若選單列過於擁擠，右鍵點按浮動膠囊——或收合後的細條——並選擇 **「設定…」**；也可在 **設定 › 一般 › 快速鍵** 中為它指派全域快速鍵。

> [!NOTE]
> **macOS 首次啟動的 Gatekeeper 攔截**：<br>
> Pulse 是開放原始碼專案，沒有 Apple 開發者憑證。首次啟動時，macOS 可能會阻擋應用程式：
> - **方式 1（圖形介面）**：啟動 Pulse，關閉警示，打開 **系統設定 → 隱私權與安全性**，然後點按 **仍要打開**。
> - **方式 2（終端機）**：
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
>   *更新透過應用程式內的 Sparkle 提供。更新後，macOS 可能再次要求瀏覽器鑰匙圈存取權。*

---

## 隱私與安全

Pulse 以嚴格的「本機優先」安全原則設計：
- **沒有 Pulse 後端**：你的 Mac 用你自己的登入狀態連線至你原本就在使用的服務商。同時會為 Token 用量支出頁從 [models.dev](https://models.dev) 取得公開模型價格，並向 GitHub/Sparkle 檢查應用程式更新。服務商請求、登入時的權杖交換與 models.dev 會使用「設定 › 一般 › 網路」中選擇的代理，Pulse 也會把手動代理傳給支援的輔助程序。Sparkle 的更新檢查一律跟隨 macOS 系統代理設定。
- **本機憑證**：在產品本身如此運作的前提下，讀取開發工具已存放在本機的憑證（`~/.claude`、`~/.codex`、Cursor 儲存空間等）；部分服務商需要你在設定中輸入金鑰或登入。
- **加密的本機儲存**：手動輸入的 API 金鑰與工作階段權杖會加密，並嚴格存放於 Pulse 的本機應用程式目錄，權限僅限擁有者。
- **本機用量記錄**：Pulse 會讀取對話記錄、資料庫與匯出檔，以取得 token 數量，以及標題、工作目錄等這類工作階段中介資料。這些記錄可能包含對話文字；處理完全在你的 Mac 上完成，記錄也留在本機。Pulse 只讀取這些記錄，僅此而已。

---

## 從原始碼建置

Pulse 以原生 Swift 與 SwiftUI 建置。建置目前原始碼需要完整的 **Xcode**（而非 Command Line Tools），並包含 **macOS 26 SDK**；應用程式可在 **macOS 14+** 上執行。

```bash
# 複製儲存庫
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# 建置應用程式套件
./Scripts/bundle.sh

# 啟動
open build.noindex/Pulse.app
```

`swift run Pulse` 是不打包套件、快速建置並執行的方式，但通知與應用程式內更新只有在打包後的應用程式才能運作。工具鏈設定請見 [Docs/build-from-source.md](Docs/build-from-source.md)。發佈版本：[Docs/releasing.md](Docs/releasing.md)。

---

## 參與貢獻

文件如何組織、哪些行為不能回退、如何更新正確的頁面：[CONTRIBUTING.md](CONTRIBUTING.md)。主題文件索引：[Docs/README.md](Docs/README.md)。

---

## 設計來源

Pulse 的靈感來自 [**Vinz**（@hivinz_）](https://x.com/hivinz_/status/2092996055248126353) 於 2026 年 8 月在 X 上分享的 UI 概念。Pulse 是獨立實作，互動、功能、動畫與視覺細節均為自有。Vinz 與 Pulse 沒有關聯，也不為其負責。

---

## 授權

本專案依 [Apache 2.0](LICENSE) 授權。內含的第三方資源保留其各自的授權條款；詳見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## Star 成長曲線

<a href="https://star-history.com/#qunqin24/Pulse&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
  </picture>
</a>
