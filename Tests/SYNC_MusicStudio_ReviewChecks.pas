unit SYNC_MusicStudio_ReviewChecks;

// Reviewer regressions use only synthetic PSDs and isolated JSON/library roots.
interface
procedure RunReviewChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON, System.UITypes,
  Winapi.Windows, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_TestHelpers;
type
  TCancelSharedDriver = class
    Timer: TTimer;
    Seen: Boolean;
    procedure Tick(Sender: TObject);
    procedure AppException(Sender: TObject; E: Exception);
  end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('Review regression: '+Text); end;
procedure TCancelSharedDriver.AppException(Sender: TObject; E: Exception);
begin Writeln('VCL_EXCEPTION '+E.ClassName+': '+E.Message); Flush(Output); Halt(1); end;
procedure TCancelSharedDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings;
begin
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]); Timer.Enabled := False;
    Check((D.LayersFrame<>nil) and (D.AudioFrame=nil) and (D.SingingFrame=nil),'shared attribute popup frame');
    Seen := True; D.ModalResult := mrCancel; Exit;
  end;
end;
procedure WaitScene(F: TFormMusicStudioSettings; Track: Integer);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  repeat
    F.Preview.SceneCache.PollResults; Application.ProcessMessages;
    Check((F.Preview.SceneCache.ActiveLoadJobs<=2) and (F.Preview.SceneCache.ActiveRenderJobs<=2),'bounded scene jobs');
    if (F.Preview.SceneCache.ActiveLoadJobs=0) and (F.Preview.SceneCache.ActiveRenderJobs=0) and
      ((Track<0) or (F.Preview.SceneCache.ImageForTrack(Track)<>nil)) then Exit;
    Check(GetTickCount64<Deadline,'scene timeout: '+F.Preview.SceneCache.StatusForTrack(Track)); Sleep(2);
  until False;
end;
procedure CheckPixel(F: TFormMusicStudioSettings; R,G,B,A: Byte; const Message: string);
var Image: TBitmap; Row: PByte;
begin
  Image := F.Preview.SceneCache.ImageForTrack(0); Check(Image<>nil,Message+' missing image'); Row := Image.ScanLine[0];
  Check((Row[0]=B) and (Row[1]=G) and (Row[2]=R) and (Row[3]=A),Message);
end;
procedure SelectName(F: TFormMusicStudioSettings; const Name: string);
var I: Integer;
begin
  for I := 0 to F.PatternList.Count-1 do if F.PatternList.Items[I]=Name then begin
    F.PatternList.ItemIndex := I; F.PatternList.OnClick(F.PatternList); Exit;
  end;
  raise Exception.Create('Expected library item: '+Name);
