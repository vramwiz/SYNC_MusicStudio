unit SYNC_MusicStudio_VisualCacheChecks;
interface
procedure RunVisualCacheChecks(const Root: string);
implementation
uses System.Classes, System.SysUtils, System.Types, System.Math, System.IOUtils, System.JSON,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_BitmapCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_TestHelpers;
type
  TVisualViewAccess = class(TMusicStudioArrangementView)
    procedure ScrollTo(Seconds: Integer);
    procedure ScrollVerticalTo(Pixels: Integer);
  end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure TVisualViewAccess.ScrollTo(Seconds: Integer);
var I: Integer;
begin for I := 0 to ControlCount-1 do if (Controls[I] is TScrollBar) and (TScrollBar(Controls[I]).Kind=sbHorizontal) then TScrollBar(Controls[I]).Position := Seconds; end;
procedure TVisualViewAccess.ScrollVerticalTo(Pixels: Integer);
var I: Integer;
begin for I := 0 to ControlCount-1 do if (Controls[I] is TScrollBar) and (TScrollBar(Controls[I]).Kind=sbVertical) then TScrollBar(Controls[I]).Position := Pixels; end;
procedure Big16(S: TStream; Value: Word);
var B: array[0..1] of Byte;
begin B[0] := Value shr 8; B[1] := Value and 255; S.WriteBuffer(B,2); end;
procedure Big32(S: TStream; Value: Cardinal);
var B: array[0..3] of Byte;
begin B[0] := Value shr 24; B[1] := (Value shr 16) and 255; B[2] := (Value shr 8) and 255; B[3] := Value and 255; S.WriteBuffer(B,4); end;
procedure WriteMidi(const Path: string; Shift: Byte = 0);
var S: TFileStream; Data: TBytes;
  procedure Track(const Bytes: TBytes);
  const Tag: AnsiString = 'MTrk';
  begin S.WriteBuffer(Tag[1],4); Big32(S,Length(Bytes)); S.WriteBuffer(Bytes[0],Length(Bytes)); end;
const Header: AnsiString = 'MThd';
begin
  S := TFileStream.Create(Path,fmCreate);
  try
    S.WriteBuffer(Header[1],4); Big32(S,6); Big16(S,1); Big16(S,3); Big16(S,480);
    Track(TBytes.Create(0,$FF,$51,3,7,$A1,$20,$83,$60,$FF,$51,3,$0F,$42,$40,0,$FF,$2F,0));
    Data := TBytes.Create(0,$FF,5,1,97,0,$90,60+Shift,100,$83,$60,$80,60+Shift,0,
      0,$90,72+Shift,100,$83,$60,$80,72+Shift,0,0,$FF,$2F,0); Track(Data);
    Track(TBytes.Create($81,$70,$90,48+Shift,100,$85,$50,$80,48+Shift,0,0,$FF,$2F,0));
  finally S.Free; end;
end;
procedure WritePitchMidi(const Path: string; Updated: Boolean = False);
const Header: AnsiString = 'MThd'; Tag: AnsiString = 'MTrk';
var S: TFileStream; Data: TBytes; T,I: Integer; Key: Byte;
begin
  S := TFileStream.Create(Path,fmCreate);
  try
    S.WriteBuffer(Header[1],4); Big32(S,6); Big16(S,1); Big16(S,6); Big16(S,480);
    for T := 0 to 5 do begin
      Data := nil;
      if T>0 then for I := 0 to 3 do begin
        case T of
          1: if Updated then Key := 68 else Key := 60;
          2: Key := 0;
          3: Key := 127;
          4: case I of 1: Key := 127; 2: Key := 64; else Key := 0; end;
        else Key := 60+I mod 2;
        end;
        Data := Data+TBytes.Create(0,$90,Key,100,$83,$60,$80,Key,0);
      end;
      Data := Data+TBytes.Create(0,$FF,$2F,0);
      S.WriteBuffer(Tag[1],4); Big32(S,Length(Data)); S.WriteBuffer(Data[0],Length(Data));
    end;
  finally S.Free; end;
