unit SYNC_MusicStudio_VideoRenderer;

// An effect owns its worker and decoded snapshot. Host callbacks never lend SDK
// pointers to workers. Every request waits for its own time, including export/seek.
interface

uses System.Classes, System.SyncObjs, AviUtl2FilterTypes,
  SYNC_MusicStudio_HostBackground, SYNC_MusicStudio_PsdTransform;

type
  TMusicStudioVideoPixels = TMusicStudioFramePixels;
  TMusicStudioVideoSession = class
  private
    FLock: TCriticalSection;
    FWorker: TThread;
    FLibraryRoot: string;
    FBackground: TMusicStudioHostBackground;
  public
    constructor Create(const LibraryRoot: string = '');
    destructor Destroy; override;
    function Render(const JSON: string; Seconds: Double; Width,Height: Integer;
      out Pixels: TMusicStudioVideoPixels; out ErrorText: string;
      ViewX: Double = 0; ViewY: Double = 0; ViewScale: Double = 1): Boolean;
    property Background: TMusicStudioHostBackground read FBackground;
  end;

// A settings close/apply also refreshes independently saved shared PSD settings.
procedure InvalidateMusicStudioVideoSnapshots;

implementation

uses Winapi.Windows, System.SysUtils, System.Types, System.Math, Vcl.Graphics,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_VisualCache,
  SYNC_MusicStudio_PsdSceneCache;

type
  TMusicStudioVideoWorker = class(TThread)
  private
    FWake, FDone: TEvent;
    FDocument: TMusicStudioDocument;
    FStore: TMusicStudioSharedPsdLibrary;
    FMidi: TMusicStudioVisualCache;
    FScene: TMusicStudioPsdSceneCache;
    FTrackIndexes: TArray<Integer>;
    FLastJSON, FLibraryRoot, FSnapshotError: string;
    FPreparedGeneration: Integer;
    FHasSnapshot: Boolean;
    procedure PrepareSnapshot;
    procedure AwaitScene;
    procedure Compose;
  protected
    procedure Execute; override;
  public
    JSON, ErrorText: string;
    Seconds,ViewX,ViewY,ViewScale: Double;
    Width,Height,Generation: Integer;
    Pixels: TMusicStudioVideoPixels;
    constructor Create(const LibraryRoot: string);
    destructor Destroy; override;
    procedure Request;
  end;

var SnapshotGeneration: Integer;

procedure InvalidateMusicStudioVideoSnapshots;
begin TInterlocked.Increment(SnapshotGeneration); end;

constructor TMusicStudioVideoSession.Create(const LibraryRoot: string);
begin
  inherited Create; FLock := TCriticalSection.Create; FLibraryRoot := LibraryRoot;
  FBackground := TMusicStudioHostBackground.Create;
end;

destructor TMusicStudioVideoSession.Destroy;
begin FBackground.Free; FWorker.Free; FLock.Free; inherited; end;

function TMusicStudioVideoSession.Render(const JSON: string; Seconds: Double;
  Width,Height: Integer; out Pixels: TMusicStudioVideoPixels; out ErrorText: string;
  ViewX,ViewY,ViewScale: Double): Boolean;
var Worker: TMusicStudioVideoWorker;
begin
  Pixels := nil; ErrorText := ''; Result := False;
  if IsNan(ViewX) or IsInfinite(ViewX) or IsNan(ViewY) or IsInfinite(ViewY) or
    IsNan(ViewScale) or IsInfinite(ViewScale) or (Abs(ViewX)>30720) or (Abs(ViewY)>17280) or
    (ViewScale<0.001) or (ViewScale>100) then Exit;
  if IsNan(Seconds) or IsInfinite(Seconds) or (Seconds<0) or
    (Width<1) or (Height<1) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>33554432) then Exit;
  FLock.Acquire;
  try
    if FWorker=nil then begin
      FWorker := TMusicStudioVideoWorker.Create(FLibraryRoot); FWorker.Start;
    end;
    Worker := TMusicStudioVideoWorker(FWorker);
    Worker.JSON := JSON; Worker.Seconds := Seconds;
    Worker.ViewX := ViewX; Worker.ViewY := ViewY; Worker.ViewScale := ViewScale;
    Worker.Width := Width; Worker.Height := Height;
    Worker.Generation := TInterlocked.CompareExchange(SnapshotGeneration,0,0);
    Worker.Request;
    Pixels := Worker.Pixels; ErrorText := Worker.ErrorText;
    Result := Length(Pixels)=NativeInt(Width)*Height;
  finally FLock.Release; end;
end;

constructor TMusicStudioVideoWorker.Create(const LibraryRoot: string);
begin
  inherited Create(True); FreeOnTerminate := False; FLibraryRoot := LibraryRoot;
  FWake := TEvent.Create(nil,False,False,''); FDone := TEvent.Create(nil,True,False,'');
end;

destructor TMusicStudioVideoWorker.Destroy;
begin
  Terminate; FWake.SetEvent;
  // No message pump/reentrant callback while the main host thread waits.
  WaitForSingleObject(Handle,INFINITE);
  FDone.Free; FWake.Free; inherited;
end;

procedure TMusicStudioVideoWorker.Request;
begin
  FDone.ResetEvent; FWake.SetEvent; FDone.WaitFor(INFINITE);
end;

procedure TMusicStudioVideoWorker.AwaitScene;
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+30000;
  repeat
    if Terminated then raise EAbort.Create('映像処理を終了しました。');
    FMidi.Poll; FScene.PollResults;
    if (FMidi.ActiveJobs=0) and (FScene.ActiveLoadJobs=0) and
      (FScene.ActiveRenderJobs=0) then Break;
    if GetTickCount64>=Deadline then raise Exception.Create('PSD映像の準備がタイムアウトしました。');
    Sleep(1);
  until False;
