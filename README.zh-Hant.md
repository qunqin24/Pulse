<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>不用逐一打開用量頁面，就知道 Claude Code、Codex、Cursor 還剩多少額度。</b><br>
  免費開源的 macOS 小工具，貼在螢幕邊緣，所有 AI 程式設計額度一眼看完。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/badge/%E4%B8%8B%E8%BC%89-000000?style=for-the-badge&logo=apple&logoColor=white" alt="下載 macOS 版 Pulse"></a>
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=black" alt="最新版本"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?label=%E4%B8%8B%E8%BC%89%E6%AC%A1%E6%95%B8&color=black" alt="下載次數"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?label=%E6%98%9F%E8%99%9F&color=black" alt="GitHub 星號"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/%E6%8E%88%E6%AC%8A-Apache%202.0-blue" alt="Apache 2.0 授權"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 或更新版本</b> · Apple 晶片與 Intel 通用 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <b>繁體中文</b> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" height="400" alt="貼在螢幕邊緣的 Pulse 懸浮膠囊">
  &nbsp;&nbsp;
  <img src="Docs/panel.webp" height="400" alt="指標移到圓環上，會打開一張卡片，列出每項額度與重置時間">
</p>

- **77 個服務，一眼看完**——Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Kiro、Grok、DeepSeek、Kimi Code 等等，每個都有自己的圓環。
- **沒有 Pulse 帳號，也沒有 Pulse 伺服器**——直接使用你已有的登入，不回傳任何東西。
- **只顯示真實數字**——每個用量百分比都是服務商自己回報的。少數估算會明確標示；服務商沒有提供數字時，Pulse 會直接說明，不去猜測。
- **原生、安靜**——以 Swift 與 SwiftUI 撰寫，macOS 26 上是 Liquid Glass。可以停靠在左側、右側、頂端，或底部 Dock 旁邊，閒置時收成一條細線，也可以只待在選單列裡。

