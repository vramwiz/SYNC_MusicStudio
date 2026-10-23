unit SYNC_MusicStudio_LibraryData;

// スロット別の一覧。共有項目を閲覧しても作品JSONへ勝手に参照を追加しない。
interface
uses SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary;
type
  TMusicStudioLibraryItem = record
    Pattern: TMusicStudioPattern;
    PatternIndex: Integer; // -1: この作品では未使用の共有項目。
    Shared, Missing: Boolean;
    PsdVersion: string; // 共有revisionと設定内容。描画中にmetadataを読み直さない。
    ThumbnailConfigJSON, ExpressionJSON: string; // 基本PSDと表情は独立した値コピー。
  end;
function MusicStudioLibraryItems(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  const Kind, AssetID: string): TArray<TMusicStudioLibraryItem>; overload;
function MusicStudioLibraryItems(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  const Kinds: TArray<string>; const AssetID: string; const Attribute: string = ''): TArray<TMusicStudioLibraryItem>; overload;
function MusicStudioLibraryKinds(const Accepts: TArray<string>; const AssetID: string;
  AllowPsd: Boolean): TArray<string>;
function MusicStudioReferenceIndex(Document: TMusicStudioDocument; const Kind,AssetID,SharedID: string): Integer;
function MusicStudioEmotionItem(const Pattern: TMusicStudioPattern;
  const Assets: TArray<TMusicStudioPsdAsset>): TMusicStudioLibraryItem;
implementation
uses System.Generics.Collections, System.Hash, System.SysUtils, SYNC_MusicStudio_LayerStepData,
  SYNC_MusicStudio_PerformanceLibrary;
function MusicStudioLibraryKinds(const Accepts: TArray<string>; const AssetID: string;
  AllowPsd: Boolean): TArray<string>;
var Kind: string;
begin
  Result := nil;
  for Kind in Accepts do
    if (Kind='audio') or (Kind='singing') or (Kind='performance') or (Kind='tempo') or ((Kind='psd') and AllowPsd) or
      (((Kind='emotion') or (Kind='animation') or (Kind='instrument')) and (AssetID<>'')) then
      Result := Result+[Kind];
end;
function MusicStudioReferenceIndex(Document: TMusicStudioDocument; const Kind,AssetID,SharedID: string): Integer;
var I: Integer; P: TMusicStudioPattern;
begin
  for I := 0 to Document.PatternCount-1 do begin
    P := Document.PatternAt(I);
    if (P.Kind=Kind) and (P.AssetID=AssetID) and (P.SharedPatternID=SharedID) then Exit(I);
  end;
  Result := -1;
end;
function MusicStudioEmotionItem(const Pattern: TMusicStudioPattern;
  const Assets: TArray<TMusicStudioPsdAsset>): TMusicStudioLibraryItem;
var Asset: TMusicStudioPsdAsset; Preset: TMusicStudioSharedPattern; Found: Boolean;
begin
  Result := Default(TMusicStudioLibraryItem); Result.Pattern := Pattern;
  Result.Shared := Pattern.AssetID<>''; Result.Missing := True; Result.PatternIndex := -1;
  for Asset in Assets do if (Asset.ID=Pattern.AssetID) and (Pattern.Kind='emotion') then begin
    Result.Pattern.FilePath := Asset.FilePath; Result.ThumbnailConfigJSON := Asset.ConfigJSON;
    Result.ExpressionJSON := Pattern.ConfigJSON; Found := Pattern.SharedPatternID='';
    for Preset in Asset.Patterns do if (Preset.ID=Pattern.SharedPatternID) and (Preset.Kind='emotion') then begin
      Result.ExpressionJSON := Preset.ConfigJSON; Found := True; Break;
    end;
    Result.Missing := Asset.Missing or not Found;
    Result.PsdVersion := 'emotion:'+Asset.ID+':'+Asset.Revision+':'+Pattern.SharedPatternID+':'+
      THashSHA2.GetHashString(Asset.ConfigJSON+'|'+Result.ExpressionJSON);
    Exit;
  end;
  Result.PsdVersion := 'emotion-missing:'+Pattern.ID;
end;
function MusicStudioLibraryItems(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  const Kind,AssetID: string): TArray<TMusicStudioLibraryItem>;
begin
  if Kind='generic' then Result := MusicStudioLibraryItems(Document,Store,TArray<string>.Create('audio','singing','performance','tempo'),AssetID)
  else Result := MusicStudioLibraryItems(Document,Store,TArray<string>.Create(Kind),AssetID);
end;
function MusicStudioLibraryItems(Document: TMusicStudioDocument; Store: TMusicStudioSharedPsdLibrary;
  const Kinds: TArray<string>; const AssetID: string; const Attribute: string): TArray<TMusicStudioLibraryItem>;
