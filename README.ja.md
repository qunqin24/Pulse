<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>使用量のページを開かなくても、Claude Code・Codex・Cursor の残りがわかる。</b><br>
  画面の端に置いておくだけで、AI コーディングの利用枠がひと目でわかる、無料・オープンソースの macOS アプリ。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/badge/%E3%83%80%E3%82%A6%E3%83%B3%E3%83%AD%E3%83%BC%E3%83%89-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 版 Pulse をダウンロード"></a>
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?label=%E6%9C%80%E6%96%B0%E3%83%AA%E3%83%AA%E3%83%BC%E3%82%B9&color=black" alt="最新リリース"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?label=%E3%83%80%E3%82%A6%E3%83%B3%E3%83%AD%E3%83%BC%E3%83%89%E6%95%B0&color=black" alt="ダウンロード数"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?label=%E3%82%B9%E3%82%BF%E3%83%BC&color=black" alt="GitHub スター"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/%E3%83%A9%E3%82%A4%E3%82%BB%E3%83%B3%E3%82%B9-Apache%202.0-blue" alt="Apache 2.0 ライセンス"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 以降</b> · Apple シリコンと Intel に対応 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <b>日本語</b> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" height="400" alt="画面の端に寄せた Pulse のフローティングレール">
  &nbsp;&nbsp;
  <img src="Docs/panel.webp" height="400" alt="リングにポインタを乗せると、すべての上限とリセット時刻を並べたカードが開きます">
</p>

- **77 のサービスをひと目で**——Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Kiro、Grok、DeepSeek、Kimi Code など。それぞれに専用のリングがあります。
- **Pulse のアカウントもサーバーもなし**——いまお使いのログインをそのまま使い、何も送り返しません。
- **表示するのは実際の数字だけ**——使用率はすべてサービス自身が報告した値です。数少ない推定値にはそう明記し、サービスが数字を出さないときは、推測せずにそのことを表示します。
- **ネイティブで控えめ**——Swift と SwiftUI 製で、macOS 26 では Liquid Glass。画面の左・右・上、または下の Dock の横に寄せられ、使っていないときは細い線に畳まれます。メニューバーだけで使うこともできます。

