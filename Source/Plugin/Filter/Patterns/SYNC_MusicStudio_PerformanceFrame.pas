unit SYNC_MusicStudio_PerformanceFrame;

// 拍を正本とする演奏パターンのピアノロール編集。名前・色・確定は共通枠へ任せる。
// ノート追加/移動/削除と時間軸ズームを担当し、音声・楽器姿勢・ファイル解析は行わない。
interface

uses System.Classes, System.JSON, System.Types, Winapi.Windows,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  SYNC_MusicStudio_BeatData;

type
  TMusicStudioPerformanceFrame = class(TFrame)
  private
    FData: TMusicStudioPerformanceData;
    FLengthEdit, FVelocityEdit: TEdit;
    FDurationCombo: TComboBox;
    FStateLabel, FZoomLabel: TLabel;
    FRoll: TPaintBox;
    FHorizontal, FVertical: TScrollBar;
    FBitmap: TBitmap;
    FUpdating, FDragging: Boolean;
    FSelected, FTopPitch, FRenderCount: Integer;
    FDragPoint: TPoint;
    FDragNote: TMusicStudioPerformanceNote;
    FPixelsPerBeat, FStartBeat, FPreviewTempoBPM: Double;
    FNoteColor: TColor;
    FInputError: string;
    FOnChange: TNotifyEvent;
    procedure BuildUI;
    procedure LengthChanged(Sender: TObject);
    procedure HorizontalChanged(Sender: TObject);
    procedure VerticalChanged(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure RollPaint(Sender: TObject);
    procedure RollMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure RollMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure RollMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure RebuildRoll;
    procedure RefreshScrollbars;
    procedure Changed;
    function DevicePixelsPerBeat: Double;
    function KeyWidth: Integer;
    function RulerHeight: Integer;
    function PitchHeight: Integer;
    function PitchAt(Y: Integer): Integer;
    function BeatAt(X: Integer): Double;
    function HitNote(X,Y: Integer): Integer;
    function NewDuration: Double;
    procedure SetPixelsPerBeat(Value: Double);
    procedure SetViewStartBeat(Value: Double);
    procedure SetPreviewTempoBPM(Value: Double);
    procedure SetNoteColor(Value: TColor);
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadPerformance(const ConfigJSON: string); overload;
    procedure LoadPerformance(ConfigJSON: TJSONObject); overload;
    function ConfigJSON: string;
    function AddNote(StartBeat, LengthBeats: Double; Pitch, Velocity: Integer): Integer;
    procedure SelectNote(Index: Integer);
    procedure MoveSelectedNote(StartBeat: Double; Pitch: Integer);
    procedure DeleteSelectedNote;
    function NoteRect(Index: Integer): TRect;
    function SnapStep: Double;
    property Data: TMusicStudioPerformanceData read FData;
    property SelectedNote: Integer read FSelected;
    property PixelsPerBeat: Double read FPixelsPerBeat write SetPixelsPerBeat;
    property ViewStartBeat: Double read FStartBeat write SetViewStartBeat;
    property PreviewTempoBPM: Double read FPreviewTempoBPM write SetPreviewTempoBPM;
    property NoteColor: TColor read FNoteColor write SetNoteColor;
    property PianoRoll: TPaintBox read FRoll;
    property RenderCount: Integer read FRenderCount;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses System.SysUtils, System.Math, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

{$R *.dfm}

function IsBlackKey(Pitch: Integer): Boolean;
begin Result := Pitch mod 12 in [1,3,6,8,10]; end;

constructor TMusicStudioPerformanceFrame.Create(AOwner: TComponent);
begin
  inherited;
  FData := TMusicStudioPerformanceData.Create; FBitmap := TBitmap.Create;
  FSelected := -1; FTopPitch := 72; FPixelsPerBeat := 80; FPreviewTempoBPM := 120;
  FNoteColor := $008BDD9D; TabStop := True;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;

destructor TMusicStudioPerformanceFrame.Destroy;
begin FDragging := False; FreeAndNil(FBitmap); FreeAndNil(FData); inherited; end;

procedure TMusicStudioPerformanceFrame.SetParent(AParent: TWinControl);
var Component: TComponent;
begin
  inherited;
  if (AParent = nil) or (FData = nil) then Exit;
  if FRoll = nil then begin
    FUpdating := True;
    try
      BuildUI;
      FLengthEdit.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant);
    finally FUpdating := False; end;
    RefreshScrollbars; RebuildRoll;
  end;
  for Component in Self do if Component is TButton then ApplySyncMusicStudioDarkButton(TButton(Component));
