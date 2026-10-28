program SYNC_MusicStudio_EditorStage1Tests;

// オーディオパターンのJSON・実デコード・取消・非同期差替え・統合画面の操作を検証する。
{$APPTYPE CONSOLE}

uses
  SYNC_MusicStudio_MeterEditor in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_MeterEditor.pas',
  SYNC_MusicStudio_SmallSlotData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_SmallSlotData.pas',
  SYNC_MusicStudio_SmallSlotEditor in '..\Source\Plugin\Filter\Performer\SYNC_MusicStudio_SmallSlotEditor.pas',
  SYNC_MusicStudio_PerformanceKinds in '..\Source\Common\Project\Performance\SYNC_MusicStudio_PerformanceKinds.pas',
  SYNC_MusicStudio_PerformanceLibrary in '..\Source\Common\Project\Performance\SYNC_MusicStudio_PerformanceLibrary.pas',
  SYNC_MusicStudio_PerformerData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_PerformerData.pas',
  SYNC_MusicStudio_PerformerPsd in '..\Source\Common\Project\Performer\SYNC_MusicStudio_PerformerPsd.pas',
  SYNC_MusicStudio_PerformerEditor in '..\Source\Plugin\Filter\Performer\SYNC_MusicStudio_PerformerEditor.pas',
  SYNC_MusicStudio_PerformanceEditor in '..\Source\Plugin\Filter\Performance\SYNC_MusicStudio_PerformanceEditor.pas',
  SYNC_MusicStudio_InstrumentRules in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_InstrumentRules.pas',
  SYNC_MusicStudio_InstrumentData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_InstrumentData.pas',
  SYNC_MusicStudio_InstrumentFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_InstrumentFrame.pas',
  SYNC_MusicStudio_DrumPsdRules in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_DrumPsdRules.pas',
  SYNC_MusicStudio_DrumData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_DrumData.pas',
  SYNC_MusicStudio_DrumFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_DrumFrame.pas',
  SYNC_MusicStudio_MeterMap in '..\Source\Common\Project\Timing\SYNC_MusicStudio_MeterMap.pas',
  SYNC_MusicStudio_ClipTempo in '..\Source\Common\Project\Timing\SYNC_MusicStudio_ClipTempo.pas',
  SYNC_MusicStudio_TimelineMetrics in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_TimelineMetrics.pas',
  SYNC_MusicStudio_TimelineContent in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_TimelineContent.pas',
  SYNC_MusicStudio_TempoRulerEditor in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TempoRulerEditor.pas',
  SYNC_MusicStudio_TempoPatternFrame in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TempoPatternFrame.pas',
  SYNC_MusicStudio_MidiTempo in '..\Source\Common\Singing\SYNC_MusicStudio_MidiTempo.pas',
  SYNC_MusicStudio_TempoPatternData in '..\Source\Common\Project\Timing\SYNC_MusicStudio_TempoPatternData.pas',
  SYNC_MusicStudio_LayerStepFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_LayerStepFrame.pas',
  SYNC_MusicStudio_LayerStepData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_LayerStepData.pas',
  SYNC_MusicStudio_PsdPlacementEditor in '..\Source\Plugin\Filter\Preview\SYNC_MusicStudio_PsdPlacementEditor.pas',
  SYNC_MusicStudio_PsdTransform in '..\Source\Common\Project\Arrangement\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_MusicStudio_EditHistory in '..\Source\Common\Project\SYNC_MusicStudio_EditHistory.pas',
  SYNC_MusicStudio_LibraryThumbnails in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_LibraryThumbnails.pas',
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_MusicStudio_VisualCacheChecks in 'Visual\SYNC_MusicStudio_VisualCacheChecks.pas',
  SYNC_MusicStudio_WaveCacheChecks in 'Audio\SYNC_MusicStudio_WaveCacheChecks.pas',
  SYNC_MusicStudio_PreviewChecks in 'Audio\SYNC_MusicStudio_PreviewChecks.pas',
  SYNC_MusicStudio_SlotChecks in 'Timeline\SYNC_MusicStudio_SlotChecks.pas',
  SYNC_MusicStudio_EditorModelChecks in 'Model\SYNC_MusicStudio_EditorModelChecks.pas',
  SYNC_MusicStudio_EditorInteractionChecks in 'Timeline\SYNC_MusicStudio_EditorInteractionChecks.pas',
  System.Classes, System.SysUtils, System.Types, System.Math, System.IOUtils,
  System.JSON, System.Generics.Collections, System.UITypes, Winapi.Windows, Vcl.Forms, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ProjectData in '..\Source\Common\Project\SYNC_MusicStudio_ProjectData.pas',
  SYNC_MusicStudio_ArrangementData in '..\Source\Common\Project\Arrangement\SYNC_MusicStudio_ArrangementData.pas',
  SYNC_MusicStudio_PatternData in '..\Source\Common\Project\SYNC_MusicStudio_PatternData.pas',
  SYNC_MusicStudio_AudioWaveform in '..\Source\Common\Audio\SYNC_MusicStudio_AudioWaveform.pas',
  SYNC_MusicStudio_WaveCache in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_WaveCache.pas',
  SYNC_MusicStudio_BitmapCache in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_BitmapCache.pas',
  SYNC_MusicStudio_VisualCache in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_VisualCache.pas',
  SYNC_MusicStudio_PreviewPlayback in '..\Source\Common\Audio\SYNC_MusicStudio_PreviewPlayback.pas',
  SYNC_MusicStudio_PsdPreview in '..\Source\Common\Render\SYNC_MusicStudio_PsdPreview.pas',
  SYNC_MusicStudio_FramebufferCapture in '..\Source\Common\Render\SYNC_MusicStudio_FramebufferCapture.pas',
  SYNC_MusicStudio_HostBackground in '..\Source\Common\Render\SYNC_MusicStudio_HostBackground.pas',
  SYNC_MusicStudio_PreviewFrame in '..\Source\Plugin\Filter\Preview\SYNC_MusicStudio_PreviewFrame.pas',
  SYNC_MusicStudio_DarkTheme in '..\Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  SYNC_MusicStudio_Controls in '..\Source\Plugin\Filter\Controls\SYNC_MusicStudio_Controls.pas',
  SYNC_MusicStudio_AudioClipFrame in '..\Source\Plugin\Filter\Patterns\Audio\SYNC_MusicStudio_AudioClipFrame.pas',
  SYNC_MusicStudio_Vowels in '..\Source\Common\Singing\SYNC_MusicStudio_Vowels.pas',
  SYNC_MusicStudio_SingingFormats in '..\Source\Common\Singing\SYNC_MusicStudio_SingingFormats.pas',
  SYNC_MusicStudio_SingingData in '..\Source\Common\Singing\SYNC_MusicStudio_SingingData.pas',
  SYNC_MusicStudio_SingingFrame in '..\Source\Plugin\Filter\Patterns\Singing\SYNC_MusicStudio_SingingFrame.pas',
  SYNC_MusicStudio_SlotFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SlotFrame.pas',
  SYNC_MusicStudio_PsdTrackFrame in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_PsdTrackFrame.pas',
  SYNC_MusicStudio_DarkScrollBar in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_DarkScrollBar.pas',
  SYNC_MusicStudio_ArrangementView in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_ArrangementView.pas',
  SYNC_MusicStudio_PatternSettingsForm in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PatternSettingsForm.pas',
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\Library\SYNC_MusicStudio_SharedPsdLibrary.pas',
  SYNC_MusicStudio_LibraryData in '..\Source\Common\Project\Library\SYNC_MusicStudio_LibraryData.pas',
  SYNC_MusicStudio_BeatData in '..\Source\Common\Project\Timing\SYNC_MusicStudio_BeatData.pas',
  SYNC_MusicStudio_MotionData in '..\Source\Common\Motion\SYNC_MusicStudio_MotionData.pas',
  SYNC_MusicStudio_AnimationSync in '..\Source\Common\Motion\SYNC_MusicStudio_AnimationSync.pas',
  SYNC_MusicStudio_PerformanceTrace in '..\Source\Common\Diagnostics\SYNC_MusicStudio_PerformanceTrace.pas',
  SYNC_MusicStudio_AnimationSlotData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_AnimationSlotData.pas',
  SYNC_MusicStudio_PsdLayersFrame in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_PsdLayersFrame.pas',
  SYNC_MusicStudio_SharedLibraryEditor in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_SharedLibraryEditor.pas',
  SYNC_MusicStudio_MotionFrame in '..\Source\Plugin\Filter\Patterns\Motion\SYNC_MusicStudio_MotionFrame.pas',
  SYNC_MusicStudio_PerformanceFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_PerformanceFrame.pas',
  SYNC_MusicStudio_PsdSceneCache in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdSceneCache.pas',
  SYNC_MusicStudio_PerformanceCache in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_PerformanceCache.pas',
  SYNC_MusicStudio_TimingFrame in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TimingFrame.pas',
  SYNC_MusicStudio_ArtDocument in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtDocument.pas',
  SYNC_MusicStudio_ArtLayerName in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtLayerName.pas',
  SYNC_MusicStudio_ArtPsd in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtPsd.pas',
  SYNC_MusicStudio_ArtPsdOrigin in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtPsdOrigin.pas',
  SYNC_MusicStudio_PsdLayers in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayers.pas',
  SYNC_MusicStudio_LayerScale in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_LayerScale.pas',
  SYNC_MusicStudio_PsdLayerConfig in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_PsdLayerConfig.pas',
  SYNC_MusicStudio_PsdLayerFrameUI in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_PsdLayerFrameUI.pas',
  SYNC_MusicStudio_PsdLayerJobs in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerJobs.pas',
  SYNC_MusicStudio_SettingsForm in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsForm.pas',
  SYNC_MusicStudio_SettingsDialogs in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsDialogs.pas',
  SYNC_MusicStudio_SettingsSlotMenus in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsSlotMenus.pas';

