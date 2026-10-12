// JSON adapter for reusable PSD mouth assignments and expression visibility.
// Unknown members and missing layer keys survive load/save for later relinking.
unit SYNC_MusicStudio_PsdLayerConfig;

interface

uses System.SysUtils, System.JSON, SYNC_MusicStudio_PsdLayers;

const
  MUSIC_STUDIO_MOUTH_NAMES: array[0..11] of string =
    ('normal','a','i','u','e','o','n','smallA','smallI','smallU','smallE','smallO');
  MUSIC_STUDIO_MOUTH_CAPTIONS: array[0..11] of string =
    ('通常 / 閉じ口','あ','い','う','え','お','ん','小さい あ','小さい い',
     '小さい う','小さい え','小さい お');

function ParseMusicStudioPsdConfig(const Text: string): TJSONObject;
function MusicStudioPsdConfigObject(Config: TJSONObject; const Name: string): TJSONObject;
function MusicStudioMouthLayer(Config: TJSONObject; Index: Integer): string;
procedure MusicStudioAssignMouth(Config: TJSONObject; Index: Integer; const Key: string);
function BuildMusicStudioPsdOverrides(Document: TMusicStudioLayerDocument;
  Config: TJSONObject; MouthIndex: Integer = -1): TJSONObject;
// 合成用の値コピーに表情を重ねる。PSD本体・基本設定・母音割当は変更しない。
function BuildMusicStudioExpressionOverrides(Document: TMusicStudioLayerDocument;
  BaseConfig, Expression: TJSONObject): TJSONObject;

implementation

function MusicStudioPsdConfigObject(Config: TJSONObject; const Name: string): TJSONObject;
var Value: TJSONValue;
begin
  Value := Config.GetValue(Name);
  if Value=nil then begin Result := TJSONObject.Create; Config.AddPair(Name,Result); end
  else if Value is TJSONObject then Result := TJSONObject(Value)
  else raise Exception.Create('PSD設定の '+Name+' が不正です。');
end;

function ParseMusicStudioPsdConfig(const Text: string): TJSONObject;
var Value: TJSONValue; Pair: TJSONPair; I: Integer;
begin
  if Length(Text)>262144 then raise Exception.Create('PSD設定JSONが大きすぎます。');
  if Trim(Text)='' then Result := TJSONObject.Create
  else begin
    Value := TJSONObject.ParseJSONValue(Text);
    if not (Value is TJSONObject) then begin Value.Free; raise Exception.Create('PSD設定JSONが不正です。'); end;
    Result := TJSONObject(Value);
  end;
  try
    if Result.GetValue('version')=nil then Result.AddPair('version',TJSONNumber.Create(1));
    for Pair in MusicStudioPsdConfigObject(Result,'visibility') do
      if not (Pair.JsonValue is TJSONBool) then raise Exception.Create('PSDレイヤーの表示設定が不正です。');
    MusicStudioPsdConfigObject(Result,'mouthLayers');
    for I := 0 to 11 do MusicStudioMouthLayer(Result,I);
  except Result.Free; raise; end;
end;

function MusicStudioMouthLayer(Config: TJSONObject; Index: Integer): string;
var Value: TJSONValue;
begin
  Result := ''; if (Config=nil) or (Index<0) or (Index>11) then Exit;
  Value := MusicStudioPsdConfigObject(Config,'mouthLayers').GetValue(MUSIC_STUDIO_MOUTH_NAMES[Index]);
  if Value=nil then Exit;
  if not (Value is TJSONString) then raise Exception.Create('PSD母音の割当が不正です。');
  Result := TJSONString(Value).Value;
end;

procedure MusicStudioAssignMouth(Config: TJSONObject; Index: Integer; const Key: string);
var Obj: TJSONObject; Pair: TJSONPair;
begin
  if (Config=nil) or (Index<0) or (Index>11) then Exit;
  Obj := MusicStudioPsdConfigObject(Config,'mouthLayers');
  Pair := Obj.RemovePair(MUSIC_STUDIO_MOUTH_NAMES[Index]); Pair.Free;
  if Key<>'' then Obj.AddPair(MUSIC_STUDIO_MOUTH_NAMES[Index],Key);
end;

function BuildMusicStudioPsdOverrides(Document: TMusicStudioLayerDocument;
  Config: TJSONObject; MouthIndex: Integer): TJSONObject;
var Value: TJSONValue; Pair: TJSONPair; Key, Selected: string; I: Integer;
begin
  Result := TJSONObject.Create;
  try
    if Config<>nil then begin
      Value := Config.GetValue('visibility');
      if Value is TJSONObject then
        for Pair in TJSONObject(Value) do
          if Pair.JsonValue is TJSONBool then
            MusicStudioSetJsonBoolean(Result,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
    end;
    if (Document=nil) or (MouthIndex<0) or (MouthIndex>11) then Exit;
    Selected := MusicStudioMouthLayer(Config,MouthIndex);
    if (Selected='') and (MouthIndex>=7) then Selected := MusicStudioMouthLayer(Config,MouthIndex-6);
    if not Document.HasLayer(Selected) then Exit;
    for I := 0 to 11 do begin
      Key := MusicStudioMouthLayer(Config,I);
      if Document.HasLayer(Key) then MusicStudioSetJsonBoolean(Result,Key,False);
    end;
    Document.SelectLayerOverride(Result,Selected);
  except Result.Free; raise; end;
end;

function BuildMusicStudioExpressionOverrides(Document: TMusicStudioLayerDocument;
  BaseConfig, Expression: TJSONObject): TJSONObject;
var Config, Overrides, Visibility: TJSONObject; Pair: TJSONPair;
begin
  Config := TJSONObject(BaseConfig.Clone); Overrides := nil;
  try
    Overrides := BuildMusicStudioPsdOverrides(Document,BaseConfig,-1);
    Visibility := MusicStudioPsdConfigObject(Expression,'visibility');
    for Pair in Visibility do MusicStudioSetJsonBoolean(Overrides,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
    for Pair in Visibility do if TJSONBool(Pair.JsonValue).AsBoolean then
      Document.SelectLayerOverride(Overrides,Pair.JsonString.Value);
    Config.RemovePair('visibility').Free; Config.AddPair('visibility',Overrides); Overrides := nil;
    Result := BuildMusicStudioPsdOverrides(Document,Config,0);
  finally Overrides.Free; Config.Free; end;
end;

end.
