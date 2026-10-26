unit SYNC_MusicStudio_PsdStorageChecks;
// 全素材/子プロセス/出力をテストRootへ隔離。PSD本体とJSONの原子性を別に検証する。
interface
procedure RunPsdStorageChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON,
  Winapi.Windows, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_TestHelpers;
type
  TCopyFault = (cfNone,cfInterrupted,cfShort,cfCorrupt,cfPublishBlocked,cfMetadataBlocked);
  TFaultLibrary = class(TMusicStudioSharedPsdLibrary)
  public
    Fault: TCopyFault;
    LastTarget: string;
    SawUnpublishedStage: Boolean;
  protected
    procedure CopyPsdData(Source,Target: TStream); override;
  end;
procedure Check(B: Boolean; const M: string);
begin if not B then raise Exception.Create(M); end;
function Hash(const Path: string): string;
begin Result := THashSHA2.GetHashStringFromFile(Path); end;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := LowerCase(Copy(GUIDToString(G),2,36)); end;
procedure TFaultLibrary.CopyPsdData(Source,Target: TStream);
var Dir,Path: string; Data: array[0..255] of Byte; B: Byte; Keep: TFileStream;
begin
  LastTarget := '';
  for Dir in TDirectory.GetDirectories(Root) do
    for Path in TDirectory.GetFiles(Dir,'source.psd.*.tmp') do
      LastTarget := TPath.Combine(Dir,'source.psd');
  Check(LastTarget<>'','staging file not found');
  SawUnpublishedStage := not TFile.Exists(LastTarget);
  Check(SawUnpublishedStage,'canonical PSD visible before validation');
  case Fault of
    cfInterrupted,cfShort: begin
      Source.ReadBuffer(Data,SizeOf(Data)); Target.WriteBuffer(Data,SizeOf(Data));
      if Fault=cfInterrupted then raise EWriteError.Create('Injected interrupted PSD copy');
    end;
  else
    inherited;
    if Fault=cfCorrupt then begin
      Target.Position := Target.Size-1; Target.ReadBuffer(B,1); B := B xor $FF;
      Target.Position := Target.Size-1; Target.WriteBuffer(B,1);
    end else if Fault=cfPublishBlocked then begin
      // 別の書込者が先に正しい本体を公開した状況。既存ファイルを置換/削除しない。
      Keep := TFileStream.Create(LastTarget,fmCreate);
      try Source.Position := 0; Keep.CopyFrom(Source,0); finally Keep.Free; end;
    end else if Fault=cfMetadataBlocked then
      ForceDirectories(TPath.Combine(ExtractFileDir(LastTarget),'asset.json'));
  end;
end;
procedure CheckNoStages(const LibraryRoot: string);
var Dir: string;
begin
  for Dir in TDirectory.GetDirectories(LibraryRoot) do
    Check(Length(TDirectory.GetFiles(Dir,'*.tmp'))=0,'handled failure left staged file');
end;
procedure CheckFaults(const Dir,Source,OriginalHash: string);
var Fault: TCopyFault; L: TFaultLibrary; A,B: TMusicStudioPsdAsset;
  Error,Metadata,BeforeMetadata,Revision,ID,Refs: string; Dup: Boolean;
