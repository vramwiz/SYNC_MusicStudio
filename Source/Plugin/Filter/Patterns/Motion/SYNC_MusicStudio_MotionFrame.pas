unit SYNC_MusicStudio_MotionFrame;

// PSD専用アニメーション設定UI。共通の名前・色・確定は外側が担当する。
// 入力画像を複製して保持し、時計も画像処理もこのフレーム内で完結する無音プレビュー。
interface

uses System.Classes, System.JSON, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics, SYNC_MusicStudio_MotionData;

type
  TMusicStudioMotionFrame = class(TFrame)
  private
    FConfig: TMusicStudioMotionConfig;
    FSource, FRendered: TBitmap;
    FPreview: TPaintBox;
    FTimer: TTimer;
    FPlayButton: TButton;
    FTypeCombo: TComboBox;
    FEdits: array[0..8] of TEdit;
    FTempoEdit: TEdit;
    FBeatBar: TTrackBar;
    FState, FBeatLabel: TLabel;
    FUpdating, FPlaying: Boolean;
    FTempoBPM, FBeat, FStartBeat: Double;
    FStartTick: UInt64;
    FSourceRevision, FConfigRevision, FRenderedSource, FRenderedConfig: Integer;
    FRenderedBeat: Double;
    FRenderCount: Integer;
    FConfigError: string;
    FOnChange: TNotifyEvent;
    procedure BuildUI;
    procedure ControlsChanged(Sender: TObject);
    procedure TempoChanged(Sender: TObject);
    procedure BeatChanged(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure ShowConfig;
    procedure RenderPreview;
    procedure SetPreviewTempoBPM(Value: Double);
    procedure SetPreviewBeatPosition(Value: Double);
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadMotion(const ConfigJSON: string); overload;
    procedure LoadMotion(ConfigJSON: TJSONObject); overload;
    function ConfigJSON: string;
    // 呼出側のBitmapは変更・解放しない。参照解除はnilを渡す。
    procedure PreviewBitmap(Bitmap: TBitmap);
    procedure StartSilentPreview;
    procedure StopSilentPreview;
    property PreviewTempoBPM: Double read FTempoBPM write SetPreviewTempoBPM;
    property PreviewBeatPosition: Double read FBeat write SetPreviewBeatPosition;
    property IsPreviewing: Boolean read FPlaying;
    property RenderCount: Integer read FRenderCount;
    property RenderedBitmap: TBitmap read FRendered;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses System.SysUtils, System.Math, System.Types,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

{$R *.dfm}

function DisplayNumber(Value: Double): string;
begin Result := FloatToStr(Value,TFormatSettings.Invariant); end;

function ReadNumber(Edit: TEdit; const Name: string): Double;
begin
  if not TryStrToFloat(Trim(Edit.Text),Result,TFormatSettings.Invariant) and
    not TryStrToFloat(Trim(Edit.Text),Result) then
    raise EArgumentException.Create(Name + ' は数値で入力してください。');
end;

constructor TMusicStudioMotionFrame.Create(AOwner: TComponent);
begin
  inherited;
  FConfig := TMusicStudioMotionConfig.Create;
  FSource := TBitmap.Create; FRendered := TBitmap.Create;
  FRenderedSource := -1; FRenderedConfig := -1; FRenderedBeat := -1;
  FTempoBPM := 120;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;

destructor TMusicStudioMotionFrame.Destroy;
begin
  if FTimer <> nil then begin FTimer.Enabled := False; FTimer.OnTimer := nil; end;
  FSource.Free; FRendered.Free; FConfig.Free;
  inherited;
end;

procedure TMusicStudioMotionFrame.SetParent(AParent: TWinControl);
var Component: TComponent;
begin
  inherited;
  if (AParent = nil) or (FConfig = nil) then Exit;
  if FPreview = nil then begin
    FUpdating := True;
    try BuildUI; finally FUpdating := False; end;
    ShowConfig;
    FUpdating := True;
    try
      FTempoEdit.Text := DisplayNumber(FTempoBPM);
      FBeatBar.Position := EnsureRange(Round(FBeat*100),0,400);
    finally FUpdating := False; end;
    if not FSource.Empty then FState.Caption := '対象画像だけを変形します。音声は起動しません。';
    RenderPreview;
  end;
  for Component in Self do
    if Component is TButton then ApplySyncMusicStudioDarkButton(TButton(Component));
end;

procedure TMusicStudioMotionFrame.BuildUI;
const Captions: array[0..8] of string =
  ('強さ（px / %）','速さ','腰位置（0～100）','柔らかさ（0～100）',
   '拍ずらし','X移動（px）','Y移動（px）','拡大率（%）','回転（度）');
var Settings: TScrollBox; PreviewPanel, Header, Footer: TPanel; L: TLabel;
  I,Y: Integer; Kind: TMusicStudioRhythmType;
begin
  Settings := TScrollBox.Create(Self); Settings.Parent := Self; Settings.Align := alLeft;
  Settings.Width := 228; Settings.BorderStyle := bsNone; Settings.Color := $00282828;
  Settings.ParentColor := False; Settings.HorzScrollBar.Visible := False;
  L := TLabel.Create(Self); L.Parent := Settings; L.SetBounds(12,8,200,20);
  L.Caption := 'リズム変形';
  FTypeCombo := TComboBox.Create(Self); FTypeCombo.Parent := Settings;
  FTypeCombo.SetBounds(12,32,192,26); FTypeCombo.Style := csDropDownList;
  FTypeCombo.Color := $002E2E2E; FTypeCombo.Font.Color := $00E3E3E3;
  for Kind := Low(Kind) to High(Kind) do FTypeCombo.Items.Add(MusicStudioRhythmCaption(Kind));
  FTypeCombo.OnChange := ControlsChanged;
  Y := 70;
  for I := 0 to High(FEdits) do begin
    L := TLabel.Create(Self); L.Parent := Settings; L.SetBounds(12,Y+4,130,20);
    L.Caption := Captions[I];
    FEdits[I] := TEdit.Create(Self); FEdits[I].Parent := Settings;
    FEdits[I].SetBounds(144,Y,60,26); FEdits[I].MaxLength := 16;
    ApplySyncMusicStudioDarkEdit(FEdits[I]); FEdits[I].OnChange := ControlsChanged;
    Inc(Y,38);
  end;
  L := TLabel.Create(Self); L.Parent := Settings; L.SetBounds(12,Y,192,62);
  L.AutoSize := False; L.WordWrap := True;
  L.Caption := '腰位置・柔らかさは振り子とステップに使用。端から出た部分は透明になります。';
  PreviewPanel := TPanel.Create(Self); PreviewPanel.Parent := Self; PreviewPanel.Align := alClient;
  PreviewPanel.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(PreviewPanel);
  Header := TPanel.Create(Self); Header.Parent := PreviewPanel; Header.Align := alTop;
  Header.Height := 70; Header.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Header);
  FPlayButton := TMusicStudioButton.Create(Self); FPlayButton.Parent := Header;
  FPlayButton.SetBounds(12,8,142,30); FPlayButton.Caption := '無音プレビュー';
  FPlayButton.OnClick := PlayClick; ApplySyncMusicStudioDarkButton(FPlayButton);
  L := TLabel.Create(Self); L.Parent := Header; L.SetBounds(166,14,82,20); L.Caption := '確認用 BPM';
  FTempoEdit := TEdit.Create(Self); FTempoEdit.Parent := Header;
  FTempoEdit.SetBounds(250,10,64,26); FTempoEdit.Text := '120';
  ApplySyncMusicStudioDarkEdit(FTempoEdit); FTempoEdit.OnChange := TempoChanged;
  FBeatLabel := TLabel.Create(Self); FBeatLabel.Parent := Header;
  FBeatLabel.SetBounds(12,45,400,20); FBeatLabel.Caption := '0.00 拍';
  Footer := TPanel.Create(Self); Footer.Parent := PreviewPanel; Footer.Align := alBottom;
  Footer.Height := 76; Footer.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(Footer);
  FBeatBar := TTrackBar.Create(Self); FBeatBar.Parent := Footer;
  FBeatBar.Align := alTop; FBeatBar.Height := 30; FBeatBar.Min := 0; FBeatBar.Max := 400;
  FBeatBar.TickStyle := tsNone; FBeatBar.OnChange := BeatChanged;
  FState := TLabel.Create(Self); FState.Parent := Footer; FState.Align := alClient;
  FState.AutoSize := False; FState.WordWrap := True;
  FState.Caption := 'PSD画像が未指定です。プレビューは画像だけを動かし、音声を起動しません。';
  FPreview := TPaintBox.Create(Self); FPreview.Parent := PreviewPanel; FPreview.Align := alClient;
  FPreview.OnPaint := PreviewPaint;
  FTimer := TTimer.Create(Self); FTimer.Interval := 40; FTimer.Enabled := False; FTimer.OnTimer := Tick;
