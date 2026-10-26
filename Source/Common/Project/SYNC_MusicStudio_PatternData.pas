unit SYNC_MusicStudio_PatternData;

// パターンの固定IDと共通属性・音声属性を管理する。原JSONを所有し未知フィールドを保持する。
interface

uses
  System.JSON, System.SysUtils, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_PsdTransform;

type
  TMusicStudioPattern = record
    ID, Kind, Name, Color, FilePath, AssetID, SharedPatternID, ConfigJSON: string;
    PerformanceAttribute,LibraryRevision: string; // 共通演奏の分類と配置時の版。AssetIDは使わない。
    Volume: Double; // 1.0 = 100%。音源データや波形キャッシュは保存しない。
    SourceTrack: Integer; // 歌唱MIDI内の0始まりトラック番号。-1は未選択。
    Duration: Double; // 読込済み音源の長さ。配置の初期長さ用メタデータで、実データではない。
    SourceStartSeconds: Double; // 歌唱の有効音符区間の先頭。旧文書は0で従来同期を保つ。
  end;

  TMusicStudioAssetResolver = function(const AssetID: string): string of object;
  TMusicStudioDocument = class
  private
    FRoot: TJSONObject;
    FAssetResolver: TMusicStudioAssetResolver;
    FTiming: TMusicStudioTempoMap;
    procedure RebuildTiming;
    procedure SyncTimingSeconds;
    // Rootと有効mapを一緒に確定し、tempo再合成が拒否された削除/並替を復元する。
    procedure ApplyTimingMutation(const Mutation: TProc);
    function PatternArray: TJSONArray;
  public
    destructor Destroy; override;
    function BeatToSeconds(Beat: Double): Double;
    function SecondsToBeat(Seconds: Double): Double;
    function SetTiming(const TimingJSON: string; out ErrorText: string): Boolean;
    function SetTempoAtBeat(Beat,BPM: Double; out Scope,ErrorText: string): Boolean;
    function ManualTimingJSON: string;
    property Timing: TMusicStudioTempoMap read FTiming;
    // 成功時だけ文書を入れ替える。失敗時に現在の文書を失わない。
    function TryLoad(const Text: string; out ErrorText: string): Boolean;
    function TrySave(out Text, ErrorText: string): Boolean;
    function PatternCount: Integer;
    function PatternAt(Index: Integer): TMusicStudioPattern;
    // 演奏パターンに保存された末尾。秒素材など制限しない属性は0。
    function PatternLengthBeats(const PatternID: string): Double;
    function AddAudio: Integer;
    function AddSinging: Integer;
    function AddPerformance: Integer;
    function AddTempo: Integer;
    // PSDの全表示状態を作品内へ値コピーする。正本や素材には保存しない。
    function AddCustomExpression(const Pattern: TMusicStudioPattern): Integer;
    function AddReference(const Pattern: TMusicStudioPattern): Integer;
    procedure AssignPsd(Index: Integer; const AssetID: string);
    // PSD解析結果を反映する。既存の配置と手動スロットを保持する。
    procedure SetPerformer(Index: Integer; const Attribute: string; const Slots: TArray<string>; UpdateSlots: Boolean = True; const ChoicesJSON: string = '');
    // 小型枠の候補操作。候補Rootを検証してから採用し、失敗時は作品を変更しない。
    procedure WriteSmallElement(TrackIndex,SlotIndex,ClipIndex: Integer; const Mode,Choice: string; StartSeconds,LengthSeconds: Double);
    function CopyTrack(Index: Integer): string;
    function PasteTrack(const Text: string): Integer;
    // 同じ共通ID/版の作品snapshotを再利用する。別PSDでも同じ属性なら利用できる。
    function ImportPerformance(const Pattern: TMusicStudioPattern): Integer;
    // 共通UIDの名称だけを全配置snapshotへ反映する。演奏データと配置時の版は保持する。
    procedure RenamePerformance(const Attribute,SharedID,Name: string);
    // 明示保存した共通演奏を、現在作品の同じ共通UIDのsnapshotへ反映する。配置ID/位置/長さは保持。
    function RefreshPerformanceSnapshots(const Pattern: TMusicStudioPattern): Integer;
    property AssetResolver: TMusicStudioAssetResolver read FAssetResolver write FAssetResolver;
    // 指定IDの属性だけを変更し、そのパターンの拡張属性を保持する。
    procedure UpdatePattern(const Pattern: TMusicStudioPattern);
    procedure RemovePattern(Index: Integer);
    function TrackCount: Integer;
    function TrackAt(Index: Integer): TMusicStudioTrack;
    function AddTrack(const Kind: string): Integer;
    function AddSlot(TrackIndex: Integer; const Kind: string): Integer;
    function UpdateSlot(TrackIndex, SlotIndex: Integer; const Name, Color: string;
      const Accepts: TArray<string>; out ErrorText: string): Boolean;
    procedure RemoveSlot(TrackIndex, SlotIndex: Integer);
    procedure ReorderSlot(TrackIndex, FromIndex, ToIndex: Integer);
    procedure UpdateTrack(Index: Integer; const Name, Color, PsdPath: string);
    procedure UpdatePsdTransform(Index: Integer; const Transform: TMusicStudioPsdTransform);
    procedure ReorderTrack(FromIndex,ToIndex: Integer);
    procedure RemoveTrack(Index: Integer);
    function AddPlacement(TrackIndex: Integer; const PatternID: string;
      StartSeconds, LengthSeconds: Double; out ErrorText: string): Boolean; overload;
    function AddPlacement(TrackIndex, SlotIndex: Integer; const PatternID: string;
      StartSeconds, LengthSeconds: Double; out ErrorText: string): Boolean; overload;
    // 配置ID/時刻を保って参照だけを更新する。属性・素材違いは変更前に拒否する。
    procedure ReplacePlacementPattern(TrackIndex,SlotIndex,ClipIndex: Integer; const PatternID: string);
    procedure RemovePlacement(TrackIndex, ClipIndex: Integer); overload;
    procedure RemovePlacement(TrackIndex, SlotIndex, ClipIndex: Integer); overload;
    procedure MovePlacement(TrackIndex, ClipIndex: Integer; StartSeconds, LengthSeconds: Double); overload;
    procedure MovePlacement(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds, LengthSeconds: Double); overload;
    function MoveBeatPlacement(TrackIndex,SlotIndex,ClipIndex: Integer; StartBeat,LengthBeats: Double; out ErrorText: string): Boolean;
    function AddBeatPlacement(TrackIndex,SlotIndex: Integer; const PatternID: string; StartBeat,LengthBeats: Double; out ErrorText: string): Boolean;
    function PatternInUse(const PatternID: string): Boolean;
  end;

