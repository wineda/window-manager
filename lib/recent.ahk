#Requires AutoHotkey v2.0

; ==============================================================
;  最近使ったファイル(仕様: docs/recent_files.md)
;    Windows の「最近使った項目」を fzf であいまい検索して開く。
;    ホットキーで Windows Terminal を起動し、lib\fr.ps1 を実行する。
;  本体から呼ぶ関数: RecentFiles(ホットキー)、RecentLoad(設定の読み込み)
;  設定: [General] の Recent(キー)/ RecentSize(列数,行数)/ RecentShell(pwsh か powershell)
; ==============================================================

; [General] の設定を読む(本体の LoadAll から)
RecentLoad(path) {
    size := Clean(IniRead(path, "General", "RecentSize", "110,30"))
    if RegExMatch(ToHalf(size), "^\d+\s*,\s*\d+$")
        Cfg.RecentSize := RegExReplace(ToHalf(size), "\s+")
    else
        Errors.Push("[General] RecentSize は「列数,行数」で書きます: " size)
    shell := Clean(IniRead(path, "General", "RecentShell", "pwsh"))
    Cfg.RecentShell := (shell != "") ? shell : "pwsh"
    Reg(IniRead(path, "General", "Recent", ""), RecentFiles, "最近使ったファイル")
}

; ホットキー: 検索用のターミナルを開く(すでに開いていれば前面に出す)
RecentFiles(*) {
    static title := "RecentFiles"
    SetDpi()
    SetTitleMatchMode(1)                                    ; タイトルの先頭一致
    win := title " ahk_exe WindowsTerminal.exe"
    if (hwnd := WinExist(win)) {
        LogTool("recent", "", "activated", hwnd)
        WinActivate(hwnd)
        return
    }
    script := A_ScriptDir "\lib\fr.ps1"
    if !FileExist(script) {
        MsgBox("fr.ps1 が見つかりません。`n`n" script, "ウィンドウ整理ツール", "Icon!")
        return
    }
    cmd := Format('wt.exe -w new --size {1} new-tab --title {2} --suppressApplicationTitle '
        . '{3} -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{4}"',
        Cfg.RecentSize, title, Cfg.RecentShell, script)
    try Run(cmd)
    catch {
        LogTool("recent", "", "error")
        MsgBox("Windows Terminal(wt.exe)を起動できません。インストールされているか確認してください。",
            "ウィンドウ整理ツール", "Icon!")
        return
    }
    hwnd := WinWait(win, , 3)
    if !hwnd {
        LogTool("recent", "", "none")
        return
    }
    Sleep(200)                                              ; --size の反映を待つ
    ; マウスのあるモニターの中央に置く(見えない枠と DPI は MoveExact が補正)
    MonitorGetWorkArea(MouseMonitor(), &l, &t, &r, &b)
    v := VisibleRect(hwnd)
    LogMark(hwnd, "recent")
    LogTool("recent", "", "launched", hwnd)
    MoveExact(hwnd, l + (r - l - v.w) // 2, t + (b - t - v.h) // 2, v.w, v.h)
    WinActivate(hwnd)
}
