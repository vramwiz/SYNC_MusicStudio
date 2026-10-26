unit SYNC_MusicStudio_PhraseRollChecks;
// Real MIDI worker and integrated singing clips, with independent local-pitch pixel checks. No audio.
interface
procedure RunDarkScrollChecks(const Root: string);
procedure RunSingingGestureChecks(const Root: string);
procedure RunLyricTimelineChecks(const Root: string);
procedure RunPhraseRollChecks(const Root: string);
implementation
uses SYNC_MusicStudio_DarkScrollBar, System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils, System.Hash,
  System.Generics.Collections, System.Generics.Defaults, Winapi.Windows, Winapi.Messages,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_TestHelpers;
type
  TNoteSpec = record StartTick,EndTick,Key: Integer; end;
  TEvent = record Tick,Order,Key: Integer; Ending: Boolean; end;
const
  Notes: array[0..18] of TNoteSpec = (
    (StartTick:0;EndTick:600;Key:48),(StartTick:480;EndTick:960;Key:52),
    (StartTick:900;EndTick:1200;Key:50),(StartTick:1200;EndTick:2160;Key:49),
    (StartTick:2400;EndTick:2880;Key:84),(StartTick:2880;EndTick:3360;Key:86),
    (StartTick:3360;EndTick:3840;Key:85),(StartTick:3841;EndTick:4320;Key:127),
    (StartTick:4800;EndTick:5280;Key:0),
    (StartTick:5760;EndTick:6240;Key:60),(StartTick:5760;EndTick:6240;Key:64),
    (StartTick:5760;EndTick:6240;Key:67),(StartTick:6240;EndTick:6720;Key:62),
    (StartTick:7200;EndTick:9600;Key:70),(StartTick:7440;EndTick:7680;Key:72),
    (StartTick:8160;EndTick:8640;Key:74),(StartTick:9600;EndTick:10080;Key:71),
    (StartTick:10560;EndTick:10800;Key:70),(StartTick:10801;EndTick:11040;Key:72));
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Phrase roll: '+Message); end;
procedure WriteMidi(const Path: string; Shift: Integer = 0);
var FileData,Body: TMemoryStream; Events: TList<TEvent>; E: TEvent; I,T,LastTick: Integer;
  procedure ByteTo(S: TStream; Value: Byte);
  begin S.WriteBuffer(Value,1); end;
  procedure Big32(S: TStream; Value: Cardinal);
  begin ByteTo(S,Byte(Value shr 24)); ByteTo(S,Byte((Value shr 16) and $FF)); ByteTo(S,Byte((Value shr 8) and $FF)); ByteTo(S,Byte(Value and $FF)); end;
  procedure VLQ(Value: Cardinal);
  var Data: array[0..3] of Byte; J: Integer;
  begin J := 3; Data[J] := Byte(Value and $7F); Value := Value shr 7;
    while Value>0 do begin Dec(J); Data[J] := Byte(Value and $7F) or $80; Value := Value shr 7; end;
    Body.WriteBuffer(Data[J],4-J);
  end;
begin
  FileData := TMemoryStream.Create; Body := TMemoryStream.Create; Events := TList<TEvent>.Create;
  try
    Big32(FileData,$4D546864); Big32(FileData,6); ByteTo(FileData,0); ByteTo(FileData,1);
    ByteTo(FileData,0); ByteTo(FileData,2); ByteTo(FileData,1); ByteTo(FileData,$E0);
    for T := 0 to 1 do begin
      Body.Clear; Events.Clear;
      for I := 0 to High(Notes) do begin
        E.Tick := Notes[I].StartTick; E.Order := I; E.Key := Notes[I].Key;
        if T=1 then E.Key := 40+I mod 5 else if (E.Key>0) and (E.Key<127) then Inc(E.Key,Shift);
        E.Ending := False; Events.Add(E); E.Tick := Notes[I].EndTick; E.Ending := True; Events.Add(E);
      end;
      Events.Sort(TComparer<TEvent>.Construct(function(const A,B: TEvent): Integer
        begin Result := CompareValue(A.Tick,B.Tick); if Result=0 then begin
          Result := Ord(B.Ending)-Ord(A.Ending); if Result=0 then Result := CompareValue(A.Order,B.Order); end; end));
      LastTick := 0;
      for E in Events do begin
        VLQ(Cardinal(E.Tick-LastTick)); LastTick := E.Tick;
        if E.Ending then ByteTo(Body,$80) else begin
          ByteTo(Body,$FF); ByteTo(Body,5); ByteTo(Body,3); ByteTo(Body,$E3); ByteTo(Body,$81); ByteTo(Body,$82);
          ByteTo(Body,0); ByteTo(Body,$90);
        end;
        ByteTo(Body,Byte(E.Key)); if E.Ending then ByteTo(Body,0) else ByteTo(Body,100);
      end;
      ByteTo(Body,0); ByteTo(Body,$FF); ByteTo(Body,$2F); ByteTo(Body,0);
      Big32(FileData,$4D54726B); Big32(FileData,Cardinal(Body.Size)); Body.Position := 0; FileData.CopyFrom(Body,Body.Size);
    end;
    FileData.SaveToFile(Path);
  finally Events.Free; Body.Free; FileData.Free; end;
