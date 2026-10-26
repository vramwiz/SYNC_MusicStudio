unit SYNC_MusicStudio_StageChecks;
// 仮想ステージ/列選択/並替/非表示/口の縮小/カスタム表情を合成素材だけで確認する。
interface
procedure RunStageChecks(const Root: string; const PluginPath: string = ''; MouthOnly: Boolean = False);
// Rootに隔離素材を生成し、直接操作/同期/映像を無音検証する。native popupはPrepareへ差し替える。
procedure RunAnimationSlotChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.IOUtils, System.Math,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Menus,
  AviUtl2FilterTypes, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_PsdTransform, SYNC_MusicStudio_VideoRenderer, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_SmallSlotEditor, SYNC_MusicStudio_ArtLayerName, SYNC_MusicStudio_MotionData, SYNC_MusicStudio_AnimationSync;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('STAGE: '+Text); end;
type
  TAnimationMenuProbe = class
    Editor: TMusicStudioSmallSlotEditor;
    Calls: Integer;
    procedure Open(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
  end;
procedure TAnimationMenuProbe.Open(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint);
begin Inc(Calls); Check(Editor.Prepare(TrackIndex,SlotIndex,ClipIndex,Seconds),'animation click menu prepare'); end;
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
procedure RunStageChecks(const Root,PluginPath: string; MouthOnly: Boolean);
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
    if not MouthOnly then begin
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
    end;
    // Default stays full size. Enabled size decreases and resets at each identical vowel.
    Midi := TPath.Combine(Root,'same-vowels.mid');
    TFile.WriteAllBytes(Midi,TBytes.Create($4D,$54,$68,$64,0,0,0,6,0,0,0,1,1,$E0,$4D,$54,$72,$6B,0,0,0,32,
      0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,$2F,0));
    J := UI.Document.AddSinging; P := UI.Document.PatternAt(J); P.FilePath := Midi; P.SourceTrack := 0; P.Duration := 2; UI.Document.UpdatePattern(P);
    Check(UI.Document.AddPlacement(1,Sing,P.ID,0,2,Error),Error); Reload; Await;
    AtTime(0.1); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','default mouth not full size');
    AtTime(0.9); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','default mouth varies');
    Config := ParseMusicStudioPsdConfig(A.ConfigJSON); MusicStudioSetJsonBoolean(Config,'animateMouthSize',True);
    A.ConfigJSON := Config.ToJSON; FreeAndNil(Config); Check(UI.SharedLibrary.TrySave(A,Error),Error); Reload; Await;
    AtTime(0); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','start mouth');
    AtTime(0.25); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='49','quarter mouth');
    AtTime(0.5); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='36','mid mouth');
    AtTime(0.75); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='25','three quarter mouth');
    AtTime(0.999); HashHalf := MouthHash(UI.Preview.SceneCache.ImageForTrack(1)); Check(HashHalf='16','end half mouth '+HashHalf);
    AtTime(1); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','same vowel did not reset');
    AtTime(1.5); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='36','same vowel did not shrink');
    AtTime(0.25); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='49','reverse seek mouth');
    UI.Preview.SetTrackVisible(1,False); Await; Jobs := UI.Preview.SceneCache.RenderCount;
    AtTime(0.5); Check(UI.Preview.SceneCache.RenderCount=Jobs,'hidden singing still rendered');
    UI.Preview.SetTrackVisible(1,True); Await;
    Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='36','show current mouth');
    Writeln('STAGE_MOUTH_OK'); Flush(Output);
    // Dedicated custom slot works without the fixed expression row; snapshot survives reload/undo.
    UI.TimelineBox.ToggleTrack(1); UI.TimelineBox.SelectSlot(1,CustomSlot); Before := JSON;
    Driver.Custom := True; Driver.Done := False; Driver.Timer.Enabled := True;
    UI.SmallSlotEditor.EditCustomAt(1,CustomSlot,-1,0);
    Check(Driver.Done and (Driver.Failure=''),'custom modal '+Driver.Failure); Check(JSON<>Before,'custom capture not saved');
    AtTime(0.6); Check(AlphaCount(UI.Preview.SceneCache.ImageForTrack(1),Rect(8,8,16,16))=64,'custom visibility not drawn');
    Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='36','custom froze singing mouth');
    Check((ColorToRGB(UI.Preview.SceneCache.ImageForTrack(1).Canvas.Pixels[32,24]) and $FF)=230,'automatic mouth did not follow custom expression branch');
    AtTime(0.1); Check(MouthHash(UI.Preview.SceneCache.ImageForTrack(1))='64','custom froze mouth scale');
    After := JSON; UI.UndoEdit; Check(JSON=Before,'custom edit undo'); UI.RedoEdit; Check(JSON=After,'custom redo'); Await;
    UI.TimelineBox.SelectSlot(1,0); UI.PatternList.ItemIndex := -1;
    for I := 0 to UI.PatternList.Count-1 do if UI.PatternList.Items[I]=A.Name then UI.PatternList.ItemIndex := I;
    Check(UI.DropSelectedLibraryAt(1,-1,0,Error),Error); Check(UI.Document.TrackAt(1).Name='red','PSD file name caption'); Await;
    UI.TimelineBox.SelectTrack(1); UI.Preview.SetOutputView(0,0,0.25); Capture(UI,'stage-editor.png');
    if PluginPath<>'' then SDKStage(PluginPath,TPath.Combine(Root,'red.psd'));
    TFile.WriteAllText(TPath.Combine(Root,'stage-project.json'),JSON,TEncoding.UTF8);
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'stage used audio');
    if MouthOnly then Writeln('MOUTH_SIZE_DEFAULT_OFF_CONTINUOUS_RESTART_SEEK_VISIBILITY_CUSTOM_UNDO_NO_AUDIO_OK')
    else Writeln('STAGE_EDITOR_CAPABILITIES_COLUMNS_DELETE_REORDER_PLACEMENT_FIVE_PSD_SOLO_OUTPUT_CAMERA_MOUTH_CUSTOM_UNDO_OK');
  finally Config.Free; Video.Free; Driver.Timer.Free; Driver.Free; Manual.Free; D.Free; UI.Free; end;
