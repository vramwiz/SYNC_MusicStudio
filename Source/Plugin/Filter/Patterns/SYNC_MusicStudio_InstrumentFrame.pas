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
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  end;
  TMusicStudioInstrumentFrame = class(TFrame)
  private
    FData: TMusicStudioInstrumentData;
    FRules: TMusicStudioInstrumentRules;
    FHistory: TMusicStudioEditHistory;
    FGrid: TInstrumentGrid;
    FHeader: TPanel;
    FLength: TEdit;
    FPlay,FStop: TButton;
    FStatus: TLabel;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FSelected,FMode,FDownX: Integer;
    FCandidate,FOriginal: TInstrumentBlock;
    FAnchor,FPosition,FOrigin,FTempo: Double;
    FTick: UInt64;
    FPlaying,FMoved: Boolean;
    FOnPosition: TNotifyEvent;
    function P(Value: Integer): Integer;
    function RowHeight: Integer;
    function RowIndex(const Name: string): Integer;
    function XBeat(Beat: Double): Integer;
    function BeatAt(X: Integer): Double;
    function Bounds(const B: TInstrumentBlock): TRect;
    procedure BuildUI;
    procedure Draw;
    procedure Down(Button: TMouseButton; X,Y: Integer);
    procedure Move(X,Y: Integer);
    procedure Up(Button: TMouseButton; X,Y: Integer);
    procedure CancelDrag;
    procedure Change(const Before: string);
    procedure PopupAt(X,Y: Integer);
    procedure Choose(Sender: TObject);
    procedure ChooseStage(Sender: TObject);
    procedure LengthExit(Sender: TObject);
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
    procedure Seek(Beat: Double);
    procedure Stop;
    procedure HandleKey(var Key: Word; Shift: TShiftState);
    property Data: TMusicStudioInstrumentData read FData;
    property Rules: TMusicStudioInstrumentRules read FRules;
    property Grid: TInstrumentGrid read FGrid;
    property TimelineRowHeight: Integer read RowHeight;
    property Position: Double read FPosition;
    property OnPositionChange: TNotifyEvent read FOnPosition write FOnPosition;
  end;
implementation
uses System.SysUtils, System.Math, System.UITypes, SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme;
{$R *.dfm}
procedure TInstrumentGrid.Paint;
begin if FOwnerFrame<>nil then FOwnerFrame.Draw; end;
procedure TInstrumentGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; SetFocus; FOwnerFrame.Down(Button,X,Y); end;
procedure TInstrumentGrid.MouseMove(Shift: TShiftState; X,Y: Integer);
begin inherited; FOwnerFrame.Move(X,Y); end;
procedure TInstrumentGrid.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; FOwnerFrame.Up(Button,X,Y); end;
procedure TInstrumentGrid.CaptureChanged(var Message: TMessage);
begin inherited; if (FOwnerFrame<>nil) and not FMouseUp then FOwnerFrame.CancelDrag; end;
procedure TInstrumentGrid.WndProc(var Message: TMessage);
begin
  if Message.Msg=WM_LBUTTONUP then begin FMouseUp := True; try inherited; finally FMouseUp := False; end; end else inherited;
end;
constructor TMusicStudioInstrumentFrame.Create(AOwner: TComponent);
begin
  inherited; FData := TMusicStudioInstrumentData.Create; FRules := TMusicStudioInstrumentRules.Create;
  FHistory := TMusicStudioEditHistory.Create; FSelected := -1; FTempo := 120;
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
  L := TLabel.Create(Self); L.Parent := FHeader; L.SetBounds(216,13,80,20); L.Caption := '長さ（拍）';
  FLength := TEdit.Create(Self); FLength.Parent := FHeader; FLength.SetBounds(300,8,76,28);
  FLength.Text := '16'; ApplySyncMusicStudioDarkEdit(FLength); FLength.OnExit := LengthExit;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom; FStatus.AutoSize := False;
  FStatus.Height := 44; FStatus.WordWrap := True;
  FStatus.Caption := 'PSDから行と候補を生成。空白ドラッグで区間追加、クリックで候補、中央で移動、両端で長さ。Delete / Ctrl+Z・Y';
  FGrid := TInstrumentGrid.Create(Self); FGrid.FOwnerFrame := Self; FGrid.Parent := Self;
  FGrid.Align := alClient; FGrid.DoubleBuffered := True; FGrid.TabStop := True;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 33; FTimer.OnTimer := Tick;
  FMenu := TPopupMenu.Create(Self);
