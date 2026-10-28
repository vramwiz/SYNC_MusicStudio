unit SYNC_MusicStudio_TimingFrame;

// 手動テンポ表と先頭/途中拍子を編集する属性独立フレーム。
// 拍位置と未知JSONフィールドを保持する。確定/取消は外側のダイアログが担当する。
// 音声、時計、ファイル入出力を起動しない。
interface

uses System.Classes, System.JSON, System.Types, Winapi.Windows, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids, Vcl.Graphics, Vcl.ComCtrls, SYNC_MusicStudio_BeatData,
  SYNC_MusicStudio_MeterEditor;

type
  TMusicStudioTimingFrame = class(TFrame)
  private
    FMap: TMusicStudioTempoMap;
    FMeterEditor: TMusicStudioMeterEditor;
    FPages: TPageControl;
    FRows: TStringGrid;
    FBeatEdit, FBPMEdit: TEdit;
    FNumerator, FDenominator: TComboBox;
    FDeleteButton: TButton;
    FStateLabel: TLabel;
    FSelected: Integer;
    FUpdating: Boolean;
    FError: string;
    FOnChange: TNotifyEvent;
    procedure MeterEditorChanged(Sender: TObject);
    procedure BuildUI;
    procedure ShowTiming;
    procedure ShowSelected;
    procedure RefreshRows;
    procedure SetState(const ErrorText: string; Notify: Boolean);
    procedure Changed;
    procedure ApplyPoint(Index: Integer; Beat, BPM: Double; UpdateEditors: Boolean);
    function FindPoint(Beat: Double): Integer;
    function GetCanApply: Boolean;
    function GetStateText: string;
    procedure InputsChanged(Sender: TObject);
    procedure MeterChanged(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure RowSelected(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    procedure DrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadTiming(const TimingJSON: string); overload;
    procedure LoadTiming(TimingJSON: TJSONObject); overload;
    function ConfigJSON: string;
    // 追加は同じ拍を上書きしない。編集は選択行の未知フィールドを引き継ぐ。
    function AddTempoPoint(Beat, BPM: Double): Integer;
    procedure EditTempoPoint(Index: Integer; Beat, BPM: Double);
    procedure DeleteTempoPoint(Index: Integer);
    procedure SelectTempoPoint(Index: Integer);
    procedure SetMeter(Numerator, Denominator: Integer);
    // 拍子編集は同じmapを借用し、外側のOK/取消と作品Undoで確定する。呼出元は解放しない。
    property MeterEditor: TMusicStudioMeterEditor read FMeterEditor;
    property Pages: TPageControl read FPages;
    property TempoMap: TMusicStudioTempoMap read FMap;
    property SelectedTempoPoint: Integer read FSelected;
    property CanApply: Boolean read GetCanApply;
    property StateText: string read GetStateText;
    property BeatInput: TEdit read FBeatEdit;
    property BPMInput: TEdit read FBPMEdit;
    property NumeratorCombo: TComboBox read FNumerator;
    property DenominatorCombo: TComboBox read FDenominator;
    property TempoGrid: TStringGrid read FRows;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses System.SysUtils, System.Math,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

{$R *.dfm}

const DENOMINATORS: array[0..6] of Integer = (1,2,4,8,16,32,64);

function DisplayNumber(Value: Double): string;
begin Result := FloatToStr(Value,TFormatSettings.Invariant); end;

function ReadInput(Edit: TEdit; const Name: string): Double;
begin
  if not TryStrToFloat(Trim(Edit.Text),Result,TFormatSettings.Invariant) and
    not TryStrToFloat(Trim(Edit.Text),Result) then
    raise EArgumentException.Create(Name+' は数値で入力してください。');
end;

constructor TMusicStudioTimingFrame.Create(AOwner: TComponent);
begin
  inherited;
  FMap := TMusicStudioTempoMap.Create; FSelected := 0;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
  // Combo/Gridはウィンドウが必要なので、親設定後に作成する。
end;

destructor TMusicStudioTimingFrame.Destroy;
begin
  if FMeterEditor<>nil then FMeterEditor.OnChange := nil;
  FreeAndNil(FMeterEditor); FreeAndNil(FMap); inherited;
end;

procedure TMusicStudioTimingFrame.SetParent(AParent: TWinControl);
var Component: TComponent;
begin
  inherited;
  if (AParent = nil) or (FMap = nil) then Exit;
  if FRows = nil then begin
    FUpdating := True;
    try BuildUI; finally FUpdating := False; end;
    ShowTiming; Resize;
  end;
  for Component in Self do
    if Component is TButton then ApplySyncMusicStudioDarkButton(TButton(Component));
end;

procedure TMusicStudioTimingFrame.BuildUI;
var Header, Info, Footer: TPanel; LabelControl: TLabel; Button: TButton; I: Integer; TempoTab, MeterTab: TTabSheet;
begin
  FPages := TPageControl.Create(Self); FPages.Parent := Self; FPages.Align := alClient;
  TempoTab := TTabSheet.Create(Self); TempoTab.PageControl := FPages; TempoTab.Caption := 'テンポ';
  MeterTab := TTabSheet.Create(Self); MeterTab.PageControl := FPages; MeterTab.Caption := '拍子変更';
  FPages.ActivePage := TempoTab;
  Header := TPanel.Create(Self); Header.Parent := TempoTab; Header.Align := alTop;
  Header.Height := 46; Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Header;
  LabelControl.SetBounds(12,14,94,22); LabelControl.Caption := '先頭の拍子';
  FNumerator := TComboBox.Create(Self); FNumerator.Parent := Header;
  FNumerator.SetBounds(108,9,68,28); FNumerator.Style := csDropDownList;
  FNumerator.Color := $002E2E2E; FNumerator.Font.Color := $00E3E3E3;
  for I := 1 to 32 do FNumerator.Items.Add(IntToStr(I));
  FNumerator.OnChange := MeterChanged;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Header;
  LabelControl.SetBounds(184,14,20,22); LabelControl.Caption := '/';
  FDenominator := TComboBox.Create(Self); FDenominator.Parent := Header;
  FDenominator.SetBounds(206,9,68,28); FDenominator.Style := csDropDownList;
  FDenominator.Color := $002E2E2E; FDenominator.Font.Color := $00E3E3E3;
  for I := Low(DENOMINATORS) to High(DENOMINATORS) do FDenominator.Items.Add(IntToStr(DENOMINATORS[I]));
  FDenominator.OnChange := MeterChanged;
  Info := TPanel.Create(Self); Info.Parent := TempoTab; Info.Align := alTop;
  Info.Height := 54; Info.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Info);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Info; LabelControl.Align := alClient;
  LabelControl.AutoSize := False; LabelControl.WordWrap := True;
  LabelControl.Caption := '四分音符＝1拍。テンポは指定拍から変更します。'+sLineBreak+
    '0拍は必須。小節位置を保持して秒を再計算します。途中の変更は「拍子変更」タブで編集します。';
  Footer := TPanel.Create(Self); Footer.Parent := TempoTab; Footer.Align := alBottom;
  Footer.Height := 100; Footer.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Footer);
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Footer;
  LabelControl.SetBounds(12,14,60,22); LabelControl.Caption := '開始拍';
  FBeatEdit := TEdit.Create(Self); FBeatEdit.Parent := Footer; FBeatEdit.SetBounds(72,10,100,28);
  FBeatEdit.MaxLength := 16; ApplySyncMusicStudioDarkEdit(FBeatEdit); FBeatEdit.OnChange := InputsChanged;
  LabelControl := TLabel.Create(Self); LabelControl.Parent := Footer;
  LabelControl.SetBounds(184,14,40,22); LabelControl.Caption := 'BPM';
  FBPMEdit := TEdit.Create(Self); FBPMEdit.Parent := Footer; FBPMEdit.SetBounds(228,10,88,28);
  FBPMEdit.MaxLength := 12; ApplySyncMusicStudioDarkEdit(FBPMEdit); FBPMEdit.OnChange := InputsChanged;
  Button := TMusicStudioButton.Create(Self); Button.Parent := Footer; Button.SetBounds(332,9,108,30);
  Button.Caption := 'テンポ点を追加'; Button.OnClick := AddClick; ApplySyncMusicStudioDarkButton(Button);
  FDeleteButton := TMusicStudioButton.Create(Self); FDeleteButton.Parent := Footer;
  FDeleteButton.SetBounds(450,9,96,30); FDeleteButton.Caption := '選択行を削除';
  FDeleteButton.OnClick := DeleteClick; ApplySyncMusicStudioDarkButton(FDeleteButton);
  FStateLabel := TLabel.Create(Self); FStateLabel.Parent := Footer;
  FStateLabel.SetBounds(12,46,Width-24,48); FStateLabel.Anchors := [akLeft,akTop,akRight];
  FStateLabel.AutoSize := False; FStateLabel.WordWrap := True;
  FRows := TStringGrid.Create(Self); FRows.Parent := TempoTab; FRows.Align := alClient;
  FRows.ColCount := 3; FRows.FixedCols := 0; FRows.FixedRows := 1; FRows.RowCount := 2;
  FRows.Options := [goFixedVertLine,goFixedHorzLine,goVertLine,goHorzLine,goRowSelect,goThumbTracking];
  FRows.DefaultDrawing := False; FRows.Color := $00272727; FRows.FixedColor := $00373737;
  FRows.Font.Assign(Font); FRows.Font.Color := $00E3E3E3;
  FRows.OnDrawCell := DrawCell; FRows.OnSelectCell := RowSelected;
  FMeterEditor := TMusicStudioMeterEditor.Create(Self); FMeterEditor.Parent := MeterTab;
  FMeterEditor.Align := alClient; FMeterEditor.Bind(FMap); FMeterEditor.OnChange := MeterEditorChanged;
