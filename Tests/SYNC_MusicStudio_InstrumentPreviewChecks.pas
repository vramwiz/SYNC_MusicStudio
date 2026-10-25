unit SYNC_MusicStudio_InstrumentPreviewChecks;

// 演奏編集の実イベント、局所再生、未確定dragとPSD画素を隔離検証する。音声/DPI変更なし。
interface
procedure RunInstrumentPreviewChecks(const Root: string; const RealPSD: string = '');
procedure RunInstrumentGestureChecks(const Root: string; const RealPSD: string = '');
// 診断PNGをRootへ出力する。PathのPSDは読取のみ。
procedure InspectBassRest(const Root,Path: string);
procedure InspectHiHat(const Root,Path: string);
procedure BuildHiHatCandidate(const Root,Path: string);
// 中間足PNG/変更前控えをRootへ作成し、既存候補PSDがあれば保存内容を照合する。PSD編集/保存は本体APIの責務。
procedure BuildBassRestCandidate(const Root,Path: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.Types, System.Math, System.JSON, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, Vcl.Graphics, Vcl.Imaging.pngimage,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_InstrumentFrame,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PsdSceneCache,
  SYNC_MusicStudio_PerformanceLibrary, SYNC_MusicStudio_ArtLayerName;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('INSTRUMENT_PREVIEW: '+Text); end;
procedure InspectHiHat(const Root,Path: string);
var D: TMusicStudioLayerDocument; A,B,C,Idle: TBitmap; PNG: TPngImage; V: TJSONObject; S: TInstrumentState;
  I,X,Y,Diff: Integer; P,Q: PByte; Values: TArray<Integer>;
  Dialog: TMusicStudioPatternSettings; Data: TMusicStudioInstrumentData; Pattern: TMusicStudioPattern;
  Block: TInstrumentBlock; Deadline: UInt64;
  Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset; Doc: TMusicStudioDocument;
  Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache; Duplicate: Boolean; Error: string;
  Track,Slot,Index,SX,SY: Integer; Expected: TBitmap;
  procedure Ready;
  begin
    Deadline := GetTickCount64+10000;
    repeat
      Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'hi-hat editor timeout');
      if Dialog.InstrumentPreview<>nil then Dialog.InstrumentPreview.Poll;
    until (Dialog.InstrumentFrame<>nil) and (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
    Check(Dialog.InstrumentPreview.PreviewBitmap<>nil,'hi-hat editor bitmap absent');
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; A := TBitmap.Create; B := TBitmap.Create;
  C := TBitmap.Create; Idle := TBitmap.Create; PNG := TPngImage.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Values := D.InstrumentRules.Stages('左足','ハイハット');
    TFile.WriteAllText(TPath.Combine(Root,'rules.json'),D.InstrumentRules.DiagnosticJSON);
    Check((Length(Values)>=2) and (Values[0]=0) and (Values[1]=1),'hi-hat needs stages 0/1');
    for I := -1 to 1 do begin
      S := Default(TInstrumentState); S.Row := '左足'; S.Choice := 'ハイハット';
      if I<0 then V := D.InstrumentRules.Visibility([])
      else begin S.Stage := Values[I]; V := D.InstrumentRules.Visibility([S]); end;
      try Check(D.Render(B,V),D.LastError); finally V.Free; end;
      if I=-1 then Idle.Assign(B);
      PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'hihat-'+IntToStr(I)+'.png'));
      C.PixelFormat := pf32bit; C.SetSize(400,430); C.Canvas.CopyRect(Rect(0,0,400,430),B.Canvas,Rect(950,570,1350,1000));
      PNG.Assign(C); PNG.SaveToFile(TPath.Combine(Root,'hihat-crop-'+IntToStr(I)+'.png'));
      if I=0 then A.Assign(B);
    end;
    Diff := 0;
    for Y := 0 to A.Height-1 do begin P := A.ScanLine[Y]; Q := B.ScanLine[Y];
      for X := 0 to A.Width-1 do if not CompareMem(@P[X*4],@Q[X*4],4) then Inc(Diff);
    end;
    Writeln('HIHAT_STAGE_0_1_DIFFERENT_PIXELS ',Diff);
    Check(Diff>0,'hi-hat raw rendering does not switch');
    Data := TMusicStudioInstrumentData.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
    try
      Data.Load('{"lengthBeats":4,"notes":[]}'); Block := Default(TInstrumentBlock);
      Block.Row := '左足'; Block.Choice := 'ハイハット'; Block.StartBeat := 0; Block.EndBeat := 4; Block.Stage := 1;
      Check(Data.PutBlock(-1,Block),'hi-hat automatic cycle block');
      Pattern := Default(TMusicStudioPattern); Pattern.Kind := 'performance'; Pattern.Name := 'ハイハット差分確認';
      Pattern.Color := '#EDBA70'; Pattern.ConfigJSON := Data.JSON; Dialog.SilentVisualMode := True;
      Dialog.LoadPerformanceSteps(Pattern,'11111111-1111-1111-1111-111111111111',Path,'{}',120);
      Dialog.Show; Ready; Dialog.InstrumentFrame.Seek(0.5); Ready; A.Assign(Dialog.InstrumentPreview.PreviewBitmap);
      Dialog.InstrumentFrame.Seek(1.5); Ready; B.Assign(Dialog.InstrumentPreview.PreviewBitmap); Diff := 0;
      for Y := 0 to A.Height-1 do begin P := A.ScanLine[Y]; Q := B.ScanLine[Y];
        for X := 0 to A.Width-1 do if not CompareMem(@P[X*4],@Q[X*4],4) then Inc(Diff);
      end;
      Check(Diff>0,'hi-hat editor does not switch'); Writeln('HIHAT_EDITOR_STAGE_0_1_DIFFERENT_PIXELS ',Diff);
      Dialog.InstrumentFrame.Seek(2.5); Ready; Idle.Assign(Dialog.InstrumentPreview.PreviewBitmap);
      Dialog.InstrumentFrame.Seek(4); Ready;
      Check((Length(Dialog.InstrumentFrame.PreviewStates)=1) and (Dialog.InstrumentFrame.PreviewStates[0].Stage=2),'hi-hat end did not hold aftermath');
      Dialog.Hide;
      Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'SceneLibrary')); Doc := TMusicStudioDocument.Create;
      Scene := TMusicStudioPsdSceneCache.Create; Cache := TMusicStudioVisualCache.Create;
      try
        Check(Store.TryImport(Path,'ハイハット確認','#EDBA70',Asset,Duplicate,Error),Error);
        Data.BindAsset(Asset.ID); Pattern.ConfigJSON := Data.JSON;
        Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance');
        Index := Doc.AddPerformance; Pattern.ID := Doc.PatternAt(Index).ID; Doc.UpdatePattern(Pattern);
        Check(Doc.AddBeatPlacement(Track,Slot,Pattern.ID,0,4,Error),Error); Scene.Bind(Doc,Store,Cache);
        for I := 0 to 2 do begin
          Scene.SetPosition((I+0.5)/2,I+0.5); Deadline := GetTickCount64+10000;
          repeat Scene.PollResults; Check(GetTickCount64<Deadline,'hi-hat scene timeout'); Sleep(2);
          until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
          C.Assign(Scene.ImageForTrack(Track)); if I=1 then Expected := B else if I=0 then Expected := A else Expected := Idle;
          // SceneCacheの通常表示は最大512px。原寸の編集画像を同じ画素座標へ参照して照合する。
          Check((C.Width=512) and (C.Height=341),'hi-hat scene preview dimensions');
          for Y := 0 to C.Height-1 do begin
            SY := Int64(Y)*Expected.Height div C.Height; P := Expected.ScanLine[SY]; Q := C.ScanLine[Y];
            for X := 0 to C.Width-1 do begin SX := Int64(X)*Expected.Width div C.Width;
              Check(CompareMem(@P[SX*4],@Q[X*4],4),'hi-hat scene differs from editor');
            end;
          end;
          PNG.Assign(C); PNG.SaveToFile(TPath.Combine(Root,'scene-'+IntToStr(I)+'.png'));
        end;
        Check(THashSHA2.GetHashStringFromFile(TPath.Combine(Root,'scene-0.png'))<>
          THashSHA2.GetHashStringFromFile(TPath.Combine(Root,'scene-1.png')),'hi-hat scene states look identical');
        Writeln('HIHAT_SCENE_PREPARE_STRIKE_AFTERMATH_HOLD_MATCH_EDITOR_PIXELS_NO_AUDIO_OK');
      finally Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    finally Dialog.Free; Data.Free; end;
  finally PNG.Free; Idle.Free; C.Free; B.Free; A.Free; D.Free; end;
