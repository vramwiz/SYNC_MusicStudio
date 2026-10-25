// Workers own decoded snapshots and results. Completion is polled, with no queued UI callbacks.
unit SYNC_MusicStudio_PsdLayerJobs;

interface

uses System.Classes, System.SysUtils, System.JSON, Vcl.Graphics,
  SYNC_MusicStudio_PsdLayers;

type
  TMusicStudioPsdLayerLoadJob = class(TThread)
  private
    FDocument: TMusicStudioLayerDocument;
    FError: string;
    FPath: string;
    FGeneration: Integer;
    FStarted: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Path: string; Generation: Integer);
    destructor Destroy; override;
    procedure Start; reintroduce;
    function TakeDocument: TMusicStudioLayerDocument;
    property ErrorMessage: string read FError;
    property Path: string read FPath;
    property Generation: Integer read FGeneration;
  end;
  TMusicStudioPsdLayerRenderJob = class(TThread)
  private
    FDocument: TMusicStudioLayerDocument;
    FOverrides: TJSONObject;
    FBitmap: TBitmap;
    FError: string;
    FGeneration: Integer;
    FMaximumDimension: Integer;
    FStarted: Boolean;
  protected
    procedure Execute; override;
  public
    // Clones metadata before Start; original document may be freed immediately afterwards.
    constructor Create(Document: TMusicStudioLayerDocument; Overrides: TJSONObject; Generation: Integer; MaximumDimension: Integer = 0);
    destructor Destroy; override;
    procedure Start; reintroduce;
    function TakeBitmap: TBitmap;
    property ErrorMessage: string read FError;
    property Generation: Integer read FGeneration;
  end;

implementation

constructor TMusicStudioPsdLayerLoadJob.Create(const Path: string; Generation: Integer);
begin
  inherited Create(True); FreeOnTerminate := False;
  FPath := Path; FGeneration := Generation;
end;

destructor TMusicStudioPsdLayerLoadJob.Destroy;
begin
  Terminate; if not FStarted then Start; if not Finished then WaitFor; FDocument.Free; inherited;
end;

procedure TMusicStudioPsdLayerLoadJob.Start;
begin FStarted := True; inherited Start; end;

procedure TMusicStudioPsdLayerLoadJob.Execute;
begin
  if Terminated then Exit;
  try
    FDocument := TMusicStudioLayerDocument.Create;
    if not FDocument.LoadFile(FPath) then begin FError := FDocument.LastError; FreeAndNil(FDocument); end;
    if Terminated then FreeAndNil(FDocument);
  except on E: Exception do begin FError := E.Message; FreeAndNil(FDocument); end; end;
end;

function TMusicStudioPsdLayerLoadJob.TakeDocument: TMusicStudioLayerDocument;
begin Result := FDocument; FDocument := nil; end;

constructor TMusicStudioPsdLayerRenderJob.Create(Document: TMusicStudioLayerDocument;
  Overrides: TJSONObject; Generation,MaximumDimension: Integer);
begin
  inherited Create(True); FreeOnTerminate := False; FGeneration := Generation;
  FMaximumDimension := MaximumDimension;
  FDocument := Document.Clone;
  if Overrides<>nil then FOverrides := TJSONObject(Overrides.Clone);
end;

destructor TMusicStudioPsdLayerRenderJob.Destroy;
begin
  Terminate; if not FStarted then Start; if not Finished then WaitFor;
  FBitmap.Free; FOverrides.Free; FDocument.Free; inherited;
end;

procedure TMusicStudioPsdLayerRenderJob.Start;
begin FStarted := True; inherited Start; end;

procedure TMusicStudioPsdLayerRenderJob.Execute;
begin
  if Terminated then Exit;
  try
    FBitmap := TBitmap.Create;
    if not FDocument.Render(FBitmap,FOverrides,FMaximumDimension) then begin
      FError := FDocument.LastError; FreeAndNil(FBitmap);
    end;
    if Terminated then FreeAndNil(FBitmap);
  except on E: Exception do begin FError := E.Message; FreeAndNil(FBitmap); end; end;
end;

function TMusicStudioPsdLayerRenderJob.TakeBitmap: TBitmap;
begin Result := FBitmap; FBitmap := nil; end;

end.
