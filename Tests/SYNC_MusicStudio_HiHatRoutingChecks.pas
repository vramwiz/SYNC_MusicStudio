unit SYNC_MusicStudio_HiHatRoutingChecks;

// 実素材/保存済み区間を読取のみで照合し、足の切替が他の手足を変えないことを検証する。
interface
procedure RunHiHatRoutingChecks(const Root,PSD,PerformanceJSON,BaseJSON: string);
procedure BuildHiHatPedalCandidate(const Root,PSD: string);
procedure RunBassAssignmentChecks(const Root,PSD,PerformanceJSON,BaseJSON: string; ExpectMotion: Boolean);
procedure BuildBassPedalCandidate(const Root,PSD: string);
implementation
uses System.SysUtils, System.IOUtils, System.Types, System.JSON, System.Math, System.Generics.Collections,
  Vcl.Graphics, Vcl.Imaging.pngimage, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd, SYNC_MusicStudio_ArtLayerName,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_InstrumentRules, SYNC_MusicStudio_InstrumentData,
  SYNC_MusicStudio_PsdLayerConfig;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create('HIHAT_ROUTING: '+Text); end;
procedure BuildBassPedalCandidate(const Root,PSD: string);
var Original,Edited,Saved: TArtDocument; Pedal,Foot: TArtLayer; Patterns: TList<TArtLayer>;
  G,L,Pattern: TArtLayer; Pixels: TBytes; Bounds: TArtBounds; Stage,Lift,X,Y,C,P,Y0,Y1: Integer;
  SY,F,A,Color: Double; Name,Target: string; Image: TBitmap; PNG: TPngImage;
  D: TMusicStudioLayerDocument; S: TInstrumentState; V: TJSONObject;
  procedure Find(List: TList<TArtLayer>; const Parent: string);
  var Item: TArtLayer; Path: string;
  begin
    for Item in List do begin Path := Parent+'/'+ParseLayerName(Item.Name).DisplayName;
      if Item.Name='バスドラムペダル' then begin Check(Pedal=nil,'duplicate fixed pedal'); Pedal := Item; end;
      if Path.Contains('/右足/') and (Item.Kind=alkGroup) and ParseLayerName(Item.Name).DisplayName.StartsWith('バスドラム') then Patterns.Add(Item);
      Find(Item.Children,Path);
    end;
  end;
  procedure SameNames(A,B: TList<TArtLayer>);
  var I: Integer;
  begin Check(A.Count=B.Count,'bass hierarchy'); for I := 0 to A.Count-1 do begin
    Check(A[I].Name=B[I].Name,'bass names'); SameNames(A[I].Children,B[I].Children); end;
  end;
