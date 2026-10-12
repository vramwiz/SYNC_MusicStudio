unit SYNC_MusicStudio_PerformanceCacheChecks;

// 演奏描画の拍→秒・音域fit・crop・LRU・解析/タイル再利用を無音で検証する。
// 作品JSON以外のファイル参照や音声/楽譜/PSD解析は不要。
interface
procedure RunPerformanceCacheChecks(const Root: string);

implementation

uses System.SysUtils, System.Types, System.IOUtils, Winapi.Windows,
  Vcl.Graphics, Vcl.Imaging.pngimage, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_PerformanceCache;

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;

procedure Clear(Bitmap: TBitmap; Width: Integer = 900; Height: Integer = 64;
  Color: TColor = clBlack);
begin
  Bitmap.PixelFormat := pf24bit; Bitmap.SetSize(Width,Height);
  Bitmap.Canvas.Brush.Color := Color; Bitmap.Canvas.FillRect(Rect(0,0,Width,Height));
end;

function WhiteCount(Bitmap: TBitmap; X: Integer): Integer;
var Y: Integer;
begin
  Result := 0;
  for Y := 0 to Bitmap.Height-1 do if ColorToRGB(Bitmap.Canvas.Pixels[X,Y]) = ColorToRGB(clWhite) then Inc(Result);
end;

procedure SaveBitmap(Bitmap: TBitmap; const Path: string);
var Png: TPngImage;
begin
  Png := TPngImage.Create; try Png.Assign(Bitmap); Png.SaveToFile(Path); finally Png.Free; end;
end;

procedure TestCache(const Root: string);
const Notes = '{"lengthBeats":8,"notes":[{"startBeat":0,"lengthBeats":1,"pitch":60,"velocity":100},'+
  '{"startBeat":2,"lengthBeats":4,"pitch":72,"velocity":100}]}';
var Document: TMusicStudioDocument; Cache: TMusicStudioPerformanceCache; Bitmap: TBitmap;
  Pattern, Other: TMusicStudioPattern; I,H,Parse,TimingParse,Raster: Integer;
  ErrorText, Before, After: string; Visible: TRect;
