unit SYNC_MusicStudio_LayerStepChecks;

// 所有VCL画面・TempのPSD/MIDIだけ。拍保存、step合成、tempo境界と旧編集機能を無音検証。
interface
procedure RunLayerStepChecks(const Root: string);
procedure RunLayerStepPointChecks(const Root: string);
procedure RunLayerStepTailReview(const Root: string);
procedure RunLayerStepBoundaryReview(const Root: string);
procedure RunLayerStepRealPointDemo(const Root,Source,SeedJSON: string);
procedure RunCompactPointErrorChecks(const Root: string);
procedure RunLayerObjectChecks(const Root: string);
procedure RunObjectReviewChecks(const Root: string; MinimumDPI: Boolean);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Hash, System.Math,
  System.Types, System.UITypes, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.ExtCtrls, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_LayerStepData, SYNC_MusicStudio_BeatData, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerConfig,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_LayerStepFrame, SYNC_MusicStudio_SettingsForm,
  SYNC_MusicStudio_TestHelpers, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_VideoRenderer, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_SingingData, SYNC_MusicStudio_PsdTransform;
type TStepDialogDriver = class
    Timer: TTimer;
    Save,Seen,Added,UsePoints: Boolean;
    Deadline: UInt64;
    procedure Tick(Sender: TObject);
  end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('Layer steps: '+Message); end;
procedure Same(A,B: Double; const Message: string);
begin Check(Abs(A-B)<1E-8,Message+Format(' (%g / %g)',[A,B])); end;
function LayerKey(D: TMusicStudioLayerDocument; const Name: string): string; forward;
procedure TStepDialogDriver.Tick(Sender: TObject);
var I: Integer; D: TMusicStudioPatternSettings;
begin
  Check(GetTickCount64<Deadline,'modal dialog timeout');
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]); if D.LayerStepFrame=nil then Continue;
    D.LayerStepFrame.LayerEditor.PollResults; if not D.LayerStepFrame.LayerEditor.CanApply then Exit;
    Seen := True;
    if not Added then begin
      if UsePoints then begin D.LayerStepFrame.SeekBeat(3.25); Check(D.LayerStepFrame.LayerEditor.SetLayerVisibility(LayerKey(D.LayerStepFrame.LayerEditor.Document,'leg'),True),'modal point check'); end
      else D.LayerStepFrame.AddStep(3.25);
      Added := True; Exit;
    end;
    Timer.Enabled := False; if Save then D.ModalResult := mrOK else D.ModalResult := mrCancel; Exit;
  end;
end;
procedure MidiFixture(const Path: string);
const Bytes: array[0..57] of Byte = ($4D,$54,$68,$64,0,0,0,6,0,0,0,1,$01,$E0,
  $4D,$54,$72,$6B,0,0,0,36,0,$FF,5,3,$E3,$81,$82,0,$90,60,100,
  $83,$60,$80,60,0,0,$FF,5,3,$E3,$81,$84,0,$90,64,100,$83,$60,$80,64,0,0,$FF,$2F,0);
var Stream: TFileStream;
begin Stream := TFileStream.Create(Path,fmCreate); try Stream.WriteBuffer(Bytes,SizeOf(Bytes)); finally Stream.Free; end; end;
function Text(Document: TMusicStudioDocument): string;
var Error: string;
begin Check(Document.TrySave(Result,Error),Error); end;
procedure Fixture(const Path: string);
var D: TArtDocument; G,L: TArtLayer;
  procedure Image(Parent: TArtLayer; const Name: string; X,Y: Integer; R,G,B: Byte; Visible: Boolean);
  var I: Integer;
  begin
    L := D.AddLayer(alkImage,Name,TArtBounds.Create(X,Y,X+4,Y+4),Parent); L.Visible := Visible; SetLength(L.Pixels,64);
    for I := 0 to 15 do begin L.Pixels[I*4] := R; L.Pixels[I*4+1] := G; L.Pixels[I*4+2] := B; L.Pixels[I*4+3] := 255; end;
  end;
begin
  D := TArtDocument.Create;
  try
    D.Width := 64; D.Height := 40;
    G := D.AddLayer(alkGroup,'mouth',TArtBounds.Create(0,0,0,0)); G.BlendKey := 'norm';
    Image(G,'*normal',24,8,0,255,0,True); Image(G,'*a',24,8,255,0,0,False);
    G := D.AddLayer(alkGroup,'pose',TArtBounds.Create(0,0,0,0)); G.BlendKey := 'norm';
    Image(G,'*idle',4,8,0,255,0,True); Image(G,'*hit',4,8,255,0,0,False); Image(G,'*expression',4,8,0,0,255,False);
    Image(nil,'arm',16,8,230,180,0,False); Image(nil,'leg',20,8,230,0,200,False);
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
function LayerKey(D: TMusicStudioLayerDocument; const Name: string): string;
var L: TMusicStudioLayerInfo;
begin for L in D.Layers do if L.Name=Name then Exit(L.Key); raise Exception.Create('Missing layer '+Name); end;
procedure Capture(F: TForm; const Path: string);
var B: TBitmap; PNG: TPngImage; DC,MemoryDC: HDC; Origin: TPoint;
  Info: TBitmapInfo; Pixels: Pointer; Dib,Old: HGDIOBJ;
