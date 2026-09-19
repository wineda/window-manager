# 操作ログの仕様(`lib/log.ahk`)

ウィンドウの操作を CSV に記録し、`docs/claude_hotkey_handoff.md` 第7章の λ・W・d・r・p・k を実測するための仕様です。実装は `lib/log.ahk`、解析は `analysis/analyze.py`。

| 項目 | 内容 |
|---|---|
| 有効化 | `claude_hotkey.ini` の `[General]` に `Log=1`(既定は無効) |
| 保存先 | `%LOCALAPPDATA%\claude_hotkey\logs\`(`LogDir` で変更可) |
| ファイル | `YYYY-MM-DD.csv`(ローカル日付で1日1ファイル、追記) |
| 形式 | CSV(RFC 4180)、UTF-8(BOM付き)、CRLF、1行目にヘッダー |
| スキーマ版 | 1(`start` 行の `detail` に `schema=1`) |

---

## 1. 方針

- **1イベント = 1行**の追記型。判定結果(区画に合っているか)だけでなく**生の矩形を必ず残す**ので、判定の許容値を変えて後から再計算できる
- 記録する窓は `IsAppWindow()` を満たすもの(第7章の N と同じ母集団)
- タイトル・パス・URL は既定で記録しない(第6章)
- 既定はオフ。ユーザーが明示的に有効にする

## 2. 設定(`[General]`)

| キー | 既定 | 内容 |
|---|---|---|
| `Log` | `0` | `1` で記録する |
| `LogDir` | (空) | 保存先。空なら `%LOCALAPPDATA%\claude_hotkey\logs`。環境変数を使える |
| `LogTitle` | `0` | `0`=記録しない、`1`=記録する、`hash`=CRC32 の 8 桁だけ |
| `LogExclude` | (空) | 記録しない実行ファイル名(カンマ区切り、大文字小文字は区別しない) |
| `LogKeepDays` | `90` | 起動時に、この日数より古いファイルを削除。`0` で無期限 |
| `SnapshotMinutes` | `5` | 開いている全窓を書き出す間隔。`0` で起動時だけ |
| `IdleMinutes` | `5` | この分数だけ物理入力がなければ離席(`idle`)とみなす。`0` で無効 |
| `ZoneTolerance` | `8` | 区画に合っているとみなす、各辺のずれの上限(px) |

保存先に書き込めないときは、起動時のエラー一覧に出してログを無効にします(他の機能は動きます)。

## 3. ファイル

- ファイル名の日付は**書き込み時**のローカル日付。行は 5 秒(または 50 行)ごとにまとめて書くので、日付の境目の数秒は翌日のファイルに入ることがある。`ts` で判断する
- 文字コードは UTF-8(BOM付き)。Excel でそのまま開ける。pandas は `encoding="utf-8-sig"`
- 列は**末尾にしか追加しない**。列を増やしたら `schema` を上げる。古いファイルと混ぜて読めるようにするため

## 4. 列(全イベント共通。該当しない列は空)

| 列 | 型 | 内容 |
|---|---|---|
| `ts` | 文字列 | ローカル時刻 ISO 8601、ミリ秒とオフセット付き。例 `2026-09-19T09:03:12.410+09:00` |
| `tick` | 整数 | `A_TickCount`(起動からのミリ秒)。時計合わせの影響を受けない**経過時間計算用** |
| `session` | 文字列 | 起動ごとの ID(`起動時刻-乱数4桁`)。再読み込みで変わる |
| `seq` | 整数 | セッション内の連番(同一ミリ秒の順序保証) |
| `event` | 列挙 | 第5章 |
| `wid` | 整数 | セッション内で窓に振る連番。初見時に採番。窓の鍵は `session + wid`(`hwnd` は再利用されるため) |
| `hwnd` | 16進 | ウィンドウハンドル(デバッグ用) |
| `proc` | 文字列 | 実行ファイル名(`msedge.exe`)。パスは残さない |
| `cls` | 文字列 | ウィンドウクラス |
| `mon` | 整数 | 窓の中心があるモニター番号(`MonitorGet` の番号) |
| `state` | 列挙 | `normal` / `min` / `max` |
| `x`,`y`,`w`,`h` | 整数 | `VisibleRect()` の見た目の矩形(物理px)。`state=min` の間は最小化直前の値を保持 |
| `zone` | 文字列 | 区画判定の結果(第6章)。空=どの区画にも合っていない |
| `cause` | 列挙 | `user` / `tool` / `app`(第6章) |
| `action` | 列挙 | ツールの操作:`show` / `layout` / `autoplace` / `snap` / `focus` |
| `target` | 文字列 | 操作の対象:呼び出し設定名、レイアウト名、スナップの位置、`minimize` / `restore` |
| `result` | 列挙 | `moved` / `minimized` / `restored` / `launched` / `none` / `error` |
| `detail` | 文字列 | `key=value;key=value` の予備欄 |
| `title` | 文字列 | `LogTitle` が `0` なら常に空 |

## 5. イベント

| `event` | いつ | 発生源 | 主に埋まる列 |
|---|---|---|---|
| `start` / `stop` | 起動、終了(再読み込みも stop→start) | `OnExit` | `detail`:`schema`, `ver`, `ahk`, `script` |
| `monitor` | 起動時、画面構成の変更(`WM_DISPLAYCHANGE`) | — | モニター1台1行。`detail`:`mon`, `x`, `y`, `w`, `h`(全体)、`work=l/t/w/h`(作業領域)、`dpi`、`primary` |
| `snapshot` | 起動時と `SnapshotMinutes` ごと | — | 開いている窓1つ1行。取りこぼしの保険であり、N・p・k の主データ |
| `create` | 窓が現れた | シェルフック `HSHELL_WINDOWCREATED` | 矩形、`zone`。起動前からある窓は `create` を書かず `snapshot` だけ。`detail` の `via=` は検出経路(`create` / `activate` / `uncloak` / `tool` / `event`) |
| `destroy` | 窓が消えた | `HSHELL_WINDOWDESTROYED` | 最後の矩形。取りこぼしをスナップショットで検出したときは `via=snapshot` |
| `activate` | 前面の窓が変わった | `HSHELL_WINDOWACTIVATED` | `cause` |
| `move` | 位置か大きさが変わった | `EVENT_OBJECT_LOCATIONCHANGE`(300ms のデバウンス)、`EVENT_SYSTEM_MOVESIZEEND` | 新しい矩形、`zone`、`cause` |
| `minimize` / `restore` / `maximize` / `unmaximize` | 状態が変わった | `EVENT_SYSTEM_MINIMIZESTART/END`、`LOCATIONCHANGE` | `state`、矩形、`cause` |
| `cloak` / `uncloak` | 別の仮想デスクトップへ移った / 戻った | `EVENT_OBJECT_CLOAKED/UNCLOAKED` | — |
| `tool` | ツールが操作した | 各機能の入口 | `action`, `target`, `result`, `wid`(対象があれば)。`detail` の `count=` は動かした窓の数 |
| `idle` / `resume` | 離席とみなした / 戻った | `A_TimeIdlePhysical`(15秒ごとに判定) | `detail`:`since=tick`(離席が始まった tick)、`at=tick`(戻った tick) |
| `lock` / `unlock` | 画面ロック / 解除 | `WM_WTSSESSION_CHANGE` | — |
| `retitle` | タイトルが変わった(`LogTitle` が `0` 以外のときだけ) | `HSHELL_REDRAW` | `title` |

状態と矩形が同時に変わったときは、状態のイベントを1行だけ書く(矩形はその行に入る)。

## 6. 派生列の定義

**`zone`(区画判定)**
モニターの作業領域と `Gap` から各区画の矩形を `ZoneRect()` で計算し、4辺の最大のずれが `ZoneTolerance` 以内なら、最もずれの小さい区画名。`state=max` は `全体`。どれにも合わなければ空。本体の配置と同じ計算式を使うので、ツールが置いた直後の窓は必ず区画名が付く。

**`cause`(誰が動かしたか)**
1. ツールが `WinMove` / `WinMinimize` / `WinRestore` する直前に `LogMark()` で印を付け、その後 1.5 秒以内のイベントは `tool`(`action` / `target` も入る)
2. `EVENT_SYSTEM_MOVESIZEEND`(ドラッグ完了)由来なら `user`
3. 最小化・復元・前面化は、直前 1 秒以内に物理入力があれば `user`、なければ `app`(アプリの自己再配置、他アプリによる前面化)
4. それ以外の位置変更は `app`

3 と 4 はヒューリスティック。解析では `tool` と `user` の区別を主に使い、`app` は「その他」として扱う。

**`wid`**
`create` / `snapshot` / `activate` などで初めて見た時点で採番。`destroy` 後に同じ `hwnd` が再利用されても別の `wid` になる。

## 7. プライバシー

- `title` は既定で空。`LogTitle=hash` は同じ文書の再出現を追えるが内容は分からない(ただし候補が少なければ推測は可能)
- `LogExclude` に書いたアプリは行自体を書かない(`wid` は採番するので欠番になる)
- トレイメニュー「ログを一時停止」で止められる(記録は続くが書かない)。「ログフォルダを開く」で場所を確認できる
- ログフォルダはリポジトリに入れない(`.gitignore`)

## 8. 解析(第7章との対応)

活動時間 T は、セッションの時間から `idle`〜`resume` と `lock`〜`unlock` を除いたもの。

| 記号 | 算出 |
|---|---|
| **N** | 開いている窓の数の時間平均。`snapshot` を基準に `create` / `destroy` で補間 |
| **λ** | `create` の数 ÷ T(件/時間)。寿命 3 秒未満は一時的なポップアップとして別集計 |
| **W** | `destroy.tick − create.tick`。平均と中央値(裾が重い)。セッション終了時にまだ開いている窓は打ち切りとして数える。あわせて最小化されていない時間・前面だった時間 |
| 検算 | N ≈ λ × W(リトルの法則) |
| **d** | 窓ごとに「整列(`zone` あり)/非整列」の時系列を作り、整列→非整列の回数 ÷ 整列していた延べ時間 |
| **r** | 非整列→整列の回数 ÷ 非整列だった延べ時間。`cause` で `tool` と `user` に分ける |
| 検算 | 予測 d/(d+r) と実測の「非整列だった時間の割合」を比べる(マルコフ模型の妥当性) |
| **p** | 各 `snapshot` で、同じモニターの `normal` な窓の全ペアのうち矩形が交差する割合。あわせて「幅・高さとも作業領域の半分より大きい窓」の割合 |
| **k** | プロセスごとに、期間中に現れた矩形をクラスタ(許容 16px)した数 |
| 機能の効果 | `tool` 行の `action` / `result` 別回数。`show` で `minimized` の回数(W の短縮)。自動配置の有効・無効での d の差 |

最小化中の時間は d・r の分母に入れない。小さなユーティリティ窓(幅か高さが作業領域の 40% 未満)を d・r から除くかは解析時に決める。`analysis/analyze.py` が上記をすべて計算する。

## 9. 実装メモ

- `lib/log.ahk` を本体の先頭で `#Include`。本体は `LogInit()`(起動時)、`LogTool()`(各機能の入口)、`LogMark()`(窓を動かす直前)、`LogShell()`(シェルフック)だけを呼ぶ
- `SetWinEventHook` は `WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS`。`LOCATIONCHANGE` はキャレットや子要素でも来るので、`idObject=0`・`idChild=0`・記録済みの窓だけに絞り、窓ごとに 300ms のデバウンス。ドラッグ中(`MOVESIZESTART`〜`END`)は書かない
- 行は配列にため、5 秒ごと・50 行・終了時に書く。書き込みに失敗したらツールチップを1回出す
- 区画の判定は本体の `ZoneTable()` / `ZoneRect()` を使う(配置と同じ式)
- タイムゾーンのオフセットは起動時とスナップショットごとに `A_Now − A_NowUTC` から求める

