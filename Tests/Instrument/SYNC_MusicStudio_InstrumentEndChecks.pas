unit SYNC_MusicStudio_InstrumentEndChecks;
interface
procedure RunSnareTrace(const Root,PSD,ProjectJSON: string);
procedure RunInstrumentEndChecks(const Root,PSD: string);
procedure RunSnareVideoTrace(const Root,PSD,ProjectJSON: string);
procedure ExportSnareFrames(const Root,PSD,ProjectJSON: string);
implementation
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math, System.Types,
  System.Generics.Collections, Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Graphics,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentPlayback,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_InstrumentFrame, SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_SharedPsdLibrary,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_VideoRenderer, System.Hash, Vcl.Imaging.pngimage;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('INSTRUMENT_END: '+Text); end;
function Key(const States: TArray<TInstrumentState>): string;
var S: TInstrumentState;
begin
  Result := '';
  for S in States do Result := Result+S.Row+'|'+S.Choice+'|'+S.LayerScope+'|'+IntToStr(S.Stage)+';';
end;
function Same(A,B: Vcl.Graphics.TBitmap): Boolean;
var Y: Integer;
begin
  Result := (A<>nil) and (B<>nil) and (A.Width=B.Width) and (A.Height=B.Height);
  if Result then for Y := 0 to A.Height-1 do if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
end;
procedure RunSnareTrace(const Root,PSD,ProjectJSON: string);
var Doc: TMusicStudioDocument; D: TMusicStudioLayerDocument; Model: TMusicStudioInstrumentData;
  P: TMusicStudioPattern; Dialog: TMusicStudioPatternSettings; Frames: TObjectDictionary<string,Vcl.Graphics.TBitmap>;
  States: TArray<TInstrumentState>; S: TInstrumentState; V: TJSONObject; B: Vcl.Graphics.TBitmap;
  I,J,Cycle,Previous,ExpectedCount,Misses: Integer; Beat,LastBeat: Double; Deadline,Started: UInt64;
  Seen: array[0..1,0..2] of Boolean; Lines: TStringList; Error,K,Before: string;
  Shot: Vcl.Graphics.TBitmap; ShotPNG: TPngImage;
  procedure WaitPreview;
  begin
    Deadline := GetTickCount64+15000;
    repeat Application.ProcessMessages; Sleep(1); Check(GetTickCount64<Deadline,'trace preview timeout');
    until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
  end;
  function Expected(const Values: TArray<TInstrumentState>): Vcl.Graphics.TBitmap;
  begin
    K := Key(Values);
    if not Frames.TryGetValue(K,Result) then begin
      V := D.InstrumentRules.Visibility(Values); B := Vcl.Graphics.TBitmap.Create;
      try Check(D.Render(B,V,512),D.LastError); Frames.Add(K,B); Result := B; B := nil;
      finally B.Free; V.Free; end;
    end;
  end;
