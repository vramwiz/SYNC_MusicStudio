unit SYNC_MusicStudio_InstrumentPhaseChecks;

// 四肢共通の25/25/50、欠損余韻、最後のパターン保持、clip間の保持を無音で検証する。
interface
procedure RunInstrumentPhaseChecks(const Root: string; const RealPSD: string = '');
procedure RunInstrumentRepeatChecks(const Root,PSD: string; AllLimbs: Boolean = False);
procedure RunPsdSampledChecks(const Root,PSD: string);
procedure RunInstrumentResonanceChecks(const Root,PSD: string);
procedure RunInstrumentCymbalVisibilityChecks(const Root,PSD: string);
procedure RunPsdRenderCostChecks(const Root,PSD,Baseline: string);
procedure RunInstrumentEffectChecks(const Root,PSD: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Types, System.JSON, System.Math, Vcl.Graphics,
  SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_PsdLayers,
  SYNC_MusicStudio_InstrumentData, SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentPlayback,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_VisualCache,
  SYNC_MusicStudio_PsdSceneCache, SYNC_MusicStudio_PatternSettingsForm,
  Winapi.Windows, Vcl.Forms, Vcl.Imaging.pngimage, SYNC_MusicStudio_VideoRenderer,
  SYNC_MusicStudio_DrumPsdRules, System.Diagnostics, System.Hash, System.Generics.Collections;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('INSTRUMENT_PHASE: '+Text); end;
procedure RunInstrumentEffectChecks(const Root,PSD: string);
const Beats: array[0..6] of Double = (0.1,0.249999,0.25,0.5,0.999999,1.0,100.0);
var D: TMusicStudioLayerDocument; Model: TMusicStudioInstrumentData; Block,Next: TInstrumentBlock;
  States: TArray<TInstrumentState>; Row: TInstrumentRow; Choice: string;
  V: TJSONObject; I,J,Cases: Integer; L: TMusicStudioLayerInfo; A,B: Vcl.Graphics.TBitmap;
  Rules: TMusicStudioInstrumentRules; Meta: TArray<TDrumPsdLayer>; Parent,Channel,PatternKey: string;
  Ranges: TArray<TInstrumentPlaybackRange>; Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset;
  Doc: TMusicStudioDocument; Cache: TMusicStudioVisualCache; Scene: TMusicStudioPsdSceneCache;
  Dialog: TMusicStudioPatternSettings; Pattern: TMusicStudioPattern; Duplicate: Boolean;
  Error,JSON,Before: string; Track,Slot,Index: Integer; Deadline: UInt64; PNG: TPngImage;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; X,Y: Integer; Scan: PByte; Beat: Double;
  Together: TArray<TInstrumentBlock>;
  function Same(A,B: Vcl.Graphics.TBitmap): Boolean;
  var Y: Integer;
  begin
    Result := (A.Width=B.Width) and (A.Height=B.Height); if not Result then Exit;
    for Y := 0 to A.Height-1 do if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
  end;
  function Visible(const Item: TMusicStudioLayerInfo): Boolean;
  var Current: TMusicStudioLayerInfo; Value: TJSONValue; K: Integer; Found: Boolean;
  begin
    Current := Item;
    repeat
      Value := V.GetValue(Current.Key);
      if Value<>nil then Result := Value is TJSONTrue else Result := Current.Visible;
      if not Result or (Current.Group='') then Exit;
      Found := False; for K := 0 to High(D.Layers) do if D.Layers[K].Path=Current.Group then begin Current := D.Layers[K]; Found := True; Break; end;
      Check(Found,'effect ancestor missing');
    until False;
  end;
  function EffectCount: Integer;
  var Item: TMusicStudioLayerInfo;
  begin
    Result := 0;
    for Item in D.Layers do if not Item.IsGroup and Item.Path.StartsWith('/演奏エフェクト/') and Visible(Item) then Inc(Result);
  end;
  function EffectStage(const Values: TArray<TInstrumentState>): Integer;
  var S: TInstrumentState;
  begin
    Result := -999; for S in Values do if S.LayerScope='effect' then Exit(S.Stage);
  end;
  function AddMeta(const Name,Parent: string): string;
  var I: Integer;
  begin
    I := Length(Meta); SetLength(Meta,I+1); Result := IntToStr(I+1);
    Meta[I].Key := Result; Meta[I].ParentKey := Parent; Meta[I].Name := Name; Meta[I].Path := Name;
    Meta[I].IsGroup := True; Meta[I].Visible := False;
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create;
  A := Vcl.Graphics.TBitmap.Create; B := Vcl.Graphics.TBitmap.Create; Rules := TMusicStudioInstrumentRules.Create; PNG := TPngImage.Create;
  try
    Check(D.LoadFile(PSD),D.LastError); Check(D.InstrumentRules.RowCount=4,'effects changed UI rows'); Cases := 0;
    for I := 0 to D.InstrumentRules.RowCount-1 do begin Row := D.InstrumentRules.RowAt(I);
      for Choice in Row.Choices do if D.InstrumentRules.HasEffectChoice(Row.Name,Choice) then begin
        Inc(Cases); Block := Default(TInstrumentBlock); Block.Row := Row.Name; Block.Choice := Choice; Block.EndBeat := 1;
        for J := Low(Beats) to High(Beats) do begin
          States := MusicStudioInstrumentPlaybackStates([Block],D.InstrumentRules,Beats[J]);
          V := D.InstrumentRules.Visibility(States);
          try
            if (J>=2) and (J<=4) then Check(EffectCount=1,'effect missing '+Choice) else Check(EffectCount=0,'effect persisted '+Choice);
            if J=4 then begin
              for L in D.Layers do if not L.IsGroup and L.Path.StartsWith('/演奏エフェクト/') then MusicStudioSetJsonBoolean(V,L.Key,False);
              Check(D.Render(A,V,512),D.LastError);
            end;
            if J=5 then begin Check(D.Render(B,V,512),D.LastError); Check(Same(A,B),'limb changed at effect end '+Choice); end;
          finally V.Free; end;
        end;
        SetLength(Ranges,1); Ranges[0].Blocks := [Block]; Ranges[0].StartBeat := 0; Ranges[0].EndBeat := 0.2;
        Check(EffectStage(MusicStudioInstrumentActionStates(Ranges,D.InstrumentRules,0.3))=-1,'pre-strike clipped effect');
        Ranges[0].EndBeat := 0.7;
        Check(EffectStage(MusicStudioInstrumentActionStates(Ranges,D.InstrumentRules,0.7))=-1,'effect ignored clipped end');
        Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],D.InstrumentRules,0.3))=1,'reverse seek effect');
      end;
    end;
    Check(Cases=9,'expected nine effect choices');
    SetLength(Together,3);
    Together[0] := Default(TInstrumentBlock); Together[0].Row := '右手'; Together[0].Choice := 'スネア中央（エフェクト付き）'; Together[0].EndBeat := 1;
    Together[1] := Together[0]; Together[1].Row := '左手'; Together[1].Choice := 'ハイハット閉（エフェクト付き）'; Together[1].StartBeat := 0.5; Together[1].EndBeat := 1.5;
    Together[2] := Together[0]; Together[2].Row := '右足'; Together[2].Choice := 'バスドラム'; Together[2].StartBeat := 0.25; Together[2].EndBeat := 1.25;
    for I := 0 to 3 do begin
      if I=0 then Beat := 0.8 else Beat := 0.76+I*0.25;
      V := D.InstrumentRules.Visibility(MusicStudioInstrumentPlaybackStates(Together,D.InstrumentRules,Beat));
      try Check(EffectCount=3-I,'independent hand/foot effect lifetimes'); finally V.Free; end;
    end;
    Writeln('NINE_EFFECT_LIFETIMES_AND_LIMB_HOLD_OK');
    // Additional effect frames advance independently while the limb holds stage2.
    Parent := AddMeta('身体',''); Channel := AddMeta('右手',Parent); PatternKey := AddMeta('*A',Channel);
    for I := 0 to 2 do AddMeta('*'+IntToStr(I),PatternKey);
    Parent := AddMeta('演奏エフェクト',''); Channel := AddMeta('右手効果',Parent); PatternKey := AddMeta('*A',Channel);
    for I := 0 to 4 do AddMeta('*'+IntToStr(I),PatternKey); Rules.Build(Meta);
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'A'; Block.EndBeat := 1;
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,0.1))=0,'optional effect preparation');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,0.25))=1,'effect strike boundary');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,0.749999))=1,'double strike ended early');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,0.75))=2,'effect tail boundary');
    States := MusicStudioInstrumentPlaybackStates([Block],Rules,0.85);
    Check((States[0].Stage=2) and (EffectStage(States)=3),'effect/limb stages remain coupled');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,0.96))=4,'final effect frame');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates([Block],Rules,1))=-1,'effect end boundary');
    Model.Load('{"lengthBeats":4,"notes":[],"future":"preserve"}');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'スネア中央（エフェクト付き）'; Block.EndBeat := 1;
    Check(Model.PutBlock(-1,Block),'effect block'); Next := Block; Next.StartBeat := 1.2; Next.EndBeat := 2.2;
    Check(Model.PutBlock(-1,Next),'effect retrigger'); Before := Model.JSON;
    Check(EffectStage(MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,1.1))=-1,'effect gap');
    Check(EffectStage(MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,1.5))=1,'effect retrigger');
    Check(Model.JSON=Before,'effect evaluation changed project');
    Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'PSDAssets')); Doc := TMusicStudioDocument.Create;
    Cache := TMusicStudioVisualCache.Create; Scene := TMusicStudioPsdSceneCache.Create; Dialog := TMusicStudioPatternSettings.Create(nil);
    try
      Check(Store.TryImport(PSD,'打撃効果','#EDBA70',Asset,Duplicate,Error),Error); Check(Doc.TryLoad('',Error),Error);
      Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance'); Index := Doc.AddPerformance;
      Pattern := Doc.PatternAt(Index); Pattern.ConfigJSON := Model.JSON; Doc.UpdatePattern(Pattern);
      Check(Doc.AddBeatPlacement(Track,Slot,Pattern.ID,0,4,Error),Error); Check(Doc.TrySave(JSON,Error),Error);
      Scene.Bind(Doc,Store,Cache); Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(Pattern,Asset.ID,PSD,'{}',120); Dialog.Show;
      Deadline := GetTickCount64+15000;
      repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'effect editor load timeout');
      until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
      for Beat in TArray<Double>.Create(0.1,0.3,0.7,0.999999,1.0,1.1,1.5,0.3) do begin
        States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,Beat);
        V := D.InstrumentRules.Visibility(States); try Check(D.Render(A,V,512),D.LastError); finally V.Free; end;
        Scene.SetPosition(Beat/2,Beat); Dialog.InstrumentFrame.Seek(Beat); Deadline := GetTickCount64+15000;
        repeat Application.ProcessMessages; Scene.PollResults; Dialog.InstrumentPreview.Poll; Sleep(2);
          Check(GetTickCount64<Deadline,'effect preview timeout');
        until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil) and not Dialog.InstrumentPreview.Busy;
        Check(Same(A,Scene.ImageForTrack(Track)),'effect scene pixels'); Check(Same(A,Dialog.InstrumentPreview.PreviewBitmap),'effect editor pixels');
        if (Beat=0.7) or (Beat=1.0) then begin PNG.Assign(A); PNG.SaveToFile(TPath.Combine(Root,'effect-'+FormatFloat('0.0',Beat,TFormatSettings.Invariant)+'.png')); end;
      end;
      Dialog.Hide; Video := TMusicStudioVideoSession.Create(Store.Root);
      try
        Scene.MaximumImageDimension := 0; Scene.Bind(Doc,Store,Cache);
        for Beat in TArray<Double>.Create(0.3,0.7,1.0,0.3) do begin
          Scene.SetPosition(Beat/2,Beat); Deadline := GetTickCount64+15000;
          repeat Scene.PollResults; Sleep(2); Check(GetTickCount64<Deadline,'native effect timeout'); until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
          A.Assign(Scene.ImageForTrack(Track)); Check(Video.Render(JSON,Beat/2,A.Width,A.Height,Pixels,Error),Error);
          for Y := 0 to A.Height-1 do begin Scan := A.ScanLine[Y]; for X := 0 to A.Width-1 do
            Check((Pixels[Y*A.Width+X].R=Scan[X*4+2]) and (Pixels[Y*A.Width+X].G=Scan[X*4+1]) and
              (Pixels[Y*A.Width+X].B=Scan[X*4]) and (Pixels[Y*A.Width+X].A=Scan[X*4+3]),'effect video pixels'); end;
        end;
      finally Video.Free; end;
    finally Dialog.Free; Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    Writeln('NINE_EFFECT_CHOICES_EXPIRE_LIMBS_HOLD_EXTRA_FRAMES_CLIP_SEEK_RETRIGGER_EDITOR_SCENE_VIDEO_OK');
  finally PNG.Free; Rules.Free; B.Free; A.Free; Model.Free; D.Free; end;
