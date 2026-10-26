program SYNC_MusicStudio_NoAudioTests;
{$APPTYPE CONSOLE}
uses
  SYNC_MusicStudio_SingingFormatChecks in 'Singing\SYNC_MusicStudio_SingingFormatChecks.pas',
  SYNC_MusicStudio_InstrumentEndChecks in 'Instrument\SYNC_MusicStudio_InstrumentEndChecks.pas',
  SYNC_MusicStudio_InstrumentAppliedChecks in 'Instrument\SYNC_MusicStudio_InstrumentAppliedChecks.pas',
  SYNC_MusicStudio_InstrumentPhaseChecks in 'Instrument\SYNC_MusicStudio_InstrumentPhaseChecks.pas',
  SYNC_MusicStudio_HiHatRoutingChecks in 'Instrument\SYNC_MusicStudio_HiHatRoutingChecks.pas',
  SYNC_MusicStudio_InstrumentPreviewChecks in 'Instrument\SYNC_MusicStudio_InstrumentPreviewChecks.pas',
  SYNC_MusicStudio_InstrumentPreview in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_InstrumentPreview.pas',
  SYNC_MusicStudio_PsdListChecks in 'Psd\SYNC_MusicStudio_PsdListChecks.pas',
  SYNC_MusicStudio_FileDropList in '..\Source\Plugin\Filter\Controls\SYNC_MusicStudio_FileDropList.pas',
  SYNC_MusicStudio_PsdImport in '..\Source\Common\Project\Library\SYNC_MusicStudio_PsdImport.pas',
  SYNC_MusicStudio_PsdDropChecks in 'Timeline\SYNC_MusicStudio_PsdDropChecks.pas',
  SYNC_MusicStudio_SlotUIChecks in 'Timeline\SYNC_MusicStudio_SlotUIChecks.pas',
  SYNC_MusicStudio_SmallSlotData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_SmallSlotData.pas',
  SYNC_MusicStudio_SmallSlotEditor in '..\Source\Plugin\Filter\Performer\SYNC_MusicStudio_SmallSlotEditor.pas',
  SYNC_MusicStudio_PerformerChecks in 'Model\SYNC_MusicStudio_PerformerChecks.pas',
  SYNC_MusicStudio_PerformanceKinds in '..\Source\Common\Project\Performance\SYNC_MusicStudio_PerformanceKinds.pas',
  SYNC_MusicStudio_PerformanceLibrary in '..\Source\Common\Project\Performance\SYNC_MusicStudio_PerformanceLibrary.pas',
  SYNC_MusicStudio_PerformerData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_PerformerData.pas',
  SYNC_MusicStudio_PerformerPsd in '..\Source\Common\Project\Performer\SYNC_MusicStudio_PerformerPsd.pas',
  SYNC_MusicStudio_PerformerEditor in '..\Source\Plugin\Filter\Performer\SYNC_MusicStudio_PerformerEditor.pas',
  SYNC_MusicStudio_PerformanceEditor in '..\Source\Plugin\Filter\Performance\SYNC_MusicStudio_PerformanceEditor.pas',
  SYNC_MusicStudio_InstrumentChecks in 'Instrument\SYNC_MusicStudio_InstrumentChecks.pas',
  SYNC_MusicStudio_StageChecks in 'Scene\SYNC_MusicStudio_StageChecks.pas',
  SYNC_MusicStudio_AnimationCostChecks in 'Scene\SYNC_MusicStudio_AnimationCostChecks.pas',
  SYNC_MusicStudio_InstrumentRules in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_InstrumentRules.pas',
  SYNC_MusicStudio_InstrumentData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_InstrumentData.pas',
  SYNC_MusicStudio_InstrumentPlayback in '..\Source\Common\Project\Performance\SYNC_MusicStudio_InstrumentPlayback.pas',
  SYNC_MusicStudio_InstrumentFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_InstrumentFrame.pas',
  SYNC_MusicStudio_DrumPsdChecks in 'Model\SYNC_MusicStudio_DrumPsdChecks.pas',
  SYNC_MusicStudio_DrumPsdRules in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_DrumPsdRules.pas',
  SYNC_MusicStudio_DrumChecks in 'Model\SYNC_MusicStudio_DrumChecks.pas',
  SYNC_MusicStudio_DrumData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_DrumData.pas',
  SYNC_MusicStudio_DrumFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_DrumFrame.pas',
  SYNC_MusicStudio_CursorTempoChecks in 'Timeline\SYNC_MusicStudio_CursorTempoChecks.pas',
  SYNC_MusicStudio_MeterMap in '..\Source\Common\Project\Timing\SYNC_MusicStudio_MeterMap.pas',
  SYNC_MusicStudio_ClipTempo in '..\Source\Common\Project\Timing\SYNC_MusicStudio_ClipTempo.pas',
  SYNC_MusicStudio_TempoTimelineChecks in 'Timeline\SYNC_MusicStudio_TempoTimelineChecks.pas',
  SYNC_MusicStudio_TimelineMetrics in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_TimelineMetrics.pas',
  SYNC_MusicStudio_TimelineContent in '..\Source\Plugin\Filter\Timeline\SYNC_MusicStudio_TimelineContent.pas',
  SYNC_MusicStudio_TempoRulerEditor in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TempoRulerEditor.pas',
  SYNC_MusicStudio_TempoPatternFrame in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TempoPatternFrame.pas',
  SYNC_MusicStudio_MidiTempo in '..\Source\Common\Singing\SYNC_MusicStudio_MidiTempo.pas',
  SYNC_MusicStudio_TempoPatternData in '..\Source\Common\Project\Timing\SYNC_MusicStudio_TempoPatternData.pas',
  SYNC_MusicStudio_LayerStepChecks in 'Model\SYNC_MusicStudio_LayerStepChecks.pas',
  SYNC_MusicStudio_LayerStepFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_LayerStepFrame.pas',
  SYNC_MusicStudio_LayerStepData in '..\Source\Common\Project\Performance\SYNC_MusicStudio_LayerStepData.pas',
  SYNC_MusicStudio_ExpressionPlacementChecks in 'Timeline\SYNC_MusicStudio_ExpressionPlacementChecks.pas',
  SYNC_MusicStudio_VideoRenderer in '..\Source\Common\Render\SYNC_MusicStudio_VideoRenderer.pas',
  SYNC_MusicStudio_PsdPlacementEditor in '..\Source\Plugin\Filter\Preview\SYNC_MusicStudio_PsdPlacementEditor.pas',
  SYNC_MusicStudio_PsdTransform in '..\Source\Common\Project\Arrangement\SYNC_MusicStudio_PsdTransform.pas',
  SYNC_MusicStudio_EditHistory in '..\Source\Common\Project\SYNC_MusicStudio_EditHistory.pas',
  SYNC_MusicStudio_TransportThumbnailChecks in 'Visual\SYNC_MusicStudio_TransportThumbnailChecks.pas',
  SYNC_MusicStudio_LibraryThumbnails in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_LibraryThumbnails.pas',
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  System.SysUtils, System.IOUtils, Vcl.Forms, Vcl.Dialogs, System.UITypes,
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
  SYNC_MusicStudio_SettingsForm in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsForm.pas',
  SYNC_MusicStudio_SettingsDialogs in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsDialogs.pas',
  SYNC_MusicStudio_SettingsSlotMenus in '..\Source\Plugin\Filter\Settings\SYNC_MusicStudio_SettingsSlotMenus.pas',
  SYNC_MusicStudio_MotionData in '..\Source\Common\Motion\SYNC_MusicStudio_MotionData.pas',
  SYNC_MusicStudio_AnimationSync in '..\Source\Common\Motion\SYNC_MusicStudio_AnimationSync.pas',
  SYNC_MusicStudio_PerformanceTrace in '..\Source\Common\Diagnostics\SYNC_MusicStudio_PerformanceTrace.pas',
  SYNC_MusicStudio_AnimationSlotData in '..\Source\Common\Project\Performer\SYNC_MusicStudio_AnimationSlotData.pas',
  SYNC_MusicStudio_MotionFrame in '..\Source\Plugin\Filter\Patterns\Motion\SYNC_MusicStudio_MotionFrame.pas',
  SYNC_MusicStudio_MotionChecks in 'Model\SYNC_MusicStudio_MotionChecks.pas',
  SYNC_MusicStudio_ArtDocument in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtDocument.pas',
  SYNC_MusicStudio_ArtLayerName in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtLayerName.pas',
  SYNC_MusicStudio_ArtPsd in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtPsd.pas',
  SYNC_MusicStudio_ArtPsdOrigin in '..\Source\Common\Render\Layers\Model\SYNC_MusicStudio_ArtPsdOrigin.pas',
  SYNC_MusicStudio_PsdLayerConfig in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_PsdLayerConfig.pas',
  SYNC_MusicStudio_PsdLayerFrameUI in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_PsdLayerFrameUI.pas',
  SYNC_MusicStudio_PsdLayerJobs in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayerJobs.pas',
  SYNC_MusicStudio_PsdLayers in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdLayers.pas',
  SYNC_MusicStudio_LayerScale in '..\Source\Common\Render\Layers\Rules\SYNC_MusicStudio_LayerScale.pas',
  SYNC_MusicStudio_PsdLayersFrame in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_PsdLayersFrame.pas',
  SYNC_MusicStudio_PsdLayerChecks in 'Psd\SYNC_MusicStudio_PsdLayerChecks.pas',
  SYNC_MusicStudio_LibraryData in '..\Source\Common\Project\Library\SYNC_MusicStudio_LibraryData.pas',
  SYNC_MusicStudio_SharedLibraryEditor in '..\Source\Plugin\Filter\Patterns\Psd\SYNC_MusicStudio_SharedLibraryEditor.pas',
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\Library\SYNC_MusicStudio_SharedPsdLibrary.pas',
  SYNC_MusicStudio_SharedLibraryChecks in 'Model\SYNC_MusicStudio_SharedLibraryChecks.pas',
  SYNC_MusicStudio_BeatData in '..\Source\Common\Project\Timing\SYNC_MusicStudio_BeatData.pas',
  SYNC_MusicStudio_PerformanceFrame in '..\Source\Plugin\Filter\Patterns\Performance\SYNC_MusicStudio_PerformanceFrame.pas',
  SYNC_MusicStudio_BeatChecks in 'Timing\SYNC_MusicStudio_BeatChecks.pas',
  SYNC_MusicStudio_PsdSceneCache in '..\Source\Common\Render\Layers\SYNC_MusicStudio_PsdSceneCache.pas',
  SYNC_MusicStudio_PerformanceCache in '..\Source\Plugin\Filter\Library\SYNC_MusicStudio_PerformanceCache.pas',
  SYNC_MusicStudio_PsdSceneChecks in 'Scene\SYNC_MusicStudio_PsdSceneChecks.pas',
  SYNC_MusicStudio_PerformanceCacheChecks in 'Audio\SYNC_MusicStudio_PerformanceCacheChecks.pas',
  SYNC_MusicStudio_TimingFrame in '..\Source\Plugin\Filter\Patterns\Timing\SYNC_MusicStudio_TimingFrame.pas',
  TimingChecks in 'Timing\TimingChecks.pas',
  SYNC_MusicStudio_TestHelpers in 'Support\SYNC_MusicStudio_TestHelpers.pas',
  SYNC_MusicStudio_EditorModelChecks in 'Model\SYNC_MusicStudio_EditorModelChecks.pas',
  SYNC_MusicStudio_EditorInteractionChecks in 'Timeline\SYNC_MusicStudio_EditorInteractionChecks.pas',
  SYNC_MusicStudio_SlotChecks in 'Timeline\SYNC_MusicStudio_SlotChecks.pas',
  SYNC_MusicStudio_VisualCacheChecks in 'Visual\SYNC_MusicStudio_VisualCacheChecks.pas',
  SYNC_MusicStudio_PhraseRollChecks in 'Singing\SYNC_MusicStudio_PhraseRollChecks.pas',
  SYNC_MusicStudio_PsdRealAssetChecks in 'Psd\SYNC_MusicStudio_PsdRealAssetChecks.pas',
  SYNC_MusicStudio_NoAudioChecks in 'Core\SYNC_MusicStudio_NoAudioChecks.pas',
  SYNC_MusicStudio_PsdStorageChecks in 'Psd\SYNC_MusicStudio_PsdStorageChecks.pas',
  SYNC_MusicStudio_PsdDisplayChecks in 'Psd\SYNC_MusicStudio_PsdDisplayChecks.pas',
  SYNC_MusicStudio_PsdMouthChecks in 'Psd\SYNC_MusicStudio_PsdMouthChecks.pas',
  SYNC_MusicStudio_PsdPlaybackChecks in 'Scene\SYNC_MusicStudio_PsdPlaybackChecks.pas',
  SYNC_MusicStudio_ReviewChecks in 'Core\SYNC_MusicStudio_ReviewChecks.pas';
