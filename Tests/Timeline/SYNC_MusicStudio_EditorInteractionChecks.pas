unit SYNC_MusicStudio_EditorInteractionChecks;

// 実VCLフォームの歌唱設定・D&Dハンドラー・配置/トラックのメニューと再読込を検証する。
interface
procedure RunEditorInteractionChecks(const Root: string);
implementation
uses
  System.Classes, System.SysUtils, System.Types, System.Math, System.IOUtils,
  System.UITypes, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_SingingFrame, SYNC_MusicStudio_SingingData, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_TestHelpers;

type
  TViewAccess = class(TMusicStudioArrangementView)
    procedure SelectAt(X,Y: Integer);
    procedure WheelAt(X,Y,Delta: Integer; Shift: TShiftState);
  end;
  TInteractionDriver = class
    Timer: TTimer;
    Mode: string;
    Path: string;
    Seen: Boolean;
    procedure Tick(Sender: TObject);
    procedure AppException(Sender: TObject; E: Exception);
  end;

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;

procedure Capture(Form: TForm; const Path: string);
var Bitmap: TBitmap; PNG: TPngImage;
begin
  Form.Show; Form.Update; Application.ProcessMessages;
  Bitmap := Form.GetFormImage; PNG := TPngImage.Create;
  try PNG.Assign(Bitmap); PNG.SaveToFile(Path); finally PNG.Free; Bitmap.Free; end;
end;

procedure AwaitSinging(Frame: TMusicStudioSingingFrame);
var Start: UInt64;
begin
  Start := GetTickCount64;
  while Frame.IsLoading do begin
    Frame.PollResults; Application.ProcessMessages;
    Check(GetTickCount64 - Start < 10000,'Singing decode timeout');
    Sleep(1);
  end;
end;

procedure TViewAccess.SelectAt(X,Y: Integer);
begin MouseDown(mbRight,[],X,Y); end;
procedure TViewAccess.WheelAt(X,Y,Delta: Integer; Shift: TShiftState);
begin DoMouseWheel(Shift,Delta,ClientToScreen(Point(X,Y))); end;

procedure TInteractionDriver.AppException(Sender: TObject; E: Exception);
begin Writeln('VCL_EXCEPTION '+ E.ClassName+': '+E.Message); Flush(Output); Halt(1); end;

procedure TInteractionDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings; C: TComponent; F: TForm;
begin
  for I := Screen.FormCount - 1 downto 0 do begin
    F := Screen.Forms[I];
    if F is TMusicStudioPatternSettings then begin
      D := TMusicStudioPatternSettings(F); Timer.Enabled := False; Seen := True;
      if Mode = 'singing-cancel' then begin D.NameEdit.Text := '取り消す名前'; D.ModalResult := mrCancel; Exit; end;
      if Mode = 'singing' then begin
        Check(Assigned(D.SingingFrame) and not Assigned(D.AudioFrame),'Wrong attribute frame');
        D.NameEdit.Text := 'ボーカル'; D.ColorEdit.Text := '#C78AE8';
        D.SingingFrame.SelectFile(Path); AwaitSinging(D.SingingFrame);
        Check(D.SingingFrame.Source.Status = ssReady,D.SingingFrame.Source.Message);
      end;
      if Mode = 'track' then begin
        Check(Assigned(D.PsdFrame),'PSD frame missing');
        D.NameEdit.Text := '歌唱者PSD'; D.ColorEdit.Text := '#C78AE8'; D.PsdFrame.SelectFile(Path);
      end;
      for C in D do if (C is TButton) and (TButton(C).Caption = 'OK') then TButton(C).Click;
      Exit;
    end;
    if (Mode = 'placement') and (F.Caption = '配置の開始・長さ') then begin
      Timer.Enabled := False; Seen := True;
      for C in F do if C is TEdit then begin
        if TEdit(C).Top = 18 then TEdit(C).Text := '3.5' else TEdit(C).Text := '6.5';
      end;
      for C in F do if (C is TButton) and (TButton(C).Caption = 'OK') then TButton(C).Click;
      Exit;
    end;
    if Mode = 'delete-track' then
      for C in F do if (C is TButton) and (TButton(C).ModalResult = mrYes) then begin
        Timer.Enabled := False; Seen := True; TButton(C).Click; Exit;
      end;
  end;
