unit SYNC_MusicStudio_LibraryThumbnails;

// 左一覧は共有VisualCacheへ可視行を要求するだけ。Paintにファイル読込/合成を持ち込まない。
// 行番号をworkerへ渡さず、PSDパス・共有revision・設定内容とsource世代で結果を照合する。
interface
uses System.Classes, System.Types, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  SYNC_MusicStudio_LibraryData, SYNC_MusicStudio_VisualCache;
type
  TMusicStudioLibraryThumbnails = class
  private
    FList: TListBox;
    FCache: TMusicStudioVisualCache;
    FItems: TArray<TMusicStudioLibraryItem>;
    FTimer: TTimer;
    FRoot,FMetadataStamp: string;
    FLastCheck: UInt64;
    FSerial,FTop,FHeight,FPPI,FCacheHits: Integer;
    FOnMetadataChange: TNotifyEvent;
    procedure Tick(Sender: TObject);
    function MetadataStamp: string;
    procedure SyncRequests;
  public
    constructor Create(List: TListBox; Cache: TMusicStudioVisualCache);
    destructor Destroy; override;
    procedure Bind(const Items: TArray<TMusicStudioLibraryItem>; const LibraryRoot: string);
    function ThumbnailRect(const ItemRect: TRect): TRect;
    procedure Draw(Canvas: TCanvas; Index: Integer; const ItemRect: TRect; Background: TColor);
    property CacheHits: Integer read FCacheHits;
    property OnMetadataChange: TNotifyEvent read FOnMetadataChange write FOnMetadataChange;
  end;
implementation
uses System.SysUtils, System.Math, System.Hash, Winapi.Windows,
  SYNC_MusicStudio_BitmapCache;

constructor TMusicStudioLibraryThumbnails.Create(List: TListBox; Cache: TMusicStudioVisualCache);
begin
  inherited Create; FList := List; FCache := Cache; FTop := -1; FPPI := -1;
  FTimer := TTimer.Create(nil); FTimer.Interval := 80; FTimer.OnTimer := Tick;
end;
destructor TMusicStudioLibraryThumbnails.Destroy;
begin
  FTimer.Enabled := False; FTimer.Free; FOnMetadataChange := nil;
  FCache.SetLibrarySources(nil); inherited;
end;
function TMusicStudioLibraryThumbnails.MetadataStamp: string;
var Item: TMusicStudioLibraryItem;
begin
  Result := '';
  for Item in FItems do if (Item.Pattern.Kind='psd') or (Item.Pattern.Kind='emotion') then begin
    // A managed PSD can disappear/reappear without any asset.json revision change.
    // Watch even initially missing sources: their visible requests are suppressed until this rebind.
    Result := Result+'|'+Item.Pattern.ID+':'+MusicStudioFileStamp(Item.Pattern.FilePath);
    if Item.Pattern.AssetID<>'' then Result := Result+':'+
      MusicStudioFileStamp(IncludeTrailingPathDelimiter(FRoot)+Item.Pattern.AssetID+'\asset.json');
  end;
end;
procedure TMusicStudioLibraryThumbnails.Bind(const Items: TArray<TMusicStudioLibraryItem>; const LibraryRoot: string);
var I: Integer;
begin
  FItems := Copy(Items); FRoot := LibraryRoot;
  for I := 0 to High(FItems) do if (FItems[I].Pattern.Kind='psd') and (FItems[I].PsdVersion='') then
    FItems[I].PsdVersion := 'local:'+THashSHA2.GetHashString(FItems[I].Pattern.ConfigJSON);
  for I := 0 to High(FItems) do if (FItems[I].Pattern.Kind='psd') and (FItems[I].ThumbnailConfigJSON='') then
    FItems[I].ThumbnailConfigJSON := FItems[I].Pattern.ConfigJSON;
  FMetadataStamp := MetadataStamp; FLastCheck := GetTickCount64;
  SyncRequests; FList.Invalidate;