end;

procedure TMusicStudioPerformanceFrame.BuildUI;
var Header, Footer, Body: TPanel; L: TLabel; B: TButton;
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop;
  Header.Height := 44; Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  L := TLabel.Create(Self); L.Parent := Header; L.SetBounds(12,13,70,20); L.Caption := '長さ（拍）';
  FLengthEdit := TEdit.Create(Self); FLengthEdit.Parent := Header; FLengthEdit.SetBounds(82,9,66,26);
  FLengthEdit.Text := '16'; ApplySyncMusicStudioDarkEdit(FLengthEdit); FLengthEdit.OnChange := LengthChanged;
  L := TLabel.Create(Self); L.Parent := Header; L.SetBounds(160,13,64,20); L.Caption := '音符長';
  FDurationCombo := TComboBox.Create(Self); FDurationCombo.Parent := Header;
  FDurationCombo.SetBounds(218,9,132,26); FDurationCombo.Style := csDropDownList;
  FDurationCombo.Items.Add('自動（スナップ）'); FDurationCombo.Items.Add('4拍');
  FDurationCombo.Items.Add('2拍'); FDurationCombo.Items.Add('1拍'); FDurationCombo.Items.Add('1/2拍');
  FDurationCombo.Items.Add('1/4拍'); FDurationCombo.Items.Add('1/8拍'); FDurationCombo.Items.Add('1/16拍');
  FDurationCombo.ItemIndex := 0; FDurationCombo.Color := $002E2E2E; FDurationCombo.Font.Color := $00E3E3E3;
  L := TLabel.Create(Self); L.Parent := Header; L.SetBounds(364,13,52,20); L.Caption := '強さ';
  FVelocityEdit := TEdit.Create(Self); FVelocityEdit.Parent := Header; FVelocityEdit.SetBounds(410,9,54,26);
  FVelocityEdit.Text := '100'; FVelocityEdit.MaxLength := 3; ApplySyncMusicStudioDarkEdit(FVelocityEdit);
  B := TMusicStudioButton.Create(Self); B.Parent := Header; B.SetBounds(480,8,88,28);
  B.Caption := '音符削除'; B.OnClick := DeleteClick; ApplySyncMusicStudioDarkButton(B);
  Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom;
  Footer.Height := 70; Footer.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Footer);
  FZoomLabel := TLabel.Create(Self); FZoomLabel.Parent := Footer; FZoomLabel.SetBounds(12,4,700,20);
  FZoomLabel.Anchors := [akLeft,akTop,akRight]; FZoomLabel.AutoSize := False;
  FStateLabel := TLabel.Create(Self); FStateLabel.Parent := Footer; FStateLabel.SetBounds(12,26,700,40);
  FStateLabel.Anchors := [akLeft,akTop,akRight]; FStateLabel.AutoSize := False; FStateLabel.WordWrap := True;
  FStateLabel.Caption := '左クリック: 追加/選択・ドラッグ: 移動・右クリック/Delete: 削除・Ctrl+ホイール: 時間軸ズーム';
  Body := TPanel.Create(Self); Body.Parent := Self; Body.Align := alClient;
  Body.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Body);
  FHorizontal := TScrollBar.Create(Self); FHorizontal.Parent := Body; FHorizontal.Align := alBottom;
  FHorizontal.Kind := sbHorizontal; FHorizontal.Height := 18; FHorizontal.OnChange := HorizontalChanged;
  FVertical := TScrollBar.Create(Self); FVertical.Parent := Body; FVertical.Align := alRight;
  FVertical.Kind := sbVertical; FVertical.Width := 18; FVertical.Min := 0; FVertical.Max := 127;
  FVertical.OnChange := VerticalChanged;
  FRoll := TPaintBox.Create(Self); FRoll.Parent := Body; FRoll.Align := alClient;
  FRoll.OnPaint := RollPaint; FRoll.OnMouseDown := RollMouseDown;
  FRoll.OnMouseMove := RollMouseMove; FRoll.OnMouseUp := RollMouseUp;
