unit SYNC_MusicStudio_PerformerData;

// 演奏者の属性・能力スロット・複製を作品JSONへ適用する。PSD/共通ライブラリの実体を複製しない。
interface
uses System.JSON;
// 既存PSDトラックのroleは読取互換として残し、保存時にperformerへ統合する。
procedure MusicStudioUpgradePerformers(Root: TJSONObject);
function MusicStudioValidatePerformers(Root: TJSONObject; out ErrorText: string): Boolean;
// 呼出元が検証済み固定属性を渡す。既存配置と手動スロットは残し、自動生成した空スロットだけ更新する。
procedure MusicStudioSetPerformer(Root: TJSONObject; Index: Integer; const Attribute: string; const Slots: TArray<string>; UpdateSlots: Boolean = True; const ChoicesJSON: string = '');
// 借用Rootから文字列コピーを返す。PasteはIDを全発行し、パターン参照と未知フィールドを保持する。
function MusicStudioCopyTrack(Root: TJSONObject; Index: Integer): string;
function MusicStudioPasteTrack(Root: TJSONObject; const Text: string): Integer;
implementation
uses System.SysUtils, System.Generics.Collections, SYNC_MusicStudio_PerformanceKinds, SYNC_MusicStudio_SmallSlotData;
procedure Put(O: TJSONObject; const K: string; V: TJSONValue);
begin O.RemovePair(K).Free; O.AddPair(K,V); end;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := GUIDToString(G); end;
function Track(Root: TJSONObject; Index: Integer): TJSONObject;
begin Result := TJSONObject(TJSONArray(Root.GetValue('tracks'))[Index]); end;
procedure MusicStudioUpgradePerformers(Root: TJSONObject);
var V: TJSONValue; O: TJSONObject;
begin
  for V in TJSONArray(Root.GetValue('tracks')) do if V is TJSONObject then begin
    O := TJSONObject(V);
    if O.GetValue<string>('kind','')='psd' then Put(O,'role',TJSONString.Create('performer'));
  end;
end;
function MusicStudioValidatePerformers(Root: TJSONObject; out ErrorText: string): Boolean;
var V,A,S,C,P: TJSONValue; O,Pattern: TJSONObject; Patterns: TDictionary<string,string>; Attribute,K: string;
begin
  ErrorText := ''; Result := False;
  Patterns := TDictionary<string,string>.Create;
  try
  if Root.GetValue('patterns') is TJSONArray then for P in TJSONArray(Root.GetValue('patterns')) do begin
    Pattern := TJSONObject(P);
    if Pattern.GetValue('performanceLibrary') is TJSONObject then Patterns.Add(Pattern.GetValue<string>('id'),
      TJSONObject(Pattern.GetValue('performanceLibrary')).GetValue<string>('attribute'));
  end;
  for V in TJSONArray(Root.GetValue('tracks')) do if V is TJSONObject then begin
    O := TJSONObject(V); if O.GetValue<string>('kind','')<>'psd' then Continue;
    A := O.GetValue('performanceAttribute');
    if (A<>nil) and (not (A is TJSONString) or ((A.Value<>'') and (PerformanceKindIndex(A.Value)<0))) then begin
      ErrorText := '演奏属性は固定リストから選択してください。'; Exit;
    end;
    Attribute := ''; if A<>nil then Attribute := A.Value;
    if O.GetValue('providedSlots')<>nil then begin
      ErrorText := 'PSD提供スロットは既知の能力名の配列です。';
      if not (O.GetValue('providedSlots') is TJSONArray) then Exit;
      for S in TJSONArray(O.GetValue('providedSlots')) do
        if not (S is TJSONString) or not ((S.Value='singing') or (S.Value='performance') or MusicStudioSmallSlot(S.Value) or (S.Value='animation')) then Exit;
    end;
    for S in TJSONArray(O.GetValue('slots')) do for C in TJSONArray(TJSONObject(S).GetValue('clips')) do
      if Patterns.TryGetValue(TJSONObject(C).GetValue<string>('patternId'),K) and (K<>Attribute) then begin
        ErrorText := '配置済み共通演奏と演奏者の属性が一致しません。'; Exit;
      end;
  end;
  Result := True;
  finally Patterns.Free; end;
