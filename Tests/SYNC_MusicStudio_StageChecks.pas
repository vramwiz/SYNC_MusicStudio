unit SYNC_MusicStudio_StageChecks;
// 仮想ステージ/列選択/並替/非表示/口の縮小/カスタム表情を合成素材だけで確認する。
interface
procedure RunStageChecks(const Root: string; const PluginPath: string = '');
implementation
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.IOUtils, System.Math,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_PsdTransform, SYNC_MusicStudio_VideoRenderer, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_SmallSlotEditor, SYNC_MusicStudio_ArtLayerName;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('STAGE: '+Text); end;
type TStageDriver = class
  Timer: TTimer;
  UI: TFormMusicStudioSettings;
  Reply: Integer;
  Done,Custom: Boolean;
  Seen,Failure: string;
  function Confirm(const Text: string): Boolean;
  procedure Tick(Sender: TObject);
end;
function TStageDriver.Confirm(const Text: string): Boolean;
begin Seen := Text; Done := True; Result := Reply=mrYes; end;
procedure TStageDriver.Tick(Sender: TObject);
var I: Integer; F: TForm; D: TMusicStudioPatternSettings; L: TMusicStudioLayerInfo;
begin
  try
    for I := 0 to Screen.FormCount-1 do begin
      F := Screen.Forms[I]; if F=UI then Continue;
      if Custom and (F is TMusicStudioPatternSettings) then begin
        D := TMusicStudioPatternSettings(F); if D.LayersFrame=nil then Continue;
        D.LayersFrame.PollResults; if D.LayersFrame.IsLoading then Exit;
        for L in D.LayersFrame.Document.Layers do begin
          if ParseLayerName(L.Name).DisplayName='笑い目' then Check(D.LayersFrame.SetLayerVisibility(L.Key,True),'custom visibility click');
          if ParseLayerName(L.Name).DisplayName='別口' then Check(D.LayersFrame.SetLayerVisibility(L.Key,True),'custom mouth branch');
          if ParseLayerName(L.Name).DisplayName='口' then Check(D.LayersFrame.SetLayerVisibility(L.Key,False),'hide original mouth branch');
        end;
        D.NameEdit.Text := '目を変更'; Timer.Enabled := False; Done := True; D.ModalResult := mrOK; Exit;
      end;

    end;
  except on E: Exception do begin Failure := E.Message; Timer.Enabled := False;
    for I := 0 to Screen.FormCount-1 do if Screen.Forms[I]<>UI then Screen.Forms[I].ModalResult := mrCancel;
  end; end;
end;
procedure Fixture(const Path: string; Red: Boolean; MouthNames: Boolean);
var Art: TArtDocument; Body,Group,Layer,Choice: TArtLayer; I,J: Integer; Name: string;
  procedure Pixels(L: TArtLayer; R,G,B: Byte);
  var K: Integer;
  begin SetLength(L.Pixels,L.Bounds.Width*L.Bounds.Height*4); for K := 0 to Length(L.Pixels) div 4-1 do begin
    L.Pixels[K*4] := R; L.Pixels[K*4+1] := G; L.Pixels[K*4+2] := B; L.Pixels[K*4+3] := 255;
  end; end;
