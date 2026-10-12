unit SYNC_MusicStudio_PsdMouthChecks;
// Real modal controls and shared-library persistence, with PSD-only isolated fixtures.
interface
procedure RunPsdMouthChecks(const Root: string; const ActualPSD: string = ''; const SeedAssetJSON: string = '');
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.JSON, System.Types, System.Math,
  System.UITypes, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_PsdLayerConfig, SYNC_MusicStudio_PsdLayersFrame,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_SharedLibraryEditor,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_TestHelpers;
type
  TMouthDriver = class
    Timer, PopupTimer: TTimer;
    Keys: array[0..11] of string;
    OldKey, BranchKey, Dir, Failure: string;
    Index, Step: Integer;
    Reopen, CancelAfter, CheckParts: Boolean;
    IntegratedPPI: Integer;
    ScaledOnce, ViewChecksDone: Boolean;
    PopupFrame: TMusicStudioPsdLayersFrame;
    PopupPick: Integer;
    PopupSeen: Boolean;
    PopupKey: string;
    Deadline: UInt64;
    procedure Tick(Sender: TObject);
    procedure AppException(Sender: TObject; E: Exception);
    procedure PopupTick(Sender: TObject);
    procedure ChooseMouth(F: TMusicStudioPsdLayersFrame; Mouth,Route: Integer; CancelPopup: Boolean = False);
    procedure CheckSelectionView(D: TMusicStudioPatternSettings; F: TMusicStudioPsdLayersFrame);
  end;
procedure Check(B: Boolean; const M: string);
begin if not B then raise Exception.Create('PSD mouth: '+M); end;
function FindName(D: TMusicStudioLayerDocument; const Name: string; const Branch: string = ''): string;
var L: TMusicStudioLayerInfo;
begin
  Result := ''; for L in D.Layers do if (L.Name=Name) and ((Branch='') or (Pos(Branch,L.Path)>0)) then Exit(L.Key);
  raise Exception.Create('PSD mouth layer not found: '+Name);
end;
procedure WriteNestedPSD(const Path: string);
var D: TArtDocument; Face,Mouth,Branch,L,Other: TArtLayer; I,J: Integer;
  procedure Image(Parent: TArtLayer; const Name: string; X: Integer; Visible: Boolean; R,G,B: Byte);
  begin
    L := D.AddLayer(alkImage,Name,TArtBounds.Create(X,0,X+1,2),Parent); L.Visible := Visible;
    L.Pixels := TBytes.Create(R,G,B,255,R,G,B,255);
  end;
begin
  D := TArtDocument.Create;
  try
    D.Width := 4; D.Height := 2; Face := D.AddLayer(alkGroup,'face',TArtBounds.Create(0,0,0,0)); Face.BlendKey := 'norm';
    Image(Face,'body_'+StringOfChar('長',80),1,True,30,90,180); Image(Face,'hair',2,True,200,60,100);
    Mouth := D.AddLayer(alkGroup,'mouth',TArtBounds.Create(0,0,0,0),Face); Mouth.BlendKey := 'norm';
    Image(Mouth,'*ordinary',0,True,0,255,0); Image(Mouth,'decoration',3,True,180,100,50);
    Branch := D.AddLayer(alkGroup,'*phonemes',TArtBounds.Create(0,0,0,0),Mouth); Branch.BlendKey := 'norm'; Branch.Visible := False;
    for I := 0 to 5 do begin J := I*30; Image(Branch,'*shape'+IntToStr(I),0,I=0,Byte(40+J),Byte(100+J),Byte(200-J)); end;
    Other := D.AddLayer(alkGroup,'other',TArtBounds.Create(0,0,0,0)); Other.BlendKey := 'norm'; Other.Visible := False;
    Image(Other,'*shape0',0,True,1,2,3);
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
procedure SaveClient(D: TForm; const Path: string);
var B: TBitmap; P: TPngImage; DC: HDC;
begin
  D.Update; B := TBitmap.Create; P := TPngImage.Create;
  try
    B.SetSize(D.ClientWidth,D.ClientHeight); DC := GetDC(D.Handle);
    try Check(BitBlt(B.Canvas.Handle,0,0,B.Width,B.Height,DC,0,0,SRCCOPY),'modal capture');
    finally ReleaseDC(D.Handle,DC); end;
    P.Assign(B); P.SaveToFile(Path);
  finally P.Free; B.Free; end;
end;
function SamePixels(A,B: TBitmap): Boolean;
var Y: Integer;
begin
  Result := (A.Width=B.Width) and (A.Height=B.Height);
  if Result then for Y := 0 to A.Height-1 do
    if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
end;
procedure CheckPartsPixels(B: TBitmap);
var Y: Integer;
begin
  Check((B.Width=4) and (B.Height=2),'body/hair/decoration fixture dimensions');
  for Y := 0 to 1 do begin
    Check(PCardinal(NativeUInt(B.ScanLine[Y])+4)^=$FF1E5AB4,'non-star body pixel changed');
    Check(PCardinal(NativeUInt(B.ScanLine[Y])+8)^=$FFC83C64,'non-star hair pixel changed');
    Check(PCardinal(NativeUInt(B.ScanLine[Y])+12)^=$FFB46432,'non-star decoration pixel changed');
  end;
