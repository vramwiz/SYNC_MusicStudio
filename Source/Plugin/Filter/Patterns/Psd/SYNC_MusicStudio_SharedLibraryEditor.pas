unit SYNC_MusicStudio_SharedLibraryEditor;

// 共有項目の追加/編集ポップアップ。キャンセル中は管理コピーも設定も書き込まない。
interface
uses System.Classes, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary;
function AddMusicStudioSharedItem(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  const Kind, AssetID: string; out Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
function EditMusicStudioSharedItem(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.UITypes, Vcl.Forms, Vcl.Dialogs,
  SYNC_MusicStudio_PatternSettingsForm;
function NewID: string;
var G: TGUID;
begin CreateGUID(G); Result := LowerCase(Copy(GUIDToString(G),2,36)); end;
function SharedPattern(const P: TMusicStudioPattern): TMusicStudioSharedPattern;
begin
  Result := Default(TMusicStudioSharedPattern); Result.ID := P.SharedPatternID; Result.AssetID := P.AssetID;
  Result.Kind := P.Kind; Result.Name := P.Name; Result.Color := P.Color; Result.ConfigJSON := P.ConfigJSON;
end;
function ShowEditor(Owner: TComponent; var P: TMusicStudioPattern; const Path,BaseConfig: string): Boolean;
var D: TMusicStudioPatternSettings;
begin
  D := TMusicStudioPatternSettings.Create(Owner);
  try
    D.LoadSharedPattern(P,Path,BaseConfig); Result := D.ShowModal=mrOK;
    if Result then D.ReadSharedPattern(P);
  finally D.Free; end;
end;
function AddMusicStudioSharedItem(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  const Kind,AssetID: string; out Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
var FileDialog: TOpenDialog; Source,Hash,ExpectedRevision: string; A,Existing: TMusicStudioPsdAsset;
  Found,Dup: Boolean; N: Integer;
begin
  Result := False; ErrorText := ''; Pattern := Default(TMusicStudioPattern);
  try
    Pattern.Kind := Kind; Pattern.Color := '#CC8CE0';
    if Kind='psd' then begin
      FileDialog := TOpenDialog.Create(Owner);
      try
        FileDialog.Filter := 'PSDファイル (*.psd)|*.psd'; FileDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing];
        FileDialog.Title := '共有PSDへ登録する原本を選択（原本は変更しません）';
        if not FileDialog.Execute then Exit; Source := TPath.GetFullPath(FileDialog.FileName);
      finally FileDialog.Free; end;
      Hash := THashSHA2.GetHashStringFromFile(Source); Found := False;
      for Existing in Store.Assets do if SameText(Existing.ContentHash,Hash) then begin A := Existing; Found := True; Break; end;
      Pattern.Name := ChangeFileExt(ExtractFileName(Source),''); Pattern.ConfigJSON := '';
      if Found then begin Pattern.Name := A.Name; Pattern.Color := A.Color; Pattern.ConfigJSON := A.ConfigJSON; end;
      if not ShowEditor(Owner,Pattern,Source,Pattern.ConfigJSON) then Exit;
      if not SameText(Hash,THashSHA2.GetHashStringFromFile(Source)) then raise Exception.Create('設定中にPSD原本が変わりました。再度登録してください。');
      ExpectedRevision := ''; if Found then ExpectedRevision := A.Revision;
      if not Store.TryImport(Source,Pattern.Name,Pattern.Color,Existing,Dup,ErrorText,ExpectedRevision) then Exit;
      if Dup and not Found then raise Exception.Create('同じPSDが別画面から登録されました。一覧から設定を開き直してください。');
      A := Existing;
      Pattern.AssetID := A.ID; Pattern.FilePath := A.FilePath;
      A.Name := Pattern.Name; A.Color := Pattern.Color; A.ConfigJSON := Pattern.ConfigJSON;
      Result := Store.TrySave(A,ErrorText);
    end else begin
      if not Store.TryRead(AssetID,A,ErrorText) then Exit;
      if A.Missing then raise Exception.Create('PSD管理コピーが見つかりません。共有PSD一覧で復旧してください。');
      Pattern.AssetID := A.ID; Pattern.SharedPatternID := NewID; Pattern.FilePath := A.FilePath;
      if Kind='emotion' then begin Pattern.Name := '表情'; Pattern.ConfigJSON := A.ConfigJSON; end
      else if Kind='animation' then begin Pattern.Name := 'アニメーション'; Pattern.ConfigJSON := ''; end
      else if Kind='instrument' then begin Pattern.Name := '楽器の姿勢'; Pattern.ConfigJSON := A.ConfigJSON; end
      else raise Exception.Create('この共有属性は未対応です。');
      if not ShowEditor(Owner,Pattern,A.FilePath,A.ConfigJSON) then Exit;
      N := Length(A.Patterns); SetLength(A.Patterns,N+1); A.Patterns[N] := SharedPattern(Pattern);
      Result := Store.TrySave(A,ErrorText);
    end;
  except on E: Exception do ErrorText := E.Message; end;
end;
function EditMusicStudioSharedItem(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
var A: TMusicStudioPsdAsset; I: Integer; Found: Boolean; D: TOpenDialog;
begin
  Result := False; ErrorText := '';
  try
    if not Store.TryRead(Pattern.AssetID,A,ErrorText) then Exit;
    if A.Missing then begin
      D := TOpenDialog.Create(Owner);
      try
        D.Filter := 'PSDファイル (*.psd)|*.psd'; D.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing];
        D.Title := '欠損した管理コピーと同じ内容のPSDを選択'; if not D.Execute then Exit;
        if not Store.TryRelocate(A.ID,D.FileName,ErrorText) then Exit;
      finally D.Free; end;
      if not Store.TryRead(Pattern.AssetID,A,ErrorText) then Exit;
    end;
    Found := Pattern.Kind='psd';
    if Found then begin Pattern.Name := A.Name; Pattern.Color := A.Color; Pattern.ConfigJSON := A.ConfigJSON; end
    else for I := 0 to High(A.Patterns) do if A.Patterns[I].ID=Pattern.SharedPatternID then begin
      Pattern.Name := A.Patterns[I].Name; Pattern.Color := A.Patterns[I].Color; Pattern.ConfigJSON := A.Patterns[I].ConfigJSON; Found := True; Break;
    end;
    if not Found then raise Exception.Create('共有パターンが見つかりません。');
    if not ShowEditor(Owner,Pattern,A.FilePath,A.ConfigJSON) then Exit;
    if Pattern.Kind='psd' then begin A.Name := Pattern.Name; A.Color := Pattern.Color; A.ConfigJSON := Pattern.ConfigJSON; end
    else for I := 0 to High(A.Patterns) do if A.Patterns[I].ID=Pattern.SharedPatternID then begin A.Patterns[I] := SharedPattern(Pattern); Break; end;
    Result := Store.TrySave(A,ErrorText);
  except on E: Exception do ErrorText := E.Message; end;
end;
end.
