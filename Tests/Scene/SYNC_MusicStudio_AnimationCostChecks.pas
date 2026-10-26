unit SYNC_MusicStudio_AnimationCostChecks;
// Read-only real PSD/project profiling. The caller provides an isolated library and visual-only JSON.
interface
// PSD/ProjectJSONを読取専用で使い、隔離LibraryRootで無音計測する。Rootへ集計JSON/hash/logを出力する。
procedure RunAnimationCostChecks(const Root,PSD,ProjectJSON,LibraryRoot: string);
implementation
uses System.SysUtils, System.Classes, System.Types, System.JSON, System.IOUtils, System.Diagnostics, System.Hash,
  Winapi.Windows, Vcl.Graphics, SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_MotionData,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PerformanceTrace;
function MS(Tick: Int64): Double;
begin Result := (TStopwatch.GetTimeStamp-Tick)*1000.0/TStopwatch.Frequency; end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('Animation cost: '+Text); end;
function Hash(Image: TBitmap): string;
var Bytes: TBytes; Y: Integer; Stream: TBytesStream;
begin
  SetLength(Bytes,Image.Width*Image.Height*4);
  for Y := 0 to Image.Height-1 do Move(PByte(Image.ScanLine[Y])^,Bytes[Y*Image.Width*4],Image.Width*4);
  Stream := TBytesStream.Create(Bytes);
  try Result := THashSHA2.GetHashString(Stream); finally Stream.Free; end;
end;
procedure RunAnimationCostChecks(const Root,PSD,ProjectJSON,LibraryRoot: string);
var Layers: TMusicStudioLayerDocument; Base,Dest: TBitmap; Motion: TMusicStudioMotionConfig;
  Doc: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary; Scene: TMusicStudioPsdSceneCache;
  Visual: TMusicStudioVisualCache; Requests: TArray<TMusicStudioVisualRequest>; Request: TMusicStudioVisualRequest;
  P: TMusicStudioPattern; Report,Test: TJSONObject; Cases: TJSONArray; Hashes: TStringList;
  Transform: TMusicStudioMotionTransform;
  K: TMusicStudioRhythmType; I,J,Frames,TrackIndex: Integer; Tick,Start,LastRequest: Int64;
  Deadline: UInt64; Elapsed,Total,Maximum,ExactTotal,Published,Previous: Double; Error,BeforePSD,BeforeProject: string;
  procedure Await;
  begin
    Deadline := GetTickCount64+20000;
    repeat
      Visual.Poll; Scene.PollResults;
      if (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Visual.ActiveJobs=0) and
        (Scene.ImageForTrack(TrackIndex)<>nil) then Exit;
      Check(GetTickCount64<Deadline,'scene timeout '+Scene.StatusForTrack(TrackIndex)); Sleep(1);
    until False;
  end;