begin
  Document := TMusicStudioDocument.Create; Cache := TMusicStudioPerformanceCache.Create; Bitmap := TBitmap.Create;
  try
    Check(Document.TryLoad('',ErrorText),ErrorText); Document.AddPerformance;
    Pattern := Document.PatternAt(0); Pattern.Name := 'テンポ境界を跨ぐ演奏'; Pattern.ConfigJSON := Notes;
    Document.UpdatePattern(Pattern);
    Check(Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":120},{"beat":4,"bpm":60}]}',ErrorText),ErrorText);
    Cache.SetPatterns(Document); Check((Cache.ParseCount = 1) and (Cache.SourceCount = 1),'Performance cache did not parse once');
    Check(Cache.PatternMessage(Pattern.ID) = '', 'Valid performance not ready');
    Clear(Bitmap); Visible := Rect(0,0,900,64);
    Cache.Draw(Bitmap.Canvas,Visible,Visible,Pattern.ID,0,160,96,clBlack,clWhite);
    Check((WhiteCount(Bitmap,20) > 0) and (WhiteCount(Bitmap,100) = 0) and
      (WhiteCount(Bitmap,170) > 0) and (WhiteCount(Bitmap,630) > 0) and
      (WhiteCount(Bitmap,660) = 0),'Tempo boundary did not change note end seconds');
    SaveBitmap(Bitmap,TPath.Combine(Root,'performance-timeline-tempo.png'));
    Parse := Cache.ParseCount; TimingParse := Cache.TimingParseCount; Raster := Cache.RasterCount;
    for I := 1 to 100 do begin
      Cache.Draw(Bitmap.Canvas,Visible,Visible,Pattern.ID,0,160,96,clBlack,clWhite);
      Cache.SetPatterns(Document);
    end;
    Check((Cache.ParseCount = Parse) and (Cache.TimingParseCount = TimingParse) and
      (Cache.RasterCount = Raster),'100 draw/unchanged bind parsed or rasterized');
    Clear(Bitmap); Cache.Draw(Bitmap.Canvas,Visible,Visible,Pattern.ID,2,160,96,clBlack,clWhite);
    Check((WhiteCount(Bitmap,20) > 0) and (WhiteCount(Bitmap,720) > 0) and
      (WhiteCount(Bitmap,830) = 0),'Placement start beat not reflected in note duration');
    Check(Cache.ParseCount = Parse,'Different placement reparsed performance');
    SaveBitmap(Bitmap,TPath.Combine(Root,'performance-timeline-offset.png'));
    Clear(Bitmap,900,64,clRed);
    Cache.Draw(Bitmap.Canvas,Rect(0,0,900,64),Rect(270,8,540,54),Pattern.ID,0,160,96,clBlack,clWhite);
    Check((Bitmap.Canvas.Pixels[269,20] = clRed) and (Bitmap.Canvas.Pixels[540,20] = clRed) and
      (Bitmap.Canvas.Pixels[350,7] = clRed) and (Bitmap.Canvas.Pixels[350,54] = clRed), 'Visible crop wrote outside viewport');
    Check(WhiteCount(Bitmap,300) > 0,'Cropped partial tile omitted overlapping note');
    Clear(Bitmap,80,64); Cache.Draw(Bitmap.Canvas,Rect(-300,0,600,64),Rect(0,0,80,64),Pattern.ID,0,160,96,clBlack,clWhite);
    Check(WhiteCount(Bitmap,20) > 0,'Horizontal scroll moved relative time origin');
    Check(Document.TrySave(Before,ErrorText),ErrorText);
    Check(Document.SetTiming('{"tempoPoints":[{"beat":0,"bpm":60}]}',ErrorText),ErrorText);
    Cache.SetPatterns(Document); Check(Cache.ParseCount = Parse,'Tempo change reparsed canonical beat notes');
    Clear(Bitmap); Visible := Rect(0,0,900,64);
    Cache.Draw(Bitmap.Canvas,Visible,Visible,Pattern.ID,0,160,96,clBlack,clWhite);
    Check((WhiteCount(Bitmap,100) > 0) and (WhiteCount(Bitmap,170) = 0) and
      (WhiteCount(Bitmap,340) > 0) and (WhiteCount(Bitmap,870) > 0), 'BPM changed without tile invalidation');
    Other := Document.PatternAt(0); Check(Other.ConfigJSON = Pattern.ConfigJSON,'BPM changed canonical note beats');
    Check(Document.TrySave(After,ErrorText),ErrorText); Check(Before <> After,'Timing change not saved');
    Document.AddPerformance; Other := Document.PatternAt(1); Other.ConfigJSON := Notes;
    Document.UpdatePattern(Other); Cache.SetPatterns(Document); Check(Cache.ParseCount = Parse+1,'Unchanged source reparsed when adding pattern');
    Pattern.ConfigJSON := '{"lengthBeats":8,"notes":[{"startBeat":0,"lengthBeats":1,"pitch":0,"velocity":1},'+
      '{"startBeat":0,"lengthBeats":1,"pitch":127,"velocity":127}]}';
    Document.UpdatePattern(Pattern); Cache.SetPatterns(Document);
    Check(Cache.ParseCount = Parse+2,'Only changed pattern not reparsed');
    for H := 1 to 64 do begin
      Clear(Bitmap,400,H); Cache.Draw(Bitmap.Canvas,Rect(0,0,400,H),Rect(0,0,400,H),Pattern.ID,0,160,96,clBlack,clWhite);
      Check((WhiteCount(Bitmap,20) > 0) and (WhiteCount(Bitmap,300) = 0),'Pitch edge/short clip fit lost notes or stretched time');
    end;
    Clear(Bitmap,400,96); Cache.Draw(Bitmap.Canvas,Rect(0,0,400,96),Rect(0,0,400,96),Pattern.ID,0,240,144,clBlack,clWhite);
    Check(WhiteCount(Bitmap,20) >= 6,'144DPI edge note thickness insufficient');
    SaveBitmap(Bitmap,TPath.Combine(Root,'performance-timeline-pitch-144dpi.png'));
    Parse := Cache.ParseCount; TimingParse := Cache.TimingParseCount;
    for I := 1 to 180 do Cache.Draw(Bitmap.Canvas,Rect(0,0,400,96),Rect(0,0,400,96),
      Pattern.ID,0,100+I,96+(I mod 2)*48,clBlack,clWhite);
    Check((Cache.TileCount <= 128) and (Cache.ParseCount = Parse) and
      (Cache.TimingParseCount = TimingParse),'LRU exceeded bound or zoom/DPI parsed source');
    Pattern.ConfigJSON := '{"lengthBeats":8,"notes":[]}'; Document.UpdatePattern(Pattern);
    Cache.SetPatterns(Document); Check(Cache.PatternMessage(Pattern.ID) = '音符なし','Empty performance status not explicit');
    Document.RemovePattern(0); Cache.SetPatterns(Document);
    Check((Cache.SourceCount = 1) and (Cache.PatternMessage(Pattern.ID) = 'パターン参照切れ'), 'Deleted performance cache retained');
    Cache.SetPatterns(nil); Check((Cache.SourceCount = 0) and (Cache.TileCount = 0),'Clear retained sources/tiles');
    // 文書を所有しないsnapshotなので、先に文書を破棄してもDrawできる。
    Cache.SetPatterns(Document); Document.Free; Document := nil;
    Clear(Bitmap); Cache.Draw(Bitmap.Canvas,Rect(0,0,900,64),Rect(0,0,900,64),Other.ID,0,160,96,clBlack,clWhite);
    Check(WhiteCount(Bitmap,20) > 0,'Destroyed document invalidated cached snapshot');
  finally Bitmap.Free; Cache.Free; Document.Free; end;
end;

procedure RunPerformanceCacheChecks(const Root: string);
begin
  ForceDirectories(Root); TestCache(Root);
  Writeln('PERFORMANCE_CACHE_TIMING_PITCH_LRU_OK'); Flush(Output);
end;

end.
