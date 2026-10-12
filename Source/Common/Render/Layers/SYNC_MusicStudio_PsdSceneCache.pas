unit SYNC_MusicStudio_PsdSceneCache;

// UI所有のPSDシーン。Bindで参照JSONを値コピーし、描画は借用画像だけを参照する。
// 読込/合成は最大各2 worker。旧世代も上限に数え、UI callbackや音声を使用しない。
interface

uses Winapi.Windows, System.Classes, System.JSON, System.Generics.Collections,
  Vcl.Graphics, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_MotionData,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerJobs, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_LayerStepData;

type
  TMusicStudioSceneBeatResolver = function(Seconds: Double): Double of object;
  TMusicStudioSceneTransforms = TArray<TMusicStudioMotionTransform>;

  TMusicStudioSceneRenderJob = class(TThread)
  private
    FDocument: TMusicStudioLayerDocument;
    FOverrides: TJSONObject;
    FBase, FImage: TBitmap;
    FTransforms: TMusicStudioSceneTransforms;
    FStarted: Boolean;
    FMaximumDimension: Integer;
  protected
    procedure Execute; override;
  public
    BindGeneration, SourceGeneration, RequestGeneration, TrackIndex: Integer;
    SourceKey, BaseKey, ImageKey, ErrorText: string;
    Composed: Boolean;
    constructor Create(Document: TMusicStudioLayerDocument; Overrides: TJSONObject;
      CachedBase: TBitmap; const Transforms: TMusicStudioSceneTransforms;
      MaximumDimension: Integer = 512);
    destructor Destroy; override;
    procedure Start; reintroduce;
    function TakeBase: TBitmap;
    function TakeImage: TBitmap;
  end;

  TMusicStudioSceneSource = class
  public
    Key, Path, Fingerprint, ErrorText, ConfigError: string;
    Generation: Integer;
    NeedLoad: Boolean;
    Document: TMusicStudioLayerDocument;
    Config: TJSONObject;
    LoadJob: TMusicStudioPsdLayerLoadJob; // Job listが所有する。
    BaseImages: TObjectDictionary<string,TBitmap>;
    constructor Create;
    destructor Destroy; override;
  end;

  TMusicStudioScenePlacement = class
  public
    ID, Kind, MidiPath, ErrorText: string;
    StartSeconds, LengthSeconds, StartBeat: Double;
    MidiTrack: Integer;
    Visibility: TJSONObject;
    Steps: TMusicStudioLayerStepData;
    StepConfigs: TObjectList<TJSONObject>;
    Motion: TMusicStudioMotionConfig;
    destructor Destroy; override;
  end;

  TMusicStudioSceneTrack = class
  public
    TrackIndex, RequestGeneration: Integer;
    Source: TMusicStudioSceneSource; // Scene source listが所有する。
    Placements: TObjectList<TMusicStudioScenePlacement>;
    Image: TBitmap;
    Overrides: TJSONObject;
    Transforms: TMusicStudioSceneTransforms;
    BaseKey, DesiredKey, ImageKey, ErrorText, WarningText: string;
    NeedRender: Boolean;
    RenderJob: TMusicStudioSceneRenderJob; // Job listが所有する。
    constructor Create;
    destructor Destroy; override;
  end;

  TMusicStudioPsdSceneCache = class
  private
    FSources: TObjectList<TMusicStudioSceneSource>;
    FTracks: TObjectList<TMusicStudioSceneTrack>;
    FLoads: TObjectList<TMusicStudioPsdLayerLoadJob>;
    FRenders: TObjectList<TMusicStudioSceneRenderJob>;
    FMidiCache: TMusicStudioVisualCache; // 借用。Clearしてから先方を破棄する。
    FTiming: TMusicStudioTempoMap; // Bind時に複製。Documentの寿命に依存しない。
    FBeatResolver: TMusicStudioSceneBeatResolver;
    FSeconds, FBeatPosition, FTempoBPM: Double;
    FGeneration, FNextGeneration, FSerial, FLoadCount, FRenderCount,
      FCompositionCount, FNextTrack: Integer;
    FLastFileCheck: UInt64;
    FFrozenSources: Boolean;
    FMaximumImageDimension: Integer;
    function TrackFor(Index: Integer): TMusicStudioSceneTrack;
    function SourceFor(const Key: string): TMusicStudioSceneSource;
    procedure StartJobs;
    procedure RefreshTrack(Track: TMusicStudioSceneTrack);
    procedure ResetSource(Source: TMusicStudioSceneSource; const Stamp: string);
    function MouthAt(Placement: TMusicStudioScenePlacement): Integer;
    function StartBeat(Seconds: Double): Double;
  public
    constructor Create;
    destructor Destroy; override;
    // Document/Storeは保持しない。共有変更後は再Bindする。TempoBPMは明示された一定テンポ。
    procedure Bind(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
      MidiCache: TMusicStudioVisualCache; TempoBPM: Double = 120);
    procedure SetPosition(Seconds: Double); overload;
    // 可変テンポではBeatResolverを設定し、親のTimingMapから現在拍と開始拍を渡す。
    procedure SetPosition(Seconds, BeatPosition: Double); overload;
    function PollResults(CheckFiles: Boolean = False): Boolean;
    // 実トラック番号で参照。画像は次の位置/Bind/Poll/Clearまで借用。保持にはAssignする。
    function ImageForTrack(TrackIndex: Integer): TBitmap;
    function StatusForTrack(TrackIndex: Integer): string;
    function ActiveLoadJobs: Integer;
    function ActiveRenderJobs: Integer;
    procedure Clear;
    property BeatResolver: TMusicStudioSceneBeatResolver read FBeatResolver write FBeatResolver;
    property Serial: Integer read FSerial;
    property LoadCount: Integer read FLoadCount;
    property RenderCount: Integer read FRenderCount;
    property CompositionCount: Integer read FCompositionCount;
    // 映像ホスト専用。Bind後の外部ファイル監視を停止し、再Bindで明示的に更新する。
    property FrozenSources: Boolean read FFrozenSources write FFrozenSources;
    // 0ならPSD本来の解像度。編集プレビューの既定値512は維持する。
    property MaximumImageDimension: Integer read FMaximumImageDimension write FMaximumImageDimension;
  end;

