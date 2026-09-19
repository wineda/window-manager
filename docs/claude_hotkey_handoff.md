# ウィンドウ整理ツール(AutoHotkey v2)引き継ぎ資料

claude.ai のチャットで作った AutoHotkey スクリプトを Claude Code に移すための資料です。ソース全文と仕様をこの1ファイルにまとめています。

| 項目 | 内容 |
|---|---|
| 本体 | `claude_hotkey.ahk`(640行。付録Aに全文) |
| 設定 | `claude_hotkey.ini`(無ければ初回起動時に自動生成) |
| 動作環境 | Windows 10 / 11、AutoHotkey v2.0 系 |
| 最終更新 | 2026-09-19 |

---

## 0. Claude Code での始め方

1. 作業用の空フォルダにこのファイルを置き、そのフォルダで Claude Code を起動します。
2. 次のように依頼します。

   ```text
   claude_hotkey_handoff.md を docs/ に移して、付録Aから claude_hotkey.ahk を、
   第2章の雛形から CLAUDE.md を作って。そのあと第8章のコマンドで構文チェックをして。
   ```

3. すでに使っている `claude_hotkey.ini` があれば、同じフォルダにコピーします(設定を引き継げます)。

できあがる構成は次のとおりです。

```text
project/
├── CLAUDE.md                     … 第2章の雛形(Claude Code が毎回読む指示)
├── claude_hotkey.ahk             … 付録A
├── claude_hotkey.ini             … 初回起動で自動生成(既存の設定があればそれを置く)
└── docs/
    └── claude_hotkey_handoff.md  … この資料
```

**ファイルを作るときの注意(Claude Code 向け)**

- `claude_hotkey.ahk` は付録Aのコードブロックの中身を**1文字も変えずに**保存する。文字コードは UTF-8、改行は CRLF 推奨。
- `claude_hotkey.ini` は作らない。スクリプトの初回起動時に `CreateDefaultIni()` が UTF-16 LE(BOM付き)で生成する。既存の INI は上書きしない。

---

## 1. 概要

キー操作でウィンドウを整理する常駐スクリプトです。機能は5つあります。

| 機能 | 既定のキー | 内容 |
|---|---|---|
| 呼び出し | Ctrl+Alt+C など | 指定アプリを画面中央に指定サイズで表示。もう一度押すと最小化。起動していなければ起動する |
| レイアウト | Ctrl+Alt+F1 / F2 | 登録アプリのウィンドウをまとめて定位置に並べる |
| 自動配置 | なし(常時) | アプリを起動したら、そのアプリの定位置に置く |
| スナップ | Ctrl+Alt+G → 位置キー | アクティブウィンドウを分割位置に置く。Windows 標準にない3分割も可 |
| 集中モード | Ctrl+Alt+F | アクティブ以外を最小化。もう一度押すと復元 |

設定はすべて `claude_hotkey.ini` で管理します。変更後は Ctrl+Alt+R またはトレイメニューで再読み込みします。

---

## 2. CLAUDE.md の雛形

