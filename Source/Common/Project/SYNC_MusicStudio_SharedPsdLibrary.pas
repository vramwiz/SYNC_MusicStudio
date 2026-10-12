unit SYNC_MusicStudio_SharedPsdLibrary;

// 作品をまたぐPSD/設定の正本。原本を変更せず管理コピーと固定IDを保存する。
// 構築/一覧/解決は読取のみ。Import/Save時だけ Known Folder Documents 配下へ書く。
interface
uses System.JSON, System.Classes;
type
  TMusicStudioSharedPattern = record
    ID, AssetID, Kind, Name, Color, ConfigJSON: string;
  end;
  TMusicStudioPsdAsset = record
    ID, Name, Color, FilePath, OriginalPath, ContentHash, ConfigJSON, Revision: string;
    Missing: Boolean;
    Patterns: TArray<TMusicStudioSharedPattern>;
  end;
  TMusicStudioSharedPsdLibrary = class
  private
    FRoot: string;
    FLastWarning: string;
    function AssetDirectory(const ID: string): string;
    function MetadataPath(const ID: string): string;
    function ReadMetadata(const ID: string): TJSONObject;
    function LockLibrary: NativeUInt;
    procedure UnlockLibrary(Handle: NativeUInt);
    procedure PublishPsdCopy(const SourcePath,TargetPath,ExpectedHash: string);
  protected
    // ストリームへのコピーだけを分離。公開/検証/失敗時整理は共通経路で行う。
    procedure CopyPsdData(Source,Target: TStream); virtual;
  public
    // OverrideRootはテスト隔離用。空ならKnown Folder Documentsを使用する。
    constructor Create(const OverrideRoot: string = '');
    function Assets: TArray<TMusicStudioPsdAsset>;
    function TryRead(const ID: string; out Asset: TMusicStudioPsdAsset; out ErrorText: string): Boolean;
    function ResolvePath(const ID: string): string;
    // 同一内容は既存ID。同名異内容は新規ID。UIで合成可能と確認後に呼び出す。
    function TryImport(const SourcePath, Name, Color: string; out Asset: TMusicStudioPsdAsset;
      out Duplicate: Boolean; out ErrorText: string): Boolean;
    // 同一フォルダーの排他書込ロックと楽観的版照合。競合時は上書きせずFalse。
    function TrySave(var Asset: TMusicStudioPsdAsset; out ErrorText: string): Boolean;
    // 管理コピー欠損の復旧。同一hashのPSDだけを同じIDへコピーする。
    function TryRelocate(const ID, SourcePath: string; out ErrorText: string): Boolean;
    property Root: string read FRoot;
    property LastWarning: string read FLastWarning;
  end;
function MusicStudioDocumentsDirectory: string;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.Generics.Collections,
  Winapi.Windows, Winapi.ShlObj, Winapi.KnownFolders, Winapi.ActiveX;
function MusicStudioDocumentsDirectory: string;
var P: PWideChar;
begin
  P := nil;
  if Failed(SHGetKnownFolderPath(FOLDERID_Documents,0,0,P)) then
    raise Exception.Create('Documentsの保存先を取得できません。');
  try Result := P; finally CoTaskMemFree(P); end;
end;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := LowerCase(Copy(GUIDToString(G),2,36)); end;
function CheckedID(const ID: string): string;
var G: TGUID;
begin
  Result := ID;
  if Length(Result)=36 then Result := '{'+Result+'}';
  try G := StringToGUID(Result); except raise Exception.Create('共有PSDのIDが不正です。'); end;
  Result := LowerCase(Copy(GUIDToString(G),2,36));
end;
procedure Put(O: TJSONObject; const K: string; V: TJSONValue);
begin O.RemovePair(K).Free; O.AddPair(K,V); end;
procedure CheckNameColor(const Name, Color: string);
var I: Integer;
begin
  if (Trim(Name)='') or (Length(Name)>200) then raise Exception.Create('名前は1～200文字で入力してください。');
  if (Length(Color)<>7) or (Color[1]<>'#') then raise Exception.Create('色は#RRGGBBで指定してください。');
  for I := 2 to 7 do if not CharInSet(Color[I],['0'..'9','a'..'f','A'..'F']) then
    raise Exception.Create('色は#RRGGBBで指定してください。');
