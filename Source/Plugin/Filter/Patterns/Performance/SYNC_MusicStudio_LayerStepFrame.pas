unit SYNC_MusicStudio_LayerStepFrame;

// 演奏設定のカーソル、設定点と無音ループ。共通の名前/色や作品への確定は親フォームが担当。
interface
uses System.Classes, System.Types, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  SYNC_MusicStudio_LayerStepData, SYNC_MusicStudio_PsdLayersFrame,
  SYNC_MusicStudio_PsdLayerFrameUI, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_EditHistory;
type
  TMusicStudioLayerStepFrame = class(TFrame)
  private
    FData: TMusicStudioLayerStepData;
    FLayers: TMusicStudioPsdLayersFrame;
    FGrid: TMusicStudioPsdPreviewSurface;
    FPlayButton,FStopButton: TButton;
    FHeader,FStepHeader: TPanel;
    FLengthLabel,FStepLengthLabel: TLabel;
    FDeleteButton: TButton;
    FClock: TTimer;
    FTiming: TMusicStudioTempoMap;
    FHistory: TMusicStudioEditHistory;
    FLengthEdit,FStepLengthEdit: TEdit;
    FStatus,FZoomLabel: TLabel;
    FSelected: Integer;
    FZoom,FStartBeat,FTempoBPM,FCursorBeat,FPanStart: Double;
    FPath,FBaseConfig,FInputError,FPreviewConfig: string;
    FUpdating,FPlaying,FPointerDown,FPanning: Boolean;
    FLastTick: UInt64;
    FDownPoint: TPoint;
    FObjectDown,FObjectResize,FDragStarted,FDragValid: Boolean;
    FOriginalStep: TMusicStudioLayerStep;
    FProposedStart,FProposedLength: Double;
    FDragError,FNotice: string;
    function LayoutPPI: Integer;
    function HeaderWidth: Integer;
    function BeatAtX(X: Integer): Double;
    function XAtBeat(Beat: Double): Integer;
    function BoundsRect(StartBeat,LengthBeats: Double): TRect;
    procedure LayoutChrome;
    function PixelsPerBeat: Double;
    procedure BuildUI;
    procedure UpdateStatus;
    procedure SyncCursor;
    procedure SetViewStart(Value: Double);
    procedure ReloadEditingState;
    procedure FinishPan(Cancel: Boolean);
    procedure ClockTick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure LengthChanged(Sender: TObject);
    procedure StepLengthChanged(Sender: TObject);
    procedure LayerChanged(Sender: TObject);

    procedure DeleteClick(Sender: TObject);
    procedure PaintGrid(Sender: TObject);
    procedure GridDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure GridMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure GridUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure GridCaptureLost(Sender: TObject);
    procedure GridWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure SetZoom(Value: Double);
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // PSDは選択トラックの読取snapshot。既存stepのasset IDを別PSDへ付け替えない。
    procedure LoadPerformance(const ConfigJSON,AssetID,Path,BaseConfig: string; TempoBPM: Double; const TimingJSON: string = '');
    function ConfigJSON: string;
    procedure SelectStep(Index: Integer);
    function AddStep(StartBeat: Double): Integer;
    procedure DeleteSelected;
    procedure SeekBeat(Beat: Double);
    procedure PlayPause;
    procedure Stop;
    procedure AdvancePlayback(Seconds: Double);
    procedure UndoEdit;
    procedure RedoEdit;
    function HandleEditorKey(var Key: Word; Shift: TShiftState): Boolean;
    function MarkerRect(Index: Integer): TRect;
    function ResizeHandleRect(Index: Integer): TRect;
    function StepRect(Index: Integer): TRect;
    function SnapStep: Double;
    property Data: TMusicStudioLayerStepData read FData;
    property LayerEditor: TMusicStudioPsdLayersFrame read FLayers;
    property StepGrid: TMusicStudioPsdPreviewSurface read FGrid;
    property SelectedStep: Integer read FSelected;
    property CursorBeat: Double read FCursorBeat;
    property ViewStartBeat: Double read FStartBeat;
    property TimelineHeaderWidth: Integer read HeaderWidth;
    property IsPlaying: Boolean read FPlaying;
    property PlaybackTimer: TTimer read FClock;
    property PlayButton: TButton read FPlayButton;
    property StopButton: TButton read FStopButton;
    property Zoom: Double read FZoom write SetZoom;
    property LengthEdit: TEdit read FLengthEdit;
    property StepLengthEdit: TEdit read FStepLengthEdit;
  end;
