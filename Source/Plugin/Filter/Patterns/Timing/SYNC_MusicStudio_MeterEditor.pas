unit SYNC_MusicStudio_MeterEditor;

// 途中拍子の小節表を編集する。TempoMapは借用し、ファイル保存や作品履歴は担当しない。
// 数値は選択行へ即反映するが、モデルで候補検証に失敗した入力は確定させず画面に保持する。
interface
uses System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids,
  SYNC_MusicStudio_BeatData;
type
  TMusicStudioMeterEditor = class(TPanel)
  private
    FMap: TMusicStudioTempoMap;
    FRows: TStringGrid;
    FMeasure: TEdit;
    FNumerator, FDenominator: TComboBox;
    FDelete: TButton;
    FState: TLabel;
    FSelected: Integer;
    FUpdating: Boolean;
    FError: string;
    FOnChange: TNotifyEvent;
    procedure BuildUI;
    procedure RefreshRows;
    procedure ShowSelected;
    procedure NotifyChange;
    procedure InputsChanged(Sender: TObject);
    procedure RowSelected(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    procedure DrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    function GetCanApply: Boolean;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Mapは所有しない。nilで切離し、再Bind時は入力エラーと選択を初期化する。
    procedure Bind(Map: TMusicStudioTempoMap);
    // 外部で先頭拍子を変えた後に表示を同期する。不正な編集中テキストは保持する。
    procedure RefreshMap;
    // Mapへ小節単位で追加/編集/削除する。失敗は例外、成功時だけOnChangeを通知する。
    function AddChange(Measure, Numerator, Denominator: Integer): Integer;
    procedure EditChange(Index, Measure, Numerator, Denominator: Integer);
    procedure DeleteChange(Index: Integer);
    // 行を選び直すと未確定の不正入力を取り消す。保存済みの作品へは書き込まない。
    procedure SelectChange(Index: Integer);
    property CanApply: Boolean read GetCanApply;
    property ErrorText: string read FError;
    property SelectedChange: Integer read FSelected;
    property MeasureInput: TEdit read FMeasure;
    property NumeratorCombo: TComboBox read FNumerator;
    property DenominatorCombo: TComboBox read FDenominator;
    property Grid: TStringGrid read FRows;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation
uses System.SysUtils, System.Math, Winapi.Windows, Vcl.Graphics,
  SYNC_MusicStudio_MeterMap, SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme;
const DENOMINATORS: array[0..6] of Integer = (1,2,4,8,16,32,64);
constructor TMusicStudioMeterEditor.Create(AOwner: TComponent);
begin
  inherited;
  BevelOuter := bvNone; FSelected := -1;
  ApplySyncMusicStudioDarkPanel(Self);
end;
procedure TMusicStudioMeterEditor.SetParent(AParent: TWinControl);
begin
  inherited;
  if (AParent<>nil) and (FRows=nil) then begin BuildUI; RefreshMap; end;
end;
procedure TMusicStudioMeterEditor.BuildUI;
var Header, Footer: TPanel; L: TLabel; B: TButton; I: Integer;
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop;
  Header.Height := 58; Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  L := TLabel.Create(Self); L.Parent := Header; L.Align := alClient; L.AutoSize := False; L.WordWrap := True;
  L.Caption := '拍子は指定した小節の先頭から切り替わります。先頭拍子は「テンポ」タブで設定します。'+sLineBreak+
    '選択行の数値を編集できます。テンポ点は小節位置を保持して再計算します。';
  Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom;
  Footer.Height := 112; Footer.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Footer);
  L := TLabel.Create(Self); L.Parent := Footer; L.SetBounds(12,14,60,24); L.Caption := '開始小節';
  FMeasure := TEdit.Create(Self); FMeasure.Parent := Footer; FMeasure.SetBounds(78,10,86,28);
  FMeasure.MaxLength := 8; ApplySyncMusicStudioDarkEdit(FMeasure); FMeasure.OnChange := InputsChanged;
  FNumerator := TComboBox.Create(Self); FNumerator.Parent := Footer;
  FNumerator.SetBounds(180,10,64,28); FNumerator.Style := csDropDownList;
  for I := 1 to 32 do FNumerator.Items.Add(IntToStr(I));
  FNumerator.Color := $002E2E2E; FNumerator.Font.Color := $00E3E3E3; FNumerator.OnChange := InputsChanged;
  L := TLabel.Create(Self); L.Parent := Footer; L.SetBounds(252,14,16,24); L.Caption := '/';
  FDenominator := TComboBox.Create(Self); FDenominator.Parent := Footer;
  FDenominator.SetBounds(274,10,64,28); FDenominator.Style := csDropDownList;
  for I := Low(DENOMINATORS) to High(DENOMINATORS) do FDenominator.Items.Add(IntToStr(DENOMINATORS[I]));
  FDenominator.Color := $002E2E2E; FDenominator.Font.Color := $00E3E3E3; FDenominator.OnChange := InputsChanged;
  B := TMusicStudioButton.Create(Self); B.Parent := Footer; B.SetBounds(354,9,112,30);
  B.Caption := '拍子変更を追加'; B.OnClick := AddClick; ApplySyncMusicStudioDarkButton(B);
  FDelete := TMusicStudioButton.Create(Self); FDelete.Parent := Footer; FDelete.SetBounds(478,9,100,30);
  FDelete.Caption := '選択行を削除'; FDelete.OnClick := DeleteClick; ApplySyncMusicStudioDarkButton(FDelete);
  FState := TLabel.Create(Self); FState.Parent := Footer; FState.SetBounds(12,48,600,56);
  FState.Anchors := [akLeft,akTop,akRight]; FState.AutoSize := False; FState.WordWrap := True;
  FRows := TStringGrid.Create(Self); FRows.Parent := Self; FRows.Align := alClient;
  FRows.ColCount := 3; FRows.RowCount := 2; FRows.FixedCols := 0; FRows.FixedRows := 1;
  FRows.Options := [goFixedVertLine,goFixedHorzLine,goVertLine,goHorzLine,goRowSelect,goThumbTracking];
  FRows.DefaultDrawing := False; FRows.Color := $00272727; FRows.FixedColor := $00373737;
  FRows.OnSelectCell := RowSelected; FRows.OnDrawCell := DrawCell;
  Resize;
