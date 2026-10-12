unit SYNC_MusicStudio_PsdSceneChecks;

// Temp隔離の合成PSD/歌詞MIDIで共有口形・表情・変形と世代破棄を無音検証する。
// PCM/MP3/waveOut/試聴を参照しない。Runは親の直列検証ホストが担当する。
interface
procedure RunMusicStudioPsdSceneChecks(const OutputDir: string);
implementation

uses Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  System.JSON, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_VisualCache,
  SYNC_MusicStudio_MotionData, SYNC_MusicStudio_ProjectData;

procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('PSD scene: '+Message); end;

procedure WriteSceneFixture(const Path: string; NormalRed: Byte = 0);
var Doc: TArtDocument; Mouth,Expression: TArtLayer;
  procedure Image(const Name: string; X,Y,W,H: Integer; R,G,B: Byte; Visible: Boolean);
  var Layer,Parent: TArtLayer; I: Integer;
  begin
    if X<20 then Parent := Mouth else Parent := Expression;
    Layer := Doc.AddLayer(alkImage,Name,TArtBounds.Create(X,Y,X+W,Y+H),Parent);
    Layer.Visible := Visible; SetLength(Layer.Pixels,W*H*4);
    for I := 0 to W*H-1 do begin
      Layer.Pixels[I*4] := R; Layer.Pixels[I*4+1] := G;
      Layer.Pixels[I*4+2] := B; Layer.Pixels[I*4+3] := 255;
    end;
  end;
begin
  Doc := TArtDocument.Create;
  try
    Doc.Width := 64; Doc.Height := 40;
    Mouth := Doc.AddLayer(alkGroup,'口',TArtBounds.Create(4,8,12,14));
    Expression := Doc.AddLayer(alkGroup,'表情',TArtBounds.Create(24,8,32,14));
    Image('*通常',4,8,8,6,NormalRed,255,0,True);
    Image('*あ',4,8,8,6,255,0,0,False);
    Image('*い',4,8,8,6,0,0,255,False);
    Image('*普通の表情',24,8,8,6,255,255,0,True);
    Image('*笑顔',24,8,8,6,0,255,255,False);
    WriteNewPsd(Doc,Path,pcRaw);
  finally Doc.Free; end;
end;

procedure WriteLyricMidi(const Path: string);
const Data: array[0..57] of Byte = (
  $4D,$54,$68,$64,0,0,0,6,0,0,0,1,$01,$E0,
  $4D,$54,$72,$6B,0,0,0,36,
  0,$FF,5,3,$E3,$81,$82,0,$90,60,100,
  $83,$60,$80,60,0,0,$FF,5,3,$E3,$81,$84,0,$90,64,100,
  $83,$60,$80,64,0,0,$FF,$2F,0);
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(Path,fmCreate);
  try Stream.WriteBuffer(Data,SizeOf(Data)); finally Stream.Free; end;
end;

function LayerKey(Document: TMusicStudioLayerDocument; const Name: string): string;
var Layer: TMusicStudioLayerInfo;
begin Result := ''; for Layer in Document.Layers do if Layer.Name=Name then Exit(Layer.Key); end;

procedure Pixel(Image: TBitmap; X,Y: Integer; R,G,B: Byte; const Message: string);
var Row: PByte;
begin
  Check(Image<>nil,Message+' image missing'); Row := Image.ScanLine[Y];
  Check((Row[X*4]=B) and (Row[X*4+1]=G) and (Row[X*4+2]=R) and (Row[X*4+3]=255),Message);
end;

function ImageHash(Image: TBitmap): string;
var Data: TBytes; Y: Integer; Stream: TBytesStream;
begin
  SetLength(Data,Image.Width*Image.Height*4);
  for Y := 0 to Image.Height-1 do Move(PByte(Image.ScanLine[Y])^,Data[Y*Image.Width*4],Image.Width*4);
  Stream := TBytesStream.Create(Data);
  try Result := THashSHA2.GetHashString(Stream); finally Stream.Free; end;
end;