end;
procedure TMouthDriver.AppException(Sender: TObject; E: Exception);
begin Failure := E.Message; end;
procedure TMouthDriver.CheckSelectionView(D: TMusicStudioPatternSettings; F: TMusicStudioPsdLayersFrame);
var Before: string; Config,Overrides: TJSONObject; B,Old,NameBefore,NameAfter,LabelsBefore,LabelsAfter: TBitmap;
    I,Row,Column,Count,Width: Integer; P: TPoint; Anchor,AfterAnchor,Pan: TPointF; Zoom: Double; R: TRect; DC: HDC;
  procedure Await;
  var Limit: UInt64;
  begin
    Limit := GetTickCount64+10000;
    repeat
      F.PollResults; Application.ProcessMessages;
      if not F.IsRendering and not F.IsLoading then begin Check(F.CanApply,F.StateText); Exit; end;
      Sleep(2);
    until GetTickCount64>Limit;
    Check(False,'selection composition timeout');
  end;
  procedure Wheel(Delta: SmallInt);
  begin
    P := F.UIControls.Preview.ClientToScreen(Point(2,2));
    F.UIControls.Preview.Perform(WM_MOUSEWHEEL,NativeUInt(Word(Delta)) shl 16,MakeLParam(P.X,P.Y));
  end;
  procedure CheckView;
  begin
    Check(SameValue(F.ViewZoom,Zoom,0.00001) and (Abs(F.ViewPan.X-Pan.X)<0.001) and
      (Abs(F.ViewPan.Y-Pan.Y)<0.001),'selection/assignment reset zoom or pan');
  end;
  procedure CaptureRow(Name,Labels: TBitmap);
  begin
    F.UIControls.LayerList.ItemIndex := Row; F.UIControls.LayerList.TopIndex := Row; F.UIControls.LayerList.SetFocus;
    F.UIControls.LayerList.Repaint; R := F.UIControls.LayerList.ItemRect(Row);
    Column := MulDiv(36,Abs(F.UIControls.LayerList.Font.Height),13);
    Width := F.UIControls.LayerList.ClientWidth-Column-2; Check(Width>15,'name column missing at narrow DPI');
    Name.PixelFormat := pf32bit; Name.SetSize(Width,R.Height);
    Labels.PixelFormat := pf32bit; Labels.SetSize(Column-4,R.Height);
    DC := GetDC(F.UIControls.LayerList.Handle);
    try
      Check(BitBlt(Name.Canvas.Handle,0,0,Width,R.Height,DC,Column+1,R.Top,SRCCOPY),'name row capture');
      Check(BitBlt(Labels.Canvas.Handle,0,0,Labels.Width,R.Height,DC,2,R.Top,SRCCOPY),'vowel row capture');
    finally ReleaseDC(F.UIControls.LayerList.Handle,DC); end;
  end;