begin
  Origin := F.ClientToScreen(Point(0,0)); SetWindowPos(F.Handle,0,F.Left-Origin.X,F.Top-Origin.Y,0,0,SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  F.Repaint; Application.ProcessMessages; B := TBitmap.Create; PNG := TPngImage.Create;
  try DC := GetDC(F.Handle); Check(DC<>0,'native capture window DC'); MemoryDC := CreateCompatibleDC(DC);
    FillChar(Info,SizeOf(Info),0); Info.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
    Info.bmiHeader.biWidth := F.ClientWidth; Info.bmiHeader.biHeight := -F.ClientHeight;
    Info.bmiHeader.biPlanes := 1; Info.bmiHeader.biBitCount := 32;
    Dib := CreateDIBSection(DC,Info,DIB_RGB_COLORS,Pixels,0,0); Check(Dib<>0,'native capture DIB'); Old := SelectObject(MemoryDC,Dib);
    try Check(BitBlt(MemoryDC,0,0,F.ClientWidth,F.ClientHeight,DC,0,0,SRCCOPY),'native capture error '+IntToStr(GetLastError));
    finally SelectObject(MemoryDC,Old); DeleteDC(MemoryDC); ReleaseDC(F.Handle,DC); end;
    B.Handle := Dib;
    PNG.Assign(B); PNG.SaveToFile(Path);
  finally PNG.Free; B.Free; end;
end;
procedure WaitEditor(F: TMusicStudioLayerStepFrame);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  repeat F.LayerEditor.PollResults; Application.ProcessMessages;
    if F.LayerEditor.CanApply then Exit;
    Check(GetTickCount64<Deadline,F.LayerEditor.StateText); Sleep(2);
  until False;
end;
procedure Model;
var D: TMusicStudioLayerStepData; Step: TMusicStudioLayerStep; Before: string; I: Integer;
begin
  D := TMusicStudioLayerStepData.Create;
  try
    D.LoadJSON('{"lengthBeats":8,"future":{"keep":true},"notes":[{"startBeat":0.123,"lengthBeats":0.7,"pitch":60,"velocity":93,"extra":"note"}],"layerSteps":{"version":1,"assetId":"00000000-0000-0000-0000-000000000001","extra":"keep","steps":[]}}');
    I := D.AddStep(0.123,0.731,'{"visibility":{"key":true},"extra":"config"}'); Step := D.StepAt(I); Before := D.ConfigJSON;
    try D.LengthBeats := 0.5; Check(False,'shortening silently erased'); except on E: EArgumentException do ; end;
    Check(D.ConfigJSON=Before,'failed shortening changed JSON');
    Same(D.StepAt(0).StartBeat,0.123,'off-grid start'); Same(D.StepAt(0).LengthBeats,0.731,'off-grid length');
    Check(D.ActiveStepAt(0.122)=-1,'step onset'); Check(D.ActiveStepAt(0.123)=0,'step start'); Check(D.ActiveStepAt(0.854)=-1,'step exclusive end');
    try D.LoadJSON('{"lengthBeats":8,"layerSteps":{"assetId":"","steps":[{}]}}'); Check(False,'invalid accepted'); except on E: EArgumentException do ; end;
    Check(D.ConfigJSON=Before,'invalid load adopted'); D.LoadJSON(Before); Check(Pos('note',D.ConfigJSON)>0,'legacy note extension lost');
    Check(Pos('config',D.ConfigJSON)>0,'step config extension lost'); Check(D.StepAt(0).ID=Step.ID,'stable ID roundtrip');
    D.DeleteStep(0); Check(D.StepCount=0,'delete'); Writeln('PASS step model validation/off-grid/stable IDs/extensions/shortening refusal/rest');
  finally D.Free; end;
end;
procedure Pixel(const Pixels: TMusicStudioVideoPixels; X,Y: Integer; R,G,B,A: Byte; const Message: string);
begin Check((Pixels[Y*64+X].R=R) and (Pixels[Y*64+X].G=G) and (Pixels[Y*64+X].B=B) and (Pixels[Y*64+X].A=A),Message); end;
procedure RunLayerStepTailReview(const Root: string);
var Dialog: TMusicStudioPatternSettings; D: TMusicStudioLayerStepData; P: TMusicStudioPattern;
  Dir,Source,Arm: string; R: TRect;
begin
  Dir := TPath.Combine(Root,'tail-point'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source);
  D := TMusicStudioLayerStepData.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
  try
    D.Enable('00000000-0000-0000-0000-000000000001'); D.LengthBeats := 8;
    D.AddSettingPoint(7.9998,'{"visibility":{}}'); P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '末尾設定点'; P.Color := '#80B0E0'; P.ConfigJSON := D.ConfigJSON;
    Dialog.LoadPerformanceSteps(P,D.AssetID,Source,'{}',120); Dialog.Show; WaitEditor(Dialog.LayerStepFrame);
    Dialog.LayerStepFrame.SelectStep(0); WaitEditor(Dialog.LayerStepFrame);
    Same(Dialog.LayerStepFrame.CursorBeat,7.9998,'tail exact cursor'); Check(Dialog.LayerStepFrame.SelectedStep=0,'tail selection lost');
    Arm := LayerKey(Dialog.LayerStepFrame.LayerEditor.Document,'arm'); Check(Dialog.LayerStepFrame.LayerEditor.SetLayerVisibility(Arm,True),'tail edit'); WaitEditor(Dialog.LayerStepFrame);
    Check(Dialog.LayerStepFrame.Data.StepCount=1,'tail edit created duplicate'); Dialog.LayerStepFrame.DeleteSelected; Check(Dialog.LayerStepFrame.Data.StepCount=0,'tail delete');
    Dialog.LayerStepFrame.UndoEdit; WaitEditor(Dialog.LayerStepFrame); Check(Dialog.LayerStepFrame.Data.StepCount=1,'tail delete undo');
    R := Dialog.LayerStepFrame.MarkerRect(0);
    Dialog.LayerStepFrame.StepGrid.Perform(WM_RBUTTONDOWN,0,LPARAM(((R.Top+R.Bottom) div 2 shl 16) or ((R.Left+R.Right) div 2)));
    Check(Dialog.LayerStepFrame.Data.StepCount=0,'tail right click delete');
    Writeln('POINT_REVIEW_END_MINUS_0_0002_EXACT_SELECT_EDIT_DELETE_UNDO_RIGHT_CLICK_OK');
  finally Dialog.Free; D.Free; end;
end;
procedure RunLayerStepBoundaryReview(const Root: string);
var Main: TFormMusicStudioSettings; D: TMusicStudioLayerStepData; Asset: TMusicStudioPsdAsset; P: TMusicStudioPattern;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Layers: TMusicStudioLayerDocument;
  Dir,Source,Arm,Leg,Error,JSON: string; I,Track,Slot: Integer; Dup: Boolean; T: Double;
begin
  Dir := TPath.Combine(Root,'point-boundary'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source);
  Main := TFormMusicStudioSettings.Create(nil); D := TMusicStudioLayerStepData.Create; Layers := TMusicStudioLayerDocument.Create; Video := nil;
  try
    Main.SilentVisualMode := True; Main.LibraryRoot := TPath.Combine(Dir,'library'); Main.LoadDocument('');
    Check(Main.SharedLibrary.TryImport(Source,'小数設定点','#80B0E0',Asset,Dup,Error),Error); Check(Layers.LoadFile(Asset.FilePath),Layers.LastError);
    Arm := LayerKey(Layers,'arm'); Leg := LayerKey(Layers,'leg'); Track := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Track,Asset.ID); Slot := Main.Document.AddSlot(Track,'performance');
    I := Main.Document.AddPerformance; P := Main.Document.PatternAt(I); D.LoadJSON(P.ConfigJSON); D.Enable(Asset.ID); D.LengthBeats := 8;
    D.AddSettingPoint(0,'{"visibility":{"'+Arm+'":true}}'); D.AddSettingPoint(0.1,'{"visibility":{"'+Arm+'":false,"'+Leg+'":true}}');
    P.ConfigJSON := D.ConfigJSON; Main.Document.UpdatePattern(P); Check(Main.Document.AddBeatPlacement(Track,Slot,P.ID,4,8,Error),Error);
    JSON := Text(Main.Document); Video := TMusicStudioVideoSession.Create(Main.LibraryRoot);
    for I := 0 to 8 do begin
      case I mod 3 of 0: T := (4.1-1E-9)/2; 1: T := 4.1/2; else T := (4.1+1E-9)/2; end;
      Check(Video.Render(JSON,T,64,40,Pixels,Error),Error);
      if I mod 3=0 then begin Pixel(Pixels,17,9,230,180,0,255,'decimal before arm'); Pixel(Pixels,21,9,0,0,0,0,'decimal before leg'); end
      else begin Pixel(Pixels,17,9,0,0,0,0,'decimal boundary stale arm'); Pixel(Pixels,21,9,230,0,200,255,'decimal boundary leg'); end;
    end;
    Writeln('POINT_REVIEW_ABSOLUTE_4_PLUS_0_1_BEFORE_EQUAL_AFTER_REVERSE_SEEK_FIXED_RGBA_OK');
  finally Video.Free; Layers.Free; D.Free; Main.Free; end;
