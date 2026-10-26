unit SYNC_MusicStudio_SlotChecks;

// 仮想JSONの通常読込、旧形式移行、スロット独立性、実フォームの受入属性/順番/削除を検証。
interface
procedure RunSlotChecks(const EvidenceRoot: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Math, System.Generics.Collections,
  System.UITypes, Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Imaging.pngimage, SYNC_MusicStudio_ProjectData,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_ArrangementView;
type
  TSlotViewAccess = class(TMusicStudioArrangementView)
    procedure SelectAt(X,Y: Integer);
  end;
  TSlotDriver = class
    Timer: TTimer;
    Seen: Boolean;
    WarningSeen: Boolean;
    Stage: Integer;
    Mode: string;
    procedure Tick(Sender: TObject);
    procedure ExceptionRaised(Sender: TObject; E: Exception);
  end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
function Fixture(const Name: string): string;
begin Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),'..\..\Samples\Debug\'+Name)); end;
function SlotObj(Obj: TJSONObject; Track,Slot: Integer): TJSONObject;
begin Result := TJSONObject(TJSONArray(TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[Track]).GetValue('slots')).Items[Slot]); end;
procedure Replace(Obj: TJSONObject; const Key: string; Value: TJSONValue);
begin Obj.RemovePair(Key).Free; Obj.AddPair(Key,Value); end;
procedure TestReservedPerformanceMigration;
var D: TMusicStudioDocument; Obj,Clip: TJSONObject; Text,Error,Before,After: string;
  C: TMusicStudioPlacement;
begin
  D := TMusicStudioDocument.Create;
  try
    Text := TFile.ReadAllText(Fixture('generic-slots.json'),TEncoding.UTF8);
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      Replace(Obj,'timing',TJSONObject.ParseJSONValue('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":4,"bpm":60}]}'));
      Clip := TJSONObject(TJSONArray(SlotObj(Obj,1,0).GetValue('clips')).Items[0]);
      Replace(Clip,'startSeconds',TJSONNumber.Create(1)); Replace(Clip,'lengthSeconds',TJSONNumber.Create(4));
      Clip.AddPair('futureClip','keep');
      Check(D.TryLoad(Obj.ToJSON,Error),Error); C := D.TrackAt(1).Slots[0].Clips[0];
      Check((C.ID='debug-playing-clip') and SameValue(C.StartBeat,2) and SameValue(C.LengthBeats,5) and
        SameValue(C.StartSeconds,1) and SameValue(C.LengthSeconds,4),'legacy performance tempo-boundary migration');
      Check(D.TrySave(Before,Error),Error);
      Check((Pos('"futureClip":"keep"',Before)>0) and (Pos('"arrangementVersion":3',Before)>0),'legacy migration extensions/version');
      Clip.AddPair('timeBase','beats');
      Check(not D.TryLoad(Obj.ToJSON,Error),'partial legacy beat fields overwritten');
      Check((Error<>'') and D.TrySave(After,Error) and (Before=After),'partial migration mutated current document');
      Clip.RemovePair('timeBase').Free;
      Replace(Obj,'timing',TJSONObject.ParseJSONValue('{"tempoPoints":[{"beat":0,"bpm":1000}]}'));
      Replace(Clip,'startSeconds',TJSONNumber.Create(600000));
      Check(not D.TryLoad(Obj.ToJSON,Error),'legacy migration exceeded beat limit');
      Check((Error<>'') and D.TrySave(After,Error) and (Before=After),'out-of-range migration mutated current document');
      Replace(Obj,'timing',TJSONObject.ParseJSONValue('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":4,"bpm":60}]}'));
      Replace(Clip,'startSeconds',TJSONNumber.Create(1)); Clip.AddPair('timeBase','beats');
      Clip.AddPair('startBeat',TJSONNumber.Create(100)); Clip.AddPair('lengthBeats',TJSONNumber.Create(5));
      Check(D.TryLoad(Obj.ToJSON,Error),Error); C := D.TrackAt(1).Slots[0].Clips[0];
      Check(SameValue(C.StartBeat,100) and SameValue(C.LengthBeats,5),'existing canonical beats overwritten by legacy seconds');
      Check(D.TrySave(After,Error) and (Pos('"arrangementVersion":3',After)>0) and
        (Pos('"startSeconds":1',After)>0),'existing beats promotion discarded original fields');
      Before := After; Replace(Clip,'startBeat',TJSONNumber.Create(999999));
      Check(not D.TryLoad(Obj.ToJSON,Error),'performance end beat exceeded placement edit limit');
      Check((Error<>'') and D.TrySave(After,Error) and (Before=After),'end beat reject changed current document');
    finally Obj.Free; end;
    Check(TFile.ReadAllText(Fixture('generic-slots.json'),TEncoding.UTF8)=Text,'legacy fixture overwritten');
    Writeln('LEGACY_PERFORMANCE_TEMPO_BOUNDARY_IDS_EXTENSIONS_ATOMIC_REJECT_EXISTING_BEATS_OK');
  finally D.Free; end;
