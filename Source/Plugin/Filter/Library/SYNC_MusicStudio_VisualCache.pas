unit SYNC_MusicStudio_VisualCache;
// MIDI/PSDの共有読込。ピアノロールの索引はワーカーで構築、Paintは既存タイル/画像だけを利用。
interface
uses System.Classes, System.SyncObjs, System.Generics.Collections, System.Types,
  Winapi.Windows, Vcl.Graphics, SYNC_MusicStudio_SingingData, SYNC_MusicStudio_PsdPreview,
  SYNC_MusicStudio_BitmapCache;
type
  TMusicStudioVisualKind = (vkMidi,vkPsd);
  TMusicStudioVisualStatus = (vsUnselected,vsPending,vsReady,vsMissing,vsBroken);
  TMusicStudioVisualRequest = record
    Kind: TMusicStudioVisualKind;
    Path: string;
    Visible: Boolean;
    PsdVersion,ConfigJSON,ExpressionJSON: string; // 表情は基本PSD設定を変更せず合成する。
  end;
  TMusicStudioRollPhrase = record
    FirstNote,LastNote: Integer;
    StartSeconds,EndSeconds: Double;
    Lowest,Highest,PitchLow,PitchHigh,PitchSpan: Integer;
  end;
  TMusicStudioRollTrack = class
    Notes: TMusicStudioSingingNotes; // 開始秒順
    PrefixEnd: TArray<Double>; // 長い音符を含め、可視区間の候補を二分探索する。
    Lowest,Highest: Integer;
    PitchLow,PitchHigh,PitchSpan: Integer; // 全トラックの要約。描画はフレーズ別の音域を使う。
    Phrases: TArray<TMusicStudioRollPhrase>;
    NotePhrases: TArray<Integer>; // 各音符から解析済みフレーズへ。タイル/配置端で再分割しない。
    List: TList<TMusicStudioSingingNote>;
    constructor Create;
    destructor Destroy; override;
    function FirstOverlap(Seconds: Double): Integer;
    procedure PreparePitchRange(Cancel: TThread = nil);
  end;
  TMusicStudioRollTracks = TObjectDictionary<Integer,TMusicStudioRollTrack>;
  TMusicStudioIndexedMidiJob = class(TMusicStudioSingingJob)
  private
    FReady: TEvent;
  protected
    procedure Execute; override;
  public
    Rolls: TMusicStudioRollTracks;
    constructor Create(const Path: string; ID: Integer);
    destructor Destroy; override;
    function Done: Boolean; reintroduce;
  end;
  TMusicStudioVisualSource = class
    Kind: TMusicStudioVisualKind;
    Path,Fingerprint,Message: string;
    PsdVersion,ConfigJSON,ExpressionJSON: string;
    LastUsed: UInt64;
    Revision,JobRevision: Integer;
    Visible,PsdAdmitted: Boolean; // 可視要求の先頭64実体だけが画像枠を予約する。
    Status: TMusicStudioVisualStatus;
    Midi: TMusicStudioSingingSource;
    Rolls: TMusicStudioRollTracks;
    Image: TBitmap; // premultiplied BGRA、長辺512px以内。原PSDは変更しない。
    MidiJob: TMusicStudioIndexedMidiJob;
    PsdJob: TMusicStudioPsdPreviewJob;
    destructor Destroy; override;
  end;
  TMusicStudioVisualCache = class
  private
    FSources: TObjectDictionary<string,TMusicStudioVisualSource>;
    FRetired: TObjectList<TThread>;
    FBitmaps: TMusicStudioBitmapCache;
    FRevision,FSerial,FMidiDecodeCount,FPsdDecodeCount,FRasterCount: Integer;
    FUseStamp: UInt64;
    FPrimaryRequests,FLibraryRequests: TArray<TMusicStudioVisualRequest>;
    function Key(Kind: TMusicStudioVisualKind; const Path: string; const PsdVersion: string = ''): string;
    procedure SyncSources;
    procedure UpdatePsdReservations;
    function PsdSlotsInUse: Integer;
    function EvictPsdImage: Boolean;
    procedure TrimPsdImages;
    procedure Retire(Source: TMusicStudioVisualSource);
    function CheckFile(Source: TMusicStudioVisualSource): Boolean;
    procedure StartJobs;
    procedure AdoptPsd(Source: TMusicStudioVisualSource);
    function RollTile(Source: TMusicStudioVisualSource; Track,Index,Height,PPI: Integer;
      Scale: Double; Background,Foreground: TColor; Lyrics: Boolean): TBitmap;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure SetSources(const Requests: TArray<TMusicStudioVisualRequest>);
    // 一覧とタイムラインの要求を合流。片方のスクロールで他方のsourceを失わない。
    procedure SetLibrarySources(const Requests: TArray<TMusicStudioVisualRequest>);
    function Poll(CheckFiles: Boolean = False): Boolean;
    function Find(Kind: TMusicStudioVisualKind; const Path: string; const PsdVersion: string = ''): TMusicStudioVisualSource;
    function MidiMessage(Source: TMusicStudioVisualSource; Track: Integer): string;
    procedure DrawRoll(Canvas: TCanvas; const R,VisibleArea: TRect; Source: TMusicStudioVisualSource;
      Track: Integer; Scale: Double; PPI: Integer; Background,Foreground: TColor; Transparent: Boolean = False; Lyrics: Boolean = False);
    function Thumbnail(Source: TMusicStudioVisualSource; Width,Height,PPI: Integer; Background: TColor): TBitmap;
    function ActiveJobs: Integer;
    function BitmapCount: Integer;
    property Serial: Integer read FSerial;
    property MidiDecodeCount: Integer read FMidiDecodeCount;
    property PsdDecodeCount: Integer read FPsdDecodeCount;
    property RasterCount: Integer read FRasterCount;
  end;
