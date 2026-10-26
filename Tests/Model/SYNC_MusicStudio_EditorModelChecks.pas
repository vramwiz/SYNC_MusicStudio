unit SYNC_MusicStudio_EditorModelChecks;

// 合成MIDIによるテンポ/歌詞/境界、参照型のトラック/配置JSON整合を検証する。
interface
procedure RunEditorModelChecks(const Root: string);
implementation
uses
  System.SysUtils, System.Classes, System.Math, System.IOUtils, System.JSON, System.Generics.Collections,
  SYNC_MusicStudio_ProjectData, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_SingingData, SYNC_MusicStudio_Vowels,
  SYNC_MusicStudio_TestHelpers;

procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;

procedure B(S: TStream; Value: Byte);
begin S.WriteBuffer(Value,1); end;
procedure Big16(S: TStream; Value: Word);
begin B(S,Value shr 8); B(S,Value and $FF); end;
procedure Big32(S: TStream; Value: Cardinal);
begin Big16(S,Value shr 16); Big16(S,Value and $FFFF); end;
procedure Tag(S: TStream; const Value: AnsiString);
begin S.WriteBuffer(Value[1],Length(Value)); end;
procedure VLQ(S: TStream; Value: Cardinal);
var Buf: array[0..3] of Byte; I,J: Integer;
begin
  I := 3; Buf[I] := Value and $7F; Value := Value shr 7;
  while Value > 0 do begin Dec(I); Buf[I] := (Value and $7F) or $80; Value := Value shr 7; end;
  for J := I to 3 do B(S,Buf[J]);
end;
procedure Meta(S: TStream; Delta: Cardinal; Kind: Byte; const Text: string);
var Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(Text);
  VLQ(S,Delta); B(S,$FF); B(S,Kind); VLQ(S,Length(Bytes));
  if Length(Bytes) > 0 then S.WriteBuffer(Bytes[0],Length(Bytes));
end;
procedure Tempo(S: TStream; Delta: Cardinal; Value: Cardinal);
begin
  VLQ(S,Delta); B(S,$FF); B(S,$51); B(S,3);
  B(S,Value shr 16); B(S,(Value shr 8) and $FF); B(S,Value and $FF);
end;
procedure Note(S: TStream; Delta: Cardinal; Status,Key,Velocity: Byte);
begin VLQ(S,Delta); B(S,Status); B(S,Key); B(S,Velocity); end;
procedure Track(S, Data: TMemoryStream);
begin Tag(S,'MTrk'); Big32(S,Data.Size); S.CopyFrom(Data,0); end;

procedure WriteMidi(const Path: string; Lyrics: Boolean; LyricKind: Byte = $05; KarMarker: Boolean = False);
var S,T: TMemoryStream;
begin
  S := TMemoryStream.Create; T := TMemoryStream.Create;
  try
    Tag(S,'MThd'); Big32(S,6); Big16(S,1); Big16(S,3); Big16(S,480);
    Meta(T,0,$03,'歌唱トラック');
    if KarMarker then Meta(T,0,$01,'@KMIDI KARAOKE FILE');
    if Lyrics then Meta(T,0,LyricKind,'きゃ');
    Note(T,0,$90,60,100); Note(T,960,$80,60,0);
    if Lyrics then Meta(T,0,LyricKind,'ー');
    Note(T,0,$90,62,90); Note(T,480,$80,62,0); Meta(T,0,$2F,'');
    Track(S,T); T.Clear;
    // テンポトラックを後に置き、読み順で歌唱秒位置が変わらないことを検証。
    Tempo(T,0,500000); Tempo(T,480,1000000); Meta(T,0,$2F,''); Track(S,T); T.Clear;
    Meta(T,0,$03,'伴奏（歌詞なし）');
    Note(T,0,$91,48,70); Note(T,240,$81,48,0); Meta(T,0,$2F,''); Track(S,T);
    S.SaveToFile(Path);
  finally T.Free; S.Free; end;
end;

procedure TestSinging(const Root: string);
var Source: TMusicStudioSingingSource; Bytes, Encoded: TBytes; Path: string; Job: TMusicStudioSingingJob;
  I,J: Integer; Encoding: TEncoding;