end;

function TMusicStudioPerformanceFrame.KeyWidth: Integer;
begin Result := MulDiv(54,CurrentPPI,96); end;
function TMusicStudioPerformanceFrame.RulerHeight: Integer;
begin Result := MulDiv(24,CurrentPPI,96); end;
function TMusicStudioPerformanceFrame.PitchHeight: Integer;
begin Result := Max(1,MulDiv(16,CurrentPPI,96)); end;
function TMusicStudioPerformanceFrame.DevicePixelsPerBeat: Double;
begin Result := FPixelsPerBeat*CurrentPPI/96; end;
function TMusicStudioPerformanceFrame.SnapStep: Double;
begin Result := MusicStudioSnapStep(FPixelsPerBeat); end;
function TMusicStudioPerformanceFrame.PitchAt(Y: Integer): Integer;
begin Result := FTopPitch-(Y-RulerHeight) div PitchHeight; end;
function TMusicStudioPerformanceFrame.BeatAt(X: Integer): Double;
begin Result := FStartBeat+(X-KeyWidth)/DevicePixelsPerBeat; end;

procedure TMusicStudioPerformanceFrame.Resize;
begin
  inherited;
  if (FRoll <> nil) and (FBitmap <> nil) then begin RefreshScrollbars; RebuildRoll; end;
end;

procedure TMusicStudioPerformanceFrame.RefreshScrollbars;
var MaxStart, VisibleBeats: Double;
begin
  if (FRoll = nil) or FUpdating then Exit;
  VisibleBeats := Max(0,FRoll.Width-KeyWidth)/DevicePixelsPerBeat;
  MaxStart := Max(0,FData.LengthBeats-VisibleBeats); FStartBeat := EnsureRange(FStartBeat,0.0,MaxStart);
  FUpdating := True;
  try
    FHorizontal.Min := 0; FHorizontal.Max := Max(0,Ceil(MaxStart*1000));
    FHorizontal.Position := EnsureRange(Round(FStartBeat*1000),0,FHorizontal.Max);
    FVertical.Position := 127-FTopPitch;
  finally FUpdating := False; end;
end;

function TMusicStudioPerformanceFrame.NoteRect(Index: Integer): TRect;
var Note: TMusicStudioPerformanceNote; LeftX,RightX,TopY: Integer;
begin
  Note := FData.NoteAt(Index);
  LeftX := KeyWidth+Round(EnsureRange((Note.StartBeat-FStartBeat)*DevicePixelsPerBeat,-1.0E9,1.0E9));
  RightX := KeyWidth+Round(EnsureRange((Note.StartBeat+Note.LengthBeats-FStartBeat)*DevicePixelsPerBeat,-1.0E9,1.0E9));
  TopY := RulerHeight+(FTopPitch-Note.Pitch)*PitchHeight;
  Result := Rect(LeftX,TopY+1,Max(LeftX+2,RightX)-1,TopY+PitchHeight-1);
end;

procedure TMusicStudioPerformanceFrame.RebuildRoll;
var C: TCanvas; X,Y,Pitch,I,RH,KH,PH,Index,Last: Integer; Step,Beat,EndBeat: Double;
  NoteR, Clip: TRect; Note: TMusicStudioPerformanceNote; IsQuarter: Boolean;
