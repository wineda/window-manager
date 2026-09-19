#Requires AutoHotkey v2.0

; ==============================================================
;  操作ログ(仕様: docs/logging.md)
;    ウィンドウの生成・破棄・切り替え・移動・最小化と、ツールの操作を
;    1日1ファイルの CSV に追記する。第7章の λ・W・d・r・p・k を実測するため。
;  本体から呼ぶ関数: LogInit / LogTool / LogMark / LogShell
;  既定では無効。[General] の Log=1 で有効になる
; ==============================================================

; モジュールの状態(本体の Cfg などと同じく、起動時に1つ作る)
Lg := {}
Lg.On         := false        ; 設定で有効か
Lg.Paused     := false        ; トレイメニューで一時停止中か
Lg.Dir        := ""           ; 保存先フォルダ
Lg.TitleMode  := "0"          ; 0 / 1 / hash
Lg.Exclude    := NewMap()     ; 記録しない実行ファイル名
Lg.KeepDays   := 90
Lg.SnapMin    := 5            ; スナップショットの間隔(分)
Lg.IdleMin    := 5            ; 離席とみなす分数
Lg.Tol        := 8            ; 区画に合っているとみなす許容のずれ(px)
Lg.Session    := ""           ; 起動ごとの ID
Lg.Seq        := 0            ; セッション内の連番
Lg.Tz         := "+00:00"     ; タイムゾーンのオフセット
Lg.Win        := Map()        ; hwnd → 窓の記録 {wid, proc, cls, skip, state, x, y, w, h, mon, zone, title}
Lg.NextWid    := 1
Lg.Timers     := Map()        ; hwnd → LogSync の BoundFunc(デバウンス用)
Lg.Cause      := Map()        ; hwnd → 保留中の原因
Lg.How        := Map()        ; hwnd → 保留中の検出経路(create / uncloak など)
Lg.Mark       := Map()        ; hwnd → {until, action, target} ツール操作の印
Lg.Dragging   := Map()        ; hwnd → true(ユーザーがドラッグ中)
Lg.LastActive := 0
Lg.Idle       := false
Lg.Buf        := []           ; 未書き込みの行
Lg.Hooks      := []           ; SetWinEventHook のハンドル
Lg.Cb         := 0
Lg.WriteError := false

