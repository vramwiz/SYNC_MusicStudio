unit SYNC_MusicStudio_ClipTempo;

// Instance-local BPM corrections in source quarter beats; MIDI and patterns stay intact.
interface
uses System.JSON, SYNC_MusicStudio_BeatData;
procedure ValidateMusicStudioTempoOverrides(Value: TJSONValue);
function MusicStudioClipTempo(Base: TMusicStudioTempoMap; Clip: TJSONObject): TMusicStudioTempoMap;
procedure SetMusicStudioClipBPM(Clip: TJSONObject; Beat,BPM: Double);
implementation
uses System.SysUtils, System.Math, System.Generics.Collections;
procedure Put(O: TJSONObject; const K: string; V: TJSONValue);
begin O.RemovePair(K).Free; O.AddPair(K,V); end;
procedure ValidateMusicStudioTempoOverrides(Value: TJSONValue);
var V: TJSONValue; O: TJSONObject; Beat,BPM: Double; Seen: TDictionary<Double,Boolean>;
begin
  if Value=nil then Exit;
  if not (Value is TJSONArray) or (TJSONArray(Value).Count>1024) then raise EArgumentException.Create('tempoOverrides must be an array of at most 1024 points');
  Seen := TDictionary<Double,Boolean>.Create;
  try for V in TJSONArray(Value) do begin
    if not (V is TJSONObject) then raise EArgumentException.Create('Invalid tempo override'); O := TJSONObject(V);
    if not (O.GetValue('beat') is TJSONNumber) or not (O.GetValue('bpm') is TJSONNumber) then raise EArgumentException.Create('Tempo override needs beat and bpm');
    Beat := TJSONNumber(O.GetValue('beat')).AsDouble; BPM := TJSONNumber(O.GetValue('bpm')).AsDouble;
    if IsNan(Beat) or IsInfinite(Beat) or (Beat<0) or (Beat>1000000) or IsNan(BPM) or IsInfinite(BPM) or (BPM<1) or (BPM>999.99) then
      raise EArgumentException.Create('Tempo override beat/BPM is out of range');
    if Seen.ContainsKey(Beat) then raise EArgumentException.Create('Duplicate tempo override beat'); Seen.Add(Beat,True);
  end; finally Seen.Free; end;
end;
function MusicStudioClipTempo(Base: TMusicStudioTempoMap; Clip: TJSONObject): TMusicStudioTempoMap;
var V: TJSONValue; O: TJSONObject;
begin
  ValidateMusicStudioTempoOverrides(Clip.GetValue('tempoOverrides')); Result := TMusicStudioTempoMap.Create;
  try Result.LoadJSON(Base.TimingJSON);
    if Clip.GetValue('tempoOverrides') is TJSONArray then for V in TJSONArray(Clip.GetValue('tempoOverrides')) do begin
      O := TJSONObject(V); Result.SetBPMAt(TJSONNumber(O.GetValue('beat')).AsDouble,TJSONNumber(O.GetValue('bpm')).AsDouble);
    end;
  except Result.Free; raise; end;
end;
procedure SetMusicStudioClipBPM(Clip: TJSONObject; Beat,BPM: Double);
var A: TJSONArray; V: TJSONValue; O: TJSONObject;
begin
  ValidateMusicStudioTempoOverrides(Clip.GetValue('tempoOverrides')); A := Clip.GetValue('tempoOverrides') as TJSONArray;
  if A=nil then begin A := TJSONArray.Create; Clip.AddPair('tempoOverrides',A); end;
  for V in A do begin O := TJSONObject(V); if TJSONNumber(O.GetValue('beat')).AsDouble=Beat then begin Put(O,'bpm',TJSONNumber.Create(BPM)); Exit; end; end;
  if A.Count>=1024 then raise EArgumentException.Create('Too many tempo corrections');
  O := TJSONObject.Create; O.AddPair('beat',TJSONNumber.Create(Beat)); O.AddPair('bpm',TJSONNumber.Create(BPM)); A.AddElement(O);
end;
end.