begin
  Timer.Enabled := False; Before := F.ConfigJSON; Config := ParseMusicStudioPsdConfig(Before);
  B := TBitmap.Create; Old := TBitmap.Create; NameBefore := TBitmap.Create; NameAfter := TBitmap.Create;
  LabelsBefore := TBitmap.Create; LabelsAfter := TBitmap.Create;
  try
    Check(not F.UIControls.LayerList.CheckMode,'song list still uses visibility checks');
    Check(F.UIControls.Preview.DoubleBuffered,'preview buffering disabled');
    Check(F.UIControls.Preview.ClientHeight>=MulDiv(120,Abs(F.Font.Height),13),'PSD preview too short at minimum window size');
    F.FitPreview; Count := F.PreviewRenderCount; Old.Assign(F.PreviewBitmap);
    Anchor := F.PreviewToImage(PointF(2,2)); Wheel(120); AfterAnchor := F.PreviewToImage(PointF(2,2));
    Check((F.ViewZoom>1) and (Abs(Anchor.X-AfterAnchor.X)<0.02) and
      (Abs(Anchor.Y-AfterAnchor.Y)<0.02),'native wheel did not anchor zoom to cursor');
    Anchor := PointF(F.PreviewBitmap.Width*0.37,F.PreviewBitmap.Height*0.61);
    AfterAnchor := F.PreviewToImage(F.ImageToPreview(Anchor));
    Check((Abs(Anchor.X-AfterAnchor.X)<0.02) and (Abs(Anchor.Y-AfterAnchor.Y)<0.02),'view coordinate round trip');
    F.UIControls.Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(2,2));
    Check(F.ViewDragging and (GetCapture=F.UIControls.Preview.Handle),'preview drag missing capture');
    Pan := F.ViewPan; F.UIControls.Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam($FFE1,21));
    Check((Abs(F.ViewPan.X-Pan.X+33)<0.01) and (Abs(F.ViewPan.Y-Pan.Y-19)<0.01),'drag outside control did not pan');
    F.UIControls.Preview.Perform(WM_LBUTTONUP,0,MakeLParam($FFE1,21));
    Check(not F.ViewDragging and (GetCapture<>F.UIControls.Preview.Handle),'mouse-up retained capture');
    F.UIControls.Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(2,2)); ReleaseCapture;
    Check(not F.ViewDragging,'capture loss left drag active');
    F.UIControls.Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(2,2));
    F.UIControls.Preview.Perform(WM_CANCELMODE,0,0); Check(not F.ViewDragging,'cancel-mode retained drag');
    Wheel(-10000); Check(SameValue(F.ViewZoom,0.1,0.00001),'minimum zoom limit');
    Wheel(10000); Check(SameValue(F.ViewZoom,32,0.00001),'maximum zoom limit');
    F.UIControls.FitButton.Click; Check(SameValue(F.ViewZoom,1) and (F.ViewPan.X=0) and (F.ViewPan.Y=0),'fit button did not reset view');
    Wheel(120); Pan := F.ViewPan; Zoom := F.ViewZoom;
    D.Width := D.Width+24; D.Width := D.Width-24; CheckView;
    Check(F.PreviewRenderCount=Count,'zoom/pan/resize recomposed PSD');
    // Native row click previews an unassigned expression without changing JSON or invoking assignment.
    Row := F.Document.LayerIndex(Keys[5]); F.UIControls.LayerList.TopIndex := Row;
    R := F.UIControls.LayerList.ItemRect(Row); P := Point(F.UIControls.LayerList.ClientWidth-12,(R.Top+R.Bottom) div 2);
    F.UIControls.LayerList.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(P.X,P.Y));
    F.UIControls.LayerList.Perform(WM_LBUTTONUP,0,MakeLParam(P.X,P.Y));
    Check(F.SelectedLayerKey=Keys[5],'native click selected wrong expression');
    Check((F.PreviewBitmap<>nil) and SamePixels(Old,F.PreviewBitmap),'selection blanked the previous composite');
    F.UIControls.Preview.Repaint;
    DC := GetDC(F.UIControls.Preview.Handle);
    try Check(F.UIControls.Preview.Perform(WM_ERASEBKGND,DC,0)=1,'preview background erase not suppressed');
    finally ReleaseDC(F.UIControls.Preview.Handle,DC); end;
    // Queue several generations before polling; only the final selected row may be published.
    Check(F.SelectLayer(Keys[2]) and F.SelectLayer(Keys[4]) and F.SelectLayer(Keys[1]),'rapid selection row absent');
    Check(F.ConfigJSON=Before,'row selection modified saved assignments/visibility'); CheckView; Await;
    Overrides := BuildMusicStudioPsdOverrides(F.Document,Config,0);
    try
      F.Document.SelectLayerOverride(Overrides,Keys[1]); Check(F.Document.Render(B,Overrides),F.Document.LastError);
      Check(SamePixels(B,F.PreviewBitmap),'final selection preview shows stale generation');
      if CheckParts then CheckPartsPixels(F.PreviewBitmap);
    finally Overrides.Free; end;
    Check(F.ConfigJSON=Before,'completed selection changed config'); CheckView;
    SaveClient(D,TPath.Combine(Dir,'selection-zoom-pan.png'));
    // Compare native name pixels before/after assigning; only the fixed left vowel column changes.
    Check(F.SelectLayer(Keys[5]),'vowel label target absent');
    F.UIControls.MouthMenu.Items[13].Click; Await;
    Row := F.Document.LayerIndex(Keys[5]); CaptureRow(NameBefore,LabelsBefore);
    F.AssignSelectedMouth(11); Await; CheckView; CaptureRow(NameAfter,LabelsAfter);
    Check(SamePixels(NameBefore,NameAfter),'assignment shifted/repainted layer-name X coordinates');
    Check(not SamePixels(LabelsBefore,LabelsAfter),'vowel column did not display assigned small vowel');
    R := F.UIControls.LayerList.ItemRect(Row);
    F.UIControls.LayerList.OnMouseMove(F.UIControls.LayerList,[],4,(R.Top+R.Bottom) div 2);
    Check(Pos(MUSIC_STUDIO_MOUTH_CAPTIONS[11],F.UIControls.LayerList.Hint)>0,'full assigned vowel tooltip missing');
    SaveClient(D,TPath.Combine(Dir,'assigned-small-vowel-fixed-column.png'));
    // Restore the starting assignments through the same public editor commands.
    for I := 0 to 11 do if MusicStudioMouthLayer(Config,I)='' then F.ClearSelectedMouth(I)
    else begin Check(F.SelectLayer(MusicStudioMouthLayer(Config,I)),'restore assigned key absent'); F.AssignSelectedMouth(I); end;
    F.SelectMouth(0); Await; CheckView;
    F.UIControls.Preview.Perform(WM_LBUTTONDBLCLK,MK_LBUTTON,MakeLParam(2,2));
    F.UIControls.Preview.Perform(WM_LBUTTONUP,0,MakeLParam(2,2));
    Check(SameValue(F.ViewZoom,1) and (F.ViewPan.X=0) and (F.ViewPan.Y=0),'double click did not restore fit');
    Writeln('PSD_SELECTION_CONFIG_UNCHANGED_LAST_GENERATION_PARTS_FIXED_VOWEL_COLUMN_NATIVE_WHEEL_ANCHOR_PAN_CAPTURE_LIMITS_FIT_VIEW_PRESERVED_OK ppi=',D.CurrentPPI);
  finally
    LabelsAfter.Free; LabelsBefore.Free; NameAfter.Free; NameBefore.Free; Old.Free; B.Free; Config.Free;
    Timer.Enabled := True;
  end;
