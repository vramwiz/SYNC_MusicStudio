unit SYNC_MusicStudio_VideoOutputChecks;

interface
procedure RunVideoOutputChecks(const PluginPath, OutputDir: string);
implementation

uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  System.JSON, Vcl.Forms, Vcl.ExtCtrls, Vcl.Graphics, Vcl.Imaging.pngimage, AviUtl2FilterTypes,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PsdTransform, SYNC_MusicStudio_LayerStepData,
  SYNC_MusicStudio_TempoPatternData, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_ArtDocument,
  SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_VideoRenderer,
  SYNC_MusicStudio_HostBackgroundChecks, SYNC_MusicStudio_FramebufferFixture;

type
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  // Independent SDK prefix, checked against downloaded 2026/10/10 filter2.h.
  TSdkVideo = record
    Scene: PSCENE_INFO;
    Obj: POBJECT_INFO;
    GetData: procedure(Buffer: PPIXEL_RGBA); cdecl;
    SetData: procedure(Buffer: PPIXEL_RGBA; W,H: Integer); cdecl;
    FunctionsBeforeUserData: array[0..30] of Pointer;
    UserData: Pointer;
    RemainingFunctions: array[0..4] of Pointer;
  end;
  TItems = array[0..5] of Pointer;
  PItems = ^TItems;
  TModalBackgroundProbe = class
    Timer: TTimer;
    Passed: Boolean;
    ExpectMissing: Boolean;
    Attempts: Integer;
    ErrorText,PNGPath: string;
    procedure Tick(Sender: TObject);
    constructor Create(const Path: string);
    destructor Destroy; override;
  end;

var Captured, Input: TMusicStudioVideoPixels; CaptureWidth,CaptureHeight,SetCalls: Integer;
    SDKJSON: UTF8String; SettingsWindow,StageWindow,CancelWindow: HWND;
    SDKApplyCalls: Integer; SDKFramebuffer: TMusicStudioFramebufferFixture;

function SDKGetFramebuffer: Pointer; cdecl;
begin Result := nil; if SDKFramebuffer<>nil then Result := SDKFramebuffer.TexturePointer; end;

function SDKFocus: OBJECT_HANDLE; cdecl;
begin Result := Pointer(10001); end;
function SDKFindObject(Layer,Frame: Integer): OBJECT_HANDLE; cdecl;
begin Result := nil; if Layer=7 then Result := SDKFocus; end;
function SDKCountEffect(Obj: OBJECT_HANDLE; Effect: LPCWSTR): Integer; cdecl;
begin Result := 1; end;
function SDKGetJSON(Obj: OBJECT_HANDLE; Effect,Item: LPCWSTR): PAnsiChar; cdecl;
begin Result := PAnsiChar(SDKJSON); end;
function SDKSetJSON(Obj: OBJECT_HANDLE; Effect,Item: LPCWSTR; Value: PAnsiChar): LongBool; cdecl;
begin Inc(SDKApplyCalls); Result := True; end;

function EnumSettings(Window: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..255] of Char;
begin
  GetClassName(Window,Name,Length(Name));
  if Pos('TFormMusicStudioSettings',string(Name))>0 then SettingsWindow := Window;
  Result := True;
end;
function EnumSettingsChild(Window: HWND; Param: LPARAM): BOOL; stdcall;
var Name,Caption: array[0..255] of Char;
begin
  GetClassName(Window,Name,Length(Name)); GetWindowText(Window,Caption,Length(Caption));
  if Pos('TMusicStudioPsdPreviewSurface',string(Name))>0 then StageWindow := Window;
  if string(Caption)='キャンセル' then CancelWindow := Window;
  Result := True;
end;

constructor TModalBackgroundProbe.Create(const Path: string);
begin
  inherited Create; PNGPath := Path; Timer := TTimer.Create(nil);
  Timer.Interval := 100; Timer.OnTimer := Tick;
end;
destructor TModalBackgroundProbe.Destroy;
begin Timer.Free; inherited; end;
procedure TModalBackgroundProbe.Tick(Sender: TObject);
var DC: HDC; R: TRect; X,Y,BG,Half: Integer; C: Cardinal; Row: PByte;
    Bitmap: TBitmap; PNG: TPngImage;
begin
  Inc(Attempts); SettingsWindow := 0; StageWindow := 0; CancelWindow := 0;
  EnumThreadWindows(GetCurrentThreadId,@EnumSettings,0);
  if SettingsWindow<>0 then begin
    EnumChildWindows(SettingsWindow,@EnumSettingsChild,0);
    ShowWindow(SettingsWindow,SW_SHOWNORMAL);
    if (StageWindow<>0) and (CancelWindow<>0) then begin
      RedrawWindow(StageWindow,nil,0,RDW_INVALIDATE or RDW_UPDATENOW);
      GetClientRect(StageWindow,R); DC := GetDC(StageWindow); BG := 0; Half := 0;
      Bitmap := TBitmap.Create; Bitmap.PixelFormat := pf24bit; Bitmap.SetSize(R.Width,R.Height);
      try
        BitBlt(Bitmap.Canvas.Handle,0,0,R.Width,R.Height,DC,0,0,SRCCOPY);
        for Y := 0 to R.Height-1 do begin
          Row := Bitmap.ScanLine[Y];
          for X := 0 to R.Width-1 do begin
            C := RGB(Row[X*3+2],Row[X*3+1],Row[X*3]);
            if C=RGB(20,40,60) then Inc(BG);
            if (Abs(Integer(GetRValue(C))-110)<=2) and
              (Abs(Integer(GetGValue(C))-60)<=2) and (Abs(Integer(GetBValue(C))-50)<=2) then Inc(Half);
          end;
        end;
      finally Bitmap.Free; ReleaseDC(StageWindow,DC); end;
      if ((not ExpectMissing) and (BG>1000) and (Half>8)) or
        (ExpectMissing and (BG=0) and (Half=0)) then begin
        Passed := True; Timer.Enabled := False;
        Bitmap := TBitmap.Create; PNG := TPngImage.Create;
        try
          GetClientRect(SettingsWindow,R); Bitmap.SetSize(R.Width,R.Height); DC := GetDC(SettingsWindow);
          try BitBlt(Bitmap.Canvas.Handle,0,0,R.Width,R.Height,DC,0,0,SRCCOPY);
          finally ReleaseDC(SettingsWindow,DC); end;
          PNG.Assign(Bitmap); PNG.SaveToFile(PNGPath);
        finally PNG.Free; Bitmap.Free; end;
        SendMessage(CancelWindow,BM_CLICK,0,0);
      end else if Attempts>=50 then begin
        Timer.Enabled := False; ErrorText := Format('DLL settings pixels: input %d / half alpha %d',[BG,Half]);
        SendMessage(CancelWindow,BM_CLICK,0,0);
      end;
    end else if Attempts>=50 then begin
      Timer.Enabled := False; ErrorText := 'DLL settings child windows unavailable';
      PostMessage(SettingsWindow,WM_CLOSE,0,0);
    end;
  end;
