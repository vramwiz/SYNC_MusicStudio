program SYNC_MusicStudio_NoAudioTests;
{$APPTYPE CONSOLE}
uses
  SYNC_MusicStudio_CursorTempoChecks in 'SYNC_MusicStudio_CursorTempoChecks.pas',
  SYNC_MusicStudio_MeterMap in '..\Source\Common\Project\SYNC_MusicStudio_MeterMap.pas',
  SYNC_MusicStudio_ClipTempo in '..\Source\Common\Project\SYNC_MusicStudio_ClipTempo.pas',
  SYNC_MusicStudio_TempoTimelineChecks in 'SYNC_MusicStudio_TempoTimelineChecks.pas',
  SYNC_MusicStudio_TimelineMetrics in '..\Source\Plugin\Filter\SYNC_MusicStudio_TimelineMetrics.pas',
  SYNC_MusicStudio_TimelineContent in '..\Source\Plugin\Filter\SYNC_MusicStudio_TimelineContent.pas',
  SYNC_MusicStudio_TempoRulerEditor in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TempoRulerEditor.pas',
  SYNC_MusicStudio_TempoPatternFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TempoPatternFrame.pas',
  SYNC_MusicStudio_MidiTempo in '..\Source\Common\Singing\SYNC_MusicStudio_MidiTempo.pas',
  SYNC_MusicStudio_TempoPatternData in '..\Source\Common\Project\SYNC_MusicStudio_TempoPatternData.pas',
  SYNC_MusicStudio_LayerStepChecks in 'SYNC_MusicStudio_LayerStepChecks.pas',
  SYNC_MusicStudio_LayerStepFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_LayerStepFrame.pas',
  SYNC_MusicStudio_LayerStepData in '..\Source\Common\Project\SYNC_MusicStudio_LayerStepData.pas',
  SYNC_MusicStudio_ExpressionPlacementChecks in 'SYNC_MusicStudio_ExpressionPlacementChecks.pas',
  SYNC_MusicStudio_VideoRenderer in '..\Source\Common\Render\SYNC_MusicStudio_VideoRenderer.pas',
  SYNC_MusicStudio_PsdPlacementEditor in '..\Source\Plugin\Filter\SYNC_MusicStudio_PsdPlacementEditor.pas',
  SYNC_MusicStudio_PsdTransform in '..\Source\Common\Project\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_MusicStudio_EditHistory in '..\Source\Common\Project\SYNC_MusicStudio_EditHistory.pas',
  SYNC_MusicStudio_TransportThumbnailChecks in 'SYNC_MusicStudio_TransportThumbnailChecks.pas',
  SYNC_MusicStudio_LibraryThumbnails in '..\Source\Plugin\Filter\SYNC_MusicStudio_LibraryThumbnails.pas',
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  System.SysUtils, System.IOUtils, Vcl.Forms, Vcl.Dialogs, System.UITypes,
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
  SYNC_MusicStudio_SettingsForm in '..\Source\Plugin\Filter\SYNC_MusicStudio_SettingsForm.pas',
  SYNC_MusicStudio_MotionData in '..\Source\Common\Motion\SYNC_MusicStudio_MotionData.pas',
  SYNC_MusicStudio_MotionFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_MotionFrame.pas',
  SYNC_MusicStudio_MotionChecks in 'SYNC_MusicStudio_MotionChecks.pas',
  SYNC_MusicStudio_ArtDocument in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtDocument.pas',
  SYNC_MusicStudio_ArtLayerName in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtLayerName.pas',
  SYNC_MusicStudio_ArtPsd in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsd.pas',
  SYNC_MusicStudio_ArtPsdOrigin in '..\Source\Common\Render\Layers\SYNC_MusicStudio_ArtPsdOrigin.pas',
  SYNC_MusicStudio_PsdLayerConfig in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerConfig.pas',
  SYNC_MusicStudio_PsdLayerFrameUI in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerFrameUI.pas',
  SYNC_MusicStudio_PsdLayerJobs in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerJobs.pas',
  SYNC_MusicStudio_PsdLayers in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayers.pas',
  SYNC_MusicStudio_PsdLayersFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PsdLayersFrame.pas',
  SYNC_MusicStudio_PsdLayerChecks in 'SYNC_MusicStudio_PsdLayerChecks.pas',
  SYNC_MusicStudio_LibraryData in '..\Source\Common\Project\SYNC_MusicStudio_LibraryData.pas',
  SYNC_MusicStudio_SharedLibraryEditor in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_SharedLibraryEditor.pas',
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\SYNC_MusicStudio_SharedPsdLibrary.pas',
  SYNC_MusicStudio_SharedLibraryChecks in 'SYNC_MusicStudio_SharedLibraryChecks.pas',
  SYNC_MusicStudio_BeatData in '..\Source\Common\Project\SYNC_MusicStudio_BeatData.pas',
  SYNC_MusicStudio_PerformanceFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_PerformanceFrame.pas',
  SYNC_MusicStudio_BeatChecks in 'SYNC_MusicStudio_BeatChecks.pas',
  SYNC_MusicStudio_PsdSceneCache in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdSceneCache.pas',
  SYNC_MusicStudio_PerformanceCache in '..\Source\Plugin\Filter\SYNC_MusicStudio_PerformanceCache.pas',
  SYNC_MusicStudio_PsdSceneChecks in 'SYNC_MusicStudio_PsdSceneChecks.pas',
  SYNC_MusicStudio_PerformanceCacheChecks in 'SYNC_MusicStudio_PerformanceCacheChecks.pas',
  SYNC_MusicStudio_TimingFrame in '..\Source\Plugin\Filter\Patterns\SYNC_MusicStudio_TimingFrame.pas',
  TimingChecks in 'TimingChecks.pas',
  SYNC_MusicStudio_TestHelpers in 'SYNC_MusicStudio_TestHelpers.pas',
  SYNC_MusicStudio_EditorModelChecks in 'SYNC_MusicStudio_EditorModelChecks.pas',
  SYNC_MusicStudio_EditorInteractionChecks in 'SYNC_MusicStudio_EditorInteractionChecks.pas',
  SYNC_MusicStudio_SlotChecks in 'SYNC_MusicStudio_SlotChecks.pas',
  SYNC_MusicStudio_VisualCacheChecks in 'SYNC_MusicStudio_VisualCacheChecks.pas',
  SYNC_MusicStudio_PhraseRollChecks in 'SYNC_MusicStudio_PhraseRollChecks.pas',
  SYNC_MusicStudio_PsdRealAssetChecks in 'SYNC_MusicStudio_PsdRealAssetChecks.pas',
  SYNC_MusicStudio_NoAudioChecks in 'SYNC_MusicStudio_NoAudioChecks.pas',
  SYNC_MusicStudio_PsdStorageChecks in 'SYNC_MusicStudio_PsdStorageChecks.pas',
  SYNC_MusicStudio_PsdDisplayChecks in 'SYNC_MusicStudio_PsdDisplayChecks.pas',
  SYNC_MusicStudio_PsdMouthChecks in 'SYNC_MusicStudio_PsdMouthChecks.pas',
  SYNC_MusicStudio_PsdPlaybackChecks in 'SYNC_MusicStudio_PsdPlaybackChecks.pas',
  SYNC_MusicStudio_ReviewChecks in 'SYNC_MusicStudio_ReviewChecks.pas';
