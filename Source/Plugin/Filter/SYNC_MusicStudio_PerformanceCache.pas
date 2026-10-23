unit SYNC_MusicStudio_PerformanceCache;

// 演奏パターンの拍索引と描画タイルをUIスレッドで共有する。
// JSON解析・テンポsnapshotはSetPatternsだけ。Drawは文書やファイルへアクセスしない。
// 単調なテンポ表を使い、タイル可視秒→拍から重なる音符だけを索引で取得する。
interface

uses System.Types, System.Generics.Collections, Winapi.Windows, Vcl.Graphics,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_BitmapCache, SYNC_MusicStudio_LayerStepData, SYNC_MusicStudio_TempoPatternData,
  SYNC_MusicStudio_InstrumentData;

type
  TMusicStudioPerformanceSource = class
    ConfigJSON, Message: string;
    Revision, PitchLow, PitchHigh, PitchSpan: Integer;
    Notes: TArray<TMusicStudioPerformanceNote>; // 開始拍順。
    Steps: TMusicStudioLayerStepData;
    Tempo: TMusicStudioTempoPatternData;
    Instrument: TMusicStudioInstrumentData; // 共通区間のsnapshot。PaintでJSONを読まない。
    InstrumentRows: TArray<string>;
    PrefixEnd: TArray<Double>; // 開始順に求めた最大終了拍。
    function FirstOverlap(Beat: Double): Integer;
    procedure Build(const Text: string; IsTempo: Boolean = False);
    destructor Destroy; override;
  end;

  TMusicStudioPerformanceCache = class
  private
    FSources: TObjectDictionary<string,TMusicStudioPerformanceSource>;
    FTiming: TMusicStudioTempoMap;
    FTimingJSON: string;
    FBitmaps: TMusicStudioBitmapCache;
    FRevision, FTimingRevision, FParseCount, FTimingParseCount, FRasterCount: Integer;
    function Tile(Source: TMusicStudioPerformanceSource; Index, Height, PPI: Integer;
      StartBeat, PixelsPerSecond: Double; Background, Foreground: TColor): TBitmap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure SetPatterns(Document: TMusicStudioDocument);
    procedure Draw(Canvas: TCanvas; const R, VisibleArea: TRect; const PatternID: string;
      StartBeat, PixelsPerSecond: Double; PPI: Integer; Background, Foreground: TColor);
    function PatternMessage(const PatternID: string): string;
    function SourceCount: Integer;
    function TileCount: Integer;
    property ParseCount: Integer read FParseCount;
    property TimingParseCount: Integer read FTimingParseCount;
    property RasterCount: Integer read FRasterCount;
  end;

implementation

uses System.SysUtils, System.Math, System.Generics.Defaults;

function TMusicStudioPerformanceSource.FirstOverlap(Beat: Double): Integer;
var HighIndex, Mid: Integer;
begin
  Result := 0; HighIndex := Length(Notes);
  while Result < HighIndex do begin
    Mid := (Result+HighIndex) div 2;
    if PrefixEnd[Mid] <= Beat then Result := Mid+1 else HighIndex := Mid;
  end;
end;

procedure TMusicStudioPerformanceSource.Build(const Text: string; IsTempo: Boolean);
const MinimumPitchSpan = 5;
var Data: TMusicStudioPerformanceData; I,Lowest,Highest: Integer; EndBeat: Double;
  Block: TInstrumentBlock; Row: string; Found: Boolean;
