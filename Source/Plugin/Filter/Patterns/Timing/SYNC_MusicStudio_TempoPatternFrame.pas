unit SYNC_MusicStudio_TempoPatternFrame;

// MIDI tempo参照の取込/取消とsnapshot表示。曲の手動tempoや音声処理には触れない。
interface
uses System.Classes, System.Generics.Collections, System.SyncObjs, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids, Vcl.Dialogs, SYNC_MusicStudio_TempoPatternData;
type
  TMusicStudioTempoImportJob = class(TThread)
  private FDone: TEvent;
  protected procedure Execute; override;
  public
    Path,TimingJSON,ErrorText: string;
    Generation: Integer;
    LengthBeats: Double;
    constructor Create(const FilePath: string; Gen: Integer);
    destructor Destroy; override;
    function Done: Boolean;
  end;
  TMusicStudioTempoPatternFrame = class(TFrame)
  private
    FData: TMusicStudioTempoPatternData;
    FJobs: TObjectList<TMusicStudioTempoImportJob>;
    FTimer: TTimer;
    FDialog: TOpenDialog;
    FPath,FLength: TEdit;
    FSummary,FState: TLabel;
    FGrid: TStringGrid;
    FGeneration: Integer;
    FPendingPath,FInputError: string;
    FUpdating,FLoading: Boolean;
    FOnSourceChange: TNotifyEvent;
    FFileButton: TButton;
    procedure BuildUI;
    procedure FileClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure LengthChanged(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Refresh;
  protected procedure SetParent(AParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadTempo(const ConfigJSON: string);
    procedure StartImport(const Path: string);
    procedure CancelImport;
    procedure PollResults;
    function ConfigJSON: string;
    property Data: TMusicStudioTempoPatternData read FData;
    property Loading: Boolean read FLoading;
    property FileButton: TButton read FFileButton;
    property OnSourceChange: TNotifyEvent read FOnSourceChange write FOnSourceChange;
  end;
implementation
uses System.SysUtils, System.Math, System.JSON, Winapi.Windows, SYNC_MusicStudio_MidiTempo,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
{$R *.dfm}
constructor TMusicStudioTempoImportJob.Create(const FilePath: string; Gen: Integer);
begin inherited Create(True); FreeOnTerminate := False; Path := FilePath; Generation := Gen; FDone := TEvent.Create(nil,True,False,''); end;
destructor TMusicStudioTempoImportJob.Destroy;
begin Terminate; WaitFor; FDone.Free; inherited; end;
procedure TMusicStudioTempoImportJob.Execute;
begin
  try try ReadMusicStudioMidiTempo(Path,TimingJSON,LengthBeats,Self);
    except on E: Exception do ErrorText := E.Message; end;
  finally FDone.SetEvent; end;
end;
function TMusicStudioTempoImportJob.Done: Boolean;
begin
  // 起動前にTerminateされたTThreadはExecuteを呼ばない。退役枠を永久に占有させない。
  Result := (FDone.WaitFor(0)=wrSignaled) or Finished;
end;
constructor TMusicStudioTempoPatternFrame.Create(AOwner: TComponent);
begin inherited; FData := TMusicStudioTempoPatternData.Create; FJobs := TObjectList<TMusicStudioTempoImportJob>.Create(True);
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;
destructor TMusicStudioTempoPatternFrame.Destroy;
begin if Assigned(FTimer) then FTimer.Enabled := False; CancelImport; FJobs.Free; FData.Free; inherited; end;
procedure TMusicStudioTempoPatternFrame.SetParent(AParent: TWinControl);
begin inherited; if (AParent<>nil) and (FData<>nil) and (FGrid=nil) then BuildUI; end;
procedure TMusicStudioTempoPatternFrame.BuildUI;
var Header,Footer,FileRow: TPanel; B: TButton;
begin
  Header := TPanel.Create(Self); Header.Parent := Self; Header.Align := alTop; Header.Height := 130; Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  FileRow := TPanel.Create(Self); FileRow.Parent := Header; FileRow.Align := alTop; FileRow.Height := 44; FileRow.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(FileRow);
  FFileButton := TMusicStudioButton.Create(Self); FFileButton.Parent := FileRow; FFileButton.Align := alRight; FFileButton.Width := 140;
  FFileButton.AlignWithMargins := True; FFileButton.Margins.SetBounds(6,12,12,4); FFileButton.Caption := 'MIDIから読込…'; FFileButton.OnClick := FileClick;
  FPath := TEdit.Create(Self); FPath.Parent := FileRow; FPath.Align := alClient; FPath.AlignWithMargins := True; FPath.Margins.SetBounds(12,12,0,4);
  FPath.ReadOnly := True; ApplySyncMusicStudioDarkEdit(FPath);
  B := TMusicStudioButton.Create(Self); B.Parent := Header; B.SetBounds(12,52,110,28); B.Caption := '読込取消'; B.OnClick := CancelClick;
  FLength := TEdit.Create(Self); FLength.Parent := Header; FLength.SetBounds(250,52,90,26); ApplySyncMusicStudioDarkEdit(FLength); FLength.OnChange := LengthChanged;
  FSummary := TLabel.Create(Self); FSummary.Parent := Header; FSummary.SetBounds(138,58,106,22); FSummary.Caption := 'パターン長 (拍)';
  FState := TLabel.Create(Self); FState.Parent := Header; FState.SetBounds(12,94,Header.ClientWidth-24,32);
  FState.AutoSize := False; FState.Anchors := [akLeft,akTop,akRight]; FState.ShowHint := True;
  Footer := TPanel.Create(Self); Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 62; Footer.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Footer);
  FSummary := TLabel.Create(Self); FSummary.Parent := Footer; FSummary.Align := alClient; FSummary.AlignWithMargins := True;
  FSummary.Margins.SetBounds(12,8,12,8); FSummary.WordWrap := True; FSummary.AutoSize := False;
  FSummary.Caption := '曲全体へ適用。配置区間はtempo clipが手動tempoより優先、終了後は手動/他のclipへ復帰。MIDI拍子は参考表示、曲の拍子は上部BPM/拍子で設定。';
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Self; FGrid.Align := alClient; FGrid.ColCount := 2; FGrid.FixedCols := 0; FGrid.RowCount := 2;
  FGrid.ColWidths[0] := 180; FGrid.ColWidths[1] := 160; FGrid.Options := [goFixedVertLine,goFixedHorzLine,goVertLine,goHorzLine,goRowSelect];
  FGrid.Color := $002A2A2A; FGrid.FixedColor := $003C3C3C; FGrid.Font.Color := $00E3E3E3;
  FDialog := TOpenDialog.Create(Self); FDialog.Filter := 'Tempo MIDI|*.mid;*.midi;*.kar|すべて|*.*'; FDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing];
  FTimer := TTimer.Create(Self); FTimer.Interval := 40; FTimer.OnTimer := Tick; Refresh;