// patternsがない旧JSONも受け付ける。既知audio属性の型・範囲と固定ID重複を検証する。
function ValidateMusicStudioPatterns(Root: TJSONObject; out ErrorText: string): Boolean;

implementation

uses
  System.Math, System.Generics.Collections, SYNC_MusicStudio_LayerStepData, SYNC_MusicStudio_TempoPatternData,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_DrumData, SYNC_MusicStudio_InstrumentData,
  SYNC_MusicStudio_PerformerData, SYNC_MusicStudio_PerformanceKinds, SYNC_MusicStudio_SmallSlotData;

function ValidColor(const Value: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(Value) = 7) and (Value[1] = '#');
  if not Result then Exit;
  for I := 2 to 7 do
    if not CharInSet(Value[I], ['0'..'9', 'a'..'f', 'A'..'F']) then Exit(False);
end;

function ValidateMusicStudioPatterns(Root: TJSONObject; out ErrorText: string): Boolean;
var Pair: TJSONPair;
  Items: TJSONValue;
  Item: TJSONValue;
  Obj, Audio: TJSONObject;
  IDs: TDictionary<string, Boolean>;
  ID: string;
  Volume: Double;
  Duration: TJSONValue;
  SourceTrack: Integer; Performance: TMusicStudioPerformanceData; Timing: TMusicStudioTempoMap; Steps: TMusicStudioLayerStepData; Tempo: TMusicStudioTempoPatternData;
  Drums: TMusicStudioDrumData;
  Instrument: TMusicStudioInstrumentData;
begin
  Result := False;
  ErrorText := '';
  try
    Timing := TMusicStudioTempoMap.Create;
    try
      if Assigned(Root.GetValue('timing')) then begin
        if not (Root.GetValue('timing') is TJSONObject) then raise Exception.Create('timingはJSONオブジェクトで指定してください。');
        Timing.LoadJSON(TJSONObject(Root.GetValue('timing')));
      end;
    finally Timing.Free; end;
  except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
  Items := Root.GetValue('patterns');
  if Items = nil then Exit(True);
  ErrorText := 'patterns は配列で指定してください。';
  if not (Items is TJSONArray) then Exit;
  IDs := TDictionary<string, Boolean>.Create;
  try
    for Item in TJSONArray(Items) do
    begin
      ErrorText := 'パターンには文字列のid、kind、name、#RRGGBB形式のcolorが必要です。';
      if not (Item is TJSONObject) then Exit;
      Obj := TJSONObject(Item);
      if not (Obj.GetValue('id') is TJSONString) or
        not (Obj.GetValue('kind') is TJSONString) or
        not (Obj.GetValue('name') is TJSONString) or
        not (Obj.GetValue('color') is TJSONString) then Exit;
      ID := Obj.GetValue('id').Value;
      if (Trim(ID) = '') or (Trim(Obj.GetValue('kind').Value) = '') or
        (Trim(Obj.GetValue('name').Value) = '') or
        not ValidColor(Obj.GetValue('color').Value) then Exit;
      ErrorText := 'パターンIDが重複しています: ' + ID;
      if IDs.ContainsKey(ID) then Exit;
      IDs.Add(ID, True);
      if Obj.GetValue('kind').Value='selection' then begin
        ErrorText := '独立演出の要素指定が不正です。';
        if not ValidateMusicStudioSelection(Obj.GetValue('selection')) then Exit;
        Continue;
      end;
      if Obj.GetValue('kind').Value = 'singing' then
      begin
        ErrorText := '歌唱パターンにはsinging.filePathと-1以上のsinging.trackIndexが必要です。';
        if not (Obj.GetValue('singing') is TJSONObject) then Exit;
        Audio := TJSONObject(Obj.GetValue('singing'));
        if not (Audio.GetValue('filePath') is TJSONString) or
          not (Audio.GetValue('trackIndex') is TJSONNumber) then Exit;
        if not TryStrToInt(Audio.GetValue('trackIndex').Value, SourceTrack) or
          (SourceTrack < -1) or (SourceTrack > 255) then Exit;
        if Audio.GetValue('sourceStartSeconds')<>nil then begin
          ErrorText := '歌唱の参照開始秒が不正です。';
          if not (Audio.GetValue('sourceStartSeconds') is TJSONNumber) then Exit;
          Volume := TJSONNumber(Audio.GetValue('sourceStartSeconds')).AsDouble;
          if IsNan(Volume) or IsInfinite(Volume) or (Volume<0) or (Volume>604800) then Exit;
        end;
      end
      else if Obj.GetValue('kind').Value = 'audio' then
      begin
      ErrorText := 'オーディオクリップにはaudio.filePathと0～2のaudio.volumeが必要です。';
      if not (Obj.GetValue('audio') is TJSONObject) then Exit;
      Audio := TJSONObject(Obj.GetValue('audio'));
      if not (Audio.GetValue('filePath') is TJSONString) or
        not (Audio.GetValue('volume') is TJSONNumber) then Exit;
      Volume := TJSONNumber(Audio.GetValue('volume')).AsDouble;
      if IsNan(Volume) or IsInfinite(Volume) or (Volume < 0) or (Volume > 2) then Exit;
      end
      else if Obj.GetValue('kind').Value='tempo' then begin
        if not (Obj.GetValue('tempo') is TJSONObject) then begin ErrorText := 'tempoパターンにはtempo属性が必要です。'; Exit; end;
        Tempo := TMusicStudioTempoPatternData.Create;
        try try Tempo.LoadJSON(Obj.GetValue('tempo').ToJSON);
          except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
        finally Tempo.Free; end;
        Continue;
      end
      else if Obj.GetValue('kind').Value='performance' then begin
        ErrorText := '共通演奏の属性/ID/版が不正です。';
        if not ValidatePerformanceReference(Obj.GetValue('performanceLibrary')) then Exit;
        ErrorText := '演奏パターンには拍で記したperformance属性が必要です。';
        if not (Obj.GetValue('performance') is TJSONObject) then Exit;
        Performance := TMusicStudioPerformanceData.Create;
        try
          try Performance.LoadJSON(TJSONObject(Obj.GetValue('performance')));
          except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
        finally Performance.Free; end;
        Steps := TMusicStudioLayerStepData.Create;
        try
          try Steps.LoadJSON(Obj.GetValue('performance').ToJSON);
          except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
        finally Steps.Free; end;
        if MusicStudioHasInstrumentTimeline(Obj.GetValue('performance').ToJSON) then begin
          Instrument := TMusicStudioInstrumentData.Create;
          try try Instrument.Load(Obj.GetValue('performance').ToJSON);
            except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
          finally Instrument.Free; end;
        end;
        if MusicStudioHasDrums(Obj.GetValue('performance').ToJSON) then begin
          Drums := TMusicStudioDrumData.Create;
          try
            try Drums.Load(Obj.GetValue('performance').ToJSON);
            except on E: Exception do begin ErrorText := E.Message; Exit; end; end;
          finally Drums.Free; end;
        end;
        Continue;
      end
      else if (Obj.GetValue('kind').Value='psd') or (Obj.GetValue('kind').Value='emotion') or
        (Obj.GetValue('kind').Value='animation') or (Obj.GetValue('kind').Value='instrument') then begin
        ErrorText := 'PSD属性には固定assetIdとsharedPatternIdが必要です。';
        if not (Obj.GetValue('reference') is TJSONObject) then Exit;
        Audio := TJSONObject(Obj.GetValue('reference'));
        if not (Audio.GetValue('assetId') is TJSONString) or (Trim(Audio.GetValue('assetId').Value)='') or
          not (Audio.GetValue('sharedPatternId') is TJSONString) then Exit;
        if Obj.GetValue('expression')<>nil then begin
          if not (Obj.GetValue('expression') is TJSONObject) then begin ErrorText := '表情の表示設定が不正です。'; Exit; end;
          if Length(Obj.GetValue('expression').ToJSON)>262144 then begin ErrorText := '表情の表示設定が大きすぎます。'; Exit; end;
          if not (TJSONObject(Obj.GetValue('expression')).GetValue('visibility') is TJSONObject) then begin ErrorText := '表情のvisibilityが不正です。'; Exit; end;
          for Pair in TJSONObject(TJSONObject(Obj.GetValue('expression')).GetValue('visibility')) do
            if not (Pair.JsonValue is TJSONBool) then begin ErrorText := '表情レイヤーは真偽値です。'; Exit; end;
        end;
        Continue;
      end
      else Continue;
      Duration := Audio.GetValue('durationSeconds');
      if Assigned(Duration) then
      begin
        ErrorText := 'durationSeconds は0以上の有限の秒数で指定してください。';
        if not (Duration is TJSONNumber) then Exit;
        Volume := TJSONNumber(Duration).AsDouble;
        if IsNan(Volume) or IsInfinite(Volume) or (Volume < 0) or (Volume > 604800) then Exit;
        if (Obj.GetValue('kind').Value='singing') and (Audio.GetValue('sourceStartSeconds') is TJSONNumber) and
          (TJSONNumber(Audio.GetValue('sourceStartSeconds')).AsDouble+Volume>604800) then begin
          ErrorText := '歌唱の参照区間が上限604800秒を超えています。'; Exit;
        end;
      end;
    end;
    ErrorText := '';
    Result := True;
  finally
    IDs.Free;
  end;
