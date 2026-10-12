unit SYNC_MusicStudio_WaveCacheChecks;
// 解析回数/実サンプルの時間対応/更新/取消と、折りたたみGUIを独立して検証する。
interface
procedure RunWaveCacheChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_WaveCache, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_ArrangementView;
type
  TWaveViewAccess = class(TMusicStudioArrangementView)
    procedure Press(X,Y: Integer; Button: TMouseButton);
    procedure MoveTo(X,Y: Integer);
    procedure ReleaseAt(X,Y: Integer);
    procedure ScrollVertical(Delta: Integer);
  end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure TWaveViewAccess.Press(X,Y: Integer; Button: TMouseButton);
begin MouseDown(Button,[],X,Y); end;
procedure TWaveViewAccess.MoveTo(X,Y: Integer);
begin MouseMove([ssLeft],X,Y); end;
procedure TWaveViewAccess.ReleaseAt(X,Y: Integer);
begin MouseUp(mbLeft,[],X,Y); end;
procedure TWaveViewAccess.ScrollVertical(Delta: Integer);
begin DoMouseWheel([ssShift],Delta,ClientToScreen(Point(10,10))); end;
procedure WriteFixture(const Path: string; Silent: Boolean; Seconds: Integer = 2);
var Bytes: TBytes; I,Count: Integer;
begin
  Count := 8000*Seconds;
  Bytes := TBytes.Create(82,73,70,70,0,0,0,0,87,65,86,69,102,109,116,32,
    16,0,0,0,1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,100,97,116,97,0,0,0,0);
  SetLength(Bytes,44+Count*2); PCardinal(@Bytes[4])^ := Count*2+36; PCardinal(@Bytes[40])^ := Count*2;
  if not Silent then for I := 8000 to Count-1 do
    if Odd(I) then PSmallInt(@Bytes[44+I*2])^ := 16000 else PSmallInt(@Bytes[44+I*2])^ := -16000;
  TFile.WriteAllBytes(Path,Bytes);
end;
procedure Await(Cache: TMusicStudioWaveCache);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  repeat Cache.Poll; Application.ProcessMessages; Sleep(1);
    Check(GetTickCount64 < Deadline,Format('Wave cache jobs timeout: active=%d decode=%d discard=%d',
      [Cache.ActiveJobs,Cache.DecodeCount,Cache.DiscardCount]));
  until Cache.ActiveJobs = 0;
end;
function ColumnInk(Bitmap: TBitmap; X: Integer; Background: TColor): Integer;
var Y: Integer;
begin
  Result := 0;
  for Y := 0 to Bitmap.Height-1 do if ColorToRGB(Bitmap.Canvas.Pixels[X,Y]) <> ColorToRGB(Background) then Inc(Result);
end;
procedure TestCache(const Root: string);
var Cache: TMusicStudioWaveCache; Bitmap: TBitmap; Path,SilentPath,BrokenPath,MissingPath: string;
  Source: TMusicStudioWaveSource; Decode,Raster,Rev,I: Integer; Stamp: TDateTime;
  Paths: TArray<string>;