end;
function Text(O: TJSONObject; const K: string): string;
begin
  if not (O.GetValue(K) is TJSONString) then raise Exception.Create('共有PSDメタデータの'+K+'が不正です。');
  Result := O.GetValue(K).Value;
end;
function ObjectJSON(const S: string): TJSONObject;
var V: TJSONValue;
begin
  if Length(S)>1024*1024 then raise Exception.Create('共有設定は1MiB以内にしてください。');
  V := TJSONObject.ParseJSONValue(S,False,True);
  if not (V is TJSONObject) then begin V.Free; raise Exception.Create('共有設定はJSONオブジェクトで指定してください。'); end;
  Result := TJSONObject(V);
end;
procedure AtomicSave(const Path, Data: string);
var TempPath: string;
begin
  TempPath := Path+'.'+NewID+'.tmp';
  try
    TFile.WriteAllText(TempPath,Data,TEncoding.UTF8);
    if not MoveFileEx(PChar(TempPath),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  finally if TFile.Exists(TempPath) then TFile.Delete(TempPath); end;
end;
procedure CheckPSD(const Path: string);
var S: TFileStream; B: array[0..25] of Byte;
begin
  if not SameText(ExtractFileExt(Path),'.psd') then raise Exception.Create('PSDファイルを選択してください。');
  S := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<26) or (S.Size>512*1024*1024) then raise Exception.Create('PSDサイズは26B～512MiBにしてください。');
    S.ReadBuffer(B,SizeOf(B));
    if (B[0]<>Ord('8')) or (B[1]<>Ord('B')) or (B[2]<>Ord('P')) or (B[3]<>Ord('S')) or
      (B[4]<>0) or (B[5]<>1) then raise Exception.Create('PSD v1のヘッダーではありません。');
  finally S.Free; end;
end;
procedure TMusicStudioSharedPsdLibrary.CopyPsdData(Source,Target: TStream);
var Buffer: array[0..65535] of Byte; Count: Integer;
begin
  Source.Position := 0;
  repeat
    Count := Source.Read(Buffer,SizeOf(Buffer));
    if Count>0 then Target.WriteBuffer(Buffer,Count);
  until Count=0;
end;
procedure TMusicStudioSharedPsdLibrary.PublishPsdCopy(const SourcePath,TargetPath,ExpectedHash: string);
var Source: TFileStream; Target: THandleStream; TempPath: string;
    Handle: THandle; ExpectedSize: Int64; CreatedTemp: Boolean;
