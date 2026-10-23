unit SYNC_MusicStudio_SlotUIChecks;

// 小型演出/大小の行高/固定PSD表示/優先順位を合成PSDで確認する。音声処理とDPI変更は呼ばない。
interface
procedure RunSlotUIChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.IOUtils, System.Math, System.Hash,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_SmallSlotData;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('SLOT_UI: '+Text); end;
procedure RunSlotUIChecks(const Root: string);
var Art: TArtDocument; Actor,G,Pattern: TArtLayer; D: TMusicStudioLayerDocument; Profile: TMusicStudioPerformerProfile;
  UI: TFormMusicStudioSettings; A: TMusicStudioPsdAsset; Duplicate: Boolean; Data: TMusicStudioInstrumentData;
  Block: TInstrumentBlock; P: TMusicStudioPattern; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache;
  Path,Hash,Error,Text,Before,PatternID,ClipID: string; T,Expr,Face,Pose,Symbol,Perf,Sing,I,X,Y,EndX: Integer;
  C: TMusicStudioPlacement; R,R2: TRect; Scroll: TScrollBar; PNG: TPngImage; B: TBitmap;
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
  begin Check(UI.Document.TrySave(Text,Error),Error); UI.LoadDocument(Text); UI.TimelineBox.SelectSlot(T,Expr); UI.TimelineBox.SetZoom(80); end;
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
begin
  ForceDirectories(Root); Art := TArtDocument.Create;
  try
    Art.Width := 8; Art.Height := 2; Actor := Group('自由な演奏者',nil); Group('演奏属性:ドラム',Actor); Group('口',Actor);
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
    Check(UI.TimelineBox.SlotHeight('singing')>3*UI.TimelineBox.SlotHeight('emotion'),'large vs compact height');
    R := UI.TimelineBox.TrackThumbnailRect(T); Check((R.Width>0) and (R.Right<UI.TimelineBox.HeaderWidth),'PSD in fixed track header');
    for I := 0 to UI.TimelineBox.ComponentCount-1 do if UI.TimelineBox.Components[I] is TScrollBar then begin
      Scroll := TScrollBar(UI.TimelineBox.Components[I]); if Scroll.Kind=sbHorizontal then begin Scroll.Position := 64; R2 := UI.TimelineBox.TrackThumbnailRect(T); Check(R=R2,'horizontal scroll keeps track preview'); Scroll.Position := 0; end;
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
    X := TimeX(C.StartSeconds+2); Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X+80,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X+80,Y);
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds-2)<1E-8,'middle drag moves');
    X := TimeX(C.StartSeconds)+1; Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X+40,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,X+40,Y);
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds-2.5)<1E-8,'left edge resize');
    EndX := TimeX(C.StartSeconds+C.LengthSeconds)-2; Mouse(WM_LBUTTONDOWN,EndX,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,EndX-40,Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,EndX-40,Y);
    C := UI.Document.TrackAt(T).Slots[Expr].Clips[0]; Check(Abs(C.StartSeconds+C.LengthSeconds-5.5)<1E-8,'right edge resize');
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
    B := TBitmap.Create; PNG := TPngImage.Create;
    try B.SetSize(UI.ClientWidth,UI.ClientHeight); UI.PaintTo(B.Canvas,0,0); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'slot-ui.png'));
    finally PNG.Free; B.Free; end;
    Profile.Slots := TArray<string>.Create('singing','performance'); UI.Document.SetPerformer(T,'drums',Profile.Slots);
    UI.TimelineBox.Refresh; Check(UI.TimelineBox.SlotRowTop(T,Expr)=-1,'missing PSD capability hidden'); Check(Length(UI.Document.TrackAt(T).Slots[Expr].Clips)=1,'hidden data preserved');
    Check(THashSHA2.GetHashStringFromFile(Path)=Hash,'PSD source unchanged');
    Writeln('SLOT_UI_LARGE_SMALL_FIXED_PREVIEW_PSD_CHOICES_CONTEXT_MOVE_EDGES_UNDO_UID_DEFAULT_HIDDEN_PRIORITY_POSE_RESTORE_NO_AUDIO_OK');
  finally Data.Free; UI.Free; D.Free; end;
end;
end.
