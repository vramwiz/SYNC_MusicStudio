unit SYNC_MusicStudio_PsdDisplayChecks;
// PSD追加情報と実設定画面の合成/再選択/開き直しを無音・隔離rootで検証する。
interface
procedure RunPsdDisplayChecks(const Root: string; const ActualPSD: string = '');
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PsdLayersFrame, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_TestHelpers;
procedure Check(B: Boolean; const M: string);
begin if not B then raise Exception.Create('PSD display: '+M); end;
function U32(const Data: TBytes; P: Integer): Cardinal;
begin
  Check((P>=0) and (P+4<=Length(Data)),'fixture u32 bounds');
  Result := (Cardinal(Data[P]) shl 24) or (Cardinal(Data[P+1]) shl 16) or (Cardinal(Data[P+2]) shl 8) or Data[P+3];
end;
procedure PutU32(var Data: TBytes; P: Integer; V: Cardinal);
begin
  Data[P] := Byte(V shr 24); Data[P+1] := Byte((V shr 16) and $FF);
  Data[P+2] := Byte((V shr 8) and $FF); Data[P+3] := Byte(V and $FF);
end;
procedure AddFixtureTag(const Source,Target: string; const Key: AnsiString; Value: Byte);
var Data,ResultData: TBytes; MaskP,InfoP,RecordP,ExtraP,InsertP,Channels,I: Integer;
begin
  // テスト生成PSDの最初のレイヤーに正規の16B追加情報を挿入。各境界長も更新する。
  Data := TFile.ReadAllBytes(Source); Check(Length(Key)=4,'fixture tag key');
  MaskP := 26+4+Integer(U32(Data,26)); MaskP := MaskP+4+Integer(U32(Data,MaskP));
  InfoP := MaskP+4; RecordP := InfoP+4+2;
  Channels := (Integer(Data[RecordP+16]) shl 8) or Data[RecordP+17];
  ExtraP := RecordP+18+Channels*6+12; InsertP := ExtraP+4+Integer(U32(Data,ExtraP));
  Check((InsertP>=ExtraP+4) and (InsertP<Length(Data)),'fixture extra boundary');
  SetLength(ResultData,Length(Data)+16); Move(Data[0],ResultData[0],InsertP);
  ResultData[InsertP] := Ord('8'); ResultData[InsertP+1] := Ord('B');
  ResultData[InsertP+2] := Ord('I'); ResultData[InsertP+3] := Ord('M');
  for I := 1 to 4 do ResultData[InsertP+3+I] := Ord(Key[I]);
  PutU32(ResultData,InsertP+8,4); ResultData[InsertP+12] := Value;
  Move(Data[InsertP],ResultData[InsertP+16],Length(Data)-InsertP);
  PutU32(ResultData,ExtraP,U32(Data,ExtraP)+16); PutU32(ResultData,InfoP,U32(Data,InfoP)+16);
  PutU32(ResultData,MaskP,U32(Data,MaskP)+16); TFile.WriteAllBytes(Target,ResultData);