implementation
uses System.SysUtils, System.Math, System.JSON, System.Generics.Defaults,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig;
type
  TMusicStudioRollThreadAccess = class(TThread);
  TMusicStudioConfiguredPsdJob = class(TMusicStudioPsdPreviewJob)
  private
    FConfigJSON,FExpressionJSON: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const FilePath,ConfigJSON,ExpressionJSON: string);
  end;

constructor TMusicStudioConfiguredPsdJob.Create(const FilePath,ConfigJSON,ExpressionJSON: string);
begin inherited Create(FilePath); FConfigJSON := ConfigJSON; FExpressionJSON := ExpressionJSON; end;

procedure TMusicStudioConfiguredPsdJob.Execute;
var Document: TMusicStudioLayerDocument; Config,Overrides,Expression: TJSONObject;
  Image: TBitmap; X,Y,W,H: Integer; Factor: Double; Row: PByte;
begin
  Document := TMusicStudioLayerDocument.Create; Config := nil; Overrides := nil; Expression := nil; Image := TBitmap.Create;
  try
    try
      if Terminated then Exit;
      if not Document.LoadFile(Path) then raise Exception.Create(Document.LastError);
      if Terminated then Exit;
      Config := ParseMusicStudioPsdConfig(FConfigJSON);
      if FExpressionJSON<>'' then begin
        Expression := ParseMusicStudioPsdConfig(FExpressionJSON);
        Overrides := BuildMusicStudioExpressionOverrides(Document,Config,Expression);
      end else Overrides := BuildMusicStudioPsdOverrides(Document,Config,0);
      if not Document.Render(Image,Overrides) then raise Exception.Create(Document.LastError);
      if Terminated then Exit;
      Factor := Min(1.0,512.0/Max(Image.Width,Image.Height));
      W := Max(1,Round(Image.Width*Factor)); H := Max(1,Round(Image.Height*Factor));
      Width := W; Height := H; SetLength(Pixels,W*H*4);
      for Y := 0 to H-1 do begin
        if Terminated then begin Pixels := nil; Exit; end;
        Row := Image.ScanLine[Int64(Y)*Image.Height div H];
        for X := 0 to W-1 do Move(Row[Int64(X)*Image.Width div W*4],Pixels[(Y*W+X)*4],4);
      end;
    except on E: Exception do begin ErrorText := E.Message; Pixels := nil; end; end;
  finally Image.Free; Overrides.Free; Expression.Free; Config.Free; Document.Free; end;
