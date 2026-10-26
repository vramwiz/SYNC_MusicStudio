unit SYNC_MusicStudio_InstrumentChecks;
// 共通PSDの専用無音ケース。実素材/実共有設定/DPI試験を使用しない。
interface
procedure RunCompactEditorChecks(const Root: string);
procedure RunInstrumentChecks(const Root: string);
procedure InspectInstrumentPSD(const Root,Path: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentFrame,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_PerformanceLibrary, SYNC_MusicStudio_EditHistory;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('INSTRUMENT: '+Text); end;
procedure InspectInstrumentPSD(const Root,Path: string);
var D: TMusicStudioLayerDocument;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create;
  try
    Check(D.LoadFile(Path),D.LastError);
    TFile.WriteAllText(TPath.Combine(Root,'instrument-analysis.json'),D.InstrumentRules.DiagnosticJSON,TEncoding.UTF8);
    Writeln('INSTRUMENT_ROWS ',D.InstrumentRules.RowCount);
  finally D.Free; end;
end;
procedure RunInstrumentChecks(const Root: string);
var Art: TArtDocument; A,B,C,Keyword,Pattern: TArtLayer; PSD,Hash,Text,Before,Error: string;
  D,Clone: TMusicStudioLayerDocument; Model,ReadBack: TMusicStudioInstrumentData;
  State: TInstrumentState; Block: TInstrumentBlock; V: TJSONObject;
  Dialog: TMusicStudioPatternSettings; F: TMusicStudioInstrumentFrame; P: TMusicStudioPattern;
  I,Row,Y,Track,Slot,Index: Integer; Key: Word; Deadline: UInt64; Bitmap: TBitmap; PNG: TPngImage;
  Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset; Duplicate: Boolean;
  Doc: TMusicStudioDocument; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache;
  function Group(const Name: string; Parent: TArtLayer): TArtLayer;
  begin Result := Art.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,8,2),Parent); Result.Visible := True; end;
  procedure Image(const Name: string; Parent: TArtLayer; X: Integer; R,G,B: Byte; Visible: Boolean);
  var L: TArtLayer;
  begin
    L := Art.AddLayer(alkImage,Name,TArtBounds.Create(X,0,X+1,1),Parent); L.Visible := Visible;
    L.Pixels := TBytes.Create(R,G,B,255);
  end;
  function LayerKey(const Suffix: string): string;
  var L: TMusicStudioLayerInfo;
  begin for L in D.Layers do if L.Path.EndsWith(Suffix) then Exit(L.Key); raise Exception.Create('fixture key '+Suffix); end;
  function Visible(Overrides: TJSONObject; const Suffix: string): Boolean;
  begin Result := Overrides.GetValue<TJSONBool>(LayerKey(Suffix)).AsBoolean; end;
  function XBeat(Beat: Double): Integer;
  begin Result := 134+Round(Beat/F.Data.LengthBeats*(F.Grid.Width-135)); end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin F.Grid.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure SceneAt(Beat: Double);
  begin
    Scene.SetPosition(Beat/2,Beat); Deadline := GetTickCount64+5000;
    repeat Scene.PollResults; Check(GetTickCount64<Deadline,'scene timeout'); Sleep(1);
    until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
  end;
  function AlphaAt(Image: TBitmap; X: Integer): Byte;
  var Bytes: PByte;
  begin Bytes := Image.ScanLine[0]; Result := Bytes[X*4+3]; end;
