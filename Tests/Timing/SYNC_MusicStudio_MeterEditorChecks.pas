unit SYNC_MusicStudio_MeterEditorChecks;

// 途中拍子の候補検証、実コントロール入力、作品保存/Undoを隔離して検証する。
// 音声・DPI変更・native popup・実作品/共有素材の入出力は実行しない。
interface
procedure RunMeterEditorChecks(const Root: string);
implementation
uses System.Generics.Collections, System.SysUtils, System.Classes, System.JSON, System.Math, System.IOUtils,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_BeatData, SYNC_MusicStudio_TimingFrame, SYNC_MusicStudio_MeterEditor,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_EditHistory;
const FIXTURE = '{"future":"keep","meter":{"numerator":4,"denominator":4},'+
  '"meterChanges":[{"measure":5,"numerator":7,"denominator":8,"id":"seven"},'+
  '{"measure":9,"numerator":3,"denominator":4,"id":"three"}],'+
  '"tempoPoints":[{"beat":0,"bpm":120},{"measure":6,"beatInMeasure":1,"bpm":60,"id":"tempo"}]}';
procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
procedure Near(Expected, Actual: Double; const Msg: string);
begin Check(Abs(Expected-Actual)<1E-7,Msg); end;
procedure TestModel;
var M: TMusicStudioTempoMap; O: TJSONObject; A: TJSONArray; Before: string; Failed: Boolean; Index: Integer;
begin
  M := TMusicStudioTempoMap.Create;
  try
    M.LoadJSON(FIXTURE); Index := M.AddMeterChange(3,3,4); Check(Index=0,'Add not sorted');
    Near(14,M.MeasureStart(5),'Meter start not recalculated');
    Near(18.5,M.TempoPoint(1).Beat,'Tempo measure anchor moved');
    Near(9.25,M.TempoPoint(1).StartSeconds,'Tempo seconds not rebuilt');
    M.SetMeterChange(1,4,6,8);
    O := TJSONObject.ParseJSONValue(M.TimingJSON) as TJSONObject;
    try
      Check(O.GetValue('future').Value='keep','Root extension lost');
      A := O.GetValue('meterChanges') as TJSONArray;
      Check(TJSONObject(A.Items[1]).GetValue('id').Value='seven','Changed row extension lost');
    finally O.Free; end;
    Before := M.TimingJSON; Failed := False;
    try M.AddMeterChange(4,4,4); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Duplicate add not atomic');
    Failed := False; try M.SetMeterChange(0,1,3,4); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Measure one accepted');
    Failed := False; try M.AddMeterChange(10,4,3); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Bad denominator mutated state');
    Failed := False; try M.SetMeterChange(-1,10,4,4); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Negative edit inserted a new row');
    Failed := False; try M.AddMeterChange(16000001,4,4); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Quarter-beat limit not atomic');
    M.SetMeterChange(0,7,5,8); Check(M.MeterChange(1).Measure=7,'Moved row not sorted');
    M.DeleteMeterChange(1); Check(M.MeterChangeCount=2,'Delete failed');
    M.DeleteMeterChange(1); M.DeleteMeterChange(0); Before := M.TimingJSON; M.LoadJSON(Before);
    Check(M.MeterChangeCount=0,'Last deleted row resurrected');
    M.LoadJSON('{"meterChanges":null}'); M.AddMeterChange(2,3,4); Check(M.MeterChangeCount=1,'Null old array rejected');
    M.LoadJSON('{"tempoPoints":[{"beat":0,"bpm":120},{"measure":3,"beatInMeasure":3,"bpm":90}]}');
    Before := M.TimingJSON; Failed := False;
    try M.AddMeterChange(3,3,4); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before=M.TimingJSON),'Out-of-measure tempo anchor displaced');
    Writeln('METER_MUTATION_SORT_UNKNOWN_FIELDS_ANCHOR_ATOMIC_DELETE_OK'); Flush(Output);
  finally M.Free; end;
end;
// 個々の実コントロールを同じ座標へ描画する。画面外formのPrintWindowには依存しない。
procedure RenderControls(Control: TWinControl; Bitmap: TBitmap; X,Y: Integer);
var I: Integer; Child: TControl;
begin
  Control.PaintTo(Bitmap.Canvas.Handle,X,Y);
  for I := 0 to Control.ControlCount-1 do begin
    Child := Control.Controls[I];
    if (Child is TWinControl) and Child.Visible then
      RenderControls(TWinControl(Child),Bitmap,X+Child.Left,Y+Child.Top);
  end;
end;
procedure TestFrame(const Root: string);
var F: TForm; T: TMusicStudioTimingFrame; E: TMusicStudioMeterEditor; Before: string;
  Failed: Boolean; B: TBitmap; P: TPngImage; I: Integer; Doc: TMusicStudioDocument;
  H: TMusicStudioEditHistory; OldJSON, NewJSON, Restored, ErrorText: string;
