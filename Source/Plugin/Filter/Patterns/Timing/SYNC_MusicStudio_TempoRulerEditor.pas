unit SYNC_MusicStudio_TempoRulerEditor;

// 小節ルーラーの手動tempo点操作。clip由来の有効mapとは別の元データを編集する。
interface
uses System.Classes, Vcl.Forms, Vcl.Menus, SYNC_MusicStudio_PatternData;
type
  TMusicStudioTempoCommit = function: Boolean of object;
  TMusicStudioTempoRulerEditor = class
  private
    FOwner: TForm;
    FDocument: TMusicStudioDocument;
    FMenu: TPopupMenu;
    FBeat: Double;
    FCommit: TMusicStudioTempoCommit;
    procedure EditClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    constructor Create(Owner: TForm; Document: TMusicStudioDocument; Commit: TMusicStudioTempoCommit);
    destructor Destroy; override;
    procedure ShowMenu(Beat: Double);
    function SetPoint(Beat,BPM: Double; out Error: string): Boolean;
    function DeletePoint(Beat: Double; out Error: string): Boolean;
    property Menu: TPopupMenu read FMenu;
  end;
implementation
uses System.SysUtils, System.Math, System.Types, System.UITypes, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Controls, Vcl.Dialogs,
  SYNC_MusicStudio_BeatData, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
constructor TMusicStudioTempoRulerEditor.Create(Owner: TForm; Document: TMusicStudioDocument; Commit: TMusicStudioTempoCommit);
var Item: TMenuItem;
begin
  inherited Create; FOwner := Owner; FDocument := Document; FCommit := Commit; FMenu := TPopupMenu.Create(nil);
  Item := TMenuItem.Create(FMenu); Item.Caption := '手動テンポを追加 / 設定…'; Item.OnClick := EditClick; FMenu.Items.Add(Item);
  Item := TMenuItem.Create(FMenu); Item.Caption := 'この小節の手動テンポを削除'; Item.OnClick := DeleteClick; FMenu.Items.Add(Item);
end;
destructor TMusicStudioTempoRulerEditor.Destroy;
begin FMenu.Free; inherited; end;
procedure TMusicStudioTempoRulerEditor.ShowMenu(Beat: Double);
var Map: TMusicStudioTempoMap; I: Integer; P: TPoint;
begin
  FBeat := FDocument.Timing.MeasureStart(FDocument.Timing.MeasureAtBeat(Max(0.0,Beat)));
  Map := TMusicStudioTempoMap.Create;
  try Map.LoadJSON(FDocument.ManualTimingJSON); FMenu.Items[1].Enabled := False;
    for I := 1 to Map.PointCount-1 do if Abs(Map.TempoPoint(I).Beat-FBeat)<1E-9 then FMenu.Items[1].Enabled := True;
  finally Map.Free; end;
  P := Mouse.CursorPos; FMenu.Popup(P.X,P.Y);
end;
function TMusicStudioTempoRulerEditor.SetPoint(Beat,BPM: Double; out Error: string): Boolean;
var Map: TMusicStudioTempoMap;
begin
  Result := False; Map := TMusicStudioTempoMap.Create;
  try
    try Map.LoadJSON(FDocument.ManualTimingJSON); Map.SetBPMAt(Beat,BPM);
      Result := FDocument.SetTiming(Map.TimingJSON,Error); if Result and Assigned(FCommit) then Result := FCommit;
    except on E: Exception do Error := E.Message; end;
  finally Map.Free; end;
end;
function TMusicStudioTempoRulerEditor.DeletePoint(Beat: Double; out Error: string): Boolean;
var Map: TMusicStudioTempoMap; I: Integer;
begin
  Result := False; Error := '先頭0拍の基準tempoは削除できません。'; if Beat<=0 then Exit;
  Map := TMusicStudioTempoMap.Create;
  try
    try Map.LoadJSON(FDocument.ManualTimingJSON);
      for I := 1 to Map.PointCount-1 do if Abs(Map.TempoPoint(I).Beat-Beat)<1E-9 then begin
        Map.DeleteTempoPoint(I); Result := FDocument.SetTiming(Map.TimingJSON,Error);
        if Result and Assigned(FCommit) then Result := FCommit; Exit;
      end;
      Error := 'この小節に手動tempo点はありません。';
    except on E: Exception do Error := E.Message; end;
  finally Map.Free; end;
end;
procedure TMusicStudioTempoRulerEditor.EditClick(Sender: TObject);
var Dialog: TForm; Input: TEdit; LabelControl: TLabel; Footer: TPanel; B: TButton; BPM: Double; Error: string; Manual: TMusicStudioTempoMap;
begin
  Dialog := TForm.CreateNew(FOwner);
  try
    Dialog.Caption := Format('%d小節の手動テンポ',[FDocument.Timing.MeasureAtBeat(FBeat)]);
    Dialog.Position := poOwnerFormCenter; Dialog.ClientWidth := 480; Dialog.ClientHeight := 190; Dialog.BorderStyle := bsDialog;
    ApplySyncMusicStudioDarkForm(Dialog); ApplyMusicStudioEditorFont(Dialog);
    LabelControl := TLabel.Create(Dialog); LabelControl.Parent := Dialog; LabelControl.SetBounds(16,16,440,44);
    LabelControl.AutoSize := False; LabelControl.WordWrap := True; LabelControl.Caption := Format('手動BPMを編集します。現在の有効BPM: %g。clip区間はclip優先、0拍は削除不可。',[FDocument.Timing.BPMAt(FBeat)]);
    Input := TEdit.Create(Dialog); Input.Parent := Dialog; Input.SetBounds(16,72,170,28);
    Manual := TMusicStudioTempoMap.Create;
    try Manual.LoadJSON(FDocument.ManualTimingJSON); Input.Text := FloatToStr(Manual.BPMAt(FBeat),TFormatSettings.Invariant);
    finally Manual.Free; end;
    ApplySyncMusicStudioDarkEdit(Input);
    Footer := TPanel.Create(Dialog); Footer.Parent := Dialog; Footer.Align := alBottom; Footer.Height := 54;
    B := TMusicStudioButton.Create(Dialog); B.Parent := Footer; B.SetBounds(236,12,100,30); B.Caption := 'OK'; B.ModalResult := mrOK;
    B := TMusicStudioButton.Create(Dialog); B.Parent := Footer; B.SetBounds(352,12,110,30); B.Caption := 'キャンセル'; B.ModalResult := mrCancel;
    while Dialog.ShowModal=mrOK do begin
      if TryStrToFloat(Input.Text,BPM,TFormatSettings.Invariant) and SetPoint(FBeat,BPM,Error) then Break;
      if Error='' then Error := 'BPMを1～999.99で入力してください。'; MessageDlg(Error,mtWarning,[mbOK],0);
    end;
  finally Dialog.Free; end;
end;
procedure TMusicStudioTempoRulerEditor.DeleteClick(Sender: TObject);
var Error: string;
begin if not DeletePoint(FBeat,Error) then MessageDlg(Error,mtWarning,[mbOK],0); end;
end.