end;

procedure SetValue(Obj: TJSONObject; const Name: string; Value: TJSONValue);
begin
  Obj.RemovePair(Name).Free;
  Obj.AddPair(Name, Value);
end;

destructor TMusicStudioDocument.Destroy;
begin
  FTiming.Free;
  FRoot.Free;
  inherited;
end;

function TMusicStudioDocument.TryLoad(const Text: string; out ErrorText: string): Boolean;
var
  Normalized: string;
  NewRoot: TJSONObject;
  NewTiming: TMusicStudioTempoMap;
begin
  Result := TryNormalizeMusicStudioJSON(Text, Normalized, ErrorText);
  if not Result then Exit;
  NewRoot := TJSONObject.ParseJSONValue(Normalized) as TJSONObject;
  try NewTiming := BuildMusicStudioEffectiveTempo(NewRoot);
  except on E: Exception do begin NewRoot.Free; ErrorText := E.Message; Exit(False); end; end;
  FTiming.Free; FTiming := NewTiming;
  FRoot.Free; FRoot := NewRoot;
end;

function TMusicStudioDocument.TrySave(out Text, ErrorText: string): Boolean;
begin
  SyncTimingSeconds;
  Result := TryNormalizeMusicStudioJSON(FRoot.ToJSON, Text, ErrorText);
end;

function TMusicStudioDocument.PatternArray: TJSONArray;
begin
  Result := FRoot.GetValue('patterns') as TJSONArray;
end;

function TMusicStudioDocument.PatternCount: Integer;
var
  Items: TJSONArray;
begin
  Items := PatternArray;
  if Items = nil then Result := 0 else Result := Items.Count;
end;

function TMusicStudioDocument.PatternAt(Index: Integer): TMusicStudioPattern;
var
  Obj, Audio: TJSONObject;
begin
  Result := Default(TMusicStudioPattern);
  Audio := nil;
  Obj := PatternArray.Items[Index] as TJSONObject;
  Result.ID := Obj.GetValue('id').Value;
  Result.Kind := Obj.GetValue('kind').Value;
  Result.Name := Obj.GetValue('name').Value;
  Result.Color := Obj.GetValue('color').Value;
  if Result.Kind = 'audio' then
  begin
    Audio := Obj.GetValue('audio') as TJSONObject;
    Result.FilePath := Audio.GetValue('filePath').Value;
    Result.Volume := TJSONNumber(Audio.GetValue('volume')).AsDouble;
  end;
  if Result.Kind = 'singing' then
  begin
    Audio := Obj.GetValue('singing') as TJSONObject;
    Result.FilePath := Audio.GetValue('filePath').Value;
    Result.SourceTrack := StrToInt(Audio.GetValue('trackIndex').Value);
    if Audio.GetValue('sourceStartSeconds') is TJSONNumber then Result.SourceStartSeconds := TJSONNumber(Audio.GetValue('sourceStartSeconds')).AsDouble;
  end;
  if Obj.GetValue('performance') is TJSONObject then Result.ConfigJSON := Obj.GetValue('performance').ToJSON;
  if Obj.GetValue('selection') is TJSONObject then Result.ConfigJSON := Obj.GetValue('selection').ToJSON;
  if Obj.GetValue('performanceLibrary') is TJSONObject then begin
    Audio := TJSONObject(Obj.GetValue('performanceLibrary'));
    Result.PerformanceAttribute := Audio.GetValue<string>('attribute');
    Result.SharedPatternID := Audio.GetValue<string>('id'); Result.LibraryRevision := Audio.GetValue<string>('revision');
  end;
  if Obj.GetValue('tempo') is TJSONObject then begin
    Result.ConfigJSON := Obj.GetValue('tempo').ToJSON;
    if TJSONObject(Obj.GetValue('tempo')).GetValue('filePath') is TJSONString then Result.FilePath := TJSONObject(Obj.GetValue('tempo')).GetValue('filePath').Value;
  end;
  if Obj.GetValue('expression') is TJSONObject then Result.ConfigJSON := Obj.GetValue('expression').ToJSON;
  if Obj.GetValue('reference') is TJSONObject then begin
    Audio := TJSONObject(Obj.GetValue('reference'));
    Result.AssetID := Audio.GetValue('assetId').Value; Result.SharedPatternID := Audio.GetValue('sharedPatternId').Value;
    if Assigned(FAssetResolver) then Result.FilePath := FAssetResolver(Result.AssetID);
  end;
  if (Result.Kind = 'audio') or (Result.Kind = 'singing') then
    if Audio.GetValue('durationSeconds') is TJSONNumber then
      Result.Duration := TJSONNumber(Audio.GetValue('durationSeconds')).AsDouble;
