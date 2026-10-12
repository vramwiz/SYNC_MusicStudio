unit SYNC_MusicStudio_BitmapCache;
// UIスレッド所有の描画画像LRU。波形/ピアノロール/PSD縮小像が同じ仕組みを使う。
interface
uses System.Generics.Collections, Winapi.Windows, Vcl.Graphics;
type
  TMusicStudioCachedBitmap = class
    Bitmap: TBitmap;
    Stamp: UInt64;
    destructor Destroy; override;
  end;
  TMusicStudioBitmapCache = class
  private
    FItems: TObjectDictionary<string,TMusicStudioCachedBitmap>;
    FStamp: UInt64;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const Key: string): TBitmap;
    // Bitmapの所有権を引き取る。上限128個、最も古い画像を解放する。
    procedure Add(const Key: string; Bitmap: TBitmap);
    procedure Clear;
    function Count: Integer;
  end;
function MusicStudioFileStamp(const Path: string): string;
function MusicStudioPathKey(const Path: string): string;
function MusicStudioDoubleKey(Value: Double): string;
implementation
uses System.SysUtils;
function MusicStudioFileStamp(const Path: string): string;
var Data: TWin32FileAttributeData;
begin
  if (Path = '') or not GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Data) or
    ((Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then Exit('');
  Result := IntToHex(Data.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Data.ftLastWriteTime.dwLowDateTime,8)+
    IntToHex(Data.nFileSizeHigh,8)+IntToHex(Data.nFileSizeLow,8);
end;
function MusicStudioPathKey(const Path: string): string;
begin
  if Path = '' then Exit('');
  try Result := LowerCase(ExpandFileName(Path)); except Result := LowerCase(Path); end;
end;
function MusicStudioDoubleKey(Value: Double): string;
begin Result := IntToHex(PUInt64(@Value)^,16); end;
destructor TMusicStudioCachedBitmap.Destroy;
begin Bitmap.Free; inherited; end;
constructor TMusicStudioBitmapCache.Create;
begin inherited; FItems := TObjectDictionary<string,TMusicStudioCachedBitmap>.Create([doOwnsValues]); end;
destructor TMusicStudioBitmapCache.Destroy;
begin FItems.Free; inherited; end;
procedure TMusicStudioBitmapCache.Clear;
begin FItems.Clear; end;
function TMusicStudioBitmapCache.Count: Integer;
begin Result := FItems.Count; end;
function TMusicStudioBitmapCache.Find(const Key: string): TBitmap;
var Item: TMusicStudioCachedBitmap;
begin
  Result := nil; Inc(FStamp);
  if FItems.TryGetValue(Key,Item) then begin Item.Stamp := FStamp; Result := Item.Bitmap; end;
end;
procedure TMusicStudioBitmapCache.Add(const Key: string; Bitmap: TBitmap);
var Item,Oldest: TMusicStudioCachedBitmap; Pair: TPair<string,TMusicStudioCachedBitmap>; OldKey: string;
begin
  if FItems.ContainsKey(Key) then FItems.Remove(Key);
  if FItems.Count >= 128 then begin
    Oldest := nil; OldKey := '';
    for Pair in FItems do if (Oldest = nil) or (Pair.Value.Stamp < Oldest.Stamp) then begin Oldest := Pair.Value; OldKey := Pair.Key; end;
    FItems.Remove(OldKey);
  end;
  Item := TMusicStudioCachedBitmap.Create; Item.Bitmap := Bitmap; Inc(FStamp); Item.Stamp := FStamp;
  FItems.Add(Key,Item);
end;
end.
