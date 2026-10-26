unit SYNC_MusicStudio_PsdImport;

// 外部dropのPSDを読込/合成検証後に管理コピーへ登録する。原本を変更しない。
interface
uses SYNC_MusicStudio_SharedPsdLibrary;
function ImportMusicStudioPsdFile(Store: TMusicStudioSharedPsdLibrary; const Path: string;
  out Asset: TMusicStudioPsdAsset; out Duplicate: Boolean; out ErrorText: string): Boolean;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, Vcl.Graphics, SYNC_MusicStudio_PsdLayers;
function ImportMusicStudioPsdFile(Store: TMusicStudioSharedPsdLibrary; const Path: string;
  out Asset: TMusicStudioPsdAsset; out Duplicate: Boolean; out ErrorText: string): Boolean;
var D: TMusicStudioLayerDocument; B: TBitmap; Hash: string;
begin
  Result := False; Duplicate := False; ErrorText := ''; Asset := Default(TMusicStudioPsdAsset);
  try
    if not SameText(ExtractFileExt(Path),'.psd') then raise Exception.Create('PSDファイルをドロップしてください。');
    Hash := THashSHA2.GetHashStringFromFile(Path);
    D := TMusicStudioLayerDocument.Create; B := TBitmap.Create;
    try
      if not D.LoadFile(Path) then raise Exception.Create(D.LastError);
      if not D.Render(B) then raise Exception.Create(D.LastError);
    finally B.Free; D.Free; end;
    if not SameText(Hash,THashSHA2.GetHashStringFromFile(Path)) then raise Exception.Create('読込中にPSD原本が変わりました。再度登録してください。');
    Result := Store.TryImport(Path,ChangeFileExt(TPath.GetFileName(Path),''),'#CC8CE0',Asset,Duplicate,ErrorText);
  except on E: Exception do ErrorText := E.Message; end;
end;
end.