end;
constructor TMusicStudioRollTrack.Create;
begin inherited; Lowest := 127; Highest := 0; List := TList<TMusicStudioSingingNote>.Create; end;
destructor TMusicStudioRollTrack.Destroy;
begin List.Free; inherited; end;
function TMusicStudioRollTrack.FirstOverlap(Seconds: Double): Integer;
var Hi,Mid: Integer;
begin
  Result := 0; Hi := Length(Notes);
  while Result<Hi do begin Mid := (Result+Hi) div 2; if PrefixEnd[Mid]<=Seconds then Result := Mid+1 else Hi := Mid; end;
end;
procedure FitPitchRange(Lowest,Highest: Integer; out PitchLow,PitchHigh,PitchSpan: Integer);
const MinimumSpan = 5;
begin
  if Highest<Lowest then begin PitchLow := 0; PitchHigh := MinimumSpan-1; end
  else begin
    PitchLow := Max(0,Lowest-1); PitchHigh := Min(127,Highest+1);
    if PitchHigh-PitchLow+1<MinimumSpan then begin
      PitchLow := Max(0,PitchLow-(MinimumSpan-(PitchHigh-PitchLow+1)+1) div 2);
      PitchHigh := Min(127,PitchLow+MinimumSpan-1); PitchLow := Max(0,PitchHigh-MinimumSpan+1);
    end;
  end;
  PitchSpan := PitchHigh-PitchLow+1;
end;
procedure TMusicStudioRollTrack.PreparePitchRange(Cancel: TThread);
const TimeTolerance = 1E-9; // 浮動小数点変換の丸めだけを許容。実際の短い休符は維持する。
var Groups: TList<TMusicStudioRollPhrase>; Phrase: TMusicStudioRollPhrase; I: Integer;
  procedure FinishPhrase;
  begin
    FitPitchRange(Phrase.Lowest,Phrase.Highest,Phrase.PitchLow,Phrase.PitchHigh,Phrase.PitchSpan);
    Groups.Add(Phrase);
  end;
begin
  FitPitchRange(Lowest,Highest,PitchLow,PitchHigh,PitchSpan);
  Phrases := nil; SetLength(NotePhrases,Length(Notes));
  if Length(Notes)=0 then Exit;
  Groups := TList<TMusicStudioRollPhrase>.Create;
  try
    Phrase := Default(TMusicStudioRollPhrase); Phrase.FirstNote := -1;
    for I := 0 to High(Notes) do begin
      if (I mod 1024=0) and (Cancel<>nil) and TMusicStudioRollThreadAccess(Cancel).Terminated then Exit;
      // The running maximum end merges chords and notes bridged by a sustained tone.
      if (Phrase.FirstNote<0) or (Notes[I].StartSeconds>Phrase.EndSeconds+TimeTolerance) then begin
        if Phrase.FirstNote>=0 then FinishPhrase;
        Phrase.FirstNote := I; Phrase.StartSeconds := Notes[I].StartSeconds;
        Phrase.EndSeconds := Notes[I].EndSeconds; Phrase.Lowest := Notes[I].Key; Phrase.Highest := Notes[I].Key;
      end else begin
        Phrase.EndSeconds := Max(Phrase.EndSeconds,Notes[I].EndSeconds);
        Phrase.Lowest := Min(Phrase.Lowest,Notes[I].Key); Phrase.Highest := Max(Phrase.Highest,Notes[I].Key);
      end;
      Phrase.LastNote := I; NotePhrases[I] := Groups.Count;
    end;
    FinishPhrase; Phrases := Groups.ToArray;
  finally Groups.Free; end;
end;
constructor TMusicStudioIndexedMidiJob.Create(const Path: string; ID: Integer);
begin inherited; FReady := TEvent.Create(nil,True,False,''); end;
destructor TMusicStudioIndexedMidiJob.Destroy;
begin Terminate; WaitFor; Rolls.Free; FReady.Free; inherited; end;
function TMusicStudioIndexedMidiJob.Done: Boolean;
begin Result := (FReady.WaitFor(0)=wrSignaled) or Finished; end;
procedure TMusicStudioIndexedMidiJob.Execute;
var Note: TMusicStudioSingingNote; Track: TMusicStudioSingingTrack;
  Roll: TMusicStudioRollTrack; I,Count: Integer; EndTime: Double;