begin
  Path := TPath.Combine(Root,'singing-demo.mid'); WriteMidi(Path,True);
  Source := LoadMusicStudioSinging(Path);
  Check(Source.Status = ssReady,Source.Message);
  Check((Length(Source.Tracks) = 3) and (Length(Source.Notes) = 3),'MIDI track/note count');
  Check(SameValue(Source.Notes[0].EndSeconds,1.5,0.00001),'Global tempo map applied too late');
  Check(SameValue(Source.Notes[1].EndSeconds,2.5,0.00001),'Tempo change duration');
  Check((Source.Notes[0].Lyric = 'きゃ') and (Source.Notes[0].Vowels = 'a') and
    (Source.Notes[1].Vowels = 'a'),'Lyric association / vowel / long vowel');
  Check(MusicStudioLyricVowels('アイウエオン') = 'aiueon','Katakana vowels');
  Check(MusicStudioLyricVowels('漢字') = '??','Unknown pronunciation was guessed');
  WriteMidi(TPath.Combine(Root,'no-lyrics.mid'),False);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'no-lyrics.mid')).Status = ssNoLyrics,'No lyrics status');
  Check(LoadMusicStudioSinging('').Status = ssEmpty,'Empty status');
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'missing.mid')).Status = ssMissing,'Missing status');
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'demo.unsupported')).Status = ssUnsupported,'Unsupported extension');
  Bytes := TFile.ReadAllBytes(Path); Bytes[9] := 2; TFile.WriteAllBytes(TPath.Combine(Root,'format2.mid'),Bytes);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'format2.mid')).Status = ssUnsupported,'SMF2 status');
  Bytes := TFile.ReadAllBytes(Path); Bytes[12] := $E7; TFile.WriteAllBytes(TPath.Combine(Root,'smpte.mid'),Bytes);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'smpte.mid')).Status = ssUnsupported,'SMPTE status');
  Bytes := TFile.ReadAllBytes(Path); SetLength(Bytes,Length(Bytes) - 2);
  TFile.WriteAllBytes(TPath.Combine(Root,'broken.mid'),Bytes);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'broken.mid')).Status = ssBroken,'Truncated MIDI accepted');
  WriteMidi(TPath.Combine(Root,'singing.kar'),True,$01);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'singing.kar')).Status = ssReady,'KAR text lyrics');
  WriteMidi(TPath.Combine(Root,'ordinary-text.mid'),True,$01);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'ordinary-text.mid')).Status = ssNoLyrics,'Ordinary text treated as lyrics');
  WriteMidi(TPath.Combine(Root,'marked-kar.mid'),True,$01,True);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'marked-kar.mid')).Status = ssReady,'KAR marker in .mid');
  Bytes := TFile.ReadAllBytes(Path);
  Encoding := TEncoding.GetEncoding(932);
  try Encoded := Encoding.GetBytes('きゃ'); finally Encoding.Free; end;
  for I := 0 to Length(Bytes) - 6 do if (Bytes[I] = $E3) and (Bytes[I+1] = $81) and
    (Bytes[I+2] = $8D) and (Bytes[I+3] = $E3) and (Bytes[I+4] = $82) and (Bytes[I+5] = $83) then begin
    for J := 0 to 5 do if J < Length(Encoded) then Bytes[I+J] := Encoded[J] else Bytes[I+J] := 32;
    Break;
  end;
  TFile.WriteAllBytes(TPath.Combine(Root,'shift-jis.mid'),Bytes);
  Source := LoadMusicStudioSinging(TPath.Combine(Root,'shift-jis.mid'));
  Check((Source.Status = ssReady) and (Source.Notes[0].Lyric = 'きゃ'),'Shift-JIS lyrics fallback');
  Bytes := TFile.ReadAllBytes(Path); for I := 22 to 26 do Bytes[I] := $80;
  TFile.WriteAllBytes(TPath.Combine(Root,'bad-vlq.mid'),Bytes);
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'bad-vlq.mid')).Status = ssBroken,'Five-byte VLQ accepted');
  Job := TMusicStudioSingingJob.Create(Path,17);
  try
    Job.Start; Job.WaitFor;
    Check(Job.Done and (Job.RequestID = 17) and (Job.Source.Status = ssReady),'Async MIDI job');
  finally Job.Free; end;
  Writeln('SINGING_MIDI_TEMPO_LYRICS_VOWELS_STATUSES_ASYNC_OK');
