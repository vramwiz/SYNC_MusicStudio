unit SYNC_MusicStudio_InstrumentPreview;

// 演奏編集専用のPSD表示。読込済みPSDを複製し、最新の意味状態だけを非同期合成する。
// 元PSD/共有設定/作品には書き込まず、workerの完了は所有timerで回収する。
interface
uses System.Classes, System.JSON, System.Types, Winapi.Messages, Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerJobs, SYNC_MusicStudio_InstrumentRules,
  SYNC_MusicStudio_BitmapCache;
type
  TMusicStudioInstrumentPreview = class(TCustomControl)
  private
    FDocument: TMusicStudioLayerDocument;
    FConfig,FOverrides: TJSONObject;
    FBitmap: TBitmap;
    FJob: TMusicStudioPsdLayerRenderJob;
    FFrames: TMusicStudioBitmapCache;
    FCacheHits: Integer;
    FTimer: TTimer;
    FKey,FStateKey,FError: string;
    FGeneration,FRenderCount: Integer;
    FPending: Boolean;
    FZoom: Double;
    FPan: TPointF;
    FDragPoint: TPoint;
    FDragging: Boolean;
    function ViewTop: Integer;
    function ViewScale: Double;
    procedure EndPan;
    procedure CaptureLost(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure CancelMode(var Message: TMessage); message WM_CANCELMODE;
    procedure Tick(Sender: TObject);
    function GetBusy: Boolean;
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure DblClick; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Bind(Document: TMusicStudioLayerDocument; const BaseConfig: string);
    procedure SetStates(const States: TArray<TInstrumentState>);
    procedure Poll;
    procedure Fit;
    procedure ZoomAt(WheelDelta: Integer; const Point: TPoint);
    function ImageToView(const Point: TPointF): TPointF;
    function ViewToImage(const Point: TPointF): TPointF;
    property ViewZoom: Double read FZoom;
    property ViewPan: TPointF read FPan;
    property ViewDragging: Boolean read FDragging;
    property PreviewBitmap: TBitmap read FBitmap; // 借用。次のPoll/Bindまで有効。
    property RenderCount: Integer read FRenderCount;
    property CacheHits: Integer read FCacheHits;
    property Busy: Boolean read GetBusy;
    property ErrorText: string read FError;
  end;
implementation
uses System.SysUtils, System.Math, Winapi.Windows,
  SYNC_MusicStudio_PsdLayerConfig;
constructor TMusicStudioInstrumentPreview.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; FZoom := 1;
  FFrames := TMusicStudioBitmapCache.Create(16);
  ShowHint := True; Hint := 'ホイールで拡大縮小、左ドラッグで移動、ダブルクリックで全体表示。';
  FTimer := TTimer.Create(Self); FTimer.Interval := 16; FTimer.OnTimer := Tick;
end;
destructor TMusicStudioInstrumentPreview.Destroy;
begin
  if FTimer<>nil then FTimer.Enabled := False;
  EndPan;
  FJob.Free; FFrames.Free; FBitmap.Free; FOverrides.Free; FConfig.Free; FDocument.Free;
  inherited;
end;
procedure TMusicStudioInstrumentPreview.Bind(Document: TMusicStudioLayerDocument; const BaseConfig: string);
begin
  FreeAndNil(FJob); FreeAndNil(FBitmap); FreeAndNil(FOverrides); FreeAndNil(FConfig); FreeAndNil(FDocument);
  FFrames.Clear; FCacheHits := 0;
  FKey := ''; FStateKey := ''; FError := ''; FPending := False; Inc(FGeneration);
  Fit;
  if Document<>nil then begin
    FDocument := Document.Clone; FConfig := ParseMusicStudioPsdConfig(BaseConfig); SetStates(nil);
  end;
  Invalidate;
end;
procedure TMusicStudioInstrumentPreview.SetStates(const States: TArray<TInstrumentState>);
var Base,Changes,Config,Overrides: TJSONObject; Pair: TJSONPair; State: TInstrumentState; Pose: Boolean; Key,StateKey: string;
  Cached: Vcl.Graphics.TBitmap;
begin
  if FDocument=nil then Exit;
  // 無変化の再生tickでは433層等のvisibility JSONを組み直さず、合成workerへCPUを渡す。
  StateKey := IntToStr(Length(States))+';';
  for State in States do StateKey := StateKey+IntToStr(Length(State.Row))+':'+State.Row+
    IntToStr(Length(State.Choice))+':'+State.Choice+IntToStr(Length(State.SelectionMode))+':'+State.SelectionMode+
    IntToStr(Length(State.LayerScope))+':'+State.LayerScope+IntToStr(State.Stage)+';';
  if StateKey=FStateKey then Exit;
  Cached := FFrames.Find(StateKey);
  if Cached<>nil then begin
    FStateKey := StateKey; FKey := ''; Inc(FGeneration); FPending := False; FError := '';
    if FJob<>nil then FJob.Terminate;
    if FBitmap=nil then FBitmap := Vcl.Graphics.TBitmap.Create; FBitmap.Assign(Cached);
    Inc(FCacheHits); Inc(FRenderCount); Invalidate; Exit;
  end;
  Base := nil; Changes := nil; Config := nil; Overrides := nil;
  try
    Base := BuildMusicStudioPsdOverrides(FDocument,FConfig,-1);
    Changes := FDocument.InstrumentRules.Visibility(States);
    for Pair in Changes do MusicStudioSetJsonBoolean(Base,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
    Config := FConfig.Clone as TJSONObject; Config.RemovePair('visibility').Free; Config.AddPair('visibility',Base); Base := nil;
    Pose := False; for State in States do if (State.Row='ポーズ') and
      FDocument.InstrumentRules.HasChoice(State.Row,State.Choice) then Pose := True;
    if Pose then Overrides := BuildMusicStudioPsdOverrides(FDocument,Config,-1)
    else Overrides := BuildMusicStudioPsdOverrides(FDocument,Config,0);
    Key := Overrides.ToJSON; FStateKey := StateKey; if Key=FKey then Exit;
    FKey := Key; Inc(FGeneration); FOverrides.Free; FOverrides := Overrides; Overrides := nil;
    FPending := True; FError := ''; if FJob<>nil then FJob.Terminate;
    Poll;
  finally Overrides.Free; Config.Free; Changes.Free; Base.Free; end;
end;
procedure TMusicStudioInstrumentPreview.Poll;
var Cached: Vcl.Graphics.TBitmap;
begin
  if (FJob<>nil) and FJob.Finished then begin
    if FJob.Generation=FGeneration then begin
      FError := FJob.ErrorMessage;
      FreeAndNil(FBitmap);
      if FError='' then begin
        FBitmap := FJob.TakeBitmap; Inc(FRenderCount);
        if FBitmap<>nil then begin
          Cached := Vcl.Graphics.TBitmap.Create;
          try Cached.Assign(FBitmap); FFrames.Add(FStateKey,Cached); Cached := nil; finally Cached.Free; end;
        end;
      end;
      Invalidate;
    end;
    FreeAndNil(FJob);
  end;
  if FPending and (FJob=nil) and (FDocument<>nil) then begin
    FJob := TMusicStudioPsdLayerRenderJob.Create(FDocument,FOverrides,FGeneration,512);
    FPending := False; FJob.Start;
  end;
end;
procedure TMusicStudioInstrumentPreview.Tick(Sender: TObject);
begin
  try Poll; except on E: Exception do begin FError := E.Message; FPending := False; Invalidate; end; end;
end;
function TMusicStudioInstrumentPreview.GetBusy: Boolean;
begin Result := FPending or (FJob<>nil); end;
function TMusicStudioInstrumentPreview.ViewTop: Integer;
begin Canvas.Font.Assign(Font); Result := Max(30,Canvas.TextHeight('PSD')+12); end;
function TMusicStudioInstrumentPreview.ViewScale: Double;
begin
  Result := 1;
  if (FBitmap<>nil) and not FBitmap.Empty then
    Result := Min(Max(1,Width-24)/FBitmap.Width,Max(1,Height-ViewTop-24)/FBitmap.Height)*FZoom;
end;
function TMusicStudioInstrumentPreview.ImageToView(const Point: TPointF): TPointF;
begin
  Result := Point; if FBitmap=nil then Exit;
  Result := PointF(Width/2+FPan.X+(Point.X-FBitmap.Width/2)*ViewScale,
    ViewTop+(Height-ViewTop)/2+FPan.Y+(Point.Y-FBitmap.Height/2)*ViewScale);
end;
function TMusicStudioInstrumentPreview.ViewToImage(const Point: TPointF): TPointF;
begin
  Result := Point; if FBitmap=nil then Exit;
  Result := PointF((Point.X-Width/2-FPan.X)/ViewScale+FBitmap.Width/2,
    (Point.Y-ViewTop-(Height-ViewTop)/2-FPan.Y)/ViewScale+FBitmap.Height/2);
end;
procedure TMusicStudioInstrumentPreview.EndPan;
begin
  FDragging := False; Cursor := crDefault;
  if HandleAllocated and (GetCapture=Handle) then MouseCapture := False;
end;
procedure TMusicStudioInstrumentPreview.CaptureLost(var Message: TMessage);
begin inherited; EndPan; end;
procedure TMusicStudioInstrumentPreview.CancelMode(var Message: TMessage);
begin EndPan; inherited; end;
procedure TMusicStudioInstrumentPreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if (Button<>mbLeft) or (Y<ViewTop) or (FBitmap=nil) then Exit;
  FDragging := True; FDragPoint := Point(X,Y); MouseCapture := True; Cursor := crSizeAll;
end;
procedure TMusicStudioInstrumentPreview.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited; if not FDragging then Exit;
  FPan := PointF(FPan.X+X-FDragPoint.X,FPan.Y+Y-FDragPoint.Y); FDragPoint := Point(X,Y); Invalidate;
end;
procedure TMusicStudioInstrumentPreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; if Button=mbLeft then EndPan; end;
function TMusicStudioInstrumentPreview.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var Point: TPoint;
begin
  Point := ScreenToClient(MousePos); Result := PtInRect(ClientRect,Point);
  if Result then ZoomAt(WheelDelta,Point);
end;
procedure TMusicStudioInstrumentPreview.ZoomAt(WheelDelta: Integer; const Point: TPoint);
var NewZoom,Ratio: Double;
begin
  if (FBitmap=nil) or FBitmap.Empty or (Point.Y<ViewTop) then Exit;
  EndPan; NewZoom := EnsureRange(FZoom*Power(1.2,WheelDelta/120),0.1,32.0); Ratio := NewZoom/FZoom;
  FPan := PointF(Ratio*FPan.X+(1-Ratio)*(Point.X-Width/2),
    Ratio*FPan.Y+(1-Ratio)*(Point.Y-ViewTop-(Height-ViewTop)/2));
  FZoom := NewZoom; Invalidate;
end;
procedure TMusicStudioInstrumentPreview.Fit;
begin EndPan; FZoom := 1; FPan := PointF(0,0); Invalidate; end;
procedure TMusicStudioInstrumentPreview.DblClick;
begin inherited; Fit; end;
procedure TMusicStudioInstrumentPreview.Resize;
begin inherited; EndPan; Invalidate; end;
procedure TMusicStudioInstrumentPreview.Paint;
var X,Y,Tile,Top,Margin,Saved: Integer; TL,BR: TPointF; R: TRect; Text: string;
begin
  Canvas.Font.Assign(Font); Top := ViewTop; Margin := 12;
  Canvas.Brush.Color := $002B2B2B; Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear; Canvas.Font.Color := $00E6E6E6;
  R := Rect(Margin,0,Width-Margin,Top); Text := Format('PSDプレビュー %.0f%%',[FZoom*100]);
  DrawText(Canvas.Handle,PChar(Text),-1,R,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS);
  Tile := 12;
  Canvas.Brush.Style := bsSolid;
  for Y := 0 to Max(0,(Height-Top) div Tile) do for X := 0 to Width div Tile do begin
    if Odd(X+Y) then Canvas.Brush.Color := $003C3C3C else Canvas.Brush.Color := $00333333;
    Canvas.FillRect(Rect(X*Tile,Top+Y*Tile,Min(Width,(X+1)*Tile),Min(Height,Top+(Y+1)*Tile)));
  end;
  if (FBitmap<>nil) and (FBitmap.Width>0) and (FBitmap.Height>0) then begin
    TL := ImageToView(PointF(0,0)); BR := ImageToView(PointF(FBitmap.Width,FBitmap.Height));
    Saved := SaveDC(Canvas.Handle);
    try
      IntersectClipRect(Canvas.Handle,0,Top,Width,Height);
      Canvas.StretchDraw(Rect(Round(TL.X),Round(TL.Y),Round(BR.X),Round(BR.Y)),FBitmap);
    finally RestoreDC(Canvas.Handle,Saved); Canvas.Refresh; end;
  end else begin
    Text := '表示を準備しています…'; if FError<>'' then Text := FError;
    R := Rect(Margin,Top+Margin,Width-Margin,Height-Margin); Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle,PChar(Text),-1,R,DT_WORDBREAK);
  end;
  Canvas.Pen.Color := $00505050; Canvas.MoveTo(Width-1,0); Canvas.LineTo(Width-1,Height);
end;
end.
