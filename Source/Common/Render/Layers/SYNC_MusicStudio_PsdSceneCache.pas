unit SYNC_MusicStudio_PsdSceneCache;

// UI所有のPSDシーン。Bindで参照JSONを値コピーし、描画は借用画像だけを参照する。
// 読込/合成は最大各2 worker。旧世代も上限に数え、UI callbackや音声を使用しない。
interface

uses Winapi.Windows, System.Types, System.Classes, System.JSON, System.Generics.Collections,
  Vcl.Graphics, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_MotionData,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerJobs, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_LayerStepData,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_AnimationSync;

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
    FScaleKey: string;
    FPartScale: Double;
    FQueuedTick,FFinishedTick: Int64;
  protected
    procedure Execute; override;
  public
    BindGeneration, SourceGeneration, RequestGeneration, TrackIndex: Integer;
    SourceKey, BaseKey, ImageKey, ErrorText: string;
    Composed: Boolean;
    PlaybackEpoch: Integer;
    PositionSeconds: Double;
    constructor Create(Document: TMusicStudioLayerDocument; Overrides: TJSONObject;
      CachedBase: TBitmap; const Transforms: TMusicStudioSceneTransforms;
      MaximumDimension: Integer = 512; const ScaleKey: string = ''; PartScale: Double = 1);
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
    ID, Kind, SlotKind, SyncSource, MidiPath, ErrorText: string;
    StartSeconds, LengthSeconds, StartBeat,SourceStartSeconds: Double;
    MidiTrack: Integer;
    AnimationCues: TArray<TMusicStudioAnimationCue>;
    Visibility: TJSONObject;
    Steps: TMusicStudioLayerStepData;
    Instrument: TMusicStudioInstrumentData;
    PlaybackBlocks: TArray<TInstrumentBlock>; // Bind時の値コピー。frameごとの全区間複製を避ける。
    HasSelection,IsCustomExpression: Boolean;
    Selection: TInstrumentState; // 独立スロットの意味指定。配置の秒区間と共に評価する。
    StepConfigs: TObjectList<TJSONObject>;
    Motion: TMusicStudioMotionConfig;
    destructor Destroy; override;
  end;

  TMusicStudioSceneTrack = class
  public
    TrackIndex, RequestGeneration, PublishedGeneration: Integer;
    ImageSeconds: Double;
    Enabled: Boolean;
    MouthKey: string;
    MouthScale: Double;
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
    FRealtimePlayback: Boolean;
    FPlaybackEpoch: Integer;
    FMaximumImageDimension: Integer;
    procedure SetRealtimePlayback(Value: Boolean);
    function TrackFor(Index: Integer): TMusicStudioSceneTrack;
    function SourceFor(const Key: string): TMusicStudioSceneSource;
    procedure StartJobs;
    procedure RefreshTrack(Track: TMusicStudioSceneTrack);
    procedure ResetSource(Source: TMusicStudioSceneSource; const Stamp: string);
    function MouthAt(Placement: TMusicStudioScenePlacement; out Scale: Double): Integer;
    function AnimationPhase(Track: TMusicStudioSceneTrack; const SourceKind: string; out Phase: Double): Boolean;
    function SourceEnabled(Source: TMusicStudioSceneSource): Boolean;
    function StartBeat(Seconds: Double): Double;
  public
    constructor Create;
    destructor Destroy; override;
    // Document/Storeは保持しない。共有変更後は再Bindする。TempoBPMは明示された一定テンポ。
    procedure Bind(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
      MidiCache: TMusicStudioVisualCache; TempoBPM: Double = 120; const HiddenTrackIDs: TArray<string> = nil);
    procedure SetPosition(Seconds: Double); overload;
    // 可変テンポではBeatResolverを設定し、親のTimingMapから現在拍と開始拍を渡す。
    procedure SetPosition(Seconds, BeatPosition: Double); overload;
    function PollResults(CheckFiles: Boolean = False): Boolean;
    // 実トラック番号で参照。画像は次の位置/Bind/Poll/Clearまで借用。保持にはAssignする。
    procedure SetTrackEnabled(TrackIndex: Integer; Enabled: Boolean);
    function NativeSizeForTrack(TrackIndex: Integer): System.Types.TSize;
    function ImageForTrack(TrackIndex: Integer): TBitmap;
    // 公開済み画像が要求された秒を返す診断。画像なし/非表示は-1。現在の再生時計とは独立する。
    function PublishedSecondsForTrack(TrackIndex: Integer): Double;
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
    // Live preview may publish completed in-flight frames; exact seek/export stays strict by default.
    property RealtimePlayback: Boolean read FRealtimePlayback write SetRealtimePlayback;
    property FrozenSources: Boolean read FFrozenSources write FFrozenSources;
    // 0ならPSD本来の解像度。編集プレビューの既定値512は維持する。
    property MaximumImageDimension: Integer read FMaximumImageDimension write FMaximumImageDimension;
  end;

