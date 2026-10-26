unit SYNC_MusicStudio_ArrangementData;

// 汎用スロットと配置。トラックの描画媒体と受入属性を分離し、旧clipsを移行する。
interface
uses System.JSON, SYNC_MusicStudio_PsdTransform;
type
  TMusicStudioPlacement = record
    ID, PatternID, SlotID: string;
    StartSeconds, LengthSeconds, StartBeat, LengthBeats: Double;
    TimeBase: string;
  end;
  TMusicStudioSlot = record
    ID, Kind, Name, Color: string;
    Order: Integer;
    Accepts: TArray<string>;
    Choices: TArray<string>; // PSDの意味名候補。仮想通常/非表示はここへ混ぜない。
    Clips: TArray<TMusicStudioPlacement>;
  end;
  TMusicStudioTrack = record
    ID, Kind, Name, Color, PsdPath, PsdAssetID, Role, PerformanceAttribute: string;
    PsdTransform: TMusicStudioPsdTransform;
    Slots: TArray<TMusicStudioSlot>;
    ProvidedSlots: TArray<string>; // PSD解析が提供した能力。既存の手動/配置済み枠とは区別する。
    HasCapabilityMetadata: Boolean;
    Clips: TArray<TMusicStudioPlacement>; // 旧単一スロットAPIの読取互換。先頭スロットのみ。
  end;
// 検証のみ。旧1/新2を識別し、ID・受入属性・親slotId・時刻を確認する。Rootは変更しない。
function ValidateMusicStudioArrangement(Root: TJSONObject; out ErrorText: string): Boolean;
// 検証済みRootの旧clipsを既定スロットへ置換する。呼出側で移行後も再検証してから採用する。
function UpgradeMusicStudioArrangement(Root: TJSONObject; out ErrorText: string): Boolean;
// JSONを所有しない値のスナップショットを返す。結果への変更はRootへ反映されない。
function MusicStudioTrackAt(Root: TJSONObject; Index: Integer): TMusicStudioTrack;
// 作業文書へ固定ID付きのトラック/スロットを追加する。素材実体を操作しない。
function MusicStudioAddTrack(Root: TJSONObject; const Kind: string): Integer;
function MusicStudioAddSlot(Root: TJSONObject; TrackIndex: Integer; const Kind: string): Integer;
// 既存配置が使用する受入属性は外せない。FalseのときはRootを変更しない。
function MusicStudioUpdateSlot(Root: TJSONObject; TrackIndex, SlotIndex: Integer;
  const Name, Color: string; const Accepts: TArray<string>; out ErrorText: string): Boolean;
// 指定枠とその配置だけを削除し順番を詰める。元パターンと他の枠は保持する。
procedure MusicStudioRemoveSlot(Root: TJSONObject; TrackIndex, SlotIndex: Integer);
// ID/配置参照/拡張フィールドを保持して配列順とorderを変更する。
procedure MusicStudioReorderSlot(Root: TJSONObject; TrackIndex, FromIndex, ToIndex: Integer);
// 指定スロットのacceptsと時刻を検証し、新配置IDを発行する。Falseなら変更しない。
function MusicStudioAddPlacement(Root: TJSONObject; TrackIndex, SlotIndex: Integer;
  const PatternID: string; StartSeconds, LengthSeconds: Double; out ErrorText: string): Boolean; overload;
function MusicStudioAddPlacement(Root: TJSONObject; TrackIndex: Integer;
  const PatternID: string; StartSeconds, LengthSeconds: Double; out ErrorText: string): Boolean; overload;
procedure MusicStudioUpdateTrack(Root: TJSONObject; Index: Integer; const Name, Color, PsdPath: string);
procedure MusicStudioSetPlacementBeats(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer; StartBeat,LengthBeats: Double);
procedure MusicStudioAssignPsd(Root: TJSONObject; Index: Integer; const AssetID: string);
procedure MusicStudioSetPsdTransform(Root: TJSONObject; Index: Integer; const Transform: TMusicStudioPsdTransform);
procedure MusicStudioReorderTrack(Root: TJSONObject; FromIndex,ToIndex: Integer);
procedure MusicStudioRemoveTrack(Root: TJSONObject; Index: Integer);
procedure MusicStudioRemovePlacement(Root: TJSONObject; TrackIndex, SlotIndex, ClipIndex: Integer); overload;
procedure MusicStudioRemovePlacement(Root: TJSONObject; TrackIndex, ClipIndex: Integer); overload;
procedure MusicStudioMovePlacement(Root: TJSONObject; TrackIndex, SlotIndex, ClipIndex: Integer;
  StartSeconds, LengthSeconds: Double); overload;
procedure MusicStudioMovePlacement(Root: TJSONObject; TrackIndex, ClipIndex: Integer;
  StartSeconds, LengthSeconds: Double); overload;
function MusicStudioPatternInUse(Root: TJSONObject; const PatternID: string): Boolean;
function MusicStudioSlotCompatible(const PatternKind: string; const Slot: TMusicStudioSlot; out Reason: string): Boolean;
// 旧トラック直下clipsの検証専用。新UIの適合性にはSlotCompatibleを使う。
function MusicStudioCompatible(const PatternKind, TrackKind: string; out Reason: string): Boolean;
function MusicStudioSlotKindName(const Kind: string): string;
// New animation slots accept shared animation patterns; synchronization belongs to the placement's slot.
function MusicStudioAnimationSource(const Kind: string): string;
function MusicStudioCanAddAnimationSlot(const Track: TMusicStudioTrack; const Kind: string): Boolean;
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_ClipTempo,
  SYNC_MusicStudio_SmallSlotData;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := GUIDToString(G); end;
