unit SYNC_MusicStudio_TempoTimelineChecks;

// Tempo clip合成・小節座標・参照MIDI・所有UIを無音検証。音声fixture/decode/出力なし。
interface
procedure RunTempoTimelineChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math, System.Types,
  System.UITypes, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_BeatData, SYNC_MusicStudio_TempoPatternData, SYNC_MusicStudio_MidiTempo,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_TempoPatternFrame, SYNC_MusicStudio_TimelineMetrics,
  SYNC_MusicStudio_TestHelpers;
type TTempoPopupProbe = class
    Timer: TTimer; Seen: Boolean; Deadline: UInt64;
    procedure Tick(Sender: TObject);
  end;
  TTempoDialogProbe = class
    Timer: TTimer; Save,Seen: Boolean; Deadline: UInt64;
    procedure Tick(Sender: TObject);
  end;
  TManualTempoProbe = class
    Timer: TTimer; Seen: Boolean; InitialText: string;
    procedure Tick(Sender: TObject);
  end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Tempo timeline: '+Message); end;
procedure Same(A,B: Double; const Message: string);
begin Check(Abs(A-B)<1E-7,Message+Format(' (%g / %g)',[A,B])); end;
procedure TTempoPopupProbe.Tick(Sender: TObject);
begin
  if FindWindow('#32768',nil)<>0 then begin Seen := True; Timer.Enabled := False; EndMenu; end
  else if GetTickCount64>Deadline then begin Timer.Enabled := False; EndMenu; end;
end;
procedure TTempoDialogProbe.Tick(Sender: TObject);
var I: Integer; Dialog: TMusicStudioPatternSettings;
begin
  Check(GetTickCount64<Deadline,'integrated tempo dialog timeout');
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    Dialog := TMusicStudioPatternSettings(Screen.Forms[I]); if not Dialog.Visible or (Dialog.TempoFrame=nil) then Continue;
    Seen := True; Timer.Enabled := False; Dialog.NameEdit.Text := 'テンポ操作確認'; Dialog.ColorEdit.Text := '#2468AC';
    if Save then Dialog.ModalResult := mrOK else Dialog.ModalResult := mrCancel; Exit;
  end;
end;
procedure TManualTempoProbe.Tick(Sender: TObject);
var I,J: Integer; F: TForm;
begin
  for I := 0 to Screen.FormCount-1 do begin F := Screen.Forms[I];
    if not F.Visible or (Pos('小節の手動テンポ',F.Caption)=0) then Continue;
    for J := 0 to F.ControlCount-1 do if F.Controls[J] is TEdit then begin
      InitialText := TEdit(F.Controls[J]).Text; Seen := True; Timer.Enabled := False; F.ModalResult := mrOK; Exit;
    end;
  end;
end;
procedure NativeRulerPopup(F: TFormMusicStudioSettings; Beat: Double; CanDelete: Boolean);
var Probe: TTempoPopupProbe; P: TPoint;
begin
  Probe := TTempoPopupProbe.Create; Probe.Timer := TTimer.Create(nil);
  try
    Probe.Timer.Enabled := False; Probe.Timer.Interval := 20; Probe.Timer.OnTimer := Probe.Tick;
    Probe.Deadline := GetTickCount64+5000;
    P := F.TimelineBox.ClientToScreen(Point(F.TimelineBox.HeaderWidth+Round(Beat*40),10));
    SetCursorPos(P.X,P.Y); SetForegroundWindow(F.Handle); SetFocus(F.TimelineBox.Handle);
    Probe.Timer.Enabled := True;
    SendMessage(F.TimelineBox.Handle,WM_CONTEXTMENU,F.TimelineBox.Handle,MakeLParam(P.X,P.Y));
    Check(Probe.Seen,'native ruler popup missing');
    Check(F.TempoRuler.Menu.Items[1].Enabled=CanDelete,'ruler delete enabled state');
  finally Probe.Timer.Free; Probe.Free; end;
