unit SYNC_MusicStudio_InstrumentFrame;
// PSDから生成した行を共通タイムラインで編集する。ファイル解析/画像描画/作品確定は親へ分離する。
interface
uses System.Classes, System.Types, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Menus, Vcl.Graphics,
  SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_EditHistory;
type
  TMusicStudioInstrumentFrame = class;
  TInstrumentGrid = class(TCustomControl)
  private
    FOwnerFrame: TMusicStudioInstrumentFrame;
    FMouseUp: Boolean;
    procedure CaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure MouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;
  TMusicStudioInstrumentFrame = class(TFrame)
  private
    FData: TMusicStudioInstrumentData;
    FRules: TMusicStudioInstrumentRules;
    FHistory: TMusicStudioEditHistory;
    FGrid: TInstrumentGrid;
    FHeader: TPanel;
    FLength: TEdit;
    FLengthLabel: TLabel;
    FPlay,FStop: TButton;
    FStatus: TLabel;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FSelected,FMode,FDownX: Integer;
    FCandidate,FOriginal: TInstrumentBlock;
    FAnchor,FPosition,FOrigin,FTempo,FDraftPosition: Double;
    FZoom,FViewStart,FPanStart: Double;
    FTick: UInt64;
    FPlaying,FMoved: Boolean;
    FOnPosition: TNotifyEvent;
    function P(Value: Integer): Integer;
    function RowHeight: Integer;
    function RowIndex(const Name: string): Integer;
    function XBeat(Beat: Double): Integer;
    function BeatAt(X: Integer): Double;
    function PixelsPerBeat: Double;
    function GridStep: Double;
    function ClampStart(Beat: Double): Double;
    function HitMode(X,Y: Integer; out Index: Integer): Integer;
    procedure Wheel(Shift: TShiftState; Delta,X: Integer);
    function Bounds(const B: TInstrumentBlock): TRect;
    procedure BuildUI;
    procedure Draw;
    procedure Down(Button: TMouseButton; X,Y: Integer);
    procedure Move(X,Y: Integer);
    procedure Up(Button: TMouseButton; X,Y: Integer);
    procedure CancelDrag;
    procedure PreviewDrag(X: Integer);
    procedure Change(const Before: string);
    procedure PopupAt(X,Y: Integer);
    procedure Choose(Sender: TObject);
    procedure LengthExit(Sender: TObject);
    procedure LengthKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PlayClick(Sender: TObject);
    procedure Tick(Sender: TObject);
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 解析済みテーブルだけを複製。PSD変更後の再Bindでも既存の区間を削除しない。
    procedure BindRules(Rules: TMusicStudioInstrumentRules);
    procedure LoadPattern(const ConfigJSON,AssetID: string; Rules: TMusicStudioInstrumentRules; Tempo: Double);
    function ConfigJSON: string;
    // 未確定dragは独立した試写位置で評価する。再生位置と保存用Dataは変更しない。
    function PreviewStates: TArray<TInstrumentState>;
    procedure Seek(Beat: Double);
    procedure Stop;
    procedure HandleKey(var Key: Word; Shift: TShiftState);
    function BeatToX(Beat: Double): Integer;
    function XToBeat(X: Integer): Double;
    procedure ZoomAt(Shift: TShiftState; Delta,X: Integer);
    property Data: TMusicStudioInstrumentData read FData;
    property Rules: TMusicStudioInstrumentRules read FRules;
    property Grid: TInstrumentGrid read FGrid;
    property TimelineRowHeight: Integer read RowHeight;
    property Position: Double read FPosition;
    property IsPlaying: Boolean read FPlaying;
    property PlayButton: TButton read FPlay;
    property StopButton: TButton read FStop;
    property LengthEdit: TEdit read FLength;
    property PlaybackTimer: TTimer read FTimer;
    property SnapStep: Double read GridStep;
    property ZoomFactor: Double read FZoom;
    property ViewStartBeat: Double read FViewStart;
    property OnPositionChange: TNotifyEvent read FOnPosition write FOnPosition;
  end;