procedure Put(Obj: TJSONObject; const Key: string; Value: TJSONValue);
begin Obj.RemovePair(Key).Free; Obj.AddPair(Key, Value); end;
function TextField(Obj: TJSONObject; const Key: string; out Value: string): Boolean;
begin
  Result := Obj.GetValue(Key) is TJSONString;
  if Result then Value := Obj.GetValue(Key).Value else Value := '';
end;
function ColorValid(const Value: string): Boolean;
var I: Integer;
begin
  Result := (Length(Value) = 7) and (Value[1] = '#');
  if Result then for I := 2 to 7 do if not CharInSet(Value[I], ['0'..'9','a'..'f','A'..'F']) then Exit(False);
end;
function NumberField(Obj: TJSONObject; const Key: string; Minimum, Maximum: Double): Boolean;
var N: Double;
begin
  Result := Obj.GetValue(Key) is TJSONNumber; if not Result then Exit;
  N := TJSONNumber(Obj.GetValue(Key)).AsDouble;
  Result := not IsNan(N) and not IsInfinite(N) and (N >= Minimum) and (N <= Maximum);
end;
function MusicStudioAnimationSource(const Kind: string): string;
begin
  Result := '';
  if Kind='animationSinging' then Result := 'singing'
  else if Kind='animationPerformance' then Result := 'performance'
  else if Kind='animationRhythm' then Result := 'tempo';
end;
function MusicStudioCanAddAnimationSlot(const Track: TMusicStudioTrack; const Kind: string): Boolean;
var Slot: TMusicStudioSlot; Source: string;
begin
  Result := False; Source := MusicStudioAnimationSource(Kind);
  if (Track.Kind<>'psd') or (Source='') then Exit;
  if Source='tempo' then Exit(True);
  for Slot in Track.Slots do if Slot.Kind=Source then Exit(True);
end;
function MusicStudioSlotKindName(const Kind: string): string;
begin
  if Kind = 'audio' then Result := '音声'
  else if Kind = 'singing' then Result := '歌唱 / 口パク'
  else if Kind = 'psd' then Result := 'PSD割当'
  else if Kind = 'instrument' then Result := '楽器'
  else if Kind = 'animationSinging' then Result := 'アニメーション（歌唱）'
  else if Kind = 'animationPerformance' then Result := 'アニメーション（演奏）'
  else if Kind = 'animationRhythm' then Result := 'アニメーション（リズム）'
  else if Kind = 'animation' then Result := 'アニメーション'
  else if Kind = 'performance' then Result := '演奏'
  else if Kind = 'tempo' then Result := 'テンポ'
  else if Kind = 'customExpression' then Result := '表情カスタム'
  else if Kind = 'emotion' then Result := '表情'
  else if Kind = 'face' then Result := '顔色'
  else if Kind = 'pose' then Result := 'ポーズ'
  else if Kind = 'symbol' then Result := '記号'
  else if Kind = 'rhythm' then Result := 'リズム同期（属性編集・描画は準備中）'
  else if Kind = 'generic' then Result := '汎用'
  else Result := '未対応属性: ' + Kind;
end;
function DefaultAccepts(const Kind: string): TArray<string>;
begin
  if MusicStudioAnimationSource(Kind)<>'' then Exit(TArray<string>.Create('animation'));
  if Kind = 'customExpression' then Result := TArray<string>.Create('emotion')
  else if Kind = 'generic' then Result := TArray<string>.Create('audio','singing')
  else Result := TArray<string>.Create(Kind);
end;
function ContainsKind(const Accepts: TArray<string>; const Kind: string): Boolean;
var S: string;
begin for S in Accepts do if S = Kind then Exit(True); Result := False; end;
function MusicStudioSlotCompatible(const PatternKind: string; const Slot: TMusicStudioSlot; out Reason: string): Boolean;
begin
  Result := ContainsKind(Slot.Accepts, PatternKind);
  if Result then Reason := ''
  else Reason := '「' + Slot.Name + '」スロットは属性「' + PatternKind + '」を受け入れません。';
end;
function MusicStudioCompatible(const PatternKind, TrackKind: string; out Reason: string): Boolean;
var Slot: TMusicStudioSlot;
begin
  Slot := Default(TMusicStudioSlot);
  if TrackKind = 'audio' then Slot.Kind := 'audio' else if TrackKind = 'psd' then Slot.Kind := 'singing';
  Slot.Name := MusicStudioSlotKindName(Slot.Kind); Slot.Accepts := DefaultAccepts(Slot.Kind);
  Result := MusicStudioSlotCompatible(PatternKind,Slot,Reason);
end;
function ArrangementVersion(Root: TJSONObject; out Version: Integer; out ErrorText: string): Boolean;
var V: TJSONValue;
begin
  V := Root.GetValue('arrangementVersion'); Version := 1; Result := V = nil; if Result then Exit;
  Result := (V is TJSONNumber) and TryStrToInt(V.Value,Version) and (Version in [1,2,3]);
  if not Result then ErrorText := 'arrangementVersionは1（旧clips）、2（スロット）、3（拍の演奏配置）に対応します。';
end;
function ReadAccepts(Obj: TJSONObject; out Accepts: TArray<string>): Boolean;
var A: TJSONArray; I,J: Integer;
begin
  Result := False; Accepts := nil; if not (Obj.GetValue('accepts') is TJSONArray) then Exit;
  A := TJSONArray(Obj.GetValue('accepts')); if A.Count = 0 then Exit; SetLength(Accepts,A.Count);
  for I := 0 to A.Count - 1 do begin
    if not (A.Items[I] is TJSONString) or (Trim(A.Items[I].Value) = '') then Exit;
    Accepts[I] := A.Items[I].Value;
    for J := 0 to I - 1 do if Accepts[J] = Accepts[I] then Exit;
  end;
  Result := True;
