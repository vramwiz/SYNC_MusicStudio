#requires -Version 7.0
param([string]$WorkRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$exchange=[IO.Path]::GetFullPath('D:\DelphiProg\AIArtToPSD\Win64\Release\Exchange')
if((Get-Item -LiteralPath $exchange).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Exchange root is a reparse point'}
$batch=Get-Content -LiteralPath (Join-Path $WorkRoot 'batch.json') -Raw -Encoding utf8|ConvertFrom-Json
$pipes=[Collections.Generic.HashSet[string]]::new()
foreach($item in $batch){
    $verified=Get-Content -LiteralPath (Join-Path $item.staging 'app-verification.json') -Raw -Encoding utf8|ConvertFrom-Json
    if(-not $verified.passed -or (Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $verified.file_sha256){throw 'Keep verification payloads until final PSD is verified'}
    if(Get-Process -Id $verified.pid -ErrorAction SilentlyContinue){throw 'Owned application is still running; preserve its exchange jobs'}
    if(-not (Test-Path -LiteralPath (Join-Path $item.record_directory '作業報告.txt'))){throw 'Publish reports before cleanup'}
    $firstJob=Join-Path $exchange $verified.checks[0].jobId
    $connection=Get-Content -LiteralPath (Join-Path $firstJob 'connection.json') -Raw -Encoding utf8|ConvertFrom-Json
    if(-not $connection.pipeName.StartsWith('AIArtToPSD.'+$verified.pid+'.')){throw 'Owned verification pipe mismatch'}
    [void]$pipes.Add($connection.pipeName)
}
$deleted=[Collections.Generic.List[object]]::new()
$jobs=0
foreach($directory in @(Get-ChildItem -LiteralPath $exchange -Directory)){
    if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
    $connectionFile=Join-Path $directory.FullName 'connection.json'
    if(-not (Test-Path -LiteralPath $connectionFile)){continue}
    $connection=Get-Content -LiteralPath $connectionFile -Raw -Encoding utf8|ConvertFrom-Json
    if(-not $pipes.Contains($connection.pipeName)){continue}
    if($connection.jobId -ne $directory.Name){throw 'Job identity mismatch'}
    $absolute=[IO.Path]::GetFullPath($directory.FullName)
    if(-not $absolute.StartsWith($exchange+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Job path is outside explicit exchange root'}
    $targets=[Collections.Generic.List[IO.FileInfo]]::new()
    foreach($name in @('snapshot.psd','preview.png','recovery.json')){
        $path=Join-Path $absolute $name
        if(Test-Path -LiteralPath $path){$targets.Add((Get-Item -LiteralPath $path))}
    }
    $input=Join-Path $absolute 'input'
    if(Test-Path -LiteralPath $input){
        if((Get-Item -LiteralPath $input).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Input directory is a reparse point'}
        foreach($file in @(Get-ChildItem -LiteralPath $input -File -Filter '*.png')){$targets.Add($file)}
    }
    foreach($file in $targets){
        $path=[IO.Path]::GetFullPath($file.FullName)
        if(-not $path.StartsWith($absolute+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unexpected payload path'}
        $deleted.Add(@{path=$path;bytes=$file.Length;jobId=$connection.jobId})
        Remove-Item -LiteralPath $path
    }
    $record=@{verifiedFinalPsdRetained=$true;sourcePngRetained=$true;payloadsRemoved=$true;recoveryAvailable=$false;reason='Owned completed verification job; reopen final PSD. Request/result/connection metadata retained.'}
    [IO.File]::WriteAllText((Join-Path $absolute 'cleanup.json'),($record|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $jobs++
}
$bytes=($deleted|Measure-Object -Property bytes -Sum).Sum
$record=@{verified_jobs_cleaned=$jobs;deleted_file_count=$deleted.Count;reclaimed_bytes=$bytes;deleted=$deleted.ToArray();source_and_final_assets_preserved=$true}
[IO.File]::WriteAllText((Join-Path $WorkRoot 'exchange-cleanup.json'),($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{JobsCleaned=$jobs;FilesDeleted=$deleted.Count;ReclaimedMiB=[math]::Round($bytes/1MB,1);SourcesAndFinalPSD='preserved'}|ConvertTo-Json