begin
  ForceDirectories(Root); Art := TArtDocument.Create;
  try
    Art.Width := 8; Art.Height := 2; A := Group('自由な人物名',nil); B := Group('機材XYZ',nil); C := Group('装飾567',nil);
    Keyword := Group('右手',A); Pattern := Group('ソロ',Keyword);
    Image('*0',Pattern,0,80,80,80,True); Image('*1',Pattern,0,230,30,20,False);
    Image('*2',Pattern,0,150,30,20,False); Image('*3',Pattern,0,100,30,20,False);
    Pattern := Group('ストローク',Keyword); Image('*1',Pattern,0,30,30,230,False);
    Keyword := Group('右手',B); Pattern := Group('ソロ',Keyword); Image('*1',Pattern,1,20,230,30,False); Image('*2',Pattern,1,20,150,30,False);
    Keyword := Group('右手',C); Pattern := Group('ソロ',Keyword); Image('*1',Pattern,2,20,30,230,False); Image('*2',Pattern,2,20,30,150,False);
    Keyword := Group('表情',A); Image('通常という名前は任意',Keyword,3,80,80,80,True); Image('*笑顔',Keyword,3,230,140,20,False);
    Keyword := Group('表情',C); Image('*笑顔',Keyword,5,230,140,20,False);
    Keyword := Group('ポーズ',A); Image('基本',Keyword,4,80,80,80,True); Image('*お辞儀',Keyword,4,40,180,180,False);
    Keyword := Group('記号',C); Image('*汗',Keyword,6,120,120,230,False);
    Keyword := Group('顔色',A); Image('これが既定',Keyword,7,80,80,80,True);
    Image('胴体素材自由名',A,7,70,70,70,True);
    PSD := TPath.Combine(Root,'common-instrument.psd'); WriteNewPsd(Art,PSD,pcRaw);
  finally Art.Free; end;
  Hash := THashSHA2.GetHashStringFromFile(PSD);
  D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create; ReadBack := TMusicStudioInstrumentData.Create;
  try
    Check(D.LoadFile(PSD),D.LastError); Check(D.InstrumentRules.RowCount=4,'merged row count / visible-only omitted');
    Check(D.InstrumentRules.HasChoice('表情','笑顔') and not D.InstrumentRules.HasChoice('表情','通常という名前は任意'),'hidden choices / display prefix removal');
    Check(not D.InstrumentRules.HasChoice('顔色','これが既定'),'visible default not offered');
    Check(Length(D.InstrumentRules.Stages('右手','ソロ'))=4,'stage union');
    State.Row := '右手'; State.Choice := 'ソロ'; State.Stage := 3;
    V := D.InstrumentRules.Visibility([State]);
    try
      Check(Visible(V,'自由な人物名/右手/ソロ/*3'),'character stage3');
      Check(not Visible(V,'機材XYZ/右手/ソロ/*2') and not Visible(V,'装飾567/右手/ソロ/*2'),'missing stage clears last body/effect phase');
    finally V.Free; end;
    Model.Load('{"lengthBeats":8,"notes":[],"future":"keep"}');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'ソロ'; Block.Stage := 1; Block.StartBeat := 1; Block.EndBeat := 7;
    Check(Model.PutBlock(-1,Block),'action range'); Block.Row := '表情'; Block.Choice := '笑顔'; Block.StartBeat := 2; Block.EndBeat := 4;
    Check(Model.PutBlock(-1,Block),'selection range'); Block.Row := 'ポーズ'; Block.Choice := 'お辞儀'; Block.StartBeat := 3; Block.EndBeat := 5;
    Check(Model.PutBlock(-1,Block),'pose range');
    V := D.InstrumentRules.Visibility(Model.StatesAt(3.5));
    try Check(not V.GetValue<TJSONBool>(LayerKey('自由な人物名/右手')).AsBoolean,'pose suppresses action');
      Check(not Visible(V,'自由な人物名/胴体素材自由名'),'pose replaces ordinary body siblings');
      Check(Visible(V,'自由な人物名/ポーズ/*お辞儀'),'pose selected'); finally V.Free; end;
    V := D.InstrumentRules.Visibility(Model.StatesAt(5.5));
    try Check(Visible(V,'自由な人物名/右手/ソロ/*1'),'pose end restores current action'); Check(Visible(V,'自由な人物名/表情/通常という名前は任意'),'selection end restores PSD defaults'); finally V.Free; end;
    Text := Model.JSON; ReadBack.Load(Text); Check(ReadBack.JSON=Text,'stable save reload and unknown fields');
    Before := ReadBack.JSON; Block.StartBeat := 3.1; Check(not ReadBack.PutBlock(-1,Block),'overlap rejected');
    try ReadBack.Load('{"lengthBeats":-1}'); except on E: Exception do ; end; Check(ReadBack.JSON=Before,'invalid load atomic');
    Clone := D.Clone; try Check(Clone.InstrumentRules.DiagnosticJSON=D.InstrumentRules.DiagnosticJSON,'clone preserves parsed rows'); finally Clone.Free; end;
    Dialog := TMusicStudioPatternSettings.Create(nil);
    try
      P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '全楽器共通'; P.Color := '#90C4E0'; P.ConfigJSON := '{"lengthBeats":8,"notes":[]}';
      Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(P,'11111111-1111-1111-1111-111111111111',PSD,'{}',120);
      Dialog.Show; Deadline := GetTickCount64+5000;
      repeat Application.ProcessMessages; Check(GetTickCount64<Deadline,'automatic common editor route'); Sleep(2); until Dialog.InstrumentFrame<>nil;
      F := Dialog.InstrumentFrame; Check(F.Rules.RowCount=4,'UI generated rows');
      Row := -1; for I := 0 to F.Rules.RowCount-1 do if F.Rules.RowAt(I).Name='右手' then Row := I;
      Y := 28+Row*F.TimelineRowHeight+10;
      Mouse(WM_LBUTTONDOWN,XBeat(1)+1,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,XBeat(2),Y,MK_LBUTTON); Mouse(WM_LBUTTONUP,XBeat(2),Y);
      Check((F.Data.Blocks.Count=1) and (F.Data.Blocks[0].Row='右手'),'native interval creation on generated row');
      Before := F.ConfigJSON; Key := VK_DELETE; F.HandleKey(Key,[]); Check(F.Data.Blocks.Count=0,'delete block');
      Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]); Check(F.ConfigJSON=Before,'UI undo');
      F.BindRules(D.InstrumentRules); Check(F.ConfigJSON=Before,'PSD candidate refresh preserves blocks');
      Dialog.ReadPattern(P); ReadBack.Load(P.ConfigJSON); Check(ReadBack.Blocks.Count=1,'parent saves common intervals');
      Bitmap := TBitmap.Create; PNG := TPngImage.Create;
      try
        Bitmap.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(Bitmap.Canvas,0,0); PNG.Assign(Bitmap); PNG.SaveToFile(TPath.Combine(Root,'common-editor.png'));
      finally PNG.Free; Bitmap.Free; end;
      Dialog.Hide;
    finally Dialog.Free; end;
    Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'library')); Doc := TMusicStudioDocument.Create;
    Cache := TMusicStudioVisualCache.Create; Scene := TMusicStudioPsdSceneCache.Create;
    try
      Check(Store.TryImport(PSD,'共通テスト','#90C4E0',Asset,Duplicate,Error),Error);
      Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance');
      Model.BindAsset(Asset.ID); Index := Doc.AddPerformance; P := Doc.PatternAt(Index); P.ConfigJSON := Model.JSON; Doc.UpdatePattern(P);
      Check(Doc.AddBeatPlacement(Track,Slot,P.ID,0,8,Error),Error); Check(Doc.TrySave(Text,Error),Error);
      Check(Doc.TryLoad(Text,Error),Error); Scene.Bind(Doc,Store,Cache); SceneAt(2.5);
      Check((AlphaAt(Scene.ImageForTrack(Track),0)>0) and (AlphaAt(Scene.ImageForTrack(Track),1)>0) and (AlphaAt(Scene.ImageForTrack(Track),2)>0),'scene synchronized arbitrary roots');
      SceneAt(3.5); Check((AlphaAt(Scene.ImageForTrack(Track),0)=0) and (AlphaAt(Scene.ImageForTrack(Track),4)>0),'scene pose masks performance');
      SceneAt(5.5); Check(AlphaAt(Scene.ImageForTrack(Track),0)>0,'scene pose end resumes');
      TFile.WriteAllText(TPath.Combine(Root,'common-project.json'),Text,TEncoding.UTF8);
    finally Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    Check(Hash=THashSHA2.GetHashStringFromFile(PSD),'source PSD unchanged');
    TFile.WriteAllText(TPath.Combine(Root,'common-analysis.json'),D.InstrumentRules.DiagnosticJSON,TEncoding.UTF8);
    Writeln('INSTRUMENT_RECURSIVE_ROWS_CHOICES_STAGE_LINK_DEFAULT_POSE_UI_SAVE_SCENE_NO_AUDIO_OK');
  finally ReadBack.Free; Model.Free; D.Free; end;