end;
procedure BuildHiHatCandidate(const Root,Path: string);
var Original,Edited,Reloaded: TArtDocument; Foot: TArtLayer; Count,X,Y,C,P,Y0,Y1: Integer;
  Pixels: TBytes; PNG: TPngImage; Row,Alpha: PByte; SY,F,A,Color: Double; Target: string;
  procedure Find(List: TList<TArtLayer>; const ParentPath: string);
  var L: TArtLayer; Path: string;
  begin
    for L in List do begin
      Path := ParentPath+'/'+ParseLayerName(L.Name).DisplayName;
      if Path.EndsWith('/左足/ハイハット/1/足_開き') then begin Foot := L; Inc(Count); end;
      Find(L.Children,Path);
    end;
  end;
  procedure SameNames(A,B: TList<TArtLayer>);
  var I: Integer;
  begin
    Check(A.Count=B.Count,'hi-hat hierarchy changed');
    for I := 0 to A.Count-1 do begin Check(A[I].Name=B[I].Name,'hi-hat name changed'); SameNames(A[I].Children,B[I].Children); end;
  end;
begin
  ForceDirectories(Root); Original := ReadPsd(Path); Edited := Original.Clone; Reloaded := nil; PNG := nil;
  try
    Foot := nil; Count := 0; Find(Edited.Roots,''); Check(Count=1,'hi-hat open foot not unique');
    Check((Foot.Bounds.Width=148) and (Foot.Bounds.Height=342),'unexpected hi-hat image');
    Pixels := Copy(Foot.Pixels);
    for Y := 0 to Foot.Bounds.Height-1 do begin
      // 膝側72pxを固定。足首までの移行部だけ縮め、靴全体を30px上げて開放を見える形にする。
      if Y<=72 then SY := Y else if Y<120 then SY := 72+(Y-72)*78/48 else SY := Y+30;
      for X := 0 to Foot.Bounds.Width-1 do begin
        P := (Y*Foot.Bounds.Width+X)*4;
        if SY>Foot.Bounds.Height-1 then begin FillChar(Pixels[P],4,0); Continue; end;
        Y0 := Floor(SY); Y1 := Min(Foot.Bounds.Height-1,Y0+1); F := SY-Y0;
        A := Foot.Pixels[(Y0*148+X)*4+3]*(1-F)+Foot.Pixels[(Y1*148+X)*4+3]*F;
        Pixels[P+3] := EnsureRange(Round(A),0,255);
        for C := 0 to 2 do begin
          Color := Foot.Pixels[(Y0*148+X)*4+C]*Foot.Pixels[(Y0*148+X)*4+3]*(1-F)+
            Foot.Pixels[(Y1*148+X)*4+C]*Foot.Pixels[(Y1*148+X)*4+3]*F;
          if A>0 then Pixels[P+C] := EnsureRange(Round(Color/A),0,255) else Pixels[P+C] := 0;
        end;
      end;
    end;
    Foot.Pixels := Pixels; PNG := TPngImage.CreateBlank(COLOR_RGBALPHA,8,148,342);
    for Y := 0 to 341 do begin
      Row := PNG.Scanline[Y]; Alpha := PByte(PNG.AlphaScanline[Y]);
      for X := 0 to 147 do begin P := (Y*148+X)*4; Row[X*3] := Pixels[P+2]; Row[X*3+1] := Pixels[P+1]; Row[X*3+2] := Pixels[P]; Alpha[X] := Pixels[P+3]; end;
    end;
    PNG.SaveToFile(TPath.Combine(Root,'hihat-open-foot.png'));
    Target := TPath.Combine(Root,'東北きりたん_ドラム.psd');
    Check(not SameText(TPath.GetFullPath(Target),TPath.GetFullPath(Path)),'candidate must differ from source');
    if TFile.Exists(Target) then begin
      Reloaded := ReadPsd(Target); SameNames(Edited.Roots,Reloaded.Roots);
      Check(SameArtDocumentVisualContent(Edited,Reloaded),'hi-hat saved visual content mismatch');
      InspectHiHat(TPath.Combine(Root,'after'),Target);
      Writeln('HIHAT_ONE_IMAGE_ONLY_ALL_NAMES_HIERARCHY_FLAGS_BOUNDS_BASS_OTHER_RGBA_PRESERVED_OK');
    end;
    if not TFile.Exists(TPath.Combine(Root,'before.psd')) then TFile.Copy(Path,TPath.Combine(Root,'before.psd'),False);
  finally PNG.Free; Reloaded.Free; Edited.Free; Original.Free; end;