implementation

uses System.SysUtils, System.Math, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_BitmapCache, SYNC_MusicStudio_InstrumentPlayback, SYNC_MusicStudio_PerformanceTrace;

constructor TMusicStudioSceneRenderJob.Create(Document: TMusicStudioLayerDocument;
  Overrides: TJSONObject; CachedBase: TBitmap; const Transforms: TMusicStudioSceneTransforms;
  MaximumDimension: Integer; const ScaleKey: string; PartScale: Double);
var PerfTick: Int64;
begin
  PerfTick := MusicStudioPerfStamp;
  FScaleKey := ScaleKey; FPartScale := PartScale;
  inherited Create(True); FreeOnTerminate := False;
  FTransforms := Copy(Transforms);
  FMaximumDimension := MaximumDimension;
  if CachedBase<>nil then begin FBase := TBitmap.Create; FBase.Assign(CachedBase); end
  else begin FDocument := Document.Clone; FOverrides := TJSONObject(Overrides.Clone); end;
  if CachedBase=nil then MusicStudioPerfAdd('scene.prepare.cold',MusicStudioPerfElapsed(PerfTick),'maxDimension='+IntToStr(MaximumDimension))
  else MusicStudioPerfAdd('scene.prepare.cached',MusicStudioPerfElapsed(PerfTick));
  FQueuedTick := MusicStudioPerfStamp;
end;

procedure TMusicStudioSceneRenderJob.Start;
begin FStarted := True; inherited Start; end;

destructor TMusicStudioSceneRenderJob.Destroy;
begin
  Terminate; if not FStarted then Start; if not Finished then WaitFor;
  FDocument.Free; FOverrides.Free; FBase.Free; FImage.Free; inherited;
end;

procedure TMusicStudioSceneRenderJob.Execute;
var Full,Next: TBitmap; Transform: TMusicStudioMotionTransform; PerfTick,TotalTick: Int64;
begin
  if Terminated then Exit;
  MusicStudioPerfAdd('scene.queue',MusicStudioPerfElapsed(FQueuedTick)); TotalTick := MusicStudioPerfStamp;
  Full := nil; Next := nil;
  try
    try
      if FBase=nil then begin
        Full := TBitmap.Create;
        PerfTick := MusicStudioPerfStamp;
        if not FDocument.Render(Full,FOverrides,FMaximumDimension,FScaleKey,FPartScale) then begin ErrorText := FDocument.LastError; Exit; end;
        MusicStudioPerfAdd('scene.compose',MusicStudioPerfElapsed(PerfTick));
        FBase := Full; Full := nil; Composed := True;
      end;
      if Terminated then Exit;
      PerfTick := MusicStudioPerfStamp; FImage := TBitmap.Create; FImage.Assign(FBase);
      MusicStudioPerfAdd('scene.copy',MusicStudioPerfElapsed(PerfTick));
      for Transform in FTransforms do begin
        if Terminated then Exit;
        // Transform値は縮小キャンバス座標に事前変換済み。
        Next := TBitmap.Create; PerfTick := MusicStudioPerfStamp; RenderMusicStudioMotion(FImage,Next,Transform);
        MusicStudioPerfAdd('scene.motion',MusicStudioPerfElapsed(PerfTick),IntToStr(FImage.Width)+'x'+IntToStr(FImage.Height));
        FImage.Free; FImage := Next; Next := nil;
      end;
    except on E: Exception do begin ErrorText := E.Message; FreeAndNil(FImage); end; end;
  finally Full.Free; Next.Free; FFinishedTick := MusicStudioPerfStamp;
    MusicStudioPerfAdd('scene.worker',MusicStudioPerfElapsed(TotalTick)); end;
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
begin Instrument.Free; StepConfigs.Free; Steps.Free; Visibility.Free; Motion.Free; inherited; end;
constructor TMusicStudioSceneTrack.Create;
begin inherited; Enabled := True; MouthScale := 1; Placements := TObjectList<TMusicStudioScenePlacement>.Create(True); end;
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
  Store: TMusicStudioSharedPsdLibrary; MidiCache: TMusicStudioVisualCache; TempoBPM: Double; const HiddenTrackIDs: TArray<string>);