begin
  ForceDirectories(Root); Doc := TMusicStudioDocument.Create; D := TMusicStudioLayerDocument.Create;
  Model := TMusicStudioInstrumentData.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
  Frames := TObjectDictionary<string,Vcl.Graphics.TBitmap>.Create([doOwnsValues]); Lines := TStringList.Create;
  try
    Check(Doc.TryLoad(TFile.ReadAllText(ProjectJSON),Error),Error); Check(D.LoadFile(PSD),D.LastError);
    P := Default(TMusicStudioPattern);
    for I := 0 to Doc.PatternCount-1 do if Doc.PatternAt(I).Kind='performance' then begin P := Doc.PatternAt(I); Break; end;
    Check(P.ID<>'','performance snapshot missing'); Model.Load(P.ConfigJSON);
    Check(Model.PlaybackEndBeat=4,'actual occupied loop end'); P.ConfigJSON := Model.JSON; Before := Model.JSON;
    for I := 0 to 399 do Expected(MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,I/100));
    ExpectedCount := Frames.Count; Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(P,Model.AssetID,PSD,'{}',120);
    Dialog.Show; WaitPreview; Dialog.InstrumentFrame.Seek(0); WaitPreview;
    Shot := Vcl.Graphics.TBitmap.Create; ShotPNG := TPngImage.Create;
    try Shot.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(Shot.Canvas,0,0);
      ShotPNG.Assign(Shot); ShotPNG.SaveToFile(TPath.Combine(Root,'pattern-loop.png'));
    finally ShotPNG.Free; Shot.Free; end;
    Lines.Add(Format('source blocks=%d live blocks=%d length=%g',[Model.Blocks.Count,Dialog.InstrumentFrame.Data.Blocks.Count,Dialog.InstrumentFrame.Data.LengthBeats]));
    Dialog.InstrumentFrame.Seek(1.2); WaitPreview; Lines.Add('seek1.2 '+Key(Dialog.InstrumentFrame.PreviewStates));
    Dialog.InstrumentFrame.Seek(0); WaitPreview;
    FillChar(Seen,SizeOf(Seen),0); Cycle := 0; LastBeat := 0; Misses := 0;
    Previous := Dialog.InstrumentPreview.RenderCount; Started := GetTickCount64; Dialog.InstrumentFrame.PlayButton.Click;
    repeat
      Application.ProcessMessages; Dialog.InstrumentPreview.Poll; Beat := Dialog.InstrumentFrame.Position;
      if Beat<LastBeat-0.5 then Inc(Cycle); LastBeat := Beat;
      if Dialog.InstrumentPreview.RenderCount<>Previous then begin
        Previous := Dialog.InstrumentPreview.RenderCount; States := Dialog.InstrumentFrame.PreviewStates;
        Lines.Add(Format('publish %d ms beat %.4f %s',[GetTickCount64-Started,Beat,Key(States)]));
        for S in States do if (S.Row='右手') and (S.LayerScope='body') and S.Choice.Contains('スネア') and (S.Stage=1) then begin
          J := -1;
          if S.Choice='スネア中央（エフェクト付き）' then J := 0 else if S.Choice='スネア右側' then J := 1 else if S.Choice='スネア中央' then J := 2;
          if (J>=0) and (Cycle<=1) then begin
            if Same(Expected(States),Dialog.InstrumentPreview.PreviewBitmap) then Seen[Cycle,J] := True else Inc(Misses);
            Lines.Add(Format('%d ms cycle %d beat %.4f %s strike shown=%s',[GetTickCount64-Started,Cycle,Beat,S.Choice,BoolToStr(Seen[Cycle,J],True)]));
          end;
        end;
      end;
      Sleep(1); Check(GetTickCount64-Started<12000,'trace clock stalled');
    until Cycle>=2;
    Dialog.InstrumentFrame.PlayButton.Click; Dialog.Hide;
    Lines.Add(Format('reference states=%d live-created=%d stale=%d cacheHits=%d',[ExpectedCount,Frames.Count-ExpectedCount,Misses,Dialog.InstrumentPreview.CacheHits]));
    for I := 0 to 1 do for J := 0 to 2 do Lines.Add(Format('cycle %d snare %d shown=%s',[I,J,BoolToStr(Seen[I,J],True)]));
    Lines.SaveToFile(TPath.Combine(Root,'snare-trace.log'),TEncoding.UTF8); Writeln(Lines.Text);
    Check(Model.JSON=Before,'trace mutated performance');
    for I := 0 to 1 do for J := 0 to 2 do Check(Seen[I,J],'snare strike absent cycle '+IntToStr(I)+' snare '+IntToStr(J));
    Writeln('ACTUAL_TWELVE_BLOCK_PATTERN_ALL_SIX_SNARE_STRIKES_SHOWN_NO_AUDIO_OK');
  finally Lines.Free; Frames.Free; Dialog.Free; Model.Free; D.Free; Doc.Free; end;