begin
  ConfigJSON := Text; Message := '';
  FreeAndNil(Steps); Steps := TMusicStudioLayerStepData.Create;
  FreeAndNil(Tempo);
  FreeAndNil(Instrument); InstrumentRows := nil;
  if not IsTempo and MusicStudioHasInstrumentTimeline(Text) then begin
    Instrument := TMusicStudioInstrumentData.Create;
    try
      Instrument.Load(Text);
      for Block in Instrument.Blocks do begin
        Found := False; for Row in InstrumentRows do if Row=Block.Row then Found := True;
        if not Found then InstrumentRows := InstrumentRows+[Block.Row];
      end;
    except on E: Exception do Message := E.Message; end;
    Notes := nil; PrefixEnd := nil; PitchLow := 0; PitchSpan := Max(1,Length(InstrumentRows)); PitchHigh := PitchSpan-1; Exit;
  end;
  if IsTempo then begin
    Tempo := TMusicStudioTempoPatternData.Create;
    try Tempo.LoadJSON(Text); Message := ''; except on E: Exception do Message := E.Message; end;
    Notes := nil; PrefixEnd := nil; PitchLow := 0; PitchHigh := 4; PitchSpan := 5; Exit;
  end;
  Data := TMusicStudioPerformanceData.Create;
  try
    try
      Data.LoadJSON(Text); Steps.LoadJSON(Text); Lowest := Data.LowestPitch; Highest := Data.HighestPitch;
      SetLength(Notes,Data.NoteCount);
      for I := 0 to Data.NoteCount-1 do Notes[I] := Data.NoteAt(I);
      TArray.Sort<TMusicStudioPerformanceNote>(Notes,TComparer<TMusicStudioPerformanceNote>.Construct(
        function(const Left, Right: TMusicStudioPerformanceNote): Integer
        begin
          if Left.StartBeat < Right.StartBeat then Result := -1
          else if Left.StartBeat > Right.StartBeat then Result := 1 else Result := 0;
        end));
      SetLength(PrefixEnd,Length(Notes)); EndBeat := 0;
      for I := 0 to High(Notes) do begin
        EndBeat := Max(EndBeat,Notes[I].StartBeat+Notes[I].LengthBeats); PrefixEnd[I] := EndBeat;
      end;
      if Length(Notes) = 0 then begin PitchLow := 0; PitchHigh := MinimumPitchSpan-1; end
      else begin
        PitchLow := Max(0,Lowest-1); PitchHigh := Min(127,Highest+1);
        if PitchHigh-PitchLow+1 < MinimumPitchSpan then begin
          PitchLow := Max(0,PitchLow-(MinimumPitchSpan-(PitchHigh-PitchLow+1)+1) div 2);
          PitchHigh := Min(127,PitchLow+MinimumPitchSpan-1); PitchLow := Max(0,PitchHigh-MinimumPitchSpan+1);
        end;
      end;
      PitchSpan := PitchHigh-PitchLow+1;
    except on E: Exception do begin
      Message := E.Message; Notes := nil; PrefixEnd := nil; PitchLow := 0; PitchHigh := 4; PitchSpan := 5;
    end; end;
  finally Data.Free; end;
end;
destructor TMusicStudioPerformanceSource.Destroy;
begin Instrument.Free; Tempo.Free; Steps.Free; inherited; end;

constructor TMusicStudioPerformanceCache.Create;
begin
  inherited;
  FSources := TObjectDictionary<string,TMusicStudioPerformanceSource>.Create([doOwnsValues]);
  FTiming := TMusicStudioTempoMap.Create; FBitmaps := TMusicStudioBitmapCache.Create;
end;

destructor TMusicStudioPerformanceCache.Destroy;
begin FBitmaps.Free; FTiming.Free; FSources.Free; inherited; end;

procedure TMusicStudioPerformanceCache.Clear;
begin
  FBitmaps.Clear; FSources.Clear; FTiming.Free; FTiming := TMusicStudioTempoMap.Create;
  FTimingJSON := ''; Inc(FRevision); Inc(FTimingRevision);
end;

procedure TMusicStudioPerformanceCache.SetPatterns(Document: TMusicStudioDocument);
var Seen: TDictionary<string,Boolean>; Pattern: TMusicStudioPattern;
  Source: TMusicStudioPerformanceSource; Keys: TArray<string>; Key, TimingText: string; I: Integer;
  Candidate: TMusicStudioTempoMap;
begin
  if Document = nil then begin Clear; Exit; end;
  if Document.Timing <> nil then TimingText := Document.Timing.TimingJSON else TimingText := '';
  if TimingText <> FTimingJSON then begin
    Candidate := TMusicStudioTempoMap.Create;
    try
      Candidate.LoadJSON(TimingText); Inc(FTimingParseCount);
      FTiming.Free; FTiming := Candidate; Candidate := nil; FTimingJSON := TimingText;
      Inc(FTimingRevision); FBitmaps.Clear;
    finally Candidate.Free; end;
  end;
  Seen := TDictionary<string,Boolean>.Create;
  try
    for I := 0 to Document.PatternCount-1 do begin
      Pattern := Document.PatternAt(I); if (Pattern.Kind<>'performance') and (Pattern.Kind<>'tempo') then Continue;
      Seen.AddOrSetValue(Pattern.ID,True);
      if FSources.TryGetValue(Pattern.ID,Source) and (Source.ConfigJSON = Pattern.ConfigJSON) then Continue;
      Source := TMusicStudioPerformanceSource.Create;
      try
        Source.Build(Pattern.ConfigJSON,Pattern.Kind='tempo'); Inc(FParseCount); Inc(FRevision); Source.Revision := FRevision;
        FSources.AddOrSetValue(Pattern.ID,Source); Source := nil;
      finally Source.Free; end;
    end;
    Keys := FSources.Keys.ToArray;
    for Key in Keys do if not Seen.ContainsKey(Key) then FSources.Remove(Key);
  finally Seen.Free; end;
end;

