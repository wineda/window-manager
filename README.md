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
| 最近使ったファイル | `Ctrl+Alt+O` | Windows の「最近使った項目」を fzf であいまい検索して開く |

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
| `lib/recent.ahk` | 最近使ったファイルのモジュール(本体が `#Include`) | UTF-8(BOM なし)・CRLF |
| `lib/fr.ps1` | 最近使ったファイルの検索・起動(PowerShell) | UTF-8(BOM付き)・CRLF |
| `tests/fr.tests.ps1` | `fr.ps1` の表示整形のテスト | UTF-8(BOM付き)・CRLF |
| `claude_hotkey.ini` | 設定。無ければ初回起動時に自動生成 | UTF-16 LE(BOM付き)・CRLF |
| `docs/claude_hotkey_handoff.md` | 仕様・設計・テスト手順の全文 | UTF-8 |
| `docs/logging.md` | 操作ログの仕様(列・イベント・解析方法) | UTF-8 |
| `docs/recent_files.md` | 最近使ったファイルの仕様 | UTF-8 |
| `analysis/analyze.py` | 操作ログの解析(標準ライブラリのみ) | UTF-8 |
| `analysis/analyze.ps1` | 解析を Docker で実行するラッパー(Windows) | UTF-8(BOM付き)・CRLF |
| `analysis/Dockerfile` | 解析用イメージ(`python:3.12-slim` + 上の2スクリプト) | UTF-8 |
| `CLAUDE.md` | Claude Code 向けの開発ルール | UTF-8 |

`claude_hotkey.ini` はリポジトリに含めていません(初回起動時に生成されるため)。`.gitattributes` で
UTF-16 LE として扱う設定を入れてあるので、コミットすれば差分をテキストで確認できます。

## 操作ログ

ウィンドウの生成・切り替え・移動・最小化と、ツールの操作を CSV に記録して、
[仕様書 第7章](docs/claude_hotkey_handoff.md) の「散らかりのモデル」の各パラメータ(λ・W・d・r・p・k)を実測できます。

1. `claude_hotkey.ini` の `[General]` に `Log=1` を書いて再読み込みする
2. `%LOCALAPPDATA%\claude_hotkey\logs\YYYY-MM-DD.csv` に1日1ファイルで記録される(トレイメニュー「ログフォルダを開く」)
3. 解析する(Docker Desktop が必要。Python のインストールは不要):

   ```powershell
   powershell -ExecutionPolicy Bypass -File analysis\analyze.ps1
   ```

   初回だけ解析用のイメージを作ります(数十秒)。別のフォルダや `analyze.py` のオプションも渡せます:
   `analysis\analyze.ps1 -LogDir D:\logs --min-life 5`

   Docker を直接使う場合(Windows 以外も同じ):

   ```sh
   docker build -t claude-hotkey-analyze analysis
   docker run --rm -v "<ログフォルダ>:/logs:ro" claude-hotkey-analyze
   ```

ウィンドウのタイトルは既定では記録しません。列の意味と解析方法は [`docs/logging.md`](docs/logging.md) を参照してください。
サンプルは `analysis/sample/` にあります。

## 最近使ったファイル

`Ctrl+Alt+O` で Windows Terminal が開き、Windows の「最近使った項目」を fzf であいまい検索できます。Enter で既定のアプリで開き、Esc で閉じます。
一覧は「ファイル名  更新日時  フォルダ」の列で、パスが長くてもファイル名が左にそろいます。検索は見えている部分だけに当たります。

必要なもの(いずれも `winget install` で入ります):fzf(`junegunn.fzf`)、PowerShell 7(`Microsoft.PowerShell`)、Windows Terminal(11 は標準搭載)。
キーや大きさは `[General]` の `Recent` / `RecentSize` / `RecentShell` で変えられます。詳しくは [`docs/recent_files.md`](docs/recent_files.md)。

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

解析スクリプトのテスト(合成ログで手計算した値と照合)。Docker で:

```powershell
powershell -ExecutionPolicy Bypass -File analysis\analyze.ps1 -Test
```

Python がある環境なら `python analysis\test_analyze.py` でも同じです。

最近使ったファイルの表示整形のテスト(全角の幅、省略、フォルダの短縮):

```powershell
pwsh -File tests\fr.tests.ps1
```