implementation
uses System.SysUtils, System.Math, System.UITypes, SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme,
  SYNC_MusicStudio_InstrumentPlayback;
{$R *.dfm}
procedure TInstrumentGrid.Paint;
begin if FOwnerFrame<>nil then FOwnerFrame.Draw; end;
procedure TInstrumentGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; SetFocus; FOwnerFrame.Down(Button,X,Y); end;
procedure TInstrumentGrid.MouseMove(Shift: TShiftState; X,Y: Integer);
begin inherited; FOwnerFrame.Move(X,Y); end;
procedure TInstrumentGrid.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; FOwnerFrame.Up(Button,X,Y); end;
function TInstrumentGrid.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := PtInRect(ClientRect,ScreenToClient(MousePos));
  if Result and (FOwnerFrame<>nil) then FOwnerFrame.Wheel(Shift,WheelDelta,ScreenToClient(MousePos).X);
end;
procedure TInstrumentGrid.MouseLeave(var Message: TMessage);
begin inherited; if (FOwnerFrame<>nil) and (FOwnerFrame.FMode=0) then Cursor := crDefault; end;
procedure TInstrumentGrid.CaptureChanged(var Message: TMessage);
begin inherited; if (FOwnerFrame<>nil) and not FMouseUp then FOwnerFrame.CancelDrag; end;
procedure TInstrumentGrid.WndProc(var Message: TMessage);
begin
  if Message.Msg=WM_LBUTTONUP then begin FMouseUp := True; try inherited; finally FMouseUp := False; end; end else inherited;
end;
constructor TMusicStudioInstrumentFrame.Create(AOwner: TComponent);
begin
  inherited; FData := TMusicStudioInstrumentData.Create; FRules := TMusicStudioInstrumentRules.Create;
  FHistory := TMusicStudioEditHistory.Create; FSelected := -1; FTempo := 120; FZoom := 1;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;
destructor TMusicStudioInstrumentFrame.Destroy;
begin
  FOnPosition := nil; if FTimer<>nil then FTimer.Enabled := False;
  CancelDrag; if FGrid<>nil then FGrid.FOwnerFrame := nil;
  FHistory.Free; FRules.Free; FData.Free; inherited;
end;
procedure TMusicStudioInstrumentFrame.SetParent(AParent: TWinControl);
begin inherited; if (AParent<>nil) and (FData<>nil) and (FGrid=nil) then BuildUI; end;
procedure TMusicStudioInstrumentFrame.BuildUI;
var L: TLabel;
begin
  FHeader := TPanel.Create(Self); FHeader.Parent := Self; FHeader.Align := alTop; FHeader.Height := 46;
  FHeader.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(FHeader);
  FPlay := TMusicStudioButton.Create(Self); FPlay.Parent := FHeader; FPlay.SetBounds(8,8,92,28);
  FPlay.Caption := '再生'; FPlay.OnClick := PlayClick; ApplySyncMusicStudioDarkButton(FPlay);
  FStop := TMusicStudioButton.Create(Self); FStop.Parent := FHeader; FStop.SetBounds(108,8,92,28);
  FStop.Caption := '停止'; FStop.OnClick := PlayClick; ApplySyncMusicStudioDarkButton(FStop);
  L := TLabel.Create(Self); L.Parent := FHeader; L.SetBounds(216,13,80,20); L.Caption := '長さ（拍）'; FLengthLabel := L;
  FLength := TEdit.Create(Self); FLength.Parent := FHeader; FLength.SetBounds(300,8,76,28);
  FLength.Text := '16'; ApplySyncMusicStudioDarkEdit(FLength); FLength.OnExit := LengthExit;
  FLength.OnKeyDown := LengthKeyDown; FLength.ShowHint := True;
  FLength.Hint := '保存とD&D配置に使う長さ。設定内の再生は、最後に配置した区間の末尾でループします。';
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.AutoSize := False;
  FStatus.Height := 44; FStatus.WordWrap := True;
  FStatus.Caption := 'PSDから行と候補を生成。空白ドラッグで区間追加、クリックで候補、中央で移動、両端で長さ。Delete / Ctrl+Z・Y';
  FGrid := TInstrumentGrid.Create(Self); FGrid.FOwnerFrame := Self; FGrid.Parent := Self;
  FGrid.Align := alClient; FGrid.DoubleBuffered := True; FGrid.TabStop := True;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 16; FTimer.OnTimer := Tick;
  FMenu := TPopupMenu.Create(Self);
  Resize;
