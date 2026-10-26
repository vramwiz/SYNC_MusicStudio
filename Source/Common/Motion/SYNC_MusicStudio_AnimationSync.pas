unit SYNC_MusicStudio_AnimationSync;
// Immutable onset/end cues. No file reads, audio, UI or playback clock state.
interface
type
  TMusicStudioAnimationCue = record
    StartValue, EndValue: Double;
  end;
// 呼出元所有の値配列を開始/終了順へ並べ替える。時刻の単位は全要素で秒または拍へ統一する。
procedure SortMusicStudioAnimationCues(var Cues: TArray<TMusicStudioAnimationCue>);
// 整列済み配列と同単位の位置を受け、発音中の位相0..1を返す。休符はFalseで、再生履歴を持たない。
// 重なりは新しい開始を優先する。Cuesと元作品は変更しない。
function MusicStudioAnimationPhase(const Cues: TArray<TMusicStudioAnimationCue>;
  Position: Double; out Phase: Double): Boolean;
implementation
uses System.Math, System.Generics.Collections, System.Generics.Defaults;
procedure SortMusicStudioAnimationCues(var Cues: TArray<TMusicStudioAnimationCue>);
begin
  TArray.Sort<TMusicStudioAnimationCue>(Cues,TComparer<TMusicStudioAnimationCue>.Construct(
    function(const A,B: TMusicStudioAnimationCue): Integer
    begin
      if A.StartValue<B.StartValue then Exit(-1);
      if A.StartValue>B.StartValue then Exit(1);
      if A.EndValue<B.EndValue then Exit(-1);
      if A.EndValue>B.EndValue then Exit(1);
      Result := 0;
    end));
end;
function MusicStudioAnimationPhase(const Cues: TArray<TMusicStudioAnimationCue>;
  Position: Double; out Phase: Double): Boolean;
var L,R,M,I: Integer; EndValue: Double;
begin
  Phase := 0; Result := False; L := 0; R := Length(Cues);
  while L<R do begin M := L+(R-L) div 2;
    if Cues[M].StartValue<=Position then L := M+1 else R := M;
  end;
  for I := L-1 downto 0 do if Cues[I].EndValue>Position then begin
    EndValue := Cues[I].EndValue;
    if EndValue<=Cues[I].StartValue then Continue;
    Phase := EnsureRange((Position-Cues[I].StartValue)/(EndValue-Cues[I].StartValue),0.0,1.0);
    Exit(True);
  end;
end;
end.
