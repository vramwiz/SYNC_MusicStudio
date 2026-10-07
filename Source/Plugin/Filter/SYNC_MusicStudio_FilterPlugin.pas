unit SYNC_MusicStudio_FilterPlugin;

// 演奏スタジオの登録、設定画面起動、選択オブジェクトへのJSON反映を担当する。

interface

uses
  AviUtl2FilterTypes;

// 「SYNC / 演奏スタジオ」と設定・JSONデータの2項目だけを登録する。
function GetMusicStudioFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils,
  System.UITypes,
  PluginFilterTable,
  SYNC_MusicStudio_ProjectData,
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
  public
    constructor Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE);
    function ApplyJSON(const JSONText: string; out ErrorText: string): Boolean;
  end;

var
  SettingsButton: TFILTER_ITEM_BUTTON;
  JSONDataItem: TFILTER_ITEM_STRING;
  PluginTableInitialized: Boolean;

constructor TMusicStudioSettingsSession.Create(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE);
begin
  inherited Create;
  FEdit := Edit;
  FObject := Obj;
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
        Form.ShowModal;
      finally
        Form.Free;
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
begin
  // PSD描画の実装前はホストの映像をそのまま維持し、音声も変更しない。
  Result := 1;
end;

function GetMusicStudioFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER, MUSIC_STUDIO_EFFECT_NAME, 'SYNC',
      '音楽素材とPSDによる演奏シーンの編集スタジオ', MusicStudioProcVideo, nil);
    AddButton(SettingsButton, '設定', SettingsButtonCallback);
    AddString(JSONDataItem, MUSIC_STUDIO_JSON_ITEM_NAME, MUSIC_STUDIO_DEFAULT_JSON);
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
