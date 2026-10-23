program SYNC_MusicStudio_FoundationTests;

// JSON保存境界、設定フォーム、実際に配備したFilterの登録を検証する。

{$APPTYPE CONSOLE}

uses
  SYNC_MusicStudio_InstrumentRules in '..\Source\Common\Render\Layers\SYNC_MusicStudio_InstrumentRules.pas',
  SYNC_MusicStudio_InstrumentData in '..\Source\Common\Project\SYNC_MusicStudio_InstrumentData.pas',
  SYNC_MusicStudio_InstrumentFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_InstrumentFrame.pas',
  SYNC_MusicStudio_DrumPsdRules in '..\Source\Common\Render\Layers\SYNC_MusicStudio_DrumPsdRules.pas',
  SYNC_MusicStudio_DrumData in '..\Source\Common\Project\SYNC_MusicStudio_DrumData.pas',
  SYNC_MusicStudio_DrumFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_DrumFrame.pas',
  SYNC_MusicStudio_MeterMap in '..\Source\Common\Project\SYNC_MusicStudio_MeterMap.pas',
  SYNC_MusicStudio_ClipTempo in '..\Source\Common\Project\SYNC_MusicStudio_ClipTempo.pas',
  SYNC_MusicStudio_TimelineMetrics in '..\Source\Plugin\Filter\SYNC_MusicStudio_TimelineMetrics.pas',
  SYNC_MusicStudio_TimelineContent in '..\Source\Plugin\Filter\SYNC_MusicStudio_TimelineContent.pas',
  SYNC_MusicStudio_TempoRulerEditor in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TempoRulerEditor.pas',
  SYNC_MusicStudio_TempoPatternFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TempoPatternFrame.pas',
  SYNC_MusicStudio_MidiTempo in '..\Source\Common\Singing\SYNC_MusicStudio_MidiTempo.pas',
  SYNC_MusicStudio_TempoPatternData in '..\Source\Common\Project\SYNC_MusicStudio_TempoPatternData.pas',
  SYNC_MusicStudio_LayerStepFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_LayerStepFrame.pas',
  SYNC_MusicStudio_LayerStepData in '..\Source\Common\Project\SYNC_MusicStudio_LayerStepData.pas',
  SYNC_MusicStudio_EditHistory in '..\Source\Common\Project\SYNC_MusicStudio_EditHistory.pas',
  SYNC_MusicStudio_PsdPlacementEditor in '..\Source\Plugin\Filter\SYNC_MusicStudio_PsdPlacementEditor.pas',
  SYNC_MusicStudio_PsdTransform in '..\Source\Common\Project\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_MusicStudio_LibraryThumbnails in '..\Source\Plugin\Filter\SYNC_MusicStudio_LibraryThumbnails.pas',
  System.JSON,
  System.SysUtils,
  System.UITypes,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.Graphics,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  SYNC_MusicStudio_ProjectData in '..\Source\Common\Project\SYNC_MusicStudio_ProjectData.pas',
  SYNC_MusicStudio_ArrangementData in '..\Source\Common\Project\SYNC_MusicStudio_ArrangementData.pas',
  SYNC_MusicStudio_PatternData in '..\Source\Common\Project\SYNC_MusicStudio_PatternData.pas',
  SYNC_MusicStudio_AudioWaveform in '..\Source\Common\Audio\SYNC_MusicStudio_AudioWaveform.pas',
  SYNC_MusicStudio_WaveCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_WaveCache.pas',
  SYNC_MusicStudio_BitmapCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_BitmapCache.pas',
  SYNC_MusicStudio_VisualCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_VisualCache.pas',
  SYNC_MusicStudio_PreviewPlayback in '..\Source\Common\Audio\SYNC_MusicStudio_PreviewPlayback.pas',
  SYNC_MusicStudio_PsdPreview in '..\Source\Common\Render\SYNC_MusicStudio_PsdPreview.pas',
  SYNC_MusicStudio_FramebufferCapture in '..\Source\Common\Render\SYNC_MusicStudio_FramebufferCapture.pas',
  SYNC_MusicStudio_HostBackground in '..\Source\Common\Render\SYNC_MusicStudio_HostBackground.pas',
  SYNC_MusicStudio_PreviewFrame in '..\Source\Plugin\Filter\SYNC_MusicStudio_PreviewFrame.pas',
  SYNC_MusicStudio_Controls in '..\Source\Plugin\Filter\SYNC_MusicStudio_Controls.pas',
  SYNC_MusicStudio_AudioClipFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_AudioClipFrame.pas',
  SYNC_MusicStudio_Vowels in '..\Source\Common\Singing\SYNC_MusicStudio_Vowels.pas',
  SYNC_MusicStudio_SingingData in '..\Source\Common\Singing\SYNC_MusicStudio_SingingData.pas',
  SYNC_MusicStudio_SingingFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SingingFrame.pas',
  SYNC_MusicStudio_SlotFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SlotFrame.pas',
  SYNC_MusicStudio_PsdTrackFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PsdTrackFrame.pas',
  SYNC_MusicStudio_ArrangementView in '..\Source\Plugin\Filter\SYNC_MusicStudio_ArrangementView.pas',
  SYNC_MusicStudio_PatternSettingsForm in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PatternSettingsForm.pas',
  SYNC_MusicStudio_DarkTheme in '..\Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\SYNC_MusicStudio_SharedPsdLibrary.pas',
  SYNC_MusicStudio_LibraryData in '..\Source\Common\Project\SYNC_MusicStudio_LibraryData.pas',
  SYNC_MusicStudio_BeatData in '..\Source\Common\Project\SYNC_MusicStudio_BeatData.pas',
  SYNC_MusicStudio_MotionData in '..\Source\Common\Motion\SYNC_MusicStudio_MotionData.pas',
  SYNC_MusicStudio_PsdLayersFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PsdLayersFrame.pas',
  SYNC_MusicStudio_SharedLibraryEditor in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SharedLibraryEditor.pas',
  SYNC_MusicStudio_MotionFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_MotionFrame.pas',
  SYNC_MusicStudio_PerformanceFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PerformanceFrame.pas',
  SYNC_MusicStudio_PsdSceneCache in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdSceneCache.pas',
  SYNC_MusicStudio_PerformanceCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_PerformanceCache.pas',
  SYNC_MusicStudio_TimingFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TimingFrame.pas',
  SYNC_MusicStudio_ArtDocument in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtDocument.pas',
  SYNC_MusicStudio_ArtLayerName in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtLayerName.pas',
  SYNC_MusicStudio_ArtPsd in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsd.pas',
  SYNC_MusicStudio_ArtPsdOrigin in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsdOrigin.pas',
  SYNC_MusicStudio_PsdLayers in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayers.pas',
  SYNC_MusicStudio_PsdLayerConfig in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerConfig.pas',
  SYNC_MusicStudio_PsdLayerFrameUI in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerFrameUI.pas',
  SYNC_MusicStudio_PsdLayerJobs in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerJobs.pas',
  SYNC_MusicStudio_SettingsForm in '..\Source\Plugin\Filter\SYNC_MusicStudio_SettingsForm.pas';