Claude Code はプロジェクト直下の `CLAUDE.md` をセッション開始時に読み込みます(参考: https://code.claude.com/docs/en/memory )。下のブロックの中身を `CLAUDE.md` として保存してください。

````markdown
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
````

---

## 3. ファイル構成

| ファイル | 内容 | 文字コード・改行 |
|---|---|---|
| `claude_hotkey.ahk` | 本体 | UTF-8、CRLF 推奨(AutoHotkey v2 は BOM なしの UTF-8 を読める) |
| `claude_hotkey.ini` | 設定。無ければ初回起動時に自動生成 | UTF-16 LE(BOM付き)、CRLF |

- PC 起動時に自動で動かすには、`Win + R` →「`shell:startup`」で開くフォルダに `claude_hotkey.ahk` のショートカットを置きます。
- git で管理する場合、`.gitattributes` に `claude_hotkey.ini text working-tree-encoding=UTF-16LE-BOM eol=crlf` を書くと、INI の差分をテキストとして確認できます。

---

## 4. 機能仕様

### 4.1 呼び出し(`ShowWindow`)

`[General]`・`[Snap]`・`[Layout:*]` 以外のセクションが、それぞれ1つの呼び出し設定になります。

1. `Process` のウィンドウを `FindAppWindow()` で探す(`IsAppWindow()` を満たす最初のウィンドウ)。
2. 見つからなければ `Path` を実行する。
   - 実行した時刻を `Launching[Process]` に記録する(自動配置と取り合わないため。4.3参照)。
   - 500ms ごとに最大30回(15秒)ウィンドウを探し、見つかったら 300ms 待つ。見つからなければ何もしない。
   - 実行に失敗したら、Path を確認するようメッセージを出す。
3. マウスカーソルのあるモニターの作業領域(タスクバーを除く)の中央に、`Width` × `Height` で置く位置を計算する。
4. 最小化の判定:次をすべて満たすときは最小化して終わる。
   - `ToggleMinimize=1`
   - 対象ウィンドウがアクティブで、最小化も最大化もされていない
   - 見た目の位置とサイズ(`VisibleRect()`)が、計算した位置と ±2px 以内
   - このため、同じアプリでもサイズの違う設定のキーを押すと、最小化ではなくサイズの切り替えになる。
5. 最小化・最大化されていれば `RestoreIfNeeded()` で通常の状態に戻し、`MoveExact()` で配置してアクティブにする。
6. `AlwaysOnTop` を毎回設定する(1=最前面に固定、0=解除)。

サイズは数値なら px(物理ピクセル)、`%` 付きなら作業領域に対する割合です。全角の数字や `%` も使えます。

### 4.2 レイアウト(`ApplyLayout`)

- `[Layout:名前]` の `Key` で実行する。
- 「実行ファイル名=位置」ごとに、そのプロセスの `IsAppWindow()` を満たすウィンドウをすべて `PlaceInZone()` で配置する。同じプロセスのウィンドウが複数あると、同じ位置に重なる。
- 置くモニターは、マウスカーソルのあるモニター。位置に `@n` があればそのモニター。
- 配置したウィンドウをすべて前面に出し(`WinMoveTop`)、実行前にアクティブだったウィンドウが含まれていればそれを、なければ最初に配置したウィンドウをアクティブにする。
- 対象のウィンドウが1つもなければ、ツールチップで知らせる。

### 4.3 自動配置(`OnShellMsg` / `AutoPlace`)

- `[General]` の `AutoLayout` にレイアウト名を書くと有効になり、そのレイアウトの「実行ファイル名=位置」を使う。
- `RegisterShellHookWindow` で `HSHELL_WINDOWCREATED`(=1)を受け取り、600ms 後に `AutoPlace()` を実行する。
- 次をすべて満たすときだけ配置する。
  - ウィンドウが存在し、`IsAppWindow()` を満たす
  - プロセスが `AutoLayout` のレイアウトに含まれる
  - そのプロセスを呼び出し機能で起動してから30秒以上たっている
  - そのプロセスの `IsAppWindow()` を満たすウィンドウがほかにない(=アプリ起動時の最初のウィンドウ。ポップアップや2枚目以降のウィンドウは動かさない)
- 置くモニターはマウスカーソルのあるモニター(`@n` があればそのモニター)。

### 4.4 スナップ(`SnapMenu`)

- `[General]` の `Snap` のキーで始める。アクティブウィンドウが `IsAppWindow()` を満たさなければ何もしない。
- 最大化を解除する前に、ウィンドウの中心があるモニターを決めておく(解除後の位置が別のモニターにある場合があるため)。
- `[Snap]` の一覧をツールチップで出し、`InputHook("T3")` で次のキーを1つ待つ。
  - すべてのキーを終了キー兼抑制(`ES`)にし、修飾キー(Ctrl / Alt / Shift / Win)だけ除く。ホットキーの修飾キーを押したままでも誤判定しない。
  - Esc、3秒のタイムアウト、登録されていないキーのときは何もしない。
- キー名は `NormalizeKey()` で正規化する(`Numpad7` や `NumpadHome` → `7`、英字は小文字)。
- ツールチップには `[Snap]` の記載順に、3つずつ改行して表示する。

### 4.5 集中モード(`ToggleFocus`)

- 前回最小化したウィンドウ(`FocusStash`)のうち、まだ最小化中のものがあれば、それらを元に戻す。奥にあったものから順に戻して重なり順を保ち、最後に元のアクティブウィンドウをアクティブにする。
- なければ、アクティブ以外の `IsAppWindow()` を満たすウィンドウ(最小化済みを除く)を最小化し、重なり順で `FocusStash` に記録する。
- `FocusStash` はメモリ上だけにあり、再読み込みで消える。

### 4.6 トレイメニュー

| 項目 | 動作 |
|---|---|
| 登録キーの一覧 | `UsedKeys` を「Ctrl+Alt+C  呼び出し「Claude 通常」」の形で表示 |
| 設定ファイルを開く | メモ帳で INI を開く |
| 設定を再読み込み | `Reload()` |

アイコンにマウスを乗せると「ウィンドウ整理ツール」と表示されます。

### 4.7 設定の問題の扱い

- 読み込み中に見つかった問題は `Errors` に集め、最後に1回だけ一覧を表示する。問題のない設定はそのまま有効になる。
- 検出する問題:キーの重複、キーの書式(`Hotkey()` が失敗)、位置の書式、`Width` / `Height` の書式、呼び出し設定の `Key` なし、`AutoLayout` のレイアウトが存在しない。

---

## 5. 設定ファイルの仕様(`claude_hotkey.ini`)

### 5.1 形式

- UTF-16 LE(BOM付き)、CRLF。`IniRead`(Windows の GetPrivateProfileString)で日本語を扱うため。
- コメントは行頭の `;`。行の途中の「空白+`;`」以降も `Clean()` で取り除く(書き間違いの救済)。
- セクションは4種類:`[General]`、`[Snap]`、`[Layout:名前]`、それ以外(呼び出し設定)。

### 5.2 `[General]`

| キー | 書かないとき | 初期の INI | 内容 |
|---|---|---|---|
| `Reload` | 無効 | `^!r` | 設定の再読み込み |
| `Focus` | 無効 | `^!f` | 集中モード |
| `Snap` | 無効 | `^!g` | スナップを始めるキー |
| `AutoLayout` | 無効 | `作業` | 自動配置に使うレイアウト名 |
| `Gap` | `0` | `0` | ウィンドウ同士の隙間(px)。画面の端は半分。偶数を推奨(奇数は切り捨て) |

### 5.3 `[Snap]`

`キー=位置` の形で書きます。キーは1つ(数字・英字・テンキーなど)です。初期値は次のとおりです。

| キー | 位置 | キー | 位置 | キー | 位置 |
|---|---|---|---|---|---|
| 7 | 左上 | 8 | 上半分 | 9 | 右上 |
| 4 | 左半分 | 5 | 中央 | 6 | 右半分 |
| 1 | 左下 | 2 | 下半分 | 3 | 右下 |
| q | 左1/3 | w | 中1/3 | e | 右1/3 |
| a | 左2/3 | s | 全体 | d | 右2/3 |

### 5.4 `[Layout:名前]`

- `Key=`:実行するキー。省略すると自動配置専用のレイアウトになる。
- `実行ファイル名=位置`:何行でも書ける。実行ファイル名の大文字・小文字は区別しない。

初期値:

| レイアウト | Key | 内容 |
|---|---|---|
| 作業 | `^!F1` | `msedge.exe`・`chrome.exe`=左2/3、`claude.exe`=右1/3 |
| 資料比較 | `^!F2` | `msedge.exe`・`chrome.exe`=左半分、`WINWORD.EXE`・`EXCEL.EXE`=右半分 |

### 5.5 呼び出し設定(その他のセクション)

| キー | 書かないとき | 内容 |
|---|---|---|
| `Key` | (必須) | 呼び出すキー |
| `Process` | `claude.exe` | 対象の実行ファイル名 |
| `Path` | `Process` と同じ | 起動していないときに実行するパス。`%LOCALAPPDATA%` などの環境変数を使える |
| `Width` / `Height` | `1200` / `800` | px、または `%`(作業領域に対する割合) |
| `AlwaysOnTop` | `0` | 1=常に最前面 |
| `ToggleMinimize` | `1` | 1=前面で同じ位置・サイズのときに押すと最小化 |

初期値:

| セクション | Key | 内容 |
|---|---|---|
| `[Claude 通常]` | `^!c` | 1200×800 |
| `[Claude 大きめ]` | `^!+c` | 90%×90%、最前面 |
| `[メモ帳]` | `^!n` | `notepad.exe`、800×600 |

Claude の `Path` は `%LOCALAPPDATA%\AnthropicClaude\claude.exe` です。

### 5.6 位置の書き方

作業領域(タスクバーを除く画面)に対する割合です。

| 名前 | X | Y | 幅 | 高さ |
|---|---|---|---|---|
| 全体 | 0 | 0 | 1 | 1 |
| 中央 | 0.15 | 0.1 | 0.7 | 0.8 |
| 左半分 / 右半分 | 0 / 0.5 | 0 | 0.5 | 1 |
| 上半分 / 下半分 | 0 | 0 / 0.5 | 1 | 0.5 |
| 左1/3 / 中1/3 / 右1/3 | 0 / 1/3 / 2/3 | 0 | 1/3 | 1 |
| 左2/3 / 右2/3 | 0 / 1/3 | 0 | 2/3 | 1 |
| 左上 / 右上 | 0 / 0.5 | 0 | 0.5 | 0.5 |
| 左下 / 右下 | 0 / 0.5 | 0.5 | 0.5 | 0.5 |

- 数値で指定するときは `X,Y,幅,高さ`(%、4つとも必須)。例:`0,0,60,100`
- 末尾に `@n` を付けると n 台目のモニター。存在しない番号なら既定のモニター。例:`左半分@2`
- 全角の数字・`/`・`@`・`,`・`%`・`.` は半角に直してから読む。

### 5.7 キーの書き方

AutoHotkey のホットキー表記です。`^`=Ctrl、`!`=Alt、`+`=Shift、`#`=Win。例:`^!c`、`^!F1`、`#c`

---

## 6. 内部設計

### 6.1 グローバル変数

| 名前 | 種類 | 内容 |
|---|---|---|
| `INI` | 文字列 | 設定ファイルのパス(スクリプトと同じフォルダ) |
| `Cfg` | Object | `Gap` |
| `SnapList` | Array | `[キー, 位置]` の配列(ツールチップ用、記載順) |
| `SnapMap` | Map | 正規化したキー → 位置 |
| `AutoApps` | Map | 実行ファイル名 → 位置(自動配置用) |
| `Launching` | Map | 実行ファイル名 → 呼び出しで起動した時刻(`A_TickCount`) |
| `FocusStash` | Array | 集中モードで最小化したウィンドウ(重なり順) |
| `UsedKeys` | Map | ホットキー → 表示名(重複チェックと一覧表示用) |
| `Errors` | Array | 設定の問題のメッセージ |

Map はすべて `NewMap()`(大文字・小文字を区別しない)で作ります。

### 6.2 関数一覧

| 分類 | 関数 | 役割 |
|---|---|---|
| 読み込み | `LoadAll(path)` | INI 全体を読み、ホットキー・スナップ・レイアウト・自動配置を登録 |
| | `LoadLayout(path, sec)` | `[Layout:名前]` を `{Name, Key, Apps}` にする |
| | `LoadProfile(path, sec)` | 呼び出し設定を `{Name, Key, Process, Width, Height, OnTop, Toggle, Path}` にする |
| | `Reg(key, fn, label)` | ホットキーを登録。重複・書式エラーを `Errors` に積む |
| | `ReadSection(path, sec)` | セクションを `[キー, 値]` の配列で返す(記載順を保つ) |
| | `CheckZone(spec, label)` | 位置の書式を検査 |
| 機能 | `ShowWindow(p, *)` | 呼び出し(4.1) |
| | `ApplyLayout(L, *)` | レイアウト(4.2) |
| | `OnShellMsg(wParam, lParam, *)` / `AutoPlace(hwnd)` | 自動配置(4.3) |
| | `SnapMenu(*)` / `SnapHelp()` / `NormalizeKey(k)` | スナップ(4.4) |
| | `ToggleFocus(*)` | 集中モード(4.5) |
| 位置計算 | `ParseZone(spec)` | 位置の文字列 → `{x, y, w, h, mon}`(割合)。不正なら `ValueError` |
| | `PlaceInZone(hwnd, spec, defMon)` | 位置に合わせて配置(Gap を反映) |
| | `ParseSize(val, total)` | `1200` → px、`70%` → 割合から px |
| | `MoveExact(hwnd, x, y, w, h)` | 見えない枠を補正して、見た目どおりの位置・サイズに移動 |
| | `VisibleRect(hwnd)` | 見た目の矩形(DWM の枠)。取れなければ `WinGetPos` |
| | `RestoreIfNeeded(hwnd)` | 最小化・最大化を通常の状態に戻す |
| 判定 | `IsAppWindow(hwnd)` | タスクバーに出る普通のウィンドウか |
| | `IsCloaked(hwnd)` | 別の仮想デスクトップなどで隠れているか |
| | `FindAppWindow(proc)` | プロセスの最初の普通のウィンドウ |
| | `MonitorAt(x, y)` / `MouseMonitor()` / `WindowMonitor(hwnd)` | モニター番号を返す |
| 補助 | `SetDpi()` | スレッドを Per-Monitor DPI v2 にする |
| | `ShowTip(msg)` | 1.5秒だけツールチップを出す |
| | `ShowKeyList(*)` / `KeyName(k)` | 登録キーの一覧、`^!c` → `Ctrl+Alt+C` |
| | `NewMap()` / `Clean(s)` / `ToInt(v, def)` / `ToHalf(s)` / `ExpandEnv(s)` | 小さな共通処理 |
| | `CreateDefaultIni(path)` | 初期の INI を UTF-16 で書き出す |

### 6.3 座標とウィンドウの扱い

- **DPI**:各処理の最初に `SetDpi()`(`SetThreadDpiAwarenessContext(-4)`)を呼び、座標をすべて物理ピクセルにそろえる。拡大率の違うモニターが混在してもずれないようにするため。
- **見えない枠**:Windows 10 / 11 のウィンドウは、影の部分(左右と下におよそ7px)が `WinGetPos` の範囲に含まれる。`DwmGetWindowAttribute`(`DWMWA_EXTENDED_FRAME_BOUNDS`=9)で見た目の矩形を取り、差分を足して `WinMove` する。モニターをまたいで DPI が変わる場合に備え、最大2回繰り返す。
- **位置の比較**:トグルの判定などは `VisibleRect()`(見た目の矩形)で比べる。
- **分割の丸め**:区画の左端と右端をそれぞれ丸めてから幅を出すので、隣の区画との間に隙間や重なりができない。
- **状態の復元**:`RestoreIfNeeded()` は「最小化 →(元が最大化なら)最大化 → 通常」の2段階に対応し、各段階の後に 100ms 待つ。
- **対象ウィンドウの判定**(`IsAppWindow()`):表示中、タイトルあり、デスクトップ・タスクバー(`Progman`、`WorkerW`、`Shell_TrayWnd`、`Shell_SecondaryTrayWnd`)でない、`WS_EX_NOACTIVATE` でない、`WS_EX_APPWINDOW` でなければツールウィンドウでも所有者付き(ダイアログなど)でもない、Cloaked でない。
- **モニターの判定**:どのモニターかは `MonitorGet`(タスクバー込み)で判定し、配置の計算は `MonitorGetWorkArea`(タスクバー除く)で行う。

---

## 7. 設計の背景(散らかりのモデル)

ウィンドウが散らかる理由を4つの式で考え、各機能がどれかの項を改善するように設計しています。

| 式 | 意味 |
|---|---|
| 配置の数 = kᴺ × N! | N 個のウィンドウ、置き場所の候補 k 通り、重なり順 N! 通り。整った配置はごく一部なので、放っておくと散らかる |
| N = λ × W | リトルの法則。λ=1時間に開く数、W=1つを開いておく平均時間 |
| ずれている割合 = d / (d + r) | 2状態マルコフ連鎖。d=ずれる頻度、r=片付ける頻度 |
| 重なる組の数 = N(N−1)/2 × p | 幅・高さとも画面の半分より大きいウィンドウは、どこに置いても中心を覆うので p = 1 |

| 改善する項 | 対応する機能 |
|---|---|
| W を短く | 呼び出し(もう一度押すと最小化)、集中モード |
| d を小さく | 自動配置 |
| r を大きく | レイアウト、スナップ(片付けがキー1つで済む) |
| p を0に近づける | 区画に分けた配置(レイアウト、スナップ) |
| k を1にする | 定位置(レイアウト、自動配置) |

式を動かして確かめられる可視化ページ:https://claude.ai/artifact/S8gxFEGjpHx9ygjGekKkNp (claude.ai の非公開アーティファクト)

---

## 8. テストと検証

### 8.1 実施済みの確認(2026-09-19)

- **構文**:AutoHotkey 2.0.28 の `/validate` でエラーなし。`#Warn All` を付けても警告なし(Linux 上の Wine で実行)。
- **設定の読み込み**:初期の INI、配布した INI、わざと壊した INI を読み込み、7種類の問題(キーの重複、位置の書式×2、サイズの書式、キーの書式、Key なし、存在しない AutoLayout)をすべて検出。
- **関数**:`ParseZone`(全角・`@2`・数値指定)、`ParseSize`、`NormalizeKey`、`KeyName`、`Clean`、`ExpandEnv` の結果を確認。
- **Wine のメモ帳での動作**:各位置への配置、Gap、最大化からの配置、呼び出し → 最小化 → 復元、集中モード、レイアウト、自動配置の条件(2枚目のウィンドウと呼び出し直後は動かさない)。
- **未確認(実機の Windows が必要)**:見えない枠の補正(Wine には DWM がないため代わりの処理だけ通過)、複数モニターと DPI の混在、シェルフックが実際に届くタイミング、Claude デスクトップ版での動作。

### 8.2 構文チェックのコマンド

AutoHotkey はウィンドウアプリなので、出力をパイプで受けないとシェルが終了を待ちません。

PowerShell:

```powershell
$ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"   # インストール先に合わせる
& $ahk /ErrorStdOut /validate .\claude_hotkey.ahk 2>&1 | Out-String
"exit code: $LASTEXITCODE"   # 0 なら問題なし
```

Git Bash(`/validate` などがパスに変換されないように `MSYS_NO_PATHCONV=1` を付ける):

```bash
MSYS_NO_PATHCONV=1 "/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe" /ErrorStdOut /validate claude_hotkey.ahk 2>&1 | cat
echo "exit code: ${PIPESTATUS[0]}"
```

### 8.3 関数だけを試す方法

本体のうち「`;  設定の読み込み`」の見出しコメントから下は関数定義だけです。この部分を別ファイルに切り出し、先頭にテスト用のコードを付けて実行すると、ホットキーを登録せずに関数を試せます。結果は `` FileAppend(文字列 "`n", "*", "UTF-8") `` で標準出力に出します。テスト用のコードでは、`Cfg`・`SnapList`・`SnapMap`・`AutoApps`・`Launching`・`FocusStash`・`UsedKeys`・`Errors` をグローバルで用意してください。

### 8.4 実機での動作確認チェックリスト

- [ ] 初回起動で INI が作られ、エラーが出ない
- [ ] Ctrl+Alt+C:Claude が画面中央に 1200×800 で出る。もう一度押すと最小化される。最大化した状態からでも中央に戻る
- [ ] Ctrl+Alt+Shift+C:90% の大きさで最前面に出る。続けて Ctrl+Alt+C を押すと 1200×800 になり、最前面が外れる
- [ ] Claude を終了した状態で Ctrl+Alt+C:起動して中央に出る(自動配置で右1/3に動かされない)
- [ ] Ctrl+Alt+F1:Edge / Chrome が左2/3、Claude が右1/3 に並ぶ。隣り合うウィンドウの間に隙間ができない
- [ ] `Gap=8` にすると、ウィンドウの間と画面の端の隙間がそろう
- [ ] Ctrl+Alt+G → 各キー:表のとおりの位置に動く。テンキーでも動く。Esc か3秒放置で何もしない
- [ ] Ctrl+Alt+F:ほかのウィンドウが最小化される。もう一度押すと元の重なり順で戻る
- [ ] Edge を起動すると左2/3に置かれる。2枚目のウィンドウやポップアップは動かない
- [ ] INI に重複したキーや不正な位置を書くと一覧でエラーが出て、ほかの設定は使える
- [ ] 複数モニター:マウスのあるモニターに出る。`@2` を付けると2台目に出る
- [ ] 拡大率の違うモニター間でスナップしても位置がずれない
- [ ] トレイメニューの「登録キーの一覧」「設定ファイルを開く」「設定を再読み込み」が動く

---

## 9. 既知の制約

- 管理者権限で動いているアプリのウィンドウは、スクリプトも管理者として実行しないと動かせない場合がある。
- ストアアプリ(電卓・設定など)は `ApplicationFrameHost.exe` のウィンドウになるため、実行ファイル名で指定できない。
- 起動後に自分で位置を復元するアプリは、600ms 後の自動配置と取り合うことがある。
- レイアウトでは、同じプロセスの複数のウィンドウが同じ位置に重なる。
- Ctrl+Alt+英字は、アプリのショートカットと重なることがある(例:Word の Ctrl+Alt+F は脚注の挿入)。
- Claude デスクトップ版のインストール先が違う場合(ストア版など)は、`Path` を書き換える必要がある。
- 集中モードの記録は、再読み込みすると消える。
- `Width` / `Height` の px は物理ピクセルなので、拡大率150%などの画面では見た目が小さくなる。
- 設定ファイルは UTF-16 でないと、日本語のセクション名や値を読めない。

---

## 10. 今後の改善候補

- **操作ログの記録**(チャットで検討済み):アクティブの切り替え、移動、最小化、ホットキーの使用を CSV に記録し、第7章の λ・W・d・r を実測する。ウィンドウタイトルは記録しないか伏せ字にできるようにする。
- **INI を UTF-8 で扱う**:`IniRead` をやめ、`FileRead` と自前の読み取り処理に置き換える。エディタや Claude Code から直接編集しやすくなる。
- 同じアプリの複数のウィンドウを、区画の中で少しずつずらして置く。
- スナップで隣のモニターへ移すキー。
- 今の配置をレイアウトとして INI に書き出す機能。
- 設定を編集する画面(GUI)。

---

## 付録A:`claude_hotkey.ahk` 全文

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================
;  ウィンドウ整理ツール
;    呼び出し   … 指定アプリを画面中央へ(もう一度押すと最小化)
;    レイアウト … 登録アプリをまとめて定位置へ
;    自動配置   … アプリを起動したら定位置へ
;    スナップ   … 今のウィンドウをキー操作で分割配置
;    集中モード … 今のウィンドウ以外を最小化(もう一度押すと復元)
;  設定: 同じフォルダの claude_hotkey.ini
; ==============================================================

INI := A_ScriptDir "\claude_hotkey.ini"
if !FileExist(INI)
    CreateDefaultIni(INI)

Cfg        := {Gap: 0}
SnapList   := []          ; スナップの一覧(表示用・ファイルの順番)
SnapMap    := NewMap()    ; キー → 位置
AutoApps   := NewMap()    ; 自動配置: 実行ファイル名 → 位置
Launching  := NewMap()    ; 呼び出しで起動した時刻
FocusStash := []          ; 集中モードで最小化したウィンドウ
UsedKeys   := NewMap()    ; 登録済みのキー
Errors     := []

LoadAll(INI)

A_IconTip := "ウィンドウ整理ツール"
A_TrayMenu.Add()
A_TrayMenu.Add("登録キーの一覧", ShowKeyList)
A_TrayMenu.Add("設定ファイルを開く", (*) => Run('notepad.exe "' INI '"'))
A_TrayMenu.Add("設定を再読み込み", (*) => Reload())

if Errors.Length {
    msg := ""
    for errMsg in Errors
        msg .= "・" errMsg "`n"
    MsgBox("設定ファイルに問題があります(問題のない設定は有効です):`n`n" msg,
        "ウィンドウ整理ツール", "Icon!")
}

; ==============================================================
;  設定の読み込み
; ==============================================================
LoadAll(path) {
    Cfg.Gap := ToInt(Clean(IniRead(path, "General", "Gap", "0")), 0)

    Reg(IniRead(path, "General", "Reload", ""), (*) => Reload(), "設定の再読み込み")
    Reg(IniRead(path, "General", "Focus", ""), ToggleFocus, "集中モード")
    Reg(IniRead(path, "General", "Snap", ""), SnapMenu, "スナップ")

    ; ---- スナップの位置 ----
    for pair in ReadSection(path, "Snap") {
        if !CheckZone(pair[2], "Snap / " pair[1])
            continue
        SnapList.Push(pair)
        SnapMap[NormalizeKey(pair[1])] := pair[2]
    }

    ; ---- レイアウトと呼び出し ----
    layouts := NewMap()
    for sec in StrSplit(IniRead(path), "`n") {
        if (sec = "" || sec = "General" || sec = "Snap")
            continue
        if (SubStr(sec, 1, 7) = "Layout:") {
            L := LoadLayout(path, sec)
            layouts[L.Name] := L
            Reg(L.Key, ApplyLayout.Bind(L), "レイアウト「" L.Name "」")
        } else {
            p := LoadProfile(path, sec)
            if (p.Key = "")
                Errors.Push("[" sec "] Key が未設定です")
            else
                Reg(p.Key, ShowWindow.Bind(p), "呼び出し「" sec "」")
        }
    }

    ; ---- 自動配置 ----
    auto := Clean(IniRead(path, "General", "AutoLayout", ""))
    if (auto = "")
        return
    if !layouts.Has(auto) {
        Errors.Push("[General] AutoLayout のレイアウト「" auto "」が見つかりません")
        return
    }
    for proc, zone in layouts[auto].Apps
        AutoApps[proc] := zone
    DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
    OnMessage(DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt"), OnShellMsg)
}

LoadLayout(path, sec) {
    L := {Name: Trim(SubStr(sec, 8)), Key: "", Apps: NewMap()}
    for pair in ReadSection(path, sec) {
        if (pair[1] = "Key")
            L.Key := pair[2]
        else if CheckZone(pair[2], sec " / " pair[1])
            L.Apps[pair[1]] := pair[2]
    }
    return L
}

LoadProfile(path, sec) {
    p := {Name: sec}
    p.Key     := Clean(IniRead(path, sec, "Key", ""))
    p.Process := Clean(IniRead(path, sec, "Process", "claude.exe"))
    p.Width   := Clean(IniRead(path, sec, "Width", "1200"))
    p.Height  := Clean(IniRead(path, sec, "Height", "800"))
    p.OnTop   := Clean(IniRead(path, sec, "AlwaysOnTop", "0")) = "1"
    p.Toggle  := Clean(IniRead(path, sec, "ToggleMinimize", "1")) = "1"
    exe       := Clean(IniRead(path, sec, "Path", ""))
    p.Path    := ExpandEnv(exe != "" ? exe : p.Process)
    try {
        ParseSize(p.Width, 1000)
        ParseSize(p.Height, 1000)
    } catch
        Errors.Push("[" sec "] Width / Height の書き方が不正です")
    return p
}

; キー → 関数の登録(重複・書き間違いをチェック)
Reg(key, fn, label) {
    key := Clean(key)
    if (key = "")
        return
    if UsedKeys.Has(key) {
        Errors.Push(label "のキー " KeyName(key) " は、" UsedKeys[key] " と重複しています")
        return
    }
    try {
        Hotkey(key, fn)
        UsedKeys[key] := label
    } catch
        Errors.Push(label "のキーの書き方が不正です: " key)
}

; セクションを [キー, 値] の配列で返す(ファイルの順番を保つ)
ReadSection(path, sec) {
    out := []
    try text := IniRead(path, sec)
    catch
        return out
    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";" || !(pos := InStr(line, "=")))
            continue
        out.Push([Trim(SubStr(line, 1, pos - 1)), Clean(SubStr(line, pos + 1))])
    }
    return out
}