end;
procedure RunReviewChecks(const Root: string);
var F: TFormMusicStudioSettings; Layers: TMusicStudioLayerDocument; Driver: TCancelSharedDriver;
  Asset,Other,Imported: TMusicStudioPsdAsset; Dup: Boolean; G: TGUID;
  Dir,Source,OtherSource,Hash,OtherHash,Error,Before,After,JSONA,JSONB,Key,Revision: string;
  Track,Second,Generic,I,Count,Loads: Integer; Config: TJSONObject; P: TMusicStudioPattern;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'review-'+GUIDToString(G)); ForceDirectories(Dir);
  Source := TPath.Combine(Dir,'original\character.psd'); OtherSource := TPath.Combine(Dir,'other\character.psd');
  ForceDirectories(ExtractFileDir(Source)); ForceDirectories(ExtractFileDir(OtherSource));
  WriteLayeredTestPSD(Source,40,115,190); WriteLayeredTestPSD(OtherSource,180,75,25);
  Hash := THashSHA2.GetHashStringFromFile(Source); OtherHash := THashSHA2.GetHashStringFromFile(OtherSource);
  F := TFormMusicStudioSettings.Create(nil); Layers := TMusicStudioLayerDocument.Create; Driver := TCancelSharedDriver.Create;
  Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Driver.Timer.Interval := 30;
  Driver.Timer.OnTimer := Driver.Tick; Application.OnException := Driver.AppException;
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Dir,'library'); F.LoadDocument('');
    Check(F.SharedLibrary.TryImport(Source,'same name','#90C4E0',Asset,Dup,Error),Error);
    Check(F.SharedLibrary.TryImport(OtherSource,'same name','#90C4E0',Other,Dup,Error),Error);
    Check(Asset.ID<>Other.ID,'same filename different PSD identity');
    Check(Layers.LoadFile(Asset.FilePath),Layers.LastError); Key := Layers.Layers[0].Key;
    SetLength(Asset.Patterns,1); CreateGUID(G); Asset.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36));
    Asset.Patterns[0].AssetID := Asset.ID; Asset.Patterns[0].Kind := 'emotion';
    Asset.Patterns[0].Name := 'own expression'; Asset.Patterns[0].Color := '#90C4E0';
    Config := ParseMusicStudioPsdConfig('');
    try MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),Key,False);
      Asset.Patterns[0].ConfigJSON := Config.ToJSON;
    finally Config.Free; end;
    Check(F.SharedLibrary.TrySave(Asset,Error),Error);
    SetLength(Other.Patterns,1); Other.Patterns[0] := Asset.Patterns[0]; Other.Patterns[0].AssetID := Other.ID;
    CreateGUID(G); Other.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36)); Other.Patterns[0].Name := 'foreign expression';
    Check(F.SharedLibrary.TrySave(Other,Error),Error);
    Track := F.Document.AddTrack('psd'); F.Document.AssignPsd(Track,Asset.ID);
    Check(F.Document.TrySave(JSONA,Error),Error); F.LoadDocument(JSONA); WaitScene(F,Track);
    CheckPixel(F,40,115,190,255,'initial assigned PSD');
    Revision := Asset.Revision;
    // Re-register the same original, then use the same invalidation path as the + popup.
    Check(F.SharedLibrary.TryImport(Source,'same name','#90C4E0',Imported,Dup,Error),Error);
    Check(Dup and (Imported.ID=Asset.ID),'same original re-register stable ID');
    Imported.Name := 'updated shared name'; Config := ParseMusicStudioPsdConfig(Imported.ConfigJSON);
    try MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),Key,False); Imported.ConfigJSON := Config.ToJSON;
    finally Config.Free; end;
    Check(F.SharedLibrary.TrySave(Imported,Error),Error); Check(Imported.Revision<>Revision,'shared revision changed');
    F.SharedLibraryChanged; WaitScene(F,Track); CheckPixel(F,0,0,0,0,'updated shared visibility invalidates scene');
    Check(F.PatternList.Items.IndexOf('updated shared name')>=0,'shared name list refreshed');
    Check(F.Document.TrySave(After,Error) and (JSONA=After),'shared registration did not mutate project references');
    Asset := Imported; Config := ParseMusicStudioPsdConfig(Asset.ConfigJSON);
    try MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),Key,True); Asset.ConfigJSON := Config.ToJSON;
    finally Config.Free; end;
    Check(F.SharedLibrary.TrySave(Asset,Error),Error); F.SharedLibraryChanged; WaitScene(F,Track);
    CheckPixel(F,40,115,190,255,'shared base restored');
    I := F.Document.AddSinging; P := F.Document.PatternAt(I); P.Name := 'local singing'; F.Document.UpdatePattern(P);
    F.Document.AddAudio; Second := F.Document.AddTrack('psd'); F.Document.AssignPsd(Second,Other.ID);
    Generic := F.Document.AddSlot(Track,'generic');
    Check(F.Document.UpdateSlot(Track,Generic,'mixed','#90C4E0',TArray<string>.Create('singing','emotion'),Error),Error);
    Check(F.Document.TrySave(Before,Error),Error); F.LoadDocument(Before); F.TimelineBox.SelectSlot(Track,Generic);
    Check((F.LibraryKind='generic') and (F.PatternList.Count=2),'mixed accepts list includes singing and assigned-PSD emotion');
    Check((F.AddMenu.Items.Count=2) and (F.AddMenu.Items[0].Caption=MusicStudioSlotKindName('singing')) and
      (F.AddMenu.Items[1].Caption=MusicStudioSlotKindName('emotion')),'mixed accepts menu');
    Check(F.PatternList.Items.IndexOf('foreign expression')<0,'mixed list leaked other PSD');
    Driver.Seen := False; Driver.Timer.Enabled := True; F.AddMenu.Items[1].Click;
    Check(Driver.Seen,'multi-kind shared add popup'); Check(F.Document.TrySave(After,Error) and (Before=After),'cancel shared add changed project');
    SelectName(F,'own expression'); Count := F.Document.PatternCount;
    Check(not F.DropSelectedLibraryAt(Second,TestSlotIndex(F.Document,Second,'emotion'),1,Error),'foreign PSD drop accepted');
    Check((Error<>'') and (Count=F.Document.PatternCount),'foreign drop reason/reference rollback');
    Check(F.Document.TrySave(After,Error) and (Before=After),'foreign drop altered JSON');
    Check(F.DropSelectedLibraryAt(Track,Generic,1,Error),Error);
    F.Preview.Seek(1.5); WaitScene(F,Track); CheckPixel(F,0,0,0,0,'own expression applies');
    F.Document.AssignPsd(Track,Other.ID); F.SharedLibraryChanged; F.Preview.Seek(1.5); WaitScene(F,Track);
    CheckPixel(F,180,75,25,255,'PSD switch rejects old foreign expression');
    Check(Pos('別のPSD',F.Preview.SceneCache.StatusForTrack(Track))>0,'foreign expression status explained');
    F.TimelineBox.SelectSlot(Track,Generic); Check(F.PatternList.Items.IndexOf('own expression')<0,'switch hides foreign expression list');
    Check(F.Document.UpdateSlot(Track,Generic,'single','#90C4E0',TArray<string>.Create('emotion'),Error),Error);
    F.SharedLibraryChanged; F.TimelineBox.SelectSlot(Track,Generic);
    Check((F.LibraryKind='emotion') and (F.AddMenu.Items.Count=1),'single accept direct context');
    Driver.Seen := False; Driver.Timer.Enabled := True; F.AddButton.Click; Check(Driver.Seen,'single shared direct add popup');
    I := F.Document.AddSlot(Track,'singing');
    Check(F.Document.UpdateSlot(Track,I,'mixed singing usage','#90C4E0',TArray<string>.Create('singing','emotion'),Error),Error);
    F.SharedLibraryChanged; F.TimelineBox.SelectSlot(Track,I);
    Check((F.LibraryKind='generic') and (F.PatternList.Count=2) and (F.AddMenu.Items.Count=2),'slot usage name did not override accepts');
    I := F.Document.AddSlot(Track,'rhythm'); F.SharedLibraryChanged; F.TimelineBox.SelectSlot(Track,I);
    Check(not F.AddButton.Enabled and (F.PatternList.Count=0) and (F.AddMenu.Items.Count=1) and
      not F.AddMenu.Items[0].Enabled,'unimplemented rhythm exposed as implemented');
    Check(F.Document.TrySave(JSONB,Error),Error);
    for I := 1 to 30 do begin
      case I mod 3 of 0: F.LoadDocument(JSONB); 1: F.LoadDocument(JSONA); else F.LoadDocument(''); end;
      Check((F.Preview.SceneCache.ActiveLoadJobs<=2) and (F.Preview.SceneCache.ActiveRenderJobs<=2),'switch concurrency');
      Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'switch invoked audio');
      Application.ProcessMessages;
    end;
    F.LoadDocument(JSONB); F.Preview.Seek(1.5); WaitScene(F,Track); CheckPixel(F,180,75,25,255,'last JSON generation wins');
    Loads := F.Preview.SceneCache.LoadCount;
    for I := 1 to 100 do begin F.TimelineBox.Repaint; F.Preview.Stage.Repaint; end;
    Check(Loads=F.Preview.SceneCache.LoadCount,'paint reparsed shared PSD');
    Check(THashSHA2.GetHashStringFromFile(Source)=Hash,'original PSD changed');
    Check(THashSHA2.GetHashStringFromFile(OtherSource)=OtherHash,'other original PSD changed');
    Writeln('REVIEW_SHARED_REREGISTER_REVISION_SCENE_AND_LIST_REFRESH_OK');
    Writeln('REVIEW_ACCEPTS_MULTI_SINGLE_SHARED_POPUP_CANCEL_FOREIGN_PSD_DROP_UNSUPPORTED_OK');
    Writeln('REVIEW_PSD_SWITCH_FOREIGN_EXPRESSION_JSON30_GENERATION_PAINT100_NO_AUDIO_OK');
  finally Application.OnException := nil; Driver.Timer.Free; Driver.Free; Layers.Free; F.Free; end;
end;
end.