begin
  ForceDirectories(Root); Report := TJSONObject.Create; Hashes := TStringList.Create;
  Layers := TMusicStudioLayerDocument.Create; Base := TBitmap.Create; Dest := TBitmap.Create;
  Motion := TMusicStudioMotionConfig.Create; Doc := TMusicStudioDocument.Create;
  Store := TMusicStudioSharedPsdLibrary.Create(LibraryRoot); Visual := TMusicStudioVisualCache.Create; Scene := TMusicStudioPsdSceneCache.Create;
  BeforePSD := THashSHA2.GetHashStringFromFile(PSD); BeforeProject := THashSHA2.GetHashStringFromFile(ProjectJSON);
  try
    Tick := TStopwatch.GetTimeStamp; Check(Layers.LoadFile(PSD),Layers.LastError); Report.AddPair('loadMs',TJSONNumber.Create(MS(Tick)));
    Report.AddPair('width',TJSONNumber.Create(Layers.Width)); Report.AddPair('height',TJSONNumber.Create(Layers.Height));
    Report.AddPair('layers',TJSONNumber.Create(Length(Layers.Layers)));
    Tick := TStopwatch.GetTimeStamp; Check(Layers.Render(Base,nil,512),Layers.LastError); Report.AddPair('compose512Ms',TJSONNumber.Create(MS(Tick)));
    Report.AddPair('previewWidth',TJSONNumber.Create(Base.Width)); Report.AddPair('previewHeight',TJSONNumber.Create(Base.Height));
    Cases := TJSONArray.Create; Report.AddPair('motions',Cases); Motion.Strength := 50; Motion.Speed := 2;
    for K := Low(K) to High(K) do begin
      Motion.RhythmType := K; Total := 0; Maximum := 0;
      for I := 0 to 11 do begin
        CalculateMusicStudioMotionTransform(Motion,I/12.0,Transform);
        Tick := TStopwatch.GetTimeStamp; RenderMusicStudioMotion(Base,Dest,Transform); Elapsed := MS(Tick);
        Total := Total+Elapsed; if Elapsed>Maximum then Maximum := Elapsed;
        Hashes.Add(MusicStudioRhythmKey(K)+'-'+IntToStr(I)+'='+Hash(Dest));
      end;
      Test := TJSONObject.Create; Test.AddPair('type',MusicStudioRhythmKey(K)); Test.AddPair('meanMs',TJSONNumber.Create(Total/12));
      Test.AddPair('maxMs',TJSONNumber.Create(Maximum)); Cases.AddElement(Test);
    end;
    Hashes.SaveToFile(TPath.Combine(Root,'motion-hashes.txt'),TEncoding.UTF8);
    Check(Doc.TryLoad(TFile.ReadAllText(ProjectJSON,TEncoding.UTF8),Error),Error); Doc.AssetResolver := Store.ResolvePath;
    TrackIndex := -1;
    for I := 0 to Doc.TrackCount-1 do begin Check(Doc.TrackAt(I).Kind<>'audio','profile input contains audio'); if TrackIndex<0 then TrackIndex := I; end;
    Check(TrackIndex>=0,'no PSD track');
    Requests := nil;
    for I := 0 to Doc.PatternCount-1 do begin
      P := Doc.PatternAt(I); Check(P.Kind<>'audio','profile input contains audio pattern');
      if P.Kind='singing' then begin Request := Default(TMusicStudioVisualRequest); Request.Kind := vkMidi; Request.Path := P.FilePath; Request.Visible := True; Requests := Requests+[Request]; end;
    end;
    Visual.SetSources(Requests); Scene.FrozenSources := True; Scene.Bind(Doc,Store,Visual);
    Await; ExactTotal := 0;
    for J := 0 to 23 do begin
      Tick := TStopwatch.GetTimeStamp; Scene.SetPosition(2.4+J/30.0); Await; ExactTotal := ExactTotal+MS(Tick);
    end;
    Report.AddPair('sceneExactMeanMs',TJSONNumber.Create(ExactTotal/24));
    Report.AddPair('sceneRenders',TJSONNumber.Create(Scene.RenderCount)); Report.AddPair('sceneCompositions',TJSONNumber.Create(Scene.CompositionCount));
    Report.AddPair('midiLoads',TJSONNumber.Create(Visual.MidiDecodeCount));
    Scene.RealtimePlayback := True; Start := TStopwatch.GetTimeStamp; LastRequest := 0; Frames := 0; Previous := -1;
    repeat
      if (LastRequest=0) or (MS(LastRequest)>=30) then begin
        LastRequest := TStopwatch.GetTimeStamp; Scene.SetPosition(2.4+MS(Start)/1000.0);
      end;
      Visual.Poll; Scene.PollResults; Published := Scene.PublishedSecondsForTrack(TrackIndex);
      if Published<>Previous then begin Inc(Frames); Previous := Published; end;
      MusicStudioPerfFlush; Sleep(1);
    until MS(Start)>=2000;
    Scene.RealtimePlayback := False; Scene.SetPosition(4.4); Await;
    Report.AddPair('livePublishedFrames2s',TJSONNumber.Create(Frames));
    Report.AddPair('sourceUnchanged',TJSONBool.Create(BeforePSD=THashSHA2.GetHashStringFromFile(PSD)));
    Check(BeforePSD=THashSHA2.GetHashStringFromFile(PSD),'PSD source changed');
    Check(BeforeProject=THashSHA2.GetHashStringFromFile(ProjectJSON),'profile input project changed');
    MusicStudioPerfFlush(True);
    TFile.WriteAllText(TPath.Combine(Root,'profile-report.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally
    Scene.Free; Visual.Free; Store.Free; Doc.Free; Motion.Free; Dest.Free; Base.Free; Layers.Free; Hashes.Free; Report.Free;
  end;
end;
end.
