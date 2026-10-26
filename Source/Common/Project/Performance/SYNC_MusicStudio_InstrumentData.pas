unit SYNC_MusicStudio_InstrumentData;
// 共通楽器の拍区間を作品JSONへ保存する。PSDの物理キーを保存せず、再読込で意味名へ再接続する。
interface
uses System.JSON, System.Generics.Collections, SYNC_MusicStudio_InstrumentRules;
type
  TInstrumentBlock = record
    ID,Row,Choice: string;
    StartBeat,EndBeat: Double;
    Stage: Integer;
  end;
  TMusicStudioInstrumentData = class
  private
    FRoot: TJSONObject;
    FBlocks: TList<TInstrumentBlock>;
    FAssetID: string;
    FLength: Double;
  public
    constructor Create;
    destructor Destroy; override;
    // 候補を検証後に一括採用。未知フィールドと従来notes/layerStepsを保持する。
    procedure Load(const Text: string);
    procedure BindAsset(const ID: string);
    function JSON: string;
    function PutBlock(Index: Integer; Value: TInstrumentBlock): Boolean;
    procedure DeleteBlock(Index: Integer);
    procedure SetLength(Value: Double);
    // 設定内の試写は最後の区間まで。保存用の手動長さは変更しない。
    function PlaybackEndBeat: Double;
    function StatesAt(Beat: Double; OriginBeat: Double = 0): TArray<TInstrumentState>;
    property Blocks: TList<TInstrumentBlock> read FBlocks;
    property LengthBeats: Double read FLength;
    property AssetID: string read FAssetID;
  end;
function MusicStudioHasInstrumentTimeline(const Text: string): Boolean;
implementation
uses System.SysUtils, System.Math, SYNC_MusicStudio_BeatData;
function MusicStudioHasInstrumentTimeline(const Text: string): Boolean;
var V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(Text);
  try Result := (V is TJSONObject) and (TJSONObject(V).GetValue('instrumentTimeline')<>nil); finally V.Free; end;
end;
constructor TMusicStudioInstrumentData.Create;
begin inherited; FRoot := TJSONObject.Create; FBlocks := TList<TInstrumentBlock>.Create; FLength := 16; end;
destructor TMusicStudioInstrumentData.Destroy;
begin FBlocks.Free; FRoot.Free; inherited; end;
procedure TMusicStudioInstrumentData.BindAsset(const ID: string);
var G: TGUID; Normalized: string;
begin
  Normalized := '';
  if ID<>'' then begin
    try
      if Length(ID)=36 then G := StringToGUID('{'+ID+'}') else G := StringToGUID(ID);
    except on E: EConvertError do raise Exception.Create('PSD素材IDが不正です。'); end;
    if IsEqualGUID(G,Default(TGUID)) then raise Exception.Create('PSD素材IDが不正です。');
    Normalized := LowerCase(Copy(GUIDToString(G),2,36));
  end;
  if (FAssetID<>'') and (FAssetID<>Normalized) then raise Exception.Create('別のPSD素材の演奏パターンです。');
  FAssetID := Normalized;
end;
procedure TMusicStudioInstrumentData.SetLength(Value: Double);
var B: TInstrumentBlock;
begin
  if IsNan(Value) or IsInfinite(Value) or (Value<=0) or (Value>1000000) then raise Exception.Create('演奏長は0より大きく100万拍以下です。');
  for B in FBlocks do if B.EndBeat>Value then raise Exception.Create('区間があるため短縮できません。');
  FLength := Value;
end;
function TMusicStudioInstrumentData.PlaybackEndBeat: Double;
var B: TInstrumentBlock;
begin
  Result := 0;
  for B in FBlocks do Result := Max(Result,B.EndBeat);
  if Result<=0 then Result := FLength;
  Result := Min(Result,FLength);
end;
function TMusicStudioInstrumentData.PutBlock(Index: Integer; Value: TInstrumentBlock): Boolean;
var I: Integer; G: TGUID; B: TInstrumentBlock;
begin
  Result := False;
  if (Index < -1) or (Index>=FBlocks.Count) or (Value.Row='') or (Value.Choice='') or (Value.Stage<0) or (Value.Stage>1000000) or
    IsNan(Value.StartBeat) or IsInfinite(Value.StartBeat) or IsNan(Value.EndBeat) or IsInfinite(Value.EndBeat) or
    (Value.StartBeat<0) or (Value.EndBeat>FLength) or (Value.EndBeat-Value.StartBeat<1E-8) then Exit;
  if (Index=-1) and (FBlocks.Count>=8192) then Exit;
  if Value.ID='' then begin CreateGUID(G); Value.ID := GUIDToString(G); end;
  for I := 0 to FBlocks.Count-1 do if I<>Index then begin
    B := FBlocks[I];
    if B.ID=Value.ID then Exit;
    if (B.Row=Value.Row) and (Value.StartBeat<B.EndBeat-1E-8) and (Value.EndBeat>B.StartBeat+1E-8) then Exit;
  end;
  if Index=-1 then FBlocks.Add(Value) else FBlocks[Index] := Value; Result := True;
end;
procedure TMusicStudioInstrumentData.DeleteBlock(Index: Integer);
begin if (Index>=0) and (Index<FBlocks.Count) then FBlocks.Delete(Index); end;
procedure TMusicStudioInstrumentData.Load(const Text: string);
var V,Item: TJSONValue; D,O: TJSONObject; Candidate: TMusicStudioInstrumentData; B: TInstrumentBlock;
  function Num(Obj: TJSONObject; const Key: string): Double;
  begin
    if not (Obj.GetValue(Key) is TJSONNumber) then raise Exception.Create('演奏の数値が不正: '+Key);
    Result := TJSONNumber(Obj.GetValue(Key)).AsDouble;
    if IsNan(Result) or IsInfinite(Result) then raise Exception.Create('演奏の数値が不正: '+Key);
  end;
  function Str(Obj: TJSONObject; const Key: string): string;
  begin
    if not (Obj.GetValue(Key) is TJSONString) then raise Exception.Create('演奏の文字列が不正: '+Key);
    Result := Obj.GetValue(Key).Value;
  end;