begin
  try
    SetTextCodePage(Output,65001); SetTextCodePage(ErrOutput,65001);
    Application.Initialize;
    if ParamStr(2)='--object-review-tiny' then begin RunObjectReviewChecks(ParamStr(1),False); Exit; end;
    if ParamStr(2)='--object-review-minimum' then begin RunObjectReviewChecks(ParamStr(1),True); Exit; end;
    if ParamStr(2)='--layer-objects' then begin RunLayerObjectChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--step-point-errors' then begin RunCompactPointErrorChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--step-point-real' then begin RunLayerStepRealPointDemo(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--step-point-tail' then begin RunLayerStepTailReview(ParamStr(1)); Exit; end;
    if ParamStr(2)='--step-point-boundary' then begin RunLayerStepBoundaryReview(ParamStr(1)); Exit; end;
    if ParamStr(2)='--step-points' then begin RunLayerStepPointChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--cursor-upper' then begin RunCursorUpperChecks; Exit; end;
    if ParamStr(2)='--cursor-tempo' then begin RunCursorTempoChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--tempo-timeline' then begin RunTempoTimelineChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--layer-steps' then begin RunLayerStepChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--expressions-placement' then begin RunExpressionPlacementChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--ui-real' then begin RunTransportRealPreview(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--ui-thumbnails' then begin RunMusicStudioPsdLayerChecks(ParamStr(1),False); RunTransportThumbnailChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--phrase-roll' then begin RunPhraseRollChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--psd-playback' then begin RunPsdPlaybackChecks(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--psd-mouth' then begin RunPsdMouthChecks(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--psd-display' then begin RunPsdDisplayChecks(ParamStr(1),ParamStr(3)); Exit; end;
    RunPsdDisplayChecks(ParamStr(1));
    RunCursorTempoChecks(ParamStr(1));
    RunTempoTimelineChecks(ParamStr(1));
    RunLayerStepChecks(ParamStr(1));
    RunExpressionPlacementChecks(ParamStr(1));
    RunPsdMouthChecks(ParamStr(1));
    ForceDirectories(TPath.Combine(ParamStr(1),'regression'));
    RunEditorModelChecks(TPath.Combine(ParamStr(1),'regression'));
    RunEditorInteractionChecks(TPath.Combine(ParamStr(1),'regression'));
    RunSlotChecks(TPath.Combine(ParamStr(1),'regression'));
    RunVisualCacheChecks(TPath.Combine(ParamStr(1),'regression'));
    RunPhraseRollChecks(ParamStr(1));
    RunMusicStudioPsdLayerChecks(ParamStr(1),ParamStr(2)<>'--skip-layers');
    RunBeatChecks(ParamStr(1));
    RunTimingChecks(ParamStr(1));
    RunSharedLibraryChecks(ParamStr(1));
    if ParamStr(2)<>'--no-force-termination' then RunPsdStorageChecks(ParamStr(1))
    else Writeln('PSD_STORAGE_PROCESS_INTERRUPTION_SUITE_SKIPPED_NO_FORCE_TERMINATION');
    RunMotionChecks(ParamStr(1));
    RunPerformanceCacheChecks(ParamStr(1));
    RunNoAudioChecks(ParamStr(1));
    RunMusicStudioPsdSceneChecks(ParamStr(1));
    RunPsdPlaybackChecks(ParamStr(1));
    RunReviewChecks(ParamStr(1));
    RunTransportThumbnailChecks(ParamStr(1));
    RunMusicStudioPsdRealAssetChecks(ParamStr(1));
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