end;
procedure WriteGroupFixture(const Path: string);
var D: TArtDocument; G,L: TArtLayer; I: Integer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 3; D.Height := 1;
    G := D.AddLayer(alkGroup,'group',TArtBounds.Create(0,0,0,0)); G.BlendKey := 'norm';
    L := D.AddLayer(alkImage,'image',TArtBounds.Create(0,0,3,1),G);
    SetLength(L.Pixels,12);
    for I := 0 to 2 do begin L.Pixels[I*4] := 200; L.Pixels[I*4+1] := 100;
      L.Pixels[I*4+2] := 50; L.Pixels[I*4+3] := 255; end;
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
procedure AddGroupMaskFixture(const Source,Target: string; PassThrough,MissingChannel: Boolean);
var Data,OutData: TBytes; MaskP,InfoP,RecordP,ExtraP,ExtraLen,Count,Channels,I,LastRecord,LastExtra,StreamP,N,P: Integer;
begin
  // Add a real -2 mask channel to the last record (the folder) in this generated PSD.
  Data := TFile.ReadAllBytes(Source); MaskP := 26+4+Integer(U32(Data,26));
  MaskP := MaskP+4+Integer(U32(Data,MaskP)); InfoP := MaskP+4; RecordP := InfoP+6;
  Count := (Integer(Data[InfoP+4]) shl 8) or Data[InfoP+5]; if Count>32767 then Count := 65536-Count;
  N := 0; LastRecord := 0; LastExtra := 0;
  for I := 0 to Count-1 do begin
    Channels := (Integer(Data[RecordP+16]) shl 8) or Data[RecordP+17];
    for P := 0 to Channels-1 do Inc(N,Integer(U32(Data,RecordP+20+P*6)));
    ExtraP := RecordP+18+Channels*6+12; ExtraLen := Integer(U32(Data,ExtraP));
    LastRecord := RecordP; LastExtra := ExtraP; RecordP := ExtraP+4+ExtraLen;
  end;
  Check((LastRecord>0) and (U32(Data,LastExtra+4)=0),'generated group has no initial mask');
  Check((Data[LastRecord+16]=0) and (Data[LastRecord+17]=0),'generated folder channel count');
  StreamP := RecordP+N; Check(StreamP=InfoP+4+Integer(U32(Data,InfoP)),'generated channel boundary');
  // 6B channel descriptor + 20B mask data + 4B raw mask plane.
  SetLength(OutData,Length(Data)+30); Move(Data[0],OutData[0],LastRecord+18);
  OutData[LastRecord+17] := 1;
  if not MissingChannel then begin OutData[LastRecord+18] := $FF; OutData[LastRecord+19] := $FE; end;
  PutU32(OutData,LastRecord+20,4);
  Move(Data[LastRecord+18],OutData[LastRecord+24],LastExtra+8-(LastRecord+18));
  P := LastExtra+6; PutU32(OutData,P,U32(Data,LastExtra)+20); PutU32(OutData,P+4,20);
  // Mask rectangle x=1..3, y=0..1; outside default=0, coverage=[128,255].
  PutU32(OutData,P+8,0); PutU32(OutData,P+12,1); PutU32(OutData,P+16,1); PutU32(OutData,P+20,3);
  Move(Data[LastExtra+8],OutData[LastExtra+34],StreamP-(LastExtra+8));
  OutData[StreamP+28] := 128; OutData[StreamP+29] := 255;
  Move(Data[StreamP],OutData[StreamP+30],Length(Data)-StreamP);
  PutU32(OutData,InfoP,U32(Data,InfoP)+30); PutU32(OutData,MaskP,U32(Data,MaskP)+30);
  if PassThrough then begin P := LastRecord+22+6;
    OutData[P] := Ord('p'); OutData[P+1] := Ord('a'); OutData[P+2] := Ord('s'); OutData[P+3] := Ord('s'); end;
  TFile.WriteAllBytes(Target,OutData);
