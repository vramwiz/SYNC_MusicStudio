program BuildInstrumentPsd;
{$APPTYPE CONSOLE}

// Production-asset helper using AIArtToPSD's original reader, writer,
// compositor and exclusive-selection code. Source RGBA and full canvases
// are preserved; this program performs no trimming or image generation.
uses
  System.SysUtils, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections, ArtDocument, ArtPng, ArtPsd, ArtParts;

function S(O: TJSONObject; const Key: string): string;
begin
  Result := '';
  if O.GetValue(Key) <> nil then Result := O.GetValue(Key).Value;
end;

function Hash(const Data: TBytes): string;
var H: THashSHA2;
begin
  H := THashSHA2.Create; H.Update(Data); Result := LowerCase(H.HashAsString);
end;

function FindPath(D: TArtDocument; const Path: string): TArtLayer;
var List: TList<TArtLayer>; Match: TArtLayer;
begin
  List := D.Roots; Result := nil;
  for var Name in Path.Split(['/']) do begin
    Match := nil;
    for var L in List do
      if L.Name = Name then begin
        if Match <> nil then raise Exception.Create('Ambiguous path: '+Path);
        Match := L;
      end;
    if Match = nil then raise Exception.Create('Missing path: '+Path);
    Result := Match; List := Match.Children;
  end;
end;

procedure Run(const ConfigName: string);
var C,O,Report,Row: TJSONObject; Definitions,States,LayerRows,StateRows: TJSONArray;
    D,R: TArtDocument; L,Parent,Reloaded,Selected: TArtLayer;
    Map: TDictionary<string,TArtLayer>; Paths: TDictionary<string,string>;
    Im: TArtPngData; OutDir,PsdName,Key,Path,ParentKey: string;
    Pixels,Expected: TBytes; VisibleCount: Integer;
