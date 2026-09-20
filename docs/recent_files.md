# 最近使ったファイル(`lib/recent.ahk` + `lib/fr.ps1`)

Windows が記録している「最近使った項目」を、ホットキーから fzf であいまい検索して開く機能です。元は単独の2ファイル構成(`recent-files.ahk` + `fr.ps1`)の仕様でしたが、このリポジトリでは本体 `claude_hotkey.ahk` の機能として組み込んでいます(第7章に変更点)。

| 項目 | 内容 |
|---|---|
| 起動 | `[General]` の `Recent` のキー(初期の INI では `Ctrl+Alt+O`) |
| 検索 UI | fzf(Windows Terminal 上で表示) |
| 対象 | `%APPDATA%\Microsoft\Windows\Recent` の `.lnk` が指すファイル・フォルダ |
| 開き方 | 関連付けられた既定のアプリ(フォルダはエクスプローラー) |

---

## 1. 概要

Windows が自動で記録している「最近使った項目」(`%APPDATA%\Microsoft\Windows\Recent` 内の `.lnk` ショートカット)を履歴として使います。独自の履歴 DB は持ちません。

## 2. 構成

| ファイル | 役割 |
|---|---|
| `lib/recent.ahk` | ホットキーで Windows Terminal を起動し、画面中央に置く(本体が `#Include`) |
| `lib/fr.ps1` | 履歴を取得して列に整形し、fzf に渡して、選ばれた項目を開く(PowerShell) |
| `tests/fr.tests.ps1` | `fr.ps1` の表示整形のテスト(Pester 不要)。`pwsh -File tests\fr.tests.ps1` |

`fr.ps1` は **UTF-8(BOM付き)・CRLF** で保存します。Windows PowerShell 5.1 は BOM のない UTF-8 を ANSI として読み、日本語のメッセージが化けるためです。

## 3. 設定(`[General]`)

| キー | 初期の INI | 内容 |
|---|---|---|
| `Recent` | `^!o` | 起動キー。空欄で無効。書き方は本体と同じ(`^`=Ctrl `!`=Alt `+`=Shift `#`=Win) |
| `RecentSize` | `110,30` | ターミナルの大きさ(列数,行数)。全角の数字・カンマも可 |
| `RecentShell` | `pwsh` | `pwsh`(PowerShell 7)または `powershell`(Windows PowerShell 5.1) |

既存の INI にはキーがないので、使うときは `[General]` に追記して再読み込みします。書かなければ `Recent` は無効、他は初期値です。

## 4. 動作

### ホットキー(`RecentFiles()`)

1. タイトルが `RecentFiles` で始まる Windows Terminal の窓があれば、新しく開かずにそれを前面に出す
2. なければ次のコマンドで新しいウィンドウとして起動する(`{…}` は設定値)

   ```text
   wt.exe -w new --size {RecentSize} new-tab --title RecentFiles --suppressApplicationTitle
       {RecentShell} -NoLogo -NoProfile -ExecutionPolicy Bypass -File "…\lib\fr.ps1"
   ```

3. 3 秒以内に窓が現れたら、**マウスのあるモニター**の作業領域の中央に置く(`MoveExact()` で見えない枠と DPI を補正)
4. `wt.exe` を起動できないとき(未インストール)、`fr.ps1` が無いときはメッセージを出す

### 検索・起動(`fr.ps1`)

