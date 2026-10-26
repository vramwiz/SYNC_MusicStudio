unit SYNC_MusicStudio_PerformerChecks;

// トラック統合/属性別正本/異なるPSDへの配置を隔離rootで検証する。音声処理/DPI変更を呼ばない。
interface
procedure RunPerformerChecks(const Root: string);
implementation
uses System.SysUtils, System.JSON, System.IOUtils, System.Hash, System.Classes,
  Winapi.Windows,
  Vcl.Forms, Vcl.Graphics, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls, Vcl.Imaging.pngimage, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PerformanceKinds,
  SYNC_MusicStudio_PerformanceLibrary, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_LibraryData,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PerformerEditor;
type
  TAttributeAnswer = class
    Timer: TTimer;
    Cancel: Boolean;
    procedure Tick(Sender: TObject);
  end;
procedure TAttributeAnswer.Tick(Sender: TObject);
var F: TCustomForm; C: TComponent;
begin
  F := Screen.ActiveCustomForm; if (F=nil) or (F.Caption<>'演奏属性') then Exit;
  Timer.Enabled := False;
  if Cancel then F.ModalResult := mrCancel
  else begin for C in F do if C is TListBox then TListBox(C).ItemIndex := PerformanceKindIndex('bass'); F.ModalResult := mrOK; end;
end;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('PERFORMER: '+Text); end;
procedure RunPerformerChecks(const Root: string);
var Art: TArtDocument; Actor,Channel,Pattern,Marker,L: TArtLayer; D: TMusicStudioLayerDocument;
  Profile: TMusicStudioPerformerProfile; Store: TMusicStudioSharedPsdLibrary; Lib,OtherLib: TMusicStudioPerformanceLibrary;
  A,B: TMusicStudioPsdAsset; Doc,OtherDoc: TMusicStudioDocument; P,Stale,Changed: TMusicStudioPattern;
  Data: TMusicStudioInstrumentData; Block: TInstrumentBlock; Items: TArray<TMusicStudioLibraryItem>;
  Error,PSD,CopyJSON,Before,Text,HashA,HashB: string; Duplicate: Boolean; I,J,T1,T2,T3,S1,S2,PI: Integer;
  UI,OtherUI: TFormMusicStudioSettings; Bitmap: TBitmap; PNG: TPngImage;
  SongEditor: TMusicStudioPatternSettings; Deadline: UInt64;
  Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache;
  Answer: TAttributeAnswer;
  function Group(const Name: string; Parent: TArtLayer): TArtLayer;
  begin Result := Art.AddLayer(alkGroup,Name,TArtBounds.Create(0,0,8,2),Parent); end;
  function Fixture(const Name: string; LastStage: Integer; const MarkerName: string = '演奏属性:ドラム'): string;
  var N: Integer;
  begin
    Art := TArtDocument.Create;
    try
      Art.Width := 8; Art.Height := 2; Actor := Group('人物名は任意',nil);
      Marker := Group(MarkerName,Actor); Marker.Visible := False;
      Channel := Group('右手',Actor); Pattern := Group('ソロ',Channel);
      for N := 0 to LastStage do begin
        L := Art.AddLayer(alkImage,'*'+IntToStr(N),TArtBounds.Create(0,0,1,1),Pattern);
        L.Pixels := TBytes.Create(220,30,20,255); L.Visible := N=0;
      end;
      Group('口',Actor); Channel := Group('表情',Actor);
      L := Art.AddLayer(alkImage,'*笑顔',TArtBounds.Create(1,0,2,1),Channel);
      L.Pixels := TBytes.Create(20,220,30,255); L.Visible := False;
      Channel := Group('ポーズ',Actor);
      L := Art.AddLayer(alkImage,'*お辞儀',TArtBounds.Create(2,0,3,1),Channel);
      L.Pixels := TBytes.Create(20,30,220,255); L.Visible := False;
      Result := TPath.Combine(Root,Name+'.psd'); WriteNewPsd(Art,Result,pcRaw);
    finally Art.Free; end;
  end;
  function SlotOf(Document: TMusicStudioDocument; Track: Integer; const Kind: string): Integer;
  var N: Integer; T: TMusicStudioTrack;
  begin
    T := Document.TrackAt(Track); for N := 0 to High(T.Slots) do if T.Slots[N].Kind=Kind then Exit(N);
    raise Exception.Create('slot '+Kind);
  end;
  procedure SelectKind(Form: TFormMusicStudioSettings; Track: Integer; const Kind: string);
  begin Form.TimelineBox.SelectSlot(Track,SlotOf(Form.Document,Track,Kind)); Form.PatternList.ItemIndex := 0; end;
  function AlphaAt(Image: TBitmap; X: Integer): Byte;
  var Bytes: PByte;
  begin Bytes := Image.ScanLine[0]; Result := Bytes[X*4+3]; end;