end;
procedure WritePsd(const Path: string; Changed: Boolean = False);
var S: TFileStream; Header: TBytes; C,X,Y: Integer; Value: Byte;
begin
  Header := TBytes.Create(56,66,80,83,0,1,0,0,0,0,0,0,0,4,0,0,0,64,0,0,0,128,0,8,0,3);
  S := TFileStream.Create(Path,fmCreate);
  try
    S.WriteBuffer(Header[0],26); Big32(S,0); Big32(S,0); Big32(S,6); Big32(S,2); Big16(S,$FFFF); Big16(S,0);
    for C := 0 to 3 do for Y := 0 to 63 do for X := 0 to 127 do begin
      Value := 0;
      if X<64 then case C of
        0: if (Y<32) and not Changed then Value := 255;
        1: if (Y<32) and Changed then Value := 255;
        2: if Y>=32 then Value := 255;
        3: if Y<32 then Value := 128 else Value := 255;
      end;
      S.WriteBuffer(Value,1);
    end;
  finally S.Free; end;
end;
function Request(Kind: TMusicStudioVisualKind; const Path: string; Visible: Boolean = True): TMusicStudioVisualRequest;
begin Result.Kind := Kind; Result.Path := Path; Result.Visible := Visible; end;
procedure Await(Cache: TMusicStudioVisualCache);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  repeat Cache.Poll; Application.ProcessMessages; Sleep(1); Check(GetTickCount64<Deadline,'Visual cache timeout'); until Cache.ActiveJobs=0;
end;
function WhiteCount(B: TBitmap; X: Integer): Integer;
var Y: Integer;
begin Result := 0; for Y := 0 to B.Height-1 do if ColorToRGB(B.Canvas.Pixels[X,Y])=ColorToRGB(clWhite) then Inc(Result); end;
procedure TestCache(const Root: string);
var Cache: TMusicStudioVisualCache; Midi,Psd: TMusicStudioVisualSource; B,Thumb: TBitmap;
  MidiPath,PsdPath,Broken,Missing: string; I,DecodeM,DecodeP,Raster,Rev: Integer; Stamp: TDateTime; Pixel: PByte; Deadline: UInt64;
