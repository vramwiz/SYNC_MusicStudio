unit SYNC_MusicStudio_InstrumentRules;
// 全楽器共通の読込時解析。上位名に依存せず、再生は固定キー参照だけを使用する。
interface
uses System.JSON, System.Generics.Collections, SYNC_MusicStudio_DrumPsdRules;
const
  INSTRUMENT_SELECTION_ROWS: array[0..3] of string = ('表情','顔色','記号','ポーズ');
  INSTRUMENT_ACTION_ROWS: array[0..3] of string = ('右手','左手','右足','左足');
type
  TInstrumentRowKind = (irkSelection,irkAction);
  TInstrumentReference = record
    Layer: TDrumPsdLayer;
    Row,Choice,ChannelKey,PatternKey: string;
    Kind: TInstrumentRowKind;
    Stage: Integer;
    Ambiguous: Boolean;
  end;
  TInstrumentRow = record
    Name: string;
    Kind: TInstrumentRowKind;
    Choices: TArray<string>;
  end;
  TInstrumentState = record
    Row,Choice: string;
    Stage: Integer;
  end;
  TMusicStudioInstrumentRules = class
  private
    FLayers: TArray<TDrumPsdLayer>;
    FReferences: TArray<TInstrumentReference>;
    FRows: TArray<TInstrumentRow>;
    FDiagnostics: TArray<string>;
    FByKey: TDictionary<string,Integer>;
    procedure IndexLayers;
    procedure VisibleAncestors(Target: TJSONObject; const Key: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    // 元PSDを書かず、読込メタデータから行・候補・関連する全レイヤーを構築する。
    procedure Build(const Layers: TArray<TDrumPsdLayer>);
    function Clone: TMusicStudioInstrumentRules;
    function RowCount: Integer;
    function RowAt(Index: Integer): TInstrumentRow;
    function HasChoice(const Row,Choice: string): Boolean;
    function Stages(const Row,Choice: string): TArray<Integer>;
    // 指定なしは元の表示。欠損段階は当該グループを消し、ポーズは他の制御行を抑制する。
    function Visibility(const States: TArray<TInstrumentState>): TJSONObject;
    function DiagnosticJSON: string;
  end;
implementation
uses System.SysUtils, SYNC_MusicStudio_ArtLayerName;
function Keyword(const Name: string; out Kind: TInstrumentRowKind): Boolean;
var S: string;
begin
  for S in INSTRUMENT_SELECTION_ROWS do if S=Name then begin Kind := irkSelection; Exit(True); end;
  for S in INSTRUMENT_ACTION_ROWS do if S=Name then begin Kind := irkAction; Exit(True); end;
  Result := False;
end;
procedure Put(Target: TJSONObject; const Key: string; Value: Boolean);
begin Target.RemovePair(Key).Free; Target.AddPair(Key,TJSONBool.Create(Value)); end;
constructor TMusicStudioInstrumentRules.Create;
begin inherited; FByKey := TDictionary<string,Integer>.Create; end;
destructor TMusicStudioInstrumentRules.Destroy;
begin FByKey.Free; inherited; end;
procedure TMusicStudioInstrumentRules.Clear;
begin FLayers := nil; FReferences := nil; FRows := nil; FDiagnostics := nil; FByKey.Clear; end;
procedure TMusicStudioInstrumentRules.IndexLayers;
var I: Integer;
begin FByKey.Clear; for I := 0 to High(FLayers) do FByKey.Add(FLayers[I].Key,I); end;
procedure TMusicStudioInstrumentRules.Build(const Layers: TArray<TDrumPsdLayer>);
var Refs: TList<TInstrumentReference>; Rows: TList<TInstrumentRow>; Issues: TList<string>;
  Seen: TDictionary<string,Integer>; Names: TList<string>; Row: TInstrumentRow; Ref,Old: TInstrumentReference;
  I,J,K,N,Stage,ParentIndex: Integer; RowName,Choice,Body,Parent,Logical: string; Kind,ParentKind: TInstrumentRowKind;
  Nested,Numeric: Boolean;
begin
  Clear; FLayers := Copy(Layers); IndexLayers;
  Refs := TList<TInstrumentReference>.Create; Rows := TList<TInstrumentRow>.Create;
  Issues := TList<string>.Create; Seen := TDictionary<string,Integer>.Create; Names := TList<string>.Create;
  try
    for I := 0 to High(FLayers) do begin
      RowName := ParseLayerName(FLayers[I].Name).DisplayName;
      if not FLayers[I].IsGroup or not Keyword(RowName,Kind) then Continue;
      Nested := False; Parent := FLayers[I].ParentKey; N := 0;
      while (Parent<>'') and FByKey.TryGetValue(Parent,ParentIndex) do begin
        Inc(N); if N>128 then begin Nested := True; Break; end;
        if Keyword(ParseLayerName(FLayers[ParentIndex].Name).DisplayName,ParentKind) then Nested := True;
        Parent := FLayers[ParentIndex].ParentKey;
      end;
      if Nested then begin Issues.Add('固定キーワードの入れ子は未対応: '+FLayers[I].Path); Continue; end;
      for J := 0 to High(FLayers) do if FLayers[J].ParentKey=FLayers[I].Key then begin
        Choice := ParseLayerName(FLayers[J].Name).DisplayName;
        if Choice='' then begin Issues.Add('空の候補名: '+FLayers[J].Path); Continue; end;
        Ref := Default(TInstrumentReference); Ref.Row := RowName; Ref.Kind := Kind;
        Ref.Choice := Choice; Ref.ChannelKey := FLayers[I].Key; Ref.PatternKey := FLayers[J].Key; Ref.Stage := -1;
        if Kind=irkSelection then begin
          Ref.Layer := FLayers[J]; Logical := Ref.ChannelKey+'|'+Choice;
          if Seen.TryGetValue(Logical,K) then begin Old := Refs[K]; Old.Ambiguous := True; Refs[K] := Old; Ref.Ambiguous := True; Issues.Add('同じ親の候補名が重複: '+FLayers[J].Path); end
          else Seen.Add(Logical,Refs.Count);
          Refs.Add(Ref);
        end else begin
          if not FLayers[J].IsGroup then begin Issues.Add('動作パターンはグループで指定: '+FLayers[J].Path); Continue; end;
          for K := 0 to High(FLayers) do if FLayers[K].ParentKey=FLayers[J].Key then begin
            Body := ParseLayerName(FLayers[K].Name).DisplayName; Numeric := Body<>'';
            for N := 1 to Length(Body) do if not CharInSet(Body[N],['0'..'9']) then Numeric := False;
            if not Numeric or not TryStrToInt(Body,Stage) or (Stage>1000000) then begin Issues.Add('数値差分でないため未登録: '+FLayers[K].Path); Continue; end;
            Ref.Layer := FLayers[K]; Ref.Stage := Stage; Ref.Ambiguous := False;
            Logical := Ref.ChannelKey+'|'+Choice+'|'+IntToStr(Stage);
            if Seen.TryGetValue(Logical,N) then begin Old := Refs[N]; Old.Ambiguous := True; Refs[N] := Old; Ref.Ambiguous := True; Issues.Add('同じ行・パターンの差分が重複: '+FLayers[K].Path); end
            else Seen.Add(Logical,Refs.Count);
            Refs.Add(Ref);
          end;
        end;
      end;
    end;
    for Ref in Refs do if not Ref.Ambiguous and ((Ref.Kind=irkAction) or not Ref.Layer.Visible) then begin
      N := -1; for I := 0 to Rows.Count-1 do if Rows[I].Name=Ref.Row then N := I;
      if N<0 then begin Row := Default(TInstrumentRow); Row.Name := Ref.Row; Row.Kind := Ref.Kind; Rows.Add(Row); N := Rows.Count-1; end;
      Row := Rows[N]; Names.Clear; Names.AddRange(Row.Choices);
      if not Names.Contains(Ref.Choice) then Names.Add(Ref.Choice);
      Row.Choices := Names.ToArray; Rows[N] := Row;
    end;
    FReferences := Refs.ToArray; FRows := Rows.ToArray; FDiagnostics := Issues.ToArray;
  finally Names.Free; Seen.Free; Issues.Free; Rows.Free; Refs.Free; end;
end;
function TMusicStudioInstrumentRules.Clone: TMusicStudioInstrumentRules;
var I: Integer;
begin
  Result := TMusicStudioInstrumentRules.Create;
  try
    Result.FLayers := Copy(FLayers); Result.FReferences := Copy(FReferences); Result.FDiagnostics := Copy(FDiagnostics);
    Result.FRows := Copy(FRows); for I := 0 to High(FRows) do Result.FRows[I].Choices := Copy(FRows[I].Choices);
    Result.IndexLayers;
  except Result.Free; raise; end;
end;
function TMusicStudioInstrumentRules.RowCount: Integer;
begin Result := Length(FRows); end;
function TMusicStudioInstrumentRules.RowAt(Index: Integer): TInstrumentRow;
begin Result := FRows[Index]; Result.Choices := Copy(Result.Choices); end;
function TMusicStudioInstrumentRules.HasChoice(const Row,Choice: string): Boolean;
var R: TInstrumentRow; S: string;
begin for R in FRows do if R.Name=Row then for S in R.Choices do if S=Choice then Exit(True); Result := False; end;
function TMusicStudioInstrumentRules.Stages(const Row,Choice: string): TArray<Integer>;
var R: TInstrumentReference; Values: TList<Integer>;
begin
  Values := TList<Integer>.Create;
  try
    for R in FReferences do if (R.Row=Row) and (R.Choice=Choice) and (R.Kind=irkAction) and not R.Ambiguous and not Values.Contains(R.Stage) then Values.Add(R.Stage);
    Values.Sort; Result := Values.ToArray;
  finally Values.Free; end;
end;
procedure TMusicStudioInstrumentRules.VisibleAncestors(Target: TJSONObject; const Key: string);
var Current: string; I,J,Depth: Integer;
begin
  Current := Key; Depth := 0;
  while (Current<>'') and FByKey.TryGetValue(Current,I) do begin
    Inc(Depth); if Depth>128 then Break;
    // 既存の手動レイヤー選択と同じ、先頭*の兄弟排他を祖先にも適用する。
    if (FLayers[I].Name<>'') and (FLayers[I].Name[1]='*') then
      for J := 0 to High(FLayers) do
        if (J<>I) and (FLayers[J].ParentKey=FLayers[I].ParentKey) and
          (FLayers[J].Name<>'') and (FLayers[J].Name[1]='*') then Put(Target,FLayers[J].Key,False);
    Put(Target,Current,True); Current := FLayers[I].ParentKey;
  end;
end;
function TMusicStudioInstrumentRules.Visibility(const States: TArray<TInstrumentState>): TJSONObject;
var R: TInstrumentReference; State: TInstrumentState; Pose,MatchingChannel: Boolean; Other: TInstrumentReference;
  ActorParent: string; Layer: TDrumPsdLayer;
begin
  Result := TJSONObject.Create;
  try
    for R in FReferences do begin
      Put(Result,R.Layer.Key,R.Layer.Visible);
      if FByKey.ContainsKey(R.PatternKey) then Put(Result,R.PatternKey,FLayers[FByKey[R.PatternKey]].Visible);
      if FByKey.ContainsKey(R.ChannelKey) then Put(Result,R.ChannelKey,FLayers[FByKey[R.ChannelKey]].Visible);
      if (R.Row='ポーズ') and FByKey.ContainsKey(R.ChannelKey) then begin
        ActorParent := FLayers[FByKey[R.ChannelKey]].ParentKey;
        if ActorParent<>'' then for Layer in FLayers do if Layer.ParentKey=ActorParent then Put(Result,Layer.Key,Layer.Visible);
      end;
    end;
    Pose := False; for State in States do if (State.Row='ポーズ') and HasChoice(State.Row,State.Choice) then Pose := True;
    for State in States do begin
      if (Pose and (State.Row<>'ポーズ')) or not HasChoice(State.Row,State.Choice) then Continue;
      for R in FReferences do if R.Row=State.Row then begin
        MatchingChannel := R.Kind=irkAction;
        if not MatchingChannel then for Other in FReferences do if (Other.ChannelKey=R.ChannelKey) and (Other.Choice=State.Choice) and not Other.Ambiguous then MatchingChannel := True;
        if MatchingChannel then Put(Result,R.Layer.Key,False);
      end;
      for R in FReferences do if (R.Row=State.Row) and (R.Choice=State.Choice) and not R.Ambiguous and
        ((R.Kind=irkSelection) or (R.Stage=State.Stage)) then VisibleAncestors(Result,R.Layer.Key);
    end;
    if Pose then for R in FReferences do if R.Row<>'ポーズ' then Put(Result,R.ChannelKey,False);
    if Pose then for State in States do if State.Row='ポーズ' then
      for R in FReferences do if (R.Row=State.Row) and (R.Choice=State.Choice) and not R.Ambiguous then begin
        ActorParent := FLayers[FByKey[R.ChannelKey]].ParentKey;
        // 上位名は使わず、ポーズ行と同じ親の通常身体を差し替える。別ルートの機材は消さない。
        if ActorParent<>'' then for Layer in FLayers do
          if (Layer.ParentKey=ActorParent) and (Layer.Key<>R.ChannelKey) then Put(Result,Layer.Key,False);
      end;
  except Result.Free; raise; end;
end;
function TMusicStudioInstrumentRules.DiagnosticJSON: string;
var Root,O: TJSONObject; Rows,Choices,Issues: TJSONArray; R: TInstrumentRow; S: string;
begin
  Root := TJSONObject.Create;
  try
    Rows := TJSONArray.Create; Root.AddPair('rows',Rows);
    for R in FRows do begin
      O := TJSONObject.Create; O.AddPair('name',R.Name); O.AddPair('action',TJSONBool.Create(R.Kind=irkAction));
      Choices := TJSONArray.Create; O.AddPair('choices',Choices); for S in R.Choices do Choices.Add(S); Rows.AddElement(O);
    end;
    Issues := TJSONArray.Create; Root.AddPair('diagnostics',Issues); for S in FDiagnostics do Issues.Add(S);
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
end.