end;
function TMusicStudioInstrumentFrame.P(Value: Integer): Integer;
begin Result := MulDiv(Value,Max(CurrentPPI,MulDiv(Abs(Font.Height),96,13)),96); end;
function TMusicStudioInstrumentFrame.RowHeight: Integer;
begin Result := Min(P(48),Max(1,(FGrid.Height-P(28)) div Max(1,FRules.RowCount))); end;
function TMusicStudioInstrumentFrame.RowIndex(const Name: string): Integer;
var I: Integer;
begin for I := 0 to FRules.RowCount-1 do if FRules.RowAt(I).Name=Name then Exit(I); Result := -1; end;
function TMusicStudioInstrumentFrame.XBeat(Beat: Double): Integer;
begin Result := Round(EnsureRange(P(134)+(Beat-FViewStart)*PixelsPerBeat,-500000000.0,500000000.0)); end;
function TMusicStudioInstrumentFrame.BeatAt(X: Integer): Double;
begin Result := EnsureRange(FViewStart+(X-P(134))/PixelsPerBeat,0.0,FData.LengthBeats); end;
function TMusicStudioInstrumentFrame.BeatToX(Beat: Double): Integer;
begin Result := XBeat(Beat); end;
function TMusicStudioInstrumentFrame.XToBeat(X: Integer): Double;
begin Result := BeatAt(X); end;
procedure TMusicStudioInstrumentFrame.ZoomAt(Shift: TShiftState; Delta,X: Integer);
begin Wheel(Shift,Delta,X); end;
function TMusicStudioInstrumentFrame.PixelsPerBeat: Double;
begin Result := Max(1,FGrid.Width-P(134)-1)/FData.LengthBeats*FZoom; end;
function TMusicStudioInstrumentFrame.GridStep: Double;
begin
  Result := 1;
  while PixelsPerBeat*Result<P(16) do Result := Result*2;
  while (Result>1/64) and (PixelsPerBeat*Result/2>=P(16)) do Result := Result/2;
end;
function TMusicStudioInstrumentFrame.ClampStart(Beat: Double): Double;
begin Result := EnsureRange(Beat,0.0,Max(0.0,FData.LengthBeats-Max(1,FGrid.Width-P(134)-1)/PixelsPerBeat)); end;
procedure TMusicStudioInstrumentFrame.Wheel(Shift: TShiftState; Delta,X: Integer);
var Anchor: Double;
begin
  CancelDrag; X := EnsureRange(X,P(134),FGrid.Width);
  Anchor := BeatAt(X);
  if ssShift in Shift then FViewStart := ClampStart(FViewStart-Delta/120*Max(1,FGrid.Width-P(134)-1)/PixelsPerBeat/4)
  else begin
    FZoom := EnsureRange(FZoom*Power(1.25,Delta/120),1.0,2048.0);
    FViewStart := ClampStart(Anchor-(X-P(134))/PixelsPerBeat);
  end;
  FStatus.Caption := Format('グリッド %g拍 / ホイール: 拡縮 / 中ボタンドラッグ: 横移動 / 区間中央: 移動 / 両端: 伸縮',[GridStep]);
  FGrid.Invalidate;