procedure SaveImage(Image: TBitmap; const Path: string);
var PNG: TPngImage;
begin PNG := TPngImage.Create; try PNG.Assign(Image); PNG.SaveToFile(Path); finally PNG.Free; end; end;

procedure AwaitScene(Scene: TMusicStudioPsdSceneCache; Midi: TMusicStudioVisualCache);
var Deadline: UInt64; I: Integer; Ready: Boolean;
begin
  Deadline := GetTickCount64+15000;
  repeat
    if Midi<>nil then Midi.Poll;
    Scene.PollResults;
    Check((Scene.ActiveLoadJobs<=2) and (Scene.ActiveRenderJobs<=2),'worker concurrency exceeded');
    Ready := (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0);
    if Midi<>nil then Ready := Ready and (Midi.ActiveJobs=0);
    for I := 0 to 3 do Ready := Ready and (Scene.ImageForTrack(I)<>nil);
    if Ready then Exit;
    Sleep(5);
  until GetTickCount64>=Deadline;
  raise Exception.Create('PSD scene timeout: '+Scene.StatusForTrack(0));
end;

procedure ConfigureAsset(Store: TMusicStudioSharedPsdLibrary; var Asset: TMusicStudioPsdAsset;
  out AKey,IKey: string);
var Document: TMusicStudioLayerDocument; Config,Expression: TJSONObject;
    Error: string; Motion: TMusicStudioMotionConfig; G: TGUID;
begin
  Document := TMusicStudioLayerDocument.Create; Config := ParseMusicStudioPsdConfig('');
  Expression := ParseMusicStudioPsdConfig(''); Motion := TMusicStudioMotionConfig.Create;
  try
    Check(Document.LoadFile(Asset.FilePath),Document.LastError);
    AKey := LayerKey(Document,'*あ'); IKey := LayerKey(Document,'*い');
    MusicStudioAssignMouth(Config,0,LayerKey(Document,'*通常'));
    MusicStudioAssignMouth(Config,1,AKey); MusicStudioAssignMouth(Config,2,IKey);
    Asset.ConfigJSON := Config.ToJSON; SetLength(Asset.Patterns,3);
    CreateGUID(G); Asset.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36)); Asset.Patterns[0].AssetID := Asset.ID;
    Asset.Patterns[0].Kind := 'emotion'; Asset.Patterns[0].Name := '笑顔'; Asset.Patterns[0].Color := '#AABBCC';
    MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Expression,'visibility'),LayerKey(Document,'*普通の表情'),False);
    MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Expression,'visibility'),LayerKey(Document,'*笑顔'),True);
    Asset.Patterns[0].ConfigJSON := Expression.ToJSON;
    Asset.Patterns[1] := Asset.Patterns[0]; CreateGUID(G); Asset.Patterns[1].ID := LowerCase(Copy(GUIDToString(G),2,36));
    Asset.Patterns[1].Kind := 'instrument'; Asset.Patterns[1].Name := '任意の姿勢';
    CreateGUID(G); Asset.Patterns[2].ID := LowerCase(Copy(GUIDToString(G),2,36)); Asset.Patterns[2].AssetID := Asset.ID;
    Asset.Patterns[2].Kind := 'animation'; Asset.Patterns[2].Name := '振り子'; Asset.Patterns[2].Color := '#AABBCC';
    Motion.RhythmType := rmtPendulum; Motion.Strength := 5; Motion.Speed := 2; Motion.OffsetX := 2;
    Asset.Patterns[2].ConfigJSON := Motion.ToJSON;
    Check(Store.TrySave(Asset,Error),Error);
  finally Motion.Free; Expression.Free; Config.Free; Document.Free; end;
end;

