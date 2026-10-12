#requires -Version 7.0
param([string]$WorkRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$sender='D:\DelphiProg\AIArtToPSD\Tools\Send-ArtCommand.ps1'
$pixel=Get-Content -LiteralPath (Join-Path $WorkRoot 'pixel-verification.json') -Raw -Encoding UTF8|ConvertFrom-Json
$endpoints=@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes') -Filter '*.json' -File|ForEach-Object {
    $endpoint=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    $proc=Get-Process -Id $endpoint.pid -ErrorAction SilentlyContinue
    if($proc -and $proc.ProcessName -eq 'AIArtToPSD'){$endpoint}
})
if($endpoints.Count -ne 1){throw 'Expected one live endpoint'}
$script:pipeName=$endpoints[0].pipeName
$script:poseName='*基本_スティック上げ_非打撃'
function Send-Art([string]$Command,[hashtable]$Arguments=@{}) {
    $json=ConvertTo-Json -InputObject $Arguments -Depth 32 -Compress
    $reply=(& $sender -PipeName $script:pipeName -Command $Command -ArgsJson $json -TimeoutMs 60000)|ConvertFrom-Json
    if(-not $reply.ok){throw $reply.error.message}
    return $reply.data
}
function Write-JsonNew([string]$Path,$Object) {
    if(Test-Path -LiteralPath $Path){throw ('Preserve existing record: '+$Path)}
    [IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}
function Read-Document {
    $doc=Send-Art 'document' @{offset=0;limit=24;includePixelHashes=$true}
    if($doc.hasMore){throw 'Inspect additional layers before editing'}
    return $doc
}
function Write-Result($Job,$Assets,$Operations) {
    $request=Get-Content -LiteralPath (Join-Path $Job.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;
        documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($Assets);operations=@($Operations)}
    Write-JsonNew (Join-Path $Job.directory 'result.json.tmp') $result
    Move-Item -LiteralPath (Join-Path $Job.directory 'result.json.tmp') -Destination (Join-Path $Job.directory 'result.json')
    $current=Send-Art 'status' @{jobId=$Job.jobId}
    if($current.job.stale){throw 'Document changed; do not import a stale result'}
    $imported=Send-Art 'import' @{jobId=$Job.jobId}
    if($imported.state -ne 'completed'){throw 'Import not confirmed'}
}
function Assert-Preserved($Doc,$Before,[bool]$AfterReload=$false) {
    if($Doc.width -ne $Before.width -or $Doc.height -ne $Before.height -or $Doc.layers.Count -ne ($Before.layers.Count+1)){throw 'Canvas or layer count mismatch'}
    $added=@($Doc.layers|Where-Object name -eq $script:poseName)
    if($added.Count -ne 1 -or $added[0].pixelSha256 -ne $pixel.rgba_sha256){throw 'New pose pixel mismatch'}
    $existing=@($Doc.layers|Where-Object name -ne $script:poseName)
    $mapping=@{}
    for($i=0;$i -lt $Before.layers.Count;$i++){
        $old=$Before.layers[$i];$new=$existing[$i]
        $mapping[$old.layerId]=$new.layerId
        foreach($key in @('name','kind','opacity','hasMask')){
            if($old.$key -ne $new.$key){throw ('Existing attribute changed: '+$old.name+'/'+$key)}
        }
        foreach($key in @('left','top','right','bottom')){
            if($old.bounds.$key -ne $new.bounds.$key){throw ('Existing bounds changed: '+$old.name)}
        }
        if($old.kind -eq 'image' -and $old.pixelSha256 -ne $new.pixelSha256){throw ('Existing pixels changed: '+$old.name)}
        if(-not $AfterReload -and ($old.layerId -ne $new.layerId -or $old.parentId -ne $new.parentId)){throw 'Existing identity changed'}
        if($old.parentId -ne $script:poseParent -and $old.visible -ne $new.visible){throw ('Unrelated visibility changed: '+$old.name)}
    }
    for($i=0;$i -lt $Before.layers.Count;$i++){
        $parent=$Before.layers[$i].parentId
        $expected=if([string]::IsNullOrEmpty($parent)){''}else{$mapping[$parent]}
        if($existing[$i].parentId -ne $expected){throw 'Existing hierarchy changed'}
    }
    if($added[0].parentId -ne $mapping[$script:poseParent]){throw 'Added pose parent mismatch'}
    foreach($key in @('left','top','right','bottom')){
        if($added[0].bounds.$key -ne $script:basicBounds.$key){throw 'Added bounds mismatch'}
    }
    if($added[0].opacity -ne 255 -or $added[0].hasMask -or $added[0].kind -ne 'image'){throw 'Added layer attributes mismatch'}
}
function Assert-Selected($Doc,[string]$Name) {
    $parent=($Doc.layers|Where-Object name -eq '演奏姿勢').layerId
    $visible=@($Doc.layers|Where-Object {$_.parentId -eq $parent -and $_.name.StartsWith('*') -and $_.visible})
    if($visible.Count -ne 1 -or $visible[0].name -ne $Name){throw 'Pose exclusive selection failed'}
}
$status=Send-Art 'status'
if(-not $status.canEdit -or $status.fileName -notlike '*ドラム*.psd'){throw 'Expected editable drum PSD'}
$before=Read-Document
$basic=@($before.layers|Where-Object name -eq '*基本')
if($basic.Count -ne 1 -or $basic[0].pixelSha256 -ne $pixel.source_rgba_sha256){throw 'Basic pose changed since generation; retain current edits'}
if(@($before.layers|Where-Object name -eq $script:poseName).Count -ne 0){throw 'Pose already exists'}
$script:poseParent=$basic[0].parentId
$script:basicBounds=$basic[0].bounds
$originalPath=$status.fileName
$originalHash=(Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-JsonNew (Join-Path $WorkRoot 'before-apply-document.json') $before
$job=Send-Art 'export' @{prompt='Add the prepared raised-stick non-contact basic variation as a new exclusive full-body pose; preserve all current layers.'}
Write-JsonNew (Join-Path $WorkRoot 'apply-job.json') $job
$request=Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($request.documentId -ne $before.documentId -or $request.ifRevision -ne $before.revision){throw 'Document changed before export'}
$images=Join-Path $job.directory 'images'
if(-not(Test-Path -LiteralPath $images)){New-Item -ItemType Directory -Path $images|Out-Null}
$imagePath=Join-Path $images 'basic-raised-stick.png'
if(Test-Path -LiteralPath $imagePath){throw 'Preserve existing image'}
Copy-Item -LiteralPath (Join-Path $WorkRoot '基本_スティック上げ_非打撃.png') -Destination $imagePath
if((Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pixel.png_sha256){throw 'PNG copy mismatch'}
$newId=[guid]::NewGuid().ToString('B').ToUpperInvariant()
$siblings=@($before.layers|Where-Object parentId -eq $script:poseParent)
$basicIndex=[Array]::FindIndex([object[]]$siblings,[Predicate[object]]{param($layer) $layer.layerId -eq $basic[0].layerId})
$insertBefore=if($basicIndex+1 -lt $siblings.Count){$siblings[$basicIndex+1].layerId}else{''}
$asset=@{assetId='basic-raised-stick';path='images/basic-raised-stick.png';sha256=$pixel.png_sha256;width=1536;height=1024;pixelFormat='RGBA8';colorSpace='sRGB'}
$ops=@(@{op='add_layer';layerId=$newId;name=$script:poseName;parentId=$script:poseParent;beforeLayerId=$insertBefore;visible=$false;opacity=255;assetId=$asset.assetId;bounds=$basic[0].bounds},@{op='select_part';layerId=$newId})
Write-Result $job @($asset) $ops
$after=Read-Document
Assert-Preserved $after $before
Assert-Selected $after $script:poseName
Write-JsonNew (Join-Path $WorkRoot 'after-import-document.json') $after
Write-Output 'Added raised-stick pose; all existing layers preserved.'
# Verify both states in the real app before saving the final selected state.
$raised=Send-Art 'export' @{prompt='Read-only native preview and switch verification of raised-stick pose.'}
Write-JsonNew (Join-Path $WorkRoot 'raised-preview-job.json') $raised
Copy-Item -LiteralPath (Join-Path $raised.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-raised-preview.png')
Write-Result $raised @() @(@{op='select_part';layerId=$basic[0].layerId})
$basicDoc=Read-Document
Assert-Preserved $basicDoc $before
Assert-Selected $basicDoc '*基本'
$basicPreview=Send-Art 'export' @{prompt='Read-only native preview of accepted basic pose; restore raised-stick selection afterward.'}
Write-JsonNew (Join-Path $WorkRoot 'basic-preview-job.json') $basicPreview
Copy-Item -LiteralPath (Join-Path $basicPreview.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-basic-preview.png')
Write-Result $basicPreview @() @(@{op='select_part';layerId=$newId})
$ready=Read-Document
Assert-Preserved $ready $before
Assert-Selected $ready $script:poseName
Write-Output 'Basic and raised poses switched exclusively; original pose pixels unchanged.'
$root='C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD'
$name='東北きりたん_打撃_ドラム_基本スティック上げ'
$output=Join-Path $root ($name+'.psd')
$suffix=2
while(Test-Path -LiteralPath $output){$output=Join-Path $root ($name+'_'+$suffix.ToString('00')+'.psd');$suffix++}
$saved=Send-Art 'save' @{documentId=$ready.documentId;ifRevision=$ready.revision;fileName=$output}
$reloaded=Read-Document
Assert-Preserved $reloaded $before $true
Assert-Selected $reloaded $script:poseName
if($reloaded.fileName -ne $output){throw 'Saved name mismatch'}
Write-JsonNew (Join-Path $WorkRoot 'after-save-document.json') $reloaded
if((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original PSD changed'}
$inspection=Send-Art 'export' @{prompt='Final read-only verification of saved raised-stick pose; no additional edit.'}
Write-JsonNew (Join-Path $WorkRoot 'saved-preview-job.json') $inspection
Copy-Item -LiteralPath (Join-Path $inspection.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-saved-preview.png')
$null=Send-Art 'cancel' @{jobId=$inspection.jobId}
$final=Send-Art 'status'
if($final.modified){throw 'Unexpected edits after save; preserve user state and inspect'}
Write-JsonNew (Join-Path $WorkRoot 'application-verification.json') @{
    passed=$true;output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();
    original_psd=$originalPath;original_sha256=$originalHash;original_psd_unchanged=$true;
    added_pose=$script:poseName;pose_count=8;layer_count=15;new_pose_rgba_sha256=$pixel.rgba_sha256;
    all_existing_layer_pixels_bounds_attributes_hierarchy_unchanged=$true;
    basic_and_raised_switched_exclusively=$true;raised_selected=$true;saved_and_reloaded=$true;
    current_unsaved_edits_preserved=$true;modified=$final.modified;user_visual_acceptance='pending'
}
Write-Output ('PASS: saved '+$output)