function TMusicStudioPerformanceCache.PatternMessage(const PatternID: string): string;
var Source: TMusicStudioPerformanceSource;
begin
  if not FSources.TryGetValue(PatternID,Source) then Exit('パターン参照切れ');
  if Source.Message <> '' then Exit(Source.Message);
  if Source.Instrument<>nil then begin
    if Source.Instrument.Blocks.Count=0 then Exit('演奏区間なし') else Exit('');
  end;
  if Source.Tempo<>nil then Exit('');
  if (Source.Steps<>nil) and Source.Steps.Enabled then begin
    if Source.Steps.StepCount=0 then Exit('stepなし') else Exit('');
  end;
  if Length(Source.Notes) = 0 then Exit('音符なし');
  Result := '';
end;

function TMusicStudioPerformanceCache.Tile(Source: TMusicStudioPerformanceSource;
  Index, Height, PPI: Integer; StartBeat, PixelsPerSecond: Double;
  Background, Foreground: TColor): TBitmap;
var Key: string; Bitmap: TBitmap; I,Y,Margin,InnerHeight,NoteHeight,LeftX,RightX: Integer;
  TileStart,TileEnd,BaseSeconds,StartLocalBeat,EndLocalBeat,StartSeconds,EndSeconds,Center: Double;
  Note: TMusicStudioPerformanceNote; R: TRect; Step: TMusicStudioLayerStep; Point: TMusicStudioTempoPoint; EndPoint: Double;
  Block: TInstrumentBlock; Lane: Integer;
