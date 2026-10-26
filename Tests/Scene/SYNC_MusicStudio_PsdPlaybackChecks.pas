unit SYNC_MusicStudio_PsdPlaybackChecks;
// Integrated silent-clock playback: real MIDI/PSD scene requests, native paint and source lifetime.
interface
procedure RunPsdPlaybackChecks(const Root: string; const ActualPSD: string = ''; const SeedJSON: string = '');
implementation
uses System.SysUtils, System.Classes, System.Types, System.Math, System.IOUtils, System.Hash, System.JSON,
  Winapi.Windows, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_ArtDocument,
  SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_TestHelpers;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('PSD playback: '+Message); end;
procedure WritePSD(const Path: string; BrokenBlend: Boolean = False);
var D: TArtDocument; Mouth,L: TArtLayer; I,J: Integer; Bytes,Marker: TBytes; Found: Boolean;
  procedure Image(const Name: string; X,Y,W,H: Integer; R,G,B: Byte; Parent: TArtLayer; Visible: Boolean);
  var J: Integer;
  begin
    L := D.AddLayer(alkImage,Name,TArtBounds.Create(X,Y,X+W,Y+H),Parent); L.Visible := Visible;
    SetLength(L.Pixels,W*H*4);
    for J := 0 to W*H-1 do begin L.Pixels[J*4] := R; L.Pixels[J*4+1] := G; L.Pixels[J*4+2] := B; L.Pixels[J*4+3] := 255; end;
  end;
begin
  D := TArtDocument.Create;
  try
    D.Width := 160; D.Height := 120;
    Mouth := D.AddLayer(alkGroup,'mouth',TArtBounds.Create(0,0,0,0)); Mouth.BlendKey := 'norm';
    for I := 0 to 5 do Image('*shape'+IntToStr(I),70,60,20,12,Byte(30+I*35),Byte(230-I*25),Byte(40+I*30),Mouth,I=0);
    Image('body',0,0,160,120,45,70,90,nil,True);
    WriteNewPsd(D,Path,pcRaw);
    if BrokenBlend then begin
      // The PSD writer itself rejects unsupported composites. Mutate the isolated
      // fixture only after its valid flattened preview has been written.
      Bytes := TFile.ReadAllBytes(Path); Marker := TEncoding.ASCII.GetBytes('8BIMnorm'); Found := False;
      for I := 0 to Length(Bytes)-Length(Marker) do begin
        J := 0; while (J<Length(Marker)) and (Bytes[I+J]=Marker[J]) do Inc(J);
        if J=Length(Marker) then begin
          Bytes[I+4] := Ord('s'); Bytes[I+5] := Ord('c'); Bytes[I+6] := Ord('r'); Bytes[I+7] := Ord('n'); Found := True;
        end;
      end;
      Check(Found,'unsupported fixture blend signature absent'); TFile.WriteAllBytes(Path,Bytes);
    end;
  finally D.Free; end;
end;
procedure WriteMidi(const Path: string);
const Lyrics: array[0..4] of string = ('あ','い','う','え','お');
var Body,FileData: TMemoryStream; I: Integer; Bytes: TBytes;
  procedure ByteTo(S: TStream; Value: Byte);
  begin S.WriteBuffer(Value,1); end;
  procedure Four(S: TStream; Value: Cardinal);
  begin ByteTo(S,Byte(Value shr 24)); ByteTo(S,Byte((Value shr 16) and $FF)); ByteTo(S,Byte((Value shr 8) and $FF)); ByteTo(S,Byte(Value and $FF)); end;
begin
  Body := TMemoryStream.Create; FileData := TMemoryStream.Create;
  try
    for I := 0 to 39 do begin
      Bytes := TEncoding.UTF8.GetBytes(Lyrics[I mod 5]);
      ByteTo(Body,0); ByteTo(Body,$FF); ByteTo(Body,5); ByteTo(Body,Length(Bytes)); Body.WriteBuffer(Bytes[0],Length(Bytes));
      ByteTo(Body,0); ByteTo(Body,$90); ByteTo(Body,60); ByteTo(Body,100);
      ByteTo(Body,120); ByteTo(Body,$80); ByteTo(Body,60); ByteTo(Body,0);
    end;
    ByteTo(Body,0); ByteTo(Body,$FF); ByteTo(Body,$2F); ByteTo(Body,0);
    Four(FileData,$4D546864); Four(FileData,6); Four(FileData,1); ByteTo(FileData,1); ByteTo(FileData,$E0);
    Four(FileData,$4D54726B); Four(FileData,Body.Size); Body.Position := 0; FileData.CopyFrom(Body,Body.Size);
    FileData.SaveToFile(Path);
  finally FileData.Free; Body.Free; end;