type
  TModalDriver = class
  public
    Timer: TTimer;
    Path, Screenshot: string;
    Cancel: Boolean;
    Seen: Boolean;
    procedure Tick(Sender: TObject);
    procedure AppException(Sender: TObject; E: Exception);
  end;

var
  TestRoot, WavPath, Mp3Path: string;

function AudioTestsExplicitlyEnabled: Boolean;
var I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do if SameText(ParamStr(I),'--allow-audio-tests') then Exit(True);
end;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

procedure Capture(Form: TForm; const Path: string);
var
  Bitmap: TBitmap;
  PNG: TPngImage;
begin
  Form.Show;
  Form.Update;
  Application.ProcessMessages;
  Bitmap := Form.GetFormImage;
  PNG := TPngImage.Create;
  try
    PNG.Assign(Bitmap);
    PNG.SaveToFile(Path);
  finally
    PNG.Free;
    Bitmap.Free;
  end;
end;

procedure WriteWave(const Path: string; Bits, Seconds: Integer; FloatSamples: Boolean);
var
  Stream: TFileStream;
  Header: TBytes;
  Samples: TBytes;
  I, C, FrameCount, BytesPerSample: Integer;
  Value: Double;
  SignedValue: Integer;
  FloatValue: Single;
  DataSize: Cardinal;
