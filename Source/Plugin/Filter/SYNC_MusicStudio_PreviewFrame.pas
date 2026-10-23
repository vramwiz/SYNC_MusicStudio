unit SYNC_MusicStudio_PreviewFrame;

// 編集プレビューの時計とPSD部位/MIDI表示。文書を借用し、音声出力とPSDシーンを所有。
interface
uses System.Classes, System.Types, Winapi.Messages, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Controls,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_PreviewPlayback,
  SYNC_MusicStudio_SingingData, SYNC_MusicStudio_VisualCache,
  SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_PsdSceneCache,
  SYNC_MusicStudio_HostBackground, SYNC_MusicStudio_PsdTransform, SYNC_MusicStudio_PsdPlacementEditor,
  SYNC_MusicStudio_PsdLayerFrameUI;
type
  TMusicStudioTempoEditEvent = function(Beat,BPM: Double; out ErrorText: string): Boolean of object;
  TMusicStudioPreviewFrame = class(TFrame)
  private
    FDocument: TMusicStudioDocument;
    FPlayback: TMusicStudioPlaybackJob;
    FTimer: TTimer;
    FPosition,FEnd,FContentEnd: Double; // FEnd is preview navigation; content references keep their own seconds.
    FTempoLabel: TLabel;
    FTempoEditing,FTempoDirty,FTempoUpdating,FTempoCommitting: Boolean;
    FTempoEditBeat: Double;
    FOnTempoEdit: TMusicStudioTempoEditEvent;
    FChanging: Boolean;
    FSilentVisualMode, FVisualRunning: Boolean;
    FVisualStart: UInt64;
    FVisualOrigin: Double;
    FMidiDoneCount: Integer;
    FPeak: Single;
    FStatus,FTransport: TLabel;
    FFooter: TPanel;
    FPsdNames: TArray<string>;
    FMidiJobs: TArray<TMusicStudioSingingJob>;
    FMidiIDs: TArray<string>;
    FSharedVisualCache: TMusicStudioVisualCache; // ArrangementView所有。フォーム破棄前に接続を外す。
    FSharedLibrary: TMusicStudioSharedPsdLibrary; // 設定フォーム所有。Bind時のみ借用する。
    FSceneCache: TMusicStudioPsdSceneCache;
    FTrackIndices: TArray<Integer>;
    FVisualSerial: Integer;
    FOnPositionChange: TNotifyEvent;
    FOnReadHostBackground: TMusicStudioReadBackground;
    FHostBackground: Vcl.Graphics.TBitmap;
    FBackgroundWidth,FBackgroundHeight: Integer;
    FBackgroundSerial: UInt64;
    FBackgroundFrame: Integer;
    FBackgroundStatus: string;
    FPlacement: TMusicStudioPsdPlacementEditor;
    FFlipped: array[0..3] of Vcl.Graphics.TBitmap;
    FFlipSerial,FFlipFlags: array[0..3] of Integer;
    function DisplayImage(Index: Integer): Vcl.Graphics.TBitmap;
    procedure StageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure StageMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure StageMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure StageCaptureLost(Sender: TObject);
    procedure WMPlacementCaptureLost(var Message: TMessage); message WM_APP+108;
    function VideoRect: TRect;
    procedure SetSilentVisualMode(Value: Boolean);
    function PreviewImage(Index: Integer): Vcl.Graphics.TBitmap;
    procedure Tick(Sender: TObject);
    procedure PaintStage(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure SeekChanged(Sender: TObject);
    procedure ClearAssets;
    procedure ReleasePlayback;
    procedure UpdatePosition;
    function LyricAtPosition: string;
    function LoadedImageCount: Integer;
    procedure TempoEnter(Sender: TObject);
    procedure TempoChanged(Sender: TObject);
    procedure TempoExit(Sender: TObject);
    procedure TempoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    procedure Resize; override;
  public
    Stage: TMusicStudioPsdPreviewSurface;
    PlayButton,StopButton: TButton;
    TempoEdit: TEdit;
    SeekBar: TTrackBar;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 文書切替時は旧再生/ジョブを停止してから新しい参照を借用する。
    procedure Bind(Document: TMusicStudioDocument);
    procedure StartSilentVisualPreview;
    procedure Play;
    procedure TogglePlayback;
    procedure Pause;
    procedure Stop;
    procedure Seek(Seconds: Double);
    procedure RestoreMusicalCursor(Beat,EndBeat: Double; Resume: Boolean);
    procedure ValidateMusicalCursor(Beat,EndBeat: Double);
    function ApplyTempoEdit: Boolean;
    procedure CancelTempoEdit;
    procedure RefreshTempoText(Force: Boolean = False);
    function HandleTempoKey(var Key: Word; Shift: TShiftState): Boolean;
    procedure RefreshHostBackground;
    procedure ClearHostBackground;
    function IsPlaying: Boolean;
    function IsAudioEngineAllocated: Boolean;
    function PlaybackSnapshot: TMusicStudioPlaybackSnapshot;
    function CharacterBounds(TrackIndex: Integer; out Video,Bounds: TRect): Boolean;
    property PlacementEditor: TMusicStudioPsdPlacementEditor read FPlacement;
    property SilentVisualMode: Boolean read FSilentVisualMode write SetSilentVisualMode;
    property AudioEngineAllocated: Boolean read IsAudioEngineAllocated;
    property Position: Double read FPosition;
    property EndSeconds: Double read FEnd;
    property ContentEndSeconds: Double read FContentEnd;
    property CurrentLyric: string read LyricAtPosition;
    property ImageCount: Integer read LoadedImageCount;
    property SharedVisualCache: TMusicStudioVisualCache read FSharedVisualCache write FSharedVisualCache;
    property SharedLibrary: TMusicStudioSharedPsdLibrary read FSharedLibrary write FSharedLibrary;
    property SceneCache: TMusicStudioPsdSceneCache read FSceneCache;
    property OnPositionChange: TNotifyEvent read FOnPositionChange write FOnPositionChange;
    property OnTempoEdit: TMusicStudioTempoEditEvent read FOnTempoEdit write FOnTempoEdit;
    property OnReadHostBackground: TMusicStudioReadBackground read FOnReadHostBackground write FOnReadHostBackground;
    property HostBackgroundSerial: UInt64 read FBackgroundSerial;
    property HostBackgroundFrame: Integer read FBackgroundFrame;
    property HostBackgroundStatus: string read FBackgroundStatus;
    property DisplayVideoRect: TRect read VideoRect;
  end;
implementation
{$POINTERMATH ON}
uses AviUtl2FilterTypes, System.SysUtils, System.Math, System.UITypes, Winapi.Windows,
  SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_ArrangementData;
{$R *.dfm}
constructor TMusicStudioPreviewFrame.Create(AOwner: TComponent);
  function ButtonAt(X,W: Integer; const Caption: string; Event: TNotifyEvent): TButton;
  begin Result := TMusicStudioButton.Create(Self); Result.Parent := FFooter;
    Result.SetBounds(X,8,W,28); Result.Caption := Caption; Result.OnClick := Event; end;
begin
  inherited; ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self); FEnd := 10; DoubleBuffered := True;
  FSceneCache := TMusicStudioPsdSceneCache.Create;
  FHostBackground := Vcl.Graphics.TBitmap.Create;
  FFooter := TPanel.Create(Self); FFooter.Parent := Self; FFooter.Align := alBottom;
  FFooter.Height := 84; FFooter.BevelOuter := bvNone; ApplySyncMusicStudioDarkPanel(FFooter);
  PlayButton := ButtonAt(12,104,'▶ 再生',PlayClick);
  PlayButton.ShowHint := True;
  StopButton := ButtonAt(124,104,'■ 停止',StopClick);
  FTempoLabel := TLabel.Create(Self); FTempoLabel.Parent := FFooter; FTempoLabel.SetBounds(238,13,32,20); FTempoLabel.Caption := 'BPM';
  TempoEdit := TEdit.Create(Self); TempoEdit.Parent := FFooter; TempoEdit.SetBounds(274,8,82,28); TempoEdit.Text := '120';
  ApplySyncMusicStudioDarkEdit(TempoEdit); TempoEdit.ShowHint := True;
  TempoEdit.Hint := '入力開始時のカーソル区間を編集。Enter/欄を離れると確定、Escで取消。テンポclip中はこの配置だけへ補正。';
  TempoEdit.OnEnter := TempoEnter; TempoEdit.OnChange := TempoChanged; TempoEdit.OnExit := TempoExit; TempoEdit.OnKeyDown := TempoKeyDown;
  FTransport := TLabel.Create(Self); FTransport.Parent := FFooter; FTransport.AutoSize := False;
  FTransport.SetBounds(370,10,400,24);
  FTransport.ShowHint := True;
  FStatus := TLabel.Create(Self); FStatus.Parent := FFooter; FStatus.AutoSize := False;
  FStatus.SetBounds(12,38,Width-24,20); FStatus.Anchors := [akLeft,akTop,akRight];
  FStatus.Caption := 'PSD部位・母音・表情・アニメーションの編集プレビュー。歌声生成は未対応。';
  SeekBar := TTrackBar.Create(Self); SeekBar.Parent := FFooter; SeekBar.SetBounds(8,59,Width-16,24);
  SeekBar.Anchors := [akLeft,akTop,akRight]; SeekBar.Min := 0; SeekBar.Max := 10000;
  SeekBar.TickStyle := tsNone; SeekBar.OnChange := SeekChanged;
  Stage := TMusicStudioPsdPreviewSurface.Create(Self); Stage.Parent := Self; Stage.Align := alClient; Stage.OnPaint := PaintStage;
  Stage.TabStop := False; FFooter.DoubleBuffered := True;
  FPlacement := TMusicStudioPsdPlacementEditor.Create(Stage); FPlacement.OnBounds := CharacterBounds;
  Stage.OnMouseDown := StageMouseDown; Stage.OnMouseMove := StageMouseMove; Stage.OnMouseUp := StageMouseUp;
  Stage.OnCaptureLost := StageCaptureLost;
  Stage.ShowHint := True; FStatus.ShowHint := True;
  FTimer := TTimer.Create(Self); FTimer.Interval := 30; FTimer.OnTimer := Tick;
  UpdatePosition;