end;

function TMusicStudioDocument.BeatToSeconds(Beat: Double): Double;
begin Result := FTiming.BeatToSeconds(Beat); end;
function TMusicStudioDocument.SecondsToBeat(Seconds: Double): Double;
begin Result := FTiming.SecondsToBeat(Seconds); end;
procedure TMusicStudioDocument.SyncTimingSeconds;
var I,J,K: Integer; T: TMusicStudioTrack; C: TMusicStudioPlacement;
begin
  RebuildTiming;
  for I := 0 to TrackCount-1 do begin
    T := MusicStudioTrackAt(FRoot,I);
    for J := 0 to High(T.Slots) do for K := 0 to High(T.Slots[J].Clips) do begin
      C := T.Slots[J].Clips[K];
      if C.TimeBase='beats' then MusicStudioMovePlacement(FRoot,I,J,K,BeatToSeconds(C.StartBeat),
        BeatToSeconds(C.StartBeat+C.LengthBeats)-BeatToSeconds(C.StartBeat));
    end;
  end;
end;
function TMusicStudioDocument.ManualTimingJSON: string;
var DefaultMap: TMusicStudioTempoMap;
begin
  if FRoot.GetValue('timing') is TJSONObject then Exit(FRoot.GetValue('timing').ToJSON);
  DefaultMap := TMusicStudioTempoMap.Create; try Result := DefaultMap.TimingJSON; finally DefaultMap.Free; end;
end;
procedure TMusicStudioDocument.ApplyTimingMutation(const Mutation: TProc);
var BeforeRoot: TJSONObject; BeforeTiming: TMusicStudioTempoMap;
begin
  BeforeRoot := TJSONObject(FRoot.Clone); BeforeTiming := TMusicStudioTempoMap.Create;
  try
    BeforeTiming.LoadJSON(FTiming.TimingJSON);
    try Mutation(); SyncTimingSeconds;
    except
      FRoot.Free; FRoot := BeforeRoot; BeforeRoot := nil;
      FTiming.Free; FTiming := BeforeTiming; BeforeTiming := nil;
      raise;
    end;
  finally BeforeTiming.Free; BeforeRoot.Free; end;
end;
function TMusicStudioDocument.SetTempoAtBeat(Beat,BPM: Double; out Scope,ErrorText: string): Boolean;
var Target: string;
begin
  Result := False; Scope := ''; ErrorText := '';
  try ApplyTimingMutation(procedure begin SetMusicStudioTempoAtBeat(FRoot,Beat,BPM,Target); end);
    Scope := Target; Result := True;
  except on E: Exception do ErrorText := E.Message; end;
end;
procedure TMusicStudioDocument.RebuildTiming;
var Candidate: TMusicStudioTempoMap; I,J,K: Integer; T: TMusicStudioTrack; C: TMusicStudioPlacement;
begin
  Candidate := BuildMusicStudioEffectiveTempo(FRoot);
  try
    for I := 0 to TrackCount-1 do begin T := TrackAt(I);
      for J := 0 to High(T.Slots) do for K := 0 to High(T.Slots[J].Clips) do begin C := T.Slots[J].Clips[K];
        if (C.TimeBase='beats') and (Candidate.BeatToSeconds(C.StartBeat+C.LengthBeats)>604800) then
          raise EArgumentException.Create('合成tempoで拍配置が604800秒を超えます。');
      end;
    end;
    FTiming.Free; FTiming := Candidate; Candidate := nil;
  finally Candidate.Free; end;
end;
function TMusicStudioDocument.SetTiming(const TimingJSON: string; out ErrorText: string): Boolean;
var Candidate: TMusicStudioTempoMap; I,J,K: Integer; T: TMusicStudioTrack; C: TMusicStudioPlacement; Root: TJSONObject; ManualText: string;
begin
  Result := False; ErrorText := ''; Candidate := TMusicStudioTempoMap.Create; Root := TJSONObject(FRoot.Clone);
  try
    try
      Candidate.LoadJSON(TimingJSON);
      ManualText := Candidate.TimingJSON; SetValue(Root,'timing',TJSONObject.ParseJSONValue(ManualText));
      FreeAndNil(Candidate); Candidate := BuildMusicStudioEffectiveTempo(Root);
      for I := 0 to TrackCount-1 do begin
        T := MusicStudioTrackAt(FRoot,I);
        for J := 0 to High(T.Slots) do for K := 0 to High(T.Slots[J].Clips) do begin
          C := T.Slots[J].Clips[K];
          if (C.TimeBase='beats') and (Candidate.BeatToSeconds(C.StartBeat+C.LengthBeats)>604800) then
            raise Exception.Create('テンポ変更後の演奏配置が604800秒を超えます。');
        end;
      end;
      SetValue(FRoot,'timing',TJSONObject.ParseJSONValue(ManualText));
      FTiming.Free; FTiming := Candidate; Candidate := nil; SyncTimingSeconds; Result := True;
    except on E: Exception do ErrorText := E.Message; end;
  finally Root.Free; Candidate.Free; end;
end;
function TMusicStudioDocument.AddTempo: Integer;
var Items: TJSONArray; Obj: TJSONObject; G: TGUID; Data: TMusicStudioTempoPatternData;
begin
  Items := PatternArray; if Items=nil then begin Items := TJSONArray.Create; FRoot.AddPair('patterns',Items); end;
  CreateGUID(G); Obj := TJSONObject.Create; Obj.AddPair('id',GUIDToString(G)); Obj.AddPair('kind','tempo');
  Obj.AddPair('name','テンポ '+IntToStr(Items.Count+1)); Obj.AddPair('color','#73C2A6'); Data := TMusicStudioTempoPatternData.Create;
  try Obj.AddPair('tempo',TJSONObject.ParseJSONValue(Data.ConfigJSON)); finally Data.Free; end;
  Result := Items.Count; Items.AddElement(Obj);
