// Owns a read-only decoded PSD. Keys describe complete paths and duplicate siblings.
// Rendering accepts visibility overrides, never changes or saves the source archive.
unit SYNC_MusicStudio_PsdLayers;

interface

uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  System.Types, Vcl.Graphics, SYNC_MusicStudio_ArtDocument;

type
  TMusicStudioLayerInfo = record
    Key, Name, Path, Group: string;
    Visible, IsGroup: Boolean;
    Bounds: TRect;
    SourceIndex: Integer;
  end;
  TMusicStudioLayerDocument = class
  private
    FDocument: TArtDocument;
    FFilePath, FLastError: string;
    FLayers: TArray<TMusicStudioLayerInfo>;
    FByKey: TDictionary<string,TArtLayer>;
    FParents: TDictionary<string,string>;
    FImages: TObjectDictionary<string,TBitmap>;
    FCacheBytes: Int64;
    FLoadCount, FRenderCount: Integer;
    procedure BuildLayers;
    procedure Clear;
    function GetLoaded: Boolean;
    function GetWidth: Integer;
    function GetHeight: Integer;
    function GetCacheCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    // Failed loads clear earlier decoded data, retaining an explanatory LastError.
    function LoadFile(const Path: string): Boolean;
    // Copies metadata and shares immutable channel arrays; safe for a worker's lifetime.
    function Clone: TMusicStudioLayerDocument;
    function HasLayer(const Key: string): Boolean;
    function LayerIndex(const Key: string): Integer;
    procedure RequireVisibleAncestors(Overrides: TJSONObject; const Key: string);
    // Honors PSDTool '*' exclusivity at the selected layer and every opened ancestor.
    procedure SelectLayerOverride(Overrides: TJSONObject; const Key: string);
    // Caller owns Target and Overrides. BGRA is premultiplied for VCL alpha drawing.
    function Render(Target: TBitmap; Overrides: TJSONObject = nil): Boolean;
    property Loaded: Boolean read GetLoaded;
    property FilePath: string read FFilePath;
    property LastError: string read FLastError;
    property Width: Integer read GetWidth;
    property Height: Integer read GetHeight;
    property Layers: TArray<TMusicStudioLayerInfo> read FLayers;
    property LoadCount: Integer read FLoadCount;
    property RenderCount: Integer read FRenderCount;
    property CacheCount: Integer read GetCacheCount;
  end;

procedure MusicStudioSetJsonBoolean(Obj: TJSONObject; const Key: string; Value: Boolean);

implementation

uses System.Math, SYNC_MusicStudio_ArtPsd;

const MAX_RENDER_CACHE_BYTES = Int64(64)*1024*1024;
  MAX_RENDER_CACHE_ITEMS = 8;

procedure MusicStudioSetJsonBoolean(Obj: TJSONObject; const Key: string; Value: Boolean);
var Pair: TJSONPair;
begin
  if Obj=nil then Exit;
  Pair := Obj.RemovePair(Key); Pair.Free;
  Obj.AddPair(Key,TJSONBool.Create(Value));
end;

constructor TMusicStudioLayerDocument.Create;
begin
  inherited;
  FByKey := TDictionary<string,TArtLayer>.Create;
  FParents := TDictionary<string,string>.Create;
  FImages := TObjectDictionary<string,TBitmap>.Create([doOwnsValues]);
end;

destructor TMusicStudioLayerDocument.Destroy;
begin
  Clear; FImages.Free; FParents.Free; FByKey.Free; inherited;
end;

procedure TMusicStudioLayerDocument.Clear;
begin
  FImages.Clear; FCacheBytes := 0; FByKey.Clear; FParents.Clear;
  FLayers := nil; FreeAndNil(FDocument); FLastError := '';
end;

function TMusicStudioLayerDocument.GetLoaded: Boolean;
begin Result := FDocument<>nil; end;
function TMusicStudioLayerDocument.GetWidth: Integer;
begin Result := 0; if Loaded then Result := FDocument.Width; end;
function TMusicStudioLayerDocument.GetHeight: Integer;
begin Result := 0; if Loaded then Result := FDocument.Height; end;
function TMusicStudioLayerDocument.GetCacheCount: Integer;
begin Result := FImages.Count; end;

