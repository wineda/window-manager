# ウィンドウ整理ツール(AutoHotkey v2)

キー操作でウィンドウを整理する、Windows 用の常駐スクリプトです。

| 機能 | 既定のキー | 内容 |
|---|---|---|
| 呼び出し | `Ctrl+Alt+C` ほか | 指定アプリを画面中央に指定サイズで表示。もう一度押すと最小化。起動していなければ起動する |
| レイアウト | `Ctrl+Alt+F1` / `F2` | 登録アプリのウィンドウをまとめて定位置に並べる |
| 自動配置 | なし(常時) | アプリを起動したら、そのアプリの定位置に置く |
| スナップ | `Ctrl+Alt+G` → 位置キー | アクティブウィンドウを分割位置に置く。Windows 標準にない3分割も可 |
| 集中モード | `Ctrl+Alt+F` | アクティブ以外を最小化。もう一度押すと復元 |

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
| `claude_hotkey.ahk` | 本体(640行) | UTF-8(BOM なし)・CRLF |
| `claude_hotkey.ini` | 設定。無ければ初回起動時に自動生成 | UTF-16 LE(BOM付き)・CRLF |
| `docs/claude_hotkey_handoff.md` | 仕様・設計・テスト手順の全文 | UTF-8 |
| `CLAUDE.md` | Claude Code 向けの開発ルール | UTF-8 |

`claude_hotkey.ini` はリポジトリに含めていません(初回起動時に生成されるため)。`.gitattributes` で
UTF-16 LE として扱う設定を入れてあるので、コミットすれば差分をテキストで確認できます。

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