end;

procedure StartDriver(Driver: TInteractionDriver; const Mode, Path: string);
begin Driver.Mode := Mode; Driver.Path := Path; Driver.Seen := False; Driver.Timer.Enabled := True; end;

procedure RunEditorInteractionChecks(const Root: string);
var
  F: TFormMusicStudioSettings; D: TMusicStudioPatternSettings; Driver: TInteractionDriver;
  P: TMusicStudioPattern; Accept: Boolean; X,Y,AudioSlot,SingingSlot: Integer; Text,ErrorText,ID: string;
  Header: TBytes; Component: TComponent;
begin
  F := TFormMusicStudioSettings.Create(nil); Driver := TInteractionDriver.Create;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False;
  Driver.Timer.Interval := 50; Driver.Timer.OnTimer := Driver.Tick;
  Application.OnException := Driver.AppException;
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Root,'interaction-library');
    F.ClientHeight := 900;
    F.LoadDocument(''); F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
    F.TrackAddMenu.Items[0].Click; F.TrackAddMenu.Items[1].Click;
    AudioSlot := TestSlotIndex(F.Document,0,'audio'); SingingSlot := TestSlotIndex(F.Document,1,'singing');
    F.TimelineBox.SelectSlot(0,AudioSlot); F.AddButton.Click;
    F.TimelineBox.SelectSlot(1,SingingSlot); F.AddButton.Click;
    Check((F.Document.PatternCount = 2) and (F.Document.TrackCount = 2),'GUI track/pattern add');
    StartDriver(Driver,'singing',TPath.Combine(Root,'singing-demo.mid')); F.EditButton.Click;
    Check(Driver.Seen,'Singing popup did not open');
    P := F.Document.PatternAt(1);
    Check((P.Name = 'ボーカル') and (P.SourceTrack = 0) and SameValue(P.Duration,2.5),'Singing GUI settings lost');
    StartDriver(Driver,'singing-cancel',''); F.EditButton.Click;
    Check(Driver.Seen and (F.Document.PatternAt(1).Name = 'ボーカル'),'Singing cancel mutated document');
    D := TMusicStudioPatternSettings.Create(F);
    try
      D.SilentVisualMode := True;
      D.LoadPattern(P); AwaitSinging(D.SingingFrame);
      Check(D.SingingFrame.NotesList.Items.Count = 2,'Saved track did not reopen');
      D.SingingFrame.SelectFile(P.FilePath);
      for Component in D do if (Component is TButton) and (TButton(Component).Caption = 'OK') then TButton(Component).Click;
      Check(D.ModalResult = mrNone,'Dialog closed while source metadata was still loading');
      D.LoadPattern(P); AwaitSinging(D.SingingFrame);
      D.SingingFrame.TrackCombo.ItemIndex := 2;
      D.SingingFrame.TrackCombo.OnChange(D.SingingFrame.TrackCombo);
      Check(D.SingingFrame.NotesList.Items.Count = 1,'Changing source track did not change notes');
      D.SingingFrame.TrackCombo.ItemIndex := 0;
      D.SingingFrame.TrackCombo.OnChange(D.SingingFrame.TrackCombo);
      Capture(D,TPath.Combine(Root,'singing-settings.png'));
      D.ClientWidth := 680; D.ClientHeight := 480;
      Capture(D,TPath.Combine(Root,'singing-minimum.png'));
      Check(D.SingingFrame.PathEdit.Width > 300,'Singing minimum source collapsed');
      D.SingingFrame.SelectFile(P.FilePath);
      D.SingingFrame.SelectFile(TPath.Combine(Root,'broken.mid'));
      Check(Length(D.SingingFrame.Source.Notes) = 0,'Old singing notes not immediately cleared');
      AwaitSinging(D.SingingFrame);
      Check(D.SingingFrame.Source.Status = ssBroken,'Old MIDI contaminated broken result');
      D.SingingFrame.SelectFile(P.FilePath); D.SingingFrame.SelectFile('');
      Application.ProcessMessages; D.SingingFrame.PollResults;
      Check((D.SingingFrame.FilePath = '') and (Length(D.SingingFrame.Source.Notes) = 0),'Old result contaminated clear');
      D.SingingFrame.SelectFile(P.FilePath); // 解放時に実行中の読込を回収。
    finally D.Free; end;
    F.TimelineBox.SelectSlot(1,SingingSlot); SelectTestPattern(F,P.ID);
    X := F.TimelineBox.HeaderWidth + 80; Y := F.TimelineBox.TrackRowTop(0) + 20;
    F.TimelineBox.OnDragOver(F.TimelineBox,F.PatternList,X,Y,dsDragMove,Accept);
    Check(not Accept and (Pos('受け入れません',F.StatusLabel.Caption) > 0),'Incompatible singing drop not rejected/reason missing');
    Y := F.TimelineBox.SlotRowTop(1,SingingSlot) + 20;
    F.TimelineBox.OnDragOver(F.TimelineBox,F.PatternList,X,Y,dsDragMove,Accept); Check(Accept,'Compatible singing rejected');
    F.TimelineBox.OnDragDrop(F.TimelineBox,F.PatternList,X,Y);
    Check(Length(F.Document.TrackAt(1).Slots[SingingSlot].Clips) = 1,'D&D did not create singing placement');
    F.TimelineBox.SelectSlot(0,AudioSlot); SelectTestPattern(F,F.Document.PatternAt(0).ID);
    Y := F.TimelineBox.SlotRowTop(0,AudioSlot)+20;
    F.TimelineBox.OnDragDrop(F.TimelineBox,F.PatternList,X,Y);
    F.TimelineBox.OnDragDrop(F.TimelineBox,F.PatternList,X + 200,Y);
    Check(Length(F.Document.TrackAt(0).Clips) = 2,'Repeated audio D&D failed');
    ID := F.Document.TrackAt(0).Clips[0].ID;
    TViewAccess(F.TimelineBox).SelectAt(X + 5,Y);
    F.ArrangementMenu.OnPopup(F.ArrangementMenu);
    StartDriver(Driver,'placement',''); F.ArrangementMenu.Items[4].Click;
    Check(Driver.Seen and (F.Document.TrackAt(0).Clips[0].ID = ID) and
      SameValue(F.Document.TrackAt(0).Clips[0].StartSeconds,3.5),'Placement setting changed/lost ID');
    F.TimelineBox.OnClipMove(0,0,0,4.5);
    Check(SameValue(F.Document.TrackAt(0).Clips[0].StartSeconds,4.5),'Clip move handler');
    X := F.TimelineBox.HeaderWidth + 185;
    TViewAccess(F.TimelineBox).SelectAt(X,Y);
    StartDriver(Driver,'placement','');
    F.TimelineBox.Perform(WM_LBUTTONDBLCLK,MK_LBUTTON,LPARAM((Y shl 16) or X));
    Check(Driver.Seen and not TViewAccess(F.TimelineBox).MouseCapture,'Double click left a drag capture after modal settings');
    F.TimelineBox.OnClipMove(0,0,0,4.5);
    TViewAccess(F.TimelineBox).WheelAt(F.TimelineBox.HeaderWidth,10,120,[]);
    Check(F.TimelineBox.SecondsAtPoint(F.TimelineBox.HeaderWidth + 200) < 5,'Mouse wheel did not zoom time');
    F.TimelineBox.SetZoom(40);
    // ヘッダーだけを持つ合成PSD。画素まで検証したと表示しない。
    SetLength(Header,38); Header[0] := Ord('8'); Header[1] := Ord('B'); Header[2] := Ord('P'); Header[3] := Ord('S');
    Header[5] := 1; Header[13] := 4; Header[17] := 64; Header[21] := 64; Header[23] := 8; Header[25] := 3;
    TFile.WriteAllBytes(TPath.Combine(Root,'header-only.psd'),Header);
    // The legacy direct-path editor remains available for an existing path.
    F.Document.UpdateTrack(1,'旧参照PSD','#C78AE8',TPath.Combine(Root,'header-only.psd'));
    Check(F.Document.TrySave(Text,ErrorText),ErrorText); F.LoadDocument(Text); F.TimelineBox.SelectSlot(1,SingingSlot);
    TViewAccess(F.TimelineBox).SelectAt(20,F.TimelineBox.TrackRowTop(1)+20);
    F.ArrangementMenu.OnPopup(F.ArrangementMenu);
    StartDriver(Driver,'track',TPath.Combine(Root,'header-only.psd')); F.ArrangementMenu.Items[2].Click;
    Check(Driver.Seen and (F.Document.TrackAt(1).Name = '歌唱者PSD'),'Track settings not persisted');
    D := TMusicStudioPatternSettings.Create(F);
    try D.SilentVisualMode := True; D.LoadTrack(F.Document.TrackAt(1)); Capture(D,TPath.Combine(Root,'psd-track-settings.png')); finally D.Free; end;
    Capture(F,TPath.Combine(Root,'editor-arrangement.png'));
    F.ClientWidth := 1000; F.ClientHeight := 562;
    Capture(F,TPath.Combine(Root,'arrangement-minimum.png'));
    Check(F.TimelineBox.RowHeight > 40,'Track rows collapsed');
    Check(F.Document.TrySave(Text,ErrorText),ErrorText);
    TFile.WriteAllText(TPath.Combine(Root,'editor-operable.json'),Text,TEncoding.UTF8);
    F.LoadDocument(Text);
    Check((F.Document.TrackCount = 2) and (Length(F.Document.TrackAt(0).Clips) = 2) and
      (F.Document.TrackAt(0).Clips[0].ID = ID),'GUI arrangement reload');
    F.TimelineBox.SelectSlot(0,AudioSlot); SelectTestPattern(F,F.Document.PatternAt(0).ID); F.DeleteButton.Click;
    Check(F.Document.PatternCount = 2,'Used source pattern removed');
    TViewAccess(F.TimelineBox).SelectAt(F.TimelineBox.HeaderWidth + 185,F.TimelineBox.SlotRowTop(0,0)+20);
    F.ArrangementMenu.OnPopup(F.ArrangementMenu); F.ArrangementMenu.Items[5].Click;
    Check(Length(F.Document.TrackAt(0).Clips) = 1,'Clip menu delete failed');
    TViewAccess(F.TimelineBox).SelectAt(20,F.TimelineBox.RulerHeight + 20);
    StartDriver(Driver,'delete-track',''); F.ArrangementMenu.Items[3].Click;
    Check(Driver.Seen and (F.Document.TrackCount = 1) and (F.Document.PatternCount = 2),'Track delete removed source patterns');
    // 保存上限で新パターンを登録できなくても未知属性と現文書をそのまま保つ。
    F.LoadDocument(MUSIC_STUDIO_DEFAULT_JSON); F.Document.AddTrack('audio');
    Check(F.Document.TrySave(Text,ErrorText),ErrorText);
    Text := Copy(Text,1,Length(Text)-1) + ',"padding":"' + StringOfChar('x',32720-Length(Text)-13) + '"}';
    F.LoadDocument(Text); F.AddButton.Click;
    Check(F.Document.PatternCount = 0,'Oversized mutation was kept');
    Check(F.Document.TrySave(ErrorText,ID) and (ErrorText = Text),'Rejected mutation changed original document');
    F.LoadDocument('{"schemaVersion":1,"previewAudio":null,"materials":[],"characters":[],"tracks":[],"patterns":'+
      '[{"id":"future-id","kind":"future","name":"未対応素材","color":"#88AAFF","keep":"unchanged"}]}');
    Check((F.PatternList.Count=0) and not F.EditButton.Enabled and not F.DeleteButton.Enabled,'Future kind exposed as a supported editor');
    F.DeleteButton.OnClick(F.DeleteButton);
    Check((F.Document.PatternCount = 1) and (Pos('unchanged',F.JSONMemo.Text) > 0),'Future data changed');
    F.CancelButtonClick(nil);
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'non-audio GUI allocated output or decoded sound');
  finally Application.OnException := nil; Driver.Timer.Free; Driver.Free; F.Free; end;
  Writeln('GUI_SINGING_CANCEL_REOPEN_STALE_RESIZE_DND_REASONS_PLACEMENTS_TRACK_MENUS_RELOAD_OK');
end;
end.