begin
  try
    try
      Source := LoadMusicStudioSinging(FilePath,Self);
      if Terminated or not (Source.Status in [ssReady,ssNoLyrics]) then Exit;
      Rolls := TMusicStudioRollTracks.Create([doOwnsValues]);
      for Track in Source.Tracks do Rolls.Add(Track.Index,TMusicStudioRollTrack.Create);
      Count := 0;
      for Note in Source.Notes do begin
        Inc(Count); if (Count mod 1024=0) and Terminated then Exit;
        if Rolls.TryGetValue(Note.TrackIndex,Roll) then begin
          Roll.List.Add(Note); Roll.Lowest := Min(Roll.Lowest,Note.Key); Roll.Highest := Max(Roll.Highest,Note.Key);
        end;
      end;
      for Roll in Rolls.Values do begin
        if Terminated then Exit;
        Roll.List.Sort(TComparer<TMusicStudioSingingNote>.Construct(
          function(const A,B: TMusicStudioSingingNote): Integer
          begin if A.StartSeconds < B.StartSeconds then Result := -1 else if A.StartSeconds > B.StartSeconds then Result := 1 else Result := 0; end));
        Roll.Notes := Roll.List.ToArray; FreeAndNil(Roll.List);
        Roll.PreparePitchRange(Self); if Terminated then Exit;
        SetLength(Roll.PrefixEnd,Length(Roll.Notes)); EndTime := 0;
        for I := 0 to High(Roll.Notes) do begin
          if (I mod 1024=0) and Terminated then Exit;
          EndTime := Max(EndTime,Roll.Notes[I].EndSeconds); Roll.PrefixEnd[I] := EndTime;
        end;
      end;
      Source.Notes := nil; // 索引済みの音符だけを保持し、全トラック配列を二重保持しない。
    except on E: Exception do begin Source.Status := ssBroken; Source.Message := E.Message; FreeAndNil(Rolls); end; end;
  finally FReady.SetEvent; end;
end;
destructor TMusicStudioVisualSource.Destroy;
begin Rolls.Free; Image.Free; inherited; end;
constructor TMusicStudioVisualCache.Create;
begin
  inherited; FSources := TObjectDictionary<string,TMusicStudioVisualSource>.Create([doOwnsValues]);
  FRetired := TObjectList<TThread>.Create(True); FBitmaps := TMusicStudioBitmapCache.Create;
end;
destructor TMusicStudioVisualCache.Destroy;
begin Clear; FRetired.Free; FBitmaps.Free; FSources.Free; inherited; end;
function TMusicStudioVisualCache.Key(Kind: TMusicStudioVisualKind; const Path,PsdVersion: string): string;
begin Result := IntToStr(Ord(Kind))+':'+MusicStudioPathKey(Path); if PsdVersion<>'' then Result := Result+'|'+PsdVersion; end;
procedure TMusicStudioVisualCache.Retire(Source: TMusicStudioVisualSource);
begin
  if Assigned(Source.MidiJob) then begin Source.MidiJob.Terminate; FRetired.Add(Source.MidiJob); Source.MidiJob := nil; end;
  if Assigned(Source.PsdJob) then begin Source.PsdJob.Terminate; FRetired.Add(Source.PsdJob); Source.PsdJob := nil; end;
end;
procedure TMusicStudioVisualCache.Clear;
var Source: TMusicStudioVisualSource;
begin
  for Source in FSources.Values do Retire(Source);
  FSources.Clear; FPrimaryRequests := nil; FLibraryRequests := nil; FBitmaps.Clear; Inc(FRevision); Inc(FSerial);
end;
function TMusicStudioVisualCache.CheckFile(Source: TMusicStudioVisualSource): Boolean;
var Stamp: string;
begin
  Stamp := MusicStudioFileStamp(Source.Path);
  Result := (Source.Revision=0) or (Stamp<>Source.Fingerprint); if not Result then Exit;
  Retire(Source); Inc(FRevision); Inc(FSerial); Source.Revision := FRevision; Source.Fingerprint := Stamp;
  FreeAndNil(Source.Image); FreeAndNil(Source.Rolls); Source.Midi := Default(TMusicStudioSingingSource); FBitmaps.Clear;
  if Source.Path='' then begin Source.Status := vsUnselected; Source.Message := '未割当'; end
  else if Stamp='' then begin Source.Status := vsMissing; Source.Message := '参照先が見つかりません'; end
  else begin Source.Status := vsPending; Source.Message := '読込中…'; end;
