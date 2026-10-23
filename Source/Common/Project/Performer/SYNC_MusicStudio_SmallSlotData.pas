unit SYNC_MusicStudio_SmallSlotData;

// PSD候補と独立演出区間の意味データ。配置UID/秒座標を既存clipsで保持し、実レイヤーキーを保存しない。
interface
uses System.JSON;
function MusicStudioSmallSlot(const Kind: string): Boolean;
function MusicStudioSelectionRow(const Kind: string): string;
// default/hiddenは仮想要素。choiceはPSD由来の実名。独立演出パターンの設定を検証する。
function ValidateMusicStudioSelection(Value: TJSONValue): Boolean;
// 解析済み候補だけを枠へコピーする。既存の区間/手動設定は変更しない。
procedure MusicStudioSmallChoices(Root: TJSONObject; TrackIndex: Integer; const RulesJSON: string);
// ClipIndex=-1は追加。変更時は他配置と共有したパターンを分離し、未知属性を保持する。
procedure MusicStudioWriteSmallElement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer;
  const Mode,Choice: string; StartSeconds,LengthSeconds: Double);
// 独立要素の孤立パターンだけを整理する。通常パターンと共有中の要素は保持する。
procedure MusicStudioPruneSmallElements(Root: TJSONObject);
implementation
uses System.SysUtils, System.Math, System.Generics.Collections;
function MusicStudioSmallSlot(const Kind: string): Boolean;
begin Result := (Kind='emotion') or (Kind='face') or (Kind='pose') or (Kind='symbol'); end;
function MusicStudioSelectionRow(const Kind: string): string;
begin
  if Kind='emotion' then Result := '表情' else if Kind='face' then Result := '顔色'
  else if Kind='pose' then Result := 'ポーズ' else if Kind='symbol' then Result := '記号' else Result := '';
end;
function ValidateMusicStudioSelection(Value: TJSONValue): Boolean;
var O: TJSONObject; Row,Mode,Choice: string;
begin
  Result := False; if not (Value is TJSONObject) then Exit; O := TJSONObject(Value);
  if not (O.GetValue('row') is TJSONString) or not (O.GetValue('mode') is TJSONString) or
    not (O.GetValue('choice') is TJSONString) then Exit;
  Row := O.GetValue('row').Value; Mode := O.GetValue('mode').Value; Choice := O.GetValue('choice').Value;
  if not ((Row='表情') or (Row='顔色') or (Row='ポーズ') or (Row='記号')) then Exit;
  Result := ((Mode='choice') and (Choice<>'')) or ((Mode='default') and (Choice='')) or
    ((Mode='hidden') and (Row='記号') and (Choice=''));
end;
procedure Put(O: TJSONObject; const Key: string; V: TJSONValue);
begin O.RemovePair(Key).Free; O.AddPair(Key,V); end;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := GUIDToString(G); end;
procedure MusicStudioSmallChoices(Root: TJSONObject; TrackIndex: Integer; const RulesJSON: string);
var V,R,S: TJSONValue; O,Track: TJSONObject; Row: string;
begin
  V := TJSONObject.ParseJSONValue(RulesJSON);
  try
    if not (V is TJSONObject) or not (TJSONObject(V).GetValue('rows') is TJSONArray) then Exit;
    Track := TJSONObject(TJSONArray(Root.GetValue('tracks'))[TrackIndex]);
    for S in TJSONArray(Track.GetValue('slots')) do begin
      O := TJSONObject(S); Row := MusicStudioSelectionRow(O.GetValue<string>('kind','')); if Row='' then Continue;
      Put(O,'choices',TJSONArray.Create);
      for R in TJSONArray(TJSONObject(V).GetValue('rows')) do
        if TJSONObject(R).GetValue<string>('name','')=Row then
          Put(O,'choices',TJSONObject(R).GetValue('choices').Clone as TJSONValue);
    end;
  finally V.Free; end;
end;
procedure MusicStudioPruneSmallElements(Root: TJSONObject);
var Used: TDictionary<string,Boolean>; T,S,C: TJSONValue; Patterns: TJSONArray; I: Integer; P: TJSONObject;
begin
  Used := TDictionary<string,Boolean>.Create;
  try
    for T in TJSONArray(Root.GetValue('tracks')) do if (T is TJSONObject) and (TJSONObject(T).GetValue('slots') is TJSONArray) then
      for S in TJSONArray(TJSONObject(T).GetValue('slots')) do for C in TJSONArray(TJSONObject(S).GetValue('clips')) do
        Used.AddOrSetValue(TJSONObject(C).GetValue<string>('patternId'),True);
    Patterns := Root.GetValue('patterns') as TJSONArray; if Patterns=nil then Exit;
    for I := Patterns.Count-1 downto 0 do begin
      P := TJSONObject(Patterns[I]); if (P.GetValue<string>('kind','')='selection') and
        not Used.ContainsKey(P.GetValue<string>('id')) then Patterns.Remove(I).Free;
    end;
  finally Used.Free; end;