var Patterns: TDictionary<string,TMusicStudioPattern>; Assets: TDictionary<string,TMusicStudioPsdAsset>;
    Pattern: TMusicStudioPattern; Asset: TMusicStudioPsdAsset; Source: TMusicStudioSceneSource;
    Track: TMusicStudioTrack; SceneTrack: TMusicStudioSceneTrack; Slot: TMusicStudioSlot;
    Clip: TMusicStudioPlacement; Entry: TMusicStudioScenePlacement;
    I,J: Integer; Path,Key,Config,Error,HiddenID: string;
    Cue: TMusicStudioAnimationCue; Block: TInstrumentBlock; Step: TMusicStudioLayerStep;
    Notes: TMusicStudioPerformanceData; Note: TMusicStudioPerformanceNote;
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
      SceneTrack := TMusicStudioSceneTrack.Create; FTracks.Add(SceneTrack); SceneTrack.TrackIndex := I;
      for HiddenID in HiddenTrackIDs do if HiddenID=Track.ID then SceneTrack.Enabled := False;
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
          (Pattern.Kind<>'instrument') and (Pattern.Kind<>'animation') and (Pattern.Kind<>'performance') and (Pattern.Kind<>'selection') then Continue;
        Entry := TMusicStudioScenePlacement.Create; SceneTrack.Placements.Add(Entry);
        Entry.ID := Clip.ID; Entry.Kind := Pattern.Kind; Entry.SlotKind := Slot.Kind;
        Entry.SyncSource := MusicStudioAnimationSource(Slot.Kind);
        Entry.StartSeconds := Clip.StartSeconds; Entry.LengthSeconds := Clip.LengthSeconds;
        if Clip.TimeBase='beats' then Entry.StartBeat := Clip.StartBeat
        else Entry.StartBeat := StartBeat(Clip.StartSeconds);
        Entry.MidiPath := Pattern.FilePath; Entry.MidiTrack := Pattern.SourceTrack;
        Entry.SourceStartSeconds := Pattern.SourceStartSeconds;
        try
          if Pattern.Kind='singing' then Continue;
          if Pattern.Kind='selection' then begin
            Config := Pattern.ConfigJSON;
            with TJSONObject.ParseJSONValue(Config) as TJSONObject do try
              Entry.Selection.Row := GetValue<string>('row'); Entry.Selection.Choice := GetValue<string>('choice');
              Entry.Selection.SelectionMode := GetValue<string>('mode'); Entry.HasSelection := True;
            finally Free; end;
            Continue;
          end;
          if Pattern.Kind='performance' then begin
            if MusicStudioHasInstrumentTimeline(Pattern.ConfigJSON) then begin
              Entry.Instrument := TMusicStudioInstrumentData.Create; Entry.Instrument.Load(Pattern.ConfigJSON);
              Entry.Instrument.BindAsset(Track.PsdAssetID);
              Entry.PlaybackBlocks := Entry.Instrument.Blocks.ToArray;
              for Block in Entry.PlaybackBlocks do if MusicStudioActionRow(Block.Row) then begin
                Cue.StartValue := Block.StartBeat; Cue.EndValue := Block.EndBeat;
                Entry.AnimationCues := Entry.AnimationCues+[Cue];
              end;
              SortMusicStudioAnimationCues(Entry.AnimationCues);
              Continue;
            end;
            if not MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) then begin
              Notes := TMusicStudioPerformanceData.Create;
              try
                Notes.LoadJSON(Pattern.ConfigJSON);
                for J := 0 to Notes.NoteCount-1 do begin
                  Note := Notes.NoteAt(J); if Note.Velocity=0 then Continue;
                  Cue.StartValue := Note.StartBeat; Cue.EndValue := Note.StartBeat+Note.LengthBeats;
                  Entry.AnimationCues := Entry.AnimationCues+[Cue];
                end;
                SortMusicStudioAnimationCues(Entry.AnimationCues);
              finally Notes.Free; end;
              Continue;
            end;
            Entry.Steps := TMusicStudioLayerStepData.Create; Entry.Steps.LoadJSON(Pattern.ConfigJSON);
            if (Entry.Steps.AssetID<>'') and (Entry.Steps.AssetID<>Track.PsdAssetID) then
              raise Exception.Create('演奏stepは別のPSD素材を参照しています。');
            Entry.StepConfigs := TObjectList<TJSONObject>.Create(True);
            for J := 0 to Entry.Steps.StepCount-1 do begin
              Step := Entry.Steps.StepAt(J); Entry.StepConfigs.Add(ParseMusicStudioPsdConfig(Step.ConfigJSON));
              Cue.StartValue := Step.StartBeat; Cue.EndValue := Step.StartBeat+Step.LengthBeats;
              Entry.AnimationCues := Entry.AnimationCues+[Cue];
            end;
            SortMusicStudioAnimationCues(Entry.AnimationCues);
            Continue;
          end;
          if (Pattern.AssetID<>'') and (Pattern.AssetID<>Track.PsdAssetID) then
            raise Exception.Create('配置パターンは別のPSD素材を参照しています。');
          Config := SharedConfig(Asset,Pattern);
          if Pattern.Kind='animation' then begin Entry.Motion := TMusicStudioMotionConfig.Create; Entry.Motion.LoadJSON(Config); end
          else begin Entry.Visibility := ParseMusicStudioPsdConfig(Config); Entry.IsCustomExpression := (Pattern.Kind='emotion') and (Pattern.SharedPatternID='') and (Pattern.ConfigJSON<>''); end;
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

