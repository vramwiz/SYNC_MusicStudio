unit SYNC_MusicStudio_DrumData;

// PSDと独立したドラム編集モデル。拍を正本とし、未知の作品属性を保持する。
// 音声、ファイル、描画には依存しない。読込は候補の検証完了後だけ反映する。
interface
uses System.JSON, System.Generics.Collections;
type
  TDrumHitState = (dhUnchecked, dhPlayable, dhImpossible);
  TDrumHit = record
    Row: Integer;
    Beat: Double;
    State: TDrumHitState;
  end;
  TDrumBar = record
    Lane, Kind: Integer; // 0=表情、1=全体モーション
    StartBeat, EndBeat: Double;
  end;
  TMusicStudioDrumData = class
  private
    FRoot: TJSONObject;
    FBars, FSteps: Integer;
    FRows: TArray<string>;
    FHits: TList<TDrumHit>;
    FRanges: TList<TDrumBar>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Load(const Text: string);
    function JSON: string;
    function LengthBeats: Double;
    function Step: Double;
    procedure SetGrid(Bars, Steps: Integer);
    function HitAt(Row: Integer; Beat: Double): Integer;
    procedure Toggle(Row: Integer; Beat: Double);
    procedure SetHitState(Index: Integer; State: TDrumHitState);
    function PutBar(Index: Integer; const Value: TDrumBar): Boolean;
    procedure DeleteBar(Index: Integer);
    property Bars: Integer read FBars;
    property StepsPerBar: Integer read FSteps;
    property Rows: TArray<string> read FRows;
    property Hits: TList<TDrumHit> read FHits;
    property Ranges: TList<TDrumBar> read FRanges;
  end;
function MusicStudioHasDrums(const Text: string): Boolean;
function DrumKindName(Lane, Kind: Integer): string;
implementation
uses System.SysUtils, System.Math;

function MusicStudioHasDrums(const Text: string): Boolean;
var V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(Text);
  try Result := (V is TJSONObject) and (TJSONObject(V).GetValue('drumPattern')<>nil);
  finally V.Free; end;
end;
function DrumKindName(Lane, Kind: Integer): string;
const Faces: array[0..9] of string = ('なし','笑顔','真剣','怒り','悲しみ','驚き','目閉じ','ウインク','楽しげ','集中');
  Moves: array[0..9] of string = ('なし','上下動','左右揺れ','左傾き','右傾き','前後傾き','跳ねる','大きな揺れ','小刻みな揺れ','アクセント');
begin
  if (Kind<0) or (Kind>9) then Exit('不明');
  if Lane=0 then Result := Faces[Kind] else Result := Moves[Kind];
end;
constructor TMusicStudioDrumData.Create;
begin
  inherited;
  FRoot := TJSONObject.Create; FHits := TList<TDrumHit>.Create; FRanges := TList<TDrumBar>.Create;
  FBars := 1; FSteps := 16;
  FRows := ['スネア','ハイハット','ハイタム','ロータム','フロアタム','クラッシュ','ライド','バスドラム','スティック'];
end;
destructor TMusicStudioDrumData.Destroy;
begin FRanges.Free; FHits.Free; FRoot.Free; inherited; end;
function TMusicStudioDrumData.LengthBeats: Double;
begin Result := FBars*4; end;
function TMusicStudioDrumData.Step: Double;
begin Result := 4/FSteps; end;
procedure TMusicStudioDrumData.SetGrid(Bars, Steps: Integer);
var H: TDrumHit; B: TDrumBar;
begin
  if (Bars<1) or (Bars>64) or not (Steps in [4,8,12,16,24,32,48,64]) then
    raise Exception.Create('小節数は1～64、分割数は4/8/12/16/24/32/48/64です。');
  for H in FHits do if H.Beat>=Bars*4 then raise Exception.Create('末尾に打点があるため短縮できません。');
  for B in FRanges do if B.EndBeat>Bars*4 then raise Exception.Create('末尾にバーがあるため短縮できません。');
  FBars := Bars; FSteps := Steps;
end;
function TMusicStudioDrumData.HitAt(Row: Integer; Beat: Double): Integer;
var I: Integer;
begin
  for I := 0 to FHits.Count-1 do
    if (FHits[I].Row=Row) and (Abs(FHits[I].Beat-Beat)<1E-8) then Exit(I);
  Result := -1;