end;
function KeyByName(D: TMusicStudioLayerDocument; const Name,Branch: string): string;
var Info: TMusicStudioLayerInfo;
begin
  Result := ''; for Info in D.Layers do if (Info.Name=Name) and ((Branch='') or (Pos(Branch,Info.Path)>0)) then Exit(Info.Key);
  raise Exception.Create('PSD playback layer not found: '+Name);
end;
function HashImage(B: TBitmap): string;
var Data: TBytes; Y: Integer; S: TBytesStream;
begin
  Check(B<>nil,'image missing'); SetLength(Data,B.Width*B.Height*4);
  for Y := 0 to B.Height-1 do Move(PByte(B.ScanLine[Y])^,Data[Y*B.Width*4],B.Width*4);
  S := TBytesStream.Create(Data); try Result := THashSHA2.GetHashString(S); finally S.Free; end;
end;
procedure SmallExpected(Full,Dest: TBitmap);
var X,Y,W,H: Integer; Factor: Double;
begin
  Factor := Min(1.0,512/Max(Full.Width,Full.Height)); W := Max(1,Round(Full.Width*Factor)); H := Max(1,Round(Full.Height*Factor));
  Dest.PixelFormat := pf32bit; Dest.SetSize(W,H); Dest.AlphaFormat := afPremultiplied;
  for Y := 0 to H-1 do for X := 0 to W-1 do
    PCardinal(NativeUInt(Dest.ScanLine[Y])+NativeUInt(X*4))^ := PCardinal(NativeUInt(Full.ScanLine[Int64(Y)*Full.Height div H])+NativeUInt(Int64(X)*Full.Width div W*4))^;
end;
procedure Capture(F: TFormMusicStudioSettings; const Path: string);
var B: TBitmap; PNG: TPngImage; DC: HDC;
begin
  F.Update; B := TBitmap.Create; PNG := TPngImage.Create;
  try
    B.SetSize(F.ClientWidth,F.ClientHeight); DC := GetDC(F.Handle);
    try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'native capture'); finally ReleaseDC(F.Handle,DC); end;
    PNG.Assign(B); PNG.SaveToFile(Path);
  finally PNG.Free; B.Free; end;
