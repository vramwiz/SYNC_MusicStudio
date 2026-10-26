unit SYNC_MusicStudio_PreviewChecks;

// 実waveOut出力/時計/所有資源、音量/配置、停止・再開・シーク・閉じる、PSD raw/RLEを検証。
interface
procedure RunPreviewChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.Math, System.Diagnostics, System.IOUtils, System.Hash,
  Winapi.Windows, Winapi.Messages, Winapi.TlHelp32, System.Types, Vcl.Controls, Vcl.StdCtrls,
  Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage, SYNC_MusicStudio_PreviewPlayback,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PsdPreview,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_Controls, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_TestHelpers;
type TFontAccess = class(TControl);
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
// RTLで公開されないOpenThreadを読取/同期だけに使用し、対象はこの検証プロセスに限定する。
function OpenObservedThread(Access: Cardinal; Inherit: BOOL; ThreadID: Cardinal): THandle; stdcall;
  external 'kernel32.dll' name 'OpenThread';
procedure Pump(Milliseconds: Integer);
var Watch: TStopwatch;
begin Watch := TStopwatch.StartNew; repeat Application.ProcessMessages; Sleep(2); until Watch.ElapsedMilliseconds>=Milliseconds; end;
function RunAudio(const Path: string; Gain,Start,Length,Seek: Double; Missing: Boolean): Single;
var Clips: TMusicStudioPreviewClips; Job: TMusicStudioPlaybackJob; Watch: TStopwatch; Snapshot: TMusicStudioPlaybackSnapshot;
begin
  SetLength(Clips,1); Clips[0].FilePath := Path; Clips[0].Name := ExtractFileName(Path);
  Clips[0].Volume := Gain; Clips[0].StartSeconds := Start; Clips[0].LengthSeconds := Length;
  Job := TMusicStudioPlaybackJob.Create(Clips,Seek,Start+Length); Result := 0;
  try
    Job.Start; Watch := TStopwatch.StartNew;
    repeat
      Snapshot := Job.Snapshot; Result := Max(Result,Snapshot.Peak);
      Check(Snapshot.State<>psFailed,'waveOut/decoder failed: '+Snapshot.Message);
      if Snapshot.Position>Seek+0.15 then Break;
      Pump(3);
    until Job.Done or (Watch.ElapsedMilliseconds>6000);
    Check((Snapshot.Position>Seek+0.1) and (Snapshot.SubmittedFrames>1024),'Native audio clock/output did not advance');
    if Missing then Check(Snapshot.Message<>'','Missing source silently reported successful audio')
    else Check(Snapshot.Message='','Valid source was skipped: '+Snapshot.Message);
    Check(MusicStudioPreviewOutputCount=1,'Duplicate or missing owned waveOut device');
  finally Job.Free; end;
  Check(MusicStudioPreviewOutputCount=0,'Stop left owned waveOut output active');
end;
procedure TestMixerAndEnd(const Root: string);
var Clips: TMusicStudioPreviewClips; Job: TMusicStudioPlaybackJob; S: TMusicStudioPlaybackSnapshot;
  Watch: TStopwatch; Peak: Single;
begin
  SetLength(Clips,2);
  Clips[0].FilePath := TPath.Combine(Root,'stage1-demo.wav'); Clips[0].Volume := 0.25; Clips[0].LengthSeconds := 0.35;
  Clips[1] := Clips[0]; Job := TMusicStudioPlaybackJob.Create(Clips,0,0.35); Peak := 0;
  try
    Job.Start; Watch := TStopwatch.StartNew;
    repeat S := Job.Snapshot; Peak := Max(Peak,S.Peak); Pump(3); until Job.Done or (Watch.ElapsedMilliseconds>3000);
    S := Job.Snapshot;
    Check(Job.Done and (S.State=psFinished) and SameValue(S.Position,0.35),'Playback did not finish at arrangement end');
    Check((Peak>0.2) and (Peak<0.5),'Overlapping clips did not mix with individual gain');
    Check(MusicStudioPreviewOutputCount=0,'Natural end left output active');
  finally Job.Free; end;
  Check(RunAudio(TPath.Combine(Root,'stage1-demo.wav'),1,0.5,0.4,0,False)=0,'Audio played before placement start');
  Check(RunAudio(TPath.Combine(Root,'stage1-demo.wav'),1,0.5,0.4,0.6,False)>0.1,'Seek did not use placement-local source time');
  Writeln('AUDIO_OVERLAP_GAIN_PLACEMENT_START_LOCAL_SEEK_NATURAL_END_OK');
