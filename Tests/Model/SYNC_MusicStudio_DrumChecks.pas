unit SYNC_MusicStudio_DrumChecks;
// 所有するテスト画面と隔離JSONだけでドラム編集を検証。音声とPSDは使用しない。
interface
procedure RunDrumChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_DrumData, SYNC_MusicStudio_DrumFrame, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SettingsForm;
type
  TDrumPopupDriver = class
    Timer: TTimer;
    Menu: TPopupMenu;
    Choice: Integer;
    procedure Tick(Sender: TObject);
  end;
  TDrumDialogDriver = class
    Timer: TTimer;
    Save,Seen,PreviewDelivered: Boolean;
    Main: TFormMusicStudioSettings;
    procedure Tick(Sender: TObject);
  end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('DRUM: '+Text); end;
procedure TDrumPopupDriver.Tick(Sender: TObject);
begin Timer.Enabled := False; Menu.Items[Choice].Click; EndMenu; end;
procedure TDrumDialogDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings;
begin
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]); if D.DrumFrame=nil then Continue;
    Timer.Enabled := False; Seen := True;
    D.DrumFrame.Data.Toggle(0,1.25); D.DrumFrame.Seek(1.5);
    PreviewDelivered := (Pos('表情:',Main.StatusLabel.Caption)>0) and (Abs(Main.Preview.Position-0.75)<1E-8);
    if Save then D.ModalResult := mrOK else D.ModalResult := mrCancel;
    Exit;
  end;
end;
procedure EntryChecks(const Root: string);
var F: TFormMusicStudioSettings; Driver: TDrumDialogDriver; Doc: TMusicStudioDocument;
  Text,Error,Before: string; Track,Slot,I,Index: Integer; Found: Boolean;
begin
  F := TFormMusicStudioSettings.Create(nil); Driver := TDrumDialogDriver.Create; Doc := TMusicStudioDocument.Create;
  Driver.Main := F;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick;
  try
    Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Slot := Doc.AddSlot(Track,'performance');
    Check(Doc.TrySave(Text,Error),Error); F.SilentVisualMode := True;
    F.LibraryRoot := TPath.Combine(Root,'entry-library'); F.LoadDocument(Text); F.Show;
    F.TimelineBox.SelectSlot(Track,Slot); Found := False;
    for I := 0 to F.AddMenu.Items.Count-1 do if F.AddMenu.Items[I].Caption='ドラムパターン' then begin
      F.AddMenu.Items[I].Click; Found := True; Break;
    end;
    Check(Found,'drum entry menu'); Index := F.SelectedLibraryPattern;
    Check((Index>=0) and MusicStudioHasDrums(F.Document.PatternAt(Index).ConfigJSON),'PSD-free addition');
    Before := F.Document.PatternAt(Index).ConfigJSON;
    Driver.Save := False; Driver.Seen := False; Driver.Timer.Enabled := True; F.EditButton.Click;
    Check(Driver.Seen and (F.Document.PatternAt(Index).ConfigJSON=Before),'entry cancel');
    Driver.Save := True; Driver.Seen := False; Driver.Timer.Enabled := True; F.EditButton.Click;
    Check(Driver.Seen and (F.Document.PatternAt(Index).ConfigJSON<>Before),'entry apply');
    Check(Driver.PreviewDelivered,'main preview state delivery');
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'entry zero audio');
    Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text);
    Check(MusicStudioHasDrums(F.Document.PatternAt(Index).ConfigJSON),'entry project reopen');
    TFile.WriteAllText(TPath.Combine(Root,'drum-project.json'),Text,TEncoding.UTF8);
    Writeln('DRUM_ENTRY_ADD_CANCEL_APPLY_PREVIEW_REOPEN_ZERO_AUDIO_OK');
  finally Driver.Timer.Free; Driver.Free; Doc.Free; F.Free; end;
end;
procedure RunDrumChecks(const Root: string);
var Data,CopyData: TMusicStudioDrumData; Bar: TDrumBar; Saved,Bad,Error: string;
  Dialog: TMusicStudioPatternSettings; Pattern: TMusicStudioPattern; F: TMusicStudioDrumFrame;
  Key: Word; Bmp: TBitmap; PNG: TPngImage; DC: HDC; I,Y,RH: Integer; Doc: TMusicStudioDocument;
  PopupDriver: TDrumPopupDriver;
  Combo: TComboBox; InitialWidth: Integer;
  function XBeat(Beat: Double): Integer;
  begin Result := 134+Round(Beat*(F.Grid.Width-135)/F.Data.LengthBeats); end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin F.Grid.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure Click(X,Y: Integer);
  begin Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X,Y); end;
  procedure Drag(X1,Y1,X2,Y2: Integer);
  begin Mouse(WM_LBUTTONDOWN,X1,Y1,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X2,Y2,MK_LBUTTON); Mouse(WM_LBUTTONUP,X2,Y2); end;
  procedure Shot(const Name: string);
  begin
    Dialog.Repaint; Application.ProcessMessages;
    Bmp := TBitmap.Create; PNG := TPngImage.Create;
    try
      Bmp.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); DC := GetDC(Dialog.Handle);
      try Check(BitBlt(Bmp.Canvas.Handle,0,0,Bmp.Width,Bmp.Height,DC,0,0,SRCCOPY),'native capture');
      finally ReleaseDC(Dialog.Handle,DC); end;
      PNG.Assign(Bmp); PNG.SaveToFile(TPath.Combine(Root,Name));
    finally PNG.Free; Bmp.Free; end;
  end;
