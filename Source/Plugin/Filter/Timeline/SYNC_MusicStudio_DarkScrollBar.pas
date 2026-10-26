unit SYNC_MusicStudio_DarkScrollBar;
// タイムライン用の独自scrollbar。位置は呼出側の論理単位、Maxは移動可能な最大位置。
// 値/hoverが変わった時だけ再描画し、nativeテーマと背景消去による白いflashを避ける。
interface
uses System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Forms;
type
  TMusicStudioDarkScrollBar = class(TCustomControl)
  private
    FKind: TScrollBarKind;
    FMin,FMax,FPosition,FPageSize,FSmallChange,FLargeChange: Integer;
    FHover,FPressed,FDragOrigin,FDragPosition: Integer;
    FRepeater: TTimer;
    FOnChange: TNotifyEvent;
    FPaintCount: Integer;
    procedure SetKind(Value: TScrollBarKind);
    procedure SetMin(Value: Integer);
    procedure SetMax(Value: Integer);
    procedure SetPosition(Value: Integer);
    procedure SetPageSize(Value: Integer);
    function Axis(X,Y: Integer): Integer;
    function AxisSize: Integer;
    function ButtonSize: Integer;
    function ThumbLength: Integer;
    function PartAt(X,Y: Integer): Integer;
    procedure Step(Part: Integer);
    procedure RepeatStep(Sender: TObject);
    procedure Stop;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure WMCancelMode(var Message: TMessage); message WM_CANCELMODE;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Range/page/positionをまとめて反映。同値なら再描画/通知しない。
    procedure Configure(Minimum,Maximum,Page,Value: Integer);
    function ThumbRect: TRect;
    property Kind: TScrollBarKind read FKind write SetKind;
    property Min: Integer read FMin write SetMin;
    property Max: Integer read FMax write SetMax;
    property Position: Integer read FPosition write SetPosition;
    property PageSize: Integer read FPageSize write SetPageSize;
    property SmallChange: Integer read FSmallChange write FSmallChange;
    property LargeChange: Integer read FLargeChange write FLargeChange;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property PaintCount: Integer read FPaintCount;
  end;
implementation
uses System.Math, System.UITypes, Winapi.Windows, Vcl.Graphics;
constructor TMusicStudioDarkScrollBar.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ParentBackground := False; TabStop := True;
  ControlStyle := ControlStyle+[csOpaque]-[csCaptureMouse];
  Color := $00252525; Width := 160; Height := 17; FSmallChange := 1; FLargeChange := 10; FPageSize := 10;
  FRepeater := TTimer.Create(Self); FRepeater.Enabled := False; FRepeater.OnTimer := RepeatStep;
end;
procedure TMusicStudioDarkScrollBar.Configure(Minimum,Maximum,Page,Value: Integer);
var Changed: Boolean;
begin
  Maximum := System.Math.Max(Minimum,Maximum); Page := System.Math.Max(0,Page);
  Value := EnsureRange(Value,Minimum,Maximum);
  if (Minimum=FMin) and (Maximum=FMax) and (Page=FPageSize) and (Value=FPosition) then Exit;
  Changed := Value<>FPosition; FMin := Minimum; FMax := Maximum; FPageSize := Page; FPosition := Value;
  Invalidate; if Changed and Assigned(FOnChange) then FOnChange(Self);