function TMusicStudioPsdSceneCache.AnimationPhase(Track: TMusicStudioSceneTrack;
  const SourceKind: string; out Phase: Double): Boolean;
var Entry,Selected: TMusicStudioScenePlacement; Source: TMusicStudioVisualSource;
  Roll: TMusicStudioRollTrack; I: Integer; Local,Latest: Double;
begin
  Result := False; Phase := 0; Selected := nil;
  for Entry in Track.Placements do if (Entry.SlotKind=SourceKind) and (Entry.Kind=SourceKind) and
    (FSeconds>=Entry.StartSeconds) and (FSeconds<Entry.StartSeconds+Entry.LengthSeconds) then
    if (Selected=nil) or (Entry.StartSeconds>=Selected.StartSeconds) then Selected := Entry;
  if (Selected=nil) or (Selected.ErrorText<>'') then Exit;
  if SourceKind='performance' then
    Exit(MusicStudioAnimationPhase(Selected.AnimationCues,FBeatPosition-Selected.StartBeat,Phase));
  if (FMidiCache=nil) or (Selected.MidiTrack<0) then Exit;
  Source := FMidiCache.Find(vkMidi,Selected.MidiPath);
  if (Source=nil) or (Source.Status<>vsReady) or (Source.Rolls=nil) or
    not Source.Rolls.TryGetValue(Selected.MidiTrack,Roll) then Exit;
  Local := FSeconds-Selected.StartSeconds+Selected.SourceStartSeconds; Latest := -1;
  I := Roll.FirstOverlap(Local);
  while (I<Length(Roll.Notes)) and (Roll.Notes[I].StartSeconds<=Local) do begin
    if (Roll.Notes[I].EndSeconds>Local) and (Roll.Notes[I].StartSeconds>=Latest) then begin
      Latest := Roll.Notes[I].StartSeconds;
      Result := Roll.Notes[I].Lyric<>'';
      if Result then Phase := EnsureRange((Local-Latest)/(Roll.Notes[I].EndSeconds-Latest),0.0,1.0);
    end;
    Inc(I);
  end;
