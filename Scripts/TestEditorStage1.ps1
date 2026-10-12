param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [switch]$AllowAudioTests
)
$ErrorActionPreference = 'Stop'
# No fixture, decoder or output is started before an explicit audio opt-in.
if (-not $AllowAudioTests) {
    throw 'AUDIO_TESTS_BLOCKED: Use TestNoAudio.ps1. AllowAudioTests is only for an explicit user audio-resume authorization.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $projectRoot 'Tests'
$testOutput = Join-Path $testRoot 'Win64'
$evidenceRoot = Join-Path $projectRoot 'Temp\EditorStage1\verification'
[IO.Directory]::CreateDirectory((Join-Path $testOutput 'DCU')) | Out-Null
[IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
$compilerPath = Join-Path $BdsRoot 'bin\dcc64.exe'
# コンパイル失敗でも前回の成功ログを今回の結果として残さない。
$stdoutPath = Join-Path $evidenceRoot 'editor-tests.log'
$stderrPath = Join-Path $evidenceRoot 'editor-tests.stderr.log'
[IO.File]::WriteAllText($stdoutPath, 'NOT_RUN: compilation has not completed.')
[IO.File]::WriteAllText($stderrPath, '')
Push-Location -LiteralPath $testRoot
try {
    foreach ($testProject in @('SYNC_MusicStudio_EditorStage1Tests', 'SYNC_MusicStudio_EditorPreview')) {
        & $compilerPath '-B' '-Q' '-$R+' '-$Q+' '-EWin64' '-N0Win64\DCU' ($testProject + '.dpr')
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $testProject" }
    }
    $testProcess = Start-Process -FilePath (Join-Path $testOutput 'SYNC_MusicStudio_EditorStage1Tests.exe') `
        -ArgumentList ('"' + $evidenceRoot + '" --allow-audio-tests') -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    # Windows PowerShell 5.1では待機前にハンドルを保持しないとExitCodeがnullになる場合がある。
    $null = $testProcess.Handle
    if (-not $testProcess.WaitForExit(60000)) {
        $testProcess.Kill()
        throw 'Editor verification timed out after 60 seconds; its test process was stopped.'
    }
    $testProcess.WaitForExit()
    $testProcess.Refresh()
    Get-Content -LiteralPath $stdoutPath
    if ($testProcess.ExitCode -ne 0) { throw 'Editor stage 1 verification failed' }
} finally { Pop-Location }