end;

procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Video output: '+Message); end;

procedure GetData(Buffer: PPIXEL_RGBA); cdecl;
begin if Length(Input)>0 then Move(Input[0],Buffer^,Length(Input)*4); end;

procedure SetData(Buffer: PPIXEL_RGBA; W,H: Integer); cdecl;
begin
  Inc(SetCalls); CaptureWidth := W; CaptureHeight := H;
  SetLength(Captured,NativeInt(W)*H); Move(Buffer^,Captured[0],Length(Captured)*4);
end;

procedure Pixel(const Pixels: TMusicStudioVideoPixels; W,X,Y,R,G,B,A: Integer; const Message: string);
var P: TPIXEL_RGBA;
begin
  Check(Length(Pixels)>Y*W+X,Message+' missing'); P := Pixels[Y*W+X];
  Check((P.R=R) and (P.G=G) and (P.B=B) and (P.A=A),Message+' RGBA');
end;

function Hash(const Pixels: TMusicStudioVideoPixels): string;
var S: TBytesStream; B: TBytes;
begin
  SetLength(B,Length(Pixels)*4); if Length(B)>0 then Move(Pixels[0],B[0],Length(B));
  S := TBytesStream.Create(B); try Result := THashSHA2.GetHashString(S); finally S.Free; end;
end;

procedure SavePNG(const Pixels: TMusicStudioVideoPixels; W,H: Integer; const Path: string);
var Bitmap: TBitmap; PNG: TPngImage; X,Y: Integer; Row: PByte; P: TPIXEL_RGBA;
begin
  Bitmap := TBitmap.Create; PNG := TPngImage.Create;
  try
    Bitmap.PixelFormat := pf32bit; Bitmap.SetSize(W,H); Bitmap.AlphaFormat := afPremultiplied;
    for Y := 0 to H-1 do begin Row := Bitmap.ScanLine[Y];
      for X := 0 to W-1 do begin P := Pixels[Y*W+X]; Row[X*4] := P.B;
        Row[X*4+1] := P.G; Row[X*4+2] := P.R; Row[X*4+3] := P.A; end;
    end;
    PNG.Assign(Bitmap); PNG.SaveToFile(Path);
  finally PNG.Free; Bitmap.Free; end;
end;

procedure Fixture(const Path: string);
var Doc: TArtDocument; Mouth: TArtLayer;
  procedure Image(const Name: string; X,Y,W,H,R,G,B,A: Integer; Visible: Boolean; Parent: TArtLayer);
  var Layer: TArtLayer; I: Integer;
  begin
    Layer := Doc.AddLayer(alkImage,Name,TArtBounds.Create(X,Y,X+W,Y+H),Parent);
    Layer.Visible := Visible; SetLength(Layer.Pixels,W*H*4);
    for I := 0 to W*H-1 do begin Layer.Pixels[I*4] := R; Layer.Pixels[I*4+1] := G;
      Layer.Pixels[I*4+2] := B; Layer.Pixels[I*4+3] := A; end;
  end;
begin
  Doc := TArtDocument.Create;
  try
    Doc.Width := 64; Doc.Height := 40;
    Mouth := Doc.AddLayer(alkGroup,'口',TArtBounds.Create(4,8,12,14));
    Image('*通常',4,8,8,6,0,255,0,255,True,Mouth);
    Image('*あ',4,8,8,6,255,0,0,255,False,Mouth);
    Image('*い',4,8,8,6,0,0,255,255,False,Mouth);
    Image('半透明',40,2,4,3,200,80,40,128,True,nil);
    Image('上下確認',56,34,4,3,255,255,0,255,True,nil);
    WriteNewPsd(Doc,Path,pcRaw);
  finally Doc.Free; end;
end;

procedure LyricMidi(const Path: string);
const Data: array[0..57] of Byte = (
  $4D,$54,$68,$64,0,0,0,6,0,0,0,1,$01,$E0,
  $4D,$54,$72,$6B,0,0,0,36,
  0,$FF,5,3,$E3,$81,$82,0,$90,60,100,
  $83,$60,$80,60,0,0,$FF,5,3,$E3,$81,$84,0,$90,64,100,
  $83,$60,$80,64,0,0,$FF,$2F,0);
var S: TFileStream;
begin S := TFileStream.Create(Path,fmCreate); try S.WriteBuffer(Data,SizeOf(Data)); finally S.Free; end; end;

function Key(Layers: TMusicStudioLayerDocument; const Name: string): string;
var Layer: TMusicStudioLayerInfo;
begin Result := ''; for Layer in Layers.Layers do if Layer.Name=Name then Exit(Layer.Key); end;