begin
  if (FRoll = nil) or (FBitmap = nil) then Exit;
  FZoomLabel.Caption := Format('四分音符=1拍  ・  ズーム %.0f px/拍  ・  スナップ %.5g 拍  ・  確認用 %.2f BPM',
    [FPixelsPerBeat,SnapStep,FPreviewTempoBPM]);
  FBitmap.PixelFormat := pf24bit; FBitmap.SetSize(Max(1,FRoll.Width),Max(1,FRoll.Height));
  C := FBitmap.Canvas; C.Font.Assign(Font); C.Brush.Color := $00202020; C.FillRect(Rect(0,0,FBitmap.Width,FBitmap.Height));
  C.Font.Color := $00BEBEBE; KH := KeyWidth; RH := RulerHeight; PH := PitchHeight;
  for Y := 0 to (FRoll.Height-RH) div PH do begin
    Pitch := FTopPitch-Y; if (Pitch < 0) or (Pitch > 127) then Continue;
    if IsBlackKey(Pitch) then C.Brush.Color := $00262626 else C.Brush.Color := $002D2D2D;
    C.FillRect(Rect(KH,RH+Y*PH,FRoll.Width,RH+(Y+1)*PH));
    if IsBlackKey(Pitch) then C.Brush.Color := $003B3B3B else C.Brush.Color := $006A6A6A;
    C.FillRect(Rect(0,RH+Y*PH,KH-1,RH+(Y+1)*PH-1));
    if Pitch mod 12 = 0 then begin C.Brush.Style := bsClear;
      C.TextOut(MulDiv(6,CurrentPPI,96),RH+Y*PH,'C'+IntToStr(Pitch div 12-1)); C.Brush.Style := bsSolid; end;
  end;
  C.Brush.Color := $00383838; C.FillRect(Rect(0,0,FRoll.Width,RH));
  Step := SnapStep; EndBeat := FStartBeat+Max(0,FRoll.Width-KH)/DevicePixelsPerBeat;
  Index := Floor(FStartBeat/Step); Last := Ceil(EndBeat/Step);
  for I := Index to Last do begin
    Beat := I*Step; X := KH+Round((Beat-FStartBeat)*DevicePixelsPerBeat);
    if (X < KH) or (X >= FRoll.Width) then Continue;
    IsQuarter := Abs(Beat-Round(Beat)) < 1.0E-9;
    if IsQuarter then C.Pen.Color := $00414141 else C.Pen.Color := $00353535;
    C.MoveTo(X,RH); C.LineTo(X,FRoll.Height);
    if IsQuarter and (DevicePixelsPerBeat >= 32) then begin
      C.Brush.Style := bsClear; C.TextOut(X+3,3,FloatToStr(Beat,TFormatSettings.Invariant)); C.Brush.Style := bsSolid;
    end;
  end;
  Clip := Rect(KH,RH,FRoll.Width,FRoll.Height);
  for I := 0 to FData.NoteCount-1 do begin
    Note := FData.NoteAt(I);
    if (Note.StartBeat+Note.LengthBeats < FStartBeat) or (Note.StartBeat > EndBeat) then Continue;
    if not IntersectRect(NoteR,NoteRect(I),Clip) then Continue;
    C.Brush.Color := FNoteColor; C.Pen.Color := $005A8E65;
    if I = FSelected then C.Pen.Color := clWhite;
    C.Rectangle(NoteR);
  end;
  Inc(FRenderCount); FRoll.Invalidate;
end;

procedure TMusicStudioPerformanceFrame.RollPaint(Sender: TObject);
begin FRoll.Canvas.Draw(0,0,FBitmap); end;

procedure TMusicStudioPerformanceFrame.Changed;
begin RefreshScrollbars; RebuildRoll; if Assigned(FOnChange) then FOnChange(Self); end;

procedure TMusicStudioPerformanceFrame.LengthChanged(Sender: TObject);
var Value: Double;
begin
  if FUpdating then Exit;
  try
    if not TryStrToFloat(Trim(FLengthEdit.Text),Value,TFormatSettings.Invariant) and
      not TryStrToFloat(Trim(FLengthEdit.Text),Value) then
      raise EArgumentException.Create('パターンの長さは拍数で入力してください。');
    FData.LengthBeats := Value; FInputError := ''; FStateLabel.Font.Color := $00E3E3E3;
    FStateLabel.Caption := '拍を保持して編集します。音声は起動しません。'; Changed;
  except on E: Exception do begin
    FInputError := E.Message; FStateLabel.Caption := E.Message; FStateLabel.Font.Color := $0087A6FF;
  end; end;
