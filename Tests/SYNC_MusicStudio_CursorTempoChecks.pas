unit SYNC_MusicStudio_CursorTempoChecks;

interface
procedure RunCursorTempoChecks(const Root: string);
procedure RunCursorUpperChecks;
implementation
uses System.SysUtils, System.Classes, System.JSON, System.Math, System.IOUtils, System.Hash, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_TempoPatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_TimelineMetrics;
type TCursorRestoreFailure = class
    Form: TFormMusicStudioSettings; Original: TNotifyEvent; Fired: Boolean;
    procedure PositionChanged(Sender: TObject);
  end;
procedure TCursorRestoreFailure.PositionChanged(Sender: TObject);
begin
  if not Fired and (Form.Document.Timing.BPMAt(0)=60) then begin Fired := True; raise EInvalidOperation.Create('Injected cursor UI restore failure'); end;
  if Assigned(Original) then Original(Sender);
end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Cursor BPM: '+Message); end;
procedure Same(A,B: Double; const Message: string);
begin Check(Abs(A-B)<1E-7,Message+Format(' (%g/%g)',[A,B])); end;
function Text(D: TMusicStudioDocument): string;
var Error: string;
begin Check(D.TrySave(Result,Error),Error); end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; P: TPngImage; DC,MemoryDC: HDC; Origin: TPoint; OK: Boolean;
  Info: TBitmapInfo; Pixels: Pointer; Dib,Old: HGDIOBJ;
begin
  Writeln(Format('BPM_CAPTURE visible=%s client=%dx%d handle=%d',[BoolToStr(F.Visible,True),F.ClientWidth,F.ClientHeight,F.Handle]));
  Origin := F.ClientToScreen(Point(0,0)); SetWindowPos(F.Handle,0,F.Left-Origin.X,F.Top-Origin.Y,0,0,SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  F.Repaint; Application.ProcessMessages; B := TBitmap.Create; P := TPngImage.Create;
  try DC := GetDC(F.Handle); MemoryDC := CreateCompatibleDC(DC); FillChar(Info,SizeOf(Info),0);
    Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader); Info.bmiHeader.biWidth := F.ClientWidth;
    Info.bmiHeader.biHeight := -F.ClientHeight; Info.bmiHeader.biPlanes := 1; Info.bmiHeader.biBitCount := 32;
    Dib := CreateDIBSection(DC,Info,DIB_RGB_COLORS,Pixels,0,0); Check(Dib<>0,'capture DIB'); Old := SelectObject(MemoryDC,Dib);
    try OK := Winapi.Windows.BitBlt(MemoryDC,0,0,F.ClientWidth,F.ClientHeight,DC,0,0,SRCCOPY);
      if not OK then begin
        Writeln('BPM_NATIVE_BITBLT_UNAVAILABLE_'+IntToStr(GetLastError)+'_OWNED_WM_PRINT_FALLBACK');
        SendMessage(F.Handle,WM_PRINT,MemoryDC,PRF_CLIENT or PRF_CHILDREN or PRF_ERASEBKGND);
      end;
    finally SelectObject(MemoryDC,Old); DeleteDC(MemoryDC); ReleaseDC(F.Handle,DC); end;
    B.Handle := Dib;
    P.Assign(B); P.SaveToFile(Path);
  finally P.Free; B.Free; end;
end;
procedure Key(F: TFormMusicStudioSettings; K: Word; Ctrl: Boolean = False);
begin
  if Ctrl then begin F.UndoEdit; Exit; end;
  SendMessage(F.Preview.TempoEdit.Handle,WM_KEYDOWN,K,0); SendMessage(F.Preview.TempoEdit.Handle,WM_KEYUP,K,0);
end;
procedure SetInput(F: TFormMusicStudioSettings; const Value: string);
begin
  F.Preview.TempoEdit.SetFocus; Application.ProcessMessages; F.Preview.TempoEdit.Text := Value;
