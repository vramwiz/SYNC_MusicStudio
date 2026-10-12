unit TimingChecks;

// テンポ表編集、未知JSON保持、入力エラー、再オープンとDPIを無音で検証する。
// 音源/MIDI/PSDの読み込み、再生、デコード、音声バックエンドを参照しない。
interface
procedure RunTimingChecks(const Root: string);

implementation

uses System.SysUtils, System.Classes, System.JSON, System.Math, System.IOUtils,
  System.Generics.Collections, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  Vcl.Imaging.pngimage, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_TimingFrame;

type
  TTestForm = class(TForm)
    procedure ScaleTo144;
  end;
  TChangeSink = class
    Count: Integer;
    procedure Changed(Sender: TObject);
  end;

const FIXTURE = '{"future":{"keep":true},"meter":{"numerator":7,"denominator":8,"label":"seven"},'+
  '"tempoPoints":[{"beat":0,"bpm":120,"id":"first"},{"beat":4,"bpm":60,"id":"middle"},'+
  '{"beat":8,"bpm":180,"id":"last","extra":{"keep":7}}]}';

procedure TTestForm.ScaleTo144;
begin ChangeScale(144,CurrentPPI,True); end;
procedure TChangeSink.Changed(Sender: TObject);
begin Inc(Count); end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure Near(Expected, Actual: Double; const Text: string);
begin Check(Abs(Expected-Actual) < 1.0E-6,Text); end;

procedure TestModel;
var Map: TMusicStudioTempoMap; Value: TJSONValue; Points: TJSONArray;
  Before: string; Failed: Boolean;
begin
  Map := TMusicStudioTempoMap.Create;
  try
    Map.LoadJSON(FIXTURE);
    Map.SetTempoPoint(2,2,90); Check(Map.PointCount = 3,'Move changed tempo count');
    Near(2,Map.TempoPoint(1).Beat,'Moved tempo not sorted');
    Near(1,Map.BeatToSeconds(2),'Moved point boundary discontinuity');
    Near(1+2.0*60/90,Map.BeatToSeconds(4),'Moved point seconds not rebuilt');
    Map.SetMeter(3,4); Near(3,Map.BeatsPerMeasure,'Fixed meter mutation');
    Value := TJSONObject.ParseJSONValue(Map.TimingJSON);
    try
      Check(TJSONObject(Value).GetValue('future') is TJSONObject,'Unknown timing root lost');
      Check(TJSONObject(TJSONObject(Value).GetValue('meter')).GetValue('label').Value = 'seven','Unknown meter field lost');
      Points := TJSONArray(TJSONObject(Value).GetValue('tempoPoints'));
      Check(TJSONObject(Points.Items[1]).GetValue('id').Value = 'last','Moved point identity lost');
      Check(TJSONObject(Points.Items[1]).GetValue('extra') is TJSONObject,'Moved point extension lost');
      Check(TJSONObject(Points.Items[1]).GetValue('startSeconds') = nil,'Derived seconds became timing source');
    finally Value.Free; end;
    Before := Map.TimingJSON; Failed := False;
    try Map.SetTempoPoint(1,Map.TempoPoint(2).Beat,90); except on EArgumentException do Failed := True; end;
    Check(Failed and (Map.TimingJSON = Before),'Duplicate edit was not atomic');
    Failed := False; try Map.SetTempoPoint(0,1,120); except on EArgumentException do Failed := True; end;
    Check(Failed and (Map.TimingJSON = Before),'Beat zero moved');
    Failed := False; try Map.DeleteTempoPoint(0); except on EArgumentException do Failed := True; end;
    Check(Failed and (Map.TimingJSON = Before),'Beat zero deleted');
    Failed := False; try Map.SetMeter(4,3); except on EArgumentException do Failed := True; end;
    Check(Failed and (Map.TimingJSON = Before),'Invalid meter was not atomic');
    Map.DeleteTempoPoint(1); Check(Map.PointCount = 2,'Delete failed');
    Near(3.5,Map.TempoPoint(1).Beat,'Delete changed remaining measure anchor');
    Near(1.75,Map.BeatToSeconds(3.5),'Delete did not rebuild seconds');
    Value := TJSONObject.ParseJSONValue(Map.TimingJSON);
    try
      Points := TJSONArray(TJSONObject(Value).GetValue('tempoPoints'));
      Check(TJSONObject(Points.Items[1]).GetValue('id').Value = 'middle','Delete damaged remaining extension');
    finally Value.Free; end;
  finally Map.Free; end;
end;

procedure SaveForm(Form: TForm; const Path: string);
var Image: TBitmap; Png: TPngImage;
begin
  Application.ProcessMessages; Image := Form.GetFormImage; Png := TPngImage.Create;
  try Png.Assign(Image); Png.SaveToFile(Path); finally Png.Free; Image.Free; end;
end;

procedure TestFrame(const Root: string);
var Form: TTestForm; Frame: TMusicStudioTimingFrame; Sink: TChangeSink;
  Before: string; Failed: Boolean; Index,Count,I: Integer; Value: TJSONValue;
