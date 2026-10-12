param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$PluginPath,
    [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PluginPath)) {
    $PluginPath = Join-Path $projectRoot 'Win64\Debug\SYNC_MusicStudio_Filter.auf2'
}
$PluginPath = (Resolve-Path -LiteralPath $PluginPath).ProviderPath
if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath)) {
    $ScreenshotPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScreenshotPath)
}
$testRoot = Join-Path $projectRoot 'Tests'
$testOutput = Join-Path $testRoot 'Win64'
[System.IO.Directory]::CreateDirectory((Join-Path $testOutput 'DCU')) | Out-Null
$compilerPath = Join-Path $BdsRoot 'bin\dcc64.exe'
Push-Location -LiteralPath $testRoot
try {
    & $compilerPath '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' 'SYNC_MusicStudio_FoundationTests.dpr'
    if ($LASTEXITCODE -ne 0) { throw "Foundation test compilation failed: $LASTEXITCODE" }
    & (Join-Path $testOutput 'SYNC_MusicStudio_FoundationTests.exe') $PluginPath $ScreenshotPath
    if ($LASTEXITCODE -ne 0) { throw "Foundation tests failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}
