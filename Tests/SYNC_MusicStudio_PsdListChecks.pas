unit SYNC_MusicStudio_PsdListChecks;

// Explorerと同じHDROP通知で外部登録、一覧削除/復帰、既存作品参照を隔離検証する。
interface
procedure RunPsdListChecks(const Root: string; const ActualPSD: string = '');
procedure RunAudioLibraryChecks(const Root,ExistingWav: string);
implementation
uses System.SysUtils, System.Classes, System.UITypes, System.IOUtils, System.Hash, System.Types,
  Winapi.Windows, Winapi.Messages, Winapi.ShlObj, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls,
  SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_FileDropList,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_PerformerEditor, SYNC_MusicStudio_PerformerPsd,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd;
type TDropAccess = class(TMusicStudioFileDropList)
  procedure Rebuild;
end;
procedure TDropAccess.Rebuild;
begin RecreateWnd; end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('PSD_LIST: '+Message); end;
procedure Fixture(const Path: string; Color: Byte);
var D: TArtDocument; Row,Action,L: TArtLayer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 2; D.Height := 2;
    L := D.AddLayer(alkGroup,'演奏属性:ドラム',TArtBounds.Create(0,0,0,0)); L.Visible := False;
    Row := D.AddLayer(alkGroup,'右手',TArtBounds.Create(0,0,0,0));
    Action := D.AddLayer(alkGroup,'*打撃',TArtBounds.Create(0,0,0,0),Row);
    L := D.AddLayer(alkImage,'*0',TArtBounds.Create(0,0,1,1),Action);
    L.Pixels := TBytes.Create(Color,80,90,255); WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
procedure Drop(UI: TFormMusicStudioSettings; const Paths: TArray<string>);
var Text,Path: string; H: HGLOBAL; P: Pointer; Header: TDropFiles;
begin
  Text := ''; for Path in Paths do Text := Text+Path+#0; Text := Text+#0;
  H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT,SizeOf(Header)+Length(Text)*SizeOf(Char));
  Check(H<>0,'HDROP allocation'); P := GlobalLock(H);
  try
    Header := Default(TDropFiles); Header.pFiles := SizeOf(Header); Header.fWide := True;
    Move(Header,P^,SizeOf(Header)); Move(PChar(Text)^,PByte(P)[SizeOf(Header)],Length(Text)*SizeOf(Char));
  finally GlobalUnlock(H); end;
  // 通知を受けたリストがDragFinishで所有HDROPを解放する。
  SendMessage(UI.PatternList.Handle,WM_DROPFILES,H,0);
end;
procedure RunPsdListChecks(const Root,ActualPSD: string);
var UI: TFormMusicStudioSettings; A,Current,Stale: TMusicStudioPsdAsset;
  Profile: TMusicStudioPerformerProfile; P: TMusicStudioPattern;
  PathA,PathB,Bad,Wrong,Error,Text,Before,Hash,RealHash: string;
  T,Music,Count: Integer; Duplicate: Boolean;
  function JSON: string;
  begin Check(UI.Document.TrySave(Result,Error),Error); end;
  procedure SelectAsset(const ID: string);
  var I: Integer;
  begin
    UI.TimelineBox.SelectSlot(T,0);
    Check(UI.SharedLibrary.TryRead(ID,Current,Error),Error);
    for I := 0 to UI.PatternList.Count-1 do begin
      UI.PatternList.ItemIndex := I;
      // 一覧の名前を取得済み正本と比較する。テストfixtureは同名にしない。
      if UI.PatternList.Items[I]=Current.Name then begin UI.PatternList.OnClick(UI.PatternList); Exit; end;
    end;
    raise Exception.Create('PSD_LIST: selected PSD absent');
  end;
