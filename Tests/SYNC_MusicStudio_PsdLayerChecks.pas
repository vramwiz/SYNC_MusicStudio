// Silent PSD-only checks: fixture write/read, real layer composition, mapping and VCL lifetime.
// No audio decoder, playback engine, MIDI player or waveOut unit is referenced.
unit SYNC_MusicStudio_PsdLayerChecks;

interface

procedure RunMusicStudioPsdLayerChecks(const OutputDir: string; RunUI: Boolean = True);

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.Types,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig,
  SYNC_MusicStudio_PsdLayerJobs, SYNC_MusicStudio_PsdLayersFrame;

procedure Check(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create('PSD layers: '+Message); end;

procedure CheckExpressionInput(Frame: TMusicStudioPsdLayersFrame; const Key: string);
var I,X: Integer; R: TRect; Before: string;
begin
  Check(Frame.UIControls.LayerList.CheckMode,'expression visibility controls absent');
  Check(Frame.SelectLayer(Key),'expression target missing'); I := Frame.Document.LayerIndex(Key);
  Frame.UIControls.LayerList.TopIndex := I; R := Frame.UIControls.LayerList.ItemRect(I);
  X := MulDiv(18,Abs(Frame.UIControls.LayerList.Font.Height),13); Before := Frame.ConfigJSON;
  Frame.UIControls.LayerList.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(X,(R.Top+R.Bottom) div 2));
  Frame.UIControls.LayerList.Perform(WM_LBUTTONUP,0,MakeLParam(X,(R.Top+R.Bottom) div 2));
  Check(not Frame.UIControls.LayerList.Checked[I] and (Before<>Frame.ConfigJSON),'expression click did not disable visibility');
  Frame.UIControls.LayerList.Perform(WM_KEYDOWN,VK_SPACE,0);
  Check(Frame.UIControls.LayerList.Checked[I],'expression Space did not enable visibility');
end;

function AddImage(Doc: TArtDocument; Parent: TArtLayer; const Name: string;
  X,Y,W,H: Integer; R,G,B,A: Byte; Visible: Boolean): TArtLayer;
var I: Integer;
begin
  Result := Doc.AddLayer(alkImage,Name,TArtBounds.Create(X,Y,X+W,Y+H),Parent);
  Result.Visible := Visible; SetLength(Result.Pixels,PixelByteCount(W,H,4));
  for I := 0 to W*H-1 do begin
    Result.Pixels[I*4] := R; Result.Pixels[I*4+1] := G;
    Result.Pixels[I*4+2] := B; Result.Pixels[I*4+3] := A;
  end;
end;

procedure WriteFixtures(const Dir: string);
var D: TArtDocument; Face,Mouth: TArtLayer; Data: TBytes; I: Integer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 64; D.Height := 40;
    Face := D.AddLayer(alkGroup,'!顔',TArtBounds.Create(0,0,20,40));
    Mouth := D.AddLayer(alkGroup,'口/表情',TArtBounds.Create(4,8,12,14),Face);
    AddImage(D,Mouth,'*通常',4,8,8,6,0,255,0,255,True);
    AddImage(D,Mouth,'*あ',4,8,8,6,255,0,0,255,False);
    AddImage(D,Mouth,'*い',4,8,8,6,0,0,255,255,False);
    AddImage(D,nil,'同名',24,0,4,4,255,255,0,255,True);
    AddImage(D,nil,'同名',32,0,4,4,0,255,255,255,True);
    AddImage(D,nil,'半透明',56,4,4,4,255,255,255,128,True);
    WriteNewPsd(D,TPath.Combine(Dir,'psd-layers-raw.psd'),pcRaw);
    WriteNewPsd(D,TPath.Combine(Dir,'psd-layers-rle.psd'),pcRle);
  finally D.Free; end;
  Data := TFile.ReadAllBytes(TPath.Combine(Dir,'psd-layers-raw.psd'));
  Data[5] := 2; TFile.WriteAllBytes(TPath.Combine(Dir,'psd-layers-unsupported.psd'),Data);
  Data := TFile.ReadAllBytes(TPath.Combine(Dir,'psd-layers-raw.psd'));
  Data[18] := 0; Data[19] := 0; Data[20] := $75; Data[21] := $31;
  TFile.WriteAllBytes(TPath.Combine(Dir,'psd-layers-huge.psd'),Data);
  Data := TFile.ReadAllBytes(TPath.Combine(Dir,'psd-layers-raw.psd'));
  for I := 26 to High(Data)-3 do
    if (Data[I]=Ord('n')) and (Data[I+1]=Ord('o')) and (Data[I+2]=Ord('r')) and (Data[I+3]=Ord('m')) then begin
      Data[I] := Ord('s'); Data[I+1] := Ord('c'); Data[I+2] := Ord('r'); Data[I+3] := Ord('n'); Break;
    end;
  TFile.WriteAllBytes(TPath.Combine(Dir,'psd-layers-unsupported-blend.psd'),Data);
  TFile.WriteAllText(TPath.Combine(Dir,'psd-layers-broken.psd'),'broken',TEncoding.UTF8);