end;

procedure TMusicStudioPerformanceFrame.LoadPerformance(const ConfigJSON: string);
begin
  FData.LoadJSON(ConfigJSON); FSelected := -1; FDragging := False; FStartBeat := 0;
  if FData.HighestPitch >= 0 then FTopPitch := Min(127,Max(12,FData.HighestPitch+2)) else FTopPitch := 72;
  FInputError := '';
  if FStateLabel <> nil then FStateLabel.Font.Color := $00E3E3E3;
  if FLengthEdit <> nil then begin
    FUpdating := True; try FLengthEdit.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant);
    finally FUpdating := False; end;
  end;
  RefreshScrollbars; RebuildRoll;
end;

procedure TMusicStudioPerformanceFrame.LoadPerformance(ConfigJSON: TJSONObject);
begin if ConfigJSON = nil then LoadPerformance('') else LoadPerformance(ConfigJSON.ToJSON); end;

function TMusicStudioPerformanceFrame.ConfigJSON: string;
begin
  if FInputError <> '' then raise EArgumentException.Create(FInputError);
  Result := FData.ConfigJSON;
end;

function TMusicStudioPerformanceFrame.AddNote(StartBeat, LengthBeats: Double; Pitch, Velocity: Integer): Integer;
var Note: TMusicStudioPerformanceNote;
begin
  Note.StartBeat := StartBeat; Note.LengthBeats := LengthBeats; Note.Pitch := Pitch; Note.Velocity := Velocity;
  Result := FData.AddNote(Note); FSelected := Result; Changed;
end;

procedure TMusicStudioPerformanceFrame.SelectNote(Index: Integer);
begin
  if (Index < -1) or (Index >= FData.NoteCount) then raise EArgumentOutOfRangeException.Create('音符番号');
  FSelected := Index; RebuildRoll;
end;

procedure TMusicStudioPerformanceFrame.MoveSelectedNote(StartBeat: Double; Pitch: Integer);
var Note: TMusicStudioPerformanceNote;
begin
  if FSelected < 0 then Exit;
  Note := FData.NoteAt(FSelected); Note.StartBeat := StartBeat; Note.Pitch := Pitch;
  FData.SetNote(FSelected,Note); Changed;
end;

procedure TMusicStudioPerformanceFrame.DeleteSelectedNote;
begin
  if FSelected < 0 then Exit;
  FData.DeleteNote(FSelected); FSelected := -1; FDragging := False; Changed;
end;

procedure TMusicStudioPerformanceFrame.DeleteClick(Sender: TObject);
begin DeleteSelectedNote; end;

function TMusicStudioPerformanceFrame.HitNote(X,Y: Integer): Integer;
var I: Integer;
begin
  Result := -1;
  if (X < KeyWidth) or (Y < RulerHeight) then Exit;
  for I := FData.NoteCount-1 downto 0 do if PtInRect(NoteRect(I),Point(X,Y)) then Exit(I);
end;

function TMusicStudioPerformanceFrame.NewDuration: Double;
const Durations: array[1..7] of Double = (4,2,1,0.5,0.25,0.125,0.0625);
begin
  if FDurationCombo.ItemIndex in [1..7] then Result := Durations[FDurationCombo.ItemIndex] else Result := SnapStep;
end;

procedure TMusicStudioPerformanceFrame.RollMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X,Y: Integer);
var Index,Pitch,Velocity: Integer; Beat,Duration: Double;
begin
  if CanFocus then SetFocus;
  Index := HitNote(X,Y);
  if Button = mbRight then begin FSelected := Index; DeleteSelectedNote; Exit; end;
  if Button <> mbLeft then Exit;
  try
    if Index < 0 then begin
      if (X < KeyWidth) or (Y < RulerHeight) then begin FSelected := -1; RebuildRoll; Exit; end;
      Pitch := PitchAt(Y); if (Pitch < 0) or (Pitch > 127) then Exit;
      Beat := MusicStudioSnapBeat(BeatAt(X),SnapStep); Beat := Max(0.0,Beat);
      if Beat >= FData.LengthBeats then Exit;
      Duration := Min(NewDuration,FData.LengthBeats-Beat);
      if not TryStrToInt(Trim(FVelocityEdit.Text),Velocity) or (Velocity < 1) or (Velocity > 127) then
        raise EArgumentException.Create('強さは1～127で入力してください。');
      Index := AddNote(Beat,Duration,Pitch,Velocity);
    end;
    FSelected := Index; FDragPoint := Point(X,Y); FDragNote := FData.NoteAt(Index);
    FDragging := True; RebuildRoll;
  except on E: Exception do FStateLabel.Caption := E.Message; end;
