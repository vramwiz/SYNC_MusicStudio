unit SYNC_MusicStudio_TransportThumbnailChecks;
// 統合画面のtransportとPSD一覧/スロット画像。隔離PSDと無音時計だけを使用する。
interface
procedure RunTransportThumbnailChecks(const Root: string);
procedure RunTransportRealPreview(const Root,AssetID: string);
implementation
uses System.SysUtils, System.IOUtils, System.Classes, System.Types, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_LibraryData;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('transport/thumbnail: '+Text); end;
procedure Pump(Milliseconds: Cardinal);
var Start: UInt64;
begin Start := GetTickCount64; repeat Application.ProcessMessages; Sleep(2); until GetTickCount64-Start>=Milliseconds; end;
procedure Capture(Form: TForm; const Path: string);
var Bitmap: TBitmap; PNG: TPngImage; DC: HDC;
begin
  Form.Show; ShowWindow(Form.Handle,SW_SHOWNOACTIVATE); Form.Repaint; Pump(100);
  Bitmap := TBitmap.Create; Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); PNG := TPngImage.Create;
  DC := GetDC(Form.Handle);
  try BitBlt(Bitmap.Canvas.Handle,0,0,Bitmap.Width,Bitmap.Height,DC,0,0,SRCCOPY);
    PNG.Assign(Bitmap); PNG.SaveToFile(Path);
  finally ReleaseDC(Form.Handle,DC); PNG.Free; Bitmap.Free; end;
end;
function Version(const Asset: TMusicStudioPsdAsset): string;
begin Result := Asset.Revision+':'+THashSHA2.GetHashString(Asset.ConfigJSON); end;
function ImageHash(Image: TBitmap): string;
var Bytes: TBytes; Y: Integer; Stream: TBytesStream;
begin
  Check(Image<>nil,'missing cached image'); SetLength(Bytes,Image.Width*Image.Height*4);
  for Y := 0 to Image.Height-1 do Move(Image.ScanLine[Y]^,Bytes[Y*Image.Width*4],Image.Width*4);
  Stream := TBytesStream.Create(Bytes);
  try Result := THashSHA2.GetHashString(Stream); finally Stream.Free; end;
