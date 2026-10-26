unit SYNC_MusicStudio_InstrumentAppliedChecks;

// 保存済み作品と共通正本の隔離コピーで、実モーダル保存→配置→ホストJSON→映像を確認する。
interface
procedure RunInstrumentAppliedChecks(const Root,ProjectFile,AssetDirectory,LibraryFile: string);
implementation
uses System.SysUtils, System.IOUtils, System.JSON, System.Classes, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PerformanceLibrary,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_PsdSceneCache,
  SYNC_MusicStudio_VideoRenderer;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('INSTRUMENT_APPLIED: '+Message); end;
type TSaveDriver = class
  Timer: TTimer;
  Expected,ExpectedLater: Vcl.Graphics.TBitmap;
  Stage: Integer;
  Started: UInt64;
  Failed,Applied: string;
  procedure Tick(Sender: TObject);
  function Apply(const JSON: string; out Error: string): Boolean;
end;
function TSaveDriver.Apply(const JSON: string; out Error: string): Boolean;
begin Applied := JSON; Error := ''; Result := True; end;
procedure TSaveDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings;
begin
  try
    Check(GetTickCount64-Started<15000,'save dialog timeout');
    for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
      D := TMusicStudioPatternSettings(Screen.Forms[I]);
      if (D.InstrumentFrame=nil) or (D.InstrumentPreview=nil) or D.InstrumentPreview.Busy then Exit;
      if Stage=0 then begin D.InstrumentFrame.Seek(1.1875); Stage := 1; Exit; end;
      if Stage=1 then begin Expected.Assign(D.InstrumentPreview.PreviewBitmap); D.InstrumentFrame.Seek(1.8125); Stage := 2; Exit; end;
      ExpectedLater.Assign(D.InstrumentPreview.PreviewBitmap); Timer.Enabled := False; D.Close; Stage := 3; Exit;
    end;
  except on E: Exception do begin Failed := E.Message; Timer.Enabled := False;
    for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then Screen.Forms[I].Close;
  end; end;
end;
function Tracks(const Text: string): string;
var V: TJSONObject;
begin V := TJSONObject.ParseJSONValue(Text) as TJSONObject; try Result := V.GetValue('tracks').ToJSON; finally V.Free; end; end;
procedure SavePNG(Image: Vcl.Graphics.TBitmap; const Path: string);
var P: TPngImage;
begin P := TPngImage.Create; try P.Assign(Image); P.SaveToFile(Path); finally P.Free; end; end;
procedure RunInstrumentAppliedChecks(const Root,ProjectFile,AssetDirectory,LibraryFile: string);
var UI: TFormMusicStudioSettings; Driver: TSaveDriver; Store: TMusicStudioPerformanceLibrary;
  Latest,Saved,P,Bad: TMusicStudioPattern; Model: TMusicStudioInstrumentData;
  PSDRoot,Target,Before,After,Error,AssetID,ID: string; Meta: TJSONObject; I,J,N,Y,X: Integer;
  Deadline: UInt64; CanClose,Rejected: Boolean; Image: Vcl.Graphics.TBitmap; Beat: Double;
  Scene: TMusicStudioPsdSceneCache; Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Row: PByte;
  procedure Await(Scene: TMusicStudioPsdSceneCache);
  begin Deadline := GetTickCount64+15000;
    repeat Application.ProcessMessages; Scene.PollResults; Sleep(2); Check(GetTickCount64<Deadline,'scene timeout');
    until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(1)<>nil);
  end;