end;

procedure TMusicStudioMotionFrame.ShowConfig;
begin
  if FTypeCombo = nil then Exit;
  FUpdating := True;
  try
    FTypeCombo.ItemIndex := Ord(FConfig.RhythmType);
    FEdits[0].Text := DisplayNumber(FConfig.Strength); FEdits[1].Text := DisplayNumber(FConfig.Speed);
    FEdits[2].Text := DisplayNumber(FConfig.Param1); FEdits[3].Text := DisplayNumber(FConfig.Param2);
    FEdits[4].Text := DisplayNumber(FConfig.ShiftBeats); FEdits[5].Text := DisplayNumber(FConfig.OffsetX);
    FEdits[6].Text := DisplayNumber(FConfig.OffsetY); FEdits[7].Text := DisplayNumber(FConfig.ScalePercent);
    FEdits[8].Text := DisplayNumber(FConfig.RotationDegrees);
  finally FUpdating := False; end;
end;

procedure TMusicStudioMotionFrame.ControlsChanged(Sender: TObject);
var Candidate: TMusicStudioMotionConfig; PreviousJSON: string;
begin
  if FUpdating then Exit;
  Candidate := TMusicStudioMotionConfig.Create;
  try
    try
      PreviousJSON := FConfig.ToJSON; Candidate.LoadJSON(PreviousJSON);
      if FTypeCombo.ItemIndex < 0 then Exit;
      Candidate.RhythmType := TMusicStudioRhythmType(FTypeCombo.ItemIndex);
      Candidate.Strength := ReadNumber(FEdits[0],'強さ'); Candidate.Speed := ReadNumber(FEdits[1],'速さ');
      Candidate.Param1 := ReadNumber(FEdits[2],'腰位置'); Candidate.Param2 := ReadNumber(FEdits[3],'柔らかさ');
      Candidate.ShiftBeats := ReadNumber(FEdits[4],'拍ずらし'); Candidate.OffsetX := ReadNumber(FEdits[5],'X移動');
      Candidate.OffsetY := ReadNumber(FEdits[6],'Y移動'); Candidate.ScalePercent := ReadNumber(FEdits[7],'拡大率');
      Candidate.RotationDegrees := ReadNumber(FEdits[8],'回転'); Candidate.Validate;
      FConfigError := '';
      if PreviousJSON <> Candidate.ToJSON then begin
        FConfig.LoadJSON(Candidate.ToJSON); Inc(FConfigRevision);
        RenderPreview; if Assigned(FOnChange) then FOnChange(Self);
      end;
      FState.Font.Color := $00E3E3E3;
      if FSource.Empty then FState.Caption := 'PSD画像が未指定です。'
      else FState.Caption := '対象画像だけを変形します。音声は起動しません。';
    except on E: Exception do begin
      FConfigError := E.Message; FState.Caption := E.Message; FState.Font.Color := $0087A6FF;
    end; end;
  finally Candidate.Free; end;
