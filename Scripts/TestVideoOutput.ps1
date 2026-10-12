param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$PluginPath,
    [string]$EvidenceRoot
)

# Silent PSD/MIDI frame host. Never decode/play audio or deploy to AviUtl2.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$taskRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PluginPath)) { $PluginPath = Join-Path $taskRoot 'Win64\Debug\SYNC_MusicStudio_Filter.auf2' }
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { $EvidenceRoot = Join-Path $taskRoot 'Temp\EditorStage1\video-output-report\sdk-debug' }
$PluginPath = (Resolve-Path -LiteralPath $PluginPath).ProviderPath
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
[IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
$result = [ordered]@{ Status = 'compiling'; Passed = $false; AudioRun = $false; PluginPath = $PluginPath; StartedUtc = [DateTime]::UtcNow.ToString('o') }
$resultPath = Join-Path $EvidenceRoot 'video-result.json'
$result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
$testRoot = Join-Path $taskRoot 'Tests'
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'Win64\DCU')) | Out-Null
Push-Location -LiteralPath $testRoot
try {
    & (Join-Path $BdsRoot 'bin\dcc64.exe') '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' 'SYNC_MusicStudio_VideoOutputTests.dpr' 2>&1 |
        Tee-Object -FilePath (Join-Path $EvidenceRoot 'video-compile.log')
    if ($LASTEXITCODE -ne 0) { throw "Video host compilation failed: $LASTEXITCODE" }
    $result.Status = 'running'; $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $proc = Start-Process -FilePath (Join-Path $testRoot 'Win64\SYNC_MusicStudio_VideoOutputTests.exe') `
        -ArgumentList ('"' + $PluginPath + '" "' + $EvidenceRoot + '"') -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $EvidenceRoot 'video-tests.log') `
        -RedirectStandardError (Join-Path $EvidenceRoot 'video-tests.stderr.log')
    $null = $proc.Handle
    if (-not $proc.WaitForExit(60000)) { $proc.Kill(); throw 'Test-owned video host timed out.' }
    $proc.WaitForExit(); $proc.Refresh()
    Get-Content -LiteralPath (Join-Path $EvidenceRoot 'video-tests.log') -Encoding UTF8
    Get-Content -LiteralPath (Join-Path $EvidenceRoot 'video-tests.stderr.log') -Encoding UTF8
    if ($proc.ExitCode -ne 0) { throw "Video tests failed: $($proc.ExitCode)" }
    $result.Status = 'passed'; $result.Passed = $true
} catch {
    $result.Status = 'failed'; $result.Error = $_.Exception.Message
    throw
} finally {
    $result.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Pop-Location
}