end;
procedure WritePSD(const Path: string; RLE: Boolean);
var S: TFileStream; C,I,X: Integer;
  procedure B(Value: Byte); begin S.WriteBuffer(Value,1); end;
  procedure U16(Value: Word); begin B(Value shr 8); B(Value and 255); end;
  procedure U32(Value: Cardinal); begin U16(Value shr 16); U16(Value and 65535); end;
begin
  S := TFileStream.Create(Path,fmCreate);
  try
    for I in [56,66,80,83] do B(I); U16(1); for I := 1 to 6 do B(0);
    U16(3); U32(64); U32(64); U16(8); U16(3); U32(0); U32(0); U32(0);
    if RLE then begin U16(1); for I := 0 to 3*64-1 do U16(2); end else U16(0);
    for C := 0 to 2 do for I := 0 to 63 do
      if RLE then begin B(193); B(40+C*75); end
      else for X := 0 to 63 do B(40+C*75);
  finally S.Free; end;
end;
procedure TestPSD(const Root: string);
var Job: TMusicStudioPsdPreviewJob; Watch: TStopwatch; Path: string; RLE: Boolean;
begin
  for RLE in [False,True] do begin
    if RLE then Path := TPath.Combine(Root,'preview-rle.psd') else Path := TPath.Combine(Root,'preview-raw.psd');
    WritePSD(Path,RLE); Job := TMusicStudioPsdPreviewJob.Create(Path);
    try
      Job.Start; Watch := TStopwatch.StartNew;
      while not Job.Done and (Watch.ElapsedMilliseconds<3000) do Pump(2);
      Check(Job.Done and (Job.ErrorText=''),'PSD merged decode: '+Job.ErrorText);
      Check((Job.Width=64) and (Job.Height=64) and (Length(Job.Pixels)=64*64*4),'PSD dimensions');
      Check((Job.Pixels[0]=190) and (Job.Pixels[1]=115) and (Job.Pixels[2]=40) and (Job.Pixels[3]=255),'PSD merged colors');
    finally Job.Free; end;
  end;
  Path := TPath.Combine(Root,'preview-broken.psd'); TFile.WriteAllText(Path,'broken');
  Job := TMusicStudioPsdPreviewJob.Create(Path);
  try Job.Start; while not Job.Done do Pump(2); Check((Job.ErrorText<>'') and (Length(Job.Pixels)=0),'Broken PSD produced pixels');
  finally Job.Free; end;
  Writeln('PSD_MERGED_RGB8_RAW_RLE_BOUNDS_COLORS_AND_BROKEN_OK');
end;
procedure TestLongSource(const Root: string);
var S: TFileStream; Header: TBytes; Path: string; DataSize: Cardinal;
begin
  Path := TPath.Combine(Root,'preview-long-temporary.wav'); DataSize := 44100*2*1200;
  Header := TBytes.Create(82,73,70,70,0,0,0,0,87,65,86,69,102,109,116,32,
    16,0,0,0,1,0,1,0,68,172,0,0,136,88,1,0,2,0,16,0,100,97,116,97,0,0,0,0);
  PCardinal(@Header[4])^ := DataSize+36; PCardinal(@Header[40])^ := DataSize;
  S := TFileStream.Create(Path,fmCreate);
  try S.WriteBuffer(Header[0],Length(Header)); S.Size := DataSize+44; finally S.Free; end;
  try RunAudio(Path,1,0,1200,1199.5,False); finally TFile.Delete(Path); end;
  Writeln('AUDIO_LONG_20MIN_STREAM_SEEK_NEAR_END_BOUNDED_OUTPUT_OK');