var L: TList<TMusicStudioLibraryItem>; Item: TMusicStudioLibraryItem; A: TMusicStudioPsdAsset;
  SP: TMusicStudioSharedPattern; I: Integer; P: TMusicStudioPattern; Present: Boolean; Kind: string;
  Performance: TMusicStudioPerformanceLibrary;
  function Accepts(const Value: string): Boolean;
  var K: string;
  begin Result := False; for K in Kinds do if K=Value then Exit(True); end;
begin
  Result := nil; if Document=nil then Exit;
  L := TList<TMusicStudioLibraryItem>.Create;
  try
    if Accepts('performance') and (Attribute<>'') and (Store<>nil) then begin
      Performance := TMusicStudioPerformanceLibrary.Create(Store.Root);
      try
        for P in Performance.Patterns(Attribute) do begin
          Item := Default(TMusicStudioLibraryItem); Item.Pattern := P; Item.Shared := True; Item.PatternIndex := -1;
          for I := 0 to Document.PatternCount-1 do
            if (Document.PatternAt(I).Kind='performance') and (Document.PatternAt(I).SharedPatternID=P.SharedPatternID) and
              (Document.PatternAt(I).LibraryRevision=P.LibraryRevision) and (Document.PatternAt(I).PerformanceAttribute=Attribute) then Item.PatternIndex := I;
          L.Add(Item);
        end;
      finally Performance.Free; end;
    end;
    if Accepts('psd') and Assigned(Store) then for A in Store.Assets do begin
      Item := Default(TMusicStudioLibraryItem); Item.PatternIndex := MusicStudioReferenceIndex(Document,'psd',A.ID,'');
      Item.Shared := True; Item.Missing := A.Missing; Item.Pattern.Kind := 'psd'; Item.Pattern.AssetID := A.ID;
      Item.Pattern.ID := 'asset:'+A.ID; Item.Pattern.Name := A.Name; Item.Pattern.Color := A.Color;
      Item.PsdVersion := A.Revision+':'+THashSHA2.GetHashString(A.ConfigJSON);
      Item.Pattern.FilePath := A.FilePath; Item.Pattern.ConfigJSON := A.ConfigJSON;
      Item.ThumbnailConfigJSON := A.ConfigJSON; L.Add(Item);
    end;
    if Assigned(Store) and (AssetID<>'') then
      for A in Store.Assets do if A.ID=AssetID then for SP in A.Patterns do
        if Accepts(SP.Kind) and ((SP.Kind='emotion') or (SP.Kind='animation') or (SP.Kind='instrument')) then begin
        Item := Default(TMusicStudioLibraryItem); Item.PatternIndex := MusicStudioReferenceIndex(Document,SP.Kind,A.ID,SP.ID);
        Item.Shared := True; Item.Missing := A.Missing; Item.Pattern.Kind := SP.Kind; Item.Pattern.AssetID := A.ID;
        Item.Pattern.SharedPatternID := SP.ID; Item.Pattern.ID := 'shared:'+SP.ID; Item.Pattern.Name := SP.Name;
        Item.Pattern.Color := SP.Color; Item.Pattern.FilePath := A.FilePath; Item.Pattern.ConfigJSON := SP.ConfigJSON;
        if SP.Kind='emotion' then begin
          P := Item.Pattern; Item := MusicStudioEmotionItem(P,TArray<TMusicStudioPsdAsset>.Create(A));
          Item.PatternIndex := MusicStudioReferenceIndex(Document,SP.Kind,A.ID,SP.ID);
        end;
        L.Add(Item);
      end;
    // ローカルの音声/歌唱、共有欠損の既存参照を保持して表示する。
    for I := 0 to Document.PatternCount-1 do begin
      P := Document.PatternAt(I);
      Kind := P.Kind;
      if not Accepts(Kind) then Continue;
      if (Kind='performance') and (P.PerformanceAttribute<>'') then begin
        // 旧版snapshotは配置済み作品の再生用。正本一覧へ別項目として増やさない。
        Continue;
      end;
      if (Kind='performance') and (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>'') and
        (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>AssetID) then Continue;
      if ((Kind='emotion') or (Kind='animation') or (Kind='instrument')) and (P.AssetID<>AssetID) then Continue;
      Present := False;
      for Item in L do if Item.PatternIndex=I then begin Present := True; Break; end;
      if Present then Continue;
      Item := Default(TMusicStudioLibraryItem); Item.PatternIndex := I; Item.Pattern := P;
      Item.Shared := P.AssetID<>''; Item.Missing := Item.Shared; L.Add(Item);
    end;
    Result := L.ToArray;
  finally L.Free; end;
end;
end.