end;
procedure RunPsdRenderCostChecks(const Root,PSD,Baseline: string);
var D,Worker: TMusicStudioLayerDocument; B: Vcl.Graphics.TBitmap; V: TJSONObject;
  Frames: TArray<TInstrumentState>; State: TInstrumentState;
  Hashes,Reference,Times: TStringList; Stream: TMemoryStream; Watch: TStopwatch;
  Art: TArtDocument; Group,Image: TArtLayer; Pixels: TBytes;
  I,J,K,Mode,Frame,Size: Integer; Key,Hash: string; Total: Double;
  procedure RecordHash(const Name: string; Data: TStream);
  begin
    Data.Position := 0; Hash := THashSHA2.GetHashString(Data); Hashes.Values[Name] := Hash;
    if Baseline<>'' then Check(Reference.Values[Name]=Hash,'optimized pixels differ: '+Name);
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; B := Vcl.Graphics.TBitmap.Create;
  Hashes := TStringList.Create; Reference := TStringList.Create; Times := TStringList.Create; Stream := TMemoryStream.Create;
  try
    if Baseline<>'' then Reference.LoadFromFile(Baseline);
    Check(D.LoadFile(PSD),D.LastError);
    for Mode := 0 to 1 do begin
      Total := 0; Size := 0; if Mode=0 then Size := 512;
      for Frame := 0 to 14 do begin
        Frames := nil;
        if Frame<6 then begin
          for I := 0 to 3 do begin
            State := Default(TInstrumentState); State.Row := INSTRUMENT_ACTION_ROWS[I]; State.Stage := Frame mod 3;
            case I of 0: State.Choice := 'スネア右側'; 1: State.Choice := 'ハイハット開';
              2: State.Choice := 'バスドラム'; 3: State.Choice := 'ハイハット'; end;
            if I=0 then State.LayerScope := 'body'; Frames := Frames+[State];
          end;
        end else begin
          State := Default(TInstrumentState); State.Row := '右手'; State.Choice := 'クラッシュ';
          State.Stage := 1+(Frame-6) mod 2; State.LayerScope := 'body'; Frames := [State];
          State.Stage := Frame-5; State.LayerScope := 'resonance'; Frames := Frames+[State];
        end;
        V := D.InstrumentRules.Visibility(Frames); Worker := nil;
        try
          Watch := TStopwatch.StartNew; Worker := D.Clone; Check(Worker.Render(B,V,Size),Worker.LastError);
          Watch.Stop; Total := Total+Watch.Elapsed.TotalMilliseconds;
          Key := Format('%d/%d',[Size,Frame]); Times.Values[Key] := FormatFloat('0.000',Watch.Elapsed.TotalMilliseconds);
          Stream.Clear; for J := 0 to B.Height-1 do Stream.WriteBuffer(B.ScanLine[J]^,B.Width*4);
          RecordHash(Key,Stream);
        finally Worker.Free; V.Free; end;
      end;
      Writeln('COLD_WORKER_RENDER_MAX_',Size,'_AVG_MS ',FormatFloat('0.000',Total/15));
    end;
    // Independent old-output hashes cover transparent pixels, normal/pass groups,
    // multiply, masks, opacity, canvas clipping and one-pixel sampled outputs.
    for K := 0 to 7 do begin
      Art := TArtDocument.Create;
      try
        Art.Width := 49; Art.Height := 37;
        for I := 0 to 3 do begin
          Group := Art.AddLayer(alkGroup,'group',TArtBounds.Create(0,0,0,0));
          if Odd(K) and (I=1) then Group.BlendKey := 'pass' else Group.BlendKey := 'norm';
          if (K=2) and (I=2) then Group.Opacity := 0;
          if (K=3) and (I=3) then Group.Opacity := 177;
          if (K=4) and (I=1) then begin Group.HasMask := True; Group.MaskDefault := 0;
            Group.MaskBounds := TArtBounds.Create(7,8,17,20); SetLength(Group.MaskPixels,120);
            for J := 0 to 119 do Group.MaskPixels[J] := J*2; end;
          Group := Art.AddLayer(alkGroup,'nested',TArtBounds.Create(0,0,0,0),Group);
          Image := Art.AddLayer(alkImage,'image',TArtBounds.Create(-4+I*8,3+I*5,12+I*8,17+I*5),Group);
          if (K=5) and (I=2) then Image.BlendKey := 'mul ';
          if (K=6) and (I=2) then Image.Opacity := 0;
          if (K=7) and (I=2) then Image.Visible := False;
          SetLength(Image.Pixels,16*14*4);
          for J := 0 to 16*14-1 do begin
            Image.Pixels[J*4] := J mod 251; Image.Pixels[J*4+1] := J*3 mod 251; Image.Pixels[J*4+2] := 210;
            case J mod 4 of 0: Image.Pixels[J*4+3] := 0; 1: Image.Pixels[J*4+3] := 255;
              2: Image.Pixels[J*4+3] := 127; 3: Image.Pixels[J*4+3] := 1; end;
          end;
        end;
        for Mode := 0 to 2 do begin
          case Mode of 0: Pixels := RenderPsdLayers(Art); 1: Pixels := RenderPsdLayers(Art,17,13);
            2: Pixels := RenderPsdLayers(Art,1,1); end;
          Stream.Clear; Stream.WriteBuffer(Pixels[0],Length(Pixels)); RecordHash(Format('synthetic/%d/%d',[K,Mode]),Stream);
        end;
      finally Art.Free; end;
    end;
    if Baseline<>'' then Check(Hashes.Count=Reference.Count,'reference cases changed');
    Hashes.SaveToFile(TPath.Combine(Root,'render-hashes.txt')); Times.SaveToFile(TPath.Combine(Root,'render-times.txt'));
    Writeln('PSD_RENDER_REFERENCE_PIXELS_OK cases=',Hashes.Count);
  finally Stream.Free; Times.Free; Reference.Free; Hashes.Free; B.Free; D.Free; end;