implementation

uses System.SysUtils, System.Math, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_BitmapCache;

procedure SmallImage(Source, Dest: TBitmap; MaximumDimension: Integer);
var Factor: Double; X,Y,W,H,SX,SY: Integer; Row,SourceRow: PByte;
begin
  Factor := 1;
  if MaximumDimension>0 then Factor := Min(1.0,MaximumDimension/Max(Source.Width,Source.Height));
  W := Max(1,Round(Source.Width*Factor)); H := Max(1,Round(Source.Height*Factor));
  Dest.PixelFormat := pf32bit; Dest.SetSize(W,H); Dest.AlphaFormat := afPremultiplied;
  for Y := 0 to H-1 do begin
    SY := Int64(Y)*Source.Height div H; SourceRow := Source.ScanLine[SY]; Row := Dest.ScanLine[Y];
    for X := 0 to W-1 do begin SX := Int64(X)*Source.Width div W; Move(SourceRow[SX*4],Row[X*4],4); end;
  end;
end;

constructor TMusicStudioSceneRenderJob.Create(Document: TMusicStudioLayerDocument;
  Overrides: TJSONObject; CachedBase: TBitmap; const Transforms: TMusicStudioSceneTransforms;
  MaximumDimension: Integer);
begin
  inherited Create(True); FreeOnTerminate := False;
  FTransforms := Copy(Transforms);
  FMaximumDimension := MaximumDimension;
  if CachedBase<>nil then begin FBase := TBitmap.Create; FBase.Assign(CachedBase); end
  else begin FDocument := Document.Clone; FOverrides := TJSONObject(Overrides.Clone); end;
end;

procedure TMusicStudioSceneRenderJob.Start;
begin FStarted := True; inherited Start; end;

destructor TMusicStudioSceneRenderJob.Destroy;
begin
  Terminate; if not FStarted then Start; if not Finished then WaitFor;
  FDocument.Free; FOverrides.Free; FBase.Free; FImage.Free; inherited;
end;

procedure TMusicStudioSceneRenderJob.Execute;
var Full,Next: TBitmap; Transform: TMusicStudioMotionTransform;
begin
  if Terminated then Exit;
  Full := nil; Next := nil;
  try
    try
      if FBase=nil then begin
        Full := TBitmap.Create;
        if not FDocument.Render(Full,FOverrides) then begin ErrorText := FDocument.LastError; Exit; end;
        FBase := TBitmap.Create; SmallImage(Full,FBase,FMaximumDimension); Composed := True;
      end;
      if Terminated then Exit;
      FImage := TBitmap.Create; FImage.Assign(FBase);
      for Transform in FTransforms do begin
        if Terminated then Exit;
        // Transform値は縮小キャンバス座標に事前変換済み。
        Next := TBitmap.Create; RenderMusicStudioMotion(FImage,Next,Transform);
        FImage.Free; FImage := Next; Next := nil;
      end;
    except on E: Exception do begin ErrorText := E.Message; FreeAndNil(FImage); end; end;
  finally Full.Free; Next.Free; end;
