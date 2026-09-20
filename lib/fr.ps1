# fr.ps1 - 最近使ったファイルを fzf で検索して開く(仕様: docs/recent_files.md)
# 本体の RecentFiles() が Windows Terminal 上で実行する。単体で実行しても動く
#
# 一覧は「ファイル名  更新日時  フォルダ(省略形)」の列にして、検索もその部分だけを対象にする。
# 各行は「フルパス + TAB + 表示用の文字列」で、fzf には TAB の後ろだけを見せ、Enter で TAB の前を開く。

# 日本語ファイル名の文字化け対策
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ==============================================================
#  表示の整形(tests\fr.tests.ps1 が dot-source して検証する)
# ==============================================================

# 画面上の幅(全角 = 2桁)。絵文字などのサロゲートペアは 2 単位 = 2桁として数える
function Get-Width([string]$s) {
    return $s.Length + [regex]::Matches($s, '[\u1100-\u115F\u2E80-\u303E\u3041-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]').Count
}

# 幅が max を超えたら、末尾 tail 桁を残して中央を … にする(拡張子が見えるように)
function Format-Ellipsis([string]$s, [int]$max, [int]$tail = 12) {
    if ((Get-Width $s) -le $max) { return $s }
    $tail = [Math]::Min($tail, [Math]::Max(0, $max - 2))
    $si = [System.Globalization.StringInfo]::new($s)          # サロゲートペアや結合文字を 1 文字として扱う
    $n = $si.LengthInTextElements
    $t = ''; $tw = 0
    for ($i = $n - 1; $i -ge 0; $i--) {
        $c = $si.SubstringByTextElements($i, 1)
        $cw = Get-Width $c
        if ($tw + $cw -gt $tail) { break }
        $t = $c + $t; $tw += $cw
    }
    $h = ''; $hw = 0; $budget = $max - $tw - 1
    for ($i = 0; $i -lt $n; $i++) {
        $c = $si.SubstringByTextElements($i, 1)
        $cw = Get-Width $c
        if ($hw + $cw -gt $budget) { break }
        $h += $c; $hw += $cw
    }
    return "$h…$t"
}

# 幅 max の列にそろえる(長ければ … で詰め、短ければ右に空白を足す)
function Format-Cell([string]$s, [int]$max) {
    $s = Format-Ellipsis $s $max
    return $s + (' ' * [Math]::Max(0, $max - (Get-Width $s)))
}

# フォルダの省略形。%USERPROFILE% は ~ に、長ければ先頭の要素と末尾の要素を残して間を … にする
function Format-Folder([string]$dir, [int]$max) {
    $up = if ($env:USERPROFILE) { $env:USERPROFILE.TrimEnd('\') } else { '' }
    if ($up -and ($dir.Equals($up, [StringComparison]::OrdinalIgnoreCase) -or
                  $dir.StartsWith($up + '\', [StringComparison]::OrdinalIgnoreCase))) {
        $dir = '~' + $dir.Substring($up.Length)
    }
    if ((Get-Width $dir) -le $max) { return $dir }
    $parts = @($dir -split '\\')
    $headCount = if ($dir.StartsWith('\\')) { 4 } else { 1 }     # \\server\share は 4 要素、~ や C: は 1 要素
    if ($parts.Count -le $headCount + 1) { return Format-Ellipsis $dir $max }
    $head = ($parts[0..($headCount - 1)] -join '\') + '\…'
    $tail = ''
    for ($i = $parts.Count - 1; $i -ge $headCount; $i--) {  # 末尾の要素から、入るだけ残す
        $cand = '\' + $parts[$i] + $tail
        if ((Get-Width ($head + $cand)) -gt $max) { break }
        $tail = $cand
    }
    if ($tail -eq '') { return Format-Ellipsis $parts[-1] $max }
    return $head + $tail
}

# 1件を 1 行に: フルパス + TAB + 「ファイル名  更新日時  フォルダ」
function Format-Line([string]$target, [bool]$isDir, [datetime]$time, [int]$nameW, [int]$folderW) {
    $i = $target.LastIndexOf('\')
    $name = if ($i -ge 0) { $target.Substring($i + 1) } else { $target }
    $dir  = if ($i -ge 0) { $target.Substring(0, $i) } else { '' }
    if ($name -eq '') { $name = $target; $dir = '' }              # D:\ のようなルート
    if ($isDir -and -not $name.EndsWith('\')) { $name += '\' }
    $date = $time.ToString('MM/dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    return $target + "`t" + (Format-Cell $name $nameW) + '  ' + $date + '  ' + (Format-Folder $dir $folderW)
}

# ==============================================================
#  本体
# ==============================================================
if ($MyInvocation.InvocationName -eq '.') { return }          # テストが関数だけを読み込むとき

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Host "fzf が見つかりません。次のコマンドでインストールしてください:"
    Write-Host "  winget install junegunn.fzf"
    Read-Host "Enter で閉じます" | Out-Null
    exit 0
}

# 列の幅は画面の幅から決める(fzf のポインター 2 桁とスクロールバー 1 桁を除く)
$cols = 110
try { if ($Host.UI.RawUI.WindowSize.Width -ge 60) { $cols = $Host.UI.RawUI.WindowSize.Width } } catch {}
$nameW   = [Math]::Max(20, [Math]::Min(42, $cols - 60))     # 110 列なら 42
$folderW = $cols - 3 - $nameW - 2 - 11 - 2                    # 110 列なら 50

# Windows の「最近使った項目」(.lnk)を新しい順に並べ、リンク先を取り出す
$sh   = New-Object -ComObject WScript.Shell
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$lines = foreach ($lnk in (Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\*.lnk" | Sort-Object LastWriteTime -Descending)) {
    $target = $sh.CreateShortcut($lnk.FullName).TargetPath
    if (-not $target -or -not $seen.Add($target)) { continue }   # 空のパスと重複を除く
    $isDir = [System.IO.Directory]::Exists($target)
    if (-not $isDir -and -not [System.IO.File]::Exists($target)) { continue }   # もう無いもの
    Format-Line $target $isDir $lnk.LastWriteTime $nameW $folderW
}

if (-not $lines) {
    Write-Host "最近使った項目がありません(Windows の設定「最近使った項目を表示する」を確認してください)"
    Read-Host "Enter で閉じます" | Out-Null
    exit 0
}

$line = $lines | fzf --prompt "Recent> " --reverse --tiebreak=index --delimiter '\t' --with-nth 2 --nth 2
if ($line) { Invoke-Item -LiteralPath (($line -split "`t", 2)[0]) }
exit 0  # Esc でキャンセルしてもウィンドウが閉じるように