end;
procedure TMouthDriver.PopupTick(Sender: TObject);
var Info: TGUIThreadInfo; Config: TJSONObject; I: Integer;
begin
  FillChar(Info,SizeOf(Info),0); Info.cbSize := SizeOf(Info);
  if not GetGUIThreadInfo(GetCurrentThreadId,Info) or ((Info.flags and GUI_INMENUMODE)=0) then Exit;
  PopupTimer.Enabled := False;
  try
    Check(PopupFrame.SelectedLayerKey=PopupKey,'context menu selected a different row');
    Check(PopupFrame.UIControls.MouthMenu.Items.Count=14,'popup 12 assignments/clear missing');
    Config := ParseMusicStudioPsdConfig(PopupFrame.ConfigJSON);
    try
      for I := 0 to 11 do Check(PopupFrame.UIControls.MouthMenu.Items[I].Checked=
        (MusicStudioMouthLayer(Config,I)=PopupKey),'popup assigned checkmark wrong');
    finally Config.Free; end;
    PopupSeen := True;
  except on E: Exception do Failure := E.Message; end;
  // Native selection dispatches WM_COMMAND after the menu loop closes. Defer
  // the callback instead of changing the UI from inside TrackPopupMenu.
  EndMenu;
  if (Failure='') and (PopupPick>=0) then
    PostMessage(Info.hwndMenuOwner,WM_COMMAND,PopupFrame.UIControls.MouthMenu.Items[PopupPick].Command,0);
end;
procedure TMouthDriver.ChooseMouth(F: TMusicStudioPsdLayersFrame; Mouth,Route: Integer; CancelPopup: Boolean);
var R: TRect; Target: Integer; Handled: Boolean; Key: Word; BeforeCombo: Integer;
    PopupStarted: UInt64;
begin
  PopupFrame := F; PopupPick := Mouth; PopupKey := Keys[Mouth]; PopupSeen := False;
  // Native popups require an active owner. A hidden test host can otherwise
  // lose activation to the surrounding desktop between asynchronous ticks.
  SetForegroundWindow(GetParentForm(F).Handle); SetActiveWindow(GetParentForm(F).Handle);
  Application.CancelHint;
  if CancelPopup then PopupPick := -1;
  Target := F.Document.LayerIndex(PopupKey); Check(Target>=0,'popup row missing');
  BeforeCombo := F.UIControls.MouthCombo.ItemIndex;
  if Route=1 then F.UIControls.LayerList.TopIndex := Target
  else if Route=4 then begin
    F.UIControls.LayerList.ItemIndex := Target-1;
    F.UIControls.LayerList.Perform(WM_KEYDOWN,VK_DOWN,1); F.UIControls.LayerList.Perform(WM_KEYUP,VK_DOWN,1);
    Check(F.SelectedLayerKey=PopupKey,'keyboard arrow selected wrong row');
  end else Check(F.SelectLayer(PopupKey),'popup target absent');
  Check(F.UIControls.MouthCombo.ItemIndex=BeforeCombo,'selecting a layer changed preview mother first');
  Timer.Enabled := False; PopupStarted := GetTickCount64; PopupTimer.Enabled := True;
  try
    case Route of
      1: begin
        R := F.UIControls.LayerList.ItemRect(Target); Handled := False;
        F.UIControls.LayerList.OnContextPopup(F.UIControls.LayerList,Point(70,(R.Top+R.Bottom) div 2),Handled);
        Check(Handled,'row context popup not handled');
      end;
      2,3: begin
        Key := VK_APPS; if Route=3 then Key := VK_F10;
        if Route=3 then F.UIControls.LayerList.OnKeyDown(F.UIControls.LayerList,Key,[ssShift])
        else F.UIControls.LayerList.OnKeyDown(F.UIControls.LayerList,Key,[]);
        Check(Key=0,'keyboard popup not handled');
      end;
      4: Check(F.UIControls.LayerList.Perform(CM_DIALOGKEY,VK_RETURN,0)=1,'Enter accepted dialog instead of assigning');
    else F.UIControls.AssignButton.Click;
    end;
    Application.ProcessMessages; // Dispatch the native popup's posted WM_COMMAND.
    Check(Failure='',Failure); Check(PopupSeen,Format('native assignment popup not displayed mouth=%d route=%d step=%d elapsed=%d foreground=%x owner=%x active=%x',[Mouth,Route,Step,GetTickCount64-PopupStarted,GetForegroundWindow,GetParentForm(F).Handle,GetActiveWindow]));
    Check(F.SelectedLayerKey=PopupKey,'assignment changed selected target');
    Check(Pos(MUSIC_STUDIO_MOUTH_CAPTIONS[Mouth],F.UIControls.SelectionLabel.Caption)>0,'selected layer assigned mother not shown');
  finally PopupTimer.Enabled := False; Timer.Enabled := True; end;
