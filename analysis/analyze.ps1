<#
.SYNOPSIS
  操作ログを Docker で解析する(Python のインストール不要)。仕様: docs/logging.md 第8章
.DESCRIPTION
  analysis/Dockerfile からイメージを作り(2回目からはキャッシュで一瞬)、ログフォルダを
  読み取り専用でマウントして analyze.py を実行する。Docker Desktop が必要。
.EXAMPLE
  .\analysis\analyze.ps1                              # %LOCALAPPDATA%\claude_hotkey\logs を解析
  .\analysis\analyze.ps1 -LogDir D:\logs --min-life 5  # フォルダと analyze.py のオプションを指定
  .\analysis\analyze.ps1 -Test                        # 解析スクリプトのテスト(合成ログで検算)
  .\analysis\analyze.ps1 -Rebuild                     # イメージを作り直す
#>
[CmdletBinding()]
param(
    [string]$LogDir = "$env:LOCALAPPDATA\claude_hotkey\logs",
    [switch]$Test,
    [switch]$Rebuild,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Options = @()
)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # コンテナからの日本語の出力を化けさせない
$image = "claude-hotkey-analyze"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "docker が見つかりません。Docker Desktop をインストールして起動してください。"
    exit 1
}
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker が動いていません。Docker Desktop を起動してください。"
    exit 1
}

# イメージを作る(Dockerfile と analyze.py が変わっていなければキャッシュで一瞬)
docker image inspect $image 2>$null | Out-Null
if ($LASTEXITCODE -ne 0 -or $Rebuild) {
    Write-Host "解析用のイメージを作成します(初回だけ数十秒かかります)..."
}
docker build -q -t $image $PSScriptRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "イメージの作成に失敗しました。"
    exit 1
}

if ($Test) {
    docker run --rm --entrypoint python $image test_analyze.py
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $LogDir)) {
    Write-Host "ログフォルダがありません: $LogDir"
    Write-Host "claude_hotkey.ini の [General] で Log=1 にして再読み込みすると作られます。"
    exit 1
}
$LogDir = (Resolve-Path -LiteralPath $LogDir).Path
docker run --rm -v "${LogDir}:/logs:ro" $image /logs @Options
exit $LASTEXITCODE
