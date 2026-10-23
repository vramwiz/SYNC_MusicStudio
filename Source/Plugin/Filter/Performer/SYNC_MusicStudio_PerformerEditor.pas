unit SYNC_MusicStudio_PerformerEditor;

// 演奏者の固定属性選択とPSD能力判定のUI境界。取消時は作品/共通設定へ書き込まない。
interface
uses System.Classes, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PerformerPsd;
// OK時だけ固定キーを返す。取消では既存値を維持する。
function ChooseMusicStudioAttribute(Owner: TComponent; var Attribute: string): Boolean;
// Storeは借用、解析Documentは処理内で所有・破棄する。失敗時は説明を返し、既存枠を変更しない。
function ReadMusicStudioPerformer(Store: TMusicStudioSharedPsdLibrary; const AssetID: string;
  out Profile: TMusicStudioPerformerProfile; out ErrorText: string): Boolean;
implementation
uses System.SysUtils, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, SYNC_MusicStudio_Controls,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_PerformanceKinds, SYNC_MusicStudio_PsdLayers;
function ChooseMusicStudioAttribute(Owner: TComponent; var Attribute: string): Boolean;
var D: TForm; C: TListBox; L: TLabel; B: TButton; I: Integer;
begin
  D := TForm.CreateNew(Owner);
  try
    D.Caption := '演奏属性'; D.Position := poOwnerFormCenter; D.BorderStyle := bsDialog;
    D.ClientWidth := 440; D.ClientHeight := 290; ApplySyncMusicStudioDarkForm(D);
    L := TLabel.Create(D); L.Parent := D; L.SetBounds(16,16,408,40);
    L.AutoSize := False; L.WordWrap := True; L.Caption := '共通演奏パターンの分類を固定リストから選択してください。';
    C := TListBox.Create(D); C.Parent := D; C.SetBounds(16,60,408,172);
    for I := Low(PERFORMANCE_NAMES) to High(PERFORMANCE_NAMES) do C.Items.Add(PERFORMANCE_NAMES[I]);
    C.ItemIndex := PerformanceKindIndex(Attribute); ApplySyncMusicStudioDarkListBox(C);
    B := TMusicStudioButton.Create(D); B.Parent := D; B.SetBounds(216,246,96,30); B.Caption := 'OK'; B.ModalResult := mrOK;
    B := TMusicStudioButton.Create(D); B.Parent := D; B.SetBounds(320,246,104,30); B.Caption := 'キャンセル'; B.ModalResult := mrCancel; B.Cancel := True;
    repeat
      Result := D.ShowModal=mrOK; if not Result then Exit;
    until C.ItemIndex>=0;
    Attribute := PERFORMANCE_KEYS[C.ItemIndex];
  finally D.Free; end;
end;
function ReadMusicStudioPerformer(Store: TMusicStudioSharedPsdLibrary; const AssetID: string;
  out Profile: TMusicStudioPerformerProfile; out ErrorText: string): Boolean;
var A: TMusicStudioPsdAsset; D: TMusicStudioLayerDocument;
begin
  Result := False; Profile := Default(TMusicStudioPerformerProfile);
  if not Store.TryRead(AssetID,A,ErrorText) then Exit;
  D := TMusicStudioLayerDocument.Create;
  try
    if not D.LoadFile(A.FilePath) then begin ErrorText := D.LastError; Exit; end;
    Profile := MusicStudioPerformerProfile(D,A.ConfigJSON);
    Result := True;
  finally D.Free; end;
end;
end.