end;
destructor TMusicStudioPreviewFrame.Destroy;
begin FTimer.Enabled := False; FOnReadHostBackground := nil; FOnPositionChange := nil;
  FOnTempoEdit := nil;
  Stage.OnCaptureLost := nil; FreeAndNil(FPlacement);
  ReleasePlayback; ClearAssets; FSceneCache.Free; FHostBackground.Free; FDocument := nil; inherited; end;

procedure TMusicStudioPreviewFrame.ClearHostBackground;
begin
  FBackgroundSerial := 0; FBackgroundWidth := 0; FBackgroundHeight := 0;
  FHostBackground.SetSize(0,0); Stage.Invalidate;
end;

procedure TMusicStudioPreviewFrame.RefreshHostBackground;
var Snapshot: TMusicStudioBackgroundSnapshot; X,Y: Integer; Row: PByte; P: TPIXEL_RGBA;
begin
  if not Assigned(FOnReadHostBackground) then Exit;
  if not FOnReadHostBackground(FBackgroundSerial,Snapshot) then begin
    if FBackgroundSerial<>0 then ClearHostBackground;
    FBackgroundStatus := Snapshot.Status;
    if FBackgroundStatus='' then FBackgroundStatus := '背景未取得: AviUtl2の対象描画を待っています。';
    Stage.Hint := FBackgroundStatus;
    if not Assigned(FPlayback) then FStatus.Caption := '背景未取得: AviUtl2の対象描画を待っています。';
    Exit;
  end;
  FBackgroundStatus := Snapshot.Status;
  Stage.Hint := 'AviUtl2の描画前フレームバッファを静止画として表示。'+sLineBreak+
    '編集側のシークはPSD/MIDIのみ。背景はホスト描画時に更新します。'+sLineBreak+FBackgroundStatus;
  if not Assigned(FPlayback) then FStatus.Caption := 'AviUtl2の描画前背景（静止画） · 詳細は背景のツールチップ';
  if Snapshot.Serial=FBackgroundSerial then Exit;
  if (Snapshot.Width<1) or (Snapshot.Height<1) or
    (Length(Snapshot.Pixels)<>Int64(Snapshot.Width)*Snapshot.Height) then begin ClearHostBackground; Exit; end;
  FHostBackground.PixelFormat := pf32bit; FHostBackground.SetSize(Snapshot.Width,Snapshot.Height);
  FHostBackground.AlphaFormat := afPremultiplied;
  for Y := 0 to Snapshot.Height-1 do begin
    Row := FHostBackground.ScanLine[Y];
    for X := 0 to Snapshot.Width-1 do begin
      P := Snapshot.Pixels[Y*Snapshot.Width+X];
      Row[X*4] := P.B; Row[X*4+1] := P.G; Row[X*4+2] := P.R; Row[X*4+3] := P.A;
    end;
  end;
  FBackgroundWidth := Snapshot.Width; FBackgroundHeight := Snapshot.Height;
  FBackgroundFrame := Snapshot.Frame; FBackgroundSerial := Snapshot.Serial;
  Stage.Invalidate;