end;
procedure Capture(Form: TForm; const Path: string);
var Bitmap: TBitmap; PNG: TPngImage;
begin
  Form.Show; Form.Update; Application.ProcessMessages; Bitmap := Form.GetFormImage; PNG := TPngImage.Create;
  try PNG.Assign(Bitmap); PNG.SaveToFile(Path); finally PNG.Free; Bitmap.Free; end;
end;
procedure TestGUI(const Root: string);
var D: TMusicStudioDocument; F: TFormMusicStudioSettings; P: TMusicStudioPattern;
  Text,Before,ErrorText,RealPSD,SourceHash: string; Position: Double; I: Integer;
begin
  D := TMusicStudioDocument.Create; F := TFormMusicStudioSettings.Create(nil);
  try
    Check(D.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,ErrorText),ErrorText); D.AddAudio; P := D.PatternAt(0);
    P.FilePath := TPath.Combine(Root,'stage1-demo.wav'); P.Volume := 0.25; P.Duration := 12; D.UpdatePattern(P);
    D.AddTrack('audio'); Check(D.AddPlacement(0,0,P.ID,0.25,3,ErrorText),ErrorText);
    WriteLayeredTestPSD(TPath.Combine(Root,'preview-layers.psd'));
    D.AddTrack('psd'); D.UpdateTrack(1,'PSD部位プレビュー','#C78AE8',TPath.Combine(Root,'preview-layers.psd'));
    D.AddSinging; P := D.PatternAt(1); P.FilePath := TPath.Combine(Root,'singing-demo.mid');
    P.SourceTrack := 0; P.Duration := 2.5; D.UpdatePattern(P);
    Check(D.AddPlacement(1,TestSlotIndex(D,1,'singing'),P.ID,0.25,2.5,ErrorText),ErrorText);
    Check(D.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text); F.Show; Pump(80);
    TFile.WriteAllText(TPath.Combine(Root,'preview-demo.json'),Text,TEncoding.UTF8);
    Check(F.Document.TrySave(Before,ErrorText),ErrorText);
    for I := 1 to 10 do F.Preview.Play;
    Pump(450); Check(F.Preview.IsPlaying and (F.Preview.Position>0.15),'GUI play did not advance');
    Check(MusicStudioPreviewOutputCount=1,'Rapid play created multiple outputs');
    Check(SameValue(F.TimelineBox.Playhead,F.Preview.Position),'Timeline/preview clocks differ');
    Check((F.Preview.ImageCount=1) and (Pos('きゃ [60]',F.Preview.CurrentLyric)>0),'PSD/MIDI content not synchronized');
    Capture(F,TPath.Combine(Root,'preview-playing.png'));
    F.Preview.Pause; Position := F.Preview.Position; Pump(100);
    Check(not F.Preview.IsPlaying and SameValue(F.Preview.Position,Position) and (MusicStudioPreviewOutputCount=0),'Pause leaked sound/clock');
    F.TimelineBox.OnSeek(1.5); Check(SameValue(F.Preview.Position,1.5),'Ruler seek not shared');
    F.Preview.Play; Pump(150); Check(F.Preview.Position>1.5,'Resume lost seek offset');
    F.Preview.Seek(0.75); Pump(120); Check((F.Preview.Position>=0.75) and (MusicStudioPreviewOutputCount=1),'Playing seek duplicated/lost output');
    F.Preview.Stop; Check((MusicStudioPreviewOutputCount=0) and SameValue(F.Preview.Position,0),'Stop left sound/position');
    F.Preview.Seek(1.8); Check(Pos('ー [62]',F.Preview.CurrentLyric)>0,'MIDI lyric seek did not follow placement offset');
    F.Preview.Seek(2.8); Check(F.Preview.CurrentLyric='','Ended MIDI note remained in preview');
    Check(F.Document.TrySave(Text,ErrorText) and (Text=Before),'Transport modified JSON');
    F.Preview.Play; Pump(80);
    Check(not F.ImportJSONFile(TPath.GetFullPath(TPath.Combine(Root,'..\..\..\Samples\Debug\unsupported-version.json')),ErrorText),
      'Invalid JSON accepted during playback');
    Check((MusicStudioPreviewOutputCount=0) and F.Document.TrySave(Text,ErrorText) and (Text=Before),
      'Rejected JSON import left audio or lost document');
    F.Preview.Play; Pump(70); F.LoadDocument(MUSIC_STUDIO_DEFAULT_JSON);
    Check((MusicStudioPreviewOutputCount=0) and not F.Preview.IsPlaying,'JSON switch retained old audio');
    F.LoadDocument(Before); F.Preview.Play; Pump(100); F.CancelButtonClick(nil);
    Check(MusicStudioPreviewOutputCount=0,'Close/cancel retained audio');
    RealPSD := 'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PSD\東北きりたん_打撃_ドラム_持ち方修正.psd';
    if FileExists(RealPSD) then begin
      SourceHash := THashSHA2.GetHashStringFromFile(RealPSD); D.UpdateTrack(1,'既存PSD（読取のみ）','#C78AE8',RealPSD);
      Check(D.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text); Pump(500);
      Check(F.Preview.ImageCount=1,'Existing PSD merged image was not displayed');
      F.Preview.Seek(0.5); Capture(F,TPath.Combine(Root,'preview-existing-psd.png'));
      Check(SourceHash=THashSHA2.GetHashStringFromFile(RealPSD),'Existing PSD was modified');
      Writeln('EXISTING_PSD_READ_ONLY_MERGED_PREVIEW_SHA256_UNCHANGED_OK');
    end;
  finally F.Free; D.Free; end;
  Check(MusicStudioPreviewOutputCount=0,'Form destruction retained output');
  Writeln('GUI_PREVIEW_PLAY_PAUSE_STOP_RULER_SEEK_SYNC_RAPID_PLAY_JSON_SWITCH_CLOSE_OK');
