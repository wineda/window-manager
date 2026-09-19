# ウィンドウ整理ツール(AutoHotkey v2)

## 概要
- 本体: claude_hotkey.ahk / 設定: claude_hotkey.ini(初回起動時に自動生成)
- 仕様・設計・テスト手順: docs/claude_hotkey_handoff.md(第4〜10章)
- 機能: 呼び出し / レイアウト / 自動配置 / スナップ / 集中モード

## 守ること
- AutoHotkey **v2** の構文で書く。v1 の構文(コマンド形式、%var% 参照など)は使わない
- claude_hotkey.ini は UTF-16 LE(BOM付き)。UTF-8 で保存すると日本語のセクション名や値が読めなくなる
  - INI を直接書き換えない。初期内容を変えるときは CreateDefaultIni() の継続セクションを直す
  - どうしても編集が必要なら PowerShell で UTF-16 LE(BOM付き)として読み書きする
- INI の既存のセクション・キーの書式は変えない(利用者の設定が読めなくなるため)。追加は可
- 画面に出す文言とコメントは日本語
- ホットキーの追加は Reg() を通す(重複と書式エラーを検出するため)
- ウィンドウの移動は PlaceInZone() / MoveExact() を使う(見えない枠と DPI を補正するため)
- 関数の先頭で SetDpi() を呼ぶ(座標を物理ピクセルにそろえるため)

## AutoHotkey v2 の注意
- 文字列の中でも「空白+;」はコメント扱いになる。文字列に書くときは `` `; `` とエスケープする
- 継続セクション(CreateDefaultIni)の中にダブルクォートを書くと文字列が終わる
- 関数の中でグローバル変数に代入するときは global 宣言が必要(読むだけ、要素の変更だけなら不要)
- `x (y)` は連結、`x(y)` は関数呼び出し

## 確認方法
- 構文チェック(PowerShell):
  & "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate .\claude_hotkey.ahk 2>&1 | Out-String; $LASTEXITCODE
  - 0 なら問題なし。エラー時は行番号と内容が表示される
  - 警告も見るときは、先頭に #Warn All, StdOut を一時的に足して実行する
- 変更後は docs/claude_hotkey_handoff.md 第8章のチェックリストで動作確認する
