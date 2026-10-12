unit SYNC_MusicStudio_FilterPlugin;

// 演奏スタジオの登録、設定画面起動、選択オブジェクトへのJSON反映を担当する。

interface

uses
  AviUtl2FilterTypes;

// 「SYNC / 演奏スタジオ」と設定・JSONデータの2項目だけを登録する。
function GetMusicStudioFilterTable: PFILTER_PLUGIN_TABLE;
procedure SetMusicStudioHostVersion(Version: Cardinal);

implementation

uses
  System.SysUtils,
  System.UITypes,
  PluginFilterTable,
  SYNC_MusicStudio_ProjectData,
  SYNC_MusicStudio_VideoRenderer,
  SYNC_MusicStudio_HostBackground,
  SYNC_MusicStudio_SettingsForm,
  Vcl.Dialogs;

const
  MUSIC_STUDIO_EFFECT_NAME = '演奏スタジオ';
  MUSIC_STUDIO_JSON_ITEM_NAME = 'JSONデータ';

type
  TMusicStudioSettingsSession = class
  private
    FEdit: PEDIT_SECTION;          // モーダル設定画面の間だけ有効なホスト編集API。
    FObject: OBJECT_HANDLE;       // 開いた時点の保存対象。後からフォーカスを取り直さない。
    FSceneID: Integer;
  public
    constructor Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE);
    function ApplyJSON(const JSONText: string; out ErrorText: string): Boolean;
    function ReadBackground(AfterSerial: UInt64;
      out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
  end;

var
  SettingsButton: TFILTER_ITEM_BUTTON;
  JSONDataItem: TFILTER_ITEM_STRING;
  PluginTableInitialized: Boolean;
  HostVersion: Cardinal;

procedure SetMusicStudioHostVersion(Version: Cardinal);
begin HostVersion := Version; end;

constructor TMusicStudioSettingsSession.Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE);
begin
  inherited Create;
  FEdit := Edit;
  FObject := Obj;
  FSceneID := -1;
  if Edit^.Info<>nil then FSceneID := PEDIT_INFO(Edit^.Info)^.SceneID;
end;

function TMusicStudioSettingsSession.ReadBackground(AfterSerial: UInt64;
  out Snapshot: TMusicStudioBackgroundSnapshot): Boolean;
begin
  Result := ReadMusicStudioBackground(FObject,FSceneID,AfterSerial,Snapshot);
  // The modal editor does not make AviUtl2 render. Keep the last owned static
  // frame on cache-only reopen/seek and report its frame instead of hiding it.
  if Result and (FEdit^.Info<>nil) and
    (Snapshot.Frame<>PEDIT_INFO(FEdit^.Info)^.Frame) then begin
    Snapshot.Status := Snapshot.Status+sLineBreak+Format(
      '静止背景の取得フレーム %d / AviUtl2カーソル %d（未更新）',
      [Snapshot.Frame,PEDIT_INFO(FEdit^.Info)^.Frame]);
  end;
end;

function TMusicStudioSettingsSession.ApplyJSON(const JSONText: string; out ErrorText: string): Boolean;
var
  UTF8Text: UTF8String;
begin
  Result := False;
  ErrorText := '';
  try
    UTF8Text := UTF8String(JSONText);
    Result := FEdit^.SetObjectItemValue(FObject, MUSIC_STUDIO_EFFECT_NAME,
      MUSIC_STUDIO_JSON_ITEM_NAME, PAnsiChar(UTF8Text));
    if Result then InvalidateMusicStudioVideoSnapshots;
    if not Result then
      ErrorText := 'JSONデータを演奏スタジオへ反映できませんでした。';
  except
    on E: Exception do
      ErrorText := 'JSONデータの反映中にエラーが発生しました: ' + E.Message;
  end;
end;

procedure SettingsButtonCallback(Edit: PEDIT_SECTION); cdecl;
var
  CurrentJSON: string;
  Form: TFormMusicStudioSettings;
  Obj: OBJECT_HANDLE;
  RawValue: PAnsiChar;
  Session: TMusicStudioSettingsSession;