end;

procedure TMusicStudioMotionFrame.LoadMotion(const ConfigJSON: string);
begin
  FConfig.LoadJSON(ConfigJSON); FConfigError := '';
  if FState <> nil then FState.Font.Color := $00E3E3E3;
  StopSilentPreview;
  Inc(FConfigRevision); ShowConfig; RenderPreview;
end;

procedure TMusicStudioMotionFrame.LoadMotion(ConfigJSON: TJSONObject);
begin
  if ConfigJSON = nil then LoadMotion('') else LoadMotion(ConfigJSON.ToJSON);
end;

function TMusicStudioMotionFrame.ConfigJSON: string;
begin
  // 編集中の不正値を直前の有効値へ黙って戻して確定しない。
  if FConfigError <> '' then raise EArgumentException.Create(FConfigError);
  Result := FConfig.ToJSON;
end;

procedure TMusicStudioMotionFrame.PreviewBitmap(Bitmap: TBitmap);
var Identity: TMusicStudioMotionTransform;
begin
  StopSilentPreview;
  if Bitmap = nil then begin FSource.SetSize(0,0);
    if FState <> nil then FState.Caption := 'PSD画像が未指定です。'; end
  else begin
    CalculateMusicStudioRhythmTransform(rmtNone,0,2,0,Identity);
    RenderMusicStudioMotion(Bitmap,FSource,Identity);
    if FState <> nil then FState.Caption := '対象画像だけを変形します。音声は起動しません。';
  end;
  Inc(FSourceRevision); RenderPreview;
end;