begin
  ForceDirectories(Root); PathA := TPath.Combine(Root,'東北きりたん 試験 A.PSD');
  PathB := TPath.Combine(Root,'東北きりたん 試験 B.psd'); Bad := TPath.Combine(Root,'破損.psd');
  Wrong := TPath.Combine(Root,'対象外.txt'); Fixture(PathA,60); Fixture(PathB,160);
  TFile.WriteAllText(Bad,'not a PSD'); TFile.WriteAllText(Wrong,'text'); Hash := THashSHA2.GetHashStringFromFile(PathA);
  UI := TFormMusicStudioSettings.Create(nil);
  try
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    T := UI.Document.AddTrack('performer'); Music := UI.Document.AddTrack('audio'); Text := JSON; UI.LoadDocument(Text);
    UI.TimelineBox.SelectSlot(T,0); UI.Show; ShowWindow(UI.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
    Check((GetWindowLongPtr(UI.PatternList.Handle,GWL_EXSTYLE) and WS_EX_ACCEPTFILES)<>0,'file drop not enabled');
    Before := JSON; Drop(UI,TArray<string>.Create(PathA,PathB,Bad,Wrong));
    Check(Length(UI.SharedLibrary.Assets)=2,'batch accepted invalid or lost valid PSD');
    Check(UI.PatternList.Count=2,'registered PSD list absent'); Check(JSON=Before,'registration changed project');
    Check(Pos('一部を登録できません',UI.StatusLabel.Caption)>0,'partial errors not reported');
    A := UI.SharedLibrary.Assets[0]; SelectAsset(A.ID); Check(UI.DeleteButton.Enabled,'shared PSD delete remains disabled');
    Check(UI.DropSelectedLibraryAt(T,-1,0,Error),Error);
    P := Default(TMusicStudioPattern); P.Kind := 'psd'; P.AssetID := A.ID; P.Name := A.Name; P.Color := A.Color;
    UI.Document.AddReference(P); Text := JSON; UI.LoadDocument(Text); SelectAsset(A.ID);
    Before := JSON; Stale := A; A.Name := '名前設定を保持'; Check(UI.SharedLibrary.TrySave(A,Error),Error);
    Check(not UI.RemoveSelectedLibraryPsd(Error),'stale visible row deleted newer settings');
    Check(not UI.SharedLibrary.TryImport(PathA,'ignored','#90C0E0',Current,Duplicate,Error,Stale.Revision),'stale reimport accepted');
    SelectAsset(A.ID); Check(UI.RemoveSelectedLibraryPsd(Error),Error);
    Check(UI.PatternList.Count=1,'deleted PSD returned as local missing reference'); Check(JSON=Before,'list deletion changed project');
    Check(UI.Document.TrackAt(T).PsdAssetID=A.ID,'deletion lost assigned asset');
    Check(UI.SharedLibrary.TryRead(A.ID,Current,Error) and Current.HiddenFromLibrary,'hidden asset cannot be resolved');
    Check(TFile.Exists(Current.FilePath),'deletion removed managed PSD');
    Check(ReadMusicStudioPerformer(UI.SharedLibrary,A.ID,Profile,Error) and (Length(Profile.Slots)=1),Error);
    Check(not UI.SharedLibrary.TrySave(A,Error),'stale editor overwrote deletion');
    TDropAccess(UI.PatternList).Rebuild;
    Check((GetWindowLongPtr(UI.PatternList.Handle,GWL_EXSTYLE) and WS_EX_ACCEPTFILES)<>0,'recreated list lost file drop');
    // 削除した同じ内容を再登録。元のID/設定を保持して一覧だけ復帰する。
    Check(UI.SharedLibrary.TryRead(Stale.ID,Current,Error),Error);
    Drop(UI,TArray<string>.Create(Current.OriginalPath)); Check(UI.PatternList.Count=2,'reimport did not restore hidden PSD');
    Check(UI.SharedLibrary.TryRead(Stale.ID,Current,Error) and not Current.HiddenFromLibrary,'reimport changed ID/hidden flag');
    Check(Current.Name='名前設定を保持','reimport lost metadata');
    Count := Length(UI.SharedLibrary.Assets); Drop(UI,TArray<string>.Create(Current.OriginalPath));
    Check(Length(UI.SharedLibrary.Assets)=Count,'duplicate created extra asset');
    UI.TimelineBox.SelectSlot(Music,0); Drop(UI,TArray<string>.Create(PathA));
    Check(Pos('WAV / MP3',UI.StatusLabel.Caption)>0,'audio list did not reject PSD');
    Check(Length(UI.SharedLibrary.Assets)=Count,'wrong list mode wrote library');
    if ActualPSD<>'' then begin
      UI.TimelineBox.SelectSlot(T,0); RealHash := THashSHA2.GetHashStringFromFile(ActualPSD);
      Drop(UI,TArray<string>.Create(ActualPSD)); Check(Length(UI.SharedLibrary.Assets)=Count+1,'real PSD did not register');
      Check(UI.DropSelectedLibraryAt(T,-1,0,Error),Error);
      Check((Length(UI.Document.TrackAt(T).Slots)>1) and (UI.Document.TrackAt(T).Slots[1].Kind='performance'),'real drum capability absent');
      Check(RealHash=THashSHA2.GetHashStringFromFile(ActualPSD),'real PSD source changed');
    end;
    Check(Hash=THashSHA2.GetHashStringFromFile(PathA),'source changed');
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'audio used by PSD list checks');
    TFile.WriteAllText(TPath.Combine(Root,'psd-list-project.json'),JSON);
    Writeln('PSD_LIST_EXTERNAL_HDROP_BATCH_RECREATE_DELETE_REFERENCE_RESTORE_REVISION_NO_AUDIO_OK');
  finally UI.Free; end;
end;
type TAudioDialogDriver = class
  Timer: TTimer;
  Path: string;
  Done,NoDecode: Boolean;
  procedure Tick(Sender: TObject);