begin
  FrameCount := 44100 * Seconds;
  BytesPerSample := Bits div 8;
  DataSize := FrameCount * 2 * BytesPerSample;
  Header := TBytes.Create(82,73,70,70,0,0,0,0,87,65,86,69,102,109,116,32,
    16,0,0,0,1,0,2,0,68,172,0,0,0,0,0,0,0,0,0,0,100,97,116,97,0,0,0,0);
  PCardinal(@Header[4])^ := DataSize + 36;
  PCardinal(@Header[28])^ := 44100 * 2 * BytesPerSample;
  PWord(@Header[32])^ := 2 * BytesPerSample;
  PWord(@Header[34])^ := Bits;
  PCardinal(@Header[40])^ := DataSize;
  if FloatSamples then Header[20] := 3;
  SetLength(Samples, DataSize);
  for I := 0 to FrameCount - 1 do
  begin
    Value := Sin(I * 2 * Pi * 440 / 44100) * (0.35 + 0.3 * Sin(I * 2 * Pi / 44100));
    for C := 0 to 1 do
    begin
      if C = 1 then Value := -Value; // 左右逆相でもピークを消さない。
      if FloatSamples then
      begin
        FloatValue := Value;
        Move(FloatValue, Samples[(I * 2 + C) * BytesPerSample], SizeOf(FloatValue));
      end
      else
      begin
        case Bits of
          8: Samples[(I * 2 + C)] := Round(Value * 127) + 128;
          16: PSmallInt(@Samples[(I * 2 + C) * 2])^ := Round(Value * 32767);
          24: begin
            SignedValue := Round(Value * 8388607);
            Samples[(I * 2 + C) * 3] := Byte(SignedValue and $FF);
            Samples[(I * 2 + C) * 3 + 1] := Byte((SignedValue shr 8) and $FF);
            Samples[(I * 2 + C) * 3 + 2] := Byte((SignedValue shr 16) and $FF);
          end;
          32: PInteger(@Samples[(I * 2 + C) * 4])^ := Round(Value * 2147483647);
        end;
      end;
    end;
  end;
  Stream := TFileStream.Create(Path, fmCreate);
  try
    Stream.WriteBuffer(Header[0], Length(Header));
    Stream.WriteBuffer(Samples[0], Length(Samples));
  finally
    Stream.Free;
  end;