end;

function TMusicStudioPreviewFrame.VideoRect: TRect;
var W,H,M: Integer;
begin
  M := MulDiv(24,CurrentPPI,96); W := 16; H := 9;
  if FBackgroundSerial<>0 then begin W := FBackgroundWidth; H := FBackgroundHeight; end;
  Result := MusicStudioFitFrameRect(Rect(M,M,Max(M+1,Stage.Width-M),Max(M+1,Stage.Height-M)),W,H);
end;
procedure TMusicStudioPreviewFrame.Resize;
begin
  inherited;
  if Assigned(FPlacement) then FPlacement.Cancel;
  if Assigned(FTransport) then FTransport.Width := Max(1,FFooter.ClientWidth-FTransport.Left-12);
end;
procedure TMusicStudioPreviewFrame.ClearAssets;
var I: Integer;
begin
  FSceneCache.Clear; FTrackIndices := nil;
  for I := 0 to High(FFlipped) do begin FreeAndNil(FFlipped[I]); FFlipSerial[I] := -1; end;
  for I := 0 to High(FMidiJobs) do FMidiJobs[I].Terminate;
  for I := 0 to High(FMidiJobs) do FMidiJobs[I].Free;
  FMidiJobs := nil; FMidiIDs := nil; FPsdNames := nil; FMidiDoneCount := 0;
