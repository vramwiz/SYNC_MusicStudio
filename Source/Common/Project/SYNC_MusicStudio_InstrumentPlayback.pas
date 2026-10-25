unit SYNC_MusicStudio_InstrumentPlayback;

// 両手両足の準備/打撃/余韻と最後の姿勢を、再生履歴に依存せず拍から評価する。
// 入力は借用する値コピー。PSD/区間JSONを変更せず、seekでも同じ姿勢を返す。
interface
uses SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentRules;
type
  TInstrumentPlaybackRange = record
    Blocks: TArray<TInstrumentBlock>;
    StartBeat,EndBeat: Double;
  end;
function MusicStudioActionRow(const Name: string): Boolean;
function MusicStudioInstrumentActionStates(const Ranges: TArray<TInstrumentPlaybackRange>;
  Rules: TMusicStudioInstrumentRules; Beat: Double): TArray<TInstrumentState>;
function MusicStudioInstrumentPlaybackStates(const Blocks: TArray<TInstrumentBlock>;
  Rules: TMusicStudioInstrumentRules; Beat: Double): TArray<TInstrumentState>;
implementation
uses System.Math, SYNC_MusicStudio_BeatData;
function MusicStudioActionRow(const Name: string): Boolean;
var Row: string;
begin for Row in INSTRUMENT_ACTION_ROWS do if Name=Row then Exit(True); Result := False; end;
function MusicStudioInstrumentActionStates(const Ranges: TArray<TInstrumentPlaybackRange>;
  Rules: TMusicStudioInstrumentRules; Beat: Double): TArray<TInstrumentState>;
var Last,LastResonance: array[0..3] of TInstrumentBlock; Starts,Ends,Hits: array[0..3] of Double;
  Found,Resonating: array[0..3] of Boolean; Range: TInstrumentPlaybackRange; B: TInstrumentBlock;
  I,J,Value,Prepare,Strike,Rest,Stage: Integer; Start,Finish,Progress,Hit,Elapsed: Double;
  Values,Decay: TArray<Integer>; S: TInstrumentState;
begin
  Result := nil; if Rules=nil then Exit;
  for I := 0 to 3 do begin Found[I] := False; Resonating[I] := False; end;
  for Range in Ranges do for B in Range.Blocks do begin
    Start := Range.StartBeat+B.StartBeat; Finish := Min(Range.EndBeat,Range.StartBeat+B.EndBeat);
    if (MusicStudioComparePositions(Beat,Start)<0) or (Finish<=Start) or not Rules.HasChoice(B.Row,B.Choice) then Continue;
    for I := 0 to 3 do if B.Row=INSTRUMENT_ACTION_ROWS[I] then begin
      if not Found[I] or (MusicStudioComparePositions(Start,Starts[I])>=0) then begin
        Found[I] := True; Last[I] := B; Starts[I] := Start; Ends[I] := Finish;
      end;
      // 腕の次候補/配置の終端に依存せず、実際に打撃へ到達した最後の機材を評価する。
      Hit := Start+(B.EndBeat-B.StartBeat)*0.25;
      if Rules.HasResonanceChoice(B.Row,B.Choice) and
        (MusicStudioComparePositions(Hit,Finish)<0) and (MusicStudioComparePositions(Beat,Hit)>=0) and
        (not Resonating[I] or (MusicStudioComparePositions(Hit,Hits[I])>=0)) then begin
        Resonating[I] := True; Hits[I] := Hit; LastResonance[I] := B;
      end;
    end;
  end;
  for I := 0 to 3 do if Found[I] then begin
    B := Last[I]; Values := Rules.Stages(B.Row,B.Choice); if Length(Values)=0 then Continue;
    Prepare := Values[0];
    for Value in Values do if Value=0 then Prepare := 0;
    Strike := Prepare; Rest := Prepare;
    for Value in Values do begin if Value=1 then Strike := 1; if Value=2 then Rest := 2; end;
    Stage := Rest;
    if MusicStudioComparePositions(Beat,Ends[I])<0 then begin
      // 先頭25%が準備、次50%が打撃、最後25%が余韻。打撃時間を従来の2倍にする。
      Progress := B.EndBeat-B.StartBeat;
      if MusicStudioComparePositions(Beat,Starts[I]+Progress*0.25)<0 then Stage := Prepare
      else if MusicStudioComparePositions(Beat,Starts[I]+Progress*0.75)<0 then Stage := Strike;
    end;
    S := Default(TInstrumentState); S.Row := B.Row; S.Choice := B.Choice; S.Stage := Stage;
    if Rules.HasResonanceRow(B.Row) or Rules.HasEffectRow(B.Row) then S.LayerScope := 'body';
    Result := Result+[S];
    if Rules.HasEffectRow(B.Row) then begin
      S.Stage := -1; S.LayerScope := 'effect';
      if MusicStudioComparePositions(Beat,Ends[I])<0 then begin
        Values := Rules.EffectStages(B.Row,B.Choice); Progress := B.EndBeat-B.StartBeat;
        if MusicStudioComparePositions(Beat,Starts[I]+Progress*0.25)<0 then begin
          for Value in Values do if Value=0 then S.Stage := 0;
        end else if MusicStudioComparePositions(Beat,Starts[I]+Progress*0.75)<0 then begin
          for Value in Values do if Value=1 then S.Stage := 1;
        end else begin
          Decay := nil; for Value in Values do if Value>=2 then Decay := Decay+[Value];
          if Length(Decay)>0 then begin
            J := 0;
            while (J<Length(Decay)-1) and
              (MusicStudioComparePositions(Beat,Starts[I]+Progress*(0.75+0.25*(J+1)/Length(Decay)))>=0) do Inc(J);
            S.Stage := Decay[J];
          end;
        end;
      end;
      Result := Result+[S];
    end;
  end;
  for I := 0 to 3 do if Resonating[I] then begin
    B := LastResonance[I]; Values := Rules.ResonanceStages(B.Row,B.Choice); Decay := nil; Strike := -1;
    for Value in Values do if Value>=2 then Decay := Decay+[Value] else if Value=1 then Strike := 1;
    if (Strike<0) or (Length(Decay)=0) then Continue;
    Elapsed := Max(0.0,Beat-Hits[I]); Stage := Strike;
    if MusicStudioComparePositions(Elapsed,0.20)>=0 then begin
      J := 0;
      while (J<Length(Decay)-1) and (MusicStudioComparePositions(Elapsed,0.20+(J+1)*0.20)>=0) do Inc(J);
      Stage := Decay[J];
    end;
    S := Default(TInstrumentState); S.Row := B.Row; S.Choice := B.Choice;
    S.Stage := Stage; S.LayerScope := 'resonance'; Result := Result+[S];
  end;
end;
function MusicStudioInstrumentPlaybackStates(const Blocks: TArray<TInstrumentBlock>;
  Rules: TMusicStudioInstrumentRules; Beat: Double): TArray<TInstrumentState>;
var B: TInstrumentBlock; S: TInstrumentState; Range: TInstrumentPlaybackRange;
begin
  Result := nil;
  for B in Blocks do if not MusicStudioActionRow(B.Row) and
    (MusicStudioComparePositions(Beat,B.StartBeat)>=0) and (MusicStudioComparePositions(Beat,B.EndBeat)<0) then begin
      S := Default(TInstrumentState); S.Row := B.Row; S.Choice := B.Choice; S.Stage := B.Stage; Result := Result+[S];
    end;
  Range.Blocks := Blocks; Range.StartBeat := 0; Range.EndBeat := MaxDouble;
  Result := Result+MusicStudioInstrumentActionStates([Range],Rules,Beat);
end;
end.
