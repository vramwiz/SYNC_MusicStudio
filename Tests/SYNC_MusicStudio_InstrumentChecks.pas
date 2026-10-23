unit SYNC_MusicStudio_InstrumentChecks;
// 共通PSDの専用無音ケース。実素材/実共有設定/DPI試験を使用しない。
interface
procedure RunInstrumentChecks(const Root: string);
procedure InspectInstrumentPSD(const Root,Path: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentFrame,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache;
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
end.
