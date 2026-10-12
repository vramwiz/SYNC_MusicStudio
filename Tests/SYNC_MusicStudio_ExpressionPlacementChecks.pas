unit SYNC_MusicStudio_ExpressionPlacementChecks;

// Temp内のPSD/共有正本と所有VCL画面だけを使う。音声decode/fixture/出力を呼ばない。
interface
procedure RunExpressionPlacementChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON, System.Generics.Collections,
  System.Types, System.Math, System.UITypes, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls,
  Vcl.Graphics, Vcl.Imaging.pngimage, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_LibraryData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_TestHelpers,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PsdTransform,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_VideoRenderer,
  SYNC_MusicStudio_EditHistory, SYNC_MusicStudio_BeatData;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Expression/placement: '+Message); end;
procedure CloseEnough(A,B: Double; const Message: string);
begin Check(Abs(A-B)<0.00001,Message+Format(' (%g / %g)',[A,B])); end;
function ID: string;
var G: TGUID;
begin CreateGUID(G); Result := LowerCase(Copy(GUIDToString(G),2,36)); end;
procedure Fixture(const Path: string);
var D: TArtDocument; L: TArtLayer; X,Y,N: Integer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 64; D.Height := 32;
    L := D.AddLayer(alkImage,'expression',TArtBounds.Create(18,6,46,26)); L.Visible := True; SetLength(L.Pixels,28*20*4);
    for N := 0 to 28*20-1 do begin L.Pixels[N*4] := 255; L.Pixels[N*4+1] := 255; L.Pixels[N*4+2] := 0; L.Pixels[N*4+3] := 255; end;
    L := D.AddLayer(alkImage,'body',TArtBounds.Create(0,0,64,32)); L.Visible := True; SetLength(L.Pixels,64*32*4);
    for Y := 0 to 31 do for X := 0 to 63 do begin
      N := (Y*64+X)*4; L.Pixels[N] := X*3; L.Pixels[N+1] := Y*7; L.Pixels[N+2] := 40; L.Pixels[N+3] := 255;
    end;
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
procedure WaitReady(F: TFormMusicStudioSettings); forward;
procedure Capture(Form: TForm; const Path: string);
var B: TBitmap; PNG: TPngImage; DC: HDC; Origin: TPoint;
begin
  // この検証ホストだけの画面。144DPIのclient全体が隔離desktop内に収まる位置に置く。
  Origin := Form.ClientToScreen(Point(0,0));
  SetWindowPos(Form.Handle,0,Form.Left-Origin.X,Form.Top-Origin.Y,0,0,SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  if Form is TFormMusicStudioSettings then WaitReady(TFormMusicStudioSettings(Form));
  Form.Repaint; Application.ProcessMessages;
  if Form is TFormMusicStudioSettings then begin
    TFormMusicStudioSettings(Form).Preview.Stage.Repaint;
    TFormMusicStudioSettings(Form).PatternList.Repaint;
    TFormMusicStudioSettings(Form).TimelineBox.Repaint;
  end;
  B := TBitmap.Create; PNG := TPngImage.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(Form.ClientWidth,Form.ClientHeight);
    DC := GetDC(Form.Handle);
    try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'owned native client capture');
    finally ReleaseDC(Form.Handle,DC); end;
    PNG.Assign(B); PNG.SaveToFile(Path);
  finally PNG.Free; B.Free; end;
end;
procedure WaitReady(F: TFormMusicStudioSettings);
var Deadline: UInt64; I,Count: Integer; Ready: Boolean;
begin
  Deadline := GetTickCount64+10000;
  repeat
    F.Preview.SceneCache.PollResults; F.TimelineBox.PollWaveforms; Application.ProcessMessages;
    Check(F.TimelineBox.VisualCache.ActiveJobs<=2,'thumbnail job limit');
    Ready := True; Count := 0;
    for I := 0 to F.Document.TrackCount-1 do if (F.Document.TrackAt(I).Kind='psd') and (Count<4) then begin
      Inc(Count); Ready := Ready and (F.Preview.SceneCache.ImageForTrack(I)<>nil);
    end;
    if (F.Preview.SceneCache.ActiveLoadJobs=0) and (F.Preview.SceneCache.ActiveRenderJobs=0) and
      (F.TimelineBox.VisualCache.ActiveJobs=0) and Ready then Exit;
    Check(GetTickCount64<Deadline,'load timeout'); Sleep(2);
  until False;