implementation
uses System.SysUtils, System.Math, System.JSON, System.UITypes, Winapi.Windows,
  Vcl.Graphics, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
{$R *.dfm}
constructor TMusicStudioLayerStepFrame.Create(AOwner: TComponent);
begin
  inherited; FData := TMusicStudioLayerStepData.Create; FTiming := TMusicStudioTempoMap.Create;
  FHistory := TMusicStudioEditHistory.Create; FSelected := -1; FZoom := 96; FTempoBPM := 120;
  FClock := TTimer.Create(Self); FClock.Enabled := False; FClock.Interval := 33; FClock.OnTimer := ClockTick;
  DoubleBuffered := True; ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;
destructor TMusicStudioLayerStepFrame.Destroy;
begin
  FClock.Enabled := False; FPlaying := False; FinishPan(False);
  if Assigned(FLayers) then FLayers.OnChange := nil;
  FHistory.Free; FTiming.Free; FData.Free; inherited;
end;
procedure TMusicStudioLayerStepFrame.SetParent(AParent: TWinControl);
begin inherited; if (AParent<>nil) and (FData<>nil) and (FGrid=nil) then BuildUI; end;
procedure TMusicStudioLayerStepFrame.BuildUI;
var Header,StepHeader,GridPanel: TPanel; L: TLabel; B: TButton;
  function LabelAt(Parent: TWinControl; X,W: Integer; const Text: string): TLabel;
  begin L := TLabel.Create(Self); L.Parent := Parent; L.AutoSize := False; L.SetBounds(X,12,W,22); L.Caption := Text; Result := L; end;
  function EditAt(Parent: TWinControl; X,W: Integer; Event: TNotifyEvent): TEdit;
  begin Result := TEdit.Create(Self); Result.Parent := Parent; Result.SetBounds(X,8,W,26); ApplySyncMusicStudioDarkEdit(Result); Result.OnChange := Event; end;
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Top := 0; Header.Height := 44;
  Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  FHeader := Header; FLengthLabel := LabelAt(Header,12,92,'パターン長 (拍)'); FLengthEdit := EditAt(Header,108,68,LengthChanged);
  FPlayButton := TMusicStudioButton.Create(Self); FPlayButton.Parent := Header; FPlayButton.SetBounds(194,8,104,28); FPlayButton.Caption := '▶ 再生'; FPlayButton.OnClick := PlayClick;
  FStopButton := TMusicStudioButton.Create(Self); FStopButton.Parent := Header; FStopButton.SetBounds(306,8,104,28); FStopButton.Caption := '■ 停止'; FStopButton.OnClick := StopClick;
  FZoomLabel := TLabel.Create(Self); FZoomLabel.Parent := Header; FZoomLabel.AutoSize := False; FZoomLabel.SetBounds(424,12,610,22); FZoomLabel.Anchors := [akLeft,akTop,akRight];
  GridPanel := TPanel.Create(Self); GridPanel.Parent := Self; GridPanel.Align := alTop; GridPanel.Top := 44; GridPanel.Height := 132;
  GridPanel.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(GridPanel);
  FGrid := TMusicStudioPsdPreviewSurface.Create(Self); FGrid.Parent := GridPanel; FGrid.Align := alClient;
  FGrid.OnPaint := PaintGrid; FGrid.OnMouseDown := GridDown; FGrid.OnMouseMove := GridMove; FGrid.OnMouseUp := GridUp;
  FGrid.OnCaptureLost := GridCaptureLost; FGrid.OnMouseWheel := GridWheel;
  FGrid.ShowHint := True; FGrid.Hint := 'クリックでカーソル移動、四角で設定点選択。ホイールで表示拡縮、ドラッグで横移動。右クリックで設定点削除。';
  StepHeader := TPanel.Create(Self); StepHeader.Parent := Self; StepHeader.Align := alTop; StepHeader.Top := 176; StepHeader.Height := 44;
  StepHeader.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(StepHeader);
  FStepHeader := StepHeader; FStepLengthLabel := LabelAt(StepHeader,12,112,'区間長 (拍)'); FStepLengthEdit := EditAt(StepHeader,128,80,StepLengthChanged); FStepLengthEdit.ReadOnly := True;
  B := TMusicStudioButton.Create(Self); B.Parent := StepHeader; B.SetBounds(222,8,100,28); B.Caption := '設定点削除'; B.OnClick := DeleteClick;
  FDeleteButton := B;
  FStatus := TLabel.Create(Self); FStatus.Parent := StepHeader; FStatus.AutoSize := False; FStatus.SetBounds(336,12,690,22); FStatus.Anchors := [akLeft,akTop,akRight]; FStatus.ShowHint := True;
  FLayers := TMusicStudioPsdLayersFrame.Create(Self); FLayers.Parent := Self; FLayers.Align := alClient; FLayers.OnChange := LayerChanged;
  FLayers.CompactLayout := True;
  LayoutChrome;