begin
  ForceDirectories(Root); Data := TMusicStudioDrumData.Create; CopyData := TMusicStudioDrumData.Create;
  try
    Check((Data.Rows[8]='スティック') and (Data.StepsPerBar=16),'default grid/stick');
    Data.Toggle(0,0); Data.Toggle(7,0); Data.SetHitState(1,dhPlayable);
    Data.Toggle(8,3.75); Data.SetHitState(2,dhImpossible);
    Bar.Lane := 0; Bar.Kind := 1; Bar.StartBeat := 0; Bar.EndBeat := 1;
    Check(Data.PutBar(-1,Bar),'first range'); Bar.StartBeat := 0.5; Bar.EndBeat := 1.5;
    Check(not Data.PutBar(-1,Bar),'overlap rejection'); Bar.StartBeat := 1; Bar.EndBeat := 2;
    Check(Data.PutBar(-1,Bar),'adjacency accepted'); Bar.Lane := 1; Bar.Kind := 6;
    Check(Data.PutBar(-1,Bar),'separate lanes may overlap');
    Saved := Data.JSON; CopyData.Load(Saved);
    Check((CopyData.Hits.Count=3) and (CopyData.Hits[2].State=dhImpossible) and (CopyData.Ranges.Count=3),'round trip');
    Bad := StringReplace(Saved,'"stepsPerBar":16','"stepsPerBar":0',[]);
    try CopyData.Load(Bad); Check(False,'invalid grid accepted'); except on E: Exception do Check(CopyData.JSON=Saved,'failed load atomic'); end;
    Data.SetGrid(2,16); Data.Toggle(0,7.75);
    try Data.SetGrid(1,16); Check(False,'destructive shortening accepted'); except on E: Exception do Check(Data.Bars=2,'shortening atomic'); end;
    Data.Load(Saved);
    Pattern := Default(TMusicStudioPattern); Pattern.ID := 'drum-demo'; Pattern.Kind := 'performance';
    Pattern.Name := 'ドラムパターン'; Pattern.Color := '#EDBA70'; Pattern.ConfigJSON := Saved;
    Dialog := TMusicStudioPatternSettings.Create(nil);
    try
      Dialog.SilentVisualMode := True; Dialog.LoadPattern(Pattern); F := Dialog.DrumFrame;
      Check((F<>nil) and (Dialog.LayersFrame=nil) and (Dialog.LayerStepFrame=nil),'PSD independent editor route');
      Dialog.Show; Dialog.BringToFront; Application.ProcessMessages;
      RH := Max(1,(F.Grid.Height-28) div 11); Y := 28+RH div 2;
      I := F.Data.Hits.Count; Click(XBeat(1.25)+5,Y);
      Check((F.Data.Hits.Count=I+1) and (F.Data.HitAt(0,1.25)>=0),'native hit on');
      Click(XBeat(1.25)+5,Y); Check(F.Data.Hits.Count=I,'native hit off');
      Y := 28+9*RH+RH div 2;
      Drag(XBeat(2.25),Y,XBeat(3.25),Y);
      Check(F.Data.Ranges.Count=4,'native blank range drag');
      Check(Abs(F.Data.Ranges[3].StartBeat-2.25)<1E-8,'range start');
      Drag(XBeat(2.75),Y,XBeat(3),Y);
      Check(Abs(F.Data.Ranges[3].StartBeat-2.5)<1E-8,'native move');
      Drag(XBeat(3.5)-1,Y,XBeat(3.75),Y);
      Check(Abs(F.Data.Ranges[3].EndBeat-3.75)<1E-8,'native right resize');
      Drag(XBeat(2.5)+1,Y,XBeat(2.25),Y);
      Check(Abs(F.Data.Ranges[3].StartBeat-2.25)<1E-8,'native left resize');
      Saved := F.ConfigJSON;
      Drag(XBeat(2.75),Y,XBeat(1.25),Y);
      Check(F.ConfigJSON=Saved,'overlap drag is rejected');
      Mouse(WM_LBUTTONDOWN,XBeat(2.75),Y,MK_LBUTTON);
      Mouse(WM_MOUSEMOVE,XBeat(3),Y,MK_LBUTTON); Key := VK_ESCAPE; F.HandleKey(Key,[]);
      Check(F.ConfigJSON=Saved,'Escape drag cancellation');
      Mouse(WM_LBUTTONDOWN,XBeat(2.75),Y,MK_LBUTTON);
      Mouse(WM_MOUSEMOVE,XBeat(3),Y,MK_LBUTTON);
      Check(GetCapture=F.Grid.Handle,'test grid owns capture'); ReleaseCapture;
      Mouse(WM_LBUTTONUP,XBeat(3),Y); Check(F.ConfigJSON=Saved,'capture loss then mouseup cancels');
      Key := VK_DELETE; F.HandleKey(Key,[]); Check(F.Data.Ranges.Count=3,'delete');
      Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]); Check(F.ConfigJSON=Saved,'undo');
      Key := Ord('Y'); F.HandleKey(Key,[ssCtrl]); Check(F.Data.Ranges.Count=3,'redo');
      Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]);
      PopupDriver := TDrumPopupDriver.Create;
      PopupDriver.Timer := TTimer.Create(nil); PopupDriver.Timer.Enabled := False; PopupDriver.Timer.Interval := 20;
      PopupDriver.Timer.OnTimer := PopupDriver.Tick;
      try
        for I := 0 to F.ComponentCount-1 do if F.Components[I] is TPopupMenu then PopupDriver.Menu := TPopupMenu(F.Components[I]);
        Check(PopupDriver.Menu<>nil,'popup component'); PopupDriver.Choice := 2; PopupDriver.Timer.Enabled := True;
        Click(XBeat(2.75),Y); Check(F.Data.Ranges[3].Kind=2,'native expression popup choice');
      finally PopupDriver.Timer.Free; PopupDriver.Free; end;
      Click(XBeat(2),8); Check(Abs(F.Position-2)<=F.Data.LengthBeats/(F.Grid.Width-135),'ruler seek stopped');
      Key := VK_SPACE; F.HandleKey(Key,[]); Check(F.State=dtPlaying,'play');
      Sleep(60); Application.ProcessMessages; Check(F.Position>2,'silent clock');
      Key := VK_SPACE; F.HandleKey(Key,[]); Check(F.State=dtPaused,'pause');
      Saved := F.ConfigJSON; Sleep(40); Application.ProcessMessages;
      Check(F.ConfigJSON=Saved,'transport does not edit'); F.Stop; Check(F.Position=0,'stop resets');
      Dialog.ReadPattern(Pattern); CopyData.Load(Pattern.ConfigJSON); Check(CopyData.Ranges.Count=4,'parent save');
      for I := 0 to F.ComponentCount-1 do begin
        Check(not (F.Components[I] is TScrollBar),'no horizontal or vertical scrollbar');
        if F.Components[I] is TComboBox then begin
          Combo := TComboBox(F.Components[I]);
          Check((Combo.Style=csOwnerDrawFixed) and Assigned(Combo.OnDrawItem),'dark owner draw combo');
        end;
      end;
      InitialWidth := F.Grid.Width; Dialog.ClientWidth := 900; Application.ProcessMessages;
      Check(F.Grid.Width<InitialWidth,'grid follows form width');
      Click(F.Grid.Width-1,8); Check(Abs(F.Position-F.Data.LengthBeats)<1E-8,'full pattern end fits narrow width');
      Check(F.ConfigJSON=Saved,'resize preserves musical data'); Dialog.ClientWidth := 1050;
      for I := 0 to F.ComponentCount-1 do if (F.Components[I] is TComboBox) and
        (TComboBox(F.Components[I]).Items.Count=64) then begin
        Combo := TComboBox(F.Components[I]); Combo.ItemIndex := 1; Combo.OnChange(Combo);
        Check(F.Data.Bars=2,'two measures'); Click(XBeat(7.75)+1,28+RH div 2);
        Check(F.Data.HitAt(0,7.75)>=0,'last step in second measure fits width');
        Click(XBeat(7.75)+1,28+RH div 2); Combo.ItemIndex := 0; Combo.OnChange(Combo);
        Check(F.ConfigJSON=Saved,'measure fit preserves original data');
        Combo.DroppedDown := True; Application.ProcessMessages; Shot('drums-combo-dark.png'); Combo.DroppedDown := False;
        Break;
      end;
      Shot('drums-96.png');
      Dialog.Hide; Check(F.State=dtStopped,'hide stops clock');
      TFile.WriteAllText(TPath.Combine(Root,'drum-performance.json'),Pattern.ConfigJSON,TEncoding.UTF8);
    finally Dialog.Free; end;
    Doc := TMusicStudioDocument.Create;
    try
      Check(Doc.TryLoad('{"schemaVersion":1,"previewAudio":null,"materials":[],"characters":[],"tracks":[],"patterns":[]}',Error),Error);
      I := Doc.AddPerformance; Pattern.ID := Doc.PatternAt(I).ID; Doc.UpdatePattern(Pattern);
      Check(Doc.TrySave(Saved,Error),Error);
      Check(Doc.TryLoad(Saved,Error),Error); Check(MusicStudioHasDrums(Doc.PatternAt(I).ConfigJSON),'document reload');
      TFile.WriteAllText(TPath.Combine(Root,'drum-project.json'),Saved,TEncoding.UTF8);
    finally Doc.Free; end;
    Writeln('DRUM_MODEL_UI_SAVE_TRANSPORT_OK');
    EntryChecks(Root);
  finally CopyData.Free; Data.Free; end;
end;
end.
