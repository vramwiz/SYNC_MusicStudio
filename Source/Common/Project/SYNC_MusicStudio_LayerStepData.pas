unit SYNC_MusicStudio_LayerStepData;

// 演奏パターン内の拍区間ごとのPSD表示設定。ノートと未知フィールドを保護し、PSD/音声を読まない。
interface
uses System.JSON, System.Generics.Collections;
type
  TMusicStudioLayerStep = record
    ID,ConfigJSON: string;
    StartBeat,LengthBeats: Double;
    HoldUntilNext: Boolean;
  end;
  TMusicStudioLayerStepData = class
  private
    FOriginal: TJSONObject;
    FExtras: TObjectList<TJSONObject>;
    FSteps: TArray<TMusicStudioLayerStep>;
    FAssetID: string;
    FLengthBeats: Double;
    FEnabled: Boolean;
    procedure ValidateStep(const Step: TMusicStudioLayerStep; PatternLength: Double);
    procedure SetLengthBeats(Value: Double);
    procedure SetAssetID(const Value: string);
    procedure NormalizePointLengths;
  public
    constructor Create;
    destructor Destroy; override;
    // 検証済み候補だけを採用。壊れたJSONは現在のデータを変えない。
    procedure LoadJSON(const Text: string);
    function ConfigJSON: string;
    procedure Enable(const AssetID: string);
    function StepCount: Integer;
    function StepAt(Index: Integer): TMusicStudioLayerStep;
    // 同じ開始拍は既存stepを選択する。ズーム自体はこのAPIを呼ばない。
    function AddStep(StartBeat,LengthBeats: Double; const ConfigJSON: string): Integer;
    // 新しい設定点は次の開始点（なければパターン末尾）まで保持。旧区間stepは保持する。
    function AddSettingPoint(StartBeat: Double; const ConfigJSON: string): Integer;
    function EditableBounds(Index: Integer; StartBeat,LengthBeats: Double; Hold: Boolean;
      out EffectiveLength: Double; out ErrorText: string): Boolean;
    procedure SetEditableBounds(Index: Integer; StartBeat,LengthBeats: Double; Hold: Boolean);
    procedure SetStep(Index: Integer; const Step: TMusicStudioLayerStep);
    procedure DeleteStep(Index: Integer);
    // 重なる区間では開始拍が新しいstepを優先。終端は含まない。
    function ActiveStepAt(Beat: Double; OriginBeat: Double = 0): Integer;
    property Enabled: Boolean read FEnabled;
    property AssetID: string read FAssetID write SetAssetID;
    property LengthBeats: Double read FLengthBeats write SetLengthBeats;
  end;
function MusicStudioPerformanceHasLayerSteps(const ConfigJSON: string): Boolean;
function MusicStudioPerformanceLayerAsset(const ConfigJSON: string): string;
function MusicStudioMergeLayerStepConfig(const BaseConfig,StepConfig: string): string;
implementation
uses System.SysUtils, System.Math, SYNC_MusicStudio_BeatData;
procedure Put(Obj: TJSONObject; const Key: string; Value: TJSONValue);
begin Obj.RemovePair(Key).Free; Obj.AddPair(Key,Value); end;
function ObjectJSON(const Text: string): TJSONObject;
var V: TJSONValue;
begin
  if Text.Trim='' then Exit(TJSONObject.Create);
  V := TJSONObject.ParseJSONValue(Text);
  if not (V is TJSONObject) then begin V.Free; raise EArgumentException.Create('演奏stepのJSONはオブジェクトで指定してください。'); end;
  Result := TJSONObject(V);
end;
function Number(Obj: TJSONObject; const Key: string): Double;
begin
  if not (Obj.GetValue(Key) is TJSONNumber) then raise EArgumentException.Create(Key+'は数値で指定してください。');
  Result := TJSONNumber(Obj.GetValue(Key)).AsDouble;
end;
procedure ValidateConfig(const Text: string);
var Obj: TJSONObject; V: TJSONValue; Pair: TJSONPair;
begin
  Obj := ObjectJSON(Text);
  try
    V := Obj.GetValue('visibility');
    if Assigned(V) then begin
      if not (V is TJSONObject) then raise EArgumentException.Create('stepのvisibilityはオブジェクトで指定してください。');
      for Pair in TJSONObject(V) do if (Pair.JsonString.Value.Trim='') or not (Pair.JsonValue is TJSONBool) then
        raise EArgumentException.Create('PSDレイヤーは固定キーと真偽値で指定してください。');
    end;
  finally Obj.Free; end;