end;

procedure TMusicStudioVideoWorker.PrepareSnapshot;
var I,N: Integer; Error: string; Pattern: TMusicStudioPattern;
    Requests: TArray<TMusicStudioVisualRequest>;
begin
  // Clear before parsing, so malformed/replaced JSON can never show old images.
  FScene.Clear; FMidi.Clear; FTrackIndexes := nil; FHasSnapshot := False;
  FLastJSON := JSON; FPreparedGeneration := Generation;
  if Length(JSON)>MUSIC_STUDIO_MAX_JSON_LENGTH then
    raise Exception.Create('JSONデータが保存上限を超えています。');
  if not FDocument.TryLoad(JSON,Error) then raise Exception.Create(Error);
  FDocument.AssetResolver := FStore.ResolvePath;
  for I := 0 to FDocument.TrackCount-1 do
    if (FDocument.TrackAt(I).Kind='psd') then begin
      N := Length(FTrackIndexes); SetLength(FTrackIndexes,N+1); FTrackIndexes[N] := I;
    end;
  // Audio patterns are deliberately never opened by the video worker.
  for I := 0 to FDocument.PatternCount-1 do begin
    Pattern := FDocument.PatternAt(I);
    if (Pattern.Kind<>'singing') or (Pattern.FilePath='') or (Pattern.SourceTrack<0) then Continue;
    N := Length(Requests); SetLength(Requests,N+1);
    Requests[N].Kind := vkMidi; Requests[N].Path := Pattern.FilePath; Requests[N].Visible := True;
  end;
  FMidi.SetSources(Requests); FScene.Bind(FDocument,FStore,FMidi);
  AwaitScene; FHasSnapshot := True;
end;

procedure BlendPixel(var Dest: TPIXEL_RGBA; R,G,B,A: Integer);
var Inv: Integer;
begin
  Inv := 255-A;
  // SDK/D3D uses premultiplied RGBA. PSD bitmaps are premultiplied BGRA.
  Dest.R := Min(255,R+(Integer(Dest.R)*Inv+127) div 255);
  Dest.G := Min(255,G+(Integer(Dest.G)*Inv+127) div 255);
  Dest.B := Min(255,B+(Integer(Dest.B)*Inv+127) div 255);
  Dest.A := Min(255,A+(Integer(Dest.A)*Inv+127) div 255);
end;

procedure TMusicStudioVideoWorker.Compose;
var I,N,X,Y,SX,SY,L,T,W,H: Integer; Image: TBitmap; Row: PByte;
    Bounds: System.Types.TRect; Transform: TMusicStudioPsdTransform;
begin
  N := Length(FTrackIndexes); if N=0 then Exit;
  SetLength(Pixels,NativeInt(Width)*Height);
  // A transparent scene, equal-width lanes, centered and bottom aligned.
  // No editor chrome/lyrics/background is included in the output image.
  for I := N-1 downto 0 do begin
    Image := FScene.ImageForTrack(FTrackIndexes[I]);
    if Image=nil then begin
      if ErrorText<>'' then ErrorText := ErrorText+sLineBreak;
      ErrorText := ErrorText+FScene.StatusForTrack(FTrackIndexes[I]); Continue;
    end;
    Bounds := MusicStudioCharacterRect(Width,Height,N,I,Image.Width,Image.Height);
    Transform := FDocument.TrackAt(FTrackIndexes[I]).PsdTransform;
    Bounds := MusicStudioStageRect(Transform,Image.Width,Image.Height,Width,Height,Bounds,ViewX,ViewY,ViewScale);
    W := Bounds.Width; H := Bounds.Height; L := Bounds.Left; T := Bounds.Top;
    for Y := Max(0,-T) to Min(H-1,Height-T-1) do begin
      SY := Int64(Y)*Image.Height div H;
      if Transform.FlipY then SY := Image.Height-1-SY;
      Row := Image.ScanLine[SY];
      for X := Max(0,-L) to Min(W-1,Width-L-1) do begin
        SX := Int64(X)*Image.Width div W;
        if Transform.FlipX then SX := Image.Width-1-SX;
        BlendPixel(Pixels[(T+Y)*Width+L+X],Row[SX*4+2],Row[SX*4+1],Row[SX*4],Row[SX*4+3]);
      end;
    end;
  end;
end;

procedure TMusicStudioVideoWorker.Execute;
begin
  try
    while not Terminated do begin
      FWake.WaitFor(INFINITE); if Terminated then Break;
      try
        Pixels := nil; ErrorText := '';
        if FScene=nil then begin
          FDocument := TMusicStudioDocument.Create;
          FStore := TMusicStudioSharedPsdLibrary.Create(FLibraryRoot);
          FMidi := TMusicStudioVisualCache.Create; FScene := TMusicStudioPsdSceneCache.Create;
          FScene.FrozenSources := True; FScene.MaximumImageDimension := 0;
        end;
        if not FHasSnapshot or (FLastJSON<>JSON) or (FPreparedGeneration<>Generation) then begin
          FSnapshotError := '';
          try PrepareSnapshot;
          except on E: Exception do begin FSnapshotError := E.Message; FHasSnapshot := True; end; end;
        end;
        if FSnapshotError<>'' then raise Exception.Create(FSnapshotError);
        FScene.SetPosition(Seconds); AwaitScene; Compose;
      except on E: Exception do begin ErrorText := E.Message; Pixels := nil; end; end;
      FDone.SetEvent;
    end;
  finally
    FScene.Free; FMidi.Free; FStore.Free; FDocument.Free; FDone.SetEvent;
  end;
end;

end.
