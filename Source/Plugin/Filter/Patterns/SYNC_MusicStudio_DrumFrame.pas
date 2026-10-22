unit SYNC_MusicStudio_DrumFrame;

// ドラム操作UI。PSDと音声を呼ばず、編集データと無音時計のsnapshotを通知する。
// ドラッグ候補はmouseupで確定。取消/capture喪失では保存せず、親フォームが作品の適用を担当する。
interface
uses System.Classes, System.Types, Winapi.Windows, Winapi.Messages,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Menus,
  SYNC_MusicStudio_DrumData, SYNC_MusicStudio_EditHistory;
type
  TDrumTransport = (dtStopped, dtPlaying, dtPaused);
  TDrumPreviewEvent = procedure(Sender: TObject; Beat: Double; State: TDrumTransport;
    Emotion, Motion: Integer) of object;
  TMusicStudioDrumFrame = class;
  TMusicStudioDrumGrid = class(TCustomControl)
  private
    FEditor: TMusicStudioDrumFrame;
    FHandlingMouseUp: Boolean;
    procedure CaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  end;
  TMusicStudioDrumFrame = class(TFrame)
  private
    FData: TMusicStudioDrumData;
    FHistory: TMusicStudioEditHistory;
    FGrid: TMusicStudioDrumGrid;
    FHeader: TPanel;
    FBars,FDivision: TComboBox;
    FPlay,FStop: TButton;
    FStatus: TLabel;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FSelected,FDragMode,FDownX,FDownY: Integer;
    FAnchor,FPosition,FClockBeat: Double;
    FClockTick: UInt64;
    FCandidate,FOriginal: TDrumBar;
    FUpdating,FMoved: Boolean;
    FState: TDrumTransport;
    FOnPreview: TDrumPreviewEvent;
    FTempo: Double;
    procedure BuildUI;
    procedure Configure(Sender: TObject);
    procedure DrawCombo(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure Transport(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure KindClick(Sender: TObject);
    procedure BuildMenu;
    procedure Publish;
    procedure Commit(const Before: string);
    procedure CancelDrag;
    procedure PaintGrid;
    procedure Down(Button: TMouseButton; X,Y: Integer);
    procedure Move(X,Y: Integer);
    procedure Up(Button: TMouseButton; X,Y: Integer);
    function Scale(Value: Integer): Integer;
    function RowHeight: Integer;
    function LabelWidth: Integer;
    function PixelsPerBeat: Double;
    function BeatAt(X: Integer): Double;
    function XAt(Beat: Double): Integer;
    function BarRect(const B: TDrumBar): TRect;
    function FindBar(X,Y: Integer): Integer;
    procedure RefreshControls;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Load(const Text: string);
    function ConfigJSON: string;
    procedure Stop;
    procedure Seek(Beat: Double);
    procedure HandleKey(var Key: Word; Shift: TShiftState);
    property Data: TMusicStudioDrumData read FData;
    property Grid: TMusicStudioDrumGrid read FGrid;
    property Position: Double read FPosition;
    property State: TDrumTransport read FState;
    property TempoBPM: Double read FTempo write FTempo;
    property OnPreview: TDrumPreviewEvent read FOnPreview write FOnPreview;
  end;
implementation
uses System.SysUtils, System.Math, System.UITypes, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
{$R *.dfm}
type
  // ネイティブの開閉/キーボード操作を維持し、テーマ依存で白く残る矢印だけを補う。
  TMusicStudioDrumComboBox = class(TComboBox)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

procedure TMusicStudioDrumComboBox.WndProc(var Message: TMessage);
var Info: TComboBoxInfo; DC: HDC; C: TCanvas; X,Y,D: Integer;
begin
  inherited;
  if (Message.Msg<>WM_PAINT) and (Message.Msg<>WM_PRINTCLIENT) then Exit;
  Info.cbSize := SizeOf(Info); if not GetComboBoxInfo(Handle,Info) then Exit;
  if Message.Msg=WM_PRINTCLIENT then DC := HDC(Message.WParam) else DC := GetDC(Handle);
  if DC=0 then Exit;
  C := TCanvas.Create;
  try
    C.Handle := DC; C.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR; C.FillRect(Info.rcButton);
    C.Brush.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR; if not Enabled then C.Brush.Color := clGray;
    C.Pen.Color := C.Brush.Color;
    X := (Info.rcButton.Left+Info.rcButton.Right) div 2; Y := (Info.rcButton.Top+Info.rcButton.Bottom) div 2;
    D := Max(2,MulDiv(3,CurrentPPI,96)); C.Polygon([Point(X-D,Y-1),Point(X+D,Y-1),Point(X,Y+D-1)]);
    C.Handle := 0;
  finally C.Free; if Message.Msg=WM_PAINT then ReleaseDC(Handle,DC); end;
end;

procedure TMusicStudioDrumGrid.Paint;
begin FEditor.PaintGrid; end;
procedure TMusicStudioDrumGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; SetFocus; FEditor.Down(Button,X,Y); end;
procedure TMusicStudioDrumGrid.MouseMove(Shift: TShiftState; X,Y: Integer);
begin inherited; FEditor.Move(X,Y); end;
procedure TMusicStudioDrumGrid.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; FEditor.Up(Button,X,Y); end;
procedure TMusicStudioDrumGrid.KeyDown(var Key: Word; Shift: TShiftState);
begin FEditor.HandleKey(Key,Shift); inherited; end;
procedure TMusicStudioDrumGrid.CaptureChanged(var Message: TMessage);
begin inherited; if (FEditor<>nil) and not FHandlingMouseUp then FEditor.CancelDrag; end;
procedure TMusicStudioDrumGrid.WndProc(var Message: TMessage);
begin
  // VCLはmouseupハンドラより先にcaptureを解放する。その経路だけは確定を許す。
  if Message.Msg=WM_LBUTTONUP then begin
    FHandlingMouseUp := True;
    try inherited; finally FHandlingMouseUp := False; end;
  end else inherited;
end;

constructor TMusicStudioDrumFrame.Create(AOwner: TComponent);
begin
  inherited;
  FData := TMusicStudioDrumData.Create; FHistory := TMusicStudioEditHistory.Create;
  FSelected := -1; FTempo := 120; FDragMode := 0;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;
procedure TMusicStudioDrumFrame.SetParent(AParent: TWinControl);
begin
  inherited;
  if (AParent<>nil) and (FData<>nil) and (FGrid=nil) then begin
    FUpdating := True;
    try BuildUI; finally FUpdating := False; end;
    RefreshControls;
  end;
end;
procedure TMusicStudioDrumFrame.BuildUI;
var L: TLabel; I: Integer;
  procedure Combo(var C: TComboBox; X,W: Integer);
  begin
    C := TMusicStudioDrumComboBox.Create(Self); C.Parent := FHeader; C.SetBounds(X,8,W,28);
    ApplySyncMusicStudioDarkComboBox(C,DrawCombo); C.OnChange := Configure;
  end;
  procedure LabelAt(const S: string; X: Integer);
  begin L := TLabel.Create(Self); L.Parent := FHeader; L.SetBounds(X,13,50,20); L.Caption := S; end;
begin
  FHeader := TPanel.Create(Self); FHeader.Parent := Self; FHeader.Align := alTop;
  FHeader.Height := 46; FHeader.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(FHeader);
  FPlay := TMusicStudioButton.Create(Self); FPlay.Parent := FHeader; FPlay.SetBounds(8,8,92,28);
  FPlay.Caption := '再生'; FPlay.OnClick := Transport; ApplySyncMusicStudioDarkButton(FPlay);
  FStop := TMusicStudioButton.Create(Self); FStop.Parent := FHeader; FStop.SetBounds(108,8,92,28);
  FStop.Caption := '停止'; FStop.OnClick := Transport; ApplySyncMusicStudioDarkButton(FStop);
  LabelAt('小節',212); Combo(FBars,250,58); for I := 1 to 64 do FBars.Items.Add(IntToStr(I)); FBars.ItemIndex := 0;
  LabelAt('分割',320); Combo(FDivision,358,62); FDivision.Items.CommaText := '4,8,12,16,24,32,48,64'; FDivision.ItemIndex := 3;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self; FStatus.Align := alBottom;
  FStatus.AutoSize := False; FStatus.Height := 48; FStatus.WordWrap := True;
  FGrid := TMusicStudioDrumGrid.Create(Self); FGrid.FEditor := Self; FGrid.Parent := Self;
  FGrid.Align := alClient; FGrid.TabStop := True; FGrid.DoubleBuffered := True;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 33; FTimer.OnTimer := Tick;
  FMenu := TPopupMenu.Create(Self);
  RefreshControls;
end;
destructor TMusicStudioDrumFrame.Destroy;
begin
  if FTimer<>nil then FTimer.Enabled := False;
  FOnPreview := nil; CancelDrag; if FGrid<>nil then FGrid.FEditor := nil;
  FHistory.Free; FData.Free; inherited;
end;
function TMusicStudioDrumFrame.Scale(Value: Integer): Integer;
var Form: TCustomForm;
begin
  Form := GetParentForm(Self);
  if Form<>nil then Result := MulDiv(Value,Form.CurrentPPI,96)
  else Result := MulDiv(Value,CurrentPPI,96);
end;
function TMusicStudioDrumFrame.LabelWidth: Integer;
begin Result := Scale(134); end;
function TMusicStudioDrumFrame.RowHeight: Integer;
begin Result := Max(1,(FGrid.Height-Scale(28)) div (Length(FData.Rows)+2)); end;
function TMusicStudioDrumFrame.PixelsPerBeat: Double;
begin Result := Max(1,FGrid.Width-LabelWidth-1)/FData.LengthBeats; end;
function TMusicStudioDrumFrame.BeatAt(X: Integer): Double;
begin Result := EnsureRange((X-LabelWidth)/PixelsPerBeat,0.0,FData.LengthBeats); end;
function TMusicStudioDrumFrame.XAt(Beat: Double): Integer;
begin Result := LabelWidth+Round(Beat*PixelsPerBeat); end;
function TMusicStudioDrumFrame.BarRect(const B: TDrumBar): TRect;
var Y: Integer;
begin
  Y := Scale(28)+(Length(FData.Rows)+B.Lane)*RowHeight;
  Result := Rect(XAt(B.StartBeat),Y+Min(Scale(4),RowHeight div 4),XAt(B.EndBeat),Y+RowHeight-Min(Scale(4),RowHeight div 4));
end;
procedure TMusicStudioDrumFrame.Resize;
begin inherited; if FGrid<>nil then begin CancelDrag; RefreshControls; end; end;
procedure TMusicStudioDrumFrame.RefreshControls;
begin
  if (FGrid=nil) or (Parent=nil) then Exit;
  FUpdating := True;
  try
    FBars.ItemIndex := FData.Bars-1; FDivision.ItemIndex := FDivision.Items.IndexOf(IntToStr(FData.StepsPerBar));
    FStatus.Caption := '打点クリック: ON/OFF（橙=未判定・緑=正常・赤=異常）。右クリック: 表示状態。'+sLineBreak+
      '下2行: 空白ドラッグでバー追加、クリックで種類、中央で移動、両端で伸縮。Delete: 削除 / Ctrl+Z・Y';
    FGrid.Invalidate;
  finally FUpdating := False; end;
end;
procedure TMusicStudioDrumFrame.Load(const Text: string);
begin Stop; FData.Load(Text); FHistory.Clear; FSelected := -1; RefreshControls; end;
function TMusicStudioDrumFrame.ConfigJSON: string;
begin Result := FData.JSON; end;
procedure TMusicStudioDrumFrame.Commit(const Before: string);
begin FHistory.RecordChange(Before,FData.JSON); RefreshControls; Publish; end;
procedure TMusicStudioDrumFrame.Configure(Sender: TObject);
var Before: string;
begin
  if FUpdating then Exit; CancelDrag; Before := FData.JSON;
  try FData.SetGrid(FBars.ItemIndex+1,StrToInt(FDivision.Text));
    FPosition := Min(FPosition,FData.LengthBeats); FClockBeat := FPosition; FClockTick := GetTickCount64;
    Commit(Before);
  except on E: Exception do begin RefreshControls; FStatus.Caption := E.Message; end; end;
end;
procedure TMusicStudioDrumFrame.DrawCombo(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  DrawSyncMusicStudioDarkComboBoxItem(TComboBox(Control),Index,Rect,State,CurrentPPI);
end;
procedure TMusicStudioDrumFrame.Publish;
var B: TDrumBar; Emotion,Motion: Integer;
begin
  Emotion := 0; Motion := 0;
  for B in FData.Ranges do if (FPosition>=B.StartBeat) and (FPosition<B.EndBeat) then
    if B.Lane=0 then Emotion := B.Kind else Motion := B.Kind;
  if Assigned(FOnPreview) then FOnPreview(Self,FPosition,FState,Emotion,Motion);
end;
procedure TMusicStudioDrumFrame.Seek(Beat: Double);
begin
  FPosition := EnsureRange(Beat,0.0,FData.LengthBeats); FClockBeat := FPosition; FClockTick := GetTickCount64;
  FGrid.Invalidate; Publish;
end;
procedure TMusicStudioDrumFrame.Stop;
begin FTimer.Enabled := False; FState := dtStopped; FPlay.Caption := '再生'; Seek(0); end;
procedure TMusicStudioDrumFrame.Transport(Sender: TObject);
begin
  if Sender=FStop then begin Stop; Exit; end;
  if FState=dtPlaying then begin Tick(nil); FState := dtPaused; FTimer.Enabled := False; FPlay.Caption := '再生'; end
  else begin
    if FPosition>=FData.LengthBeats then Seek(0);
    FClockBeat := FPosition; FClockTick := GetTickCount64; FState := dtPlaying;
    FTimer.Enabled := True; FPlay.Caption := '一時停止';
  end;
  Publish;
end;
procedure TMusicStudioDrumFrame.Tick(Sender: TObject);
var B: Double;
begin
  if FState<>dtPlaying then Exit;
  B := FClockBeat+(GetTickCount64-FClockTick)/60000*EnsureRange(FTempo,1.0,999.99);
  FPosition := B-Floor(B/FData.LengthBeats)*FData.LengthBeats;
  FGrid.Invalidate; Publish;
end;
procedure TMusicStudioDrumFrame.PaintGrid;
var C: TCanvas; I,J,X,Y,RH,First,Last: Integer; H: TDrumHit; B: TDrumBar; R: TRect;
  procedure DrawBar(const Value: TDrumBar; Selected: Boolean);
  var Q: TRect;
  begin
    Q := BarRect(Value);
    if (Q.Right<LabelWidth) or (Q.Left>FGrid.Width) or (Q.Bottom<=Scale(28)) or (Q.Top>=FGrid.Height) then Exit;
    C.Brush.Color := $006B5842; if Value.Lane=1 then C.Brush.Color := $00634F63;
    C.Pen.Color := $00998C7A; if Selected then C.Pen.Color := $00FFFFFF;
    C.Rectangle(Q); C.Font.Color := clWhite;
    InflateRect(Q,-Scale(5),0); C.Brush.Style := bsClear;
    DrawText(C.Handle,PChar(DrumKindName(Value.Lane,Value.Kind)),-1,Q,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS);
    C.Brush.Style := bsSolid;
  end;
begin
  C := FGrid.Canvas; RH := RowHeight; C.Font.Assign(Font);
  C.Brush.Color := $00222222; C.FillRect(FGrid.ClientRect);
  SaveDC(C.Handle);
  try
    IntersectClipRect(C.Handle,LabelWidth,0,FGrid.Width,FGrid.Height);
    First := 0;
    Last := Min(FData.Bars*FData.StepsPerBar-1,Ceil(BeatAt(FGrid.Width)/FData.Step));
    for J := First to Last do begin
      X := XAt(J*FData.Step);
      if J mod FData.StepsPerBar=0 then begin C.Font.Color := clSilver; C.TextOut(X+3,3,IntToStr(J div FData.StepsPerBar+1)); end;
      for I := 0 to High(FData.Rows) do begin
        Y := Scale(28)+I*RH;
        if (Y<Scale(28)) or (Y>=FGrid.Height) then Continue;
        C.Brush.Color := $00383838; if (J div Max(1,FData.StepsPerBar div 4)) mod 2=1 then C.Brush.Color := $00434343;
        C.Pen.Color := $00222222; C.Rectangle(X+1,Y+Scale(5),Max(X+2,XAt((J+1)*FData.Step)-1),Y+RH-Scale(5));
      end;
    end;
    for H in FData.Hits do begin
      X := XAt(H.Beat); Y := Scale(28)+H.Row*RH;
      if (Y<Scale(28)) or (Y>=FGrid.Height) then Continue;
      case H.State of dhUnchecked: C.Brush.Color := $0064B8EA; dhPlayable: C.Brush.Color := $0087CF89; dhImpossible: C.Brush.Color := $005757E5; end;
      C.Pen.Color := C.Brush.Color;
      C.Rectangle(X+1,Y+Scale(6),Max(X+2,XAt(H.Beat+FData.Step)-1),Y+RH-Scale(6));
    end;
    for I := 0 to FData.Ranges.Count-1 do begin B := FData.Ranges[I]; if (FDragMode=0) or (I<>FSelected) then DrawBar(B,I=FSelected); end;
    if FDragMode>0 then DrawBar(FCandidate,True);
    C.Pen.Color := $0080E8FF; X := XAt(FPosition); C.MoveTo(X,0); C.LineTo(X,FGrid.Height);
  finally RestoreDC(C.Handle,-1); end;
  C.Brush.Color := $002B2B2B; C.FillRect(Rect(0,0,LabelWidth,FGrid.Height)); C.Font.Color := $00E0E0E0;
  C.TextOut(Scale(8),Scale(5),'4/4 ・ 無音');
  for I := 0 to Length(FData.Rows)+1 do begin
    Y := Scale(28)+I*RH;
    if (Y<Scale(28)) or (Y>=FGrid.Height) then Continue;
    R := Rect(Scale(8),Y,LabelWidth-Scale(6),Y+RH);
    if I<Length(FData.Rows) then DrawText(C.Handle,PChar(FData.Rows[I]),-1,R,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS)
    else if I=Length(FData.Rows) then DrawText(C.Handle,'表情',-1,R,DT_SINGLELINE or DT_VCENTER)
    else DrawText(C.Handle,'全体モーション',-1,R,DT_SINGLELINE or DT_VCENTER);
  end;
end;
function TMusicStudioDrumFrame.FindBar(X,Y: Integer): Integer;
var I: Integer;
begin for I := 0 to FData.Ranges.Count-1 do if PtInRect(BarRect(FData.Ranges[I]),Point(X,Y)) then Exit(I); Result := -1; end;
procedure TMusicStudioDrumFrame.CancelDrag;
begin FDragMode := 0; if Assigned(FGrid) then begin FGrid.MouseCapture := False; FGrid.Invalidate; end; end;
procedure TMusicStudioDrumFrame.Down(Button: TMouseButton; X,Y: Integer);
var Row,I: Integer; B: Double; Before: string; P: TPoint; Item: TMenuItem;
begin
  CancelDrag;
  if X<LabelWidth then Exit;
  if Y<Scale(28) then begin if Button=mbLeft then Seek(BeatAt(X)); Exit; end;
  Row := (Y-Scale(28)) div RowHeight;
  B := Floor((BeatAt(X)+1E-9)/FData.Step)*FData.Step;
  if Row<Length(FData.Rows) then begin
    FSelected := -1;
    // 分割変更前の非グリッド打点も、描画位置からそのまま操作できる。
    for I := FData.Hits.Count-1 downto 0 do
      if (FData.Hits[I].Row=Row) and (X>=XAt(FData.Hits[I].Beat)) and
        (X<Max(XAt(FData.Hits[I].Beat)+2,XAt(FData.Hits[I].Beat+FData.Step))) then begin B := FData.Hits[I].Beat; Break; end;
    if B>=FData.LengthBeats then Exit;
    Before := FData.JSON;
    if Button=mbLeft then begin FData.Toggle(Row,B); Commit(Before); end
    else if Button=mbRight then begin
      I := FData.HitAt(Row,B); if I<0 then Exit;
      FMenu.Items.Clear;
      for Row := 0 to 2 do begin
        Item := TMenuItem.Create(FMenu); Item.Tag := I*10+Row+1000;
        case Row of 0: Item.Caption := '未判定'; 1: Item.Caption := '正常（表示確認）'; 2: Item.Caption := '異常（表示確認）'; end;
        Item.OnClick := KindClick; Item.Checked := Ord(FData.Hits[I].State)=Row; FMenu.Items.Add(Item);
      end;
      P := FGrid.ClientToScreen(Point(X,Y)); FMenu.Popup(P.X,P.Y);
    end;
    Exit;
  end;
  if (Row>=Length(FData.Rows)+2) or (Button<>mbLeft) then Exit;
  FSelected := FindBar(X,Y); FDownX := X; FDownY := Y; FMoved := False; FAnchor := B;
  if FSelected>=0 then begin
    FOriginal := FData.Ranges[FSelected]; FCandidate := FOriginal; FDragMode := 2;
    if Abs(X-XAt(FOriginal.StartBeat))<=Min(Scale(6),Max(1,(XAt(FOriginal.EndBeat)-XAt(FOriginal.StartBeat)) div 3)) then FDragMode := 3
    else if Abs(X-XAt(FOriginal.EndBeat))<=Min(Scale(6),Max(1,(XAt(FOriginal.EndBeat)-XAt(FOriginal.StartBeat)) div 3)) then FDragMode := 4;
  end else begin
    FCandidate.Lane := Row-Length(FData.Rows); FCandidate.Kind := 0;
    FCandidate.StartBeat := B; FCandidate.EndBeat := Min(B+FData.Step,FData.LengthBeats); FDragMode := 1;
  end;
  FGrid.MouseCapture := True; FGrid.Invalidate;
end;
procedure TMusicStudioDrumFrame.Move(X,Y: Integer);
var B,Delta,Len: Double;
begin
  if FDragMode=0 then Exit;
  if (Abs(X-FDownX)>Scale(3)) or (Abs(Y-FDownY)>Scale(3)) then FMoved := True;
  if not FMoved then Exit;
  B := Round(BeatAt(X)/FData.Step)*FData.Step;
  case FDragMode of
    1: begin FCandidate.StartBeat := Min(FAnchor,Min(B,FData.LengthBeats-FData.Step)); FCandidate.EndBeat := Max(FAnchor+FData.Step,Min(B,FData.LengthBeats)); end;
    2: begin
      Len := FOriginal.EndBeat-FOriginal.StartBeat;
      Delta := Round((X-FDownX)/PixelsPerBeat/FData.Step)*FData.Step;
      FCandidate.StartBeat := EnsureRange(FOriginal.StartBeat+Delta,0.0,FData.LengthBeats-Len); FCandidate.EndBeat := FCandidate.StartBeat+Len;
    end;
    3: FCandidate.StartBeat := EnsureRange(B,0.0,FOriginal.EndBeat-Min(FData.Step,FOriginal.EndBeat-FOriginal.StartBeat));
    4: FCandidate.EndBeat := EnsureRange(B,FOriginal.StartBeat+Min(FData.Step,FOriginal.EndBeat-FOriginal.StartBeat),FData.LengthBeats);
  end;
  FGrid.Invalidate;
end;
procedure TMusicStudioDrumFrame.Up(Button: TMouseButton; X,Y: Integer);
var Before: string; Mode: Integer; OpenMenu: Boolean; P: TPoint;
begin
  if (Button<>mbLeft) or (FDragMode=0) then Exit;
  Move(X,Y); Mode := FDragMode; OpenMenu := not FMoved and (FSelected>=0); Before := FData.JSON;
  if FMoved then begin
    if FData.PutBar(FSelected,FCandidate) then begin
      if Mode=1 then FSelected := FData.Ranges.Count-1; Commit(Before);
    end else FStatus.Caption := '同じ行のバーは重ねられません。';
  end;
  CancelDrag;
  if OpenMenu then begin BuildMenu; P := FGrid.ClientToScreen(Point(X,Y)); FMenu.Popup(P.X,P.Y); end;
end;
procedure TMusicStudioDrumFrame.BuildMenu;
var I: Integer; Item: TMenuItem;
begin
  FMenu.Items.Clear;
  for I := 0 to 9 do begin
    Item := TMenuItem.Create(FMenu); Item.Caption := DrumKindName(FData.Ranges[FSelected].Lane,I);
    Item.Tag := I; Item.Checked := FData.Ranges[FSelected].Kind=I; Item.OnClick := KindClick; FMenu.Items.Add(Item);
  end;
end;
procedure TMusicStudioDrumFrame.KindClick(Sender: TObject);
var Before: string; B: TDrumBar; Tag: Integer;
begin
  Before := FData.JSON; Tag := TMenuItem(Sender).Tag;
  if Tag>=1000 then FData.SetHitState((Tag-1000) div 10,TDrumHitState((Tag-1000) mod 10))
  else if (FSelected>=0) and (FSelected<FData.Ranges.Count) then begin
    B := FData.Ranges[FSelected]; B.Kind := Tag; FData.PutBar(FSelected,B);
  end;
  Commit(Before);
end;
procedure TMusicStudioDrumFrame.HandleKey(var Key: Word; Shift: TShiftState);
var Before,Text: string;
begin
  if Key=VK_ESCAPE then begin if FDragMode<>0 then begin CancelDrag; Key := 0; end; Exit; end;
  Before := FData.JSON;
  if (ssCtrl in Shift) and (Key=Ord('Z')) then begin
    CancelDrag; if FHistory.Undo(Before,Text) then FData.Load(Text); Key := 0;
  end else if (ssCtrl in Shift) and (Key=Ord('Y')) then begin
    CancelDrag; if FHistory.Redo(Before,Text) then FData.Load(Text); Key := 0;
  end else if Key=VK_DELETE then begin
    CancelDrag; FData.DeleteBar(FSelected); FSelected := -1; Commit(Before); Key := 0;
  end else if Key=VK_SPACE then begin Transport(FPlay); Key := 0; end else Exit;
  FSelected := -1; RefreshControls; Publish;
end;
end.