end;

function TMusicStudioSceneRenderJob.TakeBase: TBitmap;
begin Result := FBase; FBase := nil; end;
function TMusicStudioSceneRenderJob.TakeImage: TBitmap;
begin Result := FImage; FImage := nil; end;

constructor TMusicStudioSceneSource.Create;
begin inherited; BaseImages := TObjectDictionary<string,TBitmap>.Create([doOwnsValues]); end;
destructor TMusicStudioSceneSource.Destroy;
begin Document.Free; Config.Free; BaseImages.Free; inherited; end;
destructor TMusicStudioScenePlacement.Destroy;
begin StepConfigs.Free; Steps.Free; Visibility.Free; Motion.Free; inherited; end;
constructor TMusicStudioSceneTrack.Create;
begin inherited; Placements := TObjectList<TMusicStudioScenePlacement>.Create(True); end;
destructor TMusicStudioSceneTrack.Destroy;
begin Placements.Free; Image.Free; Overrides.Free; inherited; end;

constructor TMusicStudioPsdSceneCache.Create;
begin
  inherited;
  FSources := TObjectList<TMusicStudioSceneSource>.Create(True);
  FTracks := TObjectList<TMusicStudioSceneTrack>.Create(True);
  FLoads := TObjectList<TMusicStudioPsdLayerLoadJob>.Create(True);
  FRenders := TObjectList<TMusicStudioSceneRenderJob>.Create(True); FTempoBPM := 120;
  FMaximumImageDimension := 512;
end;

destructor TMusicStudioPsdSceneCache.Destroy;
begin
  Clear; FRenders.Free; FLoads.Free; FTracks.Free; FSources.Free; inherited;
end;

procedure TMusicStudioPsdSceneCache.Clear;
var L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioSceneRenderJob;
begin
  Inc(FGeneration); Inc(FSerial);
  if FLoads<>nil then for L in FLoads do L.Terminate;
  if FRenders<>nil then for R in FRenders do R.Terminate;
  if FTracks<>nil then FTracks.Clear; if FSources<>nil then FSources.Clear;
  FreeAndNil(FTiming);
  FMidiCache := nil; FSeconds := 0; FBeatPosition := 0; FNextTrack := 0;
end;

function TMusicStudioPsdSceneCache.TrackFor(Index: Integer): TMusicStudioSceneTrack;
var Track: TMusicStudioSceneTrack;
begin Result := nil; for Track in FTracks do if Track.TrackIndex=Index then Exit(Track); end;
function TMusicStudioPsdSceneCache.SourceFor(const Key: string): TMusicStudioSceneSource;
var Source: TMusicStudioSceneSource;
begin Result := nil; for Source in FSources do if Source.Key=Key then Exit(Source); end;

function SharedConfig(const Asset: TMusicStudioPsdAsset; const Pattern: TMusicStudioPattern): string;
var Shared: TMusicStudioSharedPattern;
begin
  Result := Pattern.ConfigJSON;
  if Pattern.SharedPatternID='' then Exit;
  if Pattern.AssetID<>Asset.ID then raise Exception.Create('このPSDと共有パターンの素材IDが一致しません。');
  for Shared in Asset.Patterns do if Shared.ID=Pattern.SharedPatternID then begin
    if Shared.Kind<>Pattern.Kind then raise Exception.Create('共有パターンの属性が一致しません。');
    Exit(Shared.ConfigJSON);
  end;
  raise Exception.Create('共有パターンが見つかりません: '+Pattern.SharedPatternID);
end;

procedure TMusicStudioPsdSceneCache.Bind(Document: TMusicStudioDocument;
  Store: TMusicStudioSharedPsdLibrary; MidiCache: TMusicStudioVisualCache; TempoBPM: Double);
