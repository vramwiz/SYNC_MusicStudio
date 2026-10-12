unit SYNC_MusicStudio_MotionChecks;

// 純粋なJSON/拍→変形/透過画像と無音UI時計だけを検証する。
// 音声再生・音声デコード・MIDI/PSDファイル解析を呼ばない独立チェック。
interface
procedure RunMotionChecks(const Root: string);

implementation

uses System.Classes, System.SysUtils, System.JSON, System.Math, System.IOUtils, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_MotionData, SYNC_MusicStudio_MotionFrame;

type
  TPixelBGRA = packed record B,G,R,A: Byte; end;
  TPixelRow = array[0..MaxInt div SizeOf(TPixelBGRA)-1] of TPixelBGRA;
  PPixelRow = ^TPixelRow;
  TTestForm = class(TForm)
    procedure ScaleTo144;
  end;

procedure TTestForm.ScaleTo144;
begin ChangeScale(144,CurrentPPI,True); end;

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;

procedure Near(Expected, Actual: Double; const Text: string);
begin Check(Abs(Expected-Actual) < 0.000001,Text); end;

procedure ClearImage(Image: TBitmap; W: Integer = 5; H: Integer = 5);
var Y: Integer;
begin
  Image.PixelFormat := pf32bit; Image.SetSize(W,H); Image.AlphaFormat := afPremultiplied;
  for Y := 0 to H-1 do FillChar(Image.ScanLine[Y]^,W*4,0);
end;

procedure SetPixel(Image: TBitmap; X,Y: Integer; B,G,R,A: Byte);
var Row: PPixelRow;
begin Row := Image.ScanLine[Y]; Row[X].B := B; Row[X].G := G; Row[X].R := R; Row[X].A := A; end;

function Pixel(Image: TBitmap; X,Y: Integer): TPixelBGRA;
var Row: PPixelRow;
begin Row := Image.ScanLine[Y]; Result := Row[X]; end;

function Digest(Image: TBitmap): UInt64;
var X,Y: Integer; Row: PPixelRow;
begin
  Result := 0;
  for Y := 0 to Image.Height-1 do begin Row := Image.ScanLine[Y];
    for X := 0 to Image.Width-1 do Inc(Result,UInt64(PCardinal(@Row[X])^)*UInt64(1+X+Y*Image.Width));
  end;
end;

procedure TestConfig;
var Config: TMusicStudioMotionConfig; Value: TJSONValue; Obj: TJSONObject; Before: string;
  Failed: Boolean;
begin
  Config := TMusicStudioMotionConfig.Create;
  try
    Config.LoadJSON('{"futureRoot":{"keep":true},"rhythm":{"type":"pendulum",'+
      '"strength":25,"speed":2,"futureRhythm":"keep"},'+
      '"transform":{"scalePercent":80,"futureTransform":[1,2]}}');
    Config.ShiftBeats := 0.25;
    Value := TJSONObject.ParseJSONValue(Config.ToJSON);
    try
      Obj := TJSONObject(Value);
      Check(Obj.GetValue('futureRoot') <> nil,'Motion root extension lost');
      Check(TJSONObject(Obj.GetValue('rhythm')).GetValue('futureRhythm').Value = 'keep',
        'Motion rhythm extension lost');
      Check(TJSONObject(Obj.GetValue('transform')).GetValue('futureTransform') is TJSONArray,
        'Motion transform extension lost');
    finally Value.Free; end;
    Before := Config.ToJSON;
    Failed := False;
    try Config.LoadJSON('{"rhythm":{"speed":0}}'); except on EArgumentException do Failed := True; end;
    Check(Failed and (Before = Config.ToJSON),'Invalid load changed valid motion config');
    Failed := False;
    try Config.LoadJSON('{"version":2}'); except on EArgumentException do Failed := True; end;
    Check(Failed,'Future motion schema silently accepted');
    Failed := False;
    try Config.LoadJSON('{"rhythm":{"type":"horizontalJump"}}'); except on EArgumentException do Failed := True; end;
    Check(Failed,'Removed motion type shown as supported');
    Failed := False;
    try Config.LoadJSON('{"transform":{"x":"bad"}}'); except on EArgumentException do Failed := True; end;
    Check(Failed,'Nonnumeric motion accepted');
  finally Config.Free; end;
end;

