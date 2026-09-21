<p align="center">
  <img src="AppIcon/pulse-icon-1024.png" width="112" alt="Pulse">
</p>

<h1 align="center">Pulse</h1>

<p align="center">
  <b>軽量でエレガントな、画面端に置く macOS 向け AI コーディング利用枠モニター。</b><br>
  Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Grok などの上限と残量をリアルタイムに把握。
</p>

<p align="center">
  <a href="https://github.com/qunqin24/Pulse/releases/latest"><img src="https://img.shields.io/github/v/release/qunqin24/Pulse?color=black" alt="最新リリース"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-333333?logo=apple" alt="macOS 14+">
  <a href="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml"><img src="https://github.com/qunqin24/Pulse/actions/workflows/ci.yml/badge.svg" alt="CI ビルド"></a>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="ライセンス"></a>
  <a href="https://github.com/qunqin24/Pulse/stargazers"><img src="https://img.shields.io/github/stars/qunqin24/Pulse?color=black" alt="GitHub スター"></a>
  <a href="https://github.com/qunqin24/Pulse/releases"><img src="https://img.shields.io/github/downloads/qunqin24/Pulse/total?color=black" alt="ダウンロード数"></a>
  <a href="https://github.com/qunqin24/Pulse/issues"><img src="https://img.shields.io/github/issues/qunqin24/Pulse?color=black" alt="オープンな Issue"></a>
  <a href="https://github.com/qunqin24/Pulse/commits/main"><img src="https://img.shields.io/github/last-commit/qunqin24/Pulse?color=black" alt="最終コミット"></a>
</p>

<p align="center">
  <sub><b>macOS 14 Sonoma 以降</b> · Apple Silicon と Intel のユニバーサル · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <b>日本語</b> · <a href="README.ko.md"><b>한국어</b></a></sub>
</p>

<p align="center">
  <img src="Docs/demo.gif" width="340" alt="画面端に貼り付いた Pulse のフローティングレール">
</p>

Pulse は画面の端にすっと収まる、控えめなフローティングモニターです。各サービスが報告する残量をそのまま表示します——使うのはその製品自身のクライアント経路で、Pulse のサーバーではありません——あなたがすでに持っているログインをそのまま使い、何も送り返しません。画面に出る使用率は、すべてサービス自身が報告した数字です。