end;
procedure Await(Cache: TMusicStudioVisualCache);
var Limit: UInt64;
begin
  Limit := GetTickCount64+10000;
  repeat Cache.Poll; Application.ProcessMessages; if Cache.ActiveJobs=0 then Exit; Sleep(2); until GetTickCount64>Limit;
  Check(False,'worker timeout');
end;
procedure WhiteBounds(B: TBitmap; X: Integer; out Top,Bottom: Integer);
var Y: Integer;
begin Top := -1; Bottom := -1; for Y := 0 to B.Height-1 do if ColorToRGB(B.Canvas.Pixels[X,Y])=ColorToRGB(clWhite) then begin
  if Top<0 then Top := Y; Bottom := Y; end;
end;
procedure SavePNG(B: TBitmap; const Path: string);
var P: TPngImage;
begin P := TPngImage.Create; try P.Assign(B); P.SaveToFile(Path); finally P.Free; end; end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; DC: HDC;
begin F.Update; B := TBitmap.Create; try B.SetSize(F.ClientWidth,F.ClientHeight); DC := GetDC(F.Handle);
  try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'native capture'); finally ReleaseDC(F.Handle,DC); end;
  SavePNG(B,Path); finally B.Free; end;
end;
procedure TestCache(const Root,Path: string);
var Cache: TMusicStudioVisualCache; Source: TMusicStudioVisualSource; Roll: TMusicStudioRollTrack;
  Request: TMusicStudioVisualRequest; B,C: TBitmap; I,H,PPI,T0,T1,B0,B1,Decode,Raster,Revision: Integer;
  BeforeHash: string; Stamp: TDateTime; GroupPointer: Pointer; Scale: Double;