end;
procedure TestActiveFormClose(const Root: string);
var D: TMusicStudioDocument; F: TFormMusicStudioSettings; P: TMusicStudioPattern;
  Text,Before,ErrorText,Path,SavedText,SaveError: string; Header: TBytes; Stream: TFileStream;
  Mode,I,J: Integer; Baseline: TArray<Cardinal>; Handles: TArray<THandle>; Watch: TStopwatch;
  function ThreadIDs: TArray<Cardinal>;
  var Snapshot: THandle; Entry: TThreadEntry32; N: Integer;
  begin
    Result := nil; Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD,0);
    Check(Snapshot<>INVALID_HANDLE_VALUE,'Cannot capture worker threads');
    try
      Entry.dwSize := SizeOf(Entry);
      if Thread32First(Snapshot,Entry) then repeat
        if Entry.th32OwnerProcessID=GetCurrentProcessId then begin
          N := Length(Result); SetLength(Result,N+1); Result[N] := Entry.th32ThreadID;
        end;
      until not Thread32Next(Snapshot,Entry);
    finally CloseHandle(Snapshot); end;
  end;
  procedure CaptureWorkers(const Kind: string);
  var ID,OldID: Cardinal; Found: Boolean; N,PreviousCount: Integer; Handle: THandle;
  begin
    PreviousCount := Length(Handles);
    for ID in ThreadIDs do begin
      Found := False; for OldID in Baseline do if ID=OldID then Found := True;
      if Found then Continue;
      Handle := OpenObservedThread(SYNCHRONIZE,False,ID);
      if Handle=0 then Continue;
      if WaitForSingleObject(Handle,0)<>WAIT_TIMEOUT then begin CloseHandle(Handle); Continue; end;
      N := Length(Handles); SetLength(Handles,N+1); Handles[N] := Handle;
    end;
    Check(Length(Handles)>PreviousCount,'Close fixture did not observe live '+Kind+' workers');
  end;