- `.lnk` を更新日時の新しい順に並べ、リンク先のパスを取り出す。空のパス、存在しないパス、重複(大文字小文字は区別しない)を除く
- 1件を **「ファイル名  更新日時  フォルダ」の列**に整形して fzf に渡す。パスが長くてもファイル名が左端にそろう

  ```text
   Recent> 
     128/128 ────────────────────────────────────────────────────────────────────
   ▌ 請求書_202609.pdf                      09/19 14:02  ~\Downloads
     見積書_ABC商事_v3.xlsx                 09/19 11:40  ~\Documents\プロジェクト\2026\第3四半期
     窓整理\                                09/18 16:30  ~\Documents\プロジェクト
     経費精算_2026.xlsx                     09/18 09:12  \\nas\share\総務
     提案書_XYZ社_draft.pptx                09/16 13:08  ~\Documents\…\XYZ社\提案
  ```

  | 列 | 内容 |
  |---|---|
  | ファイル名 | 幅 42 桁(全角は 2 桁)。長ければ中央を `…` にして末尾 12 桁(拡張子側)を残す。フォルダは末尾に `\` |
  | 更新日時 | `.lnk` の更新日時 = その項目を最後に開いた日時。`MM/dd HH:mm` |
  | フォルダ | `%USERPROFILE%` を `~` に置き換える。長ければ先頭(`~` / `C:` / `\\server\share`)と末尾の要素を残して間を `…` にする |

- 列の幅は画面の幅(`RecentSize` の列数)から決める。110 列なら ファイル名 42・日時 11・フォルダ 50 で、fzf のポインター 2 桁とスクロールバー 1 桁を除いた 107 桁に収まる
- 各行は **フルパス + TAB + 表示用の文字列**。fzf には TAB の後ろだけを見せて検索させる(`--delimiter '\t' --with-nth 2 --nth 2`)ので、`C:\Users\<名前>` のような見えない部分には検索が当たらない。Enter で選ばれた行の TAB より前(フルパス)を開く
- fzf は上から下に表示(`--reverse`)。同じスコアなら新しい順(`--tiebreak=index`)
- Enter で開き、ウィンドウは自動で閉じる。Esc でも閉じる(`exit 0`)
- 入出力を UTF-8 にして日本語ファイル名の文字化けを防ぐ
- プロファイルを読まずに起動する(`-NoProfile`)
- fzf が見つからなければ、インストール方法を表示して Enter で閉じる。履歴が空のときも同様に知らせる
- 整形の関数は `tests/fr.tests.ps1` で検証する。`fr.ps1` を dot-source すると関数だけが読み込まれる(`$MyInvocation.InvocationName -eq '.'` で本体を飛ばす)

## 5. 必要環境

| ソフト | インストール |
|---|---|
| fzf | `winget install junegunn.fzf` |
| PowerShell 7 | `winget install Microsoft.PowerShell`(5.1 を使うなら `RecentShell=powershell`) |
| Windows Terminal | Windows 11 は標準搭載。10 は `winget install Microsoft.WindowsTerminal` |

## 6. 制約

- エクスプローラーや標準の「開く」ダイアログ経由で開いたものは記録されるが、VS Code など独自の履歴を持つアプリで開いたファイルは記録されないことがある
- 存在確認をするため、切断されたネットワークドライブ上の履歴があると表示が遅くなることがある
- Windows の設定で「最近使った項目の表示」がオフだと履歴が記録されない
- 検索ウィンドウは通常のアプリの窓なので、操作ログ(`docs/logging.md`)にも `create` / `activate` / `destroy` が記録される。ツールの操作としては `tool` 行の `action=recent`(`result`: `launched` / `activated` / `none` / `error`)

## 7. 元の仕様からの変更点

| 元の仕様 | このリポジトリ | 理由 |
|---|---|---|
| 単独の `recent-files.ahk`(常駐) | 本体の機能。`lib/recent.ahk` を `#Include` | 常駐スクリプトを増やさない。キーの重複検出・再読み込み・トレイメニュー・ログを共用する |
| ホットキー `Ctrl+Alt+R` 固定 | INI の `Recent`(初期値 `^!o`) | **`^!r` は本体の「設定の再読み込み」と重複する**。`^!r` にしたければ `Reload` を別のキーにする(重複すると起動時に一覧で知らせる) |
| `--size 110,30`、`pwsh` をコードに直書き | `RecentSize` / `RecentShell` | INI で変えられるように |
| 主モニターの中央に `WinMove` | マウスのあるモニターの中央に `MoveExact()` | 複数モニターと DPI、見えない枠に対応(本体の規約) |
| `WinExist("RecentFiles")` | タイトル先頭一致 + `ahk_exe WindowsTerminal.exe` | 他アプリの似たタイトルを誤検出しない |
| fzf が無いと即終了 | メッセージを出して Enter で閉じる | 原因が分かるように |
| パス全体を 1 列で表示し、パス全体を検索 | 「ファイル名  更新日時  フォルダ」の列表示。検索は見えている部分だけ | 長いパスでファイル名が切れる・位置がそろわない・`Users\名前` などにノイズが当たるのを防ぐ |

## 8. カスタマイズ

| 変更したいこと | 変更箇所 |
|---|---|
| ホットキー | INI の `Recent` |
| ウィンドウの大きさ | INI の `RecentSize` |
| シェル | INI の `RecentShell` |
| fzf の見た目・挙動 | `lib/fr.ps1` の `fzf` 行のオプション |
| 列の幅 | `lib/fr.ps1` の `$nameW`(ファイル名)と `$folderW`(フォルダ)の計算式 |
| 日時の書式 | `lib/fr.ps1` の `Format-Line` の `MM/dd HH:mm` |