end;
function TMusicStudioLayerStepFrame.PixelsPerBeat: Double;
begin Result := FZoom*LayoutPPI/96; end;
function TMusicStudioLayerStepFrame.SnapStep: Double;
begin Result := MusicStudioSnapStep(FZoom); end;
procedure TMusicStudioLayerStepFrame.SetZoom(Value: Double);
var Anchor: Double;
begin
  if FGrid=nil then begin FZoom := EnsureRange(Value,24.0,1536.0); Exit; end;
  FinishPan(True); Anchor := FStartBeat+Max(1,FGrid.ClientWidth-HeaderWidth)/(2*PixelsPerBeat);
  FZoom := EnsureRange(Value,24.0,1536.0); SetViewStart(Anchor-Max(1,FGrid.ClientWidth-HeaderWidth)/(2*PixelsPerBeat)); UpdateStatus;
end;
procedure TMusicStudioLayerStepFrame.Resize;
begin inherited; if Assigned(FGrid) then begin LayoutChrome; FinishPan(True); SetViewStart(FStartBeat); UpdateStatus; end; end;
procedure TMusicStudioLayerStepFrame.UpdateStatus;
var Text: string; Legacy: Boolean;
begin
  if (FGrid=nil) or (FLayers=nil) then Exit;
  FZoomLabel.Caption := Format('%d小節 · %g拍 · %dフレーム · BPM %g · 無音ループ',
    [FTiming.MeasureAtBeat(FCursorBeat),FTiming.BeatInMeasure(FCursorBeat)+1,Round(FTiming.BeatToSeconds(FCursorBeat)*30),FTiming.BPMAt(FCursorBeat)]);
  Legacy := False; if FSelected>=0 then Legacy := not FData.StepAt(FSelected).HoldUntilNext;
  FStepLengthEdit.Enabled := Legacy; FLayers.Enabled := FPath<>'';
  FLayers.UIControls.HintLabel.Caption := 'カーソル位置でチェック変更 → 設定点を保存。四角を選択 → その設定を編集。';
  if FObjectDown and FDragStarted and not FDragValid then Text := FDragError
  else if FInputError<>'' then Text := FInputError
  else if FNotice<>'' then Text := FNotice
  else if FPath='' then Text := '先に共有PSDを歌唱PSDスロットへ割り当ててください。'
  else if FSelected<0 then Text := 'チェック変更で設定点を作成 · クリック/ズーム/パンはデータ不変'
  else if Legacy then Text := Format('区間設定 %d · 開始 %g拍 · 長さ %g拍',[FSelected+1,FData.StepAt(FSelected).StartBeat,FData.StepAt(FSelected).LengthBeats])
  else Text := Format('設定点 %d · 次の点/末尾まで保持 · %d個の設定',[FSelected+1,FData.StepCount]);
  FStatus.Caption := Text; FStatus.Hint := Text;
  if FPlaying then FPlayButton.Caption := 'Ⅱ 一時停止' else FPlayButton.Caption := '▶ 再生';
end;
procedure TMusicStudioLayerStepFrame.LoadPerformance(const ConfigJSON,AssetID,Path,BaseConfig: string; TempoBPM: Double; const TimingJSON: string);
var JSON: TJSONValue;
begin
  FClock.Enabled := False; FPlaying := False; FinishPan(False); FUpdating := True;
  try
    FData.LoadJSON(ConfigJSON);
    if FData.AssetID='' then FData.Enable(AssetID)
    else if (AssetID<>'') and (FData.AssetID<>AssetID) then raise EArgumentException.Create('別のPSDの演奏です。元のPSDトラックで編集してください。');
    FPath := Path; FBaseConfig := BaseConfig; FTempoBPM := TempoBPM; FTiming.SetTempoPoint(0,0,TempoBPM);
    if TimingJSON<>'' then begin JSON := TJSONObject.ParseJSONValue(TimingJSON);
      try if not (JSON is TJSONObject) then raise EArgumentException.Create('拍子/テンポが不正です。'); FTiming.LoadJSON(TJSONObject(JSON)); finally JSON.Free; end;
    end;
    FSelected := -1; FInputError := ''; FPreviewConfig := ''; FCursorBeat := 0; FStartBeat := 0; FHistory.Clear;
    FLengthEdit.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); FStepLengthEdit.Text := '';
    FLayers.LoadPSD(FPath,FBaseConfig,True);
  finally FUpdating := False; end;
  SyncCursor;
end;
function TMusicStudioLayerStepFrame.ConfigJSON: string;
var Value: Double;
begin
  if FInputError<>'' then raise EArgumentException.Create(FInputError);
  if not TryStrToFloat(FLengthEdit.Text,Value,TFormatSettings.Invariant) or (Value<>FData.LengthBeats) then
    raise EArgumentException.Create('パターン長の入力を修正してください。');
  if (FSelected>=0) and not FData.StepAt(FSelected).HoldUntilNext and (not TryStrToFloat(FStepLengthEdit.Text,Value,TFormatSettings.Invariant) or
    (Value<>FData.StepAt(FSelected).LengthBeats)) then raise EArgumentException.Create('step長の入力を修正してください。');
  FLayers.PollResults;
  if (FData.StepCount>0) and not FLayers.CanApply then begin
    if FLayers.IsLoading or FLayers.IsRendering then raise EArgumentException.Create('PSDの読込・合成が完了してから確定してください。');
    raise EArgumentException.Create(FLayers.StateText);
  end;
  Result := FData.ConfigJSON;