end;
function TMusicStudioDocument.AddPerformance: Integer;
var O: TJSONObject; A: TJSONArray; G: TGUID;
begin
  A := PatternArray; if A=nil then begin A := TJSONArray.Create; FRoot.AddPair('patterns',A); end;
  CreateGUID(G); O := TJSONObject.Create; O.AddPair('id',GUIDToString(G)); O.AddPair('kind','performance');
  O.AddPair('name','演奏 '+IntToStr(A.Count+1)); O.AddPair('color','#EDBA70');
  O.AddPair('performance',TJSONObject.ParseJSONValue('{"lengthBeats":16,"notes":[]}')); Result := A.Count; A.AddElement(O);
end;
function TMusicStudioDocument.AddCustomExpression(const Pattern: TMusicStudioPattern): Integer;
var O,R,Config: TJSONObject; G: TGUID; A: TJSONArray; Pair: TJSONPair;
begin
  if (Pattern.AssetID='') or (Trim(Pattern.Name)='') or (Length(Pattern.ConfigJSON)>262144) then raise Exception.Create('表情の素材・名前・サイズが不正です。');
  Config := TJSONObject.ParseJSONValue(Pattern.ConfigJSON) as TJSONObject;
  if Config=nil then raise Exception.Create('表情の表示設定が不正です。');
  try
    if not (Config.GetValue('visibility') is TJSONObject) then raise Exception.Create('表情の表示設定が不正です。');
    for Pair in TJSONObject(Config.GetValue('visibility')) do if not (Pair.JsonValue is TJSONBool) then raise Exception.Create('表情レイヤーは真偽値です。');
  except Config.Free; raise; end;
  A := PatternArray; if A=nil then begin A := TJSONArray.Create; FRoot.AddPair('patterns',A); end;
  CreateGUID(G); O := TJSONObject.Create; O.AddPair('id',GUIDToString(G)); O.AddPair('kind','emotion');
  O.AddPair('name',Pattern.Name); O.AddPair('color',Pattern.Color);
  R := TJSONObject.Create; R.AddPair('assetId',Pattern.AssetID); R.AddPair('sharedPatternId',''); O.AddPair('reference',R);
  O.AddPair('expression',Config); Result := A.Count; A.AddElement(O);
end;
function TMusicStudioDocument.AddReference(const Pattern: TMusicStudioPattern): Integer;
var I: Integer; P: TMusicStudioPattern; O,R: TJSONObject; A: TJSONArray; G: TGUID;
begin
  for I := 0 to PatternCount-1 do begin
    P := PatternAt(I);
    if (P.Kind=Pattern.Kind) and (P.AssetID=Pattern.AssetID) and (P.SharedPatternID=Pattern.SharedPatternID) then Exit(I);
  end;
  A := PatternArray; if A=nil then begin A := TJSONArray.Create; FRoot.AddPair('patterns',A); end;
  CreateGUID(G); O := TJSONObject.Create; O.AddPair('id',GUIDToString(G)); O.AddPair('kind',Pattern.Kind);
  O.AddPair('name',Pattern.Name); O.AddPair('color',Pattern.Color); R := TJSONObject.Create;
  R.AddPair('assetId',Pattern.AssetID); R.AddPair('sharedPatternId',Pattern.SharedPatternID);
  O.AddPair('reference',R); Result := A.Count; A.AddElement(O);
end;
procedure TMusicStudioDocument.AssignPsd(Index: Integer; const AssetID: string);
begin MusicStudioAssignPsd(FRoot,Index,AssetID); end;
procedure TMusicStudioDocument.SetPerformer(Index: Integer; const Attribute: string; const Slots: TArray<string>; UpdateSlots: Boolean; const ChoicesJSON: string);
begin MusicStudioSetPerformer(FRoot,Index,Attribute,Slots,UpdateSlots,ChoicesJSON); end;
procedure TMusicStudioDocument.WriteSmallElement(TrackIndex,SlotIndex,ClipIndex: Integer; const Mode,Choice: string; StartSeconds,LengthSeconds: Double);
var Candidate: TJSONObject; Error: string;
begin
  Candidate := TJSONObject(FRoot.Clone);
  try
    MusicStudioWriteSmallElement(Candidate,TrackIndex,SlotIndex,ClipIndex,Mode,Choice,StartSeconds,LengthSeconds);
    if not TryLoad(Candidate.ToJSON,Error) then raise Exception.Create(Error);
  finally Candidate.Free; end;
end;
function TMusicStudioDocument.CopyTrack(Index: Integer): string;
begin Result := MusicStudioCopyTrack(FRoot,Index); end;
function TMusicStudioDocument.PasteTrack(const Text: string): Integer;
var Candidate: TJSONObject; Error: string;
begin
  Candidate := TJSONObject(FRoot.Clone);
  try
    Result := MusicStudioPasteTrack(Candidate,Text);
    if not TryLoad(Candidate.ToJSON,Error) then raise Exception.Create(Error);
  finally Candidate.Free; end;
end;
procedure TMusicStudioDocument.RenamePerformance(const Attribute,SharedID,Name: string);
var V: TJSONValue; O,R: TJSONObject;
begin
  if PatternArray=nil then Exit;
  for V in PatternArray do begin
    O := TJSONObject(V); R := O.GetValue('performanceLibrary') as TJSONObject;
    if (R<>nil) and (R.GetValue<string>('attribute')=Attribute) and (R.GetValue<string>('id')=SharedID) then
      SetValue(O,'name',TJSONString.Create(Name));
  end;
end;
function TMusicStudioDocument.RefreshPerformanceSnapshots(const Pattern: TMusicStudioPattern): Integer;
var Before: TJSONObject; Current: TMusicStudioPattern; I: Integer; Error: string;
begin
  Result := 0;
  if (Pattern.Kind<>'performance') or (PerformanceKindIndex(Pattern.PerformanceAttribute)<0) or
    (Pattern.SharedPatternID='') or (Pattern.LibraryRevision='') then raise Exception.Create('保存済み共通演奏の参照が不正です。');
  Before := FRoot.Clone as TJSONObject;
  try
    try
      for I := 0 to PatternCount-1 do begin
        Current := PatternAt(I);
        if (Current.Kind<>'performance') or (Current.PerformanceAttribute<>Pattern.PerformanceAttribute) or
          (Current.SharedPatternID<>Pattern.SharedPatternID) then Continue;
        Current.Name := Pattern.Name; Current.Color := Pattern.Color;
        Current.ConfigJSON := Pattern.ConfigJSON; Current.LibraryRevision := Pattern.LibraryRevision;
        UpdatePattern(Current); Inc(Result);
      end;
      if not ValidateMusicStudioPatterns(FRoot,Error) then raise Exception.Create(Error);
    except FRoot.Free; FRoot := Before; Before := nil; raise; end;
  finally Before.Free; end;