end;
procedure InspectBassRest(const Root,Path: string);
var D: TMusicStudioLayerDocument; B,C: TBitmap; PNG: TPngImage; States: TArray<TInstrumentState>;
  S: TInstrumentState; V: TJSONObject; Stage: Integer; Values: TArray<Integer>;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; B := TBitmap.Create; C := TBitmap.Create; PNG := TPngImage.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Values := D.InstrumentRules.Stages('右足','バスドラム');
    for Stage := -1 to Length(Values)-1 do begin
      States := nil;
      if Stage>=0 then begin S := Default(TInstrumentState); S.Row := '右足'; S.Choice := 'バスドラム'; S.Stage := Values[Stage]; States := [S]; end;
      V := D.InstrumentRules.Visibility(States);
      try Check(D.Render(B,V),D.LastError); finally V.Free; end;
      PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'bass-'+IntToStr(Stage)+'.png'));
      C.PixelFormat := pf32bit; C.SetSize(600,450); C.Canvas.Brush.Color := clWhite; C.Canvas.FillRect(C.Canvas.ClipRect);
      C.Canvas.CopyRect(Rect(0,0,600,450),B.Canvas,Rect(320,540,920,990));
      PNG.Assign(C); PNG.SaveToFile(TPath.Combine(Root,'bass-crop-'+IntToStr(Stage)+'.png'));
    end;
    Writeln('BASS_REST_STAGES ',Length(Values));
  finally PNG.Free; C.Free; B.Free; D.Free; end;
end;
procedure BuildBassRestCandidate(const Root,Path: string);
var Original,Edited,Reloaded: TArtDocument; Changed: TList<Integer>; Target,Hash: string; Count: Integer;
  procedure ExportFoot(L: TArtLayer);
  var PNG: TPngImage; X,Y,P: Integer; Row,Alpha: PByte;
  begin
    PNG := TPngImage.CreateBlank(COLOR_RGBALPHA,8,L.Bounds.Width,L.Bounds.Height);
    try
      for Y := 0 to L.Bounds.Height-1 do begin
        Row := PNG.Scanline[Y]; Alpha := PByte(PNG.AlphaScanline[Y]);
        for X := 0 to L.Bounds.Width-1 do begin
          P := (Y*L.Bounds.Width+X)*4;
          Row[X*3] := L.Pixels[P+2]; Row[X*3+1] := L.Pixels[P+1]; Row[X*3+2] := L.Pixels[P]; Alpha[X] := L.Pixels[P+3];
        end;
      end;
      PNG.SaveToFile(TPath.Combine(Root,'mid-foot.png'));
    finally PNG.Free; end;
  end;
  function MidFoot(Source: TArtLayer): TBytes;
  var X,Y,C,Y0,Y1,Offset,H,W: Integer; SY,F,A,Color: Double;
  begin
    W := Source.Bounds.Width; H := Source.Bounds.Height;
    Check((W=124) and (H=216),'unexpected bass foot bounds');
    SetLength(Result,W*(H-6)*4);
    for Y := 0 to H-7 do begin
      // 膝側90pxを保持し、足首までの60pxで6pxだけ緩やかに持ち上げる。靴は平行移動。
      if Y<=90 then SY := Y else if Y<144 then SY := 90+(Y-90)*60/54 else SY := Y+6;
      Y0 := Floor(SY); Y1 := Min(H-1,Y0+1); F := SY-Y0;
      for X := 0 to W-1 do begin
        Offset := (Y*W+X)*4;
        A := Source.Pixels[(Y0*W+X)*4+3]*(1-F)+Source.Pixels[(Y1*W+X)*4+3]*F;
        Result[Offset+3] := EnsureRange(Round(A),0,255);
        for C := 0 to 2 do begin
          Color := Source.Pixels[(Y0*W+X)*4+C]*Source.Pixels[(Y0*W+X)*4+3]*(1-F)+
            Source.Pixels[(Y1*W+X)*4+C]*Source.Pixels[(Y1*W+X)*4+3]*F;
          if A>0 then Result[Offset+C] := EnsureRange(Round(Color/A),0,255) else Result[Offset+C] := 0;
        end;
      end;
    end;
  end;
  procedure Visit(List: TList<TArtLayer>);
  var Row,Pattern,Stage,Layer,Strike: TArtLayer; Number: Integer; Pixels: TBytes;
  begin
    for Row in List do begin
      if (Row.Kind=alkGroup) and (ParseLayerName(Row.Name).DisplayName='右足') then
        for Pattern in Row.Children do if ParseLayerName(Pattern.Name).DisplayName.StartsWith('バスドラム') then begin
          Strike := nil;
          for Stage in Pattern.Children do if ParseLayerName(Stage.Name).DisplayName='1' then
            for Layer in Stage.Children do if Layer.Name='足_踏み込み' then Strike := Layer;
          Check(Strike<>nil,'bass strike foot absent'); Pixels := MidFoot(Strike);
          for Stage in Pattern.Children do if TryStrToInt(ParseLayerName(Stage.Name).DisplayName,Number) and (Number>=2) and (Number<=4) then
            for Layer in Stage.Children do if (Layer.Kind=alkImage) and Layer.Name.StartsWith('足_') then begin
              Layer.Pixels := Copy(Pixels); Layer.Bounds := Strike.Bounds; Dec(Layer.Bounds.Bottom,6);
              Layer.Name := '足_待機中間'; Changed.Add(Layer.SourceIndex); Inc(Count);
              if Count=1 then ExportFoot(Layer);
            end;
        end;
      Visit(Row.Children);
    end;
  end;
  procedure Verify(A,B: TList<TArtLayer>);
  var I: Integer; L,R: TArtLayer;
  begin
    Check(A.Count=B.Count,'bass hierarchy changed');
    for I := 0 to A.Count-1 do begin
      L := A[I]; R := B[I]; Check((L.Kind=R.Kind) and (L.Visible=R.Visible) and (L.Opacity=R.Opacity),'bass flags changed');
      if not Changed.Contains(L.SourceIndex) then begin
        Check((L.Name=R.Name) and CompareMem(@L.Bounds,@R.Bounds,SizeOf(L.Bounds)),'unrelated bass properties changed');
        Check((Length(L.Pixels)=Length(R.Pixels)) and ((Length(L.Pixels)=0) or CompareMem(@L.Pixels[0],@R.Pixels[0],Length(L.Pixels))),'unrelated bass pixels changed');
      end;
      Verify(L.Children,R.Children);
    end;
  end;
  procedure VerifySaved(A,B: TList<TArtLayer>);
  var I: Integer; L,R: TArtLayer;
  begin
    Check(A.Count=B.Count,'saved hierarchy count');
    for I := 0 to A.Count-1 do begin
      L := A[I]; R := B[I];
      Check(L.Name=R.Name,'saved name '+L.Name+' vs '+R.Name);
      Check((L.Kind=R.Kind) and (L.Visible=R.Visible) and (L.Opacity=R.Opacity),'saved flags '+L.Name);
      Check(CompareMem(@L.Bounds,@R.Bounds,SizeOf(L.Bounds)),'saved bounds '+L.Name+' source index '+IntToStr(L.SourceIndex));
      Check((Length(L.Pixels)=Length(R.Pixels)) and ((Length(L.Pixels)=0) or CompareMem(@L.Pixels[0],@R.Pixels[0],Length(L.Pixels))),
        'saved pixels '+L.Name+' source index '+IntToStr(L.SourceIndex));
      VerifySaved(L.Children,R.Children);
    end;
  end;