begin
  Art := TArtDocument.Create;
  try
    Layer := Art.AddLayer(alkGroup,'演奏属性:ドラム',TArtBounds.Create(0,0,0,0)); Layer.Visible := False;
    Art.Width := 64; Art.Height := 64;
    Body := Art.AddLayer(alkImage,'身体',TArtBounds.Create(28,28,36,36));
    if Red then Pixels(Body,220,30,20) else Pixels(Body,20,30,220);
    Layer := Art.AddLayer(alkImage,'*笑い目',TArtBounds.Create(8,8,16,16)); Pixels(Layer,20,220,30); Layer.Visible := False;
    Group := Art.AddLayer(alkGroup,'口',TArtBounds.Create(0,0,0,0));
    for I := 1 to 6 do begin
      if MouthNames then Name := Copy('あいうえおん',I,1) else Name := '口候補'+IntToStr(I);
      Layer := Art.AddLayer(alkImage,'*'+Name,TArtBounds.Create(28,20,36,28),Group); Pixels(Layer,40,140,200);
      Layer.Visible := I=1;
    end;
    if MouthNames then begin
      Group := Art.AddLayer(alkGroup,'別口',TArtBounds.Create(0,0,0,0)); Group.Visible := False;
      for I := 1 to 6 do begin
        Layer := Art.AddLayer(alkImage,'*'+Copy('あいうえおん',I,1),TArtBounds.Create(28,20,36,28),Group);
        Pixels(Layer,230,180,10); Layer.Visible := I=1;
      end;
    end;
    Group := Art.AddLayer(alkGroup,'右手',TArtBounds.Create(0,0,0,0));
    for I := 0 to 1 do begin
      Choice := Art.AddLayer(alkGroup,'候補'+IntToStr(I),TArtBounds.Create(0,0,0,0),Group);
      for J := 0 to 2 do begin Layer := Art.AddLayer(alkImage,'*'+IntToStr(J),TArtBounds.Create(40,28,44,32),Choice);
        Pixels(Layer,50,60,80); Layer.Visible := (I=0) and (J=0); end;
    end;
    WriteNewPsd(Art,Path,pcRaw);
  finally Art.Free; end;
end;
var SDKPixels: TMusicStudioVideoPixels;
procedure SDKSetImage(Buffer: PPIXEL_RGBA; Width,Height: Integer); cdecl;
begin SetLength(SDKPixels,Width*Height); Move(Buffer^,SDKPixels[0],Length(SDKPixels)*SizeOf(TPIXEL_RGBA)); end;
procedure SDKStage(const PluginPath,PSD: string);
type TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
     TItems = array[0..5] of Pointer; PItems = ^TItems;
var Module: HMODULE; GetTable: TGetTable; Table: PFILTER_PLUGIN_TABLE; Items: PItems;
  Doc: TMusicStudioDocument; Text,Error: string; Obj: TOBJECT_INFO; Scene: TSCENE_INFO;
  Video: TFILTER_PROC_VIDEO; Data: Pointer; SavedJSON: PWideChar; OldX,OldY,OldScale: Double; T: TMusicStudioPsdTransform;
begin
  Module := LoadLibrary(PChar(PluginPath)); Check(Module<>0,'SDK DLL load'); Data := nil; SavedJSON := nil; Table := nil; Items := nil; OldX := 0; OldY := 0; OldScale := 100;
  Doc := TMusicStudioDocument.Create;
  try
    GetTable := TGetTable(GetProcAddress(Module,'GetFilterPluginTable')); Check(Assigned(GetTable),'SDK entry'); Table := GetTable(); Items := PItems(Table.Items);
    Check(Items^[5]=nil,'SDK item terminator'); SavedJSON := PFILTER_ITEM_STRING(Items^[1]).Value;
    OldX := PFILTER_ITEM_TRACK(Items^[2]).Value; OldY := PFILTER_ITEM_TRACK(Items^[3]).Value; OldScale := PFILTER_ITEM_TRACK(Items^[4]).Value;
    Check(Doc.TryLoad('',Error),Error); Doc.AddTrack('performer'); Doc.UpdateTrack(0,'SDK','#90C4E0',PSD);
    T := Default(TMusicStudioPsdTransform); T.HasStage := True; T.Scale := 1; Doc.UpdatePsdTransform(0,T); Check(Doc.TrySave(Text,Error),Error);
    PFILTER_ITEM_STRING(Items^[1]).Value := PWideChar(Text); PFILTER_ITEM_TRACK(Items^[2]).Value := 0; PFILTER_ITEM_TRACK(Items^[3]).Value := 0; PFILTER_ITEM_TRACK(Items^[4]).Value := 100;
    Obj := Default(TOBJECT_INFO); Scene := Default(TSCENE_INFO); Video := Default(TFILTER_PROC_VIDEO);
    Obj.Width := 64; Obj.Height := 64; Scene.Width := 64; Scene.Height := 64; Obj.Time := 0.6;
    Video.Object_ := @Obj; Video.Scene := @Scene; Video.SetImageData := SDKSetImage; Data := Table.Func_Create(1); Video.UserData := Data;
    SDKPixels := nil; Table.Func_Proc_Video(@Video); Check(Length(SDKPixels)=4096,'SDK did not publish'); Check(SDKPixels[32*64+32].R=220,'SDK native stage');
    PFILTER_ITEM_TRACK(Items^[2]).Value := 16; SDKPixels := nil; Table.Func_Proc_Video(@Video); Check(SDKPixels[32*64+48].R=220,'SDK X trackbar');
    PFILTER_ITEM_TRACK(Items^[2]).Value := 0; PFILTER_ITEM_TRACK(Items^[3]).Value := 16; Table.Func_Proc_Video(@Video); Check(SDKPixels[48*64+32].R=220,'SDK Y trackbar');
    PFILTER_ITEM_TRACK(Items^[3]).Value := 0; PFILTER_ITEM_TRACK(Items^[4]).Value := 50; Table.Func_Proc_Video(@Video); Check(SDKPixels[32*64+32].R=220,'SDK scale trackbar');
    PFILTER_ITEM_TRACK(Items^[2]).Value := 16; Table.Func_Proc_Video(@Video); Check(SDKPixels[32*64+48].R=220,'SDK X must remain output pixels after scaling');
    Writeln('STAGE_SDK_X_Y_SCALE_NO_AUDIO_OK');
  finally
    if Data<>nil then Table.Func_Destroy(1,Data);
    if SavedJSON<>nil then begin PFILTER_ITEM_STRING(Items^[1]).Value := SavedJSON; PFILTER_ITEM_TRACK(Items^[2]).Value := OldX; PFILTER_ITEM_TRACK(Items^[3]).Value := OldY; PFILTER_ITEM_TRACK(Items^[4]).Value := OldScale; end;
    Doc.Free; FreeLibrary(Module); SDKPixels := nil;
  end;