end;
constructor TMusicStudioLayerStepData.Create;
begin inherited; FOriginal := TJSONObject.Create; FExtras := TObjectList<TJSONObject>.Create(True); FLengthBeats := 16; end;
destructor TMusicStudioLayerStepData.Destroy;
begin FExtras.Free; FOriginal.Free; inherited; end;
procedure TMusicStudioLayerStepData.SetAssetID(const Value: string);
var G: TGUID;
begin
  if Value<>'' then begin G := StringToGUID('{'+Value+'}'); if IsEqualGUID(G,Default(TGUID)) then raise EArgumentException.Create('PSD IDが不正です。'); end;
  if (Value='') and (Length(FSteps)>0) then raise EArgumentException.Create('stepのPSD参照を外せません。');
  FAssetID := Value;
end;
procedure TMusicStudioLayerStepData.ValidateStep(const Step: TMusicStudioLayerStep; PatternLength: Double);
begin
  if (Step.ID.Trim='') or IsNan(Step.StartBeat) or IsInfinite(Step.StartBeat) or (Step.StartBeat<0) or
    IsNan(Step.LengthBeats) or IsInfinite(Step.LengthBeats) or (Step.LengthBeats<=0) or
    (not Step.HoldUntilNext and (Step.LengthBeats<1/1024)) or
    (Step.StartBeat+Step.LengthBeats>PatternLength+1E-9) then raise EArgumentException.Create('stepの開始/長さがパターンの範囲外です。');
  ValidateConfig(Step.ConfigJSON);
end;
procedure TMusicStudioLayerStepData.SetLengthBeats(Value: Double);
var Step: TMusicStudioLayerStep; Data: TMusicStudioPerformanceData; I: Integer;
begin
  Data := TMusicStudioPerformanceData.Create;
  try Data.LoadJSON(FOriginal); Data.LengthBeats := Value;
    for I := 0 to High(FSteps) do begin
      Step := FSteps[I];
      if Step.HoldUntilNext then Step.LengthBeats := Value-Step.StartBeat;
      ValidateStep(Step,Value);
    end;
  finally Data.Free; end;
  FLengthBeats := Value; NormalizePointLengths;
end;
procedure TMusicStudioLayerStepData.NormalizePointLengths;
var I,L,R,M: Integer; Starts: TArray<Double>;
begin
  SetLength(Starts,Length(FSteps)); for I := 0 to High(FSteps) do Starts[I] := FSteps[I].StartBeat;
  TArray.Sort<Double>(Starts);
  for I := 0 to High(FSteps) do if FSteps[I].HoldUntilNext then begin
    L := 0; R := Length(Starts);
    while L<R do begin M := (L+R) div 2;
      if Starts[M]<=FSteps[I].StartBeat then L := M+1 else R := M;
    end;
    if L<Length(Starts) then FSteps[I].LengthBeats := Starts[L]-FSteps[I].StartBeat
    else FSteps[I].LengthBeats := FLengthBeats-FSteps[I].StartBeat;
  end;
end;
procedure TMusicStudioLayerStepData.Enable(const AssetID: string);
begin SetAssetID(AssetID); FEnabled := True; end;
procedure TMusicStudioLayerStepData.LoadJSON(const Text: string);
var Root,Obj,Container: TJSONObject; Value: TJSONValue; ArrayValue: TJSONArray;
  Candidate: TMusicStudioLayerStepData; Performance: TMusicStudioPerformanceData; I,J: Integer;
  Step: TMusicStudioLayerStep;