end;

procedure TestArrangement(const Root: string);
var D,E: TMusicStudioDocument; P: TMusicStudioPattern; T: TMusicStudioTrack;
  Audio,Singing,AT,PT: Integer; Text,ErrorText,Before: string; C: TMusicStudioPlacement;
  Obj: TJSONObject; A: TJSONArray; Reject: Boolean;
begin
  D := TMusicStudioDocument.Create; E := TMusicStudioDocument.Create;
  try
    Check(D.TryLoad(MUSIC_STUDIO_DEFAULT_JSON,ErrorText),ErrorText);
    Audio := D.AddAudio; Singing := D.AddSinging;
    P := D.PatternAt(Singing); P.Name := 'ボーカル'; P.FilePath := TPath.Combine(Root,'singing-demo.mid');
    P.SourceTrack := 0; P.Duration := 2.5; D.UpdatePattern(P);
    AT := D.AddTrack('audio'); PT := D.AddTrack('psd');
    D.UpdateTrack(PT,'歌唱PSD','#BBAAFF','C:\素材\人物.psd');
    Check(D.AddPlacement(AT,TestSlotIndex(D,AT,'audio'),D.PatternAt(Audio).ID,1,12,ErrorText),ErrorText);
    Check(D.AddPlacement(AT,TestSlotIndex(D,AT,'audio'),D.PatternAt(Audio).ID,18,12,ErrorText),ErrorText);
    Check(D.AddPlacement(PT,TestSlotIndex(D,PT,'singing'),P.ID,0,2.5,ErrorText),ErrorText);
    Check(not D.AddPlacement(PT,TestSlotIndex(D,PT,'psd'),D.PatternAt(Audio).ID,0,1,ErrorText) and (ErrorText <> ''),'Audio allowed in PSD assignment slot');
    Check(not D.AddPlacement(AT,TestSlotIndex(D,AT,'audio'),P.ID,0,1,ErrorText) and (ErrorText <> ''),'Singing allowed in audio slot');
    T := D.TrackAt(AT); Check((T.Clips[0].ID <> T.Clips[1].ID) and
      (T.Clips[0].ID <> T.Clips[0].PatternID),'Placement ID equals source or duplicate');
    C := T.Clips[0]; D.MovePlacement(AT,0,3.5,8);
    Check(D.TrackAt(AT).Clips[0].ID = C.ID,'Move changed placement ID');
    Reject := False; try D.RemovePattern(Audio); except Reject := True; end;
    Check(Reject,'In-use pattern deleted');
    Check(D.TrySave(Text,ErrorText),ErrorText); Before := Text;
    Check(E.TryLoad(Text,ErrorText),ErrorText);
    Check((E.TrackCount = 2) and (E.TrackAt(PT).PsdPath = 'C:\素材\人物.psd') and
      (E.PatternAt(Singing).SourceTrack = 0),'Reference roundtrip');
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[0]).RemovePair('kind').Free;
      TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[0]).AddPair('kind','future-track');
      Check(E.TryLoad(Obj.ToJSON,ErrorText),ErrorText);
      Check(E.PatternInUse(E.PatternAt(Audio).ID),'Unknown track source reference was not protected');
    finally Obj.Free; end;
    Check(E.TryLoad(Before,ErrorText),ErrorText);
    Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
    try
      A := TJSONArray(TJSONObject(TJSONArray(TJSONObject(TJSONArray(Obj.GetValue('tracks')).Items[0]).GetValue('slots')).Items[0]).GetValue('clips'));
      TJSONObject(A.Items[0]).RemovePair('patternId').Free;
      TJSONObject(A.Items[0]).AddPair('patternId','missing-id');
      Check(not E.TryLoad(Obj.ToJSON,ErrorText),'Missing pattern reference accepted');
      Check(E.TrySave(Text,ErrorText) and (Text = Before),'Failed load lost current document');
    finally Obj.Free; end;
    D.RemoveTrack(AT); Check(D.PatternCount = 2,'Removing track removed source patterns');
    D.RemoveTrack(0); D.RemovePattern(Audio);
    Check((D.PatternCount = 1) and (D.TrackCount = 0),'Delete lifecycle');
    Check(D.TrySave(Text,ErrorText),ErrorText);
    TFile.WriteAllText(TPath.Combine(Root,'arrangement-roundtrip.json'),Before,TEncoding.UTF8);
    Writeln('TRACK_COMPATIBILITY_IDS_MOVE_DELETE_REFERENCES_ROUNDTRIP_OK');
  finally E.Free; D.Free; end;