begin
  ForceDirectories(Root); PSD := Fixture('different-name-A',3); HashA := THashSHA2.GetHashStringFromFile(PSD);
  Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'PSDAssets'));
  Lib := TMusicStudioPerformanceLibrary.Create(Store.Root); OtherLib := TMusicStudioPerformanceLibrary.Create(Store.Root);
  Doc := TMusicStudioDocument.Create; OtherDoc := TMusicStudioDocument.Create; D := TMusicStudioLayerDocument.Create;
  Data := TMusicStudioInstrumentData.Create;
  try
    Check(not TDirectory.Exists(Lib.Root),'constructor/read must not create files');
    Check(Length(Lib.Patterns('drums'))=0,'empty library'); Check(not TDirectory.Exists(Lib.Root),'empty read creates no files');
    Answer := TAttributeAnswer.Create; Answer.Timer := TTimer.Create(nil);
    try
      Answer.Timer.Interval := 25; Answer.Timer.OnTimer := Answer.Tick; Text := ''; Answer.Timer.Enabled := True;
      Check(ChooseMusicStudioAttribute(nil,Text) and (Text='bass'),'fixed list manual selection');
      Answer.Cancel := True; Answer.Timer.Enabled := True; Check(not ChooseMusicStudioAttribute(nil,Text),'manual cancel');
      Check(Text='bass','manual cancel keeps selection');
    finally Answer.Timer.Free; Answer.Free; end;
    PSD := Fixture('no-marker',2,'任意の説明レイヤー'); Check(D.LoadFile(PSD),D.LastError);
    Check(MusicStudioPerformerProfile(D,'{}').Attribute='','generic limbs do not guess instrument');
    PSD := TPath.Combine(Root,'different-name-A.psd');
    Check(D.LoadFile(PSD),D.LastError); Profile := MusicStudioPerformerProfile(D,'{}');
    Check(Profile.Attribute='drums','fixed marker'); Check(Length(Profile.Slots)=4,'singing/performance/expression/pose capabilities');
    Check(Store.TryImport(PSD,'演奏者A','#90C4E0',A,Duplicate,Error),Error);
    PSD := Fixture('different-name-B',2); HashB := THashSHA2.GetHashStringFromFile(PSD);
    Check(Store.TryImport(PSD,'演奏者B','#90C4E0',B,Duplicate,Error),Error); Check(A.ID<>B.ID,'different PSD IDs');
    Check(Doc.TryLoad('',Error),Error); T1 := Doc.AddTrack('performer');
    Check((Doc.TrackAt(T1).Role='performer') and (Length(Doc.TrackAt(T1).Slots)=1),'PSD first / single track type');
    Doc.AssignPsd(T1,A.ID); Doc.SetPerformer(T1,Profile.Attribute,Profile.Slots);
    Text := Doc.TrackAt(T1).Slots[1].ID; Doc.SetPerformer(T1,Profile.Attribute,Profile.Slots);
    Check(Doc.TrackAt(T1).Slots[1].ID=Text,'same capabilities preserve empty slot IDs');
    T2 := Doc.AddTrack('instrument'); Doc.AssignPsd(T2,B.ID); Doc.SetPerformer(T2,'drums',Profile.Slots);
    S1 := SlotOf(Doc,T1,'performance'); S2 := SlotOf(Doc,T2,'performance');
    I := Doc.AddSinging;
    PSD := TPath.Combine(Root,'delayed-song.mid');
    TFile.WriteAllBytes(PSD,TBytes.Create($4D,$54,$68,$64,0,0,0,6,0,0,0,1,1,$E0,
      $4D,$54,$72,$6B,0,0,0,14,$83,$60,$90,$3C,100,$83,$60,$80,$3C,0,0,$FF,$2F,0));
    SongEditor := TMusicStudioPatternSettings.Create(nil);
    try
      P := Doc.PatternAt(I); P.FilePath := PSD; P.SourceTrack := 0; SongEditor.SilentVisualMode := True; SongEditor.LoadPattern(P);
      Deadline := GetTickCount64+5000;
      repeat SongEditor.SingingFrame.PollResults; Check(GetTickCount64<Deadline,'song decode timeout'); Sleep(1); until not SongEditor.SingingFrame.IsLoading;
      SongEditor.ReadPattern(P); Check(Abs(P.SourceStartSeconds-0.5)<1E-8,'song excludes leading rest');
      Check(Abs(P.Duration-0.5)<1E-8,'song active length'); Doc.UpdatePattern(P);
    finally SongEditor.Free; end;
    Items := MusicStudioLibraryItems(Doc,Store,'singing',A.ID);
    Check((Length(Items)=1) and (Items[0].PatternIndex=I),'song project list');
    Items := MusicStudioLibraryItems(Doc,Store,'singing',B.ID); Check(Length(Items)=1,'same song list across performers');
    Check(OtherDoc.TryLoad('',Error),Error); Items := MusicStudioLibraryItems(OtherDoc,Store,'singing',A.ID); Check(Length(Items)=0,'singing not global');
    Data.Load('{"lengthBeats":8,"notes":[],"unknown":"keep"}');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'ソロ'; Block.Stage := 3; Block.StartBeat := 1; Block.EndBeat := 4;
    Check(Data.PutBlock(-1,Block),'common block');
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '共通ソロ'; P.Color := '#EDBA70';
    P.PerformanceAttribute := 'drums'; P.ConfigJSON := Data.JSON;
    Check(Lib.TrySave(P,Error),Error); Stale := P; Check(Length(OtherLib.Patterns('drums'))=1,'another project reads same library');
    Check(Length(OtherLib.Patterns('guitar'))=0,'attribute filtering');
    PI := Doc.ImportPerformance(P); Check(Doc.ImportPerformance(P)=PI,'same revision deduplicated');
    Check(Doc.AddBeatPlacement(T1,S1,Doc.PatternAt(PI).ID,0,8,Error),Error);
    Check(Doc.AddBeatPlacement(T2,S2,Doc.PatternAt(PI).ID,0,8,Error),Error);
    CopyJSON := Doc.CopyTrack(T1); I := Doc.PatternCount; T3 := Doc.PasteTrack(CopyJSON);
    try OtherDoc.PasteTrack(CopyJSON); except on E: Exception do ; end;
    Check(OtherDoc.TrackCount=0,'foreign-project missing references reject paste atomically');
    Check(Doc.PatternCount=I,'copy keeps shared patterns'); Check(Doc.TrackAt(T3).ID<>Doc.TrackAt(T1).ID,'fresh track ID');
    Check(Doc.TrackAt(T3).PsdAssetID=A.ID,'copy same PSD reference');
    for J := 0 to High(Doc.TrackAt(T1).Slots) do begin
      Check(Doc.TrackAt(T3).Slots[J].ID<>Doc.TrackAt(T1).Slots[J].ID,'fresh slot ID');
      if Length(Doc.TrackAt(T1).Slots[J].Clips)>0 then begin
        Check(Doc.TrackAt(T3).Slots[J].Clips[0].ID<>Doc.TrackAt(T1).Slots[J].Clips[0].ID,'fresh clip ID');
        Check(Doc.TrackAt(T3).Slots[J].Clips[0].SlotID=Doc.TrackAt(T3).Slots[J].ID,'copy clip parent');
      end;
    end;
    Doc.SetPerformer(T2,'guitar',nil,False); Check(not Doc.AddBeatPlacement(T2,S2,Doc.PatternAt(PI).ID,10,8,Error),'foreign attribute rejected');
    Doc.SetPerformer(T2,'drums',nil,False); Before := Doc.PatternAt(PI).ConfigJSON;
    Changed := P; Changed.Name := '更新版'; Check(OtherLib.TrySave(Changed,Error),Error);
    Check(not Lib.TrySave(Stale,Error),'stale revision refused'); Check(Doc.PatternAt(PI).ConfigJSON=Before,'existing snapshot unchanged');
    Check(Doc.PatternAt(PI).LibraryRevision<>Changed.LibraryRevision,'existing revision pinned');
    Check(Doc.TrySave(Text,Error),Error); Check(OtherDoc.TryLoad(Text,Error),Error);
    Check(OtherDoc.TrackAt(T1).Role='performer','performer roundtrip'); TFile.WriteAllText(TPath.Combine(Root,'performer-project.json'),Text,TEncoding.UTF8);
    Cache := TMusicStudioVisualCache.Create; Scene := TMusicStudioPsdSceneCache.Create;
    try
      // 別PSDの差分不足も同一snapshotで描画でき、正本の後日変更は参照しない。
      Scene.Bind(OtherDoc,Store,Cache); Scene.SetPosition(1,2); Deadline := GetTickCount64+5000;
      repeat Scene.PollResults; Check(GetTickCount64<Deadline,'cross PSD scene timeout'); Sleep(1);
      until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(T1)<>nil) and (Scene.ImageForTrack(T2)<>nil);
      Check(AlphaAt(Scene.ImageForTrack(T1),0)>0,'source PSD existing stage renders');
      Check(AlphaAt(Scene.ImageForTrack(T2),0)=0,'other PSD missing stage omitted');
    finally Scene.Free; Cache.Free; end;
    Before := Text; Check(not OtherDoc.TryLoad(Text.Replace('"performanceAttribute":"drums"','"performanceAttribute":"free-text"'),Error),'free attribute refused');
    Check(OtherDoc.TrySave(Text,Error) and (Text=Before),'invalid load atomic');
    Check(not Lib.TryRead('../escape',P.SharedPatternID,Stale,Error),'path key rejected');
    TFile.WriteAllText(TPath.Combine(TPath.Combine(Lib.Root,'drums'),'00000000-0000-0000-0000-000000000001.json'),'{broken',TEncoding.UTF8);
    Check((Length(Lib.Patterns('drums'))=1) and (Lib.Warning<>''),'corrupt library item isolated');
    UI := TFormMusicStudioSettings.Create(nil); OtherUI := TFormMusicStudioSettings.Create(nil);
    try
      UI.SilentVisualMode := True; UI.LibraryRoot := Store.Root; UI.LoadDocument('');
      T1 := UI.Document.AddTrack('performer'); UI.Document.TrySave(Text,Error); UI.LoadDocument(Text);
      SelectKind(UI,T1,'psd'); Check(Length(UI.PatternList.Items.ToStringArray)>0,'PSD list');
      I := 0; while (I<UI.PatternList.Count) and (UI.PatternList.Items[I]<>A.Name) do Inc(I); UI.PatternList.ItemIndex := I;
      Check(UI.DropSelectedLibraryAt(T1,0,0,Error),Error);
      Check(UI.Document.TrackAt(T1).PerformanceAttribute='drums','UI auto attribute');
      SelectKind(UI,T1,'performance'); Check(UI.PatternList.Count=1,'common UI list');
      Check(UI.DropSelectedLibraryAt(T1,SlotOf(UI.Document,T1,'performance'),0,Error),Error);
      I := UI.Document.PatternCount;
      for J := 0 to UI.ArrangementMenu.Items.Count-1 do if UI.ArrangementMenu.Items[J].Caption='トラックをコピー' then UI.ArrangementMenu.Items[J].Click;
      for J := 0 to UI.ArrangementMenu.Items.Count-1 do if UI.ArrangementMenu.Items[J].Caption='トラックをペースト' then UI.ArrangementMenu.Items[J].Click;
      Check((UI.Document.TrackCount=2) and (UI.Document.PatternCount=I),'UI track copy paste shares patterns');
      OtherUI.SilentVisualMode := True; OtherUI.LibraryRoot := Store.Root; OtherUI.LoadDocument('');
      T2 := OtherUI.Document.AddTrack('performer'); OtherUI.Document.AssignPsd(T2,B.ID); OtherUI.Document.SetPerformer(T2,'drums',Profile.Slots);
      OtherUI.Document.TrySave(Text,Error); OtherUI.LoadDocument(Text); SelectKind(OtherUI,T2,'performance');
      Check(OtherUI.PatternList.Count=1,'other project same UI list');
      Check(OtherUI.DropSelectedLibraryAt(T2,SlotOf(OtherUI.Document,T2,'performance'),0,Error),Error);
      UI.Show; Application.ProcessMessages; Bitmap := TBitmap.Create; PNG := TPngImage.Create;
      try Bitmap.SetSize(UI.ClientWidth,UI.ClientHeight); UI.PaintTo(Bitmap.Canvas,0,0); PNG.Assign(Bitmap); PNG.SaveToFile(TPath.Combine(Root,'performer-ui.png'));
      finally PNG.Free; Bitmap.Free; end;
    finally OtherUI.Free; UI.Free; end;
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(Root,'different-name-A.psd'))=HashA,'source A unchanged');
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(Root,'different-name-B.psd'))=HashB,'source B unchanged');
    Writeln('PERFORMER_PSD_SLOTS_PROJECT_SINGING_ATTRIBUTE_LIBRARY_CROSS_PSD_COPY_REVISION_UI_NO_AUDIO_OK');
  finally Data.Free; D.Free; OtherDoc.Free; Doc.Free; OtherLib.Free; Lib.Free; Store.Free; end;
end;
end.
