unit SYNC_MusicStudio_HostBackgroundChecks;

// Silent input-frame ownership, SDK identity and native settings preview checks.
interface
procedure RunHostBackgroundChecks(const Dir,PsdPath,MidiPath: string);
implementation

uses Winapi.Windows, System.SysUtils, System.Classes, System.Types,
  System.IOUtils, System.Math, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes, SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_HostBackground, SYNC_MusicStudio_FilterPlugin,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_FramebufferCapture,
  SYNC_MusicStudio_FramebufferFixture, Winapi.DXGIFormat;

type
  TItems = array[0..2] of Pointer;
  PItems = ^TItems;
  TReader = class
    Owner: OBJECT_HANDLE;
    SceneID: Integer;
    function Read(Serial: UInt64; out S: TMusicStudioBackgroundSnapshot): Boolean;
  end;

var Input,Captured: TMusicStudioFramePixels;
    HostJSON: UTF8String;
    Fixture: TMusicStudioFramebufferFixture;
    ObjectA,ObjectB: OBJECT_HANDLE;
    WriteCalls: Integer;

procedure Check(OK: Boolean; const Text: string); forward;

function FixtureTexture: Pointer; cdecl;
begin Result := nil; if Fixture<>nil then Result := Fixture.TexturePointer; end;

procedure FramebufferChecks;
var Capture: TMusicStudioFramebufferCapture; Pixels: TMusicStudioFramePixels;
    Data: TBytes; W,H,I: Integer; Status: string;
begin
  Fixture := TMusicStudioFramebufferFixture.Create; Capture := TMusicStudioFramebufferCapture.Create;
  try
    Check(not Capture.Capture(nil,Pixels,W,H,Status),'nil texture callback');
    SetLength(Data,24); for I := 0 to 5 do begin Data[I*4] := 30; Data[I*4+1] := 20; Data[I*4+2] := 10; Data[I*4+3] := 128; end;
    Data[0] := 90; Fixture.Fill(3,2,DXGI_FORMAT_B8G8R8A8_UNORM,Data);
    Check(Capture.Capture(FixtureTexture,Pixels,W,H,Status),Status);
    Check((W=3) and (H=2) and (Pixels[0].R=10) and (Pixels[0].B=90) and
      (Pixels[3].B=30) and (Pixels[0].A=128),'BGRA row pitch/orientation/alpha');
    SetLength(Data,8); PWord(@Data[0])^ := 65535; PWord(@Data[2])^ := 32896;
    PWord(@Data[4])^ := 0; PWord(@Data[6])^ := 16448;
    Fixture.Fill(1,1,DXGI_FORMAT_R16G16B16A16_UNORM,Data);
    Check(Capture.Capture(FixtureTexture,Pixels,W,H,Status),Status);
    Check((Pixels[0].R=255) and (Pixels[0].G=128) and (Pixels[0].B=0) and (Pixels[0].A=64),'UNORM16');
    PWord(@Data[0])^ := $3C00; PWord(@Data[2])^ := $3800; PWord(@Data[4])^ := 0; PWord(@Data[6])^ := $3400;
    Fixture.Fill(1,1,DXGI_FORMAT_R16G16B16A16_FLOAT,Data);
    Check(Capture.Capture(FixtureTexture,Pixels,W,H,Status),Status);
    Check((Pixels[0].R=255) and (Pixels[0].G=128) and (Pixels[0].A=64),'FLOAT16');
    for I := 1 to 20 do begin
      SetLength(Data,I*3*4); FillChar(Data[0],Length(Data),255);
      Fixture.Fill(I,3,DXGI_FORMAT_R8G8B8A8_UNORM,Data);
      Check(Capture.Capture(FixtureTexture,Pixels,W,H,Status) and (W=I) and (H=3) and
        (Length(Pixels)=I*3) and (Pixels[High(Pixels)].A=255),'staging resize');
    end;
    Writeln('BACKGROUND_WARP_RGBA_BGRA_UNORM16_FLOAT16_ROW_PITCH_ALPHA_RESIZE20_OK');
  finally Capture.Free; FreeAndNil(Fixture); end;
end;