var Patterns: TDictionary<string,TMusicStudioPattern>; Assets: TDictionary<string,TMusicStudioPsdAsset>;
    Pattern: TMusicStudioPattern; Asset: TMusicStudioPsdAsset; Source: TMusicStudioSceneSource;
    Track: TMusicStudioTrack; SceneTrack: TMusicStudioSceneTrack; Slot: TMusicStudioSlot;
    Clip: TMusicStudioPlacement; Entry: TMusicStudioScenePlacement;
    I,J: Integer; Path,Key,Config,Error: string;
begin
  Clear;
  if IsNan(TempoBPM) or IsInfinite(TempoBPM) or (TempoBPM<1) or (TempoBPM>1000) then
    raise EArgumentException.Create('シーンのテンポは1～1000BPMで指定してください。');
  FTempoBPM := TempoBPM; FMidiCache := MidiCache;
  if Document=nil then Exit;
  FTiming := TMusicStudioTempoMap.Create;
  if Document.Timing<>nil then FTiming.LoadJSON(Document.Timing.TimingJSON)
  else FTiming.SetConstantBPM(TempoBPM);
  Patterns := TDictionary<string,TMusicStudioPattern>.Create;
  Assets := TDictionary<string,TMusicStudioPsdAsset>.Create;
  try
    for I := 0 to Document.PatternCount-1 do begin Pattern := Document.PatternAt(I); Patterns.AddOrSetValue(Pattern.ID,Pattern); end;
    for I := 0 to Document.TrackCount-1 do begin
      Track := Document.TrackAt(I); if Track.Kind<>'psd' then Continue;
      if FTracks.Count>=4 then Break;
      SceneTrack := TMusicStudioSceneTrack.Create; FTracks.Add(SceneTrack); SceneTrack.TrackIndex := I;
      Path := Track.PsdPath; Config := '{}'; Error := ''; Asset := Default(TMusicStudioPsdAsset);
      if Track.PsdAssetID<>'' then begin
        if not Assets.TryGetValue(Track.PsdAssetID,Asset) then begin
          if Store=nil then Error := '共有PSDライブラリが未接続です。'
          else if not Store.TryRead(Track.PsdAssetID,Asset,Error) then Asset := Default(TMusicStudioPsdAsset)
          else Assets.Add(Track.PsdAssetID,Asset);
        end;
        if Asset.ID<>'' then begin Path := Asset.FilePath; Config := Asset.ConfigJSON; end;
      end;
      Key := Track.PsdAssetID+'|'+MusicStudioPathKey(Path);
      Source := SourceFor(Key);
      if Source=nil then begin
        Source := TMusicStudioSceneSource.Create; FSources.Add(Source);
        Source.Key := Key; Source.Path := Path; Source.ErrorText := Error;
        Inc(FNextGeneration); Source.Generation := FNextGeneration;
        try Source.Config := ParseMusicStudioPsdConfig(Config);
        except on E: Exception do begin Source.ConfigError := '共有PSD設定: '+E.Message; Source.ErrorText := Source.ConfigError; end; end;
        Source.Fingerprint := MusicStudioFileStamp(Path);
        Source.NeedLoad := (Path<>'') and (Source.Fingerprint<>'') and (Source.ErrorText='');
        if (Source.ErrorText='') and not Source.NeedLoad then
          if Path='' then Source.ErrorText := 'PSD未割当' else Source.ErrorText := 'PSD参照先が見つかりません';
      end;
      SceneTrack.Source := Source;
      for Slot in Track.Slots do for Clip in Slot.Clips do begin
        if not Patterns.TryGetValue(Clip.PatternID,Pattern) then Continue;
        if (Pattern.Kind<>'singing') and (Pattern.Kind<>'emotion') and
          (Pattern.Kind<>'instrument') and (Pattern.Kind<>'animation') and (Pattern.Kind<>'performance') then Continue;
        Entry := TMusicStudioScenePlacement.Create; SceneTrack.Placements.Add(Entry);
        Entry.ID := Clip.ID; Entry.Kind := Pattern.Kind;
        Entry.StartSeconds := Clip.StartSeconds; Entry.LengthSeconds := Clip.LengthSeconds;
        if Clip.TimeBase='beats' then Entry.StartBeat := Clip.StartBeat
        else Entry.StartBeat := StartBeat(Clip.StartSeconds);
        Entry.MidiPath := Pattern.FilePath; Entry.MidiTrack := Pattern.SourceTrack;
        try
          if Pattern.Kind='singing' then Continue;
          if Pattern.Kind='performance' then begin
            if not MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) then Continue;
            Entry.Steps := TMusicStudioLayerStepData.Create; Entry.Steps.LoadJSON(Pattern.ConfigJSON);
            if (Entry.Steps.AssetID<>'') and (Entry.Steps.AssetID<>Track.PsdAssetID) then
              raise Exception.Create('演奏stepは別のPSD素材を参照しています。');
            Entry.StepConfigs := TObjectList<TJSONObject>.Create(True);
            for J := 0 to Entry.Steps.StepCount-1 do Entry.StepConfigs.Add(ParseMusicStudioPsdConfig(Entry.Steps.StepAt(J).ConfigJSON));
            Continue;
          end;
          if (Pattern.AssetID<>'') and (Pattern.AssetID<>Track.PsdAssetID) then
            raise Exception.Create('配置パターンは別のPSD素材を参照しています。');
          Config := SharedConfig(Asset,Pattern);
          if Pattern.Kind='animation' then begin Entry.Motion := TMusicStudioMotionConfig.Create; Entry.Motion.LoadJSON(Config); end
          else Entry.Visibility := ParseMusicStudioPsdConfig(Config);
        except on E: Exception do Entry.ErrorText := E.Message; end;
      end;
    end;
  finally Assets.Free; Patterns.Free; end;
  FLastFileCheck := GetTickCount64; StartJobs;