## 10. 見積もり

1日あたり `activate` 500〜2000、`move` 100〜500、`create` / `destroy` 100〜300、`snapshot` 約 1200(10窓 × 12回/時 × 10時間)。合計 3〜5 千行 × 約 120 バイト ≈ **0.5 MB/日**、90 日で 45 MB 程度。

## 11. サンプル

```csv
ts,tick,session,seq,event,wid,hwnd,proc,cls,mon,state,x,y,w,h,zone,cause,action,target,result,detail,title
2026-09-19T09:00:00.012+09:00,1234567,20260919090000-3f2a,1,start,,,,,,,,,,,,,,,,schema=1;ver=1.0;ahk=2.0.28;script=claude_hotkey.ahk,
2026-09-19T09:00:00.020+09:00,1234575,20260919090000-3f2a,2,monitor,,,,,,,,,,,,,,,,mon=1;x=0;y=0;w=2560;h=1440;work=0/0/2560/1400;dpi=96;primary=1,
2026-09-19T09:00:00.031+09:00,1234586,20260919090000-3f2a,3,snapshot,1,0x1A0F32,msedge.exe,Chrome_WidgetWin_1,1,normal,0,0,1707,1400,左2/3,,,,,,
2026-09-19T09:03:12.410+09:00,1426965,20260919090000-3f2a,4,create,2,0x2B0044,EXCEL.EXE,XLMAIN,1,normal,312,180,1400,900,,,,,,via=create,
2026-09-19T09:03:13.015+09:00,1427570,20260919090000-3f2a,5,tool,2,0x2B0044,EXCEL.EXE,XLMAIN,1,normal,312,180,1400,900,,,autoplace,作業,moved,,
2026-09-19T09:03:13.320+09:00,1427875,20260919090000-3f2a,6,move,2,0x2B0044,EXCEL.EXE,XLMAIN,1,normal,1280,0,1280,1400,右半分,tool,autoplace,作業,,,
2026-09-19T09:03:13.400+09:00,1427955,20260919090000-3f2a,7,activate,2,0x2B0044,EXCEL.EXE,XLMAIN,1,normal,1280,0,1280,1400,右半分,user,,,,,
```