end;
function TMusicStudioInstrumentFrame.P(Value: Integer): Integer;
begin Result := MulDiv(Value,CurrentPPI,96); end;
function TMusicStudioInstrumentFrame.RowHeight: Integer;
begin Result := Min(P(48),Max(1,(FGrid.Height-P(28)) div Max(1,FRules.RowCount))); end;
function TMusicStudioInstrumentFrame.RowIndex(const Name: string): Integer;
var I: Integer;
begin for I := 0 to FRules.RowCount-1 do if FRules.RowAt(I).Name=Name then Exit(I); Result := -1; end;
function TMusicStudioInstrumentFrame.XBeat(Beat: Double): Integer;
begin Result := P(134)+Round(Beat/FData.LengthBeats*Max(1,FGrid.Width-P(134)-1)); end;
function TMusicStudioInstrumentFrame.BeatAt(X: Integer): Double;
begin Result := EnsureRange((X-P(134))/Max(1,FGrid.Width-P(134)-1)*FData.LengthBeats,0.0,FData.LengthBeats); end;
function TMusicStudioInstrumentFrame.Bounds(const B: TInstrumentBlock): TRect;
var Y,Inset: Integer;
begin Y := P(28)+RowIndex(B.Row)*RowHeight; Inset := Min(P(5),RowHeight div 4); Result := Rect(XBeat(B.StartBeat),Y+Inset,XBeat(B.EndBeat),Y+RowHeight-Inset); end;
procedure TMusicStudioInstrumentFrame.Resize;
begin inherited; if FGrid<>nil then begin CancelDrag; FGrid.Invalidate; end; end;
procedure TMusicStudioInstrumentFrame.BindRules(Rules: TMusicStudioInstrumentRules);
var NewRules: TMusicStudioInstrumentRules; B: TInstrumentBlock;
begin
  NewRules := Rules.Clone; FRules.Free; FRules := NewRules; FSelected := -1; CancelDrag;
  FStatus.Caption := '空白ドラッグ: 追加 / クリック: 候補・数値差分 / 中央: 移動 / 両端: 伸縮 / Delete / Ctrl+Z・Y';
  for B in FData.Blocks do if not FRules.HasChoice(B.Row,B.Choice) then FStatus.Caption := 'PSDにない候補を含みます。区間は保持しています。PSDを修正するか候補を選び直してください。';
  FGrid.Invalidate;
end;
procedure TMusicStudioInstrumentFrame.LoadPattern(const ConfigJSON,AssetID: string; Rules: TMusicStudioInstrumentRules; Tempo: Double);
begin
  Stop; FData.Load(ConfigJSON); FData.BindAsset(AssetID); BindRules(Rules); FHistory.Clear;
  FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); FTempo := Tempo;
end;
function TMusicStudioInstrumentFrame.ConfigJSON: string;
begin LengthExit(nil); Result := FData.JSON; end;
procedure TMusicStudioInstrumentFrame.Change(const Before: string);
begin FHistory.RecordChange(Before,FData.JSON); FGrid.Invalidate; Seek(FPosition); end;
procedure TMusicStudioInstrumentFrame.LengthExit(Sender: TObject);
var Value: Double; Before: string;
begin
  Before := FData.JSON;
  try
    if not TryStrToFloat(FLength.Text,Value,TFormatSettings.Invariant) then raise Exception.Create('演奏長を拍で入力してください。');
    FData.SetLength(Value); Change(Before);
  except on E: Exception do begin FStatus.Caption := E.Message; if Sender=nil then raise; end; end;
end;
procedure TMusicStudioInstrumentFrame.Seek(Beat: Double);
begin FPosition := EnsureRange(Beat,0.0,FData.LengthBeats); FOrigin := FPosition; FTick := GetTickCount64; FGrid.Invalidate; if Assigned(FOnPosition) then FOnPosition(Self); end;
procedure TMusicStudioInstrumentFrame.Stop;
begin FPlaying := False; if FTimer<>nil then FTimer.Enabled := False; if FPlay<>nil then FPlay.Caption := '再生'; if FGrid<>nil then Seek(0); end;
procedure TMusicStudioInstrumentFrame.PlayClick(Sender: TObject);
begin
  if Sender=FStop then begin Stop; Exit; end;
  if FPlaying then begin Tick(nil); FPlaying := False; FPlay.Caption := '再生'; end
  else begin if FPosition>=FData.LengthBeats then Seek(0); FOrigin := FPosition; FTick := GetTickCount64; FPlaying := True; FPlay.Caption := '一時停止'; end;
  FTimer.Enabled := FPlaying;