end;
procedure RunStageChecks(const Root,PluginPath: string);
var UI: TFormMusicStudioSettings; D,Manual: TMusicStudioLayerDocument; Config: TJSONObject;
  Profile: TMusicStudioPerformerProfile; A,B: TMusicStudioPsdAsset; Duplicate,Rejected: Boolean;
  Error,Text,Before,After,Midi,HashHalf,OrderID: string;
  T: TMusicStudioPsdTransform; P: TMusicStudioPattern; I,J,Track,Sing,CustomSlot,Count,StartCount,Y,TargetY,Jobs: Integer;
  V,R: TRect; Deadline: UInt64; Native: TSize; Driver: TStageDriver; Video: TMusicStudioVideoSession;
  Pixels: TMusicStudioVideoPixels; Bitmap: TBitmap; PNG: TPngImage; Key: Word;
  function Slot(Index: Integer; const Kind: string): Integer;
  var N: Integer;
  begin for N := 0 to High(UI.Document.TrackAt(Index).Slots) do if UI.Document.TrackAt(Index).Slots[N].Kind=Kind then Exit(N);
    raise Exception.Create('missing slot '+Kind); end;
  function JSON: string;
  begin Check(UI.Document.TrySave(Result,Error),Error); end;
  procedure Reload;
  begin Text := JSON; UI.LoadDocument(Text); end;
  procedure Await;
  begin
    Deadline := GetTickCount64+6000;
    repeat Application.ProcessMessages; UI.TimelineBox.PollWaveforms; UI.Preview.SceneCache.PollResults; Sleep(2);
      Check(GetTickCount64<Deadline,'scene deadline');
    until (UI.Preview.SceneCache.ActiveLoadJobs=0) and (UI.Preview.SceneCache.ActiveRenderJobs=0);
  end;
  procedure AtTime(Seconds: Double);
  begin UI.Preview.Seek(Seconds); Await; end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin UI.TimelineBox.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure StageMouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin UI.Preview.Stage.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  function AlphaCount(Image: TBitmap; const Area: TRect): Integer;
  var X,Y: Integer; Row: PByte;
  begin Result := 0; for Y := Area.Top to Area.Bottom-1 do begin Row := Image.ScanLine[Y];
    for X := Area.Left to Area.Right-1 do if Row[X*4+3]>0 then Inc(Result); end;
  end;
  function MouthHash(Image: TBitmap): string;
  begin Result := IntToStr(AlphaCount(Image,Rect(28,20,36,28))); end;
  procedure Capture(Form: TForm; const Name: string);
    procedure Buttons(Parent: TWinControl);
    var I,Saved: Integer; C: TControl; Pt: TPoint;
    begin for I := 0 to Parent.ControlCount-1 do begin C := Parent.Controls[I]; if not C.Visible then Continue;
      if C is TButton then begin Pt := Form.ScreenToClient(C.ClientToScreen(Point(0,0))); Saved := SaveDC(Bitmap.Canvas.Handle);
        try SetViewportOrgEx(Bitmap.Canvas.Handle,Pt.X,Pt.Y,nil); TButton(C).Perform(WM_PRINTCLIENT,Bitmap.Canvas.Handle,PRF_CLIENT);
        finally RestoreDC(Bitmap.Canvas.Handle,Saved); end;
      end else if C is TWinControl then Buttons(TWinControl(C));
    end; end;
  begin Bitmap := TBitmap.Create; PNG := TPngImage.Create;
    try Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); Form.PaintTo(Bitmap.Canvas,0,0); Buttons(Form); PNG.Assign(Bitmap); PNG.SaveToFile(TPath.Combine(Root,Name));
    finally PNG.Free; Bitmap.Free; end;
  end;
  procedure DeleteWithReply(Reply: Integer; const ScopeWord: string);
  begin
    Driver.Reply := Reply; Driver.Custom := False; Driver.Done := False; Driver.Seen := ''; Driver.Timer.Enabled := False;
    Key := VK_DELETE; UI.TimelineBox.Perform(WM_KEYDOWN,Key,0);
    Check(Driver.Done and (Driver.Failure='') and (Pos(ScopeWord,Driver.Seen)>0),'delete scope '+ScopeWord+' '+Driver.Failure+' '+Driver.Seen);
  end;