end;
function TMusicStudioDocument.ImportPerformance(const Pattern: TMusicStudioPattern): Integer;
var I: Integer; P: TMusicStudioPattern;
begin
  if (Pattern.Kind<>'performance') or (PerformanceKindIndex(Pattern.PerformanceAttribute)<0) or
    (Pattern.SharedPatternID='') or (Pattern.LibraryRevision='') then raise Exception.Create('共通演奏の参照が不正です。');
  for I := 0 to PatternCount-1 do begin
    P := PatternAt(I);
    if (P.Kind='performance') and (P.SharedPatternID=Pattern.SharedPatternID) and
      (P.PerformanceAttribute=Pattern.PerformanceAttribute) and (P.LibraryRevision=Pattern.LibraryRevision) then Exit(I);
  end;
  Result := AddPerformance; P := Pattern; P.ID := PatternAt(Result).ID; UpdatePattern(P);
end;
function TMusicStudioDocument.AddSinging: Integer;
var
  Items: TJSONArray;
  Obj, Singing: TJSONObject;
  GUID: TGUID;
begin
  Items := PatternArray;
  if Items = nil then begin Items := TJSONArray.Create; FRoot.AddPair('patterns', Items); end;
  CreateGUID(GUID);
  Obj := TJSONObject.Create;
  Obj.AddPair('id', GUIDToString(GUID));
  Obj.AddPair('kind', 'singing');
  Obj.AddPair('name', Format('歌唱 %d', [Items.Count + 1]));
  Obj.AddPair('color', '#CC8CE0');
  Singing := TJSONObject.Create;
  Singing.AddPair('filePath', '');
  Singing.AddPair('trackIndex', TJSONNumber.Create(-1));
  Obj.AddPair('singing', Singing);
  Result := Items.Count;
  Items.AddElement(Obj);
end;

function TMusicStudioDocument.AddAudio: Integer;
var
  Items: TJSONArray;
  Obj, Audio: TJSONObject;
  GUID: TGUID;
begin
  Items := PatternArray;
  if Items = nil then
  begin
    Items := TJSONArray.Create;
    FRoot.AddPair('patterns', Items);
  end;
  CreateGUID(GUID);
  Obj := TJSONObject.Create;
  Obj.AddPair('id', GUIDToString(GUID));
  Obj.AddPair('kind', 'audio');
  Obj.AddPair('name', Format('オーディオクリップ %d', [Items.Count + 1]));
  Obj.AddPair('color', '#6FBFAD');
  Audio := TJSONObject.Create;
  Audio.AddPair('filePath', '');
  Audio.AddPair('volume', TJSONNumber.Create(1.0));
  Obj.AddPair('audio', Audio);
  Result := Items.Count;
  Items.AddElement(Obj);
end;

procedure TMusicStudioDocument.UpdatePattern(const Pattern: TMusicStudioPattern);
var
  Item: TJSONValue;
  Obj, Audio, Before: TJSONObject;
begin
  Audio := nil;
  if PatternArray = nil then raise Exception.Create('編集対象のパターンが見つかりません。');
  for Item in PatternArray do
  begin
    Obj := Item as TJSONObject;
    if Obj.GetValue('id').Value <> Pattern.ID then Continue;
    if Obj.GetValue('kind').Value <> Pattern.Kind then raise Exception.Create('この操作ではパターンの属性を変更できません。');
    Before := nil;
    if Pattern.Kind='tempo' then Before := TJSONObject(FRoot.Clone);
    try
    SetValue(Obj, 'name', TJSONString.Create(Pattern.Name));
    SetValue(Obj, 'color', TJSONString.Create(Pattern.Color));
    if Pattern.Kind='performance' then begin
      SetValue(Obj,'performance',TJSONObject.ParseJSONValue(Pattern.ConfigJSON));
      if Pattern.PerformanceAttribute<>'' then begin
        Audio := TJSONObject.Create; Audio.AddPair('attribute',Pattern.PerformanceAttribute);
        Audio.AddPair('id',Pattern.SharedPatternID); Audio.AddPair('revision',Pattern.LibraryRevision);
        SetValue(Obj,'performanceLibrary',Audio);
      end;
    end;
    if (Pattern.Kind='emotion') and (Pattern.SharedPatternID='') and (Pattern.ConfigJSON<>'') then SetValue(Obj,'expression',TJSONObject.ParseJSONValue(Pattern.ConfigJSON));
    if Pattern.Kind='tempo' then SetValue(Obj,'tempo',TJSONObject.ParseJSONValue(Pattern.ConfigJSON));
    if Pattern.Kind='selection' then SetValue(Obj,'selection',TJSONObject.ParseJSONValue(Pattern.ConfigJSON));
    if Pattern.Kind = 'audio' then
    begin
      Audio := Obj.GetValue('audio') as TJSONObject;
      SetValue(Audio, 'filePath', TJSONString.Create(Pattern.FilePath));
      SetValue(Audio, 'volume', TJSONNumber.Create(Pattern.Volume));
    end;
    if Pattern.Kind = 'singing' then
    begin
      Audio := Obj.GetValue('singing') as TJSONObject;
      SetValue(Audio, 'filePath', TJSONString.Create(Pattern.FilePath));
      SetValue(Audio, 'trackIndex', TJSONNumber.Create(Pattern.SourceTrack));
      SetValue(Audio, 'sourceStartSeconds',TJSONNumber.Create(Pattern.SourceStartSeconds));
    end;
    if (Pattern.Kind = 'audio') or (Pattern.Kind = 'singing') then
      SetValue(Audio, 'durationSeconds', TJSONNumber.Create(Pattern.Duration));
    if Pattern.Kind='tempo' then SyncTimingSeconds;
    except
      if Before<>nil then begin FRoot.Free; FRoot := Before; RebuildTiming; end;
      raise;
    end;
    Before.Free;
    Exit;
  end;
  raise Exception.Create('編集対象のパターンが見つかりません。');
end;

procedure TMusicStudioDocument.RemovePattern(Index: Integer);
begin
  if PatternInUse(PatternAt(Index).ID) then raise Exception.Create('配置中のパターンです。先にトラック上の配置を削除してください。');
  PatternArray.Remove(Index).Free;
end;

function TMusicStudioDocument.TrackCount: Integer;
begin Result := TJSONArray(FRoot.GetValue('tracks')).Count; end;
function TMusicStudioDocument.TrackAt(Index: Integer): TMusicStudioTrack;
var I,J: Integer; C: TMusicStudioPlacement;
begin
  Result := MusicStudioTrackAt(FRoot, Index);
  if (Result.PsdAssetID<>'') and Assigned(FAssetResolver) then Result.PsdPath := FAssetResolver(Result.PsdAssetID);
  for I := 0 to High(Result.Slots) do for J := 0 to High(Result.Slots[I].Clips) do begin
    C := Result.Slots[I].Clips[J];
    if C.TimeBase='beats' then begin
      Result.Slots[I].Clips[J].StartSeconds := BeatToSeconds(C.StartBeat);
      Result.Slots[I].Clips[J].LengthSeconds := BeatToSeconds(C.StartBeat+C.LengthBeats)-BeatToSeconds(C.StartBeat);
    end;
  end;
  if Length(Result.Slots)>0 then Result.Clips := Result.Slots[0].Clips;