begin
  // 一時ファイルは公開先と同じディレクトリ。部分コピーをsource.psdへ露出しない。
  TempPath := TargetPath+'.'+NewID+'.tmp'; Source := nil; Target := nil; Handle := INVALID_HANDLE_VALUE; CreatedTemp := False;
  try
    Source := TFileStream.Create(SourcePath,fmOpenRead or fmShareDenyWrite);
    ExpectedSize := Source.Size;
    if (ExpectedSize<26) or (ExpectedSize>512*1024*1024) then raise Exception.Create('PSDサイズが変更されました。再登録してください。');
    // 別の書込者を拒否しつつ、この開いたハンドルのまま原子的に移動できるようにする。
    Handle := CreateFile(PChar(TempPath),GENERIC_READ or GENERIC_WRITE,FILE_SHARE_READ or FILE_SHARE_DELETE,
      nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
    if Handle=INVALID_HANDLE_VALUE then RaiseLastOSError;
    CreatedTemp := True;
    Target := THandleStream.Create(Handle); CopyPsdData(Source,Target);
    if Target.Size<>ExpectedSize then raise Exception.Create('PSDコピーのサイズが一致しません。管理コピーは公開していません。');
    if not FlushFileBuffers(Handle) then RaiseLastOSError;
    Target.Position := 0;
    if not SameText(ExpectedHash,THashSHA2.GetHashString(Target)) then
      raise Exception.Create('PSDコピーの内容が一致しません。管理コピーは公開していません。');
    // 欠損回復でも既存の管理ファイルを置換しない。先に他者が公開した場合は失敗する。
    if not MoveFileEx(PChar(TempPath),PChar(TargetPath),MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
  finally
    Target.Free; if Handle<>INVALID_HANDLE_VALUE then CloseHandle(Handle); Source.Free;
    if CreatedTemp and TFile.Exists(TempPath) then TFile.Delete(TempPath);
  end;
end;
constructor TMusicStudioSharedPsdLibrary.Create(const OverrideRoot: string);
begin
  inherited Create;
  if OverrideRoot<>'' then FRoot := TPath.GetFullPath(OverrideRoot)
  else FRoot := TPath.Combine(MusicStudioDocumentsDirectory,'SYNC_MusicStudio\Libraries\PSDAssets');
  if not SameText(FRoot,TPath.GetPathRoot(FRoot)) then FRoot := ExcludeTrailingPathDelimiter(FRoot);
end;
function TMusicStudioSharedPsdLibrary.AssetDirectory(const ID: string): string;
begin Result := TPath.Combine(FRoot,CheckedID(ID)); end;
function TMusicStudioSharedPsdLibrary.MetadataPath(const ID: string): string;
begin Result := TPath.Combine(AssetDirectory(ID),'asset.json'); end;
function TMusicStudioSharedPsdLibrary.LockLibrary: NativeUInt;
var Deadline: UInt64; Code: Cardinal;
begin
  // フォルダー内の同じファイルをshare=0で開く。大小文字/末尾区切りやセッションが違っても同じ実体をロックする。
  Deadline := GetTickCount64+2000;
  repeat
    Result := CreateFile(PChar(TPath.Combine(FRoot,'.write.lock')),GENERIC_READ or GENERIC_WRITE,0,nil,
      OPEN_ALWAYS,FILE_ATTRIBUTE_HIDDEN,0);
    if Result<>INVALID_HANDLE_VALUE then Exit;
    Code := GetLastError;
    if (Code<>ERROR_SHARING_VIOLATION) and (Code<>ERROR_LOCK_VIOLATION) then RaiseLastOSError(Code);
    if GetTickCount64>=Deadline then raise Exception.Create('共有PSDを別の編集画面が保存中です。もう一度操作してください。');
    Sleep(10);
  until False;
end;
procedure TMusicStudioSharedPsdLibrary.UnlockLibrary(Handle: NativeUInt);
begin CloseHandle(Handle); end;
function TMusicStudioSharedPsdLibrary.ReadMetadata(const ID: string): TJSONObject;
var Path: string; S: TFileStream; Data: TBytes;
begin
  Path := MetadataPath(ID); S := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if S.Size>1024*1024 then raise Exception.Create('共有PSDメタデータが1MiBを超えています。');
    SetLength(Data,S.Size); if Length(Data)>0 then S.ReadBuffer(Data[0],Length(Data));
  finally S.Free; end;
  Result := ObjectJSON(TEncoding.UTF8.GetString(Data));
  try
    if not (Result.GetValue('version') is TJSONNumber) or (Result.GetValue('version').Value<>'1') or
      (CheckedID(Text(Result,'id'))<>CheckedID(ID)) then raise Exception.Create('共有PSDメタデータのバージョン/IDが一致しません。');
  except Result.Free; raise; end;
end;
function TMusicStudioSharedPsdLibrary.TryRead(const ID: string; out Asset: TMusicStudioPsdAsset; out ErrorText: string): Boolean;
var O,P: TJSONObject; A: TJSONArray; I: Integer; Key: string; IDs: TDictionary<string,Boolean>;
begin
  Result := False; ErrorText := '';
  try
    Key := CheckedID(ID); Asset := Default(TMusicStudioPsdAsset);
    O := ReadMetadata(Key);
    try
      Asset.ID := CheckedID(Text(O,'id')); Asset.Name := Text(O,'name'); Asset.Color := Text(O,'color');
      CheckNameColor(Asset.Name,Asset.Color);
      Asset.OriginalPath := Text(O,'originalPath'); Asset.ContentHash := Text(O,'contentHash');
      Asset.Revision := Text(O,'revision'); Asset.FilePath := TPath.Combine(AssetDirectory(Key),'source.psd');
      Asset.Missing := not TFile.Exists(Asset.FilePath);
      if not (O.GetValue('config') is TJSONObject) then raise Exception.Create('共有PSD configが不正です。');
      Asset.ConfigJSON := O.GetValue('config').ToJSON;
      if not (O.GetValue('patterns') is TJSONArray) then raise Exception.Create('共有PSD patternsが不正です。');
      A := TJSONArray(O.GetValue('patterns')); SetLength(Asset.Patterns,A.Count);
      IDs := TDictionary<string,Boolean>.Create;
      try
      for I := 0 to A.Count-1 do begin
        if not (A.Items[I] is TJSONObject) then raise Exception.Create('共有パターンが不正です。');
        P := TJSONObject(A.Items[I]);
        Asset.Patterns[I].ID := CheckedID(Text(P,'id')); Asset.Patterns[I].AssetID := Asset.ID;
        if IDs.ContainsKey(Asset.Patterns[I].ID) then raise Exception.Create('共有パターンIDが重複しています。');
        IDs.Add(Asset.Patterns[I].ID,True);
        Asset.Patterns[I].Kind := Text(P,'kind'); Asset.Patterns[I].Name := Text(P,'name'); Asset.Patterns[I].Color := Text(P,'color');
        CheckNameColor(Asset.Patterns[I].Name,Asset.Patterns[I].Color);
        if not (P.GetValue('config') is TJSONObject) then raise Exception.Create('共有パターンconfigが不正です。');
        Asset.Patterns[I].ConfigJSON := P.GetValue('config').ToJSON;
      end;
      finally IDs.Free; end;
      Result := True;
    finally O.Free; end;
  except on E: Exception do ErrorText := E.Message; end;
end;
function TMusicStudioSharedPsdLibrary.Assets: TArray<TMusicStudioPsdAsset>;
var Dir,Error: string; A: TMusicStudioPsdAsset; L: TList<TMusicStudioPsdAsset>;
begin
  Result := nil; FLastWarning := ''; if not TDirectory.Exists(FRoot) then Exit;
  L := TList<TMusicStudioPsdAsset>.Create;
  try
    for Dir in TDirectory.GetDirectories(FRoot) do
      if TryRead(ExtractFileName(Dir),A,Error) then L.Add(A)
      else FLastWarning := Copy(FLastWarning+ExtractFileName(Dir)+': '+Error+sLineBreak,1,2048);
    Result := L.ToArray;
  finally L.Free; end;
end;
function TMusicStudioSharedPsdLibrary.ResolvePath(const ID: string): string;
begin
  Result := '';
  try Result := TPath.Combine(AssetDirectory(ID),'source.psd'); except on E: Exception do Result := ''; end;
end;
function TMusicStudioSharedPsdLibrary.TryImport(const SourcePath,Name,Color: string; out Asset: TMusicStudioPsdAsset;
  out Duplicate: Boolean; out ErrorText: string): Boolean;
var A: TMusicStudioPsdAsset; Hash,Dir,CopyPath,ImportedID: string; O: TJSONObject; Handle: NativeUInt;
  Imported,Published: Boolean;
begin
  Result := False; Duplicate := False; ErrorText := ''; Asset := Default(TMusicStudioPsdAsset);
  try
    CheckNameColor(Name,Color); CheckPSD(SourcePath); Hash := THashSHA2.GetHashStringFromFile(SourcePath);
    ForceDirectories(FRoot);
    Handle := LockLibrary;
    try
      for A in Assets do if SameText(A.ContentHash,Hash) then begin
        if A.Missing then PublishPsdCopy(SourcePath,A.FilePath,Hash);
        Asset := A; Asset.Missing := False; Duplicate := True; Result := True; Exit;
      end;
      Asset.ID := NewID; Dir := AssetDirectory(Asset.ID); Imported := False; Published := False;
      if not CreateDirectory(PChar(Dir),nil) then RaiseLastOSError;
      CopyPath := TPath.Combine(Dir,'source.psd');
      try
        PublishPsdCopy(SourcePath,CopyPath,Hash); Published := True;
        O := TJSONObject.Create;
        try
          O.AddPair('version',TJSONNumber.Create(1)); O.AddPair('id',Asset.ID); O.AddPair('name',Name); O.AddPair('color',Color);
          O.AddPair('originalPath',TPath.GetFullPath(SourcePath)); O.AddPair('contentHash',Hash); O.AddPair('revision',NewID);
          O.AddPair('config',ObjectJSON('{"version":1,"mouthLayers":{},"visibility":{}}')); O.AddPair('patterns',TJSONArray.Create);
          AtomicSave(MetadataPath(Asset.ID),O.ToJSON); Imported := True;
        finally O.Free; end;
        ImportedID := Asset.ID; Result := TryRead(ImportedID,Asset,ErrorText);
      finally
        // この関数が新規生成した固定GUIDフォルダーだけを失敗時に整理する。
        if not Imported then begin
          if Published and TFile.Exists(CopyPath) then TFile.Delete(CopyPath);
          if TDirectory.Exists(Dir) and (Length(TDirectory.GetFiles(Dir))=0) and (Length(TDirectory.GetDirectories(Dir))=0) then TDirectory.Delete(Dir,False);
        end;
      end;
    finally UnlockLibrary(Handle); end;
  except on E: Exception do ErrorText := E.Message; end;
end;
function TMusicStudioSharedPsdLibrary.TrySave(var Asset: TMusicStudioPsdAsset; out ErrorText: string): Boolean;
var O,P,OldPattern: TJSONObject; A,OldPatterns: TJSONArray; SP: TMusicStudioSharedPattern;
  H: NativeUInt; Revision,ID: string; V: TJSONValue; IDs: TDictionary<string,Boolean>;
begin
  Result := False; ErrorText := '';
  try
    CheckNameColor(Asset.Name,Asset.Color);
    H := LockLibrary;
    try
      O := ReadMetadata(Asset.ID);
      try
        if Text(O,'revision')<>Asset.Revision then raise Exception.Create('共有PSDは他の画面で更新されました。再読込してから保存してください。');
        Put(O,'name',TJSONString.Create(Asset.Name)); Put(O,'color',TJSONString.Create(Asset.Color));
        Put(O,'config',ObjectJSON(Asset.ConfigJSON)); A := TJSONArray.Create;
        OldPatterns := TJSONArray(O.GetValue('patterns')); IDs := TDictionary<string,Boolean>.Create;
        try
          for SP in Asset.Patterns do begin
            ID := CheckedID(SP.ID);
            if IDs.ContainsKey(ID) then raise Exception.Create('共有パターンIDが重複しています。');
            IDs.Add(ID,True); CheckNameColor(SP.Name,SP.Color);
            if (SP.AssetID<>'') and (CheckedID(SP.AssetID)<>CheckedID(Asset.ID)) then
              raise Exception.Create('共有パターンの素材IDが一致しません。');
            OldPattern := nil;
            if OldPatterns<>nil then for V in OldPatterns do if (V is TJSONObject) and
              SameText(Text(TJSONObject(V),'id'),ID) then begin OldPattern := TJSONObject(V); Break; end;
            if (SP.Kind<>'emotion') and (SP.Kind<>'animation') and (SP.Kind<>'instrument') and
              ((OldPattern=nil) or (Text(OldPattern,'kind')<>SP.Kind)) then raise Exception.Create('未対応の共有パターンです。');
            if OldPattern=nil then P := TJSONObject.Create else P := TJSONObject(OldPattern.Clone);
            A.AddElement(P); Put(P,'id',TJSONString.Create(ID)); Put(P,'kind',TJSONString.Create(SP.Kind));
            Put(P,'name',TJSONString.Create(SP.Name)); Put(P,'color',TJSONString.Create(SP.Color)); Put(P,'config',ObjectJSON(SP.ConfigJSON));
          end;
          Put(O,'patterns',A); A := nil;
        finally IDs.Free; A.Free; end;
        Revision := NewID; Put(O,'revision',TJSONString.Create(Revision));
        if Length(O.ToJSON)>1024*1024 then raise Exception.Create('共有PSD設定が1MiBを超えています。');
        AtomicSave(MetadataPath(Asset.ID),O.ToJSON); Asset.Revision := Revision; Result := True;
      finally O.Free; end;
    finally UnlockLibrary(H); end;
  except on E: Exception do ErrorText := E.Message; end;
end;
function TMusicStudioSharedPsdLibrary.TryRelocate(const ID,SourcePath: string; out ErrorText: string): Boolean;
var A: TMusicStudioPsdAsset; H: NativeUInt;
begin
  Result := False; ErrorText := '';
  try
    CheckPSD(SourcePath); H := LockLibrary;
    try
      if not TryRead(ID,A,ErrorText) then Exit;
      if TFile.Exists(A.FilePath) then raise Exception.Create('管理コピーは存在します。上書き復旧は行いません。');
      if not SameText(A.ContentHash,THashSHA2.GetHashStringFromFile(SourcePath)) then raise Exception.Create('内容が異なるPSDです。別素材として登録してください。');
      PublishPsdCopy(SourcePath,A.FilePath,A.ContentHash);
      Result := True;
    finally UnlockLibrary(H); end;
  except on E: Exception do ErrorText := E.Message; end;
end;
end.