end;
procedure CompositeChecks(const Dir: string);
var D: TArtDocument; G,L,Base: TArtLayer; Pixels: TBytes; GroupPath,DividerPath,MaskPath,PassPath,MissingPath: string;
begin
  D := TArtDocument.Create;
  try
    D.Width := 1; D.Height := 1;
    L := D.AddLayer(alkImage,'multiply',TArtBounds.Create(0,0,1,1)); L.BlendKey := 'mul ';
    L.Pixels := TBytes.Create(128,128,128,255);
    Base := D.AddLayer(alkImage,'base',TArtBounds.Create(0,0,1,1)); Base.Pixels := TBytes.Create(200,100,50,255);
    Pixels := D.RenderRGBA; Check((Pixels[0]=100) and (Pixels[1]=50) and (Pixels[2]=25) and (Pixels[3]=255),'opaque multiply result');
    L.Pixels := TBytes.Create(128,128,128,128); Base.Pixels := TBytes.Create(200,100,50,128);
    Pixels := D.RenderRGBA;
    Check((Pixels[0]=143) and (Pixels[1]=93) and (Pixels[2]=68) and (Pixels[3]=192),'semi-transparent source/backdrop multiply');
    Base.Visible := False; Pixels := D.RenderRGBA;
    Check((Pixels[0]=128) and (Pixels[1]=128) and (Pixels[2]=128) and (Pixels[3]=128),'multiply over transparent background');
  finally D.Free; end;
  GroupPath := TPath.Combine(Dir,'group.psd'); DividerPath := TPath.Combine(Dir,'divider-tsly.psd');
  MaskPath := TPath.Combine(Dir,'group-mask.psd'); PassPath := TPath.Combine(Dir,'group-mask-pass.psd');
  MissingPath := TPath.Combine(Dir,'group-mask-missing.psd'); WriteGroupFixture(GroupPath);
  AddFixtureTag(GroupPath,DividerPath,'tsly',0);
  D := ReadPsd(DividerPath);
  try Pixels := RenderPsdLayers(D); Check((Pixels[0]=200) and (Pixels[3]=255),'divider tsly blocked image');
  finally D.Free; end;
  AddGroupMaskFixture(GroupPath,MaskPath,False,False);
  AddGroupMaskFixture(GroupPath,PassPath,True,False);
  AddGroupMaskFixture(GroupPath,MissingPath,False,True);
  D := ReadPsd(MaskPath);
  try
    G := D.Roots[0]; Check(G.HasMask and (Length(G.MaskPixels)=2),'group mask plane not decoded');
    Pixels := RenderPsdLayers(D); Check((Pixels[3]=0) and (Pixels[7]=128) and (Pixels[11]=255),'group mask coverage/default coordinates');
    G.MaskDisabled := True; Pixels := RenderPsdLayers(D); Check((Pixels[3]=255) and (Pixels[7]=255),'disabled group mask');
    G.MaskDisabled := False; G.MaskInvert := True; Pixels := RenderPsdLayers(D);
    Check((Pixels[3]=255) and (Pixels[7]=127) and (Pixels[11]=0),'inverted group mask');
    G.MaskInvert := False; G.Opacity := 128; Pixels := RenderPsdLayers(D); Check((Pixels[7]=64) and (Pixels[11]=128),'group opacity and mask');
  finally D.Free; end;
  D := ReadPsd(PassPath);
  try
    try RenderPsdLayers(D); Check(False,'masked pass-through silently accepted');
    except on E: EArtFormat do Check(Pos('Mask on non-isolated',E.Message)>0,E.Message); end;
  finally D.Free; end;
  try D := ReadPsd(MissingPath); D.Free; Check(False,'missing group mask channel accepted');
  except on E: EArtFormat do Check(Pos('Missing mask channel',E.Message)>0,E.Message); end;
  Writeln('PSD_DIVIDER_TSLY_MULTIPLY_ALPHA_ISOLATED_GROUP_MASK_AND_REJECTION_PIXELS_OK');
end;
procedure AwaitFrame(F: TMusicStudioPsdLayersFrame);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+30000;
  repeat
    Application.ProcessMessages; F.PollResults;
    if not F.IsLoading and not F.IsRendering then Exit;
    Sleep(5);
  until GetTickCount64>=Deadline;
  raise Exception.Create('PSD display frame timed out: '+F.StateText);
end;
procedure SaveClient(Form: TForm; const Path: string);
var B: TBitmap; P: TPngImage; DC: HDC;
begin
  Form.Update; Application.ProcessMessages; B := TBitmap.Create; P := TPngImage.Create;
  try
    B.SetSize(Form.ClientWidth,Form.ClientHeight); DC := GetDC(Form.Handle);
    try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'client capture');
    finally ReleaseDC(Form.Handle,DC); end;
    P.Assign(B); P.SaveToFile(Path);
  finally P.Free; B.Free; end;
end;
function OpaquePixels(B: TBitmap): Integer;
var X,Y: Integer; Row: PByte;
begin
  Result := 0;
  for Y := 0 to B.Height-1 do begin Row := B.ScanLine[Y];
    for X := 0 to B.Width-1 do if Row[X*4+3]>0 then Inc(Result);
  end;
