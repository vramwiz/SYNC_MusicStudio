unit SYNC_MusicStudio_TempoPatternData;

// 参照ファイルから取得済みのtempo snapshot。曲の手動tempoとclipの優先合成もファイルI/Oなしで行う。
interface
uses System.JSON, SYNC_MusicStudio_BeatData;
type
  TMusicStudioTempoPatternData = class
  private
    FOriginal: TJSONObject;
    FTiming: TMusicStudioTempoMap;
    FFilePath: string;
    FLengthBeats: Double;
    procedure SetLengthBeats(Value: Double);
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadJSON(const ConfigJSON: string);
    procedure ImportSnapshot(const Path,TimingJSON: string; LengthBeats: Double);
    function ConfigJSON: string;
    property Timing: TMusicStudioTempoMap read FTiming;
    property FilePath: string read FFilePath;
    property LengthBeats: Double read FLengthBeats write SetLengthBeats;
  end;
// 結果の所有権は呼出側。手動Root.timingは変更しない。tempo clipが有効区間だけ優先する。
function BuildMusicStudioEffectiveTempo(Root: TJSONObject): TMusicStudioTempoMap;
procedure SetMusicStudioTempoAtBeat(Root: TJSONObject; Beat,BPM: Double; out Scope: string);
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, System.Generics.Defaults, SYNC_MusicStudio_ClipTempo;
type TTempoClip = class
    StartBeat,LengthBeats: Double;
    Order: Integer;
    Pattern: TMusicStudioTempoPatternData; // 共有snapshotを借用。
    Timing: TMusicStudioTempoMap;
    OwnTiming: Boolean;
    destructor Destroy; override;
  end;
destructor TTempoClip.Destroy;
begin if OwnTiming then Timing.Free; inherited; end;
function ClipPointIndex(Map: TMusicStudioTempoMap; Start,Beat: Double): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 1 to Map.PointCount-1 do begin
    if MusicStudioComparePositions(Start+Map.TempoPoint(I).Beat,Beat)>0 then Break;
    Result := I;
  end;
end;
procedure Put(Obj: TJSONObject; const Key: string; Value: TJSONValue);
begin Obj.RemovePair(Key).Free; Obj.AddPair(Key,Value); end;
function RootJSON(const Text: string): TJSONObject;
var V: TJSONValue;
begin
  if Text.Trim='' then Exit(TJSONObject.Create);
  V := TJSONObject.ParseJSONValue(Text); if not (V is TJSONObject) then begin V.Free; raise EArgumentException.Create('tempoはJSONオブジェクトで指定してください。'); end;
  Result := TJSONObject(V);
end;
constructor TMusicStudioTempoPatternData.Create;
begin inherited; FOriginal := TJSONObject.Create; FTiming := TMusicStudioTempoMap.Create; FLengthBeats := 16; end;
destructor TMusicStudioTempoPatternData.Destroy;
begin FTiming.Free; FOriginal.Free; inherited; end;
procedure TMusicStudioTempoPatternData.SetLengthBeats(Value: Double);
begin
  if IsNan(Value) or IsInfinite(Value) or (Value<1/64) or (Value>1000000) or
    (FTiming.TempoPoint(FTiming.PointCount-1).Beat>=Value) then raise EArgumentException.Create('tempoパターン長は最後のtempo点より後、1/64～1000000拍で指定してください。');
  FLengthBeats := Value;
end;
procedure TMusicStudioTempoPatternData.LoadJSON(const ConfigJSON: string);
var Obj: TJSONObject; Candidate: TMusicStudioTempoMap; Length: Double; Path: string;
begin
  Obj := RootJSON(ConfigJSON); Candidate := TMusicStudioTempoMap.Create;
  try
    if Assigned(Obj.GetValue('filePath')) and not (Obj.GetValue('filePath') is TJSONString) then raise EArgumentException.Create('tempo.filePathは文字列で指定してください。');
    if Assigned(Obj.GetValue('timing')) and not (Obj.GetValue('timing') is TJSONObject) then raise EArgumentException.Create('tempo.timingはオブジェクトで指定してください。');
    Candidate.LoadJSON(Obj.GetValue('timing') as TJSONObject); Length := 16; Path := '';
    if Obj.GetValue('filePath') is TJSONString then Path := Obj.GetValue('filePath').Value;
    if Assigned(Obj.GetValue('lengthBeats')) then begin
      if not (Obj.GetValue('lengthBeats') is TJSONNumber) then raise EArgumentException.Create('tempo.lengthBeatsは数値で指定してください。');
      Length := TJSONNumber(Obj.GetValue('lengthBeats')).AsDouble;
    end;
    if IsNan(Length) or IsInfinite(Length) or (Length<1/64) or (Length>1000000) or
      (Candidate.TempoPoint(Candidate.PointCount-1).Beat>=Length) then raise EArgumentException.Create('tempoパターンの長さが不正です。');
    FTiming.Free; FTiming := Candidate; Candidate := nil; FOriginal.Free; FOriginal := TJSONObject(Obj.Clone);
    FLengthBeats := Length; FFilePath := Path;
  finally Candidate.Free; Obj.Free; end;