procedure Check(OK: Boolean; const Text: string);
begin if not OK then raise Exception.Create('Host background: '+Text); end;

function TReader.Read(Serial: UInt64; out S: TMusicStudioBackgroundSnapshot): Boolean;
begin Result := ReadMusicStudioBackground(Owner,SceneID,Serial,S); end;

function FindObject(Layer,Frame: Integer): OBJECT_HANDLE; cdecl;
begin
  Result := nil;
  if (Frame<0) or (Frame>10000) then Exit;
  if Layer=7 then Result := ObjectA else if Layer=8 then Result := ObjectB;
end;
function CountEffect(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Integer; cdecl;
begin Result := 0; if (Obj=ObjectA) or (Obj=ObjectB) then Result := 1; end;
function GetJSON(Obj: OBJECT_HANDLE; Effect,Item: LPCWSTR): PAnsiChar; cdecl;
begin Result := PAnsiChar(HostJSON); end;
procedure GetInput(Buffer: PPIXEL_RGBA); cdecl;
begin if Length(Input)>0 then Move(Input[0],Buffer^,Length(Input)*4); end;
procedure SetOutput(Buffer: PPIXEL_RGBA; W,H: Integer); cdecl;
begin SetLength(Captured,W*H); Move(Buffer^,Captured[0],Length(Captured)*4); Inc(WriteCalls); end;

procedure Fill(var P: TMusicStudioFramePixels; W,H,R,G,B,A: Integer);
var I: Integer;
begin
  P := nil; SetLength(P,W*H);
  for I := 0 to High(P) do begin P[I].R := R; P[I].G := G; P[I].B := B; P[I].A := A; end;
end;

procedure RegistryChecks;
var A,B,Duplicate: TMusicStudioHostBackground;
    S,Old: TMusicStudioBackgroundSnapshot; P: TMusicStudioFramePixels;
    Serial: UInt64; Worker: TThread; I,J: Integer;
begin
  A := TMusicStudioHostBackground.Create; B := TMusicStudioHostBackground.Create;
  Duplicate := nil;
  try
    Fill(P,64,40,20,40,60,255); A.Publish(ObjectA,2,0,64,40,0,P); P := nil;
    Check(ReadMusicStudioBackground(ObjectA,2,0,S),'initial frame');
    Check((S.Width=64) and (S.Height=40) and (S.Pixels[0].R=20),'owned source');
    Serial := S.Serial; Old := S; S.Pixels[0].R := 99;
    Check(ReadMusicStudioBackground(ObjectA,2,0,S) and (S.Pixels[0].R=20),'consumer mutated capture');
    Check(ReadMusicStudioBackground(ObjectA,2,Serial,S) and (S.Pixels=nil),'unchanged frame recopied');
    Fill(P,32,48,60,80,100,128); B.Publish(ObjectB,2,5,32,48,1,P); P := nil;
    Check(ReadMusicStudioBackground(ObjectB,2,0,S) and (S.Pixels[0].R=60),'second instance');
    Check(not ReadMusicStudioBackground(ObjectB,3,0,S),'wrong scene');
    Fill(P,64,40,60,80,100,128);
    B.Publish(ObjectB,-1,0,64,40,0,P);
    Check(ReadMusicStudioBackground(ObjectB,3,0,S),'read-only render nil EDIT_INFO rejected same object');
    Check(not ReadMusicStudioBackground(Pointer(99999),3,0,S),'nil EDIT_INFO borrowed another object');
    B.Publish(ObjectB,2,0,64,40,0,P);
    Duplicate := TMusicStudioHostBackground.Create;
    Fill(P,8,8,1,2,3,255); Duplicate.Publish(ObjectA,2,0,8,8,0,P);
    Check(not ReadMusicStudioBackground(ObjectA,2,0,S),'ambiguous object selected arbitrarily');
    FreeAndNil(Duplicate);
    Worker := TThread.CreateAnonymousThread(procedure
      var FramePixels: TMusicStudioFramePixels; K: Integer;
      begin
        for K := 1 to 500 do begin
          Fill(FramePixels,64,40,K mod 251,0,0,255);
          A.Publish(ObjectA,2,K,64,40,K/30,FramePixels);
        end;
      end);
    Worker.FreeOnTerminate := False;
    try
      Worker.Start;
      for I := 1 to 500 do begin
        Check(ReadMusicStudioBackground(ObjectA,2,0,S),'concurrent read lost frame');
        for J := 1 to High(S.Pixels) do Check(S.Pixels[J].R=S.Pixels[0].R,'torn frame');
      end;
      Worker.WaitFor;
    finally Worker.Free; end;
    A.Publish(ObjectA,2,0,0,40,0,P);
    Check(not ReadMusicStudioBackground(ObjectA,2,0,S),'invalid dimensions kept old frame');
    Check((Old.Width=64) and (Length(Old.Pixels)=64*40),'old UI-owned copy invalidated');
    FreeAndNil(B); Check(not ReadMusicStudioBackground(ObjectB,2,0,S),'destroyed session retained frame');
    Writeln('BACKGROUND_OWNERSHIP_SCENES_AMBIGUITY_500_CONCURRENT_FRAMES_DESTROY_OK');
    Flush(Output);
  finally Duplicate.Free; B.Free; A.Free; end;
end;

procedure Capture(Form: TFormMusicStudioSettings; const Path: string);
var Bitmap: Vcl.Graphics.TBitmap; PNG: TPngImage; DC: HDC;
begin
  Form.Preview.Stage.Repaint;
  Bitmap := Vcl.Graphics.TBitmap.Create; PNG := TPngImage.Create;
  try
    Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); DC := GetDC(Form.Handle);
    try Check(BitBlt(Bitmap.Canvas.Handle,0,0,Bitmap.Width,Bitmap.Height,DC,0,0,SRCCOPY),'native capture');
    finally ReleaseDC(Form.Handle,DC); end;
    PNG.Assign(Bitmap); PNG.SaveToFile(Path);
  finally PNG.Free; Bitmap.Free; end;