procedure TMusicStudioLayerDocument.BuildLayers;
var Items: TList<TMusicStudioLayerInfo>;
  procedure Walk(List: TList<TArtLayer>; const ParentKey, ParentPath: string; Depth: Integer);
  var Ordinals: TDictionary<string,Integer>; Layer: TArtLayer;
      Info: TMusicStudioLayerInfo; Ordinal: Integer;
  begin
    if Depth>128 then raise EArtFormat.Create('PSDの階層が深すぎます。');
    Ordinals := TDictionary<string,Integer>.Create;
    try
      for Layer in List do begin
        if Layer.Kind=alkDivider then Continue;
        if not Ordinals.TryGetValue(Layer.Name,Ordinal) then Ordinal := 0;
        Inc(Ordinal); Ordinals.AddOrSetValue(Layer.Name,Ordinal);
        Info := Default(TMusicStudioLayerInfo);
        Info.Key := ParentKey+'/'+IntToStr(Length(Layer.Name))+':'+Layer.Name+'#'+IntToStr(Ordinal);
        Info.Name := Layer.Name; Info.Path := ParentPath+'/'+Layer.Name;
        Info.Group := ParentPath; Info.Visible := Layer.Visible;
        Info.IsGroup := Layer.Kind=alkGroup; Info.SourceIndex := Layer.SourceIndex;
        Info.Bounds := Rect(Layer.Bounds.Left,Layer.Bounds.Top,Layer.Bounds.Right,Layer.Bounds.Bottom);
        Items.Add(Info); FByKey.Add(Info.Key,Layer); FParents.Add(Info.Key,ParentKey);
        Walk(Layer.Children,Info.Key,Info.Path,Depth+1);
      end;
    finally Ordinals.Free; end;
  end;
begin
  FByKey.Clear; FParents.Clear; Items := TList<TMusicStudioLayerInfo>.Create;
  try Walk(FDocument.Roots,'','',0); FLayers := Items.ToArray;
  finally Items.Free; end;
end;

function TMusicStudioLayerDocument.LoadFile(const Path: string): Boolean;
begin
  Clear; FFilePath := Path; Result := False;
  try
    if Trim(Path)='' then raise EArtFormat.Create('PSDが未選択です。');
    if not FileExists(Path) then raise EArtFormat.Create('PSDの参照ファイルが見つかりません。');
    if not SameText(ExtractFileExt(Path),'.psd') then raise EArtFormat.Create('PSDファイルを指定してください。');
    Inc(FLoadCount); FDocument := ReadPsd(Path); BuildLayers; Result := True;
  except on E: Exception do begin
    FLastError := E.Message; FImages.Clear; FByKey.Clear; FParents.Clear;
    FLayers := nil; FreeAndNil(FDocument);
  end; end;
end;

function TMusicStudioLayerDocument.Clone: TMusicStudioLayerDocument;
begin
  Result := TMusicStudioLayerDocument.Create;
  try
    Result.FFilePath := FFilePath; Result.FLastError := FLastError;
    if Loaded then begin Result.FDocument := FDocument.Clone; Result.BuildLayers; end;
  except Result.Free; raise; end;
end;

function TMusicStudioLayerDocument.HasLayer(const Key: string): Boolean;
begin Result := FByKey.ContainsKey(Key); end;
function TMusicStudioLayerDocument.LayerIndex(const Key: string): Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to High(FLayers) do if FLayers[I].Key=Key then Exit(I);
end;

procedure TMusicStudioLayerDocument.RequireVisibleAncestors(Overrides: TJSONObject; const Key: string);
var Parent, NextParent: string;
begin
  if (Overrides=nil) or not HasLayer(Key) then Exit;
  Parent := Key;
  while Parent<>'' do begin
    MusicStudioSetJsonBoolean(Overrides,Parent,True);
    if not FParents.TryGetValue(Parent,NextParent) then Break;
    Parent := NextParent;
  end;