end;

procedure WriteSilentMp3(const Path: string);
var
  Stream: TFileStream;
  Frame: TBytes;
  I: Integer;
begin
  // MPEG1 Layer3 128kbps/44.1kHz stereo、zero-length granulesの無音フレーム。
  SetLength(Frame, 417);
  Frame[0] := $FF; Frame[1] := $FB; Frame[2] := $90; Frame[3] := 0;
  Stream := TFileStream.Create(Path, fmCreate);
  try for I := 1 to 200 do Stream.WriteBuffer(Frame[0], Length(Frame));
  finally Stream.Free; end;
end;

procedure AwaitJob(Job: TMusicStudioWaveJob);
var
  Started: UInt64;
begin
  Started := GetTickCount64;
  while not Job.Done and (GetTickCount64 - Started < 15000) do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
  Check(Job.Done, 'Decode did not finish within 15 seconds');
  Job.WaitFor;
end;

procedure TestAudio;
var
  Job: TMusicStudioWaveJob;
  Bits: Integer;
  Path: string;
  Peak: Single;
  I: Integer;
begin
  for Bits in [8,16,24,32] do
  begin
    Path := TPath.Combine(TestRoot, Format('pcm%d.wav', [Bits]));
    WriteWave(Path, Bits, 1, False);
    Job := TMusicStudioWaveJob.Create(Path, 1);
    try
      Job.Start; AwaitJob(Job);
      Check(Job.ErrorText = '', 'PCM decode: ' + Job.ErrorText);
      Check((Job.Info.SampleRate = 44100) and (Job.Info.Channels = 2) and
        SameValue(Job.Info.Duration, 1, 0.001), 'PCM metadata mismatch');
      Peak := 0;
      for I := 0 to High(Job.Waveform) do Peak := Max(Peak, Job.Waveform[I].Maximum);
      Check(Peak > 0.6, 'Anti-phase stereo peaks were lost');
    finally Job.Free; end;
  end;
  Path := TPath.Combine(TestRoot, 'float.wav');
  WriteWave(Path, 32, 1, True);
  Job := TMusicStudioWaveJob.Create(Path, 1);
  try Job.Start; AwaitJob(Job); Check(Job.ErrorText = '', Job.ErrorText);
  finally Job.Free; end;
  WriteSilentMp3(Mp3Path);
  Job := TMusicStudioWaveJob.Create(Mp3Path, 1);
  try
    Job.Start; AwaitJob(Job);
    Check(Job.ErrorText = '', 'MP3 decode: ' + Job.ErrorText);
    Check((Length(Job.Waveform) > 0) and (Job.Info.Duration > 4) and
      (Job.Info.SampleRate = 44100), 'MP3 was not decoded into samples');
  finally Job.Free; end;
  TFile.WriteAllText(TPath.Combine(TestRoot, 'broken.wav'), 'broken');
  TFile.WriteAllText(TPath.Combine(TestRoot, 'broken.mp3'), 'broken');
  for Path in [TPath.Combine(TestRoot, 'missing.wav'), TPath.Combine(TestRoot, 'broken.wav'),
    TPath.Combine(TestRoot, 'broken.mp3')] do
  begin
    Job := TMusicStudioWaveJob.Create(Path, 1);
    try
      Job.Start; AwaitJob(Job);
      Check((Job.ErrorText <> '') and (Length(Job.Waveform) = 0), 'Broken input accepted');
    finally Job.Free; end;
  end;
  Writeln('AUDIO_PCM8_16_24_32_FLOAT_MP3_AND_ERRORS_OK');