end;
procedure TMusicStudioVisualCache.SetSources(const Requests: TArray<TMusicStudioVisualRequest>);
begin FPrimaryRequests := Copy(Requests); SyncSources; end;
procedure TMusicStudioVisualCache.SetLibrarySources(const Requests: TArray<TMusicStudioVisualRequest>);
begin FLibraryRequests := Copy(Requests); SyncSources; end;
procedure TMusicStudioVisualCache.SyncSources;
var Wanted: TDictionary<string,Boolean>; Request: TMusicStudioVisualRequest; Source: TMusicStudioVisualSource; K: string;
begin
  Wanted := TDictionary<string,Boolean>.Create;
  try
    for Source in FSources.Values do Source.Visible := False;
    for Request in FPrimaryRequests+FLibraryRequests do begin
      K := Key(Request.Kind,Request.Path,Request.PsdVersion); Wanted.AddOrSetValue(K,True);
      if not FSources.TryGetValue(K,Source) then begin
        Source := TMusicStudioVisualSource.Create; Source.Kind := Request.Kind; Source.Path := Request.Path;
        Source.PsdVersion := Request.PsdVersion; Source.ConfigJSON := Request.ConfigJSON;
        Source.ExpressionJSON := Request.ExpressionJSON;
        FSources.Add(K,Source); CheckFile(Source);
      end;
      Source.Visible := Source.Visible or Request.Visible;
      if Request.Visible then begin Inc(FUseStamp); Source.LastUsed := FUseStamp; end;
    end;
    for K in FSources.Keys.ToArray do if not Wanted.ContainsKey(K) then begin Retire(FSources[K]); FSources.Remove(K); FBitmaps.Clear; Inc(FSerial); end;
    UpdatePsdReservations; TrimPsdImages; StartJobs;
  finally Wanted.Free; end;
end;
procedure TMusicStudioVisualCache.UpdatePsdReservations;
var Request: TMusicStudioVisualRequest; Source: TMusicStudioVisualSource; Count: Integer; Changed: Boolean;
begin
  // Stable request order gives the timeline priority, then the visible library rows.
  // Paint/LRU touches do not rotate admission when more than 64 sources are visible.
  for Source in FSources.Values do Source.PsdAdmitted := False;
  Count := 0; Changed := False;
  for Request in FPrimaryRequests+FLibraryRequests do
    if Request.Visible and (Request.Kind=vkPsd) and
      FSources.TryGetValue(Key(Request.Kind,Request.Path,Request.PsdVersion),Source) and
      not Source.PsdAdmitted and (Source.Status in [vsPending,vsReady]) and (Count<64) then begin
      Source.PsdAdmitted := True; Inc(Count);
    end;
  for Source in FSources.Values do if (Source.Kind=vkPsd) and not Source.PsdAdmitted then begin
    if Assigned(Source.PsdJob) then Retire(Source);
    if Source.Visible and Assigned(Source.Image) then begin
      FreeAndNil(Source.Image); Source.Status := vsPending; Changed := True;
    end;
  end;
  if Changed then begin FBitmaps.Clear; Inc(FSerial); end;
end;
function TMusicStudioVisualCache.PsdSlotsInUse: Integer;
var Source: TMusicStudioVisualSource;
begin
  Result := 0;
  for Source in FSources.Values do if (Source.Kind=vkPsd) and
    (Assigned(Source.Image) or Assigned(Source.PsdJob)) then Inc(Result);
end;
function TMusicStudioVisualCache.EvictPsdImage: Boolean;
var Source,Oldest: TMusicStudioVisualSource;
begin
  Oldest := nil;
  for Source in FSources.Values do if Assigned(Source.Image) and not Source.PsdAdmitted and
    ((Oldest=nil) or (Source.LastUsed<Oldest.LastUsed)) then Oldest := Source;
  Result := Oldest<>nil;
  if Result then begin
    FreeAndNil(Oldest.Image); Oldest.Status := vsPending; FBitmaps.Clear; Inc(FSerial);
  end;
end;
procedure TMusicStudioVisualCache.TrimPsdImages;
begin
  // Jobs reserve a slot before decoding; adoption cannot create a 65th image.
  while PsdSlotsInUse>64 do if not EvictPsdImage then Break;