begin
  MidiPath := TPath.Combine(Root,'visual-tempo.mid'); PsdPath := TPath.Combine(Root,'visual-alpha.psd');
  Broken := TPath.Combine(Root,'visual-broken.mid'); Missing := TPath.Combine(Root,'visual-missing.psd');
  WriteMidi(MidiPath); WritePsd(PsdPath); TFile.WriteAllText(Broken,'broken'); if TFile.Exists(Missing) then TFile.Delete(Missing);
  Cache := TMusicStudioVisualCache.Create; B := TBitmap.Create;
  try
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,MidiPath,False),Request(vkPsd,PsdPath,False)));
    Check((Cache.ActiveJobs=0) and (Cache.MidiDecodeCount=0),'Invisible visual source parsed');
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,MidiPath),Request(vkMidi,UpperCase(MidiPath)),
      Request(vkPsd,PsdPath),Request(vkPsd,UpperCase(PsdPath)),Request(vkMidi,Broken),Request(vkPsd,Missing),Request(vkMidi,''),Request(vkPsd,'')));
    Check(Cache.Find(vkMidi,MidiPath).Status=vsPending,'MIDI pending not explicit'); Await(Cache);
    Midi := Cache.Find(vkMidi,MidiPath); Psd := Cache.Find(vkPsd,PsdPath);
    Check((Midi=Cache.Find(vkMidi,UpperCase(MidiPath))) and (Psd=Cache.Find(vkPsd,UpperCase(PsdPath))) and
      (Cache.MidiDecodeCount=2) and (Cache.PsdDecodeCount=1),'Duplicate source not shared');
    Check((Length(Midi.Rolls[1].Notes)=2) and (Midi.Rolls[1].Notes[0].Key=60) and (Midi.Rolls[1].Notes[1].Key=72) and
      SameValue(Midi.Rolls[1].Notes[0].StartSeconds,0) and SameValue(Midi.Rolls[1].Notes[0].EndSeconds,0.5) and
      SameValue(Midi.Rolls[1].Notes[1].StartSeconds,0.5) and
      SameValue(Midi.Rolls[1].Notes[1].EndSeconds,1.5),'Global tempo/real MIDI timing wrong');
    Check((Cache.MidiMessage(Midi,0)='音符なし') and (Cache.MidiMessage(Midi,-1)<>'') and (Cache.MidiMessage(Midi,99)<>'') and
      (Cache.Find(vkMidi,Broken).Status=vsBroken) and (Cache.Find(vkPsd,Missing).Status=vsMissing) and
      (Cache.Find(vkPsd,'').Status=vsUnselected),'Empty/missing/broken states conflated');
    B.SetSize(320,64); Cache.DrawRoll(B.Canvas,Rect(0,0,320,64),Rect(0,0,320,64),Midi,1,160,96,clBlack,clWhite);
    Check((WhiteCount(B,20)>0) and (WhiteCount(B,100)>0) and (WhiteCount(B,270)=0),'MIDI roll range stretched');
    Check((B.Canvas.Pixels[20,54]=clWhite) and (B.Canvas.Pixels[100,8]=clWhite) and
      (B.Canvas.Pixels[20,8]<>clWhite) and (B.Canvas.Pixels[100,54]<>clWhite),'Real key pitch/duration not reflected');
    B.Canvas.Brush.Color := clBlack; B.Canvas.FillRect(Rect(0,0,320,64));
    Cache.DrawRoll(B.Canvas,Rect(0,0,120,64),Rect(0,0,320,64),Midi,1,160,96,clBlack,clWhite);
    Check((WhiteCount(B,100)>0) and (WhiteCount(B,130)=0),'Clip length failed to cut MIDI note');
    Cache.DrawRoll(B.Canvas,Rect(0,0,320,64),Rect(0,0,320,64),Midi,2,160,96,clBlack,clWhite);
    Check((WhiteCount(B,20)=0) and (WhiteCount(B,60)>0),'Selected MIDI track ignored');
    Pixel := Psd.Image.ScanLine[0]; Check((Psd.Image.Width=128) and (Psd.Image.Height=64) and
      (Pixel[2]=128) and (Pixel[3]=128),Format('PSD alpha/orientation not preserved: %dx%d BGRA=%d,%d,%d,%d',
      [Psd.Image.Width,Psd.Image.Height,Pixel[0],Pixel[1],Pixel[2],Pixel[3]]));
    Thumb := Cache.Thumbnail(Psd,64,64,96,clLime);
    Check(ColorToRGB(Thumb.Canvas.Pixels[8,5])=ColorToRGB(clLime),'PSD aspect ratio not maintained');
    Check(ColorToRGB(Thumb.Canvas.Pixels[48,20])=ColorToRGB(clLime),'Transparent PSD became opaque');
    Check(GetRValue(ColorToRGB(Thumb.Canvas.Pixels[8,20]))>=125,'Premultiplied alpha lost');
    Check(GetBValue(ColorToRGB(Thumb.Canvas.Pixels[8,45]))>=250,'PSD vertically reversed');
    DecodeM := Cache.MidiDecodeCount; DecodeP := Cache.PsdDecodeCount; Raster := Cache.RasterCount;
    for I := 1 to 100 do begin
      Cache.DrawRoll(B.Canvas,Rect(0,0,320,64),Rect(0,0,320,64),Midi,2,160,96,clBlack,clWhite);
      Check(Cache.Thumbnail(Psd,64,64,96,clLime)=Thumb,'Repeated thumbnail regenerated');
    end;
    Check((Cache.RasterCount=Raster) and (Cache.MidiDecodeCount=DecodeM) and (Cache.PsdDecodeCount=DecodeP),'Paint parsed/rasterized repeatedly');
    for I := 1 to 160 do Cache.DrawRoll(B.Canvas,Rect(-100,0,220,64),Rect(0,0,320,64),Midi,1,10+I,144,clBlack,clRed);
    Check((Cache.BitmapCount<=128) and (Cache.MidiDecodeCount=DecodeM),'Zoom/scroll/DPI cache unbounded or reparsed');
    Stamp := TFile.GetLastWriteTimeUtc(MidiPath); Rev := Midi.Revision; WriteMidi(MidiPath,7); TFile.SetLastWriteTimeUtc(MidiPath,Stamp+1/86400);
    Cache.Poll(True); Check((Midi.Revision<>Rev) and (Midi.Rolls=nil),'Updated MIDI kept old notes'); Await(Cache);
    Check((Midi.Rolls[1].Notes[0].Key=67) and (Cache.MidiDecodeCount=DecodeM+1),'Same-size MIDI update ignored');
    Stamp := TFile.GetLastWriteTimeUtc(PsdPath); Rev := Psd.Revision; WritePsd(PsdPath,True); TFile.SetLastWriteTimeUtc(PsdPath,Stamp+1/86400);
    Cache.Poll(True); Check((Psd.Revision<>Rev) and (Psd.Image=nil),'Updated PSD kept old image'); Await(Cache);
    Pixel := Psd.Image.ScanLine[0]; Check((Pixel[1]=128) and (Cache.PsdDecodeCount=DecodeP+1),'PSD update ignored');
    Cache.Clear; Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,MidiPath),Request(vkPsd,PsdPath)));
    Cache.Clear; Await(Cache); Check(Cache.Find(vkPsd,PsdPath)=nil,'Cancelled old generation retained');
    // Replace the file after its worker completes but before UI adoption.
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,MidiPath)));
    Midi := Cache.Find(vkMidi,MidiPath); Deadline := GetTickCount64+10000;
    while not Midi.MidiJob.Done do begin Sleep(1); Check(GetTickCount64<Deadline,'Stale-generation worker timeout'); end;
    Stamp := TFile.GetLastWriteTimeUtc(MidiPath); WriteMidi(MidiPath,3); TFile.SetLastWriteTimeUtc(MidiPath,Stamp+1/86400);
    Cache.Poll(False); Check(Midi.Rolls=nil,'Completed stale MIDI adopted after file replacement'); Await(Cache);
    Check(Midi.Rolls[1].Notes[0].Key=63,'New MIDI generation was replaced by old notes');
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,MidiPath),Request(vkPsd,PsdPath)));
    Writeln('VISUAL_CACHE_REAL_TEMPO_TRACK_NOTES_PSD_ALPHA_ASPECT_SHARED_100_PAINT_ZOOM_DPI_LRU_FILE_UPDATES_CANCEL_OK');
  finally B.Free; Cache.Free; end;
