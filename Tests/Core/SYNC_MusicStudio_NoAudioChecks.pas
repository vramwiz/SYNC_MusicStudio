unit SYNC_MusicStudio_NoAudioChecks;

// 音声ジョブ・デコード・waveOutを一切呼ばない専用のモデル/UI検証。
interface
procedure RunNoAudioChecks(const Root: string);
implementation
uses System.SysUtils, System.IOUtils, Winapi.Windows, Vcl.Forms, Vcl.Graphics,
  Vcl.Imaging.pngimage, SYNC_MusicStudio_SettingsForm, SYNC_MusicStudio_ProjectData,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_ArrangementData;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;
procedure Pump(Milliseconds: Cardinal);
var Started: UInt64;
begin
  Started := GetTickCount64;
  repeat Application.ProcessMessages; Sleep(5); until GetTickCount64-Started>=Milliseconds;
end;
procedure Capture(Form: TForm; const Path: string);
var B: TBitmap; P: TPngImage;
begin
  Form.Show; Form.Update; Application.ProcessMessages;
  B := Form.GetFormImage; P := TPngImage.Create;
  try P.Assign(B); P.SaveToFile(Path); finally P.Free; B.Free; end;
end;
procedure AwaitLayers(D: TMusicStudioPatternSettings);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64+10000;
  repeat
    D.LayersFrame.PollResults; Application.ProcessMessages;
    if not D.LayersFrame.IsLoading and not D.LayersFrame.IsRendering then Break;
    Check(GetTickCount64<Deadline,'PSD editor timeout: '+D.LayersFrame.StateText); Sleep(2);
  until False;
  Check(D.LayersFrame.CanApply,D.LayersFrame.StateText);
end;
procedure CheckSharedUI(const Root: string);
var F: TFormMusicStudioSettings; D: TMusicStudioPatternSettings;
  Asset,Other: TMusicStudioPsdAsset; G: TGUID; Dup: Boolean;
  Error,Text,LibraryRoot: string; TS,TI,Performance,I,Count: Integer;
  P: TMusicStudioPattern; C: TMusicStudioPlacement; FirstStep: Double;
