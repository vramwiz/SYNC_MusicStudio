unit SYNC_MusicStudio_DrumPsdChecks;
// 命名規則に沿う合成PSDだけで解析・補完・複製・原本不変を検証。音声を使用しない。
interface
procedure RunDrumPsdChecks(const Root: string);
procedure InspectDrumPsd(const Root,Path: string);
implementation
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, Vcl.Graphics,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_DrumPsdRules;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('DRUM_PSD: '+Text); end;
procedure InspectDrumPsd(const Root,Path: string);
var D: TMusicStudioLayerDocument;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create;
  try
    Check(D.LoadFile(Path),D.LastError);
    TFile.WriteAllText(TPath.Combine(Root,'drum-psd-references.json'),D.DrumRules.DiagnosticJSON,TEncoding.UTF8);
    Writeln('DRUM_PSD_REFERENCES ',D.DrumRules.ReferenceCount,' ',TPath.Combine(Root,'drum-psd-references.json'));
  finally D.Free; end;
end;
procedure RunDrumPsdChecks(const Root: string);
var Doc: TArtDocument; Back,Character,Front,LA,RA,LL,RL,FX: TArtLayer;
  D,C: TMusicStudioLayerDocument; Bitmap: TBitmap; Rules: TMusicStudioDrumPsdRules;
  B: TDrumPsdBinding; R: TDrumPsdReference; Text,Path,Hash: string; I,Count: Integer;
  Layers: TArray<TDrumPsdLayer>; DuplicateRules: TMusicStudioDrumPsdRules;
  function Group(const Name: string; Parent: TArtLayer = nil): TArtLayer;
  begin Result := Doc.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,2,2),Parent); Result.Visible := True; end;
  procedure Image(const Name: string; Parent: TArtLayer);
  var Layer: TArtLayer; J: Integer;
  begin
    Layer := Doc.AddLayer(alkImage,Name,TArtBounds.Create(0,0,2,2),Parent);
    Layer.Visible := Name='BASE'; SetLength(Layer.Pixels,16);
    for J := 0 to 3 do begin Layer.Pixels[J*4] := 70; Layer.Pixels[J*4+1] := 120; Layer.Pixels[J*4+2] := 180; Layer.Pixels[J*4+3] := 255; end;
  end;