begin
  Root := ObjectJSON(Text); Candidate := TMusicStudioLayerStepData.Create; Performance := TMusicStudioPerformanceData.Create;
  try
    Performance.LoadJSON(Root); Candidate.FLengthBeats := Performance.LengthBeats;
    Value := Root.GetValue('layerSteps'); Candidate.FEnabled := Value<>nil;
    if Value<>nil then begin
      if not (Value is TJSONObject) then raise EArgumentException.Create('layerStepsはオブジェクトで指定してください。');
      Container := TJSONObject(Value);
      if Assigned(Container.GetValue('version')) and (Number(Container,'version')<>1) then raise EArgumentException.Create('layerSteps.versionは1のみ対応します。');
      if not (Container.GetValue('assetId') is TJSONString) then raise EArgumentException.Create('layerSteps.assetIdは文字列で指定してください。');
      Candidate.AssetID := Container.GetValue('assetId').Value;
      if not (Container.GetValue('steps') is TJSONArray) then raise EArgumentException.Create('layerSteps.stepsは配列で指定してください。');
      ArrayValue := TJSONArray(Container.GetValue('steps'));
      if ArrayValue.Count>8192 then raise EArgumentException.Create('stepは8192個までです。');
      if (ArrayValue.Count>0) and (Candidate.AssetID='') then raise EArgumentException.Create('stepを設定する前に共有PSDを割り当ててください。');
      SetLength(Candidate.FSteps,ArrayValue.Count);
      for I := 0 to ArrayValue.Count-1 do begin
        if not (ArrayValue.Items[I] is TJSONObject) then raise EArgumentException.Create('stepはオブジェクトで指定してください。');
        Obj := TJSONObject(ArrayValue.Items[I]);
        if not (Obj.GetValue('id') is TJSONString) or not (Obj.GetValue('config') is TJSONObject) then raise EArgumentException.Create('stepのid/configが不正です。');
        Step.ID := Obj.GetValue('id').Value; Step.StartBeat := Number(Obj,'startBeat'); Step.LengthBeats := Number(Obj,'lengthBeats'); Step.ConfigJSON := Obj.GetValue('config').ToJSON;
        Value := Obj.GetValue('holdUntilNext');
        if Assigned(Value) and not (Value is TJSONBool) then raise EArgumentException.Create('holdUntilNextは真偽値で指定してください。');
        Step.HoldUntilNext := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
        Candidate.ValidateStep(Step,Candidate.LengthBeats);
        for J := 0 to I-1 do if (Candidate.FSteps[J].ID=Step.ID) or (Abs(Candidate.FSteps[J].StartBeat-Step.StartBeat)<1E-9) then
          raise EArgumentException.Create('stepのID/開始拍が重複しています。');
        Candidate.FSteps[I] := Step; Candidate.FExtras.Add(TJSONObject(Obj.Clone));
      end;
    end;
    Candidate.NormalizePointLengths;
    FOriginal.Free; FOriginal := TJSONObject(Root.Clone); FExtras.Free; FExtras := Candidate.FExtras; Candidate.FExtras := nil;
    FSteps := Candidate.FSteps; FLengthBeats := Candidate.FLengthBeats; FEnabled := Candidate.Enabled; FAssetID := Candidate.AssetID;
  finally Performance.Free; Candidate.Free; Root.Free; end;
end;
function TMusicStudioLayerStepData.ConfigJSON: string;
var Root,Container,Obj: TJSONObject; Arr: TJSONArray; I: Integer;
begin
  Root := TJSONObject(FOriginal.Clone);
  try
    // Canonical order also makes modal Undo/Redo snapshots stable after reload.
    Container := nil;
    if FEnabled then begin
      if Root.GetValue('layerSteps') is TJSONObject then Container := TJSONObject(Root.GetValue('layerSteps').Clone)
      else Container := TJSONObject.Create;
      Root.RemovePair('layerSteps').Free;
    end;
    Put(Root,'lengthBeats',TJSONNumber.Create(FLengthBeats));
    if FEnabled then begin
      Root.AddPair('layerSteps',Container);
      Put(Container,'version',TJSONNumber.Create(1)); Put(Container,'assetId',TJSONString.Create(FAssetID)); Arr := TJSONArray.Create;
      Put(Container,'steps',Arr);
      for I := 0 to High(FSteps) do begin
        Obj := TJSONObject(FExtras[I].Clone); Put(Obj,'id',TJSONString.Create(FSteps[I].ID));
        Put(Obj,'startBeat',TJSONNumber.Create(FSteps[I].StartBeat)); Put(Obj,'lengthBeats',TJSONNumber.Create(FSteps[I].LengthBeats));
        if FSteps[I].HoldUntilNext then Put(Obj,'holdUntilNext',TJSONBool.Create(True))
        else if Obj.GetValue('holdUntilNext')<>nil then Put(Obj,'holdUntilNext',TJSONBool.Create(False));
        Put(Obj,'config',TJSONObject.ParseJSONValue(FSteps[I].ConfigJSON)); Arr.AddElement(Obj);
      end;
    end;
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
function TMusicStudioLayerStepData.StepCount: Integer;
begin Result := Length(FSteps); end;
function TMusicStudioLayerStepData.StepAt(Index: Integer): TMusicStudioLayerStep;
begin Result := FSteps[Index]; end;
function TMusicStudioLayerStepData.AddStep(StartBeat,LengthBeats: Double; const ConfigJSON: string): Integer;
var Step: TMusicStudioLayerStep; G: TGUID; I: Integer;
begin
  if not FEnabled or (FAssetID='') then raise EArgumentException.Create('先に歌唱PSDスロットへ共有PSDを割り当ててください。');
  for I := 0 to High(FSteps) do if Abs(FSteps[I].StartBeat-StartBeat)<1E-9 then Exit(I);
  if Length(FSteps)>=8192 then raise EArgumentException.Create('stepは8192個までです。');
  CreateGUID(G); Step.ID := GUIDToString(G); Step.StartBeat := StartBeat; Step.LengthBeats := LengthBeats; Step.ConfigJSON := ConfigJSON;
  Step.HoldUntilNext := False;
  ValidateStep(Step,FLengthBeats); Result := Length(FSteps); SetLength(FSteps,Result+1); FSteps[Result] := Step; FExtras.Add(TJSONObject.Create); NormalizePointLengths;