end;
function TMusicStudioInstrumentFrame.HitMode(X,Y: Integer; out Index: Integer): Integer;
var I,L,R: Integer; Area: TRect;
begin
  Index := -1; Result := 0; if (X<P(134)) or (Y<P(28)) then Exit;
  for I := FData.Blocks.Count-1 downto 0 do if RowIndex(FData.Blocks[I].Row)>=0 then begin
    Area := Bounds(FData.Blocks[I]); if not PtInRect(Area,Point(X,Y)) then Continue;
    Index := I; L := Abs(X-Area.Left); R := Abs(X-Area.Right); Result := 2;
    if (L<=P(5)) and (L<=R) then Result := 3 else if R<=P(5) then Result := 4;
    Exit;
  end;
end;
function TMusicStudioInstrumentFrame.Bounds(const B: TInstrumentBlock): TRect;
var Y,Inset: Integer;
begin Y := P(28)+RowIndex(B.Row)*RowHeight; Inset := Min(P(5),RowHeight div 4); Result := Rect(XBeat(B.StartBeat),Y+Inset,XBeat(B.EndBeat),Y+RowHeight-Inset); end;
procedure TMusicStudioInstrumentFrame.Resize;
var LabelWidth: Integer;
begin
  inherited;
  if FGrid=nil then Exit;
  FHeader.Height := P(48);
  FPlay.SetBounds(P(8),P(8),P(92),P(30)); FStop.SetBounds(P(108),P(8),P(92),P(30));
  FGrid.Canvas.Font.Assign(Font); LabelWidth := FGrid.Canvas.TextWidth(FLengthLabel.Caption)+P(8);
  FLengthLabel.AutoSize := False; FLengthLabel.SetBounds(P(216),P(8),LabelWidth,P(30));
  FLength.SetBounds(P(216)+LabelWidth,P(8),P(76),P(30));
  FStatus.Height := P(44);
  FViewStart := ClampStart(FViewStart); CancelDrag; FGrid.Invalidate;
end;
procedure TMusicStudioInstrumentFrame.BindRules(Rules: TMusicStudioInstrumentRules);
var NewRules: TMusicStudioInstrumentRules; B: TInstrumentBlock;
begin
  NewRules := Rules.Clone; FRules.Free; FRules := NewRules; FSelected := -1; CancelDrag;
  FStatus.Caption := 'ホイール: 拡縮 / 中ボタンドラッグ: 横移動 / 空白ドラッグ: 追加 / 区間中央: 移動 / 両端: 伸縮 / Ctrl+Z・Y';
  for B in FData.Blocks do if not FRules.HasChoice(B.Row,B.Choice) then FStatus.Caption := 'PSDにない候補を含みます。区間は保持しています。PSDを修正するか候補を選び直してください。';
  FGrid.Invalidate;
end;
procedure TMusicStudioInstrumentFrame.LoadPattern(const ConfigJSON,AssetID: string; Rules: TMusicStudioInstrumentRules; Tempo: Double);
begin
  Stop; FData.Load(ConfigJSON); FData.BindAsset(AssetID); FZoom := 1; FViewStart := 0; BindRules(Rules); FHistory.Clear;
  FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); FTempo := Tempo;
end;
function TMusicStudioInstrumentFrame.ConfigJSON: string;
begin LengthExit(nil); Result := FData.JSON; end;
function TMusicStudioInstrumentFrame.PreviewStates: TArray<TInstrumentState>;
var Beat: Double; Blocks: TArray<TInstrumentBlock>;
begin
  Beat := FPosition; if (FMode>=1) and (FMode<=4) then Beat := FDraftPosition;
  Blocks := FData.Blocks.ToArray;
  if (FMode>=1) and (FMode<=4) then begin
    if FSelected>=0 then Blocks[FSelected] := FCandidate else Blocks := Blocks+[FCandidate];
  end;
  Result := MusicStudioInstrumentPlaybackStates(Blocks,FRules,Beat);
end;
procedure TMusicStudioInstrumentFrame.Change(const Before: string);
begin FHistory.RecordChange(Before,FData.JSON); FGrid.Invalidate; Seek(FPosition); end;
procedure TMusicStudioInstrumentFrame.LengthExit(Sender: TObject);
var Value: Double; Before: string;
begin
  Before := FData.JSON;
  try
    if not TryStrToFloat(FLength.Text,Value,TFormatSettings.Invariant) then raise Exception.Create('演奏長を拍で入力してください。');
    if Value=FData.LengthBeats then Exit;
    FData.SetLength(Value); FViewStart := ClampStart(FViewStart); Change(Before);
    FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant);
  except on E: Exception do begin FStatus.Caption := E.Message; if Sender=nil then raise; end; end;
