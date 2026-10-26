unit SYNC_MusicStudio_FileDropList;

// Explorerのファイルdropを一覧の寿命に結び付ける。アプリ内VCLドラッグは従来どおり。
interface
uses System.Classes, Winapi.Messages, Vcl.StdCtrls;
type
  TMusicStudioFilesDropped = procedure(const Paths: TArray<string>) of object;
  TMusicStudioFileDropList = class(TListBox)
  private
    FOnFilesDropped: TMusicStudioFilesDropped;
    procedure WMDropFiles(var Message: TWMDropFiles); message WM_DROPFILES;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    property OnFilesDropped: TMusicStudioFilesDropped read FOnFilesDropped write FOnFilesDropped;
  end;
implementation
uses System.SysUtils, Winapi.Windows, Winapi.ShellAPI;
procedure TMusicStudioFileDropList.CreateWnd;
begin inherited; DragAcceptFiles(Handle,True); end;
procedure TMusicStudioFileDropList.DestroyWnd;
begin DragAcceptFiles(Handle,False); inherited; end;
procedure TMusicStudioFileDropList.WMDropFiles(var Message: TWMDropFiles);
var Paths: TArray<string>; I,N,L: Integer;
begin
  try
    N := DragQueryFile(Message.Drop,$FFFFFFFF,nil,0); SetLength(Paths,N);
    for I := 0 to N-1 do begin
      L := DragQueryFile(Message.Drop,I,nil,0); SetLength(Paths[I],L+1);
      DragQueryFile(Message.Drop,I,PChar(Paths[I]),L+1); SetLength(Paths[I],L);
    end;
  finally DragFinish(Message.Drop); Message.Result := 0; end;
  if Assigned(FOnFilesDropped) then FOnFilesDropped(Paths);
end;
end.
