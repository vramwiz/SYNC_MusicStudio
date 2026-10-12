#requires -Version 7.0
param([string]$WorkRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$sender='D:\DelphiProg\AIArtToPSD\Tools\Send-ArtCommand.ps1'
$pixels=Get-Content -LiteralPath (Join-Path $WorkRoot 'pixel-verification.json') -Raw -Encoding UTF8|ConvertFrom-Json
$expected=@{'*基本'=($pixels|Where-Object name -eq 'basic');'*基本_スティック上げ_非打撃'=($pixels|Where-Object name -eq 'raised')}
$endpoints=@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'AIArtToPSD\pipes') -Filter '*.json' -File|ForEach-Object {
    $endpoint=Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    $proc=Get-Process -Id $endpoint.pid -ErrorAction SilentlyContinue
    if($proc -and $proc.ProcessName -eq 'AIArtToPSD'){$endpoint}
})
if($endpoints.Count -ne 1){throw 'Expected one live endpoint'}
$script:pipeName=$endpoints[0].pipeName
function Send-Art([string]$Command,[hashtable]$Arguments=@{}) {
    $json=ConvertTo-Json -InputObject $Arguments -Depth 32 -Compress
    $reply=(& $sender -PipeName $script:pipeName -Command $Command -ArgsJson $json -TimeoutMs 60000)|ConvertFrom-Json
    if(-not $reply.ok){throw $reply.error.message};return $reply.data
}
function Write-JsonNew([string]$Path,$Object) {
    if(Test-Path -LiteralPath $Path){throw ('Preserve existing record: '+$Path)}
    [IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 32),[Text.UTF8Encoding]::new($false))
}
function Read-Document {
    $doc=Send-Art 'document' @{offset=0;limit=24;includePixelHashes=$true}
    if($doc.hasMore){throw 'Inspect additional layers before editing'};return $doc
}
function Write-Result($Job,$Assets,$Operations) {
    $request=Get-Content -LiteralPath (Join-Path $Job.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $result=[ordered]@{schemaVersion=$request.schemaVersion;requestId=$request.requestId;jobId=$request.jobId;
        documentId=$request.documentId;ifRevision=$request.ifRevision;assets=@($Assets);operations=@($Operations)}
    Write-JsonNew (Join-Path $Job.directory 'result.json.tmp') $result
    Move-Item -LiteralPath (Join-Path $Job.directory 'result.json.tmp') -Destination (Join-Path $Job.directory 'result.json')
    $status=Send-Art 'status' @{jobId=$Job.jobId}
    if($status.job.stale){throw 'Document changed; re-export instead of importing stale result'}
    $imported=Send-Art 'import' @{jobId=$Job.jobId}
    if($imported.state -ne 'completed'){throw 'Import not confirmed'}
}
function Assert-Preserved($Doc,$Before,[bool]$AfterReload=$false) {
    if($Doc.width -ne $Before.width -or $Doc.height -ne $Before.height -or $Doc.layers.Count -ne $Before.layers.Count){throw 'Canvas/layer count mismatch'}
    $mapping=@{}
    for($i=0;$i -lt $Before.layers.Count;$i++){
        $old=$Before.layers[$i];$new=$Doc.layers[$i];$mapping[$old.layerId]=$new.layerId
        foreach($key in @('name','kind','opacity','hasMask')){if($old.$key -ne $new.$key){throw ('Layer attribute changed: '+$old.name)}}
        foreach($key in @('left','top','right','bottom')){if($old.bounds.$key -ne $new.bounds.$key){throw ('Bounds changed: '+$old.name)}}
        if(-not $AfterReload -and ($old.layerId -ne $new.layerId -or $old.parentId -ne $new.parentId)){throw 'Identity/hierarchy changed'}
        if($expected.ContainsKey($old.name)){
            if($new.pixelSha256 -ne $expected[$old.name].rgba_sha256){throw ('Corrected pose hash mismatch: '+$old.name)}
        }elseif($old.kind -eq 'image' -and $new.pixelSha256 -ne $old.pixelSha256){throw ('Non-target pixels changed: '+$old.name)}
        if($old.parentId -ne $script:poseParent -and $old.visible -ne $new.visible){throw 'Unrelated visibility changed'}
    }
    for($i=0;$i -lt $Before.layers.Count;$i++){
        $parent=$Before.layers[$i].parentId
        $want=if([string]::IsNullOrEmpty($parent)){''}else{$mapping[$parent]}
        if($Doc.layers[$i].parentId -ne $want){throw 'Hierarchy mismatch'}
    }
}
function Assert-Selected($Doc,[string]$Name) {
    $parent=($Doc.layers|Where-Object name -eq '演奏姿勢').layerId
    $visible=@($Doc.layers|Where-Object {$_.parentId -eq $parent -and $_.name.StartsWith('*') -and $_.visible})
    if($visible.Count -ne 1 -or $visible[0].name -ne $Name){throw 'Exclusive pose selection failed'}
}
$status=Send-Art 'status'
if(-not $status.canEdit -or $status.fileName -notlike '*ドラム*.psd'){throw 'Expected editable drum PSD'}
$before=Read-Document
foreach($name in $expected.Keys){
    $target=@($before.layers|Where-Object name -eq $name)
    if($target.Count -ne 1 -or $target[0].hasMask -or $target[0].pixelSha256 -ne $expected[$name].source_rgba_sha256){throw ('Source pose changed: '+$name)}
}
$basic=($before.layers|Where-Object name -eq '*基本')
$raised=($before.layers|Where-Object name -eq '*基本_スティック上げ_非打撃')
$script:poseParent=$basic.parentId
$original=$status.fileName;$originalHash=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant()
Write-JsonNew (Join-Path $WorkRoot 'before-apply-document.json') $before
$job=Send-Art 'export' @{prompt='Apply two reference-based matched-grip corrections to basic and raised poses, preserving all other current layers and edits.'}
Write-JsonNew (Join-Path $WorkRoot 'apply-job.json') $job
$request=Get-Content -LiteralPath (Join-Path $job.directory 'request.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($request.documentId -ne $before.documentId -or $request.ifRevision -ne $before.revision){throw 'Changed during export'}
$images=Join-Path $job.directory 'images'
if(-not(Test-Path -LiteralPath $images)){New-Item -ItemType Directory -Path $images|Out-Null}
$assets=@();$ops=@()
foreach($name in @('*基本','*基本_スティック上げ_非打撃')){
    $p=$expected[$name];$target=($before.layers|Where-Object name -eq $name)
    $file=$p.name+'-grip-fixed.png';$path=Join-Path $images $file
    if(Test-Path -LiteralPath $path){throw 'Preserve existing asset'}
    Copy-Item -LiteralPath (Join-Path $WorkRoot $file) -Destination $path
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $p.png_sha256){throw 'PNG hash mismatch'}
    $assets+=@{assetId=$p.name+'-grip-fixed';path='images/'+$file;sha256=$p.png_sha256;width=1536;height=1024;pixelFormat='RGBA8';colorSpace='sRGB'}
    $ops+=@{op='replace_layer';layerId=$target.layerId;assetId=$p.name+'-grip-fixed';bounds=$target.bounds}
}
$ops+=@{op='select_part';layerId=$basic.layerId}
Write-Result $job $assets $ops
$after=Read-Document;Assert-Preserved $after $before;Assert-Selected $after '*基本'
Write-JsonNew (Join-Path $WorkRoot 'after-import-document.json') $after
Write-Output 'Both matched-grip corrections imported; other six poses and head preserved.'
$basicJob=Send-Art 'export' @{prompt='Native basic downstroke grip preview and exclusive-switch verification.'}
Write-JsonNew (Join-Path $WorkRoot 'basic-preview-job.json') $basicJob
Copy-Item -LiteralPath (Join-Path $basicJob.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-basic-preview.png')
Write-Result $basicJob @() @(@{op='select_part';layerId=$raised.layerId})
$doc=Read-Document;Assert-Preserved $doc $before;Assert-Selected $doc $raised.name
$raisedJob=Send-Art 'export' @{prompt='Native raised reference-grip preview; restore basic selection afterward.'}
Write-JsonNew (Join-Path $WorkRoot 'raised-preview-job.json') $raisedJob
Copy-Item -LiteralPath (Join-Path $raisedJob.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-raised-preview.png')
Write-Result $raisedJob @() @(@{op='select_part';layerId=$basic.layerId})
$ready=Read-Document;Assert-Preserved $ready $before;Assert-Selected $ready '*基本'
$root='C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD';$name='東北きりたん_打撃_ドラム_持ち方修正'
$output=Join-Path $root ($name+'.psd');$suffix=2
while(Test-Path -LiteralPath $output){$output=Join-Path $root ($name+'_'+$suffix.ToString('00')+'.psd');$suffix++}
$saved=Send-Art 'save' @{documentId=$ready.documentId;ifRevision=$ready.revision;fileName=$output}
$reloaded=Read-Document;Assert-Preserved $reloaded $before $true;Assert-Selected $reloaded '*基本'
if($reloaded.fileName -ne $output){throw 'Saved file mismatch'}
Write-JsonNew (Join-Path $WorkRoot 'after-save-document.json') $reloaded
if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash){throw 'Original PSD changed'}
$inspection=Send-Art 'export' @{prompt='Final read-only verification of saved reference-based grip corrections.'}
Write-JsonNew (Join-Path $WorkRoot 'saved-preview-job.json') $inspection
Copy-Item -LiteralPath (Join-Path $inspection.directory 'preview.png') -Destination (Join-Path $WorkRoot 'app-saved-basic-preview.png')
$null=Send-Art 'cancel' @{jobId=$inspection.jobId}
$final=Send-Art 'status'
Write-JsonNew (Join-Path $WorkRoot 'application-verification.json') @{
    passed=$true;output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant();
    original_psd=$original;original_sha256=$originalHash;original_psd_unchanged=$true;
    corrected_poses=@('*基本','*基本_スティック上げ_非打撃');pose_count=8;layer_count=15;
    all_other_six_pose_and_head_pixels_unchanged=$true;existing_bounds_attributes_hierarchy_unchanged=$true;
    basic_and_raised_switched_exclusively=$true;saved_and_reloaded=$true;
    current_unsaved_edits_preserved=$true;modified_at_verification=$final.modified;user_visual_acceptance='pending'
}
Write-Output ('PASS: saved '+$output)