end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; PNG: TPngImage; DC: HDC; Origin: TPoint; I: Integer;
begin
  Origin := F.ClientToScreen(Point(0,0)); SetWindowPos(F.Handle,0,F.Left-Origin.X,F.Top-Origin.Y,0,0,SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  F.Repaint; for I := 0 to F.ControlCount-1 do F.Controls[I].Repaint; Application.ProcessMessages;
  B := TBitmap.Create; PNG := TPngImage.Create;
  try B.PixelFormat := pf32bit; B.SetSize(F.ClientWidth,F.ClientHeight); DC := GetDC(F.Handle);
    try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'tempo native capture'); finally ReleaseDC(F.Handle,DC); end;
    PNG.Assign(B); PNG.SaveToFile(Path);
  finally PNG.Free; B.Free; end;
end;
function Text(D: TMusicStudioDocument): string;
var Error: string;
begin Check(D.TrySave(Result,Error),Error); end;
procedure MidiFixture(const Path: string; WithTempo: Boolean; Division: Integer = 480; WithMeter: Boolean = False; FormatOne: Boolean = False);
var S,T: TMemoryStream;
  procedure ByteValue(Stream: TStream; B: Byte); begin Stream.WriteBuffer(B,1); end;
  procedure U16(Stream: TStream; Value: Integer); begin ByteValue(Stream,(Value shr 8) and 255); ByteValue(Stream,Value and 255); end;
  procedure U32(Stream: TStream; Value: Integer); begin ByteValue(Stream,(Value shr 24) and 255); ByteValue(Stream,(Value shr 16) and 255); ByteValue(Stream,(Value shr 8) and 255); ByteValue(Stream,Value and 255); end;
  procedure Tag(Stream: TStream; const Value: AnsiString); begin Stream.WriteBuffer(Value[1],Length(Value)); end;
  procedure VLQ(Stream: TStream; Value: Integer);
  var Bytes: array[0..3] of Byte; I: Integer;
  begin I := 3; Bytes[I] := Value and 127; Value := Value shr 7;
    while Value>0 do begin Dec(I); Bytes[I] := (Value and 127) or 128; Value := Value shr 7; end;
    Stream.WriteBuffer(Bytes[I],4-I);
  end;
  procedure Tempo(Delta,Micro: Integer);
  begin VLQ(T,Delta); ByteValue(T,255); ByteValue(T,$51); ByteValue(T,3); ByteValue(T,(Micro shr 16) and 255); ByteValue(T,(Micro shr 8) and 255); ByteValue(T,Micro and 255); end;
  procedure Meter(Delta,N,D: Integer);
  begin VLQ(T,Delta); ByteValue(T,255); ByteValue(T,$58); ByteValue(T,4); ByteValue(T,N); ByteValue(T,D); ByteValue(T,24); ByteValue(T,8); end;
begin
  S := TMemoryStream.Create; T := TMemoryStream.Create;
  try
    if WithMeter then Meter(0,6,3);
    if WithTempo then begin Tempo(0,500000); Tempo(0,400000); Tempo(1920,1000000); end;
    if WithMeter then Meter(0,7,3);
    VLQ(T,1920); ByteValue(T,255); ByteValue(T,$2F); ByteValue(T,0);
    Tag(S,'MThd'); U32(S,6); if FormatOne then begin U16(S,1); U16(S,2); end else begin U16(S,0); U16(S,1); end;
    U16(S,Division); Tag(S,'MTrk'); U32(S,T.Size); T.Position := 0; S.CopyFrom(T,T.Size);
    if FormatOne then begin
      T.Clear; Tempo(0,750000); Tempo(960,1000000); VLQ(T,960); ByteValue(T,255); ByteValue(T,$2F); ByteValue(T,0);
      Tag(S,'MTrk'); U32(S,T.Size); T.Position := 0; S.CopyFrom(T,T.Size);
    end;
    S.SaveToFile(Path);
  finally T.Free; S.Free; end;
end;
procedure WaitTempo(Frame: TMusicStudioTempoPatternFrame);
var Deadline: UInt64;
begin Deadline := GetTickCount64+10000;
  repeat Frame.PollResults; Application.ProcessMessages; if not Frame.Loading then Exit;
    Check(GetTickCount64<Deadline,'tempo import timeout'); Sleep(2);
  until False;