begin
  ForceDirectories(Root); Original := ReadPsd(PSD); Edited := Original.Clone; Saved := nil; Patterns := TList<TArtLayer>.Create;
  try
    Pedal := nil; Find(Edited.Roots,''); Check((Pedal<>nil) and (Patterns.Count=3),'bass source tree');
    Check((Pedal.Bounds.Width=56) and (Pedal.Bounds.Height=72) and not Pedal.HasMask,'pedal source geometry');
    Pedal.Visible := False;
    for Stage := 0 to 4 do begin
      case Stage of 0: begin Lift := 8; Name := 'ペダル_準備'; end;
        1: begin Lift := 0; Name := 'ペダル_踏み込み'; end;
        else begin Lift := 4; Name := 'ペダル_余韻'; end; end;
      Bounds := TArtBounds.Create(776,824-Lift,832,896); SetLength(Pixels,56*(72+Lift)*4);
      for Y := 0 to Bounds.Height-1 do begin
        if Y<60+Lift then SY := Y*60/(60+Lift) else SY := Y-Lift;
        Y0 := Floor(SY); Y1 := Min(71,Y0+1); F := SY-Y0;
        for X := 0 to 55 do begin P := (Y*56+X)*4;
          A := Pedal.Pixels[(Y0*56+X)*4+3]*(1-F)+Pedal.Pixels[(Y1*56+X)*4+3]*F; Pixels[P+3] := EnsureRange(Round(A),0,255);
          for C := 0 to 2 do begin Color := Pedal.Pixels[(Y0*56+X)*4+C]*Pedal.Pixels[(Y0*56+X)*4+3]*(1-F)+Pedal.Pixels[(Y1*56+X)*4+C]*Pedal.Pixels[(Y1*56+X)*4+3]*F;
            if A>0 then Pixels[P+C] := EnsureRange(Round(Color/A),0,255) else Pixels[P+C] := 0;
          end;
        end;
      end;
      PNG := TPngImage.CreateBlank(COLOR_RGBALPHA,8,Bounds.Width,Bounds.Height);
      try for Y := 0 to Bounds.Height-1 do for X := 0 to 55 do begin P := (Y*56+X)*4;
        PByte(PNG.Scanline[Y])[X*3] := Pixels[P+2]; PByte(PNG.Scanline[Y])[X*3+1] := Pixels[P+1];
        PByte(PNG.Scanline[Y])[X*3+2] := Pixels[P]; PByte(PNG.AlphaScanline[Y])[X] := Pixels[P+3];
      end; PNG.SaveToFile(TPath.Combine(Root,'pedal-'+IntToStr(Stage)+'.png')); finally PNG.Free; end;
      for Pattern in Patterns do begin G := nil;
        for L in Pattern.Children do if L.Name='*'+IntToStr(Stage) then G := L;
        Check(G<>nil,'missing bass stage'); Check(G.Children.Count>0,'missing foot before pedal'); Foot := G.Children[0];
        Check(Foot.Kind=alkImage,'foot type'); L := Edited.AddLayer(alkImage,Name,Bounds,G); L.Pixels := Copy(Pixels);
      end;
    end;
    Target := TPath.Combine(Root,'東北きりたん_ドラム.psd'); Check(not SameText(Target,PSD),'candidate equals source');
    if TFile.Exists(Target) then begin Saved := ReadPsd(Target); SameNames(Edited.Roots,Saved.Roots);
      Check(SameArtDocumentVisualContent(Edited,Saved),'saved pedal PSD differs from expected pixels/tree/attributes');
      D := TMusicStudioLayerDocument.Create; Image := TBitmap.Create; PNG := TPngImage.Create;
      try Check(D.LoadFile(Target),D.LastError); for Stage := 0 to 2 do begin
        S := Default(TInstrumentState); S.Row := '右足'; S.Choice := 'バスドラム'; S.Stage := Stage; V := D.InstrumentRules.Visibility([S]);
        try Check(D.Render(Image,V),D.LastError); PNG.Assign(Image); PNG.SaveToFile(TPath.Combine(Root,'stage-'+IntToStr(Stage)+'.png')); finally V.Free; end;
      end; finally PNG.Free; Image.Free; D.Free; end;
      Writeln('BASS_PEDAL_THREE_PATTERNS_FIVE_STAGES_15_LAYERS_OTHER_PIXELS_TREE_DEFAULTS_PRESERVED_OK');
    end;
  finally Patterns.Free; Saved.Free; Edited.Free; Original.Free; end;
end;
procedure BuildHiHatPedalCandidate(const Root,PSD: string);
var Original,Edited,Reloaded: TArtDocument; Pattern,Stage0,Stage1,Foot0,Foot1,G,L: TArtLayer;
  Prepared,Pressed,Middle: TBytes; PreparedBounds,PressedBounds: TArtBounds; N,X,Y,C,P,Y0,Y1: Integer;
  SY,F,A,Color: Double; Target: string;
  procedure Find(List: TList<TArtLayer>; const Parent: string);
  var Item: TArtLayer; Path: string;
  begin
    for Item in List do begin Path := Parent+'/'+ParseLayerName(Item.Name).DisplayName;
      if Path.EndsWith('/左足/ハイハット') then begin Check(Pattern=nil,'ambiguous hi-hat pattern'); Pattern := Item; end;
      Find(Item.Children,Path);
    end;
  end;
  procedure WritePNG(const Name: string; const Bounds: TArtBounds; const Pixels: TBytes);
  var PNG: TPngImage; X,Y,P: Integer; Row,Alpha: PByte;
  begin
    PNG := TPngImage.CreateBlank(COLOR_RGBALPHA,8,Bounds.Width,Bounds.Height);
    try for Y := 0 to Bounds.Height-1 do begin Row := PNG.Scanline[Y]; Alpha := PByte(PNG.AlphaScanline[Y]);
      for X := 0 to Bounds.Width-1 do begin P := (Y*Bounds.Width+X)*4; Row[X*3] := Pixels[P+2]; Row[X*3+1] := Pixels[P+1]; Row[X*3+2] := Pixels[P]; Alpha[X] := Pixels[P+3]; end;
    end; PNG.SaveToFile(TPath.Combine(Root,Name)); finally PNG.Free; end;
  end;
  procedure SameNames(A,B: TList<TArtLayer>);
  var I: Integer;
  begin Check(A.Count=B.Count,'pedal hierarchy mismatch'); for I := 0 to A.Count-1 do begin
    Check(A[I].Name=B[I].Name,'pedal name mismatch'); SameNames(A[I].Children,B[I].Children); end;
  end;