end;
procedure CheckFrame(F: TMusicStudioPsdLayersFrame; const ManagedPath: string);
begin
  Check(F.FilePath=ManagedPath,'resolved managed path not bound');
  Check((F.Document<>nil) and (F.PreviewBitmap<>nil) and F.CanApply,F.StateText);
  Check(OpaquePixels(F.PreviewBitmap)>0,'composite contains only transparency');
  Check(F.UIControls.Preview.Visible and (F.UIControls.Preview.Width>20) and (F.UIControls.Preview.Height>20),'preview region absent');
  Check((F.UIControls.PathLabel.Top>=0) and (F.UIControls.PathLabel.Top+F.UIControls.PathLabel.Height<=F.UIControls.Header.ClientHeight),'path vertically clipped');
  Check(F.UIControls.PathLabel.Height>=Abs(F.UIControls.PathLabel.Font.Height)+4,'path text height too short');
  Check((F.UIControls.ReloadButton.Top>=F.UIControls.ClearButton.Top+F.UIControls.ClearButton.Height) or
    (F.UIControls.ReloadButton.Left>=F.UIControls.ClearButton.Left+F.UIControls.ClearButton.Width),
    'toolbar buttons overlap after DPI change');
end;
procedure CheckNativePaint(F: TMusicStudioPsdLayersFrame);
var X,Y,Count: Integer; DC: HDC; C: Cardinal;
begin
  // The buffered preview is now a native child window. Its parent's DC clips child pixels.
  Count := 0; DC := GetDC(F.UIControls.Preview.Handle);
  try
    for Y := 8 to F.UIControls.Preview.Height-9 do if Y mod 8=0 then
      for X := 8 to F.UIControls.Preview.Width-9 do if X mod 8=0 then begin
        C := GetPixel(DC,X,Y);
        Check(C<>CLR_INVALID,'native preview pixels unavailable');
        if (C<>$00303030) and (C<>$002A2A2A) then Inc(Count);
      end;
  finally ReleaseDC(F.UIControls.Preview.Handle,DC); end;
  Check(Count>20,'decoded PSD absent from native checker preview');
end;
procedure SettingsChecks(const Dir,Source: string; Fixture: Boolean);
var L: TMusicStudioSharedPsdLibrary; A: TMusicStudioPsdAsset; Pattern: TMusicStudioPattern;
  D: TMusicStudioPatternSettings; Error,SourceHash,ManagedHash: string; Dup: Boolean; I,Count: Integer;
  Position: TPoint; Work: TRect; DC: HDC; C: Cardinal;
begin
  SourceHash := THashSHA2.GetHashStringFromFile(Source);
  L := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'isolated-library'));
  try
    Check(L.TryImport(Source,'PSD表示確認','#CC8CE0',A,Dup,Error),Error);
    ManagedHash := THashSHA2.GetHashStringFromFile(A.FilePath);
    Pattern := Default(TMusicStudioPattern); Pattern.Kind := 'psd'; Pattern.AssetID := A.ID;
    Pattern.Name := A.Name; Pattern.Color := A.Color; Pattern.ConfigJSON := A.ConfigJSON;
    for I := 1 to 2 do begin
      D := TMusicStudioPatternSettings.Create(nil);
      try
        D.SilentVisualMode := True; D.LoadSharedPattern(Pattern,A.FilePath,A.ConfigJSON);
        D.Show; ShowWindow(D.Handle,SW_SHOWNOACTIVATE); AwaitFrame(D.LayersFrame); CheckFrame(D.LayersFrame,A.FilePath);
        Count := D.LayersFrame.PreviewRenderCount;
        D.LayersFrame.UIControls.Preview.Repaint; D.Update;
        SaveClient(D,TPath.Combine(Dir,'settings-reopen-'+IntToStr(I)+'.png'));
        CheckNativePaint(D.LayersFrame);
        if Fixture then begin
          Position := Point(D.LayersFrame.UIControls.Preview.Width div 2,D.LayersFrame.UIControls.Preview.Height div 2);
          DC := GetDC(D.LayersFrame.UIControls.Preview.Handle);
          try C := GetPixel(DC,Position.X,Position.Y); finally ReleaseDC(D.LayersFrame.UIControls.Preview.Handle,DC); end;
          Check(C=RGB(40,115,190),Format('bitmap decoded but not painted: actual=%x bitmap=%x at %d,%d preview=%d,%d %dx%d',
            [C,ColorToRGB(D.LayersFrame.PreviewBitmap.Canvas.Pixels[32,32]),Position.X,Position.Y,
             D.LayersFrame.UIControls.Preview.Left,D.LayersFrame.UIControls.Preview.Top,
             D.LayersFrame.UIControls.Preview.Width,D.LayersFrame.UIControls.Preview.Height]));
        end;
        D.ClientWidth := 900; D.ClientHeight := 650; D.Update; Application.ProcessMessages;
        CheckFrame(D.LayersFrame,A.FilePath); Check(D.LayersFrame.PreviewRenderCount=Count,'resize recomposed PSD');
        D.ScaleForPPI(144); D.Update; Application.ProcessMessages; CheckFrame(D.LayersFrame,A.FilePath);
        // Keep the entire native window on-screen; GetDC captures cannot read pixels outside the desktop.
        Work := D.Monitor.WorkareaRect; D.Position := poDesigned;
        D.Left := Work.Left+(Work.Width-D.Width) div 2; D.Top := Work.Top+(Work.Height-D.Height) div 2;
        D.Update; Application.ProcessMessages;
        SaveClient(D,TPath.Combine(Dir,'settings-dpi144-'+IntToStr(I)+'.png'));
        CheckNativePaint(D.LayersFrame);
        D.LayersFrame.LoadPSD(TPath.Combine(Dir,'missing.psd'),A.ConfigJSON); AwaitFrame(D.LayersFrame);
        Check((D.LayersFrame.Document=nil) and (D.LayersFrame.PreviewBitmap=nil) and not D.LayersFrame.CanApply,'missing selection kept earlier PSD');
        D.LayersFrame.LoadPSD(A.FilePath,A.ConfigJSON); AwaitFrame(D.LayersFrame); CheckFrame(D.LayersFrame,A.FilePath);
        D.ReadSharedPattern(Pattern);
      finally D.Free; end;
    end;
    Check((THashSHA2.GetHashStringFromFile(Source)=SourceHash) and (THashSHA2.GetHashStringFromFile(A.FilePath)=ManagedHash),'settings changed PSD bytes');
    Writeln('PSD_SETTINGS_MANAGED_BIND_RENDER_PAINT_REOPEN_RESELECT_RESIZE_DPI144_SOURCE_UNCHANGED_OK source=',Source);
  finally L.Free; end;