procedure TMusicStudioMotionFrame.RenderPreview;
var Transform: TMusicStudioMotionTransform;
begin
  if FBeatLabel <> nil then FBeatLabel.Caption := Format('%.2f 拍  ・  確認用テンポ %.2f BPM',[FBeat,FTempoBPM]);
  if FSource.Empty then begin FRendered.SetSize(0,0);
    if FPreview <> nil then FPreview.Invalidate; Exit; end;
  if (FRenderedSource = FSourceRevision) and (FRenderedConfig = FConfigRevision) and
    (FRenderedBeat = FBeat) then Exit;
  CalculateMusicStudioMotionTransform(FConfig,FBeat,Transform);
  RenderMusicStudioMotion(FSource,FRendered,Transform);
  FRenderedSource := FSourceRevision; FRenderedConfig := FConfigRevision; FRenderedBeat := FBeat;
  Inc(FRenderCount); if FPreview <> nil then FPreview.Invalidate;
end;

procedure TMusicStudioMotionFrame.PreviewPaint(Sender: TObject);
var X,Y,Cell,W,H: Integer; Scale: Double; R: TRect;
begin
  Cell := MulDiv(12,CurrentPPI,96);
  Cell := Max(1,Cell);
  for Y := 0 to FPreview.Height div Cell do
    for X := 0 to FPreview.Width div Cell do begin
      if Odd(X+Y) then FPreview.Canvas.Brush.Color := $002E2E2E
      else FPreview.Canvas.Brush.Color := $00252525;
      FPreview.Canvas.FillRect(Rect(X*Cell,Y*Cell,(X+1)*Cell,(Y+1)*Cell));
    end;
  if FRendered.Empty then Exit;
  Scale := Min((FPreview.Width-16)/FRendered.Width,(FPreview.Height-16)/FRendered.Height);
  if Scale <= 0 then Exit;
  W := Max(1,Round(FRendered.Width*Scale)); H := Max(1,Round(FRendered.Height*Scale));
  R := Rect((FPreview.Width-W) div 2,(FPreview.Height-H) div 2,
    (FPreview.Width+W) div 2,(FPreview.Height+H) div 2);
  FPreview.Canvas.StretchDraw(R,FRendered);
end;

procedure TMusicStudioMotionFrame.SetPreviewTempoBPM(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value < 1) or (Value > 999.99) then
    raise EArgumentException.Create('確認用BPMは1～999.99で指定してください。');
  FTempoBPM := Value;
  if FTempoEdit <> nil then begin
    FUpdating := True; try FTempoEdit.Text := DisplayNumber(Value); finally FUpdating := False; end;
  end;
  if FPlaying then begin FStartBeat := FBeat; FStartTick := GetTickCount64; end;
  RenderPreview;
end;

procedure TMusicStudioMotionFrame.TempoChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  try SetPreviewTempoBPM(ReadNumber(FTempoEdit,'確認用BPM'));
  except on E: Exception do begin StopSilentPreview; FState.Caption := E.Message; end; end;
end;

procedure TMusicStudioMotionFrame.SetPreviewBeatPosition(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Abs(Value) > 1000000) then
    raise EArgumentException.Create('確認用の拍位置が範囲外です。');
  FBeat := Value;
  if FBeatBar <> nil then begin
    FUpdating := True; try FBeatBar.Position := EnsureRange(Round(Value*100),0,400);
    finally FUpdating := False; end;
  end;
  if FPlaying then begin FStartBeat := FBeat; FStartTick := GetTickCount64; end;
  RenderPreview;
end;

procedure TMusicStudioMotionFrame.BeatChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  StopSilentPreview; SetPreviewBeatPosition(FBeatBar.Position/100.0);
end;

procedure TMusicStudioMotionFrame.StartSilentPreview;
begin
  if FTimer = nil then Exit;
  if FConfigError <> '' then begin FState.Caption := FConfigError; Exit; end;
  if FSource.Empty then begin FState.Caption := 'PSD画像を指定してください。'; Exit; end;
  FStartBeat := FBeat; FStartTick := GetTickCount64; FPlaying := True;
  FTimer.Enabled := True; FPlayButton.Caption := 'プレビュー停止';
end;

procedure TMusicStudioMotionFrame.StopSilentPreview;
begin
  FPlaying := False;
  if FTimer <> nil then FTimer.Enabled := False;
  if FPlayButton <> nil then FPlayButton.Caption := '無音プレビュー';
end;

procedure TMusicStudioMotionFrame.PlayClick(Sender: TObject);
begin if FPlaying then StopSilentPreview else StartSilentPreview; end;

procedure TMusicStudioMotionFrame.Tick(Sender: TObject);
begin
  if not FPlaying then Exit;
  if not Showing then begin StopSilentPreview; Exit; end;
  FBeat := FStartBeat+(GetTickCount64-FStartTick)*FTempoBPM/60000.0;
  RenderPreview;
end;

end.