end;
procedure TMusicStudioDarkScrollBar.SetKind(Value: TScrollBarKind);
begin if FKind=Value then Exit; Stop; FKind := Value; Invalidate; end;
procedure TMusicStudioDarkScrollBar.SetMin(Value: Integer);
begin Configure(Value,FMax,FPageSize,FPosition); end;
procedure TMusicStudioDarkScrollBar.SetMax(Value: Integer);
begin Configure(FMin,Value,FPageSize,FPosition); end;
procedure TMusicStudioDarkScrollBar.SetPageSize(Value: Integer);
begin Configure(FMin,FMax,Value,FPosition); end;
procedure TMusicStudioDarkScrollBar.SetPosition(Value: Integer);
begin Configure(FMin,FMax,FPageSize,Value); end;
function TMusicStudioDarkScrollBar.Axis(X,Y: Integer): Integer;
begin if FKind=sbHorizontal then Result := X else Result := Y; end;
function TMusicStudioDarkScrollBar.AxisSize: Integer;
begin if FKind=sbHorizontal then Result := ClientWidth else Result := ClientHeight; end;
function TMusicStudioDarkScrollBar.ButtonSize: Integer;
begin Result := System.Math.Min(AxisSize div 2,IfThen(FKind=sbHorizontal,ClientHeight,ClientWidth)); end;
function TMusicStudioDarkScrollBar.ThumbLength: Integer;
var Length: Integer;
begin
  Length := System.Math.Max(0,AxisSize-2*ButtonSize);
  if FMax=FMin then Exit(Length);
  Result := EnsureRange(Round(Length*(FPageSize/(Int64(FMax)-FMin+FPageSize))),System.Math.Min(Length,MulDiv(20,CurrentPPI,96)),Length);
end;
function TMusicStudioDarkScrollBar.ThumbRect: TRect;
var A,Length,Start: Integer;
begin
  A := ButtonSize; Length := ThumbLength; Start := A;
  if FMax>FMin then Inc(Start,Round((AxisSize-2*A-Length)*((Int64(FPosition)-FMin)/(Int64(FMax)-FMin))));
  if FKind=sbHorizontal then Result := Rect(Start,2,Start+Length,ClientHeight-2)
  else Result := Rect(2,Start,ClientWidth-2,Start+Length);
end;
function TMusicStudioDarkScrollBar.PartAt(X,Y: Integer): Integer;
var T: TRect; P: Integer;
begin
  Result := 0; if not PtInRect(ClientRect,Point(X,Y)) or (FMax=FMin) then Exit;
  P := Axis(X,Y); if P<ButtonSize then Exit(1); if P>=AxisSize-ButtonSize then Exit(2);
  T := ThumbRect; if PtInRect(T,Point(X,Y)) then Exit(3);
  if P<Axis(T.Left,T.Top) then Result := 4 else Result := 5;
end;
procedure TMusicStudioDarkScrollBar.Step(Part: Integer);
var Delta: Int64;
begin
  Delta := System.Math.Max(1,FSmallChange); if Part in [4,5] then Delta := System.Math.Max(1,FLargeChange);
  if Part in [1,4] then Delta := -Delta;
  SetPosition(EnsureRange(Int64(FPosition)+Delta,Int64(FMin),Int64(FMax)));
end;
procedure TMusicStudioDarkScrollBar.RepeatStep(Sender: TObject);
var P: TPoint;
begin
  FRepeater.Interval := 60; GetCursorPos(P); P := ScreenToClient(P);
  if (FPressed in [1,2,4,5]) and (PartAt(P.X,P.Y)=FPressed) then Step(FPressed);
end;
procedure TMusicStudioDarkScrollBar.Stop;
begin
  FRepeater.Enabled := False; if FPressed=0 then Exit;
  FPressed := 0; MouseCapture := False; Invalidate;
end;
procedure TMusicStudioDarkScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited; if Button<>mbLeft then Exit; if CanFocus then SetFocus;
  FPressed := PartAt(X,Y); if FPressed=0 then Exit;
  MouseCapture := True; FDragOrigin := Axis(X,Y); FDragPosition := FPosition;
  if FPressed<>3 then begin Step(FPressed); FRepeater.Interval := 400; FRepeater.Enabled := True; end;
  Invalidate;
end;
procedure TMusicStudioDarkScrollBar.MouseMove(Shift: TShiftState; X,Y: Integer);
var P,Travel: Integer; Value: Int64;
begin
  inherited;
  if FPressed=3 then begin
    Travel := AxisSize-2*ButtonSize-ThumbLength;
    if Travel>0 then begin Value := FDragPosition+Round((Axis(X,Y)-FDragOrigin)/Travel*(Int64(FMax)-FMin)); SetPosition(EnsureRange(Value,Int64(FMin),Int64(FMax))); end;
  end;
  P := PartAt(X,Y); if P<>FHover then begin FHover := P; Invalidate; end;