end;
procedure Mouse(Control: TWinControl; Msg: Cardinal; X,Y: Integer);
begin SendMessage(Control.Handle,Msg,MK_LBUTTON,MakeLParam(X and $FFFF,Y and $FFFF)); end;
procedure Drag(Control: TWinControl; X,Y,DX,DY: Integer);
begin Mouse(Control,WM_LBUTTONDOWN,X,Y); Mouse(Control,WM_MOUSEMOVE,X+DX,Y+DY); Mouse(Control,WM_LBUTTONUP,X+DX,Y+DY); end;
procedure CheckAtomicTempoMutations;
var D: TMusicStudioDocument; Tempo: TMusicStudioTempoPatternData; P: TMusicStudioPattern;
  Track,SlowSlot,FastSlot,PerfTrack,PerfSlot,I,Index: Integer; Before,Effective,Error: string;
begin
  D := TMusicStudioDocument.Create; Tempo := TMusicStudioTempoPatternData.Create;
  try
    Check(D.TryLoad('',Error),Error); Check(D.SetTiming('{"tempoPoints":[{"beat":0,"bpm":1}]}',Error),Error);
    Track := D.AddTrack('audio'); SlowSlot := D.AddSlot(Track,'tempo'); FastSlot := D.AddSlot(Track,'tempo');
    Index := D.AddTempo; P := D.PatternAt(Index); Tempo.ImportSnapshot('slow.mid','{"tempoPoints":[{"beat":0,"bpm":1}]}',10000);
    P.ConfigJSON := Tempo.ConfigJSON; D.UpdatePattern(P); Check(D.AddBeatPlacement(Track,SlowSlot,P.ID,0,10000,Error),Error);
    Index := D.AddTempo; P := D.PatternAt(Index); Tempo.ImportSnapshot('fast.mid','{"tempoPoints":[{"beat":0,"bpm":120}]}',10000);
    P.ConfigJSON := Tempo.ConfigJSON; D.UpdatePattern(P); Check(D.AddBeatPlacement(Track,FastSlot,P.ID,0,10000,Error),Error);
    PerfTrack := D.AddTrack('psd'); PerfSlot := D.AddSlot(PerfTrack,'performance'); Index := D.AddPerformance;
    Check(D.AddBeatPlacement(PerfTrack,PerfSlot,D.PatternAt(Index).ID,16000,1,Error),Error);
    Before := Text(D); Effective := D.Timing.TimingJSON;
    for I := 0 to 3 do begin
      try
        case I of
          0: D.RemovePlacement(Track,FastSlot,0);
          1: D.RemoveSlot(Track,FastSlot);
          2: D.ReorderSlot(Track,FastSlot,SlowSlot);
          3: D.RemoveTrack(Track);
        end;
        Check(False,'overflowing tempo mutation accepted');
      except on E: EArgumentException do ; end;
      Check(D.Timing.TimingJSON=Effective,'failed mutation changed effective map');
      Check(Text(D)=Before,'failed deletion/reorder changed root');
      Same(D.TrackAt(PerfTrack).Slots[PerfSlot].Clips[0].StartBeat,16000,'failed mutation lost beat clip');
    end;
    Writeln('PASS review P2 atomic tempo clip/slot/track deletion and slot reorder reject 604800s overflow, root/map unchanged');
  finally Tempo.Free; D.Free; end;
end;
procedure CheckManualTempoDialog;
var F: TFormMusicStudioSettings; Data: TMusicStudioTempoPatternData; P: TMusicStudioPattern; Probe: TManualTempoProbe;
  Track,Slot,Index: Integer; Before,Error: string;
begin
  F := TFormMusicStudioSettings.Create(nil); Data := TMusicStudioTempoPatternData.Create; Probe := TManualTempoProbe.Create;
  Probe.Timer := TTimer.Create(nil); Probe.Timer.Enabled := False;
  try
    F.SilentVisualMode := True; F.LoadDocument(''); Check(F.Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120}]}',Error),Error);
    Track := F.Document.AddTrack('audio'); Slot := F.Document.AddSlot(Track,'tempo'); Index := F.Document.AddTempo; P := F.Document.PatternAt(Index);
    Data.ImportSnapshot('reference.mid','{"tempoPoints":[{"beat":0,"bpm":60}]}',8); P.ConfigJSON := Data.ConfigJSON; F.Document.UpdatePattern(P);
    Check(F.Document.AddBeatPlacement(Track,Slot,P.ID,0,8,Error),Error); F.LoadDocument(Text(F.Document)); F.TimelineBox.SetZoom(80); F.Show;
    Before := F.Document.ManualTimingJSON; NativeRulerPopup(F,0,False);
    Probe.Timer.Interval := 20; Probe.Timer.OnTimer := Probe.Tick; Probe.Timer.Enabled := True; F.TempoRuler.Menu.Items[0].Click;
    Check(Probe.Seen and (Probe.InitialText='120'),'manual dialog seeded from effective clip BPM');
    Check(F.Document.ManualTimingJSON=Before,'unchanged OK overwrote manual BPM'); Same(F.Document.Timing.BPMAt(0),60,'manual edit removed tempo clip');
    Writeln('PASS review P2 actual manual dialog opens 120 under effective clip 60 and unchanged OK preserves manual map');
  finally Probe.Timer.Free; Probe.Free; Data.Free; F.Free; end;