begin
  Cache := TMusicStudioVisualCache.Create; B := TBitmap.Create; C := TBitmap.Create;
  BeforeHash := THashSHA2.GetHashStringFromFile(Path);
  try
    Request.Kind := vkMidi; Request.Path := Path; Request.Visible := True; Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request)); Await(Cache);
    Source := Cache.Find(vkMidi,Path); Check(Cache.MidiMessage(Source,0)='',Source.Message); Roll := Source.Rolls[0];
    Check(Length(Roll.Notes)=Length(Notes),'note data changed'); Check(Length(Roll.Phrases)=8,'rests/continuity/chord grouping wrong');
    Check((Roll.Phrases[0].Lowest=48) and (Roll.Phrases[0].Highest=52) and (Roll.Phrases[0].PitchSpan=7),'low phrase range');
    Check((Roll.Phrases[1].Lowest=84) and (Roll.Phrases[1].Highest=86) and (Roll.Phrases[1].PitchSpan=5),'high phrase range');
    Check((Roll.Phrases[2].PitchLow=123) and (Roll.Phrases[2].PitchHigh=127) and
      (Roll.Phrases[3].PitchLow=0) and (Roll.Phrases[3].PitchHigh=4),'single/edge ranges');
    Check((Roll.Phrases[4].Lowest=60) and (Roll.Phrases[4].Highest=67) and (Roll.Phrases[4].LastNote-Roll.Phrases[4].FirstNote=3),'overlapping chord split');
    Check(SameValue(Roll.Phrases[5].StartSeconds,7.5) and SameValue(Roll.Phrases[5].EndSeconds,10.5) and
      (Roll.Phrases[5].Highest=74),'sustained bridge split');
    Check((Roll.NotePhrases[17]=6) and (Roll.NotePhrases[18]=7),'one-tick real rest discarded');
    for I := 0 to High(Notes) do Check(SameValue(Roll.Notes[I].StartSeconds,Notes[I].StartTick/960) and
      SameValue(Roll.Notes[I].EndSeconds,Notes[I].EndTick/960),'note timing modified');
    GroupPointer := @Roll.Phrases[0]; Decode := Cache.MidiDecodeCount;
    for PPI in TArray<Integer>.Create(96,144) do for H in TArray<Integer>.Create(1,2,8,26,64) do begin
      B.SetSize(1840,H); Cache.DrawRoll(B.Canvas,Rect(0,0,1840,H),Rect(0,0,1840,H),Source,0,160,PPI,clBlack,clWhite);
      WhiteBounds(B,32,T0,B0); WhiteBounds(B,120,T1,B1);
      Check((T0>=0) and (B0<H) and (T1>=0) and (B1<H),'notes outside short body');
      if H>=26 then Check((T0-T1>H div 3) and (B0-B1>H div 3),'low phrase flattened by global range');
      WhiteBounds(B,420,T0,B0); WhiteBounds(B,500,T1,B1);
      if H>=26 then Check((T0-T1>H div 4) and (B0-B1>H div 4),'high phrase intervals flattened');
      WhiteBounds(B,1500,T0,B0); WhiteBounds(B,1540,T1,B1); Check((T0=T1) and (B0=B1),'pitch jumps across tile boundary');
      C.SetSize(474,H); Cache.DrawRoll(C.Canvas,Rect(-1366,0,474,H),Rect(0,0,474,H),Source,0,160,PPI,clBlack,clWhite);
      WhiteBounds(C,134,T1,B1); Check((T0=T1) and (B0=B1),'scroll changed phrase range');
      // Clipping halfway through a phrase cannot refit the remaining notes.
      C.SetSize(160,H); Cache.DrawRoll(C.Canvas,Rect(0,0,160,H),Rect(0,0,160,H),Source,0,160,PPI,clBlack,clWhite);
      WhiteBounds(B,120,T0,B0); WhiteBounds(C,120,T1,B1); Check((T0=T1) and (B0=B1),'clip cutoff changed phrase pitch');
    end;
    B.SetSize(1840,64); Cache.DrawRoll(B.Canvas,Rect(0,0,1840,64),Rect(0,0,1840,64),Source,0,160,96,clBlack,clWhite);
    SavePNG(B,TPath.Combine(Root,'phrase-roll-pixels.png')); Raster := Cache.RasterCount;
    for I := 1 to 100 do Cache.DrawRoll(B.Canvas,Rect(0,0,1840,64),Rect(0,0,1840,64),Source,0,160,96,clBlack,clWhite);
    Check((Cache.RasterCount=Raster) and (Cache.MidiDecodeCount=Decode) and (@Roll.Phrases[0]=GroupPointer),'paint rebuilt range/cache');
    for Scale in TArray<Double>.Create(40,96,256) do begin
      B.SetSize(Ceil(11.5*Scale),64); Cache.DrawRoll(B.Canvas,Rect(0,0,B.Width,64),Rect(0,0,B.Width,64),Source,0,Scale,96,clBlack,clWhite);
      WhiteBounds(B,Round(0.2*Scale),T0,B0); WhiteBounds(B,Round(0.75*Scale),T1,B1); Check(T0-T1>20,'zoom changed phrase fit');
    end;
    Cache.DrawRoll(B.Canvas,Rect(0,0,B.Width,64),Rect(0,0,B.Width,64),Source,1,160,96,clBlack,clWhite);
    Check((Source.Rolls[1].Phrases[0].Lowest=40) and (Source.Rolls[1].Phrases[0].Highest=43) and (Cache.MidiDecodeCount=Decode),'track switch retained other range or reparsed');
    Check(THashSHA2.GetHashStringFromFile(Path)=BeforeHash,'draw changed MIDI');
    Stamp := TFile.GetLastWriteTimeUtc(Path); Revision := Source.Revision; WriteMidi(Path,4); TFile.SetLastWriteTimeUtc(Path,Stamp+1/86400);
    Cache.Poll(True); Check((Source.Rolls=nil) and (Source.Revision<>Revision),'updated source kept phrase ranges'); Await(Cache);
    Check((Source.Rolls[0].Phrases[0].Lowest=52) and (Cache.MidiDecodeCount=Decode+1),'new generation range stale');
    Cache.Clear; Await(Cache); Check(Cache.Find(vkMidi,Path)=nil,'cleared source still borrowed');
    WriteMidi(Path); Check(THashSHA2.GetHashStringFromFile(Path)=BeforeHash,'fixture restore differs');
    Writeln('PHRASE_ROLL_REAL_MIDI_RESTS_CONTINUOUS_CHORD_SUSTAIN_BRIDGE_SHORT_REST_SINGLE_EDGES_LOCAL_INTERVAL_PIXELS_CLIP_TILE_SCROLL_ZOOM_DPI100_CACHE_TRACK_SOURCE_GENERATION_OK');
  finally C.Free; B.Free; Cache.Free; end;
