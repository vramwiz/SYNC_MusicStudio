unit SYNC_MusicStudio_PerformanceLibrary;

// 属性別演奏パターンの共通正本。読取では作成せず、明示保存だけを排他/版照合/原子的置換する。
// 作品へは参照ID/版と配置時snapshotを渡すため、後日の共通編集が既存曲を無断変更しない。
interface
uses SYNC_MusicStudio_PatternData;
type
  TMusicStudioPerformanceLibrary = class
  private
    FRoot,FWarning: string;
    function FileName(const Attribute,ID: string): string;
  public
    // PSDRootは既存共有root。別フォルダーの正本へ解決し、隔離rootも同じ規則で分離する。
    constructor Create(const PSDRoot: string);
    // 指定属性だけの値コピーを返す。破損ファイルはWarningへ分離し、他項目を利用可能に保つ。
    function Patterns(const Attribute: string): TArray<TMusicStudioPattern>;
    // 不存在/不正/版違いはFalseと説明。成功時だけ完全なパターンを返す。
    function TryRead(const Attribute,ID: string; out Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
    // Revision空は新規のみ。競合/不正/PSD固有stepはFalseで保存しない。
    function TrySave(var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
    property Root: string read FRoot;
    property Warning: string read FWarning;
  end;
// 意味名の共通区間だけPSD依存を除去する。旧物理キーstepを無理に汎用化しない。
function MusicStudioPortablePerformance(const Config: string): string;
implementation
uses System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections, System.Classes,
  Winapi.Windows, SYNC_MusicStudio_PerformanceKinds, SYNC_MusicStudio_LayerStepData;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := LowerCase(Copy(GUIDToString(G),2,36)); end;
function CheckedID(const Value: string): string;
var G: TGUID;
begin
  if Length(Value)=36 then G := StringToGUID('{'+Value+'}') else G := StringToGUID(Value);
  if IsEqualGUID(G,Default(TGUID)) then raise Exception.Create('演奏パターンIDが不正です。');
  Result := LowerCase(Copy(GUIDToString(G),2,36));
end;
procedure Put(O: TJSONObject; const K: string; V: TJSONValue);
begin O.RemovePair(K).Free; O.AddPair(K,V); end;
function MusicStudioPortablePerformance(const Config: string): string;
var V,D: TJSONValue; Steps: TMusicStudioLayerStepData;
begin
  Steps := TMusicStudioLayerStepData.Create;
  try
    Steps.LoadJSON(Config);
    if Steps.StepCount>0 then raise Exception.Create('旧PSD固有stepは共通ライブラリへ登録できません。共通区間で作成してください。');
  finally Steps.Free; end;
  V := TJSONObject.ParseJSONValue(Config);
  try
    if not (V is TJSONObject) then raise Exception.Create('演奏設定が不正です。');
    D := TJSONObject(V).GetValue('instrumentTimeline');
    if D is TJSONObject then Put(TJSONObject(D),'assetId',TJSONString.Create(''));
    // 空の旧step枠は特定PSDとの結び付きを残さない。
    TJSONObject(V).RemovePair('layerSteps').Free;
    Result := V.ToJSON;
  finally V.Free; end;
end;
constructor TMusicStudioPerformanceLibrary.Create(const PSDRoot: string);
begin
  inherited Create;
  if SameText(TPath.GetFileName(ExcludeTrailingPathDelimiter(PSDRoot)),'PSDAssets') then
    FRoot := TPath.Combine(TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(PSDRoot)),'PerformancePatterns')
  else FRoot := ExcludeTrailingPathDelimiter(PSDRoot)+'-PerformancePatterns';
  FRoot := TPath.GetFullPath(FRoot);
end;
function TMusicStudioPerformanceLibrary.FileName(const Attribute,ID: string): string;
begin
  if PerformanceKindIndex(Attribute)<0 then raise Exception.Create('演奏属性を選択してください。');
  Result := TPath.Combine(TPath.Combine(FRoot,Attribute),CheckedID(ID)+'.json');
end;
function TMusicStudioPerformanceLibrary.TryRead(const Attribute,ID: string; out Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
var O,CheckRoot,P: TJSONObject; V: TJSONValue; Stream: TFileStream; Bytes: TBytes; Path,Text: string;
begin
  Result := False; Pattern := Default(TMusicStudioPattern); ErrorText := ''; O := nil;
  try
    Path := FileName(Attribute,ID); Stream := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size>1024*1024 then raise Exception.Create('演奏パターンは1MiB以内です。');
      SetLength(Bytes,Stream.Size); if Length(Bytes)>0 then Stream.ReadBuffer(Bytes[0],Length(Bytes));
    finally Stream.Free; end;
    Text := TEncoding.UTF8.GetString(Bytes); if (Text<>'') and (Text[1]=#$FEFF) then Delete(Text,1,1);
    V := TJSONObject.ParseJSONValue(Text);
    if not (V is TJSONObject) then begin V.Free; raise Exception.Create('演奏ライブラリJSONが不正です。'); end;
    O := TJSONObject(V);
    if (O.GetValue<Integer>('version')<>1) or (O.GetValue<string>('attribute')<>Attribute) or
      (O.GetValue<string>('id')<>CheckedID(ID)) then raise Exception.Create('演奏ライブラリの版/属性/IDが不一致です。');
    Pattern.Kind := 'performance'; Pattern.ID := 'performance:'+CheckedID(ID);
    Pattern.SharedPatternID := CheckedID(ID); Pattern.PerformanceAttribute := Attribute;
    Pattern.LibraryRevision := CheckedID(O.GetValue<string>('revision'));
    Pattern.Name := O.GetValue<string>('name'); Pattern.Color := O.GetValue<string>('color');
    Pattern.ConfigJSON := MusicStudioPortablePerformance(O.GetValue<TJSONObject>('performance').ToJSON);
    CheckRoot := TJSONObject.Create;
    try
      P := TJSONObject.Create; P.AddPair('id',Pattern.ID); P.AddPair('kind','performance'); P.AddPair('name',Pattern.Name);
      P.AddPair('color',Pattern.Color); P.AddPair('performance',TJSONObject.ParseJSONValue(Pattern.ConfigJSON));
      CheckRoot.AddPair('patterns',TJSONArray.Create(P));
      if not ValidateMusicStudioPatterns(CheckRoot,ErrorText) then raise Exception.Create(ErrorText);
    finally CheckRoot.Free; end;
    Result := True;
  except on E: Exception do begin ErrorText := E.Message; Pattern := Default(TMusicStudioPattern); end; end;
  O.Free;
end;
function TMusicStudioPerformanceLibrary.Patterns(const Attribute: string): TArray<TMusicStudioPattern>;
var Files: TArray<string>; Path,Error: string; P: TMusicStudioPattern; L: TList<TMusicStudioPattern>;
begin
  Result := nil; FWarning := ''; if PerformanceKindIndex(Attribute)<0 then Exit;
  Path := TPath.Combine(FRoot,Attribute); if not TDirectory.Exists(Path) then Exit;
  L := TList<TMusicStudioPattern>.Create;
  try
    Files := TDirectory.GetFiles(Path,'*.json',TSearchOption.soTopDirectoryOnly); TArray.Sort<string>(Files);
    for Path in Files do
      if TryRead(Attribute,TPath.GetFileNameWithoutExtension(Path),P,Error) then L.Add(P)
      else FWarning := FWarning+TPath.GetFileName(Path)+': '+Error+#13#10;
    Result := L.ToArray;
  finally L.Free; end;
end;
function TMusicStudioPerformanceLibrary.TrySave(var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
var Candidate,Existing,Verified: TMusicStudioPattern; O: TJSONObject; Lock: THandle; Path,Temp,Text: string;
begin
  Result := False; ErrorText := ''; Temp := ''; Lock := INVALID_HANDLE_VALUE; O := nil;
  try
    Candidate := Pattern; Candidate.ConfigJSON := MusicStudioPortablePerformance(Candidate.ConfigJSON);
    if Candidate.SharedPatternID='' then Candidate.SharedPatternID := NewID;
    Path := FileName(Candidate.PerformanceAttribute,Candidate.SharedPatternID);
    ForceDirectories(FRoot);
    Lock := CreateFile(PChar(TPath.Combine(FRoot,'.write.lock')),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    if Lock=INVALID_HANDLE_VALUE then raise Exception.Create('演奏ライブラリは別の保存処理で使用中です。');
    if TFile.Exists(Path) then begin
      if not TryRead(Candidate.PerformanceAttribute,Candidate.SharedPatternID,Existing,ErrorText) then raise Exception.Create(ErrorText);
      if Existing.LibraryRevision<>Candidate.LibraryRevision then raise Exception.Create('演奏パターンが更新されています。一覧を選び直してください。');
    end else if Candidate.LibraryRevision<>'' then raise Exception.Create('元の演奏パターンがありません。');
    Candidate.LibraryRevision := NewID; Candidate.AssetID := '';
    O := TJSONObject.Create; O.AddPair('version',TJSONNumber.Create(1)); O.AddPair('id',CheckedID(Candidate.SharedPatternID));
    O.AddPair('attribute',Candidate.PerformanceAttribute); O.AddPair('revision',Candidate.LibraryRevision);
    O.AddPair('name',Candidate.Name); O.AddPair('color',Candidate.Color);
    O.AddPair('performance',TJSONObject.ParseJSONValue(Candidate.ConfigJSON));
    Text := O.ToJSON; if Length(Text)>262144 then raise Exception.Create('演奏設定が大きすぎます。');
    // 候補を検証してから正本へ公開する。検証文書のIDは正本の固定IDとは別に発行する。
    if Trim(Candidate.Name)='' then raise Exception.Create('演奏名を入力してください。');
    ForceDirectories(ExtractFileDir(Path)); Temp := Path+'.'+NewID+'.tmp'; TFile.WriteAllText(Temp,Text,TEncoding.UTF8);
    // 公開前の構造検証は作品と同じvalidatorを使う。
    with TMusicStudioDocument.Create do try
      if not TryLoad('',ErrorText) then raise Exception.Create(ErrorText);
      Candidate.ID := PatternAt(AddPerformance).ID; UpdatePattern(Candidate);
      if not TrySave(Text,ErrorText) then raise Exception.Create(ErrorText);
    finally Free; end;
    if not MoveFileEx(PChar(Temp),PChar(Path),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    Temp := ''; Verified := Candidate; Verified.ID := 'performance:'+CheckedID(Candidate.SharedPatternID); Pattern := Verified; Result := True;
  except on E: Exception do ErrorText := E.Message; end;
  if (Temp<>'') and TFile.Exists(Temp) then TFile.Delete(Temp);
  O.Free; if Lock<>INVALID_HANDLE_VALUE then CloseHandle(Lock);
end;
end.