begin
  CreateGUID(G); LibraryRoot := TPath.Combine(Root,'ui-library-'+GUIDToString(G));
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LibraryRoot := LibraryRoot;
    F.LoadDocument(MUSIC_STUDIO_DEFAULT_JSON);
    Check(F.SharedLibrary.TryImport(TPath.Combine(Root,'psd-layers-raw.psd'),'共有テストPSD','#CC8CE0',Asset,Dup,Error),Error);
    SetLength(Asset.Patterns,3);
    for I := 0 to 2 do begin
      CreateGUID(G); Asset.Patterns[I].ID := LowerCase(Copy(GUIDToString(G),2,36));
      Asset.Patterns[I].AssetID := Asset.ID; Asset.Patterns[I].Color := '#90C4E0';
      Asset.Patterns[I].Name := '共有 '+IntToStr(I+1); Asset.Patterns[I].ConfigJSON := '{}';
    end;
    Asset.Patterns[0].Kind := 'emotion'; Asset.Patterns[1].Kind := 'animation'; Asset.Patterns[2].Kind := 'instrument';
    Check(F.SharedLibrary.TrySave(Asset,Error),Error);
    // 第二素材の表情は第一素材のスロットから見えない。
    Check(F.SharedLibrary.TryImport(TPath.Combine(Root,'psd-layers-rle.psd'),'別素材PSD','#F0A870',Other,Dup,Error),Error);
    SetLength(Other.Patterns,1); Other.Patterns[0] := Asset.Patterns[0];
    Other.Patterns[0].AssetID := Other.ID; CreateGUID(G); Other.Patterns[0].ID := LowerCase(Copy(GUIDToString(G),2,36));
    Check(F.SharedLibrary.TrySave(Other,Error),Error);
    TS := F.Document.AddTrack('psd'); TI := F.Document.AddTrack('instrument');
    Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text);
    Check(F.LibraryKind='psd','PSD slot initial library'); Check(F.PatternList.Count=2,'all global PSD listed');
    Count := F.Document.PatternCount;
    F.TimelineBox.SelectSlot(TS,2); Check(not F.AddButton.Enabled,'no expression add before PSD assignment');
    Check(F.Document.PatternCount=Count,'browsing does not add work references');
    F.TimelineBox.SelectSlot(TS,0);
    for I := 0 to F.PatternList.Count-1 do if F.PatternList.Items[I]=Asset.Name then F.PatternList.ItemIndex := I;
    Check(F.DropSelectedLibraryAt(TS,0,0,Error),Error);
    Check(F.Document.TrackAt(TS).PsdAssetID=Asset.ID,'PSD slot stores stable asset ID');
    Check(F.Document.PatternCount=Count,'PSD assignment is not temporal pattern duplication');
    F.TimelineBox.SelectSlot(TS,2); Check(F.LibraryKind='emotion','expression context');
    Check(F.PatternList.Count=1,'PSD-scoped expression list'); Check(F.Document.PatternCount=Count,'expression browse remains read-only');
    F.PatternList.ItemIndex := 0; Check(F.DropSelectedLibraryAt(TS,2,1,Error),Error);
    Check(F.Document.PatternCount=Count+1,'shared work reference created on first placement');
    Check(F.DropSelectedLibraryAt(TS,2,3,Error),Error); Check(F.Document.PatternCount=Count+1,'reference ID deduplicated');
    F.TimelineBox.SelectSlot(TS,3); F.PatternList.ItemIndex := 0;
    Check(F.LibraryKind='animation','animation context'); Check(F.DropSelectedLibraryAt(TS,3,0,Error),Error);
    F.TimelineBox.SelectSlot(TI,0);
    for I := 0 to F.PatternList.Count-1 do if F.PatternList.Items[I]=Asset.Name then F.PatternList.ItemIndex := I;
    Check(F.DropSelectedLibraryAt(TI,0,0,Error),Error);
    F.TimelineBox.SelectSlot(TI,4); Check(F.LibraryKind='instrument','instrument context');
    F.PatternList.ItemIndex := 0; Check(F.DropSelectedLibraryAt(TI,4,0,Error),Error);
    F.TimelineBox.SelectSlot(TI,5); Check(F.LibraryKind='performance','performance context');
    F.AddMenu.Items[0].Click; Performance := F.SelectedLibraryPattern;
    P := F.Document.PatternAt(Performance); P.Name := '拍で保存する演奏';
    P.ConfigJSON := '{"lengthBeats":8,"notes":[{"startBeat":0,"lengthBeats":1,"pitch":60,"velocity":100},{"startBeat":2,"lengthBeats":2,"pitch":64,"velocity":80}]}';
    F.Document.UpdatePattern(P); Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text);
    F.TimelineBox.SelectSlot(TI,5); F.PatternList.ItemIndex := 0;
    Check(F.DropSelectedLibraryAt(TI,5,2,Error),Error); C := F.Document.TrackAt(TI).Slots[5].Clips[0];
    Check((C.TimeBase='beats') and (Abs(C.StartBeat-4)<0.000001) and (Abs(C.LengthBeats-8)<0.000001),'beat canonical placement');
    Check(F.Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":60},{"beat":8,"bpm":120}],"meter":{"numerator":4,"denominator":4}}',Error),Error);
    C := F.Document.TrackAt(TI).Slots[5].Clips[0];
    Check((Abs(C.StartBeat-4)<0.000001) and (Abs(C.StartSeconds-4)<0.000001) and (Abs(C.LengthSeconds-6)<0.000001),'tempo changes preserve beats across boundary');
    Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text); F.TimelineBox.SelectSlot(TI,5);
    Check(F.Document.TrackAt(TS).PsdAssetID=Asset.ID,'asset identity reload');
    FirstStep := F.TimelineBox.BeatSnapStep(0); F.TimelineBox.SetZoom(200);
    Check(F.TimelineBox.BeatSnapStep(0)<FirstStep,'arrangement zoom changes beat snap');
    Check(Abs(F.TimelineBox.SnapSecondsForSlot(1.24,TI,5)-1.25)<0.000001,'timeline beat snap boundary');
    Check(Abs(F.TimelineBox.SnapSecondsForSlot(1.24,TS,1)-1.25)<0.000001,'singing uses the displayed beat grid while stored seconds stay separate');
    Count := F.TimelineBox.PerformanceCache.ParseCount; for I := 1 to 100 do F.TimelineBox.Repaint;
    Check(F.TimelineBox.PerformanceCache.ParseCount=Count,'paint never parses performance JSON');
    F.TimelineBox.SetZoom(60);
    F.PatternList.OnClick(F.PatternList);
    Pump(600); Capture(F,TPath.Combine(Root,'integrated-instrument-beats.png'));
    F.TimelineBox.SelectSlot(TS,2); Capture(F,TPath.Combine(Root,'integrated-expression-library.png'));
    F.Preview.Seek(1.5); Pump(200);
    Check(not F.Preview.AudioEngineAllocated,'shared preview never allocates audio');
    Check(F.TimelineBox.WaveCache.DecodeCount=0,'shared preview never decodes audio');
    D := TMusicStudioPatternSettings.Create(nil);
    try
      P := Default(TMusicStudioPattern); P.Kind := 'psd'; P.Name := Asset.Name; P.Color := Asset.Color;
      P.AssetID := Asset.ID; P.FilePath := Asset.FilePath; P.ConfigJSON := Asset.ConfigJSON;
      D.SilentVisualMode := True; D.LoadSharedPattern(P,Asset.FilePath,Asset.ConfigJSON); D.Show; AwaitLayers(D);
      Check(D.LayersFrame.CanApply,D.LayersFrame.StateText);
      Capture(D,TPath.Combine(Root,'integrated-psd-settings.png'));
      // 閉じても共有データは変わらず、再オープンできる。
      D.Hide; D.LoadSharedPattern(P,Asset.FilePath,Asset.ConfigJSON); AwaitLayers(D); Check(D.LayersFrame.CanApply,'PSD settings reopen');
    finally D.Free; end;
    TFile.WriteAllText(TPath.Combine(Root,'ui-silent-project.json'),Text,TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Root,'ui-shared-root.txt'),LibraryRoot,TEncoding.UTF8);
    Writeln('SHARED_SLOT_LIBRARY_BEAT_UI_OK (isolated Documents substitute, no audio)');
  finally F.Free; end;
