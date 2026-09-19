#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\lib\log.ahk
#Include %A_ScriptDir%\lib\recent.ahk

; ==============================================================
;  ウィンドウ整理ツール
;    呼び出し   … 指定アプリを画面中央へ(もう一度押すと最小化)
;    レイアウト … 登録アプリをまとめて定位置へ
;    自動配置   … アプリを起動したら定位置へ
;    スナップ   … 今のウィンドウをキー操作で分割配置
;    集中モード … 今のウィンドウ以外を最小化(もう一度押すと復元)
;    操作ログ   … ウィンドウの操作を CSV に記録(lib\log.ahk、既定は無効)
;    最近使ったファイル … fzf であいまい検索して開く(lib\recent.ahk + lib\fr.ps1)
;  設定: 同じフォルダの claude_hotkey.ini
; ==============================================================

INI := A_ScriptDir "\claude_hotkey.ini"
if !FileExist(INI)
    CreateDefaultIni(INI)

Cfg        := {Gap: 0, AutoLayout: "", RecentSize: "110,30", RecentShell: "pwsh"}
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

LogInit(INI)                  ; 操作ログ(Log=1 のときだけ動く)

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
    RecentLoad(path)                                    ; 最近使ったファイル(lib\recent.ahk)

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
    if (auto != "") {
        if !layouts.Has(auto)
            Errors.Push("[General] AutoLayout のレイアウト「" auto "」が見つかりません")
        else {
            Cfg.AutoLayout := auto
            for proc, zone in layouts[auto].Apps
                AutoApps[proc] := zone
        }
    }

    ; ウィンドウの生成・切り替えの通知(自動配置と操作ログが使う)
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
    launched := false
    hwnd := FindAppWindow(p.Process)
    if !hwnd {
        Launching[p.Process] := A_TickCount
        try Run(p.Path)
        catch {
            LogTool("show", p.Name, "error")
            MsgBox("[" p.Name "] 起動できません。Path を確認してください。`n`n" p.Path)
            return
        }
        Loop 30 {
            Sleep(500)
            if (hwnd := FindAppWindow(p.Process))
                break
        }
        if !hwnd {
            LogTool("show", p.Name, "none")
            return
        }
        Sleep(300)
        launched := true
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
            LogMark(hwnd, "show", p.Name)
            LogTool("show", p.Name, "minimized", hwnd)
            WinMinimize(hwnd)
            return
        }
    }
    LogMark(hwnd, "show", p.Name)
    LogTool("show", p.Name, launched ? "launched" : "moved", hwnd)
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
            LogMark(hwnd, "layout", L.Name)
            PlaceInZone(hwnd, zone, mon)
            placed.Push(hwnd)
        }
    }
    if !placed.Length {
        LogTool("layout", L.Name, "none")
        ShowTip("レイアウト「" L.Name "」: 対象のウィンドウが開いていません")
        return
    }
    LogTool("layout", L.Name, "moved", 0, "count=" placed.Length)
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
    code := wParam & 0x7FFF                ; HSHELL_RUDEAPPACTIVATED(0x8004)を 4 に
    if (code = 1 && AutoApps.Count)        ; HSHELL_WINDOWCREATED
        SetTimer(AutoPlace.Bind(lParam), -600)
    LogShell(code, lParam)
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
        LogMark(hwnd, "autoplace", Cfg.AutoLayout)
        PlaceInZone(hwnd, AutoApps[proc], MouseMonitor())
        LogTool("autoplace", Cfg.AutoLayout, "moved", hwnd)
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
    if (ih.EndReason != "EndKey") {
        LogTool("snap", "", "none", hwnd)
        return
    }
    k := NormalizeKey(ih.EndKey)
    if !SnapMap.Has(k) {
        LogTool("snap", k, "none", hwnd)
        return
    }
    LogMark(hwnd, "snap", SnapMap[k])
    LogTool("snap", SnapMap[k], "moved", hwnd)
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
        Loop stillMin.Length {
            h := stillMin[stillMin.Length - A_Index + 1]
            LogMark(h, "focus", "restore")
            try WinRestore(h)
        }
        try WinActivate(active)
        LogTool("focus", "restore", "restored", active, "count=" stillMin.Length)
        ShowTip("元に戻しました")
        return
    }
    for hwnd in WinGetList() {
        if (hwnd = active || !IsAppWindow(hwnd))
            continue
        try {
            if WinGetMinMax(hwnd) = -1
                continue
            LogMark(hwnd, "focus", "minimize")
            WinMinimize(hwnd)
            FocusStash.Push(hwnd)
        }
    }
    LogTool("focus", "minimize", "minimized", active, "count=" FocusStash.Length)
    ShowTip("集中モード(もう一度押すと元に戻します)")
}

; ==============================================================
;  位置の計算と移動
; ==============================================================
; 名前付きの区画(x, y, 幅, 高さ の割合)。操作ログの区画判定でも使う
ZoneTable() {
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
    return Z
}

ParseZone(spec) {
    Z := ZoneTable()
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
    e := ZoneRect(z, mon)
    RestoreIfNeeded(hwnd)
    MoveExact(hwnd, e.x, e.y, e.w, e.h)
}

; 区画 {x, y, w, h}(割合)→ モニターの作業領域上の矩形(px、Gap を反映)
; 左端と右端をそれぞれ丸めてから幅を出すので、隣の区画との間に隙間や重なりができない
ZoneRect(z, mon) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    g := Cfg.Gap // 2
    x1 := Round(l + (r - l) * z.x) + g
    y1 := Round(t + (b - t) * z.y) + g
    x2 := Round(l + (r - l) * (z.x + z.w)) - g
    y2 := Round(t + (b - t) * (z.y + z.h)) - g
    return {x: x1, y: y1, w: x2 - x1, h: y2 - y1}
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

; ---- 操作ログ(仕様: docs/logging.md)----
; 1 にすると、ウィンドウの操作を CSV に記録します(既定は記録しない)
Log=0
; 保存先(空欄なら %LOCALAPPDATA%\claude_hotkey\logs)
LogDir=
; ウィンドウのタイトル 0=記録しない 1=記録する hash=ハッシュ値だけ
LogTitle=0
; 記録しないアプリ(実行ファイル名をカンマ区切り)
LogExclude=
; ログを残す日数(0 で無期限)
LogKeepDays=90
; 開いている全ウィンドウを記録する間隔(分)
SnapshotMinutes=5
; この分数だけ操作がなければ離席とみなす
IdleMinutes=5
; 区画に合っているとみなす許容のずれ(px)
ZoneTolerance=8

; ---- 最近使ったファイル(仕様: docs/recent_files.md)----
; Windows の「最近使った項目」を fzf であいまい検索して開く(Windows Terminal と fzf が必要)
Recent=^!o
; ターミナルの大きさ(列数,行数)
RecentSize=110,30
; 使うシェル pwsh(PowerShell 7)または powershell(Windows PowerShell 5.1)
RecentShell=pwsh

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