end;
procedure MusicStudioWriteSmallElement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer;
  const Mode,Choice: string; StartSeconds,LengthSeconds: Double);
var Track,Slot,Clip,P,Selection: TJSONObject; Patterns,Clips,Accepts: TJSONArray; V: TJSONValue; Pair: TJSONPair; Row,Name: string; Found: Boolean;
begin
  Track := TJSONObject(TJSONArray(Root.GetValue('tracks'))[TrackIndex]);
  Slot := TJSONObject(TJSONArray(Track.GetValue('slots'))[SlotIndex]); Row := MusicStudioSelectionRow(Slot.GetValue<string>('kind'));
  Selection := TJSONObject.Create;
  try
    Selection.AddPair('row',Row); Selection.AddPair('mode',Mode); Selection.AddPair('choice',Choice);
    if not ValidateMusicStudioSelection(Selection) then raise Exception.Create('小型スロットの要素が不正です。');
    if IsNan(StartSeconds) or IsInfinite(StartSeconds) or IsNan(LengthSeconds) or IsInfinite(LengthSeconds) or
      (StartSeconds<0) or (LengthSeconds<0.001) or (StartSeconds+LengthSeconds>604800) then raise Exception.Create('区間が範囲外です。');
    if Mode='choice' then begin
      Found := False; if Slot.GetValue('choices') is TJSONArray then for V in TJSONArray(Slot.GetValue('choices')) do if V.Value=Choice then Found := True;
      if not Found then raise Exception.Create('このPSDにない要素です。');
    end;
    Clips := TJSONArray(Slot.GetValue('clips'));
    if (ClipIndex < -1) or (ClipIndex>=Clips.Count) then raise Exception.Create('配置がありません。');
    Patterns := Root.GetValue('patterns') as TJSONArray;
    if Patterns=nil then begin Patterns := TJSONArray.Create; Root.AddPair('patterns',Patterns); end;
    P := nil;
    if ClipIndex>=0 then begin
      Clip := TJSONObject(Clips[ClipIndex]);
      for V in Patterns do if (TJSONObject(V).GetValue<string>('id')=Clip.GetValue<string>('patternId')) and
        (TJSONObject(V).GetValue<string>('kind')='selection') then P := V.Clone as TJSONObject;
    end;
    if P=nil then P := TJSONObject.Create;
    if P.GetValue('selection') is TJSONObject then for Pair in TJSONObject(P.GetValue('selection')) do
      if (Pair.JsonString.Value<>'row') and (Pair.JsonString.Value<>'mode') and (Pair.JsonString.Value<>'choice') then
        Selection.AddPair(Pair.JsonString.Value,Pair.JsonValue.Clone as TJSONValue);
    if Mode='default' then Name := '通常' else if Mode='hidden' then Name := '非表示' else Name := Choice;
    Put(P,'id',TJSONString.Create(NewID)); Put(P,'kind',TJSONString.Create('selection')); Put(P,'name',TJSONString.Create(Name));
    Put(P,'color',TJSONString.Create(Slot.GetValue<string>('color'))); Put(P,'selection',Selection); Selection := nil;
    Patterns.AddElement(P);
    Accepts := TJSONArray(Slot.GetValue('accepts')); Found := False;
    for V in Accepts do if V.Value='selection' then Found := True; if not Found then Accepts.Add('selection');
    if ClipIndex=-1 then begin
      Clip := TJSONObject.Create; Clip.AddPair('id',NewID); Clip.AddPair('slotId',Slot.GetValue<string>('id'));
      Clip.AddPair('startSeconds',TJSONNumber.Create(StartSeconds)); Clip.AddPair('lengthSeconds',TJSONNumber.Create(LengthSeconds));
      Clips.AddElement(Clip);
    end else Clip := TJSONObject(Clips[ClipIndex]);
    Put(Clip,'patternId',TJSONString.Create(P.GetValue<string>('id')));
    MusicStudioPruneSmallElements(Root);
  finally Selection.Free; end;
end;
end.