end;
procedure TMusicStudioInstrumentFrame.LengthKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key=VK_RETURN then begin
    Key := 0;
    try LengthExit(nil); if FGrid.CanFocus then FGrid.SetFocus; except on E: Exception do FStatus.Caption := E.Message; end;
  end else if Key=VK_ESCAPE then begin
    Key := 0; FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant);
  end;
end;
procedure TMusicStudioInstrumentFrame.Seek(Beat: Double);
begin FPosition := EnsureRange(Beat,0.0,FData.LengthBeats); FOrigin := FPosition; FTick := GetTickCount64; FGrid.Invalidate; if Assigned(FOnPosition) then FOnPosition(Self); end;
procedure TMusicStudioInstrumentFrame.Stop;
begin FPlaying := False; if FTimer<>nil then FTimer.Enabled := False; if FPlay<>nil then FPlay.Caption := '再生'; if FGrid<>nil then Seek(0); end;
procedure TMusicStudioInstrumentFrame.PlayClick(Sender: TObject);
begin
  if Sender=FStop then begin Stop; Exit; end;
  if FPlaying then begin Tick(nil); FPlaying := False; FPlay.Caption := '再生'; end
  else begin
    // 再生開始時は未確定の末尾を保存。一時停止は不正入力中でも可能にする。
    try LengthExit(nil); except Exit; end;
    if FPosition>=FData.PlaybackEndBeat then Seek(0); FOrigin := FPosition; FTick := GetTickCount64; FPlaying := True; FPlay.Caption := '一時停止';
  end;
  FTimer.Enabled := FPlaying;
end;
procedure TMusicStudioInstrumentFrame.Tick(Sender: TObject);
var Beat,LoopEnd: Double;
begin
  if not FPlaying then Exit; Beat := FOrigin+(GetTickCount64-FTick)/60000*FTempo;
  LoopEnd := FData.PlaybackEndBeat;
  FPosition := Beat-Floor(Beat/LoopEnd)*LoopEnd; FGrid.Invalidate; if Assigned(FOnPosition) then FOnPosition(Self);
end;
procedure TMusicStudioInstrumentFrame.Draw;
var C: TCanvas; I,Y,Saved,X,NextLabelX: Integer; R: TRect; Beat,Step: Double; LabelText: string;
  procedure DrawBlock(const Block: TInstrumentBlock; Selected: Boolean);
  var Q: TRect; Caption: string;
  begin
    if RowIndex(Block.Row)<0 then Exit; Q := Bounds(Block);
    C.Brush.Color := $006B5842; if not FRules.HasChoice(Block.Row,Block.Choice) then C.Brush.Color := $00444488;
    C.Pen.Color := $00998C7A; if Selected then C.Pen.Color := clWhite; C.Rectangle(Q);
    InflateRect(Q,-P(4),0); C.Font.Color := clWhite; C.Brush.Style := bsClear;
    Caption := Block.Choice;
    DrawText(C.Handle,PChar(Caption),-1,Q,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS); C.Brush.Style := bsSolid;
  end;