end;
procedure TMusicStudioPreviewFrame.Bind(Document: TMusicStudioDocument);
var I,N: Integer; T: TMusicStudioTrack; P: TMusicStudioPattern; Clips: TMusicStudioPreviewClips;
begin
  Stop; ClearAssets; FDocument := Document;
  FPlacement.Bind(Document);
  Stage.Hint := '';
  if FSilentVisualMode then FStatus.Caption := '無音表示: 音声の解析・出力は停止しています。'
  else FStatus.Caption := 'PSD部位・母音・表情・アニメーションの編集プレビュー。歌声生成は未対応。';
  if Assigned(Document) then begin
    try Clips := BuildMusicStudioPreviewClips(Document,FContentEnd); FEnd := FContentEnd;
    except on E: Exception do begin FEnd := 10; FContentEnd := 10; FStatus.Caption := E.Message; end; end;
    for I := 0 to Document.TrackCount-1 do begin
      T := Document.TrackAt(I);
      if (T.Kind='psd') and (Length(FTrackIndices)<4) then begin
        N := Length(FTrackIndices);
        SetLength(FTrackIndices,N+1); FTrackIndices[N] := I;
        SetLength(FPsdNames,N+1); FPsdNames[N] := T.Name;
      end;
    end;
    for I := 0 to Document.PatternCount-1 do begin
      P := Document.PatternAt(I);
      if (FSharedVisualCache=nil) and (P.Kind='singing') and (Length(FMidiJobs)<4) then begin
        N := Length(FMidiJobs); SetLength(FMidiJobs,N+1); SetLength(FMidiIDs,N+1);
        FMidiIDs[N] := P.ID; FMidiJobs[N] := TMusicStudioSingingJob.Create(P.FilePath,N); FMidiJobs[N].Start;
      end;
    end;
  end else begin FEnd := 10; FContentEnd := 10; end;
  FSceneCache.Bind(Document,FSharedLibrary,FSharedVisualCache);
  FSceneCache.SetPosition(0);
  if not FTempoCommitting then CancelTempoEdit;
  PlayButton.Enabled := Assigned(Document); SeekBar.Enabled := Assigned(Document); UpdatePosition; Stage.Invalidate;
end;
procedure TMusicStudioPreviewFrame.ReleasePlayback;
begin
  if Assigned(FPlayback) then begin FPlayback.Terminate; FPlayback.WaitFor; FreeAndNil(FPlayback); end;
  FVisualRunning := False; FPeak := 0;
end;
procedure TMusicStudioPreviewFrame.SetSilentVisualMode(Value: Boolean);
begin
  Stop; FSilentVisualMode := Value;
  if Value then FStatus.Caption := '無音表示: 音声の解析・出力は停止しています。';
  if not FTempoCommitting then CancelTempoEdit;
  UpdatePosition;
end;
procedure TMusicStudioPreviewFrame.RefreshTempoText(Force: Boolean);
var BPM: Double;
begin
  if (TempoEdit=nil) or (not Force and FTempoEditing) then Exit;
  BPM := 120; if FDocument<>nil then BPM := FDocument.Timing.BPMAt(FDocument.SecondsToBeat(FPosition));
  FTempoUpdating := True;
  try TempoEdit.Text := FloatToStr(BPM,TFormatSettings.Invariant); finally FTempoUpdating := False; end;
end;
procedure TMusicStudioPreviewFrame.TempoEnter(Sender: TObject);
begin
  RefreshTempoText(True); FTempoEditing := True; FTempoDirty := False;
  FTempoEditBeat := 0; if FDocument<>nil then FTempoEditBeat := FDocument.SecondsToBeat(FPosition);
end;
procedure TMusicStudioPreviewFrame.TempoChanged(Sender: TObject);
begin if not FTempoUpdating then FTempoDirty := True; end;
procedure TMusicStudioPreviewFrame.TempoExit(Sender: TObject);
begin
  if FTempoDirty then ApplyTempoEdit;
  FTempoEditing := False; FTempoDirty := False; RefreshTempoText(True);
end;
function TMusicStudioPreviewFrame.ApplyTempoEdit: Boolean;
var BPM: Double; Error: string;
begin
  Result := False;
  if not TryStrToFloat(Trim(TempoEdit.Text),BPM,TFormatSettings.Invariant) or IsNan(BPM) or IsInfinite(BPM) or (BPM<1) or (BPM>999.99) then
    Error := 'BPMは1～999.99の数値で入力してください。'
  else if not Assigned(FOnTempoEdit) then Error := 'BPMの編集先がありません。'
  else begin
    FTempoCommitting := True;
    try Result := FOnTempoEdit(FTempoEditBeat,BPM,Error); finally FTempoCommitting := False; end;
  end;
  if Result then begin FTempoDirty := False; RefreshTempoText(True);
    if FDocument<>nil then FTempoEditBeat := FDocument.SecondsToBeat(FPosition);
  end else FStatus.Caption := Error;
