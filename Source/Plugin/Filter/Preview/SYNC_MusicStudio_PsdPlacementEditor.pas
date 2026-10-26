unit SYNC_MusicStudio_PsdPlacementEditor;

// 統合プレビューの作品内配置操作。仮表示と確定通知だけを担当し、共有設定には触れない。
interface
uses System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, Vcl.Menus,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PsdTransform;
type
  TMusicStudioPlacementBounds = function(TrackIndex: Integer; out Video,Bounds: TRect): Boolean of object;
  TMusicStudioNativeSize = function(TrackIndex: Integer): TSize of object;
  TMusicStudioPlacementCommit = procedure(TrackIndex: Integer; const Transform: TMusicStudioPsdTransform) of object;
  TMusicStudioPsdPlacementEditor = class
  private
    FSurface: TCustomControl;
    FDocument: TMusicStudioDocument;
    FTrackIndex: Integer;
    FTrackID: string;
    FDragging: Boolean;
    FHandle: Integer;
    FStartMouse: TPoint;
    FVideo,FStartRect: TRect;
    FNative: TSize;
    FOriginal,FDraft: TMusicStudioPsdTransform;
    FMenu: TPopupMenu;
    FOnBounds: TMusicStudioPlacementBounds;
    FOnCommit: TMusicStudioPlacementCommit;
    FOnNativeSize: TMusicStudioNativeSize;
    function SelectedValid: Boolean;
    function GripRect(const R: TRect; Index: Integer): TRect;
    function HitAt(X,Y: Integer): Integer;
    procedure FlipClick(Sender: TObject);
  public
    constructor Create(Surface: TCustomControl);
    destructor Destroy; override;
    procedure Bind(Document: TMusicStudioDocument);
    procedure SelectTrack(Index: Integer);
    function Cancel: Boolean;
    procedure MouseDown(Button: TMouseButton; X,Y: Integer);
    procedure MouseMove(X,Y: Integer);
    procedure MouseUp(Button: TMouseButton; X,Y: Integer);
    procedure Paint(Canvas: TCanvas);
    procedure Flip(Horizontal: Boolean);
    function EffectiveTransform(TrackIndex: Integer): TMusicStudioPsdTransform;
    property SelectedTrack: Integer read FTrackIndex;
    property Dragging: Boolean read FDragging;
    property FlipMenu: TPopupMenu read FMenu;
    property OnBounds: TMusicStudioPlacementBounds read FOnBounds write FOnBounds;
    property OnNativeSize: TMusicStudioNativeSize read FOnNativeSize write FOnNativeSize;
    property OnCommit: TMusicStudioPlacementCommit read FOnCommit write FOnCommit;
  end;
implementation
uses System.SysUtils, System.Math, System.UITypes, Winapi.Windows;
type TSurfaceAccess = class(TCustomControl);
constructor TMusicStudioPsdPlacementEditor.Create(Surface: TCustomControl);
var Item: TMenuItem;
begin
  inherited Create; FSurface := Surface; FTrackIndex := -1;
  FMenu := TPopupMenu.Create(nil);
  Item := TMenuItem.Create(FMenu); Item.Caption := '左右反転'; Item.Tag := 1; Item.OnClick := FlipClick; FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu); Item.Caption := '上下反転'; Item.Tag := 2; Item.OnClick := FlipClick; FMenu.Items.Add(Item);
end;
destructor TMusicStudioPsdPlacementEditor.Destroy;
begin Cancel; FMenu.Free; inherited; end;
function TMusicStudioPsdPlacementEditor.SelectedValid: Boolean;
begin
  Result := Assigned(FDocument) and (FTrackIndex>=0) and (FTrackIndex<FDocument.TrackCount);
  if Result then Result := (FDocument.TrackAt(FTrackIndex).ID=FTrackID) and (FDocument.TrackAt(FTrackIndex).Kind='psd');
end;
procedure TMusicStudioPsdPlacementEditor.Bind(Document: TMusicStudioDocument);
begin Cancel; FDocument := Document; if not SelectedValid then SelectTrack(-1); end;
procedure TMusicStudioPsdPlacementEditor.SelectTrack(Index: Integer);
begin
  if (Index=FTrackIndex) and SelectedValid then Exit;
  Cancel; FTrackIndex := -1; FTrackID := '';
  if Assigned(FDocument) and (Index>=0) and (Index<FDocument.TrackCount) and (FDocument.TrackAt(Index).Kind='psd') then begin
    FTrackIndex := Index; FTrackID := FDocument.TrackAt(Index).ID;
  end;
  FSurface.Invalidate;