end;
procedure RunAnimationSlotChecks(const Root: string);
var UI: TFormMusicStudioSettings; A: TMusicStudioPsdAsset; Motion: TMusicStudioMotionConfig;
  P: TMusicStudioPattern; G: TGUID; Dup,Rejected: Boolean; Error,Text,Midi,Before,After: string;
  Sing,Perf,ASing,APerf,ARhythm,Index,I,N,Jobs,PerformanceIndex,SingingIndex: Integer; Deadline: UInt64;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels;
  Probe: TAnimationMenuProbe; SavedMenu: TMusicStudioSmallMenuEvent;
  X1,X2,Y,Middle,RightX,BasePatterns: Integer; C: TMusicStudioPlacement; Start,Finish: Double; ClipID: string;
  AddParent: TMenuItem; Published,PreviousPublished,Quarter: Double; SawIntermediate: Boolean;
  PublishedCount,ChangedFrames: Integer; LastPixels,CurrentPixels: TBytes; Image: TBitmap; RowIndex: Integer;
  Transform: TMusicStudioMotionTransform; Phase: Double; Cues: TArray<TMusicStudioAnimationCue>;
  function JSON: string;
  begin Check(UI.Document.TrySave(Result,Error),Error); end;
  function Slot(const Kind: string): Integer;
  var J: Integer;
  begin for J := 0 to High(UI.Document.TrackAt(0).Slots) do if UI.Document.TrackAt(0).Slots[J].Kind=Kind then Exit(J);
    raise Exception.Create('missing animation source '+Kind); end;
  function XFor(Seconds: Double): Integer;
  var X: Integer;
  begin
    Result := UI.TimelineBox.HeaderWidth;
    for X := Result to UI.TimelineBox.ClientWidth-18 do
      if UI.TimelineBox.SecondsAtSlot(X,0,APerf)>=Seconds then Exit(X);
  end;
  procedure CaptureTimeline;
  var B: TBitmap; PNG: TPngImage; X,NormalY,AnimationY: Integer;
  begin
    UI.TimelineBox.SelectSlot(0,ARhythm);
    B := TBitmap.Create; PNG := TPngImage.Create;
    try
      B.SetSize(UI.TimelineBox.ClientWidth,UI.TimelineBox.ClientHeight);
      UI.TimelineBox.PaintTo(B.Canvas.Handle,0,0);
      X := UI.TimelineBox.HeaderWidth-5;
      NormalY := UI.TimelineBox.SlotRowTop(0,Perf)+12;
      AnimationY := UI.TimelineBox.SlotRowTop(0,ARhythm)+12;
      Check(ColorToRGB(B.Canvas.Pixels[X,NormalY])<>ColorToRGB(B.Canvas.Pixels[X,AnimationY]),'animation header color not distinct');
      PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'timeline-animation.png'));
    finally PNG.Free; B.Free; end;
  end;
  procedure Await;
  begin
    Deadline := GetTickCount64+10000;
    repeat Application.ProcessMessages; UI.TimelineBox.PollWaveforms; UI.Preview.SceneCache.PollResults; Sleep(2);
      Check(GetTickCount64<Deadline,'animation timeout');
    until (UI.Preview.SceneCache.ActiveLoadJobs=0) and (UI.Preview.SceneCache.ActiveRenderJobs=0) and
      (UI.TimelineBox.VisualCache.ActiveJobs=0);
  end;
  procedure Reload;
  begin Text := JSON; UI.LoadDocument(Text); Await; end;
  procedure AtTime(Seconds: Double; ExpectedPhase: Double; Active: Boolean = True);
  var Image,Expected: TBitmap; LayerDoc: TMusicStudioLayerDocument; Config,Overrides: TJSONObject; X,Y: Integer; Row: PByte;
  begin
    UI.Preview.Seek(Seconds); Await;
    Image := UI.Preview.SceneCache.ImageForTrack(0); Check(Image<>nil,'animation image');
    LayerDoc := TMusicStudioLayerDocument.Create; Expected := TBitmap.Create; Config := ParseMusicStudioPsdConfig('{}'); Overrides := nil;
    try
      Check(LayerDoc.LoadFile(A.FilePath),LayerDoc.LastError);
      Overrides := ResolveMusicStudioMouthConfig(LayerDoc,Config); Config.Free; Config := Overrides; Overrides := nil;
      Overrides := BuildMusicStudioPsdOverrides(LayerDoc,Config,1);
      Check(LayerDoc.Render(Expected,Overrides),LayerDoc.LastError);
      if Active then begin
        CalculateMusicStudioMotionTransform(Motion,ExpectedPhase,Transform);
        Image := TBitmap.Create;
        try RenderMusicStudioMotion(Expected,Image,Transform); Expected.Assign(Image); finally Image.Free; end;
      end;
      Image := UI.Preview.SceneCache.ImageForTrack(0);
      Check((Image.Width=Expected.Width) and (Image.Height=Expected.Height),'animation image size');
      for Y := 0 to Image.Height-1 do Check(CompareMem(Image.ScanLine[Y],Expected.ScanLine[Y],Image.Width*4),
        'animation pixels at '+FloatToStr(Seconds)+' phase '+FloatToStr(ExpectedPhase));
      Check(Video.Render(JSON,Seconds,64,64,Pixels,Error),Error);
      Check(Length(Pixels)=64*64,'animation video size');
      for Y := 0 to 63 do begin Row := Image.ScanLine[Y];
        for X := 0 to 63 do Check((Pixels[Y*64+X].R=Row[X*4+2]) and (Pixels[Y*64+X].G=Row[X*4+1]) and
          (Pixels[Y*64+X].B=Row[X*4]) and (Pixels[Y*64+X].A=Row[X*4+3]),'animation preview/video mismatch');
      end;
    finally Overrides.Free; Config.Free; Expected.Free; LayerDoc.Free; end;
  end;
  procedure InstrumentAt(Seconds,ExpectedPhase: Double; Active: Boolean);
  var Saved: string; Baseline,Expected,Actual: TBitmap; X,Y: Integer; Row: PByte;
  begin
    Saved := JSON; Baseline := TBitmap.Create; Expected := TBitmap.Create; Actual := TBitmap.Create;
    try
      UI.Preview.Seek(Seconds); Await; Actual.Assign(UI.Preview.SceneCache.ImageForTrack(0));
      Check(Video.Render(JSON,Seconds,64,64,Pixels,Error),Error);
      for Y := 0 to 63 do begin Row := Actual.ScanLine[Y];
        for X := 0 to 63 do Check((Pixels[Y*64+X].R=Row[X*4+2]) and (Pixels[Y*64+X].G=Row[X*4+1]) and
          (Pixels[Y*64+X].B=Row[X*4]) and (Pixels[Y*64+X].A=Row[X*4+3]),'local/common animation preview/video mismatch');
      end;
      UI.Document.RemovePlacement(0,APerf,0); Reload; UI.Preview.Seek(Seconds); Await;
      Baseline.Assign(UI.Preview.SceneCache.ImageForTrack(0));
      if Active then begin CalculateMusicStudioMotionTransform(Motion,ExpectedPhase,Transform); RenderMusicStudioMotion(Baseline,Expected,Transform); end
      else Expected.Assign(Baseline);
      for Y := 0 to Actual.Height-1 do Check(CompareMem(Actual.ScanLine[Y],Expected.ScanLine[Y],Actual.Width*4),'common instrument sync phase/rest');
      Check(UI.Document.TryLoad(Saved,Error),Error); Reload;
    finally Actual.Free; Expected.Free; Baseline.Free; end;
  end;
  procedure Place(AnimationSlot: Integer; Start,Len: Double);
  begin Check(UI.Document.AddPlacement(0,AnimationSlot,P.ID,Start,Len,Error),Error); Reload; end;
  procedure RemoveAnimation(AnimationSlot: Integer);
  begin UI.Document.RemovePlacement(0,AnimationSlot,0); Reload; end;