end;
procedure TMusicStudioDrumData.Toggle(Row: Integer; Beat: Double);
var I: Integer; H: TDrumHit;
begin
  if (Row<0) or (Row>=Length(FRows)) or IsNan(Beat) or IsInfinite(Beat) or (Beat<0) or (Beat>=LengthBeats) then
    raise Exception.Create('打点の位置が範囲外です。');
  I := HitAt(Row,Beat);
  if I>=0 then FHits.Delete(I)
  else begin
    if FHits.Count>=32768 then raise Exception.Create('打点数の上限32768を超えています。');
    H.Row := Row; H.Beat := Beat; H.State := dhUnchecked; FHits.Add(H);
  end;
end;
procedure TMusicStudioDrumData.SetHitState(Index: Integer; State: TDrumHitState);
var H: TDrumHit;
begin H := FHits[Index]; H.State := State; FHits[Index] := H; end;
function TMusicStudioDrumData.PutBar(Index: Integer; const Value: TDrumBar): Boolean;
var I: Integer; B: TDrumBar;
begin
  Result := False;
  if (Index < -1) or (Index>=FRanges.Count) or not (Value.Lane in [0,1]) or
    (Value.Kind<0) or (Value.Kind>9) or IsNan(Value.StartBeat) or IsInfinite(Value.StartBeat) or
    IsNan(Value.EndBeat) or IsInfinite(Value.EndBeat) or (Value.StartBeat<0) or
    (Value.EndBeat>LengthBeats) or (Value.EndBeat-Value.StartBeat<1E-8) then Exit;
  for I := 0 to FRanges.Count-1 do if I<>Index then begin
    B := FRanges[I];
    if (B.Lane=Value.Lane) and (Value.StartBeat<B.EndBeat-1E-8) and (Value.EndBeat>B.StartBeat+1E-8) then Exit;
  end;
  if Index<0 then begin if FRanges.Count>=8192 then Exit; FRanges.Add(Value); end else FRanges[Index] := Value;
  Result := True;
end;
procedure TMusicStudioDrumData.DeleteBar(Index: Integer);
begin if (Index>=0) and (Index<FRanges.Count) then FRanges.Delete(Index); end;

procedure TMusicStudioDrumData.Load(const Text: string);
var Candidate: TMusicStudioDrumData; V,Item: TJSONValue; O,D: TJSONObject;
  H: TDrumHit; B: TDrumBar; N: Integer;
  function Number(const Obj: TJSONObject; const Key: string): Double;
  var J: TJSONValue;
  begin
    J := Obj.GetValue(Key);
    if not (J is TJSONNumber) then raise Exception.Create('ドラムデータの数値が不正: '+Key);
    Result := TJSONNumber(J).AsDouble;
    if IsNan(Result) or IsInfinite(Result) then raise Exception.Create('ドラムデータの数値が有限ではありません。');
  end;
  function Int(const Obj: TJSONObject; const Key: string; Lo,Hi: Integer): Integer;
  var X: Double;
  begin
    X := Number(Obj,Key);
    if (X<Lo) or (X>Hi) or (Frac(X)<>0) then raise Exception.Create('ドラムデータの整数が範囲外: '+Key);
    Result := Trunc(X);
  end;
  function Items(const Key: string): TJSONArray;
  begin
    if not (D.GetValue(Key) is TJSONArray) then raise Exception.Create('ドラムデータの配列が不正: '+Key);
    Result := TJSONArray(D.GetValue(Key));
  end;