end;
procedure RunTransportThumbnailChecks(const Root: string);
var F: TFormMusicStudioSettings; Asset,Current: TMusicStudioPsdAsset; G: TGUID;
  Dir,Error,Text,Before,OldVersion,OldHash,OldConfig,MissingPath,MetadataBefore: string; Data: TBytes;
  I,Index,Decode,Raster,Hits,Slot,SecondSlot,Buttons,CachedImages,EmptyTrack: Integer; Key: Word; Dup,AcceptDrop: Boolean;
  Position: Double; Deadline: UInt64; Source: TMusicStudioVisualSource; R: TRect;
  Config: TJSONObject; Document: TMusicStudioLayerDocument;
  LibraryItems: TArray<TMusicStudioLibraryItem>; Item: TMusicStudioLibraryItem;
  procedure SelectAsset;
  var J: Integer;
  begin
    Index := -1;
    for J := 0 to F.PatternList.Count-1 do if F.PatternList.Items[J]=Asset.Name then Index := J;
    Check(Index>=0,'asset row missing'); F.PatternList.TopIndex := Index; F.PatternList.ItemIndex := Index;
    Pump(90);
  end;
  procedure CheckDrag(Expected: Boolean);
  begin
    AcceptDrop := not Expected;
    Check(Assigned(F.TimelineBox.OnDragOver),'drag-over handler missing');
    F.TimelineBox.OnDragOver(F.TimelineBox,F.PatternList,F.TimelineBox.HeaderWidth+10,
      F.TimelineBox.SlotRowTop(0,0)+20,dsDragMove,AcceptDrop);
    Check(AcceptDrop=Expected,'automatic PSD availability did not refresh drag-over');
  end;
  procedure AwaitAsset;
  begin
    Deadline := GetTickCount64+10000;
    repeat
      F.TimelineBox.PollWaveforms; Application.ProcessMessages;
      Source := F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,Version(Asset));
      if (Source<>nil) and (Source.Status=vsReady) and (Source.Image<>nil) and
        (F.TimelineBox.VisualCache.ActiveJobs=0) then Exit;
      Check(GetTickCount64<Deadline,'cache timeout'); Sleep(2);
    until False;
  end;
  procedure CheckOversubscribedCache;
  var Cache: TMusicStudioVisualCache; Requests: TArray<TMusicStudioVisualRequest>;
    Items: TArray<TMusicStudioLibraryItem>; J,N,Ready,WarmDecode,WarmRaster,WarmSerial: Integer;
    Limit: UInt64; S: TMusicStudioVisualSource; Image: TBitmap; HiddenHash: string;
    procedure BindRequests;
    begin
      Cache.SetSources(Copy(Requests,0,4));
      Cache.SetLibrarySources(Copy(Requests,4,Length(Requests)-4));
    end;
    procedure AssertBounds;
    var Count,ReservedSlots,K: Integer; CurrentSource: TMusicStudioVisualSource;
    begin
      Count := 0; ReservedSlots := 0;
      for K := 0 to High(Requests) do begin
        CurrentSource := Cache.Find(vkPsd,Requests[K].Path,Requests[K].PsdVersion);
        if (CurrentSource<>nil) and (CurrentSource.Image<>nil) then Inc(Count);
        if (CurrentSource<>nil) and ((CurrentSource.Image<>nil) or (CurrentSource.PsdJob<>nil)) then Inc(ReservedSlots);
      end;
      Check((Count<=64) and (ReservedSlots<=64) and (Cache.ActiveJobs<=2) and (Cache.BitmapCount<=128),
        Format('70 simultaneous sources exceeded image/job reservation bounds images=%d slots=%d jobs=%d',[Count,ReservedSlots,Cache.ActiveJobs]));
    end;
    procedure WaitSettled;
    begin
      Limit := GetTickCount64+10000;
      repeat
        Cache.Poll; AssertBounds; Pump(2);
        Check(GetTickCount64<Limit,'oversubscribed cache did not settle');
      until Cache.ActiveJobs=0;
    end;
    procedure AssertImages;
    var K: Integer; Expected: string;
    begin
      for K := 0 to High(Requests) do begin
        S := Cache.Find(vkPsd,Requests[K].Path,Requests[K].PsdVersion);
        if (S<>nil) and (S.Image<>nil) then begin
          if K mod 2=0 then Expected := OldHash else Expected := HiddenHash;
          Check(ImageHash(S.Image)=Expected,'oversubscribed cache mixed image/config identities');
        end;
      end;
    end;
  begin
    Items := MusicStudioLibraryItems(F.Document,F.SharedLibrary,'psd','');
    Cache := TMusicStudioVisualCache.Create;
    try
      SetLength(Requests,70);
      for J := 0 to High(Requests) do begin
        Requests[J].Kind := vkPsd; Requests[J].Path := Items[J].Pattern.FilePath; Requests[J].Visible := True;
        Requests[J].PsdVersion := 'capacity:'+IntToStr(J mod 2);
        if J mod 2=0 then Requests[J].ConfigJSON := OldConfig else Requests[J].ConfigJSON := Config.ToJSON;
      end;
      BindRequests; WaitSettled;
      S := Cache.Find(vkPsd,Requests[1].Path,Requests[1].PsdVersion);
      HiddenHash := ImageHash(S.Image); Check(HiddenHash<>OldHash,'capacity fixture has no distinct image identities');
      Ready := 0;
      for J := 0 to High(Requests) do begin
        S := Cache.Find(vkPsd,Requests[J].Path,Requests[J].PsdVersion);
        Check(S<>nil,'oversubscribed source missing');
        if S.Image<>nil then Inc(Ready);
        Check((S.Image<>nil)=(J<64),'admission rotated away from stable primary/library order');
        Image := Cache.Thumbnail(S,46,46,96,$00242424);
        Check((Image<>nil)=(J<64),'deferred source borrowed another thumbnail');
      end;
      Check((Ready=64) and (Cache.PsdDecodeCount=64),'overflow sources decoded without an image reservation');
      AssertImages; WarmDecode := Cache.PsdDecodeCount; WarmRaster := Cache.RasterCount; WarmSerial := Cache.Serial;
      for N := 1 to 100 do begin
        Cache.Poll;
        for J := 0 to High(Requests) do Cache.Thumbnail(Cache.Find(vkPsd,Requests[J].Path,Requests[J].PsdVersion),46,46,96,$00242424);
        AssertBounds;
      end;
      for N := 1 to 10 do BindRequests;
      Pump(150); Cache.Poll;
      Check((Cache.PsdDecodeCount=WarmDecode) and (Cache.RasterCount=WarmRaster) and (Cache.Serial=WarmSerial),
        'overflow caused repaint/poll/rebind decode, raster, or invalidation thrash');
      for J := 0 to 9 do Requests[J].Visible := False;
      BindRequests; WaitSettled;
      for J := 64 to 69 do Check(Cache.Find(vkPsd,Requests[J].Path,Requests[J].PsdVersion).Image<>nil,'deferred visible source did not receive released reservation');
      AssertImages;
      // Visibility changes during newly started jobs must preserve generations and the hard budget.
      for J := 0 to 9 do Requests[J].Visible := True;
      BindRequests;
      for J := 0 to 9 do Requests[J].Visible := False;
      BindRequests;
      for J := 0 to 9 do Requests[J].Visible := True;
      BindRequests; WaitSettled; AssertImages;
      WarmDecode := Cache.PsdDecodeCount; WarmSerial := Cache.Serial;
      for N := 1 to 100 do begin Cache.Poll; AssertBounds; end;
      Check((Cache.PsdDecodeCount=WarmDecode) and (Cache.Serial=WarmSerial),'reservation switch entered regeneration loop');
      Writeln('PSD_THUMBNAIL_VISIBLE70_HARD_IMAGE64_JOB_RESERVATION_PRIMARY_PRIORITY_PLACEHOLDER_PIXEL_IDENTITY_STABLE100_REPAINT_REBIND_RELEASE_RACE_OK');
    finally Cache.Free; end;
  end;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'transport-thumbnail-'+GUIDToString(G)); ForceDirectories(Dir);
  F := TFormMusicStudioSettings.Create(nil); Document := TMusicStudioLayerDocument.Create; Config := nil;
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Dir,'isolated-library'); F.LoadDocument('');
    Data := TFile.ReadAllBytes(TPath.Combine(Root,'psd-layers-raw.psd'));
    // Different merged-image bytes give distinct fixture identities; retained layer channels stay valid.
    for I := 0 to 119 do begin
      Data[High(Data)] := Byte(I); TFile.WriteAllBytes(TPath.Combine(Dir,'fixture.psd'),Data);
      Check(F.SharedLibrary.TryImport(TPath.Combine(Dir,'fixture.psd'),'PSD '+Format('%.3d',[I]),'#CC8CE0',Current,Dup,Error),Error);
      if I=0 then Asset := Current;
    end;
    F.Document.AddTrack('psd'); F.Document.AssignPsd(0,Asset.ID);
    SecondSlot := F.Document.AddSlot(0,'psd'); EmptyTrack := F.Document.AddTrack('psd');
    Check(F.Document.TrySave(Text,Error),Error);
    MetadataBefore := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'));
    MissingPath := Asset.FilePath+'.temporarily-missing'; TFile.Move(Asset.FilePath,MissingPath);
    F.LoadDocument(Text); Before := F.JSONMemo.Text;
    Slot := 0; F.TimelineBox.SelectSlot(0,Slot); F.Show; SelectAsset;
    Source := F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,Version(Asset));
    Check((Source<>nil) and (Source.Status=vsMissing) and (Source.Image=nil),'initially missing PSD was not a placeholder');
    CheckDrag(False); Capture(F,TPath.Combine(Dir,'initially-missing.png'));
    TFile.Move(MissingPath,Asset.FilePath); Pump(1100); SelectAsset; AwaitAsset; CheckDrag(True);
    Check(F.JSONMemo.Text=Before,'automatic initial recovery changed project JSON');
    TFile.Move(Asset.FilePath,MissingPath); Pump(1100); SelectAsset; CheckDrag(False);
    Source := F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,Version(Asset));
    Check((Source.Status=vsMissing) and (Source.Image=nil),'repeated missing source retained a thumbnail');
    TFile.Move(MissingPath,Asset.FilePath); Pump(1100); SelectAsset; AwaitAsset; CheckDrag(True);
    Check(F.JSONMemo.Text=Before,'automatic repeated recovery changed project JSON');
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'))=MetadataBefore,'source-only recovery rewrote asset metadata');
    Check(F.DropSelectedLibraryAt(EmptyTrack,0,0,Error),Error);
    Check(F.Document.TrackAt(EmptyTrack).PsdAssetID=Asset.ID,'restored PSD drop did not assign the target');
    F.TimelineBox.SelectSlot(0,Slot); SelectAsset; AwaitAsset; Before := F.JSONMemo.Text;
    Writeln('PSD_LIBRARY_INITIAL_MISSING_SOURCE_ONLY_RESTORE_REMISSING_RESTORE_AUTOMATIC_THUMBNAIL_DRAGOVER_DROP_METADATA_JSON_UNCHANGED_OK');
    Check(F.PatternList.Count=120,'large library row count');
    R := F.TimelineBox.SlotThumbnailRect(0,Slot);
    Check((R.Top=F.TimelineBox.SlotRowTop(0,Slot)+7) and (R.Bottom<=F.TimelineBox.SlotRowTop(0,Slot)+F.TimelineBox.RowHeight),'image escaped PSD slot');
    Check(IsRectEmpty(F.TimelineBox.SlotThumbnailRect(0,-1)),'parent heading retained image');
    Check(not IsRectEmpty(F.TimelineBox.SlotThumbnailRect(0,SecondSlot)),'second PSD slot missing image geometry');
    F.TimelineBox.ToggleTrack(0); Check(IsRectEmpty(F.TimelineBox.TrackThumbnailRect(0)),'collapsed image retained parent position');
    F.TimelineBox.ToggleTrack(0);
    Capture(F,TPath.Combine(Dir,'integrated-96dpi.png'));
    AwaitAsset; F.PatternList.Repaint; F.TimelineBox.Repaint;
    Decode := F.TimelineBox.VisualCache.PsdDecodeCount; Raster := F.TimelineBox.VisualCache.RasterCount; Hits := F.LibraryThumbnails.CacheHits;
    for I := 1 to 100 do begin F.PatternList.Repaint; F.TimelineBox.Repaint; end;
    Check((Decode=F.TimelineBox.VisualCache.PsdDecodeCount) and (Raster=F.TimelineBox.VisualCache.RasterCount) and
      (F.LibraryThumbnails.CacheHits>Hits),Format('paint100 cache counts decode %d/%d raster %d/%d hits %d/%d',
        [Decode,F.TimelineBox.VisualCache.PsdDecodeCount,Raster,F.TimelineBox.VisualCache.RasterCount,Hits,F.LibraryThumbnails.CacheHits]));
    Check(Decode<30,'offscreen library eagerly decoded');
    OldVersion := Version(Asset); OldHash := ImageHash(Source.Image); OldConfig := Asset.ConfigJSON;
    Check(Document.LoadFile(Asset.FilePath),Document.LastError); Config := ParseMusicStudioPsdConfig('');
    for I := 0 to High(Document.Layers) do MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),Document.Layers[I].Key,False);
    Asset.ConfigJSON := Config.ToJSON; Check(F.SharedLibrary.TrySave(Asset,Error),Error);
    // The metadata timer must refresh the row without a manual rebind or a work JSON mutation.
    Pump(1100); SelectAsset; AwaitAsset;
    Check(F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,OldVersion)=nil,'old configuration source survived');
    Check(ImageHash(Source.Image)<>OldHash,'shared revision did not refresh thumbnail');
    Asset.ConfigJSON := OldConfig; Check(F.SharedLibrary.TrySave(Asset,Error),Error); F.SharedLibraryChanged; SelectAsset; AwaitAsset;
    Asset.ConfigJSON := Config.ToJSON; Check(F.SharedLibrary.TrySave(Asset,Error),Error); F.SharedLibraryChanged; OldVersion := Version(Asset);
    Asset.ConfigJSON := OldConfig; Check(F.SharedLibrary.TrySave(Asset,Error),Error); F.SharedLibraryChanged;
    Check(F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,OldVersion)=nil,'obsolete pending configuration remained attached');
    SelectAsset; AwaitAsset; Check(ImageHash(Source.Image)=OldHash,'late obsolete result mixed into current row');
    Decode := F.TimelineBox.VisualCache.PsdDecodeCount;
    TFile.SetLastWriteTimeUtc(Asset.FilePath,TFile.GetLastWriteTimeUtc(Asset.FilePath)+1/86400);
    F.TimelineBox.PollWaveforms(True); AwaitAsset; Check(F.TimelineBox.VisualCache.PsdDecodeCount>Decode,'same-size PSD update was ignored');
    MissingPath := Asset.FilePath+'.temporarily-missing'; TFile.Move(Asset.FilePath,MissingPath);
    F.TimelineBox.PollWaveforms(True); Check(Source.Status=vsMissing,'missing PSD placeholder state'); Capture(F,TPath.Combine(Dir,'missing-placeholder.png'));
    TFile.Move(MissingPath,Asset.FilePath); F.TimelineBox.PollWaveforms(True); AwaitAsset;
    for I := 0 to 9 do begin
      F.PatternList.TopIndex := I*12; Pump(100); Deadline := GetTickCount64+10000;
      repeat
        F.TimelineBox.PollWaveforms; Pump(2);
        Check(F.TimelineBox.VisualCache.ActiveJobs<=2,'PSD worker concurrency exceeded');
        Check(GetTickCount64<Deadline,'large list worker timeout');
      until F.TimelineBox.VisualCache.ActiveJobs=0;
    end;
    CachedImages := 0; LibraryItems := MusicStudioLibraryItems(F.Document,F.SharedLibrary,'psd','');
    for Item in LibraryItems do begin
      Source := F.TimelineBox.VisualCache.Find(vkPsd,Item.Pattern.FilePath,Item.PsdVersion);
      if (Source<>nil) and (Source.Image<>nil) then Inc(CachedImages);
    end;
    Check((CachedImages<=64) and (F.TimelineBox.VisualCache.BitmapCount<=128),'PSD image/bitmap LRU exceeded');
    SelectAsset; AwaitAsset;
    CheckOversubscribedCache;
    Check(F.JSONMemo.Text=Before,'browsing/cache refresh changed work JSON');
    Buttons := 0; for I := 0 to F.Preview.PlayButton.Parent.ControlCount-1 do
      if F.Preview.PlayButton.Parent.Controls[I] is TButton then Inc(Buttons);
    Check(Buttons=2,'transport is not one toggle plus stop');
    F.Preview.PlayButton.Click; Pump(70); Check(F.Preview.IsPlaying and F.Preview.PlayButton.Enabled and (Pos('一時停止',F.Preview.PlayButton.Caption)>0),'play toggle state');
    F.Preview.PlayButton.Click; Position := F.Preview.Position; Pump(80);
    Check(not F.Preview.IsPlaying and (Abs(F.Preview.Position-Position)<0.001),'pause failed to retain position');
    F.Preview.PlayButton.Click; Pump(60); Check(F.Preview.Position>Position,'resume clock');
    F.Preview.Seek(0.3); Check(F.Preview.IsPlaying,'playing seek lost toggle state');
    F.Preview.Seek(F.Preview.EndSeconds); Check(not F.Preview.IsPlaying and (Pos('再生',F.Preview.PlayButton.Caption)>0),'end seek retained pause icon');
    F.Preview.PlayButton.Click; Check(F.Preview.Position<0.05,'replay did not restart after end');
    F.Preview.Seek(F.Preview.EndSeconds-0.025); Pump(70);
    Check(not F.Preview.IsPlaying and (Pos('再生',F.Preview.PlayButton.Caption)>0),'natural end retained pause state');
    F.Preview.StopButton.Click; Check(not F.Preview.IsPlaying and (F.Preview.Position=0),'stop state');
    F.PatternList.SetFocus; Key := VK_SPACE; F.OnKeyDown(F,Key,[]); Check(F.Preview.IsPlaying,'space shortcut did not play');
    Key := VK_SPACE; F.OnKeyDown(F,Key,[]); Check(F.Preview.IsPlaying,'held space repeated toggle');
    Key := VK_SPACE; F.OnKeyUp(F,Key,[]); Key := VK_SPACE; F.OnKeyDown(F,Key,[]); Check(not F.Preview.IsPlaying,'space shortcut did not pause');
    Key := VK_SPACE; F.OnKeyUp(F,Key,[]); F.Preview.Stop;
    F.ClientWidth := 1000; F.ClientHeight := 600; Capture(F,TPath.Combine(Dir,'integrated-narrow.png'));
    // Hide before internal scaling: the physical 96DPI monitor otherwise sends a DPI reset.
    F.Hide; Pump(20); F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    F.TimelineBox.ScaleForPPI(144);
    R := F.TimelineBox.SlotThumbnailRect(0,Slot);
    Check((R.Top=F.TimelineBox.SlotRowTop(0,Slot)+MulDiv(7,144,96)) and (R.Height<=F.TimelineBox.RowHeight),
      Format('144DPI slot geometry ppi=%d top=%d row=%d height=%d rowheight=%d',[F.TimelineBox.CurrentPPI,R.Top,F.TimelineBox.SlotRowTop(0,Slot),R.Height,F.TimelineBox.RowHeight]));
    with F.GetFormImage do try SaveToFile(TPath.Combine(Dir,'integrated-144dpi-internal.bmp')); finally Free; end;
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio executed');
    Writeln('TRANSPORT_THUMBNAILS_OK rows=120 paint=100 LRU64/128 workers2 shared_revision missing_restore same_size_update 96/144DPI narrow toggle/seek/space audio=false');
  finally Config.Free; Document.Free; F.Free; end;