end;
procedure TMusicStudioTempoPatternData.ImportSnapshot(const Path,TimingJSON: string; LengthBeats: Double);
var Obj: TJSONObject;
begin
  Obj := TJSONObject(FOriginal.Clone);
  try
    Put(Obj,'filePath',TJSONString.Create(Path)); Put(Obj,'lengthBeats',TJSONNumber.Create(LengthBeats));
    Put(Obj,'timing',TJSONObject.ParseJSONValue(TimingJSON)); LoadJSON(Obj.ToJSON);
  finally Obj.Free; end;
end;
function TMusicStudioTempoPatternData.ConfigJSON: string;
var Obj: TJSONObject;
begin
  Obj := TJSONObject(FOriginal.Clone);
  try Put(Obj,'filePath',TJSONString.Create(FFilePath)); Put(Obj,'lengthBeats',TJSONNumber.Create(FLengthBeats));
    Put(Obj,'timing',TJSONObject.ParseJSONValue(FTiming.TimingJSON)); Result := Obj.ToJSON;
  finally Obj.Free; end;
end;
function BuildMusicStudioEffectiveTempo(Root: TJSONObject): TMusicStudioTempoMap;
var Manual: TMusicStudioTempoMap; Patterns: TObjectDictionary<string,TMusicStudioTempoPatternData>;
  Clips: TObjectList<TTempoClip>; Beats: TList<Double>; V,TV,SV,CV: TJSONValue;
  Obj,CObj,OutRoot: TJSONObject; Data: TMusicStudioTempoPatternData; Clip,Selected: TTempoClip;
  Point: TMusicStudioTempoPoint; B,Previous,BPM,LastBPM: Double; I,Order: Integer; Points: TJSONArray;
begin
  Result := nil; Manual := TMusicStudioTempoMap.Create; Patterns := TObjectDictionary<string,TMusicStudioTempoPatternData>.Create([doOwnsValues]);
  Clips := TObjectList<TTempoClip>.Create(True); Beats := TList<Double>.Create; OutRoot := nil;
  try
    Manual.LoadJSON(Root.GetValue('timing') as TJSONObject);
    if Root.GetValue('patterns') is TJSONArray then for V in TJSONArray(Root.GetValue('patterns')) do begin
      Obj := V as TJSONObject; if Obj.GetValue('kind').Value<>'tempo' then Continue;
      Data := TMusicStudioTempoPatternData.Create;
      try Data.LoadJSON(Obj.GetValue('tempo').ToJSON); Patterns.Add(Obj.GetValue('id').Value,Data); Data := nil;
      finally Data.Free; end;
    end;
    for I := 0 to Manual.PointCount-1 do Beats.Add(Manual.TempoPoint(I).Beat); Order := 0;
    if Root.GetValue('tracks') is TJSONArray then for TV in TJSONArray(Root.GetValue('tracks')) do begin
      if not (TV is TJSONObject) or not (TJSONObject(TV).GetValue('slots') is TJSONArray) then Continue;
      for SV in TJSONArray(TJSONObject(TV).GetValue('slots')) do
        for CV in TJSONArray(TJSONObject(SV).GetValue('clips')) do begin
          CObj := TJSONObject(CV); Inc(Order);
          if not Patterns.TryGetValue(CObj.GetValue('patternId').Value,Data) then Continue;
          Clip := TTempoClip.Create; Clip.StartBeat := TJSONNumber(CObj.GetValue('startBeat')).AsDouble;
          Clip.LengthBeats := TJSONNumber(CObj.GetValue('lengthBeats')).AsDouble; Clip.Pattern := Data; Clip.Order := Order; Clips.Add(Clip);
          ValidateMusicStudioTempoOverrides(CObj.GetValue('tempoOverrides'));
          Clip.OwnTiming := (CObj.GetValue('tempoOverrides') is TJSONArray) and (TJSONArray(CObj.GetValue('tempoOverrides')).Count>0);
          if Clip.OwnTiming then Clip.Timing := MusicStudioClipTempo(Data.Timing,CObj) else Clip.Timing := Data.Timing;
          Beats.Add(Clip.StartBeat); Beats.Add(Clip.StartBeat+Clip.LengthBeats);
          for I := 0 to Clip.Timing.PointCount-1 do begin Point := Clip.Timing.TempoPoint(I);
            if Point.Beat<Clip.LengthBeats then Beats.Add(Clip.StartBeat+Point.Beat);
          end;
        end;
    end;
    if Clips.Count=0 then begin Result := TMusicStudioTempoMap.Create; Result.LoadJSON(Manual.TimingJSON); Exit; end;
    Beats.Sort; OutRoot := RootJSON(Manual.TimingJSON); Points := TJSONArray.Create; Put(OutRoot,'tempoPoints',Points);
    Previous := -1; LastBPM := -1;
    for B in Beats do begin
      if MusicStudioComparePositions(B,Previous)=0 then Continue; Previous := B; Selected := nil;
      for Clip in Clips do if (MusicStudioComparePositions(B,Clip.StartBeat)>=0) and (MusicStudioComparePositions(B,Clip.StartBeat+Clip.LengthBeats)<0) and
        ((Selected=nil) or (MusicStudioComparePositions(Clip.StartBeat,Selected.StartBeat)>0) or
        ((MusicStudioComparePositions(Clip.StartBeat,Selected.StartBeat)=0) and (Clip.Order>Selected.Order))) then Selected := Clip;
      BPM := Manual.BPMAt(B); if Selected<>nil then BPM := Selected.Timing.TempoPoint(ClipPointIndex(Selected.Timing,Selected.StartBeat,B)).BPM;
      if BPM=LastBPM then Continue; LastBPM := BPM;
      if Points.Count>=1024 then raise EArgumentException.Create('合成tempo点は1024個までです。');
      Obj := TJSONObject.Create; Obj.AddPair('beat',TJSONNumber.Create(B)); Obj.AddPair('bpm',TJSONNumber.Create(BPM)); Points.AddElement(Obj);
    end;
    Result := TMusicStudioTempoMap.Create;
    try Result.LoadJSON(OutRoot); except Result.Free; Result := nil; raise; end;
  finally OutRoot.Free; Beats.Free; Clips.Free; Patterns.Free; Manual.Free; end;