begin
  ForceDirectories(Root); Hash := THashSHA2.GetHashStringFromFile(Path); Target := TPath.Combine(Root,'東北きりたん_ドラム.psd');
  Check(not SameText(TPath.GetFullPath(Path),TPath.GetFullPath(Target)),'candidate must differ from source');
  Original := ReadPsd(Path); Edited := Original.Clone; Reloaded := nil; Changed := TList<Integer>.Create; Count := 0;
  try
    Visit(Edited.Roots); Check(Count=9,'expected nine bass rest layers'); Verify(Original.Roots,Edited.Roots);
    // PSD保存はAIArtToPSD本体のimport/saveへ委ねる。存在する候補だけ独立に再読込照合する。
    if TFile.Exists(Target) then begin
      Reloaded := ReadPsd(Target);
      VerifySaved(Edited.Roots,Reloaded.Roots);
      Check(SameArtDocumentVisualContent(Edited,Reloaded),'bass save/reload visual content mismatch');
      InspectBassRest(TPath.Combine(Root,'after'),Target);
      Writeln('BASS_REST_CANDIDATE_NINE_LAYERS_STAGE_0_1_AND_OTHER_PIXELS_FLAGS_HIERARCHY_PRESERVED_OK');
    end else Writeln('BASS_REST_PNG_PREPARED_USE_AIART_MAIN_FOR_PSD_SAVE');
    Check(Hash=THashSHA2.GetHashStringFromFile(Path),'source changed while staging bass');
    if not TFile.Exists(TPath.Combine(Root,'before.psd')) then TFile.Copy(Path,TPath.Combine(Root,'before.psd'),False);
  finally Changed.Free; Reloaded.Free; Edited.Free; Original.Free; end;
end;
procedure Fixture(const Path: string);
var D: TArtDocument; Row,Action,L: TArtLayer;
begin
  D := TArtDocument.Create;
  try
    D.Width := 4; D.Height := 2;
    Row := D.AddLayer(alkGroup,'右手',TArtBounds.Create(0,0,0,0));
    Action := D.AddLayer(alkGroup,'*打撃',TArtBounds.Create(0,0,0,0),Row);
    L := D.AddLayer(alkImage,'*0',TArtBounds.Create(0,0,1,1),Action); L.Pixels := TBytes.Create(50,60,70,255);
    L := D.AddLayer(alkImage,'*1',TArtBounds.Create(0,0,1,1),Action); L.Pixels := TBytes.Create(230,20,30,255); L.Visible := False;
    L := D.AddLayer(alkImage,'装飾',TArtBounds.Create(2,0,3,1)); L.Pixels := TBytes.Create(40,50,60,255);
    WriteNewPsd(D,Path,pcRaw);
  finally D.Free; end;
end;
function PixelsEqual(A,B: TBitmap): Boolean;
var Y: Integer;
begin
  Result := (A<>nil) and (B<>nil) and (A.Width=B.Width) and (A.Height=B.Height);
  if Result then for Y := 0 to A.Height-1 do if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
end;
procedure RunInstrumentPreviewChecks(const Root,RealPSD: string);
const ID = '11111111-1111-1111-1111-111111111111';
var Dialog: TMusicStudioPatternSettings; F: TMusicStudioInstrumentFrame; P,Saved: TMusicStudioPattern;
  D: TMusicStudioLayerDocument; Data: TMusicStudioInstrumentData; Block: TInstrumentBlock;
  Path,Hash,Base,Before,Error,Text,RealHash: string; Key: Word; Deadline: UInt64;
  N,Track,Slot,Index,Value: Integer; V,Visibility: TJSONObject; Layer: TMusicStudioLayerInfo;
  B: TBitmap; PNG: TPngImage; Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset;
  Doc: TMusicStudioDocument; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache; Duplicate: Boolean;
  procedure Pump;
  begin Application.ProcessMessages; Sleep(2); end;
  procedure Ready;
  begin
    Deadline := GetTickCount64+10000;
    repeat
      Pump; Check(GetTickCount64<Deadline,'preview timeout');
      if Dialog.InstrumentPreview<>nil then Dialog.InstrumentPreview.Poll;
    until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy and (Dialog.InstrumentPreview.PreviewBitmap<>nil);
    Check(Dialog.InstrumentPreview.ErrorText='',Dialog.InstrumentPreview.ErrorText);
  end;
  procedure Open(const FilePath,Config: string);
  begin
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := 'ドラム 演奏'; P.Color := '#EDBA70'; P.ConfigJSON := Config;
    Dialog.LoadPerformanceSteps(P,ID,FilePath,Base,120); Dialog.Show;
    Deadline := GetTickCount64+10000;
    repeat Pump; Check(GetTickCount64<Deadline,'editor load timeout'); until Dialog.InstrumentFrame<>nil;
    F := Dialog.InstrumentFrame; Ready;
  end;
  procedure Pixel(Red: Integer);
  var Bytes: PByte;
  begin
    Ready; Bytes := Dialog.InstrumentPreview.PreviewBitmap.ScanLine[0];
    Check(Bytes[2]=Red,'cursor/draft image differs'); Check(Bytes[2*4+3]=0,'base visibility lost');
  end;
  function X(Beat: Double): Integer;
  begin Result := 134+Round(Beat/F.Data.LengthBeats*(F.Grid.Width-135)); end;
  procedure Mouse(Msg: Cardinal; Beat: Double; Buttons: WPARAM = 0);
  begin F.Grid.Perform(Msg,Buttons,MakeLParam(X(Beat),28+F.TimelineRowHeight div 2)); end;
  procedure Layout;
  var C: TControl; I: Integer;
  begin
    Check((Dialog.InstrumentPreview.Left=0) and (Dialog.InstrumentPreview.Width=F.Left),'preview/editor overlap');
    Check((Dialog.InstrumentPreview.Top=F.Top) and (Dialog.InstrumentPreview.Height=F.Height),'preview outside editor area');
    Check(F.PlayButton.Left+F.PlayButton.Width<=F.StopButton.Left,'transport overlap');
    Check(F.LengthEdit.Left+F.LengthEdit.Width<F.ClientWidth,'length outside editor');
    Check(F.PlayButton.Height>=Abs(F.Font.Height)+4,'button text clipped');
    for I := 0 to F.LengthEdit.Parent.ControlCount-1 do begin
      C := F.LengthEdit.Parent.Controls[I];
      Check(C.Top+C.Height<=C.Parent.Height,'header clipped');
      if C is TLabel then Check(C.Left+C.Width<=F.LengthEdit.Left,'length label overlap');
    end;
  end;
  procedure Capture(const Name: string);
  begin
    Ready; B := TBitmap.Create; PNG := TPngImage.Create;
    try B.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(B.Canvas,0,0); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,Name));
    finally PNG.Free; B.Free; end;
  end;