begin
  try
    if (Edit = nil) or not Assigned(Edit^.GetFocusObject) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then
      raise Exception.Create('設定の読み書きに必要なAviUtl2の編集APIを取得できませんでした。');
    Obj := Edit^.GetFocusObject;
    if Obj = nil then
      raise Exception.Create('設定対象のオブジェクトを選択してください。');
    if Assigned(Edit^.CountObjectEffect) then
      if Edit^.CountObjectEffect(Obj, MUSIC_STUDIO_EFFECT_NAME) <> 1 then
        raise Exception.Create('設定対象には演奏スタジオを1つ配置してください。');
    RawValue := Edit^.GetObjectItemValue(Obj, MUSIC_STUDIO_EFFECT_NAME, MUSIC_STUDIO_JSON_ITEM_NAME);
    if RawValue = nil then
      raise Exception.Create('設定対象のJSONデータを取得できませんでした。');
    CurrentJSON := string(UTF8String(RawValue));
    Session := TMusicStudioSettingsSession.Create(Edit, Obj);
    try
      Form := TFormMusicStudioSettings.Create(nil);
      try
        Form.LoadDocument(CurrentJSON);
        Form.OnApplyJSON := Session.ApplyJSON;
        Form.Preview.OnReadHostBackground := Session.ReadBackground;
        Form.Preview.RefreshHostBackground;
        Form.ShowModal;
      finally
        Form.Free;
        InvalidateMusicStudioVideoSnapshots;
      end;
    finally
      Session.Free;
    end;
  except
    on E: Exception do
    begin
      try
        MessageDlg('演奏スタジオの設定を開けませんでした: ' + E.Message, mtError, [mbOK], 0);
      except
        // エラー表示自体が失敗してもCコールバック境界へ例外を漏らさない。
      end;
    end;
  end;
end;

function MusicStudioProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var Session: TMusicStudioVideoSession; Overlay,Background,PreviewBackground: TMusicStudioVideoPixels;
    JSON,Error,CaptureStatus,IdentityStatus: string;
    Width,Height,PreviewWidth,PreviewHeight,I,Inv,Layer,Frame,SceneID,Cursor: Integer;
    Owner: OBJECT_HANDLE; RawJSON: PAnsiChar;