end;
procedure TestGUI(const Root,Path: string);
var F: TFormMusicStudioSettings; P: TMusicStudioPattern; I,Track,Slot,Decode,Raster: Integer;
  Text,After,Error,BeforeHash: string; Work: TRect;
  procedure FitWindow;
  begin
    Work := F.Monitor.WorkareaRect; F.Position := poDesigned;
    F.Width := Min(F.Width,Work.Width-8); F.Height := Min(F.Height,Work.Height-8);
    F.Left := Work.Left+(Work.Width-F.Width) div 2; F.Top := Work.Top+(Work.Height-F.Height) div 2;
    F.Update; Application.ProcessMessages;
  end;
begin
  F := TFormMusicStudioSettings.Create(nil); BeforeHash := THashSHA2.GetHashStringFromFile(Path);
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Root,'isolated-library'); F.LoadDocument(''); Track := F.Document.AddTrack('psd');
    for I := 0 to 1 do begin
      F.Document.AddSinging; P := F.Document.PatternAt(I); P.Name := 'フレーズ音域 '+IntToStr(I+1); P.FilePath := Path; P.SourceTrack := I; P.Duration := 11.5;
      if I=1 then P.Color := '#8ECC7C'; F.Document.UpdatePattern(P);
      if I=0 then Slot := TestSlotIndex(F.Document,Track,'singing') else Slot := F.Document.AddSlot(Track,'singing');
      Check(F.Document.AddPlacement(Track,Slot,P.ID,0,11.5,Error),Error);
      Check(F.Document.AddPlacement(Track,Slot,P.ID,13,3.2,Error),Error);
    end;
    Check(F.Document.TrySave(Text,Error),Error); TFile.WriteAllText(TPath.Combine(Root,'phrase-roll-demo.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text); F.ClientHeight := 880; F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); FitWindow; Await(F.TimelineBox.VisualCache);
    F.TimelineBox.SelectSlot(Track,TestSlotIndex(F.Document,Track,'singing'));
    F.TimelineBox.Repaint; Capture(F,TPath.Combine(Root,'phrase-roll-integrated-96.png'));
    Decode := F.TimelineBox.VisualCache.MidiDecodeCount; Raster := F.TimelineBox.VisualCache.RasterCount;
    for I := 1 to 100 do F.TimelineBox.Repaint;
    Check((F.TimelineBox.VisualCache.MidiDecodeCount=Decode) and (F.TimelineBox.VisualCache.RasterCount=Raster),'integrated paints reanalyzed/rasterized');
    P := F.Document.PatternAt(0); P.SourceTrack := 1; F.Document.UpdatePattern(P); F.TimelineBox.Refresh; F.TimelineBox.Repaint;
    Capture(F,TPath.Combine(Root,'phrase-roll-integrated-track-switch.png'));
    Check(F.TimelineBox.VisualCache.MidiDecodeCount=Decode,'selected MIDI track reparsed');
    P.SourceTrack := 0; F.Document.UpdatePattern(P); F.TimelineBox.Refresh;
    F.TimelineBox.ToggleTrack(Track); F.TimelineBox.Repaint; Capture(F,TPath.Combine(Root,'phrase-roll-integrated-collapsed.png'));
    F.TimelineBox.ToggleTrack(Track); F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    FitWindow;
    // At the physical desktop height, scroll the full singing body into view.
    for I := 0 to F.TimelineBox.ControlCount-1 do
      if (F.TimelineBox.Controls[I] is TMusicStudioDarkScrollBar) and (TMusicStudioDarkScrollBar(F.TimelineBox.Controls[I]).Kind=sbVertical) then
        TMusicStudioDarkScrollBar(F.TimelineBox.Controls[I]).Position := 120;
    F.TimelineBox.Repaint; Capture(F,TPath.Combine(Root,'phrase-roll-integrated-144.png'));
    Check(F.Document.TrySave(After,Error) and (After=Text),'view altered project JSON');
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio started');
    Check(THashSHA2.GetHashStringFromFile(Path)=BeforeHash,'GUI modified MIDI');
    Writeln('PHRASE_ROLL_INTEGRATED_SINGING_CLIPS_FOLDED_96_144_100_REPAINT_JSON_MIDI_UNCHANGED_NO_AUDIO_OK');
  finally F.Free; end;
end;
procedure RunPhraseRollChecks(const Root: string);
var Dir,Path: string; G: TGUID;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'phrase-roll-'+GUIDToString(G)); ForceDirectories(Dir);
  Path := TPath.Combine(Dir,'phrases.mid'); WriteMidi(Path); TestCache(Dir,Path); TestGUI(Dir,Path);
end;
procedure RunLyricTimelineChecks(const Root: string);
var Cache: TMusicStudioVisualCache; Source: TMusicStudioVisualSource; Request: TMusicStudioVisualRequest;
  Roll: TMusicStudioRollTrack; Full,Crop,Other: TBitmap; Path: string; I,X,Y,Top,Bottom,TextPixels,Count: Integer;
  procedure Draw(B: TBitmap; Left,Width: Integer; Transparent: Boolean = False);
  begin
    B.SetSize(Width,42); B.Canvas.Brush.Color := clNavy; B.Canvas.FillRect(Rect(0,0,Width,42));
    Cache.DrawRoll(B.Canvas,Rect(Left,0,Left+1840,42),Rect(0,0,Width,42),Source,0,160,96,clBlack,clWhite,Transparent,True);
  end;
begin
  ForceDirectories(Root); Path := TPath.Combine(Root,'lyric-timeline.mid'); WriteMidi(Path);
  Cache := TMusicStudioVisualCache.Create; Full := TBitmap.Create; Crop := TBitmap.Create; Other := TBitmap.Create;
  try
    Request := Default(TMusicStudioVisualRequest); Request.Kind := vkMidi; Request.Path := Path; Request.Visible := True;
    Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request)); Await(Cache);
    Source := Cache.Find(vkMidi,Path); Check((Source<>nil) and (Source.Status=vsReady),'lyric MIDI not ready');
    Roll := Source.Rolls[0]; Check(Roll.Notes[0].Lyric='あ','MIDI kana not preserved');
    Roll.Notes[0].Lyric := 'ひらがな'; Roll.Notes[1].Lyric := 'カナ'; Roll.Notes[2].Lyric := '';
    Inc(Source.Revision); Draw(Full,0,1840);
    WhiteBounds(Full,70,Top,Bottom); Check((Top>0) and (Bottom<41) and (Bottom-Top+1>13),'band height must exceed text');
    for X in [410,510,810,1010,1770] do begin
      WhiteBounds(Full,X,I,Y); Check((I=Top) and (Y=Bottom),'pitch changed lyric band height');
    end;
    TextPixels := 0; for X := 2 to 55 do for Y := Top+2 to Bottom-2 do
      if ColorToRGB(Full.Canvas.Pixels[X,Y])=$00202020 then Inc(TextPixels);
    Check(TextPixels>0,'kana text missing from band');
    for X := 73 to 77 do for Y := Top+2 to Bottom-2 do
      Check(ColorToRGB(Full.Canvas.Pixels[X,Y])=ColorToRGB(clWhite),'text not left aligned');
    // A source pitch change must not affect this display mode; MIDI timing stays identical.
    for I := 0 to High(Roll.Notes) do Roll.Notes[I].Key := (Roll.Notes[I].Key+17) mod 128;
    Inc(Source.Revision); Draw(Other,0,1840);
    for Y := 0 to Full.Height-1 do for X := 0 to Full.Width-1 do
      Check(Full.Canvas.Pixels[X,Y]=Other.Canvas.Pixels[X,Y],'lyrics moved vertically with pitch');
    Draw(Crop,-231,520);
    for Y := 0 to Crop.Height-1 do for X := 0 to Crop.Width-1 do
      Check(Crop.Canvas.Pixels[X,Y]=Full.Canvas.Pixels[X+231,Y],'tile or viewport clipping moved text');
    Count := Cache.RasterCount; Draw(Other,0,1840); Check(Cache.RasterCount=Count,'repeated lyric draw rerasterized');
    Draw(Other,0,1840,True); Check(Other.Canvas.Pixels[70,0]=clNavy,'summary background not transparent');
    Check(Other.Canvas.Pixels[70,Top]=clWhite,'summary lyric band disappeared');
    TextPixels := 0; for X := 2 to 55 do for Y := Top+2 to Bottom-2 do
      if ColorToRGB(Other.Canvas.Pixels[X,Y])=$00202020 then Inc(TextPixels);
    Check(TextPixels>0,'summary text became transparent');
    SavePNG(Full,TPath.Combine(Root,'lyric-bands.png'));
    Check(Cache.MidiDecodeCount=1,'lyrics display decoded MIDI again');
    Writeln('LYRIC_TIMELINE_KANA_FIXED_HEIGHT_TIMING_LEFT_TEXT_TILE_CROP_TRANSPARENT_CACHE_NO_AUDIO_OK');
  finally Other.Free; Crop.Free; Full.Free; Cache.Free; end;
