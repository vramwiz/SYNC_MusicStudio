unit SYNC_MusicStudio_ProjectData;

// 設定画面とAviUtl2が共有するJSON文書の初期化、検証、単行化を担当する。

interface

const
  MUSIC_STUDIO_SCHEMA_VERSION = 1;
  MUSIC_STUDIO_MAX_JSON_LENGTH = 32767; // AviUtl2の単行文字列項目へ保存する上限。
  MUSIC_STUDIO_DEFAULT_JSON = '{"schemaVersion":1,"previewAudio":null,"materials":[],"characters":[],"tracks":[]}';

// 空の入力は新規文書へ置換する。未知のフィールドも保持し、不正な文書は保存しない。
function TryNormalizeMusicStudioJSON(const Text: string; out JSONText, ErrorText: string): Boolean;

implementation

uses
  System.JSON,
  System.SysUtils;

function RequireArray(Document: TJSONObject; const Name: string; out ErrorText: string): Boolean;
begin
  Result := Document.GetValue(Name) is TJSONArray;
  if not Result then
    ErrorText := Name + ' は配列で指定してください。';
end;

function TryNormalizeMusicStudioJSON(const Text: string; out JSONText, ErrorText: string): Boolean;
var
  Document: TJSONObject;
  Parsed: TJSONValue;
  PreviewAudio: TJSONValue;
  SourceText: string;
  Version: Integer;
  VersionValue: TJSONValue;
begin
  Result := False;
  JSONText := '';
  ErrorText := '';
  SourceText := Trim(Text);
  if SourceText = '' then
    SourceText := MUSIC_STUDIO_DEFAULT_JSON;
  Parsed := nil;
  try
    try
      Parsed := TJSONObject.ParseJSONValue(SourceText, False, True);
      if not (Parsed is TJSONObject) then
      begin
        ErrorText := 'JSONのルートはオブジェクトで指定してください。';
        Exit;
      end;
      Document := TJSONObject(Parsed);
      VersionValue := Document.GetValue('schemaVersion');
      if not (VersionValue is TJSONNumber) then
      begin
        ErrorText := 'schemaVersion は整数で指定してください。';
        Exit;
      end;
      if not TryStrToInt(VersionValue.Value, Version) or (Version <> MUSIC_STUDIO_SCHEMA_VERSION) then
      begin
        ErrorText := '対応していないschemaVersionです。現在は1だけを扱います。';
        Exit;
      end;
      PreviewAudio := Document.GetValue('previewAudio');
      if not ((PreviewAudio is TJSONNull) or (PreviewAudio is TJSONObject)) then
      begin
        ErrorText := 'previewAudio はnullまたはファイル参照オブジェクトで指定してください。';
        Exit;
      end;
      if PreviewAudio is TJSONObject then
      begin
        if not (TJSONObject(PreviewAudio).GetValue('filePath') is TJSONString) or
          not (TJSONObject(PreviewAudio).GetValue('displayName') is TJSONString) then
        begin
          ErrorText := 'previewAudio には文字列のfilePathとdisplayNameが必要です。';
          Exit;
        end;
      end;
      if not RequireArray(Document, 'materials', ErrorText) or
        not RequireArray(Document, 'characters', ErrorText) or
        not RequireArray(Document, 'tracks', ErrorText) then
        Exit;
      SourceText := Document.ToJSON;
      if (Pos(#13, SourceText) > 0) or (Pos(#10, SourceText) > 0) then
      begin
        ErrorText := 'JSONを単行形式へ変換できませんでした。';
        Exit;
      end;
      if Length(SourceText) > MUSIC_STUDIO_MAX_JSON_LENGTH then
      begin
        ErrorText := 'JSONデータは単行化後に32,767文字以内にしてください。';
        Exit;
      end;
      JSONText := SourceText;
      Result := True;
    except
      on E: Exception do
        ErrorText := 'JSONを読み込めませんでした: ' + E.Message;
    end;
  finally
    Parsed.Free;
  end;
end;

end.
