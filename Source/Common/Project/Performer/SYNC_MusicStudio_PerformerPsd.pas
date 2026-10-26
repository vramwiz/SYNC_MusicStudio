unit SYNC_MusicStudio_PerformerPsd;

// PSDの読取結果から利用可能スロットと演奏属性の候補を返す。原PSD/作品を書き換えない。
interface
uses SYNC_MusicStudio_PsdLayers;
type
  TMusicStudioPerformerProfile = record
    Attribute: string; // 空は判定不能/競合。固定選択UIで解決する。
    Slots: TArray<string>;
    SelectionsJSON: string; // 読込時に生成した候補。メニュー/PaintでPSDを読み直さない。
  end;
// Documentは借用。レイヤーの位置やファイル名を分類条件にしない。
function MusicStudioPerformerProfile(Document: TMusicStudioLayerDocument; const ConfigJSON: string): TMusicStudioPerformerProfile;
implementation
uses System.JSON, System.SysUtils, SYNC_MusicStudio_ArtLayerName, SYNC_MusicStudio_PerformanceKinds,
  SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_PsdLayerConfig;
function MusicStudioPerformerProfile(Document: TMusicStudioLayerDocument; const ConfigJSON: string): TMusicStudioPerformerProfile;
var Layer: TMusicStudioLayerInfo; Row: TInstrumentRow; I,J,Markers: Integer; Name,Detected: string;
  Singing,Action,Emotion,Pose,Face,Symbol: Boolean; Config: TJSONValue;
begin
  Result := Default(TMusicStudioPerformerProfile);
  if (Document=nil) or not Document.Loaded then Exit;
  Action := Document.DrumRules.HasDrumStructure; Emotion := False; Pose := False;
  Face := False; Symbol := False; Result.SelectionsJSON := Document.InstrumentRules.DiagnosticJSON;
  Markers := 0; Detected := '';
  for Layer in Document.Layers do begin
    Name := ParseLayerName(Layer.Name).DisplayName;
    // 仮の明示属性名を一か所に集約。競合する指定は手動選択へ戻す。
    for I := Low(PERFORMANCE_KEYS) to High(PERFORMANCE_KEYS) do
      if (Name='演奏属性:'+PERFORMANCE_NAMES[I]) or (Name='演奏属性:'+PERFORMANCE_KEYS[I]) then begin
        if (Detected<>'') and (Detected<>PERFORMANCE_KEYS[I]) then Inc(Markers);
        Detected := PERFORMANCE_KEYS[I];
      end;
    if Name='表情' then Emotion := True;
    if Name='ポーズ' then Pose := True;
    if Name='顔色' then Face := True;
    if Name='記号' then Symbol := True;
  end;
  Config := TJSONObject.ParseJSONValue(ConfigJSON);
  try
    if Config is TJSONObject then Singing := MusicStudioCanSing(Document,TJSONObject(Config))
    else Singing := MusicStudioCanSing(Document,nil);
  finally Config.Free; end;
  for J := 0 to Document.InstrumentRules.RowCount-1 do begin
    Row := Document.InstrumentRules.RowAt(J);
    if Row.Kind=irkAction then Action := True;
    if Row.Name='表情' then Emotion := True;
    if Row.Name='ポーズ' then Pose := True;
  end;
  if Markers=0 then begin
    Result.Attribute := Detected;
    if (Detected='') and Document.DrumRules.HasDrumStructure then Result.Attribute := 'drums';
    if (Detected='') and not Action and Singing then Result.Attribute := 'vocal';
  end;
  if Singing then Result.Slots := Result.Slots+['singing'];
  if Action then Result.Slots := Result.Slots+['performance'];
  if Emotion then Result.Slots := Result.Slots+['emotion'];
  if Face then Result.Slots := Result.Slots+['face'];
  if Pose then Result.Slots := Result.Slots+['pose'];
  if Symbol then Result.Slots := Result.Slots+['symbol'];
end;
end.
