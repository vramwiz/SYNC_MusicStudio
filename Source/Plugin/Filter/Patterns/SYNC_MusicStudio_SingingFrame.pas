unit SYNC_MusicStudio_SingingFrame;

// 歌唱固有UI。名前・色・確定は外側の共通フォームが担当する。
interface

uses
  System.Classes, System.Generics.Collections, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Dialogs,
  SYNC_MusicStudio_SingingData;

type
  TMusicStudioSingingFrame = class(TFrame)
  private
    FPath: string;
    FGeneration, FSelectedTrack: Integer;
    FJobs: TObjectList<TMusicStudioSingingJob>;
    FSource: TMusicStudioSingingSource;
    FPoll: TTimer;
    FStateLabel, FHintLabel: TLabel;
    FOpenDialog: TOpenDialog;
    FOnSourceChange: TNotifyEvent;
    procedure BuildUI;
    procedure BrowseClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure TrackChanged(Sender: TObject);
    procedure PollTimer(Sender: TObject);
    procedure ShowSource;
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    PathEdit: TEdit;
    TrackCombo: TComboBox;
    NotesList: TListView;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadSinging(const Path: string; TrackIndex: Integer);
    procedure SelectFile(const Path: string);
    procedure PollResults;
    function IsLoading: Boolean;
    function SelectedDuration: Double;
    property FilePath: string read FPath;
    property SelectedTrack: Integer read FSelectedTrack;
    property Source: TMusicStudioSingingSource read FSource;
    property OnSourceChange: TNotifyEvent read FOnSourceChange write FOnSourceChange;
  end;

implementation

uses System.SysUtils, System.IOUtils, Vcl.Graphics, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

{$R *.dfm}

constructor TMusicStudioSingingFrame.Create(AOwner: TComponent);
begin
  inherited;
  FSelectedTrack := -1;
  FJobs := TObjectList<TMusicStudioSingingJob>.Create(True);
  ApplySyncMusicStudioDarkFrame(Self);
  ApplyMusicStudioEditorFont(Self);
  BuildUI;
  FSource.Status := ssEmpty;
  FSource.Message := '歌詞付きMIDI / KARを選択してください。';
  FStateLabel.Caption := FSource.Message;
end;

destructor TMusicStudioSingingFrame.Destroy;
var Job: TMusicStudioSingingJob;
begin
  if Assigned(FPoll) then FPoll.Enabled := False;
  if Assigned(FJobs) then for Job in FJobs do Job.Terminate;
  FJobs.Free;
  inherited;
end;

procedure TMusicStudioSingingFrame.SetParent(AParent: TWinControl);
var Component: TComponent;
begin
  inherited;
  if AParent = nil then Exit;
  for Component in Self do
    if Component is TButton then ApplySyncMusicStudioDarkButton(TButton(Component));
end;

procedure TMusicStudioSingingFrame.BuildUI;
var L: TLabel; B: TButton; C: TListColumn; Header: TPanel; I,X: Integer;
  Titles: array[0..4] of string; Widths: array[0..4] of Integer;
