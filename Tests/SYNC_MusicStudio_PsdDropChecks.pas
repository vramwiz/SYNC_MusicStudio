unit SYNC_MusicStudio_PsdDropChecks;

// 左の共有PSD一覧から演奏者見出しへ落とす実イベントを、隔離ライブラリで確認する。
// 音声処理・DPI変更・実共有設定への書込は行わない。
interface
procedure RunPsdDropChecks(const Root: string; const ActualPSD1: string = ''; const ActualPSD2: string = '');
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.JSON, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.Controls,
  SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_SharedPsdLibrary;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create('PSD_DROP: '+Message); end;
procedure Fixture(const Path: string; PoseOnly: Boolean);
var D: TArtDocument; Row,Pattern,L: TArtLayer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 8; D.Height := 2;
    if PoseOnly then begin
      L := D.AddLayer(alkGroup,'演奏属性:その他',TArtBounds.Create(0,0,0,0)); L.Visible := False;
      Row := D.AddLayer(alkGroup,'ポーズ',TArtBounds.Create(0,0,0,0));
      L := D.AddLayer(alkImage,'通常',TArtBounds.Create(0,0,1,1),Row);
      L.Pixels := TBytes.Create(60,80,90,255);
      L := D.AddLayer(alkImage,'*演奏姿勢',TArtBounds.Create(0,0,1,1),Row);
      L.Pixels := TBytes.Create(20,170,70,255); L.Visible := False;
    end else begin
      L := D.AddLayer(alkGroup,'演奏属性:ドラム',TArtBounds.Create(0,0,0,0)); L.Visible := False;
      Row := D.AddLayer(alkGroup,'右手',TArtBounds.Create(0,0,0,0));
      Pattern := D.AddLayer(alkGroup,'*打撃',TArtBounds.Create(0,0,0,0),Row);
      L := D.AddLayer(alkImage,'*0',TArtBounds.Create(0,0,1,1),Pattern);
      L.Pixels := TBytes.Create(90,80,60,255);
      L := D.AddLayer(alkImage,'*1',TArtBounds.Create(0,0,1,1),Pattern);
      L.Pixels := TBytes.Create(190,20,40,255); L.Visible := False;
    end;
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
procedure RunPsdDropChecks(const Root,ActualPSD1,ActualPSD2: string);
var UI: TFormMusicStudioSettings; A,B,RealAsset: TMusicStudioPsdAsset;
  Error,Text,Before,AssignedText,PathA,PathB,Held,RealPath,RealHash: string;
  T,Music,Other,TempoSlot,Images: Integer; Duplicate,Accept: Boolean; R: TRect;
  function JSON: string;
  begin Check(UI.Document.TrySave(Result,Error),Error); end;
  procedure LoadModel;
  begin Text := JSON; UI.LoadDocument(Text); end;
  procedure SelectAsset(const Asset: TMusicStudioPsdAsset);
  var I: Integer;
  begin
    UI.TimelineBox.SelectSlot(T,0);
    for I := 0 to UI.PatternList.Count-1 do if UI.PatternList.Items[I]=Asset.Name then begin UI.PatternList.ItemIndex := I; Exit; end;
    raise Exception.Create('PSD_DROP: asset not listed '+Asset.Name);
  end;
  procedure AtPoint(X,Y: Integer; Expected: Boolean; Source: TObject = nil);
  begin
    if Source=nil then Source := UI.PatternList;
    Accept := not Expected;
    UI.TimelineBox.OnDragOver(UI.TimelineBox,Source,X,Y,dsDragMove,Accept);
    Check(Accept=Expected,Format('drag acceptance expected=%s at %d,%d: %s',[
      BoolToStr(Expected,True),X,Y,UI.StatusLabel.Caption]));
  end;
  procedure RejectPoint(X,Y: Integer; Source: TObject = nil);
  begin
    Before := JSON; AtPoint(X,Y,False,Source); if Source=nil then Source := UI.PatternList;
    UI.TimelineBox.OnDragDrop(UI.TimelineBox,Source,X,Y);
    Check(JSON=Before,'rejected drag changed project');
  end;
  procedure HeaderDrop(const Asset: TMusicStudioPsdAsset; Expanded: Boolean);
  var Cursor: Double;
  begin
    SelectAsset(Asset);
    if UI.TimelineBox.TrackExpanded(T)<>Expanded then UI.TimelineBox.ToggleTrack(T);
    R := UI.TimelineBox.TrackThumbnailRect(T); Check(R.Width>0,'performer image header absent');
    UI.Preview.RestoreMusicalCursor(2,16,False); Cursor := UI.Preview.Position;
    AtPoint(R.CenterPoint.X,R.CenterPoint.Y,True);
    UI.TimelineBox.OnDragDrop(UI.TimelineBox,UI.PatternList,R.CenterPoint.X,R.CenterPoint.Y);
    Check(Abs(UI.Preview.Position-Cursor)<1E-9,'PSD drop reset playhead');
    Check(UI.Document.TrackAt(T).PsdAssetID=Asset.ID,'header drag did not assign PSD');
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'drag allocated audio');
  end;