begin
  Key := 'e:'+IntToStr(Source.Revision)+':'+IntToStr(FTimingRevision)+':'+
    MusicStudioDoubleKey(StartBeat)+':'+IntToStr(Index)+':'+IntToStr(Height)+':'+IntToStr(PPI)+':'+
    MusicStudioDoubleKey(PixelsPerSecond)+':'+IntToStr(Background)+':'+IntToStr(Foreground);
  Result := FBitmaps.Find(Key); if Result <> nil then Exit;
  Margin := Min(Max(1,MulDiv(1,PPI,96)),(Height-1) div 2);
  InnerHeight := Height-2*Margin;
  NoteHeight := Min(InnerHeight,Max(Max(1,MulDiv(2,PPI,96)),Ceil(InnerHeight/Source.PitchSpan)));
  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(256,Height);
    Bitmap.Canvas.Brush.Color := Background; Bitmap.Canvas.FillRect(Rect(0,0,256,Height));
    Bitmap.Canvas.Pen.Color := Background xor $00181818;
    for I := Source.PitchLow to Source.PitchHigh do if I mod 12 = 0 then begin
      Y := Margin+(Source.PitchHigh-I)*InnerHeight div Source.PitchSpan;
      Bitmap.Canvas.MoveTo(0,Y); Bitmap.Canvas.LineTo(256,Y);
    end;
    BaseSeconds := FTiming.BeatToSeconds(StartBeat);
    TileStart := Int64(Index)*256/PixelsPerSecond; TileEnd := (Int64(Index)+1)*256/PixelsPerSecond;
    StartLocalBeat := FTiming.SecondsToBeat(BaseSeconds+TileStart)-StartBeat;
    EndLocalBeat := FTiming.SecondsToBeat(BaseSeconds+TileEnd)-StartBeat;
    if Source.Instrument<>nil then for Block in Source.Instrument.Blocks do begin
      if (Block.StartBeat>=EndLocalBeat) or (Block.EndBeat<=StartLocalBeat) then Continue;
      Lane := 0; for I := 0 to High(Source.InstrumentRows) do if Source.InstrumentRows[I]=Block.Row then Lane := I;
      StartSeconds := FTiming.BeatToSeconds(StartBeat+Block.StartBeat)-BaseSeconds;
      EndSeconds := FTiming.BeatToSeconds(StartBeat+Block.EndBeat)-BaseSeconds;
      LeftX := Floor(EnsureRange(StartSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
      RightX := Ceil(EnsureRange(EndSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
      Y := Margin+Lane*InnerHeight div Source.PitchSpan;
      Bitmap.Canvas.Brush.Color := Foreground;
      Bitmap.Canvas.FillRect(Rect(LeftX,Y,Max(LeftX+1,RightX),Max(Y+1,Margin+(Lane+1)*InnerHeight div Source.PitchSpan)));
    end;
    if Source.Tempo<>nil then for I := 0 to Source.Tempo.Timing.PointCount-1 do begin
      Point := Source.Tempo.Timing.TempoPoint(I); EndPoint := Source.Tempo.LengthBeats;
      if I+1<Source.Tempo.Timing.PointCount then EndPoint := Source.Tempo.Timing.TempoPoint(I+1).Beat;
      if (Point.Beat>=EndLocalBeat) or (EndPoint<=StartLocalBeat) then Continue;
      StartSeconds := FTiming.BeatToSeconds(StartBeat+Point.Beat)-BaseSeconds;
      EndSeconds := FTiming.BeatToSeconds(StartBeat+EndPoint)-BaseSeconds;
      LeftX := Floor(EnsureRange(StartSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0)); RightX := Ceil(EnsureRange(EndSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
      Y := Margin+Round((1-Min(1.0,Point.BPM/300))*Max(1,InnerHeight-1));
      Bitmap.Canvas.Brush.Color := Foreground; Bitmap.Canvas.FillRect(Rect(LeftX,Y,Max(LeftX+1,RightX),Height-Margin));
    end;
    if Assigned(Source.Steps) and Source.Steps.Enabled then
      for I := 0 to Source.Steps.StepCount-1 do begin
        Step := Source.Steps.StepAt(I);
        if (Step.StartBeat>=EndLocalBeat) or (Step.StartBeat+Step.LengthBeats<=StartLocalBeat) then Continue;
        StartSeconds := FTiming.BeatToSeconds(StartBeat+Step.StartBeat)-BaseSeconds;
        EndSeconds := FTiming.BeatToSeconds(StartBeat+Step.StartBeat+Step.LengthBeats)-BaseSeconds;
        LeftX := Floor(EnsureRange(StartSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
        RightX := Ceil(EnsureRange(EndSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
        Bitmap.Canvas.Brush.Color := Foreground;
        Bitmap.Canvas.FillRect(Rect(LeftX,Margin,Max(LeftX+1,RightX),Height-Margin));
        Bitmap.Canvas.Pen.Color := Background; Bitmap.Canvas.MoveTo(LeftX,Margin); Bitmap.Canvas.LineTo(LeftX,Height-Margin);
      end;
    I := Source.FirstOverlap(StartLocalBeat); Bitmap.Canvas.Brush.Color := Foreground;
    while I < Length(Source.Notes) do begin
      Note := Source.Notes[I]; if Note.StartBeat >= EndLocalBeat then Break;
      if Note.StartBeat+Note.LengthBeats > StartLocalBeat then begin
        StartSeconds := FTiming.BeatToSeconds(StartBeat+Note.StartBeat)-BaseSeconds;
        EndSeconds := FTiming.BeatToSeconds(StartBeat+Note.StartBeat+Note.LengthBeats)-BaseSeconds;
        Center := Margin+(Source.PitchHigh-Note.Pitch+0.5)*InnerHeight/Source.PitchSpan;
        Y := EnsureRange(Round(Center-NoteHeight/2),Margin,Height-Margin-NoteHeight);
        LeftX := Floor(EnsureRange(StartSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
        RightX := Ceil(EnsureRange(EndSeconds*PixelsPerSecond-Int64(Index)*256,0.0,256.0));
        R := Rect(LeftX,Y,Max(LeftX+1,RightX),Y+NoteHeight); Bitmap.Canvas.FillRect(R);
      end; Inc(I);
    end;
    FBitmaps.Add(Key,Bitmap); Inc(FRasterCount); Result := Bitmap;
  except Bitmap.Free; raise; end;
end;

procedure TMusicStudioPerformanceCache.Draw(Canvas: TCanvas; const R, VisibleArea: TRect;
  const PatternID: string; StartBeat, PixelsPerSecond: Double; PPI: Integer;
  Background, Foreground: TColor);
var Visible: TRect; Source: TMusicStudioPerformanceSource; I,First,Last,Saved: Integer;
begin
  if (Canvas = nil) or (R.Width < 1) or (R.Height < 1) or (PixelsPerSecond <= 0) or
    IsNan(PixelsPerSecond) or IsInfinite(PixelsPerSecond) or IsNan(StartBeat) or
    IsInfinite(StartBeat) or not FSources.TryGetValue(PatternID,Source) or
    (Source.Message <> '') or not IntersectRect(Visible,R,VisibleArea) then Exit;
  First := Max(0,(Visible.Left-R.Left) div 256); Last := Max(First,(Visible.Right-1-R.Left) div 256);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Visible.Left,Visible.Top,Visible.Right,Visible.Bottom);
    for I := First to Last do Canvas.Draw(R.Left+I*256,R.Top,
      Tile(Source,I,R.Height,PPI,StartBeat,PixelsPerSecond,Background,Foreground));
  finally RestoreDC(Canvas.Handle,Saved); end;
end;

function TMusicStudioPerformanceCache.SourceCount: Integer;
begin Result := FSources.Count; end;
function TMusicStudioPerformanceCache.TileCount: Integer;
begin Result := FBitmaps.Count; end;

end.