begin
  V := TJSONObject.ParseJSONValue(Text);
  if not (V is TJSONObject) then begin V.Free; raise Exception.Create('ドラム演奏JSONが不正です。'); end;
  Candidate := TMusicStudioDrumData.Create;
  try
    D := TJSONObject(V).GetValue<TJSONObject>('drumPattern');
    if D=nil then raise Exception.Create('drumPatternがありません。');
    if Int(D,'version',1,1)<>1 then raise Exception.Create('未対応のドラム版です。');
    Candidate.SetGrid(Int(D,'bars',1,64),Int(D,'stepsPerBar',4,64));
    if Abs(Number(TJSONObject(V),'lengthBeats')-Candidate.LengthBeats)>1E-8 then
      raise Exception.Create('ドラムの小節数と演奏長が一致しません。');
    if (Items('rows').Count<1) or (Items('rows').Count>32) then raise Exception.Create('打撃対象は1～32行です。');
    SetLength(Candidate.FRows,Items('rows').Count); N := 0;
    for Item in Items('rows') do begin
      if not (Item is TJSONString) or (Trim(Item.Value)='') then raise Exception.Create('打撃対象名が不正です。');
      Candidate.FRows[N] := Item.Value; Inc(N);
    end;
    if Items('hits').Count>32768 then raise Exception.Create('打点数の上限を超えています。');
    for Item in Items('hits') do begin
      if not (Item is TJSONObject) then raise Exception.Create('打点が不正です。'); O := TJSONObject(Item);
      H.Row := Int(O,'row',0,High(Candidate.FRows)); H.Beat := Number(O,'beat');
      H.State := TDrumHitState(Int(O,'state',0,2));
      if Candidate.HitAt(H.Row,H.Beat)>=0 then raise Exception.Create('打点が重複しています。');
      Candidate.Toggle(H.Row,H.Beat); Candidate.SetHitState(Candidate.FHits.Count-1,H.State);
    end;
    if Items('ranges').Count>8192 then raise Exception.Create('バー数の上限を超えています。');
    for Item in Items('ranges') do begin
      if not (Item is TJSONObject) then raise Exception.Create('バーが不正です。'); O := TJSONObject(Item);
      B.Lane := Int(O,'lane',0,1); B.Kind := Int(O,'kind',0,9);
      B.StartBeat := Number(O,'startBeat'); B.EndBeat := Number(O,'endBeat');
      if not Candidate.PutBar(-1,B) then raise Exception.Create('バーの範囲・重複が不正です。');
    end;
    FRoot.Free; FRoot := TJSONObject(V); V := nil;
    FBars := Candidate.FBars; FSteps := Candidate.FSteps; FRows := Candidate.FRows;
    FHits.Clear; FHits.AddRange(Candidate.FHits); FRanges.Clear; FRanges.AddRange(Candidate.FRanges);
  finally Candidate.Free; V.Free; end;
end;
function TMusicStudioDrumData.JSON: string;
var Root,D,O: TJSONObject; A: TJSONArray; Notes: TJSONValue; S: string; H: TDrumHit; B: TDrumBar;
  procedure Replace(Obj: TJSONObject; const Key: string; Value: TJSONValue);
  begin Obj.RemovePair(Key).Free; Obj.AddPair(Key,Value); end;
begin
  Root := FRoot.Clone as TJSONObject;
  try
    if Root.GetValue('notes')<>nil then Notes := Root.GetValue('notes').Clone as TJSONValue
    else Notes := TJSONArray.Create;
    if Root.GetValue('drumPattern') is TJSONObject then D := Root.GetValue('drumPattern').Clone as TJSONObject
    else D := TJSONObject.Create;
    // 既知項目の順序を一定にし、読込後もJSON履歴の完全一致を維持する。
    Root.RemovePair('lengthBeats').Free; Root.RemovePair('notes').Free; Root.RemovePair('drumPattern').Free;
    Root.AddPair('lengthBeats',TJSONNumber.Create(LengthBeats)); Root.AddPair('notes',Notes); Root.AddPair('drumPattern',D);
    Replace(D,'version',TJSONNumber.Create(1)); Replace(D,'bars',TJSONNumber.Create(FBars));
    Replace(D,'stepsPerBar',TJSONNumber.Create(FSteps));
    A := TJSONArray.Create; Replace(D,'rows',A); for S in FRows do A.Add(S);
    A := TJSONArray.Create; Replace(D,'hits',A);
    for H in FHits do begin
      O := TJSONObject.Create; O.AddPair('row',TJSONNumber.Create(H.Row));
      O.AddPair('beat',TJSONNumber.Create(H.Beat)); O.AddPair('state',TJSONNumber.Create(Ord(H.State))); A.AddElement(O);
    end;
    A := TJSONArray.Create; Replace(D,'ranges',A);
    for B in FRanges do begin
      O := TJSONObject.Create; O.AddPair('lane',TJSONNumber.Create(B.Lane)); O.AddPair('kind',TJSONNumber.Create(B.Kind));
      O.AddPair('startBeat',TJSONNumber.Create(B.StartBeat)); O.AddPair('endBeat',TJSONNumber.Create(B.EndBeat)); A.AddElement(O);
    end;
    Result := Root.ToJSON;
  finally Root.Free; end;
end;
end.