begin
  ForceDirectories(Root); Original := ReadPsd(PSD); Edited := Original.Clone; Reloaded := nil;
  try
    Pattern := nil; Find(Edited.Roots,''); Check((Pattern<>nil) and (Pattern.Children.Count=2),'expected old two-stage hi-hat');
    Stage0 := Pattern.Children[0]; Stage1 := Pattern.Children[1];
    Check((Stage0.Name='*0') and (Stage1.Name='*1') and (Stage0.Children.Count=1) and (Stage1.Children.Count=1),'unexpected pedal tree');
    Foot0 := Stage0.Children[0]; Foot1 := Stage1.Children[0];
    Check((Foot0.Name='足_閉じ') and (Foot1.Name='足_開き'),'unexpected pedal image names');
    Pressed := Copy(Foot0.Pixels); PressedBounds := Foot0.Bounds; Prepared := Copy(Foot1.Pixels); PreparedBounds := Foot1.Bounds;
    Check((PressedBounds.Width=146) and (PressedBounds.Height=235),'unexpected pressed image'); Middle := Copy(Pressed);
    for Y := 0 to 234 do begin
      if Y<=72 then SY := Y else if Y<142 then SY := 72+(Y-72)*78/70 else SY := Y+8;
      for X := 0 to 145 do begin P := (Y*146+X)*4;
        if SY>234 then begin FillChar(Middle[P],4,0); Continue; end;
        Y0 := Floor(SY); Y1 := Min(234,Y0+1); F := SY-Y0; A := Pressed[(Y0*146+X)*4+3]*(1-F)+Pressed[(Y1*146+X)*4+3]*F;
        Middle[P+3] := EnsureRange(Round(A),0,255);
        for C := 0 to 2 do begin Color := Pressed[(Y0*146+X)*4+C]*Pressed[(Y0*146+X)*4+3]*(1-F)+Pressed[(Y1*146+X)*4+C]*Pressed[(Y1*146+X)*4+3]*F;
          if A>0 then Middle[P+C] := EnsureRange(Round(Color/A),0,255) else Middle[P+C] := 0;
        end;
      end;
    end;
    WritePNG('prepared.png',PreparedBounds,Prepared); WritePNG('pressed.png',PressedBounds,Pressed); WritePNG('idle.png',PressedBounds,Middle);
    Foot0.Pixels := Prepared; Foot0.Bounds := PreparedBounds; Foot0.Name := '足_準備'; Stage0.Visible := False;
    Foot1.Pixels := Pressed; Foot1.Bounds := PressedBounds; Foot1.Name := '足_踏み込み'; Stage1.Visible := False;
    for N := 2 to 4 do begin
      G := Edited.AddLayer(alkGroup,'*'+IntToStr(N),TArtBounds.Create(0,0,0,0),Pattern); G.Visible := N=3;
      L := Edited.AddLayer(alkImage,'足_待機中間',PressedBounds,G); L.Pixels := Copy(Middle);
    end;
    Target := TPath.Combine(Root,'東北きりたん_ドラム.psd');
    Check(not SameText(TPath.GetFullPath(Target),TPath.GetFullPath(PSD)),'candidate must differ');
    if TFile.Exists(Target) then begin Reloaded := ReadPsd(Target); SameNames(Edited.Roots,Reloaded.Roots);
      Check(SameArtDocumentVisualContent(Edited,Reloaded),'pedal saved visual content mismatch');
      Writeln('HIHAT_PREPARE_0_STRIKE_1_REST_2_3_4_DEFAULT_3_OTHER_LAYERS_PRESERVED_OK');
    end;
    if not TFile.Exists(TPath.Combine(Root,'before.psd')) then TFile.Copy(PSD,TPath.Combine(Root,'before.psd'),False);
  finally Reloaded.Free; Edited.Free; Original.Free; end;
