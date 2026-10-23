program SYNC_MusicStudio_EditorPreview;

// AviUtl2を起動せず、第1段階UIとJSON参照保存をユーザーが確認するための独立テストホスト。
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
  SYNC_MusicStudio_PsdPlacementEditor in '..\Source\Plugin\Filter\SYNC_MusicStudio_PsdPlacementEditor.pas',
  SYNC_MusicStudio_PsdTransform in '..\Source\Common\Project\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_MusicStudio_EditHistory in '..\Source\Common\Project\SYNC_MusicStudio_EditHistory.pas',
  SYNC_MusicStudio_LibraryThumbnails in '..\Source\Plugin\Filter\SYNC_MusicStudio_LibraryThumbnails.pas',
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  System.SysUtils, Vcl.Forms, Vcl.Dialogs, System.UITypes,
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
  SYNC_MusicStudio_DarkTheme in '..\Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  SYNC_MusicStudio_Controls in '..\Source\Plugin\Filter\SYNC_MusicStudio_Controls.pas',
  SYNC_MusicStudio_AudioClipFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_AudioClipFrame.pas',
  SYNC_MusicStudio_Vowels in '..\Source\Common\Singing\SYNC_MusicStudio_Vowels.pas',
  SYNC_MusicStudio_SingingData in '..\Source\Common\Singing\SYNC_MusicStudio_SingingData.pas',
  SYNC_MusicStudio_SingingFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SingingFrame.pas',
  SYNC_MusicStudio_SlotFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SlotFrame.pas',
  SYNC_MusicStudio_PsdTrackFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PsdTrackFrame.pas',
  SYNC_MusicStudio_ArrangementView in '..\Source\Plugin\Filter\SYNC_MusicStudio_ArrangementView.pas',
  SYNC_MusicStudio_PatternSettingsForm in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PatternSettingsForm.pas',
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\SYNC_MusicStudio_SharedPsdLibrary.pas',
  SYNC_MusicStudio_LibraryData in '..\Source\Common\Project\SYNC_MusicStudio_LibraryData.pas',
  SYNC_MusicStudio_BeatData in '..\Source\Common\Project\SYNC_MusicStudio_BeatData.pas',
  SYNC_MusicStudio_MotionData in '..\Source\Common\Motion\SYNC_MusicStudio_MotionData.pas',
  SYNC_MusicStudio_PsdLayersFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PsdLayersFrame.pas',
  SYNC_MusicStudio_SharedLibraryEditor in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SharedLibraryEditor.pas',
  SYNC_MusicStudio_MotionFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_MotionFrame.pas',
  SYNC_MusicStudio_PerformanceFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PerformanceFrame.pas',
  SYNC_MusicStudio_ArtDocument in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtDocument.pas',
  SYNC_MusicStudio_ArtLayerName in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtLayerName.pas',
  SYNC_MusicStudio_ArtPsd in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsd.pas',
  SYNC_MusicStudio_ArtPsdOrigin in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsdOrigin.pas',
  SYNC_MusicStudio_PsdLayers in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayers.pas',
  SYNC_MusicStudio_PsdLayerConfig in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerConfig.pas',
  SYNC_MusicStudio_PsdLayerFrameUI in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerFrameUI.pas',
  SYNC_MusicStudio_PsdLayerJobs in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerJobs.pas',
  SYNC_MusicStudio_PsdSceneCache in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdSceneCache.pas',
  SYNC_MusicStudio_PerformanceCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_PerformanceCache.pas',
  SYNC_MusicStudio_TimingFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TimingFrame.pas',
  SYNC_MusicStudio_SettingsForm in '..\Source\Plugin\Filter\SYNC_MusicStudio_SettingsForm.pas';

var
  Form: TFormMusicStudioSettings;
  JSONText, ErrorText: string;
  ArgIndex: Integer;
begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Form := TFormMusicStudioSettings.Create(nil);
  try
    JSONText := ''; ArgIndex := 1;
    if SameText(ParamStr(1),'--silent') then begin Form.SilentVisualMode := True; ArgIndex := 2; end;
    if ParamCount >= ArgIndex then
      try
        if not TryReadMusicStudioJSONFile(ParamStr(ArgIndex),JSONText,ErrorText) then
          MessageDlg(ErrorText,mtError,[mbOK],0);
      except on E: Exception do MessageDlg(E.Message, mtError, [mbOK], 0); end;
    if SameText(ParamStr(ArgIndex+1),'--library-root') and (ParamStr(ArgIndex+2)<>'') then
      Form.LibraryRoot := ParamStr(ArgIndex+2);
    Form.LoadDocument(JSONText);
    Form.ShowModal;
  finally Form.Free; end;
end.
