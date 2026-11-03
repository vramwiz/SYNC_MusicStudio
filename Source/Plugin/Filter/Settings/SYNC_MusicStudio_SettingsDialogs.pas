unit SYNC_MusicStudio_SettingsDialogs;

// 統合編集の画面部品と補助ダイアログを構築する。作品の履歴・ホスト適用は所有しない。
// Owner/Document/Commitは借用し、各modalはfinallyで破棄する。おまかせ演奏は既存波形を借用する。
interface
uses System.Classes, System.SysUtils, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_WaveCache, SYNC_MusicStudio_SharedPsdLibrary;
// 返す部品はOwnerが所有する。Parentへ接続してダーク表示を設定する。
function MusicStudioPanel(Owner: TComponent; Parent: TWinControl; Align: TAlign; Size: Integer): TPanel;
function MusicStudioButton(Owner: TComponent; Parent: TWinControl; X,Y,Width: Integer; const Caption: string; Click: TNotifyEvent): TButton;
function MusicStudioLabelAt(Owner: TComponent; Parent: TWinControl; X,Y: Integer; const Caption: string): TLabel;
// Trueのときだけ正規化したJSONをTextへ返す。取消ではTextを保持し、Documentは変更しない。
function EditMusicStudioRawJSON(Owner: TForm; var Text: string): Boolean;
// 有効なtrack/slot/clip indexを受け、検証に成功した編集だけDocumentへ反映してCommitを呼ぶ。
// 入力不正は画面を維持し、取消は反映せず閉じる。共有PSDのmetadata/原本へは書き込まない。
procedure EditMusicStudioTrack(Owner: TComponent; Document: TMusicStudioDocument; Index: Integer; const Commit: TFunc<Boolean>);
procedure EditMusicStudioSlot(Owner: TComponent; Document: TMusicStudioDocument; TIndex,SIndex: Integer; const Commit: TFunc<Boolean>);
procedure EditMusicStudioPlacement(Owner: TComponent; Document: TMusicStudioDocument; TIndex,SIndex,CIndex: Integer; const Commit: TFunc<Boolean>);
procedure EditMusicStudioTiming(Owner: TComponent; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>);
function GenerateMusicStudioDrumPlacement(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  Cache: TMusicStudioWaveCache; TrackIndex, SlotIndex: Integer; Cursor: Double; const Commit: TFunc<Boolean>;
  out ErrorText: string): Boolean;
implementation
uses System.UITypes, System.Math, Vcl.Dialogs, SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_TimingFrame,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_PerformerEditor, SYNC_MusicStudio_AutoDrums,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_PsdLayers;
function MusicStudioPanel(Owner: TComponent; Parent: TWinControl; Align: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Owner);
  Result.Parent := Parent;
  Result.SetBounds(0, 0, Parent.ClientWidth, Parent.ClientHeight);
  if Align in [alLeft, alRight] then Result.Width := Size else Result.Height := Size;
  Result.Align := Align;
  Result.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(Result);
end;

function MusicStudioButton(Owner: TComponent; Parent: TWinControl; X, Y, Width: Integer;
  const Caption: string; Click: TNotifyEvent): TButton;
begin
  Result := TMusicStudioButton.Create(Owner);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, Width, 30);
  Result.Caption := Caption;
  Result.OnClick := Click;
  ApplySyncMusicStudioDarkButton(Result);
end;

function MusicStudioLabelAt(Owner: TComponent; Parent: TWinControl; X, Y: Integer;
  const Caption: string): TLabel;
begin
  Result := TLabel.Create(Owner);
  Result.Parent := Parent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := Caption;
end;


function EditMusicStudioRawJSON(Owner: TForm; var Text: string): Boolean;
var
  Dialog: TForm;
  Memo: TMemo;
  Footer: TPanel;
  Normalized, ErrorText: string;