end;
procedure Mouse(Control: TWinControl; Message: Cardinal; X,Y: Integer);
begin SendMessage(Control.Handle,Message,MK_LBUTTON,MakeLParam(X and $FFFF,Y and $FFFF)); end;
procedure Drag(Control: TWinControl; X,Y,DX,DY: Integer);
begin Mouse(Control,WM_LBUTTONDOWN,X,Y); Mouse(Control,WM_MOUSEMOVE,X+DX,Y+DY); Mouse(Control,WM_LBUTTONUP,X+DX,Y+DY); end;
function DocumentText(Document: TMusicStudioDocument): string;
var Error: string;
begin Check(Document.TrySave(Result,Error),Error); end;
function RowHash(Image: TBitmap; Y: Integer): string;
var Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try Stream.WriteBuffer(Image.ScanLine[Y]^,Image.Width*4); Stream.Position := 0; Result := THashSHA2.GetHashString(Stream);
  finally Stream.Free; end;
end;
procedure ModelChecks;
var D: TMusicStudioDocument; O,Psd: TJSONObject; Transform,ReadBack: TMusicStudioPsdTransform;
  Text,Error,Before: string; H: TMusicStudioEditHistory; I: Integer;
begin
  D := TMusicStudioDocument.Create; H := TMusicStudioEditHistory.Create;
  try
    Check(D.TryLoad('',Error),Error); D.AddTrack('psd');
    Before := DocumentText(D); Transform := D.TrackAt(0).PsdTransform;
    Check(not Transform.HasBounds and not Transform.FlipX,'legacy default');
    Transform.FlipX := True; D.UpdatePsdTransform(0,Transform); Text := DocumentText(D);
    Check(D.TryLoad(Text,Error),Error); Check(D.TrackAt(0).PsdTransform.FlipX and not D.TrackAt(0).PsdTransform.HasBounds,'flip-only roundtrip');
    O := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      Psd := TJSONObject(TJSONObject(TJSONArray(O.GetValue('tracks')).Items[0]).GetValue('psd'));
      TJSONObject(Psd.GetValue('transform')).AddPair('future','keep'); Psd.AddPair('extension','preserved');
      Transform.HasBounds := True; Transform.X := -0.2; Transform.Y := 0.1; Transform.Width := 0.5; Transform.Height := 0.7;
      WriteMusicStudioPsdTransform(Psd,Transform); Check(Pos('keep',Psd.ToJSON)>0,'transform extension lost');
      Check(ReadMusicStudioPsdTransform(Psd.GetValue('transform'),ReadBack,Error),Error);
      CloseEnough(ReadBack.Width,0.5,'transform width');
      Check(D.TryLoad(O.ToJSON,Error),Error); Before := DocumentText(D);
      Transform.Width := -1;
      try D.UpdatePsdTransform(0,Transform); Check(False,'negative width accepted'); except on E: EArgumentException do ; end;
      Check(DocumentText(D)=Before,'invalid update altered JSON');
      TJSONObject(Psd.GetValue('transform')).RemovePair('width').Free;
      Check(not D.TryLoad(O.ToJSON,Error),'partial bounds accepted'); Check(DocumentText(D)=Before,'invalid load adopted');
    finally O.Free; end;
    for I := 0 to 39 do H.RecordChange(IntToStr(I),IntToStr(I+1));
    Text := '40'; for I := 1 to 32 do begin Check(H.Undo(Text,Before),'undo cap'); Text := Before; end;
    Check(not H.Undo(Text,Before),'undo exceeded cap'); Check(H.Redo(Text,Before),'redo');
    Check(not H.Redo('external',Before),'stale redo');
    Writeln('PASS transform validation/extensions/legacy/roundtrip and bounded stale-safe history');
  finally H.Free; D.Free; end;
end;
procedure ChurnChecks(const ItemA,ItemB: TMusicStudioLibraryItem; const HashA,HashB: string);
var Cache: TMusicStudioVisualCache; Requests: TArray<TMusicStudioVisualRequest>;
  I,J: Integer; Deadline: UInt64; Source: TMusicStudioVisualSource; Missing: TMusicStudioPattern;
