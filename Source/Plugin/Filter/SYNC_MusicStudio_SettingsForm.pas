unit SYNC_MusicStudio_SettingsForm;

// 1ページ統合編集画面。文書の作業コピーと一覧操作を担当し、音声デコードは専用UIに任せる。
interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Menus, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_PreviewFrame, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_LibraryData,
  SYNC_MusicStudio_PsdLayerFrameUI, SYNC_MusicStudio_LibraryThumbnails, SYNC_MusicStudio_EditHistory, SYNC_MusicStudio_PsdTransform,
  SYNC_MusicStudio_TempoRulerEditor;

type
  TMusicStudioApplyJSONEvent = function(const JSONText: string; out ErrorText: string): Boolean of object;
  TFormMusicStudioSettings = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FCancelRequested, FSyncing, FValid: Boolean;
    FInitialText: string;
    FLibraryKind: string;
    FAvailableKinds: TArray<string>;
    FVisiblePatterns: TArray<Integer>;
    FLibraryItems: TArray<TMusicStudioLibraryItem>;
    FSharedLibrary: TMusicStudioSharedPsdLibrary;
    FSilentVisualMode: Boolean;
    FDocument: TMusicStudioDocument;
    FPreview: TMusicStudioPreviewFrame;
    FLibraryThumbnails: TMusicStudioLibraryThumbnails;
    FEditHistory: TMusicStudioEditHistory;
    FTransportSpaceDown: Boolean;
    FTempoButton: TButton;
    FTempoRuler: TMusicStudioTempoRulerEditor;
    FOverview: TPanel;
    FOnApplyJSON: TMusicStudioApplyJSONEvent;
    FTrackSettingsItem, FTrackDeleteItem, FClipEditItem, FClipDeleteItem: TMenuItem;
    FSlotAddItem, FSlotSettingsItem, FSlotDeleteItem, FSlotUpItem, FSlotDownItem: TMenuItem;
    function VisiblePattern(Index: Integer): TMusicStudioPattern;
    procedure TempoRulerMenu(Beat: Double);
    procedure SetLibraryRoot(const Value: string);
    function GetLibraryRoot: string;
    procedure AddSharedPattern(const Kind: string);
    procedure AddAvailablePattern(const Kind: string);
    procedure AddMenuClick(Sender: TObject);
    procedure TempoSettingsClick(Sender: TObject);
    procedure AddInstrumentTrackClick(Sender: TObject);
    function DropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
    procedure UpdateLibrary;
    procedure LibraryMetadataChanged(Sender: TObject);
    procedure TransportKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TransportKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TransportDeactivate(Sender: TObject);
    function SelectedPatternIndex: Integer;
    procedure SelectPatternIndex(Index: Integer);
    procedure SetSilentVisualMode(Value: Boolean);
    function ReadDocument(out JSONText: string): Boolean;
    procedure BuildUI;
    procedure RefreshPatterns;
    procedure SyncMemo;
    procedure AddPerformanceClick(Sender: TObject);
    procedure AddPattern(Singing: Boolean);
    procedure AddButtonClick(Sender: TObject);
    procedure EditButtonClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure RawJSONButtonClick(Sender: TObject);
    procedure PatternListClick(Sender: TObject);
    procedure PatternListDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure PatternListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TrackAddClick(Sender: TObject);
    procedure AddAudioTrackClick(Sender: TObject);
    procedure AddPsdTrackClick(Sender: TObject);
    procedure AddTrack(const Kind: string);
    procedure SlotMenuClick(Sender: TObject);
    procedure AddSlotClick(Sender: TObject);
    procedure SlotSettingsClick(Sender: TObject);
    procedure SlotDeleteClick(Sender: TObject);
    procedure SlotUpClick(Sender: TObject);
    procedure SlotDownClick(Sender: TObject);
    procedure ReorderSlot(Delta: Integer);
    procedure DebugJSONClick(Sender: TObject);
    procedure TrackSettingsClick(Sender: TObject);
    procedure TrackDeleteClick(Sender: TObject);
    procedure ClipEditClick(Sender: TObject);
    procedure ClipDeleteClick(Sender: TObject);
    procedure ArrangementMenuPopup(Sender: TObject);
    procedure TimelineDragOver(Sender, Source: TObject; X,Y: Integer; State: TDragState; var Accept: Boolean);
    procedure TimelineDragDrop(Sender, Source: TObject; X,Y: Integer);
    procedure TimelineDblClick(Sender: TObject);
    procedure TimelineSelectionChange(Sender: TObject);
    procedure TimelineClipMove(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds: Double);
    procedure TimelineClipResize(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds,LengthSeconds: Double);
    function CommitMutation: Boolean;
    procedure PlacementCommit(TrackIndex: Integer; const Transform: TMusicStudioPsdTransform);
    procedure RestoreEditText(const Text: string);
    procedure PreviewPositionChange(Sender: TObject);
    function PreviewTempoEdit(Beat,BPM: Double; out ErrorText: string): Boolean;
    procedure FitPreview(Sender: TObject);
    procedure TimelineSeek(Seconds: Double);
  public
    ToolbarPanel, FooterPanel, InfoPanel, WorkPanel, PatternPanel, CenterPanel: TPanel;
    ImportButton, ExportButton, RestoreButton, ApplyButton, CancelButton: TButton;
    AddButton, EditButton, DeleteButton, TrackAddButton, SlotAddButton, DebugJSONButton: TButton;
    InfoLabel, StatusLabel, LibraryLabel: TLabel;
    JSONMemo: TMemo; // 高度なJSON編集と不正な既存文書の修復用。通常画面では表示しない。
    PatternList: TListBox;
    PreviewBox: TMusicStudioPsdPreviewSurface;
    TimelineBox: TMusicStudioArrangementView;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    AddMenu: TPopupMenu;
    TrackAddMenu, ArrangementMenu, SlotAddMenu: TPopupMenu;
    destructor Destroy; override;
    procedure ImportButtonClick(Sender: TObject);
    procedure ExportButtonClick(Sender: TObject);
    procedure RestoreButtonClick(Sender: TObject);
    procedure CancelButtonClick(Sender: TObject);
    procedure JSONMemoChange(Sender: TObject);
    // 不正な既存JSONも修復/取消可能にする。キャンセルはホストへ書き戻さない。
    procedure LoadDocument(const JSONText: string);
    // 共有設定の保存後にrevisionを読み直し、シーンと左一覧を更新する。
    procedure SharedLibraryChanged;
    procedure UndoEdit;
    procedure RedoEdit;
    function ImportJSONFile(const Path: string; out ErrorText: string): Boolean;
    function DropPatternAt(PatternIndex, TrackIndex: Integer; StartSeconds: Double; out Reason: string): Boolean; overload;
    function DropPatternAt(PatternIndex, TrackIndex, SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean; overload;
    property SilentVisualMode: Boolean read FSilentVisualMode write SetSilentVisualMode;
    property SharedLibrary: TMusicStudioSharedPsdLibrary read FSharedLibrary;
    property LibraryRoot: string read GetLibraryRoot write SetLibraryRoot;
    property LibraryKind: string read FLibraryKind;
    function DropSelectedLibraryAt(TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
    property SelectedLibraryPattern: Integer read SelectedPatternIndex;
    property Document: TMusicStudioDocument read FDocument;
    property Preview: TMusicStudioPreviewFrame read FPreview;
    property LibraryThumbnails: TMusicStudioLibraryThumbnails read FLibraryThumbnails;
    property TempoRuler: TMusicStudioTempoRulerEditor read FTempoRuler;
    property OnApplyJSON: TMusicStudioApplyJSONEvent read FOnApplyJSON write FOnApplyJSON;
  end;

implementation

uses
  System.IOUtils, System.SysUtils, System.UITypes, Vcl.Graphics, Winapi.Windows,
  SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_ProjectData,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_SharedLibraryEditor,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_TimingFrame, SYNC_MusicStudio_LayerStepData;

{$R *.dfm}

const SLOT_KINDS: array[0..9] of string = ('audio','psd','singing','emotion','animation','instrument','performance','rhythm','generic','tempo');

function Panel(Owner: TComponent; Parent: TWinControl; Align: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Owner);
  Result.Parent := Parent;
  Result.SetBounds(0, 0, Parent.ClientWidth, Parent.ClientHeight);
  if Align in [alLeft, alRight] then Result.Width := Size else Result.Height := Size;
  Result.Align := Align;
  Result.BevelOuter := bvNone;
  ApplySyncMusicStudioDarkPanel(Result);
end;

function Button(Owner: TComponent; Parent: TWinControl; X, Y, Width: Integer;
  const Caption: string; Click: TNotifyEvent): TButton;
begin
  Result := TMusicStudioButton.Create(Owner);
  Result.Parent := Parent;
  Result.SetBounds(X, Y, Width, 30);
  Result.Caption := Caption;
  Result.OnClick := Click;
  ApplySyncMusicStudioDarkButton(Result);
end;

function LabelAt(Owner: TComponent; Parent: TWinControl; X, Y: Integer;
  const Caption: string): TLabel;
begin
  Result := TLabel.Create(Owner);
  Result.Parent := Parent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := Caption;
end;

procedure TFormMusicStudioSettings.BuildUI;
var
  Header, Footer, Overview, TrackHeader: TPanel;
  Item: TMenuItem;
  I: Integer;
  LabelControl: TLabel;
  Splitter: TSplitter;
begin
  ToolbarPanel := Panel(Self, Self, alTop, 60);
  ImportButton := Button(Self, ToolbarPanel, 16, 16, 104, 'JSON読込', ImportButtonClick);
  ExportButton := Button(Self, ToolbarPanel, 128, 16, 104, 'JSON保存', ExportButtonClick);
  RestoreButton := Button(Self, ToolbarPanel, 248, 16, 160, '開いた時点に戻す', RestoreButtonClick);
  Button(Self, ToolbarPanel, 424, 16, 108, 'JSONを編集…', RawJSONButtonClick);
  DebugJSONButton := Button(Self,ToolbarPanel,550,16,132,'サンプルJSON…',DebugJSONClick);
  FTempoButton := Button(Self,ToolbarPanel,704,16,166,'テンポ / 拍子…',TempoSettingsClick);
  FTempoButton.ShowHint := True;
  FooterPanel := Panel(Self, Self, alBottom, 58);
  ApplyButton := Button(Self, FooterPanel, 16, 14, 148, '適用して閉じる', nil);
  ApplyButton.ModalResult := mrOK;
  CancelButton := Button(Self, FooterPanel, 176, 14, 104, 'キャンセル', CancelButtonClick);
  CancelButton.ModalResult := mrCancel;
  CancelButton.Cancel := True;
  StatusLabel := LabelAt(Self, FooterPanel, 306, 20, '');
  StatusLabel.AutoSize := False;
  StatusLabel.Width := FooterPanel.Width - 322;
  StatusLabel.Anchors := [akLeft, akTop, akRight];
  InfoPanel := Panel(Self, Self, alTop, 40);
  InfoPanel.Top := ToolbarPanel.Height;
  InfoLabel := LabelAt(Self, InfoPanel, 16, 10,
    '右のスロットを選択 → 左で追加・設定 → ドラッグで配置 → JSON保存');
  InfoLabel.AutoSize := False;
  InfoLabel.Width := InfoPanel.Width - 32;
  InfoLabel.Anchors := [akLeft, akTop, akRight];
  WorkPanel := Panel(Self, Self, alClient, 0);
  PatternPanel := Panel(Self, WorkPanel, alLeft, 268);
  PatternPanel.Constraints.MinWidth := 230;
  PatternPanel.Constraints.MaxWidth := 360;
  Header := Panel(Self, PatternPanel, alTop, 50);
  LibraryLabel := LabelAt(Self, Header, 16, 17, 'スロットを選択');
  AddButton := Button(Self, Header, Header.Width - 50, 10, 34, '＋', AddButtonClick);
  AddButton.Anchors := [akTop, akRight];
  Footer := Panel(Self, PatternPanel, alBottom, 92);
  EditButton := Button(Self, Footer, 16, 12, 142, '選択パターンを設定', EditButtonClick);
  DeleteButton := Button(Self, Footer, 166, 12, 86, '削除', DeleteButtonClick);
  LabelAt(Self, Footer, 16, 56, '名前・色はすべての属性で共通');
  PatternList := TListBox.Create(Self);
  PatternList.Parent := PatternPanel;
  PatternList.Align := alClient;
  PatternList.Style := lbOwnerDrawFixed;
  PatternList.ItemHeight := MulDiv(58, CurrentPPI, 96);
  PatternList.BorderStyle := bsNone;
  PatternList.OnClick := PatternListClick;
  PatternList.OnDblClick := EditButtonClick;
  PatternList.OnDrawItem := PatternListDrawItem;
  PatternList.OnKeyDown := PatternListKeyDown;
  PatternList.DragMode := dmAutomatic;
  ApplySyncMusicStudioDarkListBox(PatternList);
  Splitter := TSplitter.Create(Self);
  Splitter.Parent := WorkPanel;
  Splitter.Left := PatternPanel.Width;
  Splitter.Width := 6;
  Splitter.MinSize := 230;
  CenterPanel := Panel(Self, WorkPanel, alClient, 0);
  Overview := Panel(Self, CenterPanel, alTop, 272);
  FOverview := Overview;
  FPreview := TMusicStudioPreviewFrame.Create(Self); FPreview.Parent := Overview;
  FPreview.Align := alClient; PreviewBox := FPreview.Stage;
  TrackHeader := Panel(Self, CenterPanel, alTop, 44);
  TrackHeader.Top := Overview.Height;
  TrackAddButton := Button(Self, TrackHeader, 12, 7, 120, 'トラック＋', TrackAddClick);
  SlotAddButton := Button(Self,TrackHeader,140,7,112,'スロット＋',SlotMenuClick);
  LabelControl := LabelAt(Self,TrackHeader,270,14,'小節・拍 / 移動と両端はグリッドへ ・ 小節右クリックで手動テンポ');
  LabelControl.AutoSize := False; LabelControl.Width := TrackHeader.Width - 286;
  LabelControl.Anchors := [akLeft,akTop,akRight];
  TimelineBox := TMusicStudioArrangementView.Create(Self);
  FPreview.SharedVisualCache := TimelineBox.VisualCache;
  TimelineBox.SceneCache := FPreview.SceneCache;
  TimelineBox.Parent := CenterPanel;
  TimelineBox.Align := alClient;
  TimelineBox.OnDragOver := TimelineDragOver; TimelineBox.OnDragDrop := TimelineDragDrop;
  TimelineBox.OnDblClick := TimelineDblClick; TimelineBox.OnClipMove := TimelineClipMove;
  TimelineBox.OnClipResize := TimelineClipResize;
  TimelineBox.OnSelectionChange := TimelineSelectionChange;
  TimelineBox.OnSeek := TimelineSeek; FPreview.OnPositionChange := PreviewPositionChange; FPreview.OnTempoEdit := PreviewTempoEdit;
  JSONMemo := TMemo.Create(Self);
  JSONMemo.Parent := Self;
  JSONMemo.Visible := False;
  JSONMemo.OnChange := JSONMemoChange;
  OpenDialog := TOpenDialog.Create(Self);
  OpenDialog.Filter := 'JSONファイル (*.json)|*.json';
  OpenDialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
  SaveDialog := TSaveDialog.Create(Self);
  SaveDialog.Filter := OpenDialog.Filter;
  SaveDialog.DefaultExt := 'json';
  SaveDialog.FileName := 'SYNC_MusicStudio.json';
  SaveDialog.Options := [ofOverwritePrompt, ofEnableSizing];
  AddMenu := TPopupMenu.Create(Self);
  TrackAddMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(TrackAddMenu); Item.Caption := '音声トラック';
  Item.OnClick := AddAudioTrackClick; TrackAddMenu.Items.Add(Item);
  Item := TMenuItem.Create(TrackAddMenu); Item.Caption := 'PSDトラック（楽器・歌唱など）';
  Item.OnClick := AddPsdTrackClick; TrackAddMenu.Items.Add(Item);
  Item := TMenuItem.Create(TrackAddMenu); Item.Caption := '楽器トラック（歌唱も可能）';
  Item.OnClick := AddInstrumentTrackClick; TrackAddMenu.Items.Add(Item);
  ArrangementMenu := TPopupMenu.Create(Self); ArrangementMenu.OnPopup := ArrangementMenuPopup;
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := '音声トラックを追加';
  Item.OnClick := AddAudioTrackClick; ArrangementMenu.Items.Add(Item);
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := 'PSDトラックを追加';
  Item.OnClick := AddPsdTrackClick; ArrangementMenu.Items.Add(Item);
  FTrackSettingsItem := TMenuItem.Create(ArrangementMenu); FTrackSettingsItem.Caption := 'トラック設定…';
  FTrackSettingsItem.OnClick := TrackSettingsClick; ArrangementMenu.Items.Add(FTrackSettingsItem);
  FTrackDeleteItem := TMenuItem.Create(ArrangementMenu); FTrackDeleteItem.Caption := 'トラックを削除…';
  FTrackDeleteItem.OnClick := TrackDeleteClick; ArrangementMenu.Items.Add(FTrackDeleteItem);
  FClipEditItem := TMenuItem.Create(ArrangementMenu); FClipEditItem.Caption := '配置の開始・長さ…';
  FClipEditItem.OnClick := ClipEditClick; ArrangementMenu.Items.Add(FClipEditItem);
  FClipDeleteItem := TMenuItem.Create(ArrangementMenu); FClipDeleteItem.Caption := 'この配置を削除';
  FClipDeleteItem.OnClick := ClipDeleteClick; ArrangementMenu.Items.Add(FClipDeleteItem);
  SlotAddMenu := TPopupMenu.Create(Self);
  for I := 0 to High(SLOT_KINDS) do begin
    Item := TMenuItem.Create(SlotAddMenu); Item.Caption := MusicStudioSlotKindName(SLOT_KINDS[I])+'スロット';
    Item.Tag := I; Item.OnClick := AddSlotClick; SlotAddMenu.Items.Add(Item);
  end;
  FSlotAddItem := TMenuItem.Create(ArrangementMenu); FSlotAddItem.Caption := 'このトラックにスロットを追加…';
  FSlotAddItem.OnClick := SlotMenuClick; ArrangementMenu.Items.Add(FSlotAddItem);
  FSlotSettingsItem := TMenuItem.Create(ArrangementMenu); FSlotSettingsItem.Caption := 'スロット設定…';
  FSlotSettingsItem.OnClick := SlotSettingsClick; ArrangementMenu.Items.Add(FSlotSettingsItem);
  FSlotDeleteItem := TMenuItem.Create(ArrangementMenu); FSlotDeleteItem.Caption := 'このスロットを削除…';
  FSlotDeleteItem.OnClick := SlotDeleteClick; ArrangementMenu.Items.Add(FSlotDeleteItem);
  FSlotUpItem := TMenuItem.Create(ArrangementMenu); FSlotUpItem.Caption := 'スロットを上へ';
  FSlotUpItem.OnClick := SlotUpClick; ArrangementMenu.Items.Add(FSlotUpItem);
  FSlotDownItem := TMenuItem.Create(ArrangementMenu); FSlotDownItem.Caption := 'スロットを下へ';
  FSlotDownItem.OnClick := SlotDownClick; ArrangementMenu.Items.Add(FSlotDownItem);
  TimelineBox.PopupMenu := ArrangementMenu;
end;

procedure TFormMusicStudioSettings.FormCreate(Sender: TObject);
begin
  FDocument := TMusicStudioDocument.Create;
  FEditHistory := TMusicStudioEditHistory.Create;
  FSharedLibrary := TMusicStudioSharedPsdLibrary.Create; FDocument.AssetResolver := FSharedLibrary.ResolvePath;
  ApplySyncMusicStudioDarkForm(Self);
  ApplyMusicStudioEditorFont(Self);
  BuildUI;
  FLibraryThumbnails := TMusicStudioLibraryThumbnails.Create(PatternList,TimelineBox.VisualCache);
  FLibraryThumbnails.OnMetadataChange := LibraryMetadataChanged;
  KeyPreview := True; OnKeyDown := TransportKeyDown; OnKeyUp := TransportKeyUp;
  OnDeactivate := TransportDeactivate;
  FPreview.SharedLibrary := FSharedLibrary;
  FTempoRuler := TMusicStudioTempoRulerEditor.Create(Self,FDocument,CommitMutation);
  TimelineBox.OnTempoMenu := TempoRulerMenu;
  FPreview.PlacementEditor.OnCommit := PlacementCommit;
  OnResize := FitPreview; FitPreview(nil);
end;

procedure TFormMusicStudioSettings.FitPreview(Sender: TObject);
var BaseHeight: Integer;
begin
  if not Assigned(FOverview) then Exit;
  BaseHeight := MulDiv(ClientHeight,96,CurrentPPI)-562+160;
  if BaseHeight<160 then BaseHeight := 160;
  if BaseHeight>272 then BaseHeight := 272;
  FOverview.Height := MulDiv(BaseHeight,CurrentPPI,96);
end;

destructor TFormMusicStudioSettings.Destroy;
begin
  FValid := False;
  FreeAndNil(FTempoRuler); FreeAndNil(FLibraryThumbnails); FreeAndNil(FEditHistory);
  if Assigned(FPreview) then begin FPreview.Bind(nil); FPreview.SharedVisualCache := nil; FPreview.SharedLibrary := nil; end;
  if Assigned(TimelineBox) then begin TimelineBox.Bind(nil); TimelineBox.SceneCache := nil; end;
  if Assigned(PatternList) then PatternList.OnDrawItem := nil;
  FDocument.AssetResolver := nil; FDocument.Free; FSharedLibrary.Free;
  inherited;
end;

procedure TFormMusicStudioSettings.LoadDocument(const JSONText: string);
begin
  FEditHistory.Clear;
  FCancelRequested := False;
  FInitialText := JSONText;
  if Trim(FInitialText) = '' then FInitialText := MUSIC_STUDIO_DEFAULT_JSON;
  // 明示した再読込とOnChangeの二重Bindを防ぎ、同一音源の解析を重複起動しない。
  FSyncing := True;
  try JSONMemo.Text := FInitialText; finally FSyncing := False; end;
  JSONMemoChange(nil);
end;

procedure TFormMusicStudioSettings.JSONMemoChange(Sender: TObject);
var
  ErrorText: string;
begin
  if FSyncing then Exit;
  FPreview.Stop;
  // 文書のRootを入れ替える前に、旧行番号と画像スナップショットを外す。
  // スクロールバー/捕捉解除の同期通知も旧JSONへアクセスできなくする。
  TimelineBox.Bind(nil); FPreview.Bind(nil);
  FValid := FDocument.TryLoad(JSONMemo.Text, ErrorText);
  if FValid then TimelineBox.Bind(FDocument) else TimelineBox.Bind(nil);
  if FValid then FPreview.Bind(FDocument) else FPreview.Bind(nil);
  if FValid then StatusLabel.Caption := Format('パターン %d件  ·  JSON %d文字',
    [FDocument.PatternCount, Length(JSONMemo.Text)])
  else StatusLabel.Caption := 'JSONを修復してください: ' + ErrorText;
  RefreshPatterns;
end;

function TFormMusicStudioSettings.SelectedPatternIndex: Integer;
begin
  Result := -1;
  if (PatternList.ItemIndex >= 0) and (PatternList.ItemIndex < Length(FVisiblePatterns)) then
    Result := FVisiblePatterns[PatternList.ItemIndex];
end;

procedure TFormMusicStudioSettings.SelectPatternIndex(Index: Integer);
var I: Integer;
begin
  PatternList.ItemIndex := -1;
  for I := 0 to High(FVisiblePatterns) do if FVisiblePatterns[I]=Index then begin PatternList.ItemIndex := I; Break; end;
  PatternListClick(nil);
end;
procedure TFormMusicStudioSettings.LibraryMetadataChanged(Sender: TObject);
begin UpdateLibrary; end;
procedure TFormMusicStudioSettings.TransportKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FPreview.HandleTempoKey(Key,Shift) then Exit;
  if (Key=VK_ESCAPE) and FPreview.PlacementEditor.Cancel then begin Key := 0; Exit; end;
  if (Key=VK_ESCAPE) and TimelineBox.CancelInteraction then begin Key := 0; Exit; end;
  if (ActiveControl=FPreview.TempoEdit) or not ((ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox)) then begin
    if (Key=Ord('Z')) and (ssCtrl in Shift) then begin
      if ssShift in Shift then RedoEdit else UndoEdit; Key := 0; Exit;
    end;
    if (Key=Ord('Y')) and (Shift=[ssCtrl]) then begin RedoEdit; Key := 0; Exit; end;
  end;
  if (Key<>VK_SPACE) or (Shift<>[]) or (ActiveControl is TCustomEdit) or
    (ActiveControl is TCustomComboBox) or (ActiveControl is TButton) then Exit;
  Key := 0;
  if not FTransportSpaceDown then begin FTransportSpaceDown := True; FPreview.TogglePlayback; end;
end;
procedure TFormMusicStudioSettings.TransportKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin if Key=VK_SPACE then FTransportSpaceDown := False; end;
procedure TFormMusicStudioSettings.TransportDeactivate(Sender: TObject);
begin FTransportSpaceDown := False; TimelineBox.CancelInteraction; FPreview.PlacementEditor.Cancel; end;

function TFormMusicStudioSettings.VisiblePattern(Index: Integer): TMusicStudioPattern;
begin
  Result := Default(TMusicStudioPattern);
  if (Index>=0) and (Index<Length(FLibraryItems)) then Result := FLibraryItems[Index].Pattern;
end;
function TFormMusicStudioSettings.GetLibraryRoot: string;
begin Result := FSharedLibrary.Root; end;
procedure TFormMusicStudioSettings.SetLibraryRoot(const Value: string);
begin
  FPreview.Bind(nil); FPreview.SharedLibrary := nil; FDocument.AssetResolver := nil; FSharedLibrary.Free;
  FSharedLibrary := TMusicStudioSharedPsdLibrary.Create(Value); FDocument.AssetResolver := FSharedLibrary.ResolvePath;
  FPreview.SharedLibrary := FSharedLibrary;
  if FValid then begin TimelineBox.Bind(FDocument); FPreview.Bind(FDocument); end;
  UpdateLibrary;
end;
procedure TFormMusicStudioSettings.UpdateLibrary;
var I,N: Integer; SelectedID,Kind,AssetID,K: string; T: TMusicStudioTrack; S: TMusicStudioSlot; Item: TMenuItem;
  Assets: TArray<TMusicStudioPsdAsset>; Emotions: TArray<TMusicStudioLibraryItem>; P: TMusicStudioPattern;
begin
  SelectedID := VisiblePattern(PatternList.ItemIndex).ID; Kind := ''; AssetID := '';
  FAvailableKinds := nil; S := Default(TMusicStudioSlot);
  if FValid and (TimelineBox.SelectedTrack >= 0) and (TimelineBox.SelectedTrack<FDocument.TrackCount) and (TimelineBox.SelectedSlot >= 0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack); AssetID := T.PsdAssetID;
    if TimelineBox.SelectedSlot<Length(T.Slots) then begin
      S := T.Slots[TimelineBox.SelectedSlot]; Kind := S.Kind;
      FAvailableKinds := MusicStudioLibraryKinds(S.Accepts,AssetID,T.Kind='psd');
      if Length(FAvailableKinds)=1 then Kind := FAvailableKinds[0]
      else if Length(FAvailableKinds)>1 then Kind := 'generic';
    end;
  end;
  FLibraryKind := Kind;
  Emotions := nil;
  if FValid then begin
    Assets := FSharedLibrary.Assets;
    for I := 0 to FDocument.PatternCount-1 do begin
      P := FDocument.PatternAt(I); if P.Kind<>'emotion' then Continue;
      N := Length(Emotions); SetLength(Emotions,N+1); Emotions[N] := MusicStudioEmotionItem(P,Assets);
    end;
  end;
  TimelineBox.SetEmotionItems(Emotions);
  if Kind='' then LibraryLabel.Caption := 'スロットを選択' else LibraryLabel.Caption := MusicStudioSlotKindName(Kind);
  if FValid then FLibraryItems := MusicStudioLibraryItems(FDocument,FSharedLibrary,FAvailableKinds,AssetID) else FLibraryItems := nil;
  FVisiblePatterns := nil; SetLength(FVisiblePatterns,Length(FLibraryItems)); PatternList.Items.BeginUpdate;
  try
    PatternList.Items.Clear;
    for I := 0 to High(FLibraryItems) do begin
      FVisiblePatterns[I] := FLibraryItems[I].PatternIndex; PatternList.Items.Add(FLibraryItems[I].Pattern.Name);
      if FLibraryItems[I].Pattern.ID=SelectedID then PatternList.ItemIndex := I;
    end;
  finally PatternList.Items.EndUpdate; end;
  AddMenu.Items.Clear;
  for I := 0 to High(FAvailableKinds) do begin
    Item := TMenuItem.Create(AddMenu); Item.Caption := MusicStudioSlotKindName(FAvailableKinds[I]);
    Item.Tag := I; Item.OnClick := AddMenuClick; AddMenu.Items.Add(Item);
  end;
  for K in S.Accepts do if K='rhythm' then begin
    Item := TMenuItem.Create(AddMenu); Item.Caption := 'リズム同期（準備中）'; Item.Enabled := False; AddMenu.Items.Add(Item);
  end;
  AddButton.Enabled := FValid and (Length(FAvailableKinds)>0);
  if (Kind='emotion') or (Kind='animation') or (Kind='instrument') then
    if AssetID='' then StatusLabel.Caption := '先に歌唱PSDスロットへ共有PSDを割り当ててください。';
  if FSharedLibrary.LastWarning<>'' then begin
    StatusLabel.Caption := '読めない共有設定があります。詳細はこの表示にマウスを合わせてください。';
    StatusLabel.Hint := FSharedLibrary.LastWarning; StatusLabel.ShowHint := True;
  end;
  PatternListClick(nil);
  if FLibraryThumbnails<>nil then FLibraryThumbnails.Bind(FLibraryItems,FSharedLibrary.Root);
end;
procedure TFormMusicStudioSettings.SharedLibraryChanged;
begin
  if FValid then begin FPreview.Bind(FDocument); TimelineBox.Refresh; end;
  UpdateLibrary;
end;
procedure TFormMusicStudioSettings.AddSharedPattern(const Kind: string);
var P: TMusicStudioPattern; AssetID,Error: string; I: Integer;
begin
  AssetID := FDocument.TrackAt(TimelineBox.SelectedTrack).PsdAssetID;
  if not AddMusicStudioSharedItem(Self,FSharedLibrary,Kind,AssetID,P,Error) then begin
    if Error<>'' then MessageDlg(Error,mtError,[mbOK],0); Exit;
  end;
  SharedLibraryChanged;
  for I := 0 to High(FLibraryItems) do if (FLibraryItems[I].Pattern.AssetID=P.AssetID) and
    (FLibraryItems[I].Pattern.SharedPatternID=P.SharedPatternID) then begin PatternList.ItemIndex := I; Break; end;
  PatternListClick(nil); StatusLabel.Caption := '共有設定を保存しました。右のスロットへドラッグすると作品で使用します。';
end;
function TFormMusicStudioSettings.DropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
var P: TMusicStudioPattern; T: TMusicStudioTrack; Index: Integer; RestoreError: string;
begin
  Result := False; Reason := 'ドロップ先スロットを選択してください。';
  if not FValid or (ItemIndex<0) or (ItemIndex>=Length(FLibraryItems)) or (TrackIndex<0) then Exit;
  P := VisiblePattern(ItemIndex); T := FDocument.TrackAt(TrackIndex);
  if (SlotIndex<0) or (SlotIndex>=Length(T.Slots)) then Exit;
  if not MusicStudioSlotCompatible(P.Kind,T.Slots[SlotIndex],Reason) then Exit;
  if FLibraryItems[ItemIndex].Missing then begin Reason := '共有PSDが欠損しています。設定から復旧してください。'; Exit; end;
  if P.Kind='psd' then begin
    FDocument.AssignPsd(TrackIndex,P.AssetID); Result := CommitMutation; Exit;
  end;
  if (P.AssetID<>'') and (P.AssetID<>T.PsdAssetID) then begin Reason := '配置先PSDと共有パターンのPSDが一致しません。'; Exit; end;
  Index := FLibraryItems[ItemIndex].PatternIndex;
  if P.AssetID<>'' then Index := FDocument.AddReference(P);
  Result := DropPatternAt(Index,TrackIndex,SlotIndex,StartSeconds,Reason);
  if not Result and (P.AssetID<>'') then begin FDocument.TryLoad(JSONMemo.Text,RestoreError); UpdateLibrary; end;
end;
function TFormMusicStudioSettings.DropSelectedLibraryAt(TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
begin Result := DropLibraryItemAt(PatternList.ItemIndex,TrackIndex,SlotIndex,StartSeconds,Reason); end;

procedure TFormMusicStudioSettings.SetSilentVisualMode(Value: Boolean);
begin
  FSilentVisualMode := Value;
  FPreview.SilentVisualMode := Value;
  TimelineBox.SilentVisualMode := Value;
end;

procedure TFormMusicStudioSettings.RefreshPatterns;
begin
  FTempoButton.Enabled := FValid;
  if FValid then begin
    FTempoButton.Caption := 'テンポ / 拍子…';
    FTempoButton.Hint := Format('先頭BPM · テンポ点 %d個。演奏は拍固定、音声/歌唱MIDIは秒固定。',[FDocument.Timing.PointCount]);
  end;
  TrackAddButton.Enabled := FValid;
  SlotAddButton.Enabled := FValid and (FDocument.TrackCount > 0);
  TimelineBox.Refresh;
  TimelineSelectionChange(nil);
end;

procedure TFormMusicStudioSettings.SyncMemo;
var
  Text, ErrorText: string;
begin
  if not FDocument.TrySave(Text, ErrorText) then raise Exception.Create(ErrorText);
  FSyncing := True;
  try JSONMemo.Text := Text; finally FSyncing := False; end;
  FPreview.Bind(FDocument);
  StatusLabel.Caption := Format('パターン %d件  ·  JSON %d文字', [FDocument.PatternCount, Length(Text)]);
  RefreshPatterns;
end;

function TFormMusicStudioSettings.ReadDocument(out JSONText: string): Boolean;
var
  ErrorText: string;
begin
  Result := TryNormalizeMusicStudioJSON(JSONMemo.Text, JSONText, ErrorText);
  if not Result then MessageDlg(ErrorText, mtError, [mbOK], 0);
end;

procedure TFormMusicStudioSettings.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  ErrorText, JSONText: string;
begin
  FPreview.Stop;
  CanClose := True;
  if FCancelRequested then Exit;
  CanClose := False;
  try
    if not ReadDocument(JSONText) then Exit;
    if Assigned(FOnApplyJSON) then
      if not FOnApplyJSON(JSONText, ErrorText) then
      begin
        MessageDlg(ErrorText, mtError, [mbOK], 0);
        Exit;
      end;
    CanClose := True;
  except
    on E: Exception do MessageDlg('設定を保存できませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMusicStudioSettings.ImportButtonClick(Sender: TObject);
var
  ErrorText: string;
begin
  FPreview.Stop;
  if not OpenDialog.Execute then Exit;
  try
    if not ImportJSONFile(OpenDialog.FileName, ErrorText) then
    begin
      MessageDlg(ErrorText, mtError, [mbOK], 0);
      Exit;
    end;
  except
    on E: Exception do MessageDlg('JSONファイルを読み込めませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

function TFormMusicStudioSettings.ImportJSONFile(const Path: string; out ErrorText: string): Boolean;
var Text: string;
begin
  FPreview.Stop;
  Result := TryReadMusicStudioJSONFile(Path,Text,ErrorText);
  if Result then JSONMemo.Text := Text; // 初期文書と素材実体は上書きしない。
end;
procedure TFormMusicStudioSettings.DebugJSONClick(Sender: TObject);
var ModulePath: array[0..32767] of Char; Candidate,ErrorText: string;
begin
  GetModuleFileName(HInstance,ModulePath,Length(ModulePath));
  Candidate := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ModulePath),'..\..\Samples\Debug'));
  if TDirectory.Exists(Candidate) then begin
    OpenDialog.InitialDir := Candidate; OpenDialog.FileName := TPath.Combine(Candidate,'generic-slots.json');
  end;
  if OpenDialog.Execute then if not ImportJSONFile(OpenDialog.FileName,ErrorText) then
    MessageDlg(ErrorText,mtError,[mbOK],0);
end;

procedure TFormMusicStudioSettings.ExportButtonClick(Sender: TObject);
var
  JSONText: string;
begin
  if not ReadDocument(JSONText) or not SaveDialog.Execute then Exit;
  try TFile.WriteAllText(SaveDialog.FileName, JSONText, TEncoding.UTF8);
  except
    on E: Exception do MessageDlg('JSONファイルを保存できませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMusicStudioSettings.RestoreButtonClick(Sender: TObject);
begin
  JSONMemo.Text := FInitialText;
end;

procedure TFormMusicStudioSettings.CancelButtonClick(Sender: TObject);
begin
  FPreview.Stop;
  FCancelRequested := True;
end;

procedure TFormMusicStudioSettings.AddButtonClick(Sender: TObject);
var
  Position: TPoint;
begin
  if Length(FAvailableKinds)=0 then Exit;
  if Length(FAvailableKinds)=1 then begin AddAvailablePattern(FAvailableKinds[0]); Exit; end;
  Position := AddButton.ClientToScreen(Point(0, AddButton.Height));
  AddMenu.Popup(Position.X, Position.Y);
end;
procedure TFormMusicStudioSettings.AddAvailablePattern(const Kind: string);
var Index: Integer;
begin
  if Kind='performance' then AddPerformanceClick(nil)
  else if Kind='tempo' then begin Index := FDocument.AddTempo; if CommitMutation then SelectPatternIndex(Index); end
  else if (Kind='psd') or (Kind='emotion') or (Kind='animation') or (Kind='instrument') then AddSharedPattern(Kind)
  else if Kind='audio' then AddPattern(False)
  else if Kind='singing' then AddPattern(True);
end;
procedure TFormMusicStudioSettings.AddMenuClick(Sender: TObject);
var I: Integer;
begin
  I := TMenuItem(Sender).Tag;
  if (I>=0) and (I<Length(FAvailableKinds)) then AddAvailablePattern(FAvailableKinds[I]);
end;
procedure TFormMusicStudioSettings.AddPerformanceClick(Sender: TObject);
var Index: Integer; Pattern: TMusicStudioPattern; Steps: TMusicStudioLayerStepData; AssetID: string;
begin
  if not FValid then Exit;
  Index := FDocument.AddPerformance;
  AssetID := ''; if TimelineBox.SelectedTrack>=0 then AssetID := FDocument.TrackAt(TimelineBox.SelectedTrack).PsdAssetID;
  Steps := TMusicStudioLayerStepData.Create;
  try Pattern := FDocument.PatternAt(Index); Steps.LoadJSON(Pattern.ConfigJSON); Steps.Enable(AssetID);
    Pattern.ConfigJSON := Steps.ConfigJSON; FDocument.UpdatePattern(Pattern);
  finally Steps.Free; end;
  if CommitMutation then begin SelectPatternIndex(Index); PatternListClick(nil); end;
end;

procedure TFormMusicStudioSettings.AddPattern(Singing: Boolean);
var
  Index: Integer;
begin
  if not FValid then Exit;
  if Singing then Index := FDocument.AddSinging else Index := FDocument.AddAudio;
  if not CommitMutation then Exit;
  SelectPatternIndex(Index);
  PatternListClick(nil);
end;

procedure TFormMusicStudioSettings.PatternListClick(Sender: TObject);
var
  Selected: Boolean; Kind: string;
begin
  Selected := FValid and (PatternList.ItemIndex >= 0);
  EditButton.Enabled := Selected;
  if Selected then begin
    Kind := VisiblePattern(PatternList.ItemIndex).Kind;
    EditButton.Enabled := (Kind='audio') or (Kind='singing') or (Kind='performance') or (Kind='tempo') or
      (Kind='psd') or (Kind='emotion') or (Kind='animation') or (Kind='instrument');
  end;
  DeleteButton.Enabled := EditButton.Enabled and (SelectedPatternIndex>=0) and not FLibraryItems[PatternList.ItemIndex].Shared;
end;

procedure TFormMusicStudioSettings.EditButtonClick(Sender: TObject);
var
  Dialog: TMusicStudioPatternSettings;
  Pattern: TMusicStudioPattern;
  Asset: TMusicStudioPsdAsset; AssetID,Error: string;
  SharedError: string;
begin
  if not FValid or (PatternList.ItemIndex < 0) then Exit;
  if not EditButton.Enabled then Exit;
  Pattern := VisiblePattern(PatternList.ItemIndex);
  if Pattern.AssetID<>'' then begin
    if not EditMusicStudioSharedItem(Self,FSharedLibrary,Pattern,SharedError) then begin
      if SharedError<>'' then MessageDlg(SharedError,mtError,[mbOK],0); Exit;
    end;
    if SelectedPatternIndex>=0 then begin Pattern.ID := FDocument.PatternAt(SelectedPatternIndex).ID; FDocument.UpdatePattern(Pattern); CommitMutation; end;
    SharedLibraryChanged; Exit;
  end;
  if (Pattern.Kind <> 'audio') and (Pattern.Kind <> 'singing') and (Pattern.Kind<>'performance') and (Pattern.Kind<>'tempo') then Exit;
  Dialog := TMusicStudioPatternSettings.Create(Self);
  try
    Dialog.SilentVisualMode := FSilentVisualMode;
    if (Pattern.Kind='performance') and MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) then begin
      AssetID := MusicStudioPerformanceLayerAsset(Pattern.ConfigJSON);
      if (AssetID='') and (TimelineBox.SelectedTrack>=0) then AssetID := FDocument.TrackAt(TimelineBox.SelectedTrack).PsdAssetID;
      Asset := Default(TMusicStudioPsdAsset);
      if AssetID<>'' then FSharedLibrary.TryRead(AssetID,Asset,Error);
      Dialog.LoadPerformanceSteps(Pattern,AssetID,Asset.FilePath,Asset.ConfigJSON,FDocument.Timing.BPMAt(0),FDocument.Timing.TimingJSON);
    end else Dialog.LoadPattern(Pattern);
    while Dialog.ShowModal=mrOK do begin
      try Dialog.ReadPattern(Pattern); FDocument.UpdatePattern(Pattern);
      except on E: Exception do begin MessageDlg(E.Message,mtWarning,[mbOK],0); Continue; end; end;
      if CommitMutation then Break;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TFormMusicStudioSettings.DeleteButtonClick(Sender: TObject);
begin
  if not FValid or (PatternList.ItemIndex < 0) then Exit;
  if not DeleteButton.Enabled then Exit;
  if FDocument.PatternInUse(FDocument.PatternAt(SelectedPatternIndex).ID) then begin
    StatusLabel.Caption := '配置中のパターンです。先にトラック上の配置を削除してください。'; Exit;
  end;
  if MessageDlg('選択したパターンを削除しますか？ 音源ファイルは保持します。',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FDocument.RemovePattern(SelectedPatternIndex);
  SyncMemo;
end;

procedure TFormMusicStudioSettings.PatternListDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Pattern: TMusicStudioPattern;
  R: TRect;
  Value: Integer;
  Detail: string;
  TextLeft,PPI: Integer;
begin
  if not FValid or (Index < 0) or (Index >= Length(FVisiblePatterns)) then Exit;
  Pattern := VisiblePattern(Index);
  if odSelected in State then PatternList.Canvas.Brush.Color := $0048433B
  else PatternList.Canvas.Brush.Color := $002B2B2B;
  PatternList.Canvas.FillRect(Rect);
  Value := StrToInt('$' + Copy(Pattern.Color, 2, 6));
  PatternList.Canvas.Brush.Color := ((Value and $FF) shl 16) or (Value and $FF00) or (Value shr 16);
  R := Rect;
  PPI := PatternList.CurrentPPI;
  R.Left := Rect.Left + MulDiv(8,PPI,96);
  R.Right := R.Left + MulDiv(4,PPI,96);
  InflateRect(R, 0, -MulDiv(7,PPI,96));
  PatternList.Canvas.FillRect(R);
  TextLeft := MulDiv(22,PPI,96);
  if (Pattern.Kind='psd') or (Pattern.Kind='emotion') then begin
    FLibraryThumbnails.Draw(PatternList.Canvas,Index,Rect,$00333333);
    TextLeft := MulDiv(76,PPI,96);
  end;
  PatternList.Canvas.Brush.Style := bsClear;
  PatternList.Canvas.Font.Assign(Font);
  PatternList.Canvas.Font.Color := $00E6E6E6;
  R := Rect;
  Inc(R.Left, TextLeft);
  Dec(R.Right, MulDiv(8,PPI,96));
  R.Top := Rect.Top + MulDiv(7,PPI,96);
  R.Bottom := Rect.Top + PatternList.ItemHeight div 2;
  PatternList.Canvas.TextRect(R, Pattern.Name, [tfSingleLine, tfEndEllipsis]);
  PatternList.Canvas.Font.Color := $00AAAAAA;
  R.Top := R.Bottom;
  R.Bottom := Rect.Bottom - MulDiv(4,PPI,96);
  if Pattern.Kind = 'singing' then begin
    if Pattern.FilePath = '' then Detail := '歌唱  ·  歌詞MIDI未選択'
    else Detail := '歌唱  ·  ' + ExtractFileName(Pattern.FilePath);
  end
  else if Pattern.Kind='performance' then begin
    if MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) then Detail := '演奏 · 拍レイヤーstep'
    else Detail := '演奏 · 拍で記録 / ピアノロール';
  end
  else if Pattern.Kind='tempo' then Detail := 'テンポ · MIDI参照 / 曲全体へ適用'
  else if Pattern.AssetID<>'' then begin
    if FLibraryItems[Index].Missing then Detail := '共有PSD欠損: 設定から復旧'
    else Detail := MusicStudioSlotKindName(Pattern.Kind)+' · 共有 '+Copy(Pattern.AssetID,1,8);
  end
  else if Pattern.Kind <> 'audio' then Detail := '未対応属性: ' + Pattern.Kind
  else if Pattern.FilePath = '' then Detail := 'オーディオ  ·  ファイル未選択'
  else Detail := Format('オーディオ  ·  %d%%  ·  %s', [Round(Pattern.Volume * 100), ExtractFileName(Pattern.FilePath)]);
  PatternList.Canvas.TextRect(R, Detail, [tfSingleLine, tfEndEllipsis]);
  PatternList.Canvas.Brush.Style := bsSolid;
end;

procedure TFormMusicStudioSettings.PatternListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then begin Key := 0; EditButtonClick(nil); end;
end;

procedure TFormMusicStudioSettings.RawJSONButtonClick(Sender: TObject);
var
  Dialog: TForm;
  Memo: TMemo;
  Footer: TPanel;
  Text, ErrorText: string;
begin
  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := '演奏スタジオ - JSON編集';
    Dialog.SetBounds(Left + 40, Top + 40, 880, 600);
    ApplySyncMusicStudioDarkForm(Dialog);
    ApplyMusicStudioEditorFont(Dialog);
    Footer := Panel(Dialog, Dialog, alBottom, 48);
    Button(Dialog, Footer, 12, 10, 140, '編集画面へ反映', nil).ModalResult := mrOK;
    Button(Dialog, Footer, 164, 10, 100, 'キャンセル', nil).ModalResult := mrCancel;
    Memo := TMemo.Create(Dialog);
    Memo.Parent := Dialog;
    Memo.Align := alClient;
    Memo.ScrollBars := ssBoth;
    Memo.WordWrap := False;
    Memo.Font.Name := 'Consolas';
    Memo.Text := JSONMemo.Text;
    ApplySyncMusicStudioDarkMemo(Memo);
    while Dialog.ShowModal = mrOK do
    begin
      if TryNormalizeMusicStudioJSON(Memo.Text, Text, ErrorText) then
      begin
        JSONMemo.Text := Text;
        Break;
      end;
      MessageDlg(ErrorText, mtError, [mbOK], 0);
    end;
  finally
    Dialog.Free;
  end;
end;

function TFormMusicStudioSettings.CommitMutation: Boolean;
var ErrorText,BeforeText: string;
begin
  Result := False; BeforeText := JSONMemo.Text;
  try SyncMemo; FEditHistory.RecordChange(BeforeText,JSONMemo.Text); Result := True;
  except on E: Exception do begin
      FDocument.TryLoad(BeforeText, ErrorText);
      FSyncing := True; try JSONMemo.Text := BeforeText; finally FSyncing := False; end;
      FPreview.Bind(FDocument);
    RefreshPatterns; StatusLabel.Caption := '変更を反映できません: ' + E.Message;
  end; end;
end;
procedure TFormMusicStudioSettings.UndoEdit;
var Text: string; Beat,EndBeat: Double; Playing: Boolean;
begin
  Beat := FDocument.SecondsToBeat(FPreview.Position); EndBeat := FDocument.SecondsToBeat(FPreview.EndSeconds); Playing := FPreview.IsPlaying; FPreview.CancelTempoEdit;
  TimelineBox.CancelInteraction;
  FPreview.PlacementEditor.Cancel;
  if FEditHistory.Undo(JSONMemo.Text,Text) then begin RestoreEditText(Text); FPreview.RestoreMusicalCursor(Beat,EndBeat,Playing);
    FPreview.CancelTempoEdit; StatusLabel.Caption := '元に戻しました（Ctrl+Yでやり直し）'; end;
end;
procedure TFormMusicStudioSettings.RedoEdit;
var Text: string; Beat,EndBeat: Double; Playing: Boolean;
begin
  Beat := FDocument.SecondsToBeat(FPreview.Position); EndBeat := FDocument.SecondsToBeat(FPreview.EndSeconds); Playing := FPreview.IsPlaying; FPreview.CancelTempoEdit;
  TimelineBox.CancelInteraction;
  FPreview.PlacementEditor.Cancel;
  if FEditHistory.Redo(JSONMemo.Text,Text) then begin RestoreEditText(Text); FPreview.RestoreMusicalCursor(Beat,EndBeat,Playing);
    FPreview.CancelTempoEdit; StatusLabel.Caption := 'やり直しました'; end;
end;
procedure TFormMusicStudioSettings.PlacementCommit(TrackIndex: Integer; const Transform: TMusicStudioPsdTransform);
begin FDocument.UpdatePsdTransform(TrackIndex,Transform); CommitMutation; end;
procedure TFormMusicStudioSettings.RestoreEditText(const Text: string);
var TrackID,SlotID,ClipID: string; T: TMusicStudioTrack; I,S,C: Integer;
begin
  TrackID := ''; SlotID := ''; ClipID := '';
  if FValid and (TimelineBox.SelectedTrack>=0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack); TrackID := T.ID;
    if TimelineBox.SelectedSlot>=0 then begin
      SlotID := T.Slots[TimelineBox.SelectedSlot].ID;
      if TimelineBox.SelectedClip>=0 then ClipID := T.Slots[TimelineBox.SelectedSlot].Clips[TimelineBox.SelectedClip].ID;
    end;
  end;
  JSONMemo.Text := Text;
  if not FValid then Exit;
  for I := 0 to FDocument.TrackCount-1 do begin
    T := FDocument.TrackAt(I); if T.ID<>TrackID then Continue;
    TimelineBox.SelectTrack(I);
    for S := 0 to High(T.Slots) do if T.Slots[S].ID=SlotID then begin
      TimelineBox.SelectSlot(I,S);
      for C := 0 to High(T.Slots[S].Clips) do if T.Slots[S].Clips[C].ID=ClipID then TimelineBox.SelectClip(I,S,C);
      Break;
    end;
    Break;
  end;
end;

procedure TFormMusicStudioSettings.TrackAddClick(Sender: TObject);
var P: TPoint;
begin P := TrackAddButton.ClientToScreen(Point(0,TrackAddButton.Height)); TrackAddMenu.Popup(P.X,P.Y); end;
procedure TFormMusicStudioSettings.AddAudioTrackClick(Sender: TObject);
begin AddTrack('audio'); end;
procedure TFormMusicStudioSettings.AddInstrumentTrackClick(Sender: TObject);
begin AddTrack('instrument'); end;
procedure TFormMusicStudioSettings.AddPsdTrackClick(Sender: TObject);
begin AddTrack('psd'); end;
procedure TFormMusicStudioSettings.AddTrack(const Kind: string);
var Index: Integer;
begin
  if not FValid then Exit;
  Index := FDocument.AddTrack(Kind); if CommitMutation then TimelineBox.SelectTrack(Index);
end;

function TFormMusicStudioSettings.DropPatternAt(PatternIndex, TrackIndex: Integer;
  StartSeconds: Double; out Reason: string): Boolean;
begin Result := DropPatternAt(PatternIndex,TrackIndex,0,StartSeconds,Reason); end;
function TFormMusicStudioSettings.DropPatternAt(PatternIndex,TrackIndex,SlotIndex: Integer;
  StartSeconds: Double; out Reason: string): Boolean;
var P: TMusicStudioPattern; Duration: Double;
begin
  Result := False;
  if not FValid or (PatternIndex < 0) or (PatternIndex >= FDocument.PatternCount) then begin
    Reason := '左のパターンを選択してください。'; Exit;
  end;
  P := FDocument.PatternAt(PatternIndex);
  if (P.Kind='performance') and (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>'') then begin
    if (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) or
      (MusicStudioPerformanceLayerAsset(P.ConfigJSON)<>FDocument.TrackAt(TrackIndex).PsdAssetID) then begin
      Reason := '演奏stepと配置先PSDの素材IDが一致しません。'; Exit;
    end;
  end;
  Duration := P.Duration; if Duration <= 0 then Duration := 4;
  if not FDocument.AddPlacement(TrackIndex,SlotIndex,P.ID,StartSeconds,Duration,Reason) then begin
    StatusLabel.Caption := Reason; Exit;
  end;
  Result := CommitMutation;
  if Result then begin
    Reason := ''; StatusLabel.Caption := '配置しました。元パターンと配置は別IDで保存します。';
  end else Reason := StatusLabel.Caption;
end;

procedure TFormMusicStudioSettings.TimelineDragOver(Sender, Source: TObject; X,Y: Integer;
  State: TDragState; var Accept: Boolean);
var TrackIndex,SlotIndex: Integer; Reason: string; P: TMusicStudioPattern;
begin
  Accept := False;
  if not FValid or (Source <> PatternList) or (PatternList.ItemIndex < 0) then Exit;
  TrackIndex := TimelineBox.TrackAtPoint(X,Y);
  SlotIndex := TimelineBox.SlotAtPoint(X,Y);
  if (TrackIndex < 0) or (SlotIndex < 0) or (X < TimelineBox.HeaderWidth) then Reason := '展開したスロットの時間領域へドロップしてください。'
  else Accept := MusicStudioSlotCompatible(VisiblePattern(PatternList.ItemIndex).Kind,
    FDocument.TrackAt(TrackIndex).Slots[SlotIndex],Reason);
  if Accept then begin
    P := VisiblePattern(PatternList.ItemIndex);
    if FLibraryItems[PatternList.ItemIndex].Missing then begin Accept := False; Reason := '共有PSDが欠損しています。設定から復旧してください。'; end
    else if (P.AssetID<>'') and (P.Kind<>'psd') and (P.AssetID<>FDocument.TrackAt(TrackIndex).PsdAssetID) then begin
      Accept := False; Reason := '配置先PSDと共有パターンのPSDが一致しません。';
    end;
  end;
  if Accept then StatusLabel.Caption := Format('%.2f秒へ配置できます。',[TimelineBox.SecondsAtSlot(X,TrackIndex,SlotIndex)])
  else StatusLabel.Caption := Reason;
end;

procedure TFormMusicStudioSettings.TimelineDragDrop(Sender, Source: TObject; X,Y: Integer);
var Reason: string;
begin
  if Source = PatternList then DropLibraryItemAt(PatternList.ItemIndex,TimelineBox.TrackAtPoint(X,Y),
    TimelineBox.SlotAtPoint(X,Y),TimelineBox.SecondsAtSlot(X,TimelineBox.TrackAtPoint(X,Y),TimelineBox.SlotAtPoint(X,Y)),Reason);
end;

procedure TFormMusicStudioSettings.ArrangementMenuPopup(Sender: TObject);
var Selected: Boolean; T: TMusicStudioTrack;
begin
  Selected := FValid and (TimelineBox.SelectedTrack >= 0);
  if Selected then begin T := FDocument.TrackAt(TimelineBox.SelectedTrack);
    Selected := (T.Kind = 'audio') or (T.Kind = 'psd'); end;
  FTrackSettingsItem.Enabled := Selected; FTrackDeleteItem.Enabled := Selected;
  FClipEditItem.Enabled := Selected and (TimelineBox.SelectedClip >= 0);
  FClipDeleteItem.Enabled := FClipEditItem.Enabled;
  FSlotAddItem.Enabled := Selected;
  FSlotSettingsItem.Enabled := Selected and (TimelineBox.SelectedSlot >= 0);
  FSlotDeleteItem.Enabled := FSlotSettingsItem.Enabled;
  FSlotUpItem.Enabled := FSlotSettingsItem.Enabled and (TimelineBox.SelectedSlot > 0);
  FSlotDownItem.Enabled := False;
  if FSlotSettingsItem.Enabled then FSlotDownItem.Enabled := TimelineBox.SelectedSlot < High(T.Slots);
  ArrangementMenu.Items[0].Enabled := FValid; ArrangementMenu.Items[1].Enabled := FValid;
end;

procedure TFormMusicStudioSettings.TrackSettingsClick(Sender: TObject);
var T: TMusicStudioTrack; D: TMusicStudioPatternSettings; Index: Integer;
begin
  Index := TimelineBox.SelectedTrack; if not FValid or (Index < 0) then Exit;
  T := FDocument.TrackAt(Index); if (T.Kind <> 'audio') and (T.Kind <> 'psd') then Exit;
  D := TMusicStudioPatternSettings.Create(Self);
  try
    D.LoadTrack(T); if D.ShowModal <> mrOK then Exit; D.ReadTrack(T);
    FDocument.UpdateTrack(Index,T.Name,T.Color,T.PsdPath); CommitMutation;
  finally D.Free; end;
end;

procedure TFormMusicStudioSettings.SlotMenuClick(Sender: TObject);
var P: TPoint; T: TMusicStudioTrack;
begin
  if not FValid or (TimelineBox.SelectedTrack < 0) then begin StatusLabel.Caption := '先にトラックを選択してください。'; Exit; end;
  T := FDocument.TrackAt(TimelineBox.SelectedTrack);
  if (T.Kind <> 'audio') and (T.Kind <> 'psd') then Exit;
  P := SlotAddButton.ClientToScreen(Point(0,SlotAddButton.Height)); SlotAddMenu.Popup(P.X,P.Y);
end;
procedure TFormMusicStudioSettings.AddSlotClick(Sender: TObject);
var Index,TrackIndex: Integer; T: TMusicStudioTrack;
begin
  TrackIndex := TimelineBox.SelectedTrack;
  if not FValid or (TrackIndex < 0) then Exit;
  T := FDocument.TrackAt(TrackIndex); if (T.Kind <> 'audio') and (T.Kind <> 'psd') then Exit;
  Index := FDocument.AddSlot(TrackIndex,SLOT_KINDS[TMenuItem(Sender).Tag]);
  if CommitMutation then TimelineBox.SelectSlot(TrackIndex,Index);
end;
procedure TFormMusicStudioSettings.SlotSettingsClick(Sender: TObject);
var TIndex,SIndex: Integer; S: TMusicStudioSlot; D: TMusicStudioPatternSettings; ErrorText: string;
begin
  TIndex := TimelineBox.SelectedTrack; SIndex := TimelineBox.SelectedSlot;
  if not FValid or (TIndex < 0) or (SIndex < 0) then Exit;
  S := FDocument.TrackAt(TIndex).Slots[SIndex]; D := TMusicStudioPatternSettings.Create(Self);
  try
    D.LoadSlot(S);
    while D.ShowModal = mrOK do begin
      D.ReadSlot(S);
      if FDocument.UpdateSlot(TIndex,SIndex,S.Name,S.Color,S.Accepts,ErrorText) then begin CommitMutation; Break; end;
      MessageDlg(ErrorText,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;
procedure TFormMusicStudioSettings.SlotDeleteClick(Sender: TObject);
var TIndex,SIndex: Integer;
begin
  TIndex := TimelineBox.SelectedTrack; SIndex := TimelineBox.SelectedSlot;
  if not FValid or (TIndex < 0) or (SIndex < 0) then Exit;
  if MessageDlg('このスロットと中の配置を削除しますか？ 他のスロット・元パターン・参照ファイルは保持します。',
    mtConfirmation,[mbYes,mbNo],0) <> mrYes then Exit;
  FDocument.RemoveSlot(TIndex,SIndex); if CommitMutation then TimelineBox.SelectTrack(TIndex);
end;
procedure TFormMusicStudioSettings.SlotUpClick(Sender: TObject);
begin ReorderSlot(-1); end;
procedure TFormMusicStudioSettings.SlotDownClick(Sender: TObject);
begin ReorderSlot(1); end;
procedure TFormMusicStudioSettings.ReorderSlot(Delta: Integer);
var TIndex,SIndex,Target: Integer;
begin
  TIndex := TimelineBox.SelectedTrack; SIndex := TimelineBox.SelectedSlot;
  if not FValid or (TIndex < 0) or (SIndex < 0) then Exit;
  Target := SIndex+Delta;
  if (Target < 0) or (Target >= Length(FDocument.TrackAt(TIndex).Slots)) then Exit;
  FDocument.ReorderSlot(TIndex,SIndex,Target); if CommitMutation then TimelineBox.SelectSlot(TIndex,Target);
end;

procedure TFormMusicStudioSettings.TrackDeleteClick(Sender: TObject);
var Index: Integer;
begin
  Index := TimelineBox.SelectedTrack; if not FValid or (Index < 0) then Exit;
  if MessageDlg('このトラックと、その中の配置を削除しますか？ 左の元パターンと素材ファイルは保持します。',
    mtConfirmation,[mbYes,mbNo],0) <> mrYes then Exit;
  FDocument.RemoveTrack(Index); CommitMutation;
end;

procedure TFormMusicStudioSettings.ClipDeleteClick(Sender: TObject);
begin
  if not FValid or (TimelineBox.SelectedTrack < 0) or (TimelineBox.SelectedClip < 0) then Exit;
  FDocument.RemovePlacement(TimelineBox.SelectedTrack,TimelineBox.SelectedSlot,TimelineBox.SelectedClip); CommitMutation;
end;

procedure TFormMusicStudioSettings.TimelineClipMove(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds: Double);
var C: TMusicStudioPlacement;
begin
  if not FValid then Exit; C := FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Clips[ClipIndex];
  if C.StartSeconds = StartSeconds then Exit;
  try FDocument.MovePlacement(TrackIndex,SlotIndex,ClipIndex,StartSeconds,C.LengthSeconds); CommitMutation;
  except on E: Exception do begin StatusLabel.Caption := E.Message; TimelineBox.Refresh; end; end;
end;
procedure TFormMusicStudioSettings.TimelineClipResize(TrackIndex,SlotIndex,ClipIndex: Integer; StartSeconds,LengthSeconds: Double);
var C: TMusicStudioPlacement; Beat: Double; Error: string;
begin
  if not FValid then Exit; C := FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Clips[ClipIndex];
  if (Abs(C.StartSeconds-StartSeconds)<1E-9) and (Abs(C.LengthSeconds-LengthSeconds)<1E-9) then Exit;
  if C.TimeBase='beats' then begin
    Beat := FDocument.SecondsToBeat(StartSeconds);
    if not FDocument.MoveBeatPlacement(TrackIndex,SlotIndex,ClipIndex,Beat,
      FDocument.SecondsToBeat(StartSeconds+LengthSeconds)-Beat,Error) then begin StatusLabel.Caption := Error; Exit; end;
  end else try FDocument.MovePlacement(TrackIndex,SlotIndex,ClipIndex,StartSeconds,LengthSeconds);
    except on E: Exception do begin StatusLabel.Caption := E.Message; TimelineBox.Refresh; Exit; end; end;
  CommitMutation;
end;

procedure TFormMusicStudioSettings.TimelineDblClick(Sender: TObject);
begin
  if TimelineBox.SelectedClip >= 0 then ClipEditClick(nil)
  else if TimelineBox.SelectedSlot >= 0 then SlotSettingsClick(nil) else TrackSettingsClick(nil);
end;
procedure TFormMusicStudioSettings.TimelineSelectionChange(Sender: TObject);
var T: TMusicStudioTrack; PlacementTrack: Integer;
begin
  PlacementTrack := -1;
  if FValid and (TimelineBox.SelectedTrack>=0) and (TimelineBox.SelectedSlot>=0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack);
    if (T.Kind='psd') and (T.Slots[TimelineBox.SelectedSlot].Kind='psd') then PlacementTrack := TimelineBox.SelectedTrack;
  end;
  FPreview.PlacementEditor.SelectTrack(PlacementTrack);
  UpdateLibrary;
  SlotAddButton.Enabled := False;
  if not FValid then begin InfoLabel.Caption := 'JSONを修復するか、キャンセルしてください。'; Exit; end;
  if TimelineBox.SelectedTrack < 0 then begin
    InfoLabel.Caption := 'トラック＋ → スロットを選択 → 左の＋で追加・設定 → 配置 → JSON保存 / 適用'; Exit;
  end;
  T := FDocument.TrackAt(TimelineBox.SelectedTrack);
  SlotAddButton.Enabled := (T.Kind = 'audio') or (T.Kind = 'psd');
  InfoLabel.Caption := '選択トラック: '+T.Name;
  if TimelineBox.SelectedSlot >= 0 then InfoLabel.Caption := InfoLabel.Caption+
    '  /  スロット: '+T.Slots[TimelineBox.SelectedSlot].Name;
  InfoLabel.Caption := InfoLabel.Caption+'  ・  右クリックで設定 / 並べ替え / 削除';
end;

procedure TFormMusicStudioSettings.ClipEditClick(Sender: TObject);
var D: TForm; Footer: TPanel; StartEdit, LengthEdit: TEdit; C: TMusicStudioPlacement;
  StartValue, LengthValue, MaximumEnd: Double; TIndex, SIndex, CIndex: Integer; FS: TFormatSettings; ErrorText: string;
begin
  TIndex := TimelineBox.SelectedTrack; SIndex := TimelineBox.SelectedSlot; CIndex := TimelineBox.SelectedClip;
  if not FValid or (TIndex < 0) or (SIndex < 0) or (CIndex < 0) then Exit;
  C := FDocument.TrackAt(TIndex).Slots[SIndex].Clips[CIndex]; FS := TFormatSettings.Invariant;
  if C.TimeBase='beats' then MaximumEnd := 1000000 else MaximumEnd := 604800;
  D := TForm.CreateNew(Self);
  try
    D.Caption := '配置の開始・長さ'; D.Position := poOwnerFormCenter;
    D.ClientWidth := 420; D.ClientHeight := 210; D.BorderStyle := bsDialog;
    ApplySyncMusicStudioDarkForm(D);
    if C.TimeBase='beats' then begin LabelAt(D,D,20,20,'開始 (拍)'); LabelAt(D,D,20,82,'長さ (拍)'); end
    else begin LabelAt(D,D,20,20,'開始 (秒)'); LabelAt(D,D,20,82,'長さ (秒)'); end;
    StartEdit := TEdit.Create(D); StartEdit.Parent := D; StartEdit.SetBounds(180,18,210,26);
    StartEdit.Text := FloatToStr(C.StartSeconds,FS); ApplySyncMusicStudioDarkEdit(StartEdit);
    LengthEdit := TEdit.Create(D); LengthEdit.Parent := D; LengthEdit.SetBounds(180,80,210,26);
    LengthEdit.Text := FloatToStr(C.LengthSeconds,FS); ApplySyncMusicStudioDarkEdit(LengthEdit);
    if C.TimeBase='beats' then begin StartEdit.Text := FloatToStr(C.StartBeat,FS); LengthEdit.Text := FloatToStr(C.LengthBeats,FS); end;
    Footer := Panel(D,D,alBottom,56);
    Button(D,Footer,164,12,100,'OK',nil).ModalResult := mrOK;
    Button(D,Footer,276,12,114,'キャンセル',nil).ModalResult := mrCancel;
    while D.ShowModal = mrOK do begin
      if TryStrToFloat(StartEdit.Text,StartValue,FS) and TryStrToFloat(LengthEdit.Text,LengthValue,FS) and
        (StartValue >= 0) and (LengthValue >= 0.001) and (StartValue + LengthValue <= MaximumEnd) then begin
        if C.TimeBase='beats' then begin
          if not FDocument.MoveBeatPlacement(TIndex,SIndex,CIndex,StartValue,LengthValue,ErrorText) then begin MessageDlg(ErrorText,mtWarning,[mbOK],0); Continue; end;
        end else FDocument.MovePlacement(TIndex,SIndex,CIndex,StartValue,LengthValue);
        CommitMutation; Break;
      end;
      if C.TimeBase='beats' then ErrorText := '開始は0以上、長さは0.001拍以上、終了は1000000拍以内で入力してください。'
      else ErrorText := '開始は0以上、長さは0.001秒以上、終了は604800秒以内で入力してください。';
      MessageDlg(ErrorText,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;

procedure TFormMusicStudioSettings.TempoSettingsClick(Sender: TObject);
var D: TForm; Frame: TMusicStudioTimingFrame; Footer: TPanel; Error: string;
begin
  if not FValid then Exit;
  D := TForm.CreateNew(Self);
  try
    D.Caption := 'テンポ / 拍子'; D.Position := poOwnerFormCenter; D.ClientWidth := 760; D.ClientHeight := 440;
    D.Constraints.MinWidth := 670; D.Constraints.MinHeight := 430;
    ApplySyncMusicStudioDarkForm(D); ApplyMusicStudioEditorFont(D);
    Footer := Panel(D,D,alBottom,60); Button(D,Footer,404,15,100,'OK',nil).ModalResult := mrOK;
    Button(D,Footer,516,15,114,'キャンセル',nil).ModalResult := mrCancel;
    Frame := TMusicStudioTimingFrame.Create(D); Frame.Parent := D; Frame.Align := alClient;
    Frame.LoadTiming(FDocument.ManualTimingJSON);
    while D.ShowModal=mrOK do begin
      if not Frame.CanApply then begin MessageDlg(Frame.StateText,mtWarning,[mbOK],0); Continue; end;
      if FDocument.SetTiming(Frame.ConfigJSON,Error) then begin CommitMutation; Break; end;
      MessageDlg(Error,mtWarning,[mbOK],0);
    end;
  finally D.Free; end;
end;
procedure TFormMusicStudioSettings.PreviewPositionChange(Sender: TObject);
begin if Assigned(TimelineBox) then TimelineBox.SetPlayhead(FPreview.Position); end;
function TFormMusicStudioSettings.PreviewTempoEdit(Beat,BPM: Double; out ErrorText: string): Boolean;
var CursorBeat,EndBeat: Double; Playing: Boolean; Scope,BeforeText,LoadError: string;
begin
  Result := False; ErrorText := ''; if not FValid then begin ErrorText := 'JSONを修復してください。'; Exit; end;
  CursorBeat := FDocument.SecondsToBeat(FPreview.Position); EndBeat := FDocument.SecondsToBeat(FPreview.EndSeconds); Playing := FPreview.IsPlaying;
  BeforeText := JSONMemo.Text;
  if not FDocument.SetTempoAtBeat(Beat,BPM,Scope,ErrorText) then Exit;
  try
    FPreview.ValidateMusicalCursor(CursorBeat,EndBeat);
    SyncMemo; FPreview.RestoreMusicalCursor(CursorBeat,EndBeat,Playing);
    FEditHistory.RecordChange(BeforeText,JSONMemo.Text);
    StatusLabel.Caption := Scope+Format('を%g BPMへ変更しました。',[BPM]); Result := True;
  except on E: Exception do begin
    ErrorText := E.Message; FDocument.TryLoad(BeforeText,LoadError);
    FSyncing := True; try JSONMemo.Text := BeforeText; finally FSyncing := False; end;
    FPreview.Bind(FDocument); FPreview.RestoreMusicalCursor(CursorBeat,EndBeat,Playing); RefreshPatterns;
    StatusLabel.Caption := '変更を反映できません: '+ErrorText;
  end; end;
end;
procedure TFormMusicStudioSettings.TimelineSeek(Seconds: Double);
begin FPreview.Seek(Seconds); end;
procedure TFormMusicStudioSettings.TempoRulerMenu(Beat: Double);
begin if FValid then FTempoRuler.ShowMenu(Beat); end;

end.