end;
function UniqueID(const ID: string; IDs: TDictionary<string,string>; out ErrorText: string): Boolean;
begin
  Result := not IDs.ContainsKey(ID);
  if Result then IDs.Add(ID,'used')
  else ErrorText := 'トラック・スロット・パターン・配置のIDが重複しています: ' + ID;
end;
function ValidateClips(Clips: TJSONArray; const SlotID: string; const Accepts: TArray<string>;
  Version: Integer; IDs,PatternKinds: TDictionary<string,string>; out ErrorText: string): Boolean;
var CV: TJSONValue; Clip: TJSONObject; ID,PatternID,Kind: string;
begin
  Result := False;
  for CV in Clips do begin
    ErrorText := '配置にはid、patternId、開始秒と正の長さが必要です。';
    if not (CV is TJSONObject) then Exit; Clip := TJSONObject(CV);
    if not TextField(Clip,'id',ID) or (Trim(ID) = '') or not TextField(Clip,'patternId',PatternID) or
      not NumberField(Clip,'startSeconds',0,604800) or not NumberField(Clip,'lengthSeconds',1E-9,604800) then Exit;
    if not UniqueID(ID,IDs,ErrorText) then Exit;
    if (Version = 1) and Assigned(Clip.GetValue('slotId')) then begin
      ErrorText := '旧clips内のslotIdは上書きできません。スロット形式はarrangementVersion=2で指定してください。'; Exit;
    end;
    ErrorText := '配置のslotIdが親スロットと一致しません。';
    if Version >= 2 then if not (Clip.GetValue('slotId') is TJSONString) or (Clip.GetValue('slotId').Value <> SlotID) then Exit;
    ErrorText := '配置が参照するパターンがありません: ' + PatternID;
    if not PatternKinds.TryGetValue(PatternID,Kind) then Exit;
      if Kind='tempo' then try ValidateMusicStudioTempoOverrides(Clip.GetValue('tempoOverrides'));
        except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
    if (Kind<>'performance') and (Kind<>'tempo') and (TJSONNumber(Clip.GetValue('lengthSeconds')).AsDouble<0.001) then Exit;
    ErrorText := '配置の属性「' + Kind + '」をスロットが受け入れません。';
    if not ContainsKind(Accepts,Kind) then Exit;
    if (Kind='performance') or (Kind='tempo') then begin
      ErrorText := '演奏配置はarrangementVersion=3、timeBase=beatsと拍の開始/長さが必要です。';
      // 秒だけの旧予約は移行できる。既存の拍正本は全フィールドを検証し、部分指定は拒否する。
      if not ((Version=2) and (Clip.GetValue('timeBase')=nil) and (Clip.GetValue('startBeat')=nil) and
        (Clip.GetValue('lengthBeats')=nil)) then begin
        if not (Version in [2,3]) or not (Clip.GetValue('timeBase') is TJSONString) or (Clip.GetValue('timeBase').Value<>'beats') or
          not NumberField(Clip,'startBeat',0,1000000) or not NumberField(Clip,'lengthBeats',0.001,1000000) then Exit;
        if TJSONNumber(Clip.GetValue('startBeat')).AsDouble+TJSONNumber(Clip.GetValue('lengthBeats')).AsDouble>1000000 then begin
          ErrorText := '演奏配置の終了拍が上限1000000拍を超えています。'; Exit;
        end;
      end;
    end else if ((Kind='audio') or (Kind='singing')) and Assigned(Clip.GetValue('timeBase')) and
      (Clip.GetValue('timeBase').Value<>'seconds') then begin ErrorText := '音声/歌唱MIDI配置は秒を正本として保存してください。'; Exit; end;
    ErrorText := '配置の終了時刻が上限604800秒を超えています。';
    if TJSONNumber(Clip.GetValue('startSeconds')).AsDouble + TJSONNumber(Clip.GetValue('lengthSeconds')).AsDouble > 604800 then Exit;
  end;
  Result := True;
end;
function ValidateMusicStudioArrangement(Root: TJSONObject; out ErrorText: string): Boolean;
var Tracks,Patterns,Slots: TJSONArray; V,SV: TJSONValue; Obj,Pattern,SObj: TJSONObject;
  IDs,PatternKinds: TDictionary<string,string>; ID,Kind,Name,Color,SlotID: string;
  Version,I,Order: Integer; Accepts: TArray<string>; Transform: TMusicStudioPsdTransform;