**最近新增：** 在選單列顯示用量，並附上每個帳號的面板；額度重置後自動開始新視窗；會動的小機器人標記。[更新說明](https://github.com/qunqin24/Pulse/releases/latest)。

<p align="center">
  <img src="Docs/bot-mark.gif" width="300" alt="Pulse 動畫標記：每個環裡的小機器人會隨該帳號的狀態反應">
</p>

<p align="center">
  <sub>如果 Pulse 幫你躲過了一次突如其來的限額，按個 ⭐ 能讓更多人發現它。</sub>
</p>

---

## 核心特色

### 一目了然的狀態圓環
- **用量感知配色**：動態漸層會從綠色轉為琥珀、紅色，用盡時轉為深紅——也可依帳號自訂強調色。
- **即時工作狀態指示**：圓環邊緣帶有緩慢旋轉的光點，即時顯示 agent 是否正在產生回應（Claude Code、Codex、Kiro、智譜與 z.ai）。
- **時間視窗進度弧**：可選的外層副弧線，可選擇呈現目前速率限制視窗已經過或剩餘的時間比例。
- **倒數模式**：可在顯示已消耗額度（`75% used`）或剩餘額度（`25% left`）之間切換。

### 懸停詳情與智慧預測
- **完整額度明細**：將指標移到任一圓環上，即會展開詳情卡，列出所有回報的額度池、重設倒數與目前視窗狀態。
- **詳細卡片（可選，依帳號開啟）**：替你最常看的帳號打開。卡片會加上方案名稱與數字的更新時間；這台 Mac 的紀錄能算出金額時，每條額度下還會給出額度價值推算。凡是 Pulse 拿得到用量紀錄的服務，還會顯示今天、7 天、31 天的 token 用量，附 31 天長條圖、主力模型，快取命中率（紀錄裡分得清快取的才顯示），還會顯示提示快取還剩多久（Claude Code 依每次回覆記下的快取檔位計算，Codex 依 OpenAI 對 GPT-5.6 及之後模型保證的至少 30 分鐘計算）：卡片上顯示最快過期的那個對話，設定裡列出所有對話：z.ai、智譜用的是它們自己的帳號統計；Claude Code、Codex、Kimi Code、Grok、OpenCode、Cursor、Devin、Antigravity、Command Code、Copilot 讀的是這台 Mac 的紀錄，需要先開啟「Token 消耗」。
- **消耗速率與用盡預測（可選）**：開啟後會推估目前的使用節奏能否撐過本輪額度視窗，並在偵測到風險時顯示預估耗盡時間（ETA）。預設關閉。
- **釘選主要視窗**：可將最在意的額度釘在圓環上，或讓 Pulse 自動追蹤最接近用盡的那一條。

<p align="center">
  <img src="Docs/detailed-card.webp" width="620" alt="同一個 Codex 帳號的精簡卡片與詳細卡片">
</p>

### 原生流暢、安靜不打擾
- **多位置隨心停靠**：可停靠於螢幕左緣、右緣、頂部（選單列之上）或底部（Dock 旁邊），也可直向或橫向自由懸浮於任何位置。
- **多螢幕原生支援**：可將 Pulse 拖到任何外接螢幕；它會記住螢幕位置，螢幕中斷時也能優雅返回。開啟**跟隨使用中的螢幕**後，唯一的那條膠囊會自動移動到指標所在的螢幕。
- **自動收起**：閒置時自動收成極細的一條，消除干擾；只有在額度嚴重不足時，才泛紅發光。
- **可選的系統通知**：預設全部關閉，直到你開啟。額度越過 75/80/90/95%、服務商回報用盡、先前提醒過的視窗重新恢復、連續多次檢查失敗（面板正悄悄顯示較舊的數字），預付額度跌破你設定的金額，以及 Codex、Claude Code 或 DeepSeek 的官方狀態頁公布工具所依賴的服務發生故障時（只限你已開啟的服務），都會收到通知。每件事只說一次：開啟此功能時已經越線的額度會立刻告知一次，之後不再重複，直到它重設或變得更糟。
- **額度重設後自動開啟視窗（可選）**：Claude Code 和 Codex 的用量視窗，要等重設後你送出第一則訊息才開始計時。開啟後，Pulse 會在每次重設後不久、你設定的時段內，透過服務商自己的命令列工具送出一句「hi」，讓視窗從那一刻起算，而不是等你回來才開始。預設關閉；這不是 Anthropic 或 OpenAI 提供的功能，開啟前會請你確認：這麼做可能被視為規避用量限制。
- **全螢幕空間相容**：預設只留在你目前工作的 Space，全螢幕應用那邊交給它自己。
- **macOS 質感**：經典沉穩的純黑底板、適合明亮螢幕的淺色底板，或在 macOS 26+ 上使用原生 **Liquid Glass**。
- **動畫標記（可選）**：把供應商圖示換成一個會隨該帳號狀態反應的小機器人——正在工作、正在取數、額度用盡或閒置。預設關閉，逐個帳號開啟；八種人格、十八種形狀，顏色也可自行指定。
- **浮動膠囊選單與快速鍵**：右鍵點按浮動膠囊——或收合後的細條，按住 Control 點按同樣有效——可開啟含「設定…」與「結束 Pulse」的選單。在 **設定 › 一般 › 快速鍵** 中，可選擇將全域快速鍵指派給**開啟設定**與**顯示或隱藏面板**；兩者在你指定之前都保持空白。
- **選單列用量（可選）**：在選單列圖示旁顯示用得最多的那個圓環——或你指定的帳號——可選數字、迷你圓環，或並排顯示 5 小時與每週額度（`5h/9%  週/15%`），超過警示線時變紅。開啟「選單中顯示用量面板」後，點開圖示會顯示一個用量面板：概覽列出所有帳號，每個帳號一個分頁，含各項額度與重設時間、額度餘額、花費估算（開啟 Token 消耗時）與服務方官方用量頁連結。只想用選單列的話，可在同一選單裡關掉浮動面板。
- **六種介面語言**：英文、簡體中文、繁體中文、日文、韓文與俄文；大數單位會隨語言調整，分別為 K/M/B（英文與俄文）、万/亿、萬/億、万/億 與 만/억。

### 多帳號與本機帳本
- **多帳號支援**：可同時監看同一服務商的多個訂閱（Claude Code、Codex、Grok、Grok Bot），並排顯示並自訂標籤。
- **Token 消耗（僅限設定）**：預設關閉，在頁面頂端開啟後才讀取本機記錄，關閉即可停止掃描。支援本機日誌、資料庫與匯出檔，來源目錄涵蓋 **54 個用戶端來源**，包括 Gemini CLI、Cline、Roo Code、OpenClaw 與 GitHub Copilot。Cursor、Trae 等來源需要事先匯出或擷取記錄。這些來源與浮動膠囊上的 77 個配額服務商不同；各來源的支援程度與真實用戶端驗證情形不一。[來源與涵蓋範圍](Docs/token-spend-sources.md)。
- **清楚的用量估算**：預設開啟最近 7 天，並記住你選擇的區間。費用採用公開的 API 價格，而非訂閱費用。未知價格會保留為不可用，計數不完整或時間粒度較粗者會明確標示；沒有 token 計數器的來源會如實標示為不可用。
- **模型詳情與圖表**：點開單一模型可查看輸入／輸出／快取用量與估算費用、記錄足以支撐時的每日與每小時圖表、各 agent 的貢獻，以及可排序、分頁的明細表。將指標移到圖表上，即可讀取對應日期或小時及其 token 數量。無法取得的每日或每小時明細會標註為不可用。
- **月報與年報**：任選一個月或一年，用和 Token 消耗同一份本機紀錄產生一組適合分享的卡片：Token 總量與估算金額、與上個月相比的變化、每一天的日曆、你最常工作的時段、背後的模型、工具與專案、連續使用天數；填上每月訂閱花多少錢，還能看到訂閱回本了幾倍。每張卡都能存成圖片、複製或分享，六種語言都支援；專案名稱可以一鍵隱藏。從 Token 消耗頁面開啟；也可以開啟每月 1 日的提醒，告訴你上個月的月報好了。
- **七十七個服務商**：Claude Code、Codex、Kiro、Antigravity、Cursor、GitHub Copilot、Grok、Grok Bot、OpenCode Go、Kimi Code、Ollama Cloud、z.ai、Zhipu、MiniMax（國際與中國大陸）、Volcengine、Command Code、DeepSeek、Devin、小米 Coding Plan、sub2api、New API、V2EX、Qoder 與階躍星辰（StepFun）；另有 Abacus AI、Aixy、Alibaba Coding Plan、Alibaba Token Plan、Amp、Atlas Cloud、Augment Code、Bifrost、Chutes、ClawRouter、ClinePass、Codebuff、DeepInfra、DevPass、ElevenLabs、Factory、Gemini、GitKraken AI、Hugging Face、Hyper、IBM Bob、JetBrains AI、Kilo Code、LiteLLM、LLM API Key Proxy、LongCat、Manus、Mistral、Moonshot、Neuralwatt、Notion AI、Nous Portal、OpenAI API、Perplexity、Poe、Qwen Cloud、Raycast AI、Replicate、Sakana AI、Synthetic、T3 Chat、TypeSafe、v0、Venice、Vercel AI Gateway、Warp、Windsurf、xAI API、xKiro、Zed、ZenMux、ZoomMate。
- **可腳本化**：`Pulse --json` 印出最近一次讀數——方案、每一條額度、重設時間，以及數字有多舊——可接 tmux、sketchybar、Raycast 或 shell 提示字元。它只讀快取，所以高頻輪詢幾乎沒有成本。
- **開發者整合**：在設定中匯出 Raycast 擴充功能，以及可直接設定的 tmux、sketchybar 與 shell 指令碼。帳號連結會直接開啟對應頁面。[設定指南](Docs/integrations.md)。
- **擴充功能**：自己寫個小程式，就能讓 Pulse 顯示某個帳號的用量，例如公司內部的額度 API，不必再維護一份分支。開啟之前不會執行，Pulse 也不會交給它任何憑證。[撰寫說明](Docs/extensions.md)（英文）。
- **服務狀態**：Codex、Claude Code 和 DeepSeek 的設定頁照各自官方狀態頁的樣式顯示服務狀態——每一項現在是否正常、過去 90 天每天一根直條，以及狀態頁公布的可用率。開啟設定頁時讀取，開著時每 5 分鐘更新一次。
- **連線診斷**：查看實際的讀取來源、快取使用情形、最近一次檢查與備援結果。情境化操作可協助重新連線、重新登入或修正憑證；可複製不含帳號資訊與金鑰的診斷報告。
- **隱私優先**：Pulse 跑在你自己的 Mac 上，用你自己的登入狀態。它只發起四類連線，這裡列的就是全部——你原本就在使用的服務商、為「服務狀態」及其通知讀取的公開狀態頁（status.openai.com、status.claude.com、status.deepseek.com）、為 Token 消耗頁取得公開模型價格的 [models.dev](https://models.dev)，以及檢查更新的 GitHub/Sparkle。服務商請求、狀態頁、登入時的權杖交換與 models.dev 會使用「設定 › 網路與重新整理」中選擇的代理，Pulse 也會把手動代理傳給支援的輔助程序。Sparkle 的更新檢查一律跟隨 macOS 系統代理設定。

<p align="center">
  <img src="Docs/settings.webp" height="300" alt="Pulse 設定">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="帳號頁：每一條回報的額度、已用額度的估算價值，以及本機歷史">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="另一個帳號頁：方案、額度餘額與額度重設券">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="Token 消耗：總計、依類型的 token 與每日規律">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="Token 消耗：逐日、逐月、依 agent">
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
| **OpenCode Go** | API 金鑰，或現有的 OpenCode CLI 憑證；也可讀取瀏覽器裡 OpenCode 控制台的登入 | 讀取控制台登入後，詳細卡片還會顯示帳號的請求紀錄：所有裝置、所有應用程式，以及每次請求的實際花費 |
| **Kimi Code** | 直接使用 API 金鑰 | 在設定中設定 |
| **z.ai** | 直接使用 API 金鑰 | 國際站（`api.z.ai`） |
| **Zhipu** | 直接使用 API 金鑰，或已儲存的 GLM 工具憑證 | 中國大陸站（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | 直接使用 API 金鑰 | 支援國際站（`minimax.io`）與中國大陸站（`minimaxi.com`） |
| **Ollama Cloud** | 瀏覽器工作階段 cookie | 從瀏覽器本機讀取。詳見 [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine（火山引擎）** | `arkcli` 登入，否則使用貼上的 access-key 組（簽署 Top OpenAPI） | Ark Coding 與 Agent 方案；自動模式偏好貼上的金鑰而非 CLI |
| **Command Code** | 貼上的金鑰，否則使用 `cmd login` 已儲存的登入 | 以美元計價的額度餘額，含滾動 5 小時／每週限額；每月方案列標示為**估算** |
| **DeepSeek** | 貼上的金鑰；官方文件化的 `GET /user/balance` | 僅有預付餘額、沒有額度；圓環要對照什麼由你決定 |
| **Devin** | 無需輸入——讀取你的瀏覽器工作階段，無需鑰匙圈授權 | Devin 回報的每日與每週額度。沒有瀏覽器工作階段或貼上的憑證時，讀取應用程式存下的帶日期方案。端點失敗時只使用相符的端點快取，保留帳號與組織界線（[Docs/providers/devin.md](Docs/providers/devin.md)） |
| **小米 Coding Plan** | 無需輸入——讀取瀏覽器中已登入的工作階段，也可以手動貼上 `Cookie:` 標頭 | 小米 MiMo 主控台上的月度 token 額度，有結束時間就一併顯示。預付餘額會附在卡片上。帳號上沒有 Coding Plan 時會直接說明，而不是畫一個 0%（[Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)） |
| **sub2api** | 貼上的群組金鑰；閘道位址自行輸入 | 讀取自架 [sub2api](https://github.com/Wei-Shaw/sub2api) 閘道依群組核算的用量——餘額、配額、訂閱或速率限制視窗，視群組設定而定（[Docs/providers/sub2api.md](Docs/providers/sub2api.md)） |
| **New API** | 貼上的 `sk-` 金鑰；閘道位址自行輸入 | 讀取自架 [New API](https://github.com/QuantumNous/new-api) 閘道的餘額，依部署端設定的幣別顯示；不顯示百分比，因為回覆中的比例可能有兩種含義（[Docs/providers/newapi.md](Docs/providers/newapi.md)） |
| **V2EX** | 貼上的個人存取權杖 | AI Chat 滾動 5 小時的 token 配額，買過加油包再多畫一個環；視窗尚未開始時不顯示倒數（[Docs/providers/v2ex.md](Docs/providers/v2ex.md)） |
| **Qoder** | 無需輸入——讀取瀏覽器中 qoder.com 或 qoder.com.cn 的登入工作階段，也可以手動貼上 `Cookie:` 標頭 | 點數額度（方案加加購包），依 Qoder 回報的重設時間顯示；團隊方案的共用點數另外畫一個環，絕不相加；點數為零時會直接說明，而不是畫一個空環（[Docs/providers/qoder.md](Docs/providers/qoder.md)） |
| **階躍星辰（StepFun）** | 無需輸入——讀取瀏覽器中 platform.stepfun.com 或 platform.stepfun.ai 的登入工作階段，也可以手動貼上 `Cookie:` 標頭 | Step Plan：Token Plan 的每月 Credit 與加購包合成一個環，並顯示最早一批的到期日；舊版 Coding Plan 顯示 5 小時與每週兩個視窗；沒有訂閱時會直接說明，而不是畫一個環（[Docs/providers/stepfun.md](Docs/providers/stepfun.md)） |

### 更多服務商

參照 [CodexBar](https://github.com/steipete/CodexBar) 的實作撰寫。**尚未用真實帳號驗證**——如果某家用不了，歡迎[回報 issue](https://github.com/qunqin24/Pulse/issues)。各家的設定步驟見 [Docs/setup/](Docs/setup/)（英文），維護說明見 [Docs/providers/README.md](Docs/providers/README.md#profiled-providers)。

| 服務商 | 資料通道與驗證方式 | 顯示內容 |
|---|---|---|
| **Abacus AI** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 算力點數與帳單日期 |
| **Aixy** | 貼上的 API 金鑰 | 依週期的閘道預算 |
| **Alibaba Coding Plan** | 貼上的 API 金鑰 | 5 小時、每週、每月額度；先查國際站，再查中國站 |
| **Alibaba Token Plan** | 執行阿里 `bl` CLI，使用其已儲存的登入 | 5 小時、每週、每月用量比例 |
| **Amp** | 貼上的 API 金鑰 | 免費每日額度、方案額度與餘額 |
| **Atlas Cloud** | 貼上的 API 金鑰 | 餘額 |
| **Augment Code** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 本週期已用點數 |
| **Bifrost** | 貼上的金鑰；自架閘道位址由你填寫 | 虛擬金鑰的美元預算 |
| **Chutes** | 貼上的 API 金鑰 | 滾動視窗與每月額度 |
| **ClawRouter** | 貼上的 API 金鑰 | 每月預算 |
| **ClinePass** | 貼上的 API 金鑰 | 5 小時、每週、每月限額 |
| **Codebuff** | 貼上的金鑰，或讀取其 CLI 已儲存的登入 | 點數；使用 CLI 登入時另有每週限額 |
| **DeepInfra** | 貼上的 API 金鑰 | 餘額；在其後台設過限額時顯示花費比例 |
| **DevPass** | 貼上的 API 金鑰 | 每週高級額度與方案點數 |
| **ElevenLabs** | 貼上的 API 金鑰 | 本計費週期的字元額度 |
| **Factory** | 貼上的 API 金鑰 | 5 小時、每週、每月限額（舊計費為 Standard 與 Premium）；額外用量餘額 |
| **Gemini** | 讀取 Gemini CLI 儲存的登入，只讀、從不代為更新 | 每個模型的配額。該登入約一小時過期，只在近期用過 Gemini CLI 時有讀數 |
| **GitKraken AI** | 貼上的 token | 個人點數與共用池 |
| **Hugging Face** | 貼上的 token，或讀取 `hf auth login` 儲存的 | ZeroGPU 配額 |
| **Hyper** | 貼上的 API 金鑰 | Hypercredit 餘額 |
| **IBM Bob** | 貼上的 API 金鑰 | Bobcoins 相對團隊預算的用量 |
| **JetBrains AI** | 讀取 JetBrains IDE 儲存的配額檔案，不向任何地方傳送資料 | AI Assistant 配額；IDE 執行時才更新 |
| **Kilo Code** | 貼上的金鑰，或讀取其 CLI 已儲存的登入 | 點數餘額與 Kilo Pass |
| **LiteLLM** | 貼上的金鑰；自架閘道位址由你填寫 | 團隊與使用者預算 |
| **LLM API Key Proxy** | 貼上的金鑰；自架閘道位址由你填寫 | 依上游劃分的配額組 |
| **LongCat** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | Token 包額度與加油包 |
| **Manus** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 每日與每月點數 |
| **Mistral** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | API 與 Vibe 的每月額度，以及可用餘額 |
| **Moonshot** | 貼上的 API 金鑰 | Kimi 開放平台餘額，美元或人民幣 |
| **Neuralwatt** | 貼上的 API 金鑰 | kWh 訂閱、消費額度與餘額 |
| **Notion AI** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 滾動視窗與計費週期額度（Business 與 Enterprise） |
| **Nous Portal** | 讀取 Hermes Agent 儲存的登入，只讀 | 每月點數額度與餘額 |
| **OpenAI API** | 貼上的 API 金鑰 | 預付餘額（舊計費介面仍可用時） |
| **Perplexity** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | API 餘額 |
| **Poe** | 貼上的 API 金鑰 | 點數餘額 |
| **Qwen Cloud** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 5 小時、每週、每月比例，以及方案等級 |
| **Raycast AI** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | AI 點數與續期日期 |
| **Replicate** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 預付餘額 |
| **Sakana AI** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 5 小時與每週限額 |
| **Synthetic** | 貼上的 API 金鑰 | 5 小時、每週與搜尋額度 |
| **T3 Chat** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 4 小時視窗與每月用量 |
| **TypeSafe** | 貼上的 `Cookie:` 標頭 | 餘額與方案 |
| **v0** | 貼上的 API 金鑰 | 計費額度 |
| **Venice** | 貼上的 API 金鑰 | 餘額，美元或 DIEM |
| **Vercel AI Gateway** | 貼上的 API 金鑰 | 餘額 |
| **Warp** | 貼上的 API 金鑰 | 方案點數與附加點數 |
| **Windsurf** | 從 Chromium 核心瀏覽器讀取 windsurf.com 的登入 | 每日與每週配額 |
| **xAI API** | 以 `TeamID:ManagementKey` 格式填入 | 團隊預付餘額（xAI 已入帳的數額） |
| **xKiro** | 貼上的 API 金鑰 | 5 小時與每週視窗、每日免費 Token 與錢包 |
| **Zed** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 編輯預測額度與消費上限 |
| **ZenMux** | 貼上的管理金鑰 | 5 小時與 7 天配額，以及餘額 |
| **ZoomMate** | 讀取瀏覽器登入工作階段，或貼上 `Cookie:` 標頭 | 點數相對預算上限的用量 |

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
- **沒有 Pulse 後端**：你的 Mac 用你自己的登入狀態連線至你原本就在使用的服務商。同時會為「服務狀態」讀取 Codex、Claude Code 和 DeepSeek 的公開狀態頁（無需登入），為 Token 消耗頁從 [models.dev](https://models.dev) 取得公開模型價格，並向 GitHub/Sparkle 檢查應用程式更新。服務商請求、狀態頁、登入時的權杖交換與 models.dev 會使用「設定 › 網路與重新整理」中選擇的代理，Pulse 也會把手動代理傳給支援的輔助程序。Sparkle 的更新檢查一律跟隨 macOS 系統代理設定。
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

## 支持 Pulse

<p align="center">
  <sub>Pulse 是免費開源的，用愛發電、抽空更新。<br>如果它幫你躲過了一次突如其來的限流，歡迎請作者喝杯咖啡。</sub>
</p>

<p align="center">
  <a href="https://afdian.com/a/qunqin"><img src="https://img.shields.io/badge/%E6%84%9B%E7%99%BC%E9%9B%BB-%E8%AB%8B%E4%BD%9C%E8%80%85%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1-946CE6?style=for-the-badge" alt="在愛發電支持 Pulse"></a>
</p>

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