end;
procedure TMusicStudioLibraryThumbnails.SyncRequests;
var Requests: TArray<TMusicStudioVisualRequest>; Request: TMusicStudioVisualRequest;
  I,LastVisible,N: Integer;
begin
  FTop := FList.TopIndex; FHeight := FList.ClientHeight; FPPI := FList.CurrentPPI;
  FList.ItemHeight := MulDiv(58,FPPI,96);
  LastVisible := FTop+Ceil(FHeight/Max(1,FList.ItemHeight));
  Requests := nil;
  for I := 0 to High(FItems) do if (FItems[I].Pattern.Kind='psd') or (FItems[I].Pattern.Kind='emotion') then begin
    Request := Default(TMusicStudioVisualRequest);
    Request.Kind := vkPsd; Request.Path := FItems[I].Pattern.FilePath;
    Request.PsdVersion := FItems[I].PsdVersion; Request.ConfigJSON := FItems[I].ThumbnailConfigJSON;
    Request.ExpressionJSON := FItems[I].ExpressionJSON;
    Request.Visible := (I>=Max(0,FTop-1)) and (I<=LastVisible+1) and not FItems[I].Missing;
    N := Length(Requests); SetLength(Requests,N+1); Requests[N] := Request;
  end;
  FCache.SetLibrarySources(Requests);
end;
procedure TMusicStudioLibraryThumbnails.Tick(Sender: TObject);
var Stamp: string;
begin
  if (FTop<>FList.TopIndex) or (FHeight<>FList.ClientHeight) or (FPPI<>FList.CurrentPPI) then SyncRequests;
  if GetTickCount64-FLastCheck>=1000 then begin
    FLastCheck := GetTickCount64; Stamp := MetadataStamp;
    if Stamp<>FMetadataStamp then begin
      FMetadataStamp := Stamp;
      if Assigned(FOnMetadataChange) then FOnMetadataChange(Self);
    end;
  end;
  if FSerial<>FCache.Serial then begin FSerial := FCache.Serial; FList.Invalidate; end;
end;
function TMusicStudioLibraryThumbnails.ThumbnailRect(const ItemRect: TRect): TRect;
var P,Size: Integer;
begin
  P := FList.CurrentPPI; Size := MulDiv(46,P,96);
  Result := Rect(ItemRect.Left+MulDiv(20,P,96),ItemRect.Top+(ItemRect.Height-Size) div 2,
    ItemRect.Left+MulDiv(20,P,96)+Size,ItemRect.Top+(ItemRect.Height+Size) div 2);
end;
procedure TMusicStudioLibraryThumbnails.Draw(Canvas: TCanvas; Index: Integer;
  const ItemRect: TRect; Background: TColor);
var Area: TRect; Source: TMusicStudioVisualSource; Image: Vcl.Graphics.TBitmap; Text: string;
begin
  if (Index<0) or (Index>=Length(FItems)) then Exit;
  if (FItems[Index].Pattern.Kind<>'psd') and (FItems[Index].Pattern.Kind<>'emotion') then Exit;
  Area := ThumbnailRect(ItemRect); Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := Background; Canvas.FillRect(Area);
  Source := FCache.Find(vkPsd,FItems[Index].Pattern.FilePath,FItems[Index].PsdVersion);
  Image := nil;
  if not FItems[Index].Missing then Image := FCache.Thumbnail(Source,Area.Width,Area.Height,FList.CurrentPPI,Background);
  if Assigned(Image) then begin Inc(FCacheHits); Canvas.Draw(Area.Left,Area.Top,Image); end
  else begin
    Text := '…';
    if FItems[Index].Missing then Text := '?'
    else if (Source<>nil) and Source.Visible and not Source.PsdAdmitted and (Source.Status=vsPending) then Text := 'PSD'
    else if Source<>nil then case Source.Status of vsMissing,vsBroken: Text := '?'; vsUnselected: Text := 'PSD'; end;
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := $009A9A9A;
    DrawText(Canvas.Handle,PChar(Text),Length(Text),Area,DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;
end;
end.
