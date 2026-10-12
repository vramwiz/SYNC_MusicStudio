unit SYNC_MusicStudio_WaveCache;

// 編集画面の音源別包絡線と表示タイル。UIスレッド所有、PaintではIO/デコードを行わない。
// ジョブはフォームへのQueue/参照を持たず、世代・ファイル識別情報を確認して採用する。
interface
uses System.Classes, System.Generics.Collections, System.Types, Winapi.Windows, Vcl.Graphics,
  SYNC_MusicStudio_AudioWaveform, SYNC_MusicStudio_BitmapCache;
type
  TMusicStudioWaveStatus = (wsUnselected, wsPending, wsReady, wsSilent, wsMissing, wsBroken);
  TMusicStudioWaveSource = class
  public
    Path, Fingerprint, Message: string;
    Revision: Integer;
    Visible: Boolean;
    Status: TMusicStudioWaveStatus;
    Wave: TMusicStudioWaveform;
    Info: TMusicStudioAudioInfo;
    Job: TMusicStudioWaveJob;
  end;
  TMusicStudioWaveCache = class
  private
    FSources: TObjectDictionary<string,TMusicStudioWaveSource>;
    FTiles: TMusicStudioBitmapCache;
    FRetired: TObjectList<TMusicStudioWaveJob>;
    FRevision, FDecodeCount, FRasterCount, FDiscardCount: Integer;
    function Key(const Path: string): string;
    procedure Retire(Source: TMusicStudioWaveSource);
    function CheckFile(Source: TMusicStudioWaveSource): Boolean;
    procedure StartJobs;
    function Tile(Source: TMusicStudioWaveSource; Index, Height, PPI: Integer;
      PixelsPerSecond, Volume: Double; Background, Foreground: TColor): TBitmap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    // AllPathsの参照だけを保持し、VisiblePathsだけを優先して最大2ジョブを起動する。
    procedure SetSources(const AllPaths, VisiblePaths: TArray<string>);
    function Poll(CheckFiles: Boolean = False): Boolean;
    function Find(const Path: string): TMusicStudioWaveSource;
    // R.Leftが音源の0秒。配置の長さでクリップし、音源終端以後を引き伸ばさない。
    procedure Draw(Canvas: TCanvas; const R, VisibleArea: TRect; Source: TMusicStudioWaveSource;
      PixelsPerSecond, Volume: Double; PPI: Integer; Background, Foreground: TColor);
    function ActiveJobs: Integer;
    function TileCount: Integer;
    property DecodeCount: Integer read FDecodeCount;
    property RasterCount: Integer read FRasterCount;
    property DiscardCount: Integer read FDiscardCount;
  end;
implementation
uses System.SysUtils, System.Math;
const TILE_WIDTH = 256;
constructor TMusicStudioWaveCache.Create;
begin
  inherited;
  FSources := TObjectDictionary<string,TMusicStudioWaveSource>.Create([doOwnsValues]);
  FTiles := TMusicStudioBitmapCache.Create;
  FRetired := TObjectList<TMusicStudioWaveJob>.Create(True);
end;
function TMusicStudioWaveCache.Key(const Path: string): string;
begin
  Result := MusicStudioPathKey(Path);
end;
procedure TMusicStudioWaveCache.Retire(Source: TMusicStudioWaveSource);
begin
  if Assigned(Source.Job) then begin
    Source.Job.Terminate; FRetired.Add(Source.Job); Source.Job := nil; Inc(FDiscardCount);
  end;
end;
procedure TMusicStudioWaveCache.Clear;
var Source: TMusicStudioWaveSource;
begin
  for Source in FSources.Values do Retire(Source);
  FSources.Clear; FTiles.Clear; Inc(FRevision);
end;
destructor TMusicStudioWaveCache.Destroy;
begin
  Clear; FRetired.Free; FTiles.Free; FSources.Free; inherited;
end;
function TMusicStudioWaveCache.CheckFile(Source: TMusicStudioWaveSource): Boolean;
var Stamp: string;
begin
  Stamp := MusicStudioFileStamp(Source.Path);
  Result := (Source.Revision = 0) or (Stamp <> Source.Fingerprint);
  if not Result then Exit;
  Retire(Source); Inc(FRevision); Source.Revision := FRevision;
  Source.Fingerprint := Stamp; Source.Wave := nil; Source.Info := Default(TMusicStudioAudioInfo);
  FTiles.Clear;
  if Source.Path = '' then begin Source.Status := wsUnselected; Source.Message := '音源未選択'; end
  else if Stamp = '' then begin Source.Status := wsMissing; Source.Message := '音源が見つかりません'; end
  else begin Source.Status := wsPending; Source.Message := '波形を解析中…'; end;
end;
procedure TMusicStudioWaveCache.SetSources(const AllPaths, VisiblePaths: TArray<string>);
var Wanted: TDictionary<string,Boolean>; Path,K: string; Source: TMusicStudioWaveSource;
begin
  Wanted := TDictionary<string,Boolean>.Create;
  try
    for Path in AllPaths do Wanted.AddOrSetValue(Key(Path),True);
    for K in FSources.Keys.ToArray do if not Wanted.ContainsKey(K) then begin
      Retire(FSources[K]); FSources.Remove(K); FTiles.Clear;
    end;
    for Path in AllPaths do begin
      K := Key(Path);
      if not FSources.TryGetValue(K,Source) then begin
        Source := TMusicStudioWaveSource.Create; Source.Path := Path; FSources.Add(K,Source); CheckFile(Source);
      end;
      Source.Visible := False;
    end;
    for Path in VisiblePaths do if FSources.TryGetValue(Key(Path),Source) then Source.Visible := True;
    StartJobs;
  finally Wanted.Free; end;