begin
  V := TJSONObject.ParseJSONValue(Text); if not (V is TJSONObject) then begin V.Free; raise Exception.Create('演奏JSONが不正です。'); end;
  Candidate := TMusicStudioInstrumentData.Create;
  try
    Candidate.SetLength(Num(TJSONObject(V),'lengthBeats'));
    if TJSONObject(V).GetValue('instrumentTimeline')<>nil then begin
      if not (TJSONObject(V).GetValue('instrumentTimeline') is TJSONObject) then raise Exception.Create('instrumentTimelineはオブジェクトです。');
      D := TJSONObject(TJSONObject(V).GetValue('instrumentTimeline'));
      if Num(D,'version')<>1 then raise Exception.Create('未対応の共通演奏版です。');
      Candidate.BindAsset(Str(D,'assetId'));
      if not (D.GetValue('blocks') is TJSONArray) then raise Exception.Create('blocksは配列です。');
      for Item in TJSONArray(D.GetValue('blocks')) do begin
        if not (Item is TJSONObject) then raise Exception.Create('演奏区間が不正です。'); O := TJSONObject(Item);
        B.ID := Str(O,'id'); if B.ID='' then raise Exception.Create('演奏区間IDが空です。');
        B.Row := Str(O,'row'); B.Choice := Str(O,'choice'); B.StartBeat := Num(O,'startBeat'); B.EndBeat := Num(O,'endBeat');
        if (Frac(Num(O,'stage'))<>0) or (Num(O,'stage')<0) or (Num(O,'stage')>1000000) then raise Exception.Create('差分番号が不正です。');
        B.Stage := Trunc(Num(O,'stage'));
        if not Candidate.PutBlock(-1,B) then raise Exception.Create('演奏区間の重複/範囲/IDが不正です。');
      end;
    end;
    FRoot.Free; FRoot := TJSONObject(V); V := nil; FLength := Candidate.FLength; FAssetID := Candidate.FAssetID;
    FBlocks.Clear; FBlocks.AddRange(Candidate.FBlocks);
  finally Candidate.Free; V.Free; end;
end;
function TMusicStudioInstrumentData.JSON: string;
var Root,D,O,Original: TJSONObject; A: TJSONArray; B: TInstrumentBlock; V,Notes: TJSONValue;
begin
  Root := FRoot.Clone as TJSONObject;
  try
    V := Root.GetValue('instrumentTimeline'); if V is TJSONObject then D := V.Clone as TJSONObject else D := TJSONObject.Create;
    if Root.GetValue('notes')<>nil then Notes := Root.GetValue('notes').Clone as TJSONValue else Notes := TJSONArray.Create;
    Root.RemovePair('lengthBeats').Free; Root.RemovePair('notes').Free; Root.RemovePair('instrumentTimeline').Free;
    Root.AddPair('lengthBeats',TJSONNumber.Create(FLength)); Root.AddPair('notes',Notes);
    Root.AddPair('instrumentTimeline',D);
    D.RemovePair('version').Free; D.RemovePair('assetId').Free;
    D.AddPair('version',TJSONNumber.Create(1)); D.AddPair('assetId',FAssetID);
    Original := nil; if FRoot.GetValue('instrumentTimeline') is TJSONObject then Original := TJSONObject(FRoot.GetValue('instrumentTimeline'));
    D.RemovePair('blocks').Free; A := TJSONArray.Create; D.AddPair('blocks',A);
    for B in FBlocks do begin
      O := TJSONObject.Create;
      if (Original<>nil) and (Original.GetValue('blocks') is TJSONArray) then
        for V in TJSONArray(Original.GetValue('blocks')) do if (V is TJSONObject) and (TJSONObject(V).GetValue<string>('id')=B.ID) then begin O.Free; O := V.Clone as TJSONObject; Break; end;
      O.RemovePair('id').Free; O.RemovePair('row').Free; O.RemovePair('choice').Free; O.RemovePair('startBeat').Free; O.RemovePair('endBeat').Free; O.RemovePair('stage').Free;
      O.AddPair('id',B.ID); O.AddPair('row',B.Row); O.AddPair('choice',B.Choice);
      O.AddPair('startBeat',TJSONNumber.Create(B.StartBeat)); O.AddPair('endBeat',TJSONNumber.Create(B.EndBeat)); O.AddPair('stage',TJSONNumber.Create(B.Stage)); A.AddElement(O);
    end;
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
function TMusicStudioInstrumentData.StatesAt(Beat: Double; OriginBeat: Double): TArray<TInstrumentState>;
var B: TInstrumentBlock; S: TInstrumentState; Items: TList<TInstrumentState>;
begin
  Items := TList<TInstrumentState>.Create;
  try
    for B in FBlocks do if (MusicStudioComparePositions(Beat,OriginBeat+B.StartBeat)>=0) and
      (MusicStudioComparePositions(Beat,OriginBeat+B.EndBeat)<0) then begin S.Row := B.Row; S.Choice := B.Choice; S.Stage := B.Stage; Items.Add(S); end;
    Result := Items.ToArray;
  finally Items.Free; end;
end;
end.