begin
  Path := TPath.Combine(Root,'cache-envelope.wav'); SilentPath := TPath.Combine(Root,'cache-silent.wav');
  BrokenPath := TPath.Combine(Root,'cache-broken.wav'); MissingPath := TPath.Combine(Root,'cache-missing.wav');
  WriteFixture(Path,False); WriteFixture(SilentPath,True); TFile.WriteAllText(BrokenPath,'broken');
  if TFile.Exists(MissingPath) then TFile.Delete(MissingPath);
  Paths := TArray<string>.Create(Path,UpperCase(Path),SilentPath,BrokenPath,MissingPath,'');
  Cache := TMusicStudioWaveCache.Create; Bitmap := TBitmap.Create;
  try
    Writeln('WAVE_CACHE_INITIAL_START'); Flush(Output);
    Cache.SetSources(Paths,nil); Check((Cache.ActiveJobs = 0) and (Cache.DecodeCount = 0),'Invisible source decoded');
    Cache.SetSources(Paths,Paths); Check(Cache.Find(Path).Status = wsPending,'Pending not explicit');
    Check(Cache.ActiveJobs <= 2,'Unbounded waveform workers'); Await(Cache);
    Source := Cache.Find(Path);
    Check((Source.Status = wsReady) and (Cache.Find(UpperCase(Path)) = Source),'Same source not shared');
    Check((Cache.Find(SilentPath).Status = wsSilent) and (Cache.Find(BrokenPath).Status = wsBroken) and
      (Cache.Find(MissingPath).Status = wsMissing) and (Cache.Find('').Status = wsUnselected),'Wave statuses conflated');
    Check(Cache.DecodeCount = 3,'Repeated source decoded more than once');
    Bitmap.SetSize(320,40); Bitmap.Canvas.Brush.Color := clBlack; Bitmap.Canvas.FillRect(Bitmap.Canvas.ClipRect);
    Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,80,1,96,clBlack,clWhite);
    Check((ColumnInk(Bitmap,20,clBlack) <= 1) and (ColumnInk(Bitmap,120,clBlack) > 10) and
      (ColumnInk(Bitmap,200,clBlack) = 0),'Envelope stretched or time range mismatched');
    Decode := Cache.DecodeCount; Raster := Cache.RasterCount;
    for I := 1 to 100 do Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,80,1,96,clBlack,clWhite);
    Check((Cache.DecodeCount = Decode) and (Cache.RasterCount = Raster),'Repaint regenerated cached envelope/image');
    Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,80,0,96,clBlack,clWhite);
    Check(ColumnInk(Bitmap,120,clBlack) <= 1,'Mute gain not reflected in cached image');
    Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,80,2,96,clBlack,clWhite);
    Check(ColumnInk(Bitmap,120,clBlack) > 35,'200 percent gain not reflected/clamped');
    Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,120,0.75,144,clBlack,clWhite);
    Cache.Draw(Bitmap.Canvas,Rect(-100,0,60,40),Rect(0,0,320,40),Source,80,1,96,clBlack,clWhite);
    Check(Cache.DecodeCount = Decode,'Zoom/DPI/scroll decoded again');
    for I := 1 to 180 do Cache.Draw(Bitmap.Canvas,Rect(0,0,320,40),Rect(0,0,320,40),Source,10+I/2,1,96,clBlack,clWhite);
    Check((Cache.TileCount <= 128) and (Cache.DecodeCount = Decode),'Raster cache unbounded or zoom reanalysed');
    Stamp := TFile.GetLastWriteTimeUtc(Path); Rev := Source.Revision;
    WriteFixture(Path,True); TFile.SetLastWriteTimeUtc(Path,Stamp+1/86400);
    Check(Cache.Poll(True) and (Source.Revision <> Rev) and (Length(Source.Wave) = 0),'File update retained stale wave');
    Await(Cache); Check((Source.Status = wsSilent) and (Cache.DecodeCount = Decode+1),'Same-size file update not reanalysed');
    WriteFixture(MissingPath,False); Cache.Poll(True); Await(Cache);
    Check(Cache.Find(MissingPath).Status = wsReady,'Missing file reappearance not detected');
    TFile.Delete(MissingPath); Cache.Poll(True); Check(Cache.Find(MissingPath).Status = wsMissing,'Deleted file kept old image');
    WriteFixture(Path,False,20); Cache.Poll(True); Cache.Clear;
    Cache.SetSources(TArray<string>.Create(SilentPath),TArray<string>.Create(SilentPath)); Await(Cache);
    Check((Cache.Find(Path) = nil) and (Cache.Find(SilentPath).Status = wsSilent) and
      (Cache.DiscardCount > 0),'Old generation contaminated new document');
    WriteFixture(Path,False,25); Cache.SetSources(TArray<string>.Create(Path),TArray<string>.Create(Path));
    // 解放中の未完了ジョブはTerminate/WaitForで回収。フォームへのcallbackはない。
    Writeln('WAVE_CACHE_SHARED_DECODE_REPAINT_ZOOM_DPI_VISIBLE_TILES_LIMIT_SOURCE_UPDATE_GENERATION_STATUSES_OK');
  finally Bitmap.Free; Cache.Free; end;