end;
procedure RunTempoTimelineChecks(const Root: string);
var D: TMusicStudioDocument; F: TFormMusicStudioSettings; Dialog: TMusicStudioPatternSettings;
  Data: TMusicStudioTempoPatternData; Map: TMusicStudioTempoMap; Metrics: TMusicStudioTimelineMetrics;
  Dir,FilePath,NoTempo,Smpte,MeterFile,MultiFile,Broken,JSON,Before,Error,Manual,TimingText: string; Length: Double;
  P: TMusicStudioPattern; Track,Slot,Index,OtherTrack,OtherSlot,OtherIndex,Audio,AudioTrack,I,X,Y: Integer;
  Clip: TMusicStudioPlacement; Obj: TJSONObject; Bytes: TBytes; Driver: TTempoDialogProbe;
begin
  CheckAtomicTempoMutations; CheckManualTempoDialog;
  Dir := TPath.Combine(Root,'tempo-timeline'); ForceDirectories(Dir); FilePath := TPath.Combine(Dir,'tempo.mid'); NoTempo := TPath.Combine(Dir,'no-tempo.mid'); Smpte := TPath.Combine(Dir,'smpte.mid');
  MidiFixture(FilePath,True); MidiFixture(NoTempo,False); MidiFixture(Smpte,True,$E728);
  ReadMusicStudioMidiTempo(FilePath,TimingText,Length); Map := TMusicStudioTempoMap.Create;
  try Map.LoadJSON(TimingText); Same(Map.BPMAt(0),150,'same-tick last event'); Same(Map.BPMAt(4),60,'multiple tempos');
    Obj := TJSONObject.ParseJSONValue(TimingText) as TJSONObject;
    try Check(Obj.GetValue<Integer>('midi.ppq')=480,'PPQ snapshot'); Check(TJSONArray(TJSONObject(Obj.GetValue('midi')).GetValue('tempoEvents')).Count=3,'original tempo ticks retained'); finally Obj.Free; end;
  finally Map.Free; end;
  try ReadMusicStudioMidiTempo(NoTempo,JSON,Length); Check(False,'tempo-less MIDI accepted'); except on E: EReadError do ; end;
  try ReadMusicStudioMidiTempo(Smpte,JSON,Length); Check(False,'SMPTE accepted'); except on E: EReadError do ; end;
  MeterFile := TPath.Combine(Dir,'meter.mid'); MidiFixture(MeterFile,True,480,True);
  ReadMusicStudioMidiTempo(MeterFile,JSON,Length); Map := TMusicStudioTempoMap.Create;
  try Map.LoadJSON(JSON); Check((Map.Numerator=6) and (Map.Denominator=8),'initial MIDI meter');
    Obj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
    try Check(Obj.GetValue<Integer>('midi.meterChangesIgnored')=1,'later meter warning'); finally Obj.Free; end;
  finally Map.Free; end;
  Broken := TPath.Combine(Dir,'broken.mid'); Bytes := TFile.ReadAllBytes(FilePath); SetLength(Bytes,System.Length(Bytes)-1); TFile.WriteAllBytes(Broken,Bytes);
  try ReadMusicStudioMidiTempo(Broken,JSON,Length); Check(False,'truncated MIDI accepted'); except on E: EReadError do ; end;
  MultiFile := TPath.Combine(Dir,'format1.mid'); MidiFixture(MultiFile,True,480,False,True);
  ReadMusicStudioMidiTempo(MultiFile,JSON,Length); Map := TMusicStudioTempoMap.Create;
  try Map.LoadJSON(JSON); Same(Map.BPMAt(0),80,'format1 same-tick later track'); Same(Map.BPMAt(2),60,'format1 collected second track');
  finally Map.Free; end;
  D := TMusicStudioDocument.Create; Data := TMusicStudioTempoPatternData.Create; Map := TMusicStudioTempoMap.Create; F := nil; Dialog := nil;
  try
    Check(D.TryLoad('',Error),Error); Check(D.SetTiming('{"version":1,"tempoPoints":[{"beat":0,"bpm":120,"tag":"base"},{"beat":4,"bpm":130,"tag":"manual"},{"beat":8,"bpm":100}],"timeSignature":{"numerator":4,"denominator":4},"future":"keep"}',Error),Error);
    Manual := D.ManualTimingJSON; Track := D.AddTrack('audio'); Slot := D.AddSlot(Track,'tempo'); Index := D.AddTempo;
    Data.ImportSnapshot(FilePath,'{"tempoPoints":[{"beat":0,"bpm":60},{"beat":4,"bpm":180}]}',8);
    P := D.PatternAt(Index); P.ConfigJSON := Data.ConfigJSON; D.UpdatePattern(P);
    Audio := D.AddAudio; AudioTrack := D.AddTrack('audio'); Check(D.AddPlacement(AudioTrack,0,D.PatternAt(Audio).ID,1.123,3.321,Error),Error);
    Check(D.AddBeatPlacement(Track,Slot,P.ID,4,8,Error),Error);
    Same(D.Timing.BPMAt(4),60,'clip beats manual same beat'); Same(D.Timing.BPMAt(8),180,'clip multiple points'); Same(D.Timing.BPMAt(12),100,'clip-end manual restoration');
    Check(D.ManualTimingJSON=Manual,'manual map flattened');
    Before := Text(D); P.ConfigJSON := '{"lengthBeats":8,"timing":{"tempoPoints":[{"beat":0,"bpm":0}]}}';
    try D.UpdatePattern(P); Check(False,'invalid tempo edit accepted'); except on E: EArgumentException do ; end;
    Check(Text(D)=Before,'rejected tempo edit changed JSON'); P := D.PatternAt(Index);
    try D.MovePlacement(Track,Slot,0,NaN,1); Check(False,'NaN move accepted'); except on E: EArgumentException do ; end;
    Check(Text(D)=Before,'rejected move changed JSON');
    OtherTrack := D.AddTrack('psd'); OtherSlot := D.AddSlot(OtherTrack,'tempo'); OtherIndex := D.AddTempo;
    Data.ImportSnapshot(FilePath,'{"tempoPoints":[{"beat":0,"bpm":90}]}',2); P := D.PatternAt(OtherIndex); P.ConfigJSON := Data.ConfigJSON; D.UpdatePattern(P);
    Check(D.AddBeatPlacement(OtherTrack,OtherSlot,P.ID,6,2,Error),Error); Same(D.Timing.BPMAt(6),90,'later clip priority'); Same(D.Timing.BPMAt(8),180,'overlap-end underlying clip');
    D.RemovePlacement(OtherTrack,OtherSlot,0); Same(D.Timing.BPMAt(6),60,'removed clip left residual');
    Check(D.AddBeatPlacement(OtherTrack,OtherSlot,P.ID,4,2,Error),Error); Same(D.Timing.BPMAt(4),90,'same-start later track priority'); D.RemovePlacement(OtherTrack,OtherSlot,0);
    Check(D.MoveBeatPlacement(Track,Slot,0,8,4,Error),Error); Same(D.Timing.BPMAt(4),130,'move left residual'); Same(D.Timing.BPMAt(8),60,'moved clip start'); Same(D.Timing.BPMAt(12),100,'resize end restore');
    Clip := D.TrackAt(AudioTrack).Slots[0].Clips[0]; Same(Clip.StartSeconds,1.123,'audio start altered by tempo'); Same(Clip.LengthSeconds,3.321,'audio length altered by tempo');
    JSON := Text(D); Check(D.TryLoad(JSON,Error),Error); Same(D.Timing.BPMAt(8),60,'reopen effective map'); Check(D.ManualTimingJSON=Manual,'reopen manual lost');
    D.RemovePlacement(Track,Slot,0); Same(D.Timing.BPMAt(8),100,'delete restoration');
    Writeln('PASS MIDI tempo metadata/multiple points/tick ties/no-tempo/SMPTE, immutable manual map, clip priority/move/resize/delete/reopen');
    Metrics.Document := D; Metrics.Header := 180; Metrics.ScrollTicks := 0; Metrics.PPI := 96; Metrics.Zoom := 80;
    for I := 0 to 2 do begin
      Map.LoadJSON(D.ManualTimingJSON); case I of 0: Map.SetMeter(4,4); 1: Map.SetMeter(6,8); 2: Map.SetMeter(7,8); end;
      Check(D.SetTiming(Map.TimingJSON,Error),Error);
      Same(Metrics.BeatAtX(Metrics.XAtBeat(D.Timing.BeatsPerMeasure)),D.Timing.BeatsPerMeasure,'meter measure geometry');
      Check(Metrics.BeatLabel(D.Timing.BeatsPerMeasure)='2小節','meter measure number');
    end;
    Map.SetMeter(4,4); Map.SetTempoPoint(0,0,120); Map.SetTempoPoint(1,4,60); Check(D.SetTiming(Map.TimingJSON,Error),Error);
    Same(Metrics.XAtSeconds(4),420,'nonlinear seconds to beat axis'); Same(Metrics.SecondsAtX(420),4,'inverse tempo axis');
    Before := Text(D); Metrics.PPI := 144; Metrics.Zoom := 100; Check(Text(D)=Before,'DPI/zoom changed data');
    Map.SetConstantBPM(999.99); Check(D.SetTiming(Map.TimingJSON,Error),Error);
    Metrics.Zoom := 1536; Check(Metrics.XAtSeconds(604800)>0,'large offscreen coordinate overflow');
    Check(D.TryLoad(Before,Error),Error);
    F := TFormMusicStudioSettings.Create(nil); F.SilentVisualMode := True; F.LoadDocument(Text(D));
    F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); F.TimelineBox.SelectClip(AudioTrack,0,0); F.TimelineBox.SetZoom(80);
    Check(F.TempoRuler.SetPoint(16,77,Error),Error); Before := Text(F.Document); Check(F.TempoRuler.DeletePoint(16,Error),Error);
    F.UndoEdit; Check(Text(F.Document)=Before,'ruler undo'); F.RedoEdit; Check(not F.TempoRuler.DeletePoint(0,Error),'zero tempo removed');
    Check(F.TempoRuler.SetPoint(0,110,Error),Error); Check(F.Document.Timing.PointCount>=3,'ruler edit removed other points');
    F.LoadDocument(Text(D)); F.TimelineBox.SelectClip(AudioTrack,0,0); F.TimelineBox.SetZoom(80);
    Before := Text(F.Document); NativeRulerPopup(F,0,False); NativeRulerPopup(F,4,True);
    Check(Text(F.Document)=Before,'popup cancel changed JSON');
    X := F.TimelineBox.HeaderWidth+Round(D.SecondsToBeat(1.123)*40)+20; Y := F.TimelineBox.SlotRowTop(AudioTrack,0)+F.TimelineBox.RowHeight div 2;
    Mouse(F.TimelineBox,WM_LBUTTONDOWN,X,Y); Mouse(F.TimelineBox,WM_LBUTTONUP,X,Y);
    Check(Text(F.Document)=Before,'selection click quantized offgrid 1.123 seconds');
    Drag(F.TimelineBox,X,Y,1,0); Check(Text(F.Document)=Before,'subthreshold jitter changed clip');
    X := F.TimelineBox.HeaderWidth+Round(D.SecondsToBeat(1.123+3.321)*40)-2;
    Drag(F.TimelineBox,X,Y,1,0); Check(Text(F.Document)=Before,'subthreshold edge click changed clip');
    X := F.TimelineBox.HeaderWidth+Round(D.SecondsToBeat(1.123)*40)+20;
    Writeln('PASS review P2 offgrid clip click/1px jitter/edge click preserve JSON; real drag still snaps');
    Drag(F.TimelineBox,X,Y,80,0); Clip := F.Document.TrackAt(AudioTrack).Slots[0].Clips[0];
    Same(Clip.LengthSeconds,3.321,'audio move changed seconds duration');
    F.TimelineBox.SelectClip(AudioTrack,0,0);
    X := F.TimelineBox.HeaderWidth+Round(F.Document.SecondsToBeat(Clip.StartSeconds+Clip.LengthSeconds)*40)-2;
    Same(F.TimelineBox.EmotionResizeEdgeAt(X,Y),1,'audio right resize hit');
    Before := Text(F.Document); Drag(F.TimelineBox,X,Y,40,0);
    Same(F.Document.TrackAt(AudioTrack).Slots[0].Clips[0].StartSeconds,Clip.StartSeconds,'audio right resize moved opposite edge');
    Check(F.Document.TrackAt(AudioTrack).Slots[0].Clips[0].LengthSeconds<>Clip.LengthSeconds,'audio right resize unchanged');
    F.UndoEdit; Check(Text(F.Document)=Before,'audio resize undo');
    F.TimelineBox.SelectClip(AudioTrack,0,0); X := F.TimelineBox.HeaderWidth+Round(F.Document.SecondsToBeat(Clip.StartSeconds)*40)+2;
    Drag(F.TimelineBox,X,Y,20,0);
    Same(F.Document.TrackAt(AudioTrack).Slots[0].Clips[0].StartSeconds+F.Document.TrackAt(AudioTrack).Slots[0].Clips[0].LengthSeconds,
      Clip.StartSeconds+Clip.LengthSeconds,'audio left resize moved opposite edge'); F.UndoEdit;
    Before := Text(F.Document); F.TimelineBox.SetZoom(160); Check(Text(F.Document)=Before,'timeline zoom mutated seconds');
    Dialog := TMusicStudioPatternSettings.Create(nil); P := D.PatternAt(Index); Dialog.LoadPattern(P); Check(Dialog.TempoFrame<>nil,'tempo attribute UI');
    Before := Dialog.TempoFrame.Data.ConfigJSON; Dialog.TempoFrame.StartImport(FilePath); Dialog.TempoFrame.CancelImport; WaitTempo(Dialog.TempoFrame);
    Check(Dialog.TempoFrame.Data.ConfigJSON=Before,'cancel import changed snapshot');
    Dialog.TempoFrame.StartImport(FilePath); WaitTempo(Dialog.TempoFrame); Same(Dialog.TempoFrame.Data.Timing.BPMAt(0),150,'UI imported tempo');
    Before := Dialog.TempoFrame.Data.ConfigJSON; Dialog.TempoFrame.StartImport(NoTempo); WaitTempo(Dialog.TempoFrame); Check(Dialog.TempoFrame.Data.ConfigJSON=Before,'failed import changed snapshot');
    Dialog.TempoFrame.CancelImport;
    for I := 0 to 29 do begin
      if I mod 2=0 then Dialog.TempoFrame.StartImport(FilePath) else Dialog.TempoFrame.StartImport(MeterFile);
    end;
    WaitTempo(Dialog.TempoFrame);
    for I := 0 to 50 do begin Dialog.TempoFrame.PollResults; Application.ProcessMessages; Sleep(2); end;
    Check((Dialog.TempoFrame.Data.Timing.Numerator=6) and (Dialog.TempoFrame.Data.FilePath=MeterFile),'stale tempo generation adopted');
    Dialog.TempoFrame.StartImport(MeterFile); WaitTempo(Dialog.TempoFrame);
    Dialog.Show; ShowWindow(Dialog.Handle,SW_SHOWNOACTIVATE);
    Check(Dialog.TempoFrame.FileButton.BoundsRect.Right<=Dialog.TempoFrame.FileButton.Parent.ClientWidth,'MIDI file button clipped at 96 DPI');
    Capture(Dialog,TPath.Combine(Dir,'tempo-pattern-96.png'));
    Dialog.ScaleForPPI(144);
    Check(Dialog.TempoFrame.FileButton.BoundsRect.Right<=Dialog.TempoFrame.FileButton.Parent.ClientWidth,'MIDI file button clipped at 144 DPI');
    Capture(Dialog,TPath.Combine(Dir,'tempo-pattern-144.png'));
    FreeAndNil(Dialog);
    P := F.Document.PatternAt(Index); Data.ImportSnapshot(FilePath,TimingText,8); P.ConfigJSON := Data.ConfigJSON; F.Document.UpdatePattern(P);
    Check(F.Document.AddBeatPlacement(Track,Slot,P.ID,4,8,Error),Error);
    F.LoadDocument(Text(F.Document)); F.TimelineBox.SelectSlot(Track,Slot); F.TimelineBox.SetZoom(80);
    SelectTestPattern(F,P.ID); Check(F.EditButton.Enabled,'tempo list edit disabled');
    F.TimelineBox.SelectClip(Track,Slot,0); Before := Text(F.Document);
    Y := F.TimelineBox.SlotRowTop(Track,Slot)+F.TimelineBox.RowHeight div 2;
    X := F.TimelineBox.HeaderWidth+4*40+20; Drag(F.TimelineBox,X,Y,40,0);
    Same(F.Document.TrackAt(Track).Slots[Slot].Clips[0].StartBeat,5,'tempo center move did not snap');
    Same(F.Document.Timing.BPMAt(4),60,'tempo center move left residual');
    F.UndoEdit; Check(Text(F.Document)=Before,'tempo center undo'); F.RedoEdit;
    Same(F.Document.TrackAt(Track).Slots[Slot].Clips[0].StartBeat,5,'tempo center redo'); F.UndoEdit;
    F.TimelineBox.SelectClip(Track,Slot,0); X := F.TimelineBox.HeaderWidth+12*40-2; Drag(F.TimelineBox,X,Y,40,0);
    Same(F.Document.TrackAt(Track).Slots[Slot].Clips[0].LengthBeats,9,'tempo right resize'); F.UndoEdit;
    Check(Text(F.Document)=Before,'tempo resize undo'); F.TimelineBox.SelectClip(Track,Slot,0);
    X := F.TimelineBox.HeaderWidth+4*40+2; Drag(F.TimelineBox,X,Y,40,0);
    Same(F.Document.TrackAt(Track).Slots[Slot].Clips[0].StartBeat,5,'tempo left resize');
    Same(F.Document.TrackAt(Track).Slots[Slot].Clips[0].LengthBeats,7,'tempo left resize opposite edge'); F.UndoEdit;
    F.TimelineBox.SelectClip(Track,Slot,0); F.ArrangementMenu.Items[5].Click;
    Same(F.Document.Timing.BPMAt(8),100,'tempo UI delete left residual'); F.UndoEdit;
    Check(Text(F.Document)=Before,'tempo delete undo');
    SelectTestPattern(F,P.ID); Driver := TTempoDialogProbe.Create; Driver.Timer := TTimer.Create(nil);
    try
      Driver.Timer.Enabled := False; Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick;
      Driver.Deadline := GetTickCount64+5000; Driver.Save := False; Driver.Timer.Enabled := True;
      F.EditButton.Click; Check(Driver.Seen,'integrated tempo editor absent'); Check(Text(F.Document)=Before,'tempo modal cancel changed JSON');
      Driver.Seen := False; Driver.Save := True; Driver.Deadline := GetTickCount64+5000; Driver.Timer.Enabled := True;
      F.EditButton.Click; Check(Driver.Seen,'tempo editor reopen absent');
      Check((F.Document.PatternAt(Index).Name='テンポ操作確認') and (F.Document.PatternAt(Index).Color='#2468AC'),'tempo common name/color not saved');
      F.UndoEdit; Check(Text(F.Document)=Before,'tempo edit undo'); F.RedoEdit;
      Check(F.Document.PatternAt(Index).Name='テンポ操作確認','tempo edit redo'); F.UndoEdit;
    finally Driver.Timer.Free; Driver.Free; end;
    F.TimelineBox.Repaint; Capture(F,TPath.Combine(Dir,'measure-tempo-timeline-96.png'));
    TFile.WriteAllText(TPath.Combine(Dir,'tempo-timeline-demo.json'),Text(F.Document),TEncoding.UTF8);
    F.Hide; F.ScaleForPPI(144); F.Scaled := False; F.TimelineBox.ScaleForPPI(144); F.Show;
    F.TimelineBox.Repaint; Capture(F,TPath.Combine(Dir,'measure-tempo-timeline-144.png'));
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio invoked');
    Writeln('PASS 4/4+6/8+7/8 measure mapping, ruler point editing/zero protection/undo, nonlinear hit+audio move, zoom/seconds invariants, import cancel/failure');
  finally Dialog.Free; F.Free; Map.Free; Data.Free; D.Free; end;
end;
end.