begin
  C := FGrid.Canvas; C.Font.Assign(Font); C.Brush.Color := $00222222; C.FillRect(FGrid.ClientRect);
  C.Font.Color := $00E0E0E0;
  for I := 0 to FRules.RowCount-1 do begin
    Y := P(28)+I*RowHeight; C.Brush.Color := $002B2B2B; C.FillRect(Rect(0,Y,P(134),Y+RowHeight));
    R := Rect(P(8),Y,P(128),Y+RowHeight); DrawText(C.Handle,PChar(FRules.RowAt(I).Name),-1,R,DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
    C.Pen.Color := $003A3A3A; C.MoveTo(P(134),Y+RowHeight-1); C.LineTo(FGrid.Width,Y+RowHeight-1);
  end;
  Saved := SaveDC(C.Handle);
  try
    IntersectClipRect(C.Handle,P(134),0,FGrid.Width,FGrid.Height);
    Step := GridStep; Beat := Floor(FViewStart/Step)*Step; NextLabelX := P(134);
    while Beat<=Min(FData.LengthBeats,FViewStart+(FGrid.Width-P(134))/PixelsPerBeat)+1E-8 do begin
      if Abs(Beat/4-Round(Beat/4))<1E-8 then C.Pen.Color := $00666666
      else if Abs(Beat-Round(Beat))<1E-8 then C.Pen.Color := $00484848 else C.Pen.Color := $00353535;
      X := XBeat(Beat); C.MoveTo(X,0); C.LineTo(X,FGrid.Height); LabelText := '';
      if Abs(Beat/4-Round(Beat/4))<1E-8 then LabelText := IntToStr(Round(Beat/4)+1)
      else if (Abs(Beat-Round(Beat))<1E-8) and (PixelsPerBeat>=P(48)) then
        LabelText := IntToStr(Floor(Beat/4)+1)+':'+IntToStr(Round(Beat) mod 4+1);
      if (LabelText<>'') and (X>=NextLabelX) then begin
        C.TextOut(X+P(2),P(2),LabelText); NextLabelX := X+C.TextWidth(LabelText)+P(12);
      end;
      Beat := Beat+Step;
    end;
    for I := 0 to FData.Blocks.Count-1 do if (FMode<2) or (FMode>4) or (I<>FSelected) then
      DrawBlock(FData.Blocks[I],I=FSelected);
    if (FMode>=1) and (FMode<=4) then DrawBlock(FCandidate,True);
    X := XBeat(FData.LengthBeats); C.Pen.Color := $0078B8D8;
    C.MoveTo(X,P(28)); C.LineTo(X,FGrid.Height); C.Brush.Style := bsClear;
    C.Font.Color := $0078B8D8;
    if FData.PlaybackEndBeat=FData.LengthBeats then
      C.TextOut(X+P(4),P(30),'末尾 '+FloatToStr(FData.LengthBeats,TFormatSettings.Invariant)+'拍');
    if FData.PlaybackEndBeat<FData.LengthBeats then begin
      X := XBeat(FData.PlaybackEndBeat); C.Pen.Color := $0099D899; C.Font.Color := $0099D899;
      C.MoveTo(X,P(28)); C.LineTo(X,FGrid.Height);
      C.TextOut(X+P(4),P(30),'ループ末尾 '+FloatToStr(FData.PlaybackEndBeat,TFormatSettings.Invariant)+'拍');
    end;
    C.Brush.Style := bsSolid;
    C.Pen.Color := $0080E8FF; C.MoveTo(XBeat(FPosition),0); C.LineTo(XBeat(FPosition),FGrid.Height);
  finally RestoreDC(C.Handle,Saved); C.Refresh; end;
end;
procedure TMusicStudioInstrumentFrame.CancelDrag;
begin
  FMode := 0; if FGrid<>nil then begin FGrid.MouseCapture := False; FGrid.Cursor := crDefault; FGrid.Invalidate; end;
  if Assigned(FOnPosition) then FOnPosition(Self);
end;
procedure TMusicStudioInstrumentFrame.PreviewDrag(X: Integer);
begin
  FDraftPosition := EnsureRange(BeatAt(X),FCandidate.StartBeat,FCandidate.EndBeat-Min(1E-6,(FCandidate.EndBeat-FCandidate.StartBeat)/2));
  FGrid.Invalidate; if Assigned(FOnPosition) then FOnPosition(Self);
end;
procedure TMusicStudioInstrumentFrame.Down(Button: TMouseButton; X,Y: Integer);
var Row: Integer; Step: Double;
begin
  CancelDrag; if X<P(134) then Exit;
  if Button=mbMiddle then begin FMode := 5; FDownX := X; FPanStart := FViewStart; FGrid.MouseCapture := True; FGrid.Cursor := crHandPoint; Exit; end;
  if Button<>mbLeft then Exit;
  if Y<P(28) then begin
    FMode := 6; FDownX := X; FPanStart := FViewStart; FMoved := False;
    FGrid.MouseCapture := True; FGrid.Cursor := crHandPoint; Exit;
  end;
  Row := (Y-P(28)) div RowHeight; if (Row<0) or (Row>=FRules.RowCount) then Exit;
  FMode := HitMode(X,Y,FSelected); Step := GridStep;
  FDownX := X; FAnchor := Floor((BeatAt(X)+1E-9)/Step)*Step; FMoved := False;
  if FSelected>=0 then begin
    FOriginal := FData.Blocks[FSelected]; FCandidate := FOriginal;
  end else begin
    if FAnchor>=FData.LengthBeats then Exit;
    FCandidate := Default(TInstrumentBlock); FCandidate.Row := FRules.RowAt(Row).Name; FCandidate.Choice := FRules.RowAt(Row).Choices[0];
    FCandidate.StartBeat := FAnchor; FCandidate.EndBeat := Min(FAnchor+Step,FData.LengthBeats);
    FCandidate.Stage := FRules.DefaultStage(FCandidate.Row,FCandidate.Choice);
    FMode := 1;
  end;
  FGrid.MouseCapture := True;
  FStatus.Caption := FCandidate.Row+' / '+FCandidate.Choice+' / 準備 25% → 打撃 50% → 余韻 25%（終了後も保持）';
  if FMode=1 then FGrid.Cursor := crCross else if FMode=2 then FGrid.Cursor := crSizeAll else FGrid.Cursor := crSizeWE;
  PreviewDrag(X);
end;
procedure TMusicStudioInstrumentFrame.Move(X,Y: Integer);
var Beat,Delta,Len,Step: Double; Mode,Index: Integer;
begin
  if FMode=0 then begin
    if (Y<P(28)) and (X>=P(134)) then begin FGrid.Cursor := crHandPoint; Exit; end;
    Mode := HitMode(X,Y,Index);
    if Mode=2 then FGrid.Cursor := crSizeAll else if (Mode=3) or (Mode=4) then FGrid.Cursor := crSizeWE else FGrid.Cursor := crDefault;
    Exit;
  end;
  if (FMode=5) or (FMode=6) then begin
    if Abs(X-FDownX)>P(3) then FMoved := True;
    if FMoved or (FMode=5) then FViewStart := ClampStart(FPanStart-(X-FDownX)/PixelsPerBeat);
    FGrid.Invalidate; Exit;
  end;
  if Abs(X-FDownX)>P(3) then FMoved := True; if not FMoved then Exit;
  Step := GridStep; Beat := Round(BeatAt(X)/Step)*Step;
  case FMode of
    1: begin FCandidate.StartBeat := Min(FAnchor,Min(Beat,FData.LengthBeats-Min(Step,FData.LengthBeats))); FCandidate.EndBeat := Min(FData.LengthBeats,Max(FAnchor+Step,Min(Beat,FData.LengthBeats))); end;
    2: begin Len := FOriginal.EndBeat-FOriginal.StartBeat; Delta := Round((BeatAt(X)-BeatAt(FDownX))/Step)*Step;
      FCandidate.StartBeat := EnsureRange(FOriginal.StartBeat+Delta,0.0,FData.LengthBeats-Len); FCandidate.EndBeat := FCandidate.StartBeat+Len; end;
    3: FCandidate.StartBeat := EnsureRange(Beat,0.0,FOriginal.EndBeat-Min(Step,FOriginal.EndBeat-FOriginal.StartBeat));
    4: FCandidate.EndBeat := EnsureRange(Beat,FOriginal.StartBeat+Min(Step,FOriginal.EndBeat-FOriginal.StartBeat),FData.LengthBeats);
  end;
  PreviewDrag(X);
end;
procedure TMusicStudioInstrumentFrame.Up(Button: TMouseButton; X,Y: Integer);
var Before: string; Popup: Boolean; Mode: Integer;
begin
  if (Button=mbLeft) and (FMode=6) then begin
    Move(X,Y); Popup := not FMoved; CancelDrag; if Popup then Seek(BeatAt(X)); Exit;
  end;
  if (Button=mbMiddle) and (FMode=5) then begin CancelDrag; Exit; end;
  if (Button<>mbLeft) or (FMode=0) then Exit; Move(X,Y); Mode := FMode; Popup := not FMoved and (FSelected>=0);
  Before := FData.JSON;
  if FMoved then if FData.PutBlock(FSelected,FCandidate) then begin if Mode=1 then FSelected := FData.Blocks.Count-1; Change(Before); end
  else FStatus.Caption := '同じ行の区間は重ねられません。';
  CancelDrag; if Popup then PopupAt(X,Y);
end;
procedure TMusicStudioInstrumentFrame.PopupAt(X,Y: Integer);
var Row: TInstrumentRow; Item,StageRoot: TMenuItem; I,N: Integer; Values: TArray<Integer>; Point: TPoint;
begin
  if FSelected<0 then Exit; N := RowIndex(FData.Blocks[FSelected].Row); if N<0 then Exit; Row := FRules.RowAt(N); FMenu.Items.Clear;
  for I := 0 to High(Row.Choices) do begin Item := TMenuItem.Create(FMenu); Item.Caption := Row.Choices[I]; Item.Tag := I;
    Item.Checked := Row.Choices[I]=FData.Blocks[FSelected].Choice; Item.OnClick := Choose; FMenu.Items.Add(Item); end;
  if Row.Kind=irkAction then begin
    StageRoot := TMenuItem.Create(FMenu); StageRoot.Caption := '動作段階（自動：準備 → 打撃 → 余韻）'; FMenu.Items.Add(StageRoot);
    Values := FRules.Stages(Row.Name,FData.Blocks[FSelected].Choice);
    for I in Values do if I<=2 then begin Item := TMenuItem.Create(FMenu); Item.Caption := FRules.StageCaption(Row.Name,FData.Blocks[FSelected].Choice,I); Item.Enabled := False; StageRoot.Add(Item); end;
  end;
  Point := FGrid.ClientToScreen(System.Types.Point(X,Y)); FMenu.Popup(Point.X,Point.Y);
end;
procedure TMusicStudioInstrumentFrame.Choose(Sender: TObject);
var B: TInstrumentBlock; Before: string;
begin
  B := FData.Blocks[FSelected]; Before := FData.JSON; B.Choice := FRules.RowAt(RowIndex(B.Row)).Choices[TMenuItem(Sender).Tag];
  B.Stage := FRules.DefaultStage(B.Row,B.Choice);
  FStatus.Caption := B.Row+' / '+B.Choice+' / 準備 → 打撃 → 余韻（余韻なしは準備へ戻る）';
  FData.PutBlock(FSelected,B); Change(Before);
end;
procedure TMusicStudioInstrumentFrame.HandleKey(var Key: Word; Shift: TShiftState);
var Before,Text: string;
begin
  if Key=VK_ESCAPE then begin if FMode<>0 then begin CancelDrag; Key := 0; end; Exit; end;
  Before := FData.JSON;
  if (Key=Ord('Z')) and (ssCtrl in Shift) then begin CancelDrag; if FHistory.Undo(Before,Text) then FData.Load(Text); Key := 0; end
  else if (Key=Ord('Y')) and (ssCtrl in Shift) then begin CancelDrag; if FHistory.Redo(Before,Text) then FData.Load(Text); Key := 0; end
  else if Key=VK_DELETE then begin CancelDrag; FData.DeleteBlock(FSelected); Change(Before); Key := 0; end
  else if Key=VK_SPACE then begin PlayClick(FPlay); Key := 0; end else Exit;
  FSelected := -1; FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); Seek(FPosition);
end;
end.