end;

procedure TMusicStudioPerformanceFrame.RollMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
var Beat: Double; Pitch: Integer;
begin
  if not FDragging or not (ssLeft in Shift) then Exit;
  Beat := MusicStudioSnapBeat(FDragNote.StartBeat+(X-FDragPoint.X)/DevicePixelsPerBeat,SnapStep);
  Beat := EnsureRange(Beat,0.0,FData.LengthBeats-FDragNote.LengthBeats);
  Pitch := EnsureRange(FDragNote.Pitch-Round((Y-FDragPoint.Y)/PitchHeight),0,127);
  MoveSelectedNote(Beat,Pitch);
end;

procedure TMusicStudioPerformanceFrame.RollMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X,Y: Integer);
begin FDragging := False; end;

procedure TMusicStudioPerformanceFrame.SetPixelsPerBeat(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) then raise EArgumentException.Create('時間軸ズームが不正です。');
  FPixelsPerBeat := EnsureRange(Value,16.0,1024.0); RefreshScrollbars; RebuildRoll;
end;

procedure TMusicStudioPerformanceFrame.SetViewStartBeat(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) then raise EArgumentException.Create('表示開始拍が不正です。');
  FStartBeat := Value; RefreshScrollbars; RebuildRoll;
end;

procedure TMusicStudioPerformanceFrame.SetPreviewTempoBPM(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < 1) or (Value > 999.99) then
    raise EArgumentException.Create('確認用BPMは1～999.99で指定してください。');
  FPreviewTempoBPM := Value; RebuildRoll;
end;

procedure TMusicStudioPerformanceFrame.SetNoteColor(Value: TColor);
begin FNoteColor := Value; RebuildRoll; end;

procedure TMusicStudioPerformanceFrame.HorizontalChanged(Sender: TObject);
begin if FUpdating then Exit; FStartBeat := FHorizontal.Position/1000.0; RebuildRoll; end;
procedure TMusicStudioPerformanceFrame.VerticalChanged(Sender: TObject);
begin if FUpdating then Exit; FTopPitch := 127-FVertical.Position; RebuildRoll; end;

function TMusicStudioPerformanceFrame.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var Local: TPoint; Anchor: Double; Factor: Double;
begin
  Result := True;
  if (WheelDelta = 0) or (FRoll = nil) then Exit;
  if ssCtrl in Shift then begin
    Local := FRoll.ScreenToClient(MousePos); Anchor := BeatAt(Max(KeyWidth,Local.X));
    if WheelDelta > 0 then Factor := 1.25 else Factor := 0.8;
    FPixelsPerBeat := EnsureRange(FPixelsPerBeat*Factor,16.0,1024.0);
    FStartBeat := Anchor-Max(0,Local.X-KeyWidth)/DevicePixelsPerBeat;
    RefreshScrollbars; RebuildRoll;
  end else if ssShift in Shift then begin
    if WheelDelta > 0 then ViewStartBeat := FStartBeat-SnapStep*4
    else ViewStartBeat := FStartBeat+SnapStep*4;
  end else begin
    if WheelDelta > 0 then FTopPitch := Min(127,FTopPitch+3) else FTopPitch := Max(0,FTopPitch-3);
    RefreshScrollbars; RebuildRoll;
  end;
end;

procedure TMusicStudioPerformanceFrame.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_DELETE then begin DeleteSelectedNote; Key := 0; Exit; end;
  inherited;
end;

end.