end;
procedure TMusicStudioPreviewFrame.CancelTempoEdit;
begin
  FTempoDirty := False; FTempoEditing := Assigned(TempoEdit) and TempoEdit.Focused;
  RefreshTempoText(True); if FDocument<>nil then FTempoEditBeat := FDocument.SecondsToBeat(FPosition);
end;
function TMusicStudioPreviewFrame.HandleTempoKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := TempoEdit.Focused and (Shift=[]) and ((Key=VK_RETURN) or (Key=VK_ESCAPE)); if not Result then Exit;
  if Key=VK_ESCAPE then CancelTempoEdit else if FTempoDirty then ApplyTempoEdit; Key := 0;
end;
procedure TMusicStudioPreviewFrame.TempoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin HandleTempoKey(Key,Shift); end;
procedure TMusicStudioPreviewFrame.StartSilentVisualPreview;
begin
  if not FSilentVisualMode or not Assigned(FDocument) or IsPlaying then Exit;
  if FPosition>=FEnd then FPosition := 0;
  FVisualOrigin := FPosition; FVisualStart := GetTickCount64; FVisualRunning := True;
  FStatus.Caption := '無音表示: 表示用時計だけを進めます。'; UpdatePosition;
end;
function TMusicStudioPreviewFrame.IsAudioEngineAllocated: Boolean;
begin Result := Assigned(FPlayback); end;
procedure TMusicStudioPreviewFrame.Play;
var Clips: TMusicStudioPreviewClips;
begin
  if FSilentVisualMode then begin StartSilentVisualPreview; Exit; end;
  if Assigned(FPlayback) and FPlayback.Done then ReleasePlayback;
  if not Assigned(FDocument) or Assigned(FPlayback) then Exit;
  try
    Clips := BuildMusicStudioPreviewClips(FDocument,FContentEnd); FEnd := Max(FEnd,FContentEnd);
    if FPosition>=FEnd then FPosition := 0;
    FPlayback := TMusicStudioPlaybackJob.Create(Clips,FPosition,FEnd); FPlayback.Start;
    FStatus.Caption := '準備中…  歌声生成・音符からの手足動作生成は未対応。';
  except on E: Exception do begin ReleasePlayback; FStatus.Caption := E.Message; end; end;
  UpdatePosition;
end;
procedure TMusicStudioPreviewFrame.TogglePlayback;
begin if IsPlaying then Pause else Play; end;
procedure TMusicStudioPreviewFrame.Pause;
begin
  if Assigned(FPlayback) then FPosition := FPlayback.Snapshot.Position;
  if FVisualRunning then FPosition := Min(FEnd,FVisualOrigin+(GetTickCount64-FVisualStart)/1000);
  ReleasePlayback; FStatus.Caption := '一時停止。再生でこの位置から続けます。'; UpdatePosition;
end;
procedure TMusicStudioPreviewFrame.Stop;
begin ReleasePlayback; FPosition := 0; UpdatePosition; end;
procedure TMusicStudioPreviewFrame.Seek(Seconds: Double);
var Resume: Boolean;
begin
  Resume := IsPlaying; ReleasePlayback; FPosition := EnsureRange(Seconds,0.0,FEnd);
  UpdatePosition; if Resume and (FPosition<FEnd) then Play;
end;
procedure TMusicStudioPreviewFrame.RestoreMusicalCursor(Beat,EndBeat: Double; Resume: Boolean);
var Position,RangeEnd: Double;
begin
  if FDocument=nil then Exit;
  if EndBeat<=Beat then EndBeat := Beat+FDocument.Timing.MeasureLengthAtBeat(Beat);
  Position := FDocument.BeatToSeconds(Beat); RangeEnd := FDocument.BeatToSeconds(EndBeat);
  ReleasePlayback; FPosition := Max(0.0,Position); FEnd := Max(FContentEnd,Max(FPosition,RangeEnd));
  UpdatePosition; if Resume and (FPosition<FEnd) then Play;
end;
procedure TMusicStudioPreviewFrame.ValidateMusicalCursor(Beat,EndBeat: Double);
begin
  if FDocument=nil then raise EInvalidOperation.Create('作品を読み込んでください。');
  if EndBeat<=Beat then EndBeat := Beat+FDocument.Timing.MeasureLengthAtBeat(Beat);
  FDocument.BeatToSeconds(Beat); FDocument.BeatToSeconds(EndBeat);
end;
function TMusicStudioPreviewFrame.IsPlaying: Boolean;
begin Result := FVisualRunning or (Assigned(FPlayback) and not FPlayback.Done); end;
function TMusicStudioPreviewFrame.PlaybackSnapshot: TMusicStudioPlaybackSnapshot;
begin
  Result := Default(TMusicStudioPlaybackSnapshot); Result.Position := FPosition;
  if Assigned(FPlayback) then Result := FPlayback.Snapshot;
