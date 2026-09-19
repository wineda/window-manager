# fr.ps1 - 最近使ったファイルを fzf で検索して開く(仕様: docs/recent_files.md)
# 本体の RecentFiles() が Windows Terminal 上で実行する。単体で実行しても動く

# 日本語ファイル名の文字化け対策
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Host "fzf が見つかりません。次のコマンドでインストールしてください:"
    Write-Host "  winget install junegunn.fzf"
    Read-Host "Enter で閉じます" | Out-Null
    exit 0
}

# Windows の「最近使った項目」(.lnk)を新しい順に並べ、リンク先を取り出す
$sh = New-Object -ComObject WScript.Shell
$path = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent\*.lnk" |
  Sort-Object LastWriteTime -Descending |
  ForEach-Object { $sh.CreateShortcut($_.FullName).TargetPath } |
  Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
  Select-Object -Unique |
  fzf --prompt "Recent> " --reverse --tiebreak=index

if ($path) { Invoke-Item -LiteralPath $path }
exit 0  # Esc でキャンセルしてもウィンドウが閉じるように