end;
procedure TMouthDriver.Tick(Sender: TObject);
var I,N: Integer; D: TMusicStudioPatternSettings; F: TMusicStudioPsdLayersFrame;
    Config,Expected: TJSONObject; B: TBitmap; Key,Before: string; Value: TJSONValue; Work,R: TRect; Info: TMusicStudioLayerInfo;
begin
  D := nil;
  for I := 0 to Screen.FormCount-1 do if Screen.Forms[I] is TMusicStudioPatternSettings then begin
    D := TMusicStudioPatternSettings(Screen.Forms[I]); Break; end;
  if D=nil then Exit;
  try
    Check(Failure='',Failure); Check(GetTickCount64<Deadline,'modal operation timeout');
    ShowWindow(D.Handle,SW_SHOWNOACTIVATE); D.SilentVisualMode := True; F := D.LayersFrame;
    Check(F<>nil,'integrated PSD entry opened another settings mode');
    if (IntegratedPPI>0) and not ScaledOnce then begin
      D.ScaleForPPI(IntegratedPPI); D.Width := D.Constraints.MinWidth;
      F.UIControls.LeftPane.Width := MulDiv(170,IntegratedPPI,96);
      // Keep the enlarged native window on-screen so screenshots include its actual full client area.
      Work := D.Monitor.WorkareaRect; D.Position := poDesigned;
      D.Left := Work.Left+(Work.Width-D.Width) div 2; D.Top := Work.Top+(Work.Height-D.Height) div 2;
      D.Update; ScaledOnce := True;
    end;
    F.PollResults; if F.IsLoading or F.IsRendering then Exit;
    Check(F.CanApply,F.StateText);
    Check(F.UIControls.MouthCombo.Showing and F.UIControls.AssignButton.Showing and
      F.UIControls.ClearButton.Showing,'mouth selector or assignment controls hidden');
    Check(F.UIControls.MouthCombo.Items.Count=12,'mouth selector does not contain all 12 shapes');
    Check((F.UIControls.Toolbar.Top>=F.UIControls.Header.Top+F.UIControls.Header.Height) and
      (F.UIControls.Toolbar.Top+F.UIControls.Toolbar.Height<=F.ClientHeight),'mouth toolbar outside PSD frame');
    Check((F.UIControls.MouthCombo.Left>=0) and
      (F.UIControls.MouthCombo.Left+F.UIControls.MouthCombo.Width<=F.UIControls.Toolbar.ClientWidth) and
      (F.UIControls.AssignButton.Top+F.UIControls.AssignButton.Height<=F.UIControls.Toolbar.ClientHeight) and
      (F.UIControls.ClearButton.Left+F.UIControls.ClearButton.Width<=F.UIControls.Toolbar.ClientWidth),'mouth controls clipped');
    if Step<0 then begin
      // Assert before touching the combo or invoking OnChange: FillLayers must restore the saved row.
      Check(F.UIControls.MouthCombo.ItemIndex=0,'loaded modal did not select normal mouth');
      Check(F.SelectedLayerKey=Keys[0],'initial/reloaded modal selected an unrelated first layer');
      for N := 0 to High(F.Document.Layers) do begin
        Info := F.Document.Layers[N]; Check(F.UIControls.LayerList.Items[N].StartsWith(Info.Name),'row hides local name with full path');
      end;
      if Step=-3 then begin
        Before := F.ConfigJSON; ChooseMouth(F,0,0,True);
        Check(F.ConfigJSON=Before,'cancel popup changed assignments');
        if CheckParts then begin
          Key := FindName(F.Document,'*shape0','/other/'); N := F.Document.LayerIndex(Key);
          Check(F.UIControls.LayerList.Items[N]=F.UIControls.LayerList.Items[F.Document.LayerIndex(Keys[0])],'duplicate local name fixture missing');
          Key := FindName(F.Document,'body_'+StringOfChar('長',80)); Check(F.SelectLayer(Key),'long local name absent');
          R := F.UIControls.LayerList.ItemRect(F.Document.LayerIndex(Key));
          F.UIControls.LayerList.OnMouseMove(F.UIControls.LayerList,[],70,(R.Top+R.Bottom) div 2);
          Check(Pos(F.Document.Layers[F.Document.LayerIndex(Key)].Path,F.UIControls.LayerList.Hint)>0,'full path tooltip missing');
          SaveClient(D,TPath.Combine(Dir,'long-local-name.png')); Check(F.SelectLayer(Keys[0]),'restore normal selection');
        end;
        Inc(Step); Exit;
      end;
      ChooseMouth(F,0,0);
      Config := ParseMusicStudioPsdConfig(F.ConfigJSON);
      try Check(MusicStudioMouthLayer(Config,0)=Keys[0],'untouched initial/reload assign overwrote normal mouth');
      finally Config.Free; end;
      SaveClient(D,TPath.Combine(Dir,'loaded-row-'+BoolToStr(Reopen,True)+'-'+IntToStr(-Step)+'.png'));
      Inc(Step);
      if Step=-1 then F.UIControls.ReloadButton.Click;
      Exit;
    end;
    if Step=3 then begin
      Config := ParseMusicStudioPsdConfig(F.ConfigJSON);
      try
        Check((MusicStudioMouthLayer(Config,0)='') and (MusicStudioMouthLayer(Config,6)=''),'clear selected layer did not clear both assigned mouths');
        for N := 1 to 10 do if N<>6 then Check(MusicStudioMouthLayer(Config,N)=Keys[N],'clear layer changed unrelated assignment');
      finally Config.Free; end;
      Timer.Enabled := False; D.ModalResult := mrCancel; Exit;
    end;
    if Step=2 then begin
      Config := ParseMusicStudioPsdConfig(F.ConfigJSON); Expected := nil; B := TBitmap.Create;
      try
        Check(MusicStudioMouthLayer(Config,11)='','clear button kept small-O assignment');
        Expected := BuildMusicStudioPsdOverrides(F.Document,Config,11);
        Value := Expected.GetValue(Keys[5]); Check((Value is TJSONBool) and TJSONBool(Value).AsBoolean,'small-O fallback missing');
        Check(F.Document.Render(B,Expected) and SamePixels(B,F.PreviewBitmap),'small-O fallback preview mismatch');
        if CheckParts then CheckPartsPixels(F.PreviewBitmap);
      finally B.Free; Expected.Free; Config.Free; end;
      Check(F.SelectLayer(Keys[0]),'clear-layer row missing'); PopupFrame := F;
      PopupKey := Keys[0]; PopupPick := 13; PopupSeen := False; Timer.Enabled := False; PopupTimer.Enabled := True;
      try F.UIControls.AssignButton.Click; Application.ProcessMessages;
      finally PopupTimer.Enabled := False; Timer.Enabled := True; end;
      Check(Failure='',Failure); Check(PopupSeen,'clear-layer popup absent'); Step := 3; Exit;
    end;
    if Step=0 then begin
      if not ViewChecksDone then begin CheckSelectionView(D,F); ViewChecksDone := True; end;
      if Reopen then begin
        Config := ParseMusicStudioPsdConfig(F.ConfigJSON);
        try for N := 0 to 11 do Check(MusicStudioMouthLayer(Config,N)=Keys[N],'saved assignment lost: '+IntToStr(N));
        finally Config.Free; end;
      end;
      // Layer first for every initial/reopened/integrated flow; never change the combo first.
      ChooseMouth(F,Index,Index mod 5);
      Step := 1; Exit;
    end;
    Config := ParseMusicStudioPsdConfig(F.ConfigJSON); Expected := nil; B := TBitmap.Create;
    try
      Key := MusicStudioMouthLayer(Config,Index); Check(Key=Keys[Index],'assign button did not store stable key');
      Check(F.SelectedLayerKey=Keys[Index],'selected row does not match saved mouth');
      Expected := BuildMusicStudioPsdOverrides(F.Document,Config,Index);
      if Index=0 then begin
        TFile.WriteAllText(TPath.Combine(Dir,'overrides-'+BoolToStr(Reopen,True)+'.json'),Expected.ToJSON,TEncoding.UTF8);
        SaveClient(D,TPath.Combine(Dir,'modal-'+BoolToStr(Reopen,True)+'-normal.png'));
      end;
      Value := Expected.GetValue(OldKey);
      Check((Value is TJSONBool) and not TJSONBool(Value).AsBoolean,'old mouth sibling stays visible when phoneme parent opens');
      Value := Expected.GetValue(BranchKey);
      Check((Value is TJSONBool) and TJSONBool(Value).AsBoolean,'phoneme parent remains hidden');
      // Explicit expected legacy-mouth exclusion: verify actual rendered bitmap, not just a mapping string.
      MusicStudioSetJsonBoolean(Expected,OldKey,False);
      Check(F.Document.Render(B,Expected),F.Document.LastError); Check(SamePixels(B,F.PreviewBitmap),'preview does not apply vowel visibility');
      if CheckParts then CheckPartsPixels(F.PreviewBitmap);
      Check(not F.UIControls.LayerList.Checked[F.Document.LayerIndex(OldKey)],'checks disagree with rendered mouth');
      Check(F.UIControls.LayerList.Checked[F.Document.LayerIndex(BranchKey)],'checks hide active phoneme parent');
      if Index=1 then SaveClient(D,TPath.Combine(Dir,'modal-'+BoolToStr(Reopen,True)+'-a.png'));
    finally B.Free; Expected.Free; Config.Free; end;
    Inc(Index); Step := 0; if Index<=11 then Exit;
    if CancelAfter then begin
      // Cancellation after an edit must not replace the saved shared settings.
      F.UIControls.ClearButton.Click; Step := 2;
    end else begin
      Timer.Enabled := False;
      for I := 0 to D.ComponentCount-1 do if (D.Components[I] is TButton) and
        (TButton(D.Components[I]).Caption='OK') then begin TButton(D.Components[I]).Click; Exit; end;
      Check(False,'modal OK control absent');
    end;
  except on E: Exception do begin Failure := E.Message; Timer.Enabled := False; D.ModalResult := mrCancel; end; end;
