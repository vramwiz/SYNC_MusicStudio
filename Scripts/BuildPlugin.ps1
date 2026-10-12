param(
    [Parameter(Mandatory = $true)][ValidateSet('Prepare', 'Complete')][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('Debug', 'Release')][string]$Config,
    [Parameter(Mandatory = $true)][ValidateSet('SYNC_MusicStudio_Filter')][string]$ProjectName,
    [string]$OutputDirectory,
    [string]$LibraryPath,
    [string]$DeployDirectory
)

$ErrorActionPreference = 'Stop'
if (-not [string]::IsNullOrWhiteSpace($LibraryPath)) {
    $LibraryPath = [IO.Path]::GetFullPath($LibraryPath)
    if ([IO.Path]::GetFileName($LibraryPath) -ne ($ProjectName + '.dll')) {
        throw 'The build event must pass the actual SYNC_MusicStudio_Filter.dll output path.'
    }
    $OutputDirectory = [IO.Path]::GetDirectoryName($LibraryPath)
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('Win64\' + $Config)
}
$pluginDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if ($Stage -eq 'Prepare') {
    [System.IO.Directory]::CreateDirectory($pluginDirectory) | Out-Null
    Write-Output ('PLUGIN_OUTPUT_PREPARED ' + $Config + ': ' + $pluginDirectory)
    exit 0
}

if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
    $LibraryPath = Join-Path $pluginDirectory ($ProjectName + '.dll')
}
$pluginPath = Join-Path $pluginDirectory ($ProjectName + '.auf2')
[IO.File]::Copy($LibraryPath, $pluginPath, $true)
if ($Config -eq 'Release') {
    # DLLはDelphi/IDEの標準出力として保持する。配布時はauf2だけを選ぶ。
    # 前の構成が残したデバッグ記号だけを、固定のファイル名で整理する。
    $symbolsPath = Join-Path $pluginDirectory ($ProjectName + '.rsm')
    if (Test-Path -LiteralPath $symbolsPath -PathType Leaf) {
        Remove-Item -LiteralPath $symbolsPath -Force
    }
}
Write-Output ('PLUGIN_OUTPUT_COPIED ' + $Config + ': ' + $pluginPath)
if (-not [string]::IsNullOrWhiteSpace($DeployDirectory)) {
    $deployRoot = [IO.Path]::GetFullPath($DeployDirectory).TrimEnd('\')
    # 元プロジェクトの既定配備先だけを許可。他のプラグインや実作品へ書き込まない。
    if ($deployRoot -ne 'C:\ProgramData\aviutl2\Plugin\SYNC_MusicStudio') {
        throw 'Unexpected plugin deployment directory.'
    }
    [IO.Directory]::CreateDirectory($deployRoot) | Out-Null
    $deployedPath = Join-Path $deployRoot ($ProjectName + '.auf2')
    if ([IO.File]::Exists($deployedPath)) {
        # 稼働中DLL等のロックを尊重。属性解除・プロセス終了・強制置換は行わない。
        $exclusive = [IO.File]::Open($deployedPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $exclusive.Dispose()
    }
    [IO.File]::Copy($pluginPath, $deployedPath, $true)
    Write-Output ('PLUGIN_DEPLOYED ' + $Config + ': ' + $deployedPath)
}
