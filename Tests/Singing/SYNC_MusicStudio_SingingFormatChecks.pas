unit SYNC_MusicStudio_SingingFormatChecks;
// 合成楽譜だけで各形式/文字コード/テンポ/worker/UI/歌詞帯を確認。音声・DPI試験なし。
interface
procedure RunSingingFormatChecks(const Root: string);
implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Math, System.Zip, System.Types,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  SYNC_MusicStudio_SingingData, SYNC_MusicStudio_SingingFormats, SYNC_MusicStudio_SingingFrame,
  SYNC_MusicStudio_VisualCache;
procedure Check(B: Boolean; const M: string);
begin if not B then raise Exception.Create('SONG_FORMAT: '+M); end;
const UST = '[#VERSION]'#13#10'UST Version1.2'#13#10'[#SETTING]'#13#10'Tempo=120'#13#10
  +'[#0000]'#13#10'Length=480'#13#10'Lyric=あ'#13#10'NoteNum=60'#13#10
  +'[#0001]'#13#10'Length=480'#13#10'Lyric=カ'#13#10'NoteNum=64'#13#10'Tempo=60'#13#10
  +'[#0002]'#13#10'Length=480'#13#10'Lyric=R'#13#10'NoteNum=60'#13#10
  +'[#0003]'#13#10'Length=240'#13#10'Lyric=ん'#13#10'NoteNum=67'#13#10'[#TRACKEND]';
const MXML = '<?xml version="1.0"?><!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">'
  +'<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>歌唱</part-name></score-part><score-part id="P2"><part-name>合唱</part-name></score-part></part-list>'
  +'<part id="P1"><measure number="1"><attributes><divisions>480</divisions></attributes><direction><sound tempo="120"/></direction>'
  +'<note><pitch><step>C</step><octave>4</octave></pitch><duration>480</duration><lyric><text>あ</text></lyric></note>'
  +'<direction><sound tempo="60"/></direction><note><pitch><step>E</step><octave>4</octave></pitch><duration>480</duration><tie type="start"/><lyric><text>カ</text></lyric></note>'
  +'<note><pitch><step>E</step><octave>4</octave></pitch><duration>480</duration><tie type="stop"/></note>'
  +'<note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>480</duration><lyric><text>ん</text></lyric></note></measure></part>'
  +'<part id="P2"><measure number="1"><attributes><divisions>480</divisions></attributes><note><rest/><duration>480</duration></note>'
  +'<note><pitch><step>G</step><octave>4</octave></pitch><duration>480</duration><lyric><text>い</text></lyric></note></measure></part></score-partwise>';
const MSC = '<museScore version="4.0"><Score><Staff id="1"><Measure><voice><Tempo><tempo>2</tempo></Tempo>'
  +'<Chord><durationType>quarter</durationType><Lyrics><text>あ</text></Lyrics><Note><pitch>60</pitch></Note></Chord>'
  +'<Tempo><tempo>1</tempo></Tempo><Chord><durationType>quarter</durationType><dots>1</dots><Lyrics><text>カ</text></Lyrics><Note><pitch>64</pitch></Note></Chord>'
  +'<Rest><durationType>eighth</durationType></Rest><Chord><durationType>quarter</durationType><Lyrics><text>ん</text></Lyrics><Note><pitch>67</pitch></Note></Chord>'
  +'</voice></Measure></Staff></Score></museScore>';
function VSQ(V4: Boolean): string;
begin
  if V4 then Result := '<vsq4 xmlns="http://www.yamaha.co.jp/vocaloid/schema/vsq4/"><masterTrack><resolution>480</resolution><preMeasure>1</preMeasure><timeSig><nu>4</nu><de>4</de></timeSig>'
    +'<tempo><t>0</t><v>12000</v></tempo><tempo><t>2400</t><v>6000</v></tempo></masterTrack>'
    +'<vsTrack><tNo>2</tNo><name>歌唱</name><vsPart><t>1920</t><note><t>0</t><dur>480</dur><n>60</n><y>あ</y></note>'
    +'<note><t>480</t><dur>480</dur><n>64</n><y>カ</y></note></vsPart></vsTrack></vsq4>'
  else Result := '<vsq3 xmlns="http://www.yamaha.co.jp/vocaloid/schema/vsq3/"><masterTrack><resolution>480</resolution><preMeasure>1</preMeasure><timeSig><nume>4</nume><denomi>4</denomi></timeSig>'
    +'<tempo><posTick>0</posTick><bpm>12000</bpm></tempo><tempo><posTick>2400</posTick><bpm>6000</bpm></tempo></masterTrack>'
    +'<vsTrack><vsTrackNo>2</vsTrackNo><trackName>歌唱</trackName><musicalPart><posTick>1920</posTick><note><posTick>0</posTick><durTick>480</durTick><noteNum>60</noteNum><lyric>あ</lyric></note>'
    +'<note><posTick>480</posTick><durTick>480</durTick><noteNum>64</noteNum><lyric>カ</lyric></note></musicalPart></vsTrack></vsq3>';
