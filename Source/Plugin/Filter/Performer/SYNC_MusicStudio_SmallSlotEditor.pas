unit SYNC_MusicStudio_SmallSlotEditor;

// 小型スロットの候補メニューとアニメーションの直接配置/種類変更を担当する。PSD候補は作品の解析結果を使う。
// Document/View/Commitは借用。メニューは自身で所有し、モデルの確定は既存作品Undo境界へ返す。
interface
uses System.Classes, System.Types, System.SysUtils, Vcl.Menus,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary;
type
  TMusicStudioSmallSlotEditor = class(TComponent)
  private
    FView: TMusicStudioArrangementView;
    FDocument: TMusicStudioDocument;
    FStore: TMusicStudioSharedPsdLibrary;
    FCommit: TFunc<Boolean>;
    FTrack,FSlot,FClip: Integer;
    FStart: Double;
    FChoices: TArray<string>;
    procedure CustomClick(Sender: TObject);
    procedure Choose(Sender: TObject);
    procedure Delete(Sender: TObject);
  public
    Menu: TPopupMenu;
    property Store: TMusicStudioSharedPsdLibrary read FStore write FStore;
    procedure CreateAnimation(TrackIndex,SlotIndex: Integer; StartSeconds,LengthSeconds: Double);
    procedure EditCustomAt(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double);
    constructor Create(AOwner: TComponent; View: TMusicStudioArrangementView; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>); reintroduce;
    // Prepareはメニュー構築のみ。クリックされるまで文書を変更しない。
    function Prepare(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double): Boolean;
    procedure ShowMenu(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
  end;
implementation
uses System.Math, System.UITypes, System.JSON, Vcl.Forms, SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig, Vcl.Dialogs, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_SmallSlotData, SYNC_MusicStudio_MotionData;
constructor TMusicStudioSmallSlotEditor.Create(AOwner: TComponent; View: TMusicStudioArrangementView; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>);
begin inherited Create(AOwner); FView := View; FDocument := Document; FCommit := Commit; Menu := TPopupMenu.Create(Self); end;
function TMusicStudioSmallSlotEditor.Prepare(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double): Boolean;
var T: TMusicStudioTrack; S: TMusicStudioSlot; Parent,Item: TMenuItem; I,J: Integer; P: TMusicStudioPattern; Motion: TMusicStudioMotionConfig;
  procedure Add(const Caption: string; Tag: Integer);
  begin Item := TMenuItem.Create(Menu); Item.Caption := Caption; Item.Tag := Tag; Item.OnClick := Choose; Parent.Add(Item); end;
begin
  Result := False; Menu.Items.Clear;
  if (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) then Exit;
  T := FDocument.TrackAt(TrackIndex); if (SlotIndex<0) or (SlotIndex>=Length(T.Slots)) then Exit;
  S := T.Slots[SlotIndex]; if not MusicStudioSmallSlot(S.Kind) and (S.Kind<>'customExpression') and (MusicStudioAnimationSource(S.Kind)='') then Exit;
  if (ClipIndex < -1) or (ClipIndex>=Length(S.Clips)) then Exit;
  FTrack := TrackIndex; FSlot := SlotIndex; FClip := ClipIndex;
  FStart := FView.SnapSecondsForSlot(Seconds,TrackIndex,SlotIndex); FChoices := Copy(S.Choices);
  if MusicStudioAnimationSource(S.Kind)<>'' then begin
    if ClipIndex<0 then Exit;
    Motion := TMusicStudioMotionConfig.Create;
    try
      Motion.RhythmType := rmtBounce;
      for J := 0 to FDocument.PatternCount-1 do begin
        P := FDocument.PatternAt(J);
        if (P.ID=S.Clips[ClipIndex].PatternID) and (P.ConfigJSON<>'') then Motion.LoadJSON(P.ConfigJSON);
      end;
      for I := Ord(Low(TMusicStudioRhythmType)) to Ord(High(TMusicStudioRhythmType)) do begin
        Item := TMenuItem.Create(Menu); Item.Caption := MusicStudioRhythmCaption(TMusicStudioRhythmType(I));
        if I=Ord(rmtBounce) then Item.Caption := '縮み・伸び';
        Item.Tag := I; Item.RadioItem := True; Item.Checked := I=Ord(Motion.RhythmType); Item.OnClick := Choose; Menu.Items.Add(Item);
      end;
      Item := TMenuItem.Create(Menu); Item.Caption := '-'; Menu.Items.Add(Item);
      Item := TMenuItem.Create(Menu); Item.Caption := '削除'; Item.OnClick := Delete; Menu.Items.Add(Item);
    finally Motion.Free; end;
    Exit(True);
  end;
  if S.Kind='customExpression' then begin
    Item := TMenuItem.Create(Menu); if ClipIndex<0 then Item.Caption := '表情を追加…' else Item.Caption := '表情を編集…';
    Item.OnClick := CustomClick; Menu.Items.Add(Item);
    if ClipIndex>=0 then begin Item := TMenuItem.Create(Menu); Item.Caption := 'この配置を削除'; Item.OnClick := Delete; Menu.Items.Add(Item); end;
    Exit(True);
  end;
  Parent := TMenuItem.Create(Menu); if ClipIndex<0 then Parent.Caption := '追加' else Parent.Caption := '変更'; Menu.Items.Add(Parent);
  Add('通常（PSD初期状態）',-1);
  for I := 0 to High(FChoices) do Add(FChoices[I],I);
  if S.Kind='symbol' then Add('非表示',-2);
  if ClipIndex>=0 then begin Item := TMenuItem.Create(Menu); Item.Caption := '削除'; Item.OnClick := Delete; Menu.Items.Add(Item); end;
  Result := True;
end;
procedure TMusicStudioSmallSlotEditor.ShowMenu(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
begin if Prepare(TrackIndex,SlotIndex,ClipIndex,Seconds) then Menu.Popup(ScreenPoint.X,ScreenPoint.Y); end;
procedure TMusicStudioSmallSlotEditor.CreateAnimation(TrackIndex,SlotIndex: Integer; StartSeconds,LengthSeconds: Double);
begin
  FDocument.WriteAnimationElement(TrackIndex,SlotIndex,-1,Ord(rmtBounce),StartSeconds,LengthSeconds);
  if FCommit() then FView.SelectClip(TrackIndex,SlotIndex,High(FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Clips));
end;
procedure TMusicStudioSmallSlotEditor.EditCustomAt(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double);
begin if Prepare(TrackIndex,SlotIndex,ClipIndex,Seconds) then CustomClick(nil); end;
procedure TMusicStudioSmallSlotEditor.CustomClick(Sender: TObject);
var D: TMusicStudioPatternSettings; A: TMusicStudioPsdAsset; P: TMusicStudioPattern;
  Error,OldID,Before: string; I,Index: Integer; Config,Vis: TJSONObject; Layer: TMusicStudioLayerInfo;
begin
  if (FStore=nil) or not FStore.TryRead(FDocument.TrackAt(FTrack).PsdAssetID,A,Error) then Exit;
  P := Default(TMusicStudioPattern); P.Kind := 'emotion'; P.AssetID := A.ID; P.Name := '表情カスタム';
  P.Color := FDocument.TrackAt(FTrack).Slots[FSlot].Color; P.ConfigJSON := A.ConfigJSON; OldID := '';
  if FClip>=0 then begin
    OldID := FDocument.TrackAt(FTrack).Slots[FSlot].Clips[FClip].PatternID;
    for I := 0 to FDocument.PatternCount-1 do if FDocument.PatternAt(I).ID=OldID then P := FDocument.PatternAt(I);
  end;
  D := TMusicStudioPatternSettings.Create(Self);
  try
    if (P.SharedPatternID<>'') then for I := 0 to High(A.Patterns) do if A.Patterns[I].ID=P.SharedPatternID then P.ConfigJSON := A.Patterns[I].ConfigJSON;
    P.SharedPatternID := ''; D.SilentVisualMode := True; D.LoadSharedPattern(P,A.FilePath,A.ConfigJSON);
    if D.ShowModal<>mrOK then Exit; D.ReadSharedPattern(P);
    Config := ParseMusicStudioPsdConfig(P.ConfigJSON);
    try
      Vis := MusicStudioPsdConfigObject(Config,'visibility');
      if D.LayersFrame.Document<>nil then for Layer in D.LayersFrame.Document.Layers do
        if Vis.GetValue(Layer.Key)=nil then Vis.AddPair(Layer.Key,TJSONBool.Create(Layer.Visible));
      P.ConfigJSON := Config.ToJSON;
    finally Config.Free; end;
    if not FDocument.TrySave(Before,Error) then raise Exception.Create(Error);
    try
    Index := FDocument.AddCustomExpression(P); P := FDocument.PatternAt(Index);
    if FClip>=0 then FDocument.ReplacePlacementPattern(FTrack,FSlot,FClip,P.ID)
    else if not FDocument.AddPlacement(FTrack,FSlot,P.ID,FStart,Min(4.0,604800-FStart),Error) then raise Exception.Create(Error);
    if OldID<>'' then for I := FDocument.PatternCount-1 downto 0 do
      if (FDocument.PatternAt(I).ID=OldID) and (FDocument.PatternAt(I).SharedPatternID='') and
        (FDocument.PatternAt(I).ConfigJSON<>'') and not FDocument.PatternInUse(OldID) then FDocument.RemovePattern(I);
    if FCommit() then FView.SelectSlot(FTrack,FSlot);
    except on E: Exception do begin FDocument.TryLoad(Before,Error); raise; end; end;
  finally D.Free; end;
end;
procedure TMusicStudioSmallSlotEditor.Choose(Sender: TObject);
var Mode,Choice: string; Tag: Integer;
begin
  if MusicStudioAnimationSource(FDocument.TrackAt(FTrack).Slots[FSlot].Kind)<>'' then begin
    with FDocument.TrackAt(FTrack).Slots[FSlot].Clips[FClip] do
      FDocument.WriteAnimationElement(FTrack,FSlot,FClip,TMenuItem(Sender).Tag,StartSeconds,LengthSeconds);
    if FCommit() then FView.SelectClip(FTrack,FSlot,FClip); Exit;
  end;
  Tag := TMenuItem(Sender).Tag; Mode := 'choice'; Choice := '';
  if Tag=-1 then Mode := 'default' else if Tag=-2 then Mode := 'hidden'
  else if (Tag>=0) and (Tag<Length(FChoices)) then Choice := FChoices[Tag] else Exit;
  try
    FDocument.WriteSmallElement(FTrack,FSlot,FClip,Mode,Choice,FStart,Min(4.0,604800-FStart));
    if FCommit() then begin
      if FClip<0 then FClip := High(FDocument.TrackAt(FTrack).Slots[FSlot].Clips);
      FView.SelectClip(FTrack,FSlot,FClip);
    end;
  except on E: Exception do MessageDlg(E.Message,mtWarning,[mbOK],0); end;
end;
procedure TMusicStudioSmallSlotEditor.Delete(Sender: TObject);
begin
  if FClip<0 then Exit;
  FDocument.RemovePlacement(FTrack,FSlot,FClip); if FCommit() then FView.SelectSlot(FTrack,FSlot);
end;
end.