**最近の追加：** メニューバーでの使用量表示とアカウントごとのダッシュボード、リセット後に利用枠を自動で始める機能、動くボットのマーク。[更新内容](https://github.com/qunqin24/Pulse/releases/latest)。

<p align="center">
  <img src="Docs/bot-mark.gif" width="300" alt="Pulse のアニメーションマーク：各リングのボットがそのアカウントの状態に反応します">
</p>

<p align="center">
  <sub>Pulse のおかげで突然の上限を避けられたなら、⭐ をもらえると、ほかの人にも見つけてもらいやすくなります。</sub>
</p>

---

## 主な機能

### 一目でわかるステータスリング
- **使用量に応じた色**：リングは使用率に応じて滑らかに色を変え（緑 → 琥珀 → 赤 → 使い切ると濃い赤）、アカウントごとに独自のアクセントカラーも設定できます。
- **稼働中インジケーター**：リングの縁を回る小さな光点が、エージェントが今リアルタイムで応答を生成しているかを示します（Claude Code、Codex、Kiro、Zhipu、z.ai）。
- **経過ウィンドウの弧**：任意で表示できる外側の副弧が、現在の上限ウィンドウのうち経過した時間、または残りの時間を可視化します。
- **カウントダウンモード**：消費済み（`75% used`）と残り（`25% left`）を切り替えられます。

### ホバー詳細とスマート予測
- **上限の完全な内訳**：リングにポインタを合わせると、報告されたすべての枠、リセットまでのカウントダウン、現在のウィンドウ状態を示す詳細カードが開きます。
- **詳細カード（任意・アカウントごと）**：よく見るアカウントだけオンにできます。プラン名と数値の更新時刻が加わり、この Mac の記録から金額を出せる場合は各上限の推定価値も表示します。さらに、Pulse が利用履歴を取得できるサービスでは、今日・7 日間・31 日間のトークン数と 31 日分のグラフ、最も使ったモデル、キャッシュヒット率（記録がキャッシュを区別している場合のみ）、さらにプロンプトキャッシュがあとどれだけ保たれるか（Claude Code は各返信に記録されたキャッシュの段階から、Codex は GPT-5.6 以降で OpenAI が保証する最低 30 分から計算）も表示します。カードには最も早く切れる会話を、設定にはすべての会話を表示します。z.ai と Zhipu はそれぞれのアカウント統計から、Claude Code・Codex・Kimi Code・Grok・OpenCode・Cursor・Devin・Antigravity・Command Code・Copilot はこの Mac の記録から読み取ります（こちらは「トークン使用量」をオンにする必要があります）。
- **消費ペースの予測（任意）**：オンにすると、現在のペースが上限ウィンドウより長くもつかを見積もり、危険があるときは枯渇予想時刻（ETA）を表示します。既定ではオフです。
- **主要ウィンドウのピン留め**：いちばん重要な上限をリングに固定するか、枯渇に最も近いものを Pulse に自動で追わせられます。

<p align="center">
  <img src="Docs/detailed-card.webp" width="620" alt="同じ Codex アカウントのコンパクトなカードと詳細カード">
</p>

### ネイティブで滑らか、邪魔をしない
- **自在な端へのドッキング**：画面の左端・右端・上部（メニューバーの上）・下部（Dock の横）にドッキングでき、縦置き・横置きのどちらでも、どこにでも自由に浮かせられます。
- **マルチディスプレイ対応**：Pulse を任意のサブディスプレイへドラッグでき、画面の配置を記憶し、切断時も自然に戻ります。**使用中のディスプレイを追う**をオンにすると、1 本のレールがポインタのある画面へ自動で移動します。
- **自動折りたたみ**：アイドル時は髪の毛ほどの細い帯に折りたたまれ、気を散らしません。上限が危険なほど少なくなったときだけ赤く光ります。
- **オプトインの通知**：知らせてほしいものだけを選んでオンにします。上限が 75/80/90/95% を越えたとき、プロバイダが使い切ったと報告したとき、警告したウィンドウが戻ったとき、何度も続けてチェックに失敗して（パネルが古い数字を静かに表示しているとき）、前払い残高があなたの決めた金額を下回ったとき、そして Codex・Claude Code・DeepSeek の公式ステータスページが、ツールの依存するサービスの障害を伝えたとき（オンにしているサービスだけ）に知らせます。それぞれ一度だけ：オンにした時点ですでに線を越えていた上限はすぐに一度だけ伝え、その後はリセットされたとき、または悪化したときに伝えます。
- **リセット後にウィンドウを開始（オプション）**：Claude Code と Codex の利用枠は、リセット後に最初のメッセージを送った時点から数え始めます。オンにすると、Pulse はリセットの直後、指定した時間帯のうちに、プロバイダ自身のコマンドラインツールから「hi」を一度だけ送り、戻ってきた時点ではなくその時点から時計が進むようにします。既定はオフです。Anthropic や OpenAI の機能ではなく、利用制限の回避とみなされる可能性があることを確認してからオンになります。
- **Spaces にやさしい**：既定ではいま作業している Space に留まり、全画面アプリはそのままにします。
- **macOS らしい質感**：落ち着いた無地の黒いサーフェス、明るい画面に合うライトのサーフェス、または macOS 26+ のネイティブ **Liquid Glass**。
- **アニメーションマーク（任意）**：プロバイダのロゴを、そのアカウントの状態に反応する小さなボットに置き換えます。作業中、取得中、上限到達、待機中を表します。既定はオフでアカウントごとに有効化でき、8 種類の性格と 18 種類の形、そして好みの色を選べます。
- **レールメニューとショートカット**：フローティングレール——または折りたたまれた細い帯——を右クリックすると（Control クリックでも可）、「設定」と「終了」を含むメニューが開きます。**設定 › 一般 › ショートカット** では、**設定を開く** と **パネルの表示を切り替え** にグローバルショートカットを任意で割り当てられます。どちらも割り当てるまでは未設定です。
- **メニューバーの使用量（任意）**：いちばん使っているリング——または選んだアカウント——をメニューバーのアイコン横に、数字・小さなリング・5 時間と週の上限の並列表示（`5h/9%  週/15%`）のいずれかで表示し、警告ラインを超えると赤になります。「メニューに使用量パネルを表示」をオンにすると、クリックでダッシュボードが開きます：全アカウントの概要と、アカウントごとのタブ（各上限とリセット時刻、クレジット残量、トークン使用量を有効にしたときの推定費用、サービス公式の使用量ページへのリンク）。メニューバーだけで使いたい場合は、同じメニューからフローティングパネルをオフにできます。
- **5 つのインターフェース言語**：英語、簡体字中国語、繁体字中国語、日本語、韓国語に対応し、大きな数の単位も言語に合わせて切り替わります（それぞれ K/M/B、万/亿、萬/億、万/億、만/억）。

### マルチアカウントとローカル台帳
- **マルチアカウント対応**：同じプロバイダの複数のサブスクリプション（Claude Code、Codex、Grok、Grok Bot）を並べて監視し、ラベルを付けられます。
- **トークン使用量（設定内のみ）**：初期状態はオフです。ページ上部でオンにするとローカル記録を読み始め、オフにすると停止します。ログ・データベース・エクスポートを含む **54 のクライアントソース**に対応しています（Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot など）。Cursor や Trae などのエクスポート系ソースは、事前のエクスポートかキャプチャが必要です。これらはレールに表示する 77 のクォータプロバイダとは別物で、対応状況と実クライアントでの検証状況はソースごとに異なります。[ソースと対応範囲](Docs/token-spend-sources.md)。
- **明確な使用量の推定**：直近 7 日を初期表示し、選んだ期間を記憶します。コストは公開 API 価格で算出し、サブスクリプションの請求額ではありません。価格が不明な場合やトークン数の集計が不完全な場合、時刻の詳細が分からない場合はその旨を表示します。トークン数を記録しないソースは、その旨をそのまま表示します。
- **モデル詳細とチャート**：モデルを開くと、入力・出力・キャッシュのトークン数と推定コスト、記録に基づく日次・時間別チャート、エージェント別の内訳、並べ替えとページ送りができる詳細テーブルを表示します。チャートにポインタを合わせると、日付または時刻とそのトークン数を読み取れます。利用できない日次・時間別の内訳は「利用不可」と表示し、ゼロとはみなしません。
- **月間まとめ・年間まとめ**：好きな月や年について、トークン使用量と同じローカル記録から、シェアしやすいカードをまとめて作ります。トークン数と概算金額、前の月との比較、毎日のカレンダー、いちばん作業する時間帯、使ったモデル・エージェント・プロジェクト、連続日数。毎月のサブスク料金を入れれば、何倍元を取ったかも出ます。各カードは画像として保存・コピー・共有でき、5 つの言語に対応。プロジェクト名はスイッチひとつで隠せます。トークン使用量のページから開けて、毎月 1 日に先月分ができたと知らせる通知もオンにできます。
- **77 のプロバイダ**：Claude Code、Codex、Kiro、Antigravity、Cursor、GitHub Copilot、Grok、Grok Bot、OpenCode Go、Kimi Code、Ollama Cloud、z.ai、Zhipu、MiniMax（国際・中国本土）、Volcengine、Command Code、DeepSeek、Devin、Xiaomi Coding Plan、sub2api、New API、V2EX、Qoder、StepFun。ほかに Abacus AI、Aixy、Alibaba Coding Plan、Alibaba Token Plan、Amp、Atlas Cloud、Augment Code、Bifrost、Chutes、ClawRouter、ClinePass、Codebuff、DeepInfra、DevPass、ElevenLabs、Factory、Gemini、GitKraken AI、Hugging Face、Hyper、IBM Bob、JetBrains AI、Kilo Code、LiteLLM、LLM API Key Proxy、LongCat、Manus、Mistral、Moonshot、Neuralwatt、Notion AI、Nous Portal、OpenAI API、Perplexity、Poe、Qwen Cloud、Raycast AI、Replicate、Sakana AI、Synthetic、T3 Chat、TypeSafe、v0、Venice、Vercel AI Gateway、Warp、Windsurf、xAI API、xKiro、Zed、ZenMux、ZoomMate。
- **スクリプト可**：`Pulse --json` が最後の読み取り値——プラン、すべての上限、リセット時刻、数字がどれだけ古いか——を出力します。tmux、sketchybar、Raycast、シェルプロンプトにどうぞ。キャッシュを読むだけなので、ポーリングのコストはかかりません。
- **開発者向け連携**：設定から Raycast 拡張と、そのまま設定できる tmux・sketchybar・シェルのスクリプトを書き出せます。アカウントのリンクは該当ペインを直接開きます。[セットアップガイド](Docs/integrations.md)。
- **拡張機能**：自作の小さなプログラムで、1 つのアカウントの使用量（社内のクォータ API など）を Pulse のリングに表示できます。フォークを保守する必要はありません。オンにするまでは実行されず、Pulse が認証情報を渡すこともありません。[作り方](Docs/extensions.md)（英語）。
- **サービスの状態**：Codex・Claude Code・DeepSeek の設定に、それぞれの公式ステータスページと同じ見た目でサービスの状態を表示します——各項目がいま正常かどうか、過去 90 日を 1 日 1 本のバーで、そしてステータスページが公表する稼働率。設定を開いたときに読み込み、開いている間は 5 分ごとに更新します。
- **接続診断**：実際の読み取り元、キャッシュの利用、最新のチェックとフォールバックの結果を確認できます。状況に応じた操作で再接続・再ログイン・認証情報の修正ができ、アカウント情報やシークレットを含まない診断レポートをコピーできます。
- **プライバシー第一**：Pulse はあなたの Mac 上で、あなた自身のログインのもとで動きます。接続先は四つだけで、ここに挙げたものがすべてです——すでに使っているプロバイダ、「サービスの状態」とその通知のための公開ステータスページ（status.openai.com、status.claude.com、status.deepseek.com）、トークン使用量ペインの公開モデル価格を取得する [models.dev](https://models.dev)、そしてアプリの更新を確認する GitHub/Sparkle。プロバイダへのリクエスト、ステータスページ、サインイン時のトークン交換、models.dev は「設定」›「ネットワークと更新」で選んだプロキシを使い、手動プロキシは対応するヘルパープロセスにも渡されます。Sparkle のアップデート確認は常に macOS のシステムプロキシ設定に従います。

<p align="center">
  <img src="Docs/settings.webp" height="300" alt="Pulse の設定">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="アカウントペイン：報告されたすべての上限、使った分の推定額、ローカル履歴">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="別のアカウントペイン：プラン、クレジット残高、報告された上限リセット券">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="トークン使用量：合計、種類別トークン、日ごとの傾向">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="トークン使用量：日別・月別・エージェント別">
</p>

<p align="center">
  <img src="Docs/spend-agent.webp" height="290" alt="1 つのエージェントの消費">
  &nbsp;&nbsp;
  <img src="Docs/spend-model.webp" height="290" alt="1 つのモデルの消費、トークン種別ごとの価格付け">
</p>

---

## 対応プロバイダとデータ経路

Pulse は各サービスが報告する数字をそのまま表示します。画面の使用率は、その回答そのものに含まれる数字です。経路は製品ごとに異なります（文書化されたクライアント API、エディタのログイン、ローカルの language server、貼り付けたキー）——どの行にも公開の公式クォータ API があるわけではありません。貢献者向けの詳細：[Docs/providers/README.md](Docs/providers/README.md)。

| プロバイダ | データ経路と認証方法 | 備考 |
|---|---|---|
| **Claude Code** | アカウントの OAuth 使用量エンドポイント。Claude デスクトップのセッションとステータスラインへ自動フォールバック | 既存の CLI／デスクトップセッションを読み取り、シームレスに自動フォールバック |
| **Codex** | クライアントの使用量エンドポイント。`codex app-server` へフォールバック | ローカルの Codex 認証情報を直接読み取り |
| **Kiro** | Kiro CLI ネイティブの ACP 使用量メソッド | Kiro CLI のログイン済みセッションを利用。Pulse が Kiro の認証情報を読み取ったり保存したりすることはありません（[詳細](Docs/providers/kiro.md)） |
| **Antigravity** | ローカルの Language Server（LSP） | Antigravity エディタの実行中のみ有効 |
| **Cursor** | Cursor アカウントの使用量サマリー API | 既存のエディタログインから fast と slow のリクエストプールを表示 |
| **Grok** | Grok Build CLI プロキシ（`cli-chat-proxy.grok.com`） | すべての Grok 製品で共有される単一の週次プール |
| **Grok Bot** | Cursor ダッシュボード API | Cursor サブスクリプションに含まれる xAI の枠 |
| **GitHub Copilot** | GitHub Device Code 認証 | 最小限の `read:user` スコープのみ要求。リポジトリには一切アクセスしない |
| **OpenCode Go** | API キー、または既存の OpenCode CLI 認証情報。ブラウザの OpenCode コンソールのサインインも読み取れます | コンソールのサインインを読み取ると、詳細カードにアカウントのリクエスト記録（すべてのデバイス・アプリ、各リクエストの実際の費用）も表示されます |
| **Kimi Code** | API キーを直接 | 設定で構成 |
| **z.ai** | API キーを直接 | 国際ストア（`api.z.ai`） |
| **Zhipu** | API キーを直接、または保存済みの GLM ツール認証情報 | 中国本土ストア（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | API キーを直接 | 国際（`minimax.io`）と中国本土（`minimaxi.com`）に対応 |
| **Ollama Cloud** | ブラウザのセッション Cookie | ブラウザからローカルで読み取り。詳細は [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine** | `arkcli` ログイン、または貼り付けたアクセスキー（Top OpenAPI に署名） | Ark Coding / Agent プラン。自動では CLI より貼り付けたキーを優先 |
| **Command Code** | 貼り付けたキー、または `cmd login` がすでに保存したログイン | ドル建てのクレジット残高と、5時間・週ごとのローリング上限。月次プランの行は**推定**と表示 |
| **DeepSeek** | 貼り付けたキー。文書化された `GET /user/balance` | 前払い残高のみで枠はなし。リングが何を基準にするかはあなたが選ぶ |
| **Devin** | 入力は不要——ブラウザのセッションを読み取り、キーチェーンの確認も出ない | Devin が報告する日次・週次の枠。ブラウザセッションも貼り付けた認証情報もない場合は、アプリが保存した日付付きプランを読み取る。エンドポイント障害時は一致するエンドポイントのキャッシュのみを使い、アカウントと組織の境界を保つ（[Docs/providers/devin.md](Docs/providers/devin.md)） |
| **Xiaomi Coding Plan** | 入力は不要——サインイン済みのブラウザセッションを読み取る。`Cookie:` ヘッダーを貼り付けることもできる | Xiaomi MiMo コンソールの月間トークン枠。期間の終了が報告されていればそれも表示する。前払い残高はカードに 1 行として並ぶ。プランのないアカウントは 0% を描かず、そう述べる（[Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)） |
| **sub2api** | 貼り付けたグループキー。ゲートウェイのアドレスは自分で入力 | 自前で運用する [sub2api](https://github.com/Wei-Shaw/sub2api) ゲートウェイのグループ単位の集計を読み取る——残高、クォータ、サブスクリプション、レート制限のいずれかで、グループの設定によって変わる（[Docs/providers/sub2api.md](Docs/providers/sub2api.md)） |
| **New API** | 貼り付けた `sk-` キー。ゲートウェイのアドレスは自分で入力 | 自前で運用する [New API](https://github.com/QuantumNous/new-api) ゲートウェイの残高を、運用者が設定した通貨で表示。回答の比率は意味が二通りありうるため、割合は表示しない（[Docs/providers/newapi.md](Docs/providers/newapi.md)） |
| **V2EX** | 貼り付けた個人アクセストークン | AI Chat のローリング 5 時間トークン枠。購入した追加パックがあれば、もう 1 つ輪を表示。ウィンドウがまだ始まっていないときはカウントダウンを表示しない（[Docs/providers/v2ex.md](Docs/providers/v2ex.md)） |
| **Qoder** | 入力は不要——qoder.com または qoder.com.cn のサインイン済みブラウザセッションを読み取る。`Cookie:` ヘッダーを貼り付けることもできる | クレジット枠（プランとパックの合計）を Qoder が報告するリセット時刻とともに表示。チームプランの共有クレジットは別の輪として表示し、決して合算しない。クレジットが 0 のときはそう表示し、輪は描かない（[Docs/providers/qoder.md](Docs/providers/qoder.md)） |
| **StepFun** | 入力は不要——platform.stepfun.com または platform.stepfun.ai のサインイン済みブラウザセッションを読み取る。`Cookie:` ヘッダーを貼り付けることもできる | Step Plan：Token Plan の月次 Credit と追加パックを 1 つの輪にまとめ、最も早く失効する分の日付を表示。旧 Coding Plan は 5 時間枠と週間枠。プランがなければ輪を描かずにそう表示する（[Docs/providers/stepfun.md](Docs/providers/stepfun.md)） |

### その他のプロバイダ

[CodexBar](https://github.com/steipete/CodexBar) の実装を読んで移植したものです。**実際のアカウントではまだ確認していません**——動かないものがあれば [issue](https://github.com/qunqin24/Pulse/issues) でお知らせください。各プロバイダの設定手順は [Docs/setup/](Docs/setup/)（英語）、メンテナ向けの説明は [Docs/providers/README.md](Docs/providers/README.md#profiled-providers) にあります。

| プロバイダ | データ経路と認証方法 | 表示内容 |
|---|---|---|
| **Abacus AI** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | コンピュートポイントと請求日 |
| **Aixy** | 貼り付けた API キー | 期間ごとのゲートウェイ予算 |
| **Alibaba Coding Plan** | 貼り付けた API キー | 5 時間・週・月の枠。国際版コンソールを先に、次に中国本土版 |
| **Alibaba Token Plan** | Alibaba の `bl` CLI を、保存済みのログインで実行 | 5 時間・週・月の使用割合 |
| **Amp** | 貼り付けた API キー | 無料の日次枠、プランの枠とクレジット |
| **Atlas Cloud** | 貼り付けた API キー | 残高 |
| **Augment Code** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 今サイクルの使用クレジット |
| **Bifrost** | 貼り付けたキー。自前のゲートウェイのアドレスを入力 | 仮想キーのドル建て予算 |
| **Chutes** | 貼り付けた API キー | ローリング枠と月間枠 |
| **ClawRouter** | 貼り付けた API キー | 月間予算 |
| **ClinePass** | 貼り付けた API キー | 5 時間・週・月の上限 |
| **Codebuff** | 貼り付けたキー、または CLI が保存したログイン | クレジット。CLI のログインでは週次上限も |
| **DeepInfra** | 貼り付けた API キー | 残高。先方で上限を設定していればその消費割合 |
| **DevPass** | 貼り付けた API キー | 週次プレミアム枠とプランのクレジット |
| **ElevenLabs** | 貼り付けた API キー | 請求期間の文字クレジット |
| **Factory** | 貼り付けた API キー | 5 時間・週・月の上限（旧課金では Standard と Premium）。追加利用の残高 |
| **Gemini** | Gemini CLI が保存したログインを読み取るのみ（更新はしない） | モデルごとのクォータ。ログインは約 1 時間で切れるため、Gemini CLI を使っている間だけ読める |
| **GitKraken AI** | 貼り付けたトークン | 個人クレジットと共有プール |
| **Hugging Face** | 貼り付けたトークン、または `hf auth login` が保存したもの | ZeroGPU クォータ |
| **Hyper** | 貼り付けた API キー | Hypercredit 残高 |
| **IBM Bob** | 貼り付けた API キー | チーム予算に対する Bobcoins の使用量 |
| **JetBrains AI** | JetBrains IDE が保存するクォータファイル。どこにも送信しない | AI Assistant のクォータ。IDE の実行中に更新 |
| **Kilo Code** | 貼り付けたキー、または CLI が保存したログイン | クレジット残高と Kilo Pass |
| **LiteLLM** | 貼り付けたキー。自前のゲートウェイのアドレスを入力 | チームとユーザーの予算 |
| **LLM API Key Proxy** | 貼り付けたキー。自前のゲートウェイのアドレスを入力 | 上流ごとのクォータグループ |
| **LongCat** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | トークンパックの枠と追加パック |
| **Manus** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 日次と月次のクレジット |
| **Mistral** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | API と Vibe の月間枠、利用可能なクレジット |
| **Moonshot** | 貼り付けた API キー | Kimi Open Platform の残高（USD または CNY） |
| **Neuralwatt** | 貼り付けた API キー | kWh のサブスクリプション、利用枠と残高 |
| **Notion AI** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | ローリング枠と請求期間の枠（Business・Enterprise） |
| **Nous Portal** | Hermes Agent が保存したログインを読み取るのみ | 月間クレジット付与と残高 |
| **OpenAI API** | 貼り付けた API キー | 前払い残高（旧課金経路が応答する場合） |
| **Perplexity** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | API クレジット残高 |
| **Poe** | 貼り付けた API キー | ポイント残高 |
| **Qwen Cloud** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 5 時間・週・月の割合とティア |
| **Raycast AI** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | AI クレジットと更新日 |
| **Replicate** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 前払い残高 |
| **Sakana AI** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 5 時間と週の上限 |
| **Synthetic** | 貼り付けた API キー | 5 時間・週・検索の枠 |
| **T3 Chat** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 4 時間枠と月間の数値 |
| **TypeSafe** | 貼り付けた `Cookie:` ヘッダー | クレジット残高とプラン |
| **v0** | 貼り付けた API キー | 課金枠 |
| **Venice** | 貼り付けた API キー | 残高（USD または DIEM） |
| **Vercel AI Gateway** | 貼り付けた API キー | 残高 |
| **Warp** | 貼り付けた API キー | プランのクレジットと追加クレジット |
| **Windsurf** | Chromium 系ブラウザから windsurf.com のサインインを読み取る | 日次と週次のクォータ |
| **xAI API** | `TeamID:ManagementKey` の形式で貼り付け | チームの前払い残高（xAI の記帳額） |
| **xKiro** | 貼り付けた API キー | 5 時間と週の枠、日次の無料トークンとウォレット |
| **Zed** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 編集予測の枠と支出上限 |
| **ZenMux** | 貼り付けた管理キー | 5 時間と 7 日のクォータ、残高 |
| **ZoomMate** | サインイン済みブラウザのセッションを読み取る、または `Cookie:` ヘッダーを貼り付け | 予算上限に対するクレジット |

---

## インストール

1. [Releases](https://github.com/qunqin24/Pulse/releases/latest) から最新の **`Pulse-x.y.z.dmg`** をダウンロードします。
2. ディスクイメージを開き、**Pulse** を `Applications` フォルダへドラッグします。
3. 初回起動時に監視するサービスを選びます。最初はすべて未選択で、**「完了」** を押してから認証情報を読み取り、使用量を確認します。選択画面を閉じると監視は始まりません。設定からサービスをオンにすることもできます。アップデート後も選択は保たれ、新たに対応したサービスが Mac に見つかった場合だけ、一度追加を尋ねます。
4. Pulse はメニューバーに常駐します。メニューバーが混み合っている場合は、フローティングレール——または折りたたまれた細い帯——を右クリックし、**「設定…」** を選んでください。**設定 › 一般 › ショートカット** でグローバルショートカットを割り当てることもできます。

> [!NOTE]
> **macOS での初回起動（Gatekeeper）**：<br>
> Pulse は Apple Developer 証明書を持たないオープンソースプロジェクトです。初回起動時に macOS がアプリをブロックすることがあります：
> - **方法 1（GUI）**：Pulse を起動し、警告を閉じ、**システム設定 → プライバシーとセキュリティ** を開き、**このまま開く** をクリックします。
> - **方法 2（ターミナル）**：
>   ```bash
>   xattr -cr /Applications/Pulse.app
>   ```
>   *更新はアプリ内の Sparkle で提供されます。更新後、macOS がブラウザのキーチェーンへのアクセスを再び求めることがあります。*

---

## プライバシーとセキュリティ

Pulse は厳格なローカルファーストのセキュリティ原則で設計されています：
- **Pulse のバックエンドはなし**：あなたの Mac が、あなた自身のログインで、すでに使っているプロバイダへつなぎます。また、「サービスの状態」のために Codex・Claude Code・DeepSeek の公開ステータスページを（ログインなしで）読み、トークン使用量ペインのために [models.dev](https://models.dev) から公開モデル価格を取得し、GitHub/Sparkle でアプリの更新を確認します。プロバイダへのリクエスト、ステータスページ、サインイン時のトークン交換、models.dev は「設定」›「ネットワークと更新」で選んだプロキシを使い、手動プロキシは対応するヘルパープロセスにも渡されます。Sparkle のアップデート確認は常に macOS のシステムプロキシ設定に従います。
- **ローカルの認証情報**：製品がそのように動く場合、開発ツールがすでにローカルへ保存した認証情報（`~/.claude`、`~/.codex`、Cursor のストレージなど）を読み取ります。一部のプロバイダには、設定で入力するキーやサインインが必要です。
- **暗号化されたローカル保存**：手動で入力した API キーとセッショントークンは暗号化され、Pulse のローカルアプリケーションディレクトリに所有者のみの権限で厳密に保存されます。
- **ローカルの利用記録**：Pulse はトークン数と、タイトルや作業ディレクトリといったセッション情報を得るために、トランスクリプト・データベース・エクスポートを読み取ります。これらの記録には会話のテキストが含まれることがありますが、処理はあなたの Mac 上で完結し、記録もそこに留まります。Pulse が読むのはこれらの記録だけです。

---

## ソースからビルド

Pulse はネイティブの Swift と SwiftUI でビルドされています。現在のソースをビルドするには、完全な **Xcode**（Command Line Tools ではなく）と **macOS 26 SDK** が必要です。アプリの動作要件は **macOS 14+** です。

```bash
# リポジトリをクローン
git clone https://github.com/qunqin24/Pulse.git
cd Pulse

# アプリバンドルをビルド
./Scripts/bundle.sh

# 起動
open build.noindex/Pulse.app
```

`swift run Pulse` はバンドルなしで手早くビルドして実行する方法ですが、通知とアプリ内更新はバンドルしたアプリでのみ動作します。ツールチェーンの設定は [Docs/build-from-source.md](Docs/build-from-source.md) を参照してください。リリースの手順：[Docs/releasing.md](Docs/releasing.md)。

---

## コントリビュート

リポジトリの文書化の仕方、退行させてはいけないもの、正しいページの更新方法：[CONTRIBUTING.md](CONTRIBUTING.md)。トピック別ドキュメントの地図：[Docs/README.md](Docs/README.md)。

---

## デザインの出典

Pulse は 2026 年 8 月に [**Vinz**（@hivinz_）](https://x.com/hivinz_/status/2092996055248126353) が X で共有した UI コンセプトに着想を得ています。Pulse は独立した実装で、インタラクション、機能、アニメーション、視覚的な細部はすべて独自のものです。Vinz は Pulse と提携しておらず、責任も負いません。

---

## Pulse を応援する

<p align="center">
  <sub>Pulse は無料のオープンソースで、余暇の時間で開発・更新しています。<br>突然のレート制限から救われたら、作者にコーヒーを一杯どうぞ。</sub>
</p>

<p align="center">
  <a href="https://afdian.com/a/qunqin"><img src="https://img.shields.io/badge/Afdian-%E3%82%B3%E3%83%BC%E3%83%92%E3%83%BC%E3%82%92%E4%B8%80%E6%9D%AF-946CE6?style=for-the-badge" alt="Afdian で Pulse を応援"></a>
</p>

---

## ライセンス

[Apache 2.0](LICENSE) の下でライセンスされています。同梱のサードパーティ資産はそれぞれのライセンスを保持します。詳しくは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

---

## Star の推移

<a href="https://star-history.com/#qunqin24/Pulse&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=qunqin24/Pulse&type=Date" />
  </picture>
</a>
