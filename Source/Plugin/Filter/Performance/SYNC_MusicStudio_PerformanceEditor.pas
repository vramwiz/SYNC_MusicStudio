unit SYNC_MusicStudio_PerformanceEditor;

// 共通演奏の編集ダイアログ。PSDを候補表示に借用し、保存する設定からPSD固有IDを除く。
interface
uses System.Classes, SYNC_MusicStudio_PatternData, SYNC_MusicStudio_SharedPsdLibrary;
// OKで値コピーだけ更新する。ディスク保存は呼出側の共通Storeが担当する。
function EditMusicStudioPerformance(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  const AssetID: string; Silent: Boolean; BPM: Double; var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
implementation
uses System.SysUtils, Vcl.Forms, Vcl.Dialogs, System.UITypes, SYNC_MusicStudio_PatternSettingsForm,
  SYNC_MusicStudio_PerformanceLibrary, SYNC_MusicStudio_InstrumentData;
function EditMusicStudioPerformance(Owner: TComponent; Store: TMusicStudioSharedPsdLibrary;
  const AssetID: string; Silent: Boolean; BPM: Double; var Pattern: TMusicStudioPattern; out ErrorText: string): Boolean;
var D: TMusicStudioPatternSettings; A: TMusicStudioPsdAsset; Candidate: TMusicStudioPattern; Data: TMusicStudioInstrumentData;
begin
  Result := False; ErrorText := ''; Candidate := Pattern;
  if not Store.TryRead(AssetID,A,ErrorText) then Exit;
  if not MusicStudioHasInstrumentTimeline(Candidate.ConfigJSON) then begin
    Data := TMusicStudioInstrumentData.Create;
    try Data.Load(Candidate.ConfigJSON); Candidate.ConfigJSON := Data.JSON; finally Data.Free; end;
  end;
  D := TMusicStudioPatternSettings.Create(Owner);
  try
    D.SilentVisualMode := Silent;
    D.LoadPerformanceSteps(Candidate,AssetID,A.FilePath,A.ConfigJSON,BPM);
    while D.ShowModal=mrOK do begin
      try
        D.ReadPattern(Candidate); Candidate.ConfigJSON := MusicStudioPortablePerformance(Candidate.ConfigJSON);
        Pattern := Candidate; Exit(True);
      except on E: Exception do MessageDlg(E.Message,mtWarning,[mbOK],0); end;
    end;
  finally D.Free; end;
end;
end.