begin
  Result := False; ErrorText := ''; if not ArrangementVersion(Root,Version,ErrorText) then Exit;
  Tracks := TJSONArray(Root.GetValue('tracks')); Patterns := Root.GetValue('patterns') as TJSONArray;
  IDs := TDictionary<string,string>.Create; PatternKinds := TDictionary<string,string>.Create;
  try
    if Assigned(Patterns) then for V in Patterns do begin
      Pattern := TJSONObject(V); ID := Pattern.GetValue('id').Value;
      if not UniqueID(ID,IDs,ErrorText) then Exit; PatternKinds.Add(ID,Pattern.GetValue('kind').Value);
    end;
    for V in Tracks do begin
      if not (V is TJSONObject) then Continue; Obj := TJSONObject(V);
      if not TextField(Obj,'kind',Kind) then Continue;
      if (Kind <> 'audio') and (Kind <> 'psd') then Continue;
      ErrorText := '既知トラックにはid、name、#RRGGBBのcolorが必要です。';
      if not TextField(Obj,'id',ID) or (Trim(ID) = '') or not TextField(Obj,'name',Name) or
        (Trim(Name) = '') or not TextField(Obj,'color',Color) or not ColorValid(Color) then Exit;
      if not UniqueID(ID,IDs,ErrorText) then Exit;
      if Kind = 'psd' then begin
        ErrorText := 'PSDトラックのpsd.filePathは文字列で指定してください。';
        if not (Obj.GetValue('psd') is TJSONObject) or not TextField(TJSONObject(Obj.GetValue('psd')),'filePath',Name) then Exit;
        if not ReadMusicStudioPsdTransform(TJSONObject(Obj.GetValue('psd')).GetValue('transform'),Transform,ErrorText) then Exit;
      end;
      if Version = 1 then begin
        ErrorText := '旧トラックにはclips配列が必要です。slots形式にはarrangementVersion=2を指定してください。';
        if not (Obj.GetValue('clips') is TJSONArray) or Assigned(Obj.GetValue('slots')) then Exit;
        if Kind = 'audio' then Accepts := DefaultAccepts('audio') else Accepts := DefaultAccepts('singing');
        if not ValidateClips(TJSONArray(Obj.GetValue('clips')),'',Accepts,Version,IDs,PatternKinds,ErrorText) then Exit;
        Continue;
      end;
      ErrorText := '新トラックにはslots配列が必要です。clipsとの併記はできません。';
      if not (Obj.GetValue('slots') is TJSONArray) or Assigned(Obj.GetValue('clips')) then Exit;
      Slots := TJSONArray(Obj.GetValue('slots')); I := 0;
      for SV in Slots do begin
        ErrorText := 'スロットにはid、kind、name、color、order、accepts、clipsが必要です。';
        if not (SV is TJSONObject) then Exit; SObj := TJSONObject(SV);
        if not TextField(SObj,'id',SlotID) or (Trim(SlotID) = '') or not TextField(SObj,'kind',Name) or
          (Trim(Name) = '') or not TextField(SObj,'name',Name) or (Trim(Name) = '') or
          not TextField(SObj,'color',Color) or not ColorValid(Color) or not (SObj.GetValue('order') is TJSONNumber) or
          not TryStrToInt(SObj.GetValue('order').Value,Order) or not (SObj.GetValue('clips') is TJSONArray) or not ReadAccepts(SObj,Accepts) then Exit;
        if (MusicStudioAnimationSource(SObj.GetValue<string>('kind'))<>'') and
          ((Length(Accepts)<>1) or (Accepts[0]<>'animation')) then begin
          ErrorText := 'アニメーションスロットの受入属性はアニメーションです。'; Exit;
        end;
        ErrorText := 'スロットorderは配列順の0始まり連番にしてください。';
        if Order <> I then Exit; Inc(I); if not UniqueID(SlotID,IDs,ErrorText) then Exit;
        if not ValidateClips(TJSONArray(SObj.GetValue('clips')),SlotID,Accepts,Version,IDs,PatternKinds,ErrorText) then Exit;
      end;
    end;
    Result := True; ErrorText := '';
  finally PatternKinds.Free; IDs.Free; end;
end;
function NewSlot(const ID,Kind,Color: string; Order: Integer): TJSONObject;
var A: TJSONArray; S: string;
begin
  Result := TJSONObject.Create; Result.AddPair('id',ID); Result.AddPair('kind',Kind);
  Result.AddPair('name',MusicStudioSlotKindName(Kind)); Result.AddPair('color',Color);
  Result.AddPair('order',TJSONNumber.Create(Order)); A := TJSONArray.Create;
  for S in DefaultAccepts(Kind) do A.Add(S); Result.AddPair('accepts',A); Result.AddPair('clips',TJSONArray.Create);
end;
function UpgradeMusicStudioArrangement(Root: TJSONObject; out ErrorText: string): Boolean;
var V,C: TJSONValue; Obj,Slot: TJSONObject; Slots,Clips: TJSONArray;
  Version: Integer; Kind,ID: string; Changed: Boolean;
  function UpgradeReservedPerformance: Boolean;
  var Patterns: TJSONValue; P,T,S,C: TJSONValue; Track,Clip: TJSONObject;
    PerformanceIDs: TDictionary<string,Boolean>; Timing: TMusicStudioTempoMap;
    StartBeat,EndBeat: Double; Upgraded: Boolean;
  begin
    Result := True; if Version<>2 then Exit;
    Patterns := Root.GetValue('patterns'); if not (Patterns is TJSONArray) then Exit;
    PerformanceIDs := TDictionary<string,Boolean>.Create; Timing := TMusicStudioTempoMap.Create;
    try
      for P in TJSONArray(Patterns) do if TJSONObject(P).GetValue('kind').Value='performance' then
        PerformanceIDs.Add(TJSONObject(P).GetValue('id').Value,True);
      if PerformanceIDs.Count=0 then Exit;
      Timing.LoadJSON(Root.GetValue('timing') as TJSONObject); Upgraded := False;
      for T in TJSONArray(Root.GetValue('tracks')) do begin
        if not (T is TJSONObject) then Continue; Track := TJSONObject(T);
        if not TextField(Track,'kind',Kind) or ((Kind<>'audio') and (Kind<>'psd')) then Continue;
        for S in TJSONArray(Track.GetValue('slots')) do
          for C in TJSONArray(TJSONObject(S).GetValue('clips')) do begin
            Clip := TJSONObject(C);
            if not PerformanceIDs.ContainsKey(Clip.GetValue('patternId').Value) then Continue;
            // 検証済みの拍正本があれば秒から再計算せず、その座標を保持する。
            if Clip.GetValue('timeBase')<>nil then begin Upgraded := True; Continue; end;
            StartBeat := Timing.SecondsToBeat(TJSONNumber(Clip.GetValue('startSeconds')).AsDouble);
            EndBeat := Timing.SecondsToBeat(TJSONNumber(Clip.GetValue('startSeconds')).AsDouble+TJSONNumber(Clip.GetValue('lengthSeconds')).AsDouble);
            if (StartBeat<0) or (EndBeat>1000000) or (EndBeat-StartBeat<0.001) then begin
              ErrorText := '旧演奏配置を拍へ移行できません。拍の上限または長さを超えています。'; Exit(False);
            end;
            Put(Clip,'timeBase',TJSONString.Create('beats')); Put(Clip,'startBeat',TJSONNumber.Create(StartBeat));
            Put(Clip,'lengthBeats',TJSONNumber.Create(EndBeat-StartBeat)); Upgraded := True;
          end;
      end;
      if Upgraded then Put(Root,'arrangementVersion',TJSONNumber.Create(3));
    finally Timing.Free; PerformanceIDs.Free; end;
  end;