CheckZone(spec, label) {
    try {
        ParseZone(spec)
        return true
    } catch as e {
        Errors.Push("[" label "] " e.Message)
        return false
    }
}

; ==============================================================
;  呼び出し:画面中央に表示(もう一度押すと最小化)
; ==============================================================
ShowWindow(p, *) {
    SetDpi()
    hwnd := FindAppWindow(p.Process)
    if !hwnd {
        Launching[p.Process] := A_TickCount
        try Run(p.Path)
        catch {
            MsgBox("[" p.Name "] 起動できません。Path を確認してください。`n`n" p.Path)
            return
        }
        Loop 30 {
            Sleep(500)
            if (hwnd := FindAppWindow(p.Process))
                break
        }
        if !hwnd
            return
        Sleep(300)
    }

    MonitorGetWorkArea(MouseMonitor(), &l, &t, &r, &b)
    w := ParseSize(p.Width, r - l)
    h := ParseSize(p.Height, b - t)
    x := l + (r - l - w) // 2
    y := t + (b - t - h) // 2

    ; すでに前面で同じ位置・サイズなら最小化
    if (p.Toggle && WinActive(hwnd) && WinGetMinMax(hwnd) = 0) {
        v := VisibleRect(hwnd)
        if (Abs(v.x - x) <= 2 && Abs(v.y - y) <= 2 && Abs(v.w - w) <= 2 && Abs(v.h - h) <= 2) {
            WinMinimize(hwnd)
            return
        }
    }
    RestoreIfNeeded(hwnd)
    MoveExact(hwnd, x, y, w, h)
    WinActivate(hwnd)
    WinSetAlwaysOnTop(p.OnTop ? 1 : 0, hwnd)
}

