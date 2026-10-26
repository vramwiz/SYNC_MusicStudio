unit SYNC_MusicStudio_AudioClipFrame;

// 音声固有のファイル参照・非同期波形・音量UI。共通の名前と色、JSON保存は担当しない。
interface

uses
  System.Classes, System.Generics.Collections, Vcl.Forms, Vcl.StdCtrls,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Dialogs,
  SYNC_MusicStudio_AudioWaveform;

type
  TMusicStudioAudioClipFrame = class(TFrame)
  private
    FPath: string;
    FNoDecode: Boolean;
    FGeneration: Integer;
    FJobs: TObjectList<TMusicStudioWaveJob>;
    FWave: TMusicStudioWaveform;
    FInfo: TMusicStudioAudioInfo;
    FMessage: string;
    FPoll: TTimer;
    FWaveBox: TPaintBox;
    FInfoLabel, FVolumeLabel: TLabel;
    FOpenDialog: TOpenDialog;
    FOnSourceChange: TNotifyEvent;
    procedure BrowseClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure VolumeChanged(Sender: TObject);
    procedure PaintWave(Sender: TObject);
    procedure PollTimer(Sender: TObject);
    procedure BuildUI;
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    PathEdit: TEdit;
    VolumeBar: TTrackBar;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 参照は欠落/壊れた状態でも保持し、波形欄で理由を示す。新選択で旧波形を即時消去する。
    procedure SelectFile(const Path: string);
    procedure LoadAudio(const Path: string; Volume: Double);
    // タイマーと検証から呼ぶ。完了済みジョブだけを読み、現要求以外は破棄する。
    procedure PollResults;
    function WavePointCount: Integer;
    function IsLoading: Boolean;
    function Volume: Double;
    property NoDecode: Boolean read FNoDecode write FNoDecode;
    property FilePath: string read FPath;
    property WaveMessage: string read FMessage;
    property AudioInfo: TMusicStudioAudioInfo read FInfo;
    property OnSourceChange: TNotifyEvent read FOnSourceChange write FOnSourceChange;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Types, System.IOUtils, Vcl.Graphics,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

{$R *.dfm}

constructor TMusicStudioAudioClipFrame.Create(AOwner: TComponent);
begin
  inherited;
  FJobs := TObjectList<TMusicStudioWaveJob>.Create(True);
  ApplySyncMusicStudioDarkFrame(Self);
  ApplyMusicStudioEditorFont(Self);
  BuildUI;
  FMessage := 'WAV / MP3を選択すると波形を表示します。';
end;

destructor TMusicStudioAudioClipFrame.Destroy;
var
  Job: TMusicStudioWaveJob;
begin
  if Assigned(FPoll) then FPoll.Enabled := False;
  if Assigned(FJobs) then for Job in FJobs do Job.Terminate;
  FJobs.Free; // Queueを使わないため解放後のUIアクセスはない。
  inherited;
end;

procedure TMusicStudioAudioClipFrame.SetParent(AParent: TWinControl);
var
  Component: TComponent;
begin
  inherited;
  if AParent = nil then Exit;
  for Component in Self do
    if Component is TButton then ApplySyncMusicStudioDarkButton(TButton(Component));
end;

procedure TMusicStudioAudioClipFrame.BuildUI;
var
  LabelControl: TLabel;
  Button: TButton;
  WavePanel: TPanel;