end;

function TMusicStudioPsdSceneCache.StartBeat(Seconds: Double): Double;
begin
  if Assigned(FBeatResolver) then Result := FBeatResolver(Seconds)
  else if FTiming<>nil then Result := FTiming.SecondsToBeat(Seconds)
  else Result := Seconds*FTempoBPM/60.0;
end;

procedure TMusicStudioPsdSceneCache.SetPosition(Seconds: Double);
begin SetPosition(Seconds,StartBeat(Seconds)); end;
procedure TMusicStudioPsdSceneCache.SetPosition(Seconds, BeatPosition: Double);
var Track: TMusicStudioSceneTrack;
begin
  if IsNan(Seconds) or IsInfinite(Seconds) or (Seconds<0) or
    IsNan(BeatPosition) or IsInfinite(BeatPosition) or (BeatPosition<0) then
    raise EArgumentException.Create('プレビュー位置が不正です。');
  FSeconds := Seconds; FBeatPosition := BeatPosition;
  for Track in FTracks do RefreshTrack(Track);
end;

function TMusicStudioPsdSceneCache.MouthAt(Placement: TMusicStudioScenePlacement): Integer;
var Source: TMusicStudioVisualSource; Roll: TMusicStudioRollTrack;
    Note,VowelIndex: Integer; Local,LatestStart,Fraction: Double; Vowels: string; C: Char;
begin
  Result := 0;
  if (FMidiCache=nil) or (Placement.MidiTrack<0) or (Placement.MidiPath='') then Exit;
  Source := FMidiCache.Find(vkMidi,Placement.MidiPath);
  if (Source=nil) or (Source.Status<>vsReady) or (Source.Rolls=nil) or
    not Source.Rolls.TryGetValue(Placement.MidiTrack,Roll) then Exit;
  Local := FSeconds-Placement.StartSeconds; LatestStart := -1; Vowels := '';
  Note := Roll.FirstOverlap(Local);
  while (Note<Length(Roll.Notes)) and (Roll.Notes[Note].StartSeconds<=Local) do begin
    if (Roll.Notes[Note].EndSeconds>Local) and (Roll.Notes[Note].StartSeconds>=LatestStart) then begin
      LatestStart := Roll.Notes[Note].StartSeconds; Vowels := '';
      if (Roll.Notes[Note].Lyric<>'') and (Roll.Notes[Note].Vowels<>'') then begin
        Fraction := (Local-LatestStart)/(Roll.Notes[Note].EndSeconds-LatestStart);
        Vowels := Roll.Notes[Note].Vowels;
        VowelIndex := EnsureRange(Integer(1+Floor(Fraction*Length(Vowels))),1,Length(Vowels));
        C := Vowels[VowelIndex];
        case C of
          'a': Result := 1; 'i': Result := 2; 'u': Result := 3; 'e': Result := 4; 'o': Result := 5; 'n': Result := 6;
          'A': Result := 7; 'I': Result := 8; 'U': Result := 9; 'E': Result := 10; 'O': Result := 11;
        else Result := 0; end;
      end else Result := 0;
    end;
    Inc(Note);
  end;
end;