end;
function TMusicStudioLayerStepData.AddSettingPoint(StartBeat: Double; const ConfigJSON: string): Integer;
var I: Integer; Step: TMusicStudioLayerStep; G: TGUID;
begin
  if not FEnabled or (FAssetID='') then raise EArgumentException.Create('先に歌唱PSDスロットへ共有PSDを割り当ててください。');
  for I := 0 to High(FSteps) do if Abs(FSteps[I].StartBeat-StartBeat)<1E-9 then begin
    Result := I; Exit;
  end;
  for I := 0 to High(FSteps) do if not FSteps[I].HoldUntilNext and
    (MusicStudioComparePositions(StartBeat,FSteps[I].StartBeat)>0) and
    (MusicStudioComparePositions(StartBeat,FSteps[I].StartBeat+FSteps[I].LengthBeats)<0) then
    raise EArgumentException.Create('この位置には区間設定があります。四角を選択して編集してください。');
  if Length(FSteps)>=8192 then raise EArgumentException.Create('設定点は8192個までです。');
  CreateGUID(G); Step.ID := GUIDToString(G); Step.StartBeat := StartBeat;
  Step.LengthBeats := FLengthBeats-StartBeat; Step.ConfigJSON := ConfigJSON; Step.HoldUntilNext := True;
  ValidateStep(Step,FLengthBeats); Result := Length(FSteps); SetLength(FSteps,Result+1);
  FSteps[Result] := Step; FExtras.Add(TJSONObject.Create); NormalizePointLengths;
end;
function TMusicStudioLayerStepData.EditableBounds(Index: Integer; StartBeat,LengthBeats: Double; Hold: Boolean;
  out EffectiveLength: Double; out ErrorText: string): Boolean;
var Starts: TArray<Double>; I,L,R,M: Integer; OtherEnd,EndBeat: Double;
  function NextStart(Value: Double): Double;
  begin
    L := 0; R := Length(Starts);
    while L<R do begin M := (L+R) div 2; if Starts[M]<=Value then L := M+1 else R := M; end;
    if L<Length(Starts) then Result := Starts[L] else Result := FLengthBeats;
  end;
begin
  Result := False; ErrorText := ''; EffectiveLength := LengthBeats;
  if (Index<0) or (Index>=Length(FSteps)) or IsNan(StartBeat) or IsInfinite(StartBeat) or
    IsNan(LengthBeats) or IsInfinite(LengthBeats) or (StartBeat<0) or (StartBeat>=FLengthBeats) then begin
    ErrorText := 'パターン内の位置を指定してください。'; Exit;
  end;
  SetLength(Starts,Length(FSteps));
  for I := 0 to High(FSteps) do begin
    if I=Index then Starts[I] := StartBeat else begin Starts[I] := FSteps[I].StartBeat;
      if Abs(Starts[I]-StartBeat)<1E-9 then begin ErrorText := '同じ位置に設定があります。'; Exit; end;
    end;
  end;
  TArray.Sort<Double>(Starts);
  if Hold then EffectiveLength := NextStart(StartBeat)-StartBeat;
  if (EffectiveLength<=0) or (not Hold and (EffectiveLength<1/1024)) or
    (MusicStudioComparePositions(StartBeat+EffectiveLength,FLengthBeats)>0) then begin
    ErrorText := '区間はパターン内の正の長さにしてください。'; Exit;
  end;
  EndBeat := StartBeat+EffectiveLength;
  for I := 0 to High(FSteps) do if I<>Index then begin
    if FSteps[I].HoldUntilNext then OtherEnd := NextStart(FSteps[I].StartBeat)
    else OtherEnd := FSteps[I].StartBeat+FSteps[I].LengthBeats;
    if (MusicStudioComparePositions(StartBeat,OtherEnd)<0) and
      (MusicStudioComparePositions(EndBeat,FSteps[I].StartBeat)>0) then begin
      ErrorText := 'ほかの四角と重なるため変更できません。'; Exit;
    end;
  end;
  Result := True;