end;
procedure TMusicStudioPreviewFrame.UpdatePosition;
begin
  RefreshTempoText;
  PlayButton.Enabled := Assigned(FDocument);
  StopButton.Enabled := Assigned(FDocument);
  TempoEdit.Enabled := Assigned(FDocument);
  if IsPlaying then begin
    PlayButton.Caption := 'Ⅱ 一時停止';
    PlayButton.Hint := '一時停止（この位置から再開できます）';
  end else begin
    PlayButton.Caption := '▶ 再生';
    PlayButton.Hint := '再生（現在位置から開始）';
  end;
  if FSilentVisualMode then PlayButton.Hint := PlayButton.Hint+' · 無音表示';
  FChanging := True;
  try SeekBar.Position := Round(EnsureRange(FPosition/Max(0.001,FEnd),0.0,1.0)*10000);
  finally FChanging := False; end;
  FTransport.Caption := Format('%.2f / %.2f 秒   ·   30 fps位置 %d',[FPosition,FEnd,Floor(FPosition*30)]);
  FTransport.Hint := Format('プレビュー範囲: %.2f秒 / 素材配置の終端: %.2f秒。BPM編集後も音源の長さは変えません。',[FEnd,FContentEnd]);
  FSceneCache.SetPosition(FPosition);
  if Assigned(FOnPositionChange) then FOnPositionChange(Self); Stage.Invalidate;
end;
procedure TMusicStudioPreviewFrame.Tick(Sender: TObject);
var S: TMusicStudioPlaybackSnapshot; I,MidiDone: Integer;
begin
  RefreshHostBackground;
  if FSceneCache.PollResults then Stage.Invalidate;
  if FVisualRunning then begin
    FPosition := Min(FEnd,FVisualOrigin+(GetTickCount64-FVisualStart)/1000);
    if FPosition>=FEnd then FVisualRunning := False;
    UpdatePosition;
  end;
  MidiDone := 0;
  if Assigned(FSharedVisualCache) and (FVisualSerial<>FSharedVisualCache.Serial) then begin
    FVisualSerial := FSharedVisualCache.Serial; Stage.Invalidate;
  end;
  for I := 0 to High(FMidiJobs) do if FMidiJobs[I].Done then Inc(MidiDone);
  if MidiDone<>FMidiDoneCount then begin FMidiDoneCount := MidiDone; Stage.Invalidate; end;
  if Assigned(FPlayback) then begin
    S := FPlayback.Snapshot; FPosition := S.Position; FPeak := S.Peak;
    if S.State=psPreparing then FStatus.Caption := '音声出力を準備中…'
    else if S.Message<>'' then FStatus.Caption := S.Message
    else FStatus.Caption := '音声試聴 · 配置開始/長さ/音量を反映。PSD部位・表情・アニメーション / 歌声生成なし。';
    if FPlayback.Done then begin
      ReleasePlayback;
      if S.State=psFailed then FStatus.Caption := '再生できません: '+S.Message;
    end;
    UpdatePosition;
  end;
  FStatus.Hint := FStatus.Caption+sLineBreak+Stage.Hint;
end;
procedure TMusicStudioPreviewFrame.PlayClick(Sender: TObject);
begin TogglePlayback; end;
procedure TMusicStudioPreviewFrame.StopClick(Sender: TObject); begin Stop; end;
procedure TMusicStudioPreviewFrame.SeekChanged(Sender: TObject);
begin if not FChanging then Seek(SeekBar.Position/10000*FEnd); end;
function TMusicStudioPreviewFrame.PreviewImage(Index: Integer): Vcl.Graphics.TBitmap;
begin
  Result := FSceneCache.ImageForTrack(FTrackIndices[Index]);
end;
function TMusicStudioPreviewFrame.LoadedImageCount: Integer;
var I: Integer;
begin Result := 0; for I := 0 to High(FTrackIndices) do if Assigned(PreviewImage(I)) then Inc(Result); end;
function TMusicStudioPreviewFrame.LyricAtPosition: string;
var I,J,K,L,NoteIndex: Integer; Track: TMusicStudioTrack; Slot: TMusicStudioSlot; Clip: TMusicStudioPlacement;
  Note: TMusicStudioSingingNote; Pattern: TMusicStudioPattern;
  Source: TMusicStudioVisualSource; Roll: TMusicStudioRollTrack;
  LocalTime: Double;