procedure MergeVisibility(Document: TMusicStudioLayerDocument; Target, Config: TJSONObject);
var Pair: TJSONPair; Visibility: TJSONObject;
begin
  Visibility := MusicStudioPsdConfigObject(Config,'visibility');
  for Pair in Visibility do MusicStudioSetJsonBoolean(Target,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
  for Pair in Visibility do if TJSONBool(Pair.JsonValue).AsBoolean then
    Document.SelectLayerOverride(Target,Pair.JsonString.Value);
end;

function TransformKey(const T: TMusicStudioMotionTransform): string;
begin
  Result := IntToStr(T.OffsetX)+','+IntToStr(T.OffsetY)+','+MusicStudioDoubleKey(T.Scale)+','+
    MusicStudioDoubleKey(T.VerticalScale)+','+MusicStudioDoubleKey(T.AngleDegrees)+','+
    MusicStudioDoubleKey(T.TopOffsetX)+','+MusicStudioDoubleKey(T.WaistRatio)+','+MusicStudioDoubleKey(T.JointFlexibility);
end;

procedure TMusicStudioPsdSceneCache.RefreshTrack(Track: TMusicStudioSceneTrack);
var Entry,Singing,Performance: TMusicStudioScenePlacement; Overrides,Config: TJSONObject;
    Transforms: TMusicStudioSceneTransforms; T: TMusicStudioMotionTransform;
    Key,Warning: string; Mouth,N,ActiveIndex: Integer; Factor: Double; Pair: TJSONPair;
begin
  if (Track.Source=nil) or (Track.Source.Document=nil) or (Track.Source.Config=nil) then Exit;
  Overrides := nil; Config := nil; Singing := nil; Performance := nil; ActiveIndex := -1; Mouth := 0; Warning := '';
  try
    try
      Overrides := BuildMusicStudioPsdOverrides(Track.Source.Document,Track.Source.Config,-1);
      Transforms := nil;
      Factor := 1;
      if FMaximumImageDimension>0 then
        Factor := Min(1.0,FMaximumImageDimension/Max(Track.Source.Document.Width,Track.Source.Document.Height));
      for Entry in Track.Placements do begin
        if (FSeconds<Entry.StartSeconds) or (FSeconds>=Entry.StartSeconds+Entry.LengthSeconds) then Continue;
        if Entry.ErrorText<>'' then begin Warning := Entry.ErrorText; Continue; end;
        if Entry.Kind='performance' then begin
          if (Performance=nil) or (Entry.StartSeconds>=Performance.StartSeconds) then Performance := Entry;
          Continue;
        end;
        if Entry.Kind='singing' then begin
          if (Singing=nil) or (Entry.StartSeconds>=Singing.StartSeconds) then Singing := Entry;
        end else if Entry.Visibility<>nil then MergeVisibility(Track.Source.Document,Overrides,Entry.Visibility)
        else if Entry.Motion<>nil then begin
          CalculateMusicStudioMotionTransform(Entry.Motion,FBeatPosition-Entry.StartBeat,T);
          T.OffsetX := Round(T.OffsetX*Factor); T.OffsetY := Round(T.OffsetY*Factor); T.TopOffsetX := T.TopOffsetX*Factor;
          N := Length(Transforms); SetLength(Transforms,N+1); Transforms[N] := T;
        end;
      end;
      // 表情/姿勢→演奏step→母音。休符にはstepを重ねず、基本/表情を復元する。
      if (Performance<>nil) and (Performance.Steps<>nil) then
        ActiveIndex := Performance.Steps.ActiveStepAt(FBeatPosition,Performance.StartBeat);
      if ActiveIndex>=0 then begin
        for Pair in MusicStudioPsdConfigObject(Performance.StepConfigs[ActiveIndex],'visibility') do
          if not Track.Source.Document.HasLayer(Pair.JsonString.Value) then
            raise Exception.Create('演奏stepのPSDレイヤーが見つかりません: '+Pair.JsonString.Value);
        MergeVisibility(Track.Source.Document,Overrides,Performance.StepConfigs[ActiveIndex]);
      end;
      if Singing<>nil then Mouth := MouthAt(Singing);
      Config := TJSONObject(Track.Source.Config.Clone);
      Config.RemovePair('visibility').Free; Config.AddPair('visibility',Overrides); Overrides := nil;
      Overrides := BuildMusicStudioPsdOverrides(Track.Source.Document,Config,Mouth);
      Key := Overrides.ToJSON; Track.BaseKey := Key;
      for T in Transforms do Key := Key+'|'+TransformKey(T);
      Track.WarningText := Warning;
      if Key=Track.DesiredKey then Exit;
      Track.DesiredKey := Key; Track.ErrorText := ''; Inc(FNextGeneration); Track.RequestGeneration := FNextGeneration;
      Track.Overrides.Free; Track.Overrides := Overrides; Overrides := nil;
      Track.Transforms := Transforms; Track.NeedRender := True;
      if Track.RenderJob<>nil then Track.RenderJob.Terminate;
      // A new vowel/time request is still the same character. Keep the last complete image
      // while the latest generation renders; source changes, errors and Bind clear it below.
      Inc(FSerial);
    except on E: Exception do begin
      Track.ErrorText := 'PSD設定: '+E.Message; Track.NeedRender := False;
      Track.DesiredKey := ''; Inc(FNextGeneration); Track.RequestGeneration := FNextGeneration;
      if Track.RenderJob<>nil then Track.RenderJob.Terminate;
      FreeAndNil(Track.Image); Inc(FSerial);
    end; end;
  finally Config.Free; Overrides.Free; end;
end;

procedure TMusicStudioPsdSceneCache.StartJobs;
var Source: TMusicStudioSceneSource; Track: TMusicStudioSceneTrack;
    Load: TMusicStudioPsdLayerLoadJob; Render: TMusicStudioSceneRenderJob; Base: TBitmap; I,Index: Integer;
begin
  for Source in FSources do begin
    if FLoads.Count>=2 then Break;
    if not Source.NeedLoad or (Source.LoadJob<>nil) then Continue;
    Source.NeedLoad := False;
    Load := TMusicStudioPsdLayerLoadJob.Create(Source.Path,Source.Generation);
    Source.LoadJob := Load; FLoads.Add(Load); Inc(FLoadCount); Load.Start;
  end;
  if FTracks.Count=0 then Exit;
  for I := 0 to FTracks.Count-1 do begin
    if FRenders.Count>=2 then Break;
    Index := (FNextTrack+I) mod FTracks.Count; Track := FTracks[Index];
    if not Track.NeedRender or (Track.RenderJob<>nil) or (Track.Source.Document=nil) then Continue;
    Base := nil; Track.Source.BaseImages.TryGetValue(Track.BaseKey,Base);
    Render := TMusicStudioSceneRenderJob.Create(Track.Source.Document,Track.Overrides,Base,Track.Transforms,FMaximumImageDimension);
    Render.BindGeneration := FGeneration; Render.SourceGeneration := Track.Source.Generation;
    Render.RequestGeneration := Track.RequestGeneration; Render.TrackIndex := Track.TrackIndex;
    Render.SourceKey := Track.Source.Key; Render.BaseKey := Track.BaseKey; Render.ImageKey := Track.DesiredKey;
    Track.RenderJob := Render; Track.NeedRender := False; FRenders.Add(Render);
    Inc(FRenderCount); Render.Start;
  end;
  FNextTrack := (FNextTrack+1) mod FTracks.Count;
end;

procedure TMusicStudioPsdSceneCache.ResetSource(Source: TMusicStudioSceneSource; const Stamp: string);
var Track: TMusicStudioSceneTrack;
begin
  if Source.LoadJob<>nil then begin Source.LoadJob.Terminate; Source.LoadJob := nil; end;
  Source.Document.Free; Source.Document := nil; Source.BaseImages.Clear;
  Inc(FNextGeneration); Source.Generation := FNextGeneration; Source.Fingerprint := Stamp;
  Source.NeedLoad := (Stamp<>'') and (Source.Config<>nil); Source.ErrorText := Source.ConfigError;
  if (Stamp='') and (Source.ErrorText='') then Source.ErrorText := 'PSD参照先が見つかりません';
  for Track in FTracks do if Track.Source=Source then begin
    Inc(FNextGeneration); Track.RequestGeneration := FNextGeneration;
    if Track.RenderJob<>nil then Track.RenderJob.Terminate;
    FreeAndNil(Track.Image); Track.DesiredKey := ''; Track.ImageKey := ''; Track.ErrorText := '';
    Track.NeedRender := False;
  end;
  Inc(FSerial);
end;

function TMusicStudioPsdSceneCache.PollResults(CheckFiles: Boolean): Boolean;
var I: Integer; Source: TMusicStudioSceneSource; Track: TMusicStudioSceneTrack;
    L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioSceneRenderJob; Base,Image,OldImage: TBitmap;
    Stamp: string; Before: Integer; Now: UInt64; CheckNow: Boolean;
begin
  Before := FSerial; Now := GetTickCount64;
  CheckNow := not FFrozenSources and (CheckFiles or (Now-FLastFileCheck>=1000));
  if CheckNow then begin
    FLastFileCheck := Now;
    for Source in FSources do begin
      Stamp := MusicStudioFileStamp(Source.Path);
      if Stamp<>Source.Fingerprint then ResetSource(Source,Stamp);
    end;
  end;
  for I := FLoads.Count-1 downto 0 do begin
    L := FLoads[I]; if not L.Finished then Continue;
    for Source in FSources do if (Source.LoadJob=L) and (Source.Generation=L.Generation) then begin
      Source.LoadJob := nil; Stamp := Source.Fingerprint;
      if not FFrozenSources then Stamp := MusicStudioFileStamp(Source.Path);
      if Stamp<>Source.Fingerprint then ResetSource(Source,Stamp)
      else begin
        Source.Document := L.TakeDocument; Source.ErrorText := L.ErrorMessage; Inc(FSerial);
        for Track in FTracks do if Track.Source=Source then RefreshTrack(Track);
      end;
      Break;
    end;
    FLoads.Delete(I);
  end;
  for I := FRenders.Count-1 downto 0 do begin
    R := FRenders[I]; if not R.Finished then Continue;
    Track := TrackFor(R.TrackIndex); Source := SourceFor(R.SourceKey);
    if (R.BindGeneration=FGeneration) and (Source<>nil) and (Source.Generation=R.SourceGeneration) then begin
      Stamp := Source.Fingerprint;
      if not FFrozenSources then Stamp := MusicStudioFileStamp(Source.Path);
      if Stamp<>Source.Fingerprint then ResetSource(Source,Stamp)
      else begin
        // 完了時点で使う口形が変わっていても、同じsourceの合成像は安全に共有できる。
        if R.ErrorText='' then begin
          Base := R.TakeBase;
          if Base<>nil then begin
            if Source.BaseImages.Count>=8 then Source.BaseImages.Clear;
            Source.BaseImages.AddOrSetValue(R.BaseKey,Base);
          end;
          if R.Composed then Inc(FCompositionCount);
        end;
        if (Track<>nil) and (Track.RenderJob=R) and (Track.RequestGeneration=R.RequestGeneration) and
          (Track.DesiredKey=R.ImageKey) then begin
          Image := R.TakeImage; OldImage := Track.Image; Track.Image := Image; OldImage.Free;
          Track.ErrorText := R.ErrorText;
          if Image<>nil then Track.ImageKey := R.ImageKey
          else begin
            Track.ImageKey := '';
            if Track.ErrorText='' then Track.ErrorText := 'PSD合成画像を生成できませんでした。';
          end;
          Inc(FSerial);
        end;
      end;
    end;
    if (Track<>nil) and (Track.RenderJob=R) then Track.RenderJob := nil;
    FRenders.Delete(I);
  end;
  for Track in FTracks do RefreshTrack(Track); // MIDIの非同期索引完成も次のPollで口形へ反映する。
  StartJobs; Result := Before<>FSerial;
end;

function TMusicStudioPsdSceneCache.ImageForTrack(TrackIndex: Integer): TBitmap;
var Track: TMusicStudioSceneTrack;
begin Result := nil; Track := TrackFor(TrackIndex); if Track<>nil then Result := Track.Image; end;
function TMusicStudioPsdSceneCache.StatusForTrack(TrackIndex: Integer): string;
var Track: TMusicStudioSceneTrack;
begin
  Track := TrackFor(TrackIndex); if Track=nil then Exit('プレビュー対象外（PSD先頭4件まで）');
  if Track.Source.ErrorText<>'' then Exit(Track.Source.ErrorText);
  if Track.ErrorText<>'' then Exit(Track.ErrorText);
  if Track.Source.Document=nil then Exit('PSDレイヤー読込中…');
  if Track.NeedRender or (Track.RenderJob<>nil) then Exit('PSD合成中…');
  if Track.WarningText<>'' then Exit(Track.WarningText);
  if Track.Image=nil then Exit('PSD合成画像がありません');
  Result := '';
end;
function TMusicStudioPsdSceneCache.ActiveLoadJobs: Integer;
begin Result := FLoads.Count; end;
function TMusicStudioPsdSceneCache.ActiveRenderJobs: Integer;
begin Result := FRenders.Count; end;

end.
