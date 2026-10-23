unit SYNC_MusicStudio_TimelineContent;

// 拍軸へ波形/MIDI/演奏タイルを描く。tempo境界ごとに秒→pixelを分け、既存解析/cacheを再利用。
interface
uses System.Types, Vcl.Graphics, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_TimelineMetrics, SYNC_MusicStudio_WaveCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PerformanceCache;
procedure DrawMusicStudioTimelineContent(Canvas: TCanvas; const Metrics: TMusicStudioTimelineMetrics;
  const Clip: TMusicStudioPlacement; const Pattern: TMusicStudioPattern; const Bounds,Visible: TRect;
  Wave: TMusicStudioWaveCache; Visual: TMusicStudioVisualCache; Performance: TMusicStudioPerformanceCache;
  PPI: Integer; Background,Foreground: TColor);
implementation
uses System.Math, SYNC_MusicStudio_BeatData;
procedure DrawMusicStudioTimelineContent(Canvas: TCanvas; const Metrics: TMusicStudioTimelineMetrics;
  const Clip: TMusicStudioPlacement; const Pattern: TMusicStudioPattern; const Bounds,Visible: TRect;
  Wave: TMusicStudioWaveCache; Visual: TMusicStudioVisualCache; Performance: TMusicStudioPerformanceCache;
  PPI: Integer; Background,Foreground: TColor);
var First,Last,StartSeconds,EndSeconds,Next,Scale,Base: Double; I: Integer; R,Area,Allowed: TRect;
  Map: TMusicStudioTempoMap;
begin
  if not IntersectRect(Allowed,Bounds,Visible) or (Metrics.Document=nil) then Exit;
  Map := Metrics.Document.Timing; Base := Clip.StartSeconds;
  First := Max(Base,Metrics.SecondsAtX(Allowed.Left)); Last := Min(Base+Clip.LengthSeconds,Metrics.SecondsAtX(Allowed.Right));
  StartSeconds := First;
  while StartSeconds<Last-1E-12 do begin
    EndSeconds := Last;
    for I := 0 to Map.PointCount-1 do begin Next := Map.TempoPoint(I).StartSeconds;
      if (Next>StartSeconds+1E-10) and (Next<EndSeconds) then EndSeconds := Next;
    end;
    Scale := Metrics.PixelsPerBeat*Map.BPMAt(Map.SecondsToBeat(StartSeconds+1E-10))/60;
    Area := Bounds; Area.Left := Max(Allowed.Left,Metrics.XAtSeconds(StartSeconds)); Area.Right := Min(Allowed.Right,Metrics.XAtSeconds(EndSeconds));
    R := Bounds; R.Left := Round(EnsureRange(Metrics.XAtSeconds(StartSeconds)-(StartSeconds-Base)*Scale,-500000000.0,500000000.0));
    R.Right := R.Left+Max(1,Ceil(Min(1000000000.0,Clip.LengthSeconds*Scale)));
    if Pattern.Kind='singing' then R.Left := Round(EnsureRange(R.Left-Pattern.SourceStartSeconds*Scale,-500000000.0,500000000.0));
    if Pattern.Kind='audio' then Wave.Draw(Canvas,R,Area,Wave.Find(Pattern.FilePath),Scale,Pattern.Volume,PPI,Background,Foreground)
    else if Pattern.Kind='singing' then Visual.DrawRoll(Canvas,R,Area,Visual.Find(vkMidi,Pattern.FilePath),Pattern.SourceTrack,Scale,PPI,Background,Foreground)
    else Performance.Draw(Canvas,R,Area,Pattern.ID,Clip.StartBeat,Scale,PPI,Background,Foreground);
    StartSeconds := EndSeconds;
  end;
end;
end.