end;

procedure SDKPreviewChecks(const Dir,PsdPath,MidiPath: string);
var Table: PFILTER_PLUGIN_TABLE; Items: PItems; SavedValue: PWideChar;
    Scene: TSCENE_INFO; Obj: TOBJECT_INFO; Edit: TEDIT_SECTION; Info: TEDIT_INFO;
    Video: TFILTER_PROC_VIDEO; Data,OtherData: Pointer;
    Doc: TMusicStudioDocument; Error,JSON: string; Pattern: TMusicStudioPattern;
    F: TFormMusicStudioSettings; Reader: TReader; S: TMusicStudioBackgroundSnapshot;
    R: TRect; X,Y,I,Calls: Integer; Color: Cardinal; Deadline: UInt64;
  procedure PaintCheck;
  begin
    // Raw背景/alphaを測る。新しい選択ハンドルは別の配置UI検証で扱う。
    F.Preview.PlacementEditor.SelectTrack(-1);
    F.Preview.RefreshHostBackground; F.Preview.Stage.Repaint;
    R := F.Preview.DisplayVideoRect;
    Check(Abs(R.Width/R.Height-Info.Width/Info.Height)<0.01,'frame aspect changed');
    Color := ColorToRGB(F.Preview.Stage.Canvas.Pixels[R.Left+1,R.Top+1]);
    Check(Color=RGB(250,10,30),'native input background top/orientation '+IntToHex(Color,8)+
      Format(' at %d,%d frame %d,%d,%d,%d',[R.Left+1,R.Top+1,R.Left,R.Top,R.Right,R.Bottom]));
    Color := ColorToRGB(F.Preview.Stage.Canvas.Pixels[R.Left+1,R.Bottom-2]);
    Check(Color=RGB(4,20,240),'native input background bottom/orientation');
    // One source-over application at the fixture's half-transparent rectangle.
    X := R.Left+Round(41.5*R.Width/64); Y := R.Top+Round(3.5*R.Height/40);
    Color := ColorToRGB(F.Preview.Stage.Canvas.Pixels[X,Y]);
    Check((Abs(Integer(GetRValue(Color))-110)<=2) and
      (Abs(Integer(GetGValue(Color))-60)<=2) and (Abs(Integer(GetBValue(Color))-50)<=2),'PSD alpha duplicated or misplaced');
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio started');
  end;
