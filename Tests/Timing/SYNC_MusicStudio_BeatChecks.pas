unit SYNC_MusicStudio_BeatChecks;

// 拍/秒の境界、正本JSON、スナップ、無音ピアノロール操作を独立検証する。
// 音声関連ユニットもMIDI/PSD解析も参照しない。
interface
procedure RunBeatChecks(const Root: string);

implementation

uses System.SysUtils, System.Classes, System.Types, System.JSON, System.Math, System.IOUtils,
  System.Generics.Collections,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_BeatData, SYNC_MusicStudio_PerformanceFrame;

type
  TPaintAccess = class(TPaintBox)
    procedure Press(X,Y: Integer; Button: TMouseButton);
    procedure MoveTo(X,Y: Integer);
    procedure ReleaseAt(X,Y: Integer);
  end;
  TPerformanceAccess = class(TMusicStudioPerformanceFrame)
    procedure ZoomAt(X,Y: Integer; Delta: Integer);
    procedure PressDelete;
  end;
  TTestForm = class(TForm)
    procedure ScaleTo144;
  end;

procedure TPaintAccess.Press(X,Y: Integer; Button: TMouseButton);
begin MouseDown(Button,[],X,Y); end;
procedure TPaintAccess.MoveTo(X,Y: Integer);
begin MouseMove([ssLeft],X,Y); end;
procedure TPaintAccess.ReleaseAt(X,Y: Integer);
begin MouseUp(mbLeft,[],X,Y); end;
procedure TPerformanceAccess.ZoomAt(X,Y: Integer; Delta: Integer);
begin DoMouseWheel([ssCtrl],Delta,PianoRoll.ClientToScreen(Point(X,Y))); end;
procedure TPerformanceAccess.PressDelete;
var Key: Word;
begin Key := VK_DELETE; KeyDown(Key,[]); end;
procedure TTestForm.ScaleTo144;
begin ChangeScale(144,CurrentPPI,True); end;

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure Near(Expected, Actual: Double; const Text: string);
begin Check(Abs(Expected-Actual) < 0.000001,Text+Format(' expected=%.8f actual=%.8f',[Expected,Actual])); end;

procedure ExpectBadTempo(Map: TMusicStudioTempoMap; const Text: string);
var Before: string; Failed: Boolean;
begin
  Before := Map.TimingJSON; Failed := False;
  try Map.LoadJSON(Text); except on EArgumentException do Failed := True; end;
  Check(Failed and (Before = Map.TimingJSON),'Invalid timing mutated valid tempo map');
end;

procedure TestTempo;
var Map: TMusicStudioTempoMap; I: Integer; Beat, Seconds: Double; Value: TJSONValue;
  Points: TJSONArray;
