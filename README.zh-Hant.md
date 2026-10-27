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
  <sub><b>macOS 14 Sonoma 或更新版本</b> · Apple 晶片與 Intel 通用 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <b>繁體中文</b> · <a href="README.ja.md"><b>日本語</b></a> · <a href="README.ko.md"><b>한국어</b></a> · <a href="README.ru.md"><b>Русский</b></a></sub>
</p>

<p align="center">
  <img src="Docs/images/demo.gif" height="400" alt="貼在螢幕邊緣的 Pulse 懸浮膠囊">
  &nbsp;&nbsp;
  <img src="Docs/images/panel.webp" height="400" alt="指標移到圓環上，會打開一張卡片，列出每項額度與重置時間">
</p>

- **77 個服務，一眼看完**——Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Kiro、Grok、DeepSeek、Kimi Code 等等，每個都有自己的圓環。
- **沒有 Pulse 帳號，也沒有 Pulse 伺服器**——直接使用你已有的登入，不回傳任何東西。
- **只顯示真實數字**——每個用量百分比都是服務商自己回報的。少數估算會明確標示；服務商沒有提供數字時，Pulse 會直接說明，不去猜測。
- **原生、安靜**——以 Swift 與 SwiftUI 撰寫，macOS 26 上是 Liquid Glass。可以停靠在左側、右側、頂端，或底部 Dock 旁邊，閒置時收成一條細線，也可以只待在選單列裡。

**最近新增：** 在選單列顯示用量，並附上每個帳號的面板；額度重置後自動開始新視窗；會動的小機器人標記。[更新說明](https://github.com/qunqin24/Pulse/releases/latest)。

<p align="center">
  <img src="Docs/images/bot-mark.gif" width="300" alt="Pulse 動畫標記：每個環裡的小機器人會隨該帳號的狀態反應">
</p>

<p align="center">
  <sub>如果 Pulse 幫你躲過了一次突如其來的限額，按個 ⭐ 能讓更多人發現它。</sub>
</p>

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

## 核心特色

### 一眼看清的圓環
- **顏色隨用量變化**——從綠到琥珀再到紅，也可以為每個帳號設一種自己的顏色。
- **已用或剩餘**——顯示 `75% 已用` 或 `25% 剩餘`，可加一圈時鐘弧，表示目前視窗已經過去多少。
- **即時動態**——agent 工作時圓環上有轉動的小點；可選的小機器人會隨每個帳號的狀態做動作。

### 指向圓環就能看細節
- **每條額度與它的重設時間**，都在一張卡片上，進度條可選連續或分段。
- **詳細卡片**——方案、讀取時間、每條額度值多少錢，以及本機紀錄裡最近的用量。
- **消耗速度預測**——照目前的速度會在視窗重設前用完時提醒你。
- **選單列**——把用得最多的圓環顯示成數字、小圓環或並排的額度，可選開啟用量面板。

<p align="center">
  <img src="Docs/images/detailed-card.webp" width="620" alt="同一個 Codex 帳號的精簡卡片與詳細卡片">
</p>

### 不打擾你
- **停在哪都行**——左、右、頂部、Dock 旁邊，或任意位置；閒置時收成一條細線。
- **自己選的通知**——額度越線、用盡、重設、連續讀取失敗、餘額不足、服務商故障。
- **六種介面語言**——英文、簡體中文、繁體中文、日文、韓文與俄文。
- **可選功能**——全域快速鍵、跟隨目前的顯示器、截圖時隱藏。

### 消耗、狀態及其他
- **Token 消耗**——54 種本機用戶端用了多少，依公開 API 價格估算，可依天、模型與 agent 查看，統計區間可以自己選。
- **用你的貨幣顯示估算**——美元、人民幣、港幣、新臺幣、日圓、韓元或盧布。
- **用量報告**——用同一份紀錄產生、適合分享的日報、週報、月報與年報卡片。
- **服務狀態**——44 個服務商的官方狀態頁，發生故障時可以通知你。
- **連線診斷**——每個數字從哪來，以及伺服器的原始回應。
- **進階**——同一服務商多個帳號、接入自己資料來源的擴充功能、供腳本使用的 `Pulse --json`。

<p align="center">
  <img src="Docs/images/spend.webp" height="290" alt="Token 消耗：總計、依類型的 token 與每日規律">
  &nbsp;&nbsp;
  <img src="Docs/images/spend-history.webp" height="290" alt="Token 消耗：逐日、逐月、依 agent">
</p>

**完整說明**（英文）：[Docs/features.md](Docs/features.md)。

---

## 支援的服務商與資料通道

77 個服務，每個都依產品本身的方式讀取——它自己的用量介面、編輯器的登入狀態、本機 Language Server，或你貼上的金鑰；每個百分比都是服務商自己回報的。[完整清單與各自的讀取方式](Docs/supported-services.md)（英文）。

---

## 隱私與安全

- **沒有 Pulse 帳號，也沒有 Pulse 伺服器**——你的 Mac 用你自己的登入狀態連線至你在用的服務。
- **只有五類連線，全列在這裡**——這些服務、它們的公開狀態頁、取得模型價格的 [models.dev](https://models.dev)、只在你選了美元以外的貨幣時才用的 [ExchangeRate-API](https://www.exchangerate-api.com)，以及檢查更新的 GitHub/Sparkle。
- **你的金鑰加密存放在本機**，Pulse 讀取的本機用量紀錄也不會離開你的 Mac。

[詳細說明](Docs/features.md#privacy-and-security)（英文）。

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