begin
  Check(SizeOf(TOBJECT_INFO)=104,'2.1.3 object prefix size');
  Check(NativeUInt(@Obj.EffectLayer)-NativeUInt(@Obj)=96,'effect_layer offset');
  Check(NativeUInt(@Info.SceneID)-NativeUInt(@Info)=72,'edit scene_id offset');
  Check(NativeUInt(@@Edit.FindObject)-NativeUInt(@Edit)=16,'find_object offset');
  SetMusicStudioHostVersion(2010301);
  Table := GetMusicStudioFilterTable; Items := PItems(Table^.Items);
  SavedValue := PFILTER_ITEM_STRING(Items^[1])^.Value;
  Doc := TMusicStudioDocument.Create; Reader := TReader.Create;
  Data := Table^.Func_Create(777); OtherData := Table^.Func_Create(888); F := nil;
  try
    Check(Doc.TryLoad('',Error),Error); Doc.AddTrack('psd'); Doc.UpdateTrack(0,'背景検証','#AABBCC',PsdPath);
    I := Doc.AddSinging; Pattern := Doc.PatternAt(I); Pattern.FilePath := MidiPath;
    Pattern.SourceTrack := 0; Pattern.Duration := 1; Doc.UpdatePattern(Pattern);
    Check(Doc.TrySave(JSON,Error),Error); HostJSON := UTF8String(JSON);
    PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
    Scene := Default(TSCENE_INFO); Scene.Width := 64; Scene.Height := 40; Scene.Rate := 30; Scene.Scale := 1;
    Info := Default(TEDIT_INFO); Info.Width := 64; Info.Height := 40; Info.SceneID := 2;
    Edit := Default(TEDIT_SECTION); Edit.Info := @Info; Edit.FindObject := FindObject;
    Edit.CountObjectEffect := CountEffect; Edit.GetObjectItemValue := GetJSON;
    Obj := Default(TOBJECT_INFO); Obj.Width := 64; Obj.Height := 40;
    Obj.Layer := 3; Obj.EffectLayer := 7; Obj.Flag := 1; Obj.EffectID := 777;
    Video := Default(TFILTER_PROC_VIDEO); Video.Scene := @Scene; Video.Object_ := @Obj;
    Video.Edit := @Edit; Video.GetImageData := GetInput; Video.SetImageData := SetOutput; Video.UserData := Data;
    Fill(Input,64,40,20,40,60,255);
    for Y := 0 to 1 do for X := 0 to 1 do begin
      Input[Y*64+X].R := 250; Input[Y*64+X].G := 10; Input[Y*64+X].B := 30;
      Input[(39-Y)*64+X].R := 4; Input[(39-Y)*64+X].G := 20; Input[(39-Y)*64+X].B := 240;
    end;
    Check(Table^.Func_Proc_Video(@Video)=1,'callback');
    Check(ReadMusicStudioBackground(ObjectA,2,0,S),'filter-object input identity');
    Check(S.Pixels[9*64+5].R=20,'captured our own opaque PSD');
    Check((S.Pixels[3*64+41].R=20) and (S.Pixels[3*64+41].G=40),'captured our own half-alpha PSD');
    F := TFormMusicStudioSettings.Create(nil); F.SilentVisualMode := True;
    F.LibraryRoot := TPath.Combine(Dir,'background-ui-library'); F.LoadDocument(JSON);
    Reader.Owner := ObjectA; Reader.SceneID := 2; F.Preview.OnReadHostBackground := Reader.Read;
    F.Show; ShowWindow(F.Handle,SW_SHOWNORMAL); Application.ProcessMessages;
    Deadline := GetTickCount64+10000;
    repeat
      F.TimelineBox.VisualCache.Poll; F.Preview.SceneCache.PollResults; Application.ProcessMessages;
      if (F.Preview.SceneCache.ImageForTrack(0)<>nil) and (F.Preview.SceneCache.ActiveRenderJobs=0) then Break;
      Sleep(2);
    until GetTickCount64>Deadline;
    Check(F.Preview.SceneCache.ImageForTrack(0)<>nil,'UI PSD timeout');
    F.Preview.RefreshHostBackground; Capture(F,TPath.Combine(Dir,'host-background-settings.png')); PaintCheck;
    F.ClientWidth := 950; F.ClientHeight := 620; Application.ProcessMessages; PaintCheck;
    Capture(F,TPath.Combine(Dir,'host-background-resized.png'));
    F.ScaleForPPI(144); Application.ProcessMessages; PaintCheck;
    Capture(F,TPath.Combine(Dir,'host-background-144dpi.png'));
    for I := 1 to 30 do begin
      F.Preview.Seek(I/20); Obj.Frame := I; Obj.Time := I/30; Info.Frame := I;
      Check(Table^.Func_Proc_Video(@Video)=1,'seek callback'); F.Preview.RefreshHostBackground;
      Check(F.Preview.HostBackgroundFrame=I,'stale frame after seek');
    end;
    Video.UserData := OtherData; Obj.EffectLayer := 8; Obj.EffectID := 888;
    Fill(Input,64,40,90,80,70,255); Check(Table^.Func_Proc_Video(@Video)=1,'other instance callback');
    PaintCheck;
    Reader.Owner := ObjectB; F.Preview.RefreshHostBackground; R := F.Preview.DisplayVideoRect;
    F.Preview.Stage.Repaint;
    Check(Cardinal(ColorToRGB(F.Preview.Stage.Canvas.Pixels[R.Left+1,R.Top+1]))=RGB(90,80,70),'other instance mixed');
    Table^.Func_Destroy(888,OtherData); OtherData := nil; F.Preview.RefreshHostBackground;
    Check(F.Preview.HostBackgroundSerial=0,'destroy did not clear UI background');
    F.Free; F := nil;
    F := TFormMusicStudioSettings.Create(nil); F.SilentVisualMode := True;
    F.LibraryRoot := TPath.Combine(Dir,'background-ui-library'); F.LoadDocument(JSON);
    Reader.Owner := ObjectA; F.Preview.OnReadHostBackground := Reader.Read; F.Preview.RefreshHostBackground;
    Check(F.Preview.HostBackgroundFrame=30,'reopen input missing');
    Video.UserData := Data; Obj.EffectLayer := 7; HostJSON := '{'; JSON := '{';
    PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON); Fill(Input,64,40,9,8,7,255);
    Calls := WriteCalls; Check(Table^.Func_Proc_Video(@Video)=1,'broken JSON');
    Check(WriteCalls=Calls,'broken JSON output old PSD');
    Check(ReadMusicStudioBackground(ObjectA,2,0,S) and (S.Pixels[0].R=9),'broken JSON blocked input capture');
    Video.GetImageData := nil; Check(Table^.Func_Proc_Video(@Video)=1,'unavailable input callback');
    F.Preview.RefreshHostBackground; Check(F.Preview.HostBackgroundSerial=0,'unavailable input retained old background');
    SetMusicStudioHostVersion(2010200); Video.GetImageData := GetInput;
    Check(Table^.Func_Proc_Video(@Video)=1,'old host');
    Check(not ReadMusicStudioBackground(ObjectA,2,0,S),'old host read effect_layer');
    Check(not F.Preview.AudioEngineAllocated and (F.TimelineBox.WaveCache.DecodeCount=0),'audio allocated');
    Writeln('BACKGROUND_SDK_FILTER_LAYER_INPUT_ALPHA_SEEK30_REOPEN_RESIZE_144DPI_INVALID_JSON_FALLBACK_OK');
    Flush(Output);
  finally
    F.Free; Table^.Func_Destroy(777,Data); if OtherData<>nil then Table^.Func_Destroy(888,OtherData);
    Reader.Free; Doc.Free; PFILTER_ITEM_STRING(Items^[1])^.Value := SavedValue;
    Input := nil; Captured := nil; HostJSON := ''; SetMusicStudioHostVersion(0);
  end;
end;

procedure RunHostBackgroundChecks(const Dir,PsdPath,MidiPath: string);
begin
  ObjectA := Pointer(1111); ObjectB := Pointer(2222);
  FramebufferChecks; RegistryChecks; SDKPreviewChecks(Dir,PsdPath,MidiPath);
end;
end.