end;
procedure MeterChecks;
var M,N: TMusicStudioTempoMap; Old: string; Metrics: TMusicStudioTimelineMetrics; D: TMusicStudioDocument; Error,Scope: string;
begin
  M := TMusicStudioTempoMap.Create; N := TMusicStudioTempoMap.Create; D := TMusicStudioDocument.Create;
  try
    M.LoadJSON('{"meter":{"numerator":4,"denominator":4},"meterChanges":[{"measure":3,"numerator":3,"denominator":4,"tag":"keep"},{"measure":5,"numerator":7,"denominator":8}],"tempoPoints":[{"beat":0,"bpm":120},{"measure":4,"beatInMeasure":0.5,"bpm":90,"extra":"keep"},{"measure":6,"beatInMeasure":0,"bpm":75}]}');
    Same(M.TempoPoint(1).Beat,11.5,'3/4 measure anchor'); Same(M.TempoPoint(2).Beat,17.5,'7/8 measure anchor');
    Check(M.MeasureAtBeat(8)=3,'meter change exact boundary'); Check(M.MeasureAtBeat(17.5)=6,'later meter measure');
    Old := M.TimingJSON; M.SetBPMAt(11.5,60); Same(M.TempoPoint(1).Beat,11.5,'BPM moved measure point');
    N.LoadJSON(M.TimingJSON); Same(N.TempoPoint(2).Beat,17.5,'roundtrip moved later point');
    M.LoadJSON(Old); M.SetMeter(6,8); Same(M.MeasureStart(3),6,'meter change measure moved');
    Same(M.TempoPoint(1).Beat,9.5,'base meter edit lost measure anchor'); Same(M.TempoPoint(2).Beat,15.5,'later meter edit lost measure anchor');
    Check(D.TryLoad('',Error),Error); Check(D.SetTiming(Old,Error),Error); Check(D.SetTempoAtBeat(11.5,60,Scope,Error),Error);
    Same(D.Timing.BPMAt(11.5),60,'measure cursor edit'); Same(D.Timing.TempoPoint(2).Beat,17.5,'cursor edit moved later anchor');
    Metrics.Document := D; Check(Metrics.BeatLabel(8)='3小節','3/4 ruler'); Check(Metrics.BeatLabel(17.5)='6小節','7/8 ruler');
    Writeln('CURSOR_BPM_METER_CHANGES_MEASURE_ANCHORS_BASE_METER_EDIT_ROUNDTRIP_OK');
  finally D.Free; N.Free; M.Free; end;
end;
procedure DecimalBoundaryChecks;
var D: TMusicStudioDocument; Data: TMusicStudioTempoPatternData; P: TMusicStudioPattern;
  Track,Slot,Index,I: Integer; Scope,Error,Original,Source,Manual: string;
begin
  D := TMusicStudioDocument.Create; Data := TMusicStudioTempoPatternData.Create;
  try
    Check(D.TryLoad('',Error),Error); Track := D.AddTrack('audio'); Slot := D.AddSlot(Track,'tempo'); Index := D.AddTempo; P := D.PatternAt(Index);
    Data.ImportSnapshot('reference.mid','{"tempoPoints":[{"beat":0,"bpm":60},{"beat":0.1,"bpm":180}]}',1); P.ConfigJSON := Data.ConfigJSON; D.UpdatePattern(P);
    Check(D.AddBeatPlacement(Track,Slot,P.ID,4,1,Error),Error); Source := D.PatternAt(Index).ConfigJSON; Manual := D.ManualTimingJSON;
    Same(D.Timing.BPMAt(4.1-1E-10),60,'decimal just before'); Same(D.Timing.BPMAt(4.1),180,'decimal exact boundary dropped');
    Same(D.Timing.BPMAt(4.1+1E-10),180,'decimal just after');
    Original := Text(D);
    for I := 0 to 2 do begin
      Check(D.TryLoad(Original,Error),Error);
      case I of 0: Check(D.SetTempoAtBeat(4.1-1E-10,90,Scope,Error),Error);
        1: Check(D.SetTempoAtBeat(4.1,90,Scope,Error),Error);
        2: Check(D.SetTempoAtBeat(4.1+1E-10,90,Scope,Error),Error); end;
      if I=0 then begin Same(D.Timing.BPMAt(4),90,'before edit selected wrong range'); Same(D.Timing.BPMAt(4.1),180,'before edit changed next range'); end
      else begin Same(D.Timing.BPMAt(4),60,'boundary edit changed prior range'); Same(D.Timing.BPMAt(4.1),90,'boundary override missed'); end;
      Check(D.PatternAt(Index).ConfigJSON=Source,'boundary edit changed import'); Check(D.ManualTimingJSON=Manual,'boundary edit changed manual');
    end;
    Check(D.TryLoad(Original,Error),Error); Check(D.AddBeatPlacement(Track,Slot,P.ID,4,1,Error),Error);
    Check(D.SetTempoAtBeat(4.1,95,Scope,Error),Error); Same(D.Timing.BPMAt(4.1),95,'same-start overlap edit');
    D.RemovePlacement(Track,Slot,1); Same(D.Timing.BPMAt(4.1),180,'overlap correction leaked into lower clip');
    Writeln('CURSOR_BPM_REVIEW_DECIMAL_4_PLUS_0_1_BEFORE_EXACT_AFTER_OVERLAP_INSTANCE_OVERRIDE_OK');
  finally Data.Free; D.Free; end;