procedure TestMathAndImages;
var Config: TMusicStudioMotionConfig; T: TMusicStudioMotionTransform;
  Source, Dest: TBitmap; Kind: TMusicStudioRhythmType; Phase: Integer;
  Original: UInt64; Failed: Boolean;
begin
  Config := TMusicStudioMotionConfig.Create; Source := TBitmap.Create; Dest := TBitmap.Create;
  try
    CalculateMusicStudioRhythmTransform(rmtVerticalJump,0,2,50,T); Check(T.OffsetY = 0,'Jump start moved');
    CalculateMusicStudioRhythmTransform(rmtVerticalJump,0.45,2,50,T); Check(T.OffsetY = -50,'Jump apex mismatch');
    CalculateMusicStudioRhythmTransform(rmtVerticalJump,1,2,50,T); Check(T.OffsetY = 0,'Jump beat boundary mismatch');
    CalculateMusicStudioRhythmTransform(rmtShrink,0.25,2,100,T); Near(0.75,T.Scale,'Shrink curve mismatch');
    CalculateMusicStudioRhythmTransform(rmtPendulum,0.25,2,50,T); Near(50,T.TopOffsetX,'Pendulum phase mismatch');
    CalculateMusicStudioRhythmTransform(rmtPendulumTwoBeat,0,2,50,T); Near(-50,T.TopOffsetX,'Two-beat pendulum start mismatch');
    CalculateMusicStudioRhythmTransform(rmtPendulumTwoBeat,1,2,50,T); Near(50,T.TopOffsetX,'Two-beat pendulum phase mismatch');
    for Kind := Low(Kind) to High(Kind) do for Phase := -20 to 80 do begin
      CalculateMusicStudioRhythmTransform(Kind,Phase/20.0,2,100,T);
      Check(not IsNan(T.Scale) and not IsInfinite(T.Scale) and (T.Scale > 0) and
        (T.VerticalScale > 0),'Nonfinite rhythm transform');
    end;
    ClearImage(Source); SetPixel(Source,2,2,0,0,255,255); Original := Digest(Source);
    CalculateMusicStudioRhythmTransform(rmtVerticalJump,0.45,2,1,T);
    RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,2,1).R = 255) and (Digest(Source) = Original),'Jump changed source or moved wrong pixel');
    Dest.Assign(Source); RenderMusicStudioMotion(Source,Dest,T);
    Check(Digest(Source) = Original,'Shared output DIB modified source');
    ClearImage(Source); SetPixel(Source,1,0,0,0,255,255); SetPixel(Source,2,4,0,255,0,255);
    CalculateMusicStudioRhythmTransform(rmtPendulum,0.25,2,2.4,T); RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,3,0).R = 255) and (Pixel(Dest,2,4).G = 255),'Pendulum anchor differs from reference');
    ClearImage(Source); SetPixel(Source,2,0,128,0,0,128);
    Config.RhythmType := rmtNone; Config.RotationDegrees := 90;
    CalculateMusicStudioMotionTransform(Config,0,T); Original := Digest(Source);
    RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,4,2).B = 128) and (Pixel(Dest,4,2).A = 128) and
      (Digest(Source) = Original),'Rotation/alpha/original retention failed');
    Config.RotationDegrees := 0; Config.OffsetX := 1;
    CalculateMusicStudioMotionTransform(Config,0,T); RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,3,0).A = 128) and (Pixel(Dest,2,0).A = 0),'Static offset did not apply');
    Config.OffsetX := 0; Config.RhythmType := rmtVerticalJump; Config.ShiftBeats := 0.25;
    CalculateMusicStudioMotionTransform(Config,0.70,T); Check(T.OffsetY = -50,'Beat shift not applied before motion');
    ClearImage(Source,1,1); SetPixel(Source,0,0,32,64,96,128);
    CalculateMusicStudioRhythmTransform(rmtNone,0,2,0,T); RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,0,0).A = 128) and (Pixel(Dest,0,0).R = 96),'Single-pixel image alpha changed');
    Source.PixelFormat := pf24bit; Source.SetSize(3,2); Source.Canvas.Brush.Color := clRed;
    Source.Canvas.FillRect(Rect(0,0,3,2)); RenderMusicStudioMotion(Source,Dest,T);
    Check((Pixel(Dest,0,0).R = 255) and (Pixel(Dest,0,0).A = 255), 'Opaque input became transparent');
    Failed := False;
    try RenderMusicStudioMotion(Source,Source,T); except on EArgumentException do Failed := True; end;
    Check(Failed,'In-place motion silently altered source');
    Source.SetSize(0,0); RenderMusicStudioMotion(Source,Dest,T); Check(Dest.Empty,'Empty bitmap not cleared');
  finally Dest.Free; Source.Free; Config.Free; end;