function MakeJSON(Store: TMusicStudioSharedPsdLibrary; const AssetID, PsdPath,MidiPath: string; N: Integer): string;
var Doc: TMusicStudioDocument; I,Singing: Integer; Pattern: TMusicStudioPattern; Error: string;
begin
  Doc := TMusicStudioDocument.Create;
  try
    Check(Doc.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,Error),Error);
    if Store<>nil then Doc.AssetResolver := Store.ResolvePath;
    Singing := Doc.AddSinging; Pattern := Doc.PatternAt(Singing);
    Pattern.FilePath := MidiPath; Pattern.SourceTrack := 0; Pattern.Duration := 1; Doc.UpdatePattern(Pattern);
    for I := 0 to N-1 do begin
      Doc.AddTrack('psd');
      if AssetID<>'' then Doc.AssignPsd(I,AssetID)
      else Doc.UpdateTrack(I,'検証PSD','#AABBCC',PsdPath);
      Check(Doc.AddPlacement(I,1,Pattern.ID,2,1,Error),Error);
    end;
    Check(Doc.TrySave(Result,Error),Error);
  finally Doc.Free; end;
end;

procedure SessionChecks(const Dir,PsdPath,MidiPath: string; out SharedJSON: string);
var Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset; Dup: Boolean;
    Layers: TMusicStudioLayerDocument; Config: TJSONObject; Session,Other: TMusicStudioVideoSession;
    Error,JSON,BeforeJSON,NormalHash,AHash,IHash,AssetHash,PsdHash,MidiHash: string;
    Pixels,OtherPixels: TMusicStudioVideoPixels; I: Integer;
begin
  Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'isolated-library'));
  Layers := TMusicStudioLayerDocument.Create; Config := ParseMusicStudioPsdConfig('');
  Session := TMusicStudioVideoSession.Create(Store.Root); Other := TMusicStudioVideoSession.Create(Store.Root);
  try
    Check(Store.TryImport(PsdPath,'映像のみ検証','#AABBCC',Asset,Dup,Error),Error);
    Check(Layers.LoadFile(Asset.FilePath),Layers.LastError);
    MusicStudioAssignMouth(Config,0,Key(Layers,'*通常'));
    MusicStudioAssignMouth(Config,1,Key(Layers,'*あ')); MusicStudioAssignMouth(Config,2,Key(Layers,'*い'));
    Asset.ConfigJSON := Config.ToJSON; Check(Store.TrySave(Asset,Error),Error);
    PsdHash := THashSHA2.GetHashStringFromFile(Asset.FilePath); MidiHash := THashSHA2.GetHashStringFromFile(MidiPath);
    AssetHash := THashSHA2.GetHashStringFromFile(TPath.Combine(TPath.GetDirectoryName(Asset.FilePath),'asset.json'));
    JSON := MakeJSON(Store,Asset.ID,'',MidiPath,1); BeforeJSON := JSON; SharedJSON := JSON;
    TFile.WriteAllText(TPath.Combine(Dir,'isolated-video-demo.json'),JSON,TEncoding.UTF8);
    Check(Session.Render(JSON,0,64,40,Pixels,Error),Error); NormalHash := Hash(Pixels);
    Pixel(Pixels,64,5,9,0,255,0,255,'normal'); Pixel(Pixels,64,0,0,0,0,0,0,'transparent');
    Pixel(Pixels,64,41,3,100,40,20,128,'premultiplied alpha'); Pixel(Pixels,64,57,35,255,255,0,255,'top-down');
    SavePNG(Pixels,64,40,TPath.Combine(Dir,'frame-normal.png'));
    Check(Session.Render(JSON,2.25,64,40,Pixels,Error),Error); AHash := Hash(Pixels);
    Pixel(Pixels,64,5,9,255,0,0,255,'a'); SavePNG(Pixels,64,40,TPath.Combine(Dir,'frame-a.png'));
    Check(Session.Render(JSON,2.75,64,40,Pixels,Error),Error); IHash := Hash(Pixels);
    Pixel(Pixels,64,5,9,0,0,255,255,'i'); SavePNG(Pixels,64,40,TPath.Combine(Dir,'frame-i.png'));
    Check(Session.Render(JSON,2.75,128,80,Pixels,Error),Error);
    Pixel(Pixels,128,10,18,0,0,255,255,'resized exact vowel');
    Pixel(Pixels,128,114,70,255,255,0,255,'resized orientation');
    for I := 1 to 30 do begin
      Check(Session.Render(JSON,2.75,64,40,Pixels,Error) and (Hash(Pixels)=IHash),'seek i');
      Check(Session.Render(JSON,2.25,64,40,Pixels,Error) and (Hash(Pixels)=AHash),'seek a');
      Check(Session.Render(JSON,3,64,40,Pixels,Error) and (Hash(Pixels)=NormalHash),'clip end');
      Check(Session.Render(JSON,0,64,40,Pixels,Error) and (Hash(Pixels)=NormalHash),'stop/repeat');
    end;
    Check(Other.Render(JSON,2.25,64,40,OtherPixels,Error) and (Hash(OtherPixels)=AHash),'second instance');
    // A completed snapshot never opens MIDI/PSD again during frame rendering.
    TFile.Move(Asset.FilePath,Asset.FilePath+'.held'); TFile.Move(MidiPath,MidiPath+'.held');
    try
      Check(Session.Render(JSON,2.75,64,40,Pixels,Error) and (Hash(Pixels)=IHash),'snapshot reopened source');
      Check(Session.Render(JSON,2.25,64,40,Pixels,Error) and (Hash(Pixels)=AHash),'snapshot seek without files');
    finally TFile.Move(Asset.FilePath+'.held',Asset.FilePath); TFile.Move(MidiPath+'.held',MidiPath); end;
    Check(not Session.Render('{',0,64,40,Pixels,Error) and (Length(Pixels)=0) and (Error<>''),'malformed JSON stale output');
    Check(Session.Render(JSON,2.25,64,40,Pixels,Error) and (Hash(Pixels)=AHash),'restore JSON');
    Check(AssetHash=THashSHA2.GetHashStringFromFile(TPath.Combine(TPath.GetDirectoryName(Asset.FilePath),'asset.json')),'render wrote shared metadata');
    MusicStudioAssignMouth(Config,1,Key(Layers,'*い')); Asset.ConfigJSON := Config.ToJSON;
    Check(Store.TrySave(Asset,Error),Error); InvalidateMusicStudioVideoSnapshots;
    Check(Session.Render(JSON,2.25,64,40,Pixels,Error) and (Hash(Pixels)=IHash),'same JSON shared refresh');
    Check(Other.Render(JSON,2.25,64,40,OtherPixels,Error) and (Hash(OtherPixels)=IHash),'shared refresh second instance');
    Other.Free; Other := TMusicStudioVideoSession.Create(Store.Root);
    Check(Other.Render(JSON,2.75,64,40,OtherPixels,Error) and (Hash(OtherPixels)=IHash),'reopen snapshot');
    TFile.WriteAllText(TPath.Combine(Dir,'broken.mid'),'broken MIDI',TEncoding.UTF8);
    Check(Session.Render(MakeJSON(Store,Asset.ID,'',TPath.Combine(Dir,'broken.mid'),1),2.25,64,40,Pixels,Error),'broken MIDI safe');
    Pixel(Pixels,64,5,9,0,255,0,255,'broken MIDI normal fallback');
    Check(Session.Render(MakeJSON(Store,Asset.ID,'',MidiPath,2),0,128,40,Pixels,Error),Error);
    Pixel(Pixels,128,5,9,0,255,0,255,'first lane'); Pixel(Pixels,128,69,9,0,255,0,255,'second lane');
    Check(not Session.Render(JSON,-1,64,40,Pixels,Error),'negative time');
    Check(not Session.Render(JSON,0,8193,40,Pixels,Error),'size limit');
    Check(BeforeJSON=SharedJSON,'project JSON changed');
    Check(PsdHash=THashSHA2.GetHashStringFromFile(Asset.FilePath),'managed PSD changed');
    Check(MidiHash=THashSHA2.GetHashStringFromFile(MidiPath),'MIDI changed');
    Writeln('VIDEO_SNAPSHOT_ALPHA_VOWELS_SEEK_STOP_RELOAD_MULTI_INSTANCE_OK');
  finally Other.Free; Session.Free; Config.Free; Layers.Free; Store.Free; end;
