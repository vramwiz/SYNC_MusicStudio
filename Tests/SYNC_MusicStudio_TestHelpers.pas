unit SYNC_MusicStudio_TestHelpers;
// Tests resolve current slot kinds and stable pattern IDs; array positions are not identities.
interface
uses SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SettingsForm;
function TestSlotIndex(Document: TMusicStudioDocument; TrackIndex: Integer; const Kind: string): Integer;
procedure SelectTestPattern(Form: TFormMusicStudioSettings; const PatternID: string);
procedure WriteLayeredTestPSD(const Path: string; Red: Byte = 40; Green: Byte = 115; Blue: Byte = 190);
implementation
uses System.SysUtils, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_ArtDocument, SYNC_MusicStudio_ArtPsd;
function TestSlotIndex(Document: TMusicStudioDocument; TrackIndex: Integer; const Kind: string): Integer;
var Track: TMusicStudioTrack; I: Integer;
begin
  Track := Document.TrackAt(TrackIndex);
  for I := 0 to High(Track.Slots) do if Track.Slots[I].Kind=Kind then Exit(I);
  raise Exception.Create('Missing test slot '+Kind+' on '+Track.ID);
end;
procedure SelectTestPattern(Form: TFormMusicStudioSettings; const PatternID: string);
var I,Index: Integer;
begin
  for I := 0 to Form.PatternList.Count-1 do begin
    Form.PatternList.ItemIndex := I; Index := Form.SelectedLibraryPattern;
    if (Index>=0) and (Form.Document.PatternAt(Index).ID=PatternID) then begin
      Form.PatternList.OnClick(Form.PatternList); Exit;
    end;
  end;
  raise Exception.Create('Pattern not listed in selected slot: '+PatternID);
end;
procedure WriteLayeredTestPSD(const Path: string; Red,Green,Blue: Byte);
var Document: TArtDocument; Layer: TArtLayer; I: Integer;
begin
  Document := TArtDocument.Create;
  try
    Document.Width := 64; Document.Height := 64;
    Layer := Document.AddLayer(alkImage,'任意の画像部位',TArtBounds.Create(0,0,64,64));
    Layer.Visible := True; SetLength(Layer.Pixels,64*64*4);
    for I := 0 to 64*64-1 do begin
      Layer.Pixels[I*4] := Red; Layer.Pixels[I*4+1] := Green; Layer.Pixels[I*4+2] := Blue; Layer.Pixels[I*4+3] := 255;
    end;
    WriteNewPsd(Document,Path,pcRaw);
  finally Document.Free; end;
end;
end.