end;
procedure RunSingingFormatChecks(const Root: string);
var S: TMusicStudioSingingSource; Path: string; E: TEncoding; Z: TZipFile; I: Integer;
  UI: TForm; F: TMusicStudioSingingFrame; Cache: TMusicStudioVisualCache; Req: TMusicStudioVisualRequest;
  Src: TMusicStudioVisualSource; B: TBitmap; Deadline: UInt64;
  procedure Write(const Name,Text: string);
  begin TFile.WriteAllText(TPath.Combine(Root,Name),Text,TEncoding.UTF8); end;
  procedure Load(const Name: string; Notes,Tracks: Integer);
  begin Path := TPath.Combine(Root,Name); S := LoadMusicStudioSinging(Path);
    Check(S.Status=ssReady,Name+' '+S.Message); Check(Length(S.Notes)=Notes,Name+' note count');
    Check(Length(S.Tracks)=Tracks,Name+' track count'); Check(S.Notes[0].Lyric='あ',Name+' kana');
    Check(S.Notes[0].Vowels='a',Name+' vowel'); Check(SameValue(S.Notes[0].StartSeconds,0),Name+' part/premeasure offset');
    Check(SameValue(S.Notes[0].EndSeconds,0.5),Name+' first tempo');
    Check(SameValue(S.Notes[1].StartSeconds,0.5),Name+' next onset');
  end;
  procedure Zip(const Name,Entry,Text: string);
  begin
    Z := TZipFile.Create; try Z.Open(TPath.Combine(Root,Name),zmWrite);
      Z.Add(TEncoding.UTF8.GetBytes('<container><rootfiles><rootfile full-path="'+Entry+'"/></rootfiles></container>'),'META-INF/container.xml');
      Z.Add(TEncoding.UTF8.GetBytes('<ignore/>'),'unrelated.xml'); Z.Add(TEncoding.UTF8.GetBytes(Text),Entry);
    finally Z.Free; end;
  end;
begin
  ForceDirectories(Root); Write('song.ust',UST); E := TEncoding.GetEncoding(932);
  try TFile.WriteAllBytes(TPath.Combine(Root,'sjis.ust'),E.GetBytes(UST)); finally E.Free; end;
  Write('song3.vsqx',VSQ(False)); Write('song4.vsqx',VSQ(True)); Write('song.musicxml',MXML); Write('song.xml',MXML); Write('song.mscx',MSC);
  Zip('song.mxl','score/main.musicxml',MXML); Zip('song.mscz','score/main.mscx',MSC);
  Load('song.ust',3,1); Check(SameValue(S.Notes[1].EndSeconds,1.5) and SameValue(S.Notes[2].StartSeconds,2.5),'UST tempo/rest');
  Load('sjis.ust',3,1); Check(S.Notes[1].Lyric='カ','SJIS kana');
  Load('song3.vsqx',2,1); Check((S.Tracks[0].Index=2) and (S.Tracks[0].Name='歌唱') and SameValue(S.Duration,1.5),'VSQX3 track/time');
  Load('song4.vsqx',2,1); Check(SameValue(S.Duration,1.5),'VSQX4 tempo');
  Load('song.musicxml',4,2); Check(SameValue(S.Notes[1].EndSeconds,2.5),'MusicXML tie');
  Load('song.xml',4,2); Load('song.mxl',4,2);
  Load('song.mscx',3,1); Check(SameValue(S.Notes[1].EndSeconds,2) and SameValue(S.Notes[2].StartSeconds,2.5),'MuseScore dotted/rest');
  Load('song.mscz',3,1);
  Write('bad.vsqx','<vsq4>'); Check(LoadMusicStudioSinging(TPath.Combine(Root,'bad.vsqx')).Status=ssBroken,'broken XML accepted');
  Write('bad.mxl','bad zip'); Check(LoadMusicStudioSinging(TPath.Combine(Root,'bad.mxl')).Status=ssBroken,'broken ZIP accepted');
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'missing.ust')).Status=ssMissing,'missing new format');
  Check(LoadMusicStudioSinging(TPath.Combine(Root,'unsupported.ustx')).Status=ssUnsupported,'unsupported format');
  UI := TForm.CreateNew(nil); Cache := TMusicStudioVisualCache.Create; B := TBitmap.Create;
  try
    F := TMusicStudioSingingFrame.Create(UI); F.Parent := UI; F.Align := alClient;
    Path := TPath.Combine(Root,'song4.vsqx'); F.LoadSinging(Path,2); Deadline := GetTickCount64+10000;
    repeat F.PollResults; Application.ProcessMessages; Sleep(5); Check(GetTickCount64<Deadline,'UI worker timeout'); until not F.IsLoading;
    Check((F.Source.Status=ssReady) and (F.SelectedTrack=2) and (F.NotesList.Items.Count=2),'UI non-MIDI track');
    Check(SameValue(F.SelectedDuration,1.5),'UI duration');
    Req := Default(TMusicStudioVisualRequest); Req.Kind := vkMidi; Req.Path := Path; Req.Visible := True; Cache.SetSources(TArray<TMusicStudioVisualRequest>.Create(Req));
    Deadline := GetTickCount64+10000;
    repeat Cache.Poll; Sleep(5); Check(GetTickCount64<Deadline,'timeline worker timeout'); until Cache.ActiveJobs=0;
    Src := Cache.Find(vkMidi,Path); Check((Src<>nil) and (Src.Status=vsReady) and Src.Rolls.ContainsKey(2),'timeline non-MIDI index');
    B.SetSize(320,42); Cache.DrawRoll(B.Canvas,Rect(0,0,320,42),Rect(0,0,320,42),Src,2,160,96,clBlack,clWhite,False,True);
    I := Cache.RasterCount; Check(I>0,'timeline lyrics not drawn');
  finally B.Free; Cache.Free; UI.Free; end;
  Writeln('SINGING_UST_UTF8_SJIS_VSQX3_4_MUSICXML_MXL_MSCX_MSCZ_TEMPO_REST_TIE_TRACK_UI_LYRICS_NO_AUDIO_OK');
end;
end.
