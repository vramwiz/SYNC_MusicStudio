unit SYNC_MusicStudio_SettingsSlotMenus;

// 統合編集のメニュー部品、スロット追加候補と表示条件を共有する。
// メニュー表示と作品変更は呼出元が担当し、このunitは作品や素材を所有しない。
interface
uses System.Classes, Vcl.Menus, SYNC_MusicStudio_ArrangementData;
const SLOT_KINDS: array[0..15] of string = ('audio','psd','singing','emotion','animationSinging','instrument','performance','animationPerformance','generic','tempo','face','pose','symbol','customExpression','animationRhythm','animation');
// Parentに項目を追加して返す。Parent.Ownerが所有し、Clickは実行せず登録だけ行う。
function AddMusicStudioSettingsMenu(Parent: TMenuItem; const Caption: string; Click: TNotifyEvent): TMenuItem;
// 空のParentへSLOT_KINDS順に候補を構築する。Tagは種類indexで、作品の変更やPopupは行わない。
procedure PopulateMusicStudioSlotMenu(Parent: TMenuItem; Click: TNotifyEvent);
// Trackは借用snapshot。Root/Submenuの所有権を移さず、Enabled/Visibleだけを同じ条件で更新する。
// PSD読込・ファイル操作・Popup・作品の更新は行わない。
procedure ApplyMusicStudioSlotMenu(const Track: TMusicStudioTrack; Root: TPopupMenu; Submenu: TMenuItem);
implementation
function AddMusicStudioSettingsMenu(Parent: TMenuItem; const Caption: string; Click: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Parent.Owner);
  Result.Caption := Caption;
  Result.OnClick := Click;
  Parent.Add(Result);
end;

procedure PopulateMusicStudioSlotMenu(Parent: TMenuItem; Click: TNotifyEvent);
var I: Integer; Item: TMenuItem;
begin
  for I := 0 to High(SLOT_KINDS) do begin
    Item := AddMusicStudioSettingsMenu(Parent, MusicStudioSlotKindName(SLOT_KINDS[I])+'スロット', Click);
    Item.Tag := I;
  end;
end;

procedure ApplyMusicStudioSlotMenu(const Track: TMusicStudioTrack; Root: TPopupMenu; Submenu: TMenuItem);
var I: Integer; K: string; Enabled: Boolean;
begin
  for I := 0 to High(SLOT_KINDS) do begin
    Enabled := ((Track.Kind='audio') and ((SLOT_KINDS[I]='audio') or (SLOT_KINDS[I]='tempo'))) or
      ((Track.Kind='psd') and (Track.PsdAssetID<>'') and (SLOT_KINDS[I]='customExpression'));
    for K in Track.ProvidedSlots do if SLOT_KINDS[I]=K then Enabled := True;
    if MusicStudioAnimationSource(SLOT_KINDS[I])<>'' then Enabled := MusicStudioCanAddAnimationSlot(Track,SLOT_KINDS[I]);
    if SLOT_KINDS[I]='animation' then Enabled := False;
    Root.Items[I].Enabled := Enabled; Root.Items[I].Visible := Enabled;
    Submenu.Items[I].Enabled := Enabled; Submenu.Items[I].Visible := Enabled;
  end;
end;
end.