end;
procedure WhiteBounds(B: TBitmap; X: Integer; out Top,Bottom: Integer);
var Y: Integer;
begin
  Top := B.Height; Bottom := -1;
  for Y := 0 to B.Height-1 do if ColorToRGB(B.Canvas.Pixels[X,Y])=ColorToRGB(clWhite) then begin Top := Min(Top,Y); Bottom := Max(Bottom,Y); end;
end;
procedure TestPitchRange(const Root: string);
const Heights: array[0..6] of Integer = (1,2,3,8,26,39,64);
var Cache: TMusicStudioVisualCache; Source: TMusicStudioVisualSource; B: TBitmap; Path: string; Roll: TMusicStudioRollTrack;
  Track,H,PPI,Top,Bottom,OtherTop,OtherBottom,I,Decode,Raster,Low,High,Span: Integer; Stamp: TDateTime;
begin
  Path := TPath.Combine(Root,'pitch-range.mid'); WritePitchMidi(Path);
  Cache := TMusicStudioVisualCache.Create; B := TBitmap.Create;
  try
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request(vkMidi,Path))); Await(Cache); Source := Cache.Find(vkMidi,Path);
    Check((Source.Rolls[1].Lowest=60) and (Source.Rolls[1].Highest=60) and (Source.Rolls[1].PitchSpan=5),'Single note range not precomputed');
    Check((Source.Rolls[2].PitchLow=0) and (Source.Rolls[2].PitchHigh=4) and
      (Source.Rolls[3].PitchLow=123) and (Source.Rolls[3].PitchHigh=127),'MIDI edge range not fitted');
    Check((Source.Rolls[4].Lowest=0) and (Source.Rolls[4].Highest=127) and (Source.Rolls[4].PitchSpan=128),'Whole-track wide range wrong');
    Check((Source.Rolls[5].Lowest=60) and (Source.Rolls[5].Highest=61) and (Source.Rolls[5].PitchSpan=5),'Narrow range wrong');
    Check((Cache.MidiMessage(Source,0)='音符なし') and (Source.Rolls[0].PitchSpan>0),'Empty range divided by zero');
    for PPI in TArray<Integer>.Create(96,144) do for H in Heights do for Track := 1 to 5 do begin
      B.SetSize(340,H); Cache.DrawRoll(B.Canvas,Rect(0,0,340,H),Rect(0,0,340,H),Source,Track,160,PPI,clBlack,clWhite);
      WhiteBounds(B,40,Top,Bottom); Check((Top>=0) and (Bottom>=Top) and (Bottom<H),'Note escaped short object height');
      if H>=8 then Check((Top>0) and (Bottom<H-1),'Edge note lost vertical margin');
      if Track=4 then begin
        WhiteBounds(B,100,OtherTop,OtherBottom);
        if H>=8 then Check((OtherTop<Top) and (OtherBottom<Bottom),'High key is not above low key');
        WhiteBounds(B,280,OtherTop,OtherBottom); Check((Top=OtherTop) and (Bottom=OtherBottom),'Pitch scale changed across tiles');
        Cache.DrawRoll(B.Canvas,Rect(-256,0,84,H),Rect(0,0,84,H),Source,Track,160,PPI,clBlack,clWhite);
        WhiteBounds(B,24,OtherTop,OtherBottom); Check((Top=OtherTop) and (Bottom=OtherBottom),'Pitch jumped on horizontal scroll');
      end;
      if (H=26) and (PPI=96) and (Track=1) then Check((Bottom-Top+1>=4) and (Bottom-Top+1<13),'Single note too thin or too thick');
      if (H=26) and (PPI=96) and (Track=4) then Check(Bottom-Top+1>=2,'Wide range note too thin');
    end;
    B.SetSize(340,26); Cache.DrawRoll(B.Canvas,Rect(0,0,340,26),Rect(0,0,340,26),Source,5,160,96,clBlack,clWhite);
    Roll := Source.Rolls[5]; Low := Roll.PitchLow; High := Roll.PitchHigh; Span := Roll.PitchSpan;
    Decode := Cache.MidiDecodeCount; Raster := Cache.RasterCount;
    for I := 1 to 100 do Cache.DrawRoll(B.Canvas,Rect(0,0,340,26),Rect(0,0,340,26),Source,5,160,96,clBlack,clWhite);
    Check((Cache.MidiDecodeCount=Decode) and (Cache.RasterCount=Raster) and
      (Roll.PitchLow=Low) and (Roll.PitchHigh=High) and (Roll.PitchSpan=Span),'Paint recalculated pitch range');
    Cache.DrawRoll(B.Canvas,Rect(0,0,340,0),Rect(0,0,340,26),Source,5,160,96,clBlack,clWhite);
    Check(Cache.RasterCount=Raster,'Zero-height object rasterized');
    Stamp := TFile.GetLastWriteTimeUtc(Path); WritePitchMidi(Path,True); TFile.SetLastWriteTimeUtc(Path,Stamp+1/86400);
    Cache.Poll(True); Check(Source.Rolls=nil,'File update retained old range'); Await(Cache);
    Check((Source.Rolls[1].Lowest=68) and (Source.Rolls[1].PitchLow=66) and (Source.Rolls[1].PitchHigh=70),'Updated pitch range stale');
    Writeln('PIANO_CACHED_MIN_MAX_FIT_SINGLE_NARROW_EMPTY_KEYS0_127_WIDE_SHORT_HEIGHT_TILE_SCROLL_144DPI_100_PAINT_UPDATE_OK');
  finally B.Free; Cache.Free; end;