end;
type TCompactSaveDriver = class
  Timer: TTimer;
  Failure: string;
  Done,NoChange: Boolean;
  procedure Tick(Sender: TObject);
end;
procedure TCompactSaveDriver.Tick(Sender: TObject);
var I,Y: Integer; D: TMusicStudioPatternSettings; F: TMusicStudioInstrumentFrame;
begin
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]);
    try
      if D.InstrumentFrame=nil then Exit;
      if NoChange then begin Done := True; Timer.Enabled := False; D.Close; Exit; end;
      D.NameEdit.Text := '編集完了'; F := D.InstrumentFrame; F.SelectChoice(0,2);
      Y := 28+F.TimelineRowHeight div 2;
      F.Grid.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(F.BeatToX(4),Y));
      F.Grid.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(F.BeatToX(6),Y));
      F.Grid.Perform(WM_LBUTTONUP,0,MakeLParam(F.BeatToX(6),Y));
      Done := True; Timer.Enabled := False; D.Close;
    except on E: Exception do begin Failure := E.Message; Timer.Enabled := False; D.ModalResult := mrCancel; end; end;
    Exit;
  end;
end;
procedure RunCompactEditorChecks(const Root: string);
var Art: TArtDocument; Actor,G,Choice,L: TArtLayer; Row,Name,Error,Text,Before,After,PSD: string;
  UI: TFormMusicStudioSettings; D: TMusicStudioLayerDocument; Dialog: TMusicStudioPatternSettings;
  F: TMusicStudioInstrumentFrame; Model: TMusicStudioInstrumentData; B: TInstrumentBlock;
  Store: TMusicStudioPerformanceLibrary; Journal: TMusicStudioPerformanceHistory;
  P,Original,Saved,External,Empty,Song: TMusicStudioPattern; A: TMusicStudioPsdAsset; Duplicate: Boolean;
  I,J,N,Perf,Sing,Expr,Y,X,LeftRow,RightRow,Token,Notes,Parts: Integer; Accept: Boolean; Key: Word; Driver: TCompactSaveDriver;
  Bitmap: TBitmap; PNG: TPngImage; Deadline: UInt64;
  function Slot(Track: Integer; const Kind: string): Integer;
  var K: Integer;
  begin
    for K := 0 to High(UI.Document.TrackAt(Track).Slots) do
      if UI.Document.TrackAt(Track).Slots[K].Kind=Kind then Exit(K);
    raise Exception.Create('slot missing '+Kind);
  end;
  procedure GridMouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin F.Grid.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure Drag(A,Z: Double; RowIndex: Integer);
  var Y: Integer;
  begin
    Y := 28+RowIndex*F.TimelineRowHeight+F.TimelineRowHeight div 2;
    GridMouse(WM_LBUTTONDOWN,F.BeatToX(A),Y,MK_LBUTTON);
    GridMouse(WM_MOUSEMOVE,F.BeatToX(Z),Y,MK_LBUTTON);
    GridMouse(WM_LBUTTONUP,F.BeatToX(Z),Y);
  end;
  procedure Screenshot(Form: TForm; const FileName: string);
    procedure PrintButtons(Parent: TWinControl);
    var I,SavedDC: Integer; C: TControl; Origin: TPoint;
    begin
      for I := 0 to Parent.ControlCount-1 do begin
        C := Parent.Controls[I]; if not C.Visible then Continue;
        if C is TButton then begin
          Origin := Form.ScreenToClient(C.ClientToScreen(Point(0,0))); SavedDC := SaveDC(Bitmap.Canvas.Handle);
          try SetViewportOrgEx(Bitmap.Canvas.Handle,Origin.X,Origin.Y,nil);
            TButton(C).Perform(WM_PRINTCLIENT,Bitmap.Canvas.Handle,PRF_CLIENT);
          finally RestoreDC(Bitmap.Canvas.Handle,SavedDC); end;
        end else if C is TWinControl then PrintButtons(TWinControl(C));
      end;
    end;
  begin
    Bitmap := TBitmap.Create; PNG := TPngImage.Create;
    try Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); Form.PaintTo(Bitmap.Canvas,0,0); PrintButtons(Form);
      PNG.Assign(Bitmap); PNG.SaveToFile(TPath.Combine(Root,FileName));
    finally PNG.Free; Bitmap.Free; end;
  end;