end;
function TMusicStudioPsdSceneCache.MouthAt(Placement: TMusicStudioScenePlacement; out Scale: Double): Integer;
var Source: TMusicStudioVisualSource; Roll: TMusicStudioRollTrack;
    Note,VowelIndex: Integer; Local,LatestStart,Fraction: Double; Vowels: string; C: Char;
begin
  Scale := 1; Result := 0;
  if (FMidiCache=nil) or (Placement.MidiTrack<0) or (Placement.MidiPath='') then Exit;
  Source := FMidiCache.Find(vkMidi,Placement.MidiPath);
  if (Source=nil) or (Source.Status<>vsReady) or (Source.Rolls=nil) or
    not Source.Rolls.TryGetValue(Placement.MidiTrack,Roll) then Exit;
  Local := FSeconds-Placement.StartSeconds+Placement.SourceStartSeconds; LatestStart := -1; Vowels := '';
  Note := Roll.FirstOverlap(Local);
  while (Note<Length(Roll.Notes)) and (Roll.Notes[Note].StartSeconds<=Local) do begin
    if (Roll.Notes[Note].EndSeconds>Local) and (Roll.Notes[Note].StartSeconds>=LatestStart) then begin
      LatestStart := Roll.Notes[Note].StartSeconds; Vowels := '';
      if (Roll.Notes[Note].Lyric<>'') and (Roll.Notes[Note].Vowels<>'') then begin
        Fraction := (Local-LatestStart)/(Roll.Notes[Note].EndSeconds-LatestStart);
        Vowels := Roll.Notes[Note].Vowels;
        VowelIndex := EnsureRange(Integer(1+Floor(Fraction*Length(Vowels))),1,Length(Vowels));
        Fraction := Frac(Fraction*Length(Vowels));
        Scale := 1-0.5*Fraction;
        C := Vowels[VowelIndex];
        case C of
          'a','A': Result := 1; 'i','I': Result := 2; 'u','U': Result := 3;
          'e','E': Result := 4; 'o','O': Result := 5; 'n','N': Result := 6;
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
var Entry,Singing,Performance,Custom: TMusicStudioScenePlacement; Overrides,Config: TJSONObject;
    Transforms: TMusicStudioSceneTransforms; T: TMusicStudioMotionTransform;
    Key,Warning: string; Mouth,N,ActiveIndex: Integer; Factor,Phase: Double; Pair: TJSONPair; CommonVisibility: TJSONObject;
    CommonStates: TArray<TInstrumentState>; CommonState: TInstrumentState; PoseActive: Boolean;
    Independent: array[0..3] of TMusicStudioScenePlacement; I,K: Integer; HasIndependent: Boolean;
    ActionRanges: TArray<TInstrumentPlaybackRange>; RangeCount: Integer;
