$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'plan.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$resultPath = Join-Path $PSScriptRoot 'move-result.json'
if (Test-Path -LiteralPath $resultPath) { throw 'Move result already exists.' }
$sourceRoot = [System.IO.Path]::GetFullPath($plan.png_root).TrimEnd('\') + '\'
$targetRoot = (Resolve-Path -LiteralPath $plan.psd_root).ProviderPath.TrimEnd('\')
if ($plan.moves.Count -ne 11) { throw 'Expected 11 PSD files.' }
foreach ($item in $plan.moves) {
    $sourcePath = (Resolve-Path -LiteralPath $item.source).ProviderPath
    $targetPath = [System.IO.Path]::GetFullPath($item.destination)
    if (-not $sourcePath.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected source: $sourcePath" }
    if ([System.IO.Path]::GetDirectoryName($targetPath) -ne $targetRoot) { throw "Unexpected destination: $targetPath" }
    if ((Get-Item -LiteralPath $sourcePath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source is a reparse point.' }
    if (Test-Path -LiteralPath $targetPath) { throw "Destination exists: $targetPath" }
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) { throw "Source hash mismatch: $sourcePath" }
}
$completed = @()
try {
    foreach ($item in $plan.moves) {
        Move-Item -LiteralPath $item.source -Destination $item.destination
        $completed += $item
        if ((Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) { throw 'Destination hash mismatch.' }
        if (Test-Path -LiteralPath $item.source) { throw 'Source still exists.' }
    }
} catch {
    foreach ($item in $completed) {
        if ((Test-Path -LiteralPath $item.destination) -and -not (Test-Path -LiteralPath $item.source)) {
            if ((Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $item.sha256) {
                Move-Item -LiteralPath $item.destination -Destination $item.source
            }
        }
    }
    throw
}
$result = [ordered]@{ passed=$true; count=$completed.Count; source_root=$sourceRoot; destination_root=$targetRoot; moves=$completed }
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Output "Moved and hash-verified $($completed.Count) PSDs."