; ==============================================================
;  レイアウト:登録アプリをまとめて定位置へ
; ==============================================================
ApplyLayout(L, *) {
    SetDpi()
    mon := MouseMonitor()
    active := WinExist("A")
    placed := []
    for proc, zone in L.Apps {
        for hwnd in WinGetList("ahk_exe " proc) {
            if !IsAppWindow(hwnd)
                continue
            PlaceInZone(hwnd, zone, mon)
            placed.Push(hwnd)
        }
    }
    if !placed.Length {
        ShowTip("レイアウト「" L.Name "」: 対象のウィンドウが開いていません")
        return
    }
    target := placed[1]
    for hwnd in placed {
        try WinMoveTop(hwnd)
        if (hwnd = active)
            target := active
    }
    try WinActivate(target)
    ShowTip("レイアウト「" L.Name "」")
}

; ==============================================================
;  自動配置:アプリの最初のウィンドウが開いたら定位置へ
;  (ポップアップなど2つ目以降のウィンドウは動かさない)
; ==============================================================
OnShellMsg(wParam, lParam, *) {
    if (wParam = 1)                        ; HSHELL_WINDOWCREATED
        SetTimer(AutoPlace.Bind(lParam), -600)
}

AutoPlace(hwnd) {
    SetDpi()
    try {
        if !WinExist(hwnd) || !IsAppWindow(hwnd)
            return
        proc := WinGetProcessName(hwnd)
        if !AutoApps.Has(proc)
            return
        ; 呼び出しで起動した直後は呼び出し側に任せる
        if (A_TickCount - Launching.Get(proc, -100000) < 30000)
            return
        for other in WinGetList("ahk_exe " proc)
            if (other != hwnd && IsAppWindow(other))
                return
        PlaceInZone(hwnd, AutoApps[proc], MouseMonitor())
    }
}