begin
  Result := 1;
  try
    if (Video=nil) or (Video^.Object_=nil) or (Video^.Scene=nil) or
      (Video^.UserData=nil) or not Assigned(Video^.SetImageData) then Exit;
    Session := TMusicStudioVideoSession(Video^.UserData);
    Width := Video^.Object_^.Width; Height := Video^.Object_^.Height;
    if (Width<1) or (Height<1) then begin Width := Video^.Scene^.Width; Height := Video^.Scene^.Height; end;
    if (Width<1) or (Height<1) or (Width>8192) or (Height>8192) or
      (Int64(Width)*Height>33554432) then begin Session.Background.Clear; Exit; end;
    JSON := ''; if JSONDataItem.Value<>nil then JSON := string(JSONDataItem.Value);
    // Output composition still uses the object image. It is distinct from the
    // full composited scene behind a transparent/filter object.
    if Assigned(Video^.GetImageData) then begin
      SetLength(Background,NativeInt(Width)*Height); Video^.GetImageData(@Background[0]);
    end;
    if not Session.Background.CaptureFramebuffer(Video^.GetFramebufferTexture2D,
      PreviewBackground,PreviewWidth,PreviewHeight,CaptureStatus) then begin
      PreviewBackground := Background; PreviewWidth := Width; PreviewHeight := Height;
      CaptureStatus := CaptureStatus+' / オブジェクト画像へfallback';
    end;
    if Length(PreviewBackground)>0 then begin
      Owner := nil; SceneID := -1;
      IdentityStatus := '描画時の編集API不足';
      Frame := Video^.Object_^.FrameS+Video^.Object_^.Frame;
      if (Video^.Edit<>nil) and Assigned(Video^.Edit^.FindObject) and
        Assigned(Video^.Edit^.CountObjectEffect) and Assigned(Video^.Edit^.GetObjectItemValue) then begin
        IdentityStatus := '描画対象から設定オブジェクトを取得できない';
        Layer := Video^.Object_^.Layer;
        if Video^.Object_^.Flag and 1<>0 then begin
          // The drawing target's layer can differ from the filter object's layer.
          // OBJECT_INFO.effect_layer was added in host 2.1.3 (2026/8/2).
          if HostVersion>=2010300 then Layer := Video^.Object_^.EffectLayer else Layer := -1;
        end;
        if Layer>=0 then Owner := Video^.Edit^.FindObject(Layer,Frame);
        if Owner<>nil then begin
          if Video^.Edit^.CountObjectEffect(Owner,MUSIC_STUDIO_EFFECT_NAME)<>1 then begin
            IdentityStatus := '対象の演奏スタジオが1件ではない'; Owner := nil;
          end
          else begin
            RawJSON := Video^.Edit^.GetObjectItemValue(Owner,MUSIC_STUDIO_EFFECT_NAME,MUSIC_STUDIO_JSON_ITEM_NAME);
            if RawJSON=nil then begin IdentityStatus := '対象JSONを取得できない'; Owner := nil; end
            else if string(UTF8String(RawJSON))<>JSON then begin
              IdentityStatus := '対象JSONと描画JSONが一致しない'; Owner := nil;
            end;
          end;
        end;
        if Video^.Edit^.Info<>nil then SceneID := PEDIT_INFO(Video^.Edit^.Info)^.SceneID;
      end;
      Cursor := -1; if (Video^.Edit<>nil) and (Video^.Edit^.Info<>nil) then Cursor := PEDIT_INFO(Video^.Edit^.Info)^.Frame;
      if Owner<>nil then IdentityStatus := '対象照合済み';
      CaptureStatus := CaptureStatus+sLineBreak+Format(
        '%s / host=%d / object=%d / effect=%d / scene=%d / frame=%d / cursor=%d / alpha(隅/中央)=%d/%d',
        [IdentityStatus,HostVersion,Video^.Object_^.ID,Video^.Object_^.EffectID,SceneID,Frame,Cursor,PreviewBackground[0].A,
         PreviewBackground[Length(PreviewBackground) div 2].A]);
      Session.Background.Publish(Owner,SceneID,Frame,PreviewWidth,PreviewHeight,
        Video^.Object_^.Time,PreviewBackground,CaptureStatus);
    end else Session.Background.Clear(CaptureStatus);
    // Invalid JSON/PSD cannot prevent a valid input background being captured.
    if not Session.Render(JSON,Video^.Object_^.Time,Width,Height,Overlay,Error) then Exit;
    if Length(Background)=Length(Overlay) then begin
      for I := 0 to High(Overlay) do begin
        Inv := 255-Overlay[I].A;
        Overlay[I].R := Overlay[I].R+(Integer(Background[I].R)*Inv+127) div 255;
        Overlay[I].G := Overlay[I].G+(Integer(Background[I].G)*Inv+127) div 255;
        Overlay[I].B := Overlay[I].B+(Integer(Background[I].B)*Inv+127) div 255;
        Overlay[I].A := Overlay[I].A+(Integer(Background[I].A)*Inv+127) div 255;
      end;
    end;
    Video^.SetImageData(@Overlay[0],Width,Height);
  except
    if (Video<>nil) and (Video^.UserData<>nil) then
      try TMusicStudioVideoSession(Video^.UserData).Background.Clear; except end;
    // Broken references/SDK errors must not escape or terminate host output.
  end;
end;

function MusicStudioCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try Result := TMusicStudioVideoSession.Create; except end;
end;

procedure MusicStudioDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try TMusicStudioVideoSession(UserData).Free; except end;
end;

function GetMusicStudioFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA, MUSIC_STUDIO_EFFECT_NAME, 'SYNC',
      '音楽素材とPSDによる演奏シーンの編集スタジオ', MusicStudioProcVideo, nil);
    AddButton(SettingsButton, '設定', SettingsButtonCallback);
    AddString(JSONDataItem, MUSIC_STUDIO_JSON_ITEM_NAME, MUSIC_STUDIO_DEFAULT_JSON);
    GetPluginTable^.Func_Create := MusicStudioCreate;
    GetPluginTable^.Func_Destroy := MusicStudioDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
