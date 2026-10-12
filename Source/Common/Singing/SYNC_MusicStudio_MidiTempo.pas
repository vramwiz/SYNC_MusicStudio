unit SYNC_MusicStudio_MidiTempo;

// SMF0/1・PPQのtempo snapshot抽出。音符/PCM/waveOutは扱わず、取消可能な読み取りだけ。
interface
uses System.Classes;
procedure ReadMusicStudioMidiTempo(const Path: string; out TimingJSON: string; out LengthBeats: Double; Cancel: TThread = nil);
implementation
uses System.SysUtils, System.IOUtils, System.JSON, System.Math, System.Generics.Collections,
  System.Generics.Defaults, SYNC_MusicStudio_BeatData;
type TThreadAccess = class(TThread);
  TMidiTempoPoint = record Tick: Int64; Microseconds,Order: Integer; end;
procedure ReadMusicStudioMidiTempo(const Path: string; out TimingJSON: string; out LengthBeats: Double; Cancel: TThread);
var Bytes: TBytes; Position,Boundary,TrackEnd,TrackCount,Track,Division,Format,HeaderLength,Size,Status,Running,Kind,Length,Count,I,N,D: Integer;
  Tick,LastTick: Int64; Point: TMidiTempoPoint; Points: TList<TMidiTempoPoint>; Map: TMusicStudioTempoMap; Numerator,Denominator,MeterChanges: Integer;
  Root,Info,Event: TJSONObject; Events: TJSONArray;
  function ByteValue: Byte;
  begin if Position>=Boundary then raise EReadError.Create('MIDIイベントが途中で切れています。'); Result := Bytes[Position]; Inc(Position); end;
  function U16: Integer;
  begin Result := Integer(ByteValue)*256+ByteValue; end;
  function U32: Integer;
  var Value: UInt64;
  begin Value := UInt64(ByteValue)*16777216+UInt64(ByteValue)*65536+UInt64(ByteValue)*256+ByteValue;
    if Value>MaxInt then raise EReadError.Create('MIDIチャンクが大きすぎます。'); Result := Integer(Value);
  end;
  function VLQ: Integer;
  var B,J: Integer;
  begin Result := 0; for J := 0 to 3 do begin B := ByteValue; Result := (Result shl 7) or (B and 127); if B<128 then Exit; end;
    raise EReadError.Create('MIDI可変長数が不正です。');
  end;
  function Signature: string;
  begin Result := Char(ByteValue)+Char(ByteValue)+Char(ByteValue)+Char(ByteValue); end;
  procedure Skip(Value: Integer);
  begin if (Value<0) or (Value>Boundary-Position) then raise EReadError.Create('MIDI長さが不正です。'); Inc(Position,Value); end;