end;
procedure RunDialog(Store: TMusicStudioSharedPsdLibrary; var Pattern: TMusicStudioPattern;
  Driver: TMouthDriver; Reopen: Boolean; CancelAfter: Boolean = False);
var Error: string; Saved: Boolean;
begin
  Driver.Index := 0; Driver.Step := -3; Driver.Failure := ''; Driver.Reopen := Reopen; Driver.CancelAfter := CancelAfter; Driver.ViewChecksDone := False;
  Driver.Deadline := GetTickCount64+45000; Driver.Timer.Enabled := True;
  try Saved := EditMusicStudioSharedItem(nil,Store,Pattern,Error);
  finally Driver.Timer.Enabled := False; end;
  Check(Driver.Failure='',Driver.Failure); Check(Error='',Error); Check(Saved<>CancelAfter,'modal save/cancel result');
end;
procedure RunIntegratedDialog(Store: TMusicStudioSharedPsdLibrary; const Pattern: TMusicStudioPattern;
  Driver: TMouthDriver; PPI: Integer);
var Main: TFormMusicStudioSettings; Track,I: Integer; Error,Before,After: string;
    Saved: TMusicStudioPsdAsset; Config: TJSONObject; OriginalDir: string;
begin
  Main := TFormMusicStudioSettings.Create(nil); OriginalDir := Driver.Dir;
  try
    Main.SilentVisualMode := True; Main.LibraryRoot := Store.Root; Main.LoadDocument('');
    Track := Main.Document.AddTrack('psd'); Main.Document.AssignPsd(Track,Pattern.AssetID);
    Check(Main.Document.TrySave(Before,Error),Error); Main.LoadDocument(Before);
    Main.Show; ShowWindow(Main.Handle,SW_SHOWNOACTIVATE);
    Main.TimelineBox.SelectSlot(Track,TestSlotIndex(Main.Document,Track,'psd'));
    Check(Main.LibraryKind='psd','PSD slot did not show shared PSD library');
    I := Main.PatternList.Items.IndexOf(Pattern.Name); Check(I>=0,'shared PSD missing from integrated list');
    Main.PatternList.ItemIndex := I; Main.PatternList.OnClick(Main.PatternList);
    Check(Main.EditButton.Enabled and Assigned(Main.PatternList.OnDblClick),'integrated PSD settings entry absent');
    Driver.Dir := TPath.Combine(OriginalDir,'integrated-'+IntToStr(PPI)); ForceDirectories(Driver.Dir);
    SaveClient(Main,TPath.Combine(Driver.Dir,'integrated-before-open.png'));
    Driver.Index := 0; Driver.Step := -3; Driver.Failure := ''; Driver.Reopen := True;
    Driver.CancelAfter := False; Driver.IntegratedPPI := PPI; Driver.ScaledOnce := False;
    Driver.ViewChecksDone := False;
    Driver.Deadline := GetTickCount64+45000; Driver.Timer.Enabled := True;
    try Main.PatternList.OnDblClick(Main.PatternList);
    finally Driver.Timer.Enabled := False; end;
    Check(Driver.Failure='',Driver.Failure); Check(Driver.Index=12,'integrated mouth flow did not complete');
    Check(Main.SharedLibrary.TryRead(Pattern.AssetID,Saved,Error),Error);
    Config := ParseMusicStudioPsdConfig(Saved.ConfigJSON);
    try for I := 0 to 11 do Check(MusicStudioMouthLayer(Config,I)=Driver.Keys[I],'integrated entry lost mouth assignment');
    finally Config.Free; end;
    Check(Main.Document.TrySave(After,Error) and (Before=After),'opening shared PSD settings changed project JSON');
    Check(not Main.Preview.AudioEngineAllocated and (Main.TimelineBox.WaveCache.DecodeCount=0),'integrated entry started audio');
    Writeln('PSD_LAYER_FIRST_INTEGRATED_RIGHT_ROW_POPUP_12_KEYBOARD_NARROW_LOCAL_NAMES_ASSIGN_PREVIEW_SAVE_NO_AUDIO_OK ppi=',PPI);
  finally Driver.Dir := OriginalDir; Driver.IntegratedPPI := 0; Main.Free; end;