begin
  Result := False; Changed := False; if not ArrangementVersion(Root,Version,ErrorText) then Exit;
  if Version >= 2 then Exit(UpgradeReservedPerformance);
  for V in TJSONArray(Root.GetValue('tracks')) do begin
    if not (V is TJSONObject) then Continue; Obj := TJSONObject(V);
    if not TextField(Obj,'kind',Kind) then Continue; if (Kind <> 'audio') and (Kind <> 'psd') then Continue;
    ID := 'legacy-slot:' + Obj.GetValue('id').Value;
    if Kind = 'audio' then Kind := 'audio' else Kind := 'singing';
    Slot := NewSlot(ID,Kind,Obj.GetValue('color').Value,0);
    Clips := TJSONArray(TJSONObject.ParseJSONValue(Obj.GetValue('clips').ToJSON));
    for C in Clips do Put(TJSONObject(C),'slotId',TJSONString.Create(ID));
    Put(Slot,'clips',Clips); Slot.AddPair('migratedFrom','track.clips');
    Slots := TJSONArray.Create; Slots.AddElement(Slot); Obj.AddPair('slots',Slots);
    Obj.RemovePair('clips').Free; Changed := True;
  end;
  if Changed then begin Put(Root,'arrangementVersion',TJSONNumber.Create(2)); Version := 2; end;
  Result := UpgradeReservedPerformance;
end;
function TrackObject(Root: TJSONObject; Index: Integer): TJSONObject;
begin Result := TJSONObject(TJSONArray(Root.GetValue('tracks')).Items[Index]); end;
function SlotArray(Root: TJSONObject; TrackIndex: Integer): TJSONArray;
begin Result := TJSONArray(TrackObject(Root,TrackIndex).GetValue('slots')); end;
function SlotObject(Root: TJSONObject; TrackIndex,SlotIndex: Integer): TJSONObject;
begin Result := TJSONObject(SlotArray(Root,TrackIndex).Items[SlotIndex]); end;
function MusicStudioTrackAt(Root: TJSONObject; Index: Integer): TMusicStudioTrack;
var Obj,SObj,Clip: TJSONObject; V,Choice: TJSONValue; Slots,Clips: TJSONArray; I,J: Integer; ErrorText: string;
begin
  Result := Default(TMusicStudioTrack); V := TJSONArray(Root.GetValue('tracks')).Items[Index];
  if not (V is TJSONObject) then begin Result.Name := '未対応の旧トラック'; Exit; end;
  Obj := TJSONObject(V); TextField(Obj,'id',Result.ID); TextField(Obj,'kind',Result.Kind);
  TextField(Obj,'name',Result.Name); TextField(Obj,'color',Result.Color);
  if (Result.Kind <> 'audio') and (Result.Kind <> 'psd') then begin
    if Result.Name = '' then Result.Name := '未対応の旧トラック'; Exit;
  end;
  if Result.Kind = 'psd' then begin
    TextField(TJSONObject(Obj.GetValue('psd')),'filePath',Result.PsdPath);
    TextField(TJSONObject(Obj.GetValue('psd')),'assetId',Result.PsdAssetID);
    ReadMusicStudioPsdTransform(TJSONObject(Obj.GetValue('psd')).GetValue('transform'),Result.PsdTransform,ErrorText);
    TextField(Obj,'role',Result.Role);
    TextField(Obj,'performanceAttribute',Result.PerformanceAttribute);
    Result.HasCapabilityMetadata := Obj.GetValue('providedSlots') is TJSONArray;
    if Obj.GetValue('providedSlots') is TJSONArray then
      for V in TJSONArray(Obj.GetValue('providedSlots')) do Result.ProvidedSlots := Result.ProvidedSlots+[V.Value];
  end;
  Slots := TJSONArray(Obj.GetValue('slots')); SetLength(Result.Slots,Slots.Count);
  for I := 0 to Slots.Count - 1 do begin
    SObj := TJSONObject(Slots.Items[I]); TextField(SObj,'id',Result.Slots[I].ID); TextField(SObj,'kind',Result.Slots[I].Kind);
    TextField(SObj,'name',Result.Slots[I].Name); TextField(SObj,'color',Result.Slots[I].Color);
    Result.Slots[I].Order := I; ReadAccepts(SObj,Result.Slots[I].Accepts);
    if SObj.GetValue('choices') is TJSONArray then for Choice in TJSONArray(SObj.GetValue('choices')) do
      Result.Slots[I].Choices := Result.Slots[I].Choices+[Choice.Value];
    Clips := TJSONArray(SObj.GetValue('clips')); SetLength(Result.Slots[I].Clips,Clips.Count);
    for J := 0 to Clips.Count - 1 do begin
      Clip := TJSONObject(Clips.Items[J]); Result.Slots[I].Clips[J].ID := Clip.GetValue('id').Value;
      Result.Slots[I].Clips[J].PatternID := Clip.GetValue('patternId').Value;
      Result.Slots[I].Clips[J].SlotID := Clip.GetValue('slotId').Value;
      Result.Slots[I].Clips[J].StartSeconds := TJSONNumber(Clip.GetValue('startSeconds')).AsDouble;
      Result.Slots[I].Clips[J].LengthSeconds := TJSONNumber(Clip.GetValue('lengthSeconds')).AsDouble;
      TextField(Clip,'timeBase',Result.Slots[I].Clips[J].TimeBase);
      if Clip.GetValue('startBeat') is TJSONNumber then Result.Slots[I].Clips[J].StartBeat := TJSONNumber(Clip.GetValue('startBeat')).AsDouble;
      if Clip.GetValue('lengthBeats') is TJSONNumber then Result.Slots[I].Clips[J].LengthBeats := TJSONNumber(Clip.GetValue('lengthBeats')).AsDouble;
    end;
  end;
  if Slots.Count > 0 then Result.Clips := Result.Slots[0].Clips;