end;
procedure TMusicStudioInstrumentFrame.Tick(Sender: TObject);
var Beat: Double;
begin
  if not FPlaying then Exit; Beat := FOrigin+(GetTickCount64-FTick)/60000*FTempo;
  FPosition := Beat-Floor(Beat/FData.LengthBeats)*FData.LengthBeats; FGrid.Invalidate; if Assigned(FOnPosition) then FOnPosition(Self);
end;
procedure TMusicStudioInstrumentFrame.Draw;
var C: TCanvas; I,Y: Integer; R: TRect;
  procedure DrawBlock(const Block: TInstrumentBlock; Selected: Boolean);
  var Q: TRect;
  begin
    if RowIndex(Block.Row)<0 then Exit; Q := Bounds(Block);
    C.Brush.Color := $006B5842; if not FRules.HasChoice(Block.Row,Block.Choice) then C.Brush.Color := $00444488;
    C.Pen.Color := $00998C7A; if Selected then C.Pen.Color := clWhite; C.Rectangle(Q);
    InflateRect(Q,-P(4),0); C.Font.Color := clWhite; C.Brush.Style := bsClear;
    DrawText(C.Handle,PChar(Block.Choice),-1,Q,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS); C.Brush.Style := bsSolid;
  end;
begin
  C := FGrid.Canvas; C.Font.Assign(Font); C.Brush.Color := $00222222; C.FillRect(FGrid.ClientRect);
  C.Font.Color := $00E0E0E0;
  for I := 0 to FRules.RowCount-1 do begin
    Y := P(28)+I*RowHeight; C.Brush.Color := $002B2B2B; C.FillRect(Rect(0,Y,P(134),Y+RowHeight));
    R := Rect(P(8),Y,P(128),Y+RowHeight); DrawText(C.Handle,PChar(FRules.RowAt(I).Name),-1,R,DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
    C.Pen.Color := $003A3A3A; C.MoveTo(P(134),Y+RowHeight-1); C.LineTo(FGrid.Width,Y+RowHeight-1);
  end;
  for I := 0 to Min(256,Ceil(FData.LengthBeats/4)) do begin
    C.Pen.Color := $00404040; C.MoveTo(XBeat(I*4),0); C.LineTo(XBeat(I*4),FGrid.Height);
    C.TextOut(XBeat(I*4)+2,2,IntToStr(I+1));
  end;
  for I := 0 to FData.Blocks.Count-1 do if (FMode=0) or (I<>FSelected) then DrawBlock(FData.Blocks[I],I=FSelected);
  if FMode<>0 then DrawBlock(FCandidate,True);
  C.Pen.Color := $0080E8FF; C.MoveTo(XBeat(FPosition),0); C.LineTo(XBeat(FPosition),FGrid.Height);
end;
procedure TMusicStudioInstrumentFrame.CancelDrag;
begin FMode := 0; if FGrid<>nil then begin FGrid.MouseCapture := False; FGrid.Invalidate; end; end;
procedure TMusicStudioInstrumentFrame.Down(Button: TMouseButton; X,Y: Integer);
var I,Row: Integer; Values: TArray<Integer>;
begin
  CancelDrag; if (Button<>mbLeft) or (X<P(134)) then Exit;
  if Y<P(28) then begin Seek(BeatAt(X)); Exit; end;
  Row := (Y-P(28)) div RowHeight; if (Row<0) or (Row>=FRules.RowCount) then Exit;
  FSelected := -1; for I := 0 to FData.Blocks.Count-1 do if PtInRect(Bounds(FData.Blocks[I]),Point(X,Y)) then FSelected := I;
  FDownX := X; FAnchor := Floor((BeatAt(X)+1E-9)*4)/4; FMoved := False;
  if FSelected>=0 then begin
    FOriginal := FData.Blocks[FSelected]; FCandidate := FOriginal; FMode := 2;
    if Abs(X-XBeat(FOriginal.StartBeat))<=P(5) then FMode := 3
    else if Abs(X-XBeat(FOriginal.EndBeat))<=P(5) then FMode := 4;
  end else begin
    if FAnchor>=FData.LengthBeats then Exit;
    FCandidate := Default(TInstrumentBlock); FCandidate.Row := FRules.RowAt(Row).Name; FCandidate.Choice := FRules.RowAt(Row).Choices[0];
    FCandidate.StartBeat := FAnchor; FCandidate.EndBeat := Min(FAnchor+0.25,FData.LengthBeats);
    Values := FRules.Stages(FCandidate.Row,FCandidate.Choice); FCandidate.Stage := 1;
    if Length(Values)>0 then FCandidate.Stage := Values[0]; for I in Values do if I=1 then FCandidate.Stage := 1;
    FMode := 1;
  end;
  FGrid.MouseCapture := True;
end;
procedure TMusicStudioInstrumentFrame.Move(X,Y: Integer);
var Beat,Delta,Len: Double;
begin
  if FMode=0 then Exit; if Abs(X-FDownX)>P(3) then FMoved := True; if not FMoved then Exit;
  Beat := Round(BeatAt(X)*4)/4;
  case FMode of
    1: begin FCandidate.StartBeat := Min(FAnchor,Min(Beat,FData.LengthBeats-Min(0.25,FData.LengthBeats))); FCandidate.EndBeat := Min(FData.LengthBeats,Max(FAnchor+0.25,Min(Beat,FData.LengthBeats))); end;
    2: begin Len := FOriginal.EndBeat-FOriginal.StartBeat; Delta := Round((BeatAt(X)-BeatAt(FDownX))*4)/4;
      FCandidate.StartBeat := EnsureRange(FOriginal.StartBeat+Delta,0.0,FData.LengthBeats-Len); FCandidate.EndBeat := FCandidate.StartBeat+Len; end;
    3: FCandidate.StartBeat := EnsureRange(Beat,0.0,FOriginal.EndBeat-Min(0.25,FOriginal.EndBeat-FOriginal.StartBeat));
    4: FCandidate.EndBeat := EnsureRange(Beat,FOriginal.StartBeat+Min(0.25,FOriginal.EndBeat-FOriginal.StartBeat),FData.LengthBeats);
  end;
  FGrid.Invalidate;
end;
procedure TMusicStudioInstrumentFrame.Up(Button: TMouseButton; X,Y: Integer);
var Before: string; Popup: Boolean; Mode: Integer;
begin
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
  for I := 0 to High(Row.Choices) do begin Item := TMenuItem.Create(FMenu); Item.Caption := Row.Choices[I]; Item.Tag := I; Item.OnClick := Choose; FMenu.Items.Add(Item); end;
  if Row.Kind=irkAction then begin
    StageRoot := TMenuItem.Create(FMenu); StageRoot.Caption := '数値差分（再生方式は別設定）'; FMenu.Items.Add(StageRoot);
    Values := FRules.Stages(Row.Name,FData.Blocks[FSelected].Choice);
    for I in Values do begin Item := TMenuItem.Create(FMenu); Item.Caption := IntToStr(I); Item.Tag := I; Item.OnClick := ChooseStage; Item.Checked := I=FData.Blocks[FSelected].Stage; StageRoot.Add(Item); end;
  end;
  Point := FGrid.ClientToScreen(System.Types.Point(X,Y)); FMenu.Popup(Point.X,Point.Y);
end;
procedure TMusicStudioInstrumentFrame.Choose(Sender: TObject);
var B: TInstrumentBlock; Before: string; Values: TArray<Integer>;
begin
  B := FData.Blocks[FSelected]; Before := FData.JSON; B.Choice := FRules.RowAt(RowIndex(B.Row)).Choices[TMenuItem(Sender).Tag];
  Values := FRules.Stages(B.Row,B.Choice); if Length(Values)>0 then B.Stage := Values[0];
  FData.PutBlock(FSelected,B); Change(Before);
end;
procedure TMusicStudioInstrumentFrame.ChooseStage(Sender: TObject);
var B: TInstrumentBlock; Before: string;
begin B := FData.Blocks[FSelected]; Before := FData.JSON; B.Stage := TMenuItem(Sender).Tag; FData.PutBlock(FSelected,B); Change(Before); end;
procedure TMusicStudioInstrumentFrame.HandleKey(var Key: Word; Shift: TShiftState);
var Before,Text: string;
begin
  if Key=VK_ESCAPE then begin if FMode<>0 then begin CancelDrag; Key := 0; end; Exit; end;
  Before := FData.JSON;
  if (Key=Ord('Z')) and (ssCtrl in Shift) then begin CancelDrag; if FHistory.Undo(Before,Text) then FData.Load(Text); Key := 0; end
  else if (Key=Ord('Y')) and (ssCtrl in Shift) then begin CancelDrag; if FHistory.Redo(Before,Text) then FData.Load(Text); Key := 0; end
  else if Key=VK_DELETE then begin CancelDrag; FData.DeleteBlock(FSelected); Change(Before); Key := 0; end
  else if Key=VK_SPACE then begin PlayClick(FPlay); Key := 0; end else Exit;
  FSelected := -1; FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); FGrid.Invalidate;
end;
end.