end;
procedure CursorEndChecks;
var F: TFormMusicStudioSettings; Track,Index,I: Integer; Error,Base: string; Beat: Double;
begin
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LoadDocument(''); Track := F.Document.AddTrack('audio'); Index := F.Document.AddAudio;
    Check(F.Document.AddPlacement(Track,0,F.Document.PatternAt(Index).ID,0,10,Error),Error); Base := Text(F.Document);
    F.Show; SetForegroundWindow(F.Handle);
    for I := 0 to 1 do begin
      F.LoadDocument(Base); F.Preview.Seek(9); if I=1 then F.Preview.StartSilentVisualPreview;
      SetInput(F,'60'); Beat := F.Document.SecondsToBeat(F.Preview.Position); Key(F,VK_RETURN);
      Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'BPM reduction clamped musical cursor');
      Check(F.Preview.Position>17.9,'BPM reduction returned to media end/zero');
      Check(F.Preview.EndSeconds>=20,'music navigation range lost'); Same(F.Preview.ContentEndSeconds,10,'content duration stretched');
      Same(F.Document.TrackAt(Track).Slots[0].Clips[0].LengthSeconds,10,'audio reference stretched');
      if I=1 then Check(F.Preview.IsPlaying,'playing reduction stopped/restarted');
      F.UndoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'Undo clamped cursor');
      F.RedoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'Redo clamped cursor');
      Check(F.Preview.Position>17.9,'Redo returned zero'); if I=1 then Check(F.Preview.IsPlaying,'playing redo stopped'); F.Preview.Pause;
    end;
    Check(not F.Preview.AudioEngineAllocated,'cursor end test allocated audio');
    Writeln('CURSOR_BPM_REVIEW_AUDIO10_SECONDS_CURSOR9_TO18_MUSICAL_RANGE_STOP_PLAY_UNDO_REDO_NO_STRETCH_OK');
  finally F.Free; end;