end;
procedure TMusicStudioLayerStepFrame.LengthChanged(Sender: TObject);
var Value: Double; Before: string;
begin
  if FUpdating then Exit; FInputError := ''; Before := FData.ConfigJSON;
  try
    if not TryStrToFloat(FLengthEdit.Text,Value,TFormatSettings.Invariant) then raise EArgumentException.Create('パターン長を拍で入力してください。');
    FData.LengthBeats := Value; FHistory.RecordChange(Before,FData.ConfigJSON);
    FCursorBeat := Min(FCursorBeat,FData.LengthBeats); SetViewStart(FStartBeat); SyncCursor;
  except on E: Exception do FInputError := E.Message; end;
  UpdateStatus; FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.StepLengthChanged(Sender: TObject);
var Step: TMusicStudioLayerStep; Value: Double; Before: string;
begin
  if FUpdating or (FSelected<0) or FData.StepAt(FSelected).HoldUntilNext then Exit; FInputError := ''; Before := FData.ConfigJSON;
  try
    if not TryStrToFloat(FStepLengthEdit.Text,Value,TFormatSettings.Invariant) then raise EArgumentException.Create('旧区間長を拍で入力してください。');
    Step := FData.StepAt(FSelected); FData.SetEditableBounds(FSelected,Step.StartBeat,Value,False); FHistory.RecordChange(Before,FData.ConfigJSON);
  except on E: Exception do FInputError := E.Message; end;
  UpdateStatus; FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.LayerChanged(Sender: TObject);
var Step: TMusicStudioLayerStep; Before,Config: string;
begin
  if FUpdating then Exit; FClock.Enabled := False; FPlaying := False; FInputError := '';
  Before := FData.ConfigJSON; Config := FLayers.ConfigJSON;
  try
    if FSelected<0 then FSelected := FData.AddSettingPoint(FCursorBeat,Config);
    Step := FData.StepAt(FSelected); Step.ConfigJSON := Config; FData.SetStep(FSelected,Step);
    SyncCursor; FHistory.RecordChange(Before,FData.ConfigJSON);
  except on E: Exception do begin FData.LoadJSON(Before); FNotice := E.Message; FPreviewConfig := ''; SyncCursor; end; end;
end;
procedure TMusicStudioLayerStepFrame.SelectStep(Index: Integer);
begin
  if (Index<0) or (Index>=FData.StepCount) then begin FSelected := -1; SyncCursor; Exit; end;
  SeekBeat(FData.StepAt(Index).StartBeat);
end;
function TMusicStudioLayerStepFrame.AddStep(StartBeat: Double): Integer;
var Length: Double;
begin
  StartBeat := Floor(Max(0.0,StartBeat)/SnapStep+1E-9)*SnapStep;
  Length := Min(SnapStep,FData.LengthBeats-StartBeat);
  Result := FData.AddStep(StartBeat,Length,'{"visibility":{}}'); SelectStep(Result);
end;
procedure TMusicStudioLayerStepFrame.DeleteSelected;
var Before: string;
begin
  if FSelected<0 then Exit; Before := FData.ConfigJSON; FData.DeleteStep(FSelected);
  FHistory.RecordChange(Before,FData.ConfigJSON); SyncCursor;
