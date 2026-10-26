unit SYNC_MusicStudio_PerformanceTrace;
// DEBUG profiling (Release is disabled). Workers aggregate counters only; the UI flushes at most once per second.
// Default: a process-specific Temp log. SYNC_MUSICSTUDIO_PROFILE=0 disables it; a path overrides the file.
interface
// 有効時の計測tickを返す。Release/無効時は0を返し、ファイル操作を行わない。
function MusicStudioPerfStamp: Int64;
// Stampのtickから経過msを返す。Start=0では0とし、呼出元の機能へ影響を与えない。
function MusicStudioPerfElapsed(Start: Int64): Double;
// stage別にmsをメモリ集計する。workerから呼べる。入力素材やJSON本文を記録しない。
procedure MusicStudioPerfAdd(const Stage: string; Milliseconds: Double; const Detail: string = '');
// UI側から呼び、通常は1秒に1回まで出力する。Forceは検証終了用。ログ失敗は外へ例外を漏らさない。
procedure MusicStudioPerfFlush(Force: Boolean = False);
implementation
uses System.SysUtils, System.Classes, System.Diagnostics, System.SyncObjs, System.JSON,
  System.IOUtils, System.Generics.Collections, Winapi.Windows;
type
  TPerfStat = record Count: Integer; Total,Maximum: Double; Detail: string; end;
var Lock: TCriticalSection; Stats: TDictionary<string,TPerfStat>;
{$IFDEF DEBUG}
  State: Integer;
{$ENDIF}
  LogPath: string; LastFlush: UInt64;
function Enabled: Boolean;
{$IFDEF DEBUG}
var Value: string;
{$ENDIF}
begin
{$IFDEF DEBUG}
  Lock.Acquire;
  try
    if State=0 then begin
      Value := GetEnvironmentVariable('SYNC_MUSICSTUDIO_PROFILE'); if Value='' then Value := '1'; State := 1;
      if Value<>'0' then begin
        if Value='1' then Value := TPath.Combine(TPath.GetTempPath,'SYNC_MusicStudio-profile-'+IntToStr(GetCurrentProcessId)+'.jsonl');
        LogPath := Value; State := 2;
      end;
    end;
    Result := State=2;
  finally Lock.Release; end;
{$ELSE}
  Result := False;
{$ENDIF}
end;
function MusicStudioPerfStamp: Int64;
begin if Enabled then Result := TStopwatch.GetTimeStamp else Result := 0; end;
function MusicStudioPerfElapsed(Start: Int64): Double;
begin if Start=0 then Exit(0); Result := (TStopwatch.GetTimeStamp-Start)*1000.0/TStopwatch.Frequency; end;
procedure MusicStudioPerfAdd(const Stage: string; Milliseconds: Double; const Detail: string);
var S: TPerfStat;
begin
  if not Enabled then Exit;
  Lock.Acquire;
  try
    if not Stats.TryGetValue(Stage,S) then S := Default(TPerfStat);
    Inc(S.Count); S.Total := S.Total+Milliseconds; if Milliseconds>S.Maximum then S.Maximum := Milliseconds;
    if Detail<>'' then S.Detail := Detail; Stats.AddOrSetValue(Stage,S);
  finally Lock.Release; end;
end;
procedure MusicStudioPerfFlush(Force: Boolean);
var Root,Item: TJSONObject; Items: TJSONArray; Pair: TPair<string,TPerfStat>; Text: string; Tick: UInt64;
begin
  if not Enabled then Exit; Tick := GetTickCount64;
  if not Force and (Tick-LastFlush<1000) then Exit;
  Root := TJSONObject.Create;
  try
    Items := TJSONArray.Create; Root.AddPair('pid',TJSONNumber.Create(GetCurrentProcessId));
    Root.AddPair('tickMs',TJSONNumber.Create(Tick)); Root.AddPair('stages',Items);
    Lock.Acquire;
    try
      LastFlush := Tick;
      for Pair in Stats do begin
        Item := TJSONObject.Create; Item.AddPair('stage',Pair.Key); Item.AddPair('count',TJSONNumber.Create(Pair.Value.Count));
        Item.AddPair('totalMs',TJSONNumber.Create(Pair.Value.Total));
        Item.AddPair('meanMs',TJSONNumber.Create(Pair.Value.Total/Pair.Value.Count));
        Item.AddPair('maxMs',TJSONNumber.Create(Pair.Value.Maximum)); Item.AddPair('detail',Pair.Value.Detail); Items.AddElement(Item);
      end;
      Stats.Clear;
    finally Lock.Release; end;
    if Items.Count=0 then Exit; Text := Root.ToJSON;
    try
      ForceDirectories(ExtractFileDir(TPath.GetFullPath(LogPath)));
      TFile.AppendAllText(LogPath,Text+sLineBreak,TEncoding.UTF8);
      OutputDebugString(PChar('SYNC_MusicStudio PERF '+Text));
    except on E: Exception do OutputDebugString(PChar('SYNC_MusicStudio PERF log unavailable: '+E.Message)); end;
  finally Root.Free; end;
end;
initialization
{$IFDEF DEBUG}
  Lock := TCriticalSection.Create; Stats := TDictionary<string,TPerfStat>.Create;
{$ENDIF}
finalization
  Stats.Free; Lock.Free;
end.
