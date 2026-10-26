// PSD-specific editor: asynchronous read/composition, mouth mapping and expression visibility.
// Does not own common pattern name/color or start any audio engine.
unit SYNC_MusicStudio_PsdLayersFrame;

interface

uses Winapi.Windows, System.Classes, System.SysUtils, System.JSON, System.Types, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.StdCtrls, Vcl.Menus,
  SYNC_MusicStudio_PsdLayers, SYNC_MusicStudio_PsdLayerJobs,
  SYNC_MusicStudio_PsdLayerFrameUI;

type
  TMusicStudioPsdLayersFrame = class(TFrame)
  private
    FUI: TMusicStudioPsdLayerControls;
    FConfig: TJSONObject;
    FConfigError, FRenderError, FPath, FRenderingKey, FPreviewLayerKey: string;
    FDocument: TMusicStudioLayerDocument;
    FPreviewBitmap: TBitmap;
    FImages: TObjectDictionary<string,TBitmap>;
    FImageBytes: Int64;
    FLoadJobs: TObjectList<TMusicStudioPsdLayerLoadJob>;
    FRenderJobs: TObjectList<TMusicStudioPsdLayerRenderJob>;
    FPoll: TTimer;
    FGeneration, FRenderGeneration, FPreviewRenderCount: Integer;
    FNeedLoad, FNeedRender, FExpressionMode, FUpdating: Boolean;
    FCompactLayout: Boolean;
    FOnChange: TNotifyEvent;
    FViewZoom: Double;
    FViewPan: TPointF;
    FViewPPI: Integer;
    FDragging: Boolean;
    FDragPoint: TPoint;
    function PreviewOverrides: TJSONObject;
    procedure PublishPreview(Bitmap: TBitmap);
    function ViewScale: Double;
    procedure UpdateViewLabel;
    procedure PreviewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PreviewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure PreviewMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure PreviewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure PreviewCaptureLost(Sender: TObject);
    procedure PreviewResize(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure StopDrag;
    function MouthNames(const Key: string; Compact: Boolean): string;
    procedure StartPendingJobs;
    procedure FillLayers;
    procedure SelectAssignedLayer;
    procedure UpdateChecks;
    procedure UpdateMapping;
    procedure QueueRender;
    procedure Changed;
    procedure PollTimer(Sender: TObject);
    procedure MouthChanged(Sender: TObject);
    procedure LayerChecked(Sender: TObject);
    procedure LayerClicked(Sender: TObject);
    procedure LayerContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure LayerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LayerKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LayerMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure DrawLayer(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure MouthMenuPopup(Sender: TObject);
    procedure MouthMenuClick(Sender: TObject);
    procedure PreviewMouthClick(Sender: TObject);
    procedure ClearLayerAssignments(Sender: TObject);
    function SelectedMouthNames: string;
    procedure PopupMouthAt(const Position: TPoint);
    procedure AssignClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    function GetStateText: string;
    function GetCanApply: Boolean;
    function GetSelectedLayerKey: string;
    procedure ClearPreview;
    procedure CachePreview;
    procedure SetCompactLayout(Value: Boolean);
    function NeedsCompactStatus: Boolean;
    procedure RefreshCompactStatus;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadPSD(const Path, ConfigJSON: string; ExpressionMode: Boolean = False);
    // 同一PSDのstep切替は基本設定だけを差し替え、読込済みレイヤーを再利用する。
    procedure LoadExpressionConfig(const ConfigJSON: string);
    function ConfigJSON: string;
    procedure PollResults;
    procedure CancelLoad;
    function IsLoading: Boolean;
    function IsRendering: Boolean;
    function SelectLayer(const Key: string): Boolean;
    procedure AssignSelectedMouth(Index: Integer);
    procedure ClearSelectedMouth(Index: Integer);
    function SetLayerVisibility(const Key: string; Visible: Boolean): Boolean;
    procedure SelectMouth(Index: Integer);
    procedure FitPreview;
    function ImageToPreview(const P: TPointF): TPointF;
    function PreviewToImage(const P: TPointF): TPointF;
    property ViewZoom: Double read FViewZoom;
    property ViewPan: TPointF read FViewPan;
    property ViewDragging: Boolean read FDragging;
    property Document: TMusicStudioLayerDocument read FDocument;
    property UIControls: TMusicStudioPsdLayerControls read FUI;
    property FilePath: string read FPath;
    property StateText: string read GetStateText;
    property CanApply: Boolean read GetCanApply;
    property SelectedLayerKey: string read GetSelectedLayerKey;
    property PreviewBitmap: TBitmap read FPreviewBitmap;
    property PreviewRenderCount: Integer read FPreviewRenderCount;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property CompactLayout: Boolean read FCompactLayout write SetCompactLayout;
  end;

implementation

uses System.Math, SYNC_MusicStudio_DarkTheme,
  SYNC_MusicStudio_Controls, SYNC_MusicStudio_PsdLayerConfig;

{$R *.dfm}

constructor TMusicStudioPsdLayersFrame.Create(AOwner: TComponent);
begin
  inherited;
  FConfig := ParseMusicStudioPsdConfig('');
  FLoadJobs := TObjectList<TMusicStudioPsdLayerLoadJob>.Create(True);
  FRenderJobs := TObjectList<TMusicStudioPsdLayerRenderJob>.Create(True);
  FImages := TObjectDictionary<string,TBitmap>.Create([doOwnsValues]);
  FViewZoom := 1; FViewPPI := 96; DoubleBuffered := True;
  ApplySyncMusicStudioDarkFrame(Self); ApplyMusicStudioEditorFont(Self);
  FPoll := TTimer.Create(Self); FPoll.Interval := 50; FPoll.Enabled := False;
  FPoll.OnTimer := PollTimer;
end;

destructor TMusicStudioPsdLayersFrame.Destroy;
var L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioPsdLayerRenderJob;
begin
  StopDrag;
  if FPoll<>nil then FPoll.Enabled := False;
  if FLoadJobs<>nil then for L in FLoadJobs do L.Terminate;
  if FRenderJobs<>nil then for R in FRenderJobs do R.Terminate;
  FRenderJobs.Free; FLoadJobs.Free; FDocument.Free;
  FPreviewBitmap.Free; FImages.Free; FConfig.Free; inherited;
end;

procedure TMusicStudioPsdLayersFrame.SetParent(AParent: TWinControl);
var C: TComponent; I: Integer; Item,Sub: TMenuItem;
begin
  inherited; if AParent=nil then Exit;
  // Defer all native controls until the entire frame has a parent window.
  // Combo bounds and checklist recreation may request handles as well as Items.
  if FUI.Toolbar=nil then begin
    BuildMusicStudioPsdLayerControls(Self,FUI);
    FUI.MouthCombo.OnChange := MouthChanged; FUI.LayerList.OnClickCheck := LayerChecked;
    FUI.LayerList.OnClick := LayerClicked; FUI.AssignButton.OnClick := AssignClick;
    FUI.ClearButton.OnClick := ClearClick; FUI.ReloadButton.OnClick := ReloadClick;
    FUI.CancelButton.OnClick := CancelClick; FUI.Preview.OnPaint := PaintPreview;
    FUI.Preview.OnMouseWheel := PreviewWheel; FUI.Preview.OnMouseDown := PreviewDown;
    FUI.LayerList.OnMouseWheel := PreviewWheel; OnMouseWheel := PreviewWheel;
    FUI.Preview.OnMouseMove := PreviewMove; FUI.Preview.OnMouseUp := PreviewUp;
    FUI.Preview.OnCaptureLost := PreviewCaptureLost; FUI.Preview.OnResize := PreviewResize;
    FUI.Preview.OnDblClick := FitClick; FUI.FitButton.OnClick := FitClick;
    FUI.PreviewPane.DoubleBuffered := True; FUI.LayerList.DoubleBuffered := True;
    FUI.LayerList.OnContextPopup := LayerContextPopup; FUI.LayerList.OnKeyDown := LayerKeyDown;
    FUI.LayerList.OnKeyUp := LayerKeyUp;
    FUI.LayerList.OnMouseMove := LayerMouseMove; FUI.LayerList.OnDrawItem := DrawLayer;
    FUI.MouthMenu.OnPopup := MouthMenuPopup;
    for I := 0 to 11 do begin
      Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := MUSIC_STUDIO_MOUTH_CAPTIONS[I];
      Item.Tag := I; Item.OnClick := MouthMenuClick; FUI.MouthMenu.Items.Add(Item);
    end;
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '-'; FUI.MouthMenu.Items.Add(Item);
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '選択レイヤーの割当をすべて解除';
    Item.OnClick := ClearLayerAssignments; FUI.MouthMenu.Items.Add(Item);
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '-'; FUI.MouthMenu.Items.Add(Item);
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '母音の表示確認'; FUI.MouthMenu.Items.Add(Item);
    for I := 0 to 11 do begin
      Sub := TMenuItem.Create(FUI.MouthMenu); Sub.Caption := MUSIC_STUDIO_MOUTH_CAPTIONS[I];
      Sub.Tag := I; Sub.OnClick := PreviewMouthClick; Item.Add(Sub);
    end;
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '再読込'; Item.OnClick := ReloadClick; FUI.MouthMenu.Items.Add(Item);
    Item := TMenuItem.Create(FUI.MouthMenu); Item.Caption := '読込取消'; Item.OnClick := CancelClick; FUI.MouthMenu.Items.Add(Item);
    FUI.StateLabel.Caption := 'PSDが未選択です。';
  end;
  // Combo items require a parent window. Create them only after the frame is attached.
  if (FUI.MouthCombo<>nil) and (FUI.MouthCombo.Items.Count=0) then begin
    FUpdating := True;
    try
      for I := 0 to 11 do FUI.MouthCombo.Items.Add('確認: '+MUSIC_STUDIO_MOUTH_CAPTIONS[I]);
      FUI.MouthCombo.ItemIndex := 0;
    finally FUpdating := False; end;
  end;
  for C in Self do if C is TButton then ApplySyncMusicStudioDarkButton(TButton(C));
  Resize;
end;

procedure TMusicStudioPsdLayersFrame.Resize;
var PPI, Offset, Margin, LineHeight, Gap: Integer; Form: TCustomForm;
begin
  inherited; if FUI.Toolbar=nil then Exit; PPI := CurrentPPI;
  Form := GetParentForm(Self); if Form<>nil then PPI := Form.CurrentPPI;
  // ScaleForPPI can scale runtime child fonts without changing a nested frame's
  // reported CurrentPPI. The editor's 96-DPI font baseline is 13px.
  PPI := Max(PPI,MulDiv(Abs(Font.Height),96,13));
  // Runtime-created labels can inherit a scaled font before their bounds scale.
  // Keep path/status fully inside the header at both initial and changed DPI.
  Margin := MulDiv(12,PPI,96); Gap := MulDiv(5,PPI,96);
  LineHeight := Max(MulDiv(20,PPI,96),Abs(Font.Height)+MulDiv(6,PPI,96));
  FUI.PathLabel.SetBounds(Margin,MulDiv(6,PPI,96),Max(1,ClientWidth-Margin*2),LineHeight);
  if FCompactLayout then FUI.StateLabel.SetBounds(Margin,MulDiv(6,PPI,96),Max(1,ClientWidth-Margin*2),LineHeight*2)
  else FUI.StateLabel.SetBounds(Margin,FUI.PathLabel.Top+LineHeight+Gap,Max(1,ClientWidth-Margin*2),LineHeight*2);
  FUI.Header.Height := FUI.StateLabel.Top+FUI.StateLabel.Height+Gap;
  if not FExpressionMode and (ClientWidth<MulDiv(658,PPI,96)) then Offset := 34 else Offset := 0;
  FUI.Toolbar.Height := MulDiv(38+Offset,PPI,96);
  FUI.AssignButton.SetBounds(MulDiv(12,PPI,96),MulDiv(4,PPI,96),MulDiv(142,PPI,96),MulDiv(28,PPI,96));
  FUI.ClearButton.SetBounds(MulDiv(162,PPI,96),MulDiv(4,PPI,96),MulDiv(128,PPI,96),MulDiv(28,PPI,96));
  if Offset<>0 then FUI.MouthCombo.SetBounds(MulDiv(12,PPI,96),MulDiv(39,PPI,96),MulDiv(160,PPI,96),MulDiv(26,PPI,96))
  else FUI.MouthCombo.SetBounds(MulDiv(302,PPI,96),MulDiv(5,PPI,96),MulDiv(160,PPI,96),MulDiv(26,PPI,96));
  FUI.ReloadButton.Width := MulDiv(84,PPI,96); FUI.ReloadButton.Height := MulDiv(28,PPI,96);
  FUI.CancelButton.Width := MulDiv(84,PPI,96); FUI.CancelButton.Height := MulDiv(28,PPI,96);
  FUI.ReloadButton.Top := MulDiv(4+Offset,PPI,96);
  FUI.CancelButton.Top := FUI.ReloadButton.Top;
  if FExpressionMode then begin
    FUI.ReloadButton.Left := MulDiv(12,PPI,96); FUI.CancelButton.Left := MulDiv(104,PPI,96);
  end else if Offset<>0 then begin
    FUI.ReloadButton.Left := MulDiv(180,PPI,96); FUI.CancelButton.Left := MulDiv(272,PPI,96);
  end else begin
    FUI.ReloadButton.Left := MulDiv(470,PPI,96); FUI.CancelButton.Left := MulDiv(562,PPI,96);
  end;
  FUI.PathLabel.Visible := not FCompactLayout;
  FUI.Header.Visible := not FCompactLayout or NeedsCompactStatus; FUI.MappingLabel.Visible := not FCompactLayout;
  FUI.Toolbar.Visible := False;
  if FCompactLayout then FUI.Footer.Height := MulDiv(64,PPI,96) else FUI.Footer.Height := MulDiv(89,PPI,96);
  FUI.SelectionLabel.SetBounds(Margin,MulDiv(3,PPI,96),Max(1,ClientWidth-Margin*2),LineHeight);
  FUI.MappingLabel.SetBounds(Margin,MulDiv(25,PPI,96),Max(1,ClientWidth-Margin*2),LineHeight);
  if FCompactLayout then Offset := 25 else Offset := 49;
  FUI.HintLabel.SetBounds(Margin,MulDiv(Offset,PPI,96),Max(1,ClientWidth-Margin*2),MulDiv(34,PPI,96));
  FUI.LayerList.ItemHeight := Max(MulDiv(24,PPI,96),Abs(FUI.LayerList.Font.Height)+MulDiv(6,PPI,96));
  FUI.LeftPane.Width := EnsureRange(FUI.LeftPane.Width,MulDiv(170,PPI,96),Max(MulDiv(170,PPI,96),ClientWidth-MulDiv(150,PPI,96)));
  FUI.PreviewToolbar.Height := MulDiv(36,PPI,96);
  FUI.FitButton.SetBounds(MulDiv(8,PPI,96),MulDiv(4,PPI,96),MulDiv(100,PPI,96),MulDiv(28,PPI,96));
  FUI.ZoomLabel.SetBounds(MulDiv(116,PPI,96),MulDiv(7,PPI,96),Max(1,FUI.PreviewToolbar.ClientWidth-MulDiv(124,PPI,96)),LineHeight);
  if (FViewPPI>0) and (FViewPPI<>PPI) then
    FViewPan := PointF(FViewPan.X*PPI/FViewPPI,FViewPan.Y*PPI/FViewPPI);
  FViewPPI := PPI; UpdateViewLabel;
end;

procedure TMusicStudioPsdLayersFrame.SetCompactLayout(Value: Boolean);
begin FCompactLayout := Value; if FUI.Toolbar<>nil then Resize; end;

function TMusicStudioPsdLayersFrame.NeedsCompactStatus: Boolean;
begin
  Result := (FConfigError<>'') or (FRenderError<>'') or ((FPath<>'') and (FDocument=nil) and not IsLoading);
end;
procedure TMusicStudioPsdLayersFrame.RefreshCompactStatus;
begin
  if FCompactLayout and (FUI.Header<>nil) and (FUI.Header.Visible<>NeedsCompactStatus) then Resize;
end;

procedure TMusicStudioPsdLayersFrame.ClearPreview;
begin
  FreeAndNil(FPreviewBitmap); FImages.Clear; FImageBytes := 0; FUI.Preview.Invalidate;
end;

procedure TMusicStudioPsdLayersFrame.LoadPSD(const Path, ConfigJSON: string; ExpressionMode: Boolean);
var Config: TJSONObject; L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioPsdLayerRenderJob; SamePath: Boolean;
begin
  if Parent=nil then raise EInvalidOperation.Create('PSD設定フレームへ親画面を設定してから読み込んでください。');
  Inc(FGeneration); Inc(FRenderGeneration);
  for L in FLoadJobs do L.Terminate; for R in FRenderJobs do R.Terminate;
  SamePath := SameText(FPath,Path) and (FPreviewBitmap<>nil); StopDrag;
  FPath := Path; FExpressionMode := ExpressionMode; FConfigError := ''; FRenderError := ''; FPreviewLayerKey := '';
  FreeAndNil(FDocument);
  if SamePath then begin FImages.Clear; FImageBytes := 0; end
  else begin ClearPreview; FitPreview; end;
  FUI.LayerList.Clear;
  FNeedLoad := False; FNeedRender := False; FUpdating := True;
  try
    SetMusicStudioPsdLayerMode(FUI,ExpressionMode); FUI.PathLabel.Caption := Path;
    FUI.PathLabel.Hint := Path; FUI.MouthCombo.ItemIndex := 0;
    try
      Config := ParseMusicStudioPsdConfig(ConfigJSON); FConfig.Free; FConfig := Config;
      FNeedLoad := Trim(Path)<>'';
      if FNeedLoad then FUI.StateLabel.Caption := 'PSDレイヤーを読み込み中…'
      else FUI.StateLabel.Caption := 'PSDが未選択です。';
    except on E: Exception do begin FConfigError := E.Message; FUI.StateLabel.Caption := E.Message; end; end;
  finally FUpdating := False; end;
  UpdateMapping; Resize; StartPendingJobs;
end;

procedure TMusicStudioPsdLayersFrame.LoadExpressionConfig(const ConfigJSON: string);
var Config: TJSONObject;
begin
  if not FExpressionMode then raise EInvalidOperation.Create('表情モードで設定を切り替えてください。');
  Config := ParseMusicStudioPsdConfig(ConfigJSON); FUpdating := True;
  try FConfig.Free; FConfig := Config; FConfigError := ''; FRenderError := '';
    UpdateChecks; QueueRender;
  finally FUpdating := False; end;
end;
function TMusicStudioPsdLayersFrame.ConfigJSON: string;
begin
  if FConfigError<>'' then raise Exception.Create(FConfigError);
  Result := FConfig.ToJSON;
end;

function TMusicStudioPsdLayersFrame.GetCanApply: Boolean;
begin
  Result := (FConfigError='') and (FRenderError='') and (FDocument<>nil) and (FPreviewBitmap<>nil)
    and not IsLoading and not IsRendering;
  if Result then Result := FDocument.Loaded and not FPreviewBitmap.Empty;
end;
function TMusicStudioPsdLayersFrame.GetStateText: string;
begin Result := FUI.StateLabel.Caption; end;
function TMusicStudioPsdLayersFrame.IsLoading: Boolean;
begin Result := FNeedLoad or (FLoadJobs.Count>0); end;
function TMusicStudioPsdLayersFrame.IsRendering: Boolean;
begin Result := FNeedRender or (FRenderJobs.Count>0); end;

procedure TMusicStudioPsdLayersFrame.StartPendingJobs;
var L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioPsdLayerRenderJob;
    Overrides: TJSONObject; Image,Copy: TBitmap;
begin
  if FNeedLoad and (FLoadJobs.Count=0) then begin
    FNeedLoad := False; L := TMusicStudioPsdLayerLoadJob.Create(FPath,FGeneration);
    FLoadJobs.Add(L); L.Start;
  end;
  if FNeedRender and (FRenderJobs.Count=0) and (FDocument<>nil) then begin
    FNeedRender := False; Overrides := PreviewOverrides;
    try
      FRenderingKey := Overrides.ToJSON;
      if FImages.TryGetValue(FRenderingKey,Image) then begin
        Copy := TBitmap.Create;
        try Copy.Assign(Image); except Copy.Free; raise; end;
        PublishPreview(Copy);
        FUI.StateLabel.Caption := Format('%d レイヤー ・ %d × %d',[Length(FDocument.Layers),FDocument.Width,FDocument.Height]);
      end else begin
        R := TMusicStudioPsdLayerRenderJob.Create(FDocument,Overrides,FRenderGeneration);
        FRenderJobs.Add(R); R.Start; FUI.StateLabel.Caption := '選択した表示を合成中…';
      end;
    finally Overrides.Free; end;
  end;
  FPoll.Enabled := IsLoading or IsRendering;
end;

procedure TMusicStudioPsdLayersFrame.PollResults;
var I: Integer; L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioPsdLayerRenderJob; Image: TBitmap;
begin
  for I := FLoadJobs.Count-1 downto 0 do begin
    L := FLoadJobs[I]; if not L.Finished then Continue;
    if (L.Generation=FGeneration) and (L.Path=FPath) then begin
      FDocument := L.TakeDocument;
      if FDocument=nil then FUI.StateLabel.Caption := L.ErrorMessage
      else begin FillLayers; QueueRender; end;
    end;
    FLoadJobs.Delete(I);
  end;
  for I := FRenderJobs.Count-1 downto 0 do begin
    R := FRenderJobs[I]; if not R.Finished then Continue;
    if R.Generation=FRenderGeneration then begin
      Image := R.TakeBitmap;
      if Image=nil then begin
        FRenderError := R.ErrorMessage; FUI.StateLabel.Caption := '合成未対応 / 読込失敗: '+R.ErrorMessage;
      end
      else begin
        PublishPreview(Image); Inc(FPreviewRenderCount); CachePreview;
        FUI.StateLabel.Caption := Format('%d レイヤー ・ %d × %d',[Length(FDocument.Layers),FDocument.Width,FDocument.Height]);
      end;
      FUI.Preview.Invalidate;
    end;
    FRenderJobs.Delete(I);
  end;
  StartPendingJobs;
  RefreshCompactStatus;
end;

function TMusicStudioPsdLayersFrame.PreviewOverrides: TJSONObject;
var Mouth: Integer;
begin
  Mouth := FUI.MouthCombo.ItemIndex;
  // 行の試写は確認用母音より優先し、別の口枝を強制表示しない。
  if FExpressionMode or (FPreviewLayerKey<>'') then Mouth := -1;
  Result := BuildMusicStudioPsdOverrides(FDocument,FConfig,Mouth);
  // Row selection is a temporary audition, separate from saved visibility and mouth assignments.
  if not FExpressionMode and (FPreviewLayerKey<>'') then FDocument.SelectLayerOverride(Result,FPreviewLayerKey);
end;

procedure TMusicStudioPsdLayersFrame.PublishPreview(Bitmap: TBitmap);
var Old: TBitmap;
begin
  // Paint keeps the last complete image until its replacement is ready.
  Old := FPreviewBitmap; FPreviewBitmap := Bitmap; FRenderError := ''; Old.Free;
  UpdateViewLabel; FUI.Preview.Invalidate;
end;

procedure TMusicStudioPsdLayersFrame.CachePreview;
var Image, OldImage: TBitmap; Bytes: Int64;
begin
  Bytes := Int64(FPreviewBitmap.Width)*FPreviewBitmap.Height*4;
  if (FImages.Count>=8) or (FImageBytes+Bytes>Int64(64)*1024*1024) then begin FImages.Clear; FImageBytes := 0; end;
  if Bytes>Int64(64)*1024*1024 then Exit;
  if FImages.TryGetValue(FRenderingKey,OldImage) then
    Dec(FImageBytes,Int64(OldImage.Width)*OldImage.Height*4);
  Image := TBitmap.Create; Image.Assign(FPreviewBitmap);
  FImages.AddOrSetValue(FRenderingKey,Image); Inc(FImageBytes,Bytes);
end;

procedure TMusicStudioPsdLayersFrame.FillLayers;
var Info: TMusicStudioLayerInfo; Caption: string; Counts: TDictionary<string,Integer>; N: Integer;
begin
  Counts := TDictionary<string,Integer>.Create;
  for Info in FDocument.Layers do begin
    if not Counts.TryGetValue(Info.Path,N) then N := 0;
    Counts.AddOrSetValue(Info.Path,N+1);
  end;
  FUpdating := True; FUI.LayerList.Items.BeginUpdate;
  try
    FUI.LayerList.Clear;
    for Info in FDocument.Layers do begin
      Caption := Info.Name;
      if Counts[Info.Path]>1 then Caption := Caption+' ['+IntToStr(Info.SourceIndex+1)+']';
      FUI.LayerList.Items.Add(Caption);
    end;
    UpdateChecks; if FUI.LayerList.Items.Count>0 then FUI.LayerList.ItemIndex := 0;
    SelectAssignedLayer;
  finally FUI.LayerList.Items.EndUpdate; FUpdating := False; Counts.Free; end;
  UpdateMapping;
end;

procedure TMusicStudioPsdLayersFrame.SelectAssignedLayer;
var Key: string;
begin
  if FExpressionMode then Exit;
  Key := MusicStudioMouthLayer(FConfig,FUI.MouthCombo.ItemIndex);
  if (Key<>'') and not SelectLayer(Key) then FUI.LayerList.ItemIndex := -1;
end;

procedure TMusicStudioPsdLayersFrame.UpdateChecks;
var I: Integer; Info: TMusicStudioLayerInfo; Obj: TJSONObject; Value: TJSONValue;
begin
  if FDocument=nil then Exit;
  Obj := PreviewOverrides;
  try
    for I := 0 to High(FDocument.Layers) do begin
      Info := FDocument.Layers[I]; Value := Obj.GetValue(Info.Key);
      if Value is TJSONBool then FUI.LayerList.Checked[I] := TJSONBool(Value).AsBoolean
      else FUI.LayerList.Checked[I] := Info.Visible;
    end;
  finally Obj.Free; end;
end;

procedure TMusicStudioPsdLayersFrame.UpdateMapping;
var Key,Names: string; Index,Selected: Integer;
begin
  FUI.LayerList.Invalidate;
  Selected := -1; if FDocument<>nil then Selected := FDocument.LayerIndex(SelectedLayerKey);
  FUI.AssignButton.Enabled := not FExpressionMode and (Selected>=0);
  FUI.ClearButton.Enabled := not FExpressionMode and (MusicStudioMouthLayer(FConfig,FUI.MouthCombo.ItemIndex)<>'');
  if Selected>=0 then begin
    FUI.SelectionLabel.Caption := '選択: '+FDocument.Layers[Selected].Name;
    Names := SelectedMouthNames;
    if not FExpressionMode then begin
      if Names='' then Names := '未割当';
      FUI.SelectionLabel.Caption := FUI.SelectionLabel.Caption+'  ・ 割当: '+Names;
    end;
    FUI.SelectionLabel.Hint := FDocument.Layers[Selected].Path+'  ['+IntToStr(FDocument.Layers[Selected].SourceIndex+1)+']';
  end else begin FUI.SelectionLabel.Caption := 'レイヤーを選択してください'; FUI.SelectionLabel.Hint := ''; end;
  if FExpressionMode then begin FUI.MappingLabel.Caption := '表情: チェックで表示状態を設定'; Exit; end;
  if (FPreviewLayerKey<>'') and (Selected>=0) then begin
    FUI.MappingLabel.Caption := '試写: '+FDocument.Layers[Selected].Name+'（排他表示）';
    FUI.MappingLabel.Hint := FDocument.Layers[Selected].Path; Exit;
  end;
  Key := MusicStudioMouthLayer(FConfig,FUI.MouthCombo.ItemIndex);
  if Key='' then FUI.MappingLabel.Caption := '母音の割当: 未設定'
  else if FDocument=nil then FUI.MappingLabel.Caption := '母音の割当: PSD読込後に確認'
  else begin
    Index := FDocument.LayerIndex(Key);
    if Index<0 then FUI.MappingLabel.Caption := '母音の割当先が見つかりません。再割当してください。'
    else begin
      FUI.MappingLabel.Caption := '確認: '+MUSIC_STUDIO_MOUTH_CAPTIONS[FUI.MouthCombo.ItemIndex]+' → '+FDocument.Layers[Index].Name;
      FUI.MappingLabel.Hint := FDocument.Layers[Index].Path;
    end;
  end;
end;

procedure TMusicStudioPsdLayersFrame.QueueRender;
var R: TMusicStudioPsdLayerRenderJob;
begin
  Inc(FRenderGeneration); FRenderError := ''; for R in FRenderJobs do R.Terminate;
  FNeedRender := FDocument<>nil; FPoll.Enabled := IsLoading or IsRendering;
  RefreshCompactStatus;
end;

procedure TMusicStudioPsdLayersFrame.Changed;
begin
  FUpdating := True; try UpdateChecks; finally FUpdating := False; end;
  UpdateMapping; QueueRender; StartPendingJobs; if Assigned(FOnChange) then FOnChange(Self);
end;

function TMusicStudioPsdLayersFrame.GetSelectedLayerKey: string;
var I: Integer;
begin
  Result := ''; I := FUI.LayerList.ItemIndex;
  if (FDocument<>nil) and (I>=0) and (I<Length(FDocument.Layers)) then Result := FDocument.Layers[I].Key;
end;

function TMusicStudioPsdLayersFrame.SelectLayer(const Key: string): Boolean;
var Index: Integer;
begin
  Result := False; if FDocument=nil then Exit; Index := FDocument.LayerIndex(Key);
  if Index<0 then Exit; FUI.LayerList.ItemIndex := Index; LayerClicked(nil); Result := True;
end;

procedure TMusicStudioPsdLayersFrame.AssignSelectedMouth(Index: Integer);
var Key: string;
begin
  Key := SelectedLayerKey; if Key='' then Exit;
  MusicStudioAssignMouth(FConfig,Index,Key); SelectMouth(Index);
  if Assigned(FOnChange) then FOnChange(Self);
end;
procedure TMusicStudioPsdLayersFrame.ClearSelectedMouth(Index: Integer);
begin
  MusicStudioAssignMouth(FConfig,Index,''); SelectMouth(Index);
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TMusicStudioPsdLayersFrame.SetLayerVisibility(const Key: string; Visible: Boolean): Boolean;
var Obj: TJSONObject;
begin
  Result := (FDocument<>nil) and FDocument.HasLayer(Key); if not Result then Exit;
  Obj := MusicStudioPsdConfigObject(FConfig,'visibility'); MusicStudioSetJsonBoolean(Obj,Key,Visible);
  if Visible then FDocument.SelectLayerOverride(Obj,Key);
  FUpdating := True; try UpdateChecks; finally FUpdating := False; end; Changed;
end;

procedure TMusicStudioPsdLayersFrame.SelectMouth(Index: Integer);
begin
  if (Index<0) or (Index>11) then Exit;
  FUI.MouthCombo.ItemIndex := Index; FPreviewLayerKey := '';
  FUpdating := True; try UpdateChecks; SelectAssignedLayer; finally FUpdating := False; end;
  UpdateMapping; QueueRender; StartPendingJobs;
end;

procedure TMusicStudioPsdLayersFrame.CancelLoad;
var L: TMusicStudioPsdLayerLoadJob; R: TMusicStudioPsdLayerRenderJob;
begin
  Inc(FGeneration); Inc(FRenderGeneration); FNeedLoad := False; FNeedRender := False;
  for L in FLoadJobs do L.Terminate; for R in FRenderJobs do R.Terminate;
  FUI.StateLabel.Caption := '読込 / 合成を取り消しました。'; FPoll.Enabled := IsLoading or IsRendering;
  FRenderError := '合成を中止しました。再読込または行を選択してください。';
  RefreshCompactStatus;
end;

procedure TMusicStudioPsdLayersFrame.PollTimer(Sender: TObject);
begin PollResults; end;
procedure TMusicStudioPsdLayersFrame.MouthChanged(Sender: TObject);
begin if not FUpdating then SelectMouth(FUI.MouthCombo.ItemIndex); end;
procedure TMusicStudioPsdLayersFrame.LayerClicked(Sender: TObject);
var I: Integer;
begin
  I := FUI.LayerList.ItemIndex;
  if (FDocument<>nil) and (I>=0) and (I<Length(FDocument.Layers)) then
    FUI.LayerList.Hint := FDocument.Layers[I].Path+' ['+IntToStr(FDocument.Layers[I].SourceIndex+1)+']';
  UpdateMapping;
  if FUpdating or FExpressionMode or (FDocument=nil) or ((FPreviewLayerKey=SelectedLayerKey) and (FRenderError='')) then Exit;
  FPreviewLayerKey := SelectedLayerKey; UpdateMapping;
  FUpdating := True; try UpdateChecks; finally FUpdating := False; end;
  QueueRender; StartPendingJobs;
end;
function TMusicStudioPsdLayersFrame.SelectedMouthNames: string;
begin Result := MouthNames(SelectedLayerKey,False); end;
function TMusicStudioPsdLayersFrame.MouthNames(const Key: string; Compact: Boolean): string;
const ShortNames: array[0..11] of string = ('通常','あ','い','う','え','お','ん','小あ','小い','小う','小え','小お');
var I: Integer;
begin
  Result := ''; if Key='' then Exit;
  for I := 0 to 11 do if MusicStudioMouthLayer(FConfig,I)=Key then begin
    if Compact and (Result<>'') then begin
      // Two glyphs: show the first vowel plus '+'; the tooltip retains every size/assignment.
      if Result='通常' then Result := '通' else if Result.StartsWith('小') then Result := Result.Substring(1);
      Exit(Result+'+');
    end;
    if Result<>'' then if Compact then Result := Result+',' else Result := Result+' / ';
    if Compact then Result := Result+ShortNames[I] else Result := Result+MUSIC_STUDIO_MOUTH_CAPTIONS[I];
  end;
end;
procedure TMusicStudioPsdLayersFrame.MouthMenuPopup(Sender: TObject);
var I: Integer; Key: string;
begin
  Key := SelectedLayerKey;
  for I := 0 to 11 do begin
    FUI.MouthMenu.Items[I].Enabled := not FExpressionMode and (Key<>'');
    FUI.MouthMenu.Items[I].Checked := (Key<>'') and (MusicStudioMouthLayer(FConfig,I)=Key);
  end;
  FUI.MouthMenu.Items[13].Enabled := not FExpressionMode and (SelectedMouthNames<>'');
  FUI.MouthMenu.Items[15].Enabled := not FExpressionMode and (FDocument<>nil);
  for I := 0 to 11 do FUI.MouthMenu.Items[15].Items[I].Checked := (FPreviewLayerKey='') and (FUI.MouthCombo.ItemIndex=I);
  FUI.MouthMenu.Items[16].Enabled := FPath<>'';
  FUI.MouthMenu.Items[17].Enabled := IsLoading or IsRendering;
end;
procedure TMusicStudioPsdLayersFrame.MouthMenuClick(Sender: TObject);
begin if not FExpressionMode then AssignSelectedMouth(TMenuItem(Sender).Tag); end;
procedure TMusicStudioPsdLayersFrame.PreviewMouthClick(Sender: TObject);
begin SelectMouth(TMenuItem(Sender).Tag); end;
procedure TMusicStudioPsdLayersFrame.ClearLayerAssignments(Sender: TObject);
var I: Integer; Key: string;
begin
  Key := SelectedLayerKey; if FExpressionMode or (Key='') then Exit;
  for I := 0 to 11 do if MusicStudioMouthLayer(FConfig,I)=Key then MusicStudioAssignMouth(FConfig,I,'');
  Changed;
end;
procedure TMusicStudioPsdLayersFrame.PopupMouthAt(const Position: TPoint);
begin
  FUI.MouthMenu.Popup(Position.X,Position.Y);
end;
procedure TMusicStudioPsdLayersFrame.LayerContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var I: Integer; R: TRect; P: TPoint;
begin
  Handled := True;
  if MousePos.X>=0 then begin
    I := FUI.LayerList.ItemAtPos(MousePos,True);
    FUI.LayerList.ItemIndex := I; P := FUI.LayerList.ClientToScreen(MousePos);
  end else begin
    I := FUI.LayerList.ItemIndex;
    if I<0 then R := Rect(0,0,24,24) else R := FUI.LayerList.ItemRect(I); P := FUI.LayerList.ClientToScreen(Point(R.Left+24,R.Bottom));
  end;
  FUI.LayerList.SetFocus; LayerClicked(nil); PopupMouthAt(P);
end;
procedure TMusicStudioPsdLayersFrame.LayerKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var Handled: Boolean;
begin
  if ((Key=VK_APPS) or (Key=VK_RETURN) or ((Key=VK_F10) and (ssShift in Shift))) then begin
    Key := 0; Handled := False; LayerContextPopup(Sender,Point(-1,-1),Handled);
  end;
end;
procedure TMusicStudioPsdLayersFrame.LayerKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin LayerClicked(nil); end;
procedure TMusicStudioPsdLayersFrame.LayerMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
var I: Integer; Text: string;
begin
  I := FUI.LayerList.ItemAtPos(Point(X,Y),True);
  if (FDocument=nil) or (I<0) or (I>=Length(FDocument.Layers)) then Exit;
  Text := FDocument.Layers[I].Path+' ['+IntToStr(FDocument.Layers[I].SourceIndex+1)+']';
  if not FExpressionMode then begin
    if MouthNames(FDocument.Layers[I].Key,False)='' then Text := Text+'  割当: 未割当'
    else Text := Text+'  割当: '+MouthNames(FDocument.Layers[I].Key,False);
  end;
  if FUI.LayerList.Hint<>Text then begin Application.CancelHint; FUI.LayerList.Hint := Text; end;
end;
procedure TMusicStudioPsdLayersFrame.DrawLayer(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var C: TCanvas; Info: TMusicStudioLayerInfo; Ch: Char; Depth,Column,Flags: Integer; Text: string; LabelRect,CheckRect: TRect;
begin
  if (FDocument=nil) or (Index<0) or (Index>=Length(FDocument.Layers)) then Exit;
  Info := FDocument.Layers[Index]; C := FUI.LayerList.Canvas; C.Font.Assign(FUI.LayerList.Font);
  if odSelected in State then begin C.Brush.Color := $00704B33; C.Font.Color := clWhite; end
  else begin C.Brush.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR; C.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR; end;
  C.FillRect(Rect); Depth := 0; for Ch in Info.Group do if Ch='/' then Inc(Depth);
  SetBkMode(C.Handle,TRANSPARENT);
  if FExpressionMode then begin
    Column := MulDiv(20,Abs(C.Font.Height),13); CheckRect := Rect;
    CheckRect.Left := Rect.Left+MulDiv(3,Abs(C.Font.Height),13); CheckRect.Right := CheckRect.Left+MulDiv(13,Abs(C.Font.Height),13);
    CheckRect.Top := (Rect.Top+Rect.Bottom-CheckRect.Width) div 2; CheckRect.Bottom := CheckRect.Top+CheckRect.Width;
    Flags := DFCS_BUTTONCHECK; if FUI.LayerList.Checked[Index] then Flags := Flags or DFCS_CHECKED;
    DrawFrameControl(C.Handle,CheckRect,DFC_BUTTON,Flags);
  end else begin
    // Unassigned rows reserve the same column, so assignment never shifts the layer name.
    Column := MulDiv(36,Abs(C.Font.Height),13); LabelRect := Rect;
    LabelRect.Left := Rect.Left+MulDiv(4,Abs(C.Font.Height),13); LabelRect.Right := Rect.Left+Column-MulDiv(4,Abs(C.Font.Height),13);
    Text := MouthNames(Info.Key,True);
    DrawText(C.Handle,PChar(Text),Length(Text),LabelRect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    C.Pen.Color := $00444444; C.MoveTo(Rect.Left+Column,Rect.Top); C.LineTo(Rect.Left+Column,Rect.Bottom);
  end;
  Inc(Rect.Left,Column+MulDiv(4+Min(Depth,3)*6,Abs(C.Font.Height),13));
  if Info.IsGroup then C.Font.Style := [fsBold];
  Text := FUI.LayerList.Items[Index]; SetBkMode(C.Handle,TRANSPARENT);
  DrawText(C.Handle,PChar(Text),Length(Text),Rect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
end;
procedure TMusicStudioPsdLayersFrame.LayerChecked(Sender: TObject);
var I: Integer;
begin
  if FUpdating or not FExpressionMode then Exit; I := FUI.LayerList.ItemIndex;
  if I>=0 then SetLayerVisibility(SelectedLayerKey,FUI.LayerList.Checked[I]);
end;
procedure TMusicStudioPsdLayersFrame.AssignClick(Sender: TObject);
begin PopupMouthAt(FUI.AssignButton.ClientToScreen(Point(0,FUI.AssignButton.Height))); end;
procedure TMusicStudioPsdLayersFrame.ClearClick(Sender: TObject);
begin ClearSelectedMouth(FUI.MouthCombo.ItemIndex); end;
procedure TMusicStudioPsdLayersFrame.ReloadClick(Sender: TObject);
begin LoadPSD(FPath,ConfigJSON,FExpressionMode); end;
procedure TMusicStudioPsdLayersFrame.CancelClick(Sender: TObject);
begin CancelLoad; end;

procedure TMusicStudioPsdLayersFrame.PaintPreview(Sender: TObject);
var C: TCanvas; R: TRect; X,Y,Cell: Integer; TL,BR: TPointF;
begin
  C := FUI.Preview.Canvas; C.Font.Assign(Font); R := FUI.Preview.ClientRect;
  Cell := Max(8,MulDiv(12,CurrentPPI,96));
  for Y := 0 to R.Height div Cell do for X := 0 to R.Width div Cell do begin
    if Odd(X+Y) then C.Brush.Color := $002A2A2A else C.Brush.Color := $00303030;
    C.FillRect(Rect(X*Cell,Y*Cell,Min(R.Right,(X+1)*Cell),Min(R.Bottom,(Y+1)*Cell)));
  end;
  if (FPreviewBitmap=nil) or FPreviewBitmap.Empty or (R.Width<8) or (R.Height<8) then Exit;
  TL := ImageToPreview(PointF(0,0)); BR := ImageToPreview(PointF(FPreviewBitmap.Width,FPreviewBitmap.Height));
  C.StretchDraw(Rect(Round(TL.X),Round(TL.Y),Round(BR.X),Round(BR.Y)),FPreviewBitmap);
end;

function TMusicStudioPsdLayersFrame.ViewScale: Double;
begin
  Result := 1;
  if (FPreviewBitmap<>nil) and not FPreviewBitmap.Empty and (FUI.Preview<>nil) then
    Result := Max(0.00001,Min(Max(1,FUI.Preview.ClientWidth-8)/FPreviewBitmap.Width,
      Max(1,FUI.Preview.ClientHeight-8)/FPreviewBitmap.Height))*FViewZoom;
end;
function TMusicStudioPsdLayersFrame.ImageToPreview(const P: TPointF): TPointF;
var S: Double;
begin
  Result := P; if FPreviewBitmap=nil then Exit; S := ViewScale;
  Result := PointF(FUI.Preview.ClientWidth/2+FViewPan.X+(P.X-FPreviewBitmap.Width/2)*S,
    FUI.Preview.ClientHeight/2+FViewPan.Y+(P.Y-FPreviewBitmap.Height/2)*S);
end;
function TMusicStudioPsdLayersFrame.PreviewToImage(const P: TPointF): TPointF;
var S: Double;
begin
  Result := P; if FPreviewBitmap=nil then Exit; S := ViewScale;
  Result := PointF((P.X-FUI.Preview.ClientWidth/2-FViewPan.X)/S+FPreviewBitmap.Width/2,
    (P.Y-FUI.Preview.ClientHeight/2-FViewPan.Y)/S+FPreviewBitmap.Height/2);
end;
procedure TMusicStudioPsdLayersFrame.UpdateViewLabel;
begin
  if FUI.ZoomLabel<>nil then FUI.ZoomLabel.Caption := Format('倍率 %.0f%%',[FViewZoom*100]);
end;
procedure TMusicStudioPsdLayersFrame.PreviewWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var P: TPoint; Zoom,Ratio: Double;
begin
  if (FPreviewBitmap=nil) or FPreviewBitmap.Empty then Exit;
  P := FUI.Preview.ScreenToClient(MousePos);
  if not PtInRect(FUI.Preview.ClientRect,P) then Exit;
  Handled := True; Zoom := EnsureRange(FViewZoom*Power(1.2,WheelDelta/120),0.1,32.0);
  Ratio := Zoom/FViewZoom;
  FViewPan := PointF(Ratio*FViewPan.X+(1-Ratio)*(P.X-FUI.Preview.ClientWidth/2),
    Ratio*FViewPan.Y+(1-Ratio)*(P.Y-FUI.Preview.ClientHeight/2));
  FViewZoom := Zoom; UpdateViewLabel; FUI.Preview.Invalidate;
end;
procedure TMusicStudioPsdLayersFrame.PreviewDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  if (Button<>mbLeft) or (FPreviewBitmap=nil) or FPreviewBitmap.Empty then Exit;
  FUI.Preview.SetFocus; FDragPoint := Point(X,Y); FDragging := True;
  FUI.Preview.Cursor := crSizeAll; SetCapture(FUI.Preview.Handle);
end;
procedure TMusicStudioPsdLayersFrame.PreviewMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
begin
  if not FDragging then Exit;
  FViewPan := PointF(FViewPan.X+X-FDragPoint.X,FViewPan.Y+Y-FDragPoint.Y);
  FDragPoint := Point(X,Y); FUI.Preview.Invalidate;
end;
procedure TMusicStudioPsdLayersFrame.StopDrag;
begin
  FDragging := False;
  if FUI.Preview=nil then Exit;
  FUI.Preview.Cursor := crDefault;
  if FUI.Preview.HandleAllocated and (GetCapture=FUI.Preview.Handle) then ReleaseCapture;
end;
procedure TMusicStudioPsdLayersFrame.PreviewUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin if Button=mbLeft then StopDrag; end;
procedure TMusicStudioPsdLayersFrame.PreviewCaptureLost(Sender: TObject);
begin StopDrag; end;
procedure TMusicStudioPsdLayersFrame.PreviewResize(Sender: TObject);
begin StopDrag; FUI.Preview.Invalidate; end;
procedure TMusicStudioPsdLayersFrame.FitPreview;
begin StopDrag; FViewZoom := 1; FViewPan := PointF(0,0); UpdateViewLabel; if FUI.Preview<>nil then FUI.Preview.Invalidate; end;
procedure TMusicStudioPsdLayersFrame.FitClick(Sender: TObject);
begin FitPreview; end;

end.
