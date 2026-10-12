#requires -Version 7.0
param([string]$WorkRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$sender='D:\DelphiProg\AIArtToPSD\Tools\Send-ArtCommand.ps1'
$pixel=Get-Content -LiteralPath (Join-Path $WorkRoot 'pixel-verification.json') -Raw -Encoding UTF8|ConvertFrom-Json
$endpoints=@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes') -Filter '*.json' -File|ForEach-Object {
    $e=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    $p=Get-Process -Id $e.pid -ErrorAction SilentlyContinue
    if($p -and $p.ProcessName -eq 'AIArtToPSD'){$e}
})
if($endpoints.Count -ne 1){throw 'Expected one live AIArtToPSD endpoint'}
$script:pipeName=$endpoints[0].pipeName
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
    if($doc.hasMore){throw 'Unexpected additional layers; inspect before editing'}
    return $doc
}
function Assert-Preserved($Document,$Before,[string]$BasicId,[bool]$AfterReload=$false) {
    if($Document.width -ne $Before.width -or $Document.height -ne $Before.height -or $Document.layers.Count -ne $Before.layers.Count){throw 'Canvas or layer count changed'}
    for($i=0;$i -lt $Before.layers.Count;$i++){
        $old=$Before.layers[$i];$new=$Document.layers[$i]
        foreach($key in @('name','kind','opacity','hasMask')){
            if($old.$key -ne $new.$key){throw ('Layer attribute changed: '+$old.name+'/'+$key)}
        }
        foreach($key in @('left','top','right','bottom')){
            if($old.bounds.$key -ne $new.bounds.$key){throw ('Layer bounds changed: '+$old.name)}
        }
        if(-not $AfterReload -and ($new.layerId -ne $old.layerId -or $new.parentId -ne $old.parentId)){throw 'Layer hierarchy/identity changed'}
        if($old.layerId -eq $BasicId){
            if($new.pixelSha256 -ne $pixel.rgba_sha256 -or -not $new.visible){throw 'Corrected basic pose did not match'}
        }else{
            if($old.kind -eq 'image' -and $new.pixelSha256 -ne $old.pixelSha256){throw ('Non-target pixels changed: '+$old.name)}
            if($old.parentId -ne $script:poseParent -and $new.visible -ne $old.visible){throw ('Unrelated visibility changed: '+$old.name)}
        }
    }
    $poseParentId=($Document.layers|Where-Object name -eq '演奏姿勢').layerId
    $visible=@($Document.layers|Where-Object {$_.parentId -eq $poseParentId -and $_.visible})
    if($visible.Count -ne 1 -or $visible[0].name -ne '*基本'){throw 'Basic pose exclusivity failed'}
}
$status=Send-Art 'status'
if(-not $status.canEdit -or $status.fileName -notlike '*ドラム*.psd'){throw 'Expected editable drum PSD'}
$before=Read-Document
$basic=@($before.layers|Where-Object {$_.name -eq '*基本' -and $_.kind -eq 'image'})
if($basic.Count -ne 1 -or $basic[0].pixelSha256 -ne $pixel.source_rgba_sha256){throw 'Basic pose changed since generation; preserve current edits'}
$script:poseParent=$basic[0].parentId
$originalPath=$status.fileName
$originalHash=(Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-JsonNew (Join-Path $WorkRoot 'before-apply-document.json') $before
$prompt='DrumGripFix_20261009: apply prepared local grip correction to basic pose; preserve latest user edits.'
$job=Send-Art 'export' @{prompt=$prompt}
Write-JsonNew (Join-Path $WorkRoot 'apply-job.json') $job
$request=Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($request.documentId -ne $before.documentId -or $request.ifRevision -ne $before.revision){throw 'Document changed before export; prepare a fresh comparison'}
$target=@($request.layers|Where-Object layerId -eq $basic[0].layerId)
if($target.Count -ne 1 -or $target[0].hasMask){throw 'Target layer mismatch or unsupported mask'}
$images=Join-Path $job.directory 'images'
if(-not(Test-Path -LiteralPath $images)){New-Item -ItemType Directory -Path $images|Out-Null}
$assetPath=Join-Path $images 'basic-grip-fixed.png'
if(Test-Path -LiteralPath $assetPath){throw 'Preserve existing image'}
Copy-Item -LiteralPath (Join-Path $WorkRoot '基本_スティック握り修正.png') -Destination $assetPath
if((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pixel.png_sha256){throw 'Asset copy hash mismatch'}
$asset=@{assetId='basic-grip-fixed';path='images/basic-grip-fixed.png';sha256=$pixel.png_sha256;width=1536;height=1024;pixelFormat='RGBA8';colorSpace='sRGB'}
$result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;documentId=$request.documentId;ifRevision=$request.ifRevision;
    assets=@($asset);operations=@(@{op='replace_layer';layerId=$target[0].layerId;assetId=$asset.assetId;bounds=$target[0].bounds},@{op='select_part';layerId=$target[0].layerId})}
Write-JsonNew (Join-Path $job.directory 'result.json.tmp') $result
Move-Item -LiteralPath (Join-Path $job.directory 'result.json.tmp') -Destination (Join-Path $job.directory 'result.json')
$current=Send-Art 'status' @{jobId=$job.jobId}
if($current.job.stale){throw 'User changed document during preparation; do not import stale result'}
$imported=Send-Art 'import' @{jobId=$job.jobId}
if($imported.state -ne 'completed'){throw 'Import not confirmed'}
$after=Read-Document
Assert-Preserved $after $before $basic[0].layerId
Write-JsonNew (Join-Path $WorkRoot 'after-import-document.json') $after
$afterStatus=Send-Art 'status'
if(-not $afterStatus.canUndo -or -not $afterStatus.modified){throw 'Expected reversible imported edit'}
$outputRoot='C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD'
$name='東北きりたん_打撃_ドラム_基本握り修正'
$output=Join-Path $outputRoot ($name+'.psd')
$suffix=2
while(Test-Path -LiteralPath $output){$output=Join-Path $outputRoot ($name+'_'+$suffix.ToString('00')+'.psd');$suffix++}
$saved=Send-Art 'save' @{documentId=$after.documentId;ifRevision=$after.revision;fileName=$output}
$reloaded=Read-Document
Assert-Preserved $reloaded $before $basic[0].layerId $true
if($reloaded.fileName -ne $output){throw 'Saved file name mismatch'}
Write-JsonNew (Join-Path $WorkRoot 'after-save-document.json') $reloaded
if((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original PSD changed'}
$inspection=Send-Art 'export' @{prompt='Read-only visual verification of saved basic grip correction; no additional edit requested.'}
Copy-Item -LiteralPath (Join-Path $inspection.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-corrected-preview.png')
Write-JsonNew (Join-Path $WorkRoot 'preview-job.json') $inspection
$null=Send-Art 'cancel' @{jobId=$inspection.jobId}
$finalStatus=Send-Art 'status'
if($finalStatus.modified){throw 'Saved document unexpectedly modified'}
Write-JsonNew (Join-Path $WorkRoot 'application-verification.json') @{
    passed=$true;output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();
    original_psd=$originalPath;original_sha256=$originalHash;original_psd_unchanged=$true;
    corrected_basic_rgba_sha256=$pixel.rgba_sha256;all_other_layer_pixels_bounds_attributes_unchanged=$true;
    basic_selected_exclusively=$true;saved_and_reloaded=$true;modified=$finalStatus.modified;
    edit_job=$job.jobId;inspection_job=$inspection.jobId;inspection_cancelled_without_reverting_edit=$true;
    source_unsaved_edits_preserved_in_new_psd=$true;user_visual_acceptance='pending'
}
Write-Output ('PASS: basic grip replaced; all other layer pixels preserved; saved '+$output)