begin
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Self;
  LabelControl.SetBounds(16, 10, 250, 20);
  LabelControl.Caption := '音源ファイル  /  WAV・MP3';
  PathEdit := TEdit.Create(Self);
  PathEdit.Parent := Self;
  PathEdit.SetBounds(16, 36, Width - 236, 26);
  PathEdit.Anchors := [akLeft, akTop, akRight];
  PathEdit.ReadOnly := True;
  ApplySyncMusicStudioDarkEdit(PathEdit);
  Button := TMusicStudioButton.Create(Self);
  Button.Parent := Self;
  Button.SetBounds(Width - 212, 35, 100, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'ファイル選択…';
  Button.OnClick := BrowseClick;
  Button.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  Button := TMusicStudioButton.Create(Self);
  Button.Parent := Self;
  Button.SetBounds(Width - 104, 35, 88, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := '参照を解除';
  Button.OnClick := ClearClick;
  Button.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  FInfoLabel := TLabel.Create(Self);
  FInfoLabel.Parent := Self;
  FInfoLabel.SetBounds(16, 72, Width - 32, 38);
  FInfoLabel.Anchors := [akLeft, akTop, akRight];
  FInfoLabel.AutoSize := False;
  FInfoLabel.WordWrap := True;
  WavePanel := TPanel.Create(Self);
  WavePanel.Parent := Self;
  WavePanel.SetBounds(16, 116, Width - 32, Height - 188);
  WavePanel.Anchors := [akLeft, akTop, akRight, akBottom];
  WavePanel.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(WavePanel);
  FWaveBox := TPaintBox.Create(Self);
  FWaveBox.Parent := WavePanel;
  FWaveBox.Align := alClient;
  FWaveBox.OnPaint := PaintWave;
  FVolumeLabel := TLabel.Create(Self);
  FVolumeLabel.Parent := Self;
  FVolumeLabel.SetBounds(16, Height - 62, 280, 20);
  FVolumeLabel.Anchors := [akLeft, akBottom];
  VolumeBar := TTrackBar.Create(Self);
  VolumeBar.Parent := Self;
  VolumeBar.SetBounds(300, Height - 66, Width - 316, 42);
  VolumeBar.Anchors := [akLeft, akRight, akBottom];
  VolumeBar.Min := 0;
  VolumeBar.Max := 200;
  VolumeBar.Position := 100;
  VolumeBar.Frequency := 25;
  VolumeBar.OnChange := VolumeChanged;
  VolumeChanged(nil);
  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter := '音源ファイル (*.wav;*.mp3)|*.wav;*.mp3|WAV (*.wav)|*.wav|MP3 (*.mp3)|*.mp3';
  FOpenDialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
  FOpenDialog.Title := '参照する音源ファイルを選択';
  FPoll := TTimer.Create(Self);
  FPoll.Interval := 80;
  FPoll.Enabled := False;
  FPoll.OnTimer := PollTimer;
end;

procedure TMusicStudioAudioClipFrame.LoadAudio(const Path: string; Volume: Double);
begin
  VolumeBar.Position := EnsureRange(Round(Volume * 100), 0, 200);
  SelectFile(Path);
end;

procedure TMusicStudioAudioClipFrame.SelectFile(const Path: string);
var
  Job: TMusicStudioWaveJob;
begin
  Inc(FGeneration);
  for Job in FJobs do Job.Terminate;
  FPath := Path;
  PathEdit.Text := Path;
  PathEdit.Hint := Path;
  PathEdit.ShowHint := True;
  FWave := nil;
  FInfo := Default(TMusicStudioAudioInfo);
  if Path = '' then
    FMessage := 'WAV / MP3を選択すると波形を表示します。'
  else if FNoDecode then FMessage := '無音確認モード: 音声解析は停止しています。参照と音量を保存できます。'
  else
  begin
    FMessage := '音源から波形を読み込み中…';
    Job := TMusicStudioWaveJob.Create(Path, FGeneration);
    FJobs.Add(Job);
    Job.Start;
  end;
  FInfoLabel.Caption := FMessage;
  FWaveBox.Invalidate;
  FPoll.Enabled := FJobs.Count > 0;
end;

procedure TMusicStudioAudioClipFrame.BrowseClick(Sender: TObject);
begin
  FOpenDialog.FileName := FPath;
  if not FOpenDialog.Execute then Exit;
  SelectFile(TPath.GetFullPath(FOpenDialog.FileName));
  if Assigned(FOnSourceChange) then FOnSourceChange(Self);
end;

procedure TMusicStudioAudioClipFrame.ClearClick(Sender: TObject);
begin
  SelectFile('');
end;

procedure TMusicStudioAudioClipFrame.PollTimer(Sender: TObject);
begin
  PollResults;
end;

procedure TMusicStudioAudioClipFrame.PollResults;
var
  I: Integer;
  Job: TMusicStudioWaveJob;
begin
  for I := FJobs.Count - 1 downto 0 do
  begin
    Job := FJobs[I];
    if not Job.Done then Continue;
    if (Job.RequestID = FGeneration) and (Job.FilePath = FPath) then
    begin
      FWave := Job.Waveform;
      FInfo := Job.Info;
      FMessage := Job.ErrorText;
      if FMessage = '' then
        FInfoLabel.Caption := Format('%.2f秒  ·  %d Hz  ·  %d ch',
          [FInfo.Duration, FInfo.SampleRate, FInfo.Channels])
      else FInfoLabel.Caption := '波形を表示できません: ' + FMessage;
      FWaveBox.Invalidate;
    end;
    FJobs.Delete(I);
  end;
  FPoll.Enabled := FJobs.Count > 0;
end;

function TMusicStudioAudioClipFrame.WavePointCount: Integer;
begin
  Result := Length(FWave);
end;

function TMusicStudioAudioClipFrame.IsLoading: Boolean;
var
  Job: TMusicStudioWaveJob;
begin
  Result := False;
  for Job in FJobs do
    if Job.RequestID = FGeneration then Exit(True);
end;

function TMusicStudioAudioClipFrame.Volume: Double;
begin
  Result := VolumeBar.Position / 100.0;
end;

procedure TMusicStudioAudioClipFrame.VolumeChanged(Sender: TObject);
begin
  FVolumeLabel.Caption := Format('音量  %d %%', [VolumeBar.Position]);
  if VolumeBar.Position = 0 then FVolumeLabel.Caption := FVolumeLabel.Caption + '  (ミュート)'
  else FVolumeLabel.Caption := FVolumeLabel.Caption + Format('  (%.1f dB)', [20 * Log10(Volume)]);
  if Assigned(FWaveBox) then FWaveBox.Invalidate;
end;

procedure TMusicStudioAudioClipFrame.PaintWave(Sender: TObject);
var
  Canvas: TCanvas;
  X, I, J, First, Last, MidY, PlotWidth: Integer;
  Lo, Hi: Single;
  R: TRect;
begin
  Canvas := FWaveBox.Canvas;
  R := FWaveBox.ClientRect;
  Canvas.Brush.Color := $00222222;
  Canvas.FillRect(R);
  MidY := R.Height div 2;
  Canvas.Pen.Color := $00444444;
  Canvas.MoveTo(12, MidY);
  Canvas.LineTo(R.Right - 12, MidY);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := $00BFBFBF;
  if Length(FWave) = 0 then
  begin
    InflateRect(R, -16, -10);
    Canvas.TextRect(R, FMessage, [tfCenter, tfVerticalCenter, tfWordBreak]);
    Exit;
  end;
  Canvas.Pen.Color := $00ADBF6F;
  PlotWidth := Max(1, R.Width - 24);
  for X := 0 to PlotWidth - 1 do
  begin
    First := Int64(X) * Length(FWave) div PlotWidth;
    Last := Min(Length(FWave), Max(First + 1, Int64(X + 1) * Length(FWave) div PlotWidth));
    Lo := 1;
    Hi := -1;
    for I := First to Last - 1 do
    begin
      Lo := Min(Lo, FWave[I].Minimum);
      Hi := Max(Hi, FWave[I].Maximum);
    end;
    J := Max(1, MidY - 22);
    Canvas.MoveTo(X + 12, MidY - Round(EnsureRange(Hi * Volume, -1.0, 1.0) * J));
    Canvas.LineTo(X + 12, MidY - Round(EnsureRange(Lo * Volume, -1.0, 1.0) * J) + 1);
  end;
  Canvas.TextOut(12, 6, '波形  /  音量反映');
  Canvas.TextOut(12, R.Bottom - 22, '0:00');
  Canvas.TextOut(R.Right - 90, R.Bottom - 22, Format('%.2f 秒', [FInfo.Duration]));
end;

end.