end;
procedure TestSlotModel(const EvidenceRoot: string);
var D,E: TMusicStudioDocument; Text,Before,ErrorText,SlotID,ClipID: string;
  Obj: TJSONObject; S: TMusicStudioSlot; I: Integer; Rejected: Boolean;
  procedure RejectCurrent(const Reason: string);
  var Saved: string;
  begin
    Check(not E.TryLoad(Obj.ToJSON,ErrorText),Reason);
    Check((ErrorText <> '') and E.TrySave(Saved,ErrorText) and (Saved = Before),'Failed slot load changed current document');
  end;
begin
  D := TMusicStudioDocument.Create; E := TMusicStudioDocument.Create;
  try
    Check(TryReadMusicStudioJSONFile(Fixture('generic-slots.json'),Text,ErrorText),ErrorText);
    Check(D.TryLoad(Text,ErrorText),ErrorText);
    Check((D.TrackCount = 3) and (Length(D.TrackAt(1).Slots) = 4),'Sample slots missing');
    Check((D.TrackAt(1).Slots[0].Clips[0].TimeBase='beats') and
      SameValue(D.TrackAt(1).Slots[0].Clips[0].LengthBeats,40) and
      (D.TrackAt(1).Slots[0].Clips[0].ID='debug-playing-clip'),'Reserved seconds performance lost time or identity in beat migration');
    Check(D.AddPlacement(0,0,'debug-audio',30,4,ErrorText),ErrorText);
    Check(not D.AddPlacement(1,0,'debug-singing',0,4,ErrorText) and (ErrorText <> ''),'Singing accepted by performance slot');
    Check(D.AddPlacement(1,1,'debug-singing',18,4,ErrorText),ErrorText);
    Check(D.AddPlacement(2,0,'debug-singing',30,4,ErrorText),'Track kind still fixes singing placement');
    Check(D.AddPlacement(2,0,'debug-audio',40,4,ErrorText),'Generic accepts list not used');
    Check(not D.AddPlacement(1,-1,'debug-singing',0,4,ErrorText),'Track header was a slot');
    S := D.TrackAt(1).Slots[1]; SlotID := S.ID; ClipID := S.Clips[0].ID;
    D.MovePlacement(1,1,0,6,7);
    Check(SameValue(D.TrackAt(1).Slots[0].Clips[0].StartSeconds,0),'Moving singing changed performance slot');
    Check(D.TrySave(Before,ErrorText),ErrorText);
    Check(not D.UpdateSlot(1,1,'Rejected','#112233',TArray<string>.Create('audio'),ErrorText),'Used acceptance removed');
    Check(D.TrySave(Text,ErrorText) and (Text = Before),'Rejected slot edit partially mutated');
    Check(D.UpdateSlot(1,1,'ギターの口パク','#8844AA',TArray<string>.Create('singing','audio'),ErrorText),ErrorText);
    Check(D.AddPlacement(1,1,'debug-audio',32,4,ErrorText),'Accepted audio blocked by PSD track');
    D.ReorderSlot(1,1,0);
    Check((D.TrackAt(1).Slots[0].ID = SlotID) and (D.TrackAt(1).Slots[0].Clips[0].ID = ClipID) and
      (D.TrackAt(1).Slots[0].Clips[0].SlotID = SlotID),'Reorder changed slot/placement identity');
    for I := 0 to High(D.TrackAt(1).Slots) do Check(D.TrackAt(1).Slots[I].Order = I,'Slot order not contiguous');
    D.RemoveSlot(1,0);
    Check((Length(D.TrackAt(1).Slots) = 3) and (D.TrackAt(1).Slots[0].Kind = 'performance') and
      (Length(D.TrackAt(1).Slots[0].Clips) = 1) and (D.PatternCount = 3),'Slot deletion damaged siblings/source');
    Rejected := False; try D.RemovePattern(0); except Rejected := True; end;
    Check(Rejected,'Source deleted while another slot refers to it');
    Check(D.TrySave(Text,ErrorText),ErrorText); Check(E.TryLoad(Text,ErrorText),ErrorText); Before := Text;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      Replace(TJSONObject(TJSONArray(SlotObj(Obj,0,0).GetValue('clips')).Items[0]),'slotId',TJSONString.Create('other-slot'));
      RejectCurrent('Cross-slot placement reference accepted');
    finally Obj.Free; end;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try Replace(SlotObj(Obj,0,1),'id',TJSONString.Create(SlotObj(Obj,0,0).GetValue('id').Value)); RejectCurrent('Duplicate slot ID accepted'); finally Obj.Free; end;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try Replace(SlotObj(Obj,0,0),'order',TJSONNumber.Create(2)); RejectCurrent('Invalid order accepted'); finally Obj.Free; end;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try Replace(SlotObj(Obj,0,0),'accepts',TJSONArray.Create); RejectCurrent('Empty accepts accepted'); finally Obj.Free; end;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try Replace(Obj,'arrangementVersion',TJSONNumber.Create(1)); RejectCurrent('Slots silently read as legacy'); finally Obj.Free; end;
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[0]).AddPair('clips',TJSONArray.Create);
      RejectCurrent('Mixed slot/track clips silently loaded');
    finally Obj.Free; end;
    E.RemoveSlot(2,0); Check(Length(E.TrackAt(2).Slots) = 0,'Last slot deletion removed track or left phantom slot');
    Check(E.TrySave(Text,ErrorText),ErrorText); Check(D.TryLoad(Text,ErrorText),ErrorText);
    D.AddSlot(2,'singing'); Check(Length(D.TrackAt(2).Slots) = 1,'Cannot add slot to empty track');
    Check(TryReadMusicStudioJSONFile(Fixture('legacy-tracks.json'),Text,ErrorText),ErrorText);
    Check(D.TryLoad(Text,ErrorText),ErrorText);
    Check((D.TrackAt(0).Slots[0].ID = 'legacy-slot:legacy-audio-track') and
      (D.TrackAt(0).Slots[0].Clips[0].ID = 'legacy-clip-a') and
      (D.TrackAt(1).Slots[0].Kind = 'singing'),'Legacy ID migration failed');
    Check(D.TrySave(Text,ErrorText),ErrorText);
    Check((Pos('track extension',Text) > 0) and (Pos('clip extension',Text) > 0),'Migration lost extensions');
    Check(E.TryLoad(Text,ErrorText),ErrorText); Check(E.TrySave(Before,ErrorText) and (Before = Text),'Migration is not stable');
    Text := TFile.ReadAllText(Fixture('legacy-tracks.json'),TEncoding.UTF8);
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      TJSONObject(TJSONArray(TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[0]).GetValue('clips')).Items[0]).AddPair('slotId','keep-original');
      RejectCurrent('Migration overwrote legacy slotId extension');
    finally Obj.Free; end;
    Check(D.TrySave(Text,ErrorText),ErrorText);
    TFile.WriteAllText(TPath.Combine(EvidenceRoot,'legacy-migrated.json'),Text,TEncoding.UTF8);
    Check(not TryReadMusicStudioJSONFile(Fixture('unsupported-version.json'),Text,ErrorText) and
      (Pos('arrangementVersion',ErrorText) > 0),'Future version silently loaded');
    Writeln('SLOTS_SAMPLE_LEGACY_MIGRATION_ACCEPTS_IDS_ORDER_ISOLATION_DELETE_VALIDATION_OK');
  finally E.Free; D.Free; end;
