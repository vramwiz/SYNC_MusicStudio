unit SYNC_MusicStudio_SlotUIChecks;

// 小型演出/大小の行高/固定PSD表示/優先順位を合成PSDで確認する。音声処理とDPI変更は呼ばない。
interface
procedure RunSlotUIChecks(const Root: string; const ActualPSD: string = '');
implementation
uses SYNC_MusicStudio_DarkScrollBar, System.SysUtils, System.Classes, System.Types, System.JSON, System.IOUtils, System.Math, System.Hash,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_SmallSlotData;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('SLOT_UI: '+Text); end;
procedure RunSlotUIChecks(const Root,ActualPSD: string);
var Art: TArtDocument; Actor,G,Pattern: TArtLayer; D: TMusicStudioLayerDocument; Profile: TMusicStudioPerformerProfile;
  UI: TFormMusicStudioSettings; A: TMusicStudioPsdAsset; Duplicate: Boolean; Data: TMusicStudioInstrumentData;
  Block: TInstrumentBlock; P: TMusicStudioPattern; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache;
  Path,Hash,Error,Text,Before,PatternID,ClipID: string; T,Expr,Face,Pose,Symbol,Perf,Sing,I,X,Y,EndX: Integer;
  C: TMusicStudioPlacement; R,R2: TRect; Scroll: TMusicStudioDarkScrollBar; PNG: TPngImage; B: TBitmap;
  Deadline: UInt64;
  function Group(const Name: string; Parent: TArtLayer): TArtLayer;
  begin Result := Art.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,8,2),Parent); Result.Visible := True; end;
  procedure Pixel(const Name: string; Parent: TArtLayer; X: Integer; Red,Green,Blue: Byte; Visible: Boolean);
  var L: TArtLayer;
  begin L := Art.AddLayer(alkImage,Name,TArtBounds.Create(X,0,X+1,1),Parent); L.Pixels := TBytes.Create(Red,Green,Blue,255); L.Visible := Visible; end;
  function Slot(const Kind: string): Integer;
  var N: Integer;
  begin for N := 0 to High(UI.Document.TrackAt(T).Slots) do if UI.Document.TrackAt(T).Slots[N].Kind=Kind then Exit(N); raise Exception.Create('slot '+Kind); end;
  procedure Reload;
  begin Check(UI.Document.TrySave(Text,Error),Error); UI.LoadDocument(Text); if not UI.TimelineBox.TrackExpanded(T) then UI.TimelineBox.ToggleTrack(T); UI.TimelineBox.SelectSlot(T,Expr); UI.TimelineBox.SetZoom(80); end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin UI.TimelineBox.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  function TimeX(Seconds: Double): Integer;
  begin Result := UI.TimelineBox.HeaderWidth+Round(Seconds*80*UI.CurrentPPI/96); end;
  procedure Add(SlotIndex: Integer; const Mode,Choice: string; Start,Len: Double);
  begin UI.Document.WriteSmallElement(T,SlotIndex,-1,Mode,Choice,Start,Len); end;
  procedure AtTime(Seconds: Double);
  var Deadline: UInt64;
  begin
    Scene.SetPosition(Seconds,Seconds*2); Deadline := GetTickCount64+5000;
    repeat Scene.PollResults; Check(GetTickCount64<Deadline,'scene timeout'); Sleep(1);
    until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(T)<>nil);
  end;
  function PixelIs(X: Integer; Red,Green,Blue,Alpha: Byte): Boolean;
  var Bytes: PByte;
  begin Bytes := Scene.ImageForTrack(T).ScanLine[0]; Result := (Bytes[X*4]=Blue) and (Bytes[X*4+1]=Green) and (Bytes[X*4+2]=Red) and (Bytes[X*4+3]=Alpha); end;
  procedure EditorGestures;
  var Point,Screen: TPoint; V,Bounds: TRect; Zoom,Cursor,Anchor: Double; Pan: TPointF; Handled: Boolean; I: Integer;
  begin
    Check(not UI.ToolbarPanel.Visible,'top toolbar visible');
    Check(not UI.EditButton.Parent.Visible,'pattern footer visible');
    Check(UI.Preview.Parent.Parent=UI.WorkPanel,'preview not above full workspace');
    Check(UI.Preview.PlayButton.Parent.Parent=UI,'transport not above workspace');
    Check(UI.Preview.Stage.Height=UI.Preview.ClientHeight,'left preview still contains transport');
    Check(UI.Preview.PlayButton.BoundsRect.Bottom<=UI.Preview.PlayButton.Parent.Height,'compact play button clipped');
    Check(UI.Preview.TempoEdit.BoundsRect.Right<=UI.Preview.TempoEdit.Parent.Width,'compact tempo clipped');
    Check(UI.Preview.Stage.Height>0,'compact preview has no drawing area');
    UI.TimelineBox.SelectSlot(T,0); Check(UI.LibraryKind='psd','PSD context not selected');
    Handled := False; UI.PatternList.OnContextPopup(UI.PatternList,System.Types.Point(10,10),Handled);
    Check(UI.PatternList.ItemIndex=0,'context did not select hovered item');
    UI.PatternMenu.OnPopup(UI.PatternMenu);
    Check(UI.PatternMenu.Items[1].Enabled=UI.EditButton.Enabled,'context edit state');
    Check(UI.PatternMenu.Items[2].Enabled=UI.DeleteButton.Enabled,'context delete state');
    Handled := False; UI.PatternList.OnContextPopup(UI.PatternList,System.Types.Point(10,UI.PatternList.Height-1),Handled);
    UI.PatternMenu.OnPopup(UI.PatternMenu); Check(not UI.PatternMenu.Items[1].Enabled,'empty context enabled edit');
    UI.Document.TrySave(Before,Error); UI.Preview.Seek(0.5);
    Point := System.Types.Point(UI.Preview.Stage.Width div 2,UI.Preview.Stage.Height div 2);
    Screen := UI.Preview.Stage.ClientToScreen(Point); UI.PatternList.SetFocus; Zoom := UI.Preview.ViewZoom;
    UI.Perform(WM_MOUSEWHEEL,WPARAM(Word(120)) shl 16,MakeLParam(Screen.X,Screen.Y));
    Check(UI.Preview.ViewZoom>Zoom,'focused list stole preview wheel');
    Check(UI.Preview.CharacterBounds(T,V,Bounds),'preview character not ready');
    Pan := UI.Preview.ViewPan;
    UI.Preview.Stage.Perform(WM_MBUTTONDOWN,MK_MBUTTON,MakeLParam(Point.X,Point.Y));
    UI.Preview.Stage.Perform(WM_MOUSEMOVE,MK_MBUTTON,MakeLParam(Point.X+23,Point.Y-17));
    UI.Preview.Stage.Perform(WM_MBUTTONUP,0,MakeLParam(Point.X+23,Point.Y-17));
    Check(not UI.Preview.ViewDragging and (Abs(UI.Preview.ViewPan.X-Pan.X-23)<0.01) and
      (Abs(UI.Preview.ViewPan.Y-Pan.Y+17)<0.01),'main preview pan/release');
    UI.Preview.FitView; Check((UI.Preview.ViewZoom=1) and (UI.Preview.ViewPan.X=0),'main preview fit');
    UI.Preview.ZoomAt(120,Point);
    Check(UI.Preview.CharacterBounds(T,V,Bounds),'zoomed placement bounds absent');
    Point := System.Types.Point((Bounds.Left+Bounds.Right) div 2,(Bounds.Top+Bounds.Bottom) div 2);
    Pan := UI.Preview.ViewPan;
    UI.Preview.Stage.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Point.X,Point.Y));
    UI.Preview.Stage.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Point.X+12,Point.Y+8));
    UI.Preview.Stage.Perform(WM_LBUTTONUP,0,MakeLParam(Point.X+12,Point.Y+8));
    UI.Document.TrySave(Text,Error); Check(Text<>Before,'left drag failed to edit PSD placement');
    Check((UI.Preview.ViewPan.X=Pan.X) and (UI.Preview.ViewPan.Y=Pan.Y),'left drag moved viewport');
    UI.UndoEdit; UI.Document.TrySave(Text,Error); Check(Text=Before,'left drag placement undo');
    UI.Preview.FitView;
    Cursor := UI.Preview.Position;
    X := UI.TimelineBox.HeaderWidth+200; Y := UI.TimelineBox.RulerHeight div 2;
    Anchor := UI.TimelineBox.SecondsAtPoint(X);
    Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X-80,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X-80,Y);
    Check(UI.TimelineBox.SecondsAtPoint(X)>Anchor,'main ruler did not slide');
    Check(UI.Preview.Position=Cursor,'ruler slide changed playhead');
    Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X,Y);
    Check(Abs(UI.Preview.Position-UI.TimelineBox.SecondsAtPoint(X))<0.001,'main ruler click did not seek');
    UI.Document.TrySave(Text,Error); Check(Text=Before,'view gestures changed project');
    for I := 0 to UI.TimelineBox.ComponentCount-1 do if UI.TimelineBox.Components[I] is TMusicStudioDarkScrollBar then
      if TMusicStudioDarkScrollBar(UI.TimelineBox.Components[I]).Kind=sbHorizontal then TMusicStudioDarkScrollBar(UI.TimelineBox.Components[I]).Position := 0;
    Writeln('INTEGRATED_LAYOUT_CONTEXT_PREVIEW_WHEEL_PAN_FIT_RULER_SLIDE_CLICK_NO_DOCUMENT_CHANGE_OK');
  end;
