unit SYNC_MusicStudio_SharedLibraryChecks;
// 隔離ライブラリのコピー、同名/同内容/欠損/競合とKnown Folderを無音で検証する。
interface
procedure RunSharedLibraryChecks(const Root: string);
implementation
uses System.Classes, System.SysUtils, System.IOUtils, System.Hash, System.JSON, System.Generics.Collections,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_TestHelpers;
procedure Check(B: Boolean; const M: string);
begin if not B then raise Exception.Create(M); end;
procedure RunSharedLibraryChecks(const Root: string);
var L,L2: TMusicStudioSharedPsdLibrary; A,B,Stale: TMusicStudioPsdAsset;
  Error,Source,Hash,Dir,SameName,Metadata,MetadataHash,Revision,CopyHash: string;
  G: TGUID; Dup: Boolean; ChangedByte: Byte; Config,O,P: TJSONObject; Lock: TFileStream;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,GUIDToString(G)); ForceDirectories(Dir);
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'PSDAssets'));
  try
    Source := TPath.Combine(Dir,'original\source.psd'); ForceDirectories(ExtractFileDir(Source)); WriteLayeredTestPSD(Source);
    Hash := THashSHA2.GetHashStringFromFile(Source);
    Check(L.TryImport(Source,'同名素材','#CC8CE0',A,Dup,Error),Error); Check(not Dup,'first import');
    Check(A.FilePath<>Source,'managed copy'); Check(TFile.Exists(A.FilePath),'copy exists');
    Check(L.TryImport(Source,'同名素材','#CC8CE0',B,Dup,Error),Error); Check(Dup and (A.ID=B.ID),'content deduplicates');
    SameName := TPath.Combine(Dir,ExtractFileName(Source)); TFile.Copy(Source,SameName,False);
    // PSDヘッダーを保持して画像末尾だけ変える。ライブラリの内容同一性を確認する。
    ChangedByte := 42;
    with TFileStream.Create(SameName,fmOpenReadWrite) do
      try Position := Size-1; WriteBuffer(ChangedByte,1); finally Free; end;
    Check(L.TryImport(SameName,'同名素材','#CC8CE0',B,Dup,Error),Error); Check(not Dup and (A.ID<>B.ID),'same name different hash has own ID');
    Stale := A; A.ConfigJSON := '{"version":1,"mouthLayers":{"a":"root/口[1]"},"visibility":{},"future":true}';
    Check(L.TrySave(A,Error),Error);
    Metadata := TPath.Combine(ExtractFileDir(A.FilePath),'asset.json');
    MetadataHash := THashSHA2.GetHashStringFromFile(Metadata); CopyHash := THashSHA2.GetHashStringFromFile(A.FilePath);
    Check(not L.TrySave(Stale,Error),'stale save rejected');
    Check(THashSHA2.GetHashStringFromFile(Metadata)=MetadataHash,'conflict rewrote saved metadata');
    Check(THashSHA2.GetHashStringFromFile(A.FilePath)=CopyHash,'conflict rewrote managed PSD');
    Revision := A.Revision; Stale := A; Stale.Name := '置換失敗';
    Lock := TFileStream.Create(Metadata,fmOpenRead or fmShareDenyWrite);
    try Check(not L.TrySave(Stale,Error),'locked metadata replacement should fail'); finally Lock.Free; end;
    Check(Stale.Revision=Revision,'failed atomic save changed in-memory revision');
    Check(THashSHA2.GetHashStringFromFile(Metadata)=MetadataHash,'failed atomic save lost original metadata');
    Check(Length(TDirectory.GetFiles(ExtractFileDir(Metadata),'*.tmp*'))=0,'failed atomic save left temp files');
    Check(L.TryRead(A.ID,B,Error) and (B.Name=A.Name),'failed atomic save lost readable original');
    L2 := TMusicStudioSharedPsdLibrary.Create(L.Root);
    try
      Check(L2.TryRead(A.ID,B,Error),Error); B.Name := '別ストアで保存'; Check(L2.TrySave(B,Error),Error);
      MetadataHash := THashSHA2.GetHashStringFromFile(Metadata);
      Check(not L.TrySave(A,Error),'other store revision conflict ignored');
      Check(THashSHA2.GetHashStringFromFile(Metadata)=MetadataHash,'other store conflict rewrote metadata');
      A := B;
    finally L2.Free; end;
    Check(L.TryRead(A.ID,B,Error),Error); Config := TJSONObject.ParseJSONValue(B.ConfigJSON) as TJSONObject;
    try
      Check(TJSONObject(Config.GetValue('mouthLayers')).GetValue('a').Value='root/口[1]','vowels persist');
      Check(Config.GetValue('future')<>nil,'unknown config retained');
    finally Config.Free; end;
    TFile.Delete(A.FilePath); Check(L.TryRead(A.ID,B,Error) and B.Missing,'missing copy distinguished');
    Check(not L.TryRelocate(A.ID,SameName,Error),'different PSD cannot replace same asset');
    Check(L.TryRelocate(A.ID,Source,Error),Error); Check(L.ResolvePath(A.ID)=A.FilePath,'ID stable after recovery');
    TFile.Delete(A.FilePath);
    Check(L.TryImport(Source,'別名','#CC8CE0',B,Dup,Error),Error);
    Check(Dup and (B.ID=A.ID) and not B.Missing and TFile.Exists(B.FilePath),'duplicate import restores missing copy with stable ID');
    A := B; SetLength(A.Patterns,1); CreateGUID(G);
    A.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36)); A.Patterns[0].AssetID := A.ID;
    A.Patterns[0].Kind := 'emotion'; A.Patterns[0].Name := '表情'; A.Patterns[0].Color := '#CC8CE0';
    A.Patterns[0].ConfigJSON := '{"visibility":{},"futureConfig":true}'; Check(L.TrySave(A,Error),Error);
    Metadata := TPath.Combine(ExtractFileDir(A.FilePath),'asset.json');
    O := TJSONObject.ParseJSONValue(TFile.ReadAllText(Metadata,TEncoding.UTF8)) as TJSONObject;
    try
      O.AddPair('futureAsset','keep'); P := TJSONObject(TJSONArray(O.GetValue('patterns')).Items[0]);
      P.AddPair('futurePattern','keep'); TFile.WriteAllText(Metadata,O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
    Check(L.TryRead(A.ID,B,Error),Error); Check(L.TrySave(B,Error),Error);
    O := TJSONObject.ParseJSONValue(TFile.ReadAllText(Metadata,TEncoding.UTF8)) as TJSONObject;
    try
      Check(O.GetValue('futureAsset').Value='keep','unknown asset metadata retained');
      P := TJSONObject(TJSONArray(O.GetValue('patterns')).Items[0]);
      Check(P.GetValue('futurePattern').Value='keep','unknown shared pattern metadata retained');
      Check(TJSONObject(P.GetValue('config')).GetValue('futureConfig')<>nil,'unknown shared pattern config retained');
    finally O.Free; end;
    A := B; SetLength(A.Patterns,2); A.Patterns[1] := A.Patterns[0];
    Check(not L.TrySave(A,Error),'duplicate shared IDs cannot save');
    O := TJSONObject.ParseJSONValue(TFile.ReadAllText(Metadata,TEncoding.UTF8)) as TJSONObject;
    try
      TJSONArray(O.GetValue('patterns')).AddElement(TJSONValue(TJSONArray(O.GetValue('patterns')).Items[0].Clone));
      TFile.WriteAllText(Metadata,O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
    Check(not L.TryRead(B.ID,A,Error),'duplicate shared IDs cannot load'); L.Assets;
    Check(L.LastWarning<>'','invalid metadata explained in list');
    Check(not L.TryRead('..\evil',B,Error),'traversal rejected');
    Check(THashSHA2.GetHashStringFromFile(Source)=Hash,'original PSD unchanged');
    Check(MusicStudioDocumentsDirectory<>'','Known Folder Documents resolved without hardcoded profile');
    Writeln('SHARED_PSD_ATOMIC_FAILURE_RESTORE_CROSS_STORE_REVISION_NO_TMP_OK');
    Writeln('SHARED_PSD_COPY_DUPLICATE_MISSING_CONFLICT_OK (Temp isolated, original SHA unchanged)');
  finally L.Free; end;
end;
end.