end;
procedure MusicStudioSetPsdTransform(Root: TJSONObject; Index: Integer; const Transform: TMusicStudioPsdTransform);
var Obj: TJSONObject;
begin
  Obj := TrackObject(Root,Index);
  if Obj.GetValue('kind').Value<>'psd' then raise EArgumentException.Create('PSDトラックを選択してください。');
  WriteMusicStudioPsdTransform(TJSONObject(Obj.GetValue('psd')),Transform);
end;
function MusicStudioAddSlot(Root: TJSONObject; TrackIndex: Integer; const Kind: string): Integer;
var Items: TJSONArray; Color: string;
begin
  if MusicStudioAnimationSource(Kind)<>'' then begin
    if not MusicStudioCanAddAnimationSlot(MusicStudioTrackAt(Root,TrackIndex),Kind) then
      raise Exception.Create('対応する歌唱・演奏スロットが必要です。');
    Items := SlotArray(Root,TrackIndex); Result := Items.Count;
    Items.AddElement(NewSlot(NewID,Kind,'#B897D6',Result)); Exit;
  end;
  if (MusicStudioTrackAt(Root,TrackIndex).Kind='psd') and (Kind<>'psd') and
    (MusicStudioTrackAt(Root,TrackIndex).PsdAssetID='') and (MusicStudioTrackAt(Root,TrackIndex).PsdPath='') then
    raise Exception.Create('先に登録PSDを割り当ててください。');
  if (TrackObject(Root,TrackIndex).GetValue<string>('kind')='psd') and
    (TrackObject(Root,TrackIndex).GetValue('providedSlots') is TJSONArray) and (Kind<>'psd') and (Kind<>'customExpression') then begin
    if not ContainsKind(MusicStudioTrackAt(Root,TrackIndex).ProvidedSlots,Kind) then
      raise Exception.Create('割当PSDはこのスロットに対応していません。');
  end;
  if (Kind='customExpression') and (MusicStudioTrackAt(Root,TrackIndex).PsdAssetID='') then
    raise Exception.Create('先に登録PSDを割り当ててください。');
  Items := SlotArray(Root,TrackIndex); Result := Items.Count; Color := '#6FBFAD';
  if Kind = 'singing' then Color := '#CC8CE0'; Items.AddElement(NewSlot(NewID,Kind,Color,Result));
end;
function MusicStudioAddTrack(Root: TJSONObject; const Kind: string): Integer;
var Obj,Psd: TJSONObject; Items: TJSONArray; Name,Color,SlotKind: string;
begin
  if Kind = 'audio' then begin Name := '音楽トラック'; Color := '#6FBFAD'; SlotKind := 'audio'; end
  else if (Kind = 'psd') or (Kind='instrument') or (Kind='performer') then begin Name := '演奏者トラック'; Color := '#CC8CE0'; SlotKind := 'psd'; end
  else raise Exception.Create('未対応のトラック種別です。');
  Items := TJSONArray(Root.GetValue('tracks')); Result := Items.Count;
  Obj := TJSONObject.Create; Obj.AddPair('id',NewID);
  if Kind<>'audio' then begin Obj.AddPair('kind','psd'); Obj.AddPair('role','performer'); end
  else Obj.AddPair('kind',Kind);
  Obj.AddPair('name','トラック'+IntToStr(Result+1)); Obj.AddPair('color',Color); Obj.AddPair('slots',TJSONArray.Create);
  if Kind<>'audio' then begin Psd := TJSONObject.Create; Psd.AddPair('filePath',''); Obj.AddPair('psd',Psd); end;
  Items.AddElement(Obj); if not Assigned(Root.GetValue('arrangementVersion')) or (Root.GetValue('arrangementVersion').Value<>'3') then Put(Root,'arrangementVersion',TJSONNumber.Create(2)); MusicStudioAddSlot(Root,Result,SlotKind);