begin
  Result := False;
  Dialog := TForm.CreateNew(Owner);
  try
    Dialog.Caption := '演奏スタジオ - JSON編集';
    Dialog.SetBounds(Owner.Left + 40, Owner.Top + 40, 880, 600);
    ApplySyncMusicStudioDarkForm(Dialog);
    ApplyMusicStudioEditorFont(Dialog);
    Footer := MusicStudioPanel(Dialog, Dialog, alBottom, 48);
    MusicStudioButton(Dialog, Footer, 12, 10, 140, '編集画面へ反映', nil).ModalResult := mrOK;
    MusicStudioButton(Dialog, Footer, 164, 10, 100, 'キャンセル', nil).ModalResult := mrCancel;
    Memo := TMemo.Create(Dialog);
    Memo.Parent := Dialog;
    Memo.Align := alClient;
    Memo.ScrollBars := ssBoth;
    Memo.WordWrap := False;
    Memo.Font.Name := 'Consolas';
    Memo.Text := Text;
    ApplySyncMusicStudioDarkMemo(Memo);
    while Dialog.ShowModal = mrOK do
    begin
      if TryNormalizeMusicStudioJSON(Memo.Text, Normalized, ErrorText) then
      begin
        Text := Normalized; Result := True;
        Break;
      end;
      MessageDlg(ErrorText, mtError, [mbOK], 0);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure EditMusicStudioTrack(Owner: TComponent; Document: TMusicStudioDocument; Index: Integer; const Commit: TFunc<Boolean>);
var T: TMusicStudioTrack; D: TMusicStudioPatternSettings;
begin
  T := Document.TrackAt(Index); if (T.Kind <> 'audio') and (T.Kind <> 'psd') then Exit;
  D := TMusicStudioPatternSettings.Create(Owner);
  try
    D.LoadTrack(T); if D.ShowModal <> mrOK then Exit; D.ReadTrack(T);
    if (T.Kind='psd') and not ChooseMusicStudioAttribute(Owner,T.PerformanceAttribute) then Exit;
    if T.Kind='psd' then Document.SetPerformer(Index,T.PerformanceAttribute,nil,False);
    Document.UpdateTrack(Index,T.Name,T.Color,T.PsdPath); Commit();
  finally D.Free; end;
end;