begin
  Cache := TMusicStudioVisualCache.Create;
  try
    SetLength(Requests,2);
    for I := 0 to 1 do begin
      Requests[I].Kind := vkPsd; Requests[I].Visible := True; Requests[I].Path := ItemA.Pattern.FilePath;
      Requests[I].ConfigJSON := ItemA.ThumbnailConfigJSON;
    end;
    for J := 0 to 29 do begin
      for I := 0 to 1 do begin
        Requests[I].PsdVersion := 'generation-'+IntToStr(J)+'-'+IntToStr(I);
        if I=J mod 2 then Requests[I].ExpressionJSON := ItemA.ExpressionJSON else Requests[I].ExpressionJSON := ItemB.ExpressionJSON;
      end;
      Cache.SetSources(Requests); Cache.Poll; Check(Cache.ActiveJobs<=2,'churn concurrency');
    end;
    Requests[0].PsdVersion := ItemA.PsdVersion; Requests[0].ExpressionJSON := ItemA.ExpressionJSON;
    Requests[1].PsdVersion := ItemB.PsdVersion; Requests[1].ExpressionJSON := ItemB.ExpressionJSON;
    Cache.SetSources(Requests); Deadline := GetTickCount64+10000;
    repeat Cache.Poll; Check(Cache.ActiveJobs<=2,'retired concurrency');
      Check(GetTickCount64<Deadline,'churn timeout'); Sleep(2);
    until Cache.ActiveJobs=0;
    Source := Cache.Find(vkPsd,ItemA.Pattern.FilePath,ItemA.PsdVersion);
    Check((Source<>nil) and (Source.Status=vsReady) and (RowHash(Source.Image,16)=HashA),'stale expression A adopted');
    Source := Cache.Find(vkPsd,ItemB.Pattern.FilePath,ItemB.PsdVersion);
    Check((Source<>nil) and (Source.Status=vsReady) and (RowHash(Source.Image,16)=HashB),'stale expression B adopted');
    Missing := ItemA.Pattern; Missing.SharedPatternID := ID;
    Check(MusicStudioEmotionItem(Missing,[]).Missing,'missing PSD placeholder');
    Writeln('PASS 30 asynchronous expression generations, retired job limit and no stale cross-adoption');
  finally Cache.Free; end;
end;
procedure RealExpressionCheck(const Root: string);
var Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset; Preset: TMusicStudioSharedPattern;
  Pattern: TMusicStudioPattern; Item: TMusicStudioLibraryItem; Request: TMusicStudioVisualRequest;
  Cache: TMusicStudioVisualCache; Source: TMusicStudioVisualSource; D: TMusicStudioLayerDocument;
  Config,Expression,Overrides: TJSONObject; Expected,Thumb: TBitmap; PNG: TPngImage;
  Error,Before: string; Deadline: UInt64; X,Y,SX,SY: Integer; Row,Actual: PByte;
begin
  Store := TMusicStudioSharedPsdLibrary.Create; Cache := TMusicStudioVisualCache.Create;
  D := TMusicStudioLayerDocument.Create; Expected := TBitmap.Create; PNG := TPngImage.Create;
  Config := nil; Expression := nil; Overrides := nil;
  try
    Check(Store.TryRead('6720ffb6-68b1-4b4a-9582-da424493c9bc',Asset,Error),Error);
    Pattern := Default(TMusicStudioPattern);
    for Preset in Asset.Patterns do if Preset.Kind='emotion' then begin
      Pattern.ID := 'read-only-real'; Pattern.Kind := 'emotion'; Pattern.AssetID := Asset.ID;
      Pattern.SharedPatternID := Preset.ID; Break;
    end;
    Check(Pattern.Kind='emotion','real expression preset missing');
    Before := THashSHA2.GetHashStringFromFile(Asset.FilePath);
    Item := MusicStudioEmotionItem(Pattern,TArray<TMusicStudioPsdAsset>.Create(Asset)); Check(not Item.Missing,'real preset unresolved');
    Request := Default(TMusicStudioVisualRequest); Request.Kind := vkPsd; Request.Visible := True;
    Request.Path := Item.Pattern.FilePath; Request.PsdVersion := Item.PsdVersion;
    Request.ConfigJSON := Item.ThumbnailConfigJSON; Request.ExpressionJSON := Item.ExpressionJSON;
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request)); Deadline := GetTickCount64+15000;
    repeat Cache.Poll; Check(GetTickCount64<Deadline,'real expression timeout'); Sleep(2); until Cache.ActiveJobs=0;
    Source := Cache.Find(vkPsd,Request.Path,Request.PsdVersion); Check((Source<>nil) and (Source.Status=vsReady),'real expression load');
    Check(D.LoadFile(Asset.FilePath),D.LastError); Config := ParseMusicStudioPsdConfig(Asset.ConfigJSON);
    Expression := ParseMusicStudioPsdConfig(Item.ExpressionJSON); Overrides := BuildMusicStudioExpressionOverrides(D,Config,Expression);
    Check(D.Render(Expected,Overrides),D.LastError);
    for Y := 0 to Source.Image.Height-1 do begin
      SY := Int64(Y)*Expected.Height div Source.Image.Height; Row := Expected.ScanLine[SY]; Actual := Source.Image.ScanLine[Y];
      for X := 0 to Source.Image.Width-1 do begin
        SX := Int64(X)*Expected.Width div Source.Image.Width;
        Check(CompareMem(@Actual[X*4],@Row[SX*4],4),'real expression composed pixel');
      end;
    end;
    Thumb := Cache.Thumbnail(Source,92,92,144,$00404040); PNG.Assign(Thumb);
    PNG.SaveToFile(TPath.Combine(Root,'real-expression-thumbnail.png'));
    Check(THashSHA2.GetHashStringFromFile(Asset.FilePath)=Before,'real PSD changed');
    Writeln('PASS real shared expression preset thumbnail matches direct composite, PSD read-only');
  finally Overrides.Free; Expression.Free; Config.Free; PNG.Free; Expected.Free; D.Free; Cache.Free; Store.Free; end;