; ==============================================================
;  スナップ:ホットキーの後に押したキーで位置を選ぶ
; ==============================================================
SnapMenu(*) {
    SetDpi()
    hwnd := WinExist("A")
    if !hwnd || !IsAppWindow(hwnd)
        return
    if !SnapList.Length {
        ShowTip("[Snap] に位置が登録されていません")
        return
    }
    mon := WindowMonitor(hwnd)      ; 最大化解除前に今のモニターを確定
    ToolTip(SnapHelp())
    ih := InputHook("T3")
    ih.KeyOpt("{All}", "ES")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-ES")
    ih.Start()
    ih.Wait()
    ToolTip()
    if (ih.EndReason != "EndKey")
        return
    k := NormalizeKey(ih.EndKey)
    if !SnapMap.Has(k)
        return
    PlaceInZone(hwnd, SnapMap[k], mon)
    WinActivate(hwnd)
}

SnapHelp() {
    s := "位置を選択(Esc でキャンセル)`n"
    for i, pair in SnapList
        s .= StrUpper(pair[1]) ":" pair[2] . (Mod(i, 3) ? "　 " : "`n")
    return RTrim(s, "`n　 ")
}

NormalizeKey(k) {
    static np := Map("NumpadEnd", "1", "NumpadDown", "2", "NumpadPgDn", "3",
        "NumpadLeft", "4", "NumpadClear", "5", "NumpadRight", "6",
        "NumpadHome", "7", "NumpadUp", "8", "NumpadPgUp", "9", "NumpadIns", "0")
    k := Trim(k)
    if np.Has(k)
        return np[k]
    if RegExMatch(k, "i)^Numpad(\d)$", &m)
        return m[1]
    return StrLower(k)
}