end;

procedure SaveForm(Form: TForm; const Path: string);
var Bitmap: TBitmap; Png: TPngImage;
begin
  Application.ProcessMessages; Bitmap := Form.GetFormImage; Png := TPngImage.Create;
  try Png.Assign(Bitmap); Png.SaveToFile(Path); finally Png.Free; Bitmap.Free; end;
end;

procedure TestFrame(const Root: string);
var Form: TTestForm; Frame: TMusicStudioMotionFrame; Image: TBitmap;
  X,Y,Count: Integer; Start: UInt64; Original: UInt64; Saved: string;
begin
  Form := TTestForm.CreateNew(nil); Image := TBitmap.Create;
  try
    Form.Caption := 'SYNC Motion 無音設定確認'; Form.SetBounds(50,50,840,540);
    Frame := TMusicStudioMotionFrame.Create(Form);
    Frame.LoadMotion(''); Frame.PreviewTempoBPM := 90; Frame.PreviewBeatPosition := 0.5;
    Frame.Parent := Form; Frame.Align := alClient;
    ClearImage(Image,160,240);
    for Y := 40 to 214 do for X := 44 to 115 do SetPixel(Image,X,Y,150,210,235,255);
    for Y := 22 to 66 do for X := 57 to 102 do SetPixel(Image,X,Y,200,225,245,255);
    Original := Digest(Image);
    Frame.LoadMotion(''); Frame.PreviewBitmap(Image);
    SetPixel(Image,75,80,0,0,0,0); Frame.PreviewBeatPosition := 0.5;
    Check(Digest(Frame.RenderedBitmap) = Original,'Preview copy shared caller pixel buffer');
    SetPixel(Image,75,80,150,210,235,255);
    Frame.LoadMotion('{"rhythm":{"type":"pendulum","strength":18,"speed":2},'+
      '"transform":{"scalePercent":90}}');
    Frame.PreviewBitmap(Image); Check(Digest(Image) = Original,'Frame modified caller bitmap');
    Frame.PreviewTempoBPM := 120; Frame.PreviewBeatPosition := 0.25;
    Saved := Frame.ConfigJSON; Count := Frame.RenderCount;
    for X := 1 to 100 do Frame.PreviewBeatPosition := 0.25;
    Check((Frame.RenderCount = Count) and (Saved = Frame.ConfigJSON),'Same preview state regenerated or changed JSON');
    Check(Frame.RenderedBitmap.Width = 160,'Preview dimensions changed');
    Form.Show; SaveForm(Form,TPath.Combine(Root,'motion-settings-normal.png'));
    Form.Width := 620; Form.Height := 410; SaveForm(Form,TPath.Combine(Root,'motion-settings-minimum.png'));
    Form.Width := 840; Form.Height := 540; Form.ScaleTo144;
    SaveForm(Form,TPath.Combine(Root,'motion-settings-144dpi.png'));
    Count := Frame.RenderCount; Frame.StartSilentPreview;
    Check(Frame.IsPreviewing,'Silent visual preview did not start');
    Start := GetTickCount64;
    while (Frame.RenderCount = Count) and (GetTickCount64-Start < 1000) do begin
      Application.ProcessMessages; Sleep(5);
    end;
    Frame.StopSilentPreview;
    Check((Frame.RenderCount > Count) and not Frame.IsPreviewing,'Silent preview timer failed');
    Check(Saved = Frame.ConfigJSON,'Preview clock changed shared motion settings');
    Frame.PreviewBitmap(nil); Frame.StartSilentPreview;
    Check(not Frame.IsPreviewing and Frame.RenderedBitmap.Empty,'Unassigned visual preview started');
    Frame.PreviewBitmap(Image); Frame.StartSilentPreview; Frame.Free;
    Application.ProcessMessages;
  finally Image.Free; Form.Free; end;
end;

procedure RunMotionChecks(const Root: string);
begin
  ForceDirectories(Root);
  TestConfig; Writeln('MOTION_JSON_OK'); Flush(Output);
  TestMathAndImages; Writeln('MOTION_MATH_BITMAP_OK'); Flush(Output);
  TestFrame(Root); Writeln('MOTION_SILENT_FRAME_OK'); Flush(Output);
end;

end.