begin
  Form := TTestForm.CreateNew(nil); Sink := TChangeSink.Create;
  try
    Form.Caption := 'テンポ・拍子（無音確認）'; Form.SetBounds(70,70,700,510);
    Frame := TMusicStudioTimingFrame.Create(Form); Frame.OnChange := Sink.Changed;
    Frame.LoadTiming(FIXTURE);
    Check(Frame.CanApply and (Frame.TempoMap.PointCount = 3),'Unparented timing load failed');
    Frame.Parent := Form; Frame.Align := alClient; Form.Show; Application.ProcessMessages;
    Check(Frame.TempoGrid.RowCount = 4,'Timing grid not populated');
    Check(Frame.BeatInput.ReadOnly,'Zero beat input is editable');
    Count := Sink.Count; Frame.BPMInput.Text := '0';
    Check(not Frame.CanApply and (Sink.Count > Count),'Invalid BPM did not notify/disable apply');
    Frame.NumeratorCombo.ItemIndex := 4;
    Frame.NumeratorCombo.OnChange(Frame.NumeratorCombo);
    Check(not Frame.CanApply,'Meter selection silently cleared invalid tempo input');
    Failed := False; try Frame.ConfigJSON; except on EArgumentException do Failed := True; end;
    Check(Failed and (Frame.StateText <> ''),'Invalid input silently returned old timing');
    Near(120,Frame.TempoMap.BPMAt(0),'Invalid BPM mutated map');
    Frame.BPMInput.Text := '150.5'; Check(Frame.CanApply,'Corrected BPM did not enable apply');
    Near(150.5,Frame.TempoMap.BPMAt(0),'BPM text did not edit selected row');
    Index := Frame.AddTempoPoint(12,88); Frame.SelectTempoPoint(Index);
    Frame.BeatInput.Text := '6.123'; Near(6.123,Frame.TempoMap.TempoPoint(Frame.SelectedTempoPoint).Beat,'Beat input move failed');
    Frame.BPMInput.Text := ''; Check(not Frame.CanApply,'Blank BPM accepted');
    Frame.BPMInput.Text := '96'; Check(Frame.CanApply,'Valid input did not recover');
    Frame.EditTempoPoint(Frame.SelectedTempoPoint,6.123,100);
    Failed := False; Before := Frame.TempoMap.TimingJSON;
    try Frame.SetMeter(1,8); except on EArgumentException do Failed := True; end;
    Check(Failed and (Frame.TempoMap.TimingJSON=Before),'Shorter meter silently displaced an offgrid anchor');
    Frame.SetMeter(6,8); Near(3,Frame.TempoMap.BeatsPerMeasure,'GUI meter update failed');
    Frame.NumeratorCombo.ItemIndex := 6; Frame.NumeratorCombo.OnChange(Frame.NumeratorCombo);
    Near(8.123,Frame.TempoMap.TempoPoint(Frame.SelectedTempoPoint).Beat,'Meter combo re-applied stale absolute beat');
    Frame.DenominatorCombo.ItemIndex := 2; Frame.DenominatorCombo.OnChange(Frame.DenominatorCombo);
    Check((Frame.TempoMap.Numerator = 7) and (Frame.TempoMap.Denominator = 4),'Meter combo events did not edit model');
    Frame.SelectTempoPoint(0);
    Check(Frame.BeatInput.ReadOnly and (Frame.BeatInput.Text = '0'),'Selecting zero did not lock beat');
    Frame.SelectTempoPoint(2); Before := Frame.ConfigJSON; Frame.BeatInput.Text := FloatToStr(Frame.TempoMap.TempoPoint(1).Beat,TFormatSettings.Invariant);
    Check(not Frame.CanApply and (Frame.TempoMap.TimingJSON = Before),'Duplicate input mutated map');
    Frame.SelectTempoPoint(2); Check(Frame.CanApply,'Reselect did not restore valid row');
    Frame.DeleteTempoPoint(2); Check(Frame.TempoMap.PointCount = 3,'GUI delete failed');
    Frame.LoadTiming(FIXTURE); Before := Frame.ConfigJSON;
    Failed := False;
    try Frame.LoadTiming('{"meterChanges":[{"beat":3,"numerator":3,"denominator":4}]}');
    except on EArgumentException do Failed := True; end;
    Check(Failed and not Frame.CanApply and (Frame.TempoMap.TimingJSON = Before),'Mid-measure meter change not rejected atomically');
    Check(Frame.StateText<>'','Meter boundary error message missing');
    Frame.LoadTiming(Before); Check(Frame.CanApply,'Reopen did not recover load error');
    Value := TJSONObject.ParseJSONValue(Frame.ConfigJSON);
    try Check(TJSONObject(Value).GetValue('future') is TJSONObject,'UI load lost unknown root');
    finally Value.Free; end;
    for I := 1 to 100 do Frame.TempoGrid.Repaint;
    Check(Before = Frame.ConfigJSON,'Paint changed timing');
    SaveForm(Form,TPath.Combine(Root,'timing-settings-normal.png'));
    Form.Width := 610; Form.Height := 390; SaveForm(Form,TPath.Combine(Root,'timing-settings-minimum.png'));
    Form.Width := 700; Form.Height := 510; Form.ScaleTo144;
    SaveForm(Form,TPath.Combine(Root,'timing-settings-144dpi.png'));
    Check(Before = Frame.ConfigJSON,'Resize/DPI changed timing');
    Frame.LoadTiming(''); Check((Frame.TempoMap.PointCount = 1) and Frame.CanApply,'Empty reopen did not reset timing');
    Near(120,Frame.TempoMap.BPMAt(0),'Default timing BPM');
    Check((Frame.NumeratorCombo.ItemIndex = 3) and (Frame.DenominatorCombo.ItemIndex = 2),'Default meter controls');
  finally Form.Free; Sink.Free; end;
end;

procedure RunTimingChecks(const Root: string);
begin
  ForceDirectories(Root);
  TestModel; Writeln('TIMING_MODEL_EDIT_OK'); Flush(Output);
  TestFrame(Root); Writeln('TIMING_SILENT_FRAME_OK'); Flush(Output);
end;

end.
