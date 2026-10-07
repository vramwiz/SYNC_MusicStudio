param(
    [Parameter(Mandatory = $true)][ValidateSet('Prepare', 'Complete')][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('Debug', 'Release')][string]$Config,
    [Parameter(Mandatory = $true)][ValidateSet('SYNC_MusicStudio_Filter')][string]$ProjectName
)

$ErrorActionPreference = 'Stop'
$pluginDirectory = 'C:\ProgramData\aviutl2\Plugin\SYNC_MusicStudio'
if ($Stage -eq 'Prepare') {
    [System.IO.Directory]::CreateDirectory($pluginDirectory) | Out-Null
    exit 0
}

$libraryPath = Join-Path $pluginDirectory ($ProjectName + '.dll')
$pluginPath = Join-Path $pluginDirectory ($ProjectName + '.auf2')
Copy-Item -LiteralPath $libraryPath -Destination $pluginPath -Force
if ($Config -eq 'Release') {
    # 削除対象は固定出力フォルダー内の、今回のプロジェクトの成果物だけに限定する。
    foreach ($extension in @('.dll', '.rsm')) {
        $artifactPath = Join-Path $pluginDirectory ($ProjectName + $extension)
        if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
            Remove-Item -LiteralPath $artifactPath -Force
        }
    }
}
