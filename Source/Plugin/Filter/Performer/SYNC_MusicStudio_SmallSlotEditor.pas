unit SYNC_MusicStudio_SmallSlotEditor;

// 小型スロットの右クリック操作だけを担当する。候補は作品に保持したPSD解析結果を使う。
// Document/View/Commitは借用。メニューは自身で所有し、モデルの確定は既存作品Undo境界へ返す。
interface
uses System.Classes, System.Types, System.SysUtils, Vcl.Menus,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_PatternData;
type
  TMusicStudioSmallSlotEditor = class(TComponent)
  private
    FView: TMusicStudioArrangementView;
    FDocument: TMusicStudioDocument;
    FCommit: TFunc<Boolean>;
    FTrack,FSlot,FClip: Integer;
    FStart: Double;
    FChoices: TArray<string>;
    procedure Choose(Sender: TObject);
    procedure Delete(Sender: TObject);
  public
    Menu: TPopupMenu;
    constructor Create(AOwner: TComponent; View: TMusicStudioArrangementView; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>); reintroduce;
    // Prepareはメニュー構築のみ。クリックされるまで文書を変更しない。
    function Prepare(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double): Boolean;
    procedure ShowMenu(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
  end;
implementation
uses System.Math, System.UITypes, Vcl.Dialogs, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_SmallSlotData;
constructor TMusicStudioSmallSlotEditor.Create(AOwner: TComponent; View: TMusicStudioArrangementView; Document: TMusicStudioDocument; const Commit: TFunc<Boolean>);
begin inherited Create(AOwner); FView := View; FDocument := Document; FCommit := Commit; Menu := TPopupMenu.Create(Self); end;
function TMusicStudioSmallSlotEditor.Prepare(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double): Boolean;
var T: TMusicStudioTrack; S: TMusicStudioSlot; Parent,Item: TMenuItem; I: Integer;
  procedure Add(const Caption: string; Tag: Integer);
  begin Item := TMenuItem.Create(Menu); Item.Caption := Caption; Item.Tag := Tag; Item.OnClick := Choose; Parent.Add(Item); end;
begin
  Result := False; Menu.Items.Clear;
  if (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) then Exit;
  T := FDocument.TrackAt(TrackIndex); if (SlotIndex<0) or (SlotIndex>=Length(T.Slots)) then Exit;
  S := T.Slots[SlotIndex]; if not MusicStudioSmallSlot(S.Kind) then Exit;
  if (ClipIndex < -1) or (ClipIndex>=Length(S.Clips)) then Exit;
  FTrack := TrackIndex; FSlot := SlotIndex; FClip := ClipIndex;
  FStart := FView.SnapSecondsForSlot(Seconds,TrackIndex,SlotIndex); FChoices := Copy(S.Choices);
  Parent := TMenuItem.Create(Menu); if ClipIndex<0 then Parent.Caption := '追加' else Parent.Caption := '変更'; Menu.Items.Add(Parent);
  Add('通常（PSD初期状態）',-1);
  for I := 0 to High(FChoices) do Add(FChoices[I],I);
  if S.Kind='symbol' then Add('非表示',-2);
  if ClipIndex>=0 then begin Item := TMenuItem.Create(Menu); Item.Caption := '削除'; Item.OnClick := Delete; Menu.Items.Add(Item); end;
  Result := True;
end;
procedure TMusicStudioSmallSlotEditor.ShowMenu(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
begin if Prepare(TrackIndex,SlotIndex,ClipIndex,Seconds) then Menu.Popup(ScreenPoint.X,ScreenPoint.Y); end;
procedure TMusicStudioSmallSlotEditor.Choose(Sender: TObject);
var Mode,Choice: string; Tag: Integer;
begin
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