end;
procedure TMusicStudioMeterEditor.Resize;
var W: Integer;
begin
  inherited;
  if FRows=nil then Exit;
  FRows.DefaultRowHeight := MulDiv(28,CurrentPPI,96);
  W := Max(60,FRows.ClientWidth-MulDiv(22,CurrentPPI,96));
  FRows.ColWidths[0] := W div 3; FRows.ColWidths[1] := W div 3; FRows.ColWidths[2] := W-2*(W div 3);
end;
procedure TMusicStudioMeterEditor.DrawCell(Sender: TObject; ACol, ARow: Integer; Rect: TRect; State: TGridDrawState);
var C: TCanvas;
begin
  C := FRows.Canvas; C.Font.Assign(Font); C.Font.Color := $00E3E3E3;
  if gdFixed in State then C.Brush.Color := $00373737
  else if gdSelected in State then C.Brush.Color := $004F5B45 else C.Brush.Color := $00272727;
  C.FillRect(Rect); Inc(Rect.Left,10);
  DrawText(C.Handle,PChar(FRows.Cells[ACol,ARow]),-1,Rect,DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
end;
procedure TMusicStudioMeterEditor.Bind(Map: TMusicStudioTempoMap);
begin
  FMap := Map; FError := ''; FSelected := -1;
  if (FMap<>nil) and (FMap.MeterChangeCount>0) then FSelected := 0;
  RefreshMap;
end;
procedure TMusicStudioMeterEditor.RefreshRows;
var I, Count: Integer; P: TMusicStudioMeterPoint;
begin
  Count := 0; if FMap<>nil then Count := FMap.MeterChangeCount;
  FRows.RowCount := Max(2,Count+1);
  FRows.Cells[0,0] := '開始小節'; FRows.Cells[1,0] := '拍子'; FRows.Cells[2,0] := '開始拍（計算値）';
  if Count=0 then begin
    FRows.Cells[0,1] := '変更なし'; FRows.Cells[1,1] := ''; FRows.Cells[2,1] := '';
  end;
  for I := 0 to Count-1 do begin
    P := FMap.MeterChange(I); FRows.Cells[0,I+1] := IntToStr(P.Measure)+'小節';
    FRows.Cells[1,I+1] := Format('%d/%d',[P.Numerator,P.Denominator]);
    FRows.Cells[2,I+1] := FloatToStr(P.Beat,TFormatSettings.Invariant);
  end;
  if FSelected>=0 then FRows.Row := FSelected+1;
  FRows.Invalidate;
end;
procedure TMusicStudioMeterEditor.ShowSelected;
var P: TMusicStudioMeterPoint; I: Integer;
begin
  FMeasure.Enabled := FSelected>=0; FNumerator.Enabled := FSelected>=0;
  FDenominator.Enabled := FSelected>=0; FDelete.Enabled := FSelected>=0;
  if FSelected<0 then begin FMeasure.Text := ''; FNumerator.ItemIndex := -1; FDenominator.ItemIndex := -1; Exit; end;
  P := FMap.MeterChange(FSelected); FMeasure.Text := IntToStr(P.Measure); FNumerator.ItemIndex := P.Numerator-1;
  for I := Low(DENOMINATORS) to High(DENOMINATORS) do
    if P.Denominator=DENOMINATORS[I] then FDenominator.ItemIndex := I;
end;
procedure TMusicStudioMeterEditor.RefreshMap;
begin
  if FRows=nil then Exit;
  FUpdating := True;
  try
    if (FMap=nil) or (FMap.MeterChangeCount=0) then FSelected := -1
    else FSelected := EnsureRange(FSelected,0,FMap.MeterChangeCount-1);
    RefreshRows; if FError='' then ShowSelected;
    if FError<>'' then begin FState.Caption := FError; FState.Font.Color := $0087A6FF; end
    else begin FState.Caption := '変更なしは先頭拍子を全曲で使用します。行の選び直しで未確定入力を取り消せます。'; FState.Font.Color := $00E3E3E3; end;
  finally FUpdating := False; end;
end;
function TMusicStudioMeterEditor.GetCanApply: Boolean;
begin Result := FError=''; end;
procedure TMusicStudioMeterEditor.NotifyChange;
begin RefreshMap; if Assigned(FOnChange) then FOnChange(Self); end;
function TMusicStudioMeterEditor.AddChange(Measure, Numerator, Denominator: Integer): Integer;
begin
  if FMap=nil then raise EInvalidOperation.Create('拍子表がありません。');
  Result := FMap.AddMeterChange(Measure,Numerator,Denominator); FSelected := Result; FError := ''; NotifyChange;
end;
procedure TMusicStudioMeterEditor.EditChange(Index, Measure, Numerator, Denominator: Integer);
begin
  if FMap=nil then raise EInvalidOperation.Create('拍子表がありません。');
  FMap.SetMeterChange(Index,Measure,Numerator,Denominator); FSelected := 0;
  while FMap.MeterChange(FSelected).Measure<>Measure do Inc(FSelected);
  FError := ''; NotifyChange;
end;
procedure TMusicStudioMeterEditor.DeleteChange(Index: Integer);
begin
  if FMap=nil then raise EInvalidOperation.Create('拍子表がありません。');
  FMap.DeleteMeterChange(Index); FSelected := Min(Index,FMap.MeterChangeCount-1); FError := ''; NotifyChange;
end;
procedure TMusicStudioMeterEditor.SelectChange(Index: Integer);
begin
  if FMap=nil then raise EInvalidOperation.Create('拍子表がありません。');
  FMap.MeterChange(Index); FSelected := Index; FError := ''; NotifyChange;
end;
procedure TMusicStudioMeterEditor.InputsChanged(Sender: TObject);
var Measure: Integer;
begin
  if FUpdating or (FSelected<0) then Exit;
  try
    if not TryStrToInt(Trim(FMeasure.Text),Measure) then raise EArgumentException.Create('開始小節は整数で入力してください。');
    if (FNumerator.ItemIndex<0) or (FDenominator.ItemIndex<0) then raise EArgumentException.Create('拍子を選択してください。');
    EditChange(FSelected,Measure,FNumerator.ItemIndex+1,DENOMINATORS[FDenominator.ItemIndex]);
  except on E: Exception do begin FError := E.Message; NotifyChange; end; end;
end;
procedure TMusicStudioMeterEditor.RowSelected(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
begin
  CanSelect := (FMap<>nil) and (ARow>0) and (ARow<=FMap.MeterChangeCount);
  if FUpdating or not CanSelect then Exit;
  SelectChange(ARow-1);
end;
procedure TMusicStudioMeterEditor.AddClick(Sender: TObject);
var Measure: Integer; P: TMusicStudioMeterPoint;
begin
  if FMap=nil then Exit;
  try
    if not CanApply then raise EArgumentException.Create(FError);
    Measure := 2;
    if FMap.MeterChangeCount>0 then Measure := FMap.MeterChange(FMap.MeterChangeCount-1).Measure+1;
    P.Measure := Measure; P.Denominator := FMap.DenominatorAtBeat(FMap.MeasureStart(Measure));
    P.Numerator := Round(FMap.MeasureLengthAtBeat(FMap.MeasureStart(Measure))*P.Denominator/4);
    AddChange(Measure,P.Numerator,P.Denominator);
  except on E: Exception do begin FError := E.Message; NotifyChange; end; end;
end;
procedure TMusicStudioMeterEditor.DeleteClick(Sender: TObject);
begin
  try DeleteChange(FSelected);
  except on E: Exception do begin FError := E.Message; NotifyChange; end; end;
end;
end.