end;
procedure RunNoAudioChecks(const Root: string);
var F: TFormMusicStudioSettings; D: TMusicStudioPatternSettings;
  A,S,A2,TA,TS: Integer; P: TMusicStudioPattern; Text,Error: string;
begin
  ForceDirectories(Root);
  F := TFormMusicStudioSettings.Create(nil);
  try
    F.SilentVisualMode := True; F.LibraryRoot := TPath.Combine(Root,'basic-silent-library'); F.LoadDocument(MUSIC_STUDIO_DEFAULT_JSON);
    Check(F.LibraryKind='','blank has no selected slot');
    A := F.Document.AddAudio; S := F.Document.AddSinging; A2 := F.Document.AddAudio;
    P := F.Document.PatternAt(A); P.Name := '音声 一'; P.FilePath := 'Z:\DO_NOT_READ\audio.wav'; F.Document.UpdatePattern(P);
    P := F.Document.PatternAt(A2); P.Name := '音声 二'; F.Document.UpdatePattern(P);
    TA := F.Document.AddTrack('audio'); TS := F.Document.AddTrack('psd');
    Check(F.Document.AddPlacement(TA,0,F.Document.PatternAt(A).ID,0,4,Error),Error);
    Check(F.Document.TrySave(Text,Error),Error); F.LoadDocument(Text);
    Check(F.LibraryKind='audio','audio slot selected on bind');
    Check(F.LibraryLabel.Caption='音声','audio heading');
    Check(F.PatternList.Count=2,'audio-only list');
    F.PatternList.ItemIndex := 1;
    Check(F.SelectedLibraryPattern=A2,'filtered index maps to actual second audio');
    F.AddButton.OnClick(F.AddButton);
    Check(F.Document.PatternCount=4,'direct audio add without type menu');
    Check(F.PatternList.Count=3,'new audio listed');
    Check(F.Document.PatternAt(F.SelectedLibraryPattern).Kind='audio','new item selected');
    F.TimelineBox.SelectSlot(TS,1);
    Check(F.LibraryKind='singing','singing context'); Check(F.PatternList.Count=1,'singing-only list');
    F.PatternList.ItemIndex := 0; Check(F.SelectedLibraryPattern=S,'singing mapping');
    F.AddButton.OnClick(F.AddButton); Check(F.PatternList.Count=2,'direct singing add');
    F.TimelineBox.ToggleTrack(TS); Check(F.LibraryKind='singing','collapse keeps slot');
    F.TimelineBox.SelectSlot(TA,0);
    F.Preview.StartSilentVisualPreview; Pump(120);
    Check(F.Preview.Position>0.04,'silent visual clock advances');
    Check(not F.Preview.AudioEngineAllocated,'no audio engine allocation');
    F.Preview.Seek(2); Pump(70); Check(F.Preview.Position>=2,'silent seek resumes clock');
    F.Preview.Pause; Check(not F.Preview.IsPlaying,'silent pause'); F.Preview.Stop;
    Check(F.TimelineBox.WaveCache.DecodeCount=0,'no waveform job');
    Check(F.TimelineBox.WaveCache.ActiveJobs=0,'no audio workers');
    D := TMusicStudioPatternSettings.Create(nil);
    try
      D.SilentVisualMode := True; D.LoadPattern(F.Document.PatternAt(A)); Pump(60);
      Check(not D.AudioFrame.IsLoading,'audio popup no decode');
      Check(D.AudioFrame.WavePointCount=0,'audio popup no waveform data read');
      Check(D.AudioFrame.FilePath='Z:\DO_NOT_READ\audio.wav','audio reference preserved');
    finally D.Free; end;
    Capture(F,TPath.Combine(Root,'slot-library-expanded.png'));
    F.TimelineBox.ToggleTrack(TA); Capture(F,TPath.Combine(Root,'slot-library-collapsed.png'));
    F.ClientWidth := 980; F.ClientHeight := 650; Capture(F,TPath.Combine(Root,'slot-library-minimum.png'));
    F.LoadDocument(Text); Check(not F.Preview.AudioEngineAllocated,'reopen silent');
    Check(F.TimelineBox.WaveCache.DecodeCount=0,'reopen no decode');
    Writeln('SLOT_LIBRARY_SILENT_UI_OK (no audio fixtures, decode, Play, waveOut)');
  finally F.Free; end;
  CheckSharedUI(Root);
end;
end.