end;

procedure TMusicStudioTimingFrame.Resize;
var Available: Integer;
begin
  inherited;
  if FRows = nil then Exit;
  FRows.DefaultRowHeight := Max(18,MulDiv(28,CurrentPPI,96));
  Available := Max(30,FRows.ClientWidth-MulDiv(22,CurrentPPI,96));
  FRows.ColWidths[0] := Available div 3;
  FRows.ColWidths[1] := Available div 3;
  FRows.ColWidths[2] := Available-2*(Available div 3);
end;

procedure TMusicStudioTimingFrame.DrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var Canvas: TCanvas; TextRect: TRect;
begin
  Canvas := FRows.Canvas; Canvas.Font.Assign(Font);
  if gdFixed in State then Canvas.Brush.Color := $00373737
  else if gdSelected in State then Canvas.Brush.Color := $004F5B45
  else if Odd(ARow) then Canvas.Brush.Color := $00272727 else Canvas.Brush.Color := $002C2C2C;
  Canvas.Font.Color := $00E3E3E3; Canvas.FillRect(Rect);
  TextRect := Rect; Inc(TextRect.Left,MulDiv(10,CurrentPPI,96));
  DrawText(Canvas.Handle,PChar(FRows.Cells[ACol,ARow]),-1,TextRect,DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
end;

procedure TMusicStudioTimingFrame.RefreshRows;
var I: Integer; Point: TMusicStudioTempoPoint; WasUpdating: Boolean;
begin
  if FRows = nil then Exit;
  WasUpdating := FUpdating; FUpdating := True;
  try
    FRows.RowCount := FMap.PointCount+1;
    FRows.Cells[0,0] := '開始拍'; FRows.Cells[1,0] := 'BPM'; FRows.Cells[2,0] := '開始秒（計算値）';
    for I := 0 to FMap.PointCount-1 do begin
      Point := FMap.TempoPoint(I);
      FRows.Cells[0,I+1] := DisplayNumber(Point.Beat);
      FRows.Cells[1,I+1] := DisplayNumber(Point.BPM);
      FRows.Cells[2,I+1] := FormatFloat('0.000',Point.StartSeconds,TFormatSettings.Invariant);
    end;
    FRows.Row := FSelected+1; FDeleteButton.Enabled := FSelected > 0;
  finally FUpdating := WasUpdating; end;
  FRows.Invalidate;
end;

procedure TMusicStudioTimingFrame.ShowSelected;
var Point: TMusicStudioTempoPoint; WasUpdating: Boolean;
begin
  if FBeatEdit = nil then Exit;
  Point := FMap.TempoPoint(FSelected); WasUpdating := FUpdating; FUpdating := True;
  try
    FBeatEdit.ReadOnly := FSelected = 0;
    FBeatEdit.Text := DisplayNumber(Point.Beat); FBPMEdit.Text := DisplayNumber(Point.BPM);
    FDeleteButton.Enabled := FSelected > 0;
  finally FUpdating := WasUpdating; end;
end;

procedure TMusicStudioTimingFrame.ShowTiming;
var I: Integer;
begin
  if FRows = nil then Exit;
  FUpdating := True;
  try
    FNumerator.ItemIndex := FMap.Numerator-1;
    for I := Low(DENOMINATORS) to High(DENOMINATORS) do
      if FMap.Denominator = DENOMINATORS[I] then FDenominator.ItemIndex := I;
    RefreshRows; ShowSelected; FMeterEditor.Bind(FMap);
  finally FUpdating := False; end;
  SetState(FError,False);
end;

procedure TMusicStudioTimingFrame.SetState(const ErrorText: string; Notify: Boolean);
begin
  FError := ErrorText;
  if FStateLabel <> nil then begin
    FStateLabel.Caption := StateText;
    if CanApply then FStateLabel.Font.Color := $00E3E3E3 else FStateLabel.Font.Color := $0087A6FF;
  end;
  if Notify and Assigned(FOnChange) then FOnChange(Self);
end;

function TMusicStudioTimingFrame.GetCanApply: Boolean;
begin Result := (FError = '') and ((FMeterEditor=nil) or FMeterEditor.CanApply); end;

function TMusicStudioTimingFrame.GetStateText: string;
begin
  if FError <> '' then Exit(FError);
  if (FMeterEditor<>nil) and not FMeterEditor.CanApply then Exit(FMeterEditor.ErrorText);
  Result := Format('%d 個のテンポ点 ・ %d/%d 拍子 ・ 1小節 %.5g 拍'+sLineBreak+
    '数値の変更は選択行へ反映されます。拍の位置を保持し、秒位置を再計算します。',
    [FMap.PointCount,FMap.Numerator,FMap.Denominator,FMap.BeatsPerMeasure]);
end;

procedure TMusicStudioTimingFrame.MeterEditorChanged(Sender: TObject);
begin
  // 拍子変更でtempoの絶対拍が移る。未確定のtempo入力を上書きせず、表だけを同期する。
  RefreshRows; if FError='' then ShowSelected;
  SetState(FError,True);
end;

procedure TMusicStudioTimingFrame.Changed;
begin SetState('',True); end;

procedure TMusicStudioTimingFrame.LoadTiming(const TimingJSON: string);
begin
  try
    FMap.LoadJSON(TimingJSON); FSelected := 0; FError := ''; ShowTiming;
  except on E: Exception do begin SetState(E.Message,False); raise; end; end;
end;

procedure TMusicStudioTimingFrame.LoadTiming(TimingJSON: TJSONObject);
begin if TimingJSON = nil then LoadTiming('') else LoadTiming(TimingJSON.ToJSON); end;

function TMusicStudioTimingFrame.ConfigJSON: string;
begin
  if not CanApply then raise EArgumentException.Create(StateText);
  Result := FMap.TimingJSON;
end;

function TMusicStudioTimingFrame.FindPoint(Beat: Double): Integer;
var I: Integer;
begin
  for I := 0 to FMap.PointCount-1 do if FMap.TempoPoint(I).Beat = Beat then Exit(I);
  raise EArgumentException.Create('テンポ点が見つかりません。');
end;

function TMusicStudioTimingFrame.AddTempoPoint(Beat, BPM: Double): Integer;
var I: Integer;
begin
  for I := 0 to FMap.PointCount-1 do if FMap.TempoPoint(I).Beat = Beat then
    raise EArgumentException.Create('同じ拍のテンポ点があります。開始拍を変更してください。');
  FMap.SetBPMAt(Beat,BPM); FSelected := FindPoint(Beat); Result := FSelected;
  RefreshRows; ShowSelected; Changed;
end;

procedure TMusicStudioTimingFrame.ApplyPoint(Index: Integer; Beat, BPM: Double; UpdateEditors: Boolean);
begin
  FMap.SetTempoPoint(Index,Beat,BPM); FSelected := FindPoint(Beat);
  RefreshRows; if UpdateEditors then ShowSelected; Changed;
end;

procedure TMusicStudioTimingFrame.EditTempoPoint(Index: Integer; Beat, BPM: Double);
begin ApplyPoint(Index,Beat,BPM,True); end;

procedure TMusicStudioTimingFrame.DeleteTempoPoint(Index: Integer);
begin
  FMap.DeleteTempoPoint(Index); FSelected := Min(Index,FMap.PointCount-1);
  RefreshRows; ShowSelected; Changed;
end;

procedure TMusicStudioTimingFrame.SelectTempoPoint(Index: Integer);
begin
  FMap.TempoPoint(Index); FSelected := Index; RefreshRows; ShowSelected; Changed;
end;

procedure TMusicStudioTimingFrame.SetMeter(Numerator, Denominator: Integer);
begin FMap.SetMeter(Numerator,Denominator); FError := ''; ShowTiming; Changed; end;

procedure TMusicStudioTimingFrame.InputsChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  try ApplyPoint(FSelected,ReadInput(FBeatEdit,'開始拍'),ReadInput(FBPMEdit,'BPM'),False);
  except on E: Exception do SetState(E.Message,True); end;
end;

procedure TMusicStudioTimingFrame.MeterChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  try
    if (FNumerator.ItemIndex < 0) or (FDenominator.ItemIndex < 0) then
      raise EArgumentException.Create('拍子の分子と分母を選択してください。');
    FMap.SetMeter(FNumerator.ItemIndex+1,DENOMINATORS[FDenominator.ItemIndex]);
      // 小節アンカーから新しい拍位置を表示する。古い拍入力を再適用しない。
      // 不正入力は拍子選択だけで解除せず、そのテキストと理由を保持する。
      RefreshRows; if FError='' then ShowSelected; FMeterEditor.RefreshMap; SetState(FError,True);
  except on E: Exception do SetState(E.Message,True); end;
end;

procedure TMusicStudioTimingFrame.RowSelected(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
begin
  CanSelect := ARow > 0;
  if FUpdating or not CanSelect then Exit;
  FSelected := ARow-1; ShowSelected; Changed;
end;

procedure TMusicStudioTimingFrame.AddClick(Sender: TObject);
var Beat: Double;
begin
  try
    if not CanApply then raise EArgumentException.Create(FError);
    Beat := FMap.TempoPoint(FMap.PointCount-1).Beat+FMap.BeatsPerMeasure;
    AddTempoPoint(Beat,FMap.BPMAt(Beat));
  except on E: Exception do SetState(E.Message,True); end;
end;

procedure TMusicStudioTimingFrame.DeleteClick(Sender: TObject);
begin
  try DeleteTempoPoint(FSelected);
  except on E: Exception do SetState(E.Message,True); end;
end;

end.