begin
  ForceDirectories(Root); Path := TPath.Combine(Root,'演奏プレビュー.psd'); Fixture(Path); Hash := THashSHA2.GetHashStringFromFile(Path);
  D := TMusicStudioLayerDocument.Create; Data := TMusicStudioInstrumentData.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
  try
    Check(D.LoadFile(Path),D.LastError); V := TJSONObject.Create; Visibility := TJSONObject.Create;
    try
      for Layer in D.Layers do if Layer.Name='装飾' then Visibility.AddPair(Layer.Key,TJSONBool.Create(False));
      V.AddPair('visibility',Visibility); Base := V.ToJSON;
    finally V.Free; end;
    Data.Load('{"lengthBeats":8,"notes":[]}'); Block := Default(TInstrumentBlock);
    Block.Row := '右手'; Block.Choice := '打撃'; Block.Stage := 1; Block.StartBeat := 1; Block.EndBeat := 2;
    Check(Data.PutBlock(-1,Block),'fixture block'); Dialog.SilentVisualMode := True; Open(Path,Data.JSON); Layout;
    Dialog.ClientWidth := 860; Dialog.ClientHeight := 560; Layout; Capture('minimum-editor.png');
    Dialog.ClientWidth := 1150; Dialog.ClientHeight := 740; Layout;
    F.Seek(0); Pixel(50); F.Seek(1.3); Pixel(230); F.Seek(1.5); Pixel(50); F.Seek(2); Pixel(50);
    // drag中は保存値を変更せずプレビューだけ反映。Escapeで元へ戻す。
    Before := F.Data.JSON; F.Seek(0.4); Mouse(WM_LBUTTONDOWN,3.01,MK_LBUTTON);
    Check(Abs(F.Position-0.4)<1E-9,'draft down moved playhead'); Mouse(WM_MOUSEMOVE,3.5,MK_LBUTTON);
    Check(Abs(F.Position-0.4)<1E-9,'draft add moved playhead');
    Check(F.Data.JSON=Before,'draft changed saved blocks'); Pixel(50);
    Key := VK_ESCAPE; F.HandleKey(Key,[]); Pixel(50); Check(F.Data.JSON=Before,'escape changed blocks');
    Mouse(WM_LBUTTONDOWN,3.01,MK_LBUTTON); Mouse(WM_MOUSEMOVE,3.5,MK_LBUTTON); Mouse(WM_LBUTTONUP,3.5);
    Check(Abs(F.Position-0.4)<1E-9,'draft commit moved playhead');
    Check(F.Data.Blocks.Count=2,'interval commit'); F.Seek(3.2); Pixel(230);
    Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]); Pixel(50); Check(F.Data.Blocks.Count=1,'undo interval');
    Key := Ord('Y'); F.HandleKey(Key,[ssCtrl]); Pixel(230); Check(F.Data.Blocks.Count=2,'redo interval');
    F.Seek(1.3); F.PlayButton.Click; Sleep(40); F.PlaybackTimer.OnTimer(F.PlaybackTimer);
    Check(F.IsPlaying and (F.Position>1.3),'play does not advance cursor'); Pixel(230);
    F.PlayButton.Click; Check(not F.IsPlaying,'pause failed'); F.StopButton.Click; Check(F.Position=0,'stop failed'); Pixel(50);
    N := Dialog.InstrumentPreview.RenderCount; F.Seek(0.1); F.Seek(0.2); Ready;
    Check(Dialog.InstrumentPreview.RenderCount=N,'unchanged state rendered repeatedly');
    F.Seek(1.2); F.Seek(2.2); F.Seek(1.3); F.Seek(2.3); Pixel(50);
    Saved := P; Dialog.ReadPattern(Saved); Check(P.ConfigJSON=Data.JSON,'unsaved caller pattern changed');
    Check(Pos('preview',LowerCase(Saved.ConfigJSON))=0,'preview state serialized'); Capture('synthetic-editor.png');
    // 本番SceneCacheと同じ時刻で画素一致。基本設定と休止区間を含む。
    Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'PSDAssets')); Doc := TMusicStudioDocument.Create;
    Scene := TMusicStudioPsdSceneCache.Create; Cache := TMusicStudioVisualCache.Create;
    try
      Check(Store.TryImport(Path,'試験','#EDBA70',Asset,Duplicate,Error),Error); Asset.ConfigJSON := Base; Check(Store.TrySave(Asset,Error),Error);
      Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance');
      Index := Doc.AddPerformance; Saved.ID := Doc.PatternAt(Index).ID;
      Saved.ConfigJSON := MusicStudioPortablePerformance(Saved.ConfigJSON); Doc.UpdatePattern(Saved);
      Check(Doc.AddBeatPlacement(Track,Slot,Saved.ID,0,8,Error),Error); Scene.Bind(Doc,Store,Cache);
      for Value in TArray<Integer>.Create(0,1,2,3,4) do begin
        F.Seek(Value+0.1); Ready; Scene.SetPosition(F.Position/2,F.Position); Deadline := GetTickCount64+10000;
        repeat Scene.PollResults; Check(GetTickCount64<Deadline,'scene timeout'); Sleep(2);
        until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
        Check(PixelsEqual(Dialog.InstrumentPreview.PreviewBitmap,Scene.ImageForTrack(Track)),'editor differs from project preview');
      end;
      Check(Doc.TrySave(Text,Error),Error);
      TFile.WriteAllText(TPath.Combine(Root,'preview-project.json'),Text);
    finally Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    if RealPSD<>'' then begin
      RealHash := THashSHA2.GetHashStringFromFile(RealPSD); Check(D.LoadFile(RealPSD),D.LastError);
      Base := '{}'; Data.Load('{"lengthBeats":8,"notes":[]}');
      Block := Default(TInstrumentBlock); Block.Row := D.InstrumentRules.RowAt(0).Name;
      Block.Choice := D.InstrumentRules.RowAt(0).Choices[0]; Block.Stage := 1; Block.StartBeat := 0; Block.EndBeat := 2;
      Check(Data.PutBlock(-1,Block),'real block'); Open(RealPSD,Data.JSON); F.Seek(0.5); Ready; Layout; Capture('real-drum-editor.png');
      Check(RealHash=THashSHA2.GetHashStringFromFile(RealPSD),'real source changed');
    end;
    Check(Hash=THashSHA2.GetHashStringFromFile(Path),'fixture PSD changed');
    F.Seek(F.Data.LengthBeats); // 更新要求が残っていても閉じる際にworkerを回収する。
    Dialog.Hide; Check(not F.IsPlaying,'hidden editor still playing');
    Writeln('INSTRUMENT_PREVIEW_LAYOUT_DRAFT_CANCEL_SEEK_PLAY_UNDO_LATEST_SCENE_PIXELS_NO_AUDIO_OK');
  finally Dialog.Free; Data.Free; D.Free; end;