begin
  Map := TMusicStudioTempoMap.Create;
  try
    Near(120,Map.BPMAt(0),'Default BPM'); Near(4,Map.BeatsPerMeasure,'Default meter');
    Near(2,Map.BeatToSeconds(4),'Default quarter beats');
    Map.LoadJSON('{"future":{"keep":true},"meter":{"numerator":7,"denominator":8,"label":"seven"},'+
      '"tempoPoints":[{"beat":8,"bpm":180,"id":"last"},{"beat":0,"bpm":120,"id":"first"},'+
      '{"beat":4,"bpm":60,"id":"middle"}]}');
    Check(Map.PointCount = 3,'Tempo points not retained'); Near(3.5,Map.BeatsPerMeasure,'7/8 quarter unit');
    Near(0,Map.BeatToSeconds(0),'Tempo zero'); Near(2,Map.BeatToSeconds(4),'First boundary');
    Near(6,Map.BeatToSeconds(8),'Second boundary'); Near(6+2.0/3,Map.BeatToSeconds(10),'Final segment');
    Near(120,Map.BPMAt(4-1.0E-8),'BPM before boundary'); Near(60,Map.BPMAt(4),'BPM at boundary');
    for I := -10 to 200 do begin Beat := I/10.0; Seconds := Map.BeatToSeconds(Beat);
      Near(Beat,Map.SecondsToBeat(Seconds),'Tempo roundtrip'); end;
    Near(4-1.0E-8,Map.SecondsToBeat(Map.BeatToSeconds(4-1.0E-8)),'Near boundary before');
    Near(4+1.0E-8,Map.SecondsToBeat(Map.BeatToSeconds(4+1.0E-8)),'Near boundary after');
    Map.SetBPMAt(0,240); Near(1,Map.BeatToSeconds(4),'Initial BPM change'); Near(5,Map.BeatToSeconds(8),'Rebuilt seconds');
    Near(8,Map.TempoPoint(2).Beat,'BPM change moved beat');
    Map.SetBPMAt(6,90); Check(Map.PointCount = 4,'Tempo insertion failed'); Near(6,Map.TempoPoint(2).Beat,'Inserted tempo order');
    Value := TJSONObject.ParseJSONValue(Map.TimingJSON);
    try
      Check(TJSONObject(Value).GetValue('future') is TJSONObject,'Timing root extension lost');
      Points := TJSONArray(TJSONObject(Value).GetValue('tempoPoints'));
      Check(TJSONObject(Points.Items[0]).GetValue('id').Value = 'first','Sorted point extension lost');
      Check(TJSONObject(Points.Items[3]).GetValue('id').Value = 'last','Last point extension lost');
      Check(TJSONObject(Points.Items[0]).GetValue('startSeconds') = nil,'Derived seconds saved as timing source');
    finally Value.Free; end;
    ExpectBadTempo(Map,'{"tempoPoints":[{"beat":0,"bpm":0}]}');
    ExpectBadTempo(Map,'{"tempoPoints":[{"beat":1,"bpm":120}]}');
    ExpectBadTempo(Map,'{"tempoPoints":[{"beat":0,"bpm":120},{"beat":0,"bpm":80}]}');
    ExpectBadTempo(Map,'{"meterChanges":[{"beat":3,"numerator":3,"denominator":4}]}');
    ExpectBadTempo(Map,'{"meter":{"numerator":4,"denominator":3}}');
    ExpectBadTempo(Map,'{"meter":{"numerator":3.5,"denominator":4}}');
    ExpectBadTempo(Map,'{"version":2}');
    Map.SetConstantBPM(90); Check(Map.PointCount = 1,'Explicit constant tempo did not replace points');
    Near(8,Map.BeatToSeconds(12),'Constant tempo conversion');
  finally Map.Free; end;
end;

procedure TestSnap;
begin
  Near(1,MusicStudioSnapStep(12),'Low zoom snap'); Near(0.5,MusicStudioSnapStep(24),'Half snap');
  Near(0.25,MusicStudioSnapStep(48),'Quarter snap'); Near(0.125,MusicStudioSnapStep(96),'Eighth snap');
  Near(0.0625,MusicStudioSnapStep(192),'Sixteenth snap'); Near(1.0/64,MusicStudioSnapStep(768),'64th snap');
  Near(0.25,MusicStudioSnapBeat(0.125,0.25),'Positive midpoint');
  Near(0,MusicStudioSnapBeat(-0.125,0.25),'Negative midpoint');
  Near(0,MusicStudioSnapBeat(0.124999,0.25),'Before midpoint');
  Near(-0.5,MusicStudioSnapBeat(-0.376,0.25),'Negative snap');
  Near(4,MusicStudioSnapBeat(3.999,0.25),'Boundary snap');
  Near(4.25,MusicStudioSnapBeat(4.126,0.25),'After boundary snap');
end;

procedure TestPerformanceData;
var Data: TMusicStudioPerformanceData; Note: TMusicStudioPerformanceNote;
  Value: TJSONValue; Notes: TJSONArray; Before: string; Failed: Boolean; Map: TMusicStudioTempoMap;