end;

function FindKey(Doc: TMusicStudioLayerDocument; const Name: string; Ordinal: Integer = 1): string;
var Info: TMusicStudioLayerInfo; Count: Integer;
begin
  Result := ''; Count := 0;
  for Info in Doc.Layers do if Info.Name=Name then begin Inc(Count); if Count=Ordinal then Exit(Info.Key); end;
end;

procedure PixelCheck(Image: TBitmap; X,Y: Integer; R,G,B,A: Byte; const Message: string);
var Row: PByte;
begin
  Row := Image.ScanLine[Y];
  Check((Row[X*4]=B) and (Row[X*4+1]=G) and (Row[X*4+2]=R) and (Row[X*4+3]=A),Message);
end;

procedure AdapterChecks(const Dir: string);
var D,E: TMusicStudioLayerDocument; Image: TBitmap; Config,Overrides: TJSONObject;
    Closed,AKey,IKey,Duplicate1,Duplicate2,Before: string; I,Count: Integer;
begin
  D := TMusicStudioLayerDocument.Create; E := TMusicStudioLayerDocument.Create;
  Image := TBitmap.Create; Config := ParseMusicStudioPsdConfig('{"future":{"keep":true},"mouthLayers":{"o":"missing-layer"},"visibility":{"missing-visibility":false}}');
  try
    Check(D.LoadFile(TPath.Combine(Dir,'psd-layers-raw.psd')),D.LastError);
    Check(E.LoadFile(TPath.Combine(Dir,'psd-layers-rle.psd')),E.LastError);
    Closed := FindKey(D,'*通常'); AKey := FindKey(D,'*あ'); IKey := FindKey(D,'*い');
    Check((Closed<>'') and (AKey<>'') and (IKey<>''),'layer names were not enumerated');
    Duplicate1 := FindKey(D,'同名',1); Duplicate2 := FindKey(D,'同名',2);
    Check((Duplicate1<>Duplicate2) and (Duplicate1<>'') and (Duplicate2<>''),'duplicate sibling identities');
    Check(E.HasLayer(AKey) and E.HasLayer(Duplicate2),'keys unstable between raw/rle reads');
    Check(D.Render(Image),D.LastError); PixelCheck(Image,5,9,0,255,0,255,'normal layer');
    PixelCheck(Image,57,5,128,128,128,128,'premultiplied transparency');
    MusicStudioAssignMouth(Config,0,Closed); MusicStudioAssignMouth(Config,1,AKey); MusicStudioAssignMouth(Config,2,IKey);
    Overrides := BuildMusicStudioPsdOverrides(D,Config,1);
    try Check(D.Render(Image,Overrides),D.LastError); PixelCheck(Image,5,9,255,0,0,255,'assigned a layer');
      Count := D.RenderCount;
      for I := 1 to 100 do Check(D.Render(Image,Overrides),'cached rendering');
      Check((D.RenderCount=Count) and (D.LoadCount=1),'paint regenerated/decoded source');
    finally Overrides.Free; end;
    Overrides := BuildMusicStudioPsdOverrides(D,Config,8);
    try Check(D.Render(Image,Overrides),D.LastError); PixelCheck(Image,5,9,0,0,255,255,'small i fallback');
    finally Overrides.Free; end;
    Check(Config.GetValue('future')<>nil,'unknown configuration lost');
    Check(MusicStudioMouthLayer(Config,5)='missing-layer','missing layer assignment lost');
    Before := THashSHA2.GetHashStringFromFile(TPath.Combine(Dir,'psd-layers-raw.psd'));
    E.Free; E := D.Clone; Check(E.HasLayer(AKey),'snapshot keys');
    Check(E.Render(Image),E.LastError); Check(E.LoadCount=0,'snapshot reopened source');
    Check(Before=THashSHA2.GetHashStringFromFile(TPath.Combine(Dir,'psd-layers-raw.psd')),'source PSD was written');
    Check(not E.LoadFile(TPath.Combine(Dir,'psd-layers-unsupported.psd')),'PSD v2 accepted');
    Check(not E.Loaded and (E.LastError<>''),'unsupported retained earlier image');
    Check(not E.LoadFile(TPath.Combine(Dir,'psd-layers-huge.psd')),'canvas bound limit');
    Check(not E.LoadFile(TPath.Combine(Dir,'psd-layers-broken.psd')),'broken PSD');
    Check(not E.LoadFile(TPath.Combine(Dir,'missing.psd')),'missing PSD');
    Check(not E.LoadFile(''),'unselected PSD');
    Check(E.LoadFile(TPath.Combine(Dir,'psd-layers-unsupported-blend.psd')),E.LastError);
    Check(not E.Render(Image) and (E.LastError<>''),'unsupported compositing shown as success');
  finally Config.Free; Image.Free; E.Free; D.Free; end;
  Writeln('PSD_LAYERS_ADAPTER_OK');