end;
procedure RunInstrumentCymbalVisibilityChecks(const Root,PSD: string);
var D: TMusicStudioLayerDocument; Legacy: TMusicStudioInstrumentRules;
  Meta: TArray<TDrumPsdLayer>; Row: TInstrumentRow; Choice: string;
  State: TInstrumentState; Block,Hit: TInstrumentBlock; V: TJSONObject;
  I,J,Stage,Count: Integer; L: TMusicStudioLayerInfo; B: Vcl.Graphics.TBitmap; P: TPngImage;
  function Visible(const Item: TMusicStudioLayerInfo; Overrides: TJSONObject): Boolean;
  var Current: TMusicStudioLayerInfo; Value: TJSONValue; K: Integer; Found: Boolean;
  begin
    Current := Item;
    repeat
      Value := Overrides.GetValue(Current.Key);
      if Value<>nil then Result := Value is TJSONTrue else Result := Current.Visible;
      if not Result or (Current.Group='') then Exit;
      Found := False;
      for K := 0 to High(D.Layers) do if D.Layers[K].Path=Current.Group then begin Current := D.Layers[K]; Found := True; Break; end;
      Check(Found,'missing cymbal ancestor');
    until False;
  end;
  procedure CheckCrash(const Context: string);
  var Item: TMusicStudioLayerInfo; N: Integer;
  begin
    N := 0;
    for Item in D.Layers do if not Item.IsGroup and Item.Name.StartsWith('クラッシュ_余韻') and Visible(Item,V) then Inc(N);
    Check(N=1,Context+': expected one visible crash, got '+IntToStr(N)); Inc(Count);
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Legacy := TMusicStudioInstrumentRules.Create;
  B := Vcl.Graphics.TBitmap.Create; P := TPngImage.Create; Count := 0;
  try
    Check(D.LoadFile(PSD),D.LastError); SetLength(Meta,Length(D.Layers));
    // Model the older keyword-only reader: it does not know the optional resonance marker.
    for I := 0 to High(D.Layers) do begin
      L := D.Layers[I]; Meta[I].Key := L.Key; Meta[I].Name := L.Name; Meta[I].Path := L.Path;
      Meta[I].Visible := L.Visible; Meta[I].IsGroup := L.IsGroup; Meta[I].SourceIndex := L.SourceIndex;
      if L.Name='楽器余韻' then Meta[I].Name := '旧版の未知グループ';
      for J := 0 to High(D.Layers) do if (L.Group<>'') and (D.Layers[J].Path=L.Group) then Meta[I].ParentKey := D.Layers[J].Key;
    end;
    Legacy.Build(Meta);
    Hit := Default(TInstrumentBlock); Hit.Row := '右手'; Hit.Choice := 'クラッシュ'; Hit.EndBeat := 0.4;
    for I := 0 to D.InstrumentRules.RowCount-1 do begin
      Row := D.InstrumentRules.RowAt(I);
      for Choice in Row.Choices do for Stage := 0 to 2 do begin
        State := Default(TInstrumentState); State.Row := Row.Name; State.Choice := Choice; State.Stage := Stage;
        V := Legacy.Visibility([State]); try CheckCrash('legacy '+Choice+'/'+IntToStr(Stage)); finally V.Free; end;
        V := D.InstrumentRules.Visibility([State]); try CheckCrash('static '+Choice+'/'+IntToStr(Stage)); finally V.Free; end;
        Block := Default(TInstrumentBlock); Block.Row := Row.Name; Block.Choice := Choice;
        Block.StartBeat := 0.8; Block.EndBeat := 1.2;
        V := D.InstrumentRules.Visibility(MusicStudioInstrumentPlaybackStates([Block],D.InstrumentRules,0.85+Stage*0.1));
        try CheckCrash('first hit '+Choice); finally V.Free; end;
        V := D.InstrumentRules.Visibility(MusicStudioInstrumentPlaybackStates([Hit,Block],D.InstrumentRules,0.85+Stage*0.1));
        try
          CheckCrash('after crash '+Choice);
          if (Choice='スネア中央') and (Stage=1) then begin
            Check(D.Render(B,V,512),D.LastError); P.Assign(B); P.SaveToFile(TPath.Combine(Root,'snare-crash-preserved.png'));
          end;
        finally V.Free; end;
      end;
    end;
    // The editor's PSDTool-style exclusive selection also leaves the rear branch intact.
    for L in D.Layers do if L.IsGroup and L.Name.StartsWith('*') and not L.Path.StartsWith('/楽器余韻') then begin
      V := TJSONObject.Create;
      try D.SelectLayerOverride(V,L.Key); CheckCrash('native selection '+L.Path); finally V.Free; end;
    end;
    Writeln('CRASH_ALL_CHOICES_STATIC_PLAYBACK_NATIVE_LEGACY_VISIBLE_OK checks=',Count);
  finally P.Free; B.Free; Legacy.Free; D.Free; end;
