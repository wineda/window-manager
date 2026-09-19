# ウィンドウ整理ツール(AutoHotkey v2)

キー操作でウィンドウを整理する、Windows 用の常駐スクリプトです。

| 機能 | 既定のキー | 内容 |
|---|---|---|
| 呼び出し | `Ctrl+Alt+C` ほか | 指定アプリを画面中央に指定サイズで表示。もう一度押すと最小化。起動していなければ起動する |
| レイアウト | `Ctrl+Alt+F1` / `F2` | 登録アプリのウィンドウをまとめて定位置に並べる |
| 自動配置 | なし(常時) | アプリを起動したら、そのアプリの定位置に置く |
| スナップ | `Ctrl+Alt+G` → 位置キー | アクティブウィンドウを分割位置に置く。Windows 標準にない3分割も可 |
| 集中モード | `Ctrl+Alt+F` | アクティブ以外を最小化。もう一度押すと復元 |
| 操作ログ | なし(設定で有効化) | ウィンドウの操作を CSV に記録し、散らかり方を実測する(既定は無効) |

## 動作環境

- Windows 10 / 11
- AutoHotkey v2.0 系

## 使い方

1. AutoHotkey v2 をインストールする。
2. `claude_hotkey.ahk` を実行する。同じフォルダに `claude_hotkey.ini` が無ければ、初回起動時に自動生成される。
3. 設定を変えたら `Ctrl+Alt+R`、またはトレイアイコンの右クリック →「設定を再読み込み」で反映する。

PC 起動時に自動で動かすには、`Win + R` →「`shell:startup`」で開くフォルダに `claude_hotkey.ahk` のショートカットを置きます。

## ファイル構成

| ファイル | 内容 | 文字コード・改行 |
|---|---|---|
| `claude_hotkey.ahk` | 本体 | UTF-8(BOM なし)・CRLF |
| `lib/log.ahk` | 操作ログのモジュール(本体が `#Include`) | UTF-8(BOM なし)・CRLF |
| `claude_hotkey.ini` | 設定。無ければ初回起動時に自動生成 | UTF-16 LE(BOM付き)・CRLF |
| `docs/claude_hotkey_handoff.md` | 仕様・設計・テスト手順の全文 | UTF-8 |
| `docs/logging.md` | 操作ログの仕様(列・イベント・解析方法) | UTF-8 |
| `analysis/analyze.py` | 操作ログの解析(標準ライブラリのみ) | UTF-8 |
| `CLAUDE.md` | Claude Code 向けの開発ルール | UTF-8 |

`claude_hotkey.ini` はリポジトリに含めていません(初回起動時に生成されるため)。`.gitattributes` で
UTF-16 LE として扱う設定を入れてあるので、コミットすれば差分をテキストで確認できます。

## 操作ログ

ウィンドウの生成・切り替え・移動・最小化と、ツールの操作を CSV に記録して、
[仕様書 第7章](docs/claude_hotkey_handoff.md) の「散らかりのモデル」の各パラメータ(λ・W・d・r・p・k)を実測できます。

1. `claude_hotkey.ini` の `[General]` に `Log=1` を書いて再読み込みする
2. `%LOCALAPPDATA%\claude_hotkey\logs\YYYY-MM-DD.csv` に1日1ファイルで記録される(トレイメニュー「ログフォルダを開く」)
3. 解析する:

   ```powershell
   python analysis\analyze.py "$env:LOCALAPPDATA\claude_hotkey\logs"
   ```

ウィンドウのタイトルは既定では記録しません。列の意味と解析方法は [`docs/logging.md`](docs/logging.md) を参照してください。
サンプルは `analysis/sample/` にあります。

## 開発

詳しい仕様は [`docs/claude_hotkey_handoff.md`](docs/claude_hotkey_handoff.md) を参照してください
(第4章 機能仕様 / 第5章 設定ファイル / 第6章 内部設計 / 第8章 テスト)。

構文チェック(Windows・PowerShell):

```powershell
$ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"   # インストール先に合わせる
& $ahk /ErrorStdOut /validate .\claude_hotkey.ahk 2>&1 | Out-String
"exit code: $LASTEXITCODE"   # 0 なら問題なし
```

変更後は、同資料 第8.4節の実機チェックリストで動作を確認してください。

解析スクリプトのテスト(合成ログで手計算した値と照合):

```powershell
python analysis\test_analyze.py
```