; ==============================================================
;  集中モード:今のウィンドウ以外を最小化/もう一度で復元
; ==============================================================
ToggleFocus(*) {
    SetDpi()
    stillMin := []
    for hwnd in FocusStash
        try if WinExist(hwnd) && WinGetMinMax(hwnd) = -1
            stillMin.Push(hwnd)
    FocusStash.Length := 0

    active := WinExist("A")
    if stillMin.Length {
        ; 奥にあったものから順に戻して重なり順を保つ
        Loop stillMin.Length
            try WinRestore(stillMin[stillMin.Length - A_Index + 1])
        try WinActivate(active)
        ShowTip("元に戻しました")
        return
    }
    for hwnd in WinGetList() {
        if (hwnd = active || !IsAppWindow(hwnd))
            continue
        try {
            if WinGetMinMax(hwnd) = -1
                continue
            WinMinimize(hwnd)
            FocusStash.Push(hwnd)
        }
    }
    ShowTip("集中モード(もう一度押すと元に戻します)")
}

; ==============================================================
;  位置の計算と移動
; ==============================================================
ParseZone(spec) {
    static Z := Map(
        "全体",   [0, 0, 1, 1],
        "中央",   [0.15, 0.1, 0.7, 0.8],
        "左半分", [0, 0, 0.5, 1],     "右半分", [0.5, 0, 0.5, 1],
        "上半分", [0, 0, 1, 0.5],     "下半分", [0, 0.5, 1, 0.5],
        "左1/3",  [0, 0, 1/3, 1],     "中1/3",  [1/3, 0, 1/3, 1],  "右1/3", [2/3, 0, 1/3, 1],
        "左2/3",  [0, 0, 2/3, 1],     "右2/3",  [1/3, 0, 2/3, 1],
        "左上",   [0, 0, 0.5, 0.5],   "右上",   [0.5, 0, 0.5, 0.5],
        "左下",   [0, 0.5, 0.5, 0.5], "右下",   [0.5, 0.5, 0.5, 0.5]
    )
    s := ToHalf(Trim(spec))
    mon := 0
    if RegExMatch(s, "@\s*(\d+)$", &m) {
        mon := Integer(m[1])
        s := Trim(SubStr(s, 1, m.Pos - 1))
    }
    if Z.Has(s)
        r := Z[s]
    else {
        parts := StrSplit(s, ",", " `t")
        if (parts.Length != 4)
            throw ValueError("位置「" spec "」が不正です")
        r := []
        for v in parts {
            if !IsNumber(v)
                throw ValueError("位置「" spec "」が不正です")
            r.Push(v / 100)
        }
    }
    return {x: r[1], y: r[2], w: r[3], h: r[4], mon: mon}
}