end;
procedure TAudioDialogDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings;
begin
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]);
    if D.AudioFrame=nil then Continue;
    NoDecode := D.AudioFrame.NoDecode; D.AudioFrame.SelectFile(Path);
    NoDecode := NoDecode and not D.AudioFrame.IsLoading;
    Done := True; Timer.Enabled := False; D.ModalResult := mrOK; Exit;
  end;
end;
procedure RunAudioLibraryChecks(const Root,ExistingWav: string);
var UI: TFormMusicStudioSettings; Driver: TAudioDialogDriver; P: TMusicStudioPattern;
  Music,Actor,Index: Integer; Error,Text,Before,Hash: string;
  function JSON: string;
  begin Check(UI.Document.TrySave(Result,Error),Error); end;
  procedure AudioOnly;
  var N: Integer; C: TComponent;
  begin
    Check(UI.LibraryKind='audio','track header did not show audio library');
    Check(UI.AddButton.Enabled,'audio add unavailable');
    for N := 0 to UI.PatternList.Count-1 do begin
      UI.PatternList.ItemIndex := N;
      Check(UI.Document.PatternAt(UI.SelectedLibraryPattern).Kind='audio','non-audio item in list');
    end;
    for C in UI do if C is TButton then
      if (TButton(C).Caption='PSD') or (TButton(C).Caption='演奏') or (TButton(C).Caption='歌唱') then
        Check(not TButton(C).Enabled,'performer tab enabled on audio track');
  end;
begin
  Check(TFile.Exists(ExistingWav) and SameText(ExtractFileExt(ExistingWav),'.wav'),'pass an existing WAV; no fixture is generated');
  Hash := THashSHA2.GetHashStringFromFile(ExistingWav); ForceDirectories(Root);
  UI := TFormMusicStudioSettings.Create(nil); Driver := TAudioDialogDriver.Create;
  try
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Music := UI.Document.AddTrack('audio'); Actor := UI.Document.AddTrack('performer');
    UI.Document.AddSinging; Text := JSON; UI.LoadDocument(Text); UI.Show; Application.ProcessMessages;
    UI.TimelineBox.SelectTrack(Music); AudioOnly; Check(UI.PatternList.Count=0,'unrelated patterns shown');
    UI.TimelineBox.SelectTrack(Actor); Check(UI.LibraryKind='psd','performer context');
    UI.TimelineBox.SelectTrack(Music); AudioOnly;
    Before := JSON; Drop(UI,TArray<string>.Create(ExistingWav)); AudioOnly;
    Check(UI.PatternList.Count=1,'WAV HDROP not registered'); P := UI.Document.PatternAt(UI.SelectedLibraryPattern);
    Check(SameFileName(P.FilePath,ExistingWav),'WAV path not retained');
    Check(P.Name=ChangeFileExt(ExtractFileName(ExistingWav),''),'WAV name');
    UI.UndoEdit; Check(JSON=Before,'audio import undo'); UI.RedoEdit; AudioOnly;
    Index := UI.SelectedLibraryPattern; if Index<0 then begin UI.PatternList.ItemIndex := 0; Index := UI.SelectedLibraryPattern; end;
    Check(UI.DropSelectedLibraryAt(Music,0,0,Error),Error); Check(Length(UI.Document.TrackAt(Music).Slots[0].Clips)=1,'timeline placement');
    UI.TimelineBox.SelectTrack(Music); AudioOnly; UI.PatternList.ItemIndex := 0; UI.PatternList.OnClick(UI.PatternList);
    Driver.Path := TPath.Combine(Root,'missing-reference.mp3'); Driver.Timer := TTimer.Create(nil);
    Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick; Driver.Timer.Enabled := True;
    UI.PatternList.OnDblClick(UI.PatternList);
    Check(Driver.Done and Driver.NoDecode,'doubleclick audio settings / decode guard');
    P := UI.Document.PatternAt(Index); Check(P.FilePath=Driver.Path,'settings file reference');
    UI.UndoEdit; Check(SameFileName(UI.Document.PatternAt(Index).FilePath,ExistingWav),'settings undo');
    UI.TimelineBox.SelectTrack(Music); Before := JSON;
    Drop(UI,TArray<string>.Create(TPath.Combine(Root,'missing.mp3'),ParamStr(0)));
    Check(JSON=Before,'invalid audio drop changed project');
    Check(Pos('一部を登録できません',UI.StatusLabel.Caption)>0,'invalid drop not explained');
    UI.TimelineBox.SelectSlot(Music,0); AudioOnly; TDropAccess(UI.PatternList).Rebuild;
    UI.TimelineBox.SelectTrack(Actor); UI.TimelineBox.SelectTrack(Music); AudioOnly;
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'audio engine used');
    Check(THashSHA2.GetHashStringFromFile(ExistingWav)=Hash,'existing WAV changed');
    Writeln('AUDIO_LIBRARY_TRACK_SLOT_SWITCH_WAV_DROP_SETTINGS_REFERENCE_UNDO_NO_DECODE_OK');
  finally Driver.Timer.Free; Driver.Free; UI.Free; end;
end;
end.