begin
  ForceDirectories(Root); PSDRoot := TPath.Combine(Root,'PSDAssets'); AssetID := TPath.GetFileName(AssetDirectory);
  Target := TPath.Combine(PSDRoot,AssetID); ForceDirectories(Target);
  TFile.Copy(TPath.Combine(AssetDirectory,'asset.json'),TPath.Combine(Target,'asset.json'),False);
  TFile.Copy(TPath.Combine(AssetDirectory,'source.psd'),TPath.Combine(Target,'source.psd'),False);
  Meta := TJSONObject.ParseJSONValue(TFile.ReadAllText(LibraryFile)) as TJSONObject;
  try ID := Meta.GetValue<string>('id'); finally Meta.Free; end;
  Store := TMusicStudioPerformanceLibrary.Create(PSDRoot);
  Target := TPath.Combine(TPath.Combine(Store.Root,'drums'),ID+'.json'); ForceDirectories(TPath.GetDirectoryName(Target)); TFile.Copy(LibraryFile,Target,False);
  UI := TFormMusicStudioSettings.Create(nil); Driver := TSaveDriver.Create; Model := TMusicStudioInstrumentData.Create;
  Scene := TMusicStudioPsdSceneCache.Create; Video := TMusicStudioVideoSession.Create(PSDRoot);
  Driver.Expected := Vcl.Graphics.TBitmap.Create; Driver.ExpectedLater := Vcl.Graphics.TBitmap.Create;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False;
  try
    Check(Store.TryRead('drums',ID,Latest,Error),Error); Model.Load(Latest.ConfigJSON); N := Model.Blocks.Count;
    UI.SilentVisualMode := True; UI.LibraryRoot := PSDRoot; UI.OnApplyJSON := Driver.Apply;
    UI.LoadDocument(TFile.ReadAllText(ProjectFile)); UI.Show; UI.TimelineBox.SelectSlot(1,1); UI.PatternList.ItemIndex := 0; UI.PatternList.OnClick(UI.PatternList);
    Check(UI.EditButton.Enabled,'common performance edit disabled');
    UI.Preview.Seek(1.1875/2); Await(UI.Preview.SceneCache); SavePNG(UI.Preview.SceneCache.ImageForTrack(1),TPath.Combine(Root,'before-integrated.png'));
    UI.Preview.Seek(1.8125/2); Await(UI.Preview.SceneCache); SavePNG(UI.Preview.SceneCache.ImageForTrack(1),TPath.Combine(Root,'before-arms.png'));
    Check(UI.Document.TrySave(Before,Error),Error); Driver.Started := GetTickCount64; Driver.Timer.Interval := 25; Driver.Timer.OnTimer := Driver.Tick; Driver.Timer.Enabled := True;
    UI.EditButton.Click; Check((Driver.Failed='') and (Driver.Stage=3),'save driver '+Driver.Failed);
    Check(UI.Document.TrySave(After,Error),Error); TFile.WriteAllText(TPath.Combine(Root,'project-after.json'),After);
    Check(Store.TryRead('drums',ID,Saved,Error),Error);
    Check(Tracks(Before)=Tracks(After),'placements, IDs, lengths or audio tracks changed');
    J := 0;
    for I := 0 to UI.Document.PatternCount-1 do begin P := UI.Document.PatternAt(I);
      if P.SharedPatternID<>ID then Continue; Inc(J); Model.Load(P.ConfigJSON);
      Writeln('PLACED_PATTERN ',P.ID,' BLOCKS ',Model.Blocks.Count,' EXPECTED ',N);
      Check(Model.Blocks.Count=N,'saved common performance did not update placed snapshot');
      Check(P.LibraryRevision<>Latest.LibraryRevision,'placed revision did not advance');
      Check((P.ConfigJSON=Saved.ConfigJSON) and (P.LibraryRevision=Saved.LibraryRevision) and
        (P.Name=Saved.Name) and (P.Color=Saved.Color),'placed data differs from saved common pattern');
    end;
    Check(J=2,'two existing versions were not preserved as placed IDs');
    UI.Preview.Seek(1.1875/2); Await(UI.Preview.SceneCache); Image := UI.Preview.SceneCache.ImageForTrack(1);
    Check((Image.Width=Driver.Expected.Width) and (Image.Height=Driver.Expected.Height),'editor/integrated dimensions');
    for Y := 0 to Image.Height-1 do Check(CompareMem(Image.ScanLine[Y],Driver.Expected.ScanLine[Y],Image.Width*4),'arms or other pixels differ between edited and applied pattern');
    SavePNG(Image,TPath.Combine(Root,'after-integrated.png')); SavePNG(Driver.Expected,TPath.Combine(Root,'editor.png'));
    UI.Preview.Seek(1.8125/2); Await(UI.Preview.SceneCache); Image := UI.Preview.SceneCache.ImageForTrack(1);
    for Y := 0 to Image.Height-1 do Check(CompareMem(Image.ScanLine[Y],Driver.ExpectedLater.ScanLine[Y],Image.Width*4),'later arm pose differs');
    SavePNG(Image,TPath.Combine(Root,'after-arms.png'));
    UI.UndoEdit; Check(UI.Document.TrySave(Target,Error),Error); Check(Target=Before,'applied snapshot update undo');
    UI.RedoEdit; Check(UI.Document.TrySave(Target,Error),Error); Check(Target=After,'applied snapshot update redo');
    Bad := Saved; Bad.ConfigJSON := '{"lengthBeats":-1,"notes":[]}'; Rejected := False;
    try UI.Document.RefreshPerformanceSnapshots(Bad); except on E: Exception do Rejected := True; end;
    Check(Rejected,'invalid refresh accepted'); Check(UI.Document.TrySave(Target,Error),Error); Check(Target=After,'invalid refresh partially changed project');
    UI.FormCloseQuery(UI,CanClose); Check(CanClose and (Driver.Applied=After),'host apply did not receive new snapshots');
    Scene.MaximumImageDimension := 0; Scene.Bind(UI.Document,UI.SharedLibrary,nil);
    for Beat in TArray<Double>.Create(0.1875,1.1875,2.1875,3.1875,4.0,16.1875,17.1875,19.1875,21.0) do begin
      Scene.SetPosition(Beat/2); Await(Scene); Image := Scene.ImageForTrack(1);
      Check(Video.Render(Driver.Applied,Beat/2,Image.Width,Image.Height,Pixels,Error),Error);
      for Y := 0 to Image.Height-1 do begin Row := Image.ScanLine[Y]; for X := 0 to Image.Width-1 do
        Check((Pixels[Y*Image.Width+X].R=Row[X*4+2]) and (Pixels[Y*Image.Width+X].G=Row[X*4+1]) and
          (Pixels[Y*Image.Width+X].B=Row[X*4]) and (Pixels[Y*Image.Width+X].A=Row[X*4+3]),'video/integrated time or arms differ'); end;
    end;
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'applied test used audio');
    UI.Hide; Writeln('COMMON_SAVE_PLACED_SNAPSHOTS_EDITOR_INTEGRATED_VIDEO_ARMS_IDS_CLIPS_UNDO_REDO_HOST_APPLY_NO_AUDIO_OK');
  finally Driver.Timer.Free; Driver.ExpectedLater.Free; Driver.Expected.Free; Driver.Free; Video.Free; Scene.Free; Model.Free; UI.Free; Store.Free; end;
end;
end.