begin
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 8, 600, 20); L.Caption := '歌詞付きMIDI / KAR  ・  ファイル参照';
  PathEdit := TEdit.Create(Self); PathEdit.Parent := Self;
  PathEdit.SetBounds(16, 34, Width - 236, 26);
  PathEdit.Anchors := [akLeft, akTop, akRight]; PathEdit.ReadOnly := True;
  ApplySyncMusicStudioDarkEdit(PathEdit);
  B := TMusicStudioButton.Create(Self); B.Parent := Self;
  B.SetBounds(Width - 212, 33, 100, 28); B.Anchors := [akTop, akRight];
  B.Caption := 'ファイル選択…'; B.OnClick := BrowseClick;
  B := TMusicStudioButton.Create(Self); B.Parent := Self;
  B.SetBounds(Width - 104, 33, 88, 28); B.Anchors := [akTop, akRight];
  B.Caption := '参照を解除'; B.OnClick := ClearClick;
  FStateLabel := TLabel.Create(Self); FStateLabel.Parent := Self;
  FStateLabel.SetBounds(16, 68, Width - 32, 36);
  FStateLabel.Anchors := [akLeft, akTop, akRight];
  FStateLabel.AutoSize := False; FStateLabel.WordWrap := True;
  TrackCombo := TComboBox.Create(Self); TrackCombo.Parent := Self;
  TrackCombo.SetBounds(16, 110, Width - 32, 26);
  TrackCombo.Anchors := [akLeft, akTop, akRight]; TrackCombo.Style := csDropDownList;
  TrackCombo.Color := $002E2E2E; TrackCombo.Font.Color := $00E3E3E3;
  TrackCombo.OnChange := TrackChanged;
  NotesList := TListView.Create(Self); NotesList.Parent := Self;
  Header := TPanel.Create(Self); Header.Parent := Self;
  Header.SetBounds(16,146,Width - 32,26); Header.Anchors := [akLeft,akTop,akRight];
  Header.BevelOuter := bvNone; Header.Color := $00373737; Header.ParentBackground := False;
  Titles[0] := '開始 (秒)'; Titles[1] := '長さ (秒)'; Titles[2] := '音高'; Titles[3] := '歌詞'; Titles[4] := '母音';
  Widths[0] := 90; Widths[1] := 90; Widths[2] := 62; Widths[3] := 250; Widths[4] := 130;
  X := 4;
  for I := 0 to 4 do begin
    L := TLabel.Create(Self); L.Parent := Header; L.SetBounds(X,4,Widths[I],18); L.Caption := Titles[I];
    Inc(X,Widths[I]);
  end;
  NotesList.SetBounds(16, 172, Width - 32, Height - 214);
  NotesList.Anchors := [akLeft, akTop, akRight, akBottom];
  NotesList.ViewStyle := vsReport; NotesList.ReadOnly := True; NotesList.RowSelect := True;
  NotesList.ShowColumnHeaders := False;
  NotesList.Color := $00222222; NotesList.Font.Color := $00E3E3E3;
  C := NotesList.Columns.Add; C.Caption := '開始 (秒)'; C.Width := 90;
  C := NotesList.Columns.Add; C.Caption := '長さ (秒)'; C.Width := 90;
  C := NotesList.Columns.Add; C.Caption := '音高'; C.Width := 62;
  C := NotesList.Columns.Add; C.Caption := '歌詞'; C.Width := 250;
  C := NotesList.Columns.Add; C.Caption := '母音'; C.Width := 130;
  FHintLabel := TLabel.Create(Self); FHintLabel.Parent := Self;
  FHintLabel.SetBounds(16, Height - 34, Width - 32, 30);
  FHintLabel.Anchors := [akLeft, akRight, akBottom]; FHintLabel.AutoSize := False;
  FHintLabel.WordWrap := True;
  FHintLabel.Caption := 'かなの母音を表示。? は読み不明。音符編集・歌声合成・口パク描画は未実装です。';
  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.Filter := '歌詞MIDI / KAR (*.mid;*.midi;*.kar)|*.mid;*.midi;*.kar|すべてのファイル|*.*';
  FOpenDialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
  FPoll := TTimer.Create(Self); FPoll.Interval := 80; FPoll.Enabled := False;
  FPoll.OnTimer := PollTimer;
end;

procedure TMusicStudioSingingFrame.LoadSinging(const Path: string; TrackIndex: Integer);
begin
  SelectFile(Path);
  FSelectedTrack := TrackIndex;
end;

procedure TMusicStudioSingingFrame.SelectFile(const Path: string);
var Job: TMusicStudioSingingJob;
begin
  Inc(FGeneration);
  for Job in FJobs do Job.Terminate;
  FPath := Path; PathEdit.Text := Path; PathEdit.Hint := Path; PathEdit.ShowHint := True;
  FSelectedTrack := -1; FSource := Default(TMusicStudioSingingSource);
  FSource.Status := ssEmpty;
  if Path = '' then FSource.Message := '歌詞付きMIDI / KARを選択してください。'
  else begin
    FSource.Message := 'MIDIの音符・歌詞・テンポを読み込み中…';
    Job := TMusicStudioSingingJob.Create(Path, FGeneration); FJobs.Add(Job); Job.Start;
  end;
  TrackCombo.Clear; TrackCombo.Enabled := False; NotesList.Items.Clear;
  FStateLabel.Caption := FSource.Message; FStateLabel.Font.Color := $00BFBFBF;
  FPoll.Enabled := FJobs.Count > 0;
end;

procedure TMusicStudioSingingFrame.BrowseClick(Sender: TObject);
begin
  FOpenDialog.FileName := FPath;
  if not FOpenDialog.Execute then Exit;
  SelectFile(TPath.GetFullPath(FOpenDialog.FileName));
  if Assigned(FOnSourceChange) then FOnSourceChange(Self);
end;

procedure TMusicStudioSingingFrame.ClearClick(Sender: TObject);
begin SelectFile(''); end;