end;
procedure Flow(const Dir,Source,SeedAssetJSON: string; Actual: Boolean);
var Store,Other: TMusicStudioSharedPsdLibrary; A,Saved: TMusicStudioPsdAsset; Dup: Boolean;
    D: TMusicStudioLayerDocument; Driver: TMouthDriver; P: TMusicStudioPattern;
    SourceHash,ManagedHash,Error,Before,Revision: string; Config,Seed: TJSONObject; I: Integer;
    OldException: TExceptionEvent;
begin
  ForceDirectories(Dir); SourceHash := THashSHA2.GetHashStringFromFile(Source);
  Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Dir,'isolated-library')); D := TMusicStudioLayerDocument.Create;
  Driver := TMouthDriver.Create; Driver.Timer := TTimer.Create(nil); Driver.Timer.Enabled := False;
  Driver.PopupTimer := TTimer.Create(nil); Driver.PopupTimer.Enabled := False;
  Driver.PopupTimer.Interval := 20; Driver.PopupTimer.OnTimer := Driver.PopupTick;
  Driver.Timer.Interval := 20; Driver.Timer.OnTimer := Driver.Tick; Driver.Dir := Dir;
  Driver.CheckParts := not Actual;
  OldException := Application.OnException; Application.OnException := Driver.AppException;
  try
    Check(Store.TryImport(Source,'母音検証','#CC8CE0',A,Dup,Error),Error); ManagedHash := THashSHA2.GetHashStringFromFile(A.FilePath);
    Check(D.LoadFile(A.FilePath),D.LastError);
    if Actual then begin
      Driver.OldKey := FindName(D,'*A 普通','/口/'); Driver.BranchKey := FindName(D,'*00 口パク','/口/');
      Driver.Keys[0] := FindName(D,'*00','/口/');
      for I := 1 to 5 do Driver.Keys[I] := FindName(D,'*00'+Char(Ord('a')+I-1),'/口/');
    end else begin
      Driver.OldKey := FindName(D,'*ordinary'); Driver.BranchKey := FindName(D,'*phonemes');
      for I := 0 to 5 do Driver.Keys[I] := FindName(D,'*shape'+IntToStr(I),'/mouth/');
    end;
    Driver.Keys[6] := Driver.Keys[0]; for I := 7 to 11 do Driver.Keys[I] := Driver.Keys[I-6];
    Config := ParseMusicStudioPsdConfig(''); Seed := nil;
    try
      if SeedAssetJSON<>'' then begin
        Seed := TJSONObject.ParseJSONValue(TFile.ReadAllText(SeedAssetJSON,TEncoding.UTF8)) as TJSONObject;
        Config.Free; Config := ParseMusicStudioPsdConfig(Seed.GetValue('config').ToJSON);
      end;
      MusicStudioAssignMouth(Config,0,Driver.Keys[0]); Config.AddPair('mouthTestExtension','preserve'); A.ConfigJSON := Config.ToJSON;
    finally Seed.Free; Config.Free; end;
    Check(Store.TrySave(A,Error),Error);
    P := Default(TMusicStudioPattern); P.Kind := 'psd'; P.AssetID := A.ID; P.Name := A.Name; P.Color := A.Color; P.ConfigJSON := A.ConfigJSON;
    RunDialog(Store,P,Driver,False);
    Check(Store.TryRead(A.ID,Saved,Error),Error); Check(Saved.ID=A.ID,'asset identity changed'); Revision := Saved.Revision;
    Config := ParseMusicStudioPsdConfig(Saved.ConfigJSON);
    try
      for I := 0 to 11 do Check(MusicStudioMouthLayer(Config,I)=Driver.Keys[I],'persisted stable key lost');
      Check(Config.GetValue<string>('mouthTestExtension')='preserve','unknown config member lost');
    finally Config.Free; end;
    Other := TMusicStudioSharedPsdLibrary.Create(Store.Root);
    try
      Check(Other.TryRead(A.ID,Saved,Error),Error); P.ConfigJSON := Saved.ConfigJSON;
      RunDialog(Other,P,Driver,True); Check(Other.TryRead(A.ID,Saved,Error),Error);
      Config := ParseMusicStudioPsdConfig(Saved.ConfigJSON);
      try for I := 0 to 11 do Check(MusicStudioMouthLayer(Config,I)=Driver.Keys[I],'reopen assign/save overwrote mouth');
      finally Config.Free; end;
      Revision := Saved.Revision; P.ConfigJSON := Saved.ConfigJSON;
      Before := THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(A.FilePath),'asset.json'));
      RunDialog(Other,P,Driver,True,True); Check(Other.TryRead(A.ID,Saved,Error),Error);
      Check(Saved.Revision=Revision,'cancel changed shared revision');
    finally Other.Free; end;
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(ExtractFileDir(A.FilePath),'asset.json'))=Before,'cancel changed shared JSON');
    RunIntegratedDialog(Store,P,Driver,96); RunIntegratedDialog(Store,P,Driver,144);
    Check((THashSHA2.GetHashStringFromFile(Source)=SourceHash) and (THashSHA2.GetHashStringFromFile(A.FilePath)=ManagedHash),'mouth editor changed PSD bytes');
    Writeln('PSD_MOUTH_INITIAL_RELOAD_REOPEN_ROW_NO_CHANGE_EVENT_ASSIGN_SAVE_12_PREVIEW_PARTS_PIXELS_SHARED_CANCEL_SOURCE_UNCHANGED_OK source=',Source);
  finally Application.OnException := OldException; Driver.PopupTimer.Free; Driver.Timer.Free; Driver.Free; D.Free; Store.Free; end;
end;
procedure RunPsdMouthChecks(const Root,ActualPSD,SeedAssetJSON: string);
var Dir,Source: string; G: TGUID;
begin
  CreateGUID(G); Dir := TPath.Combine(Root,'psd-mouth-'+GUIDToString(G)); ForceDirectories(Dir);
  if ActualPSD<>'' then Flow(TPath.Combine(Dir,'actual'),ActualPSD,SeedAssetJSON,True)
  else begin Source := TPath.Combine(Dir,'nested-mouth.psd'); WriteNestedPSD(Source);
    Flow(TPath.Combine(Dir,'synthetic'),Source,'',False); end;
end;
end.