begin
  T := Default(TMusicStudioPsdTransform); R := MusicStudioStageRect(T,64,64,192,108,Rect(0,0,192,108));
  Check((R.Width=64) and (R.CenterPoint.X=96),'implicit position must be native and independent of order');
  ForceDirectories(Root); Fixture(TPath.Combine(Root,'red.psd'),True,True); Fixture(TPath.Combine(Root,'blue.psd'),False,True);
  Fixture(TPath.Combine(Root,'manual.psd'),True,False);
  UI := TFormMusicStudioSettings.Create(nil); D := TMusicStudioLayerDocument.Create; Manual := TMusicStudioLayerDocument.Create;
  Driver := TStageDriver.Create; Driver.UI := UI; Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Driver.Timer.Interval := 30; Driver.Timer.OnTimer := Driver.Tick; UI.OnConfirmDelete := Driver.Confirm;
  Video := nil; Config := nil;
  try
    Check(D.LoadFile(TPath.Combine(Root,'red.psd')),D.LastError); Config := ParseMusicStudioPsdConfig('{}');
    Profile := MusicStudioPerformerProfile(D,Config.ToJSON); Check(MusicStudioCanSing(D,Config),'automatic six vowels');
    Check(Manual.LoadFile(TPath.Combine(Root,'manual.psd')),Manual.LastError); Check(not MusicStudioCanSing(Manual,Config),'mouth parent alone accepted');
    J := 1; for I := 0 to High(Manual.Layers) do if not Manual.Layers[I].IsGroup and (Pos('口候補',Manual.Layers[I].Name)>0) then begin MusicStudioAssignMouth(Config,J,Manual.Layers[I].Key); Inc(J); end;
    Check(J=7,'manual fixture'); Check(MusicStudioCanSing(Manual,Config),'manual six vowels'); MusicStudioAssignMouth(Config,6,'');
    Check(not MusicStudioCanSing(Manual,Config),'incomplete manual vowels'); FreeAndNil(Config);
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Check(UI.SharedLibrary.TryImport(TPath.Combine(Root,'red.psd'),'赤','#A06060',A,Duplicate,Error),Error);
    Check(UI.SharedLibrary.TryImport(TPath.Combine(Root,'blue.psd'),'青','#6060A0',B,Duplicate,Error),Error);
    UI.Document.AddTrack('audio');
    for I := 0 to 4 do begin
      Track := UI.Document.AddTrack('performer'); Check(UI.Document.TrackAt(Track).Name='トラック'+IntToStr(Track+1),'initial track caption');
      if I=1 then UI.Document.AssignPsd(Track,B.ID) else UI.Document.AssignPsd(Track,A.ID);
      UI.Document.SetPerformer(Track,'drums',Profile.Slots,True,Profile.SelectionsJSON);
      T := Default(TMusicStudioPsdTransform); T.HasStage := True; T.Scale := 10; T.StageX := (I-2)*1100;
      if I<2 then T.StageX := 0;
      UI.Document.UpdatePsdTransform(Track,T);
    end;
    Sing := Slot(1,'singing'); CustomSlot := UI.Document.AddSlot(1,'customExpression');
    Rejected := False; try UI.Document.AddSlot(1,'face'); except Rejected := True; end; Check(Rejected,'unsupported slot accepted');
    Reload; UI.ClientWidth := 1440; UI.ClientHeight := 1000; UI.Show; Application.ProcessMessages; Await;
    Check(UI.Preview.Parent.Parent=UI.WorkPanel,'preview not above full workspace');
    Check(UI.TimelineBox.TrackColumnWidth<UI.TimelineBox.HeaderWidth,'fixed slot column missing');
    Check(UI.TimelineBox.SlotHeight('singing')=3*UI.TimelineBox.SlotHeight('emotion'),'large rows are not triple');
    Count := UI.TimelineBox.TrackRowTop(1); UI.TimelineBox.ToggleTrack(0);
    Check(UI.TimelineBox.TrackRowTop(1)=Count,'single audio expansion grew'); UI.TimelineBox.ToggleTrack(1);
    Check(UI.TimelineBox.SlotRowTop(1,Sing)=UI.TimelineBox.TrackRowTop(1),'empty header row remains');
    Check(UI.Preview.ImageCount=5,'five PSDs not loaded');
    UI.TimelineBox.SelectTrack(1); Check(UI.Preview.PlacementEditor.SelectedTrack=1,'track selection did not select character');
    Check(UI.Preview.CharacterBounds(1,V,R),'character bounds'); Native := UI.Preview.SceneCache.NativeSizeForTrack(1); Check(Native.cx=64,'native size');
    Before := JSON; T := UI.Document.TrackAt(1).PsdTransform;
    StageMouse(WM_MOUSEMOVE,R.CenterPoint.X,R.CenterPoint.Y); Check(UI.Preview.Stage.Cursor=crSizeAll,'move cursor');
    StageMouse(WM_LBUTTONDOWN,R.CenterPoint.X,R.CenterPoint.Y,MK_LBUTTON); StageMouse(WM_MOUSEMOVE,R.CenterPoint.X+18,R.CenterPoint.Y+6,MK_LBUTTON);
    Check(JSON=Before,'draft move changed document'); StageMouse(WM_LBUTTONUP,R.CenterPoint.X+18,R.CenterPoint.Y+6);
    Check((UI.Document.TrackAt(1).PsdTransform.StageX>T.StageX) and (UI.Document.TrackAt(1).PsdTransform.Scale=T.Scale),'stage movement or scale drift');
    UI.UndoEdit; Check(JSON=Before,'placement undo'); Await; UI.TimelineBox.SelectTrack(1); Check(UI.Preview.CharacterBounds(1,V,R),'bounds after undo');
    StageMouse(WM_MOUSEMOVE,R.Right,R.Bottom); Check(UI.Preview.Stage.Cursor=crSizeNWSE,'corner cursor');
    StageMouse(WM_LBUTTONDOWN,R.Right,R.Bottom,MK_LBUTTON); StageMouse(WM_MOUSEMOVE,R.Right+12,R.Bottom+12,MK_LBUTTON); StageMouse(WM_LBUTTONUP,R.Right+12,R.Bottom+12);
    Check(UI.Document.TrackAt(1).PsdTransform.Scale>T.Scale,'corner resize'); UI.UndoEdit; Await;
    UI.Preview.PlacementEditor.Flip(True); Check(UI.Document.TrackAt(1).PsdTransform.FlipX,'flip X'); UI.Preview.PlacementEditor.Flip(False); Check(UI.Document.TrackAt(1).PsdTransform.FlipY,'flip Y'); UI.UndoEdit; UI.UndoEdit; Await;
    Before := JSON; UI.Preview.VisibilityCommand(1,1); Await; Check(UI.Preview.ImageCount=1,'solo');
    Jobs := UI.Preview.SceneCache.RenderCount; AtTime(0.3); Check(UI.Preview.SceneCache.RenderCount=Jobs,'hidden/static tracks evaluated');
    Check(JSON=Before,'preview visibility serialized'); UI.Preview.VisibilityCommand(1,2); Await; Check(UI.Preview.ImageCount=5,'show all');
    Writeln('STAGE_PLACEMENT_VISIBILITY_OK'); Flush(Output);
    // Column-specific menus and delete targets are separate even when PSD context is selected.
    Y := UI.TimelineBox.TrackRowTop(1)+12; Mouse(WM_RBUTTONDOWN,100,Y); Mouse(WM_RBUTTONUP,100,Y);
    UI.ArrangementMenu.OnPopup(UI.ArrangementMenu); Check(UI.TimelineBox.SelectionScope=mssTrack,'track scope');
    Check(UI.ArrangementMenu.Items[2].Visible and not UI.ArrangementMenu.Items[9].Visible,'track menu');
    Before := JSON; DeleteWithReply(mrNo,'トラック'); Check(JSON=Before,'cancel track deletion');
    Y := UI.TimelineBox.SlotRowTop(1,Sing)+12; Mouse(WM_RBUTTONDOWN,UI.TimelineBox.TrackColumnWidth+10,Y); Mouse(WM_RBUTTONUP,UI.TimelineBox.TrackColumnWidth+10,Y);
    UI.ArrangementMenu.OnPopup(UI.ArrangementMenu); Check(UI.TimelineBox.SelectionScope=mssSlot,'slot scope');
    Check(not UI.ArrangementMenu.Items[2].Visible and UI.ArrangementMenu.Items[9].Visible,'slot menu');
    StartCount := Length(UI.Document.TrackAt(1).Slots); DeleteWithReply(mrYes,'スロット'); Check(Length(UI.Document.TrackAt(1).Slots)=StartCount-1,'slot delete'); UI.UndoEdit; Check(JSON=Before,'slot delete undo'); Await;
    UI.TimelineBox.SelectTrack(1); StartCount := UI.Document.TrackCount; DeleteWithReply(mrYes,'トラック'); Check(UI.Document.TrackCount=StartCount-1,'track delete'); UI.UndoEdit; Check(JSON=Before,'track delete undo'); Await;
    Writeln('STAGE_DELETE_SCOPES_OK'); Flush(Output);
    // Insertion marker is provisional, then the complete track moves as one undo step.
    OrderID := UI.Document.TrackAt(1).ID; Before := JSON; Y := UI.TimelineBox.TrackRowTop(1)+10; TargetY := UI.TimelineBox.TrackRowTop(4)+3;
    Mouse(WM_LBUTTONDOWN,110,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,110,TargetY,MK_LBUTTON);
    Check((JSON=Before) and (UI.TimelineBox.TrackInsertIndex=4),'track insertion preview'); Capture(UI,'track-insertion.png');
    Mouse(WM_LBUTTONUP,110,TargetY); Check(UI.Document.TrackAt(3).ID=OrderID,'track reorder'); UI.UndoEdit; Check(JSON=Before,'track reorder undo'); Await;
    Writeln('STAGE_REORDER_OK'); Flush(Output);
    // Topmost track wins in output. Global controls transform only the produced overlay.
    UI.Preview.VisibilityCommand(2,1); Await;
    Video := TMusicStudioVideoSession.Create(UI.LibraryRoot); Check(Video.Render(JSON,0,192,108,Pixels,Error,0,0,0.1),Error);
    Check(Pixels[54*192+96].R>Pixels[54*192+96].B,'top track is not front / solo leaked into output'); UI.Preview.VisibilityCommand(2,2); Await;
    UI.Document.ReorderTrack(1,2); Check(Video.Render(JSON,0,192,108,Pixels,Error,0,0,0.1),Error);
    Check(Pixels[54*192+96].B>Pixels[54*192+96].R,'reorder did not change output order'); UI.Document.ReorderTrack(2,1);
    Check(Video.Render(JSON,0,192,108,Pixels,Error,50,0,0.1),Error); Check(Pixels[54*192+146].R>Pixels[54*192+146].B,'output X');
    Writeln('STAGE_OUTPUT_OK'); Flush(Output);
    // Mouth phase restarts for consecutive identical vowels, at 1/2,3/4,1 sizes.
    Midi := TPath.Combine(Root,'same-vowels.mid');
    TFile.WriteAllBytes(Midi,TBytes.Create($4D,$54,$68,$64,0,0,0,6,0,0,0,1,1,$E0,$4D,$54,$72,$6B,0,0,0,32,
      0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,$2F,0));
    J := UI.Document.AddSinging; P := UI.Document.PatternAt(J); P.FilePath := Midi; P.SourceTrack := 0; P.Duration := 2; UI.Document.UpdatePattern(P);
    Check(UI.Document.AddPlacement(1,Sing,P.ID,0,2,Error),Error); Reload; Await;
    AtTime(0.1); HashHalf := MouthHash(UI.Preview.SceneCache.ImageForTrack(1)); Check(HashHalf='16','half mouth '+HashHalf);
    UI.Preview.SetTrackVisible(1,False); Await; Jobs := UI.Preview.SceneCache.RenderCount;
    AtTime(0.3); Check(UI.Preview.SceneCache.RenderCount=Jobs,'hidden singing still rendered');
    UI.Preview.SetTrackVisible(1,True); Await;
    Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='36','three quarter mouth / show current position');
    AtTime(0.6); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','normal mouth');
    AtTime(1.1); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))=HashHalf,'same vowel did not restart');
    Writeln('STAGE_MOUTH_OK'); Flush(Output);
    // Dedicated custom slot works without the fixed expression row; snapshot survives reload/undo.
    UI.TimelineBox.ToggleTrack(1); UI.TimelineBox.SelectSlot(1,CustomSlot); Before := JSON;
    Driver.Custom := True; Driver.Done := False; Driver.Timer.Enabled := True;
    UI.SmallSlotEditor.EditCustomAt(1,CustomSlot,-1,0);
    Check(Driver.Done and (Driver.Failure=''),'custom modal '+Driver.Failure); Check(JSON<>Before,'custom capture not saved');
    AtTime(0.6); Check(AlphaCount(UI.Preview.SceneCache.ImageForTrack(1),Rect(8,8,16,16))=64,'custom visibility not drawn');
    Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','custom froze singing mouth');
    Check((ColorToRGB(UI.Preview.SceneCache.ImageForTrack(1).Canvas.Pixels[32,24]) and $FF)=230,'automatic mouth did not follow custom expression branch');
    AtTime(0.1); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='16','custom froze mouth scale');
    After := JSON; UI.UndoEdit; Check(JSON=Before,'custom edit undo'); UI.RedoEdit; Check(JSON=After,'custom redo'); Await;
    UI.TimelineBox.SelectSlot(1,0); UI.PatternList.ItemIndex := -1;
    for I := 0 to UI.PatternList.Count-1 do if UI.PatternList.Items[I]=A.Name then UI.PatternList.ItemIndex := I;
    Check(UI.DropSelectedLibraryAt(1,-1,0,Error),Error); Check(UI.Document.TrackAt(1).Name='red','PSD file name caption'); Await;
    UI.TimelineBox.SelectTrack(1); UI.Preview.SetOutputView(0,0,0.25); Capture(UI,'stage-editor.png');
    if PluginPath<>'' then SDKStage(PluginPath,TPath.Combine(Root,'red.psd'));
    TFile.WriteAllText(TPath.Combine(Root,'stage-project.json'),JSON,TEncoding.UTF8);
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'stage used audio');
    Writeln('STAGE_EDITOR_CAPABILITIES_COLUMNS_DELETE_REORDER_PLACEMENT_FIVE_PSD_SOLO_OUTPUT_CAMERA_MOUTH_CUSTOM_UNDO_OK');
  finally Config.Free; Video.Free; Driver.Timer.Free; Driver.Free; Manual.Free; D.Free; UI.Free; end;
end;
end.