end;
procedure RunCursorUpperChecks;
var F: TFormMusicStudioSettings; Track,Index,I: Integer; Error,Base,Before: string; Beat,PositionBefore: Double; Probe: TCursorRestoreFailure;
begin
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LoadDocument(''); Track := F.Document.AddTrack('audio'); Index := F.Document.AddAudio;
    Check(F.Document.AddPlacement(Track,0,F.Document.PatternAt(Index).ID,0,604800,Error),Error); Base := Text(F.Document); F.Show; SetForegroundWindow(F.Handle);
    for I := 0 to 1 do begin
      F.LoadDocument(Base); F.Preview.Seek(9); if I=1 then F.Preview.StartSilentVisualPreview;
      SetInput(F,'60'); Beat := F.Document.SecondsToBeat(F.Preview.Position);
      Check(F.Preview.ApplyTempoEdit,'legal 604800-second clip cursor edit failed');
      Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'upper stopped/playing cursor lost');
      Check(F.Preview.EndSeconds>=1209600,'upper musical range was truncated');
      Same(F.Preview.ContentEndSeconds,604800,'upper content stretched'); if I=1 then Check(F.Preview.IsPlaying,'upper playing stopped');
      F.UndoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'upper Undo');
      F.RedoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'upper Redo'); if I=1 then Check(F.Preview.IsPlaying,'upper Redo stopped'); F.Preview.Pause;
    end;
    F.LoadDocument(Base); F.Preview.Seek(600000); SetInput(F,'60'); Beat := F.Document.SecondsToBeat(F.Preview.Position);
    Check(F.Preview.ApplyTempoEdit,'cursor beyond one million beats rejected'); Same(F.Preview.Position,1200000,'upper cursor clamped seconds');
    F.UndoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'far Undo'); F.RedoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'far Redo');
    F.LoadDocument(Base); F.Preview.Seek(600000); SetInput(F,'999.99'); Check(F.Preview.ApplyTempoEdit,'upper BPM rejected');
    Same(F.Document.SecondsToBeat(F.Preview.Position),1200000,'upper BPM cursor'); Same(F.Document.TrackAt(Track).Slots[0].Clips[0].LengthSeconds,604800,'upper BPM stretched source');
    F.Preview.Seek(600000); Beat := F.Document.SecondsToBeat(F.Preview.Position); Check(Beat>1000000,'upper tempo query fixture');
    SetInput(F,'1'); Check(F.Preview.ApplyTempoEdit,'last legal media range cannot select current manual interval');
    Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'minimum BPM large cursor');
    F.UndoEdit; F.RedoEdit; Same(F.Document.SecondsToBeat(F.Preview.Position),Beat,'upper/minimum UndoRedo');
    Before := Text(F.Document); SetInput(F,'0'); Check(not F.Preview.ApplyTempoEdit,'bad upper input accepted'); Check(Text(F.Document)=Before,'bad upper input was not atomic');
    F.LoadDocument(Base); F.Preview.Seek(9); F.Preview.StartSilentVisualPreview; Before := Text(F.Document);
    Probe := TCursorRestoreFailure.Create;
    try Probe.Form := F; Probe.Original := F.Preview.OnPositionChange; F.Preview.OnPositionChange := Probe.PositionChanged;
      SetInput(F,'60'); PositionBefore := F.Preview.Position;
      Check(not F.Preview.ApplyTempoEdit,'injected UI failure accepted'); Check(Probe.Fired,'restore failure did not run');
      Check(Text(F.Document)=Before,'restore failure committed JSON'); Same(F.Preview.Position,PositionBefore,'restore failure lost cursor');
      Check(F.Preview.IsPlaying,'restore failure lost playback'); F.UndoEdit; Check(Text(F.Document)=Before,'failed restore created undo history');
    finally F.Preview.OnPositionChange := Probe.Original; Probe.Free; end;
    F.Preview.Pause;
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'upper audio invoked');
    Writeln('CURSOR_BPM_REVIEW_LEGAL604800_MEDIA_QUERY_OVER_1M_BEATS_STOP_PLAY_FAR_CURSOR_BPM999_99_MIN1_UNDO_REDO_ATOMIC_OK');
  finally F.Free; end;
end;
procedure RunCursorTempoChecks(const Root: string);
var F: TFormMusicStudioSettings; D: TMusicStudioDocument; Data: TMusicStudioTempoPatternData;
  P: TMusicStudioPattern; Error,Scope,Before,Manual,PatternBefore,Path,FileHash,Dir: string;
  Track,Slot,Index,Audio,Song,I: Integer; Beat,Start,Length: Double;
  Bad: array[0..5] of string; Deadline: UInt64;