end;
procedure RunExpressionPlacementChecks(const Root: string);
var F: TFormMusicStudioSettings; D: TMusicStudioLayerDocument; Asset: TMusicStudioPsdAsset;
  Dup: Boolean; Dir,Source,Error,Key,Before,After,SourceHash,MetadataHash,PSDHash,JSON: string;
  Config: TJSONObject; P: TMusicStudioPattern; ItemA,ItemB: TMusicStudioLibraryItem;
  A,B: TMusicStudioVisualSource; Track,Second,S,PS,I,X,Y,RightX,Loads,Rasters: Integer;
  Clip,Neighbor: TMusicStudioPlacement; V,R,Other: TRect; Transform: TMusicStudioPsdTransform;
  Video: TMusicStudioVideoSession; Pixels,Flipped: TMusicStudioVideoPixels;
  PixelHashA,PixelHashB: string; KeyCode: Word; ExpectedEnd: Double;
begin
  ModelChecks; Dir := TPath.Combine(Root,'expressions-placement'); ForceDirectories(Dir); RealExpressionCheck(Dir);
  Source := TPath.Combine(Dir,'source.psd'); Fixture(Source); SourceHash := THashSHA2.GetHashStringFromFile(Source);
  F := TFormMusicStudioSettings.Create(nil); D := TMusicStudioLayerDocument.Create; Video := nil;
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Dir,'library'); F.LoadDocument('');
    Check(F.SharedLibrary.TryImport(Source,'テストPSD','#90C4E0',Asset,Dup,Error),Error);
    Check(D.LoadFile(Asset.FilePath),D.LastError); Key := '';
    for I := 0 to High(D.Layers) do if D.Layers[I].Name='expression' then Key := D.Layers[I].Key;
    Check(Key<>'','expression key'); SetLength(Asset.Patterns,2);
    for I := 0 to 1 do begin
      Asset.Patterns[I].ID := ID; Asset.Patterns[I].AssetID := Asset.ID; Asset.Patterns[I].Kind := 'emotion';
      Asset.Patterns[I].Name := '表情 '+IntToStr(I+1); Asset.Patterns[I].Color := '#B47AE0';
      Config := ParseMusicStudioPsdConfig('');
      try MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),Key,I=1); Asset.Patterns[I].ConfigJSON := Config.ToJSON;
      finally Config.Free; end;
    end;
    Check(F.SharedLibrary.TrySave(Asset,Error),Error);
    MetadataHash := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'));
    PSDHash := THashSHA2.GetHashStringFromFile(Asset.FilePath);
    Track := F.Document.AddTrack('psd'); F.Document.AssignPsd(Track,Asset.ID);
    Second := F.Document.AddTrack('psd'); F.Document.AssignPsd(Second,Asset.ID);
    S := TestSlotIndex(F.Document,Track,'emotion'); PS := TestSlotIndex(F.Document,Track,'psd');
    for I := 0 to 1 do begin
      P := Default(TMusicStudioPattern); P.ID := ID; P.Kind := 'emotion'; P.Name := Asset.Patterns[I].Name; P.Color := Asset.Patterns[I].Color;
      P.AssetID := Asset.ID; P.SharedPatternID := Asset.Patterns[I].ID; F.Document.AddReference(P);
      Check(F.Document.AddPlacement(Track,S,F.Document.PatternAt(I).ID,1+2*I,2-I,Error),Error);
    end;
    JSON := DocumentText(F.Document); F.LoadDocument(JSON); F.ClientWidth := 1200; F.ClientHeight := 700; F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE);
    F.TimelineBox.SelectClip(Track,S,0); F.TimelineBox.SetZoom(80); WaitReady(F); F.Repaint; Application.ProcessMessages;
    ItemA := MusicStudioEmotionItem(F.Document.PatternAt(0),F.SharedLibrary.Assets);
    ItemB := MusicStudioEmotionItem(F.Document.PatternAt(1),F.SharedLibrary.Assets);
    A := F.TimelineBox.VisualCache.Find(vkPsd,ItemA.Pattern.FilePath,ItemA.PsdVersion);
    B := F.TimelineBox.VisualCache.Find(vkPsd,ItemB.Pattern.FilePath,ItemB.PsdVersion);
    Check((A<>nil) and (B<>nil) and (A.Status=vsReady) and (B.Status=vsReady),'expression cache ready');
    PixelHashA := RowHash(A.Image,16); PixelHashB := RowHash(B.Image,16);
    Check(PixelHashA<>PixelHashB,'two expressions identical');
    ChurnChecks(ItemA,ItemB,PixelHashA,PixelHashB);
    Check((A.PsdVersion=ItemA.PsdVersion) and (A.ExpressionJSON=ItemA.ExpressionJSON),'expression snapshot/key');
    Loads := F.TimelineBox.VisualCache.PsdDecodeCount; F.Repaint; Rasters := F.TimelineBox.VisualCache.RasterCount;
    for I := 1 to 50 do begin F.Repaint; F.TimelineBox.Repaint; end;
    Check(F.TimelineBox.VisualCache.PsdDecodeCount=Loads,'paint read/composed PSD');
    Check(F.TimelineBox.VisualCache.RasterCount=Rasters,'paint ignored thumbnail cache');
    Capture(F,TPath.Combine(Dir,'expression-thumbnails-96.png'));
    Y := F.TimelineBox.SlotRowTop(Track,S)+F.TimelineBox.RowHeight div 2;
    X := F.TimelineBox.HeaderWidth+80; RightX := X+160-2;
    Check(F.TimelineBox.EmotionResizeEdgeAt(X+2,Y)=-1,'left grip'); Check(F.TimelineBox.EmotionResizeEdgeAt(RightX,Y)=1,'right grip');
    Check(F.TimelineBox.EmotionResizeEdgeAt(X+80,Y)=0,'center grip');
    Neighbor := F.Document.TrackAt(Track).Slots[S].Clips[1];
    Drag(F.TimelineBox,RightX,Y,80,0); Clip := F.Document.TrackAt(Track).Slots[S].Clips[0];
    CloseEnough(Clip.StartSeconds,1,'right keeps start'); CloseEnough(Clip.LengthSeconds,3,'right resizes');
    Check(F.Document.TrackAt(Track).Slots[S].Clips[1].ID=Neighbor.ID,'neighbor changed');
    F.UndoEdit; CloseEnough(F.Document.TrackAt(Track).Slots[S].Clips[0].LengthSeconds,2,'resize undo');
    Check(F.TimelineBox.SelectedClip=0,'undo selection lost'); F.RedoEdit;
    CloseEnough(F.Document.TrackAt(Track).Slots[S].Clips[0].LengthSeconds,3,'resize redo'); F.UndoEdit;
    Before := DocumentText(F.Document); Mouse(F.TimelineBox,WM_LBUTTONDOWN,X+2,Y); Mouse(F.TimelineBox,WM_MOUSEMOVE,X+42,Y);
    Check(DocumentText(F.Document)=Before,'draft mutated model');
    KeyCode := VK_ESCAPE; F.OnKeyDown(F,KeyCode,[]); Check(KeyCode=0,'resize Escape not consumed');
    Mouse(F.TimelineBox,WM_LBUTTONUP,X+42,Y); Check(DocumentText(F.Document)=Before,'cancel resize committed');
    Drag(F.TimelineBox,X+2,Y,-500,0); Clip := F.Document.TrackAt(Track).Slots[S].Clips[0];
    CloseEnough(Clip.StartSeconds,0,'left clamp zero'); CloseEnough(Clip.StartSeconds+Clip.LengthSeconds,3,'left keeps end'); F.UndoEdit;
    Drag(F.TimelineBox,X+80,Y,40,0); Clip := F.Document.TrackAt(Track).Slots[S].Clips[0];
    CloseEnough(Clip.StartSeconds,1.5,'center move'); CloseEnough(Clip.LengthSeconds,2,'center preserves length'); F.UndoEdit;
    ExpectedEnd := F.Document.BeatToSeconds(MusicStudioSnapBeat(F.Document.SecondsToBeat(3+23/80),F.TimelineBox.BeatSnapStep(3+23/80)));
    Drag(F.TimelineBox,RightX,Y,23,0); Clip := F.Document.TrackAt(Track).Slots[S].Clips[0];
    CloseEnough(Clip.StartSeconds+Clip.LengthSeconds,ExpectedEnd,'beat-grid resize'); F.UndoEdit;
    Drag(F.TimelineBox,RightX,Y,-500,0); Clip := F.Document.TrackAt(Track).Slots[S].Clips[0];
    CloseEnough(Clip.LengthSeconds,0.001,'minimum length');
    Check(F.TimelineBox.EmotionResizeEdgeAt(X+1,Y)=-1,'minimum left grip');
    Check(F.TimelineBox.EmotionResizeEdgeAt(X+7,Y)=1,'minimum right grip'); F.UndoEdit;
    Writeln('PASS expression composites/list+timeline cached paint, both edges/center/zero/draft/cancel/undo/redo');
    F.TimelineBox.SelectSlot(Track,PS); WaitReady(F);
    Check(F.Preview.PlacementEditor.SelectedTrack=Track,'PSD selection'); Check(F.Preview.CharacterBounds(Track,V,R),'selected image');
    Check(F.Preview.CharacterBounds(Second,V,Other),'other image'); Before := DocumentText(F.Document);
    Drag(F.Preview.Stage,Other.CenterPoint.X,Other.CenterPoint.Y,15,12); Check(DocumentText(F.Document)=Before,'other character captured');
    Drag(F.Preview.Stage,R.CenterPoint.X,R.CenterPoint.Y,20,-10); Transform := F.Document.TrackAt(Track).PsdTransform;
    Check(Transform.HasBounds,'move not saved'); CloseEnough(Transform.X,(R.Left-V.Left+20)/V.Width,'normalized X');
    Check(not F.Document.TrackAt(Second).PsdTransform.HasBounds,'other transform changed');
    After := DocumentText(F.Document); F.UndoEdit; Check(not F.Document.TrackAt(Track).PsdTransform.HasBounds,'move undo');
    Check(F.Preview.PlacementEditor.SelectedTrack=Track,'placement undo selection'); F.RedoEdit;
    Check(DocumentText(F.Document)=After,'move redo'); WaitReady(F); F.Preview.CharacterBounds(Track,V,R);
    for I := 1 to 4 do begin
      F.Preview.CharacterBounds(Track,V,R); X := R.Left+2; Y := R.Top+2;
      if I in [2,4] then X := R.Right-2; if I in [3,4] then Y := R.Bottom-2;
      Drag(F.Preview.Stage,X,Y,20,10); Transform := F.Document.TrackAt(Track).PsdTransform;
      CloseEnough(Transform.Width/Transform.Height,((R.Width/V.Width)/(R.Height/V.Height)),'aspect lock '+IntToStr(I));
      F.UndoEdit; WaitReady(F);
    end;
    F.Preview.CharacterBounds(Track,V,R); Before := DocumentText(F.Document);
    Mouse(F.Preview.Stage,WM_LBUTTONDOWN,R.CenterPoint.X,R.CenterPoint.Y); Mouse(F.Preview.Stage,WM_MOUSEMOVE,R.CenterPoint.X+30,R.CenterPoint.Y);
    Check(F.Preview.PlacementEditor.Dragging,'placement drag'); Check(DocumentText(F.Document)=Before,'placement draft wrote model');
    KeyCode := VK_ESCAPE; F.OnKeyDown(F,KeyCode,[]); Check(KeyCode=0,'placement Escape not consumed');
    Mouse(F.Preview.Stage,WM_LBUTTONUP,R.CenterPoint.X+30,R.CenterPoint.Y);
    Check(DocumentText(F.Document)=Before,'placement cancel committed');
    Check(F.Preview.PlacementEditor.FlipMenu.Items[0].Caption='左右反転','horizontal menu');
    F.Preview.PlacementEditor.FlipMenu.Items[0].Click; Check(F.Document.TrackAt(Track).PsdTransform.FlipX,'horizontal flip'); F.UndoEdit; WaitReady(F);
    F.Preview.PlacementEditor.FlipMenu.Items[1].Click; Check(F.Document.TrackAt(Track).PsdTransform.FlipY,'vertical flip'); F.UndoEdit; WaitReady(F);
    Capture(F,TPath.Combine(Dir,'placement-handles-96.png')); F.ScaleForPPI(144); WaitReady(F);
    F.Preview.CharacterBounds(Track,V,R); Before := DocumentText(F.Document);
    Drag(F.Preview.Stage,R.CenterPoint.X,R.CenterPoint.Y,30,-15); Transform := F.Document.TrackAt(Track).PsdTransform;
    CloseEnough(Transform.X,(R.Left-V.Left+30)/V.Width,'144 DPI normalized X'); F.UndoEdit; WaitReady(F);
    Capture(F,TPath.Combine(Dir,'placement-handles-144.png'));
    F.Preview.CharacterBounds(Track,V,R);
    Drag(F.Preview.Stage,R.CenterPoint.X,R.CenterPoint.Y,V.Left-R.Left-R.Width div 2,0); WaitReady(F);
    F.Preview.CharacterBounds(Track,V,R); Check(R.Left<V.Left,'outside placement was clamped');
    Before := DocumentText(F.Document);
    Drag(F.Preview.Stage,R.Left+2,R.Top+2,-10,-5); Check(DocumentText(F.Document)<>Before,'outside corner not editable');
    WaitReady(F); F.Preview.PlacementEditor.Flip(True); WaitReady(F);
    Check(F.Document.TrackAt(Track).PsdTransform.FlipX,'outside flip');
    Capture(F,TPath.Combine(Dir,'placement-outside-144.png'));
    JSON := DocumentText(F.Document); F.LoadDocument(JSON); Check(DocumentText(F.Document)=JSON,'placement reopen');
    TFile.WriteAllText(TPath.Combine(Dir,'expression-placement-demo.json'),JSON,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir,'library-root.txt'),F.LibraryRoot,TEncoding.UTF8);
    Check(F.Document.TrackAt(Track).PsdTransform.HasBounds,'placement reload');
    Writeln('PASS PSD selection isolation/move/aspect/cancel/flip/undo/redo/144DPI/reopen');
    // Video uses the same transform, exact known source pixels and clipping at the frame edges.
    Video := TMusicStudioVideoSession.Create(F.LibraryRoot);
    F.Document.RemoveTrack(Second); Transform := Default(TMusicStudioPsdTransform);
    F.Document.UpdatePsdTransform(Track,Transform); JSON := DocumentText(F.Document);
    Check(Video.Render(JSON,0,64,32,Pixels,Error),Error); Transform.FlipX := True; Transform.FlipY := True;
    F.Document.UpdatePsdTransform(Track,Transform); Check(Video.Render(DocumentText(F.Document),0,64,32,Flipped,Error),Error);
    Check(Length(Pixels)=Length(Flipped),'video dimensions');
    for I := 0 to High(Pixels) do Check(CompareMem(@Pixels[I],@Flipped[High(Pixels)-I],SizeOf(Pixels[I])),'callback flip pixels');
    Transform.HasBounds := True; Transform.X := -0.5; Transform.Y := 0.0; Transform.Width := 1; Transform.Height := 1;
    F.Document.UpdatePsdTransform(Track,Transform); Check(Video.Render(DocumentText(F.Document),0,64,32,Flipped,Error),Error);
    for I := 32 to 63 do Check(Flipped[I].A=0,'off-frame clipping');
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'original PSD changed');
    Check(THashSHA2.GetHashStringFromFile(Asset.FilePath)=PSDHash,'shared source changed');
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'))=MetadataHash,'shared config changed');
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio invoked');
    Writeln('PASS callback transform/flip/off-frame pixels, original/shared protection, zero audio');
  finally Video.Free; D.Free; F.Free; end;
end;
end.