end;
procedure RunTransportRealPreview(const Root,AssetID: string);
var F: TFormMusicStudioSettings; Asset: TMusicStudioPsdAsset; Error,Text: string;
  I: Integer; Source: TMusicStudioVisualSource; Deadline: UInt64;
begin
  ForceDirectories(Root); F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LoadDocument('');
    Check(F.SharedLibrary.TryRead(AssetID,Asset,Error),Error);
    F.Document.AddTrack('psd'); F.Document.AssignPsd(0,Asset.ID);
    Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text); F.TimelineBox.SelectSlot(0,0);
    F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE);
    for I := 0 to F.PatternList.Count-1 do if F.PatternList.Items[I]=Asset.Name then begin
      F.PatternList.TopIndex := I; F.PatternList.ItemIndex := I; Break;
    end;
    Deadline := GetTickCount64+15000;
    repeat
      F.TimelineBox.PollWaveforms; F.Preview.SceneCache.PollResults; Pump(5);
      Source := F.TimelineBox.VisualCache.Find(vkPsd,Asset.FilePath,Version(Asset));
      if (F.Preview.SceneCache.ImageForTrack(0)<>nil) and (Source<>nil) and (Source.Image<>nil) then Break;
      Check(GetTickCount64<Deadline,'real character preview timeout');
    until False;
    TFile.WriteAllText(TPath.Combine(Root,'real-character-demo.json'),Text,TEncoding.UTF8);
    F.Preview.Stage.Repaint; F.TimelineBox.Repaint; F.PatternList.Repaint;
    Capture(F,TPath.Combine(Root,'real-character-integrated.png'));
    F.Preview.PlayButton.Click; Pump(100); Capture(F,TPath.Combine(Root,'real-character-playing.png')); F.Preview.Pause;
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'real preview used audio');
    Writeln('REAL_CHARACTER_TRANSPORT_THUMBNAIL_READONLY_NO_AUDIO_OK');
  finally F.Free; end;
end;
end.