PlaceInZone(hwnd, spec, defMon) {
    z := ParseZone(spec)
    mon := (z.mon >= 1 && z.mon <= MonitorGetCount()) ? z.mon : defMon
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    g := Cfg.Gap // 2
    x1 := Round(l + (r - l) * z.x) + g
    y1 := Round(t + (b - t) * z.y) + g
    x2 := Round(l + (r - l) * (z.x + z.w)) - g
    y2 := Round(t + (b - t) * (z.y + z.h)) - g
    RestoreIfNeeded(hwnd)
    MoveExact(hwnd, x1, y1, x2 - x1, y2 - y1)
}

; "1200" → 1200px、"70%" → 作業領域の70%
ParseSize(val, total) {
    val := ToHalf(Trim(val))
    if InStr(val, "%")
        return Round(total * StrReplace(val, "%") / 100)
    return Integer(val)
}

; Windows 10/11 の「見えない枠(影)」を補正して、見た目どおりの位置に置く
MoveExact(hwnd, x, y, w, h) {
    Loop 2 {
        WinGetPos(&wx, &wy, &ww, &wh, hwnd)
        v := VisibleRect(hwnd)
        dl := v.x - wx, dt := v.y - wy
        dr := (wx + ww) - (v.x + v.w), db := (wy + wh) - (v.y + v.h)
        WinMove(x - dl, y - dt, w + dl + dr, h + dt + db, hwnd)
        v := VisibleRect(hwnd)
        if (Abs(v.x - x) <= 1 && Abs(v.y - y) <= 1 && Abs(v.w - w) <= 1 && Abs(v.h - h) <= 1)
            break
    }
}

VisibleRect(hwnd) {
    rect := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16) = 0 {
        l := NumGet(rect, 0, "Int"), t := NumGet(rect, 4, "Int")
        return {x: l, y: t, w: NumGet(rect, 8, "Int") - l, h: NumGet(rect, 12, "Int") - t}
    }
    WinGetPos(&x, &y, &w, &h, hwnd)
    return {x: x, y: y, w: w, h: h}
}

RestoreIfNeeded(hwnd) {
    Loop 2 {            ; 最小化→最大化→通常 の2段階に対応
        if WinGetMinMax(hwnd) = 0
            return
        WinRestore(hwnd)
        Sleep(100)
    }
}

; ==============================================================
;  ウィンドウ・モニターの判定
; ==============================================================
; タスクバーに出る普通のウィンドウだけを対象にする
IsAppWindow(hwnd) {
    try {
        style := WinGetStyle(hwnd)
        ex    := WinGetExStyle(hwnd)
        cls   := WinGetClass(hwnd)
        title := WinGetTitle(hwnd)
    } catch
        return false
    if !(style & 0x10000000)                                ; 非表示
        return false
    if (title = "" || cls ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")
        return false
    if (ex & 0x8000000)                                     ; アクティブにならない窓
        return false
    if !(ex & 0x40000) {                                    ; WS_EX_APPWINDOW でなければ
        if (ex & 0x80)                                      ; ツールウィンドウ
            return false
        if DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; ダイアログなど
            return false
    }
    return !IsCloaked(hwnd)                                 ; 別の仮想デスクトップ等
}

IsCloaked(hwnd) {
    c := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &c, "UInt", 4)
    return c != 0
}