end;
type
  TChoiceGestureDriver = class
    Frame: TMusicStudioInstrumentFrame;
    Timer: Vcl.ExtCtrls.TTimer;
    StageZero,Done: Boolean;
    Failed: string;
    procedure Tick(Sender: TObject);
  end;
  TCloseGestureDriver = class
    Dialog: TMusicStudioPatternSettings;
    Timer: Vcl.ExtCtrls.TTimer;
    Stage: Integer;
    Failed: string;
    procedure Tick(Sender: TObject);
  end;
procedure TChoiceGestureDriver.Tick(Sender: TObject);
var I: Integer; Menu: TPopupMenu;
begin
  Timer.Enabled := False;
  try
    Menu := nil;
    for I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TPopupMenu then Menu := TPopupMenu(Frame.Components[I]);
    Check((Menu<>nil) and (Menu.Items.Count>=2),'choice popup not built');
    if StageZero then Check(not Menu.Items[Menu.Items.Count-1].Items[0].Enabled,'automatic phase is manually selectable') else Menu.Items[0].Click;
    Done := True;
  except on E: Exception do Failed := E.Message; end;
  EndMenu;
end;
procedure TCloseGestureDriver.Tick(Sender: TObject);
begin
  try
    if Stage=0 then begin
      Dialog.InstrumentFrame.LengthEdit.Text := '0'; Inc(Stage);
      SendMessage(Dialog.Handle,WM_CLOSE,0,0);
    end else begin
      Check(Dialog.Visible and (Dialog.ModalResult=mrNone),'invalid close dismissed editor');
      Dialog.InstrumentFrame.LengthEdit.Text := '8'; Dialog.NameEdit.Text := '閉じると確定';
      Inc(Stage); Timer.Enabled := False; SendMessage(Dialog.Handle,WM_CLOSE,0,0);
    end;
  except on E: Exception do begin
    Failed := E.Message; Timer.Enabled := False; Dialog.InstrumentFrame.LengthEdit.Text := '8';
    Dialog.ModalResult := mrOK;
  end; end;
