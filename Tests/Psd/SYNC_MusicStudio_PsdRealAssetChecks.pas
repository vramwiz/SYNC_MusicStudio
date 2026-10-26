unit SYNC_MusicStudio_PsdRealAssetChecks;

// Known Folderの実PSDは読取だけ。原本前後SHA256を照合し、PNG/ログのみRootへ保存する。
// 音声処理、共有ライブラリ登録、PSD保存/認証APIは参照しない。
interface
procedure RunMusicStudioPsdRealAssetChecks(const Root: string);

implementation

uses Winapi.Windows, Winapi.ShlObj, Winapi.KnownFolders, Winapi.ActiveX,
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.StrUtils,
  System.Generics.Collections, Vcl.Graphics, Vcl.Imaging.pngimage, System.Hash,
  SYNC_MusicStudio_PsdLayers;

const
  PREFERRED_KEYBOARD = '東北きりたん_鍵盤_キーボード.psd';
  PREFERRED_DRUM = '東北きりたん_打撃_ドラム_持ち方修正.psd';

function DocumentsDirectory: string;
var Path: PWideChar; Status: HRESULT;
begin
  Path := nil; Status := SHGetKnownFolderPath(FOLDERID_Documents,0,0,Path);
  if Failed(Status) then raise EOSError.CreateFmt('Documents Known Folder取得失敗: %.8x',[Status]);
  try Result := Path; finally CoTaskMemFree(Path); end;
end;

procedure SavePreview512(Source: TBitmap; const OutputPath: string);
var Bitmap: TBitmap; PNG: TPngImage; X,Y,W,H,SX,SY: Integer; Row,SourceRow: PByte;
begin
  W := Max(1,Round(Source.Width*512.0/Max(Source.Width,Source.Height)));
  H := Max(1,Round(Source.Height*512.0/Max(Source.Width,Source.Height)));
  Bitmap := TBitmap.Create; PNG := TPngImage.Create;
  try
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(W,H); Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to H-1 do begin
      SY := Int64(Y)*Source.Height div H; SourceRow := Source.ScanLine[SY]; Row := Bitmap.ScanLine[Y];
      for X := 0 to W-1 do begin SX := Int64(X)*Source.Width div W; Move(SourceRow[SX*4],Row[X*4],4); end;
    end;
    PNG.Assign(Bitmap); PNG.SaveToFile(OutputPath);
  finally PNG.Free; Bitmap.Free; end;
end;

procedure CheckAsset(const SourcePath,OutputPath: string; Log: TStrings);
var Document: TMusicStudioLayerDocument; Bitmap: TBitmap;
    BeforeHash,AfterHash,ResultText: string; Started: UInt64;
begin
  // SourcePath is never passed to any save/import API.
  BeforeHash := THashSHA2.GetHashStringFromFile(SourcePath); Started := GetTickCount64;
  Document := TMusicStudioLayerDocument.Create; Bitmap := TBitmap.Create;
  try
    try
      if not Document.LoadFile(SourcePath) then ResultText := 'LOAD_UNSUPPORTED_OR_FAILED '+Document.LastError
      else begin
        Log.Add(Format('PSD_REAL_LOADED %s layers=%d canvas=%dx%d',[
          TPath.GetFileName(SourcePath),Length(Document.Layers),Document.Width,Document.Height]));
        if not Document.Render(Bitmap) then ResultText := 'COMPOSITE_UNSUPPORTED_OR_FAILED '+Document.LastError
        else begin SavePreview512(Bitmap,OutputPath); ResultText := 'RENDER_OK '+OutputPath; end;
      end;
    except on E: Exception do ResultText := 'ERROR '+E.ClassName+': '+E.Message; end;
  finally
    Bitmap.Free; Document.Free;
    AfterHash := THashSHA2.GetHashStringFromFile(SourcePath);
    Log.Add('PSD_REAL_RESULT '+TPath.GetFileName(SourcePath)+' '+ResultText);
    Log.Add('PSD_REAL_SHA256_BEFORE '+BeforeHash); Log.Add('PSD_REAL_SHA256_AFTER '+AfterHash);
    if not SameText(BeforeHash,AfterHash) then raise Exception.Create('実PSDのSHA256が変化しました: '+SourcePath);
    Log.Add(Format('PSD_REAL_SOURCE_UNCHANGED elapsedMs=%d',[GetTickCount64-Started]));
  end;
end;

procedure RunMusicStudioPsdRealAssetChecks(const Root: string);
var Folder,OutputRoot,FileName,Path: string; Paths: TArray<string>;
    Selected: TList<string>; Log: TStringList; I: Integer;
  procedure Prefer(const Name: string);
  var P: string;
  begin
    // Resolve an exact name from the observed direct-child inventory.
    for P in Paths do if SameText(TPath.GetFileName(P),Name) then begin Selected.Add(P); Exit; end;
  end;
begin
  Folder := TPath.Combine(DocumentsDirectory,'SYNC_MusicStudio\Characters\PSD');
  OutputRoot := TPath.GetFullPath(Root);
  if SameText(OutputRoot,Folder) or StartsText(IncludeTrailingPathDelimiter(Folder),IncludeTrailingPathDelimiter(OutputRoot)) then
    raise EArgumentException.Create('検証出力先に実PSDフォルダーは指定できません。');
  ForceDirectories(OutputRoot); Selected := TList<string>.Create; Log := TStringList.Create;
  try
    Log.Add('PSD_REAL_FOLDER '+Folder);
    if not TDirectory.Exists(Folder) then Log.Add('PSD_REAL_SKIPPED 実PSDフォルダーがありません。')
    else begin
      Paths := TDirectory.GetFiles(Folder,'*.psd',TSearchOption.soTopDirectoryOnly);
      TArray.Sort<string>(Paths);
      for Path in Paths do Log.Add('PSD_REAL_INVENTORY '+TPath.GetFileName(Path));
      Prefer(PREFERRED_KEYBOARD); Prefer(PREFERRED_DRUM);
      for Path in Paths do if Selected.Count<2 then
        if Selected.IndexOf(Path)<0 then Selected.Add(Path);
      if Selected.Count=0 then Log.Add('PSD_REAL_SKIPPED 実PSDがありません。');
      for I := 0 to Selected.Count-1 do begin
        FileName := 'psd-real-'+IntToStr(I+1)+'.png';
        CheckAsset(Selected[I],TPath.Combine(OutputRoot,FileName),Log);
      end;
    end;
    Log.Add('PSD_REAL_READONLY_CHECKS_COMPLETE (unsupported results are reported above)');
  finally
    try
      Log.SaveToFile(TPath.Combine(OutputRoot,'psd-real-assets.log'),TEncoding.UTF8);
      for Path in Log do Writeln(Path);
    finally Log.Free; Selected.Free; end;
  end;
end;

end.
