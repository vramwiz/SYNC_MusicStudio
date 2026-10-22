unit SYNC_MusicStudio_PatternSettingsForm;

// 属性共通の名前・色と確定/取消を担当する。属性専用フレームは共通枠の内側に配置する。
interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.Controls,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_AudioClipFrame, SYNC_MusicStudio_SingingFrame, SYNC_MusicStudio_PsdTrackFrame,
  SYNC_MusicStudio_SlotFrame, SYNC_MusicStudio_PsdLayersFrame, SYNC_MusicStudio_MotionFrame, SYNC_MusicStudio_PerformanceFrame,
  SYNC_MusicStudio_LayerStepFrame, SYNC_MusicStudio_TempoPatternFrame, SYNC_MusicStudio_DrumFrame;

type
  TMusicStudioPatternSettings = class(TForm)
  private
    FColorDialog: TColorDialog;
    FSwatch: TPanel;
    FOriginalName: string;
    FAttributeLabel: TLabel;
    FNameLabel: TLabel;
    FCommonPanel,FFooterPanel: TPanel;
    FColorLabel: TLabel;
    FColorButton,FOkButton,FCancelButton: TButton;
    FSourceTimer: TTimer;
    FSharedKind,FSourceKey: string;
    procedure SourceTimer(Sender: TObject);
    procedure PickColor(Sender: TObject);
    procedure ColorChanged(Sender: TObject);
    procedure SourceChanged(Sender: TObject);
    procedure AcceptClick(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditorHidden(Sender: TObject);
  protected
    procedure Resize; override;
  public
    SilentVisualMode: Boolean;
    NameEdit, ColorEdit: TEdit;
    AudioFrame: TMusicStudioAudioClipFrame;
    SingingFrame: TMusicStudioSingingFrame;
    PsdFrame: TMusicStudioPsdTrackFrame;
    SlotFrame: TMusicStudioSlotFrame;
    LayersFrame: TMusicStudioPsdLayersFrame;
    MotionFrame: TMusicStudioMotionFrame;
    PerformanceFrame: TMusicStudioPerformanceFrame;
    LayerStepFrame: TMusicStudioLayerStepFrame;
    TempoFrame: TMusicStudioTempoPatternFrame;
    DrumFrame: TMusicStudioDrumFrame;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadSharedPattern(const Pattern: TMusicStudioPattern; const Path,BaseConfig: string);
    procedure ReadSharedPattern(var Pattern: TMusicStudioPattern);
    procedure LoadPattern(const Pattern: TMusicStudioPattern);
    procedure LoadPerformanceSteps(const Pattern: TMusicStudioPattern; const AssetID,Path,BaseConfig: string; TempoBPM: Double; const TimingJSON: string = '');
    procedure ReadPattern(var Pattern: TMusicStudioPattern);
    procedure LoadTrack(const Track: TMusicStudioTrack);
    procedure ReadTrack(var Track: TMusicStudioTrack);
    procedure LoadSlot(const Slot: TMusicStudioSlot);
    procedure ReadSlot(var Slot: TMusicStudioSlot);
  end;

implementation

uses
  System.SysUtils, System.UITypes, System.Math, Winapi.Windows, Vcl.Graphics,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls, SYNC_MusicStudio_SingingData, SYNC_MusicStudio_DrumData;

{$R *.dfm}

function HexColor(const Value: string; out Color: TColor): Boolean;
var
  RGBValue: Integer;
  I: Integer;
begin
  Result := (Length(Value) = 7) and (Value[1] = '#');
  if not Result then Exit;
  for I := 2 to 7 do
    if not CharInSet(Value[I], ['0'..'9', 'a'..'f', 'A'..'F']) then Exit(False);
  Result := TryStrToInt('$' + Copy(Value, 2, 6), RGBValue);
  if Result then Color := ((RGBValue and $FF) shl 16) or (RGBValue and $FF00) or (RGBValue shr 16);
end;

constructor TMusicStudioPatternSettings.Create(AOwner: TComponent);
var
  CommonPanel, Footer: TPanel;
  LabelControl: TLabel;
  Button: TButton;
begin
  inherited;
  ApplySyncMusicStudioDarkForm(Self);
  ApplyMusicStudioEditorFont(Self);
  KeyPreview := True; OnKeyDown := EditorKeyDown; OnHide := EditorHidden;
  CommonPanel := TPanel.Create(Self);
  FCommonPanel := CommonPanel;
  CommonPanel.Parent := Self;
  CommonPanel.Align := alTop;
  CommonPanel.Height := 120;
  CommonPanel.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(CommonPanel);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := CommonPanel;
  LabelControl.SetBounds(16, 14, 140, 20);
  LabelControl.Caption := 'パターン名';
  FNameLabel := LabelControl;
  NameEdit := TEdit.Create(Self);
  NameEdit.Parent := CommonPanel;
  NameEdit.SetBounds(16, 40, 470, 26);
  NameEdit.Anchors := [akLeft, akTop, akRight];
  NameEdit.MaxLength := 200;
  ApplySyncMusicStudioDarkEdit(NameEdit);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := CommonPanel;
  LabelControl.SetBounds(510, 14, 160, 20);
  LabelControl.Anchors := [akTop, akRight];
  LabelControl.Caption := '色  (#RRGGBB)';
  FColorLabel := LabelControl;
  ColorEdit := TEdit.Create(Self);
  ColorEdit.Parent := CommonPanel;
  ColorEdit.SetBounds(510, 40, 112, 26);
  ColorEdit.Anchors := [akTop, akRight];
  ColorEdit.MaxLength := 7;
  ColorEdit.OnChange := ColorChanged;
  ApplySyncMusicStudioDarkEdit(ColorEdit);
  FSwatch := TPanel.Create(Self);
  FSwatch.Parent := CommonPanel;
  FSwatch.SetBounds(630, 40, 28, 26);
  FSwatch.Anchors := [akTop, akRight];
  FSwatch.ParentBackground := False;
  Button := TMusicStudioButton.Create(Self);
  Button.Parent := CommonPanel;
  Button.SetBounds(668, 39, 76, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := '色を選択';
  FColorButton := Button;
  Button.OnClick := PickColor;
  ApplySyncMusicStudioDarkButton(Button);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := CommonPanel;
  LabelControl.SetBounds(16, 84, 550, 20);
  FAttributeLabel := LabelControl;
  FAttributeLabel.AutoSize := False; FAttributeLabel.Anchors := [akLeft,akTop,akRight];
  Footer := TPanel.Create(Self);
  FFooterPanel := Footer;
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 56;
  Footer.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(Footer);
  Button := TMusicStudioButton.Create(Self);
  Button.Parent := Footer;
  Button.SetBounds(524, 14, 104, 30);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'OK';
  FOkButton := Button;
  Button.Default := True;
  Button.OnClick := AcceptClick;
  ApplySyncMusicStudioDarkButton(Button);
  Button := TMusicStudioButton.Create(Self);
  Button.Parent := Footer;
  Button.SetBounds(640, 14, 104, 30);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'キャンセル';
  FCancelButton := Button;
  Button.Cancel := True;
  Button.ModalResult := mrCancel;
  ApplySyncMusicStudioDarkButton(Button);
  FColorDialog := TColorDialog.Create(Self);
  FColorDialog.Options := [cdFullOpen];
  FSourceTimer := TTimer.Create(Self); FSourceTimer.Interval := 60; FSourceTimer.Enabled := False; FSourceTimer.OnTimer := SourceTimer;
end;

destructor TMusicStudioPatternSettings.Destroy;
begin
  if Assigned(FSourceTimer) then FSourceTimer.Enabled := False;
  inherited;
end;
procedure TMusicStudioPatternSettings.Resize;
var PPI,Margin,ColorX: Integer;
  procedure Place(C: TControl; X,Y,W,H: Integer);
  begin C.SetBounds(MulDiv(X,PPI,96),MulDiv(Y,PPI,96),MulDiv(W,PPI,96),MulDiv(H,PPI,96)); end;
begin
  inherited;
  if ((LayerStepFrame=nil) and (DrumFrame=nil)) or (FCommonPanel=nil) or (FFooterPanel=nil) then Exit;
  PPI := Max(CurrentPPI,MulDiv(Abs(Font.Height),96,13)); Margin := MulDiv(16,PPI,96);
  Constraints.MinWidth := MulDiv(860,PPI,96); Constraints.MinHeight := MulDiv(560,PPI,96);
  DisableAlign;
  try
    FCommonPanel.Height := MulDiv(112,PPI,96); FFooterPanel.Height := MulDiv(56,PPI,96);
    Place(FNameLabel,16,14,140,20);
    NameEdit.SetBounds(Margin,MulDiv(40,PPI,96),Max(MulDiv(140,PPI,96),ClientWidth-MulDiv(290,PPI,96)),MulDiv(26,PPI,96));
    ColorX := ClientWidth-MulDiv(250,PPI,96);
    FColorLabel.AutoSize := False; FColorLabel.SetBounds(ColorX,MulDiv(14,PPI,96),MulDiv(160,PPI,96),MulDiv(20,PPI,96));
    ColorEdit.SetBounds(ColorX,MulDiv(40,PPI,96),MulDiv(112,PPI,96),MulDiv(26,PPI,96));
    FSwatch.SetBounds(ClientWidth-MulDiv(130,PPI,96),MulDiv(40,PPI,96),MulDiv(28,PPI,96),MulDiv(26,PPI,96));
    FColorButton.SetBounds(ClientWidth-MulDiv(92,PPI,96),MulDiv(39,PPI,96),MulDiv(76,PPI,96),MulDiv(28,PPI,96));
    FAttributeLabel.SetBounds(Margin,MulDiv(80,PPI,96),Max(1,ClientWidth-2*Margin),MulDiv(24,PPI,96));
    FOkButton.SetBounds(ClientWidth-MulDiv(236,PPI,96),MulDiv(14,PPI,96),MulDiv(104,PPI,96),MulDiv(30,PPI,96));
    FCancelButton.SetBounds(ClientWidth-MulDiv(120,PPI,96),MulDiv(14,PPI,96),MulDiv(104,PPI,96),MulDiv(30,PPI,96));
  finally EnableAlign; end;
end;
procedure TMusicStudioPatternSettings.LoadSharedPattern(const Pattern: TMusicStudioPattern; const Path,BaseConfig: string);
var PPI: Integer;
begin
  FSharedKind := Pattern.Kind; FOriginalName := Pattern.Name; FSourceKey := '';
  NameEdit.Text := Pattern.Name; ColorEdit.Text := Pattern.Color;
  FSourceTimer.Enabled := False; FreeAndNil(DrumFrame); FreeAndNil(AudioFrame); FreeAndNil(SingingFrame); FreeAndNil(PsdFrame); FreeAndNil(SlotFrame); FreeAndNil(PerformanceFrame); FreeAndNil(LayerStepFrame); FreeAndNil(TempoFrame); FreeAndNil(LayersFrame); FreeAndNil(MotionFrame);
  FreeAndNil(LayersFrame); FreeAndNil(MotionFrame);
  Caption := MusicStudioSlotKindName(Pattern.Kind)+'設定';
  if Pattern.Kind='psd' then begin
    // Keep room for auditioning expressions even when the mouth toolbar wraps at a narrow width.
    PPI := Max(CurrentPPI,MulDiv(Abs(Font.Height),96,13));
    Constraints.MinHeight := Max(Constraints.MinHeight,MulDiv(640,PPI,96));
    Height := Max(Height,Constraints.MinHeight);
  end;
  FAttributeLabel.Caption := '共有PSD: 他の作品でも同じ設定を使います。作品への適用/取消とは独立して保存します。';
  if Pattern.Kind='instrument' then
    FAttributeLabel.Caption := '楽器の姿勢: 表示部位の設定を共有保存します。音符からの手・足の動作生成は未対応。';
  LayersFrame := TMusicStudioPsdLayersFrame.Create(Self); LayersFrame.Parent := Self; LayersFrame.Align := alClient;
  if Pattern.Kind='animation' then begin
    LayersFrame.Visible := False; LayersFrame.Align := alNone;
    LayersFrame.LoadPSD(Path,BaseConfig,False);
    MotionFrame := TMusicStudioMotionFrame.Create(Self); MotionFrame.Parent := Self; MotionFrame.Align := alClient;
    MotionFrame.LoadMotion(Pattern.ConfigJSON); FSourceTimer.Enabled := True;
  end else begin
    LayersFrame.LoadPSD(Path,Pattern.ConfigJSON,Pattern.Kind<>'psd');
    FSourceTimer.Enabled := False;
  end;
end;
procedure TMusicStudioPatternSettings.SourceTimer(Sender: TObject);
var Key: string;
begin
  if (MotionFrame=nil) or (LayersFrame=nil) then Exit;
  LayersFrame.PollResults;
  if LayersFrame.IsLoading or LayersFrame.IsRendering or (LayersFrame.PreviewBitmap=nil) then Exit;
  Key := IntToStr(LayersFrame.PreviewRenderCount)+':'+LayersFrame.ConfigJSON;
  if Key=FSourceKey then Exit;
  FSourceKey := Key; MotionFrame.PreviewBitmap(LayersFrame.PreviewBitmap);
end;
procedure TMusicStudioPatternSettings.ReadSharedPattern(var Pattern: TMusicStudioPattern);
begin
  if Assigned(PerformanceFrame) then Pattern.ConfigJSON := PerformanceFrame.ConfigJSON;
  Pattern.Name := Trim(NameEdit.Text); Pattern.Color := UpperCase(ColorEdit.Text);
  if Assigned(MotionFrame) then Pattern.ConfigJSON := MotionFrame.ConfigJSON
  else Pattern.ConfigJSON := LayersFrame.ConfigJSON;
end;
procedure TMusicStudioPatternSettings.LoadPattern(const Pattern: TMusicStudioPattern);
begin
  FOriginalName := Pattern.Name;
  FNameLabel.Caption := 'パターン名';
  NameEdit.Text := Pattern.Name;
  ColorEdit.Text := Pattern.Color;
  FSourceTimer.Enabled := False; FreeAndNil(DrumFrame); FreeAndNil(AudioFrame); FreeAndNil(SingingFrame); FreeAndNil(PsdFrame); FreeAndNil(SlotFrame); FreeAndNil(PerformanceFrame); FreeAndNil(LayerStepFrame); FreeAndNil(TempoFrame); FreeAndNil(LayersFrame); FreeAndNil(MotionFrame);
  if Pattern.Kind = 'audio' then begin
    FAttributeLabel.Caption := 'オーディオクリップ  ・  音源はファイル参照として保存';
    AudioFrame := TMusicStudioAudioClipFrame.Create(Self);
    AudioFrame.Parent := Self; AudioFrame.Align := alClient;
    AudioFrame.OnSourceChange := SourceChanged;
    AudioFrame.NoDecode := SilentVisualMode;
    AudioFrame.LoadAudio(Pattern.FilePath, Pattern.Volume);
  end
  else if Pattern.Kind = 'singing' then begin
    FAttributeLabel.Caption := '歌唱  ・  歌詞MIDIはファイル参照として保存';
    SingingFrame := TMusicStudioSingingFrame.Create(Self);
    SingingFrame.Parent := Self; SingingFrame.Align := alClient;
    SingingFrame.OnSourceChange := SourceChanged;
    SingingFrame.LoadSinging(Pattern.FilePath, Pattern.SourceTrack);
  end
  else if Pattern.Kind='performance' then begin
    if MusicStudioHasDrums(Pattern.ConfigJSON) then begin
      FAttributeLabel.Caption := 'ドラムパターン ・ 打点と下2行のバーを編集。時間軸クリックでシーク。表情・動作名は仮です。';
      DrumFrame := TMusicStudioDrumFrame.Create(Self); DrumFrame.Parent := Self; DrumFrame.Align := alClient;
      DrumFrame.Load(Pattern.ConfigJSON); ClientWidth := 1050; ClientHeight := 720; Resize;
      Exit;
    end;
    FAttributeLabel.Caption := '演奏は拍で編集します。Ctrl+ホイールで横ズームと拍スナップを変更、右クリックで音符削除。';
    PerformanceFrame := TMusicStudioPerformanceFrame.Create(Self); PerformanceFrame.Parent := Self; PerformanceFrame.Align := alClient;
    PerformanceFrame.LoadPerformance(Pattern.ConfigJSON);
  end
  else if Pattern.Kind='tempo' then begin
    FAttributeLabel.Caption := 'MIDI tempoを作品へ値コピー。tempo clipは曲全体に作用し、手動tempoより優先します。';
    TempoFrame := TMusicStudioTempoPatternFrame.Create(Self); TempoFrame.Parent := Self; TempoFrame.Align := alClient;
    TempoFrame.OnSourceChange := SourceChanged; TempoFrame.LoadTempo(Pattern.ConfigJSON);
  end
  else raise Exception.Create('この属性の設定UIは未実装です。');
end;

procedure TMusicStudioPatternSettings.LoadPerformanceSteps(const Pattern: TMusicStudioPattern;
  const AssetID,Path,BaseConfig: string; TempoBPM: Double; const TimingJSON: string);
begin
  LoadPattern(Pattern); FreeAndNil(PerformanceFrame);
  ClientWidth := 1050; ClientHeight := 780; Constraints.MinWidth := 860; Constraints.MinHeight := 560;
  FAttributeLabel.Caption := '小節クリック → チェックで設定。四角を移動/右端で長さ。空白ドラッグでパン、ホイールで拡縮。無音ループ。';
  FAttributeLabel.Top := 80; FAttributeLabel.Parent.Height := 104;
  LayerStepFrame := TMusicStudioLayerStepFrame.Create(Self); LayerStepFrame.Parent := Self; LayerStepFrame.Align := alClient;
  LayerStepFrame.LoadPerformance(Pattern.ConfigJSON,AssetID,Path,BaseConfig,TempoBPM,TimingJSON);
  Resize;
end;
procedure TMusicStudioPatternSettings.EditorKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if DrumFrame<>nil then begin
    if not ((ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox)) then DrumFrame.HandleKey(Key,Shift);
    Exit;
  end;
  if LayerStepFrame=nil then Exit;
  if (ActiveControl is TCustomEdit) and (ActiveControl<>LayerStepFrame.LengthEdit) and
    (ActiveControl<>LayerStepFrame.StepLengthEdit) then Exit;
  LayerStepFrame.HandleEditorKey(Key,Shift);
end;
procedure TMusicStudioPatternSettings.EditorHidden(Sender: TObject);
begin
  if LayerStepFrame<>nil then LayerStepFrame.Stop;
  if DrumFrame<>nil then DrumFrame.Stop;
end;
procedure TMusicStudioPatternSettings.LoadTrack(const Track: TMusicStudioTrack);
begin
  Caption := 'トラック設定'; FOriginalName := Track.Name;
  FNameLabel.Caption := 'トラック名';
  NameEdit.Text := Track.Name; ColorEdit.Text := Track.Color;
  FSourceTimer.Enabled := False; FreeAndNil(DrumFrame); FreeAndNil(AudioFrame); FreeAndNil(SingingFrame); FreeAndNil(PsdFrame); FreeAndNil(SlotFrame); FreeAndNil(PerformanceFrame); FreeAndNil(LayerStepFrame); FreeAndNil(TempoFrame); FreeAndNil(LayersFrame); FreeAndNil(MotionFrame);
  if Track.Kind = 'psd' then begin
    if Track.PsdAssetID<>'' then
      FAttributeLabel.Caption := '共有PSDを使用中。PSDスロットを選択すると素材と母音設定を編集できます。'
    else if Track.PsdPath='' then
      FAttributeLabel.Caption := 'PSDスロットへ左の共有PSDをドラッグして割り当てます。'
    else begin
      FAttributeLabel.Caption := '旧形式のPSD直接参照。共有PSDスロットへ登録素材を割り当てると移行できます。';
      PsdFrame := TMusicStudioPsdTrackFrame.Create(Self); PsdFrame.Parent := Self;
      PsdFrame.Align := alClient; PsdFrame.SelectFile(Track.PsdPath);
    end;
  end else FAttributeLabel.Caption := '音声トラック  ・  スロットごとに受入属性を設定';
end;

procedure TMusicStudioPatternSettings.LoadSlot(const Slot: TMusicStudioSlot);
begin
  Caption := 'スロット設定'; FOriginalName := Slot.Name; FNameLabel.Caption := 'スロット名';
  NameEdit.Text := Slot.Name; ColorEdit.Text := Slot.Color;
  FSourceTimer.Enabled := False; FreeAndNil(DrumFrame); FreeAndNil(AudioFrame); FreeAndNil(SingingFrame); FreeAndNil(PsdFrame); FreeAndNil(SlotFrame); FreeAndNil(PerformanceFrame); FreeAndNil(LayerStepFrame); FreeAndNil(TempoFrame); FreeAndNil(LayersFrame); FreeAndNil(MotionFrame);
  FAttributeLabel.Caption := 'スロットは独立した配置先です。受入属性は描画エンジンの実装状況とは別です。';
  SlotFrame := TMusicStudioSlotFrame.Create(Self); SlotFrame.Parent := Self; SlotFrame.Align := alClient;
  SlotFrame.LoadSlot(Slot);
end;
procedure TMusicStudioPatternSettings.ReadSlot(var Slot: TMusicStudioSlot);
begin
  Slot.Name := Trim(NameEdit.Text); Slot.Color := UpperCase(ColorEdit.Text);
  Slot.Accepts := SlotFrame.SelectedAccepts;
end;

procedure TMusicStudioPatternSettings.ReadTrack(var Track: TMusicStudioTrack);
begin
  Track.Name := Trim(NameEdit.Text); Track.Color := UpperCase(ColorEdit.Text);
  if Assigned(PsdFrame) then Track.PsdPath := PsdFrame.FilePath;
end;

procedure TMusicStudioPatternSettings.ReadPattern(var Pattern: TMusicStudioPattern);
begin
  if Assigned(DrumFrame) then Pattern.ConfigJSON := DrumFrame.ConfigJSON;
  if Assigned(PerformanceFrame) then Pattern.ConfigJSON := PerformanceFrame.ConfigJSON;
  if Assigned(LayerStepFrame) then Pattern.ConfigJSON := LayerStepFrame.ConfigJSON;
  if Assigned(TempoFrame) then Pattern.ConfigJSON := TempoFrame.ConfigJSON;
  Pattern.Name := Trim(NameEdit.Text);
  Pattern.Color := UpperCase(ColorEdit.Text);
  if Assigned(AudioFrame) then begin
    if (Pattern.FilePath <> AudioFrame.FilePath) or (AudioFrame.AudioInfo.Duration > 0) then
      Pattern.Duration := AudioFrame.AudioInfo.Duration;
    Pattern.FilePath := AudioFrame.FilePath;
    Pattern.Volume := AudioFrame.Volume;
  end;
  if Assigned(SingingFrame) then begin
    if (Pattern.FilePath <> SingingFrame.FilePath) or (Pattern.SourceTrack <> SingingFrame.SelectedTrack) or
      (SingingFrame.Source.Status in [ssReady,ssNoLyrics]) then
      Pattern.Duration := SingingFrame.SelectedDuration;
    Pattern.FilePath := SingingFrame.FilePath;
    Pattern.SourceTrack := SingingFrame.SelectedTrack;
  end;
end;

procedure TMusicStudioPatternSettings.SourceChanged(Sender: TObject);
begin
  if NameEdit.Text <> FOriginalName then Exit;
  if Assigned(TempoFrame) and (Pos('テンポ ',FOriginalName)=1) then NameEdit.Text := ChangeFileExt(ExtractFileName(TempoFrame.Data.FilePath),'');
  if Assigned(AudioFrame) and (Pos('オーディオクリップ ', FOriginalName) = 1) then
    NameEdit.Text := ChangeFileExt(ExtractFileName(AudioFrame.FilePath), '');
  if Assigned(SingingFrame) and (Pos('歌唱 ', FOriginalName) = 1) then
    NameEdit.Text := ChangeFileExt(ExtractFileName(SingingFrame.FilePath), '');
end;

procedure TMusicStudioPatternSettings.ColorChanged(Sender: TObject);
var
  Color: TColor;
begin
  if HexColor(ColorEdit.Text, Color) then FSwatch.Color := Color;
end;

procedure TMusicStudioPatternSettings.PickColor(Sender: TObject);
var
  Color: TColor;
  Value: Integer;
begin
  if HexColor(ColorEdit.Text, Color) then FColorDialog.Color := Color;
  if not FColorDialog.Execute then Exit;
  Value := ColorToRGB(FColorDialog.Color);
  ColorEdit.Text := Format('#%.2x%.2x%.2x', [Value and $FF, (Value shr 8) and $FF, (Value shr 16) and $FF]);
end;

procedure TMusicStudioPatternSettings.AcceptClick(Sender: TObject);
var
  Color: TColor;
begin
  if Assigned(PerformanceFrame) then try PerformanceFrame.ConfigJSON; except on E: Exception do begin FAttributeLabel.Caption := E.Message; Exit; end; end;
  if Assigned(LayerStepFrame) then try LayerStepFrame.ConfigJSON; except on E: Exception do begin FAttributeLabel.Caption := E.Message; Exit; end; end;
  if Assigned(TempoFrame) then try TempoFrame.ConfigJSON; except on E: Exception do begin FAttributeLabel.Caption := E.Message; Exit; end; end;
  if Assigned(LayersFrame) then begin
    if not LayersFrame.CanApply then begin FAttributeLabel.Caption := LayersFrame.StateText; Exit; end;
    if Assigned(MotionFrame) then try MotionFrame.ConfigJSON; except on E: Exception do begin FAttributeLabel.Caption := E.Message; Exit; end; end;
  end;
  if Assigned(SlotFrame) then if Length(SlotFrame.SelectedAccepts) = 0 then begin
    FAttributeLabel.Caption := '1つ以上の受入属性を選択してください。'; Exit;
  end;
  if (Assigned(AudioFrame) and AudioFrame.IsLoading) or (Assigned(SingingFrame) and SingingFrame.IsLoading) then begin
    FAttributeLabel.Caption := '読み込み中です。完了後にOKを押してください。取消はいつでもできます。'; Exit;
  end;
  if Assigned(SingingFrame) then
    if (SingingFrame.TrackCombo.Items.Count > 0) and (SingingFrame.TrackCombo.ItemIndex < 0) then begin
      FAttributeLabel.Caption := '保存済みのMIDIトラックがありません。利用するトラックを再選択してください。'; Exit;
    end;
  if Trim(NameEdit.Text) = '' then
  begin
    MessageDlg(FNameLabel.Caption + 'を入力してください。', mtWarning, [mbOK], 0);
    NameEdit.SetFocus;
    Exit;
  end;
  if not HexColor(ColorEdit.Text, Color) then
  begin
    MessageDlg('色を#RRGGBB形式で入力してください。', mtWarning, [mbOK], 0);
    ColorEdit.SetFocus;
    Exit;
  end;
  ModalResult := mrOK;
end;

end.