begin
  C := TJSONObject.ParseJSONValue(TFile.ReadAllText(ConfigName,TEncoding.UTF8)) as TJSONObject;
  if C = nil then raise Exception.Create('Invalid config');
  D := TArtDocument.Create; Map := TDictionary<string,TArtLayer>.Create;
  Paths := TDictionary<string,string>.Create; Report := TJSONObject.Create;
  try
    D.Width := StrToInt(S(C,'width')); D.Height := StrToInt(S(C,'height'));
    OutDir := S(C,'output'); ForceDirectories(OutDir);
    ForceDirectories(TPath.Combine(OutDir,'previews'));
    PsdName := TPath.Combine(OutDir,'assembled.psd');
    if TFile.Exists(PsdName) then raise Exception.Create('Existing PSD: '+PsdName);
    Definitions := C.GetValue('layers') as TJSONArray;
    States := C.GetValue('states') as TJSONArray;
    LayerRows := TJSONArray.Create; Report.AddPair('layers',LayerRows);
    for var V in Definitions do begin
      O := V as TJSONObject; Key := S(O,'key'); ParentKey := S(O,'parent');
      Parent := nil; Path := S(O,'name');
      if ParentKey <> '' then begin Parent := Map[ParentKey]; Path := Paths[ParentKey]+'/'+Path; end;
      if S(O,'file') = '' then
        L := D.AddLayer(alkGroup,S(O,'name'),TArtBounds.Create(0,0,0,0),Parent)
      else begin
        Im := ReadPng(S(O,'file'));
        if (Im.Width<>D.Width) or (Im.Height<>D.Height) then
          raise Exception.Create('Source canvas differs: '+S(O,'file'));
        L := D.AddLayer(alkImage,S(O,'name'),TArtBounds.Create(0,0,D.Width,D.Height),Parent);
        L.Pixels := Im.Pixels;
      end;
      L.Visible := O.GetValue('visible') is TJSONTrue;
      Map.Add(Key,L); Paths.Add(Key,Path);
      Row := TJSONObject.Create; Row.AddPair('key',Key); Row.AddPair('path',Path);
      Row.AddPair('rgba_sha256',Hash(L.Pixels));
      Row.AddPair('visible',TJSONBool.Create(L.Visible));
      LayerRows.AddElement(Row);
    end;
    ValidateExclusiveSelections(D);
    WriteNewPsd(D,PsdName,pcRle);
    R := ReadPsd(PsdName);
    try
      if (D.Width<>R.Width) or (D.Height<>R.Height) then raise Exception.Create('Saved canvas mismatch');
      for var V in Definitions do begin
        O := V as TJSONObject; L := Map[S(O,'key')]; Reloaded := FindPath(R,Paths[S(O,'key')]);
        if (Hash(L.Pixels)<>Hash(Reloaded.Pixels)) or (L.Kind<>Reloaded.Kind) or
          (L.Visible<>Reloaded.Visible) or (L.Opacity<>Reloaded.Opacity) or
          (L.Bounds.Left<>Reloaded.Bounds.Left) or (L.Bounds.Top<>Reloaded.Bounds.Top) or
          (L.Bounds.Right<>Reloaded.Bounds.Right) or (L.Bounds.Bottom<>Reloaded.Bounds.Bottom) then
          raise Exception.Create('Saved layer mismatch: '+Paths[S(O,'key')]);
      end;
      Pixels := RenderPsdLayers(R);
      if Hash(Pixels)<>Hash(D.RenderRGBA) then raise Exception.Create('Saved composite mismatch');
    finally R.Free; end;
    StateRows := TJSONArray.Create; Report.AddPair('states',StateRows);
    for var V in States do begin
      O := V as TJSONObject; R := ReadPsd(PsdName);
      try
        Selected := FindPath(R,Paths[S(O,'key')]); SelectExclusive(R,Selected);
        ValidateExclusiveSelections(R); VisibleCount := 0;
        Parent := FindPath(R,Paths['poses']);
        for var Child in Parent.Children do if Child.Visible then Inc(VisibleCount);
        if VisibleCount<>1 then raise Exception.Create('Pose exclusivity failed');
        Pixels := RenderPsdLayers(R);
        // An independent two-layer document verifies there are no accidental
        // backgrounds, duplicated gear or leaked alternative body layers.
        var Pair := TArtDocument.Create;
        try
          Pair.Width := D.Width; Pair.Height := D.Height;
          L := Pair.AddLayer(alkImage,'head',TArtBounds.Create(0,0,D.Width,D.Height));
          L.Pixels := Copy(Map['head'].Pixels);
          L := Pair.AddLayer(alkImage,'body',TArtBounds.Create(0,0,D.Width,D.Height));
          L.Pixels := Copy(Map[S(O,'key')].Pixels);
          Expected := Pair.RenderRGBA;
          if Hash(Pixels)<>Hash(Expected) then raise Exception.Create('Pose composite mismatch');
        finally Pair.Free; end;
        Path := TPath.Combine(OutDir,'previews/'+S(O,'id')+'.png');
        WriteRgbaPng(Path,D.Width,D.Height,Pixels);
        Row := TJSONObject.Create; Row.AddPair('id',S(O,'id'));
        Row.AddPair('path',Paths[S(O,'key')]); Row.AddPair('rgba_sha256',Hash(Pixels));
        Row.AddPair('visible_pose_count',TJSONNumber.Create(VisibleCount));
        Row.AddPair('source_head_body_composite_equal',TJSONTrue.Create);
        StateRows.AddElement(Row);
      finally R.Free; end;
    end;
    Report.AddPair('psd',PsdName); Report.AddPair('passed',TJSONTrue.Create);
    Report.AddPair('source_pixels_bounds_visibility_roundtrip_equal',TJSONTrue.Create);
    Report.AddPair('pose_count',TJSONNumber.Create(States.Count));
    Report.AddPair('layer_count',TJSONNumber.Create(Definitions.Count));
    TFile.WriteAllText(TPath.Combine(OutDir,'native-verification.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln('PASS: ',States.Count,' poses, ',Definitions.Count,' layers; ',PsdName);
  finally
    Report.Free; Paths.Free; Map.Free; D.Free; C.Free;
  end;
end;

begin
  try
    if ParamCount<>1 then raise Exception.Create('Usage: BuildInstrumentPsd CONFIG.json');
    Run(TPath.GetFullPath(ParamStr(1)));
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