procedure EditMusicStudioSlot(Owner: TComponent; Document: TMusicStudioDocument; TIndex,SIndex: Integer; const Commit: TFunc<Boolean>);
var S: TMusicStudioSlot; D: TMusicStudioPatternSettings; ErrorText: string;
begin
  S := Document.TrackAt(TIndex).Slots[SIndex]; D := TMusicStudioPatternSettings.Create(Owner);
  try
    D.LoadSlot(S);
    while D.ShowModal = mrOK do begin
      D.ReadSlot(S);
      if Document.UpdateSlot(TIndex,SIndex,S.Name,S.Color,S.Accepts,ErrorText) then begin Commit(); Break; end;
      MessageDlg(ErrorText,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;
procedure EditMusicStudioPlacement(Owner: TComponent; Document: TMusicStudioDocument; TIndex,SIndex,CIndex: Integer; const Commit: TFunc<Boolean>);
var D: TForm; Footer: TPanel; StartEdit, LengthEdit: TEdit; C: TMusicStudioPlacement;
  StartValue, LengthValue, MaximumEnd: Double; FS: TFormatSettings; ErrorText: string;
begin
  C := Document.TrackAt(TIndex).Slots[SIndex].Clips[CIndex]; FS := TFormatSettings.Invariant;
  if C.TimeBase='beats' then MaximumEnd := 1000000 else MaximumEnd := 604800;
  D := TForm.CreateNew(Owner);
  try
    D.Caption := '配置の開始・長さ'; D.Position := poOwnerFormCenter;
    D.ClientWidth := 420; D.ClientHeight := 210; D.BorderStyle := bsDialog;
    ApplySyncMusicStudioDarkForm(D);
    if C.TimeBase='beats' then begin MusicStudioLabelAt(D,D,20,20,'開始 (拍)'); MusicStudioLabelAt(D,D,20,82,'長さ (拍)'); end
    else begin MusicStudioLabelAt(D,D,20,20,'開始 (秒)'); MusicStudioLabelAt(D,D,20,82,'長さ (秒)'); end;
    StartEdit := TEdit.Create(D); StartEdit.Parent := D; StartEdit.SetBounds(180,18,210,26);
    StartEdit.Text := FloatToStr(C.StartSeconds,FS); ApplySyncMusicStudioDarkEdit(StartEdit);
    LengthEdit := TEdit.Create(D); LengthEdit.Parent := D; LengthEdit.SetBounds(180,80,210,26);
    LengthEdit.Text := FloatToStr(C.LengthSeconds,FS); ApplySyncMusicStudioDarkEdit(LengthEdit);
    if C.TimeBase='beats' then begin StartEdit.Text := FloatToStr(C.StartBeat,FS); LengthEdit.Text := FloatToStr(C.LengthBeats,FS); end;
    Footer := MusicStudioPanel(D,D,alBottom,56);
    MusicStudioButton(D,Footer,164,12,100,'OK',nil).ModalResult := mrOK;
    MusicStudioButton(D,Footer,276,12,114,'キャンセル',nil).ModalResult := mrCancel;
    while D.ShowModal = mrOK do begin
      if TryStrToFloat(StartEdit.Text,StartValue,FS) and TryStrToFloat(LengthEdit.Text,LengthValue,FS) and
        (StartValue >= 0) and (LengthValue >= 0.001) and (StartValue + LengthValue <= MaximumEnd) then begin
        if C.TimeBase='beats' then begin
          if not Document.MoveBeatPlacement(TIndex,SIndex,CIndex,StartValue,LengthValue,ErrorText) then begin MessageDlg(ErrorText,mtWarning,[mbOK],0); Continue; end;
        end else Document.MovePlacement(TIndex,SIndex,CIndex,StartValue,LengthValue);
        Commit(); Break;
      end;
      if C.TimeBase='beats' then ErrorText := '開始は0以上、長さは0.001拍以上、終了は1000000拍以内で入力してください。'
      else ErrorText := '開始は0以上、長さは0.001秒以上、終了は604800秒以内で入力してください。';
      MessageDlg(ErrorText,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;

procedure EditMusicStudioTiming(Owner: TComponent; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>);
var D: TForm; Frame: TMusicStudioTimingFrame; Footer: TPanel; Error: string;
begin
  D := TForm.CreateNew(Owner);
  try
    D.Caption := 'テンポ / 拍子'; D.Position := poOwnerFormCenter; D.ClientWidth := 760; D.ClientHeight := 440;
    D.Constraints.MinWidth := 670; D.Constraints.MinHeight := 430;
    ApplySyncMusicStudioDarkForm(D); ApplyMusicStudioEditorFont(D);
    Footer := MusicStudioPanel(D,D,alBottom,60); MusicStudioButton(D,Footer,404,15,100,'OK',nil).ModalResult := mrOK;
    MusicStudioButton(D,Footer,516,15,114,'キャンセル',nil).ModalResult := mrCancel;
    Frame := TMusicStudioTimingFrame.Create(D); Frame.Parent := D; Frame.Align := alClient;
    Frame.LoadTiming(Document.ManualTimingJSON);
    while D.ShowModal=mrOK do begin
      if not Frame.CanApply then begin MessageDlg(Frame.StateText,mtWarning,[mbOK],0); Continue; end;
      if Document.SetTiming(Frame.ConfigJSON,Error) then begin Commit(); Break; end;
      MessageDlg(Error,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;
function GenerateMusicStudioDrumPlacement(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  Cache: TMusicStudioWaveCache; TrackIndex, SlotIndex: Integer; Cursor: Double; const Commit: TFunc<Boolean>;
  out ErrorText: string): Boolean;
var Track,AudioTrack: TMusicStudioTrack; Slot: TMusicStudioSlot; Clip,Audio,Only: TMusicStudioPlacement;
  Pattern,Sound: TMusicStudioPattern; Asset: TMusicStudioPsdAsset; Source: TMusicStudioWaveSource;
  Layers: TMusicStudioLayerDocument; Data: TMusicStudioInstrumentData;
  I,AudioCount,CursorCount: Integer; StartBeat,FinishBeat: Double; Before,Checked,Rollback: string;
begin
  Result := False; ErrorText := '';
  try
    if (TrackIndex<0) or (TrackIndex>=Document.TrackCount) then Exit;
    Track := Document.TrackAt(TrackIndex);
    if Track.PerformanceAttribute<>'drums' then raise Exception.Create('ドラムの演奏者を選択してください。');
    if (SlotIndex<0) or (SlotIndex>High(Track.Slots)) or (Track.Slots[SlotIndex].Kind<>'performance') then begin
      SlotIndex := -1;
      for I := 0 to High(Track.Slots) do if Track.Slots[I].Kind='performance' then begin SlotIndex := I; Break; end;
    end;
    if SlotIndex<0 then raise Exception.Create('先にドラムの演奏スロットを追加してください。');
    AudioCount := 0; CursorCount := 0;
    for I := 0 to Document.TrackCount-1 do begin
      AudioTrack := Document.TrackAt(I);
      if AudioTrack.Kind<>'audio' then Continue;
      for Slot in AudioTrack.Slots do if Slot.Kind='audio' then for Clip in Slot.Clips do begin
        Inc(AudioCount); Only := Clip;
        if (Cursor>=Clip.StartSeconds) and (Cursor<Clip.StartSeconds+Clip.LengthSeconds) then begin
          Inc(CursorCount); Audio := Clip;
        end;
      end;
    end;
    if (CursorCount=0) and (AudioCount=1) then Audio := Only
    else if CursorCount<>1 then raise Exception.Create('生成元の音声配置が1つになる位置へ再生カーソルを移動してください。');
    Sound := Default(TMusicStudioPattern);
    for I := 0 to Document.PatternCount-1 do begin
      Pattern := Document.PatternAt(I);
      if Pattern.ID=Audio.PatternID then begin Sound := Pattern; Break; end;
    end;
    Source := Cache.Find(Sound.FilePath);
    if (Source=nil) or (Source.Status<>wsReady) then begin
      if (Source<>nil) and (Source.Status in [wsMissing,wsBroken,wsSilent]) then
        raise Exception.Create('音声を解析できません: '+Source.Message);
      raise Exception.Create('音声行の波形が表示されてから、もう一度実行してください。');
    end;
    StartBeat := Document.SecondsToBeat(Audio.StartSeconds);
    FinishBeat := Document.SecondsToBeat(Audio.StartSeconds+Min(Audio.LengthSeconds,Source.Info.Duration));
    for Clip in Track.Slots[SlotIndex].Clips do
      if (Clip.StartSeconds<Audio.StartSeconds+Min(Audio.LengthSeconds,Source.Info.Duration)) and
        (Clip.StartSeconds+Clip.LengthSeconds>Audio.StartSeconds) then
        raise Exception.Create('同じ範囲に演奏配置があります。空いている演奏スロットを選んでください。');
    if not Store.TryRead(Track.PsdAssetID,Asset,ErrorText) then Exit;
    Layers := TMusicStudioLayerDocument.Create; Data := TMusicStudioInstrumentData.Create;
    try
      if not Layers.LoadFile(Asset.FilePath) then raise Exception.Create(Layers.LastError);
      Data.BindAsset(Asset.ID);
      GenerateMusicStudioDrums(Data,Layers.InstrumentRules,Document.Timing,Source.Wave,Source.Info.Duration,Audio.StartSeconds,Audio.LengthSeconds);
      if not Document.TrySave(Before,ErrorText) then Exit;
      try
        I := Document.AddPerformance; Pattern := Document.PatternAt(I);
        Pattern.Name := 'おまかせドラム · '+Copy(Sound.Name,1,160);
        Pattern.ConfigJSON := Data.JSON; Document.UpdatePattern(Pattern);
        if not Document.AddBeatPlacement(TrackIndex,SlotIndex,Pattern.ID,StartBeat,FinishBeat-StartBeat,ErrorText) then
          raise Exception.Create(ErrorText);
        if not Document.TrySave(Checked,ErrorText) then raise Exception.Create(ErrorText);
        if not Commit() then raise Exception.Create('おまかせ演奏を作品へ反映できません。');
      except
        Document.TryLoad(Before,Rollback);
        raise;
      end;
      Result := True;
    finally Data.Free; Layers.Free; end;
  except on E: Exception do ErrorText := E.Message; end;
end;
end.