begin
  try
    SetTextCodePage(Output,65001); SetTextCodePage(ErrOutput,65001);
    Application.Initialize;
    if ParamStr(2)='--dark-scroll' then begin RunDarkScrollChecks(ParamStr(1)); RunSingingGestureChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--singing-gestures' then begin RunSingingGestureChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--singing-formats' then begin RunSingingFormatChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--lyric-timeline' then begin RunLyricTimelineChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--animation-cost' then begin RunAnimationCostChecks(ParamStr(1),ParamStr(3),ParamStr(4),ParamStr(5)); Exit; end;
    if ParamStr(2)='--animation-slots' then begin RunAnimationSlotChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--mouth-size' then begin RunStageChecks(ParamStr(1),ParamStr(3),True); Exit; end;
    if ParamStr(2)='--mouth-list' then begin RunPsdMouthListChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--audio-library' then begin RunAudioLibraryChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--stage-editor' then begin RunStageChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--snare-trace' then begin RunSnareTrace(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--snare-video-trace' then begin RunSnareVideoTrace(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--snare-frames' then begin ExportSnareFrames(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--instrument-end' then begin RunInstrumentEndChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-applied' then begin RunInstrumentAppliedChecks(ParamStr(1),ParamStr(3),ParamStr(4),ParamStr(5)); Exit; end;
    if ParamStr(2)='--instrument-phases' then begin RunInstrumentPhaseChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-resonance' then begin RunInstrumentResonanceChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-cymbal' then begin RunInstrumentCymbalVisibilityChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--psd-render-cost' then begin RunPsdRenderCostChecks(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--instrument-effects' then begin RunInstrumentEffectChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-repeat' then begin RunInstrumentRepeatChecks(ParamStr(1),ParamStr(3),ParamStr(4)='all'); Exit; end;
    if ParamStr(2)='--psd-render-core' then begin RunMusicStudioPsdLayerChecks(ParamStr(1),False); RunMusicStudioPsdSceneChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--psd-sampled' then begin RunPsdSampledChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--bass-pedal-candidate' then begin BuildBassPedalCandidate(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--bass-assignment' then begin RunBassAssignmentChecks(ParamStr(1),ParamStr(3),ParamStr(4),ParamStr(5),ParamStr(6)='moving'); Exit; end;
    if ParamStr(2)='--hihat-pedal-candidate' then begin BuildHiHatPedalCandidate(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--hihat-routing' then begin RunHiHatRoutingChecks(ParamStr(1),ParamStr(3),ParamStr(4),ParamStr(5)); Exit; end;
    if ParamStr(2)='--hihat' then begin InspectHiHat(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--hihat-candidate' then begin BuildHiHatCandidate(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--bass-rest-candidate' then begin BuildBassRestCandidate(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--drum-rest' then begin InspectBassRest(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-gestures' then begin RunInstrumentGestureChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--instrument-preview' then begin RunInstrumentPreviewChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--psd-list' then begin RunPsdListChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--psd-drop' then begin RunPsdDropChecks(ParamStr(1),ParamStr(3),ParamStr(4)); Exit; end;
    if ParamStr(2)='--compact-editor' then begin RunCompactEditorChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--slot-ui' then begin RunSlotUIChecks(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--performer-management' then begin RunPerformerChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--instrument' then begin RunInstrumentChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--instrument-psd' then begin InspectInstrumentPSD(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--drum-rules' then begin RunDrumPsdChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--drum-psd' then begin InspectDrumPsd(ParamStr(1),ParamStr(3)); Exit; end;
    if ParamStr(2)='--drums' then begin RunDrumChecks(ParamStr(1)); Exit; end;
    if ParamStr(2)='--drum-regression' then begin
      ForceDirectories(ParamStr(1));
      RunEditorModelChecks(ParamStr(1)); RunEditorInteractionChecks(ParamStr(1));
      RunSlotChecks(ParamStr(1)); RunBeatChecks(ParamStr(1)); RunPerformanceCacheChecks(ParamStr(1));
      RunMusicStudioPsdLayerChecks(ParamStr(1),False);
      RunNoAudioChecks(ParamStr(1)); RunReviewChecks(ParamStr(1)); Exit;
    end;
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
    RunDrumChecks(ParamStr(1));
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