begin
  for Fault := cfInterrupted to cfMetadataBlocked do begin
    L := TFaultLibrary.Create(TPath.Combine(Dir,'register-'+IntToStr(Ord(Fault))));
    try
      L.Fault := Fault;
      Check(not L.TryImport(Source,'登録失敗fixture','#77AAEE',A,Dup,Error),'fault registration succeeded');
      Check(Error<>'','registration failure not explained');
      Check(L.SawUnpublishedStage,'registration skipped staging');
      Check(Length(L.Assets)=0,'failed registration became a managed asset');
      CheckNoStages(L.Root);
      if Fault=cfPublishBlocked then Check(Hash(L.LastTarget)=OriginalHash,'publish failure changed another writer PSD')
      else Check(not TFile.Exists(L.LastTarget),'failed registration left canonical PSD');
    finally L.Free; end;
  end;
  for Fault := cfInterrupted to cfPublishBlocked do begin
    L := TFaultLibrary.Create(TPath.Combine(Dir,'restore-'+IntToStr(Ord(Fault))));
    try
      Check(L.TryImport(Source,'復旧fixture','#77AAEE',A,Dup,Error),Error);
      ID := A.ID; Revision := A.Revision; Metadata := TPath.Combine(ExtractFileDir(A.FilePath),'asset.json');
      BeforeMetadata := Hash(Metadata); Refs := '{"assetId":"'+ID+'","filePath":"'+StringReplace(A.FilePath,'\','\\',[rfReplaceAll])+'"}';
      TFile.Delete(A.FilePath); L.Fault := Fault;
      Check(not L.TryRelocate(ID,Source,Error),'fault relocation succeeded');
      Check(Hash(Metadata)=BeforeMetadata,'failed restore changed metadata');
      Check(L.TryRead(ID,B,Error) and (B.Revision=Revision) and (B.ID=ID),'failed restore changed ID/revision');
      CheckNoStages(L.Root);
      if Fault=cfPublishBlocked then begin
        Check(not B.Missing and (Hash(A.FilePath)=OriginalHash),'failed publish lost existing correct PSD');
        Check(not L.TryRelocate(ID,Source,Error),'existing managed copy was overwritten');
        Check(Hash(A.FilePath)=OriginalHash,'second restore changed existing PSD');
        TFile.Delete(A.FilePath);
      end else Check(B.Missing and not TFile.Exists(A.FilePath),'partial restore became valid canonical PSD');
      // 重複登録からの欠損復旧も同じ原子的経路を通る。
      Check(not L.TryImport(Source,'別名','#77AAEE',B,Dup,Error),'fault duplicate restoration succeeded');
      Check(Hash(Metadata)=BeforeMetadata,'duplicate recovery changed metadata'); CheckNoStages(L.Root);
      if Fault=cfPublishBlocked then begin
        Check(Hash(A.FilePath)=OriginalHash,'duplicate publish failure lost existing PSD'); TFile.Delete(A.FilePath);
      end else Check(not TFile.Exists(A.FilePath),'duplicate restore exposed partial PSD');
      L.Fault := cfNone; Check(L.TryRelocate(ID,Source,Error),Error);
      Check(L.TryRead(ID,B,Error) and not B.Missing and (B.Revision=Revision) and (B.ID=ID),'retry lost identity');
      Check((Hash(A.FilePath)=OriginalHash) and (Hash(Metadata)=BeforeMetadata),'retry content/metadata mismatch');
      Check(Refs='{"assetId":"'+B.ID+'","filePath":"'+StringReplace(B.FilePath,'\','\\',[rfReplaceAll])+'"}','project reference changed');
      CheckNoStages(L.Root);
    finally L.Free; end;
  end;
  Check(Hash(Source)=OriginalHash,'fault checks changed original PSD');
  Writeln('PSD_BODY_STAGED_SIZE_HASH_PUBLISH_FAILURE_AND_RETRY_OK');
end;
function LaunchWorker(const Mode,Root,ID,ReadyPath,ResultPath,EventName,Value: string): TProcessInformation;
var Startup: TStartupInfo; Cmd,Exe: string;
begin
  Exe := TPath.Combine(ExtractFileDir(ParamStr(0)),'SYNC_MusicStudio_SharedLibraryWorker.exe');
  Check(TFile.Exists(Exe),'shared-library worker not compiled');
  // 各引数は内部生成の隔離パス/固定モード/名前のみ。シェルを介さない。
  Cmd := '"'+Exe+'" "'+Mode+'" "'+Root+'" "'+ID+'" "'+ReadyPath+'" "'+ResultPath+'" "'+EventName+'" "'+Value+'"';
  Startup := Default(TStartupInfo); Startup.cb := SizeOf(Startup); Result := Default(TProcessInformation);
  UniqueString(Cmd);
  if not CreateProcess(nil,PChar(Cmd),nil,nil,False,CREATE_NO_WINDOW,nil,nil,Startup,Result) then RaiseLastOSError;
  CloseHandle(Result.hThread); Result.hThread := 0;
end;
procedure CloseWorker(var P: TProcessInformation);
begin
  if P.hProcess=0 then Exit;
  if WaitForSingleObject(P.hProcess,0)=WAIT_TIMEOUT then begin
    TerminateProcess(P.hProcess,99); WaitForSingleObject(P.hProcess,5000);
  end;
  CloseHandle(P.hProcess); P.hProcess := 0;
end;
procedure WaitReady(const Path: string; const P: TProcessInformation);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  while not TFile.Exists(Path) do begin
    Check(WaitForSingleObject(P.hProcess,0)=WAIT_TIMEOUT,'worker exited before barrier');
    Check(GetTickCount64<Deadline,'worker readiness timed out'); Sleep(5);
  end;
end;
procedure WaitFinished(const P: TProcessInformation);
var Code: Cardinal;
begin
  Check(WaitForSingleObject(P.hProcess,10000)=WAIT_OBJECT_0,'worker completion timed out');
  Check(GetExitCodeProcess(P.hProcess,Code) and (Code=0),'worker failed');
end;
procedure CheckConcurrentSaves(const Dir,Source,OriginalHash: string);
var L: TMusicStudioSharedPsdLibrary; A,B,Stale: TMusicStudioPsdAsset;
  Dup,Saved1,Saved2: Boolean; Error,ID,Revision,Metadata,EventName,R1,R2,F1,F2,Winner,BeforeHash: string;
  Event: THandle; P1,P2: TProcessInformation; O1,O2,Meta: TJSONObject; I: Integer;
begin
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'concurrent'));
  try
    Check(L.TryImport(Source,'競合fixture','#77AAEE',A,Dup,Error),Error);
    A.ConfigJSON := '{"version":1,"visibility":{},"futureFixture":"preserved"}'; Check(L.TrySave(A,Error),Error);
    ID := A.ID; Revision := A.Revision; Metadata := TPath.Combine(ExtractFileDir(A.FilePath),'asset.json');
    for I := 1 to 3 do begin
      Check(L.TryRead(ID,A,Error),Error); Revision := A.Revision; Stale := A;
      EventName := 'Local\SYNC_MusicStudio_Test_'+NewID;
      Event := CreateEvent(nil,True,False,PChar(EventName)); if Event=0 then RaiseLastOSError;
      P1 := Default(TProcessInformation); P2 := P1; O1 := nil; O2 := nil;
      R1 := TPath.Combine(Dir,'ready1-'+IntToStr(I)); R2 := TPath.Combine(Dir,'ready2-'+IntToStr(I));
      F1 := TPath.Combine(Dir,'result1-'+IntToStr(I)+'.json'); F2 := TPath.Combine(Dir,'result2-'+IntToStr(I)+'.json');
      try
        P1 := LaunchWorker('save',L.Root,A.ID,R1,F1,EventName,'writer-A-'+IntToStr(I));
        // 大小文字/末尾区切り表記を変えても同じ実体で排他する。
        P2 := LaunchWorker('save',UpperCase(L.Root)+'\',A.ID,R2,F2,EventName,'writer-B-'+IntToStr(I));
        WaitReady(R1,P1); WaitReady(R2,P2);
        Check((TFile.ReadAllText(R1,TEncoding.UTF8)=Revision) and (TFile.ReadAllText(R2,TEncoding.UTF8)=Revision),'writers did not capture same revision');
        Check(SetEvent(Event),'cannot release barrier'); WaitFinished(P1); WaitFinished(P2);
        O1 := TJSONObject.ParseJSONValue(TFile.ReadAllText(F1,TEncoding.UTF8)) as TJSONObject;
        O2 := TJSONObject.ParseJSONValue(TFile.ReadAllText(F2,TEncoding.UTF8)) as TJSONObject;
        Check((O1<>nil) and (O2<>nil),'worker result invalid');
        Saved1 := O1.GetValue('saved').Value='true'; Saved2 := O2.GetValue('saved').Value='true';
        Check(Saved1 xor Saved2,'concurrent writers both succeeded or both failed');
        if Saved1 then begin Meta := O2; Winner := O1.GetValue('name').Value; end
        else begin Meta := O1; Winner := O2.GetValue('name').Value; end;
        Check(Pos('他の画面',Meta.GetValue('error').Value)>0,'loser did not report optimistic conflict');
        Check(Meta.GetValue('after').Value=Revision,'failed writer advanced revision');
        Check(L.TryRead(A.ID,B,Error),Error);
        Check((B.Name=Winner) and (B.Revision<>Revision),'saved winner/revision missing');
        Check(B.ConfigJSON=A.ConfigJSON,'concurrent save lost config extension');
        BeforeHash := Hash(Metadata); Stale.Name := 'stale retry';
        Check(not L.TrySave(Stale,Error) and (Hash(Metadata)=BeforeHash),'stale retry overwrote winner');
        Check(Hash(B.FilePath)=OriginalHash,'concurrent save changed PSD body'); CheckNoStages(L.Root);
        Writeln('SHARED_LIBRARY_TWO_PROCESS_REVISION_CONFLICT_OK iteration=',I,' winner=',Winner);
      finally O1.Free; O2.Free; CloseWorker(P1); CloseWorker(P2); CloseHandle(Event); end;
    end;
  finally L.Free; end;
end;
procedure CheckProcessInterruption(const Dir,Source,OriginalHash: string);
var L: TMusicStudioSharedPsdLibrary; A,B: TMusicStudioPsdAsset; Dup: Boolean;
  Error,Metadata,BeforeHash,Ready,EventName,Stage,Revision: string; Event: THandle; P: TProcessInformation;
  Files: TArray<string>;
begin
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'process-interruption'));
  try
    Check(L.TryImport(Source,'中断fixture','#77AAEE',A,Dup,Error),Error);
    Metadata := TPath.Combine(ExtractFileDir(A.FilePath),'asset.json'); BeforeHash := Hash(Metadata); Revision := A.Revision;
    TFile.Delete(A.FilePath); Ready := TPath.Combine(Dir,'crash-ready'); EventName := 'Local\SYNC_MusicStudio_Test_'+NewID;
    Event := CreateEvent(nil,True,False,PChar(EventName)); if Event=0 then RaiseLastOSError;
    P := Default(TProcessInformation);
    try
      P := LaunchWorker('copy-crash',L.Root,A.ID,Ready,TPath.Combine(Dir,'unused-result'),EventName,Source);
      WaitReady(Ready,P); Check(not TFile.Exists(A.FilePath),'running partial copy published');
      Check(TerminateProcess(P.hProcess,99),'cannot interrupt owned fixture worker');
      Check(WaitForSingleObject(P.hProcess,5000)=WAIT_OBJECT_0,'interrupted worker remained alive');
      Files := TDirectory.GetFiles(ExtractFileDir(A.FilePath),'source.psd.*.tmp');
      Check(Length(Files)=1,'interrupted copy did not leave isolated staging evidence'); Stage := Files[0];
      Check(TFile.GetSize(Stage)=256,'unexpected partial stage size');
      Check(L.TryRead(A.ID,B,Error) and B.Missing and (B.Revision=Revision),'partial stage recognized as correct PSD');
      Check(Hash(Metadata)=BeforeHash,'process interruption changed metadata');
      Check(L.TryRelocate(A.ID,Source,Error),Error); // OS releases abandoned write lock.
      Check(L.TryRead(A.ID,B,Error) and not B.Missing and (B.Revision=Revision),'recovery after process failure lost identity');
      Check((Hash(A.FilePath)=OriginalHash) and (Hash(Metadata)=BeforeHash),'process retry changed metadata/body');
      Check(TFile.Exists(Stage),'recovery touched another operation staging file');
      TFile.Delete(Stage); CheckNoStages(L.Root);
      Writeln('PSD_COPY_PROCESS_INTERRUPTION_PARTIAL_STAGE_IGNORED_LOCK_RELEASE_RETRY_OK');
    finally CloseWorker(P); CloseHandle(Event); end;
  finally L.Free; end;
