unit SYNC_MusicStudio_ProjectData;

// 設定画面とAviUtl2が共有するJSON文書の初期化、検証、単行化を担当する。

interface

const
  MUSIC_STUDIO_SCHEMA_VERSION = 1;
  MUSIC_STUDIO_MAX_JSON_LENGTH = 32767; // AviUtl2の単行文字列項目へ保存する上限。
  MUSIC_STUDIO_MAX_JSON_INPUT = 1024 * 1024; // 整形JSONも許容しつつ解析前の入力を制限する。
  MUSIC_STUDIO_DEFAULT_JSON = '{"schemaVersion":1,"previewAudio":null,"materials":[],"characters":[],"tracks":[]}';

// 空の入力は新規文書へ置換する。未知のフィールドも保持し、不正な文書は保存しない。
function TryNormalizeMusicStudioJSON(const Text: string; out JSONText, ErrorText: string): Boolean;
// UTF-8（BOM可）の外部JSONを同一ストリームから上限付きで読み、検証後の文書を返す。
function TryReadMusicStudioJSONFile(const Path: string; out JSONText, ErrorText: string): Boolean;

implementation

uses
  System.JSON,
  System.SysUtils,
  System.Classes,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData;

function RequireArray(Document: TJSONObject; const Name: string; out ErrorText: string): Boolean;
begin
  Result := Document.GetValue(Name) is TJSONArray;
  if not Result then
    ErrorText := Name + ' は配列で指定してください。';
end;

function JSONNestingAllowed(const Text: string; out ErrorText: string): Boolean;
var C: Char; Depth: Integer; InString, Escaped, RootEnded: Boolean;
begin
  Depth := 0; InString := False; Escaped := False; RootEnded := False;
  for C in Text do begin
    if InString then begin
      if Escaped then Escaped := False
      else if C = '\' then Escaped := True
      else if C = '"' then InString := False;
      Continue;
    end;
    if RootEnded and not CharInSet(C,[' ',#9,#10,#13]) then begin
      ErrorText := 'JSONのルートの後に余分なデータがあります。'; Exit(False);
    end;
    if C = '"' then InString := True
    else if (C = '{') or (C = '[') then begin
      Inc(Depth); if Depth > 128 then begin ErrorText := 'JSONの入れ子は128階層以内にしてください。'; Exit(False); end;
    end
    else if (C = '}') or (C = ']') then begin
      Dec(Depth); if Depth < 0 then begin ErrorText := 'JSONの括弧が対応していません。'; Exit(False); end;
      if Depth = 0 then RootEnded := True;
    end;
  end;
  Result := True; // 構文と型は続く標準JSONパーサーに任せる。ここでは解析量だけを制限する。
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
  if Length(Text) > MUSIC_STUDIO_MAX_JSON_INPUT then begin
    ErrorText := '入力JSONは1MiB文字以内にしてください。保存後は32,767文字以内です。'; Exit;
  end;
  SourceText := Trim(Text);
  if SourceText = '' then
    SourceText := MUSIC_STUDIO_DEFAULT_JSON;
  if not JSONNestingAllowed(SourceText,ErrorText) then Exit;
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
      if not ValidateMusicStudioPatterns(Document, ErrorText) then
        Exit;
      if not ValidateMusicStudioArrangement(Document, ErrorText) then
        Exit;
      if not UpgradeMusicStudioArrangement(Document, ErrorText) or
        not ValidateMusicStudioArrangement(Document, ErrorText) then
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

function TryReadMusicStudioJSONFile(const Path: string; out JSONText, ErrorText: string): Boolean;
var Stream: TFileStream; Bytes: TBytes; Offset: Integer; Text: string;
begin
  Result := False; JSONText := ''; ErrorText := '';
  try
    Stream := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size > MUSIC_STUDIO_MAX_JSON_INPUT then begin
        ErrorText := 'JSONファイルは1MiB以内にしてください。保存後は32,767文字以内です。'; Exit;
      end;
      SetLength(Bytes,Stream.Size);
      if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[0],Length(Bytes));
    finally Stream.Free; end;
    Offset := 0;
    if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then Offset := 3;
    if Length(Bytes) > Offset then begin
      if not TEncoding.UTF8.IsBufferValid(@Bytes[Offset],Length(Bytes)-Offset) then begin
        ErrorText := 'JSONファイルをUTF-8で保存してください。'; Exit;
      end;
      Text := TEncoding.UTF8.GetString(Bytes,Offset,Length(Bytes)-Offset);
    end else Text := '';
    Result := TryNormalizeMusicStudioJSON(Text,JSONText,ErrorText);
  except on E: Exception do ErrorText := 'JSONファイルを読み込めません: '+E.Message; end;
end;

end.