type
  TApplyCollector = class
  public
    ApplyCount: Integer;
    SavedText: string;
    function ApplyJSON(const JSONText: string; out ErrorText: string): Boolean;
  end;
  TInitializePlugin = function(Version: Cardinal): Byte; cdecl;
  TUninitializePlugin = procedure; cdecl;
  TGetFilterPluginTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TFilterItems = array[0..2] of Pointer;
  PFilterItems = ^TFilterItems;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function TApplyCollector.ApplyJSON(const JSONText: string; out ErrorText: string): Boolean;
begin
  Inc(ApplyCount);
  SavedText := JSONText;
  ErrorText := '';
  Result := True;
end;

procedure RejectJSON(const Text: string);
var
  ErrorText: string;
  JSONText: string;
begin
  Check(not TryNormalizeMusicStudioJSON(Text, JSONText, ErrorText), 'Invalid JSON was accepted');
  Check((JSONText = '') and (ErrorText <> ''), 'Rejection must leave no savable document');
end;

procedure TestJSON;
var
  ErrorText: string;
  JSONText: string;
  SourceText: string;
  BoundaryText: string;
  Parsed: TJSONValue;
begin
  Check(TryNormalizeMusicStudioJSON('', JSONText, ErrorText), ErrorText);
  Check(JSONText = MUSIC_STUDIO_DEFAULT_JSON, 'Empty project did not initialize');
  SourceText := '{' + #13#10 + '"schemaVersion":1,"previewAudio":' +
    '{"filePath":"D:\\Music\\曲.wav","displayName":"確認音源"},' +
    '"materials":[{"id":"material-1","filePath":"D:\\Music\\歌唱.mid"}],' +
    '"characters":[],"tracks":[],"extension":{"name":"演奏\nスタジオ","enabled":true}}';
  Check(TryNormalizeMusicStudioJSON(SourceText, JSONText, ErrorText), ErrorText);
  Check((Pos(#13, JSONText) = 0) and (Pos(#10, JSONText) = 0), 'Stored JSON contains a physical newline');
  Check(Pos('material-1', JSONText) > 0, 'Material references were lost');
  Parsed := TJSONObject.ParseJSONValue(JSONText);
  try
    Check(Parsed.GetValue<string>('previewAudio.displayName') = '確認音源', 'Japanese display name was lost');
  finally
    Parsed.Free;
  end;
  Check(Pos('"extension"', JSONText) > 0, 'Unknown extension field was lost');
  Check(Pos('\n', JSONText) > 0, 'Escaped newline was lost');
  RejectJSON('{');
  RejectJSON('[]');
  RejectJSON('{}');
  RejectJSON(MUSIC_STUDIO_DEFAULT_JSON + '{}');
  RejectJSON(StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"schemaVersion":1', '"schemaVersion":2', []));
  RejectJSON(StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"schemaVersion":1', '"schemaVersion":1.5', []));
  RejectJSON(StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"schemaVersion":1', '"schemaVersion":"1"', []));
  RejectJSON(StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"previewAudio":null', '"previewAudio":{}', []));
  RejectJSON(StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"materials":[]', '"materials":{}', []));
  SourceText := Copy(MUSIC_STUDIO_DEFAULT_JSON, 1, Length(MUSIC_STUDIO_DEFAULT_JSON) - 1) + ',"extra":""}';
  BoundaryText := StringReplace(SourceText, '"extra":""',
    '"extra":"' + StringOfChar('x', MUSIC_STUDIO_MAX_JSON_LENGTH - Length(SourceText)) + '"', []);
  Check(Length(BoundaryText) = MUSIC_STUDIO_MAX_JSON_LENGTH, 'Boundary fixture has wrong size');
  Check(TryNormalizeMusicStudioJSON(BoundaryText, JSONText, ErrorText), ErrorText);
  RejectJSON(StringReplace(BoundaryText, '"extra":"', '"extra":"x', []));
  Writeln('JSON_OK');
end;

procedure TestForm;
var
  CanClose: Boolean;
  Collector: TApplyCollector;
  Form: TFormMusicStudioSettings;
  Bitmap: TBitmap;
begin
  Collector := TApplyCollector.Create;
  try
    Form := TFormMusicStudioSettings.Create(nil);
    try
      Form.LoadDocument('');
      Check(Pos('演奏スタジオ', Form.Caption) > 0, 'Wrong form name');
      Check(Trim(Form.JSONMemo.Text) = MUSIC_STUDIO_DEFAULT_JSON, 'Form did not load default document');
      Form.JSONMemo.Text := StringReplace(MUSIC_STUDIO_DEFAULT_JSON, '"tracks":[]',
        '"tracks":[{"id":"performer-1"}]', []);
      Form.RestoreButtonClick(nil);
      Check(Trim(Form.JSONMemo.Text) = MUSIC_STUDIO_DEFAULT_JSON, 'Restore did not return to opened state');
      Form.OnApplyJSON := Collector.ApplyJSON;
      Form.ModalResult := mrCancel; // タイトルバーの閉じると同じVCL状態。
      Form.FormCloseQuery(nil, CanClose);
      Check(CanClose and (Collector.ApplyCount = 1), 'Title-bar close did not apply document');
      Check(Collector.SavedText = MUSIC_STUDIO_DEFAULT_JSON, 'Wrong document applied');
      Form.LoadDocument('invalid existing JSON');
      Form.CancelButtonClick(nil);
      Form.FormCloseQuery(nil, CanClose);
      Check(CanClose and (Collector.ApplyCount = 1), 'Cancel changed host data or could not close invalid data');
      Form.LoadDocument('');
      Check(Form.TimelineBox.Height > 200, 'Timeline area collapsed');
      Check(Form.WorkPanel.Top >= Form.InfoPanel.Top + Form.InfoPanel.Height, 'Header overlaps editor');
      Check(not Form.JSONMemo.Visible, 'Raw JSON replaced the integrated editor');
      Check(Form.InfoLabel.Left + Form.InfoLabel.Width <= Form.InfoPanel.Width, 'Header exceeds form width');
      if ParamCount > 1 then
      begin
        Form.Show;
        try
          Application.ProcessMessages;
          Bitmap := Form.GetFormImage;
          try
            Bitmap.SaveToFile(ParamStr(2));
          finally
            Bitmap.Free;
          end;
        finally
          Form.Hide;
        end;
      end;
    finally
      Form.Free;
    end;
  finally
    Collector.Free;
  end;
  Writeln('SETTINGS_FORM_OK');
end;

procedure TestPlugin;
var
  Module: HMODULE;
  InitializePlugin: TInitializePlugin;
  UninitializePlugin: TUninitializePlugin;
  GetTable: TGetFilterPluginTable;
  Table: PFILTER_PLUGIN_TABLE;
  Items: PFilterItems;
begin
  Check(ParamCount > 0, 'Pass plugin artifact path');
  Module := LoadLibrary(PChar(ParamStr(1)));
  Check(Module <> 0, 'Plugin LoadLibrary failed: ' + SysErrorMessage(GetLastError));
  try
    @InitializePlugin := GetProcAddress(Module, 'InitializePlugin');
    @UninitializePlugin := GetProcAddress(Module, 'UninitializePlugin');
    @GetTable := GetProcAddress(Module, 'GetFilterPluginTable');
    Check(Assigned(InitializePlugin) and Assigned(UninitializePlugin) and Assigned(GetTable), 'DLL exports missing');
    Check(InitializePlugin(0) = 1, 'Plugin initialization failed');
    try
      Table := GetTable;
      Check(Table <> nil, 'Plugin table missing');
      Check(string(Table^.Name) = '演奏スタジオ', 'Wrong plugin name');
      Check(string(Table^.Label_) = 'SYNC', 'Wrong plugin group');
      Writeln('PLUGIN_IDENTITY_SYNC_PERFORMANCE_STUDIO_OK');
      Check(Table^.Flag = FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA, 'Wrong filter flags');
      Check(Assigned(Table^.Func_Create) and Assigned(Table^.Func_Destroy), 'Video instance lifecycle missing');
      Items := PFilterItems(Table^.Items);
      Check((Items^[0] <> nil) and (Items^[1] <> nil) and (Items^[2] = nil), 'Expected exactly two settings');
      Check(string(PFILTER_ITEM_BUTTON(Items^[0])^.ItemType) = 'button', 'Setting opener is not a button');
      Check(string(PFILTER_ITEM_BUTTON(Items^[0])^.Name) = '設定', 'Wrong setting button label');
      Check(Assigned(PFILTER_ITEM_BUTTON(Items^[0])^.Callback), 'Setting button callback missing');
      Check(string(PFILTER_ITEM_STRING(Items^[1])^.Name) = 'JSONデータ', 'Wrong JSON item label');
      Check(string(PFILTER_ITEM_STRING(Items^[1])^.Value) = MUSIC_STUDIO_DEFAULT_JSON, 'Wrong plugin default document');
      Check(Table = GetTable, 'Plugin table is not stable across calls');
      Check(Table^.Func_Proc_Video(nil) = 1, 'Pass-through callback failed');
      Check(not Assigned(Table^.Func_Proc_Audio), 'Preview WAV must not become output audio');
    finally
      UninitializePlugin;
    end;
  finally
    FreeLibrary(Module);
  end;
  Writeln('PLUGIN_ARTIFACT_OK');
end;

begin
  try
    Application.Initialize;
    TestJSON;
    TestForm;
    TestPlugin;
    Writeln('FOUNDATION_TESTS_OK');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
