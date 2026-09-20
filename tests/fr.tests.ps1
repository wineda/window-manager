# fr.ps1 の表示整形のテスト(Pester 不要)
#   実行: pwsh -File tests\fr.tests.ps1   (Windows PowerShell 5.1 なら powershell -File)
#   fr.ps1 を dot-source すると関数だけが読み込まれ、fzf は起動しない
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:USERPROFILE = 'C:\Users\user'
. "$PSScriptRoot\..\lib\fr.ps1"

$script:fail = 0
function Check([string]$label, $actual, $expected) {
    if ("$actual" -ceq "$expected") { Write-Host "[OK ] $label" }
    else {
        Write-Host "[NG ] $label"
        Write-Host "      期待: [$expected]"
        Write-Host "      実際: [$actual]"
        $script:fail++
    }
}
$e = [char]0x2026                                            # …
$emoji = [char]::ConvertFromUtf32(0x1F600)                   # 😀(サロゲートペア)

# ---- Get-Width ----
Check '幅: ASCII'          (Get-Width 'abc.txt') 7
Check '幅: 全角'           (Get-Width '見積書') 6
Check '幅: 混在'           (Get-Width '見積書_v3.xlsx') 14
Check '幅: 半角カナは 1'   (Get-Width 'ｱｲｳ') 3
Check '幅: 全角記号'       (Get-Width ([string][char]0xFF08 + '株' + [char]0xFF09)) 6   # (株)
Check '幅: 全角スペース'   (Get-Width '　') 2
Check '幅: 絵文字は 2'     (Get-Width $emoji) 2
Check '幅: … は 1'         (Get-Width $e) 1
Check '幅: 空'             (Get-Width '') 0

# ---- Format-Ellipsis ----
Check '省略: 収まれば変えない'   (Format-Ellipsis 'abc' 10) 'abc'
Check '省略: ASCII'              (Format-Ellipsis 'abcdefghijklmnopqrstuvwxyz' 15 5) "abcdefghi${e}vwxyz"
Check '省略: 拡張子を残す'       (Format-Ellipsis '見積書_とても長いファイル名_2026年9月版_v3.xlsx' 20 8) "見積書_とて${e}_v3.xlsx"
Check '省略: 幅 20 ちょうど'     (Get-Width (Format-Ellipsis '見積書_とても長いファイル名_2026年9月版_v3.xlsx' 20 8)) 20
Check '省略: 全角の境界'         (Format-Ellipsis 'ああああああ' 7 2) "ああ${e}あ"
$r = Format-Ellipsis ($emoji * 10) 7 2
Check '省略: 絵文字を割らない'   ([System.Globalization.StringInfo]::new($r).LengthInTextElements) 4
Check '省略: 絵文字の幅'         (Get-Width $r) 7
Check '省略: max が小さい'       (Get-Width (Format-Ellipsis 'abcdefghijklmnop' 5)) 5

# ---- Format-Cell ----
Check '列: 右に空白'         (Format-Cell 'a.txt' 10) 'a.txt     '
Check '列: 全角の幅で詰める' (Format-Cell '見積' 6) '見積  '
Check '列: 長ければ詰める'   (Get-Width (Format-Cell ('x' * 50) 10)) 10
Check '列: ちょうど'         (Format-Cell 'abcde' 5) 'abcde'

# ---- Format-Folder ----
Check 'フォルダ: ~ に置換'           (Format-Folder 'C:\Users\user\Documents' 50) '~\Documents'
Check 'フォルダ: プロファイル直下'   (Format-Folder 'C:\Users\user' 50) '~'
Check 'フォルダ: 大文字小文字'       (Format-Folder 'c:\users\USER\Downloads' 50) '~\Downloads'
Check 'フォルダ: 別ユーザーは残す'   (Format-Folder 'C:\Users\userX\Documents' 50) 'C:\Users\userX\Documents'
Check 'フォルダ: 中央を省略'         (Format-Folder 'C:\Users\user\Documents\プロジェクト\2026\第3四半期' 20) "~\${e}\2026\第3四半期"
Check 'フォルダ: UNC の先頭を残す'   (Format-Folder '\\nas\share\総務\経費精算\2026\9月' 22) "\\nas\share\${e}\2026\9月"
Check 'フォルダ: UNC 幅'             (Get-Width (Format-Folder '\\nas\share\総務\経費精算\2026\9月' 22)) 22
Check 'フォルダ: 要素が入らない'     (Format-Folder 'C:\Users\user\Documents\とても長いフォルダ名がここにあります' 12) "${e}にあります"
Check 'フォルダ: 空'                 (Format-Folder '' 50) ''
Check 'フォルダ: 他ドライブ'         (Format-Folder 'D:\写真\2026' 50) 'D:\写真\2026'

# ---- Format-Line ----
$t = Get-Date -Year 2026 -Month 9 -Day 19 -Hour 11 -Minute 40 -Second 0
$line = Format-Line 'C:\Users\user\Documents\見積書_ABC商事_v3.xlsx' $false $t 42 50
$full, $shown = $line -split "`t", 2
Check '行: TAB の前はフルパス'   $full 'C:\Users\user\Documents\見積書_ABC商事_v3.xlsx'
Check '行: 表示部'               $shown ('見積書_ABC商事_v3.xlsx' + (' ' * 20) + '  09/19 11:40  ~\Documents')   # 名前は 22 桁
Check '行: 表示部の幅'           (Get-Width $shown) (42 + 2 + 11 + 2 + 11)
$line = Format-Line 'C:\Users\user\Documents\プロジェクト' $true $t 42 50
Check '行: フォルダは末尾に \'  (($line -split "`t", 2)[1].Substring(0, 7)) 'プロジェクト\'
$line = Format-Line 'D:\' $true $t 42 50
Check '行: ドライブのルート'     (($line -split "`t", 2)[1].TrimEnd()) ('D:\' + (' ' * 39) + '  09/19 11:40')
$line = Format-Line '\\nas\share\総務\経費精算_2026.xlsx' $false $t 42 50
Check '行: UNC'                  (($line -split "`t", 2)[1]) ('経費精算_2026.xlsx' + (' ' * 24) + '  09/19 11:40  \\nas\share\総務')

# ---- 110 列で表示部が 107 桁に収まる(長いパスの総当たり)----
$samples = @(
    'C:\Users\user\OneDrive - 株式会社サンプル\Documents\プロジェクト\2026\第3四半期\案件A\見積書_ABC商事_とても長いファイル名_最終版_v3.xlsx',
    '\\nas\share\総務部\経費精算\2026年度\9月\個人別\経費精算書_山田太郎_2026-09.xlsx',
    'C:\Users\user\AppData\Local\Temp\' + ('x' * 120) + '.txt',
    'D:\'
)
$over = 0
foreach ($p in $samples) {
    $shown = (Format-Line $p $false $t 42 50 -split "`t", 2)[1]
    if ((Get-Width $shown) -gt 107) { $over++; Write-Host "      超過: $shown" }
}
Check '行: 110 列に収まる' $over 0

if ($script:fail) { Write-Host "NG: $($script:fail) 件"; exit 1 }
Write-Host "OK: すべて通過"
exit 0