end;

procedure TestPatterns;
var
  Doc, Reloaded: TMusicStudioDocument;
  Pattern: TMusicStudioPattern;
  Text, ErrorText, Saved: string;
  Parsed: TJSONObject;
begin
  Doc := TMusicStudioDocument.Create;
  Reloaded := TMusicStudioDocument.Create;
  try
    Check(Doc.TryLoad('', ErrorText), ErrorText);
    Check(Doc.AddAudio = 0, 'First audio index');
    Doc.AddAudio;
    Check(Doc.PatternAt(0).ID <> Doc.PatternAt(1).ID, 'IDs are duplicated');
    Pattern := Doc.PatternAt(0);
    Pattern.Name := 'メイン音源'; Pattern.Color := '#FE7A45';
    Pattern.FilePath := WavPath; Pattern.Volume := 0.75;
    Doc.UpdatePattern(Pattern);
    Check(Doc.TrySave(Text, ErrorText), ErrorText);
    Parsed := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      Parsed.AddPair('extension', TJSONObject.Create.AddPair('keep', 'root'));
      TJSONObject(TJSONArray(Parsed.GetValue('patterns'))[0]).AddPair('future', 'pattern');
      TJSONObject(TJSONObject(TJSONArray(Parsed.GetValue('patterns'))[0]).GetValue('audio')).AddPair('future', 'audio');
      Saved := Parsed.ToJSON;
    finally Parsed.Free; end;
    Check(Doc.TryLoad(Saved, ErrorText), ErrorText);
    Pattern.Name := '更新音源'; Doc.UpdatePattern(Pattern);
    Check(Doc.TrySave(Text, ErrorText), ErrorText);
    Check(Reloaded.TryLoad(Text, ErrorText), ErrorText);
    Check((Reloaded.PatternAt(0).ID = Pattern.ID) and
      (Reloaded.PatternAt(0).Color = Pattern.Color) and
      (Reloaded.PatternAt(0).FilePath = WavPath) and
      SameValue(Reloaded.PatternAt(0).Volume, 0.75), 'Round trip lost audio settings');
    Check((Pos('"keep":"root"', Text) > 0) and (Pos('"future":"audio"', Text) > 0) and
      (Pos('"future":"pattern"', Text) > 0), 'Unknown fields lost');
    Check(not Reloaded.TryLoad(StringReplace(Text, '"volume":0.75', '"volume":-1', []), ErrorText),
      'Invalid volume accepted');
    Check(Reloaded.PatternCount = 2, 'Invalid load destroyed current data');
    Check(not Reloaded.TryLoad(StringReplace(Text, Pattern.ID, Reloaded.PatternAt(1).ID, []), ErrorText),
      'Duplicate ID accepted');
    Check(not Reloaded.TryLoad(StringReplace(Text, Pattern.Color, 'bad', []), ErrorText), 'Bad color accepted');
    Check(Reloaded.TryLoad(StringReplace(Text, '"kind":"audio"', '"kind":"future"', []), ErrorText),
      'Future kind was discarded');
    TFile.WriteAllText(TPath.Combine(TestRoot, 'roundtrip.json'), Text, TEncoding.UTF8);
  finally Reloaded.Free; Doc.Free; end;
  Writeln('PATTERN_JSON_ROUNDTRIP_IDS_EXTENSIONS_VALIDATION_OK');
end;

procedure AwaitFrame(Frame: TMusicStudioAudioClipFrame);
var
  Started: UInt64;