begin
  Data := TMusicStudioPerformanceData.Create; Map := TMusicStudioTempoMap.Create;
  try
    Data.LoadJSON('{"futureRoot":{"keep":1},"lengthBeats":16,"notes":['+
      '{"id":"one","startBeat":1.5,"lengthBeats":0.75,"pitch":60,"velocity":110,"pose":"unknown"},'+
      '{"id":"two","startBeat":7,"lengthBeats":1,"pitch":127,"velocity":127}]}');
    Check((Data.LowestPitch = 60) and (Data.HighestPitch = 127),'Cached pitch range invalid');
    Before := Data.ConfigJSON; Map.SetConstantBPM(60);
    Near(1.5,Map.BeatToSeconds(Data.NoteAt(0).StartBeat),'BPM 60 conversion');
    Map.SetConstantBPM(120); Near(0.75,Map.BeatToSeconds(Data.NoteAt(0).StartBeat),'BPM 120 conversion');
    Check(Before = Data.ConfigJSON,'BPM change changed canonical note beats');
    Note := Data.NoteAt(0); Note.Pitch := 0; Data.SetNote(0,Note);
    Check((Data.LowestPitch = 0) and (Data.HighestPitch = 127),'Pitch mutation did not invalidate range');
    Note.Pitch := 61; Note.StartBeat := 4; Note.LengthBeats := 0.5; Data.AddNote(Note);
    Data.DeleteNote(1); Check(Data.NoteCount = 2,'Performance delete failed');
    Value := TJSONObject.ParseJSONValue(Data.ConfigJSON);
    try
      Check(TJSONObject(Value).GetValue('futureRoot') is TJSONObject,'Performance root extension lost');
      Notes := TJSONArray(TJSONObject(Value).GetValue('notes'));
      Check(TJSONObject(Notes.Items[0]).GetValue('id').Value = 'one','Performance note id lost');
      Check(TJSONObject(Notes.Items[0]).GetValue('pose').Value = 'unknown','Unknown instrument pose replaced');
      Check(TJSONObject(Notes.Items[1]).GetValue('startSeconds') = nil,'Performance generated seconds source');
    finally Value.Free; end;
    Before := Data.ConfigJSON; Failed := False;
    try Data.LengthBeats := 2; except on EArgumentException do Failed := True; end;
    Check(Failed and (Before = Data.ConfigJSON),'Shortening pattern discarded out-of-range notes');
    Failed := False;
    try Data.LoadJSON('{"lengthBeats":1,"notes":[{"startBeat":0.5,"lengthBeats":1,"pitch":60}]}');
    except on EArgumentException do Failed := True; end;
    Check(Failed and (Before = Data.ConfigJSON),'Invalid performance load not atomic');
    Failed := False; Note.LengthBeats := 0;
    try Data.AddNote(Note); except on EArgumentException do Failed := True; end;
    Check(Failed,'Zero note length accepted');
    Failed := False;
    try Data.LoadJSON('{"notes":[{"startBeat":0,"lengthBeats":1,"pitch":60.5}]}');
    except on EArgumentException do Failed := True; end;
    Check(Failed,'Fractional MIDI pitch accepted');
    Data.DeleteNote(1); Data.DeleteNote(0);
    Check((Data.LowestPitch = -1) and (Data.HighestPitch = -1),'Empty cached range invalid');
  finally Map.Free; Data.Free; end;
end;

procedure SaveForm(Form: TForm; const Path: string);
var Image: TBitmap; Png: TPngImage;
begin
  Application.ProcessMessages; Image := Form.GetFormImage; Png := TPngImage.Create;
  try Png.Assign(Image); Png.SaveToFile(Path); finally Png.Free; Image.Free; end;
end;

procedure TestFrame(const Root: string);
var Form: TTestForm; Frame: TMusicStudioPerformanceFrame; Roll: TPaintAccess;
  R: TRect; X,Y,Count,I: Integer; Note: TMusicStudioPerformanceNote; Before: string; Step: Double;