begin
  ForceDirectories(Root); PathA := TPath.Combine(Root,'drum.psd'); PathB := TPath.Combine(Root,'poses.psd');
  Fixture(PathA,False); Fixture(PathB,True);
  UI := TFormMusicStudioSettings.Create(nil);
  try
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'PSDAssets'); UI.LoadDocument('');
    Check(UI.SharedLibrary.TryImport(PathA,'打撃PSD','#B09060',A,Duplicate,Error),Error);
    Check(UI.SharedLibrary.TryImport(PathB,'姿勢PSD','#609080',B,Duplicate,Error),Error);
    T := UI.Document.AddTrack('performer'); Music := UI.Document.AddTrack('audio'); Other := UI.Document.AddTrack('performer');
    LoadModel; UI.Show; ShowWindow(UI.Handle,SW_SHOWNOACTIVATE); Application.ProcessMessages;
    Check(UI.PatternList.DragMode=dmAutomatic,'PSD list drag disabled');
    Check(UI.Document.TrackAt(T).PsdAssetID='','new performer already assigned');
    HeaderDrop(A,True);
    Check(UI.Document.TrackAt(T).PerformanceAttribute='drums','header assignment attribute');
    AssignedText := JSON; UI.UndoEdit; Check(UI.Document.TrackAt(T).PsdAssetID='','header assignment undo');
    UI.RedoEdit; Check(JSON=AssignedText,'header assignment redo');
    HeaderDrop(B,False); Check(UI.Document.TrackAt(T).PerformanceAttribute='other','pose-only PSD rejected');
    Check(UI.Document.TrackAt(T).Slots[1].Name='ポーズ','pose-only capability not generated');
    Check(UI.Document.TrackAt(Other).PsdAssetID='','different performer changed');
    SelectAsset(A); RejectPoint(20,UI.TimelineBox.TrackRowTop(Music)+10);
    RejectPoint(20,1); RejectPoint(20,UI.TimelineBox.TrackRowTop(T)+10,UI.StatusLabel);
    Before := JSON; Check(not UI.DropSelectedLibraryAt(UI.Document.TrackCount+1,-1,0,Error),'out-of-range track accepted');
    Check(JSON=Before,'invalid track changed document');
    // PSD枠は内部互換だけを保持し、時間軸の行は表示しない。
    HeaderDrop(A,True); Check(UI.TimelineBox.SlotRowTop(T,0)=-1,'PSD row still visible');
    SelectAsset(B); RejectPoint(UI.TimelineBox.TrackColumnWidth+20,UI.TimelineBox.SlotRowTop(T,1)+12);
    Held := A.FilePath+'.held'; TFile.Move(A.FilePath,Held);
    try
      UI.SharedLibraryChanged; SelectAsset(A); RejectPoint(20,UI.TimelineBox.TrackRowTop(T)+15);
    finally TFile.Move(Held,A.FilePath); end;
    UI.SharedLibraryChanged; SelectAsset(A); AtPoint(20,UI.TimelineBox.TrackRowTop(T)+15,True);
    // PSD以外の項目は固定列へ置かず、時間領域だけで配置する。
    TempoSlot := UI.Document.AddSlot(Music,'tempo'); UI.Document.AddTempo; LoadModel;
    if not UI.TimelineBox.TrackExpanded(Music) then UI.TimelineBox.ToggleTrack(Music);
    UI.TimelineBox.SelectSlot(Music,TempoSlot); Check(UI.PatternList.Count>0,'tempo list missing'); UI.PatternList.ItemIndex := 0;
    RejectPoint(20,UI.TimelineBox.SlotRowTop(Music,TempoSlot)+12);
    AtPoint(UI.TimelineBox.HeaderWidth+20,UI.TimelineBox.SlotRowTop(Music,TempoSlot)+12,True);
    UI.Preview.RestoreMusicalCursor(2,16,False);
    UI.TimelineBox.OnDragDrop(UI.TimelineBox,UI.PatternList,UI.TimelineBox.HeaderWidth+20,UI.TimelineBox.SlotRowTop(Music,TempoSlot)+12);
    Check(Length(UI.Document.TrackAt(Music).Slots[TempoSlot].Clips)=1,'tempo time-area drop changed');
    Check(Abs(UI.Preview.Position-UI.Document.BeatToSeconds(2))<1E-9,'pattern drop reset playhead');
    Images := 0;
    for RealPath in TArray<string>.Create(ActualPSD1,ActualPSD2) do if RealPath<>'' then begin
      RealHash := THashSHA2.GetHashStringFromFile(RealPath);
      Check(UI.SharedLibrary.TryImport(RealPath,'実PSD '+IntToStr(Images),'#90B0C0',RealAsset,Duplicate,Error),Error);
      HeaderDrop(RealAsset,True); Check(RealHash=THashSHA2.GetHashStringFromFile(RealPath),'real source changed'); Inc(Images);
    end;
    Text := JSON; UI.LoadDocument(Text); Check(UI.Document.TrySave(Before,Error) and (Text=Before),'save reload changed assignment');
    Check(not UI.Preview.AudioEngineAllocated and (UI.TimelineBox.WaveCache.DecodeCount=0),'audio used by PSD drop checks');
    TFile.WriteAllText(TPath.Combine(Root,'psd-drop-project.json'),Text,TEncoding.UTF8);
    Writeln('PSD_HEADER_DROP_EXPANDED_COLLAPSED_POSE_UNDO_REJECT_MISSING_RESTORE_HIDDEN_PSD_TEMPO_NO_AUDIO_OK real=',Images);
  finally UI.Free; end;
end;
end.
