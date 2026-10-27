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
  <sub><b>macOS 14 Sonoma 以降</b> · Apple シリコンと Intel に対応 · <a href="README.md"><b>English</b></a> · <a href="README.zh-CN.md"><b>简体中文</b></a> · <a href="README.zh-Hant.md"><b>繁體中文</b></a> · <b>日本語</b> · <a href="README.ko.md"><b>한국어</b></a> · <a href="README.ru.md"><b>Русский</b></a></sub>
</p>

<p align="center">
  <img src="Docs/images/demo.gif" height="400" alt="画面の端に寄せた Pulse のフローティングレール">
  &nbsp;&nbsp;
  <img src="Docs/images/panel.webp" height="400" alt="リングにポインタを乗せると、すべての上限とリセット時刻を並べたカードが開きます">
</p>

- **77 のサービスをひと目で**——Claude Code、Codex、Cursor、GitHub Copilot、Antigravity、Kiro、Grok、DeepSeek、Kimi Code など。それぞれに専用のリングがあります。
- **Pulse のアカウントもサーバーもなし**——いまお使いのログインをそのまま使い、何も送り返しません。
- **表示するのは実際の数字だけ**——使用率はすべてサービス自身が報告した値です。数少ない推定値にはそう明記し、サービスが数字を出さないときは、推測せずにそのことを表示します。
- **ネイティブで控えめ**——Swift と SwiftUI 製で、macOS 26 では Liquid Glass。画面の左・右・上、または下の Dock の横に寄せられ、使っていないときは細い線に畳まれます。メニューバーだけで使うこともできます。

**最近の追加：** メニューバーでの使用量表示とアカウントごとのダッシュボード、リセット後に利用枠を自動で始める機能、動くボットのマーク。[更新内容](https://github.com/qunqin24/Pulse/releases/latest)。

<p align="center">
  <img src="Docs/images/bot-mark.gif" width="300" alt="Pulse のアニメーションマーク：各リングのボットがそのアカウントの状態に反応します">
</p>

<p align="center">
  <sub>Pulse のおかげで突然の上限を避けられたなら、⭐ をもらえると、ほかの人にも見つけてもらいやすくなります。</sub>
</p>

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

## 主な機能

### ひと目でわかるリング
- **使用量に合わせた色**——緑から琥珀、赤へ。アカウントごとに好きな色も選べます。
- **使用済みか残りか**——`75% 使用` か `25% 残り`。ウィンドウがどれだけ経ったかを示す時計の弧も付けられます。
- **動いていることがわかる**——エージェントの作業中はリング上で点が回ります。アカウントの状態に合わせて動く小さなボットも選べます。

### リングを指すと詳細
- **すべての上限とリセット時刻**を 1 枚のカードに。バーは連続か区切りかを選べます。
- **詳細カード**——プラン、読み取った時刻、各上限の推定額、この Mac の記録から見た最近の使用量。
- **消費ペースの予測**——いまのペースではウィンドウのリセット前に使い切るときに知らせます。
- **メニューバー**——いちばん使っているリングを数字・小さなリング・上限の並びで。ダッシュボードも開けます。

<p align="center">
  <img src="Docs/images/detailed-card.webp" width="620" alt="同じ Codex アカウントのコンパクトなカードと詳細カード">
</p>

### じゃまにならない
- **どこにでも**——左右、上、Dock の横、好きな場所に。使わないときは細い線にたたまれます。
- **選べる通知**——上限が線を越えたとき、使い切ったとき、リセット、チェックの失敗続き、残高不足、プロバイダの障害。
- **6 つの言語**——英語、簡体字中国語、繁体字中国語、日本語、韓国語、ロシア語。
- **任意の機能**——グローバルショートカット、アクティブなディスプレイへの追従、スクリーンショットから隠す。

### 使用量・状態・そのほか
- **トークン使用量**——54 のローカルクライアントの使用量を公開 API 価格で推定し、日・モデル・エージェント別に、好きな期間で。
- **推定額をあなたの通貨で**——米ドル、人民元、香港ドル、新台湾ドル、日本円、韓国ウォン、ロシア・ルーブル。
- **使用量のまとめ**——同じ記録から作る、1 日・1 週間・1 か月・1 年の共有できるカード。
- **サービスの状態**——44 のプロバイダの公式ステータスページ。障害時には通知も。
- **接続診断**——数字の取得元と、サーバーの応答そのもの。
- **使い込む人に**——プロバイダごとの複数アカウント、自分のデータ源を足す拡張機能、スクリプト用の `Pulse --json`。

<p align="center">
  <img src="Docs/images/spend.webp" height="290" alt="トークン使用量：合計、種類別トークン、日ごとの傾向">
  &nbsp;&nbsp;
  <img src="Docs/images/spend-history.webp" height="290" alt="トークン使用量：日別・月別・エージェント別">
</p>

**すべての機能の詳細**（英語）：[Docs/features.md](Docs/features.md)。

---

## 対応プロバイダとデータ経路

77 のサービスに対応し、それぞれその製品自身のやり方で読み取ります——製品の使用量エンドポイント、エディタのログイン、ローカルの Language Server、または貼り付けたキー。割合はすべてサービス自身が報告した値です。[一覧と各サービスの読み取り方](Docs/supported-services.md)（英語）。

---

## プライバシーとセキュリティ

- **Pulse のアカウントもサーバーもなし**——あなたの Mac が、あなた自身のログインで、使っているサービスにつなぎます。
- **接続先は五つだけ、すべてここに**——それらのサービス、その公開ステータスページ、モデル価格の [models.dev](https://models.dev)、米ドル以外の通貨を選んだときだけの [ExchangeRate-API](https://www.exchangerate-api.com)、更新確認の GitHub/Sparkle。
- **キーは暗号化してこの Mac に**。Pulse が読むローカルの使用記録も Mac の外には出ません。

[詳細](Docs/features.md#privacy-and-security)（英語）。

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