procedure ConfigureProject(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  const Asset: TMusicStudioPsdAsset; const MidiPath: string);
var I,J,Slot,Index,Singing: Integer; Pattern: TMusicStudioPattern; Error: string;
begin
  Check(Document.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,Error),Error); Document.AssetResolver := Store.ResolvePath;
  Check(Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":4,"bpm":60}]}',Error),Error);
  Singing := Document.AddSinging; Pattern := Document.PatternAt(Singing);
  Pattern.FilePath := MidiPath; Pattern.SourceTrack := 0; Pattern.Duration := 1; Document.UpdatePattern(Pattern);
  for I := 0 to 4 do begin Index := Document.AddTrack('psd'); Document.AssignPsd(Index,Asset.ID); end;
  for I := 0 to 1 do Check(Document.AddPlacement(I,1,Pattern.ID,2,1,Error),Error);
  for J := 0 to High(Asset.Patterns) do begin
    Pattern := Default(TMusicStudioPattern); Pattern.Kind := Asset.Patterns[J].Kind;
    Pattern.Name := Asset.Patterns[J].Name; Pattern.Color := Asset.Patterns[J].Color;
    Pattern.AssetID := Asset.ID; Pattern.SharedPatternID := Asset.Patterns[J].ID;
    Index := Document.AddReference(Pattern); Pattern := Document.PatternAt(Index);
    Slot := Document.AddSlot(0,Pattern.Kind);
    if J=0 then Check(Document.AddPlacement(0,Slot,Pattern.ID,1,2,Error),Error)
    else if J=1 then Check(Document.AddPlacement(0,Slot,Pattern.ID,3,1,Error),Error)
    else Check(Document.AddPlacement(0,Slot,Pattern.ID,4,1,Error),Error);
  end;
end;

procedure RunMusicStudioPsdSceneChecks(const OutputDir: string);
var Dir,SourcePath,MidiPath,OriginalHash,BeforeJSON,AfterJSON,AKey,IKey,Error: string;
    G: TGUID; Duplicate: Boolean; Asset: TMusicStudioPsdAsset;
    Store: TMusicStudioSharedPsdLibrary; Document: TMusicStudioDocument;
    Scene: TMusicStudioPsdSceneCache; Midi: TMusicStudioVisualCache;
    Request: TMusicStudioVisualRequest; I,Loads,Renders,Compositions: Integer;
    Config: TJSONObject; Base,Expected: TBitmap; Layers: TMusicStudioLayerDocument;
    Motion: TMusicStudioMotionConfig; Transform: TMusicStudioMotionTransform;
begin
  CreateGUID(G); Dir := TPath.Combine(OutputDir,'psd-scene-'+GUIDToString(G)); ForceDirectories(Dir);
  SourcePath := TPath.Combine(Dir,'original.psd'); MidiPath := TPath.Combine(Dir,'lyrics.mid');
  WriteSceneFixture(SourcePath); WriteLyricMidi(MidiPath); OriginalHash := THashSHA2.GetHashStringFromFile(SourcePath);
  Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'library'));
  Document := TMusicStudioDocument.Create; Scene := TMusicStudioPsdSceneCache.Create; Midi := TMusicStudioVisualCache.Create;
  Base := TBitmap.Create; Expected := TBitmap.Create; Layers := TMusicStudioLayerDocument.Create;
  Motion := TMusicStudioMotionConfig.Create;
  try
    Check(Store.TryImport(SourcePath,'無音検証PSD','#AABBCC',Asset,Duplicate,Error),Error);
    ConfigureAsset(Store,Asset,AKey,IKey); ConfigureProject(Document,Store,Asset,MidiPath);
    Check(Document.TrySave(BeforeJSON,Error),Error);
    Request.Kind := vkMidi; Request.Path := MidiPath; Request.Visible := True;
    Midi.SetSources(TArray<TMusicStudioVisualRequest>.Create(Request));
    Scene.Bind(Document,Store,Midi); Scene.SetPosition(0); AwaitScene(Scene,Midi);
    Check(Scene.LoadCount=1,'same PSD decoded more than once for four tracks');
    Check(Scene.ImageForTrack(4)=nil,'fifth PSD track entered bounded scene');
    Pixel(Scene.ImageForTrack(0),5,9,0,255,0,'normal mouth');
    Scene.SetPosition(1.25); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),25,9,0,255,255,'shared expression');
    Scene.SetPosition(2.25); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),5,9,255,0,0,'MIDI local a'); Pixel(Scene.ImageForTrack(1),5,9,255,0,0,'shared a across tracks');
    Scene.SetPosition(2.75); AwaitScene(Scene,Midi); Pixel(Scene.ImageForTrack(0),5,9,0,0,255,'MIDI local i');
    Scene.SetPosition(3); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),5,9,0,255,0,'placement end normal');
    Pixel(Scene.ImageForTrack(0),25,9,0,255,255,'shared instrument visibility');
    Scene.SetPosition(4.25,Document.SecondsToBeat(4.25)); AwaitScene(Scene,Midi);
    Check(Layers.LoadFile(Asset.FilePath),Layers.LastError);
    Check(Layers.Render(Base),Layers.LastError);
    Motion.LoadJSON(Asset.Patterns[2].ConfigJSON);
    CalculateMusicStudioMotionTransform(Motion,0.25,Transform); RenderMusicStudioMotion(Base,Expected,Transform);
    Check(ImageHash(Scene.ImageForTrack(0))=ImageHash(Expected),'motion placement beat after tempo change');
    SaveImage(Scene.ImageForTrack(0),TPath.Combine(OutputDir,'psd-scene-shared-motion.png'));
    Loads := Scene.LoadCount; Renders := Scene.RenderCount; Compositions := Scene.CompositionCount;
    for I := 1 to 100 do begin Check(Scene.ImageForTrack(0)<>nil,'cached image'); Scene.StatusForTrack(0); Scene.PollResults; end;
    Check((Loads=Scene.LoadCount) and (Renders=Scene.RenderCount) and (Compositions=Scene.CompositionCount),'paint regenerated or reloaded PSD');
    Check(Document.TrySave(AfterJSON,Error) and (BeforeJSON=AfterJSON),'scene modified project JSON');
    Config := ParseMusicStudioPsdConfig(Asset.ConfigJSON);
    try MusicStudioAssignMouth(Config,1,IKey); Asset.ConfigJSON := Config.ToJSON; finally Config.Free; end;
    Check(Store.TrySave(Asset,Error),Error);
    Scene.Bind(Document,Store,Midi); Scene.SetPosition(2.25); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),5,9,0,0,255,'shared edited mouth after Bind');
    for I := 1 to 5 do begin Scene.Bind(Document,Store,Midi); Scene.SetPosition(2.25); Check(Scene.ActiveLoadJobs<=2,'reBind load bound'); end;
    AwaitScene(Scene,Midi); Pixel(Scene.ImageForTrack(0),5,9,0,0,255,'old generation did not publish');
    Scene.SetPosition(0); AwaitScene(Scene,Midi);
    WriteSceneFixture(Asset.FilePath,128); Scene.PollResults(True); Check(Scene.ImageForTrack(0)=nil,'changed PSD retained old image');
    AwaitScene(Scene,Midi); Pixel(Scene.ImageForTrack(0),5,9,128,255,0,'changed PSD reloaded');
    TFile.Delete(Asset.FilePath); Scene.PollResults(True);
    Check((Scene.ImageForTrack(0)=nil) and (Scene.StatusForTrack(0)<>''),'missing PSD retained image');
    TFile.Copy(SourcePath,Asset.FilePath,False); Scene.PollResults(True); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),5,9,0,255,0,'missing source recovered');
    // 静的スナップショットはmodel/storeを借用し続けない。
    Scene.Bind(Document,Store,Midi); FreeAndNil(Document); Scene.SetPosition(0); AwaitScene(Scene,Midi);
    Pixel(Scene.ImageForTrack(0),5,9,0,255,0,'model lifetime snapshot');
    Scene.Clear; Scene.PollResults; Check(Scene.ImageForTrack(0)=nil,'Clear published retired result');
    Check(OriginalHash=THashSHA2.GetHashStringFromFile(SourcePath),'original PSD changed');
    Writeln('PSD_SCENE_SHARED_MOUTH_EXPRESSION_MOTION_OK');
    Writeln('PSD_SCENE_GENERATION_PAINT_SNAPSHOT_OK');
  finally
    Scene.Free; Midi.Free; Document.Free; Store.Free; Motion.Free; Layers.Free; Expected.Free; Base.Free;
  end;
end;
end.