end;
procedure TSlotViewAccess.SelectAt(X,Y: Integer);
begin MouseDown(mbRight,[],X,Y); end;
procedure TSlotDriver.ExceptionRaised(Sender: TObject; E: Exception);
begin Writeln('SLOT_VCL_EXCEPTION '+E.Message); Flush(Output); Halt(1); end;
procedure TSlotDriver.Tick(Sender: TObject);
var I: Integer; F: TForm; D: TMusicStudioPatternSettings; C: TComponent;
  Active: HWND; ProcessID: DWORD; WindowClass: array[0..127] of Char;
begin
  // 最新のMessageDlgはScreen.FormsにないWindows TaskDialogを使う場合がある。
  // 自分の検証プロセスのダイアログだけを操作し、他アプリのウィンドウには触れない。
  if (Mode = 'reject') and (Stage = 1) then begin
    Active := GetActiveWindow; ProcessID := 0; WindowClass[0] := #0; GetWindowThreadProcessId(Active,@ProcessID);
    GetClassName(Active,WindowClass,Length(WindowClass));
    if (ProcessID = GetCurrentProcessId) and (string(WindowClass) = '#32770') then begin
      WarningSeen := True; Stage := 2;
      SendMessage(Active,TDM_CLICK_BUTTON,IDOK,0);
      if IsWindow(Active) then PostMessage(Active,WM_COMMAND,IDOK,0);
      Exit;
    end;
  end;
  for I := Screen.FormCount-1 downto 0 do begin
    F := Screen.Forms[I];
    // Screen.Formsは最前面順ではない。警告待ちでは背面の設定フォームを飛ばす。
    if (Mode = 'reject') and (Stage = 1) and (F is TMusicStudioPatternSettings) then Continue;
    if F is TMusicStudioPatternSettings then begin
      D := TMusicStudioPatternSettings(F); Timer.Enabled := False; Seen := True;
      Check(Assigned(D.SlotFrame) and not Assigned(D.AudioFrame) and not Assigned(D.SingingFrame),'Slot common wrapper dispatch');
      if Mode = 'reject' then begin
        if Stage = 0 then begin
          Stage := 1; Timer.Enabled := True;
          D.NameEdit.Text := '拒否される名前'; D.SlotFrame.AudioCheck.Checked := True; D.SlotFrame.SingingCheck.Checked := False;
          for C in D do if (C is TButton) and (TButton(C).Caption = 'OK') then TButton(C).Click;
        end else if Stage = 2 then begin Stage := 3; D.ModalResult := mrCancel; end;
        if Stage = 1 then Timer.Enabled := True;
        Exit;
      end;
      D.NameEdit.Text := '独立スロット'; D.ColorEdit.Text := '#E0B573';
      D.SlotFrame.AudioCheck.Checked := True; D.SlotFrame.SingingCheck.Checked := True;
      if Mode = 'cancel' then begin D.ModalResult := mrCancel; Exit; end;
      for C in D do if (C is TButton) and (TButton(C).Caption = 'OK') then TButton(C).Click;
      Exit;
    end;
    if (Mode = 'reject') and (Stage = 1) and not (F is TFormMusicStudioSettings) then
      for C in F do if (C is TButton) and (TButton(C).ModalResult = mrOK) then begin
        WarningSeen := True; Stage := 2; TButton(C).Click; Exit;
      end;
    if Mode = 'delete' then for C in F do if (C is TButton) and (TButton(C).ModalResult = mrYes) then begin
      Timer.Enabled := False; Seen := True; TButton(C).Click; Exit;
    end;
  end;