begin
  Started := GetTickCount64;
  repeat
    Frame.PollResults;
    Application.ProcessMessages;
    if not Frame.IsLoading then Break;
    Sleep(5);
  until GetTickCount64 - Started > 15000;
  Check(not Frame.IsLoading, 'Frame did not finish');
end;

procedure TModalDriver.Tick(Sender: TObject);
var
  I: Integer;
  Dialog: TMusicStudioPatternSettings;
  Component: TComponent;
begin
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I] is TMusicStudioPatternSettings then
    begin
      Timer.Enabled := False;
      Dialog := TMusicStudioPatternSettings(Screen.Forms[I]);
      Seen := True;
      Dialog.NameEdit.Text := 'メイン音源';
      Dialog.ColorEdit.Text := '#FE7A45';
      Dialog.AudioFrame.SelectFile(Path);
      Dialog.AudioFrame.VolumeBar.Position := 75;
      AwaitFrame(Dialog.AudioFrame);
      if Screenshot <> '' then Capture(Dialog, Screenshot);
      if Cancel then Dialog.ModalResult := mrCancel else
        for Component in Dialog do
          if (Component is TButton) and (TButton(Component).Caption = 'OK') then
            TButton(Component).Click;
      Exit;
    end;
end;

procedure TModalDriver.AppException(Sender: TObject; E: Exception);
begin
  Writeln('VCL_EXCEPTION ' + E.ClassName + ': ' + E.Message + ' at ' + IntToHex(NativeUInt(ExceptAddr), 16));
  Flush(Output);
  Halt(1);
end;

procedure TestForms;
var
  Form: TFormMusicStudioSettings;
  Popup: TMusicStudioPatternSettings;
  Driver: TModalDriver;
  Pattern: TMusicStudioPattern;
  ErrorText, Text: string;