begin
  Result := '';
  if Assigned(FDocument) then for I := 0 to FDocument.TrackCount-1 do begin
    Track := FDocument.TrackAt(I);
    for Slot in Track.Slots do for Clip in Slot.Clips do begin
      if (FPosition<Clip.StartSeconds) or (FPosition>=Clip.StartSeconds+Clip.LengthSeconds) then Continue;
      if Assigned(FSharedVisualCache) then begin
        for L := 0 to FDocument.PatternCount-1 do begin
          Pattern := FDocument.PatternAt(L); if (Pattern.ID<>Clip.PatternID) or (Pattern.Kind<>'singing') then Continue;
          Source := FSharedVisualCache.Find(vkMidi,Pattern.FilePath);
          if (Source=nil) or (Source.Status<>vsReady) or (Source.Rolls=nil) or not Source.Rolls.TryGetValue(Pattern.SourceTrack,Roll) then Continue;
          LocalTime := FPosition-Clip.StartSeconds+Pattern.SourceStartSeconds; NoteIndex := Roll.FirstOverlap(LocalTime);
          while NoteIndex<Length(Roll.Notes) do begin
            Note := Roll.Notes[NoteIndex]; if Note.StartSeconds>LocalTime then Break;
            if LocalTime<Note.EndSeconds then Result := Result+Format('%s [%d] ',[Note.Lyric,Note.Key]); Inc(NoteIndex);
          end;
        end;
        Continue;
      end;
      for J := 0 to High(FMidiJobs) do if (FMidiIDs[J]=Clip.PatternID) and FMidiJobs[J].Done then begin
        if not (FMidiJobs[J].Source.Status in [ssReady,ssNoLyrics]) then
          Result := 'MIDI: '+FMidiJobs[J].Source.Message;
        K := -1;
        for L := 0 to FDocument.PatternCount-1 do begin Pattern := FDocument.PatternAt(L); if Pattern.ID=Clip.PatternID then begin K := Pattern.SourceTrack; Break; end; end;
        for Note in FMidiJobs[J].Source.Notes do if (Note.TrackIndex=K) and
          (FPosition-Clip.StartSeconds+Pattern.SourceStartSeconds>=Note.StartSeconds) and
          (FPosition-Clip.StartSeconds+Pattern.SourceStartSeconds<Note.EndSeconds) then
          Result := Result+Format('%s [%d] ',[Note.Lyric,Note.Key]);
      end;
    end;
  end;
end;
procedure TMusicStudioPreviewFrame.StageMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin FPlacement.MouseDown(Button,X,Y); end;
procedure TMusicStudioPreviewFrame.StageMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
begin FPlacement.MouseMove(X,Y); end;
procedure TMusicStudioPreviewFrame.StageMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin FPlacement.MouseUp(Button,X,Y); end;
procedure TMusicStudioPreviewFrame.StageCaptureLost(Sender: TObject);
begin PostMessage(Handle,WM_APP+108,0,0); end;
procedure TMusicStudioPreviewFrame.WMPlacementCaptureLost(var Message: TMessage);
begin if Assigned(FPlacement) and FPlacement.Dragging and (GetCapture<>Stage.Handle) then FPlacement.Cancel; end;
function TMusicStudioPreviewFrame.CharacterBounds(TrackIndex: Integer; out Video,Bounds: TRect): Boolean;
var I: Integer; Image: Vcl.Graphics.TBitmap; Transform: TMusicStudioPsdTransform;
begin
  Result := False; Video := VideoRect; Bounds := TRect.Empty;
  for I := 0 to High(FTrackIndices) do if FTrackIndices[I]=TrackIndex then begin
    Image := PreviewImage(I); if Image=nil then Exit;
    Transform := FPlacement.EffectiveTransform(TrackIndex);
    Bounds := MusicStudioTransformedRect(Transform,Video.Width,Video.Height,
      MusicStudioCharacterRect(Video.Width,Video.Height,Length(FTrackIndices),I,Image.Width,Image.Height));
    OffsetRect(Bounds,Video.Left,Video.Top); Exit(True);
  end;
end;
function TMusicStudioPreviewFrame.DisplayImage(Index: Integer): Vcl.Graphics.TBitmap;
var Source: Vcl.Graphics.TBitmap; Transform: TMusicStudioPsdTransform; Flags,X,Y,SX,SY: Integer; Dest,Src: PCardinal;
begin
  Source := PreviewImage(Index); Result := Source; if Source=nil then Exit;
  Transform := FPlacement.EffectiveTransform(FTrackIndices[Index]);
  Flags := Ord(Transform.FlipX)+2*Ord(Transform.FlipY); if Flags=0 then Exit;
  if (FFlipped[Index]=nil) or (FFlipSerial[Index]<>FSceneCache.Serial) or (FFlipFlags[Index]<>Flags) then begin
    if FFlipped[Index]=nil then FFlipped[Index] := Vcl.Graphics.TBitmap.Create;
    FFlipped[Index].PixelFormat := pf32bit; FFlipped[Index].SetSize(Source.Width,Source.Height);
    FFlipped[Index].AlphaFormat := afPremultiplied;
    for Y := 0 to Source.Height-1 do begin
      SY := Y; if Transform.FlipY then SY := Source.Height-1-Y;
      Src := Source.ScanLine[SY]; Dest := FFlipped[Index].ScanLine[Y];
      for X := 0 to Source.Width-1 do begin
        SX := X; if Transform.FlipX then SX := Source.Width-1-X;
        Dest[X] := Src[SX];
      end;
    end;
    FFlipSerial[Index] := FSceneCache.Serial; FFlipFlags[Index] := Flags;
  end;
  Result := FFlipped[Index];
