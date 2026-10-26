unit SYNC_MusicStudio_SettingsDialogs;

// 統合編集の画面部品と補助ダイアログを構築する。作品の履歴・ホスト適用は所有しない。
// Owner/Document/Commitは借用し、各modalはfinallyで破棄する。音声・素材実体は読み書きしない。
interface
uses System.Classes, System.SysUtils, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  SYNC_MusicStudio_PatternData;
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
implementation
uses System.UITypes, Vcl.Dialogs, SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_TimingFrame,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_PerformerEditor;
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
end.