end;
function TMusicStudioPsdPlacementEditor.Cancel: Boolean;
begin
  Result := FDragging; FDragging := False; TSurfaceAccess(FSurface).MouseCapture := False;
  FSurface.Cursor := crDefault; if Result then FSurface.Invalidate;
end;
function TMusicStudioPsdPlacementEditor.EffectiveTransform(TrackIndex: Integer): TMusicStudioPsdTransform;
begin
  Result := FDocument.TrackAt(TrackIndex).PsdTransform;
  if FDragging and SelectedValid and (TrackIndex=FTrackIndex) then Result := FDraft;
end;
function TMusicStudioPsdPlacementEditor.GripRect(const R: TRect; Index: Integer): TRect;
var P: TPoint; S: Integer;
begin
  S := Max(3,MulDiv(5,FSurface.CurrentPPI,96)); P := R.TopLeft;
  if Index in [2,4] then P.X := R.Right;
  if Index in [3,4] then P.Y := R.Bottom;
  Result := Rect(P.X-S,P.Y-S,P.X+S+1,P.Y+S+1);
end;
function TMusicStudioPsdPlacementEditor.HitAt(X,Y: Integer): Integer;
var V,R: TRect; I: Integer;
begin
  Result := 0;
  if not SelectedValid or not Assigned(FOnBounds) or not FOnBounds(FTrackIndex,V,R) then Exit;
  // 映像範囲外でも、灰色の編集余白に見えている選択画像を操作できる。
  if not PtInRect(FSurface.ClientRect,Point(X,Y)) then Exit;
  for I := 1 to 4 do if PtInRect(GripRect(R,I),Point(X,Y)) then Exit(I);
  if PtInRect(R,Point(X,Y)) then Result := 5;
end;
procedure TMusicStudioPsdPlacementEditor.MouseDown(Button: TMouseButton; X,Y: Integer);
var P: TPoint;
begin
  if FDragging then Cancel;
  FHandle := HitAt(X,Y); if FHandle=0 then Exit;
  if Button=mbRight then begin
    P := FSurface.ClientToScreen(Point(X,Y)); FMenu.Popup(P.X,P.Y); Exit;
  end;
  if Button<>mbLeft then Exit;
  if not FOnBounds(FTrackIndex,FVideo,FStartRect) then Exit;
  FNative := TSize.Create(0,0); if Assigned(FOnNativeSize) then FNative := FOnNativeSize(FTrackIndex);
  FOriginal := FDocument.TrackAt(FTrackIndex).PsdTransform; FDraft := FOriginal;
  FStartMouse := Point(X,Y); FDragging := True; TSurfaceAccess(FSurface).MouseCapture := True;