end;
procedure RunSingingGestureChecks(const Root: string);
const DOC = '{"schemaVersion":1,"previewAudio":null,"materials":[],"characters":[],"arrangementVersion":2,"patterns":[{"id":"song","kind":"singing","name":"歌唱","color":"#CC8CE0","singing":{"filePath":"","trackIndex":0,"durationSeconds":2}}],'
  +'"tracks":[{"id":"track","kind":"psd","name":"歌唱者","color":"#CC8CE0","psd":{"filePath":""},"slots":[{"id":"sing","kind":"singing","name":"歌唱","color":"#CC8CE0","order":0,"accepts":["singing"],'
  +'"clips":[{"id":"clip","patternId":"song","slotId":"sing","startSeconds":1,"lengthSeconds":2}]}]}]}';
var UI: TFormMusicStudioSettings; V: TMusicStudioArrangementView; B: TBitmap;
  X,Y,Left,Right,I,ScrollPaints: Integer; OldStart,OldLength: Double; Text,Error: string; DarkH: TMusicStudioDarkScrollBar;
  function TimeX(Seconds: Double): Integer;
  var Best,Distance: Double; K: Integer;
  begin Result := V.HeaderWidth; Best := MaxDouble;
    for K := V.HeaderWidth to V.ClientWidth-20 do begin Distance := Abs(V.SecondsAtPoint(K)-Seconds); if Distance<Best then begin Best := Distance; Result := K; end; end;
  end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin V.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure Hover(X,Y: Integer);
  begin Mouse(WM_MOUSEMOVE,X,Y); Check(V.Cursor=crSizeAll,Format('singing hover cursor=%d at %d,%d track=%d slot=%d clip=%d',[V.Cursor,X,Y,V.TrackAtPoint(X,Y),V.SlotAtPoint(X,Y),V.ClipAtPoint(X,Y)])); Check(V.EmotionResizeEdgeAt(X,Y)=0,'singing resize edge remains'); end;
  procedure CheckMarker;
  begin
    B.SetSize(V.ClientWidth,V.ClientHeight); V.PaintTo(B.Canvas,0,0);
    Check(ColorToRGB(B.Canvas.Pixels[Left,Y])=$00FFD060,'start line not at exact clip start');
    Check(ColorToRGB(B.Canvas.Pixels[Left+3,Y])<>$00FFD060,'start line is still shifted right');
  end;