begin
  ForceDirectories(Root); Art := TArtDocument.Create;
  try
    Art.Width := 8; Art.Height := 2; Actor := Group('自由な演奏者',nil); Group('演奏属性:ドラム',Actor); G := Group('口',Actor); Pixel('*あ',G,7,80,80,80,True); Pixel('*い',G,7,80,80,80,False); Pixel('*う',G,7,80,80,80,False); Pixel('*え',G,7,80,80,80,False); Pixel('*お',G,7,80,80,80,False); Pixel('*ん',G,7,80,80,80,False);
    G := Group('右手',Actor); Pattern := Group('打撃',G); Pixel('*0',Pattern,0,80,80,80,True); Pixel('*1',Pattern,0,230,30,20,False);
    G := Group('表情',Actor); Pixel('初期顔',G,1,80,80,80,True); Pixel('*笑顔',G,1,20,220,30,False);
    G := Group('顔色',Actor); Pixel('初期色',G,2,80,80,80,True); Pixel('*青ざめる',G,2,20,30,220,False);
    G := Group('記号',Actor); Pixel('初期記号',G,3,80,80,80,True); Pixel('*汗',G,3,230,140,20,False);
    G := Group('ポーズ',Actor); Pixel('初期姿勢',G,4,80,80,80,True); Pixel('*キメ',G,4,200,30,180,False);
    Path := TPath.Combine(Root,'slots.psd'); WriteNewPsd(Art,Path,pcRaw);
  finally Art.Free; end;
  Hash := THashSHA2.GetHashStringFromFile(Path); D := TMusicStudioLayerDocument.Create; UI := TFormMusicStudioSettings.Create(nil);
  Data := TMusicStudioInstrumentData.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Profile := MusicStudioPerformerProfile(D,'{}'); Check(Length(Profile.Slots)=6,'six capabilities');
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Check(UI.SharedLibrary.TryImport(Path,'演奏者','#90C4E0',A,Duplicate,Error),Error);
    T := UI.Document.AddTrack('performer'); UI.Document.AssignPsd(T,A.ID); UI.Document.SetPerformer(T,'drums',Profile.Slots,True,Profile.SelectionsJSON);
    Expr := Slot('emotion'); Face := Slot('face'); Pose := Slot('pose'); Symbol := Slot('symbol'); Perf := Slot('performance'); Sing := Slot('singing');
    Check(Sing>=0,'singing slot');
    Check((Length(UI.Document.TrackAt(T).Slots[Expr].Choices)=1) and (UI.Document.TrackAt(T).Slots[Expr].Choices[0]='笑顔'),'PSD choice strips flags and excludes visible default');
    UI.ClientHeight := 1100; UI.ClientWidth := 1240; Reload; UI.Show; Application.ProcessMessages;
    Check(UI.TimelineBox.SlotHeight('singing')=UI.TimelineBox.SlotHeight('performance'),'large slots same height');
    Check(UI.TimelineBox.SlotHeight('singing')=3*UI.TimelineBox.SlotHeight('emotion'),'singing/performance triple small row height');
    Check(UI.TimelineBox.SlotHeight('singing')>UI.TimelineBox.SlotHeight('emotion'),'performance vs compact height');
    R := UI.TimelineBox.TrackThumbnailRect(T); Check((R.Width>0) and (R.Right<UI.TimelineBox.HeaderWidth),'PSD in fixed track header');
    for I := 0 to UI.TimelineBox.ComponentCount-1 do if UI.TimelineBox.Components[I] is TMusicStudioDarkScrollBar then begin
      Scroll := TMusicStudioDarkScrollBar(UI.TimelineBox.Components[I]); if Scroll.Kind=sbHorizontal then begin Scroll.Position := 64; R2 := UI.TimelineBox.TrackThumbnailRect(T); Check(R=R2,'horizontal scroll keeps track preview'); Scroll.Position := 0; end;
    end;
    UI.Document.TrySave(Before,Error); Y := UI.TimelineBox.SlotRowTop(T,Expr)+UI.TimelineBox.SlotHeight('emotion') div 2;
    Mouse(WM_LBUTTONDOWN,TimeX(0.5),Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,TimeX(0.5),Y);
    UI.Document.TrySave(Text,Error); Check(Text=Before,'blank left click creates nothing');
    Check(UI.SmallSlotEditor.Prepare(T,Expr,-1,1),'blank context'); Check(UI.SmallSlotEditor.Menu.Items[0].Caption='追加','add submenu');
    Check(UI.SmallSlotEditor.Menu.Items[0].Count=2,'virtual default plus PSD choice'); UI.SmallSlotEditor.Menu.Items[0].Items[1].Click;
    Check(Length(UI.Document.TrackAt(T).Slots[Expr].Clips)=1,'context adds'); C := UI.Document.TrackAt(T).Slots[Expr].Clips[0];
    Check(Abs(C.StartSeconds-1)<1E-8,'right click sets start');
    UI.UndoEdit; Check(Length(UI.Document.TrackAt(T).Slots[Expr].Clips)=0,'context undo'); UI.RedoEdit;
    Y := UI.TimelineBox.SlotRowTop(T,Expr)+UI.TimelineBox.SlotHeight('emotion') div 2;
    UI.Preview.Seek(1.4);
    X := TimeX(C.StartSeconds+2); Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X+80,Y,MK_LBUTTON);
    Check(Abs(UI.Preview.Position-1.4)<1E-9,'clip move dragged playhead'); Mouse(WM_LBUTTONUP,X+80,Y);
    Check(Abs(UI.Preview.Position-1.4)<1E-9,'clip move commit reset playhead');
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds-2)<1E-8,'middle drag moves');
    X := TimeX(C.StartSeconds)+1; Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X+40,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X+40,Y);
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds-2.5)<1E-8,'left edge resize');
    Check(Abs(UI.Preview.Position-1.4)<1E-9,'clip left resize reset playhead');
    EndX := TimeX(C.StartSeconds+C.LengthSeconds)-2; Mouse(WM_LBUTTONDOWN,EndX,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,EndX-40,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,EndX-40,Y);
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds+C.LengthSeconds-5.5)<1E-8,'right edge resize');
    Check(Abs(UI.Preview.Position-1.4)<1E-9,'clip right resize reset playhead');
    UI.SmallSlotEditor.Prepare(T,Expr,0,3); Check(UI.SmallSlotEditor.Menu.Items[0].Caption='変更','change submenu'); UI.SmallSlotEditor.Menu.Items[0].Items[0].Click;
    ClipID := UI.Document.TrackAt(T).Slots[Expr].Clips[0].ID; Check(ClipID=C.ID,'change preserves placement UID');
    UI.SmallSlotEditor.Prepare(T,Expr,0,3); UI.SmallSlotEditor.Menu.Items[1].Click; Check(Length(UI.Document.TrackAt(T).Slots[Expr].Clips)=0,'context delete');
    Check(UI.SmallSlotEditor.Prepare(T,Symbol,-1,1),'symbol menu'); Check(UI.SmallSlotEditor.Menu.Items[0].Items[2].Caption='非表示','virtual symbol hidden');
    Data.Load('{"lengthBeats":8,"notes":[]}'); Block := Default(TInstrumentBlock); Block.StartBeat := 0; Block.EndBeat := 8; Block.Stage := 1;
    Block.Row := '右手'; Block.Choice := '打撃'; Check(Data.PutBlock(-1,Block),'action');
    Block.Row := '表情'; Block.Choice := '笑顔'; Check(Data.PutBlock(-1,Block),'internal expression');
    Block.Row := '顔色'; Block.Choice := '青ざめる'; Check(Data.PutBlock(-1,Block),'internal face');
    Block.Row := '記号'; Block.Choice := '汗'; Check(Data.PutBlock(-1,Block),'internal symbol');
    I := UI.Document.AddPerformance; P := UI.Document.PatternAt(I); P.Name := '演奏UID'; P.ConfigJSON := Data.JSON;
    P.PerformanceAttribute := 'drums'; P.SharedPatternID := '11111111-1111-1111-1111-111111111111'; P.LibraryRevision := '22222222-2222-2222-2222-222222222222'; UI.Document.UpdatePattern(P);
    Check(UI.Document.AddBeatPlacement(T,Perf,P.ID,0,8,Error),Error); PatternID := P.ID; ClipID := UI.Document.TrackAt(T).Slots[Perf].Clips[0].ID;
    UI.Document.RenamePerformance('drums',P.SharedPatternID,'改名済み'); Check(UI.Document.TrackAt(T).Slots[Perf].Clips[0].PatternID=PatternID,'rename keeps pattern UID'); Check(UI.Document.TrackAt(T).Slots[Perf].Clips[0].ID=ClipID,'rename keeps placement UID');
    Add(Expr,'default','',1,1); Add(Face,'default','',1,1); Add(Symbol,'hidden','',1,1);
    Add(Pose,'choice','キメ',1,1); Add(Pose,'choice','キメ',4.25,1); Reload;
    Scene := TMusicStudioPsdSceneCache.Create; Cache := TMusicStudioVisualCache.Create;
    try
      Scene.Bind(UI.Document,UI.SharedLibrary,Cache); AtTime(0.5);
      Check(PixelIs(1,20,220,30,255) and PixelIs(2,20,30,220,255) and PixelIs(3,230,140,20,255),'internal selections');
      AtTime(1.5); Check(PixelIs(1,80,80,80,255) and PixelIs(2,80,80,80,255),'explicit default beats internal choices');
      Check(PixelIs(3,0,0,0,0),'explicit hidden beats internal symbol'); Check(PixelIs(0,230,30,20,255) and PixelIs(4,80,80,80,255),'independent pose ignored during performance');
      AtTime(2.5); Check(PixelIs(1,20,220,30,255) and PixelIs(3,230,140,20,255),'independent end resumes internal');
      AtTime(4.5); Check(PixelIs(0,0,0,0,0) and PixelIs(4,200,30,180,255),'pose outside performance');
      AtTime(5.5); Check(PixelIs(0,80,80,80,255) and PixelIs(4,80,80,80,255),'pose end restores PSD defaults');
    finally Scene.Free; Cache.Free; end;
    UI.Document.TrySave(Text,Error); TFile.WriteAllText(TPath.Combine(Root,'slot-project.json'),Text,TEncoding.UTF8);
    Deadline := GetTickCount64+5000;
    repeat
      UI.TimelineBox.SceneCache.PollResults; Application.ProcessMessages; Check(GetTickCount64<Deadline,'owned preview timeout'); Sleep(1);
    until (UI.TimelineBox.SceneCache.ActiveLoadJobs=0) and (UI.TimelineBox.SceneCache.ActiveRenderJobs=0) and (UI.TimelineBox.SceneCache.ImageForTrack(T)<>nil);
    EditorGestures;
    B := TBitmap.Create; PNG := TPngImage.Create;
    try B.SetSize(UI.ClientWidth,UI.ClientHeight); UI.PaintTo(B.Canvas,0,0); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'slot-ui.png'));
    finally PNG.Free; B.Free; end;
    Profile.Slots := TArray<string>.Create('singing','performance'); UI.Document.SetPerformer(T,'drums',Profile.Slots);
    UI.TimelineBox.Refresh; Check(UI.TimelineBox.SlotRowTop(T,Expr)>=0,'placed unsupported slot must stay visible'); UI.TimelineBox.SelectSlot(T,Expr); Check(Pos('未対応',UI.InfoLabel.Caption)>0,'unsupported slot warning missing'); Check(Length(UI.Document.TrackAt(T).Slots[Expr].Clips)=1,'hidden data preserved');
    Check(THashSHA2.GetHashStringFromFile(Path)=Hash,'PSD source unchanged');
    if ActualPSD<>'' then begin
      Check(D.LoadFile(ActualPSD),D.LastError); Profile := MusicStudioPerformerProfile(D,'{}');
      Check(UI.SharedLibrary.TryImport(ActualPSD,'東北きりたん_ドラム','#EDBA70',A,Duplicate,Error),Error);
      UI.Document.AssignPsd(T,A.ID); UI.Document.SetPerformer(T,'drums',Profile.Slots,True,Profile.SelectionsJSON);
      Check(UI.Document.TrySave(Text,Error),Error); UI.LoadDocument(Text); UI.TimelineBox.SelectSlot(T,0);
      UI.ClientWidth := 1140; UI.ClientHeight := 780; Application.ProcessMessages;
      Deadline := GetTickCount64+10000;
      repeat Application.ProcessMessages; Sleep(5); Check(GetTickCount64<Deadline,'real scene timeout');
      until (UI.Preview.SceneCache.ActiveLoadJobs=0) and (UI.Preview.SceneCache.ActiveRenderJobs=0) and (UI.Preview.SceneCache.ImageForTrack(T)<>nil);
      B := TBitmap.Create; PNG := TPngImage.Create;
      try B.SetSize(UI.ClientWidth,UI.ClientHeight); UI.PaintTo(B.Canvas,0,0); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'integrated-real-drum.png'));
      finally PNG.Free; B.Free; end;
    end;
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'layout test used audio');
    Writeln('SLOT_UI_LARGE_SMALL_FIXED_PREVIEW_PSD_CHOICES_CONTEXT_MOVE_EDGES_UNDO_UID_DEFAULT_HIDDEN_PRIORITY_POSE_RESTORE_NO_AUDIO_OK');
  finally Data.Free; UI.Free; D.Free; end;
end;
end.