begin
  ForceDirectories(Root);
  Check(ParseDrumPsdLayerName('*SD_1',R) and R.Exclusive and (R.Prefix='*') and (R.Identifier='SD_1'),'legacy prefix');
  Check(ParseDrumPsdLayerName('SD_1*',R) and R.Exclusive and (R.Suffix='*') and (R.Identifier='SD_1'),'new suffix');
  Check(ParseDrumPsdLayerName('!H_9:flipx',R) and R.AlwaysVisible and (R.Stage=9) and (R.Suffix=':flipx'),'existing modifiers retained');
  Check(ParseDrumPsdLayerName('BASE',R) and R.IsBase and (R.Stage=-1),'provisional base');
  Check(ParseDrumPsdLayerName('SD_BASE',R) and R.IsBase and (R.Instrument='SD'),'instrument base');
  for Text in TArray<string>.Create('SD_10','sd_1','SD_1?',' SD_1','SD_1**','SD-1','ABCD_1','SD_1:unknown','BASE?') do
    Check(not ParseDrumPsdLayerName(Text,R),'invalid/unknown symbol accepted '+Text);
  SetLength(Layers,4);
  Layers[0].Key := 'a'; Layers[0].Name := 'Character'; Layers[0].IsGroup := True;
  Layers[1].Key := 'b'; Layers[1].Name := 'Character'; Layers[1].IsGroup := True;
  Layers[2].Key := 'la'; Layers[2].ParentKey := 'a'; Layers[2].Name := 'LA'; Layers[2].IsGroup := True;
  Layers[3].Key := 'sd'; Layers[3].ParentKey := 'la'; Layers[3].Name := 'SD_1';
  DuplicateRules := TMusicStudioDrumPsdRules.Create;
  try
    DuplicateRules.Build(Layers); B := DuplicateRules.Resolve('SD','LA',1);
    Check(B.State=dprAmbiguous,'duplicate root cannot bind silently');
  finally DuplicateRules.Free; end;
  Doc := TArtDocument.Create;
  try
    Doc.Width := 2; Doc.Height := 2;
    Back := Group('Back'); Character := Group('Character'); Front := Group('Front');
    LA := Group('LA',Character); RA := Group('RA',Character); LL := Group('LL',Character); RL := Group('RL',Character);
    Image('BASE',LA); Image('BASE',RA); Image('BASE',LL); Image('BASE',RL);
    Image('SD_0*',LA); Image('*SD_1',RA);
    Image('H_1*',LA); Image('HC_2',LA); Image('HO_1',RA); Image('HC_1',LL); Image('BD_1',RL);
    Image('T1_1',RA); Image('T1_1',RA); // 同じ親の二重定義は曖昧。反対腕へ隠れて補完しない。
    Image('T3_1',LA); Image('CM_2',LA);
    Image('SD_BASE',Back); Image('SD_1',Back); Image('SD_1',Front); Image('CR_9',Front); Image('RD_1',Front); Image('ST_1',RA);
    FX := Group('FX',Front); Image('SD_1',FX); Image('SD_1?',LA);
    Path := TPath.Combine(Root,'drum-naming.psd'); WriteNewPsd(Doc,Path,pcRaw);
  finally Doc.Free; end;
  Hash := THashSHA2.GetHashStringFromFile(Path); D := TMusicStudioLayerDocument.Create; Bitmap := TBitmap.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Rules := D.DrumRules; Check(Rules.HasDrumStructure,'structure detection');
    Check(Rules.AnalysisCount=1,'one load one analysis');
    B := Rules.ResolveCommand('SDL',1);
    Check((B.State=dprFallback) and (B.ActualPart='RA') and (B.RequestedPart='LA') and (B.CommandID='SDL'),'opposite arm records actual limb and original command');
    Check(Length(B.ReferenceIndices)=1,'one actual layer'); R := Rules.ReferenceAt(B.ReferenceIndices[0]);
    Check((R.Identifier='SD_1') and (R.Layer.Name='*SD_1') and D.HasLayer(R.Layer.Key),'stable real layer key');
    B.ReferenceIndices[0] := -1; B := Rules.ResolveCommand('SDL',1); Check(B.ReferenceIndices[0]>=0,'caller array cannot mutate bindings');
    B := Rules.Resolve('HO','LA',1); R := Rules.ReferenceAt(B.ReferenceIndices[0]);
    Check((B.State=dprFallback) and (B.ActualPart='LA') and (R.Instrument='H'),'same arm common beats opposite arm dedicated');
    B := Rules.Resolve('HO','LA',2); R := Rules.ReferenceAt(B.ReferenceIndices[0]); Check(R.Instrument='HC','hat close fallback');
    B := Rules.Resolve('HO','LL',1); R := Rules.ReferenceAt(B.ReferenceIndices[0]);
    Check((B.State=dprBase) and R.IsBase,'pedal does not inherit hand open/close fallback');
    B := Rules.Resolve('HC','LL',1); Check(B.State=dprDirect,'pedal held state has stage1 without requiring stage0/2');
    B := Rules.Resolve('T2','LA',2); R := Rules.ReferenceAt(B.ReferenceIndices[0]);
    Check((B.State=dprFallback) and (R.Instrument=DRUM_PSD_COMMON_ID),'provisional limb common');
    B := Rules.ResolveCommand('T1R',1); Check((B.State=dprAmbiguous) and (Length(B.ReferenceIndices)=0),'ambiguous duplicate rejected');
    B := Rules.ResolveCommand('T3R',1); Check((B.State=dprFallback) and (B.ActualPart='LA'),'right request left fallback');
    B := Rules.Resolve('SD','Back',2); R := Rules.ReferenceAt(B.ReferenceIndices[0]); Check((B.State=dprBase) and R.IsBase,'equipment base');
    B := Rules.Resolve('SD','Front',1); Check(Length(B.ReferenceIndices)=1,'body does not include effect reference');
    R := Rules.ReferenceAt(B.ReferenceIndices[0]); Check(R.TargetKind='instrument','body target kind');
    B := Rules.Resolve('CR','Front',9,'effect'); Check(B.State=dprBase,'effect cannot borrow body image');
    B := Rules.Resolve('SD','Front',1,'effect'); Check(Length(B.ReferenceIndices)=1,'front effect binding');
    R := Rules.ReferenceAt(B.ReferenceIndices[0]); Check((R.TargetKind='effect') and (R.RootGroup='Front'),'effect keeps hierarchy and target kind');
    B := Rules.Resolve('CR','Front',9); Check(B.State=dprDirect,'extended decay stages');
    Text := Rules.DiagnosticJSON; Check((Pos('ambiguous',Text)>0) and (Pos('SD_1?',Text)>0),'diagnostics');
    TFile.WriteAllText(TPath.Combine(Root,'drum-psd-references.json'),Text,TEncoding.UTF8);
    Count := Rules.ReferenceCount; C := D.Clone;
    try
      Check((C.DrumRules.ReferenceCount=Count) and (C.DrumRules.AnalysisCount=1),'clone copies compiled references');
      Check(C.HasLayer(C.DrumRules.ReferenceAt(0).Layer.Key),'clone key resolves into clone document');
      C.DrumRules.Clear; Check(D.DrumRules.ReferenceCount=Count,'clone lifetime independent');
    finally C.Free; end;
    for I := 0 to 1 do Check(D.Render(Bitmap),D.LastError);
    Check((Rules.AnalysisCount=1) and (Rules.ReferenceCount=Count),'render does not reparse PSD names');
    Check(Hash=THashSHA2.GetHashStringFromFile(Path),'source PSD unchanged');
    Check(not D.LoadFile(Path+'.missing.psd'),'missing PSD rejected'); Check(D.DrumRules.ReferenceCount=0,'failed reload clears old references');
    Check(D.LoadFile(Path),D.LastError); Check(D.DrumRules.AnalysisCount=2,'explicit reload reparses');
    Writeln('DRUM_PSD_NAMING_HIERARCHY_FLAGS_FALLBACK_ACTUAL_LIMB_BASE_AMBIGUITY_CLONE_NO_REPARSE_OK');
  finally Bitmap.Free; D.Free; end;
end;
end.