end;
procedure TMusicStudioDarkScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; if Button=mbLeft then begin MouseMove(Shift,X,Y); Stop; end; end;
procedure TMusicStudioDarkScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  case Key of
    VK_LEFT,VK_UP: Step(1); VK_RIGHT,VK_DOWN: Step(2); VK_PRIOR: Step(4); VK_NEXT: Step(5);
    VK_HOME: Position := FMin; VK_END: Position := FMax; VK_ESCAPE: Stop;
  else Exit; end; Key := 0;
end;
function TMusicStudioDarkScrollBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin Result := True; if WheelDelta>0 then Step(1) else if WheelDelta<0 then Step(2); end;
procedure TMusicStudioDarkScrollBar.WMGetDlgCode(var Message: TWMGetDlgCode);
begin Message.Result := DLGC_WANTARROWS; end;
procedure TMusicStudioDarkScrollBar.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin Message.Result := 1; end;
procedure TMusicStudioDarkScrollBar.WMCaptureChanged(var Message: TMessage);
begin inherited; if HWND(Message.LParam)<>Handle then Stop; end;
procedure TMusicStudioDarkScrollBar.WMCancelMode(var Message: TMessage);
begin Stop; inherited; end;
procedure TMusicStudioDarkScrollBar.CMMouseLeave(var Message: TMessage);
begin inherited; if FHover<>0 then begin FHover := 0; Invalidate; end; end;
procedure TMusicStudioDarkScrollBar.Paint;
var R,T: TRect; A,CX,CY,D: Integer;
  procedure Arrow(Forward: Boolean);
  var P: TArray<TPoint>; Offset: Integer;
  begin
    Offset := A div 2; if Forward then Offset := AxisSize-A div 2;
    if FKind=sbHorizontal then begin CX := Offset; CY := ClientHeight div 2; end
    else begin CX := ClientWidth div 2; CY := Offset; end;
    D := System.Math.Max(2,MulDiv(3,CurrentPPI,96)); SetLength(P,3);
    if FKind=sbHorizontal then begin
      if not Forward then D := -D; P[0] := Point(CX+D div 2,CY); P[1] := Point(CX-D div 2,CY-Abs(D)); P[2] := Point(CX-D div 2,CY+Abs(D));
    end else begin
      if not Forward then D := -D; P[0] := Point(CX,CY+D div 2); P[1] := Point(CX-Abs(D),CY-D div 2); P[2] := Point(CX+Abs(D),CY-D div 2);
    end;
    Canvas.Brush.Color := $00B0B0B0; if FMax=FMin then Canvas.Brush.Color := $00545454;
    Canvas.Pen.Color := Canvas.Brush.Color; Canvas.Polygon(P);
  end;
begin
  Inc(FPaintCount); Canvas.Brush.Color := $00252525; Canvas.FillRect(ClientRect); A := ButtonSize;
  if FKind=sbHorizontal then R := Rect(0,0,A,ClientHeight) else R := Rect(0,0,ClientWidth,A);
  if (FHover=1) or (FPressed=1) then begin Canvas.Brush.Color := $003B3B3B; Canvas.FillRect(R); end;
  if FKind=sbHorizontal then R := Rect(AxisSize-A,0,AxisSize,ClientHeight) else R := Rect(0,AxisSize-A,ClientWidth,AxisSize);
  if (FHover=2) or (FPressed=2) then begin Canvas.Brush.Color := $003B3B3B; Canvas.FillRect(R); end;
  T := ThumbRect; Canvas.Brush.Color := $00595959;
  if FHover=3 then Canvas.Brush.Color := $00757575; if FPressed=3 then Canvas.Brush.Color := $009B8D74;
  if FMax=FMin then Canvas.Brush.Color := $00353535;
  Canvas.Pen.Color := Canvas.Brush.Color; Canvas.RoundRect(T.Left,T.Top,T.Right,T.Bottom,4,4); Arrow(False); Arrow(True);
end;
end.