end;
function TMusicStudioVisualCache.ActiveJobs: Integer;
var Source: TMusicStudioVisualSource;
begin
  Result := FRetired.Count;
  for Source in FSources.Values do begin if Assigned(Source.MidiJob) then Inc(Result); if Assigned(Source.PsdJob) then Inc(Result); end;
end;
function TMusicStudioVisualCache.BitmapCount: Integer;
begin Result := FBitmaps.Count; end;
procedure TMusicStudioVisualCache.StartJobs;
var Source: TMusicStudioVisualSource; Count: Integer;
begin
  Count := ActiveJobs;
  for Source in FSources.Values do begin
    if Count>=2 then Break;
    if Source.Visible and ((Source.Kind=vkMidi) or Source.PsdAdmitted) and
      (Source.Status=vsPending) and (Source.MidiJob=nil) and (Source.PsdJob=nil) then begin
      if Source.Kind=vkPsd then begin
        while PsdSlotsInUse>=64 do if not EvictPsdImage then Break;
        if PsdSlotsInUse>=64 then Continue;
      end;
      Source.JobRevision := Source.Revision;
      if Source.Kind=vkMidi then begin
        Source.MidiJob := TMusicStudioIndexedMidiJob.Create(Source.Path,Source.Revision); Source.MidiJob.Start; Inc(FMidiDecodeCount);
      end else begin
        if Source.PsdVersion='' then Source.PsdJob := TMusicStudioPsdPreviewJob.Create(Source.Path)
        else Source.PsdJob := TMusicStudioConfiguredPsdJob.Create(Source.Path,Source.ConfigJSON,Source.ExpressionJSON);
        Source.PsdJob.Start; Inc(FPsdDecodeCount);
      end;
      Inc(Count);
    end;
  end;
end;
procedure TMusicStudioVisualCache.AdoptPsd(Source: TMusicStudioVisualSource);
var Job: TMusicStudioPsdPreviewJob; X,Y,W,H: Integer; Factor: Double; Row: PByte;
begin
  Job := Source.PsdJob; Factor := Min(1.0,512.0/Max(Job.Width,Job.Height));
  W := Max(1,Round(Job.Width*Factor)); H := Max(1,Round(Job.Height*Factor));
  Source.Image := TBitmap.Create; Source.Image.PixelFormat := pf32bit; Source.Image.SetSize(W,H);
  // VCL premultiplies existing pixels when switching from afIgnored. Mark the
  // empty bitmap first: the PSD worker already supplies premultiplied BGRA.
  Source.Image.AlphaFormat := afPremultiplied;
  for Y := 0 to H-1 do begin
    Row := Source.Image.ScanLine[Y];
    for X := 0 to W-1 do Move(Job.Pixels[(Int64(Y)*Job.Height div H*Job.Width+Int64(X)*Job.Width div W)*4],Row[X*4],4);
  end;
end;
function TMusicStudioVisualCache.Poll(CheckFiles: Boolean): Boolean;
var Source: TMusicStudioVisualSource; I: Integer; Done: Boolean;
begin
  Result := False;
  for I := FRetired.Count-1 downto 0 do if FRetired[I].Finished then FRetired.Delete(I);
  for Source in FSources.Values do begin
    if CheckFiles and CheckFile(Source) then Result := True;
    Done := Assigned(Source.MidiJob) and Source.MidiJob.Done;
    if Assigned(Source.PsdJob) then Done := Source.PsdJob.Done;
    if not Done then Continue;
    if CheckFile(Source) then begin Result := True; Continue; end;
    if (Source.JobRevision<>Source.Revision) or
      (Assigned(Source.MidiJob) and ((Source.MidiJob.RequestID<>Source.Revision) or (Source.MidiJob.FilePath<>Source.Path))) or
      (Assigned(Source.PsdJob) and (Source.PsdJob.Path<>Source.Path)) then begin Retire(Source); Continue; end;
    Source.Status := vsReady; Source.Message := '';
    if Assigned(Source.MidiJob) then begin
      Source.Midi := Source.MidiJob.Source;
      if not (Source.Midi.Status in [ssReady,ssNoLyrics]) then begin Source.Status := vsBroken; Source.Message := Source.Midi.Message; end;
      Source.Rolls := Source.MidiJob.Rolls; Source.MidiJob.Rolls := nil; FreeAndNil(Source.MidiJob);
    end else begin
      if Source.PsdJob.ErrorText<>'' then begin Source.Status := vsBroken; Source.Message := Source.PsdJob.ErrorText; end
      else if Length(Source.PsdJob.Pixels)>0 then AdoptPsd(Source) else begin Source.Status := vsBroken; Source.Message := '合成画像がありません'; end;
      FreeAndNil(Source.PsdJob);
    end;
    Inc(FSerial); Result := True;
  end;
  UpdatePsdReservations; TrimPsdImages; StartJobs;