end;

procedure AwaitFrame(Frame: TMusicStudioPsdLayersFrame);
var Limit: UInt64;
begin
  Limit := GetTickCount64+15000;
  repeat
    Application.ProcessMessages; Frame.PollResults;
    if not Frame.IsLoading and not Frame.IsRendering then Exit;
    Sleep(5);
  until GetTickCount64>=Limit;
  raise Exception.Create('PSD layer UI timed out');
end;

procedure SaveForm(Form: TForm; const Path: string);
var Image: TBitmap; PNG: TPngImage;
begin
  Image := Form.GetFormImage; PNG := TPngImage.Create;
  try PNG.Assign(Image); PNG.SaveToFile(Path); finally PNG.Free; Image.Free; end;
end;

procedure ToolbarCheck(Frame: TMusicStudioPsdLayersFrame);
var I: Integer; Control: TControl;
begin
  Check(IsWindowVisible(GetParentForm(Frame).Handle),'test form native hidden');
  Check(IsWindowVisible(Frame.Handle),'frame native hidden');
  Check(Frame.UIControls.Toolbar.Visible and IsWindowVisible(Frame.UIControls.Toolbar.Handle),'toolbar native hidden');
  for I := 0 to Frame.UIControls.Toolbar.ControlCount-1 do begin
    Control := Frame.UIControls.Toolbar.Controls[I];
    Check(Control.Parent=Frame.UIControls.Toolbar,'toolbar child parent');
    Check(Control.Visible,'toolbar child invisible');
    Check((Control.Top>=0) and (Control.Top+Control.Height<=Frame.UIControls.Toolbar.ClientHeight),'toolbar child clipped');
    if Control is TWinControl then Check(IsWindowVisible(TWinControl(Control).Handle),'toolbar native child hidden');
  end;
  Writeln('PSD_LAYER_TOOLBAR_OK');
end;

procedure SaveClient(Form: TForm; const Path: string);
var Image: TBitmap; PNG: TPngImage; DC: HDC;
begin
  Form.BringToFront; Form.Update; Application.ProcessMessages;
  Image := TBitmap.Create; PNG := TPngImage.Create;
  try
    Image.SetSize(Form.ClientWidth,Form.ClientHeight); DC := GetDC(Form.Handle);
    try Check(BitBlt(Image.Canvas.Handle,0,0,Image.Width,Image.Height,DC,0,0,SRCCOPY),'client capture failed');
    finally ReleaseDC(Form.Handle,DC); end;
    PNG.Assign(Image); PNG.SaveToFile(Path);
  finally PNG.Free; Image.Free; end;
end;

procedure FrameChecks(const Dir: string);
var Form: TForm; Frame: TMusicStudioPsdLayersFrame; Config: TJSONObject;
    Raw,AKey,IKey,Saved: string; I,Count: Integer; L: TMusicStudioPsdLayerLoadJob;
    R: TMusicStudioPsdLayerRenderJob; D: TMusicStudioLayerDocument;