end;
procedure RunPsdSampledChecks(const Root,PSD: string);
var Art: TArtDocument; G,L: TArtLayer; Full,Small: TBytes; I,X,Y,W,H,SX,SY: Integer;
  D: TMusicStudioLayerDocument; Native,Reduced: Vcl.Graphics.TBitmap; PNG: TPngImage; Started: UInt64;
  procedure Image(const Bounds: TArtBounds; Parent: TArtLayer; Multiply: Boolean);
  var N: Integer;
  begin
    L := Art.AddLayer(alkImage,'pixel',Bounds,Parent); SetLength(L.Pixels,Bounds.Width*Bounds.Height*4);
    for N := 0 to Length(L.Pixels) div 4-1 do begin L.Pixels[N*4] := N mod 251;
      L.Pixels[N*4+1] := N*3 mod 253; L.Pixels[N*4+2] := N*7 mod 255; L.Pixels[N*4+3] := 80+N mod 176; end;
    if Multiply then L.BlendKey := 'mul ';
  end;
begin
  ForceDirectories(Root); Art := TArtDocument.Create;
  try
    Art.Width := 37; Art.Height := 29;
    Image(TArtBounds.Create(-3,5,20,25),nil,False); L.HasMask := True;
    L.MaskBounds := TArtBounds.Create(-4,4,20,28); L.MaskDefault := 0; L.MaskInvert := True;
    SetLength(L.MaskPixels,24*24); for I := 0 to High(L.MaskPixels) do L.MaskPixels[I] := I mod 256;
    G := Art.AddLayer(alkGroup,'group',TArtBounds.Create(0,0,0,0)); G.BlendKey := 'norm'; G.Opacity := 210;
    G.HasMask := True; G.MaskBounds := TArtBounds.Create(1,2,18,15); G.MaskDefault := 255;
    SetLength(G.MaskPixels,17*13); for I := 0 to High(G.MaskPixels) do G.MaskPixels[I] := 255-I mod 256;
    Image(TArtBounds.Create(11,-4,44,28),G,True); Image(TArtBounds.Create(0,0,37,29),G,False);
    Full := RenderPsdLayers(Art);
    for I := 0 to 3 do begin
      case I of 0: begin W := 17; H := 13; end; 1: begin W := 12; H := 10; end;
        2: begin W := 1; H := 1; end; else begin W := 37; H := 29; end; end;
      Small := RenderPsdLayers(Art,W,H);
      for Y := 0 to H-1 do for X := 0 to W-1 do begin SX := X*37 div W; SY := Y*29 div H;
        Check(CompareMem(@Small[(Y*W+X)*4],@Full[(SY*37+SX)*4],4),'sampled mask/alpha/multiply/group/negative edge differs'); end;
    end;
  finally Art.Free; end;
  if PSD<>'' then begin
    D := TMusicStudioLayerDocument.Create; Native := Vcl.Graphics.TBitmap.Create;
    Reduced := Vcl.Graphics.TBitmap.Create; PNG := TPngImage.Create;
    try
      Check(D.LoadFile(PSD),D.LastError); Started := GetTickCount64; Check(D.Render(Native),D.LastError);
      Writeln('NATIVE_RENDER_MS ',GetTickCount64-Started); Started := GetTickCount64;
      Check(D.Render(Reduced,nil,512),D.LastError); Writeln('SAMPLED_RENDER_MS ',GetTickCount64-Started);
      Check((Reduced.Width=512) and (Reduced.Height=341),'preview size');
      for Y := 0 to Reduced.Height-1 do for X := 0 to Reduced.Width-1 do begin
        SX := Int64(X)*Native.Width div Reduced.Width; SY := Int64(Y)*Native.Height div Reduced.Height;
        Check(CompareMem(@PByte(Reduced.ScanLine[Y])[X*4],@PByte(Native.ScanLine[SY])[SX*4],4),'actual native/preview pixels differ');
      end;
      PNG.Assign(Reduced); PNG.SaveToFile(TPath.Combine(Root,'sampled-drum.png'));
    finally PNG.Free; Reduced.Free; Native.Free; D.Free; end;
  end;
  Writeln('PSD_SAMPLED_PIXELS_MATCH_NATIVE_ALPHA_MASK_GROUP_MULTIPLY_CLIPPED_EDGES_OK');
end;
procedure RunInstrumentRepeatChecks(const Root,PSD: string; AllLimbs: Boolean);
var D: TMusicStudioLayerDocument; Model: TMusicStudioInstrumentData; B: TInstrumentBlock;
  Dialog: TMusicStudioPatternSettings; Pattern: TMusicStudioPattern; I,Previous,Changes,CacheBefore: Integer;
  Deadline,Start,Tick: UInt64; Lines: TStringList; Values: TArray<TInstrumentState>;
  Expected: array[0..2] of Vcl.Graphics.TBitmap; Seen: array[0..3,0..2] of Boolean; Phase,Hit,Y: Integer; Same: Boolean; R: string;
begin
  for Phase := 0 to 2 do Expected[Phase] := nil;
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create;
  Dialog := TMusicStudioPatternSettings.Create(nil); Lines := TStringList.Create;
  try
    Check(D.LoadFile(PSD),D.LastError); Model.Load('{"lengthBeats":8,"notes":[]}');
    for R in INSTRUMENT_ACTION_ROWS do if AllLimbs or (R='右足') then
      for I := 0 to 3 do begin B := Default(TInstrumentBlock); B.Row := R; B.Stage := 1;
        if R='右手' then B.Choice := 'スネア右側' else if R='左手' then B.Choice := 'ハイハット開'
        else if R='右足' then B.Choice := 'バスドラム' else B.Choice := 'ハイハット';
        B.StartBeat := I; B.EndBeat := I+0.5; Check(Model.PutBlock(-1,B),'repeat block'); end;
    Pattern := Default(TMusicStudioPattern); Pattern.Kind := 'performance'; Pattern.Name := '連打';
    Pattern.Color := '#EDBA70'; Pattern.ConfigJSON := Model.JSON; Dialog.SilentVisualMode := True;
    Dialog.LoadPerformanceSteps(Pattern,'',PSD,'{}',120); Dialog.Show; Deadline := GetTickCount64+10000;
    repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'repeat editor timeout');
    until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
    for Phase := 0 to 2 do begin
      if Phase=2 then Dialog.InstrumentFrame.Seek(0.4375) else Dialog.InstrumentFrame.Seek(0.0625+Phase*0.125);
      Deadline := GetTickCount64+10000;
      repeat Application.ProcessMessages; Dialog.InstrumentPreview.Poll; Sleep(2); Check(GetTickCount64<Deadline,'reference image timeout'); until not Dialog.InstrumentPreview.Busy;
      Expected[Phase] := Vcl.Graphics.TBitmap.Create; Expected[Phase].Assign(Dialog.InstrumentPreview.PreviewBitmap);
    end;
    FillChar(Seen,SizeOf(Seen),0); Dialog.InstrumentFrame.Seek(0);
    Deadline := GetTickCount64+10000;
    repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'initial reference timeout'); until not Dialog.InstrumentPreview.Busy;
    Previous := Dialog.InstrumentPreview.RenderCount; Changes := 0; CacheBefore := Dialog.InstrumentPreview.CacheHits;
    Start := GetTickCount64; Dialog.InstrumentFrame.PlayButton.Click;
    repeat
      Application.ProcessMessages; Dialog.InstrumentPreview.Poll; Tick := GetTickCount64;
      if Dialog.InstrumentPreview.RenderCount<>Previous then begin
        Previous := Dialog.InstrumentPreview.RenderCount; Inc(Changes); Values := Dialog.InstrumentFrame.PreviewStates;
        Lines.Add(Format('%d ms beat %.4f render %d phase %d',[Tick-Start,Dialog.InstrumentFrame.Position,Previous,Values[0].Stage]));
        Hit := Trunc(Dialog.InstrumentFrame.Position);
        if (Hit>=0) and (Hit<=3) and (Frac(Dialog.InstrumentFrame.Position)<0.5) then
          for Phase := 0 to 2 do begin
            Same := True;
            for Y := 0 to Expected[Phase].Height-1 do if not CompareMem(Expected[Phase].ScanLine[Y],Dialog.InstrumentPreview.PreviewBitmap.ScanLine[Y],Expected[Phase].Width*4) then begin Same := False; Break; end;
            if Same then Seen[Hit,Phase] := True;
          end;
      end;
      Sleep(2);
      Check(Tick-Start<10000,'real clock stalled');
    until Dialog.InstrumentFrame.Position>=3.4;
    Dialog.InstrumentFrame.PlayButton.Click; Lines.SaveToFile(TPath.Combine(Root,'repeat.log')); Writeln(Lines.Text);
    Check(Changes>=8,'short repeated blocks do not animate: only '+IntToStr(Changes)+' frames published');
    for Hit := 0 to 3 do Check(Seen[Hit,1],'strike bitmap missing for repeat '+IntToStr(Hit+1));
    Check(Dialog.InstrumentPreview.CacheHits-CacheBefore>=8,'repeated states still require cold rendering');
    Writeln('PREVIEW_FRAME_REUSES ',Dialog.InstrumentPreview.CacheHits-CacheBefore);
    Writeln('SHORT_REPEATED_BLOCKS_REAL_CLOCK_PREVIEW_NO_AUDIO_OK');
  finally for Phase := 0 to 2 do Expected[Phase].Free; Lines.Free; Dialog.Free; Model.Free; D.Free; end;