end;
procedure TMusicStudioTempoPatternFrame.LoadTempo(const ConfigJSON: string);
begin CancelImport; FData.LoadJSON(ConfigJSON); FInputError := ''; Refresh; end;
procedure TMusicStudioTempoPatternFrame.Refresh;
var I: Integer; Obj: TJSONObject; V: TJSONValue; Warning: string;
begin
  if FGrid=nil then Exit; FUpdating := True;
  try FPath.Text := FData.FilePath; FLength.Text := FloatToStr(FData.LengthBeats,TFormatSettings.Invariant);
    FGrid.RowCount := FData.Timing.PointCount+1; FGrid.Cells[0,0] := '相対拍'; FGrid.Cells[1,0] := 'BPM';
    for I := 0 to FData.Timing.PointCount-1 do begin FGrid.Cells[0,I+1] := FloatToStr(FData.Timing.TempoPoint(I).Beat,TFormatSettings.Invariant);
      FGrid.Cells[1,I+1] := FloatToStr(FData.Timing.TempoPoint(I).BPM,TFormatSettings.Invariant); end;
    Warning := ''; Obj := TJSONObject.ParseJSONValue(FData.Timing.TimingJSON) as TJSONObject;
    try V := nil; if Obj.GetValue('midi') is TJSONObject then V := TJSONObject(Obj.GetValue('midi')).GetValue('meterChangesIgnored');
      if (V is TJSONNumber) and (TJSONNumber(V).AsInt>0) then Warning := ' · 途中拍子変更は未適用';
    finally Obj.Free; end;
    FState.Caption := Format('%d tempo点 · MIDI先頭拍子 %d/%d%s',[FData.Timing.PointCount,FData.Timing.Numerator,FData.Timing.Denominator,Warning]);
    if FInputError<>'' then FState.Caption := FInputError; FState.Hint := FState.Caption;
  finally FUpdating := False; end;