end;
procedure TMusicStudioLayerStepFrame.DeleteClick(Sender: TObject);
begin DeleteSelected; end;
function TMusicStudioLayerStepFrame.StepRect(Index: Integer): TRect;
var Step: TMusicStudioLayerStep;
begin Step := FData.StepAt(Index); Result := BoundsRect(Step.StartBeat,Step.LengthBeats); end;
procedure TMusicStudioLayerStepFrame.PaintGrid(Sender: TObject);
var C: TCanvas; I,X,Y,EndX,Measure,Saved: Integer; Beat,Step,Limit,Head: Double; R,Bounds: TRect;
begin
  C := FGrid.Canvas; C.Brush.Style := bsSolid; C.Brush.Color := $00262626; C.FillRect(FGrid.ClientRect);
  C.Font.Assign(Font); C.Font.Color := clSilver; Step := SnapStep; Y := MulDiv(44,LayoutPPI,96);
  Saved := SaveDC(C.Handle);
  try
    IntersectClipRect(C.Handle,HeaderWidth,0,FGrid.Width,FGrid.Height);
    Limit := Min(FData.LengthBeats,FStartBeat+Max(1,FGrid.Width-HeaderWidth)/PixelsPerBeat+Step); Beat := Floor(FStartBeat/Step)*Step;
    while Beat<Limit+1E-9 do begin
      X := XAtBeat(Beat); EndX := XAtBeat(Beat+Step);
      if FTiming.MeasureAtBeat(Max(0.0,Beat)) mod 2=1 then C.Brush.Color := $00323232 else C.Brush.Color := $003B3B3B;
      C.FillRect(Rect(X+1,Y,EndX,FGrid.Height));
      if Abs(Beat-Round(Beat))<1E-9 then C.Pen.Color := $00565656 else C.Pen.Color := $00444444;
      C.MoveTo(X,Y); C.LineTo(X,FGrid.Height); Beat := Beat+Step;
    end;
    Measure := FTiming.MeasureAtBeat(FStartBeat);
    repeat
      Head := FTiming.MeasureStart(Measure); X := XAtBeat(Head); C.Pen.Color := $00707070; C.MoveTo(X,0); C.LineTo(X,FGrid.Height);
      Bounds := Rect(X+4,4,X+MulDiv(110,LayoutPPI,96),Y); C.Font.Color := clSilver; C.Brush.Style := bsClear;
      DrawText(C.Handle,PChar(IntToStr(Measure)+'小節'),-1,Bounds,DT_SINGLELINE); C.Brush.Style := bsSolid; Inc(Measure);
    until FTiming.MeasureStart(Measure)>Limit;
    for I := 0 to FData.StepCount-1 do begin
      R := StepRect(I); if (R.Right<HeaderWidth) or (R.Left>FGrid.Width) then Continue;
      C.Brush.Color := $007AAEDD; C.Pen.Color := $00BAE4FF; if I=FSelected then C.Pen.Color := clWhite; C.Rectangle(R);
      C.Pen.Color := $003A3A3A; C.MoveTo(R.Right-MulDiv(6,LayoutPPI,96),R.Top+3); C.LineTo(R.Right-MulDiv(6,LayoutPPI,96),R.Bottom-3);
    end;
    if FSelected>=0 then begin
      R := ResizeHandleRect(FSelected); C.Brush.Color := $007AAEDD; C.Pen.Color := clWhite; C.Rectangle(R);
    end;
    if FObjectDown and FDragStarted then begin
      R := BoundsRect(FProposedStart,FProposedLength); C.Brush.Style := bsClear;
      if FDragValid then C.Pen.Color := $00C0FFC0 else C.Pen.Color := $008080FF;
      C.Pen.Width := 2; C.Rectangle(R); C.Pen.Width := 1; C.Brush.Style := bsSolid;
    end;
    X := XAtBeat(FCursorBeat); C.Pen.Color := $0068A9FF; C.Pen.Width := 2; C.MoveTo(X,0); C.LineTo(X,FGrid.Height); C.Pen.Width := 1;
    if FGrid.Height>=MulDiv(124,LayoutPPI,96) then begin
      Bounds := Rect(HeaderWidth+MulDiv(12,LayoutPPI,96),MulDiv(100,LayoutPPI,96),FGrid.Width,FGrid.Height);
      C.Font.Color := clSilver; C.Brush.Style := bsClear;
      DrawText(C.Handle,'四角: 選択/移動・右端: 長さ · 空白ドラッグ: 横移動 · ホイール: 拡縮',-1,Bounds,DT_SINGLELINE);
    end;
  finally RestoreDC(C.Handle,Saved); end;
  C.Brush.Style := bsSolid; C.Brush.Color := $00383838; C.FillRect(Rect(0,0,HeaderWidth,FGrid.Height));
  C.Pen.Color := $00707070; C.MoveTo(HeaderWidth-1,0); C.LineTo(HeaderWidth-1,FGrid.Height);
  C.Brush.Style := bsClear; C.Font.Color := clSilver; Bounds := Rect(4,4,HeaderWidth-4,Y);
  DrawText(C.Handle,'小節',-1,Bounds,DT_CENTER or DT_SINGLELINE);
  Bounds := Rect(4,Y,HeaderWidth-4,Y+MulDiv(28,LayoutPPI,96)); DrawText(C.Handle,'設定',-1,Bounds,DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;
procedure TMusicStudioLayerStepFrame.GridDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var I,Picked: Integer; Latest: Double; R: TRect; HandlePicked: Boolean;
begin
  if X<HeaderWidth then Exit; Picked := -1; Latest := -1;
  HandlePicked := (FSelected>=0) and PtInRect(ResizeHandleRect(FSelected),Point(X,Y));
  if HandlePicked then Picked := FSelected
  else for I := 0 to FData.StepCount-1 do if PtInRect(StepRect(I),Point(X,Y)) and (FData.StepAt(I).StartBeat>Latest) then begin Picked := I; Latest := FData.StepAt(I).StartBeat; end;
  if Button=mbRight then begin if Picked>=0 then begin SelectStep(Picked); DeleteSelected; end; Exit; end;
  if Button<>mbLeft then Exit; FinishPan(True); FObjectDown := Picked>=0; FObjectResize := False; FDragStarted := False; FDragValid := False; FDragError := ''; FNotice := '';
  if FObjectDown then begin
    SelectStep(Picked); FOriginalStep := FData.StepAt(Picked); FProposedStart := FOriginalStep.StartBeat; FProposedLength := FOriginalStep.LengthBeats;
    R := StepRect(Picked); FObjectResize := HandlePicked or ((R.Width>MulDiv(12,LayoutPPI,96)) and (X>=R.Right-MulDiv(8,LayoutPPI,96)));
  end;
  FGrid.SetFocus; FPointerDown := True; FPanning := False; FDownPoint := Point(X,Y); FPanStart := FStartBeat; SetCapture(FGrid.Handle);
end;
function TMusicStudioLayerStepFrame.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := False; if FGrid<>nil then GridWheel(Self,Shift,WheelDelta,MousePos,Result);
  if not Result then Result := inherited;
end;
procedure TMusicStudioLayerStepFrame.SetViewStart(Value: Double);
begin
  FStartBeat := EnsureRange(Value,0.0,Max(0.0,FData.LengthBeats-Max(1,FGrid.ClientWidth-HeaderWidth)/Max(1.0,PixelsPerBeat))); FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.SyncCursor;
var I,Active: Integer; Config: string;
begin
  FSelected := -1;
  for I := 0 to FData.StepCount-1 do if Abs(FData.StepAt(I).StartBeat-FCursorBeat)<1E-9 then begin FSelected := I; Break; end;
  Active := FData.ActiveStepAt(FCursorBeat); Config := FBaseConfig;
  if Active>=0 then Config := MusicStudioMergeLayerStepConfig(FBaseConfig,FData.StepAt(Active).ConfigJSON);
  FUpdating := True;
  try
    if FSelected>=0 then FStepLengthEdit.Text := FloatToStr(FData.StepAt(FSelected).LengthBeats,TFormatSettings.Invariant) else FStepLengthEdit.Text := '';
    if Config<>FPreviewConfig then begin FLayers.LoadExpressionConfig(Config); FPreviewConfig := Config; end;
  finally FUpdating := False; end;
  UpdateStatus; FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.SeekBeat(Beat: Double);
begin
  if IsNan(Beat) or IsInfinite(Beat) then Exit; FNotice := '';
  FClock.Enabled := False; FPlaying := False; FCursorBeat := EnsureRange(Beat,0.0,FData.LengthBeats); SyncCursor;
end;
procedure TMusicStudioLayerStepFrame.PlayClick(Sender: TObject);
begin PlayPause; end;
procedure TMusicStudioLayerStepFrame.StopClick(Sender: TObject);
begin Stop; end;
procedure TMusicStudioLayerStepFrame.PlayPause;
begin
  if FPlaying then begin ClockTick(nil); FPlaying := False; FClock.Enabled := False; end
  else begin
    if FCursorBeat>=FData.LengthBeats then begin FCursorBeat := 0; SyncCursor; end;
    FPlaying := True; FLastTick := GetTickCount64; FClock.Enabled := True;
  end; UpdateStatus;
end;
procedure TMusicStudioLayerStepFrame.Stop;
begin FClock.Enabled := False; FPlaying := False; FCursorBeat := 0; SetViewStart(0); SyncCursor; end;
procedure TMusicStudioLayerStepFrame.AdvancePlayback(Seconds: Double);
var Position,Duration: Double;
begin
  if not FPlaying or IsNan(Seconds) or IsInfinite(Seconds) or (Seconds<0) then Exit;
  Duration := FTiming.BeatToSeconds(FData.LengthBeats); if Duration<=0 then Exit;
  Position := FTiming.BeatToSeconds(FCursorBeat)+Seconds; Position := Position-Floor(Position/Duration)*Duration;
  FCursorBeat := Min(FTiming.SecondsToBeat(Position),Max(0.0,FData.LengthBeats-1E-12));
  if (FCursorBeat<FStartBeat) or (FCursorBeat>FStartBeat+Max(1,FGrid.ClientWidth-HeaderWidth)/PixelsPerBeat) then SetViewStart(FCursorBeat);
  SyncCursor;
end;
procedure TMusicStudioLayerStepFrame.ClockTick(Sender: TObject);
var NowTick: UInt64;
begin
  if not FPlaying then Exit; NowTick := GetTickCount64; AdvancePlayback((NowTick-FLastTick)/1000.0); FLastTick := NowTick;
end;
procedure TMusicStudioLayerStepFrame.ReloadEditingState;
begin
  FinishPan(True); FClock.Enabled := False; FPlaying := False; FUpdating := True;
  try FLengthEdit.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant); finally FUpdating := False; end;
  FInputError := ''; FPreviewConfig := ''; SeekBeat(FCursorBeat); SetViewStart(FStartBeat);