end;
procedure TMusicStudioPsdPlacementEditor.MouseMove(X,Y: Integer);
var DX,DY,W,H,L,T: Double; AX,AY,SX,SY: Integer; Factor,MaxFactor: Double;
begin
  if not FDragging then begin
    case HitAt(X,Y) of
      1,4: FSurface.Cursor := crSizeNWSE;
      2,3: FSurface.Cursor := crSizeNESW;
      5: FSurface.Cursor := crSizeAll;
    else FSurface.Cursor := crDefault; end; Exit;
  end;
  if not SelectedValid then begin Cancel; Exit; end;
  DX := X-FStartMouse.X; DY := Y-FStartMouse.Y;
  if (DX=0) and (DY=0) then begin FDraft := FOriginal; FSurface.Invalidate; Exit; end;
  W := FStartRect.Width; H := FStartRect.Height; L := FStartRect.Left; T := FStartRect.Top;
  if (W<1) or (H<1) or (FVideo.Width<1) or (FVideo.Height<1) then begin Cancel; Exit; end;
  if FHandle=5 then begin L := L+DX; T := T+DY; end else begin
    SX := 1; SY := 1; AX := FStartRect.Left; AY := FStartRect.Top;
    if FHandle in [1,3] then begin SX := -1; AX := FStartRect.Right; end;
    if FHandle in [1,2] then begin SY := -1; AY := FStartRect.Bottom; end;
    // 対角の固定点への射影で縦横比を維持。カーソルが反対側へ交差しても負寸法にしない。
    Factor := 1+(DX*SX*W+DY*SY*H)/(W*W+H*H);
    MaxFactor := Min(4*FVideo.Width/W,4*FVideo.Height/H);
    Factor := EnsureRange(Factor,Max(0.001*FVideo.Width/W,0.001*FVideo.Height/H),MaxFactor);
    W := W*Factor; H := H*Factor; L := AX; T := AY;
    if SX<0 then L := AX-W; if SY<0 then T := AY-H;
  end;
  FDraft.HasStage := True; FDraft.HasBounds := False;
  FDraft.StageX := EnsureRange(((L+W/2)-(FVideo.Left+FVideo.Width/2))*MUSIC_STUDIO_STAGE_WIDTH/FVideo.Width,-30720.0,30720.0);
  FDraft.StageY := EnsureRange(((T+H/2)-(FVideo.Top+FVideo.Height/2))*MUSIC_STUDIO_STAGE_HEIGHT/FVideo.Height,-17280.0,17280.0);
  if (FHandle=5) and FOriginal.HasStage then begin
    FDraft.StageX := EnsureRange(FOriginal.StageX+DX*MUSIC_STUDIO_STAGE_WIDTH/FVideo.Width,-30720.0,30720.0);
    FDraft.StageY := EnsureRange(FOriginal.StageY+DY*MUSIC_STUDIO_STAGE_HEIGHT/FVideo.Height,-17280.0,17280.0);
    FDraft.Scale := FOriginal.Scale;
  end
  else if FNative.cx>0 then FDraft.Scale := EnsureRange(W*MUSIC_STUDIO_STAGE_WIDTH/FVideo.Width/FNative.cx,0.001,256.0)
  else FDraft.Scale := 1;
  FSurface.Invalidate;
end;
procedure TMusicStudioPsdPlacementEditor.MouseUp(Button: TMouseButton; X,Y: Integer);
var Changed: Boolean; Draft: TMusicStudioPsdTransform; Index: Integer;
begin
  if (Button<>mbLeft) or not FDragging then Exit; MouseMove(X,Y);
  if not FDragging then Exit;
  Changed := (FDraft.HasStage<>FOriginal.HasStage) or (FDraft.StageX<>FOriginal.StageX) or (FDraft.StageY<>FOriginal.StageY) or (FDraft.Scale<>FOriginal.Scale) or (FDraft.HasBounds<>FOriginal.HasBounds) or (FDraft.X<>FOriginal.X) or (FDraft.Y<>FOriginal.Y) or
    (FDraft.Width<>FOriginal.Width) or (FDraft.Height<>FOriginal.Height);
  Draft := FDraft; Index := FTrackIndex; Cancel;
  if Changed and Assigned(FOnCommit) then FOnCommit(Index,Draft);
end;
procedure TMusicStudioPsdPlacementEditor.FlipClick(Sender: TObject);
begin Flip(TMenuItem(Sender).Tag=1); end;
procedure TMusicStudioPsdPlacementEditor.Flip(Horizontal: Boolean);
var Transform: TMusicStudioPsdTransform;
begin
  Cancel;
  if not SelectedValid then Exit;
  Transform := FDocument.TrackAt(FTrackIndex).PsdTransform;
  if Horizontal then Transform.FlipX := not Transform.FlipX else Transform.FlipY := not Transform.FlipY;
  if Assigned(FOnCommit) then FOnCommit(FTrackIndex,Transform);
end;
procedure TMusicStudioPsdPlacementEditor.Paint(Canvas: TCanvas);
var V,R,G: TRect; I,Save: Integer;
begin
  if not SelectedValid or not Assigned(FOnBounds) or not FOnBounds(FTrackIndex,V,R) then Exit;
  Save := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,0,0,FSurface.ClientWidth,FSurface.ClientHeight);
    Canvas.Brush.Style := bsClear; Canvas.Pen.Color := clWhite; Canvas.Pen.Width := 1; Canvas.Rectangle(R);
    Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := clWhite; Canvas.Pen.Color := $004A4A4A;
    for I := 1 to 4 do begin G := GripRect(R,I); Canvas.Rectangle(G); end;
  finally RestoreDC(Canvas.Handle,Save); end;
end;
end.