end;
procedure RunPsdPlaybackChecks(const Root,ActualPSD,SeedJSON: string);
var F: TFormMusicStudioSettings; Store: TMusicStudioSharedPsdLibrary; A,OtherAsset: TMusicStudioPsdAsset; Dup: Boolean;
    D: TMusicStudioLayerDocument; Config,Seed,Overrides: TJSONObject; Full: TBitmap; Images: array[0..5] of TBitmap;
    Keys,Hashes: array[0..5] of string; G: TGUID; Dir,Source,Midi,Error,Before,After,SourceHash,ManagedHash,MetadataHash,OldHash: string;
    Track,Singing,I,J,K,X,Y,StableX,StableY,Paints,Changes,BlankFrames: Integer; P: TMusicStudioPattern;
    PixelValue,NativeColor: Cardinal; Valid: Boolean; Start,Limit: UInt64; B: TBitmap; R: TRect; W,H: Integer; Scale: Double;
  procedure Poll;
  begin
    F.TimelineBox.VisualCache.Poll; F.Preview.SceneCache.PollResults; Application.ProcessMessages;
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio was started');
  end;
  procedure Await;
  begin
    Limit := GetTickCount64+10000;
    repeat
      Poll;
      if (F.Preview.SceneCache.ActiveLoadJobs=0) and (F.Preview.SceneCache.ActiveRenderJobs=0) and
        (F.TimelineBox.VisualCache.ActiveJobs=0) and (F.Preview.SceneCache.ImageForTrack(Track)<>nil) then Exit;
      Sleep(2);
    until GetTickCount64>Limit;
    Check(False,'scene timeout: '+F.Preview.SceneCache.StatusForTrack(Track));
  end;
  procedure CheckPaint;
  begin
    Inc(Paints); B := F.Preview.SceneCache.ImageForTrack(Track);
    if B=nil then Inc(BlankFrames);
    Check(B<>nil,'mouth transition published a background-only frame');
    F.Preview.Stage.Repaint;
    H := Max(1,F.Preview.Stage.Height-12); W := Min(F.Preview.Stage.Width-24,Round(H*16/9)); H := Round(W*9/16);
    R := Rect((F.Preview.Stage.Width-W) div 2+6,26,(F.Preview.Stage.Width+W) div 2-6,6+H-30);
    Scale := Min(R.Width/B.Width,R.Height/B.Height);
    X := R.Left+(R.Width-Round(B.Width*Scale)) div 2+Round((StableX+0.5)*Scale);
    Y := R.Top+Round((StableY+0.5)*Scale);
    NativeColor := ColorToRGB(F.Preview.Stage.Canvas.Pixels[X,Y]);
    Check(NativeColor=RGB(Byte(PixelValue shr 16),Byte(PixelValue shr 8),Byte(PixelValue)),'native playback paint lost stable body/hair pixel');
    After := HashImage(B); if After<>OldHash then begin Inc(Changes); OldHash := After; end;
  end;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'psd-playback-'+GUIDToString(G)); ForceDirectories(Dir);
  Source := ActualPSD; if Source='' then begin Source := TPath.Combine(Dir,'source.psd'); WritePSD(Source); end;
  SourceHash := THashSHA2.GetHashStringFromFile(Source); Midi := TPath.Combine(Dir,'vowels.mid'); WriteMidi(Midi);
  Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'isolated-library')); D := TMusicStudioLayerDocument.Create;
  F := nil; Config := nil; Seed := nil; Full := TBitmap.Create;
  for I := 0 to 5 do Images[I] := TBitmap.Create;
  try
    Check(Store.TryImport(Source,'再生母音検証','#CC8CE0',A,Dup,Error),Error); Check(D.LoadFile(A.FilePath),D.LastError);
    Config := ParseMusicStudioPsdConfig('');
    if SeedJSON<>'' then begin
      Seed := TJSONObject.ParseJSONValue(TFile.ReadAllText(SeedJSON,TEncoding.UTF8)) as TJSONObject;
      Config.Free; Config := ParseMusicStudioPsdConfig(Seed.GetValue('config').ToJSON);
    end;
    for I := 0 to 5 do begin
      if ActualPSD<>'' then begin
        After := '*00'; if I>0 then After := After+Char(Ord('a')+I-1); Keys[I] := KeyByName(D,After,'/口/');
      end else Keys[I] := KeyByName(D,'*shape'+IntToStr(I),'');
      MusicStudioAssignMouth(Config,I,Keys[I]);
    end;
    MusicStudioAssignMouth(Config,6,Keys[0]);
    A.ConfigJSON := Config.ToJSON; Check(Store.TrySave(A,Error),Error);
    ManagedHash := THashSHA2.GetHashStringFromFile(A.FilePath); MetadataHash := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(A.FilePath),'asset.json'));
    for I := 0 to 5 do begin
      Overrides := BuildMusicStudioPsdOverrides(D,Config,I);
      try Check(D.Render(Full,Overrides),D.LastError); SmallExpected(Full,Images[I]); Hashes[I] := HashImage(Images[I]); finally Overrides.Free; end;
    end;
    StableX := -1; StableY := -1;
    for Y := Images[0].Height div 5 to Images[0].Height*4 div 5 do begin
      for X := Images[0].Width div 5 to Images[0].Width*4 div 5 do begin
        PixelValue := PCardinal(NativeUInt(Images[0].ScanLine[Y])+NativeUInt(X*4))^; Valid := (PixelValue shr 24=255) and (PixelValue and $FFFFFF<>0);
        for I := 0 to 5 do for J := -3 to 3 do for K := -3 to 3 do
          Valid := Valid and (PCardinal(NativeUInt(Images[I].ScanLine[Y+J])+NativeUInt((X+K)*4))^=PixelValue);
        if Valid then begin StableX := X; StableY := Y; Break; end;
      end;
      if StableX>=0 then Break;
    end;
    Check(StableX>=0,'stable opaque body pixel absent');
    F := TFormMusicStudioSettings.Create(nil); F.SilentVisualMode := True; F.LibraryRoot := Store.Root; F.LoadDocument('');
    Track := F.Document.AddTrack('psd'); F.Document.AssignPsd(Track,A.ID);
    Singing := F.Document.AddSinging; P := F.Document.PatternAt(Singing); P.FilePath := Midi; P.SourceTrack := 0; P.Duration := 5; F.Document.UpdatePattern(P);
    Check(F.Document.AddPlacement(Track,TestSlotIndex(F.Document,Track,'singing'),P.ID,0,5,Error),Error);
    Check(F.Document.TrySave(Before,Error),Error); F.LoadDocument(Before);
    F.Show; ShowWindow(F.Handle,SW_SHOWNOACTIVATE); Await;
    Check(F.Preview.Stage.DoubleBuffered,'integrated stage buffering disabled');
    Paints := 0; Changes := 0; BlankFrames := 0; OldHash := ''; CheckPaint;
    F.Preview.Seek(0.18); CheckPaint; Await;
    Check(HashImage(F.Preview.SceneCache.ImageForTrack(Track))=Hashes[2],'seek displayed stale mouth');
    F.Preview.Seek(0.01); Await; F.Preview.PlayButton.Click; Start := GetTickCount64;
    repeat Poll; CheckPaint; Sleep(5); until GetTickCount64-Start>=1800;
    Check(F.Preview.IsPlaying and (F.Preview.Position>1.5),'silent playback clock did not advance');
    F.Preview.PlayButton.Click; Await; CheckPaint; Check(Changes>=6,'continuous playback did not update vowels');
    Capture(F,TPath.Combine(Dir,'integrated-playing-vowels.png'));
    for I := 0 to 29 do begin F.Preview.Seek((I mod 5)*0.125+0.02); CheckPaint; end;
    F.Preview.Seek(0.52); Await; Check(HashImage(F.Preview.SceneCache.ImageForTrack(Track))=Hashes[5],'rapid seeks rolled back to old vowel');
    F.Preview.StopButton.Click; CheckPaint; Await; Check(HashImage(F.Preview.SceneCache.ImageForTrack(Track))=Hashes[1],'stop did not return to beginning');
    F.Preview.PlayButton.Click; Start := GetTickCount64;
    repeat Poll; CheckPaint; Sleep(5); until GetTickCount64-Start>=400;
    F.Preview.Pause; Await; CheckPaint;
    // Invalidated sources and a different project must never keep a previous character indefinitely.
    After := TPath.Combine(Dir,'saved-managed.psd'); TFile.Copy(A.FilePath,After);
    TFile.WriteAllBytes(A.FilePath,TBytes.Create(1,2,3)); F.Preview.SceneCache.PollResults(True);
    Check(F.Preview.SceneCache.ImageForTrack(Track)=nil,'changed source kept previous character');
    Start := GetTickCount64; repeat Poll; Sleep(2); until (F.Preview.SceneCache.ActiveLoadJobs=0) or (GetTickCount64-Start>10000);
    Check((F.Preview.SceneCache.ImageForTrack(Track)=nil) and (F.Preview.SceneCache.StatusForTrack(Track)<>''),'broken source kept stale image');
    TFile.Copy(After,A.FilePath,True); F.Preview.SceneCache.PollResults(True); Await; CheckPaint;
    WritePSD(TPath.Combine(Dir,'unsupported.psd'),True);
    TFile.Copy(TPath.Combine(Dir,'unsupported.psd'),A.FilePath,True); F.Preview.SceneCache.PollResults(True);
    Start := GetTickCount64;
    repeat Poll; Sleep(2); until ((F.Preview.SceneCache.ActiveLoadJobs=0) and (F.Preview.SceneCache.ActiveRenderJobs=0)) or (GetTickCount64-Start>10000);
    Check((F.Preview.SceneCache.ImageForTrack(Track)=nil) and (F.Preview.SceneCache.StatusForTrack(Track)<>''),'render error retained previous image');
    TFile.Copy(TPath.Combine(Dir,'saved-managed.psd'),A.FilePath,True); F.Preview.SceneCache.PollResults(True); Await; CheckPaint;
    OldHash := HashImage(F.Preview.SceneCache.ImageForTrack(Track));
    F.LoadDocument(''); Check(F.Preview.ImageCount=0,'project switch retained previous character');
    WritePSD(TPath.Combine(Dir,'other-character.psd'));
    Check(F.SharedLibrary.TryImport(TPath.Combine(Dir,'other-character.psd'),'別キャラ','#90C4E0',OtherAsset,Dup,Error),Error);
    J := F.Document.AddTrack('psd'); F.Document.AssignPsd(J,OtherAsset.ID);
    Check(F.Document.TrySave(After,Error),Error); F.LoadDocument(After);
    Check(F.Preview.SceneCache.ImageForTrack(J)=nil,'another character inherited previous image'); Await;
    Check(HashImage(F.Preview.SceneCache.ImageForTrack(J))<>OldHash,'another character displayed wrong old frame');
    F.LoadDocument(Before); Await; CheckPaint; Capture(F,TPath.Combine(Dir,'integrated-reopened-vowels.png'));
    Check(F.Document.TrySave(After,Error) and (Before=After),'playback changed project JSON');
    Check(THashSHA2.GetHashStringFromFile(A.FilePath)=ManagedHash,'managed PSD bytes changed');
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(A.FilePath),'asset.json'))=MetadataHash,'playback changed shared config');
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'original PSD changed');
    Writeln('PSD_INTEGRATED_SILENT_PLAYBACK_VOWELS_CONTINUOUS_SEEK_STOP_RESUME_NATIVE_BODY_NO_BLANK_LATEST_SOURCE_ERROR_REOPEN_JSON_UNCHANGED_OK paints=',Paints,' changes=',Changes,' blank=',BlankFrames,' source=',Source);
    TFile.WriteAllText(TPath.Combine(Dir,'playback-metrics.json'),Format('{"paints":%d,"imageChanges":%d,"blankFrames":%d,"audioRun":false}',[Paints,Changes,BlankFrames]),TEncoding.UTF8);
  finally F.Free; Seed.Free; Config.Free; Full.Free; for I := 0 to 5 do Images[I].Free; D.Free; Store.Free; end;
end;
end.
