# SKKense

読み: スケンス。第六勘つき SKK。

[macSKK](https://github.com/mtgto/macSKK)（mtgto 氏による macOS 向け SKK 入力メソッド）の fork です。SKK の明示的な変換操作はそのままに、次の 2 つを足すことを目的にしています。

- **文脈から変換候補を推論する**: カーソル前のテキストと辞書候補をローカルの小さな言語モデル（zenz-v3.1-xsmall、ONNX Runtime、CPU）に渡し、第 1 候補を選び直す。モデルは辞書にある候補の中から選ぶだけで、辞書にない語は生成しない。
- **送り仮名の位置が本来と違っても候補を出す**: `Kaku` と打つだけで `か|く` の区切りを辞書で探して「書く」を候補に出す。`MatiGa` のように送り仮名の開始位置が辞書の登録形とずれていても、読み全体から区切りを探し直す。

どちらも設定で個別に無効化でき、無効にすると macSKK と同じ動作になります。

## 状態

開発中。本家 macSKK と同じ Mac に並行インストールできるよう、Bundle Identifier（`io.github.rnnno.inputmethod.skkense`）とアプリ名（`SKKense.app`）、入力ソース名（「ひらがな (SKKense)」など）を本家と変えてあります。辞書や設定は本家とは別のコンテナ（`~/Library/Containers/io.github.rnnno.inputmethod.skkense/`）に置かれます。配布物（署名・公証済みのインストーラ）はありません。

本家への追従は `upstream`（mtgto/macSKK）のリリースごとに merge します。本家の使い方・設定は [macSKK のドキュメント](https://mtgto.github.io/macSKK/) を参照してください。

## ビルド

Xcode が必要です。

```sh
./build_restart.sh   # Debug ビルドして ~/Library/Input Methods/SKKense.app に配置し、プロセスを再起動
```

初回はシステム設定 → キーボード → 入力ソースで「ひらがな (SKKense)」を追加してください。辞書（`SKK-JISYO.L` など）は `~/Library/Containers/io.github.rnnno.inputmethod.skkense/Data/Documents/Dictionaries/` に置きます。

## 設計

- 送り仮名の自動解決は辞書の見出し語の規約（語幹 + 送り仮名 1 文字目の子音記号）だけで行い、活用表は持たない。雑音は活用語尾の許可リストと並び順で抑える。
- 文脈推薦は二段階採点（文脈と読みの KV キャッシュを先に作り、Space 押下時に候補だけを採点）で、Space 1 回あたり 20 ms 以内を上限にする。間に合わなければ従来の順序で表示する。

## ライセンスとクレジット

- 本体: GPL-3.0（macSKK を継承）。macSKK の著作権は mtgto 氏にあります。
- 文脈推薦モデル zenz-v3.1-xsmall（Keita Miwa 氏、CC-BY-SA 4.0）。同梱する場合はモデルのライセンスに従います。
