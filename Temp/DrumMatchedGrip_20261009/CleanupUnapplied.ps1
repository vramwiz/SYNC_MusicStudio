$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath 'D:\DelphiProg\SYNC_MusicStudio\Temp\DrumButtGrip_20261009').Path
$expected = 'D:\DelphiProg\SYNC_MusicStudio\Temp\DrumButtGrip_20261009'
if (-not $root.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected cleanup root' }
$names = @(
    'basic-expected-gray.png', 'basic-root-detail.png', 'basic-root-final.png', 'basic-root-fixed.png',
    'generated-basic-root.png', 'generated-raised-root-attempt1.png', 'generated-raised-root-final.png', 'generated-raised-root.png',
    'raised-expected-gray.png', 'raised-join-repair-target.png', 'raised-root-detail.png', 'raised-root-final.png', 'raised-root-fixed.png'
)
$items = foreach ($name in $names) {
    $target = (Resolve-Path -LiteralPath (Join-Path $root $name)).Path
    if (-not $target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup target outside root' }
    $item = Get-Item -LiteralPath $target
    if ($item.PSIsContainer) { throw 'Only explicit files can be cleaned' }
    [pscustomobject]@{ path = $target; bytes = $item.Length; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$manifest = [ordered]@{
    date = '2026-10-09'
    reason = 'Unapplied grip attempts superseded by the user-reference correction. Only obsolete staging copies removed.'
    root = $root
    file_count = $items.Count
    total_bytes = ($items | Measure-Object -Property bytes -Sum).Sum
    files = @($items)
    generated_originals_and_source_references_preserved = $true
    live_exchange_snapshots_preserved = $true
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'cleanup-manifest.json') -Encoding UTF8
foreach ($item in $items) { Remove-Item -LiteralPath $item.path }
foreach ($item in $items) { if (Test-Path -LiteralPath $item.path) { throw 'Cleanup incomplete' } }
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'D:\DelphiProg\SYNC_MusicStudio\Temp\DrumMatchedGrip_20261009\cleanup-manifest.json' -Encoding UTF8
[pscustomobject]@{ removed_files = $items.Count; reclaimed_bytes = $manifest.total_bytes }