end;
function TMusicStudioDocument.AddTrack(const Kind: string): Integer;
begin Result := MusicStudioAddTrack(FRoot, Kind); end;
function TMusicStudioDocument.AddSlot(TrackIndex: Integer; const Kind: string): Integer;
begin Result := MusicStudioAddSlot(FRoot,TrackIndex,Kind); end;
function TMusicStudioDocument.UpdateSlot(TrackIndex,SlotIndex: Integer; const Name,Color: string;
  const Accepts: TArray<string>; out ErrorText: string): Boolean;
begin Result := MusicStudioUpdateSlot(FRoot,TrackIndex,SlotIndex,Name,Color,Accepts,ErrorText); end;
procedure TMusicStudioDocument.RemoveSlot(TrackIndex,SlotIndex: Integer);
begin ApplyTimingMutation(procedure begin MusicStudioRemoveSlot(FRoot,TrackIndex,SlotIndex); end); end;
procedure TMusicStudioDocument.ReorderSlot(TrackIndex,FromIndex,ToIndex: Integer);
begin ApplyTimingMutation(procedure begin MusicStudioReorderSlot(FRoot,TrackIndex,FromIndex,ToIndex); end); end;
procedure TMusicStudioDocument.UpdateTrack(Index: Integer; const Name, Color, PsdPath: string);
begin
  if TrackAt(Index).PsdAssetID<>'' then MusicStudioUpdateTrack(FRoot,Index,Name,Color,'')
  else MusicStudioUpdateTrack(FRoot, Index, Name, Color, PsdPath);
end;
procedure TMusicStudioDocument.UpdatePsdTransform(Index: Integer; const Transform: TMusicStudioPsdTransform);
begin MusicStudioSetPsdTransform(FRoot,Index,Transform); end;
procedure TMusicStudioDocument.ReorderTrack(FromIndex,ToIndex: Integer);
begin ApplyTimingMutation(procedure begin MusicStudioReorderTrack(FRoot,FromIndex,ToIndex); end); end;
procedure TMusicStudioDocument.RemoveTrack(Index: Integer);
begin ApplyTimingMutation(procedure begin MusicStudioRemoveTrack(FRoot,Index); end); end;
function TMusicStudioDocument.AddPlacement(TrackIndex: Integer; const PatternID: string;
  StartSeconds, LengthSeconds: Double; out ErrorText: string): Boolean;
begin Result := AddPlacement(TrackIndex,0,PatternID,StartSeconds,LengthSeconds,ErrorText); end;
function TMusicStudioDocument.AddPlacement(TrackIndex,SlotIndex: Integer; const PatternID: string;
  StartSeconds,LengthSeconds: Double; out ErrorText: string): Boolean;
var I: Integer; P: TMusicStudioPattern; Perf: TMusicStudioPerformanceData; Tempo: TMusicStudioTempoPatternData; Beats: Double;
begin
  for I := 0 to PatternCount-1 do begin
    P := PatternAt(I); if (P.ID=PatternID) and ((P.Kind='performance') or (P.Kind='tempo')) then begin
      if (TrackIndex<0) or (TrackIndex>=TrackCount) then begin ErrorText := '配置先トラックを選択してください。'; Exit(False); end;
      if (P.Kind='performance') and (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>'') and
        (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>TrackAt(TrackIndex).PsdAssetID) then begin
        ErrorText := '演奏stepと配置先PSDの素材IDが一致しません。'; Exit(False);
      end;
      if P.Kind='performance' then begin Perf := TMusicStudioPerformanceData.Create;
        try Perf.LoadJSON(P.ConfigJSON); Beats := Perf.LengthBeats; finally Perf.Free; end;
      end else begin Tempo := TMusicStudioTempoPatternData.Create;
        try Tempo.LoadJSON(P.ConfigJSON); Beats := Tempo.LengthBeats; finally Tempo.Free; end;
      end;
      Result := AddBeatPlacement(TrackIndex,SlotIndex,PatternID,SecondsToBeat(StartSeconds),Beats,ErrorText);
      Exit;
    end;
  end;
  Result := MusicStudioAddPlacement(FRoot,TrackIndex,SlotIndex,PatternID,StartSeconds,LengthSeconds,ErrorText);
end;
function TMusicStudioDocument.PatternLengthBeats(const PatternID: string): Double;
var I: Integer; P: TMusicStudioPattern; Data: TMusicStudioPerformanceData;
begin
  Result := 0;
  for I := 0 to PatternCount-1 do begin
    P := PatternAt(I); if (P.ID<>PatternID) or (P.Kind<>'performance') then Continue;
    Data := TMusicStudioPerformanceData.Create;
    try Data.LoadJSON(P.ConfigJSON); Result := Data.LengthBeats; finally Data.Free; end;
    Exit;
  end;
end;
function TMusicStudioDocument.AddBeatPlacement(TrackIndex,SlotIndex: Integer; const PatternID: string;
  StartBeat,LengthBeats: Double; out ErrorText: string): Boolean;
var Before: TJSONObject; Start,Len,Limit: Double; K,I: Integer; P: TMusicStudioPattern;
begin
  Result := False; ErrorText := '拍の開始/長さが範囲外です。';
  if IsNan(StartBeat) or IsInfinite(StartBeat) or IsNan(LengthBeats) or IsInfinite(LengthBeats) or
    (StartBeat<0) or (LengthBeats<0.001) or (StartBeat+LengthBeats>1000000) then Exit;
  if (TrackIndex<0) or (TrackIndex>=TrackCount) then begin ErrorText := '配置先トラックを選択してください。'; Exit; end;
  for I := 0 to PatternCount-1 do begin
    P := PatternAt(I); if P.ID<>PatternID then Continue;
    if (P.Kind='performance') and (P.PerformanceAttribute<>'') and
      (P.PerformanceAttribute<>TrackAt(TrackIndex).PerformanceAttribute) then begin
      ErrorText := '配置先の演奏属性が一致しません。'; Exit;
    end;
    if not ((P.Kind='performance') or (P.Kind='tempo')) then begin ErrorText := 'この属性は秒で配置します。'; Exit; end;
    if (P.Kind='performance') and (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>'') and
      (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>TrackAt(TrackIndex).PsdAssetID) then begin
      ErrorText := '演奏stepと配置先PSDの素材IDが一致しません。'; Exit;
    end;
    Break;
  end;
  Limit := PatternLengthBeats(PatternID);
  if (Limit>0) and (MusicStudioComparePositions(LengthBeats,Limit)>0) then begin
    ErrorText := Format('パターンの末尾（%g拍）を超えて配置できません。',[Limit]); Exit;
  end;
  Before := TJSONObject(FRoot.Clone);
  try
    Start := BeatToSeconds(StartBeat); Len := BeatToSeconds(StartBeat+LengthBeats)-Start;
    if not MusicStudioAddPlacement(FRoot,TrackIndex,SlotIndex,PatternID,Start,Len,ErrorText) then Exit;
    K := Length(TrackAt(TrackIndex).Slots[SlotIndex].Clips)-1; MusicStudioSetPlacementBeats(FRoot,TrackIndex,SlotIndex,K,StartBeat,LengthBeats);
    if FRoot.GetValue('timing')=nil then SetValue(FRoot,'timing',TJSONObject.ParseJSONValue(ManualTimingJSON));
    try SyncTimingSeconds; Result := True; ErrorText := '';
    except on E: Exception do begin FRoot.Free; FRoot := Before; Before := nil; RebuildTiming; ErrorText := E.Message; end; end;
  finally Before.Free; end;