end;
procedure SetMusicStudioTempoAtBeat(Root: TJSONObject; Beat,BPM: Double; out Scope: string);
var T,S,C,P: TJSONValue; Clip,Selected,Pattern: TJSONObject; Start,Last: Double;
  Kinds: TDictionary<string,TJSONObject>; Data: TMusicStudioTempoPatternData; Map: TMusicStudioTempoMap; Point: TMusicStudioTempoPoint;
begin
  if IsNan(Beat) or IsInfinite(Beat) or (Beat<0) or (Beat>MUSICSTUDIO_MAX_QUERY_BEATS) or IsNan(BPM) or IsInfinite(BPM) or (BPM<1) or (BPM>999.99) then
    raise EArgumentException.Create('BPMは1～999.99、カーソルは有効なプレビュー範囲で指定してください。');
  Kinds := TDictionary<string,TJSONObject>.Create; Selected := nil; Last := -1;
  try
    if Root.GetValue('patterns') is TJSONArray then for P in TJSONArray(Root.GetValue('patterns')) do begin Pattern := TJSONObject(P);
      if Pattern.GetValue('kind').Value='tempo' then Kinds.Add(Pattern.GetValue('id').Value,Pattern);
    end;
    if Root.GetValue('tracks') is TJSONArray then for T in TJSONArray(Root.GetValue('tracks')) do begin
      if not (TJSONObject(T).GetValue('slots') is TJSONArray) then Continue;
      for S in TJSONArray(TJSONObject(T).GetValue('slots')) do for C in TJSONArray(TJSONObject(S).GetValue('clips')) do begin
        Clip := TJSONObject(C); if not Kinds.ContainsKey(Clip.GetValue('patternId').Value) then Continue;
        Start := TJSONNumber(Clip.GetValue('startBeat')).AsDouble;
        if (MusicStudioComparePositions(Beat,Start)>=0) and (MusicStudioComparePositions(Beat,Start+TJSONNumber(Clip.GetValue('lengthBeats')).AsDouble)<0) and
          (MusicStudioComparePositions(Start,Last)>=0) then begin Selected := Clip; Last := Start; end;
      end;
    end;
    if Selected=nil then begin
      Map := TMusicStudioTempoMap.Create;
      try Map.LoadJSON(Root.GetValue('timing') as TJSONObject); Point := Map.TempoPoint(Map.TempoPointIndexAtBeat(Beat));
        Map.SetBPMAt(Point.Beat,BPM); Put(Root,'timing',TJSONObject.ParseJSONValue(Map.TimingJSON)); Scope := '手動テンポ区間';
      finally Map.Free; end;
    end else begin
      Data := TMusicStudioTempoPatternData.Create;
      try Data.LoadJSON(Kinds[Selected.GetValue('patternId').Value].GetValue('tempo').ToJSON); Map := MusicStudioClipTempo(Data.Timing,Selected);
        try Point := Map.TempoPoint(ClipPointIndex(Map,Last,Beat)); SetMusicStudioClipBPM(Selected,Point.Beat,BPM);
          Scope := '配置したテンポクリップの区間';
        finally Map.Free; end;
      finally Data.Free; end;
    end;
  finally Kinds.Free; end;
end;
end.