end;
procedure ActualPhases(const Root,PSD: string);
var D: TMusicStudioLayerDocument; Model: TMusicStudioInstrumentData; B: TInstrumentBlock;
  States: TArray<TInstrumentState>; S: TInstrumentState; V: TJSONObject; Image,Rest: Vcl.Graphics.TBitmap;
  PNG: TPngImage; R: string; Phase,Y: Integer; Layer: TMusicStudioLayerInfo;
  Dialog: TMusicStudioPatternSettings; Pattern: TMusicStudioPattern; Deadline: UInt64;
begin
  if PSD='' then Exit;
  D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create;
  Image := Vcl.Graphics.TBitmap.Create; Rest := Vcl.Graphics.TBitmap.Create; PNG := TPngImage.Create;
  try
    Check(D.LoadFile(PSD),D.LastError); Model.Load('{"lengthBeats":8,"notes":[]}');
    for R in INSTRUMENT_ACTION_ROWS do begin
      B := Default(TInstrumentBlock); B.Row := R; B.StartBeat := 0; B.EndBeat := 4; B.Stage := 1;
      if R='右手' then B.Choice := 'スネア右側' else if R='左手' then B.Choice := 'スネア中央'
      else if R='右足' then B.Choice := 'バスドラム' else B.Choice := 'ハイハット';
      Check(D.InstrumentRules.HasChoice(R,B.Choice),'actual PSD missing '+R+'/'+B.Choice); Check(Model.PutBlock(-1,B),'actual blocks');
    end;
    for Phase := 0 to 3 do begin
      if Phase=2 then States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,3.5)
      else if Phase<3 then States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,Phase+0.5)
      else States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,100);
      for S in States do if S.LayerScope<>'effect' then Check(S.Stage=Min(Phase,2),'actual PSD phase');
      V := D.InstrumentRules.Visibility(States);
      try
        Check(D.Render(Image,V),D.LastError);
        if Phase=2 then begin
          for Layer in D.Layers do if not Layer.IsGroup and Layer.Path.StartsWith('/演奏エフェクト/') then MusicStudioSetJsonBoolean(V,Layer.Key,False);
          Check(D.Render(Rest,V),D.LastError);
        end;
      finally V.Free; end;
      if Phase=3 then begin
        Check((Image.Width=Rest.Width) and (Image.Height=Rest.Height),'actual held size');
        for Y := 0 to Image.Height-1 do Check(CompareMem(Image.ScanLine[Y],Rest.ScanLine[Y],Image.Width*4),'actual held aftermath pixels');
      end else begin
        PNG.Assign(Image); PNG.SaveToFile(TPath.Combine(Root,'actual-phase-'+IntToStr(Phase)+'.png'));
      end;
    end;
    // パターン設定も同じ3段階を使用する。実PSDを読取だけで開いて確認用画像を残す。
    Dialog := TMusicStudioPatternSettings.Create(nil);
    try Pattern := Default(TMusicStudioPattern); Pattern.Kind := 'performance'; Pattern.Name := '四肢の準備・打撃・余韻';
      Pattern.Color := '#EDBA70'; Pattern.ConfigJSON := Model.JSON; Dialog.SilentVisualMode := True;
      Dialog.LoadPerformanceSteps(Pattern,'',PSD,'{}',120); Dialog.Show; Deadline := GetTickCount64+10000;
      repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'actual editor timeout');
      until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
      Dialog.InstrumentFrame.Seek(2.5); Deadline := GetTickCount64+10000;
      repeat Dialog.InstrumentPreview.Poll; Sleep(2); Check(GetTickCount64<Deadline,'actual preview timeout'); until not Dialog.InstrumentPreview.Busy;
      Image.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(Image.Canvas,0,0); PNG.Assign(Image);
      PNG.SaveToFile(TPath.Combine(Root,'actual-phase-editor.png')); Dialog.Hide;
    finally Dialog.Free; end;
    Writeln('ACTUAL_DRUM_FOUR_LIMBS_0_PREPARE_1_STRIKE_2_AFTERMATH_HOLD_PSD_READ_ONLY_OK');
  finally PNG.Free; Rest.Free; Image.Free; Model.Free; D.Free; end;
end;
procedure RunInstrumentPhaseChecks(const Root,RealPSD: string);
var Art: TArtDocument; Row,Choice,L: TArtLayer; D: TMusicStudioLayerDocument;
  Model,Next: TMusicStudioInstrumentData; Block: TInstrumentBlock; Values: TArray<TInstrumentState>;
  I,J,Stage,Track,Slot,Index: Integer; Path,Error,Before,After: string; Deadline: UInt64;
  P: TMusicStudioPattern; Asset: TMusicStudioPsdAsset; Store: TMusicStudioSharedPsdLibrary;
  Doc: TMusicStudioDocument; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache; Duplicate: Boolean;
  Dialog: TMusicStudioPatternSettings; PNG: TPngImage; Image: Vcl.Graphics.TBitmap; Range: TInstrumentPlaybackRange;
  function Get(const States: TArray<TInstrumentState>; const Name: string): TInstrumentState;
  var S: TInstrumentState;
  begin for S in States do if S.Row=Name then Exit(S); raise Exception.Create('state absent '+Name); end;
  procedure StagesAt(Beat: Double; Expected: Integer);
  var S: TInstrumentState; R: string;
  begin
    Values := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,Beat);
    for R in INSTRUMENT_ACTION_ROWS do begin S := Get(Values,R);
      if (R='左手') and (Expected=2) then Check(S.Stage=0,'no decay must return prepare')
      else Check(S.Stage=Expected,'phase boundary '+R+' beat '+FloatToStr(Beat));
    end;
  end;
  procedure SceneAt(Beat: Double; R0,R1,R2,R3: Byte);
  var B: PByte;
  begin
    Scene.SetPosition(Beat/2,Beat); Deadline := GetTickCount64+10000;
    repeat Scene.PollResults; Check(GetTickCount64<Deadline,'scene timeout'); Sleep(2);
    until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
    B := Scene.ImageForTrack(Track).ScanLine[0];
    Check((B[2]=R0) and (B[6]=R1) and (B[10]=R2) and (B[14]=R3),'scene phases beat '+FloatToStr(Beat));
  end;
