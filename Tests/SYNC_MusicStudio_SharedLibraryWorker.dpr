program SYNC_MusicStudio_SharedLibraryWorker;
{$APPTYPE CONSOLE}
// 隔離ライブラリ用の子プロセス。音声/VCL/実ライブラリは使わない。
uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows,
  SYNC_MusicStudio_SharedPsdLibrary in '..\Source\Common\Project\Library\SYNC_MusicStudio_SharedPsdLibrary.pas';
type
  TInterruptedCopyLibrary = class(TMusicStudioSharedPsdLibrary)
  protected
    procedure CopyPsdData(Source,Target: TStream); override;
  end;
procedure TInterruptedCopyLibrary.CopyPsdData(Source,Target: TStream);
var Data: array[0..255] of Byte; Event: THandle;
begin
  Source.ReadBuffer(Data,SizeOf(Data)); Target.WriteBuffer(Data,SizeOf(Data));
  if not FlushFileBuffers(THandleStream(Target).Handle) then RaiseLastOSError;
  TFile.WriteAllText(ParamStr(4),'partial staged copy',TEncoding.UTF8);
  Event := OpenEvent(SYNCHRONIZE,False,PChar(ParamStr(6)));
  if Event=0 then RaiseLastOSError;
  try
    if WaitForSingleObject(Event,15000)<>WAIT_OBJECT_0 then
      raise Exception.Create('Interrupted-copy fixture timed out.');
  finally CloseHandle(Event); end;
  raise Exception.Create('Interrupted-copy fixture must be stopped by its owner.');
end;
var LibraryStore: TMusicStudioSharedPsdLibrary; Asset: TMusicStudioPsdAsset;
  Error,BeforeRevision: string; Event: THandle; ResultJSON: TJSONObject; Saved,Dup: Boolean;
begin
  try
    if ParamCount<>7 then raise Exception.Create('Expected mode/root/id/ready/result/event/value.');
    if (ParamStr(1)='copy-crash') or (ParamStr(1)='import-crash') then LibraryStore := TInterruptedCopyLibrary.Create(ParamStr(2))
    else if ParamStr(1)='save' then LibraryStore := TMusicStudioSharedPsdLibrary.Create(ParamStr(2))
    else raise Exception.Create('Unknown worker mode.');
    try
      if ParamStr(1)='copy-crash' then begin
        if not LibraryStore.TryRelocate(ParamStr(3),ParamStr(7),Error) then raise Exception.Create(Error);
        raise Exception.Create('Interrupted-copy fixture unexpectedly completed.');
      end;
      if ParamStr(1)='import-crash' then begin
        if not LibraryStore.TryImport(ParamStr(7),'中断登録fixture','#77AAEE',Asset,Dup,Error) then raise Exception.Create(Error);
        raise Exception.Create('Interrupted-import fixture unexpectedly completed.');
      end;
      if not LibraryStore.TryRead(ParamStr(3),Asset,Error) then raise Exception.Create(Error);
      BeforeRevision := Asset.Revision; Asset.Name := ParamStr(7);
      Event := OpenEvent(SYNCHRONIZE,False,PChar(ParamStr(6)));
      if Event=0 then RaiseLastOSError;
      try
        TFile.WriteAllText(ParamStr(4),BeforeRevision,TEncoding.UTF8);
        if WaitForSingleObject(Event,15000)<>WAIT_OBJECT_0 then raise Exception.Create('Save barrier timed out.');
      finally CloseHandle(Event); end;
      Saved := LibraryStore.TrySave(Asset,Error);
      ResultJSON := TJSONObject.Create;
      try
        ResultJSON.AddPair('saved',TJSONBool.Create(Saved)); ResultJSON.AddPair('error',Error);
        ResultJSON.AddPair('before',BeforeRevision); ResultJSON.AddPair('after',Asset.Revision);
        ResultJSON.AddPair('name',Asset.Name);
        TFile.WriteAllText(ParamStr(5),ResultJSON.ToJSON,TEncoding.UTF8);
      finally ResultJSON.Free; end;
    finally LibraryStore.Free; end;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