begin
  Raw := TPath.Combine(Dir,'psd-layers-raw.psd'); Form := TForm.CreateNew(nil);
  try
    Form.ClientWidth := 760; Form.ClientHeight := 440;
    Frame := TMusicStudioPsdLayersFrame.Create(Form); Frame.Parent := Form; Frame.Align := alClient;
    Form.Show;
    // The background console host inherits STARTUPINFO SW_HIDE. Windows consumes
    // it on the first Form.Show; show this isolated UI test form explicitly.
    Winapi.Windows.ShowWindow(Form.Handle,SW_SHOWNOACTIVATE);
    Check(IsWindowVisible(Form.Handle),'test form native hidden after explicit show');
    Frame.LoadPSD(Raw,'{"future":"keep"}'); AwaitFrame(Frame);
    Check((Frame.Document<>nil) and (Frame.PreviewBitmap<>nil),Frame.StateText);
    AKey := FindKey(Frame.Document,'*あ'); IKey := FindKey(Frame.Document,'*い');
    Check(Frame.SelectLayer(AKey),'select a'); Frame.AssignSelectedMouth(1); AwaitFrame(Frame);
    PixelCheck(Frame.PreviewBitmap,5,9,255,0,0,255,'UI mouth a');
    Check(Frame.SelectLayer(IKey),'select i'); Frame.AssignSelectedMouth(2); AwaitFrame(Frame);
    Frame.SelectMouth(1); AwaitFrame(Frame); PixelCheck(Frame.PreviewBitmap,5,9,255,0,0,255,'UI cached a');
    ToolbarCheck(Frame);
    Count := Frame.PreviewRenderCount;
    for I := 1 to 100 do begin Frame.UIControls.Preview.Repaint; Frame.PollResults; end;
    Check(Frame.PreviewRenderCount=Count,'UI paint recomposed PSD');
    Saved := Frame.ConfigJSON; Config := ParseMusicStudioPsdConfig(Saved);
    try Check(Config.GetValue('future').Value='keep','UI unknown config'); Check(MusicStudioMouthLayer(Config,1)=AKey,'UI assignment save');
    finally Config.Free; end;
    SaveForm(Form,TPath.Combine(Dir,'psd-layers-mouth.png'));
    SaveClient(Form,TPath.Combine(Dir,'psd-layers-mouth-client.png'));
    Frame.LoadPSD(Raw,Saved,True); AwaitFrame(Frame);
    Check(Frame.SetLayerVisibility(AKey,True),'expression visibility');
    Check(Frame.SetLayerVisibility(IKey,False),'expression visibility off'); AwaitFrame(Frame);
    SaveForm(Form,TPath.Combine(Dir,'psd-layers-expression.png'));
    Form.ClientWidth := 500; Form.ClientHeight := 370;
    SaveForm(Form,TPath.Combine(Dir,'psd-layers-minimum.png'));
    Form.ScaleForPPI(144); Form.ClientWidth := 950; Form.ClientHeight := 640;
    CheckExpressionInput(Frame,AKey); AwaitFrame(Frame);
    PixelCheck(Frame.PreviewBitmap,5,9,255,0,0,255,'expression checkbox/Space at 144DPI');
    SaveForm(Form,TPath.Combine(Dir,'psd-layers-144dpi.png'));
    Frame.LoadPSD(TPath.Combine(Dir,'psd-layers-broken.psd'),Saved);
    Frame.LoadPSD(Raw,Saved); Frame.LoadPSD(Raw,Saved); AwaitFrame(Frame);
    Check((Frame.Document<>nil) and (Frame.Document.FilePath=Raw),'stale completion after reload');
    Frame.LoadPSD(Raw,Saved); Frame.CancelLoad; AwaitFrame(Frame);
    Check(Frame.Document=nil,'cancelled load published result');
    Frame.LoadPSD('',Saved); Check(not Frame.IsLoading,'unselected creates job');
    Frame.LoadPSD(Raw,'broken-json'); Check(not Frame.CanApply,'invalid config accepted');
    Frame.LoadPSD(Raw,Saved); AwaitFrame(Frame);
    Frame.LoadPSD(Raw,Saved); // Form destruction drains this pending worker without queued callbacks.
  finally Form.Free; end;
  L := TMusicStudioPsdLayerLoadJob.Create(Raw,1); L.Free; // Never-started worker lifetime.
  D := TMusicStudioLayerDocument.Create;
  try Check(D.LoadFile(Raw),D.LastError); R := TMusicStudioPsdLayerRenderJob.Create(D,nil,1); R.Free;
  finally D.Free; end;
  Writeln('PSD_LAYERS_SILENT_UI_OK');
end;

procedure RunMusicStudioPsdLayerChecks(const OutputDir: string; RunUI: Boolean);
begin
  ForceDirectories(OutputDir); WriteFixtures(OutputDir); AdapterChecks(OutputDir);
  if RunUI then FrameChecks(OutputDir);
  Writeln('PSD_LAYERS_CHECKS_OK');
end;

end.