end;
procedure TMusicStudioDocument.ReplacePlacementPattern(TrackIndex,SlotIndex,ClipIndex: Integer; const PatternID: string);
var A: TJSONArray; C: TJSONObject; Track: TMusicStudioTrack; P: TMusicStudioPattern; I: Integer; Found: Boolean; Error: string;
begin
  Track := TrackAt(TrackIndex); Found := False;
  for I := 0 to PatternCount-1 do if PatternAt(I).ID=PatternID then begin P := PatternAt(I); Found := True; Break; end;
  if not Found then raise Exception.Create('参照するパターンがありません。');
  if not MusicStudioSlotCompatible(P.Kind,Track.Slots[SlotIndex],Error) then raise Exception.Create(Error);
  if (P.AssetID<>'') and (P.AssetID<>Track.PsdAssetID) then raise Exception.Create('別のPSDの表情は参照できません。');
  A := TJSONObject(TJSONArray(TJSONObject(TJSONArray(FRoot.GetValue('tracks'))[TrackIndex]).GetValue('slots'))[SlotIndex]).GetValue('clips') as TJSONArray;
  C := TJSONObject(A[ClipIndex]); C.RemovePair('patternId').Free; C.AddPair('patternId',PatternID);
end;
procedure TMusicStudioDocument.RemovePlacement(TrackIndex, ClipIndex: Integer);
begin RemovePlacement(TrackIndex,0,ClipIndex); end;
procedure TMusicStudioDocument.RemovePlacement(TrackIndex,SlotIndex,ClipIndex: Integer);
begin ApplyTimingMutation(procedure begin
  MusicStudioRemovePlacement(FRoot,TrackIndex,SlotIndex,ClipIndex); MusicStudioPruneSmallElements(FRoot);
end); end;
procedure TMusicStudioDocument.MovePlacement(TrackIndex, ClipIndex: Integer; StartSeconds, LengthSeconds: Double);
begin MovePlacement(TrackIndex,0,ClipIndex,StartSeconds,LengthSeconds); end;
procedure TMusicStudioDocument.MovePlacement(TrackIndex,SlotIndex,ClipIndex: Integer; StartSeconds,LengthSeconds: Double);
var C: TMusicStudioPlacement; Beat,Beats: Double; Error: string;
begin
  if IsNan(StartSeconds) or IsInfinite(StartSeconds) or IsNan(LengthSeconds) or IsInfinite(LengthSeconds) or
    (StartSeconds<0) or (LengthSeconds<=0) or (StartSeconds+LengthSeconds>604800) then
    raise EArgumentException.Create('開始/長さの秒が範囲外です。');
  C := TrackAt(TrackIndex).Slots[SlotIndex].Clips[ClipIndex];
  if C.TimeBase='beats' then begin
    Beat := SecondsToBeat(StartSeconds);
    if Abs(LengthSeconds-C.LengthSeconds)<0.000001 then Beats := C.LengthBeats else Beats := SecondsToBeat(StartSeconds+LengthSeconds)-Beat;
    if not MoveBeatPlacement(TrackIndex,SlotIndex,ClipIndex,Beat,Beats,Error) then raise EArgumentException.Create(Error);
    Exit;
  end;
  if LengthSeconds<0.001 then raise EArgumentException.Create('秒の配置長は0.001秒以上にしてください。');
  MusicStudioMovePlacement(FRoot,TrackIndex,SlotIndex,ClipIndex,StartSeconds,LengthSeconds);
end;
function TMusicStudioDocument.MoveBeatPlacement(TrackIndex,SlotIndex,ClipIndex: Integer; StartBeat,LengthBeats: Double; out ErrorText: string): Boolean;
var Start,Len,Limit: Double; Before: TJSONObject; C: TMusicStudioPlacement;
begin
  Result := False; ErrorText := '開始/長さの拍が範囲外です。';
  if IsNan(StartBeat) or IsInfinite(StartBeat) or IsNan(LengthBeats) or IsInfinite(LengthBeats) or
    (StartBeat<0) or (LengthBeats<0.001) or (StartBeat+LengthBeats>1000000) then Exit;
  C := TrackAt(TrackIndex).Slots[SlotIndex].Clips[ClipIndex]; Limit := PatternLengthBeats(C.PatternID);
  // 旧作品の長過ぎる配置は移動/短縮できるが、さらに伸ばさない。
  if (Limit>0) and (MusicStudioComparePositions(LengthBeats,Max(Limit,C.LengthBeats))>0) then begin
    ErrorText := Format('パターンの末尾（%g拍）を超えて伸ばせません。',[Limit]); Exit;
  end;
  Start := BeatToSeconds(StartBeat); Len := BeatToSeconds(StartBeat+LengthBeats)-Start;
  if (Start+Len>604800) or (Len<=0) then Exit;
  Before := TJSONObject(FRoot.Clone);
  try
    MusicStudioSetPlacementBeats(FRoot,TrackIndex,SlotIndex,ClipIndex,StartBeat,LengthBeats);
    MusicStudioMovePlacement(FRoot,TrackIndex,SlotIndex,ClipIndex,Start,Len);
    try SyncTimingSeconds; Result := True; ErrorText := '';
    except on E: Exception do begin FRoot.Free; FRoot := Before; Before := nil; RebuildTiming; ErrorText := E.Message; end; end;
  finally Before.Free; end;
end;
function TMusicStudioDocument.PatternInUse(const PatternID: string): Boolean;
begin Result := MusicStudioPatternInUse(FRoot, PatternID); end;

end.