end;
procedure TMusicStudioPreviewFrame.PaintStage(Sender: TObject);
var Canvas: TCanvas; Video,R,ImageRect,Meter: TRect; I,N,W,P,Save,Mark: Integer; Text,Lyric: string;
  Image: Vcl.Graphics.TBitmap;
  procedure LabelIn(const Bounds: TRect; const Value: string; Flags: Cardinal);
  var Area: TRect;
  begin Area := Bounds; DrawText(Canvas.Handle,PChar(Value),Length(Value),Area,Flags); end;
  procedure CropMark(X,Y,SX,SY: Integer);
  begin
    Canvas.MoveTo(X+SX*4,Y); Canvas.LineTo(X+SX*Mark,Y);
    Canvas.MoveTo(X,Y+SY*4); Canvas.LineTo(X,Y+SY*Mark);
  end;
begin
  Canvas := Stage.Canvas; Canvas.Brush.Color := $00404040; Canvas.FillRect(Stage.ClientRect);
  Video := VideoRect; W := Video.Width;
  Canvas.Brush.Color := clBlack; Canvas.FillRect(Video);
  if FBackgroundSerial<>0 then Canvas.StretchDraw(Video,FHostBackground);
  Canvas.Pen.Color := $004B4845; Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(Rect(Video.Left-1,Video.Top-1,Video.Right+1,Video.Bottom+1));
  Canvas.Brush.Style := bsClear; Canvas.Font.Assign(Font); Canvas.Font.Color := clSilver;
  Text := '編集プレビュー'+sLineBreak+'PSD: 母音・表情'+sLineBreak+'アニメーション / 最大4人'+sLineBreak+
    'MIDI: 歌詞・音高'+sLineBreak+'歌声生成なし';
  if Stage.Height<128 then Text := '編集プレビュー'+sLineBreak+'PSD部位 / MIDI歌詞';
  if FBackgroundSerial<>0 then Text := 'AviUtl2 静止背景'+sLineBreak+
    Format('フレーム %d',[FBackgroundFrame])+sLineBreak+'PSD / 母音・表情';
  LabelIn(Rect(12,12,Video.Left-8,Stage.Height),Text,DT_WORDBREAK);
  N := Length(FTrackIndices);
  if N=0 then LabelIn(Video,'PSDトラック未設定',DT_CENTER or DT_VCENTER or DT_SINGLELINE)
  else for I := 0 to N-1 do begin
    R := Video; R.Left := Video.Left+I*W div N+6; R.Right := Video.Left+(I+1)*W div N-6; Inc(R.Top,20); Dec(R.Bottom,30);
    Image := DisplayImage(I);
    if Assigned(Image) then begin
      CharacterBounds(FTrackIndices[I],Video,ImageRect);
      Save := SaveDC(Canvas.Handle);
      try
        IntersectClipRect(Canvas.Handle,0,0,Stage.ClientWidth,Stage.ClientHeight);
        Canvas.StretchDraw(ImageRect,Image);
      finally RestoreDC(Canvas.Handle,Save); end;
    end else begin
      Text := FSceneCache.StatusForTrack(FTrackIndices[I]);
      LabelIn(R,FPsdNames[I]+sLineBreak+Text,DT_CENTER or DT_WORDBREAK);
    end;
  end;
  Canvas.Brush.Style := bsClear; Canvas.Pen.Color := $00D0D0D0;
  Mark := MulDiv(16,CurrentPPI,96);
  CropMark(Video.Left,Video.Top,-1,-1); CropMark(Video.Right,Video.Top,1,-1);
  CropMark(Video.Left,Video.Bottom,-1,1); CropMark(Video.Right,Video.Bottom,1,1);
  FPlacement.Paint(Canvas);
  Lyric := LyricAtPosition;
  Canvas.Font.Color := clWhite; R := Video; R.Top := Max(R.Top,R.Bottom-26);
  if Lyric<>'' then LabelIn(R,'歌詞: '+Lyric,DT_CENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  P := MulDiv(12,CurrentPPI,96);
  Meter := Rect(Video.Right+P,Min(Stage.Height-P,4*P),Video.Right+2*P,Stage.Height-P);
  Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $003B3B3B; Canvas.FillRect(Meter);
  Canvas.Brush.Color := $00ADBF6F; Canvas.FillRect(MusicStudioPeakFillRect(Meter,FPeak));
end;
end.