end;
procedure Capture(F: TForm; const Path: string);
var Bitmap: TBitmap; PNG: TPngImage;
begin
  F.Show; F.Update; Application.ProcessMessages; Bitmap := F.GetFormImage; PNG := TPngImage.Create;
  try PNG.Assign(Bitmap); PNG.SaveToFile(Path); finally PNG.Free; Bitmap.Free; end;
end;
procedure Start(Driver: TSlotDriver; const Mode: string);
begin Driver.Mode := Mode; Driver.Seen := False; Driver.WarningSeen := False; Driver.Stage := 0; Driver.Timer.Enabled := True; end;
procedure TestSlotGUI(const EvidenceRoot: string);
var F: TFormMusicStudioSettings; D: TMusicStudioPatternSettings; Driver: TSlotDriver;
  Text,Before,ErrorText,ID,SourceID: string; X,Y,Index: Integer; Accept: Boolean; S: TMusicStudioSlot;
  C: TComponent;
begin
  F := TFormMusicStudioSettings.Create(nil); Driver := TSlotDriver.Create;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Driver.Timer.Interval := 50; Driver.Timer.OnTimer := Driver.Tick;
  Application.OnException := Driver.ExceptionRaised;
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(EvidenceRoot,'slot-library');
    F.LoadDocument(''); F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
    Check(F.ImportJSONFile(Fixture('generic-slots.json'),ErrorText),ErrorText);
    F.TimelineBox.SelectSlot(1,1); X := F.TimelineBox.HeaderWidth+100; Y := F.TimelineBox.SlotRowTop(1,1)+20;
    Capture(F,TPath.Combine(EvidenceRoot,'generic-slots-loaded.png'));
    Check(F.TimelineBox.SlotAtPoint(X,Y) = 1,'Expanded slot hit testing');
    F.PatternList.ItemIndex := 0; F.PatternList.OnClick(F.PatternList);
    F.TimelineBox.OnDragOver(F.TimelineBox,F.PatternList,X,Y,dsDragMove,Accept);
    Check(Accept,'Singing rejected from instrument mouth slot');
    Y := F.TimelineBox.SlotRowTop(1,0)+20;
    F.TimelineBox.OnDragOver(F.TimelineBox,F.PatternList,X,Y,dsDragMove,Accept); Check(not Accept,'Wrong slot accepts singing');
    F.TimelineBox.SelectSlot(1,1); F.ArrangementMenu.OnPopup(F.ArrangementMenu);
    S := F.Document.TrackAt(1).Slots[1]; ID := S.ID; SourceID := S.Clips[0].PatternID;
    Check(F.Document.TrySave(Before,ErrorText),ErrorText);
    Start(Driver,'cancel'); F.ArrangementMenu.Items[7].Click;
    Check(Driver.Seen and F.Document.TrySave(Text,ErrorText) and (Text = Before),'Slot cancel mutated document');
    Start(Driver,'reject'); F.ArrangementMenu.Items[7].Click;
    Check(Driver.Seen and Driver.WarningSeen and (Driver.Stage = 3) and
      F.Document.TrySave(Text,ErrorText) and (Text = Before),'GUI rejected acceptance lost document or did not reopen editor');
    Start(Driver,'edit'); F.ArrangementMenu.Items[7].Click;
    Check(Driver.Seen and (F.Document.TrackAt(1).Slots[1].Name = '独立スロット') and
      (F.Document.TrackAt(1).Slots[0].Kind = 'performance'),'Slot edit affected siblings');
    Check(F.DropPatternAt(0,1,1,28,ErrorText),'New slot accepts not used by D&D');
    F.ArrangementMenu.OnPopup(F.ArrangementMenu); F.ArrangementMenu.Items[9].Click;
    Check((F.Document.TrackAt(1).Slots[0].ID = ID) and (F.TimelineBox.SelectedSlot = 0),'GUI slot reorder identity/selection');
    D := TMusicStudioPatternSettings.Create(F);
    try
      D.SilentVisualMode := True;
      D.LoadSlot(F.Document.TrackAt(1).Slots[0]); Capture(D,TPath.Combine(EvidenceRoot,'slot-settings.png'));
      D.ClientWidth := 680; D.ClientHeight := 480; Capture(D,TPath.Combine(EvidenceRoot,'slot-minimum.png'));
      D.SlotFrame.AudioCheck.Checked := False; D.SlotFrame.SingingCheck.Checked := False;
      D.SlotFrame.PerformanceCheck.Checked := False; D.SlotFrame.EmotionCheck.Checked := False; D.SlotFrame.RhythmCheck.Checked := False;
      for C in D do if (C is TButton) and (TButton(C).Caption = 'OK') then TButton(C).Click;
      Check(D.ModalResult = mrNone,'Zero-acceptance dialog was accepted');
      S := F.Document.TrackAt(1).Slots[0]; S.Accepts := S.Accepts+['future-mouth-style'];
      D.LoadSlot(S); D.ReadSlot(S);
      Check(Pos('future-mouth-style',string.Join(',',S.Accepts)) > 0,'Common slot editor lost unknown accepted kind');
    finally D.Free; end;
    F.TimelineBox.SelectTrack(1); Capture(F,TPath.Combine(EvidenceRoot,'generic-slots.png'));
    F.ClientWidth := 1000; F.ClientHeight := 562; F.TimelineBox.SelectSlot(1,0);
    Capture(F,TPath.Combine(EvidenceRoot,'generic-slots-minimum.png'));
    Check(F.Document.TrySave(Text,ErrorText),ErrorText);
    Check(Pos('"instrument":"guitar"',Text) > 0,'Unknown instrument metadata lost');
    TFile.WriteAllText(TPath.Combine(EvidenceRoot,'generic-slots-edited.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text); Check(F.Document.TrackAt(1).Slots[0].ID = ID,'GUI slot reload identity');
    F.TimelineBox.SelectSlot(1,0); F.ArrangementMenu.OnPopup(F.ArrangementMenu);
    Start(Driver,'delete'); F.ArrangementMenu.Items[8].Click;
    Check(Driver.Seen and (Length(F.Document.TrackAt(1).Slots) = 3) and (F.Document.PatternCount = 3) and
      F.Document.PatternInUse(SourceID),'GUI deletion damaged other slot source references');
    F.TimelineBox.SelectTrack(1); F.SlotAddMenu.Items[1].Click;
    Index := High(F.Document.TrackAt(1).Slots);
    Check((F.TimelineBox.SelectedSlot = Index) and (F.TimelineBox.SlotRowTop(1,Index) >= F.TimelineBox.RulerHeight),
      'Added slot not selected/scrolled into view');
    Check(F.TimelineBox.SlotAtPoint(F.TimelineBox.HeaderWidth+10,F.TimelineBox.SlotRowTop(1,Index)+20) = Index,
      'Added slot remains outside viewport');
    Capture(F,TPath.Combine(EvidenceRoot,'generic-slot-scrolled.png'));
    D := TMusicStudioPatternSettings.Create(F);
    try
      D.SilentVisualMode := True;
      D.LoadPattern(F.Document.PatternAt(0));
      Check(not D.AudioFrame.IsLoading,'silent audio reference opened a decoder');
      Check((D.AudioFrame.WavePointCount = 0) and (D.AudioFrame.WaveMessage <> ''),'Missing fixture WAV not explicit');
      Capture(D,TPath.Combine(EvidenceRoot,'sample-missing-audio.png'));
      D.LoadPattern(F.Document.PatternAt(1));
      while D.SingingFrame.IsLoading do begin D.SingingFrame.PollResults; Application.ProcessMessages; Sleep(1); end;
      Check(D.SingingFrame.Source.Message <> '','Missing fixture MIDI not explicit');
      D.LoadTrack(F.Document.TrackAt(1)); Capture(D,TPath.Combine(EvidenceRoot,'sample-missing-psd.png'));
    finally D.Free; end;
    Check(F.Document.TrySave(Before,ErrorText),ErrorText);
    Check(not F.ImportJSONFile(Fixture('unsupported-version.json'),ErrorText),'Unsupported sample loaded in UI');
    Check(F.Document.TrySave(Text,ErrorText) and (Text = Before),'Rejected import lost current editor');
    Check(F.ImportJSONFile(Fixture('generic-slots.json'),ErrorText),ErrorText);
    F.TimelineBox.SelectTrack(1);
    Check(F.Document.TrySave(Text,ErrorText),ErrorText);
    Text := Copy(Text,1,Length(Text)-1)+',"padding":"'+StringOfChar('x',32750-Length(Text)-13)+'"}';
    F.LoadDocument(Text); F.TimelineBox.SelectTrack(1);
    Check(F.Document.TrySave(Before,ErrorText),ErrorText);
    F.SlotAddMenu.Items[1].Click;
    Check((Length(F.Document.TrackAt(1).Slots) = 4) and F.Document.TrySave(Text,ErrorText) and (Text = Before),
      'Oversized slot mutation lost original JSON');
    Check(F.ImportJSONFile(Fixture('generic-slots.json'),ErrorText),ErrorText);
    Check(F.Document.TrySave(Before,ErrorText),ErrorText);
    // 実モニターは96DPI。ScaleForPPI後のVCL内部倍率を使う独立レイアウト検証。
    // Scaled=FalseでGetDPIforWindow(96)によるgetterの置換を止め、実機切替とは区別する。
    F.ScaleForPPI(144); F.Scaled := False; F.ClientWidth := F.ClientWidth+1;
    F.TimelineBox.SelectSlot(1,1);
    Check((F.TimelineBox.CurrentPPI = 144) and SameValue(F.TimelineBox.SecondsAtPoint(F.TimelineBox.HeaderWidth+120),2),
      'DPI change broke time conversion');
    Check(F.TimelineBox.SlotAtPoint(F.TimelineBox.HeaderWidth+120,F.TimelineBox.SlotRowTop(1,1)+30) = 1,
      'DPI change broke slot targeting');
    Capture(F,TPath.Combine(EvidenceRoot,'generic-slots-dpi144.png'));
    D := TMusicStudioPatternSettings.Create(F);
    try
      D.LoadSlot(F.Document.TrackAt(1).Slots[1]); D.ClientWidth := 680; D.ClientHeight := 480;
      D.ScaleForPPI(144); D.Scaled := False; D.ClientWidth := D.ClientWidth+1;
      Check((D.ColorEdit.Left > D.NameEdit.Left+D.NameEdit.Width) and
        (D.SlotFrame.AudioCheck.Top+D.SlotFrame.AudioCheck.Height < D.SlotFrame.SingingCheck.Top),'DPI popup controls overlap');
      Capture(D,TPath.Combine(EvidenceRoot,'slot-dpi144.png'));
    finally D.Free; end;
    F.Scaled := True; F.ScaleForPPI(96);
    Check(F.Document.TrySave(Text,ErrorText) and (Text = Before),'DPI change mutated JSON');
    F.CancelButtonClick(nil);
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'slot GUI allocated output or decoded sound');
    Writeln('GUI_SAMPLE_IMPORT_MISSING_REFS_SLOTS_DND_EDIT_CANCEL_REORDER_DELETE_RESIZE_RELOAD_OK');
  finally Application.OnException := nil; Driver.Timer.Free; Driver.Free; F.Free; end;
end;
procedure RunSlotChecks(const EvidenceRoot: string);
begin TestReservedPerformanceMigration; TestSlotModel(EvidenceRoot); TestSlotGUI(EvidenceRoot); end;
end.
