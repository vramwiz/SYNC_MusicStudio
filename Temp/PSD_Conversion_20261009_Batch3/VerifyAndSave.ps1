#requires -Version 7.0
param([string]$WorkRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$sender='D:\DelphiProg\AIArtToPSD\Tools\Send-ArtCommand.ps1'
$executable='D:\DelphiProg\AIArtToPSD\Win64\Release\AIArtToPSD.exe'
$batch=Get-Content -LiteralPath (Join-Path $WorkRoot 'batch.json') -Raw -Encoding utf8 | ConvertFrom-Json
$script:pipeName=$null

function Write-JsonNew([string]$Path,$Object) {
    if(Test-Path -LiteralPath $Path){throw ('Existing record: '+$Path)}
    [IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}
function Send-Art([string]$Command,[hashtable]$Arguments=@{}) {
    $json=ConvertTo-Json -InputObject $Arguments -Depth 32 -Compress
    $raw=& $sender -PipeName $script:pipeName -Command $Command -ArgsJson $json -TimeoutMs 60000
    $reply=$raw|ConvertFrom-Json
    if(-not $reply.ok){throw $reply.error.message}
    return $reply.data
}
function Get-Document {
    $page=Send-Art 'document' @{offset=0;limit=24;includePixelHashes=$true}
    $layers=[Collections.Generic.List[object]]::new()
    foreach($layer in $page.layers){$layers.Add($layer)}
    while($page.hasMore){
        $next=Send-Art 'document' @{offset=$layers.Count;limit=24;includePixelHashes=$true}
        if($next.documentId -ne $page.documentId -or $next.revision -ne $page.revision){throw 'Document changed while paging'}
        foreach($layer in $next.layers){$layers.Add($layer)}
        $page=$next
    }
    $page.layers=$layers.ToArray()
    return $page
}
function Select-Pose([string]$Id,[string]$Label) {
    $job=Send-Art 'export' @{prompt=('Verify integrated instrument pose selection: '+$Label)}
    $request=Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw -Encoding utf8|ConvertFrom-Json
    $result=[ordered]@{
        schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId
        documentId=$request.documentId;ifRevision=$request.ifRevision
        assets=@();operations=@(@{op='select_part';layerId=$Id})
    }
    Write-JsonNew (Join-Path $job.directory 'result.json') $result
    $import=Send-Art 'import' @{jobId=$job.jobId}
    if($import.state -ne 'completed'){throw 'Selection import did not complete'}
    return $job
}
function Assert-Layers($Document,$Native) {
    if($Document.layers.Count -ne $Native.layers.Count){throw 'Unexpected layer count'}
    $paths=@{}
    for($i=0;$i -lt $Document.layers.Count;$i++){
        $layer=$Document.layers[$i];$expected=$Native.layers[$i]
        $path=$layer.name
        if($layer.parentId){$path=$paths[$layer.parentId]+'/'+$path}
        $paths[$layer.layerId]=$path
        if($path -ne $expected.path){throw ('Hierarchy differs: '+$path)}
        if($layer.kind -eq 'image' -and $layer.pixelSha256 -ne $expected.rgba_sha256){throw ('Pixels changed: '+$path)}
        if($layer.kind -eq 'image' -and ($layer.bounds.left -ne 0 -or $layer.bounds.top -ne 0 -or $layer.bounds.right -ne $Document.width -or $layer.bounds.bottom -ne $Document.height)){
            throw ('Image origin/canvas changed: '+$path)
        }
    }
}

foreach($item in $batch){
    $stage=$item.staging
    $native=Get-Content -LiteralPath (Join-Path $stage 'native-verification.json') -Raw -Encoding utf8|ConvertFrom-Json
    if(-not $native.passed){throw 'Native verification did not pass'}
    if(Test-Path -LiteralPath $item.destination){throw ('Preserve existing PSD: '+$item.destination)}
    $history=Join-Path $stage 'app-history'
    $priorHistory=$env:AIARTTOPSD_HISTORY_DIR
    try{
        $env:AIARTTOPSD_HISTORY_DIR=$history
        $application=Start-Process -FilePath $executable -ArgumentList ('"'+(Join-Path $stage 'assembled.psd')+'"') -WorkingDirectory (Split-Path $executable -Parent) -WindowStyle Hidden -PassThru
    }finally{$env:AIARTTOPSD_HISTORY_DIR=$priorHistory}
    $script:pipeName=$null
    for($attempt=0;$attempt -lt 100;$attempt++){
        foreach($endpointFile in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes') -Filter '*.json' -ErrorAction SilentlyContinue)){
            $endpoint=Get-Content -LiteralPath $endpointFile.FullName -Raw -Encoding utf8|ConvertFrom-Json
            if($endpoint.pid -eq $application.Id){$script:pipeName=$endpoint.pipeName;break}
        }
        if($script:pipeName){break}
        $application.Refresh()
        if($application.HasExited){throw 'Owned application exited before endpoint creation'}
        Start-Sleep -Milliseconds 100
    }
    if(-not $script:pipeName){throw 'Missing fresh endpoint'}
    $status=Send-Art 'status'
    if(-not $status.canEdit -or $status.modified){throw 'PSD did not open as unchanged editable document'}
    $before=Get-Document
    Write-JsonNew (Join-Path $stage 'app-document-before.json') $before
    Assert-Layers $before $native
    $poseGroup=@($before.layers|Where-Object name -eq '演奏姿勢')
    if($poseGroup.Count -ne 1){throw 'Pose parent ambiguous'}
    $poseLayers=@($before.layers|Where-Object parentId -eq $poseGroup[0].layerId)
    if($poseLayers.Count -ne $item.pose_count){throw 'Pose count mismatch'}
    $checks=[Collections.Generic.List[object]]::new()
    # Exercise every supplied pose through the application, including the
    # unchanged known-problem candidates. Native previews cover every state.
    for($index=1;$index -lt $poseLayers.Count;$index++){
        $pose=$poseLayers[$index]
        $job=Select-Pose $pose.layerId $pose.name
        $selected=Get-Document
        Assert-Layers $selected $native
        $visible=@($selected.layers|Where-Object {$_.parentId -eq $poseGroup[0].layerId -and $_.visible})
        if($visible.Count -ne 1 -or $visible[0].layerId -ne $pose.layerId){throw 'Application exclusive pose selection failed'}
        $checks.Add(@{name=$pose.name;jobId=$job.jobId;visible_pose_count=$visible.Count;all_layer_pixels_unchanged=$true})
    }
    $null=Select-Pose $poseLayers[0].layerId $poseLayers[0].name
    $current=Get-Document
    Assert-Layers $current $native
    $saved=Send-Art 'save' @{documentId=$current.documentId;ifRevision=$current.revision;fileName=$item.destination}
    $after=Get-Document
    Assert-Layers $after $native
    if($after.fileName -ne $item.destination){throw 'Saved file name mismatch'}
    for($i=0;$i -lt $after.layers.Count;$i++){
        if($after.layers[$i].visible -ne $native.layers[$i].visible){throw 'Saved default visibility mismatch'}
    }
    $status=Send-Art 'status'
    if($status.modified -or -not $status.canEdit){throw 'Saved document was not reloaded cleanly'}
    Write-JsonNew (Join-Path $stage 'app-document-after.json') $after
    $finalJob=Send-Art 'export' @{prompt='Verification only: saved integrated instrument PSD at default pose.'}
    Copy-Item -LiteralPath (Join-Path $finalJob.directory 'preview.png') -Destination (Join-Path $stage 'app-default-preview.png')
    $null=Send-Art 'cancel' @{jobId=$finalJob.jobId}
    Write-JsonNew (Join-Path $stage 'app-verification.json') @{
        passed=$true;application=$executable;pid=$application.Id;destination=$item.destination
        selected_pose_count=$checks.Count+1;checks=$checks.ToArray()
        saved_and_reloaded=$true;all_pixels_bounds_hierarchy_preserved=$true;default_restored=$true
        file_sha256=(Get-FileHash -LiteralPath $item.destination -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    # Close only our unchanged instance. No user's process or unsaved document
    # is touched. CloseMainWindow is sufficient after save/reload.
    [void]$application.CloseMainWindow()
    Write-Output ('PASS '+$item.instrument+': '+$item.pose_count+' application selections; saved '+$item.destination)
}
