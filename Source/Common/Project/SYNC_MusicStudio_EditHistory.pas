unit SYNC_MusicStudio_EditHistory;
// 作品JSONのUndo/Redo。任意の外部変更は適用callback成功後だけ履歴を進め、競合時は保持する。
interface
uses System.Generics.Collections;
type
  TMusicStudioEditStep = record BeforeText,AfterText: string; ExternalID: Integer; end;
  TMusicStudioHistoryApply = function(ExternalID: Integer; Undo: Boolean): Boolean of object;
  TMusicStudioEditHistory = class
  private
    FUndo,FRedo: TList<TMusicStudioEditStep>;
    FOnApply: TMusicStudioHistoryApply;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure RecordChange(const BeforeText,AfterText: string; ExternalID: Integer = -1);
    property OnApply: TMusicStudioHistoryApply read FOnApply write FOnApply;
    function Undo(const Current: string; out Text: string): Boolean;
    function Redo(const Current: string; out Text: string): Boolean;
  end;
implementation
uses System.SysUtils;
constructor TMusicStudioEditHistory.Create;
begin inherited; FUndo := TList<TMusicStudioEditStep>.Create; FRedo := TList<TMusicStudioEditStep>.Create; end;
destructor TMusicStudioEditHistory.Destroy;
begin FRedo.Free; FUndo.Free; inherited; end;
procedure TMusicStudioEditHistory.Clear;
begin FUndo.Clear; FRedo.Clear; end;
procedure TMusicStudioEditHistory.RecordChange(const BeforeText,AfterText: string; ExternalID: Integer);
var Step: TMusicStudioEditStep;
begin
  Step.BeforeText := Trim(BeforeText); Step.AfterText := Trim(AfterText);
  Step.ExternalID := ExternalID;
  if (Step.BeforeText=Step.AfterText) and (ExternalID<0) then Exit;
  if (FUndo.Count>0) and (FUndo.Last.AfterText<>Step.BeforeText) then Clear;
  FRedo.Clear; FUndo.Add(Step);
  if FUndo.Count>32 then FUndo.Delete(0);
end;
function TMusicStudioEditHistory.Undo(const Current: string; out Text: string): Boolean;
var Step: TMusicStudioEditStep;
begin
  Result := False; Text := '';
  if FUndo.Count=0 then Exit;
  Step := FUndo.Last;
  if Trim(Current)<>Step.AfterText then begin Clear; Exit; end;
  if (Step.ExternalID>=0) and (not Assigned(FOnApply) or not FOnApply(Step.ExternalID,True)) then Exit;
  FUndo.Delete(FUndo.Count-1); FRedo.Add(Step); Text := Step.BeforeText; Result := True;
end;
function TMusicStudioEditHistory.Redo(const Current: string; out Text: string): Boolean;
var Step: TMusicStudioEditStep;
begin
  Result := False; Text := '';
  if FRedo.Count=0 then Exit;
  Step := FRedo.Last;
  if Trim(Current)<>Step.BeforeText then begin Clear; Exit; end;
  if (Step.ExternalID>=0) and (not Assigned(FOnApply) or not FOnApply(Step.ExternalID,False)) then Exit;
  FRedo.Delete(FRedo.Count-1); FUndo.Add(Step); Text := Step.AfterText; Result := True;
end;
end.