begin
  F := TForm.CreateNew(nil); Doc := TMusicStudioDocument.Create; H := TMusicStudioEditHistory.Create;
  try
    F.ClientWidth := 760; F.ClientHeight := 440;
    T := TMusicStudioTimingFrame.Create(F); T.LoadTiming(FIXTURE); T.Parent := F; T.Align := alClient;
    // テスト所有formを画面外・非アクティブで描画し、ユーザーの操作画面に残さない。
    F.SetBounds(-30000,-30000,F.Width,F.Height); F.HandleNeeded;
    SetWindowLongPtr(F.Handle,GWL_EXSTYLE,GetWindowLongPtr(F.Handle,GWL_EXSTYLE) or WS_EX_NOACTIVATE);
    F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages; T.HandleNeeded; E := T.MeterEditor;
    Check(T.Pages.PageCount=2,'Meter tab missing'); T.Pages.ActivePageIndex := 1; Application.ProcessMessages;
    Check(E.Grid.RowCount=3,'Meter rows missing'); E.SelectChange(0);
    Before := T.TempoMap.TimingJSON; E.MeasureInput.Text := '1';
    Check(not T.CanApply and (T.TempoMap.TimingJSON=Before),'Invalid control changed model');
    Failed := False; try T.ConfigJSON; except on EArgumentException do Failed := True; end;
    Check(Failed and (T.StateText<>''),'Invalid meter allowed modal commit');
    E.MeasureInput.Text := '4'; Check(T.CanApply,'Corrected input did not recover');
    Near(12,T.TempoMap.MeterChange(0).Beat,'Measure input not applied');
    E.NumeratorCombo.ItemIndex := 5; E.NumeratorCombo.OnChange(E.NumeratorCombo);
    Check(T.TempoMap.MeterChange(0).Numerator=6,'Numerator event failed');
    E.DenominatorCombo.ItemIndex := 2; E.DenominatorCombo.OnChange(E.DenominatorCombo);
    Check(T.TempoMap.MeterChange(0).Denominator=4,'Denominator event failed');
    E.MeasureInput.Text := '9'; Check(not T.CanApply,'Duplicate control input accepted');
    E.SelectChange(0); Check(T.CanApply,'Reselect did not cancel invalid input');
    T.BPMInput.Text := '0'; Check(not T.CanApply,'Tempo invalid input ignored');
    E.EditChange(0,4,7,8); Check(not T.CanApply,'Meter edit cleared invalid tempo input');
    T.BPMInput.Text := '120'; Check(T.CanApply,'Tempo recovery failed');
    // 実ボタンのclick dispatchで既定の次小節追加と削除を確認する。
    for I := 0 to E.ComponentCount-1 do if (E.Components[I] is TButton) and
      (TButton(E.Components[I]).Caption='拍子変更を追加') then TButton(E.Components[I]).Click;
    Check(T.TempoMap.MeterChangeCount=3,'Add button failed');
    for I := 0 to E.ComponentCount-1 do if (E.Components[I] is TButton) and
      (TButton(E.Components[I]).Caption='選択行を削除') then TButton(E.Components[I]).Click;
    Check(T.TempoMap.MeterChangeCount=2,'Delete button failed');
    Check(Doc.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,ErrorText),ErrorText); Check(Doc.TrySave(OldJSON,ErrorText),ErrorText);
    Check(Doc.SetTiming(T.ConfigJSON,ErrorText),ErrorText); Check(Doc.TrySave(NewJSON,ErrorText),ErrorText); H.RecordChange(OldJSON,NewJSON);
    Check(H.Undo(NewJSON,Restored),'Undo unavailable'); Check(Doc.TryLoad(Restored,ErrorText),ErrorText);
    Check(Doc.Timing.MeterChangeCount=0,'Undo meter failed');
    Check(H.Redo(Restored,NewJSON),'Redo unavailable'); Check(Doc.TryLoad(NewJSON,ErrorText),ErrorText);
    Near(12,Doc.Timing.MeasureStart(4),'Document meter not restored');
    T.LoadTiming(Doc.ManualTimingJSON); Check(T.CanApply and (E.Grid.RowCount=3),'Reopen failed');
    Before := T.ConfigJSON;
    for I := 1 to 40 do E.Grid.Repaint;
    Check(Before=T.ConfigJSON,'Paint mutated timing');
    B := TBitmap.Create; P := TPngImage.Create;
    try
      B.SetSize(F.ClientWidth,F.ClientHeight); RenderControls(F,B,0,0); P.Assign(B);
      P.SaveToFile(TPath.Combine(Root,'meter-controls.png'));
    finally P.Free; B.Free; end;
    F.ClientWidth := 650; F.ClientHeight := 370; Application.ProcessMessages;
    Check(E.Grid.ClientHeight>2*E.Grid.DefaultRowHeight,'Minimum grid height clipped');
    for I := 0 to E.ComponentCount-1 do if E.Components[I] is TButton then
      Check(TButton(E.Components[I]).BoundsRect.Right<=TButton(E.Components[I]).Parent.ClientWidth,'Minimum meter buttons clipped');
    T.LoadTiming(''); Check(T.CanApply and not E.MeasureInput.Enabled,'Empty meter state not reset');
    Writeln('METER_TAB_INPUT_VALIDATION_RECOVERY_BUTTONS_DOCUMENT_ROUNDTRIP_UNDO_REDO_NO_POPUP_NO_AUDIO_OK'); Flush(Output);
  finally H.Free; Doc.Free; F.Free; end;
end;
procedure RunMeterEditorChecks(const Root: string);
begin
  ForceDirectories(Root); TestModel; TestFrame(Root);
end;
end.