begin
  // 8M画素の専用一時PSDを4件読込ませ、未完了ワーカーをOSハンドルで捕捉する。
  // 音声の停止/取消を先に呼ばず、FreeとWM_SYSCOMMAND/SC_CLOSEをそれぞれ検証する。
  Path := TPath.Combine(Root,'preview-close-temporary.psd');
  Header := TBytes.Create(56,66,80,83,0,1,0,0,0,0,0,0,0,3,0,0,16,0,0,0,8,0,0,8,0,3,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  Stream := TFileStream.Create(Path,fmCreate);
  try Stream.WriteBuffer(Header[0],Length(Header)); Stream.Size := Length(Header)+3*2048*4096;
  finally Stream.Free; end;
  try
    D := TMusicStudioDocument.Create;
    try
      Check(D.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,ErrorText),ErrorText); D.AddAudio; P := D.PatternAt(0);
      P.FilePath := TPath.Combine(Root,'stage1-demo.wav'); P.Volume := 0; P.Duration := 12; D.UpdatePattern(P);
      D.AddTrack('audio'); Check(D.AddPlacement(0,0,P.ID,0,12,ErrorText),ErrorText);
      for I := 1 to 4 do begin D.AddTrack('psd'); D.UpdateTrack(I,'Close fixture','#C78AE8',Path); end;
      Check(D.TrySave(Text,ErrorText),ErrorText);
      for Mode := 0 to 1 do begin
        F := TFormMusicStudioSettings.Create(nil); Handles := nil;
        try
          F.Show; Pump(30); Baseline := ThreadIDs;
          F.LoadDocument(Text); CaptureWorkers('PSD');
          Check(F.Document.TrySave(Before,ErrorText),ErrorText);
          Baseline := ThreadIDs; F.Preview.Play; CaptureWorkers('audio'); Watch := TStopwatch.StartNew;
          repeat Pump(2); until (F.Preview.PlaybackSnapshot.Position>0.03) or (Watch.ElapsedMilliseconds>3000);
          Check(F.Preview.IsPlaying and (MusicStudioPreviewOutputCount=1) and
            (F.Preview.PlaybackSnapshot.Position>0.03),'Close fixture was not actively playing');
          if Mode=1 then begin
            SendMessage(F.Handle,WM_SYSCOMMAND,SC_CLOSE,0);
            Check(not F.Visible and (MusicStudioPreviewOutputCount=0),'Title-bar close retained window/audio');
            Check(F.Document.TrySave(SavedText,SaveError) and (SavedText=Before),'Title-bar close changed fixture JSON');
          end;
          FreeAndNil(F); // 再生中の直接破棄にはStop/Cancelを挟まない。
          Check(MusicStudioPreviewOutputCount=0,'Active form destruction retained waveOut');
          for J := 0 to High(Handles) do
            Check(WaitForSingleObject(Handles[J],0)=WAIT_OBJECT_0,'Form destruction retained PSD/audio worker');
          Stream := TFileStream.Create(P.FilePath,fmOpenReadWrite or fmShareExclusive); Stream.Free;
          Stream := TFileStream.Create(TPath.Combine(Root,'preview-close-temporary.psd'),fmOpenReadWrite or fmShareExclusive); Stream.Free;
          Pump(80); Check(MusicStudioPreviewOutputCount=0,'Freed form restarted audio via delayed callback');
        finally F.Free; for J := 0 to High(Handles) do CloseHandle(Handles[J]); end;
      end;
    finally D.Free; end;
  finally TFile.Delete(TPath.Combine(Root,'preview-close-temporary.psd')); end;
  Writeln('GUI_ACTIVE_DIRECT_FREE_TITLEBAR_CLOSE_PSD_AUDIO_WORKERS_WAVEOUT_FILES_RELEASED_OK');