begin
  MeterChecks; DecimalBoundaryChecks; CursorEndChecks; RunCursorUpperChecks; Dir := TPath.Combine(Root,'cursor-tempo'); ForceDirectories(Dir);
  D := TMusicStudioDocument.Create; Data := TMusicStudioTempoPatternData.Create; F := nil;
  try
    Check(D.TryLoad('',Error),Error); Same(D.Timing.BPMAt(0),120,'new default');
    Check(D.SetTempoAtBeat(3,135,Scope,Error),Error); Same(D.Timing.BPMAt(0),135,'one point whole song');
    Check(D.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120,"tag":"first"},{"beat":4,"bpm":90},{"beat":8,"bpm":150}]}',Error),Error);
    Check(D.SetTempoAtBeat(4,80,Scope,Error),Error); Same(D.Timing.BPMAt(4-1E-8),120,'boundary edited prior point'); Same(D.Timing.BPMAt(4),80,'boundary not following range');
    Check(D.SetTempoAtBeat(20,160,Scope,Error),Error); Same(D.Timing.TempoPoint(2).Beat,8,'final range point moved'); Same(D.Timing.BPMAt(20),160,'final range');
    Audio := D.AddTrack('audio'); Index := D.AddAudio; Check(D.AddPlacement(Audio,0,D.PatternAt(Index).ID,1.123,60,Error),Error);
    Song := D.AddSinging; Slot := D.AddSlot(Audio,'singing'); Check(D.AddPlacement(Audio,Slot,D.PatternAt(Song).ID,2.234,3.456,Error),Error);
    Start := D.TrackAt(Audio).Slots[0].Clips[0].StartSeconds; Length := D.TrackAt(Audio).Slots[0].Clips[0].LengthSeconds;
    Path := TPath.Combine(Dir,'original.mid'); TFile.WriteAllBytes(Path,TBytes.Create(77,84,104,100,0,0,0,6,0,0,0,1,1,224)); FileHash := THashSHA2.GetHashStringFromFile(Path);
    Track := D.AddTrack('audio'); Slot := D.AddSlot(Track,'tempo'); Index := D.AddTempo; P := D.PatternAt(Index);
    Data.ImportSnapshot(Path,'{"tempoPoints":[{"beat":0,"bpm":60},{"beat":4,"bpm":70}],"midi":{"ppq":480,"tempoEvents":[{"tick":0,"microseconds":1000000}]}}',8);
    P.ConfigJSON := Data.ConfigJSON; D.UpdatePattern(P); PatternBefore := D.PatternAt(Index).ConfigJSON;
    Check(D.AddBeatPlacement(Track,Slot,P.ID,0,8,Error),Error); Check(D.AddBeatPlacement(Track,Slot,P.ID,12,8,Error),Error); Manual := D.ManualTimingJSON;
    Check(D.SetTempoAtBeat(0,100,Scope,Error),Error); Same(D.Timing.BPMAt(0),100,'visible clip BPM unchanged'); Same(D.Timing.BPMAt(4),70,'next imported point changed');
    Same(D.Timing.BPMAt(12),60,'another placement changed'); Check(D.ManualTimingJSON=Manual,'shadow manual mutated'); Check(D.PatternAt(Index).ConfigJSON=PatternBefore,'shared source mutated');
    Check(D.SetTempoAtBeat(4,110,Scope,Error),Error); Same(D.Timing.BPMAt(4),110,'clip source boundary'); Same(D.Timing.BPMAt(8),160,'clip end manual restore');
    Same(D.TrackAt(Audio).Slots[0].Clips[0].StartSeconds,Start,'audio start stretched'); Same(D.TrackAt(Audio).Slots[0].Clips[0].LengthSeconds,Length,'audio duration stretched');
    Same(D.TrackAt(Audio).Slots[1].Clips[0].StartSeconds,2.234,'song seconds changed'); Same(D.TrackAt(Audio).Slots[1].Clips[0].LengthSeconds,3.456,'song length changed');
    Before := Text(D); Check(D.TryLoad(Before,Error),Error); Check(Text(D)=Before,'override roundtrip');
    Check(not D.SetTempoAtBeat(0,0,Scope,Error),'zero accepted'); Check(not D.SetTempoAtBeat(0,NaN,Scope,Error),'NaN accepted'); Check(Text(D)=Before,'bad model input changed JSON');
    Check(THashSHA2.GetHashStringFromFile(Path)=FileHash,'original MIDI changed');
    Writeln('CURSOR_BPM_MANUAL_EXACT_BOUNDARY_FINAL_RANGE_CLIP_INSTANCE_ONLY_SOURCE_MANUAL_SECONDS_UNCHANGED_OK');
    F := TFormMusicStudioSettings.Create(nil); F.SilentVisualMode := True; F.LoadDocument(Text(D)); F.Show; SetForegroundWindow(F.Handle);
    Check((F.Preview.PlayButton.Width=F.Preview.StopButton.Width) and (F.Preview.PlayButton.Height=F.Preview.StopButton.Height),'transport sizes differ');
    F.Preview.Seek(0); F.TimelineBox.SetFocus; Same(StrToFloat(F.Preview.TempoEdit.Text,TFormatSettings.Invariant),100,'current BPM display');
    Before := Text(F.Document); SetInput(F,'123'); Key(F,VK_ESCAPE); Check(Text(F.Document)=Before,'Esc committed'); Check(F.Preview.TempoEdit.Text='100','Esc did not restore');
    Bad[0] := ''; Bad[1] := '0'; Bad[2] := '-1'; Bad[3] := 'abc'; Bad[4] := '1000'; Bad[5] := 'NaN';
    for I := 0 to High(Bad) do begin SetInput(F,Bad[I]); Key(F,VK_RETURN); Check(Text(F.Document)=Before,'bad Enter committed'); F.TimelineBox.SetFocus; Check(Text(F.Document)=Before,'bad blur committed'); end;
    F.Preview.Seek(F.Document.BeatToSeconds(4)); SetInput(F,'95'); Key(F,VK_RETURN); Same(F.Document.Timing.BPMAt(4),95,'Enter failed');
    Beat := F.Document.SecondsToBeat(F.Preview.Position); Same(Beat,4,'cursor beat moved');
    F.UndoEdit; Same(F.Document.Timing.BPMAt(4),110,'Undo BPM'); Check(F.Preview.TempoEdit.Text='110','Undo text stale');
    F.RedoEdit; Same(F.Document.Timing.BPMAt(4),95,'Redo BPM'); SetInput(F,'105'); F.TimelineBox.SetFocus; Same(F.Document.Timing.BPMAt(4),105,'blur failed');
    F.Preview.Seek(0); F.Preview.StartSilentVisualPreview; SetInput(F,'145'); Deadline := GetTickCount64+150;
    repeat Application.ProcessMessages; Sleep(2); until GetTickCount64>=Deadline;
    Check(F.Preview.TempoEdit.Text='145','playback overwrote editing text'); Check(F.Preview.IsPlaying,'typing paused playback'); Key(F,VK_RETURN);
    Same(F.Document.Timing.BPMAt(0),145,'latched cursor region failed'); Check(F.Preview.IsPlaying,'commit stopped playback');
    F.Preview.Pause; F.TimelineBox.SetFocus; F.Preview.Seek(F.Document.BeatToSeconds(4)); Check(F.Preview.TempoEdit.Text='105','unfocused cursor did not follow');
    F.Preview.Seek(F.Document.BeatToSeconds(3.95)); F.Preview.StartSilentVisualPreview; SetInput(F,'155'); Deadline := GetTickCount64+180;
    repeat Application.ProcessMessages; Sleep(2); until GetTickCount64>=Deadline;
    Check(F.Document.SecondsToBeat(F.Preview.Position)>4,'playback did not cross tempo boundary');
    Check(F.Preview.TempoEdit.Text='155','boundary crossing overwrote input'); Key(F,VK_RETURN);
    Same(F.Document.Timing.BPMAt(0),155,'editing-start interval not latched'); Same(F.Document.Timing.BPMAt(4),105,'crossing changed next interval');
    F.Preview.Pause; F.TimelineBox.SetFocus; F.Preview.Seek(F.Document.BeatToSeconds(4));
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio invoked');
    F.ClientWidth := F.ClientWidth+1; F.Preview.Repaint; F.Preview.TempoEdit.Repaint; F.TimelineBox.Repaint;
    Capture(F,TPath.Combine(Dir,'cursor-bpm-96.png')); TFile.WriteAllText(TPath.Combine(Dir,'cursor-bpm-demo.json'),Text(F.Document),TEncoding.UTF8);
    F.Hide; F.ScaleForPPI(144); F.Scaled := False; F.Preview.ScaleForPPI(144); F.TimelineBox.ScaleForPPI(144); F.Show;
    Check(F.Preview.PlayButton.Width=F.Preview.StopButton.Width,'144 DPI button width'); F.Preview.Repaint; Capture(F,TPath.Combine(Dir,'cursor-bpm-144.png'));
    Writeln('CURSOR_BPM_TEDIT_ENTER_BLUR_ESC_INVALID_UNDO_REDO_PLAYBACK_LATCH_NATIVE96_144_NO_AUDIO_OK');
  finally F.Free; Data.Free; D.Free; end;
end;
end.