; ==============================================================
;  初期化と終了
; ==============================================================
; 本体が LoadAll の後に呼ぶ(Cfg.Gap と Errors を使うため)
LogInit(path) {
    Lg.On := Clean(IniRead(path, "General", "Log", "0")) = "1"
    if !Lg.On
        return
    dir := Clean(IniRead(path, "General", "LogDir", ""))
    Lg.Dir       := ExpandEnv(dir != "" ? dir : "%LOCALAPPDATA%\claude_hotkey\logs")
    Lg.TitleMode := StrLower(Clean(IniRead(path, "General", "LogTitle", "0")))
    Lg.KeepDays  := ToInt(Clean(IniRead(path, "General", "LogKeepDays", "90")), 90)
    Lg.SnapMin   := ToInt(Clean(IniRead(path, "General", "SnapshotMinutes", "5")), 5)
    Lg.IdleMin   := ToInt(Clean(IniRead(path, "General", "IdleMinutes", "5")), 5)
    Lg.Tol       := ToInt(Clean(IniRead(path, "General", "ZoneTolerance", "8")), 8)
    for exe in StrSplit(Clean(IniRead(path, "General", "LogExclude", "")), ",", " `t")
        if (exe != "")
            Lg.Exclude[exe] := true

    try {
        if !DirExist(Lg.Dir)
            DirCreate(Lg.Dir)
    } catch {
        Errors.Push("[General] LogDir に書き込めません: " Lg.Dir)
        Lg.On := false
        return
    }

    Lg.Session := A_Now "-" Format("{:04x}", Random(0, 0xFFFF))
    LogTz()
    LogPurge()

    ; 書き込み・スナップショット・離席の監視
    SetTimer(LogFlush, 5000)
    if (Lg.SnapMin > 0)
        SetTimer(LogSnapshot, Lg.SnapMin * 60000)
    SetTimer(LogIdleCheck, 15000)

    ; ウィンドウのイベント(WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS)
    Lg.Cb := CallbackCreate(LogWinEvent, , 7)
    for range in [[0x000A, 0x000B], [0x0016, 0x0017], [0x800B, 0x800B], [0x8017, 0x8018]]
        Lg.Hooks.Push(DllCall("SetWinEventHook", "UInt", range[1], "UInt", range[2],
            "Ptr", 0, "Ptr", Lg.Cb, "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr"))

    OnMessage(0x007E, LogDisplayMsg)                                    ; WM_DISPLAYCHANGE
    if DllCall("wtsapi32\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
        OnMessage(0x02B1, LogSessionMsg)                                ; WM_WTSSESSION_CHANGE
    OnExit(LogStop)

    A_TrayMenu.Add("ログを一時停止", LogTogglePause)
    A_TrayMenu.Add("ログフォルダを開く", (*) => Run('explorer.exe "' Lg.Dir '"'))

    LogRow("start", 0, "", "", "", "", "schema=1;ver=1.0;ahk=" A_AhkVersion ";script=" A_ScriptName)
    LogMonitors()
    LogSnapshot()
}

LogStop(*) {
    if !Lg.On
        return
    LogRow("stop")
    LogFlush()
}

LogTogglePause(name, pos, menu) {
    Lg.Paused := !Lg.Paused
    menu.ToggleCheck(name)
    ShowTip(Lg.Paused ? "ログを一時停止しました" : "ログを再開しました")
}

; ==============================================================
;  本体から呼ぶ関数
; ==============================================================
; ツールの操作を1行記録する(呼び出し・レイアウト・自動配置・スナップ・集中モード)
LogTool(action, target := "", result := "", hwnd := 0, detail := "") {
    if !Lg.On
        return
    if (hwnd && !Lg.Win.Has(hwnd) && IsAppWindow(hwnd))
        LogTrack(hwnd, "tool")
    LogRow("tool", hwnd, "", action, target, result, detail)
}

; ツールが窓を動かす直前に印を付ける。直後に届く移動・最小化のイベントを cause=tool にする
LogMark(hwnd, action, target := "") {
    if !Lg.On
        return
    Lg.Mark[hwnd] := {until: A_TickCount + 1500, action: action, target: target}
}

; シェルフックの通知(本体の OnShellMsg から)
LogShell(code, hwnd) {
    if !Lg.On
        return
    if !hwnd {
        if (code = 4)
            Lg.LastActive := 0
        return
    }
    switch code {
        case 1:                                             ; HSHELL_WINDOWCREATED
            LogSchedule(hwnd, "app", "create")
        case 2:                                             ; HSHELL_WINDOWDESTROYED
            LogForget(hwnd, "")
        case 4:                                             ; HSHELL_WINDOWACTIVATED
            if (hwnd = Lg.LastActive)
                return
            Lg.LastActive := hwnd
            if (!IsAppWindow(hwnd) || !LogTrack(hwnd, "activate"))
                return
            LogRefresh(hwnd, "activate")
            LogRow("activate", hwnd, LogCause(hwnd, "input"))
        case 6:                                             ; HSHELL_REDRAW(タイトルの変更など)
            if (Lg.TitleMode != "0" && LogTracked(hwnd)) {
                r := Lg.Win[hwnd]
                old := r.title
                r.title := LogTitle(hwnd)
                if (r.title != old)
                    LogRow("retitle", hwnd)
            }
    }
}

; ==============================================================
;  ウィンドウのイベント(SetWinEventHook)
; ==============================================================
LogWinEvent(hHook, event, hwnd, idObject, idChild, idThread, tick) {
    if (!Lg.On || !hwnd || idObject != 0 || idChild != 0)   ; OBJID_WINDOW / CHILDID_SELF だけ
        return
    switch event {
        case 0x000A:                                        ; EVENT_SYSTEM_MOVESIZESTART
            if LogTracked(hwnd)
                Lg.Dragging[hwnd] := true
        case 0x000B:                                        ; EVENT_SYSTEM_MOVESIZEEND
            LogDrop(Lg.Dragging, hwnd)
            LogSchedule(hwnd, LogCause(hwnd, "user"), "")
        case 0x0016, 0x0017:                                ; MINIMIZESTART / MINIMIZEEND(復元)
            LogSchedule(hwnd, LogCause(hwnd, "input"), "")
        case 0x800B:                                        ; EVENT_OBJECT_LOCATIONCHANGE
            if (LogTracked(hwnd) && !Lg.Dragging.Has(hwnd))
                LogSchedule(hwnd, LogCause(hwnd, ""), "")
        case 0x8017:                                        ; EVENT_OBJECT_CLOAKED(別の仮想デスクトップへ)
            if LogTracked(hwnd)
                LogRow("cloak", hwnd)
        case 0x8018:                                        ; EVENT_OBJECT_UNCLOAKED
            if LogTracked(hwnd)
                LogRow("uncloak", hwnd)
            LogSchedule(hwnd, LogCause(hwnd, ""), "uncloak")
    }
}

; 300ms 待ってから状態を読む(連続するイベントをまとめ、最小化などの最終状態を待つ)
LogSchedule(hwnd, cause, how) {
    if (!Lg.Cause.Has(hwnd) || LogRank(cause) > LogRank(Lg.Cause[hwnd]))
        Lg.Cause[hwnd] := cause
    if (how != "")
        Lg.How[hwnd] := how
    if !Lg.Timers.Has(hwnd)
        Lg.Timers[hwnd] := LogSync.Bind(hwnd)
    SetTimer(Lg.Timers[hwnd], -300)
}

LogRank(c) => (c = "tool") ? 3 : (c = "user") ? 2 : 1

LogSync(hwnd) {
    cause := Lg.Cause.Has(hwnd) ? Lg.Cause[hwnd] : "app"
    how   := Lg.How.Has(hwnd) ? Lg.How[hwnd] : ""
    LogDrop(Lg.Cause, hwnd), LogDrop(Lg.How, hwnd)
    if !WinExist(hwnd) {
        LogForget(hwnd, "sync")
        return
    }
    if !LogTracked(hwnd) {
        if (!Lg.Win.Has(hwnd) && IsAppWindow(hwnd))
            LogTrack(hwnd, how != "" ? how : "event")
        if !LogTracked(hwnd)
            LogDrop(Lg.Timers, hwnd)
        return
    }
    ev := LogUpdate(hwnd)
    if (ev = "")
        return
    m := LogMarkInfo(hwnd)
    LogRow(ev, hwnd, cause, m.action, m.target)
}

; 誰が動かしたか: ツールの印 > ヒント(user=ドラッグ完了、input=直前に物理入力があれば user)
LogCause(hwnd, hint) {
    if (Lg.Mark.Has(hwnd) && A_TickCount < Lg.Mark[hwnd].until)
        return "tool"
    if (hint = "user")
        return "user"
    if (hint = "input")
        return (A_TimeIdlePhysical < 1000) ? "user" : "app"
    return "app"
}

LogMarkInfo(hwnd) {
    if (Lg.Mark.Has(hwnd) && A_TickCount < Lg.Mark[hwnd].until)
        return Lg.Mark[hwnd]
    return {action: "", target: ""}
}

; ==============================================================
;  窓の記録
; ==============================================================
LogTracked(hwnd) => Lg.Win.Has(hwnd) && !Lg.Win[hwnd].skip

; 窓を記録に加える。初見なら create を書く(snapshot 経由は書かない)。除外アプリなら false
LogTrack(hwnd, how := "") {
    if Lg.Win.Has(hwnd)
        return !Lg.Win[hwnd].skip
    try {
        proc := WinGetProcessName(hwnd)
        cls  := WinGetClass(hwnd)
    } catch
        return false
    r := {wid: Lg.NextWid, proc: proc, cls: cls, skip: Lg.Exclude.Has(proc), state: "", x: 0, y: 0, w: 0, h: 0, mon: 0, zone: "", title: ""}
    Lg.NextWid += 1
    Lg.Win[hwnd] := r
    if r.skip
        return false
    LogUpdate(hwnd)
    if (how != "snapshot")
        LogRow("create", hwnd, "", "", "", "", how != "" ? "via=" how : "")
    return true
}

; 記録を捨てる。記録があれば destroy を書く
LogForget(hwnd, how) {
    if Lg.Timers.Has(hwnd) {
        SetTimer(Lg.Timers[hwnd], 0)
        Lg.Timers.Delete(hwnd)
    }
    if LogTracked(hwnd)
        LogRow("destroy", hwnd, "", "", "", "", how != "" ? "via=" how : "")
    LogDrop(Lg.Win, hwnd), LogDrop(Lg.Cause, hwnd), LogDrop(Lg.How, hwnd)
    LogDrop(Lg.Mark, hwnd), LogDrop(Lg.Dragging, hwnd)
    if (hwnd = Lg.LastActive)
        Lg.LastActive := 0
}

; 状態と矩形を読み直して記録を更新し、変化の種類を返す
;   "" = 変化なし(または初回)、"move"、"minimize" / "restore" / "maximize" / "unmaximize"
LogUpdate(hwnd) {
    r := Lg.Win[hwnd]
    try {
        mm := WinGetMinMax(hwnd)
        state := (mm = -1) ? "min" : (mm = 1) ? "max" : "normal"
        ev := ""
        if (r.state != "" && state != r.state)
            ev := LogStateEvent(r.state, state)
        r.state := state
        if (state != "min") {                   ; 最小化中は直前の位置を保持する
            v := VisibleRect(hwnd)
            if (r.w && ev = "" && (v.x != r.x || v.y != r.y || v.w != r.w || v.h != r.h))
                ev := "move"
            r.x := v.x, r.y := v.y, r.w := v.w, r.h := v.h
            r.mon := MonitorAt(v.x + v.w // 2, v.y + v.h // 2)
            r.zone := LogZone(v, r.mon, state)
        }
        if (Lg.TitleMode != "0")
            r.title := LogTitle(hwnd)
        return ev
    } catch
        return ""
}

LogStateEvent(from, to) {
    if (to = "min")
        return "minimize"
    if (from = "min")
        return "restore"
    return (to = "max") ? "maximize" : "unmaximize"
}

; 記録を読み直し、取りこぼした変化があれば書く(activate と snapshot の前に)
LogRefresh(hwnd, via) {
    ev := LogUpdate(hwnd)
    if (ev != "") {
        m := LogMarkInfo(hwnd)
        LogRow(ev, hwnd, LogCause(hwnd, ""), m.action, m.target, "", "via=" via)
    }
}

; 見た目の矩形がどの区画に合っているか。最大化は「全体」。合わなければ ""
LogZone(v, mon, state) {
    if (state = "max")
        return "全体"
    best := "", bestD := Lg.Tol + 1
    for name, z in ZoneTable() {
        e := ZoneRect({x: z[1], y: z[2], w: z[3], h: z[4]}, mon)
        d := Max(Abs(e.x - v.x), Abs(e.y - v.y), Abs(e.w - v.w), Abs(e.h - v.h))
        if (d < bestD)
            best := name, bestD := d
    }
    return best
}

LogTitle(hwnd) {
    try t := WinGetTitle(hwnd)
    catch
        return ""
    if (Lg.TitleMode = "hash")
        return Format("{:08x}", DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", StrPtr(t), "UInt", StrLen(t) * 2, "UInt"))
    return (Lg.TitleMode = "1") ? t : ""
}

; ==============================================================
;  定期処理
; ==============================================================
; 開いている窓をすべて書く(起動時と SnapshotMinutes ごと)。取りこぼしの保険
LogSnapshot() {
    if (!Lg.On || Lg.Paused)
        return
    LogTz()
    seen := Map()
    for hwnd in WinGetList() {
        if !IsAppWindow(hwnd)
            continue
        seen[hwnd] := true
        if !Lg.Win.Has(hwnd) {
            if !LogTrack(hwnd, "snapshot")
                continue
        } else {
            if !LogTracked(hwnd)
                continue
            LogRefresh(hwnd, "snapshot")
        }
        LogRow("snapshot", hwnd)
    }
    ; 消えたのに destroy を取りこぼした窓
    for hwnd in Lg.Win.Clone()
        if (!seen.Has(hwnd) && !WinExist(hwnd))
            LogForget(hwnd, "snapshot")
}

LogIdleCheck() {
    if (!Lg.On || Lg.IdleMin <= 0)
        return
    idle := A_TimeIdlePhysical
    if (!Lg.Idle && idle >= Lg.IdleMin * 60000) {
        Lg.Idle := true
        LogRow("idle", 0, "", "", "", "", "since=" (A_TickCount - idle))
    } else if (Lg.Idle && idle < Lg.IdleMin * 60000) {
        Lg.Idle := false
        LogRow("resume", 0, "", "", "", "", "at=" (A_TickCount - idle))
    }
}

LogSessionMsg(wParam, lParam, *) {
    if (wParam = 7)                                         ; WTS_SESSION_LOCK
        LogRow("lock")
    else if (wParam = 8)                                    ; WTS_SESSION_UNLOCK
        LogRow("unlock")
}

LogDisplayMsg(*) {
    SetTimer(LogMonitors, -1000)
}

LogMonitors() {
    if !Lg.On
        return
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
        LogRow("monitor", 0, "", "", "", "", "mon=" A_Index ";x=" l ";y=" t ";w=" (r - l) ";h=" (b - t)
            ";work=" wl "/" wt "/" (wr - wl) "/" (wb - wt) ";dpi=" LogMonitorDpi(l, t)
            ";primary=" (A_Index = MonitorGetPrimary() ? 1 : 0))
    }
}

LogMonitorDpi(x, y) {
    dpi := A_ScreenDPI
    try {
        if (A_PtrSize = 8)
            hmon := DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 2, "Ptr")
        else
            hmon := DllCall("MonitorFromPoint", "Int", x, "Int", y, "UInt", 2, "Ptr")
        DllCall("shcore\GetDpiForMonitor", "Ptr", hmon, "UInt", 0, "UInt*", &dx, "UInt*", &dy)
        dpi := dx
    }
    return dpi
}

; ==============================================================
;  書き込み
; ==============================================================
LogRow(event, hwnd := 0, cause := "", action := "", target := "", result := "", detail := "") {
    if (!Lg.On || Lg.Paused)
        return
    has := hwnd && Lg.Win.Has(hwnd)
    if (has && Lg.Win[hwnd].skip)
        return
    Lg.Seq += 1
    n := A_Now
    ts := SubStr(n, 1, 4) "-" SubStr(n, 5, 2) "-" SubStr(n, 7, 2) "T" SubStr(n, 9, 2) ":" SubStr(n, 11, 2) ":" SubStr(n, 13, 2) "." A_MSec Lg.Tz
    f := [ts, A_TickCount, Lg.Session, Lg.Seq, event]
    if has {
        r := Lg.Win[hwnd]
        f.Push(r.wid, Format("0x{:X}", hwnd), r.proc, r.cls, r.mon, r.state, r.x, r.y, r.w, r.h, r.zone)
    } else
        f.Push("", "", "", "", "", "", "", "", "", "", "")
    f.Push(cause, action, target, result, detail, has ? Lg.Win[hwnd].title : "")
    line := ""
    for i, v in f
        line .= (i > 1 ? "," : "") LogCsv(v)
    Lg.Buf.Push(line)
    if (Lg.Buf.Length >= 50)
        LogFlush()
}

LogHeader() => "ts,tick,session,seq,event,wid,hwnd,proc,cls,mon,state,x,y,w,h,zone,cause,action,target,result,detail,title"

; RFC 4180: カンマ・引用符・改行を含む値は引用符で囲む(改行は空白にする)
LogCsv(v) {
    s := String(v)
    if !RegExMatch(s, '[,"\r\n]')
        return s
    s := StrReplace(StrReplace(s, "`r", " "), "`n", " ")
    return '"' StrReplace(s, '"', '""') '"'
}

LogFlush() {
    if !Lg.Buf.Length
        return
    rows := Lg.Buf, Lg.Buf := []
    path := Lg.Dir "\" FormatTime(A_Now, "yyyy-MM-dd") ".csv"
    text := ""
    for line in rows
        text .= line "`r`n"
    try {
        if !FileExist(path)
            FileAppend(LogHeader() "`r`n", path, "UTF-8")
        FileAppend(text, path, "UTF-8")
        Lg.WriteError := false
    } catch {
        if !Lg.WriteError {
            Lg.WriteError := true
            ShowTip("ログを書き込めません: " path)
        }
    }
}

; ローカル時刻と UTC の差 → "+09:00"
LogTz() {
    m := Round(DateDiff(A_Now, A_NowUTC, "Seconds") / 60)
    Lg.Tz := Format("{}{:02}:{:02}", m < 0 ? "-" : "+", Abs(m) // 60, Mod(Abs(m), 60))
}

; LogKeepDays より古いログを消す
LogPurge() {
    if (Lg.KeepDays <= 0)
        return
    limit := DateAdd(A_Now, -Lg.KeepDays, "Days")
    Loop Files Lg.Dir "\*.csv" {
        if !RegExMatch(A_LoopFileName, "^(\d{4})-(\d{2})-(\d{2})\.csv$", &m)
            continue
        if ((m[1] m[2] m[3] "000000") < limit)
            try FileDelete(A_LoopFileFullPath)
    }
}

; ==============================================================
;  補助
; ==============================================================
LogDrop(map, key) {
    if map.Has(key)
        map.Delete(key)
}