end;
procedure TestTypographyAndMeter(const Root: string);
var F: TFormMusicStudioSettings; D: TMusicStudioPatternSettings; P: TMusicStudioPattern;
  Text,ErrorText: string; I,Mode,PixelHeight: Integer; Area,Fill: TRect; Gain: Double;
  Component: TComponent; FoundVolume: Boolean; Watch: TStopwatch;
  procedure CheckFonts(C: TControl);
  var J: Integer;
  begin
    Check(TFontAccess(C).Font.Name='Yu Gothic UI','Mixed body typeface: '+C.ClassName);
    Check(TFontAccess(C).Font.Height=-PixelHeight,'Mixed body font height: '+C.ClassName+' '+
      IntToStr(TFontAccess(C).Font.Height));
    if C is TWinControl then for J := 0 to TWinControl(C).ControlCount-1 do
      CheckFonts(TWinControl(C).Controls[J]);
  end;
begin
  // 座標の上下、範囲外の入力、小さい/144DPIの描画領域を検証する。
  for I in [1,100,150] do begin
    Area := Rect(10,20,22,20+I);
    Fill := MusicStudioPeakFillRect(Area,0); Check(IsRectEmpty(Fill),'Mute meter has visible fill');
    Fill := MusicStudioPeakFillRect(Area,0.5);
    Check((Fill.Bottom=Area.Bottom) and (Fill.Top>=Area.Top) and
      (Fill.Height=Round(I/2)),'Half peak is not anchored at the bottom');
    Check(MusicStudioPeakFillRect(Area,1)=Area,'Maximum peak does not fill the meter');
    Check(MusicStudioPeakFillRect(Area,2)=Area,'Out-of-range maximum escaped meter');
    Check(IsRectEmpty(MusicStudioPeakFillRect(Area,-1)),'Negative peak has visible fill');
  end;
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.LoadDocument(MUSIC_STUDIO_DEFAULT_JSON); F.Document.AddAudio; P := F.Document.PatternAt(0);
    P.FilePath := TPath.Combine(Root,'stage1-demo.wav'); P.Duration := 4;
    F.Document.UpdatePattern(P); F.Document.AddTrack('audio');
    F.Document.AddTrack('psd');
    Check(F.Document.AddPlacement(0,0,P.ID,0,4,ErrorText),ErrorText);
    Check(F.Document.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text);
    for Mode := 0 to 2 do begin
      PixelHeight := 13;
      if Mode=0 then begin F.ClientWidth := 1200; F.ClientHeight := 800; end
      else begin F.ClientWidth := 1000; F.ClientHeight := 562; end;
      if Mode=2 then begin F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1; PixelHeight := 20; end;
      CheckFonts(F);
      Check(F.TimelineBox.Height>=MulDiv(180,F.TimelineBox.CurrentPPI,96),'Font/layout change collapsed arrangement');
      Check(F.PatternList.ItemHeight>=3*PixelHeight,'Pattern text exceeds row height');
      Capture(F,TPath.Combine(Root,'fonts-editor-'+IntToStr(Mode)+'.png'));
      D := TMusicStudioPatternSettings.Create(nil);
      try
        D.LoadPattern(F.Document.PatternAt(0)); D.ClientWidth := 680; D.ClientHeight := 480;
        if Mode=2 then begin D.ScaleForPPI(144); D.Scaled := False; D.ClientWidth := D.ClientWidth+1; end;
        CheckFonts(D);
        Check((D.NameEdit.Left+D.NameEdit.Width<D.ColorEdit.Left) and
          (D.AudioFrame.PathEdit.Left+D.AudioFrame.PathEdit.Width<D.AudioFrame.Width-MulDiv(212,D.CurrentPPI,96)),
          'Font change overlaps common/source controls');
        for I := 0 to 2 do begin
          Gain := I; D.AudioFrame.VolumeBar.Position := I*100; P := F.Document.PatternAt(0); D.ReadPattern(P);
          Check(SameValue(P.Volume,Gain),'Volume slider/gain inverted'); F.Document.UpdatePattern(P);
          Check(F.Document.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text);
          Check(SameValue(F.Document.PatternAt(0).Volume,Gain),'JSON changed the volume');
          D.LoadPattern(F.Document.PatternAt(0)); Check(SameValue(D.AudioFrame.Volume,Gain),'Reopened volume inverted');
          FoundVolume := False;
          for Component in D.AudioFrame do if Component is TLabel then
            if Pos(Format('音量  %d %%',[I*100]),TLabel(Component).Caption)=1 then FoundVolume := True;
          Check(FoundVolume,'Volume label differs from slider/JSON gain');
          CheckFonts(D);
        end;
        Watch := TStopwatch.StartNew;
        while D.AudioFrame.IsLoading and (Watch.ElapsedMilliseconds<3000) do begin
          D.AudioFrame.PollResults; Pump(3);
        end;
        Check(D.AudioFrame.WavePointCount>0,'Font/volume screenshot has no decoded waveform');
        Capture(D,TPath.Combine(Root,'fonts-audio-'+IntToStr(Mode)+'.png'));
        D.LoadTrack(F.Document.TrackAt(1)); CheckFonts(D);
        D.LoadSlot(F.Document.TrackAt(0).Slots[0]); CheckFonts(D);
        P := F.Document.PatternAt(0); P.Kind := 'singing'; P.FilePath := ''; D.LoadPattern(P); CheckFonts(D);
        Capture(D,TPath.Combine(Root,'fonts-singing-'+IntToStr(Mode)+'.png'));
      finally D.Free; end;
      if Mode=2 then begin F.Scaled := True; F.ScaleForPPI(96); end;
    end;
    Check(F.Document.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text);
    F.ClientWidth := 1200; F.ClientHeight := 800;
    F.Preview.Play; Pump(180); Capture(F,TPath.Combine(Root,'fonts-meter-playing.png')); F.Preview.Stop;
  finally F.Free; end;
  Writeln('GUI_UNIFIED_13PX_FONT_NORMAL_MINIMUM_144DPI_VOLUME_0_100_200_JSON_REOPEN_BOTTOM_UP_METER_OK');