end;
function PatternKind(Root: TJSONObject; const ID: string): string;
var V: TJSONValue;
begin
  Result := ''; if not Assigned(Root.GetValue('patterns')) then Exit;
  for V in TJSONArray(Root.GetValue('patterns')) do if TJSONObject(V).GetValue('id').Value = ID then Exit(TJSONObject(V).GetValue('kind').Value);
end;
function MusicStudioAddPlacement(Root: TJSONObject; TrackIndex,SlotIndex: Integer;
  const PatternID: string; StartSeconds,LengthSeconds: Double; out ErrorText: string): Boolean;
var T: TMusicStudioTrack; Kind: string; Clip: TJSONObject;
begin
  Result := False;
  if (TrackIndex < 0) or (TrackIndex >= TJSONArray(Root.GetValue('tracks')).Count) then begin ErrorText := '配置先トラックを選択してください。'; Exit; end;
  T := MusicStudioTrackAt(Root,TrackIndex);
  if (SlotIndex < 0) or (SlotIndex >= Length(T.Slots)) then begin ErrorText := '配置先のスロット行を選択してください。'; Exit; end;
  Kind := PatternKind(Root,PatternID);
  if (T.Kind='psd') and T.HasCapabilityMetadata and ((Kind='singing') or (Kind='performance')) and
    not ContainsKind(T.ProvidedSlots,Kind) then begin ErrorText := '割当PSDはこの配置の機能に対応していません。'; Exit; end;
  if Kind = '' then begin ErrorText := '配置するパターンがありません。'; Exit; end;
  if not MusicStudioSlotCompatible(Kind,T.Slots[SlotIndex],ErrorText) then Exit;
  if IsNan(StartSeconds) or IsInfinite(StartSeconds) or IsNan(LengthSeconds) or IsInfinite(LengthSeconds) or
    (StartSeconds < 0) or (LengthSeconds<=0) or ((Kind<>'performance') and (Kind<>'tempo') and (LengthSeconds<0.001)) or
    (StartSeconds + LengthSeconds > 604800) then begin ErrorText := '開始・長さが範囲外です。'; Exit; end;
  Clip := TJSONObject.Create; Clip.AddPair('id',NewID); Clip.AddPair('patternId',PatternID); Clip.AddPair('slotId',T.Slots[SlotIndex].ID);
  Clip.AddPair('startSeconds',TJSONNumber.Create(StartSeconds)); Clip.AddPair('lengthSeconds',TJSONNumber.Create(LengthSeconds));
  TJSONArray(SlotObject(Root,TrackIndex,SlotIndex).GetValue('clips')).AddElement(Clip); Result := True; ErrorText := '';
end;
function MusicStudioAddPlacement(Root: TJSONObject; TrackIndex: Integer; const PatternID: string;
  StartSeconds,LengthSeconds: Double; out ErrorText: string): Boolean;
begin Result := MusicStudioAddPlacement(Root,TrackIndex,0,PatternID,StartSeconds,LengthSeconds,ErrorText); end;
function MusicStudioUpdateSlot(Root: TJSONObject; TrackIndex,SlotIndex: Integer;
  const Name,Color: string; const Accepts: TArray<string>; out ErrorText: string): Boolean;
var Obj: TJSONObject; A: TJSONArray; V: TJSONValue; S: string; I,J: Integer; Track: TMusicStudioTrack;
begin
  Result := False; ErrorText := '名前、#RRGGBBの色、1つ以上の受入属性を指定してください。';
  if (Trim(Name) = '') or not ColorValid(Color) or (Length(Accepts) = 0) then Exit;
  for I := 0 to High(Accepts) do begin if Trim(Accepts[I]) = '' then Exit; for J := 0 to I - 1 do if Accepts[J] = Accepts[I] then Exit; end;
  Track := MusicStudioTrackAt(Root,TrackIndex);
  if (Track.Kind='psd') and Track.HasCapabilityMetadata then for S in Accepts do
    if ((S='singing') or (S='performance')) and not ContainsKind(Track.ProvidedSlots,S) then begin
      ErrorText := '割当PSDはこの受入属性に対応していません。'; Exit;
    end;
  Obj := SlotObject(Root,TrackIndex,SlotIndex);
  if (MusicStudioAnimationSource(Obj.GetValue<string>('kind'))<>'') and
    ((Length(Accepts)<>1) or (Accepts[0]<>'animation')) then begin
    ErrorText := 'アニメーションスロットの受入属性はアニメーションです。'; Exit;
  end;
  for V in TJSONArray(Obj.GetValue('clips')) do if not ContainsKind(Accepts,PatternKind(Root,TJSONObject(V).GetValue('patternId').Value)) then begin
    ErrorText := '既存配置が使用する属性は解除できません。先にその配置を削除してください。'; Exit;
  end;
  A := TJSONArray.Create; for S in Accepts do A.Add(S);
  Put(Obj,'name',TJSONString.Create(Name)); Put(Obj,'color',TJSONString.Create(Color)); Put(Obj,'accepts',A); Result := True; ErrorText := '';