begin
  Form := TFormMusicStudioSettings.Create(nil);
  Driver := TModalDriver.Create;
  Driver.Timer := TTimer.Create(nil);
  Driver.Timer.Enabled := False;
  Driver.Timer.Interval := 100;
  Driver.Timer.OnTimer := Driver.Tick;
  Application.OnException := Driver.AppException;
  try
    Form.LoadDocument('');
    Check(Form.Caption = '演奏スタジオ - 統合編集','DFM Japanese caption encoding');
    Capture(Form, TPath.Combine(TestRoot, 'editor-empty.png'));
    Check(not Form.EditButton.Enabled, 'No-selection edit is enabled');
    Check(not Form.AddButton.Enabled and (Form.AddMenu.Items.Count=0), 'Blank editor has no slot context');
    Form.TrackAddMenu.Items[0].Click;
    Check((Form.AddMenu.Items.Count=1) and Form.AddButton.Enabled, 'Audio slot offers only audio');
    Form.AddButton.Click;
    Form.AddButton.Click;
    Check((Form.PatternList.Count = 2) and (Form.PatternList.ItemIndex = 1), 'Add menu did not register clips');
    Driver.Path := WavPath;
    Driver.Screenshot := TPath.Combine(TestRoot, 'audio-settings.png');
    Driver.Timer.Enabled := True;
    Form.EditButton.Click;
    Check(Driver.Seen, 'Settings popup not opened');
    Pattern := Form.Document.PatternAt(1);
    Check((Pattern.Name = 'メイン音源') and (Pattern.Color = '#FE7A45') and
      (Pattern.FilePath = WavPath) and SameValue(Pattern.Volume, 0.75), 'GUI did not save settings');
    Driver.Path := Mp3Path; Driver.Cancel := True; Driver.Screenshot := ''; Driver.Seen := False;
    Driver.Timer.Enabled := True;
    Form.EditButton.Click;
    Check(Driver.Seen and (Form.Document.PatternAt(1).FilePath = WavPath), 'Cancel changed clip');
    Capture(Form, TPath.Combine(TestRoot, 'editor-clips.png'));
    Form.ClientWidth := 1000; Form.ClientHeight := 562;
    Capture(Form, TPath.Combine(TestRoot, 'editor-minimum.png'));
    Check((Form.TimelineBox.Width > 500) and (Form.TimelineBox.Height >= 200), 'Minimum timeline collapsed');
    Check(Form.InfoPanel.Top >= Form.ToolbarPanel.Height, 'Header overlaps toolbar');
    Check(Form.WorkPanel.Top >= Form.InfoPanel.Top + Form.InfoPanel.Height, 'Header overlaps work');
    Check(Form.Document.TrySave(Text, ErrorText), ErrorText);
    Form.LoadDocument(Text);
    Check((Form.PatternList.Count = 2) and (Form.Document.PatternAt(1).Color = '#FE7A45'), 'Reopen lost settings');
    Popup := TMusicStudioPatternSettings.Create(Form);
    try
      Popup.LoadPattern(Form.Document.PatternAt(1));
      AwaitFrame(Popup.AudioFrame);
      Check(Popup.AudioFrame.WavePointCount > 0, 'Reopen did not load waveform');
      Popup.AudioFrame.SelectFile(WavPath);
      Popup.AudioFrame.SelectFile(TPath.Combine(TestRoot, 'broken.wav'));
      Check(Popup.AudioFrame.WavePointCount = 0, 'Old waveform was not immediately cleared');
      AwaitFrame(Popup.AudioFrame);
      Check((Popup.AudioFrame.WavePointCount = 0) and (Popup.AudioFrame.WaveMessage <> ''), 'Old job contaminated new file');
      Popup.AudioFrame.SelectFile(Mp3Path);
      Popup.AudioFrame.SelectFile(WavPath);
      Popup.AudioFrame.SelectFile('');
      AwaitFrame(Popup.AudioFrame);
      Check((Popup.AudioFrame.FilePath = '') and (Popup.AudioFrame.WavePointCount = 0), 'Clear allowed old result');
      Popup.AudioFrame.LoadAudio(WavPath, 2);
      AwaitFrame(Popup.AudioFrame);
      Check(SameValue(Popup.AudioFrame.Volume, 2), '200 percent volume lost');
      Popup.ClientWidth := 680; Popup.ClientHeight := 480;
      Capture(Popup, TPath.Combine(TestRoot, 'audio-minimum.png'));
      Check(Popup.NameEdit.Left + Popup.NameEdit.Width < Popup.ColorEdit.Left, 'Common controls overlap');
      Check(Popup.AudioFrame.PathEdit.Width > 300, 'Audio source control collapsed');
      Popup.AudioFrame.SelectFile(WavPath); // 解放時に未完了ジョブを停止・回収する。
    finally Popup.Free; end;
  finally Application.OnException := nil; Driver.Timer.Free; Driver.Free; Form.Free; end;
  Writeln('GUI_ADD_EDIT_CANCEL_REOPEN_STALE_RESULTS_CLEAR_RESIZE_OK');
end;

begin
  try
    // Direct EXE launch is also safe by default. This precedes forms and all fixtures.
    if not AudioTestsExplicitlyEnabled then begin
      Writeln('AUDIO_TESTS_BLOCKED: use TestNoAudio.ps1; audio tests need explicit user resume and --allow-audio-tests.');
      ExitCode := 2; Exit;
    end;
    Application.Initialize;
    TestRoot := TPath.GetFullPath(ParamStr(1));
    ForceDirectories(TestRoot);
    WavPath := TPath.Combine(TestRoot, 'stage1-demo.wav');
    Mp3Path := TPath.Combine(TestRoot, 'silent.mp3');
    if ParamStr(2) = 'wave-cache' then begin RunWaveCacheChecks(TestRoot); Exit; end;
    if ParamStr(2) = 'visual-cache' then begin RunVisualCacheChecks(TestRoot); Exit; end;
    WriteWave(WavPath, 16, 12, False);
    TestAudio;
    TestPatterns;
    RunEditorModelChecks(TestRoot);
    TestForms;
    RunEditorInteractionChecks(TestRoot);
    RunSlotChecks(TestRoot);
    RunPreviewChecks(TestRoot);
    RunWaveCacheChecks(TestRoot);
    RunVisualCacheChecks(TestRoot);
    Writeln('EDITOR_STAGE1_TESTS_OK');
  except
    on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message + ' at ' + IntToHex(NativeUInt(ExceptAddr), 16)); ExitCode := 1; end;
  end;
end.
