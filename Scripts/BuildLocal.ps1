param(
    [string]$BdsRoot = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
    [string]$EvidenceRoot = (Join-Path $env:TEMP 'SYNC_MusicStudio-local-build')
)
# IDEの配備イベントは変更せず、MSBuild呼出時だけ無配備へ上書きする。
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'TestSourceLayout.ps1') -ProjectRoot $taskRoot
[IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
foreach ($configuration in @('Debug','Release')) {
    $command = 'call "{0}\bin\rsvars.bat" && msbuild "{1}\SYNC_MusicStudio_Filter.dproj" /t:Build /p:Config={2} /p:Platform=Win64 "/p:PostBuildEvent=echo LOCAL_NO_DEPLOY" /nologo /v:minimal' -f $BdsRoot,$taskRoot,$configuration
    & $env:ComSpec /d /c $command 2>&1 | Tee-Object -FilePath (Join-Path $EvidenceRoot ('build-'+$configuration+'.log'))
    if ($LASTEXITCODE -ne 0) { throw "Local $configuration build failed: $LASTEXITCODE" }
    & (Join-Path $PSScriptRoot 'BuildPlugin.ps1') -Stage Complete -Config $configuration -ProjectName 'SYNC_MusicStudio_Filter' -LibraryPath (Join-Path $taskRoot "Win64\$configuration\SYNC_MusicStudio_Filter.dll")
}