end;
procedure RunPsdDisplayChecks(const Root,ActualPSD: string);
var Dir,Raw,DefaultFlag,DisabledFlag,InvalidFlag,UnknownFlag: string; G: TGUID; D: TMusicStudioLayerDocument; B: TBitmap;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'psd-display-'+GUIDToString(G)); ForceDirectories(Dir);
  Raw := TPath.Combine(Dir,'original.psd'); WriteLayeredTestPSD(Raw);
  DefaultFlag := TPath.Combine(Dir,'tsly-default.psd'); DisabledFlag := TPath.Combine(Dir,'tsly-special.psd');
  InvalidFlag := TPath.Combine(Dir,'tsly-invalid.psd');
  UnknownFlag := TPath.Combine(Dir,'unknown-tag.psd');
  AddFixtureTag(Raw,DefaultFlag,'tsly',1); AddFixtureTag(Raw,DisabledFlag,'tsly',0); AddFixtureTag(Raw,InvalidFlag,'tsly',2);
  AddFixtureTag(Raw,UnknownFlag,'zzzz',0);
  CompositeChecks(Dir);
  D := TMusicStudioLayerDocument.Create; B := TBitmap.Create;
  try
    Check(D.LoadFile(DefaultFlag),D.LastError); Check(D.Render(B),'default tsly falsely rejected: '+D.LastError);
    Check(OpaquePixels(B)=64*64,'default tsly changed alpha');
    Check(D.LoadFile(DisabledFlag),D.LastError); Check(not D.Render(B) and (Pos('tsly',D.LastError)>0),'special tsly silently treated as supported');
    Check(not D.LoadFile(InvalidFlag) and (Pos('tsly',D.LastError)>0),'invalid tsly boolean accepted');
    Check(D.LoadFile(UnknownFlag),D.LastError);
    Check(not D.Render(B) and (Pos('zzzz',D.LastError)>0),'unknown tag silently ignored');
  finally B.Free; D.Free; end;
  SettingsChecks(Dir,DefaultFlag,True);
  if ActualPSD<>'' then SettingsChecks(TPath.Combine(Dir,'actual'),ActualPSD,False);
  Writeln('PSD_TSLY_DEFAULT_SUPPORTED_SPECIAL_AND_INVALID_REJECTED_SILENT_OK');
end;
end.