end;
function TMusicStudioWaveCache.ActiveJobs: Integer;
var Source: TMusicStudioWaveSource;
begin
  Result := FRetired.Count;
  for Source in FSources.Values do if Assigned(Source.Job) then Inc(Result);
end;
function TMusicStudioWaveCache.TileCount: Integer;
begin Result := FTiles.Count; end;
procedure TMusicStudioWaveCache.StartJobs;
var Source: TMusicStudioWaveSource; Count: Integer;
begin
  Count := ActiveJobs;
  for Source in FSources.Values do begin
    if Count >= 2 then Break;
    if Source.Visible and (Source.Status = wsPending) and (Source.Job = nil) then begin
      Source.Job := TMusicStudioWaveJob.Create(Source.Path,Source.Revision);
      Source.Job.Start; Inc(FDecodeCount); Inc(Count);
    end;
  end;
end;
function TMusicStudioWaveCache.Poll(CheckFiles: Boolean): Boolean;
var Source: TMusicStudioWaveSource; Job: TMusicStudioWaveJob; I: Integer; Point: TMusicStudioWavePoint;
begin
  Result := False;
  for I := FRetired.Count-1 downto 0 do if FRetired[I].Done then FRetired.Delete(I);
  for Source in FSources.Values do begin
    if CheckFiles and CheckFile(Source) then Result := True;
    Job := Source.Job;
    if (Job = nil) or not Job.Done then Continue;
    // デコード中に外部更新されたファイルの結果は採用しない。次の世代で読み直す。
    if (Job.RequestID <> Source.Revision) or (Job.FilePath <> Source.Path) or CheckFile(Source) then begin
      Result := True; Continue;
    end;
    Source.Job := nil;
    Source.Wave := Job.Waveform; Source.Info := Job.Info; Source.Message := Job.ErrorText;
    if Source.Message <> '' then Source.Status := wsBroken else begin
      Source.Status := wsSilent;
      for Point in Source.Wave do if (Point.Minimum <> 0) or (Point.Maximum <> 0) then begin Source.Status := wsReady; Break; end;
      if Source.Status = wsSilent then Source.Message := '無音';
    end;
    Job.Free; Result := True;
  end;
  StartJobs;
end;
function TMusicStudioWaveCache.Find(const Path: string): TMusicStudioWaveSource;
begin if not FSources.TryGetValue(Key(Path),Result) then Result := nil; end;
function TMusicStudioWaveCache.Tile(Source: TMusicStudioWaveSource; Index, Height, PPI: Integer;
  PixelsPerSecond, Volume: Double; Background, Foreground: TColor): TBitmap;
var K: string; Bitmap: TBitmap;
  X,I,First,Last,MidY,Amp: Integer; Lo,Hi: Single; Time: Double;
begin
  K := IntToStr(Source.Revision)+':'+IntToStr(Index)+':'+IntToStr(Height)+':'+IntToStr(PPI)+':'+
    MusicStudioDoubleKey(PixelsPerSecond)+':'+MusicStudioDoubleKey(Volume)+':'+IntToStr(Background)+':'+IntToStr(Foreground);
  Result := FTiles.Find(K); if Assigned(Result) then Exit;
  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(TILE_WIDTH,Height);
    Bitmap.Canvas.Brush.Color := Background; Bitmap.Canvas.FillRect(Rect(0,0,TILE_WIDTH,Height));
    Bitmap.Canvas.Pen.Color := Foreground; MidY := Height div 2; Amp := Max(1,MidY-1);
    for X := 0 to TILE_WIDTH-1 do begin
      Time := (Int64(Index)*TILE_WIDTH+X)/PixelsPerSecond;
      if (Time < 0) or (Time >= Source.Info.Duration) then Continue;
      First := EnsureRange(Floor(Time/Source.Info.Duration*Length(Source.Wave)),0,High(Source.Wave));
      Last := Min(Length(Source.Wave),Max(First+1,Ceil((Time+1/PixelsPerSecond)/Source.Info.Duration*Length(Source.Wave))));
      Lo := 1; Hi := -1;
      for I := First to Last-1 do begin Lo := Min(Lo,Source.Wave[I].Minimum); Hi := Max(Hi,Source.Wave[I].Maximum); end;
      Bitmap.Canvas.MoveTo(X,MidY-Round(EnsureRange(Hi*Volume,-1.0,1.0)*Amp));
      Bitmap.Canvas.LineTo(X,MidY-Round(EnsureRange(Lo*Volume,-1.0,1.0)*Amp)+1);
    end;
    FTiles.Add(K,Bitmap); Inc(FRasterCount); Result := Bitmap;
  except Bitmap.Free; raise; end;
end;
procedure TMusicStudioWaveCache.Draw(Canvas: TCanvas; const R, VisibleArea: TRect; Source: TMusicStudioWaveSource;
  PixelsPerSecond, Volume: Double; PPI: Integer; Background, Foreground: TColor);
var Visible: TRect; First,Last,I,X,Saved: Integer;
begin
  if (Source = nil) or not (Source.Status in [wsReady,wsSilent]) or (R.Height < 1) or
    (Length(Source.Wave) = 0) or (Source.Info.Duration <= 0) or not IntersectRect(Visible,R,VisibleArea) then Exit;
  First := Max(0,(Visible.Left-R.Left) div TILE_WIDTH); Last := Max(First,(Visible.Right-1-R.Left) div TILE_WIDTH);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Visible.Left,Visible.Top,Visible.Right,Visible.Bottom);
    for I := First to Last do begin
      X := R.Left+I*TILE_WIDTH;
      Canvas.Draw(X,R.Top,Tile(Source,I,R.Height,PPI,PixelsPerSecond,Volume,Background,Foreground));
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;
end.