end;
procedure CheckOrphanRegistration(const Dir,Source,OriginalHash: string);
var L: TMusicStudioSharedPsdLibrary; A: TMusicStudioPsdAsset; Dup: Boolean;
  OrphanID,OrphanPath,Error: string;
begin
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'orphan-registration'));
  try
    // 本体の公開直後・metadataの確定前に終了した状態を隔離fixtureで再現する。
    OrphanID := NewID; OrphanPath := TPath.Combine(TPath.Combine(L.Root,OrphanID),'source.psd');
    ForceDirectories(ExtractFileDir(OrphanPath)); TFile.Copy(Source,OrphanPath,False);
    Check((Length(L.Assets)=0) and (L.LastWarning<>''),'metadata-less PSD was accepted as registered');
    Check(not L.TryRead(OrphanID,A,Error),'orphan registration read succeeded');
    Check(L.TryImport(Source,'再登録fixture','#77AAEE',A,Dup,Error),Error);
    Check(not Dup and (A.ID<>OrphanID) and (Length(L.Assets)=1),'orphan prevented fresh valid registration');
    Check((Hash(OrphanPath)=OriginalHash) and (Hash(A.FilePath)=OriginalHash),'orphan retry changed PSD content');
    Writeln('PSD_PUBLISHED_WITHOUT_METADATA_ORPHAN_NOT_REGISTERED_RETRY_OK');
  finally L.Free; end;