begin
  ForceDirectories(Root); UI := TFormMusicStudioSettings.Create(nil); B := TBitmap.Create;
  try
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'isolated'); UI.LoadDocument(DOC); Check(UI.Document.TrackCount=1,'gesture document: '+UI.StatusLabel.Caption);
    UI.ClientWidth := 1240; UI.ClientHeight := 820; UI.Show; Application.ProcessMessages; V := UI.TimelineBox; V.SetZoom(160); DarkH := nil;
    for I := 0 to V.ControlCount-1 do if V.Controls[I] is TMusicStudioDarkScrollBar then
      if TMusicStudioDarkScrollBar(V.Controls[I]).Kind=sbHorizontal then DarkH := TMusicStudioDarkScrollBar(V.Controls[I]);
    Check(DarkH<>nil,'timeline did not use custom dark scrollbar');
    Check((GetWindowLongPtr(V.Handle,GWL_STYLE) and WS_CLIPCHILDREN)<>0,'timeline paints over child scrollbars');
    if not V.TrackExpanded(0) then V.ToggleTrack(0); V.SelectSlot(0,0);
    Left := TimeX(1); Right := TimeX(3); Y := V.SlotRowTop(0,0)+10;
    // The cursor must work before selecting this clip, throughout its rectangle.
    for I := 0 to 2 do begin case I of 0: X := Left+1; 1: X := (Left+Right) div 2; else X := Right-1; end; Hover(X,Y); end;
    V.SelectClip(0,0,0); Hover(Left+1,Y); Hover(Right-1,Y); CheckMarker;
    Mouse(WM_LBUTTONDOWN,Left+1,Y,MK_LBUTTON); Check(V.Cursor=crSizeAll,'mousedown cursor');
    Mouse(WM_LBUTTONUP,Left+1,Y); Check(V.Cursor=crSizeAll,'click release cursor');
    OldStart := UI.Document.TrackAt(0).Slots[0].Clips[0].StartSeconds; OldLength := UI.Document.TrackAt(0).Slots[0].Clips[0].LengthSeconds;
    // Dragging the former left grip now moves the complete clip and preserves its duration.
    DarkH.Update; ScrollPaints := DarkH.PaintCount;
    Mouse(WM_LBUTTONDOWN,Left+1,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,Left+81,Y,MK_LBUTTON);
    for I := 1 to 30 do begin V.Repaint; DarkH.Update; end;
    Check(DarkH.PaintCount=ScrollPaints,'clip drag repeatedly repainted scrollbar');
    Winapi.Windows.SetCursor(LoadCursor(0,IDC_ARROW));
    V.Perform(WM_SETCURSOR,V.Handle,MakeLParam(HTCLIENT,WM_MOUSEMOVE));
    Check(GetCursor=Screen.Cursors[crSizeAll],'native cursor reverted during capture');
    Winapi.Windows.SetCursor(LoadCursor(0,IDC_ARROW));
    V.Perform(WM_SETCURSOR,V.Handle,MakeLParam(HTHSCROLL,WM_MOUSEMOVE));
    Check(GetCursor=Screen.Cursors[crSizeAll],'native cursor reverted over child/nonclient');
    Mouse(WM_LBUTTONUP,Left+81,Y);
    Check(V.Cursor=crSizeAll,'drag release cursor');
    Check(UI.Document.TrackAt(0).Slots[0].Clips[0].StartSeconds>OldStart,'edge drag did not move');
    Check(SameValue(UI.Document.TrackAt(0).Slots[0].Clips[0].LengthSeconds,OldLength),'edge drag resized singing');
    UI.UndoEdit; Check(SameValue(UI.Document.TrackAt(0).Slots[0].Clips[0].StartSeconds,OldStart),'move undo');
    Left := TimeX(1); Right := TimeX(3); V.ToggleTrack(0); Y := V.TrackRowTop(0)+10;
    Hover(Left+1,Y); Hover((Left+Right) div 2,Y); Hover(Right-1,Y); CheckMarker;
    Mouse(WM_MOUSEMOVE,Right+20,Y); Check(V.Cursor=crDefault,'outside singing still move cursor');
    Check(UI.Document.TrySave(Text,Error),Error); TFile.WriteAllText(TPath.Combine(Root,'singing-move.json'),Text,TEncoding.UTF8);
    SavePNG(B,TPath.Combine(Root,'singing-start-marker.png'));
    Check(not UI.Preview.AudioEngineAllocated and (V.WaveCache.DecodeCount=0),'singing gestures used audio');
    Writeln('SINGING_MOVE_ONLY_FULL_HOVER_START_MARKER_EXACT_X_EDGE_MOVE_LENGTH_UNDO_EXPANDED_COLLAPSED_NO_AUDIO_OK');
  finally B.Free; UI.Free; end;