end;
procedure MusicStudioSetPerformer(Root: TJSONObject; Index: Integer; const Attribute: string; const Slots: TArray<string>; UpdateSlots: Boolean; const ChoicesJSON: string);
var O,S: TJSONObject; A,Accepts: TJSONArray; Kind: string; V: TJSONValue; I: Integer; Found: Boolean;
begin
  if (Attribute<>'') and (PerformanceKindIndex(Attribute)<0) then raise Exception.Create('未対応の演奏属性です。');
  O := Track(Root,Index); if O.GetValue<string>('kind','')<>'psd' then raise Exception.Create('演奏者トラックを選択してください。');
  Put(O,'role',TJSONString.Create('performer')); Put(O,'performanceAttribute',TJSONString.Create(Attribute));
  if not UpdateSlots then Exit;
  Accepts := TJSONArray.Create; for Kind in Slots do Accepts.Add(Kind); Put(O,'providedSlots',Accepts);
  A := TJSONArray(O.GetValue('slots'));
  for I := A.Count-1 downto 0 do begin
    S := TJSONObject(A[I]);
    if (S.GetValue<string>('kind')='animation') and (S.GetValue<string>('name')='ポーズ') and
      (S.GetValue('autoFromPSD') is TJSONBool) and S.GetValue<Boolean>('autoFromPSD') then Put(S,'kind',TJSONString.Create('pose'));
    if (S.GetValue('autoFromPSD') is TJSONBool) and S.GetValue<Boolean>('autoFromPSD') and
      (TJSONArray(S.GetValue('clips')).Count=0) then begin
      Found := False; for Kind in Slots do if Kind=S.GetValue<string>('kind') then Found := True;
      if not Found then A.Remove(I).Free;
    end;
  end;
  for Kind in Slots do begin
    Found := False;
    for V in A do if TJSONObject(V).GetValue<string>('kind','')=Kind then Found := True;
    if Found then Continue;
    S := TJSONObject.Create; S.AddPair('id',NewID); S.AddPair('kind',Kind);
    if Kind='singing' then S.AddPair('name','歌唱')
    else if Kind='performance' then S.AddPair('name','演奏')
    else S.AddPair('name',MusicStudioSelectionRow(Kind));
    S.AddPair('color','#90C4E0'); S.AddPair('order',TJSONNumber.Create(A.Count));
    Accepts := TJSONArray.Create; if MusicStudioSmallSlot(Kind) then Accepts.Add('selection') else Accepts.Add(Kind); S.AddPair('accepts',Accepts);
    S.AddPair('clips',TJSONArray.Create); S.AddPair('autoFromPSD',TJSONBool.Create(True)); A.AddElement(S);
  end;
  for I := 0 to A.Count-1 do Put(TJSONObject(A[I]),'order',TJSONNumber.Create(I));
  if ChoicesJSON<>'' then MusicStudioSmallChoices(Root,Index,ChoicesJSON);
end;
function MusicStudioCopyTrack(Root: TJSONObject; Index: Integer): string;
begin Result := Track(Root,Index).ToJSON; end;
function MusicStudioPasteTrack(Root: TJSONObject; const Text: string): Integer;
var V,S,C: TJSONValue; O,Slot,Clip: TJSONObject; A: TJSONArray; ID: string;
begin
  V := TJSONObject.ParseJSONValue(Text);
  try
    if not (V is TJSONObject) then raise Exception.Create('トラックのコピーがありません。');
    O := TJSONObject(V);
    if not (O.GetValue<string>('kind','')='psd') and not (O.GetValue<string>('kind','')='audio') then
      raise Exception.Create('未対応のトラックです。');
    Put(O,'id',TJSONString.Create(NewID)); Put(O,'name',TJSONString.Create(O.GetValue<string>('name','')+' コピー'));
    for S in TJSONArray(O.GetValue('slots')) do begin
      Slot := TJSONObject(S); ID := NewID; Put(Slot,'id',TJSONString.Create(ID));
      for C in TJSONArray(Slot.GetValue('clips')) do begin
        Clip := TJSONObject(C); Put(Clip,'id',TJSONString.Create(NewID)); Put(Clip,'slotId',TJSONString.Create(ID));
      end;
    end;
    A := TJSONArray(Root.GetValue('tracks')); Result := A.Count; A.AddElement(O); V := nil;
  finally V.Free; end;
end;
end.