end;
procedure CheckInterruptedRegistration(const Dir,Source,OriginalHash: string);
var L: TMusicStudioSharedPsdLibrary; A: TMusicStudioPsdAsset; Dup: Boolean;
  Error,Ready,EventName,Stage,OrphanDir: string; Event: THandle; P: TProcessInformation;
  Dirs,Files: TArray<string>;
begin
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'interrupted-registration'));
  try
    Ready := TPath.Combine(Dir,'import-crash-ready'); EventName := 'Local\SYNC_MusicStudio_Test_'+NewID;
    Event := CreateEvent(nil,True,False,PChar(EventName)); if Event=0 then RaiseLastOSError;
    P := Default(TProcessInformation);
    try
      P := LaunchWorker('import-crash',L.Root,'unused',Ready,TPath.Combine(Dir,'unused-import-result'),EventName,Source);
      WaitReady(Ready,P); Dirs := TDirectory.GetDirectories(L.Root);
      Check(Length(Dirs)=1,'interrupted registration directory count'); OrphanDir := Dirs[0];
      Check(not TFile.Exists(TPath.Combine(OrphanDir,'source.psd')),'partial registration published canonical PSD');
      Check(TerminateProcess(P.hProcess,99),'cannot interrupt owned import worker');
      Check(WaitForSingleObject(P.hProcess,5000)=WAIT_OBJECT_0,'interrupted import worker remained alive');
      Files := TDirectory.GetFiles(OrphanDir,'source.psd.*.tmp');
      Check(Length(Files)=1,'interrupted import staging count'); Stage := Files[0];
      Check((TFile.GetSize(Stage)=256) and (Length(L.Assets)=0),'interrupted import became managed asset');
      Check(L.TryImport(Source,'登録再試行fixture','#77AAEE',A,Dup,Error),Error);
      Check(not Dup and not A.Missing and (Length(L.Assets)=1) and (Hash(A.FilePath)=OriginalHash),'import retry did not create correct asset');
      Check(TFile.Exists(Stage),'import retry touched another operation stage');
      TFile.Delete(Stage); TDirectory.Delete(OrphanDir,False); CheckNoStages(L.Root);
      Writeln('PSD_REGISTRATION_PROCESS_INTERRUPTION_PARTIAL_STAGE_IGNORED_RETRY_OK');
    finally CloseWorker(P); CloseHandle(Event); end;
  finally L.Free; end;
end;
procedure RunPsdStorageChecks(const Root: string);
var Dir,Source,OriginalHash: string;
begin
  Dir := TPath.Combine(Root,'psd-storage-'+NewID); ForceDirectories(Dir);
  Source := TPath.Combine(Dir,'original.psd'); WriteLayeredTestPSD(Source); OriginalHash := Hash(Source);
  CheckFaults(Dir,Source,OriginalHash);
  CheckConcurrentSaves(Dir,Source,OriginalHash);
  CheckProcessInterruption(Dir,Source,OriginalHash);
  CheckInterruptedRegistration(Dir,Source,OriginalHash);
  CheckOrphanRegistration(Dir,Source,OriginalHash);
  Check(Hash(Source)=OriginalHash,'storage suite changed original fixture');
  TFile.WriteAllText(TPath.Combine(Dir,'passed.json'),'{"passed":true,"audioRun":false,"originalSHA256":"'+OriginalHash+'"}',TEncoding.UTF8);
end;
end.
