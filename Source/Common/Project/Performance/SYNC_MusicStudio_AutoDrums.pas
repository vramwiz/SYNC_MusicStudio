unit SYNC_MusicStudio_AutoDrums;

// 波形包絡線と作品の拍子から、編集可能な手足区間を生成する。
// 音源の読込・作品への書込は呼出側が担当する。
interface
uses SYNC_MusicStudio_AudioWaveform, SYNC_MusicStudio_BeatData,
  SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentData;
procedure GenerateMusicStudioDrums(Data: TMusicStudioInstrumentData;
  Rules: TMusicStudioInstrumentRules; Timing: TMusicStudioTempoMap;
  const Wave: TMusicStudioWaveform; SourceDuration, ClipStart, ClipLength: Double);
implementation
uses System.SysUtils, System.Math;

procedure GenerateMusicStudioDrums(Data: TMusicStudioInstrumentData;
  Rules: TMusicStudioInstrumentRules; Timing: TMusicStudioTempoMap;
  const Wave: TMusicStudioWaveform; SourceDuration, ClipStart, ClipLength: Double);
var Origin, Last, Beat, BarStart, BarEnd, Step, Peak, Sum, Quiet, Accent, Offbeat: Double;
  FirstBar, Bar, Pulse, Pulses, I: Integer;
  Kick, Snare, Hat, Crash, Tom: string;
  function Choice(const Row: string; const Names: array of string): string;
  var Name: string;
  begin
    for Name in Names do if Rules.HasChoice(Row,Name) then Exit(Name);
    Result := '';
  end;
  function PeakAt(Position: Double): Double;
  var Seconds, BinsPerSecond: Double; First, Finish, Index: Integer;
  begin
    Result := 0;
    Seconds := Timing.BeatToSeconds(Position)-ClipStart;
    if (Seconds< -1E-8) or (Seconds>=Min(ClipLength,SourceDuration)) then Exit;
    BinsPerSecond := Length(Wave)/SourceDuration;
    First := EnsureRange(Floor((Seconds-0.025)*BinsPerSecond),0,High(Wave));
    Finish := EnsureRange(Floor((Seconds+0.045)*BinsPerSecond),First,High(Wave));
    for Index := First to Finish do Result := Max(Result,Max(Abs(Wave[Index].Minimum),Abs(Wave[Index].Maximum)));
  end;
  procedure Hit(const Row, Name: string; AtBeat, Duration: Double);
  var B: TInstrumentBlock;
  begin
    if (Name='') or (AtBeat<Origin-1E-8) or (AtBeat>=Last) then Exit;
    B := Default(TInstrumentBlock);
    B.Row := Row; B.Choice := Name; B.Stage := 1;
    B.ID := 'auto-'+IntToStr(Data.Blocks.Count+1);
    B.StartBeat := Max(0.0,AtBeat-Origin);
    B.EndBeat := Min(Last-Origin,B.StartBeat+Duration);
    if B.EndBeat-B.StartBeat<1E-8 then Exit;
    if not Data.PutBlock(-1,B) then raise Exception.Create('おまかせ演奏の区間数が上限を超えました。音声配置を短くしてください。');
  end;
begin
  if (Length(Wave)=0) or (SourceDuration<=0) or (ClipLength<=0) then
    raise Exception.Create('解析済みの音声波形がありません。');
  Origin := Timing.SecondsToBeat(ClipStart);
  Last := Timing.SecondsToBeat(ClipStart+Min(SourceDuration,ClipLength));
  if (Last-Origin<0.001) or (Last>1000000) then raise Exception.Create('音声配置の拍範囲が不正です。');
  Kick := Choice('右足',['バスドラム','バスドラム（高速）','バスドラム（保持）']);
  Snare := Choice('右手',['スネア中央','スネア中央（エフェクト付き）','スネア右側']);
  Hat := Choice('左手',['ハイハット閉','ハイハット閉（エフェクト付き）','ハイハット開']);
  Crash := Choice('右手',['クラッシュ（エフェクト付き）','クラッシュ']);
  Tom := Choice('右手',['小タム','小タム（エフェクト付き）']);
  if (Kick='') or (Snare='') or (Hat='') then
    raise Exception.Create('PSDにバスドラム・スネア・ハイハットの差分が必要です。');
  Sum := 0;
  for I := 0 to High(Wave) do Sum := Sum+Max(Abs(Wave[I].Minimum),Abs(Wave[I].Maximum));
  Sum := Sum/Length(Wave);
  Quiet := Max(0.006,Sum*0.16); Accent := Max(0.04,Sum*1.25);
  Data.SetLength(Last-Origin); Data.PackedBlocks := True;
  FirstBar := Timing.MeasureAtBeat(Origin); Bar := FirstBar;
  BarStart := Timing.MeasureStart(Bar);
  while BarStart<Last do begin
    BarEnd := Timing.MeasureStart(Bar+1);
    Step := 4.0/Timing.DenominatorAtBeat(BarStart);
    Pulses := Round((BarEnd-BarStart)/Step);
    for Pulse := 0 to Pulses-1 do begin
      Beat := BarStart+Pulse*Step;
      if (Beat<Origin-1E-8) or (Beat>=Last) then Continue;
      Peak := PeakAt(Beat); if Peak<Quiet then Continue;
      Hit('左手',Hat,Beat,Step*0.42);
      Offbeat := Beat+Step/2;
      if (Peak>=Sum*0.65) and (PeakAt(Offbeat)>=Quiet) then Hit('左手',Hat,Offbeat,Step*0.40);
      if (Pulse=0) or ((Pulse mod 2=0) and (Peak>=Sum*0.6)) then Hit('右足',Kick,Beat,Step*0.68);
      if (Pulse=0) and ((Bar-FirstBar) mod 4=0) and (Peak>=Accent) and (Crash<>'') then
        Hit('右手',Crash,Beat,Step*0.82)
      else if (Pulse=Pulses-1) and ((Bar-FirstBar) mod 4=3) and (Peak>=Accent) and (Tom<>'') then
        Hit('右手',Tom,Beat,Step*0.68)
      else if Pulse mod 2=1 then Hit('右手',Snare,Beat,Step*0.68);
    end;
    Inc(Bar); BarStart := BarEnd;
  end;
  if Data.Blocks.Count=0 then raise Exception.Create('演奏を作れる音のある区間が見つかりません。');
end;
end.