end;
procedure RunHiHatRoutingChecks(const Root,PSD,PerformanceJSON,BaseJSON: string);
var D: TMusicStudioLayerDocument; Data: TMusicStudioInstrumentData; A,B: TBitmap; PNG: TPngImage;
  Base: TJSONObject; States,WithoutFoot,WithFoot: TArray<TInstrumentState>; S: TInstrumentState;
  Beat: Double; I,X,Y,Count,Outside: Integer; P,Q: PByte; Bounds: TRect;
  procedure Render(Image: TBitmap; const Values: TArray<TInstrumentState>);
  var V,C: TJSONObject; Pair: TJSONPair;
  begin
    V := BuildMusicStudioPsdOverrides(D,Base,-1); C := D.InstrumentRules.Visibility(Values);
    try
      for Pair in C do MusicStudioSetJsonBoolean(V,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
      Check(D.Render(Image,V),D.LastError);
    finally C.Free; V.Free; end;
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Data := TMusicStudioInstrumentData.Create;
  A := TBitmap.Create; B := TBitmap.Create; PNG := TPngImage.Create; Base := nil;
  try
    Check(D.LoadFile(PSD),D.LastError); Data.Load(TFile.ReadAllText(PerformanceJSON)); Base := ParseMusicStudioPsdConfig(TFile.ReadAllText(BaseJSON));
    for Beat in TArray<Double>.Create(1.2,1.3,1.6,2.3,3.3) do begin
      States := Data.StatesAt(Beat); WithoutFoot := nil;
      for S in States do if S.Row<>'左足' then WithoutFoot := WithoutFoot+[S];
      Render(A,WithoutFoot);
      for I := 0 to 1 do begin
        S := Default(TInstrumentState); S.Row := '左足'; S.Choice := 'ハイハット'; S.Stage := I;
        WithFoot := WithoutFoot+[S]; Render(B,WithFoot); Count := 0; Outside := 0; Bounds := Rect(A.Width,A.Height,0,0);
        for Y := 0 to A.Height-1 do begin P := A.ScanLine[Y]; Q := B.ScanLine[Y];
          for X := 0 to A.Width-1 do if not CompareMem(@P[X*4],@Q[X*4],4) then begin
            Inc(Count); if not PtInRect(Rect(1026,632,1174,974),Point(X,Y)) then Inc(Outside);
            if X<Bounds.Left then Bounds.Left := X; if Y<Bounds.Top then Bounds.Top := Y;
            if X>=Bounds.Right then Bounds.Right := X+1; if Y>=Bounds.Bottom then Bounds.Bottom := Y+1;
          end;
        end;
        Writeln(Format('BEAT %.2f LEFT_FOOT_STAGE %d DIFFERENCE %d OUTSIDE_FOOT %d BOUNDS %d,%d,%d,%d',
          [Beat,I,Count,Outside,Bounds.Left,Bounds.Top,Bounds.Right,Bounds.Bottom]));
        Check(Outside=0,'left foot changed left hand or another part');
        if I=1 then Check(Count>0,'open foot did not change');
        PNG.Assign(B); PNG.SaveToFile(TPath.Combine(Root,Format('beat-%.2f-foot-%d.png',[Beat,I])));
      end;
    end;
    Writeln('ACTUAL_PSD_MIXED_ROWS_LEFT_FOOT_ONLY_CHANGES_FOOT_OK');
  finally Base.Free; PNG.Free; B.Free; A.Free; Data.Free; D.Free; end;
end;
procedure RunBassAssignmentChecks(const Root,PSD,PerformanceJSON,BaseJSON: string; ExpectMotion: Boolean);
var D: TMusicStudioLayerDocument; Art: TArtDocument; Foot: TArtLayer; Data: TMusicStudioInstrumentData;
  A,B,C: TBitmap; PNG: TPngImage; Base: TJSONObject; States,WithoutFoot: TArray<TInstrumentState>;
  S: TInstrumentState; Beat: Double; X,Y,Count,Px,PY,MaskCount,MaxAlpha,BoxCount: Integer; P,Q: PByte;
  procedure Find(List: TList<TArtLayer>; const Parent: string);
  var Item: TArtLayer; Path: string;
  begin
    for Item in List do begin Path := Parent+'/'+ParseLayerName(Item.Name).DisplayName;
      if Path.EndsWith('/右足/バスドラム/1/足_踏み込み') then Foot := Item;
      Find(Item.Children,Path);
    end;
  end;
  procedure Render(Image: TBitmap; const Values: TArray<TInstrumentState>);
  var V,C: TJSONObject; Pair: TJSONPair;
  begin
    V := BuildMusicStudioPsdOverrides(D,Base,-1); C := D.InstrumentRules.Visibility(Values);
    try for Pair in C do MusicStudioSetJsonBoolean(V,Pair.JsonString.Value,TJSONBool(Pair.JsonValue).AsBoolean);
      Check(D.Render(Image,V),D.LastError);
    finally C.Free; V.Free; end;
  end;
begin
  ForceDirectories(Root); D := TMusicStudioLayerDocument.Create; Art := nil; Base := nil; Data := TMusicStudioInstrumentData.Create;
  A := TBitmap.Create; B := TBitmap.Create; C := TBitmap.Create; PNG := TPngImage.Create;
  try
    Check(D.LoadFile(PSD),D.LastError); Art := ReadPsd(PSD); Foot := nil; Find(Art.Roots,''); Check(Foot<>nil,'bass strike mask missing');
    MaskCount := 0; MaxAlpha := 0;
    for Y := 0 to Foot.Bounds.Height-1 do for X := 0 to Foot.Bounds.Width-1 do begin
      Px := Foot.Pixels[(Y*Foot.Bounds.Width+X)*4+3]; if Px>=240 then Inc(MaskCount); if Px>MaxAlpha then MaxAlpha := Px;
    end;
    Writeln(Format('BASS_MASK %dx%d BOUNDS %d,%d SOLID %d MAX_ALPHA %d',[Foot.Bounds.Width,Foot.Bounds.Height,Foot.Bounds.Left,Foot.Bounds.Top,MaskCount,MaxAlpha]));
    Data.Load(TFile.ReadAllText(PerformanceJSON)); Base := ParseMusicStudioPsdConfig(TFile.ReadAllText(BaseJSON));
    for Beat in TArray<Double>.Create(0.25,1.25,2.25,3.25) do begin
      States := Data.StatesAt(Beat); WithoutFoot := nil;
      for S in States do if S.Row<>'右足' then WithoutFoot := WithoutFoot+[S];
      Render(A,WithoutFoot); Render(B,States); Count := 0; BoxCount := 0;
      for Y := 0 to Foot.Bounds.Height-1 do begin
        PY := Foot.Bounds.Top+Y; P := A.ScanLine[PY]; Q := B.ScanLine[PY];
        for X := 0 to Foot.Bounds.Width-1 do begin
          Px := Foot.Bounds.Left+X; if not CompareMem(@P[Px*4],@Q[Px*4],4) then begin
            Inc(BoxCount); if Foot.Pixels[(Y*Foot.Bounds.Width+X)*4+3]>=240 then Inc(Count);
          end;
        end;
      end;
      Writeln(Format('BASS_BEAT %.2f SOLID_FOOT_DIFFERENCE %d FOOT_BOX_DIFFERENCE %d',[Beat,Count,BoxCount]));
      if ExpectMotion then Check(Count>0,'registered bass still matches idle');
      C.PixelFormat := pf32bit; C.SetSize(240,330); C.Canvas.CopyRect(Rect(0,0,240,330),B.Canvas,Rect(680,590,920,920));
      PNG.Assign(C); PNG.SaveToFile(TPath.Combine(Root,Format('bass-%.2f.png',[Beat])));
    end;
    Writeln('BASS_ASSIGNMENT_TEST_COMPLETE');
  finally PNG.Free; C.Free; B.Free; A.Free; Data.Free; Base.Free; Art.Free; D.Free; end;
end;
end.