end;
procedure TMusicStudioLayerStepFrame.UndoEdit;
var Text: string;
begin if FHistory.Undo(FData.ConfigJSON,Text) then begin FData.LoadJSON(Text); ReloadEditingState; end; end;
procedure TMusicStudioLayerStepFrame.RedoEdit;
var Text: string;
begin if FHistory.Redo(FData.ConfigJSON,Text) then begin FData.LoadJSON(Text); ReloadEditingState; end; end;
function TMusicStudioLayerStepFrame.HandleEditorKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
  if (Key=VK_ESCAPE) and FPointerDown then begin FinishPan(True); Result := True; end
  else if (ssCtrl in Shift) and (Key=Ord('Z')) then begin FinishPan(True); UndoEdit; Result := True; end
  else if (ssCtrl in Shift) and (Key=Ord('Y')) then begin FinishPan(True); RedoEdit; Result := True; end;
  if Result then Key := 0;
end;
function TMusicStudioLayerStepFrame.MarkerRect(Index: Integer): TRect;
begin Result := StepRect(Index); end;
function TMusicStudioLayerStepFrame.ResizeHandleRect(Index: Integer): TRect;
var R: TRect; Size: Integer;
begin
  R := StepRect(Index); Size := MulDiv(10,LayoutPPI,96);
  Result := Rect(R.Right-Size div 2,R.Top-MulDiv(16,LayoutPPI,96),R.Right+Size-Size div 2,R.Top-MulDiv(3,LayoutPPI,96));