end;
function TMusicStudioVisualCache.Find(Kind: TMusicStudioVisualKind; const Path,PsdVersion: string): TMusicStudioVisualSource;
begin if not FSources.TryGetValue(Key(Kind,Path,PsdVersion),Result) then Result := nil; end;
function TMusicStudioVisualCache.MidiMessage(Source: TMusicStudioVisualSource; Track: Integer): string;
var Roll: TMusicStudioRollTrack;
begin
  if Source=nil then Exit('歌唱データ準備中…');
  if Source.Status<>vsReady then Exit(Source.Message);
  if Track<0 then Exit('歌唱トラック未選択');
  if (Source.Rolls=nil) or not Source.Rolls.TryGetValue(Track,Roll) then Exit('使用トラックがありません');
  if Length(Roll.Notes)=0 then Exit('音符なし');
  Result := '';
end;
function TMusicStudioVisualCache.RollTile(Source: TMusicStudioVisualSource; Track,Index,Height,PPI: Integer;
  Scale: Double; Background,Foreground: TColor; Lyrics: Boolean): TBitmap;
var K: string; B: TBitmap; Roll: TMusicStudioRollTrack; I,J,Y,Margin,InnerHeight,NoteHeight,PreviousPhrase: Integer;
  StartTime,EndTime,Center: Double; R,Grid,TextArea: TRect; Note: TMusicStudioSingingNote; Phrase: TMusicStudioRollPhrase; Color: Longint;