end;
procedure RunLayerStepPointChecks(const Root: string);
var D: TMusicStudioLayerStepData; Main: TFormMusicStudioSettings; Dialog: TMusicStudioPatternSettings;
  F: TMusicStudioLayerStepFrame; Asset: TMusicStudioPsdAsset; P: TMusicStudioPattern;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Driver: TStepDialogDriver;
  Dir,Source,Error,Before,After,Hit,Arm,SourceHash,MetadataHash,ModelText: string;
  I,J,Track,Slot,PatternIndex,RenderBefore,Polls,Blanks: Integer; Dup,Handled: Boolean;
  R: TRect; Point: TPoint; Anchor,Cursor,Start: Double; Key: Word; Deadline: UInt64;
  procedure Mouse(Control: TWinControl; Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin Control.Perform(Msg,Buttons,LPARAM((Y shl 16) or (X and $FFFF))); end;
  procedure ClickGrid(X,Y: Integer);
  begin Mouse(F.StepGrid,WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(F.StepGrid,WM_LBUTTONUP,X,Y); WaitEditor(F); end;
  procedure ToggleLayer(const Name: string);
  var Index: Integer; Row: TRect;
  begin
    Index := F.LayerEditor.Document.LayerIndex(Name); Check(Index>=0,'checkbox layer missing');
    F.LayerEditor.UIControls.LayerList.Perform(LB_SETTOPINDEX,Max(0,Index-1),0);
    Row := F.LayerEditor.UIControls.LayerList.ItemRect(Index);
    Mouse(F.LayerEditor.UIControls.LayerList,WM_LBUTTONDOWN,6,(Row.Top+Row.Bottom) div 2,MK_LBUTTON);
    Mouse(F.LayerEditor.UIControls.LayerList,WM_LBUTTONUP,6,(Row.Top+Row.Bottom) div 2); WaitEditor(F);
  end;
  procedure CheckLayer(const Name: string; Visible: Boolean);
  begin Check(F.LayerEditor.UIControls.LayerList.Checked[F.LayerEditor.Document.LayerIndex(Name)]=Visible,'saved checkbox mismatch'); end;
  procedure PreviewPixel(X,Y: Integer; Color: TColor; const Message: string);
  begin WaitEditor(F); Check((F.LayerEditor.PreviewBitmap<>nil) and (F.LayerEditor.PreviewBitmap.Canvas.Pixels[X,Y]=Color),Message); end;
begin
  D := TMusicStudioLayerStepData.Create;
  try
    D.LoadJSON('{"lengthBeats":8,"future":"keep","notes":[{"startBeat":0.123,"lengthBeats":0.7,"pitch":60,"velocity":93,"extra":"keep"}]}');
    D.Enable('00000000-0000-0000-0000-000000000001');
    D.AddSettingPoint(0,'{"visibility":{"a":true}}'); D.AddSettingPoint(4,'{"visibility":{"b":true}}'); I := D.AddSettingPoint(2,'{"visibility":{"c":true}}');
    Same(D.StepAt(0).LengthBeats,2,'insert did not trim previous point'); Same(D.StepAt(1).LengthBeats,4,'last point end');
    Check(D.ActiveStepAt(1.9)=0,'first hold'); Check(D.ActiveStepAt(2)=I,'exclusive next point'); Check(D.ActiveStepAt(7.99)=1,'last hold'); Check(D.ActiveStepAt(8)=-1,'pattern end');
    D.DeleteStep(I); Same(D.StepAt(0).LengthBeats,4,'delete did not extend previous point');
    D.AddStep(5,0.5,'{"visibility":{"legacy":true}}'); Check(D.ActiveStepAt(5.5)=-1,'legacy rest changed');
    D.LengthBeats := 6; ModelText := D.ConfigJSON; D.LoadJSON(ModelText); Check(D.ConfigJSON=ModelText,'point JSON stable');
    Check(Pos('future',ModelText)>0,'unknown fields lost'); Check(Pos('0.123',ModelText)>0,'old notes lost');
    D.AddSettingPoint(4.0002,'{"visibility":{"close":true}}'); D.LoadJSON(D.ConfigJSON); Same(D.StepAt(1).LengthBeats,0.0002,'close point duration');
    Before := D.ConfigJSON;
    try D.LoadJSON('{"lengthBeats":8,"layerSteps":{"assetId":"00000000-0000-0000-0000-000000000001","steps":[{"id":"bad","startBeat":0,"lengthBeats":1,"holdUntilNext":"yes","config":{}}]}}'); Check(False,'bad point mode accepted'); except on E: EArgumentException do ; end;
    Check(D.ConfigJSON=Before,'bad point load adopted');
    Writeln('POINT_MODEL_NEXT_BOUNDARY_DELETE_EXTEND_LEGACY_REST_TINY_INTERVAL_EXTENSIONS_ATOMIC_OK');
  finally D.Free; end;
  RunLayerStepTailReview(Root); RunLayerStepBoundaryReview(Root); RunCompactPointErrorChecks(Root);
  Dir := TPath.Combine(Root,'step-points'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source); SourceHash := THashSHA2.GetHashStringFromFile(Source);
  Main := TFormMusicStudioSettings.Create(nil); Dialog := nil; Video := nil;
  try
    Main.SilentVisualMode := True; Main.LibraryRoot := TPath.Combine(Dir,'library'); Main.LoadDocument('');
    Check(Main.SharedLibrary.TryImport(Source,'設定点PSD','#80B0E0',Asset,Dup,Error),Error);
    MetadataHash := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'));
    Track := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Track,Asset.ID); Slot := Main.Document.AddSlot(Track,'performance');
    PatternIndex := Main.Document.AddPerformance; P := Main.Document.PatternAt(PatternIndex); D := TMusicStudioLayerStepData.Create;
    try D.LoadJSON(P.ConfigJSON); D.Enable(Asset.ID); D.LengthBeats := 8; P.ConfigJSON := D.ConfigJSON; finally D.Free; end;
    Main.Document.UpdatePattern(P); Main.LoadDocument(Text(Main.Document)); Main.TimelineBox.SelectSlot(Track,Slot); SelectTestPattern(Main,P.ID);
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
    Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True;
    Dialog.LoadPerformanceSteps(P,Asset.ID,Asset.FilePath,Asset.ConfigJSON,120); Dialog.Show; ShowWindow(Dialog.Handle,SW_SHOWNOACTIVATE);
    F := Dialog.LayerStepFrame; WaitEditor(F); Hit := LayerKey(F.LayerEditor.Document,'*hit'); Arm := LayerKey(F.LayerEditor.Document,'arm');
    Check(F.PlayButton.Width=F.StopButton.Width,'transport width'); Before := F.ConfigJSON;
    ClickGrid(F.TimelineHeaderWidth+384,12); Same(F.CursorBeat,4,'measure click cursor'); Check(F.Data.StepCount=0,'click created point'); Check(F.ConfigJSON=Before,'seek changed JSON');
    ToggleLayer(Hit); Check(F.Data.StepCount=1,'check did not create point'); Check(F.Data.StepAt(0).HoldUntilNext,'new point interval mode');
    ClickGrid(F.TimelineHeaderWidth,12); ToggleLayer(Arm); Check(F.Data.StepCount=2,'second check point'); CheckLayer(Arm,True); CheckLayer(Hit,False);
    R := F.MarkerRect(0); Check((R.Width>R.Height) and (R.Left>=F.TimelineHeaderWidth),'interval marker/fixed column'); Before := F.ConfigJSON;
    ClickGrid((R.Left+R.Right) div 2,(R.Top+R.Bottom) div 2); Same(F.CursorBeat,4,'marker cursor');
    Check(F.ConfigJSON=Before,'marker selection mutated'); CheckLayer(Hit,True); CheckLayer(Arm,False);
    ToggleLayer(Hit); Check(F.Data.StepCount=2,'edit added duplicate point'); After := F.ConfigJSON;
    Key := Ord('Z'); Dialog.OnKeyDown(Dialog,Key,[ssCtrl]); WaitEditor(F); Check(F.ConfigJSON=Before,'local undo');
    Key := Ord('Y'); Dialog.OnKeyDown(Dialog,Key,[ssCtrl]); WaitEditor(F); Check(F.ConfigJSON=After,'local redo'); ToggleLayer(Hit);
    F.SeekBeat(2); WaitEditor(F); Before := F.ConfigJSON; Check(F.SelectedStep=-1,'seek selected earlier point'); CheckLayer(Arm,True);
    Check(F.LayerEditor.SetLayerVisibility(Hit,True),'insert middle point'); WaitEditor(F); Check(F.Data.StepCount=3,'middle insertion');
    F.DeleteSelected; WaitEditor(F); Check(F.ConfigJSON=Before,'delete did not restore prior hold lengths');
    F.UndoEdit; WaitEditor(F); Check(F.Data.StepCount=3,'delete undo'); F.RedoEdit; WaitEditor(F); Check(F.ConfigJSON=Before,'delete redo');
    F.Stop; F.Zoom := 384; Before := F.ConfigJSON; Point := F.StepGrid.ClientToScreen(System.Types.Point(F.TimelineHeaderWidth+192,80));
    Anchor := F.ViewStartBeat+192/(F.Zoom*F.CurrentPPI/96); Handled := False;
    F.StepGrid.OnMouseWheel(F.StepGrid,[],120,Point,Handled); Check(Handled,'normal wheel not handled');
    Same(F.ViewStartBeat+192/(F.Zoom*F.CurrentPPI/96),Anchor,'wheel anchor'); Check(F.ConfigJSON=Before,'wheel mutated');
    Cursor := F.CursorBeat; Start := F.ViewStartBeat;
    Mouse(F.StepGrid,WM_LBUTTONDOWN,300,90,MK_LBUTTON); Mouse(F.StepGrid,WM_MOUSEMOVE,230,90,MK_LBUTTON); Mouse(F.StepGrid,WM_LBUTTONUP,230,90);
    Check(F.ViewStartBeat>Start,'drag did not pan'); Same(F.CursorBeat,Cursor,'pan changed cursor'); Check(F.ConfigJSON=Before,'pan mutated JSON');
    Start := F.ViewStartBeat; Mouse(F.StepGrid,WM_LBUTTONDOWN,300,90,MK_LBUTTON); Mouse(F.StepGrid,WM_MOUSEMOVE,230,90,MK_LBUTTON);
    Key := VK_ESCAPE; Dialog.OnKeyDown(Dialog,Key,[]); Same(F.ViewStartBeat,Start,'Escape did not cancel pan'); Check(GetCapture<>F.StepGrid.Handle,'pan capture retained');
    RenderBefore := F.LayerEditor.PreviewRenderCount; Point := F.LayerEditor.UIControls.Preview.ClientToScreen(System.Types.Point(100,100)); Handled := False;
    F.LayerEditor.UIControls.Preview.OnMouseWheel(F.LayerEditor.UIControls.Preview,[],120,Point,Handled); Check(Handled,'PSD normal wheel');
    Mouse(F.LayerEditor.UIControls.Preview,WM_LBUTTONDOWN,100,100,MK_LBUTTON); Mouse(F.LayerEditor.UIControls.Preview,WM_MOUSEMOVE,130,120,MK_LBUTTON); Mouse(F.LayerEditor.UIControls.Preview,WM_LBUTTONUP,130,120);
    Check(F.LayerEditor.ViewPan.X<>0,'PSD pan'); Check(F.ConfigJSON=Before,'PSD view mutated JSON'); Check(F.LayerEditor.PreviewRenderCount=RenderBefore,'view recomposed PSD');
    F.LayerEditor.FitPreview; F.Zoom := 96; F.Stop; PreviewPixel(17,9,RGB(230,180,0),'first point arm');
    F.PlayButton.Click; F.PlaybackTimer.Enabled := False; F.AdvancePlayback(2.25); PreviewPixel(5,9,RGB(255,0,0),'second point hit');
    Same(F.CursorBeat,4.5,'loop advance'); F.AdvancePlayback(2); PreviewPixel(17,9,RGB(230,180,0),'wrap restored first point'); Same(F.CursorBeat,0.5,'loop wrap');
    RenderBefore := F.LayerEditor.PreviewRenderCount;
    for J := 0 to 19 do begin F.AdvancePlayback(2); WaitEditor(F); Check(F.LayerEditor.PreviewBitmap<>nil,'loop blank');
      if J mod 2=0 then PreviewPixel(5,9,RGB(255,0,0),'cached loop stale hit') else PreviewPixel(17,9,RGB(230,180,0),'cached loop stale arm');
    end;
    Check(F.LayerEditor.PreviewRenderCount=RenderBefore,'cached loop recomposed'); Check(F.ConfigJSON=Before,'loop changed JSON');
    F.PlayButton.Click; Check(not F.IsPlaying and not F.PlaybackTimer.Enabled,'pause'); Cursor := F.CursorBeat;
    Deadline := GetTickCount64+80; repeat Application.ProcessMessages; Sleep(2); until GetTickCount64>=Deadline; Same(F.CursorBeat,Cursor,'paused clock advanced');
    F.SeekBeat(7.75); F.PlayButton.Click; Deadline := GetTickCount64+450; Polls := 0; Blanks := 0;
    repeat F.LayerEditor.PollResults; Application.ProcessMessages; Inc(Polls);
      if (F.LayerEditor.PreviewBitmap=nil) or F.LayerEditor.PreviewBitmap.Empty then Inc(Blanks);
      Check(not Main.Preview.AudioEngineAllocated and (Main.TimelineBox.WaveCache.DecodeCount=0),'audio during loop'); Sleep(5);
    until GetTickCount64>=Deadline;
    Check(F.CursorBeat<2,'real timer failed to loop'); Check(Blanks=0,'continuous loop blank');
    F.PlayButton.Click; F.PlayButton.Click; Check(F.IsPlaying,'resume'); F.StopButton.Click;
    Same(F.CursorBeat,0,'stop position'); Check(not F.PlaybackTimer.Enabled,'stop timer'); PreviewPixel(17,9,RGB(230,180,0),'stop first setting');
    Capture(Dialog,TPath.Combine(Dir,'point-editor-96.png'));
    Dialog.Hide; Dialog.ScaleForPPI(144); Dialog.Scaled := False; F.ScaleForPPI(144); F.LayerEditor.ScaleForPPI(144);
    Dialog.SetBounds(0,0,1380,860); Dialog.Show; WaitEditor(F); Application.ProcessMessages;
    Writeln(Format('POINT_LAYOUT_DPI form=%d frame=%d layers=%d listHeight=%d previewHeight=%d gridHeight=%d',
      [Dialog.CurrentPPI,F.CurrentPPI,F.LayerEditor.CurrentPPI,F.LayerEditor.UIControls.LayerList.ClientHeight,F.LayerEditor.UIControls.Preview.ClientHeight,F.StepGrid.ClientHeight]));
    Writeln(Format('POINT_LAYOUT_BOUNDS client=%dx%d frameHeight=%d layersHeight=%d headerHeight=%d headerVisible=%s toolbar=%d footer=%d',
      [Dialog.ClientWidth,Dialog.ClientHeight,F.ClientHeight,F.LayerEditor.ClientHeight,F.LayerEditor.UIControls.Header.Height,BoolToStr(F.LayerEditor.UIControls.Header.Visible,True),F.LayerEditor.UIControls.Toolbar.Height,F.LayerEditor.UIControls.Footer.Height]));
    Capture(Dialog,TPath.Combine(Dir,'point-editor-144-diagnostic.png'));
    Check((F.CurrentPPI=144) and (F.LayerEditor.CurrentPPI=144),'internal144 reset');
    Check(F.LayerEditor.UIControls.LayerList.ClientHeight>=144,'144 list clipped'); Check(F.LayerEditor.UIControls.Preview.ClientHeight>=96,'144 preview clipped');
    Capture(Dialog,TPath.Combine(Dir,'point-editor-144.png'));
    Before := F.ConfigJSON; F.PlayButton.Click; Dialog.Hide; Check(not F.IsPlaying and not F.PlaybackTimer.Enabled,'hide timer'); Check(F.ConfigJSON=Before,'hide changed data');
    Dialog.Show; F.SeekBeat(4); WaitEditor(F); CheckLayer(Hit,True); CheckLayer(Arm,False); Dialog.ReadPattern(P); FreeAndNil(Dialog);
    Main.Document.UpdatePattern(P); Main.LoadDocument(Text(Main.Document)); Main.TimelineBox.SelectSlot(Track,Slot); SelectTestPattern(Main,P.ID);
    Check(Main.Document.AddBeatPlacement(Track,Slot,P.ID,0,8,Error),Error); Video := TMusicStudioVideoSession.Create(Main.LibraryRoot);
    Check(Video.Render(Text(Main.Document),0.25,64,40,Pixels,Error),Error); Pixel(Pixels,17,9,230,180,0,255,'point renderer first');
    Check(Video.Render(Text(Main.Document),2.25,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'point renderer second');
    Check(Video.Render(Text(Main.Document),4.25,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,255,0,255,'arrangement must not implicitly loop');
    Main.LoadDocument(Text(Main.Document)); Main.TimelineBox.SelectSlot(Track,Slot); SelectTestPattern(Main,P.ID);
    Driver := TStepDialogDriver.Create; Driver.UsePoints := True; Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False; Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick;
    try
      Before := Text(Main.Document); Driver.Deadline := GetTickCount64+10000; Driver.Save := False; Driver.Timer.Enabled := True;
      Main.EditButton.Click; Check(Driver.Seen and Driver.Added,'point integrated modal'); Check(Text(Main.Document)=Before,'point cancel project');
      Driver.Seen := False; Driver.Added := False; Driver.Save := True; Driver.Deadline := GetTickCount64+10000; Driver.Timer.Enabled := True;
      Main.EditButton.Click; After := Text(Main.Document); Check(After<>Before,'point save'); Main.UndoEdit; Check(Text(Main.Document)=Before,'project point undo'); Main.RedoEdit; Check(Text(Main.Document)=After,'project point redo');
      Main.LoadDocument(After); Check(Text(Main.Document)=After,'project point reopen');
    finally Driver.Timer.Free; Driver.Free; end;
    TFile.WriteAllText(TPath.Combine(Dir,'point-performance-demo.json'),After,TEncoding.UTF8); TFile.WriteAllText(TPath.Combine(Dir,'library-root.txt'),Main.LibraryRoot,TEncoding.UTF8);
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'point source changed'); Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'))=MetadataHash,'point shared metadata changed');
    Writeln('POINT_NATIVE_CLICK_CURSOR_CHECK_CREATE_SQUARE_SELECT_EDIT_LOCAL_UNDO_REDO_WHEEL_PAN_96_144_OK');
    Writeln('POINT_SILENT_LOOP_WRAP_PAUSE_RESUME_STOP_HIDE_CACHED_NO_BLANK polls='+IntToStr(Polls)+' blanks='+IntToStr(Blanks));
    Writeln('POINT_PROJECT_CANCEL_SAVE_UNDO_REDO_REOPEN_RENDER_FIXED_RGBA_NO_ARRANGEMENT_LOOP_NO_AUDIO_OK');
  finally Video.Free; Dialog.Free; Main.Free; end;
end;
procedure RunCompactPointErrorChecks(const Root: string);
var Dialog: TMusicStudioPatternSettings; Host: TForm; D: TMusicStudioLayerStepData; F: TMusicStudioLayerStepFrame;
  P: TMusicStudioPattern; Dir,Source,Bad,Before: string; Deadline: UInt64; Bytes: TBytes; I: Integer; Found: Boolean;
  procedure WaitIdle;
  begin
    Deadline := GetTickCount64+10000;
    repeat F.LayerEditor.PollResults; Application.ProcessMessages;
      Check(GetTickCount64<Deadline,'compact error timeout'); Sleep(2);
    until not F.LayerEditor.IsLoading and not F.LayerEditor.IsRendering;
  end;
begin
  Dir := TPath.Combine(Root,'compact-point-errors'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source);
  Bytes := TFile.ReadAllBytes(Source); Found := False;
  for I := 0 to Length(Bytes)-8 do if (Bytes[I]=Ord('8')) and (Bytes[I+1]=Ord('B')) and (Bytes[I+2]=Ord('I')) and (Bytes[I+3]=Ord('M')) and
    (Bytes[I+4]=Ord('n')) and (Bytes[I+5]=Ord('o')) and (Bytes[I+6]=Ord('r')) and (Bytes[I+7]=Ord('m')) then begin
    Bytes[I+4] := Ord('s'); Bytes[I+5] := Ord('c'); Bytes[I+6] := Ord('r'); Bytes[I+7] := Ord('n'); Found := True; Break;
  end;
  Check(Found,'unsupported blend fixture'); Bad := TPath.Combine(Dir,'unsupported.psd'); TFile.WriteAllBytes(Bad,Bytes);
  Host := TForm.Create(nil); Host.Show; D := TMusicStudioLayerStepData.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
  try
    D.Enable('00000000-0000-0000-0000-000000000001'); D.AddSettingPoint(0,'{}'); P := Default(TMusicStudioPattern);
    P.Kind := 'performance'; P.Name := 'エラー表示の確認'; P.Color := '#80B0E0'; P.ConfigJSON := D.ConfigJSON;
    Dialog.LoadPerformanceSteps(P,D.AssetID,Source,'{}',120); Dialog.Show; F := Dialog.LayerStepFrame; WaitEditor(F); Before := F.Data.ConfigJSON;
    Check(not F.LayerEditor.UIControls.Header.Visible,'compact healthy header');
    F.LayerEditor.LoadPSD(TPath.Combine(Dir,'missing.psd'),'{}',True); WaitIdle;
    Check(F.LayerEditor.UIControls.Header.Visible and F.LayerEditor.UIControls.StateLabel.Visible,'missing error hidden');
    Check(not F.LayerEditor.CanApply,'missing marked ready');
    try F.ConfigJSON; Check(False,'missing save accepted'); except on E: EArgumentException do ; end;
    Check(F.Data.ConfigJSON=Before,'missing changed settings'); Capture(Dialog,TPath.Combine(Dir,'missing-error-96.png'));
    F.LoadPerformance(Before,D.AssetID,Source,'{}',120); WaitEditor(F); Check(not F.LayerEditor.UIControls.Header.Visible,'recovery error header retained');
    F.LayerEditor.LoadPSD(Bad,'{}',True); WaitIdle;
    Check((F.LayerEditor.Document<>nil) and not F.LayerEditor.CanApply,'unsupported render accepted');
    Check(F.LayerEditor.UIControls.Header.Visible and (Pos('合成未対応',F.LayerEditor.StateText)>0),'composition error hidden');
    Check(F.Data.ConfigJSON=Before,'unsupported changed settings'); Capture(Dialog,TPath.Combine(Dir,'composition-error-96.png'));
    F.LoadPerformance(Before,D.AssetID,Source,'{}',120); WaitEditor(F); F.LayerEditor.CancelLoad;
    Check(F.LayerEditor.UIControls.Header.Visible and not F.LayerEditor.CanApply,'cancel status hidden');
    F.LoadPerformance(Before,D.AssetID,Source,'{}',120); WaitEditor(F); Check(not F.LayerEditor.UIControls.Header.Visible,'cancel recovery');
    Writeln('POINT_COMPACT_MISSING_COMPOSITION_CANCEL_ERROR_VISIBLE_SAVE_REJECT_DATA_UNCHANGED_RECOVERY_OK');
  finally Dialog.Free; D.Free; Host.Free; end;
end;
procedure RunLayerObjectChecks(const Root: string);
var Host: TForm; Dialog: TMusicStudioPatternSettings; F: TMusicStudioLayerStepFrame; D: TMusicStudioLayerStepData;
  P: TMusicStudioPattern; Dir,Source,Before,SecondID: string; R: TRect; Key: Word; Cursor,View,PPB: Double; Handled: Boolean; Pos: TPoint;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin F.StepGrid.Perform(Msg,Buttons,LPARAM((Y shl 16) or (X and $FFFF))); end;
  procedure Drag(Index: Integer; DeltaBeats: Double; Edge: Boolean; Cancel: Integer = 0);
  var X,Y,Delta: Integer;
  begin
    R := F.StepRect(Index);
    // Tests use 96-DPI native controls for gestures; layout is captured separately at144.
    PPB := F.Zoom; if Edge then X := R.Right-2 else X := Max(F.TimelineHeaderWidth+4,(R.Left+R.Right) div 2);
    Y := (R.Top+R.Bottom) div 2; Delta := Round(DeltaBeats*PPB);
    Mouse(WM_LBUTTONDOWN,X,Y,MK_LBUTTON); Mouse(WM_MOUSEMOVE,X+Delta,Y,MK_LBUTTON);
    if Cancel=1 then begin Key := VK_ESCAPE; Dialog.OnKeyDown(Dialog,Key,[]); end
    else if Cancel=2 then F.StepGrid.Perform(WM_CANCELMODE,0,0)
    else Mouse(WM_LBUTTONUP,X+Delta,Y);
    WaitEditor(F);
  end;
begin
  Dir := TPath.Combine(Root,'layer-objects'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source);
  Host := TForm.Create(nil); Host.Show; Dialog := TMusicStudioPatternSettings.Create(nil); D := TMusicStudioLayerStepData.Create;
  try
    D.Enable('00000000-0000-0000-0000-000000000001'); D.LengthBeats := 8; D.AddSettingPoint(0,'{}'); D.AddSettingPoint(4,'{}'); SecondID := D.StepAt(1).ID;
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '区間オブジェクト'; P.Color := '#80B0E0'; P.ConfigJSON := D.ConfigJSON;
    Dialog.LoadPerformanceSteps(P,D.AssetID,Source,'{}',120); Dialog.Show; F := Dialog.LayerStepFrame; WaitEditor(F);
    Check(not F.LayerEditor.UIControls.Toolbar.Visible,'reload toolbar remains'); Before := F.Data.ConfigJSON;
    Mouse(WM_LBUTTONDOWN,10,55,MK_LBUTTON); Mouse(WM_LBUTTONUP,10,55); Check(F.Data.ConfigJSON=Before,'fixed column mutated');
    Pos := F.StepGrid.ClientToScreen(Point(10,10)); Handled := False; F.StepGrid.OnMouseWheel(F.StepGrid,[],120,Pos,Handled); Same(F.Zoom,96,'fixed column wheel zoom');
    Drag(0,-2,True); Same(F.Data.StepAt(0).LengthBeats,2,'right resize'); Check(not F.Data.StepAt(0).HoldUntilNext,'resize did not set explicit length');
    Drag(0,1,False); Same(F.Data.StepAt(0).StartBeat,1,'snapped move'); Same(F.Data.StepAt(0).LengthBeats,2,'move changed explicit length');
    Before := F.Data.ConfigJSON; Drag(0,2,False); Check(F.Data.ConfigJSON=Before,'overlap move accepted');
    Drag(0,1,False); Same(F.Data.StepAt(0).StartBeat,2,'adjacent move'); Same(F.Data.StepAt(0).StartBeat+F.Data.StepAt(0).LengthBeats,4,'adjacent edge');
    Before := F.Data.ConfigJSON; Drag(0,2,True); Check(F.Data.ConfigJSON=Before,'overlap resize accepted');
    Drag(0,-3,True); Same(F.Data.StepAt(0).LengthBeats,F.SnapStep,'reverse resize minimum'); F.UndoEdit; WaitEditor(F); Same(F.Data.StepAt(0).LengthBeats,2,'resize undo');
    F.RedoEdit; WaitEditor(F); Same(F.Data.StepAt(0).LengthBeats,F.SnapStep,'resize redo'); F.UndoEdit; WaitEditor(F);
    Before := F.Data.ConfigJSON; Drag(0,0.5,False,1); Check(F.Data.ConfigJSON=Before,'Escape committed drag'); Check(GetCapture<>F.StepGrid.Handle,'Escape capture retained');
    Drag(0,0.5,False,2); Check(F.Data.ConfigJSON=Before,'capture loss committed');
    R := F.StepRect(0); Mouse(WM_LBUTTONDOWN,R.Left+10,R.Top+10,MK_LBUTTON); Mouse(WM_MOUSEMOVE,R.Left+11,R.Top+10,MK_LBUTTON); Mouse(WM_LBUTTONUP,R.Left+11,R.Top+10);
    Check(F.Data.ConfigJSON=Before,'jitter snapped object');
    Drag(0,-1,True); Same(F.Data.StepAt(0).LengthBeats,1,'prepare zoom move'); F.Zoom := 384; Before := F.Data.ConfigJSON; Cursor := F.CursorBeat; View := F.ViewStartBeat;
    Mouse(WM_LBUTTONDOWN,F.TimelineHeaderWidth+100,10,MK_LBUTTON); Mouse(WM_MOUSEMOVE,F.TimelineHeaderWidth+600,10,MK_LBUTTON); Mouse(WM_LBUTTONUP,F.TimelineHeaderWidth+600,10);
    Check(F.ViewStartBeat<View,'empty drag pan'); Same(F.CursorBeat,Cursor,'pan cursor'); Check(F.Data.ConfigJSON=Before,'pan data');
    Drag(0,0.5,False); Same(F.Data.StepAt(0).StartBeat,2.5,'zoom pan coordinate move'); Same(F.Data.StepAt(1).StartBeat,4,'other object moved'); Check(F.Data.StepAt(1).ID=SecondID,'other ID replaced');
    Before := F.Data.ConfigJSON;
    try F.Data.AddSettingPoint(3,'{}'); Check(False,'point inside explicit accepted'); except on E: EArgumentException do ; end;
    Check(F.Data.ConfigJSON=Before,'rejected insertion mutated');
    F.Zoom := 96; F.Stop; Capture(Dialog,TPath.Combine(Dir,'object-editor-96.png'));
    Dialog.Hide; Dialog.ScaleForPPI(144); Dialog.Scaled := False; F.ScaleForPPI(144); F.LayerEditor.ScaleForPPI(144); Dialog.SetBounds(0,0,1380,860); Dialog.Show; WaitEditor(F);
    Check(F.PlayButton.BoundsRect.Bottom<=F.PlayButton.Parent.Height,'144 transport overlap'); Check(F.StepLengthEdit.BoundsRect.Bottom<=F.StepLengthEdit.Parent.Height,'144 setting row overlap');
    Check(F.LayerEditor.UIControls.Preview.ClientHeight>=96,'144 preview height'); Capture(Dialog,TPath.Combine(Dir,'object-editor-144.png'));
    F.LengthEdit.Text := '1000000'; F.Data.AddSettingPoint(999999.5,'{}'); F.Zoom := 1536; F.StepGrid.Repaint; Check(F.StepRect(2).Left<40000,'huge offscreen coordinate overflow');
    FreeAndNil(Dialog); Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.ScaleForPPI(144); Dialog.Scaled := False;
    Dialog.LoadPerformanceSteps(P,D.AssetID,Source,'{}',120); Dialog.SetBounds(0,0,1380,860); Dialog.Show; F := Dialog.LayerStepFrame; WaitEditor(F);
    Check(F.PlayButton.BoundsRect.Bottom<=F.PlayButton.Parent.Height,'initial144 transport overlap');
    Check(F.StepLengthEdit.BoundsRect.Bottom<=F.StepLengthEdit.Parent.Height,'initial144 setting overlap');
    Capture(Dialog,TPath.Combine(Dir,'object-editor-initial144.png'));
    Writeln('OBJECT_FIXED_COLUMN_SELECT_MOVE_RIGHT_RESIZE_SNAP_ADJACENT_OVERLAP_REJECT_MIN_ESC_CAPTURE_UNDO_ZOOM_PAN_DPI_HUGE_COORD_OK');
  finally D.Free; Dialog.Free; Host.Free; end;
end;
procedure RunObjectReviewChecks(const Root: string; MinimumDPI: Boolean);
var Host: TForm; Dialog: TMusicStudioPatternSettings; F: TMusicStudioLayerStepFrame; D: TMusicStudioLayerStepData;
  P: TMusicStudioPattern; Dir,Source: string; R: TRect; X,Y,I: Integer;
begin
  Dir := TPath.Combine(Root,'object-review'); ForceDirectories(Dir); Source := TPath.Combine(Dir,'character.psd'); Fixture(Source);
  Host := TForm.Create(nil); Host.Show; Dialog := TMusicStudioPatternSettings.Create(nil); D := TMusicStudioLayerStepData.Create;
  try
    D.Enable('00000000-0000-0000-0000-000000000001'); D.LengthBeats := 8; D.AddStep(0,1/1024,'{}');
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '最小区間・最小画面'; P.Color := '#80B0E0'; P.ConfigJSON := D.ConfigJSON;
    if MinimumDPI then begin Dialog.ScaleForPPI(144); Dialog.Scaled := False; end;
    Dialog.LoadPerformanceSteps(P,D.AssetID,Source,'{}',120); Dialog.Show; F := Dialog.LayerStepFrame; WaitEditor(F);
    if MinimumDPI then begin
      Dialog.SetBounds(0,0,Dialog.Constraints.MinWidth,Dialog.Constraints.MinHeight); Application.ProcessMessages; WaitEditor(F);
      Writeln(Format('MINIMUM_DPI144 outer=%dx%d min=%dx%d preview=%dx%d',[Dialog.Width,Dialog.Height,Dialog.Constraints.MinWidth,Dialog.Constraints.MinHeight,F.LayerEditor.UIControls.Preview.Width,F.LayerEditor.UIControls.Preview.Height]));
      Check(F.LayerEditor.UIControls.Preview.Height>=96,'minimum144 preview disappeared');
      Check((Dialog.Constraints.MinWidth>=1290) and (Dialog.Constraints.MinHeight>=840),'minimum dimensions not DPI scaled');
      Check(F.PlayButton.BoundsRect.Bottom<=F.PlayButton.Parent.Height,'minimum144 play clipped');
      Capture(Dialog,TPath.Combine(Dir,'minimum-144.png'));
      Dialog.Hide; Dialog.Scaled := True; Dialog.ScaleForPPI(96); Dialog.Scaled := False; F.ScaleForPPI(96); F.LayerEditor.ScaleForPPI(96);
      Dialog.SetBounds(0,0,Dialog.Constraints.MinWidth,Dialog.Constraints.MinHeight); Dialog.Show; WaitEditor(F);
      Check((Dialog.CurrentPPI=96) and (F.CurrentPPI=96),'minimum96 DPI not changed');
      Check(F.LayerEditor.UIControls.Preview.Height>=64,'minimum96 preview disappeared'); Capture(Dialog,TPath.Combine(Dir,'minimum-96.png'));
      Dialog.Hide; Dialog.Scaled := True; Dialog.ScaleForPPI(144); Dialog.Scaled := False; F.ScaleForPPI(144); F.LayerEditor.ScaleForPPI(144);
      Dialog.SetBounds(0,0,Dialog.Constraints.MinWidth,Dialog.Constraints.MinHeight); Dialog.Show; WaitEditor(F);
      Check(F.LayerEditor.UIControls.Preview.Height>=96,'DPI transition minimum preview'); Capture(Dialog,TPath.Combine(Dir,'minimum-transition144.png'));
      Check((Dialog.CurrentPPI=144) and (F.CurrentPPI=144),'transition144 DPI not changed');
      Writeln('OBJECT_REVIEW_DPI_MINIMUM_96_INITIAL144_TRANSITION144_REQUIRED_CONTROLS_PREVIEW_OK');
    end else begin
      for I := 0 to 1 do begin
      F.LoadPerformance(P.ConfigJSON,D.AssetID,Source,'{}',120); if I=0 then F.Zoom := 24 else F.Zoom := 1536;
      F.Stop; F.SelectStep(0); WaitEditor(F); R := F.StepRect(0); X := R.Left+1; Y := (R.Top+R.Bottom) div 2;
      F.StepGrid.Perform(WM_LBUTTONDOWN,MK_LBUTTON,LPARAM((Y shl 16) or X));
      F.StepGrid.Perform(WM_MOUSEMOVE,MK_LBUTTON,LPARAM((Y shl 16) or (X+Round(F.Zoom))));
      F.StepGrid.Perform(WM_LBUTTONUP,0,LPARAM((Y shl 16) or (X+Round(F.Zoom)))); WaitEditor(F);
      Same(F.Data.StepAt(0).LengthBeats,1/1024,'tiny central move resized'); Same(F.Data.StepAt(0).StartBeat,1,'tiny central move');
      F.UndoEdit; WaitEditor(F); F.SelectStep(0); R := F.ResizeHandleRect(0); X := Max(F.TimelineHeaderWidth+1,(R.Left+R.Right) div 2); Y := (R.Top+R.Bottom) div 2;
      F.StepGrid.Perform(WM_LBUTTONDOWN,MK_LBUTTON,LPARAM((Y shl 16) or X));
      F.StepGrid.Perform(WM_MOUSEMOVE,MK_LBUTTON,LPARAM((Y shl 16) or (X+Round(F.Zoom))));
      F.StepGrid.Perform(WM_LBUTTONUP,0,LPARAM((Y shl 16) or (X+Round(F.Zoom)))); WaitEditor(F);
      Check(F.Data.StepAt(0).LengthBeats>1/1024,'tiny object cannot resize');
      Same(F.Data.StepAt(0).StartBeat,0,'tiny handle moved object');
      end;
      Writeln('OBJECT_REVIEW_MIN_1_OVER1024_LOW24_MAX1536_SELECTED_HANDLE_RESIZE_CENTRAL_MOVE_UNDO_OK');
    end;
  finally D.Free; Dialog.Free; Host.Free; end;
end;
procedure RunLayerStepRealPointDemo(const Root,Source,SeedJSON: string);
var Main: TFormMusicStudioSettings; Dialog: TMusicStudioPatternSettings; D: TMusicStudioLayerStepData;
  F: TMusicStudioLayerStepFrame; Asset: TMusicStudioPsdAsset; P: TMusicStudioPattern;
  Seed: TJSONValue; Dir,BeforeHash,AfterHash,Error,Before,Key: string;
  Track,Slot,Index,I,RenderBefore: Integer; Dup: Boolean;
begin
  Dir := TPath.Combine(Root,'real-point-editor'); ForceDirectories(Dir); BeforeHash := THashSHA2.GetHashStringFromFile(Source);
  Main := TFormMusicStudioSettings.Create(nil); Dialog := nil; D := TMusicStudioLayerStepData.Create;
  try
    Main.SilentVisualMode := True; Main.LibraryRoot := TPath.Combine(Dir,'library'); Main.LoadDocument('');
    Check(Main.SharedLibrary.TryImport(Source,'演奏設定の試行用コピー','#80B0E0',Asset,Dup,Error),Error);
    if SeedJSON<>'' then begin Seed := TJSONObject.ParseJSONValue(TFile.ReadAllText(SeedJSON,TEncoding.UTF8));
      try if (Seed is TJSONObject) and (TJSONObject(Seed).GetValue('config') is TJSONObject) then begin
        Asset.ConfigJSON := TJSONObject(Seed).GetValue('config').ToJSON; Check(Main.SharedLibrary.TrySave(Asset,Error),Error);
      end; finally Seed.Free; end;
    end;
    Track := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Track,Asset.ID); Slot := Main.Document.AddSlot(Track,'performance');
    Index := Main.Document.AddPerformance; P := Main.Document.PatternAt(Index); D.LoadJSON(P.ConfigJSON); D.Enable(Asset.ID); D.LengthBeats := 16;
    D.AddSettingPoint(0,Asset.ConfigJSON); P.ConfigJSON := D.ConfigJSON; P.Name := '演奏設定点の無音試行'; Main.Document.UpdatePattern(P);
    Main.LoadDocument(Text(Main.Document)); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
    Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True;
    Dialog.LoadPerformanceSteps(P,Asset.ID,Asset.FilePath,Asset.ConfigJSON,120); Dialog.Show; F := Dialog.LayerStepFrame; WaitEditor(F);
    F.SeekBeat(4); WaitEditor(F); I := High(F.LayerEditor.Document.Layers); Key := F.LayerEditor.Document.Layers[I].Key;
    Check(F.LayerEditor.SetLayerVisibility(Key,not F.LayerEditor.UIControls.LayerList.Checked[I]),'real point toggle'); WaitEditor(F); F.Stop; WaitEditor(F);
    Before := F.ConfigJSON; F.PlayPause; F.PlaybackTimer.Enabled := False; F.AdvancePlayback(2.25); WaitEditor(F); F.AdvancePlayback(6); WaitEditor(F);
    RenderBefore := F.LayerEditor.PreviewRenderCount;
    for I := 0 to 5 do begin F.AdvancePlayback(2); WaitEditor(F); Check(F.LayerEditor.PreviewBitmap<>nil,'real loop blank'); end;
    Check(F.LayerEditor.PreviewRenderCount=RenderBefore,'real cached loop recomposed'); F.Stop; WaitEditor(F); Check(F.ConfigJSON=Before,'real loop mutated JSON');
    Capture(Dialog,TPath.Combine(Dir,'real-point-editor-96.png'));
    Dialog.Hide; Dialog.ScaleForPPI(144); Dialog.Scaled := False; F.ScaleForPPI(144); F.LayerEditor.ScaleForPPI(144);
    Dialog.SetBounds(0,0,1380,860); Dialog.Show; WaitEditor(F); Check(F.LayerEditor.UIControls.Preview.ClientHeight>=96,'real144 preview clipped');
    Capture(Dialog,TPath.Combine(Dir,'real-point-editor-144.png')); Dialog.ReadPattern(P); FreeAndNil(Dialog);
    Main.Document.UpdatePattern(P); Check(Main.Document.AddBeatPlacement(Track,Slot,P.ID,0,16,Error),Error);
    Main.LoadDocument(Text(Main.Document)); Main.TimelineBox.SelectSlot(Track,Slot); SelectTestPattern(Main,P.ID);
    TFile.WriteAllText(TPath.Combine(Dir,'real-point-performance-demo.json'),Text(Main.Document),TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir,'library-root.txt'),Main.LibraryRoot,TEncoding.UTF8);
    AfterHash := THashSHA2.GetHashStringFromFile(Source); Check(BeforeHash=AfterHash,'real original changed');
    Writeln('POINT_REAL_PSD_COPY_96_144_CACHED_SILENT_LOOP_ORIGINAL_SHA256_UNCHANGED_OK '+BeforeHash);
  finally D.Free; Dialog.Free; Main.Free; end;