end;

procedure RunEditorModelChecks(const Root: string);
var Text,ErrorText,Path,Fixture: string; Bytes: TBytes; Obj: TJSONObject;
begin
  TestSinging(Root); TestArrangement(Root);
  Path := TPath.Combine(Root,'arrangement-roundtrip.json');
  Check(TryReadMusicStudioJSONFile(Path,Text,ErrorText),ErrorText);
  Fixture := Copy(MUSIC_STUDIO_DEFAULT_JSON,1,Length(MUSIC_STUDIO_DEFAULT_JSON)-1)+',"unicode":"ボーカル"}';
  Bytes := TEncoding.UTF8.GetBytes(#$FEFF+Fixture); TFile.WriteAllBytes(TPath.Combine(Root,'utf8-bom.json'),Bytes);
  Check(TryReadMusicStudioJSONFile(TPath.Combine(Root,'utf8-bom.json'),Text,ErrorText),ErrorText);
  Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  try Check(Obj.GetValue('unicode').Value = 'ボーカル','UTF-8 Japanese JSON file lost'); finally Obj.Free; end;
  Bytes := TEncoding.UTF8.GetBytes(Fixture); TFile.WriteAllBytes(TPath.Combine(Root,'no-bom.json'),Bytes);
  Check(TryReadMusicStudioJSONFile(TPath.Combine(Root,'no-bom.json'),Text,ErrorText),ErrorText);
  SetLength(Bytes,MUSIC_STUDIO_MAX_JSON_INPUT+1); TFile.WriteAllBytes(TPath.Combine(Root,'too-large.json'),Bytes);
  Check(not TryReadMusicStudioJSONFile(TPath.Combine(Root,'too-large.json'),Text,ErrorText),'Oversized JSON file accepted');
  Bytes := TBytes.Create($FF,$FE,$41,$00); TFile.WriteAllBytes(TPath.Combine(Root,'invalid-encoding.json'),Bytes);
  Check(not TryReadMusicStudioJSONFile(TPath.Combine(Root,'invalid-encoding.json'),Text,ErrorText),'Non-UTF8 JSON accepted');
  Check(not TryReadMusicStudioJSONFile(TPath.Combine(Root,'missing.json'),Text,ErrorText),'Missing JSON file accepted');
  Check(not TryNormalizeMusicStudioJSON(StringOfChar(' ',MUSIC_STUDIO_MAX_JSON_INPUT+1),Text,ErrorText),'Oversized input parsed');
  Check(not TryNormalizeMusicStudioJSON(StringOfChar('[',129)+StringOfChar(']',129),Text,ErrorText),'Deep JSON parsed');
  Check(not TryNormalizeMusicStudioJSON(MUSIC_STUDIO_DEFAULT_JSON+' {}',Text,ErrorText),'Trailing JSON accepted');
  Check(TryNormalizeMusicStudioJSON(Copy(MUSIC_STUDIO_DEFAULT_JSON,1,Length(MUSIC_STUDIO_DEFAULT_JSON)-1)+
    ',"escaped":"brace } and [ and quote \" and slash \\"}',Text,ErrorText),ErrorText);
  Writeln('JSON_FILE_UTF8_BOM_LIMIT_NESTING_TRAILING_AND_ESCAPES_OK');
end;
end.