end;
procedure TMusicStudioLayerStepData.SetEditableBounds(Index: Integer; StartBeat,LengthBeats: Double; Hold: Boolean);
var Step: TMusicStudioLayerStep; Length: Double; ErrorText: string;
begin
  if not EditableBounds(Index,StartBeat,LengthBeats,Hold,Length,ErrorText) then raise EArgumentException.Create(ErrorText);
  Step := FSteps[Index]; Step.StartBeat := StartBeat; Step.LengthBeats := Length; Step.HoldUntilNext := Hold;
  SetStep(Index,Step);
end;
procedure TMusicStudioLayerStepData.SetStep(Index: Integer; const Step: TMusicStudioLayerStep);
var I: Integer;
begin
  ValidateStep(Step,FLengthBeats);
  if Step.ID<>FSteps[Index].ID then raise EArgumentException.Create('step IDは変更できません。');
  for I := 0 to High(FSteps) do if (I<>Index) and (Abs(FSteps[I].StartBeat-Step.StartBeat)<1E-9) then raise EArgumentException.Create('同じ開始拍のstepがあります。');
  FSteps[Index] := Step; NormalizePointLengths;
end;
procedure TMusicStudioLayerStepData.DeleteStep(Index: Integer);
var I: Integer;
begin
  if (Index<0) or (Index>=Length(FSteps)) then Exit;
  for I := Index to High(FSteps)-1 do FSteps[I] := FSteps[I+1]; SetLength(FSteps,Length(FSteps)-1); FExtras.Delete(Index); NormalizePointLengths;
end;
function TMusicStudioLayerStepData.ActiveStepAt(Beat: Double; OriginBeat: Double): Integer;
var I: Integer; Latest: Double;
begin
  Result := -1; Latest := -1;
  if IsNan(Beat) or IsInfinite(Beat) or IsNan(OriginBeat) or IsInfinite(OriginBeat) or
    (MusicStudioComparePositions(Beat,OriginBeat)<0) or (MusicStudioComparePositions(Beat,OriginBeat+FLengthBeats)>=0) then Exit;
  // Compare absolute boundaries: subtracting clip start can turn 4.1 into 0.09999999999999964.
  for I := 0 to High(FSteps) do if (MusicStudioComparePositions(Beat,OriginBeat+FSteps[I].StartBeat)>=0) and
    (MusicStudioComparePositions(Beat,OriginBeat+FSteps[I].StartBeat+FSteps[I].LengthBeats)<0) and
    (FSteps[I].StartBeat>Latest) then begin Result := I; Latest := FSteps[I].StartBeat; end;
end;
function MusicStudioPerformanceHasLayerSteps(const ConfigJSON: string): Boolean;
var Obj: TJSONObject;
begin Obj := ObjectJSON(ConfigJSON); try Result := Assigned(Obj.GetValue('layerSteps')); finally Obj.Free; end; end;
function MusicStudioPerformanceLayerAsset(const ConfigJSON: string): string;
var Data: TMusicStudioLayerStepData; Root: TJSONObject; V: TJSONValue;
begin
  Root := ObjectJSON(ConfigJSON);
  try
    V := Root.GetValue('instrumentTimeline');
    if V is TJSONObject then if TJSONObject(V).GetValue('assetId') is TJSONString then Exit(TJSONObject(V).GetValue('assetId').Value);
  finally Root.Free; end;
  Data := TMusicStudioLayerStepData.Create; try Data.LoadJSON(ConfigJSON); Result := Data.AssetID; finally Data.Free; end;
end;
function MusicStudioMergeLayerStepConfig(const BaseConfig,StepConfig: string): string;
var Base,Step,Visibility: TJSONObject; Pair: TJSONPair;
begin
  Base := ObjectJSON(BaseConfig); Step := ObjectJSON(StepConfig);
  try
    Visibility := Base.GetValue('visibility') as TJSONObject;
    if Visibility=nil then begin Visibility := TJSONObject.Create; Base.AddPair('visibility',Visibility); end;
    if Step.GetValue('visibility') is TJSONObject then for Pair in TJSONObject(Step.GetValue('visibility')) do
      Put(Visibility,Pair.JsonString.Value,TJSONValue(Pair.JsonValue.Clone));
    Result := Base.ToJSON;
  finally Step.Free; Base.Free; end;
end;
end.