end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; P: TPngImage;
begin
  F.Show;
  // Start-Process -WindowStyle Hidden can override the process's first Show.
  // Make this test-owned VCL form visible before owner-drawn button capture.
  if not IsWindowVisible(F.Handle) then begin F.Hide; F.Show; end;
  F.ClientWidth := F.ClientWidth+1; F.ClientWidth := F.ClientWidth-1;
  Application.ProcessMessages; F.Repaint; F.Update; B := F.GetFormImage; P := TPngImage.Create;
  try P.Assign(B); P.SaveToFile(Path); finally P.Free; B.Free; end;
end;
procedure TestGUI(const Root: string);
var F: TFormMusicStudioSettings; P: TMusicStudioPattern; Text,ErrorText,MidiPath,PsdPath,Before,TrackID: string;
  View: TVisualViewAccess; I,MCount,PCount,RCount: Integer; R,After: TRect; Obj: TJSONObject; Tracks: TJSONArray; First: TJSONValue;
  SingingSlot: Integer;
  procedure AwaitPreview(Count: Integer);
  var Deadline: UInt64;
  begin
    Deadline := GetTickCount64+10000;
    repeat
      F.Preview.SceneCache.PollResults; Application.ProcessMessages;
      if (F.Preview.SceneCache.ActiveLoadJobs=0) and (F.Preview.SceneCache.ActiveRenderJobs=0) and (F.Preview.ImageCount>=Count) then Exit;
      Check(GetTickCount64<Deadline,'Layer scene preview timeout'); Sleep(2);
    until False;
  end;
