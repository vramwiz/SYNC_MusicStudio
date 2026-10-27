param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
# 現行MusicStudioだけを検査する。継承UI・生成物・Git内部は走査しない。
# 違反時はビルド開始前に停止する。ファイル変更・削除・配備は行わない。
$ErrorActionPreference = 'Stop'
$layoutRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$layoutUnits = @(Get-ChildItem -LiteralPath (Join-Path $layoutRoot 'Source') -Filter 'SYNC_MusicStudio_*.pas' -File -Recurse)
if ($layoutUnits.Count -eq 0) { throw 'No current MusicStudio units found.' }
$layoutErrors = [Collections.Generic.List[string]]::new()
$layoutMaximum = 0
foreach ($layoutUnit in $layoutUnits) {
    $layoutBytes = [IO.File]::ReadAllBytes($layoutUnit.FullName)
    $layoutText = [IO.File]::ReadAllText($layoutUnit.FullName)
    $layoutLines = [IO.File]::ReadAllLines($layoutUnit.FullName).Length
    $layoutMaximum = [Math]::Max($layoutMaximum, $layoutLines)
    if ($layoutLines -gt 1500) { $layoutErrors.Add("Split unit by responsibility ($layoutLines lines): $($layoutUnit.FullName)") }
    if ($layoutBytes.Length -lt 3 -or $layoutBytes[0] -ne 239 -or $layoutBytes[1] -ne 187 -or $layoutBytes[2] -ne 191) {
        $layoutErrors.Add("UTF-8 BOM required: $($layoutUnit.FullName)")
    }
    if ($layoutText -match '(?<!\r)\n|\r(?!\n)') { $layoutErrors.Add("CRLF required: $($layoutUnit.FullName)") }
    $layoutHeader = ($layoutText -split '(?im)^interface\s*$', 2)[0]
    if ($layoutHeader -notmatch '//|\{(?!\$)|\(\*') { $layoutErrors.Add("Purpose/responsibility comment required: $($layoutUnit.FullName)") }
}
# 既存の機能分離を保つ上限。増設時は用途別の子フォルダーへ分ける。
foreach ($layoutGroup in ($layoutUnits | Group-Object DirectoryName)) {
    if ($layoutGroup.Count -gt 12) { $layoutErrors.Add("Separate functional folders ($($layoutGroup.Count) units): $($layoutGroup.Name)") }
}
$layoutDpr = [IO.File]::ReadAllText((Join-Path $layoutRoot 'SYNC_MusicStudio_Filter.dpr'))
$layoutDproj = [xml][IO.File]::ReadAllText((Join-Path $layoutRoot 'SYNC_MusicStudio_Filter.dproj'))
$layoutReferences = @([regex]::Matches($layoutDpr, "(?i)\bin\s+'([^']+\.pas)'") | ForEach-Object { $_.Groups[1].Value })
$layoutIdeReferences = @($layoutDproj.SelectNodes("//*[local-name()='DCCReference']") | ForEach-Object { $_.GetAttribute('Include') })
foreach ($layoutSet in @(@{Name='dpr'; Paths=$layoutReferences}, @{Name='dproj'; Paths=$layoutIdeReferences})) {
    foreach ($layoutDuplicate in ($layoutSet.Paths | Group-Object | Where-Object Count -gt 1)) {
        $layoutErrors.Add("Duplicate $($layoutSet.Name) reference: $($layoutDuplicate.Name)")
    }
    foreach ($layoutReference in $layoutSet.Paths) {
        if (-not (Test-Path -LiteralPath (Join-Path $layoutRoot $layoutReference) -PathType Leaf)) {
            $layoutErrors.Add("Missing $($layoutSet.Name) reference: $layoutReference")
        }
    }
}
foreach ($layoutUnit in $layoutUnits) {
    $layoutRelative = $layoutUnit.FullName.Substring($layoutRoot.Length + 1)
    if ($layoutRelative -notin $layoutReferences -or $layoutRelative -notin $layoutIdeReferences) {
        $layoutErrors.Add("Register unit in both dpr/dproj: $layoutRelative")
    }
    $layoutDfm = [IO.Path]::ChangeExtension($layoutUnit.FullName, '.dfm')
    if ($layoutUnit.Name -match 'Frame|Form' -and ([IO.File]::ReadAllText($layoutUnit.FullName) -match '(?i)\{\$R\s+\*\.dfm\}') -and -not (Test-Path -LiteralPath $layoutDfm)) {
        $layoutErrors.Add("Keep form/dfm together: $layoutRelative")
    }
}
if ($layoutErrors.Count -gt 0) { throw ($layoutErrors -join [Environment]::NewLine) }
Write-Output "SOURCE_LAYOUT_OK units=$($layoutUnits.Count) maxLines=$layoutMaximum folderLimit=12"