end;

procedure SDKChecks(const PluginPath,Dir,PsdPath,MidiPath: string);
var Module: HMODULE; Initialize: TInitialize; Uninitialize: TUninitialize; GetTable: TGetTable;
    Table: PFILTER_PLUGIN_TABLE; Items: PItems; Scene: TSCENE_INFO; Obj: TOBJECT_INFO;
    Video: TSdkVideo; SavedValue: PWideChar; JSON,Error,FirstHash: string;
    Data,OtherData: Pointer; Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset;
    I,Calls: Integer; NormalHash,AHash,IHash: string;
    Edit: TEDIT_SECTION; Info: TEDIT_INFO; Probe: TModalBackgroundProbe;
    TransformDocument: TMusicStudioDocument; Transform: TMusicStudioPsdTransform;
    TransformedJSON: string; BaselinePixels: TMusicStudioVideoPixels; X,Y: Integer;
    StepData: TMusicStudioLayerStepData; StepLayers: TMusicStudioLayerDocument; StepConfig: TJSONObject;
    StepPattern: TMusicStudioPattern; StepSlot,StepPatternIndex: Integer; Layer: TMusicStudioLayerInfo;
    StepReference: TMusicStudioVideoSession; ExpectedStep: TMusicStudioVideoPixels;
    TempoData: TMusicStudioTempoPatternData; TempoPattern: TMusicStudioPattern;
    TempoSlot,TempoIndex: Integer; ManualJSON,TempoScope,ManualStepHash: string;
    FrozenManualStep: TMusicStudioVideoPixels;