begin
  TimingJSON := ''; LengthBeats := 0;
  if TFile.GetSize(Path)>32*1024*1024 then raise EReadError.Create('MIDIは32MiB以内にしてください。');
  Bytes := TFile.ReadAllBytes(Path); Position := 0; Boundary := System.Length(Bytes);
  if Signature<>'MThd' then raise EReadError.Create('SMF MIDIヘッダーがありません。'); HeaderLength := U32;
  if HeaderLength<6 then raise EReadError.Create('MIDIヘッダーが不正です。'); Format := U16; TrackCount := U16; Division := U16;
  if not (Format in [0,1]) or (TrackCount<1) or (TrackCount>1024) or ((Format=0) and (TrackCount<>1)) or
    (Division=0) or (Division and $8000<>0) then raise EReadError.Create('SMF0/1のPPQ MIDIのみ対応しています。'); Skip(HeaderLength-6);
  Points := TList<TMidiTempoPoint>.Create; Map := TMusicStudioTempoMap.Create; LastTick := 0; Count := 0; Numerator := 4; Denominator := 4; MeterChanges := 0;
  try
    for Track := 0 to TrackCount-1 do begin
      Boundary := System.Length(Bytes); if Signature<>'MTrk' then raise EReadError.Create('MIDIトラックがありません。'); Size := U32;
      if Size>Boundary-Position then raise EReadError.Create('MIDIトラック長が不正です。'); TrackEnd := Position+Size; Boundary := TrackEnd;
      Tick := 0; Running := 0;
      while Position<TrackEnd do begin
        Inc(Count); if (Count and 1023=0) and Assigned(Cancel) and TThreadAccess(Cancel).Terminated then raise EAbort.Create('MIDI読込を取り消しました。');
        Tick := Tick+VLQ; if Tick/Division>1000000 then raise EReadError.Create('MIDI拍位置が上限を超えます。'); LastTick := Max(LastTick,Tick);
        Status := ByteValue;
        if Status<128 then begin
          if Running=0 then raise EReadError.Create('MIDI running statusが不正です。');
          if (Running and $F0) in [$C0,$D0] then N := 1 else N := 2;
          for I := 2 to N do if ByteValue>=128 then raise EReadError.Create('MIDI running channel dataが不正です。'); Continue;
        end;
        if Status<$F0 then begin Running := Status; if (Status and $F0) in [$C0,$D0] then N := 1 else N := 2;
          for I := 1 to N do if ByteValue>=128 then raise EReadError.Create('MIDI channel dataが不正です。'); Continue;
        end;
        if Status=$FF then begin
          Running := 0;
          Kind := ByteValue; Length := VLQ;
          if Kind=$51 then begin
            if Length<>3 then raise EReadError.Create('MIDI tempoイベント長が不正です。');
            Point.Tick := Tick; Point.Microseconds := Integer(ByteValue)*65536+Integer(ByteValue)*256+ByteValue; Point.Order := Count;
            if (Point.Microseconds<60001) or (Point.Microseconds>60000000) then raise EReadError.Create('MIDI tempoは1～999.99 BPMの範囲で指定してください。');
            if Points.Count>=8192 then raise EReadError.Create('MIDI tempoイベントが多すぎます。'); Points.Add(Point);
          end else if Kind=$58 then begin
            if Length<>4 then raise EReadError.Create('MIDI拍子イベント長が不正です。'); Numerator := ByteValue; D := ByteValue; Skip(2);
            if (Numerator<1) or (Numerator>32) or (D>6) then raise EReadError.Create('MIDI拍子が未対応です。');
            if Tick>0 then begin Inc(MeterChanges); Numerator := Map.Numerator; end else begin Denominator := 1 shl D; Map.SetMeter(Numerator,Denominator); end;
          end else Skip(Length);
        end else if Status in [$F0,$F7] then begin Running := 0; Skip(VLQ); end
        else raise EReadError.Create('未対応のMIDI system eventです。');
      end;
    end;
    if Assigned(Cancel) and TThreadAccess(Cancel).Terminated then raise EAbort.Create('MIDI読込を取り消しました。');
    if Points.Count=0 then raise EReadError.Create('このMIDIには明示的なtempo情報がありません。');
    Points.Sort(TComparer<TMidiTempoPoint>.Construct(function(const A,B: TMidiTempoPoint): Integer
      begin if A.Tick<B.Tick then Result := -1 else if A.Tick>B.Tick then Result := 1 else Result := A.Order-B.Order; end));
    for Point in Points do Map.SetBPMAt(Point.Tick/Division,60000000.0/Point.Microseconds);
    Map.SetMeter(Numerator,Denominator); LengthBeats := Max(1/64,Max(LastTick/Division,Map.TempoPoint(Map.PointCount-1).Beat+1/64));
    Root := TJSONObject.ParseJSONValue(Map.TimingJSON) as TJSONObject;
    try
      Info := TJSONObject.Create; Root.AddPair('midi',Info); Info.AddPair('ppq',TJSONNumber.Create(Division));
      Info.AddPair('format',TJSONNumber.Create(Format)); Info.AddPair('meterChangesIgnored',TJSONNumber.Create(MeterChanges));
      Events := TJSONArray.Create; Info.AddPair('tempoEvents',Events);
      for Point in Points do begin Event := TJSONObject.Create; Event.AddPair('tick',TJSONNumber.Create(Point.Tick));
        Event.AddPair('microseconds',TJSONNumber.Create(Point.Microseconds)); Event.AddPair('order',TJSONNumber.Create(Point.Order)); Events.AddElement(Event); end;
      TimingJSON := Root.ToJSON;
    finally Root.Free; end;
  finally Map.Free; Points.Free; end;
end;
end.
