unit SYNC_MusicStudio_AnimationSlotData;
// Direct animation intervals belong to the project. Shared presets and PSD files are never changed.
interface
uses System.JSON;
// 借用Root内で未参照になった作品内motion設定だけを削除する。共有参照/素材実体は保持する。
procedure PruneMusicStudioAnimations(Root: TJSONObject);
// 候補Rootへ区間または種類変更を反映する。VariantはRhythmTypeの序数、範囲は秒。
// 既存配置ID/範囲を保ち設定を分離する。例外時の原子性は呼出元の候補Root検証で保証する。
procedure MusicStudioWriteAnimationElement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex,Variant: Integer;
  StartSeconds,LengthSeconds: Double);
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_MotionData;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := GUIDToString(G); end;
procedure Put(O: TJSONObject; const K: string; V: TJSONValue);
begin O.RemovePair(K).Free; O.AddPair(K,V); end;
procedure PruneMusicStudioAnimations(Root: TJSONObject);
var Used: TDictionary<string,Boolean>; T,S,C: TJSONValue; Patterns: TJSONArray; I: Integer; P: TJSONObject;
begin
  Patterns := Root.GetValue('patterns') as TJSONArray; if Patterns=nil then Exit;
  Used := TDictionary<string,Boolean>.Create;
  try
    for T in TJSONArray(Root.GetValue('tracks')) do if (T is TJSONObject) and (TJSONObject(T).GetValue('slots') is TJSONArray) then
      for S in TJSONArray(TJSONObject(T).GetValue('slots')) do for C in TJSONArray(TJSONObject(S).GetValue('clips')) do
        Used.AddOrSetValue(TJSONObject(C).GetValue<string>('patternId'),True);
    for I := Patterns.Count-1 downto 0 do begin
      P := TJSONObject(Patterns[I]);
      if (P.GetValue<string>('kind','')='animation') and (P.GetValue('motion') is TJSONObject) and
        not Used.ContainsKey(P.GetValue<string>('id')) then Patterns.Remove(I).Free;
    end;
  finally Used.Free; end;
end;
procedure MusicStudioWriteAnimationElement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex,Variant: Integer;
  StartSeconds,LengthSeconds: Double);
var T: TMusicStudioTrack; S: TMusicStudioSlot; Patterns,Slots: TJSONArray; C,P,Old: TJSONObject;
  V: TJSONValue; Config: TMusicStudioMotionConfig; Error,ID,Caption: string;
begin
  T := MusicStudioTrackAt(Root,TrackIndex);
  if (SlotIndex<0) or (SlotIndex>=Length(T.Slots)) then raise Exception.Create('アニメーション枠がありません。');
  S := T.Slots[SlotIndex];
  if (T.Kind<>'psd') or (MusicStudioAnimationSource(S.Kind)='') then raise Exception.Create('同期アニメーション枠を選択してください。');
  if (Variant<Ord(Low(TMusicStudioRhythmType))) or (Variant>Ord(High(TMusicStudioRhythmType))) then raise Exception.Create('アニメーションの種類が不正です。');
  if (ClipIndex < -1) or (ClipIndex>=Length(S.Clips)) then raise Exception.Create('配置がありません。');
  if IsNan(StartSeconds) or IsInfinite(StartSeconds) or IsNan(LengthSeconds) or IsInfinite(LengthSeconds) or
    (StartSeconds<0) or (LengthSeconds<0.001) or (StartSeconds+LengthSeconds>604800) then raise Exception.Create('区間が範囲外です。');
  Patterns := Root.GetValue('patterns') as TJSONArray;
  if Patterns=nil then begin Patterns := TJSONArray.Create; Root.AddPair('patterns',Patterns); end;
  Slots := TJSONObject(TJSONArray(Root.GetValue('tracks'))[TrackIndex]).GetValue('slots') as TJSONArray;
  C := nil; Old := nil;
  if ClipIndex>=0 then begin
    C := TJSONObject(TJSONArray(TJSONObject(Slots[SlotIndex]).GetValue('clips'))[ClipIndex]);
    for V in Patterns do if TJSONObject(V).GetValue<string>('id')=C.GetValue<string>('patternId') then Old := TJSONObject(V);
  end;
  Config := TMusicStudioMotionConfig.Create; P := nil;
  try
    if (Old<>nil) and (Old.GetValue('motion')<>nil) then Config.LoadJSON(Old.GetValue('motion').ToJSON);
    Config.RhythmType := TMusicStudioRhythmType(Variant);
    Caption := MusicStudioRhythmCaption(Config.RhythmType); if Config.RhythmType=rmtBounce then Caption := '縮み・伸び';
    if Old<>nil then P := Old.Clone as TJSONObject else P := TJSONObject.Create;
    P.RemovePair('reference').Free;
    ID := NewID; Put(P,'id',TJSONString.Create(ID)); Put(P,'kind',TJSONString.Create('animation'));
    Put(P,'name',TJSONString.Create(Caption)); Put(P,'color',TJSONString.Create(S.Color));
    Put(P,'motion',TJSONObject.ParseJSONValue(Config.ToJSON)); Patterns.AddElement(P); P := nil;
    if C<>nil then Put(C,'patternId',TJSONString.Create(ID))
    else if not MusicStudioAddPlacement(Root,TrackIndex,SlotIndex,ID,StartSeconds,LengthSeconds,Error) then raise Exception.Create(Error);
    PruneMusicStudioAnimations(Root);
  finally P.Free; Config.Free; end;
end;
end.