end;
procedure TMusicStudioLayerStepFrame.GridMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
var MaxStart,EndBeat,MinEnd,Length: Double; Hold: Boolean;
begin
  if not FPointerDown then Exit;
  if not FDragStarted and (Abs(X-FDownPoint.X)>Max(3,MulDiv(GetSystemMetrics(SM_CXDRAG),LayoutPPI,96))) then FDragStarted := True;
  if not FDragStarted then Exit;
  if not FObjectDown then begin FPanning := True; FGrid.Cursor := crSizeWE; SetViewStart(FPanStart-(X-FDownPoint.X)/PixelsPerBeat); Exit; end;
  X := Max(HeaderWidth,X); FGrid.Cursor := crSizeWE;
  if FObjectResize then begin
    FProposedStart := FOriginalStep.StartBeat; Hold := False;
    MinEnd := Ceil((FOriginalStep.StartBeat+SnapStep)/SnapStep-1E-9)*SnapStep;
    EndBeat := MusicStudioSnapBeat(FOriginalStep.StartBeat+FOriginalStep.LengthBeats+(X-FDownPoint.X)/PixelsPerBeat,SnapStep);
    EndBeat := Min(Floor(FData.LengthBeats/SnapStep+1E-9)*SnapStep,Max(MinEnd,EndBeat));
    FProposedLength := EndBeat-FProposedStart;
    if FProposedLength<SnapStep-1E-9 then begin FDragValid := False; FDragError := 'スナップ1マス分の長さをパターン内に確保してください。'; UpdateStatus; FGrid.Invalidate; Exit; end;
  end else begin
    Hold := FOriginalStep.HoldUntilNext; FProposedLength := FOriginalStep.LengthBeats;
    if Hold then MaxStart := Floor((FData.LengthBeats-1/1024)/SnapStep)*SnapStep
    else MaxStart := Floor((FData.LengthBeats-FProposedLength)/SnapStep+1E-9)*SnapStep;
    FProposedStart := EnsureRange(MusicStudioSnapBeat(FOriginalStep.StartBeat+(X-FDownPoint.X)/PixelsPerBeat,SnapStep),0.0,Max(0.0,MaxStart));
  end;
  FDragValid := FData.EditableBounds(FSelected,FProposedStart,FProposedLength,Hold,Length,FDragError);
  FProposedLength := Length; UpdateStatus; FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.FinishPan(Cancel: Boolean);
begin
  if Cancel and FPointerDown then FStartBeat := FPanStart;
  FPointerDown := False; FPanning := False; FObjectDown := False; FDragStarted := False; if FGrid=nil then Exit;
  FGrid.Cursor := crDefault; if FGrid.HandleAllocated and (GetCapture=FGrid.Handle) then ReleaseCapture; FGrid.Invalidate;