begin
  Check(SizeOf(TSdkVideo)=328,'SDK video size');
  Check(NativeUInt(@Video.UserData)-NativeUInt(@Video)=280,'SDK userdata offset');
  Check(SizeOf(TFILTER_PROC_VIDEO)=SizeOf(TSdkVideo),'Delphi video layout');
  Check(SizeOf(TFILTER_PLUGIN_TABLE)=72,'SDK table size'); Check(SizeOf(TFILTER_ITEM_BUTTON)=32,'SDK button size');
  Module := LoadLibrary(PChar(PluginPath)); Check(Module<>0,'LoadLibrary');
  try
    @Initialize := GetProcAddress(Module,'InitializePlugin'); @Uninitialize := GetProcAddress(Module,'UninitializePlugin');
    @GetTable := GetProcAddress(Module,'GetFilterPluginTable');
    Check(Assigned(Initialize) and Assigned(Uninitialize) and Assigned(GetTable),'exports');
    Check(Initialize(2010301)=1,'Initialize 2.1.3a');
    try
      Table := GetTable; Check(Assigned(Table^.Func_Create) and Assigned(Table^.Func_Destroy),'lifecycle');
      Check(not Assigned(Table^.Func_Proc_Audio) and (Table^.Flag and 2=0),'audio enabled');
      Items := PItems(Table^.Items); SavedValue := PFILTER_ITEM_STRING(Items^[1])^.Value;
      Data := Table^.Func_Create(111); OtherData := Table^.Func_Create(222); Check((Data<>nil) and (OtherData<>nil) and (Data<>OtherData),'instance isolation');
      try
        FillChar(Scene,SizeOf(Scene),0); Scene.Width := 64; Scene.Height := 40; Scene.Rate := 30; Scene.Scale := 1;
        FillChar(Obj,SizeOf(Obj),0); Obj.ID := 10; Obj.EffectID := 111; Obj.Width := 64; Obj.Height := 40;
        FillChar(Video,SizeOf(Video),0); Video.Scene := @Scene; Video.Obj := @Obj;
        Video.GetData := GetData; Video.SetData := SetData; Video.UserData := Data;
        JSON := MakeJSON(nil,'',PsdPath,MidiPath,1); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'video callback');
        Check((CaptureWidth=64) and (CaptureHeight=40),'SDK dimensions');
        BaselinePixels := Copy(Captured); TransformDocument := TMusicStudioDocument.Create;
        try
          Check(TransformDocument.TryLoad(JSON,Error),Error);
          Transform := Default(TMusicStudioPsdTransform); Transform.FlipX := True; Transform.FlipY := True;
          TransformDocument.UpdatePsdTransform(0,Transform); Check(TransformDocument.TrySave(TransformedJSON,Error),Error);
          PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
          Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL transform flip');
          for I := 0 to High(Captured) do Check(CompareMem(@Captured[I],@BaselinePixels[High(Captured)-I],SizeOf(Captured[I])),'DLL flip pixels');
          Transform.HasBounds := True; Transform.X := -0.5; Transform.Y := 0; Transform.Width := 1; Transform.Height := 1;
          TransformDocument.UpdatePsdTransform(0,Transform); Check(TransformDocument.TrySave(TransformedJSON,Error),Error);
          PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
          Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL outside placement');
          for Y := 0 to 39 do for X := 0 to 63 do begin
            if X>=32 then Check(Captured[Y*64+X].A=0,'DLL outside output clipped')
            else Check(CompareMem(@Captured[Y*64+X],@BaselinePixels[(39-Y)*64+31-X],SizeOf(Captured[0])),'DLL outside UV');
          end;
          Calls := SetCalls; TransformedJSON := StringReplace(TransformedJSON,'"height":1','"height":0',[]);
          PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
          Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL zero dimension callback safe');
          Check(SetCalls=Calls,'DLL invalid transform wrote old frame');
        finally TransformDocument.Free; end;
        PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL transform legacy restore');
        Check(Hash(Captured)=Hash(BaselinePixels),'DLL legacy geometry changed');
        Writeln('VIDEO_LOADED_DLL_TRANSFORM_FLIP_OUTSIDE_UV_CLIPPING_INVALID_LEGACY_RESTORE_OK');
        Pixel(Captured,64,5,9,0,255,0,255,'DLL PSD normal'); Pixel(Captured,64,0,0,0,0,0,0,'DLL transparency');
        FirstHash := Hash(Captured); SavePNG(Captured,64,40,TPath.Combine(Dir,'sdk-transparent.png'));
        SetLength(Input,64*40); for I := 0 to High(Input) do begin Input[I].R := 20; Input[I].G := 40; Input[I].B := 60; Input[I].A := 255; end;
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'overlay');
        Pixel(Captured,64,0,0,20,40,60,255,'background retained'); Pixel(Captured,64,41,3,110,60,50,255,'source over half alpha');
        // Real DLL settings button and native pixels, using a mock read-only host.
        // No VCL objects/dynamic arrays cross the loaded Delphi module boundary.
        SDKJSON := UTF8String(JSON); Edit := Default(TEDIT_SECTION); Info := Default(TEDIT_INFO);
        Info.Width := 64; Info.Height := 40; Info.SceneID := 2;
        Edit.Info := @Info; Edit.FindObject := SDKFindObject; Edit.GetFocusObject := SDKFocus;
        Edit.CountObjectEffect := SDKCountEffect; Edit.GetObjectItemValue := SDKGetJSON; Edit.SetObjectItemValue := SDKSetJSON;
        SDKApplyCalls := 0;
        Probe := TModalBackgroundProbe.Create(TPath.Combine(Dir,'loaded-dll-no-capture-yet.png'));
        try
          Probe.ExpectMissing := True;
          PFILTER_ITEM_BUTTON(Items^[0])^.Callback(@Edit);
          Check(Probe.Passed,'settings before first matching render did not remain safe');
        finally Probe.Free; end;
        Check(SDKApplyCalls=0,'initial missing background applied JSON');
        // Actual host distinction: the object's pixels can be transparent while
        // the composited framebuffer contains other layers. Render read sections
        // can have no EDIT_INFO; settings then have their own live EDIT_INFO.
        SDKFramebuffer := TMusicStudioFramebufferFixture.Create;
        SDKFramebuffer.RGBA(64,40,Input); Input := nil;
        Video.FunctionsBeforeUserData[1] := @SDKGetFramebuffer;
        Video.FunctionsBeforeUserData[2] := @Edit; Obj.Flag := 1; Obj.EffectLayer := 7;
        Edit.Info := nil;
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL input capture');
        Edit.Info := @Info;
        Writeln('BACKGROUND_DLL_MODAL_START'); Flush(Output); SDKApplyCalls := 0;
        Probe := TModalBackgroundProbe.Create(TPath.Combine(Dir,'loaded-dll-background-settings.png'));
        try
          PFILTER_ITEM_BUTTON(Items^[0])^.Callback(@Edit);
          Check(Probe.Passed,'DLL settings background: '+Probe.ErrorText);
        finally Probe.Free; end;
        Check(SDKApplyCalls=0,'DLL background cancel applied JSON');
        // Reopening with a cached host frame must not require another render.
        Info.Frame := 1;
        Probe := TModalBackgroundProbe.Create(TPath.Combine(Dir,'loaded-dll-background-reopened.png'));
        try
          PFILTER_ITEM_BUTTON(Items^[0])^.Callback(@Edit);
          Check(Probe.Passed,'DLL reopened settings background: '+Probe.ErrorText);
        finally Probe.Free; end;
        Check(SDKApplyCalls=0,'DLL reopened background cancel applied JSON');
        Video.FunctionsBeforeUserData[1] := nil; Video.FunctionsBeforeUserData[2] := nil; Obj.Flag := 0;
        Writeln('BACKGROUND_DLL_TRANSPARENT_OBJECT_COLORED_FRAMEBUFFER_NIL_EDIT_INFO_CACHED_REOPEN_CANCEL_OK');
        Flush(Output);
        Input := nil;
        Video.UserData := OtherData; Obj.ID := 11; Obj.EffectID := 222;
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'second SDK instance'); Check(Hash(Captured)=FirstHash,'second instance image');
        Calls := SetCalls; JSON := '{'; PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'bad JSON boundary'); Check(Calls=SetCalls,'bad JSON published old PSD');
        JSON := MakeJSON(nil,'',TPath.Combine(Dir,'missing.psd'),MidiPath,1); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'missing file boundary');
        Pixel(Captured,64,5,9,0,0,0,0,'missing source no old pixels');
        TFile.WriteAllText(TPath.Combine(Dir,'broken.psd'),'broken PSD',TEncoding.UTF8);
        JSON := MakeJSON(nil,'',TPath.Combine(Dir,'broken.psd'),MidiPath,1); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON);
        Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'broken PSD boundary');
        Pixel(Captured,64,5,9,0,0,0,0,'broken PSD no stale image');
        Check(Table^.Func_Proc_Video(nil)=1,'nil boundary');
        // Read-only real shared asset; JSON/MIDI/output stay in this test directory.
        // All userdata comes from the loaded DLL, never from another memory manager.
        Store := TMusicStudioSharedPsdLibrary.Create;
        try
          Check(Store.TryRead('6720ffb6-68b1-4b4a-9582-da424493c9bc',Asset,Error),Error);
          JSON := MakeJSON(Store,Asset.ID,'',MidiPath,1);
          TFile.WriteAllText(TPath.Combine(Dir,'sdk-real-video-demo.json'),JSON,TEncoding.UTF8);
          PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(JSON); Video.UserData := Data;
          Obj.Width := 960; Obj.Height := 540; Scene.Width := 960; Scene.Height := 540;
          Obj.Time := 0; Obj.Frame := 99; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK normal');
          NormalHash := Hash(Captured); SavePNG(Captured,960,540,TPath.Combine(Dir,'sdk-real-normal.png'));
          Obj.Time := 2.25; Obj.Frame := 0; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK a');
          AHash := Hash(Captured); SavePNG(Captured,960,540,TPath.Combine(Dir,'sdk-real-a.png'));
          Obj.Time := 2.75; Obj.Frame := 0; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK i');
          IHash := Hash(Captured); SavePNG(Captured,960,540,TPath.Combine(Dir,'sdk-real-i.png'));
          Check((NormalHash<>AHash) and (AHash<>IHash) and (NormalHash<>IHash),'real PSD vowels identical');
          for I := 1 to 15 do begin
            Obj.Time := 2.25; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK seek a'); Check(Hash(Captured)=AHash,'SDK stale a');
            Obj.Time := 2.75; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK seek i'); Check(Hash(Captured)=IHash,'SDK stale i');
            Obj.Time := 3; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'SDK stop'); Check(Hash(Captured)=NormalHash,'SDK end/stop');
          end;
          Writeln('VIDEO_REAL_SHARED_PSD_LOADED_DLL_VOWELS_REVERSE_SEEK_STOP_OK');
          // Real shared PSD read-only; the step project/expected RGBA belong to this host.
          TransformDocument := TMusicStudioDocument.Create; StepData := TMusicStudioLayerStepData.Create;
          StepLayers := TMusicStudioLayerDocument.Create; StepConfig := ParseMusicStudioPsdConfig('');
          StepReference := TMusicStudioVideoSession.Create(Store.Root);
          try
            Check(TransformDocument.TryLoad(JSON,Error),Error); Check(StepLayers.LoadFile(Asset.FilePath),StepLayers.LastError);
            for Layer in StepLayers.Layers do MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(StepConfig,'visibility'),Layer.Key,False);
            StepPatternIndex := TransformDocument.AddPerformance; StepPattern := TransformDocument.PatternAt(StepPatternIndex);
            StepData.LoadJSON(StepPattern.ConfigJSON); StepData.Enable(Asset.ID); StepData.LengthBeats := 4;
            StepData.AddStep(0.5,0.5,StepConfig.ToJSON); StepPattern.ConfigJSON := StepData.ConfigJSON;
            TransformDocument.UpdatePattern(StepPattern); StepSlot := TransformDocument.AddSlot(0,'performance');
            Check(TransformDocument.AddPlacement(0,StepSlot,StepPattern.ID,0,2,Error),Error);
            Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
            Video.GetData := nil;
            for I := 0 to 11 do begin
              case I mod 3 of 0: Obj.Time := 0; 1: Obj.Time := 0.3; else Obj.Time := 0.5; end;
              Check(StepReference.Render(TransformedJSON,Obj.Time,960,540,ExpectedStep,Error),Error);
              Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL layer step');
              Check(Hash(Captured)=Hash(ExpectedStep),'DLL step did not match frozen project composite');
                if I mod 3=1 then FrozenManualStep := Copy(Captured);
              if I mod 3=1 then Check(Hash(Captured)<>NormalHash,'DLL active step did not alter layers')
              else Check(Hash(Captured)=NormalHash,'DLL rest/end did not restore base');
            end;
            TFile.WriteAllText(TPath.Combine(Dir,'sdk-real-layer-steps.json'),TransformedJSON,TEncoding.UTF8);
            SavePNG(ExpectedStep,960,540,TPath.Combine(Dir,'sdk-real-layer-step-rest.png'));
              ManualStepHash := Hash(FrozenManualStep);
              SavePNG(FrozenManualStep,960,540,TPath.Combine(Dir,'sdk-frozen-manual120-active.png'));
            Writeln('VIDEO_LOADED_DLL_REAL_PSD_LAYER_STEPS_BEATS_REVERSE_SEEK_REST_RGBA_MATCH_OK');
            // Setting points hold beyond the old interval end; fixed manual120 frames are the oracle.
            while StepData.StepCount>0 do StepData.DeleteStep(0);
            StepData.AddSettingPoint(0.5,StepConfig.ToJSON); StepData.AddSettingPoint(1.5,'{"visibility":{}}');
            StepPattern.ConfigJSON := StepData.ConfigJSON; TransformDocument.UpdatePattern(StepPattern);
            Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
            TFile.WriteAllText(TPath.Combine(Dir,'sdk-real-setting-points.json'),TransformedJSON,TEncoding.UTF8);
            for I := 0 to 15 do begin
              case I mod 4 of 0: Obj.Time := 0.1; 1: Obj.Time := 0.55; 2: Obj.Time := 0.75; else Obj.Time := 1.95; end;
              Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL setting point');
              if I mod 4=1 then Check(Hash(Captured)=ManualStepHash,'point did not hold beyond legacy end')
              else Check(Hash(Captured)=NormalHash,'point next boundary/rest mismatch');
            end;
            Writeln('VIDEO_LOADED_DLL_SETTING_POINTS_HOLD_NEXT_EXCLUSIVE_BOUNDARY_REVERSE_SEEK_FROZEN_MANUAL_RGBA_OK');
            while StepData.StepCount>0 do StepData.DeleteStep(0);
            StepData.AddStep(0.5,0.5,StepConfig.ToJSON); StepPattern.ConfigJSON := StepData.ConfigJSON;
            TransformDocument.UpdatePattern(StepPattern);
            Check(TransformDocument.AddBeatPlacement(0,StepSlot,StepPattern.ID,0.75,0.125,Error),Error);
            Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
            for I := 0 to 8 do begin
              case I mod 3 of 0: Obj.Time := 0.3; 1: Obj.Time := 0.4; else Obj.Time := 0.45; end;
              Check(StepReference.Render(TransformedJSON,Obj.Time,960,540,ExpectedStep,Error),Error);
              Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL overlap rest');
              Check(Hash(Captured)=Hash(ExpectedStep),'DLL overlap rest differs from editor snapshot');
              if I mod 3=1 then Check(Hash(Captured)=NormalHash,'newer resting clip revived old step')
              else Check(Hash(Captured)<>NormalHash,'underlying clip did not resume');
            end;
            TFile.WriteAllText(TPath.Combine(Dir,'sdk-real-step-overlap-rest.json'),TransformedJSON,TEncoding.UTF8);
            TransformDocument.RemovePlacement(0,StepSlot,1);
            Writeln('VIDEO_LOADED_DLL_NEWER_PERFORMANCE_REST_MASKS_OLDER_STEP_END_RESUMES_RGBA_OK');
            TempoData := TMusicStudioTempoPatternData.Create;
            try
              ManualJSON := TransformDocument.ManualTimingJSON;
              TempoIndex := TransformDocument.AddTempo; TempoPattern := TransformDocument.PatternAt(TempoIndex);
              TempoData.ImportSnapshot(TPath.Combine(Dir,'lyrics.mid'),'{"tempoPoints":[{"beat":0,"bpm":60},{"beat":2,"bpm":120}]}',4);
              TempoPattern.ConfigJSON := TempoData.ConfigJSON; TransformDocument.UpdatePattern(TempoPattern);
              TempoSlot := TransformDocument.AddSlot(0,'tempo');
              Check(TransformDocument.AddBeatPlacement(0,TempoSlot,TempoPattern.ID,0,4,Error),Error);
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error);
              Check(TransformDocument.ManualTimingJSON=ManualJSON,'SDK tempo clip flattened manual timing');
              PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
              for I := 0 to 14 do begin
                case I mod 5 of 0: Obj.Time := 0; 1: Obj.Time := 0.3; 2: Obj.Time := 0.5;
                  3: Obj.Time := 0.75; else Obj.Time := 1; end;
                Check(StepReference.Render(TransformedJSON,Obj.Time,960,540,ExpectedStep,Error),Error);
                Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL effective tempo');
                Check(Hash(Captured)=Hash(ExpectedStep),'DLL effective tempo disagrees with editor snapshot');
                if I mod 5 in [2,3] then Check(Hash(Captured)<>NormalHash,'tempo clip did not shift step onset')
                else Check(Hash(Captured)=NormalHash,'tempo clip rest/end incorrect');
              end;
              TFile.WriteAllText(TPath.Combine(Dir,'sdk-real-tempo-steps.json'),TransformedJSON,TEncoding.UTF8);
              Check(TransformDocument.SetTempoAtBeat(0,120,TempoScope,Error),Error);
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
              Check(TransformDocument.ManualTimingJSON=ManualJSON,'cursor clip edit changed manual map');
              Check(TransformDocument.PatternAt(TempoIndex).ConfigJSON=TempoData.ConfigJSON,'cursor clip edit changed imported source');
              for I := 0 to 5 do begin
                if I mod 2=0 then Obj.Time := 0.3 else Obj.Time := 0.75;
                Check(StepReference.Render(TransformedJSON,Obj.Time,960,540,ExpectedStep,Error),Error);
                Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL cursor BPM correction');
                Check(Hash(Captured)=Hash(ExpectedStep),'DLL clip-local BPM correction mismatched snapshot');
                if I mod 2=0 then Check(Hash(Captured)<>NormalHash,'cursor BPM failed to recompute onset')
                else Check(Hash(Captured)=NormalHash,'cursor BPM failed to recompute end');
              end;
              Writeln('VIDEO_LOADED_DLL_CURSOR_BPM_CLIP_OVERRIDE_ONLY_ONSET_END_REVERSE_SEEK_RGBA_OK');
              Check(TransformDocument.MoveBeatPlacement(0,TempoSlot,0,2,4,Error),Error);
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error);
              PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON); Obj.Time := 0.3;
              Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL moved tempo');
              Check(Hash(Captured)<>NormalHash,'moved tempo left stale onset');
              TransformDocument.RemovePlacement(0,TempoSlot,0); Check(TransformDocument.TrySave(TransformedJSON,Error),Error);
              PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON); Obj.Time := 0.75;
              Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL deleted tempo');
              Check(Hash(Captured)=NormalHash,'deleted tempo left active layer step');
              Check(TransformDocument.ManualTimingJSON=ManualJSON,'tempo movement changed manual timing');
              Writeln('VIDEO_LOADED_DLL_EFFECTIVE_TEMPO_STEP_ONSET_END_MOVE_DELETE_RGBA_MATCH_OK');
              // Decimal tempo pixels use neutral mouth; the earlier SDK cases cover singing precedence.
              for X := 0 to High(TransformDocument.TrackAt(0).Slots) do
                if TransformDocument.TrackAt(0).Slots[X].Kind='singing' then
                  while Length(TransformDocument.TrackAt(0).Slots[X].Clips)>0 do TransformDocument.RemovePlacement(0,X,0);
              TempoData.ImportSnapshot(TPath.Combine(Dir,'lyrics.mid'),'{"tempoPoints":[{"beat":0,"bpm":60},{"beat":0.1,"bpm":180}]}',4);
              TempoPattern.ConfigJSON := TempoData.ConfigJSON; TransformDocument.UpdatePattern(TempoPattern);
              Check(TransformDocument.MoveBeatPlacement(0,StepSlot,0,4,4,Error),Error);
              Check(TransformDocument.AddBeatPlacement(0,TempoSlot,TempoPattern.ID,4,4,Error),Error);
              Check(TransformDocument.Timing.BPMAt(4.1)=180,'fractional global boundary was dropped');
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
              Obj.Time := 2.25; Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL decimal source');
              Check(Hash(Captured)=ManualStepHash,'DLL decimal source did not match frozen constant-manual active RGBA');
              Check(TransformDocument.SetTempoAtBeat(4.1,90,TempoScope,Error),Error);
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
              for I := 0 to 8 do begin
                case I mod 3 of 0: Obj.Time := 2.3; 1: Obj.Time := 2.45; else Obj.Time := 2.8; end;
                Check(StepReference.Render(TransformedJSON,Obj.Time,960,540,ExpectedStep,Error),Error);
                Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL decimal override');
                Check(Hash(Captured)=Hash(ExpectedStep),'DLL decimal override mismatch');
                if I mod 3=1 then Check(Hash(Captured)=ManualStepHash,'decimal active RGBA did not match frozen constant-manual reference')
                else Check(Hash(Captured)=NormalHash,'decimal override rest incorrect');
              end;
              Writeln('VIDEO_LOADED_DLL_DECIMAL_4_PLUS_0_1_BOUNDARY_AND_CURSOR_OVERRIDE_RGBA_OK');
              Writeln('VIDEO_DECIMAL_ANALYTIC_TIMES_MATCH_FROZEN_MANUAL120_RGBA_REFERENCE_NO_VIDEOSESSION_EXPECTATION_OK');
              // At global4.1/source0.1 use analytic times and the frozen manual frames, never relative subtraction.
              while StepData.StepCount>0 do StepData.DeleteStep(0);
              StepData.AddSettingPoint(0,'{"visibility":{}}'); StepData.AddSettingPoint(0.1,StepConfig.ToJSON);
              StepPattern.ConfigJSON := StepData.ConfigJSON; TransformDocument.UpdatePattern(StepPattern);
              Check(TransformDocument.TrySave(TransformedJSON,Error),Error); PFILTER_ITEM_STRING(Items^[1])^.Value := PChar(TransformedJSON);
              for I := 0 to 8 do begin
                case I mod 3 of 0: Obj.Time := 2.1-1E-9; 1: Obj.Time := 2.1; else Obj.Time := 2.1+1E-9; end;
                Check(Table^.Func_Proc_Video(PFILTER_PROC_VIDEO(@Video))=1,'DLL decimal setting point');
                if I mod 3=0 then Check(Hash(Captured)=NormalHash,'DLL decimal point before mismatch')
                else Check(Hash(Captured)=ManualStepHash,'DLL decimal point boundary stale setting');
              end;
              Writeln('VIDEO_LOADED_DLL_SETTING_POINT_GLOBAL4_SOURCE0_1_BEFORE_EQUAL_AFTER_REVERSE_FROZEN_RGBA_OK');
            finally TempoData.Free; end;
          finally StepReference.Free; StepConfig.Free; StepLayers.Free; StepData.Free; TransformDocument.Free; end;
        finally Store.Free; end;
        Writeln('VIDEO_LOADED_DLL_SDK_CALLBACK_RGBA_OVERLAY_LOCALTIME_BOUNDARIES_OK');
      finally
        FreeAndNil(SDKFramebuffer);
        PFILTER_ITEM_STRING(Items^[1])^.Value := SavedValue;
        Table^.Func_Destroy(222,OtherData); Table^.Func_Destroy(111,Data);
      end;
    finally Uninitialize; end;
  finally FreeLibrary(Module); end;
end;

procedure RunVideoOutputChecks(const PluginPath, OutputDir: string);
var Dir,Psd,Midi,JSON,OriginalHash: string; G: TGUID;
begin
  CreateGUID(G); Dir := TPath.Combine(OutputDir,'video-'+GUIDToString(G)); ForceDirectories(Dir);
  Psd := TPath.Combine(Dir,'original.psd'); Midi := TPath.Combine(Dir,'lyrics.mid'); Fixture(Psd); LyricMidi(Midi);
  OriginalHash := THashSHA2.GetHashStringFromFile(Psd);
  SessionChecks(Dir,Psd,Midi,JSON); RunHostBackgroundChecks(Dir,Psd,Midi);
  SDKChecks(PluginPath,Dir,Psd,Midi);
  Check(OriginalHash=THashSHA2.GetHashStringFromFile(Psd),'original PSD changed');
  Writeln('VIDEO_OUTPUT_NO_AUDIO_OK '+Dir);
end;

end.