begin
  ForceDirectories(Root); Art := TArtDocument.Create;
  try
    Art.Width := 8; Art.Height := 2;
    for I := 0 to 3 do begin
      Row := Art.AddLayer(alkGroup,INSTRUMENT_ACTION_ROWS[I],TArtBounds.Create(0,0,0,0));
      for J := 0 to 1 do begin
        if J=0 then Choice := Art.AddLayer(alkGroup,'*A',TArtBounds.Create(0,0,0,0),Row)
        else Choice := Art.AddLayer(alkGroup,'*B',TArtBounds.Create(0,0,0,0),Row);
        Choice.Visible := J=0;
        for Stage := 0 to 3 do begin
          if (I=1) and (Stage=2) then Continue;
          L := Art.AddLayer(alkImage,'*'+IntToStr(Stage),TArtBounds.Create(I,0,I+1,1),Choice); L.Visible := Stage=3;
          case Stage of 0: L.Pixels := TBytes.Create(50+J*20,10,10,255);
            1: L.Pixels := TBytes.Create(150+J*20,10,10,255);
            2: L.Pixels := TBytes.Create(210+J*20,10,10,255);
            3: L.Pixels := TBytes.Create(10+J*20,10,10,255); end;
        end;
      end;
    end;
    // 同名パターンの別枝に余韻がなくても、その枝の準備を残す。
    Row := Art.AddLayer(alkGroup,'右足',TArtBounds.Create(0,0,0,0));
    Choice := Art.AddLayer(alkGroup,'*A',TArtBounds.Create(0,0,0,0),Row);
    L := Art.AddLayer(alkImage,'*0',TArtBounds.Create(4,0,5,1),Choice); L.Pixels := TBytes.Create(80,10,10,255);
    L := Art.AddLayer(alkImage,'*1',TArtBounds.Create(4,0,5,1),Choice); L.Pixels := TBytes.Create(130,10,10,255); L.Visible := False;
    Path := TPath.Combine(Root,'phases.psd'); WriteNewPsd(Art,Path,pcRaw);
  finally Art.Free; end;
  D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create; Next := TMusicStudioInstrumentData.Create;
  try
    Check(D.LoadFile(Path),D.LastError); Model.Load('{"lengthBeats":8,"notes":[],"future":"keep"}');
    for I := 0 to 3 do begin Block := Default(TInstrumentBlock); Block.Row := INSTRUMENT_ACTION_ROWS[I];
      Block.Choice := 'A'; Block.Stage := 1; Block.StartBeat := 1; Block.EndBeat := 5; Check(Model.PutBlock(-1,Block),'block'); end;
    Before := Model.JSON;
    Check(Length(MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,0.9))=0,'state before first action');
    StagesAt(1,0); StagesAt(2-0.00001,0); StagesAt(2,1); StagesAt(4-0.00001,1); StagesAt(4,2); StagesAt(5,2); StagesAt(100,2); StagesAt(2.5,1);
    Check(Model.JSON=Before,'playback changed saved intervals');
    Block := Default(TInstrumentBlock); Block.Row := '左手'; Block.Choice := 'B'; Block.StartBeat := 6; Block.EndBeat := 7; Block.Stage := 1;
    Check(Model.PutBlock(-1,Block),'alternate'); Values := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,100);
    Check((Get(Values,'左手').Choice='B') and (Get(Values,'左手').Stage=0),'last pattern without decay must hold own preparation');
    Range.Blocks := Model.Blocks.ToArray; Range.StartBeat := 10; Range.EndBeat := 14;
    Values := MusicStudioInstrumentActionStates([Range],D.InstrumentRules,100);
    Check(Get(Values,'左手').Choice='A','block outside shortened clip incorrectly became last pattern');
    Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'PSDAssets')); Doc := TMusicStudioDocument.Create;
    Scene := TMusicStudioPsdSceneCache.Create; Cache := TMusicStudioVisualCache.Create;
    try
      Check(Store.TryImport(Path,'四肢','#EDBA70',Asset,Duplicate,Error),Error); Model.BindAsset(Asset.ID);
      Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance');
      Index := Doc.AddPerformance; P := Doc.PatternAt(Index); P.ConfigJSON := Model.JSON; Doc.UpdatePattern(P);
      Check(Doc.AddBeatPlacement(Track,Slot,P.ID,0,8,Error),Error);
      Next.Load('{"lengthBeats":4,"notes":[]}'); Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'B';
      Block.StartBeat := 0; Block.EndBeat := 2; Block.Stage := 1; Check(Next.PutBlock(-1,Block),'next block');
      Index := Doc.AddPerformance; P := Doc.PatternAt(Index); P.ConfigJSON := Next.JSON; Doc.UpdatePattern(P);
      Check(Doc.AddBeatPlacement(Track,Slot,P.ID,16,4,Error),Error); Scene.Bind(Doc,Store,Cache);
      SceneAt(0.5,10,10,10,10); SceneAt(1.5,50,50,50,50); SceneAt(2.5,150,150,150,150);
      SceneAt(4.5,210,50,210,210); Check(PByte(Scene.ImageForTrack(Track).ScanLine[0])[18]=80,'body without decay vanished when other branch has stage2');
      SceneAt(7.5,210,70,210,210); SceneAt(10,210,70,210,210);
      SceneAt(16.2,70,70,210,210); SceneAt(16.75,170,70,210,210); SceneAt(19,230,70,210,210); SceneAt(100,230,70,210,210);
      SceneAt(2.5,150,150,150,150);
      Dialog := TMusicStudioPatternSettings.Create(nil);
      try
        P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := '準備 → 打撃 → 余韻'; P.Color := '#EDBA70'; P.ConfigJSON := Model.JSON;
        Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(P,Asset.ID,Path,'{}',120); Dialog.Show; Deadline := GetTickCount64+10000;
        repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'editor timeout');
        until (Dialog.InstrumentFrame<>nil) and (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
        Dialog.InstrumentFrame.Seek(7.5); Deadline := GetTickCount64+10000;
        repeat Dialog.InstrumentPreview.Poll; Sleep(2); Check(GetTickCount64<Deadline,'editor render timeout'); until not Dialog.InstrumentPreview.Busy;
        SceneAt(7.5,210,70,210,210); Image := Dialog.InstrumentPreview.PreviewBitmap;
        Check(CompareMem(Image.ScanLine[0],Scene.ImageForTrack(Track).ScanLine[0],Image.Width*4),'editor and scene differ');
        PNG := TPngImage.Create; Image := Vcl.Graphics.TBitmap.Create;
        try Image.SetSize(Dialog.ClientWidth,Dialog.ClientHeight); Dialog.PaintTo(Image.Canvas,0,0); PNG.Assign(Image); PNG.SaveToFile(TPath.Combine(Root,'phase-editor.png'));
        finally Image.Free; PNG.Free; end;
        Dialog.Hide;
      finally Dialog.Free; end;
      Check(Doc.TrySave(After,Error),Error); TFile.WriteAllText(TPath.Combine(Root,'phase-project.json'),After);
    finally Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    Writeln('FOUR_LIMBS_25_50_25_DOUBLE_STRIKE_DECAY_LAST_PATTERN_HOLD_CLIP_GAPS_SEEK_EDITOR_SCENE_NO_AUDIO_OK');
  finally Next.Free; Model.Free; D.Free; end;
  ActualPhases(Root,RealPSD);
end;
procedure RunInstrumentResonanceChecks(const Root,PSD: string);
const Beats: array[0..10] of Double = (0,0.15,0.35,0.55,0.75,0.95,1.15,1.35,1.55,1.75,3);
var D: TMusicStudioLayerDocument; Model,Retrigger: TMusicStudioInstrumentData; Block: TInstrumentBlock;
  States: TArray<TInstrumentState>; State: TInstrumentState; Ranges: TArray<TInstrumentPlaybackRange>;
  Store: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset; Duplicate: Boolean;
  Doc: TMusicStudioDocument; Scene: TMusicStudioPsdSceneCache; Cache: TMusicStudioVisualCache;
  Pattern: TMusicStudioPattern; Dialog: TMusicStudioPatternSettings; Expected,Previous: Vcl.Graphics.TBitmap;
  V: TJSONObject; PNG: TPngImage; Before,Error,ProjectJSON: string; Track,Slot,Index,I,Stage,PreviousRender,Changes: Integer;
  Deadline,Started: UInt64; Seen: array[1..9] of Boolean; Lines: TStringList; Layer: TMusicStudioLayerInfo;
  FixedIndex,RearIndex: Integer;
  Video: TMusicStudioVideoSession; Pixels: TMusicStudioVideoPixels; Image: Vcl.Graphics.TBitmap;
  Beat: Double; X,Y: Integer; Row: PByte;
  ExpectedFrames: TObjectDictionary<string,Vcl.Graphics.TBitmap>; ExpectedFrame: Vcl.Graphics.TBitmap; FrameKey: string;
  function StateKey(const Values: TArray<TInstrumentState>): string;
  var Value: TInstrumentState;
  begin
    Result := '';
    for Value in Values do Result := Result+Value.Row+'|'+Value.Choice+'|'+Value.LayerScope+'|'+IntToStr(Value.Stage)+';';
  end;
  function SamePixels(A,B: Vcl.Graphics.TBitmap): Boolean;
  var Y: Integer;
  begin
    Result := (A<>nil) and (B<>nil) and (A.Width=B.Width) and (A.Height=B.Height); if not Result then Exit;
    for Y := 0 to A.Height-1 do if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
  end;
  function ResonanceAt(Beat: Double; const Blocks: TArray<TInstrumentBlock>): TInstrumentState;
  var S: TInstrumentState;
  begin
    Result := Default(TInstrumentState); Result.Stage := -1;
    for S in MusicStudioInstrumentPlaybackStates(Blocks,D.InstrumentRules,Beat) do
      if S.LayerScope='resonance' then Exit(S);
  end;
  procedure RenderStates(const Values: TArray<TInstrumentState>);
  begin
    V := D.InstrumentRules.Visibility(Values);
    try Check(D.Render(Expected,V,512),D.LastError); finally V.Free; end;
  end;
  procedure SceneAt(Beat: Double; SaveFrame: Integer = -1);
  begin
    States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,Beat); RenderStates(States);
    Scene.SetPosition(Beat/2,Beat); Deadline := GetTickCount64+10000;
    repeat Scene.PollResults; Sleep(2); Check(GetTickCount64<Deadline,'resonance scene timeout');
    until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
    Check(SamePixels(Expected,Scene.ImageForTrack(Track)),'resonance scene differs at '+FloatToStr(Beat));
    if SaveFrame>=0 then begin PNG.Assign(Expected); PNG.SaveToFile(TPath.Combine(Root,Format('resonance-%.2d.png',[SaveFrame]))); end;
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Model := TMusicStudioInstrumentData.Create;
  Retrigger := TMusicStudioInstrumentData.Create; Expected := Vcl.Graphics.TBitmap.Create; Previous := Vcl.Graphics.TBitmap.Create;
  PNG := TPngImage.Create; Lines := TStringList.Create;
  ExpectedFrames := TObjectDictionary<string,Vcl.Graphics.TBitmap>.Create([doOwnsValues]);
  try
    Check(D.LoadFile(PSD),D.LastError); Check(D.InstrumentRules.RowCount=4,'resonance added a UI row');
    Check(D.InstrumentRules.HasResonanceChoice('右手','クラッシュ'),'crash resonance missing');
    Check(D.InstrumentRules.HasResonanceChoice('右手','クラッシュ（エフェクト付き）'),'FX resonance missing');
    Check(not D.InstrumentRules.HasResonanceChoice('右手','スネア中央'),'snare became resonant');
    Check(Length(D.InstrumentRules.ResonanceStages('右手','クラッシュ'))=10,'expected ten physical stages');
    FixedIndex := -1; RearIndex := -1;
    for I := 0 to High(D.Layers) do begin Layer := D.Layers[I];
      if Layer.Path='/固定パーツ' then FixedIndex := I; if Layer.Path='/楽器余韻' then RearIndex := I; end;
    Check((FixedIndex>=0) and (RearIndex>FixedIndex),'cymbal is not behind drum body');
    Model.Load('{"lengthBeats":4,"notes":[],"future":"keep"}');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'クラッシュ';
    Block.StartBeat := 0; Block.EndBeat := 0.4; Block.Stage := 1; Check(Model.PutBlock(-1,Block),'crash interval');
    Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'スネア中央';
    Block.StartBeat := 0.8; Block.EndBeat := 1.2; Block.Stage := 1; Check(Model.PutBlock(-1,Block),'following snare');
    Block := Default(TInstrumentBlock); Block.Row := '左足'; Block.Choice := 'ハイハット';
    Block.StartBeat := 2; Block.EndBeat := 2.4; Block.Stage := 1; Check(Model.PutBlock(-1,Block),'later limb extends loop beyond cymbal decay');
    Before := Model.JSON;
    Check(ResonanceAt(0.09,Model.Blocks.ToArray).Stage=-1,'vibration started before strike');
    Check(ResonanceAt(0.10,Model.Blocks.ToArray).Stage=1,'strike onset');
    Check(ResonanceAt(0.299999,Model.Blocks.ToArray).Stage=1,'strike duration');
    for I := 2 to 9 do begin
      State := ResonanceAt(0.30+(I-2)*0.20,Model.Blocks.ToArray);
      Check(State.Stage=I,'decay boundary '+IntToStr(I));
    end;
    Check(ResonanceAt(10000000,Model.Blocks.ToArray).Stage=9,'settled/long seek');
    States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,0.85);
    Check((States[0].Choice='スネア中央') and (States[0].LayerScope='body'),'arm did not change independently');
    Check(ResonanceAt(0.85,Model.Blocks.ToArray).Choice='クラッシュ','snare cancelled cymbal vibration');
    SetLength(Ranges,1); Ranges[0].Blocks := Model.Blocks.ToArray; Ranges[0].StartBeat := 0; Ranges[0].EndBeat := 0.08;
    States := MusicStudioInstrumentActionStates(Ranges,D.InstrumentRules,1);
    for State in States do Check(State.LayerScope<>'resonance','clipped pre-strike interval resonated');
    Ranges[0].EndBeat := 0.2; States := MusicStudioInstrumentActionStates(Ranges,D.InstrumentRules,0.65);
    Stage := -1;
    for State in States do begin
      if State.LayerScope='resonance' then Stage := State.Stage;
      if State.LayerScope='effect' then Check(State.Stage=-1,'effect outlived clipped interval');
    end;
    Check(Stage=3,'clip end cancelled decay');
    Retrigger.Load(Model.JSON); Block := Default(TInstrumentBlock); Block.Row := '右手'; Block.Choice := 'クラッシュ（エフェクト付き）';
    Block.StartBeat := 1.2; Block.EndBeat := 1.6; Block.Stage := 1; Check(Retrigger.PutBlock(-1,Block),'repeat strike');
    Check(ResonanceAt(1.25,Retrigger.Blocks.ToArray).Choice='クラッシュ','preparation cancelled prior hit');
    State := ResonanceAt(1.3,Retrigger.Blocks.ToArray);
    Check((State.Choice=Block.Choice) and (State.Stage=1),'repeat strike did not restart decay');
    Check(Model.JSON=Before,'evaluation changed saved intervals');
    Store := TMusicStudioSharedPsdLibrary.Create(TPath.Combine(Root,'PSDAssets')); Doc := TMusicStudioDocument.Create;
    Scene := TMusicStudioPsdSceneCache.Create; Cache := TMusicStudioVisualCache.Create;
    try
      Check(Store.TryImport(PSD,'クラッシュ余韻','#EDBA70',Asset,Duplicate,Error),Error);
      Check(Doc.TryLoad('',Error),Error); Track := Doc.AddTrack('psd'); Doc.AssignPsd(Track,Asset.ID); Slot := Doc.AddSlot(Track,'performance');
      Index := Doc.AddPerformance; Pattern := Doc.PatternAt(Index); Pattern.ConfigJSON := Model.JSON; Doc.UpdatePattern(Pattern);
      Check(Doc.AddBeatPlacement(Track,Slot,Pattern.ID,0,4,Error),Error); Scene.Bind(Doc,Store,Cache);
      for I := Low(Beats) to High(Beats) do SceneAt(Beats[I],I);
      SceneAt(0.45); Previous.Assign(Expected); SceneAt(0.65); Check(not SamePixels(Previous,Expected),'vibration does not move');
      SceneAt(4.5); Previous.Assign(Expected); SceneAt(5); Check(SamePixels(Previous,Expected),'settled image not stable');
      SceneAt(0.45); Check(Doc.TrySave(ProjectJSON,Error),Error); TFile.WriteAllText(TPath.Combine(Root,'resonance-project.json'),ProjectJSON);
      Dialog := TMusicStudioPatternSettings.Create(nil);
      try
        Pattern := Default(TMusicStudioPattern); Pattern.Kind := 'performance'; Pattern.Name := 'クラッシュ余韻'; Pattern.Color := '#EDBA70'; Pattern.ConfigJSON := Model.JSON;
        Dialog.SilentVisualMode := True; Dialog.LoadPerformanceSteps(Pattern,Asset.ID,PSD,'{}',120); Dialog.Show; Deadline := GetTickCount64+10000;
        repeat Application.ProcessMessages; Sleep(2); Check(GetTickCount64<Deadline,'resonance editor timeout');
        until (Dialog.InstrumentPreview<>nil) and not Dialog.InstrumentPreview.Busy;
        for I := 1 to 9 do begin
          SceneAt(Beats[I]); Dialog.InstrumentFrame.Seek(Beats[I]); Deadline := GetTickCount64+10000;
          repeat Application.ProcessMessages; Dialog.InstrumentPreview.Poll; Sleep(2); Check(GetTickCount64<Deadline,'resonance preview timeout'); until not Dialog.InstrumentPreview.Busy;
          Check(SamePixels(Expected,Dialog.InstrumentPreview.PreviewBitmap),'editor/scene resonance differ');
        end;
        // Prepare references before the live clock; verifying a published frame
        // must not itself perform a second PSD composition on the UI thread.
        for I := 0 to 219 do begin
          States := MusicStudioInstrumentPlaybackStates(Model.Blocks.ToArray,D.InstrumentRules,I/100);
          FrameKey := StateKey(States);
          if not ExpectedFrames.ContainsKey(FrameKey) then begin
            RenderStates(States); ExpectedFrame := Vcl.Graphics.TBitmap.Create;
            try ExpectedFrame.Assign(Expected); ExpectedFrames.Add(FrameKey,ExpectedFrame); ExpectedFrame := nil;
            finally ExpectedFrame.Free; end;
          end;
        end;
        FillChar(Seen,SizeOf(Seen),0); Changes := 0; Dialog.InstrumentFrame.Seek(0); Deadline := GetTickCount64+10000;
        repeat Application.ProcessMessages; Dialog.InstrumentPreview.Poll; Sleep(2); Check(GetTickCount64<Deadline,'resonance initial timeout'); until not Dialog.InstrumentPreview.Busy;
        PreviousRender := Dialog.InstrumentPreview.RenderCount; Started := GetTickCount64; Dialog.InstrumentFrame.PlayButton.Click;
        repeat
          Application.ProcessMessages; Dialog.InstrumentPreview.Poll;
          if PreviousRender<>Dialog.InstrumentPreview.RenderCount then begin
            PreviousRender := Dialog.InstrumentPreview.RenderCount; Inc(Changes); States := Dialog.InstrumentFrame.PreviewStates;
            if ExpectedFrames.TryGetValue(StateKey(States),ExpectedFrame) then Expected.Assign(ExpectedFrame) else RenderStates(States);
            if SamePixels(Expected,Dialog.InstrumentPreview.PreviewBitmap) then
              for State in States do if (State.LayerScope='resonance') and (State.Stage>=1) and (State.Stage<=9) then begin
                Seen[State.Stage] := True; Lines.Add(Format('%d ms stage %d',[GetTickCount64-Started,State.Stage])); end;
          end;
          Sleep(2); Check(GetTickCount64-Started<10000,'resonance real clock stalled');
        until Dialog.InstrumentFrame.Position>=2.2;
        Dialog.InstrumentFrame.PlayButton.Click; Dialog.Hide;
        Lines.SaveToFile(TPath.Combine(Root,'resonance-realtime.log')); Writeln(Lines.Text);
        Check(Changes>=9,'too few resonance images published');
        for Stage := 1 to 9 do Check(Seen[Stage],'real clock did not publish resonance '+IntToStr(Stage));
      finally Dialog.Free; end;
      Video := TMusicStudioVideoSession.Create(Store.Root);
      try
        Scene.MaximumImageDimension := 0; Scene.Bind(Doc,Store,Cache);
        for Beat in TArray<Double>.Create(0.15,0.55,0.95,1.35,1.75,3.0,0.55) do begin
          Scene.SetPosition(Beat/2,Beat); Deadline := GetTickCount64+15000;
          repeat Scene.PollResults; Sleep(2); Check(GetTickCount64<Deadline,'native resonance scene timeout');
          until (Scene.ActiveLoadJobs=0) and (Scene.ActiveRenderJobs=0) and (Scene.ImageForTrack(Track)<>nil);
          Image := Scene.ImageForTrack(Track);
          Check(Video.Render(ProjectJSON,Beat/2,Image.Width,Image.Height,Pixels,Error),Error);
          for Y := 0 to Image.Height-1 do begin Row := Image.ScanLine[Y]; for X := 0 to Image.Width-1 do
            Check((Pixels[Y*Image.Width+X].R=Row[X*4+2]) and (Pixels[Y*Image.Width+X].G=Row[X*4+1]) and
              (Pixels[Y*Image.Width+X].B=Row[X*4]) and (Pixels[Y*Image.Width+X].A=Row[X*4+3]),'video/scene resonance differs'); end;
        end;
      finally Video.Free; end;
    finally Scene.Free; Cache.Free; Doc.Free; Store.Free; end;
    Writeln('CRASH_PIVOT_DECAY_OTHER_ARM_RETRIGGER_CLIPPED_HIT_REVERSE_SEEK_EDITOR_SCENE_REAL_CLOCK_NO_AUDIO_OK');
  finally ExpectedFrames.Free; Lines.Free; PNG.Free; Previous.Free; Expected.Free; Retrigger.Free; Model.Free; D.Free; end;
end;
end.