end;
procedure RunLayerStepChecks(const Root: string);
var Main: TFormMusicStudioSettings; Dialog: TMusicStudioPatternSettings; Layers: TMusicStudioLayerDocument;
  Asset,Other: TMusicStudioPsdAsset; Dup: Boolean; P,Emotion: TMusicStudioPattern;
  Steps: TMusicStudioLayerStepData; Config: TJSONObject; Timing: TMusicStudioTempoMap;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Clip: TMusicStudioPlacement;
  Dir,Source,OtherSource,MidiPath,Error,Before,After,KeyHit,KeyIdle,KeyExpr,KeyArm,KeyLeg,KeyA,KeyNormal,MetaHash,SourceHash,JSON: string;
  Track,Second,Slot,Index,I,Audio,AudioTrack,Song: Integer; Rect: TRect; GUID: TGUID;
  Driver: TStepDialogDriver; MidiBefore,MidiAfter: TMusicStudioSingingSource; Step: TMusicStudioLayerStep;
  Transform: TMusicStudioPsdTransform; DemoJSON: string;
begin
  RunLayerStepPointChecks(Root); RunLayerObjectChecks(Root); RunObjectReviewChecks(Root,False); RunObjectReviewChecks(Root,True); Model;
  Dir := TPath.Combine(Root,'layer-steps'); ForceDirectories(Dir); Source := TPath.combine(Dir,'character.psd'); Fixture(Source);
  OtherSource := TPath.Combine(Dir,'other.psd'); WriteLayeredTestPSD(OtherSource,10,20,30); SourceHash := THashSHA2.GetHashStringFromFile(Source);
  Main := TFormMusicStudioSettings.Create(nil); Layers := TMusicStudioLayerDocument.Create;
  Steps := TMusicStudioLayerStepData.Create; Timing := TMusicStudioTempoMap.Create; Dialog := nil; Video := nil;
  try
    Main.SilentVisualMode := True; Main.LibraryRoot := TPath.Combine(Dir,'library'); Main.LoadDocument('');
    Check(Main.SharedLibrary.TryImport(Source,'リズムPSD','#80B0E0',Asset,Dup,Error),Error);
    Check(Main.SharedLibrary.TryImport(OtherSource,'別PSD','#90C4E0',Other,Dup,Error),Error);
    Check(Layers.LoadFile(Asset.FilePath),Layers.LastError);
    KeyHit := LayerKey(Layers,'*hit'); KeyIdle := LayerKey(Layers,'*idle'); KeyExpr := LayerKey(Layers,'*expression');
    KeyArm := LayerKey(Layers,'arm'); KeyLeg := LayerKey(Layers,'leg'); KeyA := LayerKey(Layers,'*a'); KeyNormal := LayerKey(Layers,'*normal');
    Config := ParseMusicStudioPsdConfig('');
    try MusicStudioAssignMouth(Config,0,KeyNormal); MusicStudioAssignMouth(Config,1,KeyA); Asset.ConfigJSON := Config.ToJSON; finally Config.Free; end;
    SetLength(Asset.Patterns,1); Asset.Patterns[0].Kind := 'emotion'; CreateGUID(GUID);
    Asset.Patterns[0].ID := LowerCase(Copy(GUIDToString(GUID),2,36)); Asset.Patterns[0].Name := '表情'; Asset.Patterns[0].Color := '#B090E0';
    Config := ParseMusicStudioPsdConfig('');
    try MusicStudioSetJsonBoolean(MusicStudioPsdConfigObject(Config,'visibility'),KeyExpr,True); Asset.Patterns[0].ConfigJSON := Config.ToJSON; finally Config.Free; end;
    Check(Main.SharedLibrary.TrySave(Asset,Error),Error); MetaHash := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'));
    Track := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Track,Asset.ID); Slot := Main.Document.AddSlot(Track,'performance');
    Second := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Second,Other.ID); Main.Document.AddSlot(Second,'performance');
    Index := Main.Document.AddPerformance; P := Main.Document.PatternAt(Index); Steps.LoadJSON(P.ConfigJSON); Steps.Enable(Asset.ID); Steps.LengthBeats := 8; P.ConfigJSON := Steps.ConfigJSON;
    Main.Document.UpdatePattern(P); Before := Text(Main.Document); Main.LoadDocument(Before); Main.TimelineBox.SelectSlot(Track,Slot);
    SelectTestPattern(Main,P.ID); Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
    Dialog := TMusicStudioPatternSettings.Create(nil); Dialog.SilentVisualMode := True;
    Dialog.LoadPerformanceSteps(P,Asset.ID,Asset.FilePath,Asset.ConfigJSON,120); Dialog.Show; ShowWindow(Dialog.Handle,SW_SHOWNOACTIVATE);
    Check((Dialog.LayerStepFrame<>nil) and (Dialog.PerformanceFrame=nil) and (Dialog.AudioFrame=nil),'common+specialized UI'); WaitEditor(Dialog.LayerStepFrame);
    Dialog.LayerStepFrame.AddStep(1); WaitEditor(Dialog.LayerStepFrame);
    Check(Dialog.LayerStepFrame.LayerEditor.SetLayerVisibility(KeyHit,True),'assign hit'); WaitEditor(Dialog.LayerStepFrame);
    Check(Dialog.LayerStepFrame.LayerEditor.SetLayerVisibility(KeyArm,True),'simultaneous arm');
    Check(Dialog.LayerStepFrame.LayerEditor.SetLayerVisibility(KeyLeg,True),'simultaneous leg'); WaitEditor(Dialog.LayerStepFrame);
    Dialog.LayerStepFrame.StepLengthEdit.Text := '0.5'; Dialog.LayerStepFrame.LengthEdit.Text := '8';
    Step := Dialog.LayerStepFrame.Data.StepAt(0); Step.StartBeat := 1.123; Dialog.LayerStepFrame.Data.SetStep(0,Step);
    Before := Dialog.LayerStepFrame.ConfigJSON;
    for I := 0 to 20 do Dialog.LayerStepFrame.Zoom := 24*Power(2,I mod 7);
    Check(Dialog.LayerStepFrame.ConfigJSON=Before,'zoom mutated JSON'); Dialog.LayerStepFrame.Zoom := 192;
    Rect := Dialog.LayerStepFrame.StepRect(0); Check(Rect.Width=96,'zoom changes displayed duration');
    Capture(Dialog,TPath.Combine(Dir,'step-editor-96.png'));
    Dialog.Hide; Dialog.ScaleForPPI(144); Dialog.Scaled := False;
    Dialog.LayerStepFrame.ScaleForPPI(144); Dialog.LayerStepFrame.LayerEditor.ScaleForPPI(144);
    Dialog.SetBounds(0,0,1380,860); Dialog.Show; WaitEditor(Dialog.LayerStepFrame); Capture(Dialog,TPath.Combine(Dir,'step-editor-144.png'));
    Step.StartBeat := 1; Dialog.LayerStepFrame.Data.SetStep(0,Step);
    Dialog.ReadPattern(P); Check(P.Name=Main.Document.PatternAt(Index).Name,'common name'); FreeAndNil(Dialog);
    Main.Document.UpdatePattern(P); JSON := Text(Main.Document); Main.LoadDocument(JSON); Main.TimelineBox.SelectSlot(Track,Slot); SelectTestPattern(Main,P.ID);
    Check(Main.DropSelectedLibraryAt(Track,Slot,2,Error),Error); Clip := Main.Document.TrackAt(Track).Slots[Slot].Clips[0];
    Check(Clip.TimeBase='beats','performance beat basis'); Same(Clip.StartBeat,4,'placement beat'); Same(Clip.LengthBeats,8,'pattern-derived initial clip length');
    Check(not Main.DropPatternAt(Index,Second,TestSlotIndex(Main.Document,Second,'performance'),0,Error),'foreign PSD drop accepted');
    Driver := TStepDialogDriver.Create; Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False;
    Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick;
    try
      Before := Text(Main.Document); Driver.Deadline := GetTickCount64+10000; Driver.Save := False; Driver.Timer.Enabled := True;
      Main.EditButton.Click; Check(Driver.Seen and Driver.Added,'integrated step modal not opened'); Check(Text(Main.Document)=Before,'cancel changed project');
      Driver.Seen := False; Driver.Added := False; Driver.Save := True; Driver.Deadline := GetTickCount64+10000; Driver.Timer.Enabled := True;
      Main.EditButton.Click; After := Text(Main.Document); Check(After<>Before,'modal save not applied');
      Main.UndoEdit; Check(Text(Main.Document)=Before,'step edit undo'); Main.RedoEdit; Check(Text(Main.Document)=After,'step edit redo');
      Main.LoadDocument(After); Check(Text(Main.Document)=After,'save/reopen steps');
      P := Main.Document.PatternAt(Index);
    finally Driver.Timer.Free; Driver.Free; end;
    Main.TimelineBox.Repaint; Capture(Main,TPath.Combine(Dir,'performance-slot-96.png'));
    // Expressions apply first; active performance steps take precedence, and rests restore expression.
    Emotion := Default(TMusicStudioPattern); Emotion.Kind := 'emotion'; Emotion.Name := '表情'; Emotion.Color := '#B090E0'; Emotion.AssetID := Asset.ID; Emotion.SharedPatternID := Asset.Patterns[0].ID;
    I := Main.Document.AddReference(Emotion); Check(Main.Document.AddPlacement(Track,TestSlotIndex(Main.Document,Track,'emotion'),Main.Document.PatternAt(I).ID,0,12,Error),Error);
    Video := TMusicStudioVideoSession.Create(Main.LibraryRoot); Main.Document.RemoveTrack(Second); JSON := Text(Main.Document);
    Check(Video.Render(JSON,2.4,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'rest restores expression');
    Check(Video.Render(JSON,2.6,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'performance overrides expression/star exclusion');
    Pixel(Pixels,17,9,230,180,0,255,'arm simultaneous hit'); Pixel(Pixels,21,9,230,0,200,255,'leg simultaneous hit');
    Check(Main.Document.AddBeatPlacement(Track,Slot,P.ID,5.1,0.2,Error),Error); JSON := Text(Main.Document);
    Check(Video.Render(JSON,2.6,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'newer performance rest revived older step');
    Check(Video.Render(JSON,2.7,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'underlying step did not resume after newer clip end');
    Main.Document.RemovePlacement(Track,Slot,1); JSON := Text(Main.Document);
    Writeln('PASS review P2 newer overlapping performance clip rest masks old active step, then underlying clip resumes');
    Check(Video.Render(JSON,2.75,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'exclusive step end');
    Check(Main.Document.MoveBeatPlacement(Track,Slot,0,4,16,Error),Error); JSON := Text(Main.Document);
    Check(Video.Render(JSON,6.6,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'long clip implicitly looped pattern');
    Steps.LoadJSON(P.ConfigJSON); Steps.LengthBeats := 12; P.ConfigJSON := Steps.ConfigJSON; Main.Document.UpdatePattern(P);
    Same(Main.Document.TrackAt(Track).Slots[Slot].Clips[0].LengthBeats,16,'pattern edit stretched placed clip');
    Steps.LengthBeats := 8; P.ConfigJSON := Steps.ConfigJSON; Main.Document.UpdatePattern(P);
    Steps.AddStep(3.75,1,Steps.StepAt(0).ConfigJSON); P.ConfigJSON := Steps.ConfigJSON; Main.Document.UpdatePattern(P);
    // Tempo map keeps later points. Audio and MIDI placements remain seconds, performance clips are beats.
    Audio := Main.Document.AddAudio; AudioTrack := Main.Document.AddTrack('audio');
    Check(Main.Document.AddPlacement(AudioTrack,0,Main.Document.PatternAt(Audio).ID,3.75,1.25,Error),Error);
    Song := Main.Document.AddSinging;
    MidiPath := TPath.Combine(Dir,'lyrics.mid'); MidiFixture(MidiPath); MidiBefore := LoadMusicStudioSinging(MidiPath);
    Check(MidiBefore.Status=ssReady,'MIDI fixture'); Emotion := Main.Document.PatternAt(Song); Emotion.FilePath := MidiPath; Emotion.SourceTrack := 0;
    Main.Document.UpdatePattern(Emotion);
    Check(Main.Document.AddPlacement(Track,TestSlotIndex(Main.Document,Track,'singing'),Main.Document.PatternAt(Song).ID,5.2,1.7,Error),Error);
    Timing.LoadJSON('{"version":1,"tempoPoints":[{"beat":0,"bpm":120,"tag":"zero"},{"beat":8,"bpm":90,"tag":"later"}],"timeSignature":{"numerator":4,"denominator":4},"extra":"keep"}');
    Timing.SetTempoPoint(0,0,60); Check(Timing.PointCount=2,'constant UI removed tempo points'); Check(Main.Document.SetTiming(Timing.TimingJSON,Error),Error);
    Clip := Main.Document.TrackAt(Track).Slots[Slot].Clips[0]; Same(Clip.StartBeat,4,'tempo moved beat');
    Same(Clip.StartSeconds,4,'tempo derived seconds'); Same(Clip.LengthSeconds,Main.Document.BeatToSeconds(20)-4,'tempo boundary interval');
    Same(Main.Document.TrackAt(AudioTrack).Slots[0].Clips[0].StartSeconds,3.75,'audio start changed'); Same(Main.Document.TrackAt(AudioTrack).Slots[0].Clips[0].LengthSeconds,1.25,'audio length changed');
    Same(Main.Document.TrackAt(Track).Slots[TestSlotIndex(Main.Document,Track,'singing')].Clips[0].StartSeconds,5.2,'MIDI placement changed');
    JSON := Text(Main.Document); Check(Video.Render(JSON,5.1,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'step follows project beat');
    Check(Video.Render(JSON,5.3,64,40,Pixels,Error),Error); Pixel(Pixels,25,9,255,0,0,255,'singing mouth applies after performance');
    MidiAfter := LoadMusicStudioSinging(MidiPath); Same(MidiAfter.Duration,MidiBefore.Duration,'project BPM reinterpreted MIDI tempo');
    Same(MidiAfter.Notes[0].EndSeconds,MidiBefore.Notes[0].EndSeconds,'MIDI note seconds changed');
    Check(Video.Render(JSON,5.5,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'tempo rest');
    Check(Video.Render(JSON,7.8,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'step before tempo boundary');
    Check(Video.Render(JSON,8.25,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,255,0,0,255,'step after tempo boundary');
    Check(Video.Render(JSON,8.5,64,40,Pixels,Error),Error); Pixel(Pixels,5,9,0,0,255,255,'step end derived through tempo boundary');
    Transform := Default(TMusicStudioPsdTransform); Transform.HasBounds := True; Transform.X := -0.2; Transform.Y := 0.1;
    Transform.Width := 0.75; Transform.Height := 0.75; Transform.FlipX := True; Main.Document.UpdatePsdTransform(Track,Transform);
    DemoJSON := Text(Main.Document); Main.LoadDocument(DemoJSON); Check(Main.Document.TrackAt(Track).PsdTransform.FlipX,'transform lost across step reopen');
    Same(Main.Document.TrackAt(Track).PsdTransform.X,-0.2,'outside placement lost');
    TFile.WriteAllText(TPath.Combine(Dir,'step-performance-demo.json'),DemoJSON,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir,'library-root.txt'),Main.LibraryRoot,TEncoding.UTF8);
    // Tiny high-BPM beat clips remain valid, without relaxing audio/singing minimum seconds.
    Main.Document.RemovePlacement(Track,Slot,0); Steps.LoadJSON(P.ConfigJSON); while Steps.StepCount>0 do Steps.DeleteStep(0);
    Steps.LengthBeats := 1/64; P.ConfigJSON := Steps.ConfigJSON; Main.Document.UpdatePattern(P);
    Timing.SetTempoPoint(0,0,999.99); Check(Main.Document.SetTiming(Timing.TimingJSON,Error),Error);
    Check(Main.Document.AddPlacement(Track,Slot,P.ID,0,1,Error),Error); Clip := Main.Document.TrackAt(Track).Slots[Slot].Clips[0];
    Check((Clip.LengthSeconds>0) and (Clip.LengthSeconds<0.001),'999.99BPM 1/64 beat'); Check(Main.Document.TrySave(JSON,Error),Error);
    Check(not Main.Document.AddPlacement(AudioTrack,0,Main.Document.PatternAt(Audio).ID,0,0.0005,Error),'audio minimum weakened');
    Check(THashSHA2.GetHashStringFromFile(Source)=SourceHash,'original PSD changed');
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(Asset.FilePath),'asset.json'))=MetaHash,'shared settings changed');
    Check(not Main.Preview.AudioEngineAllocated and (Main.TimelineBox.WaveCache.DecodeCount=0),'audio invoked');
    Writeln('PASS step grid/shared expression UI/zoom JSON invariant/96+144DPI/song track slot/drop/foreign reject');
    Writeln('PASS performance+expression priority/star exclusion/simultaneous layers/rest/tempo boundary/seconds invariant/high BPM tiny clip');
  finally Video.Free; Dialog.Free; Timing.Free; Steps.Free; Layers.Free; Main.Free; end;
end;
end.