end;
procedure Renumber(Items: TJSONArray);
var I: Integer;
begin for I := 0 to Items.Count - 1 do Put(TJSONObject(Items.Items[I]),'order',TJSONNumber.Create(I)); end;
procedure MusicStudioRemoveSlot(Root: TJSONObject; TrackIndex,SlotIndex: Integer);
var Items: TJSONArray;
begin Items := SlotArray(Root,TrackIndex); Items.Remove(SlotIndex).Free; Renumber(Items); end;
procedure MusicStudioReorderSlot(Root: TJSONObject; TrackIndex,FromIndex,ToIndex: Integer);
var Items,NewItems: TJSONArray; Indices: TList<Integer>; I,Value: Integer;
begin
  Items := SlotArray(Root,TrackIndex);
  if (FromIndex < 0) or (ToIndex < 0) or (FromIndex >= Items.Count) or (ToIndex >= Items.Count) then raise Exception.Create('スロット順が範囲外です。');
  if FromIndex = ToIndex then Exit; Indices := TList<Integer>.Create; NewItems := TJSONArray.Create;
  try
    for I := 0 to Items.Count - 1 do Indices.Add(I); Value := Indices[FromIndex]; Indices.Delete(FromIndex); Indices.Insert(ToIndex,Value);
    for I in Indices do NewItems.AddElement(TJSONObject.ParseJSONValue(Items.Items[I].ToJSON));
    Renumber(NewItems); Put(TrackObject(Root,TrackIndex),'slots',NewItems); NewItems := nil;
  finally NewItems.Free; Indices.Free; end;
end;
procedure MusicStudioUpdateTrack(Root: TJSONObject; Index: Integer; const Name,Color,PsdPath: string);
var Obj,Psd: TJSONObject;
begin
  Obj := TrackObject(Root,Index); Put(Obj,'name',TJSONString.Create(Name)); Put(Obj,'color',TJSONString.Create(Color));
  if Obj.GetValue('kind').Value = 'psd' then begin Psd := TJSONObject(Obj.GetValue('psd')); Put(Psd,'filePath',TJSONString.Create(PsdPath)); end;
end;
procedure MusicStudioSetPlacementBeats(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer; StartBeat,LengthBeats: Double);
var O: TJSONObject;
begin
  O := TJSONObject(TJSONArray(SlotObject(Root,TrackIndex,SlotIndex).GetValue('clips')).Items[ClipIndex]);
  Put(O,'timeBase',TJSONString.Create('beats')); Put(O,'startBeat',TJSONNumber.Create(StartBeat)); Put(O,'lengthBeats',TJSONNumber.Create(LengthBeats));
  Put(Root,'arrangementVersion',TJSONNumber.Create(3));
end;
procedure MusicStudioAssignPsd(Root: TJSONObject; Index: Integer; const AssetID: string);
var O: TJSONObject;
begin
  O := TJSONObject(TrackObject(Root,Index).GetValue('psd'));
  if not Assigned(O) then raise Exception.Create('PSDを割り当てるトラックを選択してください。');
  Put(O,'assetId',TJSONString.Create(AssetID)); Put(O,'filePath',TJSONString.Create(''));
end;
procedure MusicStudioReorderTrack(Root: TJSONObject; FromIndex,ToIndex: Integer);
var A: TJSONArray; L: TList<TJSONValue>; V: TJSONValue; I: Integer;
begin
  A := TJSONArray(Root.GetValue('tracks'));
  if (FromIndex<0) or (ToIndex<0) or (FromIndex>=A.Count) or (ToIndex>=A.Count) then
    raise EArgumentOutOfRangeException.Create('移動するトラックがありません。');
  if FromIndex=ToIndex then Exit;
  L := TList<TJSONValue>.Create;
  try
    while A.Count>0 do L.Add(A.Remove(0)); V := L.Extract(L[FromIndex]); L.Insert(ToIndex,V);
    for I := 0 to L.Count-1 do A.AddElement(L[I]);
  finally L.Free; end;
end;
procedure MusicStudioRemoveTrack(Root: TJSONObject; Index: Integer);
begin TJSONArray(Root.GetValue('tracks')).Remove(Index).Free; end;
procedure MusicStudioRemovePlacement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer);
begin TJSONArray(SlotObject(Root,TrackIndex,SlotIndex).GetValue('clips')).Remove(ClipIndex).Free; end;
procedure MusicStudioRemovePlacement(Root: TJSONObject; TrackIndex,ClipIndex: Integer);
begin MusicStudioRemovePlacement(Root,TrackIndex,0,ClipIndex); end;
procedure MusicStudioMovePlacement(Root: TJSONObject; TrackIndex,SlotIndex,ClipIndex: Integer; StartSeconds,LengthSeconds: Double);
var Clip: TJSONObject;
begin
  Clip := TJSONObject(TJSONArray(SlotObject(Root,TrackIndex,SlotIndex).GetValue('clips')).Items[ClipIndex]);
  Put(Clip,'startSeconds',TJSONNumber.Create(StartSeconds)); Put(Clip,'lengthSeconds',TJSONNumber.Create(LengthSeconds));
end;
procedure MusicStudioMovePlacement(Root: TJSONObject; TrackIndex,ClipIndex: Integer; StartSeconds,LengthSeconds: Double);
begin MusicStudioMovePlacement(Root,TrackIndex,0,ClipIndex,StartSeconds,LengthSeconds); end;
function MusicStudioPatternInUse(Root: TJSONObject; const PatternID: string): Boolean;
  function References(V: TJSONValue): Boolean;
  var Item: TJSONValue; Pair: TJSONPair;
  begin
    Result := False;
    if V is TJSONObject then begin
      if (TJSONObject(V).GetValue('patternId') is TJSONString) and (TJSONObject(V).GetValue('patternId').Value = PatternID) then Exit(True);
      for Pair in TJSONObject(V) do if (Pair.JsonString.Value = 'clips') or (Pair.JsonString.Value = 'slots') then if References(Pair.JsonValue) then Exit(True);
    end else if V is TJSONArray then for Item in TJSONArray(V) do if References(Item) then Exit(True);
  end;
begin Result := References(Root.GetValue('tracks')); end;
end.