end;
procedure TMusicStudioTempoPatternFrame.FileClick(Sender: TObject);
begin if FDialog.Execute then StartImport(FDialog.FileName); end;
procedure TMusicStudioTempoPatternFrame.StartImport(const Path: string);
var Job: TMusicStudioTempoImportJob;
begin
  Inc(FGeneration); for Job in FJobs do Job.Terminate; FPendingPath := Path; FLoading := True; FInputError := '';
  FState.Caption := 'MIDI tempoを読み込み中…'; PollResults;
end;
procedure TMusicStudioTempoPatternFrame.CancelImport;
var Job: TMusicStudioTempoImportJob;
begin Inc(FGeneration); FPendingPath := ''; FLoading := False; FInputError := '';
  if Assigned(FJobs) then for Job in FJobs do Job.Terminate;
end;
procedure TMusicStudioTempoPatternFrame.CancelClick(Sender: TObject);
begin CancelImport; FInputError := ''; Refresh; end;
procedure TMusicStudioTempoPatternFrame.Tick(Sender: TObject);
begin PollResults; end;
procedure TMusicStudioTempoPatternFrame.PollResults;
var I: Integer; Job: TMusicStudioTempoImportJob;
begin
  for I := FJobs.Count-1 downto 0 do begin Job := FJobs[I]; if not Job.Done then Continue;
    if Job.Generation=FGeneration then begin
      FLoading := False;
      if Job.ErrorText='' then begin
        try FData.ImportSnapshot(Job.Path,Job.TimingJSON,Job.LengthBeats); FInputError := '';
          if Assigned(FOnSourceChange) then FOnSourceChange(Self);
        except on E: Exception do FInputError := E.Message; end;
      end else FInputError := Job.ErrorText;
      Refresh;
    end; FJobs.Delete(I);
  end;
  if (FPendingPath<>'') and (FJobs.Count<2) then begin Job := TMusicStudioTempoImportJob.Create(FPendingPath,FGeneration);
    FPendingPath := ''; FJobs.Add(Job); Job.Start;
  end;
end;
procedure TMusicStudioTempoPatternFrame.LengthChanged(Sender: TObject);
var Value: Double;
begin
  if FUpdating then Exit; FInputError := '';
  try if not TryStrToFloat(FLength.Text,Value,TFormatSettings.Invariant) then raise EArgumentException.Create('tempo長を拍で入力してください。');
    FData.LengthBeats := Value;
  except on E: Exception do FInputError := E.Message; end;
  FState.Caption := FInputError;
end;
function TMusicStudioTempoPatternFrame.ConfigJSON: string;
begin if FLoading then raise EInvalidOperation.Create('MIDI読込完了か取消を待ってください。');
  if FInputError<>'' then raise EArgumentException.Create(FInputError); Result := FData.ConfigJSON;
end;
end.