**1.2.0 の新機能：** プロバイダのロゴの代わりに使えるアニメーションマーク。そのアカウントの状態に反応する小さなボットで、性格・形・色を選べます。[リリースノート](https://github.com/qunqin24/Pulse/releases/tag/v1.2.0)。

<p align="center">
  <img src="Docs/bot-mark.gif" width="340" alt="Pulse のアニメーションマーク：各リングのボットがそのアカウントの状態に反応します">
</p>

---

## 主な機能

### 一目でわかるステータスリング
- **使用量に応じた色**：リングは使用率に応じて滑らかに色を変え（緑 → 琥珀 → 赤 → 使い切ると濃い赤）、アカウントごとに独自のアクセントカラーも設定できます。
- **稼働中インジケーター**：リングの縁を回る小さな光点が、エージェントが今リアルタイムで応答を生成しているかを示します（Claude Code と Codex）。
- **経過ウィンドウの弧**：任意で表示できる外側の副弧が、現在の上限ウィンドウのうちどれだけ時間が経過したかを可視化します。
- **カウントダウンモード**：消費済み（`75% used`）と残り（`25% left`）を切り替えられます。

### ホバー詳細とスマート予測
- **上限の完全な内訳**：リングにポインタを合わせると、報告されたすべての枠、リセットまでのカウントダウン、現在のウィンドウ状態を示す詳細カードが開きます。
- **消費ペースの予測（任意）**：オンにすると、現在のペースが上限ウィンドウより長くもつかを見積もり、危険があるときは枯渇予想時刻（ETA）を表示します。既定ではオフです。
- **主要ウィンドウのピン留め**：いちばん重要な上限をリングに固定するか、枯渇に最も近いものを Pulse に自動で追わせられます。

### ネイティブで滑らか、邪魔をしない
- **自在な端へのドッキング**：画面の左端・右端・上部（メニューバーの上）にドッキングでき、どこにでも自由に浮かせられます。
- **マルチディスプレイ対応**：Pulse を任意のサブディスプレイへドラッグでき、画面の配置を記憶し、切断時も自然に戻ります。**アクティブなディスプレイに追従**をオンにすると、1 本のレールがポインタのある画面へ自動で移動します。
- **自動折りたたみ**：アイドル時は髪の毛ほどの細い帯に折りたたまれ、気を散らしません。上限が危険なほど少なくなったときだけ赤く光ります。
- **オプトインの通知**：知らせてほしいものだけを選んでオンにします。上限が 75/80/90/95% を越えたとき、プロバイダが使い切ったと報告したとき、警告したウィンドウが戻ったとき、何度も続けてチェックに失敗して（パネルが古い数字を静かに表示しているとき）、そして前払い残高があなたの決めた金額を下回ったときに知らせます。それぞれ一度だけ：オンにした時点ですでに線を越えていた上限はすぐに一度だけ伝え、その後はリセットされたとき、または悪化したときに伝えます。
- **Spaces にやさしい**：既定ではいま作業している Space に留まり、全画面アプリはそのままにします。
- **macOS らしい質感**：落ち着いた無地の黒いサーフェス、または macOS 26+ のネイティブ **Liquid Glass**。
- **アニメーションマーク（任意）**：プロバイダのロゴを、そのアカウントの状態に反応する小さなボットに置き換えます。作業中、取得中、上限到達、待機中を表します。既定はオフでアカウントごとに有効化でき、8 種類の性格と 18 種類の形、そして好みの色を選べます。
- **レールメニューとショートカット**：フローティングレール——または折りたたまれた細い帯——を右クリックすると（Control クリックでも可）、「設定」と「終了」を含むメニューが開きます。**設定 › 一般 › ショートカット** では、**設定を開く** と **パネルの表示を切り替え** にグローバルショートカットを任意で割り当てられます。どちらも割り当てるまでは未設定です。
- **5 つのインターフェース言語**：英語、簡体字中国語、繁体字中国語、日本語、韓国語に対応し、大きな数の単位も言語に合わせて切り替わります（それぞれ K/M/B、万/亿、萬/億、万/億、만/억）。

### マルチアカウントとローカル台帳
- **マルチアカウント対応**：同じプロバイダの複数のサブスクリプション（Claude Code、Codex、Grok、Grok Bot）を並べて監視し、ラベルを付けられます。
- **トークン消費（設定内のみ）**：初期状態はオフです。ページ上部でオンにするとローカル記録を読み始め、オフにすると停止します。ログ・データベース・エクスポートを含む **54 のクライアントソース**に対応しています（Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot など）。Cursor や Trae などのエクスポート系ソースは、事前のエクスポートかキャプチャが必要です。これらはレールに表示する 19 のクォータプロバイダとは別物で、対応状況と実クライアントでの検証状況はソースごとに異なります。[ソースと対応範囲](Docs/token-spend-sources.md)。
- **明確な使用量の推定**：直近 7 日を初期表示し、選んだ期間を記憶します。コストは公開 API 価格で算出し、サブスクリプションの請求額ではありません。価格が不明な場合やトークン数の集計が不完全な場合、時刻の詳細が分からない場合はその旨を表示します。トークン数を記録しないソースは、その旨をそのまま表示します。
- **モデル詳細とチャート**：モデルを開くと、入力・出力・キャッシュのトークン数と推定コスト、記録に基づく日次・時間別チャート、エージェント別の内訳、並べ替えとページ送りができる詳細テーブルを表示します。チャートにポインタを合わせると、日付または時刻とそのトークン数を読み取れます。利用できない日次・時間別の内訳は「利用不可」と表示し、ゼロとはみなしません。
- **20 のプロバイダ**：Claude Code、Codex、Kiro、Antigravity、Cursor、GitHub Copilot、Grok、Grok Bot、OpenCode Go、Kimi Code、Ollama Cloud、z.ai、Zhipu、MiniMax（国際・中国本土）、Volcengine、Command Code、DeepSeek、Devin、Xiaomi Coding Plan。
- **スクリプト可**：`Pulse --json` が最後の読み取り値——プラン、すべての上限、リセット時刻、数字がどれだけ古いか——を出力します。tmux、sketchybar、Raycast、シェルプロンプトにどうぞ。キャッシュを読むだけなので、ポーリングのコストはかかりません。
- **開発者向け連携**：設定から Raycast 拡張と、そのまま設定できる tmux・sketchybar・シェルのスクリプトを書き出せます。アカウントのリンクは該当ペインを直接開きます。[セットアップガイド](Docs/integrations.md)。
- **接続診断**：実際の読み取り元、キャッシュの利用、最新のチェックとフォールバックの結果を確認できます。状況に応じた操作で再接続・再ログイン・認証情報の修正ができ、アカウント情報やシークレットを含まない診断レポートをコピーできます。
- **プライバシー第一**：Pulse はあなたの Mac 上で、あなた自身のログインのもとで動きます。接続先は三つだけで、ここに挙げたものがすべてです——すでに使っているプロバイダ、トークン消費ペインの公開モデル価格を取得する [models.dev](https://models.dev)、そしてアプリの更新を確認する GitHub/Sparkle。プロバイダへのリクエスト、サインイン時のトークン交換、models.dev は「設定」›「一般」›「ネットワーク」で選んだプロキシを使い、手動プロキシは対応するヘルパープロセスにも渡されます。Sparkle のアップデート確認は常に macOS のシステムプロキシ設定に従います。

<p align="center">
  <img src="Docs/panel.webp" height="300" alt="レールの隣に開く使用量の詳細カード">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="Docs/settings.webp" height="300" alt="Pulse の設定">
</p>

<p align="center">
  <img src="Docs/account-claude-code.webp" height="290" alt="アカウントペイン：報告されたすべての上限、使った分の推定額、ローカル履歴">
  &nbsp;&nbsp;
  <img src="Docs/account-codex.webp" height="290" alt="別のアカウントペイン：プラン、クレジット残高、報告された上限リセット券">
</p>

<p align="center">
  <img src="Docs/spend.webp" height="290" alt="トークン消費：合計、種類別トークン、日ごとの傾向">
  &nbsp;&nbsp;
  <img src="Docs/spend-history.webp" height="290" alt="トークン消費：日別・月別・エージェント別">
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
| **OpenCode Go** | API キー、または既存の OpenCode CLI 認証情報 | 設定で完全に構成可能 |
| **Kimi Code** | API キーを直接 | 設定で構成 |
| **z.ai** | API キーを直接 | 国際ストア（`api.z.ai`） |
| **Zhipu** | API キーを直接、または保存済みの GLM ツール認証情報 | 中国本土ストア（`open.bigmodel.cn`） |
| **MiniMax / MiniMax CN** | API キーを直接 | 国際（`minimax.io`）と中国本土（`minimaxi.com`）に対応 |
| **Ollama Cloud** | ブラウザのセッション Cookie | ブラウザからローカルで読み取り。詳細は [Docs/ollama-cloud.md](Docs/ollama-cloud.md) |
| **Volcengine** | `arkcli` ログイン、または貼り付けたアクセスキー（Top OpenAPI に署名） | Ark Coding / Agent プラン。自動では CLI より貼り付けたキーを優先 |
| **Command Code** | 貼り付けたキー、または `cmd auth login` がすでに保存したログイン | ドル建てのクレジット残高。月次プランの行は**推定**と表示 |
| **DeepSeek** | 貼り付けたキー。文書化された `GET /user/balance` | 前払い残高のみで枠はなし。リングが何を基準にするかはあなたが選ぶ |
| **Devin** | 入力は不要——ブラウザのセッションを読み取り、キーチェーンの確認も出ない | Devin が報告する日次・週次の枠。ブラウザセッションも貼り付けた認証情報もない場合は、アプリが保存した日付付きプランを読み取る。エンドポイント障害時は一致するエンドポイントのキャッシュのみを使い、アカウントと組織の境界を保つ（[Docs/providers/devin.md](Docs/providers/devin.md)） |
| **Xiaomi Coding Plan** | 入力は不要——サインイン済みのブラウザセッションを読み取る。`Cookie:` ヘッダーを貼り付けることもできる | Xiaomi MiMo コンソールの月間トークン枠。期間の終了が報告されていればそれも表示する。前払い残高はカードに 1 行として並ぶ。プランのないアカウントは 0% を描かず、そう述べる（[Docs/providers/xiaomi-coding-plan.md](Docs/providers/xiaomi-coding-plan.md)） |

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
- **Pulse のバックエンドはなし**：あなたの Mac が、あなた自身のログインで、すでに使っているプロバイダへつなぎます。また、トークン消費ペインのために [models.dev](https://models.dev) から公開モデル価格を取得し、GitHub/Sparkle でアプリの更新を確認します。プロバイダへのリクエスト、サインイン時のトークン交換、models.dev は「設定」›「一般」›「ネットワーク」で選んだプロキシを使い、手動プロキシは対応するヘルパープロセスにも渡されます。Sparkle のアップデート確認は常に macOS のシステムプロキシ設定に従います。
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
