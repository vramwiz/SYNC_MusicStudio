unit SYNC_MusicStudio_TimelineMetrics;

// 小節/拍の座標系。秒正本の素材も有効tempoで投影し、表示だけでデータを変更しない。
interface
uses System.Types, SYNC_MusicStudio_PatternData;
type
  TMusicStudioTimelineMetrics = record
    Document: TMusicStudioDocument;
    Header,ScrollTicks,PPI: Integer;
    Zoom: Double; // 既存SetZoom APIの値。40は20論理px/四分拍。
    function PixelsPerBeat: Double;
    function FirstBeat: Double;
    function BeatAtX(X: Integer): Double;
    function SecondsAtX(X: Integer): Double;
    function XAtBeat(Beat: Double): Integer;
    function XAtSeconds(Seconds: Double): Integer;
    function SnapStep: Double;
    function SnapBeat(Beat: Double): Double;
    function BeatLabel(Beat: Double): string;
  end;
implementation
uses System.SysUtils, System.Math, SYNC_MusicStudio_BeatData;
function TMusicStudioTimelineMetrics.PixelsPerBeat: Double;
begin Result := Zoom/2*PPI/96; end;
function TMusicStudioTimelineMetrics.FirstBeat: Double;
begin Result := ScrollTicks/64; end;
function TMusicStudioTimelineMetrics.BeatAtX(X: Integer): Double;
begin Result := Max(0.0,FirstBeat+(X-Header)/PixelsPerBeat); end;
function TMusicStudioTimelineMetrics.SecondsAtX(X: Integer): Double;
begin if Document=nil then Exit(0); Result := Document.BeatToSeconds(BeatAtX(X)); end;
function TMusicStudioTimelineMetrics.XAtBeat(Beat: Double): Integer;
begin Result := Round(EnsureRange(Header+(Beat-FirstBeat)*PixelsPerBeat,-500000000.0,500000000.0)); end;
function TMusicStudioTimelineMetrics.XAtSeconds(Seconds: Double): Integer;
begin if Document=nil then Exit(Header); Result := XAtBeat(Document.SecondsToBeat(Seconds)); end;
function TMusicStudioTimelineMetrics.SnapStep: Double;
var Measure: Double;
begin
  if Document=nil then Exit(1); Measure := Document.Timing.MeasureLengthAtBeat(FirstBeat);
  Result := Measure;
  if Zoom/2*Measure>=64 then Result := MusicStudioSnapStep(Zoom/2)
  else while Zoom/2*Result<32 do Result := Result*2;
end;
function TMusicStudioTimelineMetrics.SnapBeat(Beat: Double): Double;
begin Result := Max(0.0,MusicStudioSnapBeat(Beat,SnapStep)); end;
function TMusicStudioTimelineMetrics.BeatLabel(Beat: Double): string;
var BeatUnit,Position: Double; Number: Integer;
begin
  BeatUnit := 4/Document.Timing.DenominatorAtBeat(Beat);
  Number := Document.Timing.MeasureAtBeat(Beat); Position := Document.Timing.BeatInMeasure(Beat);
  if Abs(Position)<1E-8 then Result := IntToStr(Number)+'小節'
  else Result := IntToStr(Number)+':'+FloatToStr(1+Position/BeatUnit,TFormatSettings.Invariant);
end;
end.
