unit SYNC_MusicStudio_SlotFrame;

// スロット固有UI。受入属性を編集し、名前/色/確定は共通枠に任せる。
interface
uses System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, SYNC_MusicStudio_ArrangementData;
type
  TMusicStudioSlotFrame = class(TFrame)
  private
    FExtraAccepts: TArray<string>;
    FKindLabel, FHelpLabel: TLabel;
    procedure BuildUI;
  protected
    procedure Resize; override;
    procedure SetParent(AParent: TWinControl); override;
  public
    AudioCheck, SingingCheck, PerformanceCheck, EmotionCheck, RhythmCheck: TCheckBox;
    PsdCheck, AnimationCheck, InstrumentCheck: TCheckBox;
    TempoCheck: TCheckBox;
    constructor Create(AOwner: TComponent); override;
    procedure LoadSlot(const Slot: TMusicStudioSlot);
    function SelectedAccepts: TArray<string>;
  end;
implementation
uses Winapi.Windows, System.SysUtils, System.Math, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
{$R *.dfm}
const
  SlotHelpText = '配置の適合性はこの受入属性で判定します。トラックの種類には固定しません。'+
    '既存配置が使う属性は、その配置を削除するまで解除できません。';
constructor TMusicStudioSlotFrame.Create(AOwner: TComponent);
begin
  inherited; ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
end;
procedure TMusicStudioSlotFrame.BuildUI;
  function CheckAt(Y: Integer; const Text: string): TCheckBox;
  begin
    Result := TCheckBox.Create(Self); Result.Parent := Self;
    Result.SetBounds(24,Y,Width-48,26); Result.Anchors := [akLeft,akTop,akRight]; Result.Caption := Text;
  end;
begin
  FKindLabel := TLabel.Create(Self); FKindLabel.Parent := Self; FKindLabel.SetBounds(24,14,Width-48,26);
  FKindLabel.AutoSize := False; FKindLabel.Anchors := [akLeft,akTop,akRight];
  AudioCheck := CheckAt(56,'オーディオクリップ');
  SingingCheck := CheckAt(92,'歌唱 / 口パク用MIDI');
  PerformanceCheck := CheckAt(128,'演奏（拍・ピアノロール）');
  InstrumentCheck := CheckAt(164,'楽器の姿勢');
  PsdCheck := CheckAt(56,'共有PSDの割当');
  EmotionCheck := CheckAt(92,'表情');
  AnimationCheck := CheckAt(128,'アニメーション');
  RhythmCheck := CheckAt(164,'リズム同期（予約・未対応）');
  TempoCheck := CheckAt(200,'テンポ（曲全体へ適用）');
  FHelpLabel := TLabel.Create(Self); FHelpLabel.Parent := Self;
  FHelpLabel.SetBounds(24,244,Width-48,92); FHelpLabel.AutoSize := False; FHelpLabel.WordWrap := True;
  FHelpLabel.Anchors := [akLeft,akTop,akRight];
  FHelpLabel.Caption := SlotHelpText;
  Resize;
end;
procedure TMusicStudioSlotFrame.SetParent(AParent: TWinControl);
begin
  inherited;
  if AParent<>nil then begin if FKindLabel=nil then BuildUI; Resize; end;
end;
procedure TMusicStudioSlotFrame.Resize;
var W,X,H,Margin: Integer;
  function Scaled(Value: Integer): Integer;
  begin Result := MulDiv(Value,CurrentPPI,96); end;
begin
  inherited;
  // 倍率変更と最小幅の両方で、説明文の折返しを実際のクライアント幅へ合わせる。
  if Assigned(FHelpLabel) then FHelpLabel.Width := Max(1,ClientWidth-2*FHelpLabel.Left);
  if not Assigned(PsdCheck) or (Parent=nil) then Exit;
  Margin := Scaled(24); H := Scaled(26); W := Max(1,(ClientWidth-Scaled(60)) div 2); X := Scaled(36)+W;
  AudioCheck.SetBounds(Margin,Scaled(56),W,H); SingingCheck.SetBounds(Margin,Scaled(92),W,H);
  PerformanceCheck.SetBounds(Margin,Scaled(128),W,H); InstrumentCheck.SetBounds(Margin,Scaled(164),W,H);
  PsdCheck.SetBounds(X,Scaled(56),W,H); EmotionCheck.SetBounds(X,Scaled(92),W,H);
  AnimationCheck.SetBounds(X,Scaled(128),W,H); RhythmCheck.SetBounds(X,Scaled(164),W,H);
  TempoCheck.SetBounds(Margin,Scaled(200),W,H);
end;
procedure TMusicStudioSlotFrame.LoadSlot(const Slot: TMusicStudioSlot);
var Kind: string;
begin
  FKindLabel.Caption := 'スロット種別: '+MusicStudioSlotKindName(Slot.Kind);
  AudioCheck.Checked := False; SingingCheck.Checked := False; PerformanceCheck.Checked := False;
  EmotionCheck.Checked := False; RhythmCheck.Checked := False;
  TempoCheck.Checked := False;
  PsdCheck.Checked := False; AnimationCheck.Checked := False; InstrumentCheck.Checked := False; FExtraAccepts := nil;
  for Kind in Slot.Accepts do begin
    if Kind = 'audio' then AudioCheck.Checked := True else if Kind = 'singing' then SingingCheck.Checked := True
    else if Kind = 'performance' then PerformanceCheck.Checked := True else if Kind = 'emotion' then EmotionCheck.Checked := True
    else if Kind='tempo' then TempoCheck.Checked := True
    else if Kind = 'rhythm' then RhythmCheck.Checked := True else if Kind='psd' then PsdCheck.Checked := True
    else if Kind='animation' then AnimationCheck.Checked := True else if Kind='instrument' then InstrumentCheck.Checked := True
    else FExtraAccepts := FExtraAccepts + [Kind];
  end;
  FHelpLabel.Caption := SlotHelpText;
  if Length(FExtraAccepts) > 0 then FHelpLabel.Caption := FHelpLabel.Caption +
    ' 未対応の受入属性を保持: '+string.Join(', ',FExtraAccepts);
end;
function TMusicStudioSlotFrame.SelectedAccepts: TArray<string>;
begin
  Result := Copy(FExtraAccepts);
  if AudioCheck.Checked then Result := Result + ['audio'];
  if SingingCheck.Checked then Result := Result + ['singing'];
  if PerformanceCheck.Checked then Result := Result + ['performance'];
  if EmotionCheck.Checked then Result := Result + ['emotion'];
  if RhythmCheck.Checked then Result := Result + ['rhythm'];
  if PsdCheck.Checked then Result := Result + ['psd'];
  if AnimationCheck.Checked then Result := Result + ['animation'];
  if InstrumentCheck.Checked then Result := Result + ['instrument'];
  if TempoCheck.Checked then Result := Result + ['tempo'];
end;
end.