end;
procedure RunInstrumentEndChecks(const Root,PSD: string);
var Dialog: TMusicStudioPatternSettings; F: TMusicStudioInstrumentFrame;
  Model: TMusicStudioInstrumentData; Block: TInstrumentBlock; P: TMusicStudioPattern;
  Doc: TMusicStudioDocument; UI: TFormMusicStudioSettings; Asset: TMusicStudioPsdAsset;
  Duplicate: Boolean; Error,JSON,Before,PatternID: string; Deadline: UInt64;
  T,Slot,Index,X,Y,Edge: Integer; C: TMusicStudioPlacement; K: Word;
  procedure WaitEditor;
  begin
    Deadline := GetTickCount64+15000;
    repeat Application.ProcessMessages; Sleep(1); Check(GetTickCount64<Deadline,'end editor timeout');
    until (Dialog.InstrumentFrame<>nil) and (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
    F := Dialog.InstrumentFrame;
  end;
  procedure Reload;
  begin
    Check(UI.Document.TrySave(JSON,Error),Error); UI.LoadDocument(JSON); UI.TimelineBox.SelectClip(T,Slot,0); UI.TimelineBox.SetZoom(80);
  end;
  function XBeat(Beat: Double): Integer;
  begin Result := UI.TimelineBox.HeaderWidth+Round(UI.Document.BeatToSeconds(Beat)*80*UI.CurrentPPI/96); end;
  procedure DragRight(ToBeat: Double);
  begin
    C := UI.Document.TrackAt(T).Slots[Slot].Clips[0]; Reload; Y := UI.TimelineBox.SlotRowTop(T,Slot)+UI.TimelineBox.SlotHeight('performance') div 2;
    X := XBeat(C.StartBeat+C.LengthBeats); Edge := X-2;
    Check(UI.TimelineBox.EmotionResizeEdgeAt(Edge,Y)=1,'right edge not selected');
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Edge,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(XBeat(ToBeat),Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(XBeat(ToBeat),Y));
  end;
begin
  ForceDirectories(Root); Dialog := TMusicStudioPatternSettings.Create(nil); Model := TMusicStudioInstrumentData.Create;
  Doc := TMusicStudioDocument.Create; UI := TFormMusicStudioSettings.Create(nil);
  try
    Model.Load('{"lengthBeats":8,"notes":[],"future":"keep"}'); Block := Default(TInstrumentBlock);
    Block.Row := '右手'; Block.Choice := 'スネア中央'; Block.EndBeat := 1; Check(Model.PutBlock(-1,Block),'end fixture block');
    Check(Model.PlaybackEndBeat=1,'trailing blank included in loop');
    Block.Row := '左足'; Block.StartBeat := 3; Block.EndBeat := 4; Block.ID := '';
    Check(Model.PutBlock(-1,Block),'later independent limb'); Check(Model.PlaybackEndBeat=4,'internal rest truncated loop');
    Model.DeleteBlock(1); Check(Model.PlaybackEndBeat=1,'deleting last block did not update loop');
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '末尾保存'; P.Color := '#EDBA70'; P.ConfigJSON := Model.JSON;
    Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(P,'',PSD,'{}',120); Dialog.Show; WaitEditor;
    F.LengthEdit.Text := '2.5'; F.Seek(0.99); F.PlayButton.Click;
    Check(F.Data.LengthBeats=2.5,'play ignored uncommitted length'); F.PlaybackTimer.Enabled := False;
    Sleep(50); F.PlaybackTimer.OnTimer(F.PlaybackTimer);
    Check((F.Data.PlaybackEndBeat=1) and (F.Position>=0) and (F.Position<0.25),'occupied endpoint did not loop to start'); F.PlayButton.Click;
    Dialog.ReadPattern(P); Model.Load(P.ConfigJSON); Check(Model.LengthBeats=2.5,'saved endpoint lost');
    Dialog.LoadPerformanceSteps(P,'',PSD,'{}',120); WaitEditor;
    Check((F.Data.LengthBeats=2.5) and (F.LengthEdit.Text='2.5'),'reopen endpoint lost');
    F.LengthEdit.Text := '3.25'; K := VK_RETURN; F.LengthEdit.OnKeyDown(F.LengthEdit,K,[]);
    Check((K=0) and (F.Data.LengthBeats=3.25),'Enter did not commit endpoint');
    F.LengthEdit.Text := '9'; K := VK_ESCAPE; F.LengthEdit.OnKeyDown(F.LengthEdit,K,[]);
    Check(F.LengthEdit.Text='3.25','Escape did not restore endpoint');
    K := Ord('Z'); F.HandleKey(K,[ssCtrl]); Check(F.Data.LengthBeats=2.5,'endpoint undo');
    K := Ord('Y'); F.HandleKey(K,[ssCtrl]); Check(F.Data.LengthBeats=3.25,'endpoint redo');
    F.LengthEdit.Text := '0'; F.PlayButton.Click; Check(not F.IsPlaying,'invalid endpoint started clock');
    F.LengthEdit.Text := '3.25'; F.PlayButton.Click; F.LengthEdit.Text := '0'; F.PlayButton.Click;
    Check(not F.IsPlaying,'invalid endpoint prevented pause');
    F.LengthEdit.Text := '3.25'; Dialog.ReadPattern(P); Dialog.Hide;
    UI.SilentVisualMode := True; UI.LibraryRoot := TPath.Combine(Root,'Library');
    Check(UI.SharedLibrary.TryImport(PSD,'ドラム','#EDBA70',Asset,Duplicate,Error),Error);
    Model.Load(P.ConfigJSON); Model.BindAsset(Asset.ID); P.ConfigJSON := Model.JSON;
    Check(Doc.TryLoad('',Error),Error); T := Doc.AddTrack('psd'); Doc.AssignPsd(T,Asset.ID); Slot := Doc.AddSlot(T,'performance');
    Index := Doc.AddPerformance; PatternID := Doc.PatternAt(Index).ID; P.ID := PatternID; Doc.UpdatePattern(P);
    Check(Doc.TrySave(JSON,Error),Error); UI.LoadDocument(JSON); UI.Show;
    Check(UI.DropPatternAt(Index,T,Slot,UI.Document.BeatToSeconds(4),Error),Error);
    C := UI.Document.TrackAt(T).Slots[Slot].Clips[0]; Check(Abs(C.LengthBeats-3.25)<1E-9,'D&D ignored remembered endpoint');
    Check(UI.Document.TrySave(Before,Error),Error);
    Check(not UI.Document.MoveBeatPlacement(T,Slot,0,4,4,Error),'typed resize exceeded endpoint');
    Check(UI.Document.TrySave(JSON,Error),Error); Check(JSON=Before,'invalid resize mutated project');
    DragRight(5.5); C := UI.Document.TrackAt(T).Slots[Slot].Clips[0]; Check(Abs(C.LengthBeats-1.5)<0.01,'right trim failed');
    DragRight(10); C := UI.Document.TrackAt(T).Slots[Slot].Clips[0]; Check(Abs(C.LengthBeats-3.25)<1E-9,'right drag exceeded endpoint');
    UI.UndoEdit; Check(Abs(UI.Document.TrackAt(T).Slots[Slot].Clips[0].LengthBeats-1.5)<0.01,'resize undo');
    UI.RedoEdit; Check(Abs(UI.Document.TrackAt(T).Slots[Slot].Clips[0].LengthBeats-3.25)<1E-9,'resize redo');
    DragRight(5.5); C := UI.Document.TrackAt(T).Slots[Slot].Clips[0]; Reload;
    Y := UI.TimelineBox.SlotRowTop(T,Slot)+UI.TimelineBox.SlotHeight('performance') div 2; Edge := XBeat(C.StartBeat)+2;
    Check(UI.TimelineBox.EmotionResizeEdgeAt(Edge,Y)=-1,'left edge not selected');
    UI.TimelineBox.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Edge,Y));
    UI.TimelineBox.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(XBeat(0),Y));
    UI.TimelineBox.Perform(WM_LBUTTONUP,0,MakeLParam(XBeat(0),Y));
    C := UI.Document.TrackAt(T).Slots[Slot].Clips[0];
    Check((Abs(C.LengthBeats-3.25)<1E-9) and (Abs(C.StartBeat-2.25)<0.01),'left drag exceeded endpoint');
    Check(UI.Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":4,"bpm":60}]}',Error),Error);
    Check(UI.Document.AddPlacement(T,Slot,PatternID,UI.Document.BeatToSeconds(8),1,Error),Error);
    C := UI.Document.TrackAt(T).Slots[Slot].Clips[1];
    Check((Abs(C.LengthBeats-3.25)<1E-9) and (Abs(C.LengthSeconds-3.25)<1E-9),'tempo changed beat endpoint');
    UI.Hide;
    Writeln('MANUAL_END_COMMIT_REOPEN_LOOP_ENTER_ESCAPE_UNDO_DND_RIGHT_LIMIT_ATOMICITY_OK');
  finally UI.Free; Doc.Free; Model.Free; Dialog.Free; end;
end;
procedure RunSnareVideoTrace(const Root,PSD,ProjectJSON: string);
var Source,Doc: TMusicStudioDocument; Model: TMusicStudioInstrumentData; P: TMusicStudioPattern;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Error,AssetID,Dir,JSON: string;
  I,J,T,Slot,Index,Cycle,Count,Duration: Integer; Seconds: Double; Started,FrameStart,Total,MaxMS: UInt64;
  Seen: array[0..1,0..2] of Boolean; Lines: TStringList;
begin
  ForceDirectories(Root); Source := TMusicStudioDocument.Create; Doc := TMusicStudioDocument.Create;
  Model := TMusicStudioInstrumentData.Create; Lines := TStringList.Create;
  try
    Check(Source.TryLoad(TFile.ReadAllText(ProjectJSON),Error),Error); P := Default(TMusicStudioPattern); AssetID := '';
    for I := 0 to Source.PatternCount-1 do if Source.PatternAt(I).Kind='performance' then begin P := Source.PatternAt(I); Break; end;
    for I := 0 to Source.TrackCount-1 do if Source.TrackAt(I).Kind='psd' then begin AssetID := Source.TrackAt(I).PsdAssetID; Break; end;
    Check((P.ID<>'') and (AssetID<>''),'video trace input'); Model.Load(P.ConfigJSON);
    Dir := TPath.Combine(TPath.GetDocumentsPath,'SYNC_MusicStudio\Libraries\PSDAssets\'+AssetID);
    Check(THashSHA2.GetHashStringFromFile(TPath.Combine(Dir,'source.psd'))=THashSHA2.GetHashStringFromFile(PSD),'video trace source mismatch');
    ForceDirectories(TPath.Combine(Root,'PSDAssets\'+AssetID));
    TFile.Copy(TPath.Combine(Dir,'source.psd'),TPath.Combine(Root,'PSDAssets\'+AssetID+'\source.psd'),True);
    TFile.Copy(TPath.Combine(Dir,'asset.json'),TPath.Combine(Root,'PSDAssets\'+AssetID+'\asset.json'),True);
    Check(Doc.TryLoad('',Error),Error); T := Doc.AddTrack('psd'); Doc.AssignPsd(T,AssetID);
    Doc.SetPerformer(T,P.PerformanceAttribute,nil,False); Slot := Doc.AddSlot(T,'performance');
    Index := Doc.AddPerformance; P.ID := Doc.PatternAt(Index).ID; Doc.UpdatePattern(P);
    Check(Doc.AddBeatPlacement(T,Slot,P.ID,0,4,Error),Error); Check(Doc.AddBeatPlacement(T,Slot,P.ID,4,4,Error),Error);
    Check(Doc.TrySave(JSON,Error),Error);
    Video := TMusicStudioVideoSession.Create(TPath.Combine(Root,'PSDAssets'));
    try
      Check(Video.Render(JSON,0,640,360,Pixels,Error),Error); FillChar(Seen,SizeOf(Seen),0);
      Count := 0; Total := 0; MaxMS := 0; Started := GetTickCount64;
      repeat
        FrameStart := GetTickCount64; Seconds := (FrameStart-Started)/1000;
        Check(Video.Render(JSON,Seconds,640,360,Pixels,Error),Error); Duration := GetTickCount64-FrameStart;
        Inc(Count); Inc(Total,Duration); MaxMS := Max(MaxMS,UInt64(Duration)); Cycle := Trunc(Seconds/2);
        if Cycle<2 then for I := 0 to Model.Blocks.Count-1 do begin
          if (Model.Blocks[I].Row<>'右手') or not Model.Blocks[I].Choice.Contains('スネア') then Continue;
          if (Seconds*2>=Cycle*4+Model.Blocks[I].StartBeat+(Model.Blocks[I].EndBeat-Model.Blocks[I].StartBeat)*0.25) and
            (Seconds*2<Cycle*4+Model.Blocks[I].StartBeat+(Model.Blocks[I].EndBeat-Model.Blocks[I].StartBeat)*0.75) then begin
            J := -1; if Model.Blocks[I].Choice='スネア中央（エフェクト付き）' then J := 0 else if Model.Blocks[I].Choice='スネア右側' then J := 1 else if Model.Blocks[I].Choice='スネア中央' then J := 2;
            if J>=0 then begin Seen[Cycle,J] := True; Lines.Add(Format('request %.4fs cycle%d snare%d render=%dms',[Seconds,Cycle,J,Duration])); end;
          end;
        end;
        if Duration<16 then Sleep(16-Duration);
      until Seconds>=4;
      Lines.Add(Format('frames=%d average=%.1fms max=%dms strike-window=125ms',[Count,Total/Max(1,Count),MaxMS]));
      for I := 0 to 1 do for J := 0 to 2 do Lines.Add(Format('cycle %d snare %d requested=%s',[I,J,BoolToStr(Seen[I,J],True)]));
      Lines.SaveToFile(TPath.Combine(Root,'video-clock.log'),TEncoding.UTF8); Writeln(Lines.Text);
    finally Video.Free; end;
  finally Lines.Free; Model.Free; Doc.Free; Source.Free; end;
end;
procedure ExportSnareFrames(const Root,PSD,ProjectJSON: string);
var Doc: TMusicStudioDocument; D: TMusicStudioLayerDocument; Model: TMusicStudioInstrumentData;
  P: TMusicStudioPattern; States: TArray<TInstrumentState>; S: TInstrumentState;
  B: Vcl.Graphics.TBitmap; PNG: TPngImage; V: TJSONObject; Lines: TStringList;
  I,J,Cycle: Integer; Beat: Double; Seen: array[0..1,0..2] of Integer; Error: string;
begin
  ForceDirectories(Root); Doc := TMusicStudioDocument.Create; D := TMusicStudioLayerDocument.Create;
  Model := TMusicStudioInstrumentData.Create; B := Vcl.Graphics.TBitmap.Create; PNG := TPngImage.Create; Lines := TStringList.Create;
  try
    Check(Doc.TryLoad(TFile.ReadAllText(ProjectJSON),Error),Error); Check(D.LoadFile(PSD),D.LastError);
    P := Default(TMusicStudioPattern); for I := 0 to Doc.PatternCount-1 do if Doc.PatternAt(I).Kind='performance' then begin P := Doc.PatternAt(I); Break; end;
    Model.Load(P.ConfigJSON); Check(Model.PlaybackEndBeat=4,'offline occupied loop end'); FillChar(Seen,SizeOf(Seen),0);
    for I := 0 to 119 do begin
      Cycle := I div 60; Beat := (I mod 60)/15;
      States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,Beat);
      V := D.InstrumentRules.Visibility(States); try Check(D.Render(B,V,512),D.LastError); finally V.Free; end;
      PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,Format('frame-%.3d.png',[I])));
      for S in States do if (S.Row='右手') and (S.LayerScope='body') and (S.Stage=1) then begin
        J := -1;
        if S.Choice='スネア中央（エフェクト付き）' then J := 0 else if S.Choice='スネア右側' then J := 1 else if S.Choice='スネア中央' then J := 2;
        if J>=0 then begin Inc(Seen[Cycle,J]); Lines.Add(Format('frame=%d source=%.4fs cycle=%d %s strike',[I,I/30,Cycle,S.Choice])); end;
      end;
    end;
    for I := 0 to 1 do for J := 0 to 2 do Check(Seen[I,J]=4,'fixed-frame export did not double snare to four frames');
    Lines.SaveToFile(TPath.Combine(Root,'strike-frames.txt'),TEncoding.UTF8); Writeln('OFFLINE_30FPS_120_FRAMES_ALL_SIX_SNARE_STRIKES_INCLUDED');
  finally Lines.Free; PNG.Free; B.Free; Model.Free; D.Free; Doc.Free; end;
end;
end.