begin
  K := 'm:'+IntToStr(Ord(Lyrics))+':'+IntToStr(Source.Revision)+':'+IntToStr(Track)+':'+IntToStr(Index)+':'+IntToStr(Height)+':'+IntToStr(PPI)+':'+
    MusicStudioDoubleKey(Scale)+':'+IntToStr(Background)+':'+IntToStr(Foreground);
  Result := FBitmaps.Find(K); if Assigned(Result) then Exit;
  Roll := Source.Rolls[Track];
  Margin := Min(Max(1,MulDiv(1,PPI,96)),(Height-1) div 2);
  InnerHeight := Height-2*Margin;
  B := TBitmap.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(256,Height); B.Canvas.Brush.Color := Background; B.Canvas.FillRect(Rect(0,0,256,Height));
    B.Canvas.Font.Name := 'Yu Gothic UI'; B.Canvas.Font.Height := -Max(1,MulDiv(13,PPI,96));
    Color := ColorToRGB(Foreground);
    if (GetRValue(Color)*299+GetGValue(Color)*587+GetBValue(Color)*114)>128000 then B.Canvas.Font.Color := $00202020
    else B.Canvas.Font.Color := clWhite;
    StartTime := Int64(Index)*256/Scale; EndTime := (Int64(Index)+1)*256/Scale;
    I := Roll.FirstOverlap(StartTime); PreviousPhrase := -1; B.Canvas.Brush.Color := Foreground;
    while I<Length(Roll.Notes) do begin
      Note := Roll.Notes[I]; if Note.StartSeconds>=EndTime then Break;
      if Note.EndSeconds>StartTime then begin
        Phrase := Roll.Phrases[Roll.NotePhrases[I]];
        if not Lyrics and (Roll.NotePhrases[I]<>PreviousPhrase) then begin
          PreviousPhrase := Roll.NotePhrases[I];
          Grid := Rect(Max(0,Floor(Phrase.StartSeconds*Scale)-Index*256),0,
            Min(256,Ceil(Phrase.EndSeconds*Scale)-Index*256),Height);
          B.Canvas.Pen.Color := Background xor $00181818;
          for J := Phrase.PitchLow to Phrase.PitchHigh do if J mod 12=0 then begin
            Y := Margin+(Phrase.PitchHigh-J)*InnerHeight div Phrase.PitchSpan;
            B.Canvas.MoveTo(Grid.Left,Y); B.Canvas.LineTo(Grid.Right,Y);
          end;
        end;
        // One scale per phrase preserves intervals; short bodies retain a readable minimum thickness.
        NoteHeight := Min(InnerHeight,Max(Max(1,MulDiv(2,PPI,96)),Ceil(InnerHeight/Phrase.PitchSpan)));
        Center := Margin+(Phrase.PitchHigh-Note.Key+0.5)*InnerHeight/Phrase.PitchSpan;
        Y := EnsureRange(Round(Center-NoteHeight/2),Margin,Height-Margin-NoteHeight);
        if Lyrics then begin
          NoteHeight := Min(InnerHeight,B.Canvas.TextHeight('あ')+Max(2,MulDiv(4,PPI,96)));
          Y := (Height-NoteHeight) div 2;
        end;
        R := Rect(Floor(Note.StartSeconds*Scale)-Index*256,Y,
          Ceil(Note.EndSeconds*Scale)-Index*256,Y+NoteHeight);
        R.Right := Max(R.Left+1,R.Right); B.Canvas.Brush.Style := bsSolid; B.Canvas.FillRect(R);
        if Lyrics and (Note.Lyric<>'') then begin
          TextArea := R; Inc(TextArea.Left,Max(1,MulDiv(2,PPI,96)));
          B.Canvas.Brush.Style := bsClear;
          // 音符開始の左位置を固定し、タイル境界/可視端でも文字を再配置しない。
          DrawTextW(B.Canvas.Handle,PChar(Note.Lyric),Length(Note.Lyric),TextArea,DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
        end;
      end; Inc(I);
    end;
    FBitmaps.Add(K,B); Inc(FRasterCount); Result := B;
  except B.Free; raise; end;
end;
procedure TMusicStudioVisualCache.DrawRoll(Canvas: TCanvas; const R,VisibleArea: TRect; Source: TMusicStudioVisualSource;
  Track: Integer; Scale: Double; PPI: Integer; Background,Foreground: TColor; Transparent,Lyrics: Boolean);
var Visible: TRect; I,First,Last,Saved: Integer; Tile: TBitmap;
begin
  if (R.Height<1) or (Scale<=0) or (MidiMessage(Source,Track)<>'') or not IntersectRect(Visible,R,VisibleArea) then Exit;
  First := Max(0,(Visible.Left-R.Left) div 256); Last := Max(First,(Visible.Right-1-R.Left) div 256);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Visible.Left,Visible.Top,Visible.Right,Visible.Bottom);
    for I := First to Last do begin
      Tile := RollTile(Source,Track,I,R.Height,PPI,Scale,Background,Foreground,Lyrics);
      Tile.TransparentColor := Background; Tile.Transparent := Transparent;
      try Canvas.Draw(R.Left+I*256,R.Top,Tile); finally Tile.Transparent := False; end;
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;
function TMusicStudioVisualCache.Thumbnail(Source: TMusicStudioVisualSource; Width,Height,PPI: Integer; Background: TColor): TBitmap;
var K: string; B: TBitmap; R: TRect; Factor: Double;
begin
  Result := nil;
  if (Source=nil) or (Source.Image=nil) or (Width<1) or (Height<1) then Exit;
  K := 'p:'+IntToStr(Source.Revision)+':'+IntToStr(Width)+':'+IntToStr(Height)+':'+IntToStr(PPI)+':'+IntToStr(Background);
  Result := FBitmaps.Find(K); if Assigned(Result) then Exit;
  B := TBitmap.Create;
  try
    B.PixelFormat := pf32bit; B.SetSize(Width,Height); B.Canvas.Brush.Color := Background; B.Canvas.FillRect(Rect(0,0,Width,Height));
    Factor := Min(Width/Source.Image.Width,Height/Source.Image.Height);
    R := Rect((Width-Round(Source.Image.Width*Factor)) div 2,(Height-Round(Source.Image.Height*Factor)) div 2,0,0);
    R.Right := R.Left+Max(1,Round(Source.Image.Width*Factor)); R.Bottom := R.Top+Max(1,Round(Source.Image.Height*Factor));
    B.Canvas.StretchDraw(R,Source.Image); FBitmaps.Add(K,B); Inc(FRasterCount); Result := B;
  except B.Free; raise; end;
end;
end.