end;

procedure TMusicStudioLayerDocument.SelectLayerOverride(Overrides: TJSONObject; const Key: string);
var Layer: TArtLayer; Current,Parent,SiblingParent: string; Info: TMusicStudioLayerInfo;
begin
  if (Overrides=nil) or not HasLayer(Key) then Exit;
  Current := Key;
  while Current<>'' do begin
    if not FByKey.TryGetValue(Current,Layer) or not FParents.TryGetValue(Current,Parent) then Break;
    if (Layer.Name<>'') and (Layer.Name[1]='*') then
      for Info in FLayers do
        if (Info.Key<>Current) and (Info.Name<>'') and (Info.Name[1]='*') and
           FParents.TryGetValue(Info.Key,SiblingParent) and (SiblingParent=Parent) then
          MusicStudioSetJsonBoolean(Overrides,Info.Key,False);
    MusicStudioSetJsonBoolean(Overrides,Current,True);
    Current := Parent;
  end;
end;

function TMusicStudioLayerDocument.Render(Target: TBitmap; Overrides: TJSONObject): Boolean;
var Key: string; Cache: TBitmap; Snapshot: TMusicStudioLayerDocument;
    Info: TMusicStudioLayerInfo; Value: TJSONValue; Layer: TArtLayer;
    Pixels: TBytes; Row: PByte; X,Y,P,A: Integer;
begin
  Result := False; FLastError := '';
  if Target=nil then begin FLastError := '表示先がありません。'; Exit; end;
  if not Loaded then begin FLastError := 'PSDが読み込まれていません。'; Exit; end;
  Snapshot := nil; Cache := nil;
  try
    Key := '';
    for Info in FLayers do begin
      Value := nil; if Overrides<>nil then Value := Overrides.GetValue(Info.Key);
      if (Value<>nil) and not (Value is TJSONBool) then
        raise EArtFormat.Create('PSDレイヤーの表示設定が不正です。');
      if Value=nil then begin if Info.Visible then Key := Key+'1' else Key := Key+'0'; end
      else if TJSONBool(Value).AsBoolean then Key := Key+'1' else Key := Key+'0';
    end;
    if FImages.TryGetValue(Key,Cache) then begin Target.Assign(Cache); Exit(True); end;
    Snapshot := Clone;
    for X := 0 to High(FLayers) do begin
      Layer := Snapshot.FByKey[FLayers[X].Key]; Layer.Visible := Key[X+1]='1';
    end;
    Inc(FRenderCount); Pixels := RenderPsdLayers(Snapshot.FDocument);
    Cache := TBitmap.Create; Cache.PixelFormat := pf32bit;
    Cache.SetSize(Width,Height); Cache.AlphaFormat := afPremultiplied;
    for Y := 0 to Height-1 do begin
      Row := Cache.ScanLine[Y];
      for X := 0 to Width-1 do begin
        P := (Y*Width+X)*4; A := Pixels[P+3];
        Row[X*4] := (Integer(Pixels[P+2])*A+127) div 255;
        Row[X*4+1] := (Integer(Pixels[P+1])*A+127) div 255;
        Row[X*4+2] := (Integer(Pixels[P])*A+127) div 255;
        Row[X*4+3] := A;
      end;
    end;
    Target.Assign(Cache);
    if (FImages.Count>=MAX_RENDER_CACHE_ITEMS) or
       (FCacheBytes+Int64(Width)*Height*4>MAX_RENDER_CACHE_BYTES) then begin
      FImages.Clear; FCacheBytes := 0;
    end;
    if Int64(Width)*Height*4<=MAX_RENDER_CACHE_BYTES then begin
      FImages.Add(Key,Cache); Inc(FCacheBytes,Int64(Width)*Height*4); Cache := nil;
    end;
    Result := True;
  except on E: Exception do FLastError := E.Message; end;
  Snapshot.Free;
  // A borrowed cached entry belongs to FImages; only newly generated images reach here.
  Cache.Free;
end;

end.