begin
  ForceDirectories(Root); Fixture(TPath.Combine(Root,'animation.psd'),True,True);
  UI := TFormMusicStudioSettings.Create(nil); Motion := TMusicStudioMotionConfig.Create; Video := nil; Probe := nil;
  try
    UI.ClientWidth := 1440; UI.ClientHeight := 1000;
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Video := TMusicStudioVideoSession.Create(UI.LibraryRoot);
    UI.Document.AddTrack('performer'); ARhythm := UI.Document.AddSlot(0,'animationRhythm');
    Before := JSON; Rejected := False; try UI.Document.AddSlot(0,'animationSinging'); except Rejected := True; end;
    Check(Rejected and (JSON=Before),'singing animation accepted without source');
    Rejected := False; try UI.Document.AddSlot(0,'animationPerformance'); except Rejected := True; end;
    Check(Rejected and (JSON=Before),'performance animation accepted without source');
    Check(UI.SharedLibrary.TryImport(TPath.Combine(Root,'animation.psd'),'演奏者','#90C4E0',A,Dup,Error),Error);
    UI.Document.AssignPsd(0,A.ID); UI.Document.SetPerformer(0,'drums',['singing','performance']);
    Sing := Slot('singing'); Perf := Slot('performance');
    ASing := UI.Document.AddSlot(0,'animationSinging'); APerf := UI.Document.AddSlot(0,'animationPerformance');
    Check(UI.Document.TrackAt(0).Slots[ASing].Name='アニメーション（歌唱）','singing caption');
    Check(UI.Document.TrackAt(0).Slots[APerf].Name='アニメーション（演奏）','performance caption');
    Check(UI.Document.TrackAt(0).Slots[ARhythm].Name='アニメーション（リズム）','rhythm caption');
    Motion.RhythmType := rmtBounce; Motion.Strength := 50; Motion.Speed := 2;
    SetLength(A.Patterns,1); CreateGUID(G); A.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36));
    A.Patterns[0].AssetID := A.ID; A.Patterns[0].Kind := 'animation'; A.Patterns[0].Name := '縮み・伸び';
    A.Patterns[0].Color := '#B897D6'; A.Patterns[0].ConfigJSON := Motion.ToJSON;
    Check(UI.SharedLibrary.TrySave(A,Error),Error);
    P := Default(TMusicStudioPattern); P.Kind := 'animation'; P.AssetID := A.ID; P.SharedPatternID := A.Patterns[0].ID;
    P.Name := A.Patterns[0].Name; P.Color := A.Patterns[0].Color; Index := UI.Document.AddReference(P); P := UI.Document.PatternAt(Index);
    Place(ARhythm,0.25,4); UI.TimelineBox.SelectSlot(0,ARhythm);
    UI.SlotAddMenu.OnPopup(UI.SlotAddMenu); N := 0;
    for I := 0 to UI.SlotAddMenu.Items.Count-1 do if UI.SlotAddMenu.Items[I].Visible and
      (Pos('アニメーション（',UI.SlotAddMenu.Items[I].Caption)>0) then Inc(N);
    Check(N=3,'three animation menu options'); Check(not UI.AddButton.Visible and not UI.PatternList.Visible,'animation exposes pattern list');
    Check(UI.TimelineBox.SlotHeight('animationSinging')=28,'animation row height');
    UI.TimelineBox.SelectTrack(0); UI.ArrangementMenu.OnPopup(UI.ArrangementMenu); AddParent := nil;
    for I := 0 to UI.ArrangementMenu.Items.Count-1 do if UI.ArrangementMenu.Items[I].Caption='スロット追加' then AddParent := UI.ArrangementMenu.Items[I];
    Check((AddParent<>nil) and (AddParent.Count=UI.SlotAddMenu.Items.Count),'slot add is not a submenu');
    Check(not Assigned(AddParent.OnClick),'slot add launches a separate popup');
    for I := 0 to AddParent.Count-1 do Check((AddParent.Items[I].Visible=UI.SlotAddMenu.Items[I].Visible) and
      (AddParent.Items[I].Enabled=UI.SlotAddMenu.Items[I].Enabled),'submenu eligibility differs');

    AtTime(0.25,0.5); AtTime(0.5,1); AtTime(0.75,1.5); // global beats, independent of animation clip start
    CalculateMusicStudioMotionTransform(Motion,0,Transform); Check(Transform.VerticalScale<1,'onset did not squash');
    CalculateMusicStudioMotionTransform(Motion,0.5,Transform); Check(Transform.VerticalScale>1,'preparation did not stretch');
    Check(UI.Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":2,"bpm":60}]}',Error),Error);
    Reload; AtTime(1.5,2.5); AtTime(1.0,2); RemoveAnimation(ARhythm);
    Midi := TPath.Combine(Root,'singing.mid');
    TFile.WriteAllBytes(Midi,TBytes.Create($4D,$54,$68,$64,0,0,0,6,0,0,0,1,1,$E0,$4D,$54,$72,$6B,0,0,0,32,
      0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,$2F,0));
    Index := UI.Document.AddSinging; SingingIndex := Index; Before := P.ID; P := UI.Document.PatternAt(Index);
    P.FilePath := Midi; P.SourceTrack := 0; P.Duration := 2; P.SourceStartSeconds := 0; UI.Document.UpdatePattern(P);
    Check(UI.Document.AddPlacement(0,Sing,P.ID,0,2,Error),Error);
    P := UI.Document.PatternAt(0); Check(P.ID=Before,'animation reference changed');
    Place(ASing,0,3); AtTime(0,0); AtTime(0.5,0.5); AtTime(1,0); AtTime(1.5,0.5); AtTime(0.25,0.25); AtTime(2.1,0,False);
    P := UI.Document.PatternAt(SingingIndex); P.SourceStartSeconds := 0.5; UI.Document.UpdatePattern(P); Reload;
    AtTime(0,0.5); AtTime(0.5,0); AtTime(1,0.5); AtTime(1.75,0,False);
    P.SourceStartSeconds := 0; UI.Document.UpdatePattern(P); Reload;
    Before := JSON; UI.Document.RemoveSlot(0,Sing); Reload;
    AtTime(0.5,0,False); Rejected := False; try UI.Document.AddSlot(0,'animationSinging'); except Rejected := True; end;
    Check(Rejected,'deleted source still allows new animation'); Check(UI.Document.TryLoad(Before,Error),Error); Reload;
    RemoveAnimation(ASing);
    Index := UI.Document.AddPerformance; PerformanceIndex := Index; P := UI.Document.PatternAt(Index);
    P.ConfigJSON := '{"lengthBeats":4,"notes":[{"startBeat":0,"lengthBeats":1,"pitch":60,"velocity":100},{"startBeat":2,"lengthBeats":1,"pitch":60,"velocity":100}]}';
    UI.Document.UpdatePattern(P); Check(UI.Document.AddPlacement(0,Perf,P.ID,0,3,Error),Error);
    P := UI.Document.PatternAt(0); Place(APerf,0,3);
    AtTime(0,0); AtTime(0.25,0.5); AtTime(0.75,0,False); AtTime(1,0); AtTime(1.5,0.5); AtTime(1.25,0.25);
    Before := JSON; Reload; After := JSON; Check(Before=After,'animation roundtrip changed document');
    AtTime(1.25,0.25); Jobs := UI.Preview.SceneCache.RenderCount; UI.Preview.Seek(1.25); Await;
    Check(UI.Preview.SceneCache.RenderCount=Jobs,'static time repeated rendering');
    P := UI.Document.PatternAt(PerformanceIndex);
    P.ConfigJSON := '{"lengthBeats":4,"notes":[],"instrumentTimeline":{"version":1,"assetId":"'+A.ID+'","blocks":['+
      '{"id":"action-1","row":"右手","choice":"候補0","startBeat":0,"endBeat":1,"stage":0},'+
      '{"id":"action-2","row":"右手","choice":"候補0","startBeat":2,"endBeat":3,"stage":0},'+
      '{"id":"selection-1","row":"表情","choice":"通常","startBeat":1,"endBeat":2,"stage":0}]}}';
    UI.Document.UpdatePattern(P); Reload;
    UI.Preview.Seek(0.25); Await;
    Check(UI.Preview.SceneCache.StatusForTrack(0)='','instrument animation warning');
    Check(Video.Render(JSON,0.25,64,64,Pixels,Error),Error);
    InstrumentAt(0,0,True); InstrumentAt(0.25,0.5,True); InstrumentAt(0.75,0,False); InstrumentAt(1.5,0.5,True);
    SetLength(Cues,2); Cues[0].StartValue := 2; Cues[0].EndValue := 3; Cues[1].StartValue := 0; Cues[1].EndValue := 1;
    SortMusicStudioAnimationCues(Cues); Check(MusicStudioAnimationPhase(Cues,0.5,Phase) and SameValue(Phase,0.5),'cue phase');
    Check(not MusicStudioAnimationPhase(Cues,1.5,Phase),'cue rest');
    // Real pointer messages exercise creation/move/resize; menu dispatch is intercepted before Popup.
    RemoveAnimation(APerf); UI.TimelineBox.SelectSlot(0,APerf);
    if not UI.TimelineBox.TrackExpanded(0) then UI.TimelineBox.ToggleTrack(0);
    UI.TimelineBox.SetZoom(100); Application.ProcessMessages;
    Probe := TAnimationMenuProbe.Create; Probe.Editor := UI.SmallSlotEditor;
    SavedMenu := UI.TimelineBox.OnSmallMenu; UI.TimelineBox.OnSmallMenu := Probe.Open;
    X1 := UI.TimelineBox.HeaderWidth+80; X2 := X1+100; Y := UI.TimelineBox.SlotRowTop(0,APerf)+10;
    Start := UI.TimelineBox.SnapSecondsForSlot(UI.TimelineBox.SecondsAtSlot(X1,0,APerf),0,APerf);
    Finish := UI.TimelineBox.SnapSecondsForSlot(UI.TimelineBox.SecondsAtSlot(X2,0,APerf),0,APerf);
    Before := JSON; BasePatterns := UI.Document.PatternCount;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X1,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X2,Y));
    Check(JSON=Before,'animation draft mutates document');
    UI.TimelineBox.Perform(WM_KEYDOWN,VK_ESCAPE,0); Check(JSON=Before,'animation escape changes document');
    Check(GetCapture<>UI.TimelineBox.Handle,'animation escape kept capture');
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X2,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(X1,Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(X1,Y)); Await;
    Check(Length(UI.Document.TrackAt(0).Slots[APerf].Clips)=1,'reverse drag did not create interval');
    C := UI.Document.TrackAt(0).Slots[APerf].Clips[0]; ClipID := C.ID;
    Check(SameValue(C.StartSeconds,Start) and SameValue(C.LengthSeconds,Finish-Start),'animation drag bounds');
    Check(UI.Document.PatternCount=BasePatterns+1,'local animation not created');
    After := JSON; UI.UndoEdit; Check(JSON=Before,'animation creation undo'); UI.RedoEdit; Check(JSON=After,'animation creation redo'); Await;
    Middle := (X1+X2) div 2; UI.TimelineBox.SelectClip(0,APerf,0);
    Before := JSON;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Middle,Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(Middle,Y));
    Check((Probe.Calls=1) and (JSON=Before),'left click did not open non-mutating variation menu');
    Check(GetCapture<>UI.TimelineBox.Handle,'variation menu kept drag capture');
    Check(UI.SmallSlotEditor.Menu.Items[Ord(rmtBounce)].Checked,'current animation variant not checked');
    UI.SmallSlotEditor.Menu.Items[Ord(rmtPendulum)].Click; Await;
    C := UI.Document.TrackAt(0).Slots[APerf].Clips[0];
    Check((C.ID=ClipID) and SameValue(C.StartSeconds,Start) and SameValue(C.LengthSeconds,Finish-Start),'variant changed placement identity/bounds');
    Check(UI.Document.PatternCount=BasePatterns+1,'variant left orphan local patterns');
    After := JSON; UI.UndoEdit; Check(JSON=Before,'variant undo'); UI.RedoEdit; Check(JSON=After,'variant redo'); Await;
    Motion.RhythmType := rmtPendulum; InstrumentAt(1.5,0.5,True); UI.TimelineBox.SelectClip(0,APerf,0);
    Before := JSON; Rejected := False;
    try UI.Document.WriteAnimationElement(0,APerf,0,99,Start,Finish-Start); except Rejected := True; end;
    Check(Rejected and (JSON=Before),'invalid animation write not atomic');
    RightX := XFor(C.StartSeconds+C.LengthSeconds)-1;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(RightX,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(RightX+50,Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(RightX+50,Y)); Await;
    Check(UI.Document.TrackAt(0).Slots[APerf].Clips[0].LengthSeconds>C.LengthSeconds,'animation right edge resize');
    Check(Probe.Calls=1,'resize opened variation popup');
    UI.UndoEdit; Await;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Middle,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Middle+50,Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(Middle+50,Y)); Await;
    Check(UI.Document.TrackAt(0).Slots[APerf].Clips[0].StartSeconds>C.StartSeconds,'animation move');
    Check(Probe.Calls=1,'move opened variation popup'); UI.UndoEdit; Await;
    Before := JSON; Reload; Check(JSON=Before,'local animation roundtrip');
    UI.TimelineBox.SelectSlot(0,Sing); Check(UI.PatternList.Visible and UI.AddButton.Visible,'pattern list not restored');
    TFile.WriteAllText(TPath.Combine(Root,'animation-demo.json'),JSON,TEncoding.UTF8);
    Check(UI.SmallSlotEditor.Prepare(0,APerf,0,Start),'prepare deletion');
    UI.SmallSlotEditor.Menu.Items[UI.SmallSlotEditor.Menu.Items.Count-1].Click; Await;
    Check((Length(UI.Document.TrackAt(0).Slots[APerf].Clips)=0) and (UI.Document.PatternCount=BasePatterns),'delete left orphan animation');
    UI.TimelineBox.OnSmallMenu := SavedMenu;
    // Fresh rhythm interval moves every beat without any singing or performance placement.
    UI.Document.RemovePlacement(0,Perf,0); UI.Document.RemovePlacement(0,Sing,0);
    Check(UI.Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":154}]}',Error),Error);
    UI.Document.WriteAnimationElement(0,ARhythm,-1,Ord(rmtBounce),0,8); Reload; Motion.RhythmType := rmtBounce;
    for I := 0 to 5 do AtTime(I*0.5*60/154,I*0.5);
    // A faster incoming clock must not starve an already-running render.
    UI.Preview.SceneCache.RealtimePlayback := True; Quarter := 0.25*60/154;
    UI.Preview.SceneCache.SetPosition(Quarter); UI.Preview.SceneCache.PollResults;
    UI.Preview.SceneCache.SetPosition(0.5*60/154);
    Deadline := GetTickCount64+3000; SawIntermediate := False;
    repeat
      UI.Preview.SceneCache.PollResults;
      Published := UI.Preview.SceneCache.PublishedSecondsForTrack(0);
      if SameValue(Published,Quarter,1E-9) then begin SawIntermediate := True; Break; end;
      Sleep(1);
    until GetTickCount64>=Deadline;
    Check(SawIntermediate,'live clock discarded every completed intermediate frame');
    UI.Preview.SceneCache.RealtimePlayback := False; AtTime(0.75*60/154,0.75);
    // Exercise the actual silent transport clock, rather than waiting after each seek.
    UI.Preview.Seek(0); Await; UI.Preview.StartSilentVisualPreview;
    Deadline := GetTickCount64+1300; PreviousPublished := -1; PublishedCount := 0; ChangedFrames := 0; LastPixels := nil;
    repeat
      Application.ProcessMessages; UI.Preview.SceneCache.PollResults;
      Published := UI.Preview.SceneCache.PublishedSecondsForTrack(0);
      if Published<>PreviousPublished then begin
        Inc(PublishedCount); PreviousPublished := Published; Image := UI.Preview.SceneCache.ImageForTrack(0);
        if Image<>nil then begin
          SetLength(CurrentPixels,Image.Width*Image.Height*4);
          for RowIndex := 0 to Image.Height-1 do Move(PByte(Image.ScanLine[RowIndex])^,CurrentPixels[RowIndex*Image.Width*4],Image.Width*4);
          if (Length(LastPixels)=0) or not CompareMem(@LastPixels[0],@CurrentPixels[0],Length(CurrentPixels)) then Inc(ChangedFrames);
          LastPixels := Copy(CurrentPixels);
        end;
      end;
      Sleep(2);
    until GetTickCount64>=Deadline;
    UI.Preview.Pause; Await;
    Check((PublishedCount>=6) and (ChangedFrames>=3),'rhythm transport did not publish moving frames');
    Check(not UI.Preview.SceneCache.RealtimePlayback,'pause kept live publication mode');
    CaptureTimeline;
    Writeln('RHYTHM_154_BPM_BEAT_REPETITION_NO_SOURCE_INTERMEDIATE_FRAMES_SILENT_TRANSPORT_EXACT_PAUSE_SUBMENU_OK frames=',PublishedCount,' changed=',ChangedFrames);

    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'animation used audio');
    Writeln('ANIMATION_THREE_SLOTS_SOURCE_GUARDS_DIRECT_DRAG_CLICK_VARIANTS_UNDO_LOCAL_BOUNCE_GLOBAL_TEMPO_SINGING_PERFORMANCE_RESTART_REVERSE_REST_DELETE_ROUNDTRIP_CACHE_NO_POPUP_NO_AUDIO_OK');
  finally Probe.Free; Video.Free; Motion.Free; UI.Free; end;
end;

end.