end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; P: TPngImage;
begin
  F.Show; Application.ProcessMessages; F.Update; B := F.GetFormImage; P := TPngImage.Create;
  try P.Assign(B); P.SaveToFile(Path); finally P.Free; B.Free; end;
end;
procedure TestView(const Root: string);
var F: TFormMusicStudioSettings; P: TMusicStudioPattern; Text,ErrorText,ID: string;
  I,X,Y,Decode,Raster,OtherAudioSlot: Integer; Accept: Boolean; View: TWaveViewAccess;
begin
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.LoadDocument(''); F.Document.AddAudio; P := F.Document.PatternAt(0);
    P.FilePath := TPath.Combine(Root,'cache-envelope.wav'); WriteFixture(P.FilePath,False);
    P.Name := '実波形 / 前半無音'; P.Color := '#6FBFAD'; P.Volume := 0.75; P.Duration := 2;
    F.Document.UpdatePattern(P); ID := P.ID;
    F.Document.AddTrack('audio'); F.Document.AddSlot(0,'audio');
    F.Document.UpdateSlot(0,0,'メイン音声','#6FBFAD',TArray<string>.Create('audio'),ErrorText);
    F.Document.UpdateSlot(0,1,'別スロット','#E0B573',TArray<string>.Create('audio'),ErrorText);
    Check(F.Document.AddPlacement(0,0,ID,0,2,ErrorText),ErrorText);
    Check(F.Document.AddPlacement(0,0,ID,4,4,ErrorText),ErrorText);
    Check(F.Document.AddPlacement(0,1,ID,0.5,4,ErrorText),ErrorText);
    F.Document.AddTrack('psd'); OtherAudioSlot := F.Document.AddSlot(1,'audio');
    Check(F.Document.AddPlacement(1,OtherAudioSlot,ID,2,1.5,ErrorText),ErrorText);
    Check(F.Document.TrySave(Text,ErrorText),ErrorText);
    TFile.WriteAllText(TPath.Combine(Root,'waveform-demo.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text); F.Show; Application.ProcessMessages;
    View := TWaveViewAccess(F.TimelineBox); View.SelectSlot(0,0); Await(View.WaveCache);
    Check(View.WaveCache.DecodeCount = 1,'Repeated pattern placements decoded again');
    Capture(F,TPath.Combine(Root,'waveform-expanded.png')); Decode := View.WaveCache.DecodeCount; Raster := View.WaveCache.RasterCount;
    for I := 1 to 80 do begin View.Invalidate; View.Update; end;
    Check((View.WaveCache.DecodeCount = Decode) and (View.WaveCache.RasterCount = Raster),'GUI repaint did not use cache');
    View.Press(20,View.TrackRowTop(0)+10,mbLeft); View.ReleaseAt(20,View.TrackRowTop(0)+10);
    Check(not View.TrackExpanded(0),'Header did not collapse');
    Y := View.TrackRowTop(0)+20; X := View.HeaderWidth+30;
    Check((View.SlotAtPoint(X,Y) = 0) and (View.ClipAtPoint(X,Y) = 0),'Collapsed first slot clip invisible to hit test');
    Y := View.TrackRowTop(0)+48+20;
    Check((View.SlotAtPoint(X,Y) = 1) and (View.ClipAtPoint(X,Y) = 0),'Multiple summary slots overlap or cannot select');
    View.Press(X,Y,mbRight); Check((View.SelectedSlot = 1) and (View.SelectedClip = 0) and not View.TrackExpanded(0),'Summary selection expanded or chose wrong slot');
    View.Press(X,Y,mbLeft); View.MoveTo(X+40,Y); View.ReleaseAt(X+40,Y);
    Check(SameValue(F.Document.TrackAt(0).Slots[1].Clips[0].StartSeconds,1.5),'Collapsed clip drag failed');
    Check(SameValue(F.Document.TrackAt(0).Slots[0].Clips[0].StartSeconds,0),'Summary drag changed sibling slot');
    F.PatternList.ItemIndex := 0; X := View.HeaderWidth+380;
    F.TimelineBox.OnDragOver(View,F.PatternList,X,Y,dsDragMove,Accept); Check(Accept,'Collapsed slot D&D incompatible');
    F.TimelineBox.OnDragDrop(View,F.PatternList,X,Y); Check(Length(F.Document.TrackAt(0).Slots[1].Clips) = 2,'Collapsed drop failed');
    View.ToggleTrack(0); // D&D selects/expands its slot; restore summary for captures.
    if View.TrackExpanded(0) then View.ToggleTrack(0);
    Capture(F,TPath.Combine(Root,'waveform-collapsed.png'));
    View.SetPlayhead(1.25); View.Press(View.HeaderWidth+100,10,mbLeft);
    Check(SameValue(View.Playhead,2.5),'Ruler seek broke');
    for I := 0 to 6 do begin View.SetZoom(10+I*25); View.Update; end;
    Check(View.WaveCache.DecodeCount = Decode,'GUI zoom decoded again');
    View.SetZoom(40); View.ToggleTrack(0); Check(View.TrackExpanded(0),'Collapsed track did not restore');
    Capture(F,TPath.Combine(Root,'waveform-restored.png'));
    F.ClientWidth := 1000; F.ClientHeight := 562; View.ToggleTrack(0);
    Capture(F,TPath.Combine(Root,'waveform-minimum.png'));
    for I := 1 to 14 do F.Document.AddSlot(0,'audio');
    Check(F.Document.AddPlacement(0,15,ID,0,2,ErrorText),ErrorText); View.Refresh;
    for I := 1 to 20 do View.ScrollVertical(-120);
    Y := View.TrackRowTop(0)+15*48+20; X := View.HeaderWidth+30;
    Check((Y >= View.RulerHeight) and (View.SlotAtPoint(X,Y) = 15) and (View.ClipAtPoint(X,Y) = 0),
      'Tall collapsed summary cannot scroll to final slot');
    Capture(F,TPath.Combine(Root,'waveform-tall-summary-scrolled.png'));
    Check(View.WaveCache.DecodeCount = Decode,'Summary scroll decoded shared source again');
    for I := 15 downto 2 do F.Document.RemoveSlot(0,I);
    View.Refresh; for I := 1 to 20 do View.ScrollVertical(120);
    F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    Check(View.CurrentPPI = 144,'Wave view DPI scaling absent');
    Capture(F,TPath.Combine(Root,'waveform-dpi144.png'));
    Check(View.WaveCache.DecodeCount = Decode,'DPI change decoded source again');
    View.ScrollVertical(-120); View.ScrollVertical(120); View.PollWaveforms;
    F.Document.RemovePlacement(0,1,0); View.Refresh;
    F.Document.RemoveTrack(0); View.Refresh;
    F.LoadDocument(''); Await(View.WaveCache);
    Check(View.WaveCache.Find(P.FilePath) = nil,'JSON switch retained previous source');
    F.LoadDocument(Text); F.Close; // 閉じる/解放中に参照が残らない。
    Writeln('GUI_WAVEFORM_EXPANDED_COLLAPSED_MULTI_SLOT_SELECT_DRAG_DROP_SEEK_RESTORE_NORMAL_MINIMUM_144DPI_DELETE_SWITCH_CLOSE_OK');
  finally F.Free; end;
end;
procedure RunWaveCacheChecks(const Root: string);
begin TestCache(Root); TestView(Root); end;
end.