end;
procedure TMusicStudioLayerStepFrame.GridCaptureLost(Sender: TObject);
begin if FPointerDown then begin FinishPan(True); UpdateStatus; end; end;
procedure TMusicStudioLayerStepFrame.GridUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var Changed,ObjectEdit,Resizing,Valid: Boolean; Index: Integer; Start,Length,Beat: Double; Before,Message: string;
begin
  if (Button<>mbLeft) or not FPointerDown then Exit;
  Changed := FDragStarted; ObjectEdit := FObjectDown; Resizing := FObjectResize; Valid := FDragValid; Index := FSelected;
  Start := FProposedStart; Length := FProposedLength; Message := FDragError; FinishPan(False);
  if Changed and ObjectEdit then begin
    if not Valid then begin FNotice := Message; UpdateStatus; Exit; end;
    Before := FData.ConfigJSON;
    try FData.SetEditableBounds(Index,Start,Length,not Resizing and FOriginalStep.HoldUntilNext);
      FInputError := ''; FNotice := ''; SeekBeat(Start); FHistory.RecordChange(Before,FData.ConfigJSON);
    except on E: Exception do begin FData.LoadJSON(Before); SeekBeat(FOriginalStep.StartBeat); FNotice := E.Message; UpdateStatus; end; end;
  end else if not Changed and not ObjectEdit and (X>=HeaderWidth) then begin
    Beat := MusicStudioSnapBeat(BeatAtX(X),SnapStep); if (Beat>=0) and (Beat<FData.LengthBeats) then SeekBeat(Beat);
  end;
end;
procedure TMusicStudioLayerStepFrame.GridWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var P: TPoint; Anchor: Double;
begin
  P := FGrid.ScreenToClient(MousePos); if not PtInRect(FGrid.ClientRect,P) or (P.X<HeaderWidth) then Exit;
  Handled := True; FinishPan(True); Anchor := BeatAtX(P.X);
  FZoom := EnsureRange(FZoom*Power(1.2,WheelDelta/120),24.0,1536.0); SetViewStart(Anchor-(P.X-HeaderWidth)/PixelsPerBeat); UpdateStatus;
end;
function TMusicStudioLayerStepFrame.LayoutPPI: Integer;
var Form: TCustomForm;
begin
  Result := CurrentPPI; Form := GetParentForm(Self); if Form<>nil then Result := Max(Result,Form.CurrentPPI);
  Result := Max(Result,MulDiv(Abs(Font.Height),96,13));
end;
function TMusicStudioLayerStepFrame.HeaderWidth: Integer;
begin Result := MulDiv(76,LayoutPPI,96); end;
function TMusicStudioLayerStepFrame.BeatAtX(X: Integer): Double;
begin Result := FStartBeat+(X-HeaderWidth)/PixelsPerBeat; end;
function TMusicStudioLayerStepFrame.XAtBeat(Beat: Double): Integer;
begin Result := HeaderWidth+Round(EnsureRange((Beat-FStartBeat)*PixelsPerBeat,-32768.0,32768.0)); end;
function TMusicStudioLayerStepFrame.BoundsRect(StartBeat,LengthBeats: Double): TRect;
begin
  Result := Rect(XAtBeat(StartBeat),MulDiv(44,LayoutPPI,96),XAtBeat(StartBeat+LengthBeats),MulDiv(72,LayoutPPI,96));
  Result.Right := Max(Result.Left+2,Result.Right);
end;
procedure TMusicStudioLayerStepFrame.LayoutChrome;
var PPI,Desired: Integer;
  procedure Place(C: TControl; X,Y,W,H: Integer);
  begin C.SetBounds(MulDiv(X,PPI,96),MulDiv(Y,PPI,96),MulDiv(W,PPI,96),MulDiv(H,PPI,96)); end;
begin
  if (FHeader=nil) or (FStepHeader=nil) or (FStatus=nil) or (FDeleteButton=nil) then Exit; PPI := LayoutPPI; DisableAlign;
  try
    FHeader.Height := MulDiv(44,PPI,96); FStepHeader.Height := MulDiv(44,PPI,96);
    Place(FLengthLabel,12,12,92,22); Place(FLengthEdit,108,8,68,26);
    Place(FPlayButton,194,8,104,28); Place(FStopButton,306,8,104,28);
    FZoomLabel.SetBounds(MulDiv(424,PPI,96),MulDiv(12,PPI,96),Max(1,ClientWidth-MulDiv(436,PPI,96)),MulDiv(22,PPI,96));
    Place(FStepLengthLabel,12,12,112,22); Place(FStepLengthEdit,128,8,80,26); Place(FDeleteButton,222,8,100,28);
    FStatus.SetBounds(MulDiv(336,PPI,96),MulDiv(12,PPI,96),Max(1,ClientWidth-MulDiv(348,PPI,96)),MulDiv(22,PPI,96));
    Desired := EnsureRange(ClientHeight-MulDiv(348,PPI,96),MulDiv(80,PPI,96),MulDiv(132,PPI,96));
    FGrid.Parent.Height := Desired;
  finally EnableAlign; end;
end;
end.