begin
  ForceDirectories(Root); PSD := TPath.Combine(Root,'compact.psd'); Art := TArtDocument.Create;
  try
    Art.Width := 8; Art.Height := 2;
    Actor := Art.AddLayer(alkGroup,'演奏者',TArtBounds.Create(0,0,8,2),nil); Actor.Visible := True;
    for Row in ['右手','左手','表情','顔色','ポーズ','記号'] do begin
      G := Art.AddLayer(alkGroup,Row,TArtBounds.Create(0,0,8,2),Actor); G.Visible := True;
      for Name in ['候補A','候補B','候補C'] do begin
        Choice := Art.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,8,2),G); Choice.Visible := True;
        for I := 0 to 2 do begin
          L := Art.AddLayer(alkImage,'*'+IntToStr(I),TArtBounds.Create(I,0,I+1,1),Choice);
          L.Visible := I=0; L.Pixels := TBytes.Create(100,150,200,255);
        end;
      end;
    end;
    WriteNewPsd(Art,PSD,pcRaw);
  finally Art.Free; end;
  UI := TFormMusicStudioSettings.Create(nil); D := TMusicStudioLayerDocument.Create;
  Model := TMusicStudioInstrumentData.Create; Driver := TCompactSaveDriver.Create;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Dialog := nil; Store := nil; Journal := nil;
  try
    Check(D.LoadFile(PSD),D.LastError); UI.SilentVisualMode := True;
    UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Check(UI.SharedLibrary.TryImport(PSD,'演奏者','#90C4E0',A,Duplicate,Error),Error);
    for I := 0 to 4 do begin
      N := UI.Document.AddTrack('performer'); UI.Document.AssignPsd(N,A.ID);
      UI.Document.SetPerformer(N,'drums',['singing','performance','emotion','face','pose','symbol']);
    end;
    Perf := Slot(0,'performance'); Sing := Slot(0,'singing'); Expr := Slot(0,'emotion');
    B := Default(TInstrumentBlock); B.Row := '右手'; B.Choice := '候補A'; B.EndBeat := 2;
    Check(Model.PutBlock(-1,B),'fixture block');
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '編集前'; P.Color := '#EDBA70';
    P.PerformanceAttribute := 'drums'; P.ConfigJSON := Model.JSON;
    Store := TMusicStudioPerformanceLibrary.Create(UI.LibraryRoot); Check(Store.TrySave(P,Error),Error); Original := P;
    J := UI.Document.ImportPerformance(P);
    for I := 0 to 4 do Check(UI.Document.AddBeatPlacement(I,Slot(I,'performance'),UI.Document.PatternAt(J).ID,0,4,Error),Error);
    Text := TPath.Combine(Root,'singing.mid');
    TFile.WriteAllBytes(Text,TBytes.Create($4D,$54,$68,$64,0,0,0,6,0,0,0,1,1,$E0,
      $4D,$54,$72,$6B,0,0,0,18,0,$FF,5,1,97,0,$90,60,100,$87,$40,$80,60,0,0,$FF,$2F,0));
    J := UI.Document.AddSinging; Song := UI.Document.PatternAt(J); Song.FilePath := Text;
    Song.Name := '歌唱'; Song.SourceTrack := 0; Song.Duration := 1; UI.Document.UpdatePattern(Song);
    for I := 0 to 2 do Check(UI.Document.AddPlacement(I*2,Slot(I*2,'singing'),Song.ID,0,1,Error),Error);
    Check(UI.Document.TrySave(Text,Error),Error); UI.LoadDocument(Text);
    UI.ClientWidth := 1240; UI.ClientHeight := 820; UI.Show; Application.ProcessMessages;
    Check(not UI.TimelineBox.TrackExpanded(0),'initial auto expansion');
    UI.TimelineBox.SelectSlot(0,Perf); Check(not UI.TimelineBox.TrackExpanded(0),'select auto expansion');
    X := UI.TimelineBox.TrackThumbnailRect(0).CenterPoint.X; Y := UI.TimelineBox.TrackThumbnailRect(0).CenterPoint.Y;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,Y)); UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(X,Y));
    Check((UI.LibraryKind='psd') and not UI.TimelineBox.TrackExpanded(0),'PSD image context expanded track');
    UI.PatternList.ItemIndex := 0; Accept := False;
    UI.TimelineBox.OnDragOver(UI.TimelineBox,UI.PatternList,X,Y,dsDragMove,Accept); Check(Accept,'PSD track header drop rejected');
    for I := 0 to UI.ComponentCount-1 do if UI.Components[I] is TButton then
      if TButton(UI.Components[I]).Caption='演奏' then TButton(UI.Components[I]).Click;
    Check((UI.LibraryKind='performance') and not UI.TimelineBox.TrackExpanded(0),'library tab did not select hidden context');
    Check(UI.TimelineBox.SlotRowTop(0,Slot(0,'psd'))=-1,'PSD row visible');
    UI.TimelineBox.ToggleTrack(0);
    Check(UI.TimelineBox.SlotRowTop(0,Sing)<UI.TimelineBox.SlotRowTop(0,Perf),'singing before performance');
    Check(UI.TimelineBox.SlotRowTop(0,Perf)<UI.TimelineBox.SlotRowTop(0,Expr),'performance before expression');
    Check(UI.TimelineBox.TrackRowTop(4)+UI.TimelineBox.RowHeight<UI.TimelineBox.ClientHeight-17,'five tracks / one expanded not fitting');
    UI.TimelineBox.SelectTrack(1); Check(UI.TimelineBox.TrackExpanded(0) and not UI.TimelineBox.TrackExpanded(1),'selection changed manual expansion');
    X := 12; Y := UI.TimelineBox.TrackRowTop(0)+12;
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(X,Y));
    Check(not UI.TimelineBox.TrackExpanded(0),'minus click');
    Deadline := GetTickCount64+5000;
    repeat UI.TimelineBox.PollWaveforms; Application.ProcessMessages; Sleep(5);
      Check(GetTickCount64<Deadline,'singing roll timeout');
    until UI.TimelineBox.VisualCache.MidiMessage(UI.TimelineBox.VisualCache.Find(vkMidi,Song.FilePath),0)='';
    Bitmap := TBitmap.Create;
    try
      Bitmap.SetSize(UI.TimelineBox.Width,UI.TimelineBox.Height); UI.TimelineBox.PaintTo(Bitmap.Canvas,0,0);
      Notes := 0; Parts := 0;
      for Y := UI.TimelineBox.TrackRowTop(0)+1 to UI.TimelineBox.TrackRowTop(0)+UI.TimelineBox.RowHeight-2 do
        for X := UI.TimelineBox.HeaderWidth+2 to UI.TimelineBox.HeaderWidth+30 do begin
          if ColorToRGB(Bitmap.Canvas.Pixels[X,Y])=$00F4F4F4 then Inc(Notes);
          if ColorToRGB(Bitmap.Canvas.Pixels[X,Y])=$00C98B55 then Inc(Parts);
        end;
      Check((Notes>0) and (Parts>0),'summary failed to overlay singing on colored performance');
    finally Bitmap.Free; end;
    X := UI.TimelineBox.HeaderWidth+10; Y := UI.TimelineBox.TrackRowTop(0)+UI.TimelineBox.RowHeight div 2;
    Check(UI.TimelineBox.SlotAtPoint(X,Y)=Sing,'summary singing hit priority');
    UI.TimelineBox.SelectSlot(0,Perf); UI.PatternList.ItemIndex := 0;
    Accept := False; UI.TimelineBox.OnDragOver(UI.TimelineBox,UI.PatternList,X,Y,dsDragMove,Accept);
    Check(Accept,'collapsed performance drop collided with singing');
    UI.TimelineBox.ToggleTrack(0); UI.TimelineBox.SelectSlot(0,Perf);
    Screenshot(UI,'compact-five-tracks.png');
    Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True;
    Dialog.LoadPerformanceSteps(P,A.ID,A.FilePath,A.ConfigJSON,120); Dialog.Show;
    // Preview loader creates the common frame asynchronously.
    N := 0; while (Dialog.InstrumentFrame=nil) and (N<500) do begin Application.ProcessMessages; Sleep(10); Inc(N); end;
    Check(Dialog.InstrumentFrame<>nil,'instrument frame not ready'); F := Dialog.InstrumentFrame;
    LeftRow := -1; RightRow := -1;
    for I := 0 to F.Rules.RowCount-1 do begin
      if F.Rules.RowAt(I).Name='左手' then LeftRow := I;
      if F.Rules.RowAt(I).Name='右手' then RightRow := I;
    end;
    Check((LeftRow>=0) and (RightRow>=0),'hand rows');
    F.SelectChoice(LeftRow,2); Drag(4,6,LeftRow);
    Check(F.Data.Blocks.Last.Choice='候補B','first remembered choice');
    F.SelectChoice(RightRow,3); Drag(8,10,RightRow); Drag(12,14,LeftRow);
    Check((F.Data.Blocks.Last.Choice='候補B') and (F.LastChoiceIndex('右手')=3),'independent remembered choice');
    Before := F.Data.JSON; N := F.Data.Blocks.Count;
    Y := 28+LeftRow*F.TimelineRowHeight+F.TimelineRowHeight div 2;
    GridMouse(WM_RBUTTONDOWN,F.BeatToX(13),Y,MK_RBUTTON); GridMouse(WM_RBUTTONUP,F.BeatToX(13),Y);
    Check(F.Data.Blocks.Count=N-1,'right click delete'); Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]);
    Check(F.Data.JSON=Before,'delete undo'); Key := Ord('Y'); F.HandleKey(Key,[ssCtrl]);
    Check(F.Data.Blocks.Count=N-1,'delete redo');
    Deadline := GetTickCount64+5000;
    while Dialog.InstrumentPreview.Busy do begin Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'pattern preview timeout'); end;
    Screenshot(Dialog,'indexed-patterns.png'); Dialog.ClientWidth := 860; Dialog.ClientHeight := 560; Application.ProcessMessages;
    for I := 0 to F.ComponentCount-1 do if F.Components[I] is TButton then
      Check(TButton(F.Components[I]).BoundsRect.Right<=TButton(F.Components[I]).Parent.ClientWidth,'minimum header button clipped');
    Screenshot(Dialog,'indexed-patterns-minimum.png'); Dialog.Hide; FreeAndNil(Dialog);
    Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True;
    External := Original; External.ConfigJSON := '{"lengthBeats":16,"notes":[]}'; Dialog.LoadPattern(External);
    Dialog.PerformanceFrame.AddNote(1,1,60,100); Dialog.PerformanceFrame.AddNote(3,1,64,100);
    Key := Ord('Z'); Dialog.PerformanceFrame.HandleKey(Key,[ssCtrl]); Check(Dialog.PerformanceFrame.Data.NoteCount=1,'legacy note undo');
    Key := Ord('Y'); Dialog.PerformanceFrame.HandleKey(Key,[ssCtrl]); Check(Dialog.PerformanceFrame.Data.NoteCount=2,'legacy note redo');
    FreeAndNil(Dialog); Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True; Dialog.LoadPattern(Song);
    Dialog.SingingFrame.SelectFile(''); Key := Ord('Z'); Dialog.SingingFrame.HandleKey(Key,[ssCtrl]);
    Check(Dialog.SingingFrame.FilePath=Song.FilePath,'singing reference undo');
    Deadline := GetTickCount64+5000;
    while Dialog.SingingFrame.IsLoading do begin Dialog.SingingFrame.PollResults; Sleep(1); Check(GetTickCount64<Deadline,'singing undo load'); end;
    Key := Ord('Y'); Dialog.SingingFrame.HandleKey(Key,[ssCtrl]); Check(Dialog.SingingFrame.FilePath='','singing async redo');
    FreeAndNil(Dialog);
    // Actual modal edit is one integrated step; closing destroys the local frame/history.
    UI.TimelineBox.SelectSlot(0,Perf); UI.PatternList.ItemIndex := 0; UI.PatternList.OnClick(UI.PatternList);
    Before := UI.JSONMemo.Text; Driver.Timer.Interval := 30; Driver.Timer.OnTimer := Driver.Tick; Driver.Timer.Enabled := True;
    UI.EditButton.Click; Check(Driver.Done and (Driver.Failure=''),'modal '+Driver.Failure);
    After := UI.JSONMemo.Text; Check(Before<>After,'modal did not change document');
    Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error); Check(Saved.Name='編集完了','shared save');
    Driver.NoChange := True; Driver.Done := False; Driver.Timer.Enabled := True;
    UI.EditButton.Click; Check(Driver.Done and (Driver.Failure=''),'unchanged modal '+Driver.Failure);
    Check(UI.JSONMemo.Text=After,'unchanged modal changed document');
    Check(Store.TryRead('drums',P.SharedPatternID,External,Error),Error);
    Check(External.LibraryRevision=Saved.LibraryRevision,'unchanged modal saved new revision');
    UI.UndoEdit; Check(UI.JSONMemo.Text=Before,'integrated modal undo');
    Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error); Check((Saved.Name='編集前') and (Saved.ConfigJSON=Original.ConfigJSON),'shared undo');
    UI.RedoEdit; Check(UI.JSONMemo.Text=After,'integrated modal redo');
    Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error); Check((Saved.Name='編集完了') and (Saved.ConfigJSON<>Original.ConfigJSON),'shared redo');
    External := Saved; External.Name := '外部更新'; Check(Store.TrySave(External,Error),Error);
    UI.UndoEdit; Check(UI.JSONMemo.Text=After,'conflict changed document');
    Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error); Check(Saved.Name='外部更新','conflict overwrote external');
    // Creation can be undone/redone without reverting revisions from previous saves.
    Journal := TMusicStudioPerformanceHistory.Create(UI.LibraryRoot); Empty := Default(TMusicStudioPattern);
    P := Original; P.SharedPatternID := ''; P.LibraryRevision := ''; Check(Store.TrySave(P,Error),Error);
    Token := Journal.RecordSaved(Empty,P); Check(Journal.Apply(Token,True,Error),Error);
    Check(not Store.TryRead('drums',P.SharedPatternID,Saved,Error),'new entry still exists');
    Check(Journal.Apply(Token,False,Error),Error); Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error);
    Check(SameMusicStudioPerformance(P,Saved),'creation redo body');
    P := Saved; P.Name := '二度目'; Check(Store.TrySave(P,Error),Error);
    J := Journal.RecordSaved(Saved,P); Check(Journal.Apply(J,True,Error),Error);
    Check(Journal.Apply(Token,True,Error),Error); Check(Journal.Apply(Token,False,Error),Error);
    Check(Journal.Apply(J,False,Error),Error);
    Check(Store.TryRead('drums',P.SharedPatternID,Saved,Error),Error); Check(Saved.Name='二度目','chained revision redo');
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'compact editor used audio');
    TFile.WriteAllText(TPath.Combine(Root,'compact-result.txt'),'PASS: compact layout, manual expansion, PSD hidden, indexed choices, per-limb memory, delete/undo, modal undo/redo, shared conflict and creation',TEncoding.UTF8);
    Writeln('COMPACT_EDITOR_OK');
  finally
    Driver.Timer.Free; Driver.Free; Dialog.Free; Journal.Free; Store.Free; Model.Free; D.Free; UI.Free;
  end;
end;
end.
