param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$EvidenceRoot,
    [switch]$SkipLayerUI
)

# Dedicated silent host: PSD/MIDI/model/UI only. Never run TestEditorStage1 here.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$taskRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $taskRoot 'Temp\EditorStage1\slot-library'
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
[IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
$taskResultPath = Join-Path $EvidenceRoot 'noaudio-result.json'
$taskResult = [ordered]@{ Status = 'compiling'; StartedUtc = [DateTime]::UtcNow.ToString('o'); Passed = $false; AudioRun = $false }
$taskResult | ConvertTo-Json | Set-Content -LiteralPath $taskResultPath -Encoding UTF8
[IO.File]::WriteAllText((Join-Path $EvidenceRoot 'noaudio-tests.log'), 'NOT_RUN: compilation has not completed.')
[IO.File]::WriteAllText((Join-Path $EvidenceRoot 'noaudio-tests.stderr.log'), '')
$testRoot = Join-Path $taskRoot 'Tests'
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'Win64\DCU')) | Out-Null
Push-Location -LiteralPath $testRoot
try {
    & (Join-Path $BdsRoot 'bin\dcc64.exe') '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' 'SYNC_MusicStudio_SharedLibraryWorker.dpr' 2>&1 |
        Tee-Object -FilePath (Join-Path $EvidenceRoot 'shared-library-worker-compile.log')
    if ($LASTEXITCODE -ne 0) { throw "Shared-library worker compilation failed: $LASTEXITCODE" }
    & (Join-Path $BdsRoot 'bin\dcc64.exe') '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' 'SYNC_MusicStudio_NoAudioTests.dpr' 2>&1 |
        Tee-Object -FilePath (Join-Path $EvidenceRoot 'noaudio-compile.log')
    if ($LASTEXITCODE -ne 0) { throw "No-audio compilation failed: $LASTEXITCODE" }
    $taskResult.Status = 'running'; $taskResult | ConvertTo-Json | Set-Content -LiteralPath $taskResultPath -Encoding UTF8
    $testExe = Join-Path $testRoot 'Win64\SYNC_MusicStudio_NoAudioTests.exe'
    $testArgs = '"' + $EvidenceRoot + '"'
    if ($SkipLayerUI) { $testArgs += ' --skip-layers' }
    $proc = Start-Process -FilePath $testExe -ArgumentList $testArgs -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $EvidenceRoot 'noaudio-tests.log') `
        -RedirectStandardError (Join-Path $EvidenceRoot 'noaudio-tests.stderr.log')
    $null = $proc.Handle
    # The 120-row thumbnail/LRU checks extend this suite. Keep each wait short.
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (-not $proc.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -ge $deadline) { $proc.Kill(); throw 'No-audio tests timed out.' }
    }
    $proc.WaitForExit(); $proc.Refresh()
    Get-Content -LiteralPath (Join-Path $EvidenceRoot 'noaudio-tests.log') -Encoding UTF8
    if ($proc.ExitCode -ne 0) { throw "No-audio tests failed: $($proc.ExitCode)" }
    $taskResult.Status = 'passed'; $taskResult.Passed = $true
} catch {
    $taskResult.Status = 'failed'; $taskResult.Error = $_.Exception.Message
    throw
} finally {
    $taskResult.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $taskResult | ConvertTo-Json | Set-Content -LiteralPath $taskResultPath -Encoding UTF8
    Pop-Location
}