begin
  Form := TTestForm.CreateNew(nil);
  try
    Form.Caption := '演奏ピアノロール（無音）'; Form.SetBounds(60,60,840,540);
    Frame := TMusicStudioPerformanceFrame.Create(Form);
    Frame.LoadPerformance('{"lengthBeats":8,"notes":[]}');
    Near(8,Frame.Data.LengthBeats,'Unparented frame load');
    Frame.Parent := Form; Frame.Align := alClient;
    Frame.LoadPerformance('{"lengthBeats":16,"notes":[{"startBeat":2,"lengthBeats":1,"pitch":60,"velocity":104}]}');
    Form.Show; Application.ProcessMessages; Roll := TPaintAccess(Frame.PianoRoll);
    R := Frame.NoteRect(0); X := R.Left+Round((4.4-2)*Frame.PixelsPerBeat); Y := (R.Top+R.Bottom) div 2;
    Roll.Press(X,Y,mbLeft); Roll.ReleaseAt(X,Y);
    Check(Frame.Data.NoteCount = 2,'Piano-roll click did not add note'); Note := Frame.Data.NoteAt(1);
    Near(4.5,Note.StartBeat,'Click snap'); Near(0.25,Note.LengthBeats,'Automatic snap duration');
    Check((Note.Pitch = 60) and (Note.Velocity = 100),'Click pitch/velocity mismatch');
    R := Frame.NoteRect(1); X := (R.Left+R.Right) div 2; Y := (R.Top+R.Bottom) div 2;
    Roll.Press(X,Y,mbLeft); Roll.MoveTo(X+Round(1.24*Frame.PixelsPerBeat),Y+16);
    Roll.ReleaseAt(X+Round(1.24*Frame.PixelsPerBeat),Y+16);
    Note := Frame.Data.NoteAt(1); Near(5.75,Note.StartBeat,'Drag snap'); Check(Note.Pitch = 59,'Drag pitch mismatch');
    Before := Frame.ConfigJSON; Frame.PreviewTempoBPM := 60; Check(Before = Frame.ConfigJSON,'Preview BPM rewrote beats');
    Count := Frame.RenderCount;
    for I := 1 to 100 do Frame.PianoRoll.Repaint;
    Check(Frame.RenderCount = Count,'Paint regenerated roll cache');
    for I := 1 to 4 do TPerformanceAccess(Frame).ZoomAt(300,150,120);
    Check((Frame.SnapStep < 0.25) and (Frame.PixelsPerBeat > 80),'Zoom did not adjust subdivision');
    Check(Before = Frame.ConfigJSON,'Zoom changed note data');
    Frame.ViewStartBeat := 0; SaveForm(Form,TPath.Combine(Root,'performance-piano-normal.png'));
    Form.Width := 620; Form.Height := 410; SaveForm(Form,TPath.Combine(Root,'performance-piano-minimum.png'));
    Form.Width := 840; Form.Height := 540; Step := Frame.SnapStep; Form.ScaleTo144;
    SaveForm(Form,TPath.Combine(Root,'performance-piano-144dpi.png'));
    Near(Step,Frame.SnapStep,'DPI alone changed beat subdivision'); Check(Before = Frame.ConfigJSON,'DPI changed note data');
    Frame.SelectNote(1); Frame.MoveSelectedNote(6.5,127); Note := Frame.Data.NoteAt(1);
    Near(6.5,Note.StartBeat,'API movement'); Check(Note.Pitch = 127,'Pitch 127 movement');
    Frame.DeleteSelectedNote; Check(Frame.Data.NoteCount = 1,'Selected delete failed');
    Frame.SelectNote(0); TPerformanceAccess(Frame).PressDelete; Check(Frame.Data.NoteCount = 0,'Delete key failed');
    Frame.AddNote(1,1,0,1); Frame.SelectNote(0); Frame.MoveSelectedNote(2,127);
    Check((Frame.Data.LowestPitch = 127) and (Frame.Data.HighestPitch = 127),'0/127 editor note bounds');
    Frame.LoadPerformance(''); Check(Frame.Data.NoteCount = 0,'Reopen did not reset editor');
  finally Form.Free; end;
end;

procedure RunBeatChecks(const Root: string);
begin
  ForceDirectories(Root);
  TestTempo; Writeln('BEAT_TEMPO_BOUNDARIES_OK'); Flush(Output);
  TestSnap; Writeln('BEAT_SNAP_OK'); Flush(Output);
  TestPerformanceData; Writeln('PERFORMANCE_BEAT_JSON_OK'); Flush(Output);
  TestFrame(Root); Writeln('PERFORMANCE_SILENT_FRAME_OK'); Flush(Output);
end;

end.