begin
  if not Track.Enabled then Exit;
  if (Track.Source=nil) or (Track.Source.Document=nil) or (Track.Source.Config=nil) then Exit;
  Overrides := nil; Config := nil; Singing := nil; Performance := nil; ActiveIndex := -1; Mouth := 0; Warning := '';
  PoseActive := False; Custom := nil;
  CommonStates := nil; HasIndependent := False; for I := 0 to High(Independent) do Independent[I] := nil;
  try
    try
      Overrides := BuildMusicStudioPsdOverrides(Track.Source.Document,Track.Source.Config,-1);
      SetLength(ActionRanges,Track.Placements.Count); RangeCount := 0;
      Transforms := nil;
      Factor := 1;
      if FMaximumImageDimension>0 then
        Factor := Min(1.0,FMaximumImageDimension/Max(Track.Source.Document.Width,Track.Source.Document.Height));
      for Entry in Track.Placements do begin
        if (Entry.Instrument<>nil) and (Entry.ErrorText='') and (FBeatPosition>=Entry.StartBeat) then begin
          ActionRanges[RangeCount].Blocks := Entry.PlaybackBlocks;
          ActionRanges[RangeCount].StartBeat := Entry.StartBeat;
          ActionRanges[RangeCount].EndBeat := Min(Entry.StartBeat+Entry.Instrument.LengthBeats,StartBeat(Entry.StartSeconds+Entry.LengthSeconds));
          Inc(RangeCount);
        end;
        if (FSeconds<Entry.StartSeconds) or (FSeconds>=Entry.StartSeconds+Entry.LengthSeconds) then Continue;
        if Entry.ErrorText<>'' then begin Warning := Entry.ErrorText; Continue; end;
        if Entry.HasSelection then begin
          for I := 0 to High(Independent) do if Entry.Selection.Row=INSTRUMENT_SELECTION_ROWS[I] then
            if (Independent[I]=nil) or (Entry.StartSeconds>=Independent[I].StartSeconds) then Independent[I] := Entry;
          Continue;
        end;
        if Entry.Kind='performance' then begin
          if (Performance=nil) or (Entry.StartSeconds>=Performance.StartSeconds) then Performance := Entry;
          Continue;
        end;
        if Entry.Kind='singing' then begin
          if (Singing=nil) or (Entry.StartSeconds>=Singing.StartSeconds) then Singing := Entry;
        end else if Entry.Visibility<>nil then Continue
        else if Entry.Motion<>nil then begin
          if Entry.SyncSource='tempo' then Phase := FBeatPosition
          else if Entry.SyncSource<>'' then begin
            if not AnimationPhase(Track,Entry.SyncSource,Phase) then Continue;
          end else Phase := FBeatPosition-Entry.StartBeat; // Existing animation slots retain local-beat behavior.
          CalculateMusicStudioMotionTransform(Entry.Motion,Phase,T);
          T.OffsetX := Round(T.OffsetX*Factor); T.OffsetY := Round(T.OffsetY*Factor); T.TopOffsetX := T.TopOffsetX*Factor;
          N := Length(Transforms); SetLength(Transforms,N+1); Transforms[N] := T;
        end;
      end;
      // 全レイヤーsnapshotは基本表示として先に適用し、動作と口を固定しない。
      for Entry in Track.Placements do if Entry.IsCustomExpression and (Entry.Visibility<>nil) and (Entry.ErrorText='') and
        (FSeconds>=Entry.StartSeconds) and (FSeconds<Entry.StartSeconds+Entry.LengthSeconds) then
          if (Custom=nil) or (Entry.StartSeconds>=Custom.StartSeconds) then Custom := Entry;
      // 全状態snapshotの隠れた親配下には表示ONの子もある。子から親を再表示せずそのまま復元する。
      if Custom<>nil then for Pair in MusicStudioPsdConfigObject(Custom.Visibility,'visibility') do
        MusicStudioSetJsonBoolean(Overrides,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
      // 表情/姿勢→演奏step→母音。休符にはstepを重ねず、基本/表情を復元する。
      if (Performance<>nil) and (Performance.Steps<>nil) then
        ActiveIndex := Performance.Steps.ActiveStepAt(FBeatPosition,Performance.StartBeat);
      if ActiveIndex>=0 then begin
        for Pair in MusicStudioPsdConfigObject(Performance.StepConfigs[ActiveIndex],'visibility') do
          if not Track.Source.Document.HasLayer(Pair.JsonString.Value) then
            raise Exception.Create('演奏stepのPSDレイヤーが見つかりません: '+Pair.JsonString.Value);
        MergeVisibility(Track.Source.Document,Overrides,Performance.StepConfigs[ActiveIndex]);
      end;
      if (Performance<>nil) and (Performance.Instrument<>nil) then begin
        CommonStates := Performance.Instrument.StatesAt(FBeatPosition,Performance.StartBeat);
        K := 0; for CommonState in CommonStates do if not MusicStudioActionRow(CommonState.Row) then begin CommonStates[K] := CommonState; Inc(K); end;
        SetLength(CommonStates,K);
      end;
      SetLength(ActionRanges,RangeCount);
      CommonStates := CommonStates+MusicStudioInstrumentActionStates(ActionRanges,Track.Source.Document.InstrumentRules,FBeatPosition);
      for I := 0 to High(Independent) do if Independent[I]<>nil then begin
        Entry := Independent[I];
        // 独立ポーズの実要素は演奏配置外で使う。明示通常は内部ポーズも打ち消せる。
        if (Entry.Selection.Row='ポーズ') and (Entry.Selection.SelectionMode='choice') and (Performance<>nil) then Continue;
        K := 0; for CommonState in CommonStates do if CommonState.Row<>Entry.Selection.Row then begin CommonStates[K] := CommonState; Inc(K); end;
        SetLength(CommonStates,K+1); CommonStates[K] := Entry.Selection; HasIndependent := True;
      end;
      if HasIndependent or (RangeCount>0) or ((Performance<>nil) and (Performance.Instrument<>nil)) then begin
        for CommonState in CommonStates do if (CommonState.Row='ポーズ') and
          Track.Source.Document.InstrumentRules.HasChoice(CommonState.Row,CommonState.Choice) then PoseActive := True;
        CommonVisibility := Track.Source.Document.InstrumentRules.Visibility(CommonStates,(Performance=nil) or (Performance.Instrument=nil));
        try for Pair in CommonVisibility do MusicStudioSetJsonBoolean(Overrides,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
        finally CommonVisibility.Free; end;
      end;
      // 旧PSDプリセットも独立スロットとして共通演奏より後に重ねる。
      for Entry in Track.Placements do if not Entry.IsCustomExpression and (Entry.Visibility<>nil) and (Entry.ErrorText='') and
        (FSeconds>=Entry.StartSeconds) and (FSeconds<Entry.StartSeconds+Entry.LengthSeconds) then
          MergeVisibility(Track.Source.Document,Overrides,Entry.Visibility);
      Track.MouthScale := 1; Track.MouthKey := '';
      if (Singing<>nil) and not PoseActive then Mouth := MouthAt(Singing,Track.MouthScale);
      if not MusicStudioAnimateMouthSize(Track.Source.Config) then Track.MouthScale := 1;
      if PoseActive then Mouth := -1;
      Config := TJSONObject(Track.Source.Config.Clone);
      Config.RemovePair('visibility').Free; Config.AddPair('visibility',Overrides); Overrides := nil;
      Overrides := BuildMusicStudioPsdOverrides(Track.Source.Document,Config,Mouth);
      if Mouth>0 then begin
        Track.MouthKey := MusicStudioSelectedMouth(Track.Source.Document,Config,Mouth);
      end;
      Key := Overrides.ToJSON+'|'+Track.MouthKey+'|'+FloatToStr(Track.MouthScale,TFormatSettings.Invariant); Track.BaseKey := Key;
      for T in Transforms do Key := Key+'|'+TransformKey(T);
      Track.WarningText := Warning;
      if Key=Track.DesiredKey then Exit;
      Track.DesiredKey := Key; Track.ErrorText := ''; Inc(FNextGeneration); Track.RequestGeneration := FNextGeneration;
      Track.Overrides.Free; Track.Overrides := Overrides; Overrides := nil;
      Track.Transforms := Transforms; Track.NeedRender := True;
      if not FRealtimePlayback and (Track.RenderJob<>nil) then Track.RenderJob.Terminate;
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
    if not SourceEnabled(Source) or not Source.NeedLoad or (Source.LoadJob<>nil) then Continue;
    Source.NeedLoad := False;
    Load := TMusicStudioPsdLayerLoadJob.Create(Source.Path,Source.Generation);
    Source.LoadJob := Load; FLoads.Add(Load); Inc(FLoadCount); Load.Start;
  end;
  if FTracks.Count=0 then Exit;
  for I := 0 to FTracks.Count-1 do begin
    if FRenders.Count>=2 then Break;
    Index := (FNextTrack+I) mod FTracks.Count; Track := FTracks[Index];
    if not Track.Enabled or not Track.NeedRender or (Track.RenderJob<>nil) or (Track.Source.Document=nil) then Continue;
    Base := nil; Track.Source.BaseImages.TryGetValue(Track.BaseKey,Base);
    Render := TMusicStudioSceneRenderJob.Create(Track.Source.Document,Track.Overrides,Base,Track.Transforms,FMaximumImageDimension,Track.MouthKey,Track.MouthScale);
    Render.PlaybackEpoch := FPlaybackEpoch; Render.PositionSeconds := FSeconds;
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
    Stamp: string; Resolved: TJSONObject; Before: Integer; Now: UInt64; CheckNow: Boolean;
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
        Source.Document := L.TakeDocument; Source.ErrorText := L.ErrorMessage;
        if (Source.Document<>nil) and (Source.Config<>nil) then begin
          Resolved := ResolveMusicStudioMouthConfig(Source.Document,Source.Config); Source.Config.Free; Source.Config := Resolved;
        end;
        Inc(FSerial);
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
        if (Track<>nil) and Track.Enabled and (Track.RenderJob=R) and
          (((Track.RequestGeneration=R.RequestGeneration) and (Track.DesiredKey=R.ImageKey)) or
           (FRealtimePlayback and (R.PlaybackEpoch=FPlaybackEpoch) and (R.RequestGeneration>Track.PublishedGeneration) and
            (R.ErrorText='') and (R.FImage<>nil))) then begin
          Track.PublishedGeneration := R.RequestGeneration; Track.ImageSeconds := R.PositionSeconds;
          MusicStudioPerfAdd('scene.publishLag',MusicStudioPerfElapsed(R.FFinishedTick));
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
    if (Track=nil) or (Track.ImageKey<>R.ImageKey) then MusicStudioPerfAdd('scene.discarded',0);
    FRenders.Delete(I);
  end;
  for Track in FTracks do RefreshTrack(Track); // MIDIの非同期索引完成も次のPollで口形へ反映する。
  StartJobs; Result := Before<>FSerial;
end;

procedure TMusicStudioPsdSceneCache.SetRealtimePlayback(Value: Boolean);
var Track: TMusicStudioSceneTrack;
begin
  if FRealtimePlayback=Value then Exit;
  FRealtimePlayback := Value; Inc(FPlaybackEpoch);
  if not Value then for Track in FTracks do begin
    if (Track.RenderJob<>nil) and (Track.RenderJob.RequestGeneration<>Track.RequestGeneration) then Track.RenderJob.Terminate;
    // A paused cursor must converge to its exact image even when the desired key has not changed.
    if (Track.ImageKey<>Track.DesiredKey) and ((Track.RenderJob=nil) or
      (Track.RenderJob.RequestGeneration<>Track.RequestGeneration)) then Track.NeedRender := True;
  end;
end;
function TMusicStudioPsdSceneCache.PublishedSecondsForTrack(TrackIndex: Integer): Double;
var Track: TMusicStudioSceneTrack;
begin
  Result := -1; Track := TrackFor(TrackIndex);
  if (Track<>nil) and Track.Enabled and (Track.Image<>nil) then Result := Track.ImageSeconds;
end;
function TMusicStudioPsdSceneCache.SourceEnabled(Source: TMusicStudioSceneSource): Boolean;
var Track: TMusicStudioSceneTrack;
begin Result := False; for Track in FTracks do if Track.Enabled and (Track.Source=Source) then Exit(True); end;
procedure TMusicStudioPsdSceneCache.SetTrackEnabled(TrackIndex: Integer; Enabled: Boolean);
var Track: TMusicStudioSceneTrack;
begin
  Track := TrackFor(TrackIndex); if (Track=nil) or (Track.Enabled=Enabled) then Exit;
  Track.Enabled := Enabled; Inc(FNextGeneration); Track.RequestGeneration := FNextGeneration;
  if Track.RenderJob<>nil then Track.RenderJob.Terminate;
  if Enabled then RefreshTrack(Track) else begin Track.NeedRender := False; FreeAndNil(Track.Image); Track.DesiredKey := ''; end;
  Inc(FSerial); StartJobs;
end;
function TMusicStudioPsdSceneCache.NativeSizeForTrack(TrackIndex: Integer): TSize;
var Track: TMusicStudioSceneTrack;
begin
  Result := TSize.Create(0,0); Track := TrackFor(TrackIndex);
  if (Track<>nil) and (Track.Source<>nil) and (Track.Source.Document<>nil) then
    Result := TSize.Create(Track.Source.Document.Width,Track.Source.Document.Height);
end;
function TMusicStudioPsdSceneCache.ImageForTrack(TrackIndex: Integer): TBitmap;
var Track: TMusicStudioSceneTrack;
begin Result := nil; Track := TrackFor(TrackIndex); if (Track<>nil) and Track.Enabled then Result := Track.Image; end;
function TMusicStudioPsdSceneCache.StatusForTrack(TrackIndex: Integer): string;
var Track: TMusicStudioSceneTrack;
begin
  Track := TrackFor(TrackIndex); if Track=nil then Exit('PSDトラックではありません');
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