end;
procedure RunPreviewChecks(const Root: string);
var LowPeak,HighPeak: Single; Ext: string;
begin
  for Ext in ['pcm8.wav','pcm16.wav','pcm24.wav','pcm32.wav','float.wav','silent.mp3'] do
    RunAudio(TPath.Combine(Root,Ext),1,0,0.4,0,False);
  RunAudio(TPath.Combine(Root,'silent.mp3'),1,0,4,2,False);
  LowPeak := RunAudio(TPath.Combine(Root,'stage1-demo.wav'),0.25,0.05,0.5,0,False);
  HighPeak := RunAudio(TPath.Combine(Root,'stage1-demo.wav'),2,0.05,0.5,0,False);
  Check((LowPeak>0.05) and (LowPeak<0.3) and (HighPeak>LowPeak*2),'PCM gain was not applied');
  Check(RunAudio(TPath.Combine(Root,'stage1-demo.wav'),0,0,0.4,0,False)=0,'Muted clip produced samples');
  RunAudio(TPath.Combine(Root,'missing.wav'),1,0,0.4,0,True);
  RunAudio(TPath.Combine(Root,'broken.wav'),1,0,0.4,0,True);
  Writeln('WAVEOUT_REAL_DEVICE_CLOCK_FORMATS_MP3_GAIN_MUTE_MISSING_BROKEN_STOP_OK');
  TestMixerAndEnd(Root); TestLongSource(Root); TestPSD(Root); TestGUI(Root); TestTypographyAndMeter(Root);
  TestActiveFormClose(Root); // SC_CLOSEはApplication.Terminateを送るので画面検証の最後に行う。
end;
end.
