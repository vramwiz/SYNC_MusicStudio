param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$EvidenceRoot
)
# Compile the mixed host, then exercise only its early refusal path.
# This script never supplies the audio opt-in switch and never runs an audio fixture.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$taskRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { $EvidenceRoot = Join-Path $taskRoot 'Temp\EditorStage1\silent-regression' }
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
[IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
$scriptBlocked = $false
try { & (Join-Path $PSScriptRoot 'TestEditorStage1.ps1') -BdsRoot 'Z:\DO_NOT_START_COMPILER' }
catch {
    if ($_.Exception.Message -notlike 'AUDIO_TESTS_BLOCKED:*') { throw }
    $scriptBlocked = $true
}
if (-not $scriptBlocked) { throw 'Mixed test script did not refuse audio tests.' }
$testRoot = Join-Path $taskRoot 'Tests'
Push-Location -LiteralPath $testRoot
try {
    & (Join-Path $BdsRoot 'bin\dcc64.exe') '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' 'SYNC_MusicStudio_EditorStage1Tests.dpr' 2>&1 |
        Tee-Object -FilePath (Join-Path $EvidenceRoot 'audio-gate-compile.log')
    if ($LASTEXITCODE -ne 0) { throw 'Mixed host compilation failed.' }
    $probePath = Join-Path $EvidenceRoot ('must-not-create-' + [Guid]::NewGuid().ToString('N'))
    $proc = Start-Process -FilePath (Join-Path $testRoot 'Win64\SYNC_MusicStudio_EditorStage1Tests.exe') `
        -ArgumentList ('"' + $probePath + '"') -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $EvidenceRoot 'audio-gate.log') `
        -RedirectStandardError (Join-Path $EvidenceRoot 'audio-gate.stderr.log')
    $null = $proc.Handle
    if (-not $proc.WaitForExit(10000)) { $proc.Kill(); throw 'Audio gate did not exit promptly.' }
    $proc.WaitForExit(); $proc.Refresh()
    $message = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'audio-gate.log') -Raw -Encoding UTF8
    if (($proc.ExitCode -ne 2) -or ($message -notlike 'AUDIO_TESTS_BLOCKED:*') -or (Test-Path -LiteralPath $probePath)) {
        throw 'Audio gate failed; do not run the mixed host.'
    }
    'AUDIO_GATE_SCRIPT_AND_EXE_REFUSE_BEFORE_FIXTURES_OK' | Tee-Object -FilePath (Join-Path $EvidenceRoot 'audio-gate-result.log')
} finally { Pop-Location }