FindAppWindow(proc) {
    for hwnd in WinGetList("ahk_exe " proc)
        if IsAppWindow(hwnd)
            return hwnd
    return 0
}

MonitorAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

MouseMonitor() {
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    return MonitorAt(mx, my)
}

WindowMonitor(hwnd) {
    v := VisibleRect(hwnd)
    return MonitorAt(v.x + v.w // 2, v.y + v.h // 2)
}

; ==============================================================
;  補助
; ==============================================================
; 複数モニターで拡大率が違っても座標がずれないようにする
SetDpi() {
    try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
}

ShowTip(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -1500)
}

ShowKeyList(*) {
    s := ""
    for key, label in UsedKeys
        s .= KeyName(key) "`t" label "`n"
    MsgBox(s = "" ? "登録されているキーはありません" : s, "登録キーの一覧")
}

KeyName(k) {
    static mods := Map("^", "Ctrl+", "!", "Alt+", "+", "Shift+", "#", "Win+")
    out := ""
    while (StrLen(k) > 1 && mods.Has(SubStr(k, 1, 1))) {
        out .= mods[SubStr(k, 1, 1)]
        k := SubStr(k, 2)
    }
    return out StrUpper(k)
}

NewMap() {
    m := Map()
    m.CaseSense := false
    return m
}

; 行末の「 ; コメント」を取り除く
Clean(s) => Trim(RegExReplace(s, "\s+;.*$"))

ToInt(v, def) => IsInteger(v) ? Integer(v) : def

; 全角の数字・記号を半角に
ToHalf(s) {
    static fw := "０１２３４５６７８９／＠，％．", hw := "0123456789/@,%."
    Loop Parse fw
        s := StrReplace(s, A_LoopField, SubStr(hw, A_Index, 1))
    return s
}

ExpandEnv(s) {
    n := DllCall("ExpandEnvironmentStrings", "Str", s, "Ptr", 0, "UInt", 0, "UInt")
    buf := Buffer(n * 2)
    DllCall("ExpandEnvironmentStrings", "Str", s, "Ptr", buf, "UInt", n)
    return StrGet(buf)
}

CreateDefaultIni(path) {
    text := "
    (
; ==============================================================
;  ウィンドウ整理ツール 設定ファイル
;  変更したら Reload のキー、またはトレイアイコン右クリック →「設定を再読み込み」
; ==============================================================
;
; ■ キーの書き方  ^=Ctrl  !=Alt  +=Shift  #=Win
;     例) ^!c = Ctrl+Alt+C   ^!F1 = Ctrl+Alt+F1   #c = Win+C
;
; ■ 位置の書き方(Layout と Snap で共通)
;     全体 / 中央 / 左半分 / 右半分 / 上半分 / 下半分
;     左1/3 / 中1/3 / 右1/3 / 左2/3 / 右2/3 / 左上 / 右上 / 左下 / 右下
;     数値で指定するときは X,Y,幅,高さ(画面に対する%)  例) 0,0,60,100
;     末尾に @2 を付けると2台目のモニター  例) 左半分@2
;
; ■ コメントは行の先頭に ; を付けて書きます

[General]
; 設定の再読み込み
Reload=^!r
; 集中モード:今のウィンドウ以外を最小化(もう一度押すと元に戻す)
Focus=^!f
; スナップ:押した後に [Snap] のキーで位置を選ぶ
Snap=^!g
; アプリを起動したとき自動で定位置に置くレイアウト名(空欄で無効)
AutoLayout=作業
; ウィンドウ同士の隙間(px)
Gap=0

; ---- スナップの位置(キー=位置)----
; テンキーと同じ並び + Q/W/E で3分割、A/S/D で 左2/3・全体・右2/3
[Snap]
7=左上
8=上半分
9=右上
4=左半分
5=中央
6=右半分
1=左下
2=下半分
3=右下
q=左1/3
w=中1/3
e=右1/3
a=左2/3
s=全体
d=右2/3

; ---- レイアウト:[Layout:名前] を追加すれば何個でも登録できます ----
; Key=呼び出しキー、その下に「実行ファイル名=位置」
; 実行ファイル名はタスクマネージャーの「詳細」タブで確認できます
[Layout:作業]
Key=^!F1
msedge.exe=左2/3
chrome.exe=左2/3
claude.exe=右1/3

[Layout:資料比較]
Key=^!F2
msedge.exe=左半分
chrome.exe=左半分
WINWORD.EXE=右半分
EXCEL.EXE=右半分

; ---- 呼び出し:画面中央に表示(もう一度押すと最小化)----
; Key / Process / Path / Width / Height / AlwaysOnTop / ToggleMinimize
[Claude 通常]
Key=^!c
Process=claude.exe
Path=%LOCALAPPDATA%\AnthropicClaude\claude.exe
Width=1200
Height=800

[Claude 大きめ]
Key=^!+c
Process=claude.exe
Path=%LOCALAPPDATA%\AnthropicClaude\claude.exe
Width=90%
Height=90%
AlwaysOnTop=1

[メモ帳]
Key=^!n
Process=notepad.exe
Width=800
Height=600
    )"
    FileAppend(text, path, "UTF-16 `n")
}
```

---

## 付録B:これまでの経緯

1. Ctrl+Alt+C で Claude デスクトップ版を画面中央に指定サイズで出す、最初の版。
2. キーとサイズを設定ファイル(INI)で管理できるようにした。
3. 呼び出しを複数登録できるようにした(セクション=1つの呼び出し設定)。
4. ウィンドウ整理ツールに拡張:レイアウト、自動配置、スナップ、集中モード、見えない枠と DPI の補正、設定の問題の一覧表示、トレイメニュー。
5. 散らかる理屈を数式にし、可視化ページを作った(第7章)。