procedure TMusicStudioSingingFrame.PollTimer(Sender: TObject);
begin PollResults; end;

procedure TMusicStudioSingingFrame.PollResults;
var I: Integer; Job: TMusicStudioSingingJob;
begin
  for I := FJobs.Count - 1 downto 0 do begin
    Job := FJobs[I]; if not Job.Done then Continue;
    if (Job.RequestID = FGeneration) and (Job.FilePath = FPath) then begin
      FSource := Job.Source; ShowSource;
    end;
    FJobs.Delete(I);
  end;
  FPoll.Enabled := FJobs.Count > 0;
end;

procedure TMusicStudioSingingFrame.ShowSource;
var I, Choice: Integer; T: TMusicStudioSingingTrack; Title: string;
begin
  FStateLabel.Caption := FSource.Message;
  if FSource.Status in [ssUnsupported, ssMissing, ssBroken] then FStateLabel.Font.Color := $0090A5F3
  else FStateLabel.Font.Color := $00BFBFBF;
  TrackCombo.Clear; Choice := -1;
  for I := 0 to High(FSource.Tracks) do begin
    T := FSource.Tracks[I]; Title := T.Name;
    if Title = '' then Title := 'トラック ' + IntToStr(T.Index + 1);
    TrackCombo.Items.Add(Format('%d: %s  ・  音符 %d / 歌詞 %d', [T.Index + 1, Title, T.NoteCount, T.LyricCount]));
    if T.Index = FSelectedTrack then Choice := I;
  end;
  if (Choice < 0) and (FSelectedTrack < 0) then
    for I := 0 to High(FSource.Tracks) do
      if FSource.Tracks[I].LyricCount > 0 then begin Choice := I; Break; end;
  if (Choice < 0) and (FSelectedTrack < 0) and (TrackCombo.Items.Count > 0) then Choice := 0;
  TrackCombo.Enabled := TrackCombo.Items.Count > 0;
  TrackCombo.ItemIndex := Choice;
  if (Choice < 0) and (FSelectedTrack >= 0) and (TrackCombo.Items.Count > 0) then
    FStateLabel.Caption := FStateLabel.Caption + ' / 保存済みのトラックがありません。再選択してください。';
  TrackChanged(nil);
end;

procedure TMusicStudioSingingFrame.TrackChanged(Sender: TObject);
var Note: TMusicStudioSingingNote; Item: TListItem; Count: Integer; Track: TMusicStudioSingingTrack;
begin
  if TrackCombo.ItemIndex >= 0 then FSelectedTrack := FSource.Tracks[TrackCombo.ItemIndex].Index;
  if TrackCombo.ItemIndex >= 0 then begin
    Track := FSource.Tracks[TrackCombo.ItemIndex];
    if Track.LyricCount = 0 then
      FStateLabel.Caption := Format('選択トラックに歌詞がありません。音符 %d件 / 別のトラックを選択できます。',[Track.NoteCount])
    else FStateLabel.Caption := Format('選択トラック: 音符 %d件 / 歌詞 %d件  ・  %.3f秒',[Track.NoteCount,Track.LyricCount,Track.Duration]);
  end;
  NotesList.Items.BeginUpdate;
  try
    NotesList.Items.Clear; Count := 0;
    for Note in FSource.Notes do begin
      if Note.TrackIndex <> FSelectedTrack then Continue;
      Inc(Count); if Count > 2000 then Continue;
      Item := NotesList.Items.Add; Item.Caption := Format('%.3f', [Note.StartSeconds]);
      Item.SubItems.Add(Format('%.3f', [Note.EndSeconds - Note.StartSeconds]));
      Item.SubItems.Add(IntToStr(Note.Key)); Item.SubItems.Add(Note.Lyric); Item.SubItems.Add(Note.Vowels);
    end;
    FHintLabel.Caption := 'かなの母音を表示。? は読み不明。音符編集・歌声合成・口パク描画は未実装です。';
    if Count > 2000 then FHintLabel.Caption := '音符一覧は先頭2000件を表示。' + FHintLabel.Caption;
  finally NotesList.Items.EndUpdate; end;
end;

function TMusicStudioSingingFrame.IsLoading: Boolean;
var Job: TMusicStudioSingingJob;
begin
  Result := False;
  for Job in FJobs do if Job.RequestID = FGeneration then Exit(True);
end;

function TMusicStudioSingingFrame.SelectedDuration: Double;
var T: TMusicStudioSingingTrack;
begin
  Result := 0;
  for T in FSource.Tracks do if T.Index = FSelectedTrack then Exit(T.Duration);
end;

end.