begin
  MidiPath := TPath.Combine(Root,'visual-tempo.mid'); PsdPath := TPath.Combine(Root,'visual-layers.psd'); WriteMidi(MidiPath); WriteLayeredTestPSD(PsdPath);
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Root,'visual-library'); F.LoadDocument('');
    for I := 0 to 2 do begin
      F.Document.AddSinging; P := F.Document.PatternAt(I); P.FilePath := MidiPath;
      if I=0 then begin P.SourceTrack := 1; P.Name := '歌唱 / 高音'; end
      else if I=1 then begin P.SourceTrack := 2; P.Name := '同MIDI / 低音'; end
      else begin P.SourceTrack := 0; P.Name := '音符なし'; end;
      P.Duration := 1.5; F.Document.UpdatePattern(P);
    end;
    F.Document.AddAudio; P := F.Document.PatternAt(3); P.FilePath := TPath.Combine(Root,'stage1-demo.wav'); P.Duration := 12; F.Document.UpdatePattern(P);
    for I := 0 to 1 do begin
      F.Document.AddTrack('psd'); F.Document.UpdateTrack(I,'PSDキャラ '+IntToStr(I+1),'#C78AE8',PsdPath);
      SingingSlot := TestSlotIndex(F.Document,I,'singing');
      P := F.Document.PatternAt(I); Check(F.Document.AddPlacement(I,SingingSlot,P.ID,0,1.5,ErrorText),ErrorText);
      Check(F.Document.AddPlacement(I,SingingSlot,P.ID,3,4,ErrorText),ErrorText);
    end;
    P := F.Document.PatternAt(2); Check(F.Document.AddPlacement(0,TestSlotIndex(F.Document,0,'singing'),P.ID,8,3,ErrorText),ErrorText);
    F.Document.AddTrack('audio'); P := F.Document.PatternAt(3); Check(F.Document.AddPlacement(2,0,P.ID,0,12,ErrorText),ErrorText);
    F.Document.AddTrack('psd');
    Check(F.Document.TrySave(Text,ErrorText),ErrorText); TFile.WriteAllText(TPath.Combine(Root,'piano-psd-demo.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text); F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
    View := TVisualViewAccess(F.TimelineBox); Await(View.VisualCache); AwaitPreview(2);
    Check((View.WaveCache.DecodeCount=0) and not F.Preview.AudioEngineAllocated,'Visual GUI invoked audio');
    Check((View.VisualCache.MidiDecodeCount=1) and (View.VisualCache.PsdDecodeCount=0) and (F.Preview.SceneCache.LoadCount=1),'Preview/timeline duplicated asset parsing');
    SingingSlot := TestSlotIndex(F.Document,0,'singing'); View.SelectSlot(0,SingingSlot); Capture(F,TPath.Combine(Root,'piano-psd-expanded.png'));
    MCount := View.VisualCache.MidiDecodeCount; PCount := F.Preview.SceneCache.LoadCount; RCount := View.VisualCache.RasterCount;
    for I := 1 to 100 do begin View.Invalidate; View.Update; end;
    Check((View.VisualCache.RasterCount=RCount) and (View.VisualCache.MidiDecodeCount=MCount) and
      (F.Preview.SceneCache.LoadCount=PCount),'GUI paint100 reanalysed/regenerated');
    View.ToggleTrack(0); Capture(F,TPath.Combine(Root,'piano-psd-collapsed.png'));
    Check(IsRectEmpty(View.TrackThumbnailRect(0)),'collapsed parent retained PSD slot thumbnail');
    View.ToggleTrack(0);
    R := View.TrackThumbnailRect(0); View.ScrollTo(5); After := View.TrackThumbnailRect(0);
    Check((R.Left=After.Left) and (R.Top=After.Top),'PSD thumbnail moved with horizontal scroll');
    Capture(F,TPath.Combine(Root,'piano-psd-fixed-scroll.png')); View.ScrollTo(0);
    View.SelectTrack(1); View.SelectTrack(0); View.SetZoom(120); View.Update; View.SetZoom(40);
    Check((View.VisualCache.MidiDecodeCount=MCount) and (F.Preview.SceneCache.LoadCount=PCount),'Selection/zoom reparsed source');
    View.SelectSlot(0,SingingSlot); F.ClientWidth := 1000; F.ClientHeight := 562; Capture(F,TPath.Combine(Root,'piano-psd-minimum.png'));
    View.SelectSlot(1,TestSlotIndex(F.Document,1,'psd'));
    View.ScrollVerticalTo(0);
    R := View.TrackThumbnailRect(1); View.ScrollVerticalTo(100); After := View.TrackThumbnailRect(1);
    Check((R.Left=After.Left) and (After.Top=R.Top-100),'PSD thumbnail did not follow vertical track row');
    Capture(F,TPath.Combine(Root,'piano-psd-vertical-scroll.png')); View.ScrollVerticalTo(0);
    Check(F.Document.TrySave(Before,ErrorText),ErrorText); TrackID := F.Document.TrackAt(0).ID;
    Obj := TJSONObject.ParseJSONValue(Before) as TJSONObject;
    try Tracks := TJSONArray(Obj.GetValue('tracks')); Check(Tracks.Count=4,'reorder track array count'); First := Tracks.Remove(0); Tracks.AddElement(First); F.LoadDocument(Obj.ToJSON); finally Obj.Free; end;
    Await(View.VisualCache); AwaitPreview(2); Check(F.Document.TrackAt(3).ID=TrackID,'Reordered track ID lost');
    Check(Assigned(F.Preview.SceneCache.ImageForTrack(3)),'Thumbnail not linked after track reorder');
    F.LoadDocument(Before); Await(View.VisualCache); AwaitPreview(2); View.SelectSlot(0,SingingSlot);
    F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    Check((View.CurrentPPI=144) and (View.TrackThumbnailRect(0).Left>MulDiv(100,144,96)),'DPI header geometry overlaps name');
    Capture(F,TPath.Combine(Root,'piano-psd-dpi144.png'));
    F.Document.RemoveTrack(0); View.Refresh; F.Preview.Bind(F.Document); Await(View.VisualCache); AwaitPreview(1);
    Check(Assigned(F.Preview.SceneCache.ImageForTrack(0)),'Deleting one track removed shared PSD');
    F.LoadDocument(''); Await(View.VisualCache); AwaitPreview(0); Check(F.Preview.SceneCache.ImageForTrack(0)=nil,'JSON switch retained old PSD');
    F.LoadDocument(Text); F.Close;
    Writeln('GUI_PIANO_ROLL_PSD_FIXED_HEADER_SHARED_PREVIEW_100_PAINT_COLLAPSE_RESTORE_ZOOM_SELECT_REORDER_DELETE_JSON_MINIMUM_144DPI_CLOSE_OK');
  finally F.Free; end;
end;
procedure TestPitchGUI(const Root: string);
const Names: array[0..5] of string = ('単音60','最低音0','最高音127','全音域0～127','狭音域60/61','音符なし');
var F: TFormMusicStudioSettings; P: TMusicStudioPattern; I,Decode: Integer; Text,ErrorText,Path,Before: string;
  View: TVisualViewAccess; Slots: array[0..5] of Integer;
begin
  Path := TPath.Combine(Root,'pitch-range.mid'); WritePitchMidi(Path);
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Root,'pitch-library'); F.LoadDocument(''); F.Document.AddTrack('psd');
    for I := 0 to 5 do begin
      F.Document.AddSinging; P := F.Document.PatternAt(I); P.Name := Names[I]; P.FilePath := Path;
      if I=5 then P.SourceTrack := 0 else P.SourceTrack := I+1;
      P.Duration := 2; if I=4 then P.Color := '#A6CB55'; F.Document.UpdatePattern(P);
      if I=0 then Slots[I] := TestSlotIndex(F.Document,0,'singing') else Slots[I] := F.Document.AddSlot(0,'singing');
      Check(F.Document.AddPlacement(0,Slots[I],P.ID,0,2,ErrorText),ErrorText);
      Check(F.Document.AddPlacement(0,Slots[I],P.ID,4,2,ErrorText),ErrorText);
    end;
    Check(F.Document.TrySave(Text,ErrorText),ErrorText); TFile.WriteAllText(TPath.Combine(Root,'pitch-range-demo.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text); F.ClientHeight := 950; F.Show; Application.ProcessMessages;
    View := TVisualViewAccess(F.TimelineBox); Await(View.VisualCache); View.SelectSlot(0,Slots[0]);
    Check(View.VisualCache.MidiDecodeCount=1,'Pitch range preview duplicated MIDI parsing');
    Capture(F,TPath.Combine(Root,'pitch-range-expanded.png')); Decode := View.VisualCache.MidiDecodeCount;
    View.ToggleTrack(0); Capture(F,TPath.Combine(Root,'pitch-range-collapsed.png'));
    View.SelectSlot(0,Slots[4]); P := F.Document.PatternAt(4); P.SourceTrack := 1; F.Document.UpdatePattern(P); View.Refresh; View.Update;
    Check((View.VisualCache.MidiDecodeCount=Decode) and (View.VisualCache.Find(vkMidi,Path).Rolls[1].PitchSpan=5),'Track selection reparsed or kept wrong range');
    P.SourceTrack := 5; F.Document.UpdatePattern(P); View.Refresh;
    Check(F.Document.TrySave(Before,ErrorText),ErrorText); Check(Before=Text,'Rendering or track switch altered persisted data');
    F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    Capture(F,TPath.Combine(Root,'pitch-range-dpi144.png'));
    Writeln('GUI_PITCH_FIT_SINGLE_NARROW_EDGE_WIDE_EMPTY_FOLDED_SELECTED_TRACK_144DPI_JSON_UNCHANGED_OK');
  finally F.Free; end;
end;
procedure RunVisualCacheChecks(const Root: string);
begin TestCache(Root); TestPitchRange(Root); TestGUI(Root); TestPitchGUI(Root); end;
end.