end;
procedure RunDarkScrollChecks(const Root: string);
var D: TForm; H,V: TMusicStudioDarkScrollBar; R: TRect; B: TBitmap; I,Count,Old: Integer;
  procedure Mouse(Bar: TMusicStudioDarkScrollBar; Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin Bar.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure Key(Bar: TMusicStudioDarkScrollBar; Value: Word);
  begin Bar.Perform(WM_KEYDOWN,Value,0); end;
begin
  ForceDirectories(Root); D := TForm.CreateNew(nil); B := TBitmap.Create;
  try
    D.ClientWidth := 420; D.ClientHeight := 240; D.Color := $00232323;
    H := TMusicStudioDarkScrollBar.Create(D); H.Parent := D; H.SetBounds(8,210,380,17);
    V := TMusicStudioDarkScrollBar.Create(D); V.Parent := D; V.Kind := sbVertical; V.SetBounds(395,8,17,195);
    H.Configure(0,1000,200,0); H.SmallChange := 10; H.LargeChange := 200;
    V.Configure(0,600,180,0); V.SmallChange := 20; V.LargeChange := 180; D.Show; Application.ProcessMessages;
    Check((GetWindowLongPtr(H.Handle,GWL_STYLE) and (WS_HSCROLL or WS_VSCROLL))=0,'native scrollbar style present');
    Check(H.Perform(WM_ERASEBKGND,0,0)=1,'scrollbar background erase');
    R := H.ThumbRect; Check((R.Width>=20) and (R.Right<H.ClientWidth),'thumb size');
    Mouse(H,WM_LBUTTONDOWN,R.CenterPoint.X,R.CenterPoint.Y,MK_LBUTTON);
    Mouse(H,WM_MOUSEMOVE,R.CenterPoint.X+80,R.CenterPoint.Y,MK_LBUTTON);
    Mouse(H,WM_LBUTTONUP,R.CenterPoint.X+80,R.CenterPoint.Y); Check(H.Position>0,'horizontal thumb drag');
    Old := H.Position; Mouse(H,WM_LBUTTONDOWN,3,8,MK_LBUTTON); Mouse(H,WM_LBUTTONUP,3,8);
    Check(H.Position=Old-10,'arrow step');
    Key(H,VK_HOME); Check(H.Position=0,'home'); Key(H,VK_NEXT); Check(H.Position=200,'page key');
    Key(H,VK_END); Check(H.Position=1000,'end'); H.Position := MaxInt; Check(H.Position=1000,'upper clamp');
    H.Configure(0,100,20,1000); Check(H.Position=100,'range clamp');
    H.Position := 0; R := H.ThumbRect; Mouse(H,WM_LBUTTONDOWN,R.Right+20,8,MK_LBUTTON); Mouse(H,WM_LBUTTONUP,R.Right+20,8);
    Check(H.Position>0,'track page click');
    R := V.ThumbRect; Mouse(V,WM_LBUTTONDOWN,R.CenterPoint.X,R.CenterPoint.Y,MK_LBUTTON);
    Mouse(V,WM_MOUSEMOVE,R.CenterPoint.X,R.CenterPoint.Y+40,MK_LBUTTON); Mouse(V,WM_LBUTTONUP,R.CenterPoint.X,R.CenterPoint.Y+40);
    Check(V.Position>0,'vertical thumb drag');
    Key(V,VK_HOME); Key(V,VK_DOWN); Check(V.Position=20,'vertical arrow key');
    R := V.ThumbRect; Mouse(V,WM_LBUTTONDOWN,R.CenterPoint.X,R.CenterPoint.Y,MK_LBUTTON); V.Perform(WM_CANCELMODE,0,0);
    Check(GetCapture<>V.Handle,'cancel retained capture');
    H.Repaint; Count := H.PaintCount; for I := 1 to 30 do H.Configure(H.Min,H.Max,H.PageSize,H.Position);
    H.Update; Check(H.PaintCount=Count,'same scroll range repaints');
    B.SetSize(H.ClientWidth,H.ClientHeight); H.PaintTo(B.Canvas,0,0);
    Check(ColorToRGB(B.Canvas.Pixels[30,0])=$00252525,'scrollbar track is not dark');
    SavePNG(B,TPath.Combine(Root,'dark-scrollbar.png'));
    H.Configure(0,0,0,0); Check(H.Position=0,'zero range'); R := H.ThumbRect; Check(R.Width=H.ClientWidth-2*H.ClientHeight,'zero range thumb');
    Writeln('DARK_SCROLL_THUMB_ARROWS_PAGE_KEYS_RANGE_CAPTURE_ERASE_SAME_VALUE_NO_REPAINT_OK');
  finally B.Free; D.Free; end;
end;
end.