end;
procedure RunInstrumentGestureChecks(const Root,RealPSD: string);
const ID = '11111111-1111-1111-1111-111111111111';
var Dialog: TMusicStudioPatternSettings; F: TMusicStudioInstrumentFrame; D: TMusicStudioLayerDocument;
  Data: TMusicStudioInstrumentData; Block: TInstrumentBlock; P: TMusicStudioPattern;
  Driver: TCloseGestureDriver; Path,Before,Hash,RealHash: string; Deadline: UInt64;
  Anchor,InitialStep,Step,StartBeat,EndBeat,PreviewZoom: Double; Point,View: TPoint; OriginalImage,AfterImage: TPointF;
  OldPan: TPointF; Count,I,FootRow: Integer; Key: Word; B: TBitmap; PNG: TPngImage; ChoiceDriver: TChoiceGestureDriver;
  procedure Ready;
  begin
    Deadline := GetTickCount64+10000;
    repeat
      Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'gesture preview timeout');
      if Dialog.InstrumentPreview<>nil then Dialog.InstrumentPreview.Poll;
    until (Dialog.InstrumentFrame<>nil) and (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
    F := Dialog.InstrumentFrame;
  end;
  procedure Wheel(Control: TWinControl; Delta,X,Y: Integer);
  var ScreenPoint: TPoint;
  begin
    ScreenPoint := Control.ClientToScreen(System.Types.Point(X,Y));
    Control.Perform(WM_MOUSEWHEEL,WPARAM(Word(SmallInt(Delta))) shl 16,MakeLParam(ScreenPoint.X,ScreenPoint.Y));
  end;
  procedure Mouse(Msg: Cardinal; X,Y: Integer; Buttons: WPARAM = 0);
  begin F.Grid.Perform(Msg,Buttons,MakeLParam(X,Y)); end;
  procedure Drag(A,Z: Double);
  var Cursor: Double;
  begin
    Cursor := F.Position;
    Mouse(WM_LBUTTONDOWN,F.BeatToX(A),28+F.TimelineRowHeight div 2,MK_LBUTTON);
    Check(F.Position=Cursor,'drag down moved playhead');
    Mouse(WM_MOUSEMOVE,F.BeatToX(Z),28+F.TimelineRowHeight div 2,MK_LBUTTON);
    Check(F.Position=Cursor,'drag move/resize moved playhead');
    Mouse(WM_LBUTTONUP,F.BeatToX(Z),28+F.TimelineRowHeight div 2);
    Check(F.Position=Cursor,'drag up moved playhead');
  end;
begin
  ForceDirectories(Root); Path := TPath.Combine(Root,'gestures.psd'); Fixture(Path); Hash := THashSHA2.GetHashStringFromFile(Path);
  Dialog := TMusicStudioPatternSettings.Create(nil); D := TMusicStudioLayerDocument.Create; Data := TMusicStudioInstrumentData.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Data.Load('{"lengthBeats":8,"notes":[]}');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := '打撃'; Block.Stage := 1; Block.StartBeat := 1; Block.EndBeat := 2;
    Check(Data.PutBlock(-1,Block),'gesture fixture'); P := Default(TMusicStudioPattern);
    P.Kind := 'performance'; P.Name := '操作確認'; P.Color := '#EDBA70'; P.ConfigJSON := Data.JSON;
    Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(P,ID,Path,'{}',120); Dialog.Show; Ready;
    Check(Dialog.CommitOnClose,'performance close mode absent');
    ChoiceDriver := TChoiceGestureDriver.Create;
    try
      ChoiceDriver.Frame := F; ChoiceDriver.Timer := Vcl.ExtCtrls.TTimer.Create(nil); ChoiceDriver.Timer.Interval := 40;
      ChoiceDriver.Timer.OnTimer := ChoiceDriver.Tick;
      for I := 0 to 2 do begin
        ChoiceDriver.StageZero := I=1; ChoiceDriver.Done := False; ChoiceDriver.Timer.Enabled := True;
        Mouse(WM_LBUTTONDOWN,F.BeatToX(1.5),28+F.TimelineRowHeight div 2,MK_LBUTTON);
        Mouse(WM_LBUTTONUP,F.BeatToX(1.5),28+F.TimelineRowHeight div 2);
        Check(ChoiceDriver.Done and (ChoiceDriver.Failed=''),'choice popup driver '+ChoiceDriver.Failed);
        Check(F.Data.Blocks[0].Stage=1,'automatic phases changed legacy stored stage');
      end;
      Writeln('CHOICE_POPUP_AUTOMATIC_PHASES_NO_MANUAL_STAGE_RESET_OK');
    finally ChoiceDriver.Timer.Free; ChoiceDriver.Free; end;
    for I := 0 to Dialog.ComponentCount-1 do if Dialog.Components[I] is TButton then
      if (TButton(Dialog.Components[I]).Caption='OK') or (TButton(Dialog.Components[I]).Caption='キャンセル') then
        Check(not IsWindowVisible(TButton(Dialog.Components[I]).Handle),'OK/cancel still visible');
    Before := F.Data.JSON; Count := Dialog.InstrumentPreview.RenderCount;
    Point := System.Types.Point(Dialog.InstrumentPreview.Width div 2+20,Dialog.InstrumentPreview.Height div 2);
    OriginalImage := Dialog.InstrumentPreview.ViewToImage(PointF(Point.X,Point.Y));
    Wheel(Dialog.InstrumentPreview,120,Point.X,Point.Y);
    AfterImage := Dialog.InstrumentPreview.ViewToImage(PointF(Point.X,Point.Y));
    Check((Dialog.InstrumentPreview.ViewZoom>1) and (Abs(OriginalImage.X-AfterImage.X)<0.001) and
      (Abs(OriginalImage.Y-AfterImage.Y)<0.001),'PSD pointer zoom anchor');
    F.Grid.SetFocus; View := Dialog.ScreenToClient(Dialog.InstrumentPreview.ClientToScreen(Point));
    PreviewZoom := Dialog.InstrumentPreview.ViewZoom; Wheel(Dialog,120,View.X,View.Y);
    Check((F.ZoomFactor=1) and (Dialog.InstrumentPreview.ViewZoom>PreviewZoom),'focused timeline stole preview wheel');
    OldPan := Dialog.InstrumentPreview.ViewPan;
    Dialog.InstrumentPreview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Point.X,Point.Y));
    Dialog.InstrumentPreview.Perform(WM_MOUSEMOVE,MK_LBUTTON,MakeLParam(Point.X+30,Point.Y-20));
    Dialog.InstrumentPreview.Perform(WM_LBUTTONUP,0,MakeLParam(Point.X+30,Point.Y-20));
    Check(not Dialog.InstrumentPreview.ViewDragging and (Abs(Dialog.InstrumentPreview.ViewPan.X-OldPan.X-30)<0.01) and
      (Abs(Dialog.InstrumentPreview.ViewPan.Y-OldPan.Y+20)<0.01),'PSD pan/release');
    Check((Dialog.InstrumentPreview.RenderCount=Count) and (F.Data.JSON=Before),'view gestures changed data or rerendered PSD');
    Point := System.Types.Point(F.BeatToX(1.2),20); Anchor := F.XToBeat(Point.X); InitialStep := F.SnapStep;
    Dialog.NameEdit.SetFocus; View := Dialog.ScreenToClient(F.Grid.ClientToScreen(Point)); PreviewZoom := Dialog.InstrumentPreview.ViewZoom;
    Wheel(Dialog,720,View.X,View.Y);
    Check(Dialog.InstrumentPreview.ViewZoom=PreviewZoom,'timeline wheel changed PSD view');
    Check((F.ZoomFactor>1) and (Abs(F.XToBeat(Point.X)-Anchor)<1E-7),'timeline pointer zoom anchor');
    Check(F.SnapStep<InitialStep,'zoom did not refine snap/grid'); Check(F.Data.JSON=Before,'zoom changed intervals');
    Mouse(WM_MOUSEMOVE,F.BeatToX(1.5),28+F.TimelineRowHeight div 2); Check(F.Grid.Cursor=crSizeAll,'body move cursor');
    Mouse(WM_MOUSEMOVE,F.BeatToX(1)+1,28+F.TimelineRowHeight div 2); Check(F.Grid.Cursor=crSizeWE,'start resize cursor');
    Mouse(WM_MOUSEMOVE,F.BeatToX(2)-1,28+F.TimelineRowHeight div 2); Check(F.Grid.Cursor=crSizeWE,'end resize cursor');
    Mouse(WM_MOUSEMOVE,F.BeatToX(2.5),28+F.TimelineRowHeight div 2); Check(F.Grid.Cursor=crDefault,'blank cursor');
    Drag(1.5,1.75); Check(Abs(F.Data.Blocks[0].StartBeat-1.25)<1E-7,'interval move at zoom');
    Step := F.SnapStep; StartBeat := F.Data.Blocks[0].StartBeat; EndBeat := F.Data.Blocks[0].EndBeat;
    Drag(StartBeat+1/(F.BeatToX(2)-F.BeatToX(1)),StartBeat+Step);
    Check((Abs(F.Data.Blocks[0].StartBeat-StartBeat-Step)<1E-7) and (Abs(F.Data.Blocks[0].EndBeat-EndBeat)<1E-7),'start resize at zoom');
    Drag(EndBeat-1/(F.BeatToX(2)-F.BeatToX(1)),EndBeat+Step);
    Check(Abs(F.Data.Blocks[0].EndBeat-EndBeat-Step)<1E-7,'end resize at zoom');
    for I := 1 to 3 do begin Key := Ord('Z'); F.HandleKey(Key,[ssCtrl]); end;
    Check(F.Data.JSON=Before,'gesture undo');
    View := System.Types.Point(F.Grid.Width-20,20); Anchor := F.ViewStartBeat;
    Mouse(WM_MBUTTONDOWN,View.X,View.Y,MK_MBUTTON); Mouse(WM_MOUSEMOVE,View.X-40,View.Y,MK_MBUTTON); Mouse(WM_MBUTTONUP,View.X-40,View.Y);
    Check((F.ViewStartBeat>Anchor) and (F.Data.JSON=Before),'timeline pan changed intervals');
    Anchor := F.ViewStartBeat; PreviewZoom := F.Position;
    Mouse(WM_LBUTTONDOWN,View.X,20,MK_LBUTTON); Mouse(WM_MOUSEMOVE,View.X-60,20,MK_LBUTTON); Mouse(WM_LBUTTONUP,View.X-60,20);
    Check((F.ViewStartBeat>Anchor) and (F.Position=PreviewZoom) and (F.Data.JSON=Before),'left ruler pan changed cursor/data');
    Mouse(WM_LBUTTONDOWN,F.BeatToX(2),20,MK_LBUTTON); Mouse(WM_LBUTTONUP,F.BeatToX(2),20);
    Check(Abs(F.Position-2)<0.02,'ruler click does not seek');
    Drag(2.4,2.8); Check(F.Data.Blocks.Count=2,'zoomed interval add');
    Block := F.Data.Blocks[1]; Check((Abs(Block.StartBeat/Step-Round(Block.StartBeat/Step))<1E-7) and
      (Abs(Block.EndBeat/Step-Round(Block.EndBeat/Step))<1E-7),'new interval differs from visible snap grid');
    Ready;
    if RealPSD<>'' then begin
      RealHash := THashSHA2.GetHashStringFromFile(RealPSD); Check(D.LoadFile(RealPSD),D.LastError);
      Data.Load('{"lengthBeats":8,"notes":[]}'); Block := Default(TInstrumentBlock);
      Block.Row := D.InstrumentRules.RowAt(0).Name; Block.Choice := D.InstrumentRules.RowAt(0).Choices[0];
      Block.Stage := 1; Block.StartBeat := 1; Block.EndBeat := 2; Check(Data.PutBlock(-1,Block),'real gesture block'); P.ConfigJSON := Data.JSON;
      Dialog.LoadPerformanceSteps(P,ID,RealPSD,'{}',120); Ready;
      F.Seek(1.5); Wheel(Dialog.InstrumentPreview,120,160,300); Wheel(F.Grid,720,F.BeatToX(1.2),20); Ready;
      if D.InstrumentRules.HasChoice('左足','ハイハット') then begin
        Block := Default(TInstrumentBlock); Block.Row := '左足'; Block.Choice := 'ハイハット'; Block.Stage := 0;
        Block.StartBeat := 1; Block.EndBeat := 2; Check(Data.PutBlock(-1,Block),'real hi-hat block');
        P.ConfigJSON := Data.JSON; Dialog.LoadPerformanceSteps(P,ID,RealPSD,'{}',120); Ready; F.Seek(1.5);
        FootRow := -1; for I := 0 to F.Rules.RowCount-1 do if F.Rules.RowAt(I).Name='左足' then FootRow := I;
        Check(FootRow>=0,'real left foot row absent'); Block := F.Data.Blocks[0];
        ChoiceDriver := TChoiceGestureDriver.Create;
        try
          ChoiceDriver.Frame := F; ChoiceDriver.Timer := Vcl.ExtCtrls.TTimer.Create(nil); ChoiceDriver.Timer.Interval := 40;
          ChoiceDriver.Timer.OnTimer := ChoiceDriver.Tick; ChoiceDriver.Timer.Enabled := True;
          Mouse(WM_LBUTTONDOWN,F.BeatToX(1.5),28+FootRow*F.TimelineRowHeight+F.TimelineRowHeight div 2,MK_LBUTTON);
          Mouse(WM_LBUTTONUP,F.BeatToX(1.5),28+FootRow*F.TimelineRowHeight+F.TimelineRowHeight div 2);
          Check(ChoiceDriver.Done and (ChoiceDriver.Failed=''),'real foot menu '+ChoiceDriver.Failed);
          Check((F.Data.Blocks[1].Row='左足') and (F.Data.Blocks[1].Stage=1),'left foot candidate selected wrong row/stage');
          Check((F.Data.Blocks[0].Row=Block.Row) and (F.Data.Blocks[0].Choice=Block.Choice) and (F.Data.Blocks[0].Stage=Block.Stage),'foot menu changed hand block');
          Ready; Writeln('REAL_LEFT_FOOT_MENU_DEFAULT1_OTHER_HAND_BLOCK_PRESERVED_OK');
        finally ChoiceDriver.Timer.Free; ChoiceDriver.Free; end;
      end;
      Check(RealHash=THashSHA2.GetHashStringFromFile(RealPSD),'real PSD changed');
    end;
    B := TBitmap.Create; PNG := TPngImage.Create;
    try B.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(B.Canvas,0,0); PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,'gesture-editor.png'));
    finally PNG.Free; B.Free; end;
    Dialog.Hide; Driver := TCloseGestureDriver.Create;
    try
      Driver.Dialog := Dialog; Driver.Timer := Vcl.ExtCtrls.TTimer.Create(nil); Driver.Timer.Interval := 40; Driver.Timer.OnTimer := Driver.Tick;
      Check(Dialog.ShowModal=mrOK,'window close did not commit'); Check(Driver.Failed='',Driver.Failed); Check(Driver.Stage=2,'invalid close not retained');
      Dialog.ReadPattern(P); Check(P.Name='閉じると確定','close result not readable');
    finally Driver.Timer.Free; Driver.Free; end;
    Check(Hash=THashSHA2.GetHashStringFromFile(Path),'gesture fixture changed');
    Writeln('INSTRUMENT_GESTURES_PREVIEW_ZOOM_PAN_TIMELINE_ANCHOR_GRID_SNAP_CURSORS_EDGES_UNDO_CLOSE_VALIDATE_OK');
  finally Dialog.Free; Data.Free; D.Free; end;
end;
end.
