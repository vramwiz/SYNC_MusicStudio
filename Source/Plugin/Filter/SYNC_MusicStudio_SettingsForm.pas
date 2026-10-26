unit SYNC_MusicStudio_SettingsForm;

// 1ページ統合編集画面。文書の作業コピーと一覧操作を担当し、音声デコードは専用UIに任せる。
interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.StdCtrls, Vcl.Menus, SYNC_MusicStudio_PatternData,
  SYNC_MusicStudio_ArrangementView, SYNC_MusicStudio_PreviewFrame, SYNC_MusicStudio_SharedPsdLibrary, SYNC_MusicStudio_LibraryData,
  SYNC_MusicStudio_PsdLayerFrameUI, SYNC_MusicStudio_LibraryThumbnails, SYNC_MusicStudio_EditHistory, SYNC_MusicStudio_PerformanceLibrary, SYNC_MusicStudio_PsdTransform,
  SYNC_MusicStudio_TempoRulerEditor, SYNC_MusicStudio_DrumFrame, SYNC_MusicStudio_SmallSlotEditor;

type
  TMusicStudioConfirmDeleteEvent = function(const Text: string): Boolean of object;
  TMusicStudioApplyJSONEvent = function(const JSONText: string; out ErrorText: string): Boolean of object;
  TFormMusicStudioSettings = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FCancelRequested, FSyncing, FValid: Boolean;
    FInitialText: string;
    FLibraryKind: string;
    FLibraryContext: string;
    FPerformanceAttribute,FTrackClipboard: string;
    FSmallEditor: TMusicStudioSmallSlotEditor;
    FAvailableKinds: TArray<string>;
    FVisiblePatterns: TArray<Integer>;
    FLibraryItems: TArray<TMusicStudioLibraryItem>;
    FSharedLibrary: TMusicStudioSharedPsdLibrary;
    FSilentVisualMode: Boolean;
    FDocument: TMusicStudioDocument;
    FPreview: TMusicStudioPreviewFrame;
    FLibraryThumbnails: TMusicStudioLibraryThumbnails;
    FEditHistory: TMusicStudioEditHistory;
    FPerformanceHistory: TMusicStudioPerformanceHistory;
    FPendingPerformanceChange: Integer;
    FTempoButton: TButton;
    FTempoRuler: TMusicStudioTempoRulerEditor;
    FOverview: TPanel;
    FPatternMenu: TPopupMenu;
    FLibraryTabs: array[0..2] of TButton;
    FPatternAdd,FPatternEdit,FPatternDelete: TMenuItem;
    FOnConfirmDelete: TMusicStudioConfirmDeleteEvent;
    FOnApplyJSON: TMusicStudioApplyJSONEvent;
    FTrackSettingsItem, FTrackDeleteItem, FClipEditItem, FClipDeleteItem: TMenuItem;
    FSlotAddItem, FSlotSettingsItem, FSlotDeleteItem, FSlotUpItem, FSlotDownItem: TMenuItem;
    FTransportSpaceDown: Boolean;
    procedure LibraryTabClick(Sender: TObject);
    procedure HistoryButtonClick(Sender: TObject);
    function ApplyPerformanceHistory(Index: Integer; Undo: Boolean): Boolean;
    procedure PatternContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure PatternMenuPopup(Sender: TObject);
    procedure PreviewWheel(Sender: TObject; Shift: TShiftState; Delta: Integer; MousePos: TPoint; var Handled: Boolean);
    function VisiblePattern(Index: Integer): TMusicStudioPattern;
    procedure TempoRulerMenu(Beat: Double);
    procedure SetLibraryRoot(const Value: string);
    function GetLibraryRoot: string;
    procedure AddSharedPattern(const Kind: string);
    procedure AddAvailablePattern(const Kind: string);
    procedure AddMenuClick(Sender: TObject);
    procedure TempoSettingsClick(Sender: TObject);
    procedure CopyTrackClick(Sender: TObject);
    procedure PasteTrackClick(Sender: TObject);
    procedure EditCommonPerformance(NewPattern: Boolean);
    function AssignPerformerPSD(TrackIndex: Integer; const AssetID: string; out ErrorText: string): Boolean;
    // 共有一覧の受入条件をhover/確定で共用。PSDは枠のない演奏者見出しにも割り当てる。
    function CanDropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; out Reason: string): Boolean;
    function DropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
    procedure UpdateLibrary;
    procedure LibraryMetadataChanged(Sender: TObject);
    procedure LibraryFilesDropped(const Paths: TArray<string>);
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
    procedure DrumPreview(Sender: TObject; Beat: Double; State: TDrumTransport; Emotion,Motion: Integer);
    procedure InstrumentPreview(Sender: TObject);
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
    function DropSlotAt(X,Y: Integer): Integer;
    procedure TimelineDragOver(Sender, Source: TObject; X,Y: Integer; State: TDragState; var Accept: Boolean);
    procedure TimelineDragDrop(Sender, Source: TObject; X,Y: Integer);
    procedure TimelineDblClick(Sender: TObject);
    function ConfirmDelete(const Text: string): Boolean;
    procedure TimelineTrackMove(FromIndex,ToIndex: Integer);
    procedure TimelineDelete(Sender: TObject);
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
    // Explorerのdropと削除ボタンの処理境界。PSD一覧以外/不正選択では書き込まない。
    function ImportDroppedPsd(const Path: string; out ErrorText: string): Boolean;
    // 音声一覧への外部drop。原本をコピー/解析せず、作品内に参照を登録する。
    function ImportDroppedAudio(const Path: string; out ErrorText: string): Boolean;
    function RemoveSelectedLibraryPsd(out ErrorText: string): Boolean;
    property SelectedLibraryPattern: Integer read SelectedPatternIndex;
    property Document: TMusicStudioDocument read FDocument;
    property Preview: TMusicStudioPreviewFrame read FPreview;
    property PatternMenu: TPopupMenu read FPatternMenu;
    property LibraryThumbnails: TMusicStudioLibraryThumbnails read FLibraryThumbnails;
    property TempoRuler: TMusicStudioTempoRulerEditor read FTempoRuler;
    property SmallSlotEditor: TMusicStudioSmallSlotEditor read FSmallEditor;
    property OnConfirmDelete: TMusicStudioConfirmDeleteEvent read FOnConfirmDelete write FOnConfirmDelete;
    property OnApplyJSON: TMusicStudioApplyJSONEvent read FOnApplyJSON write FOnApplyJSON;
  end;

implementation

uses
  System.IOUtils, System.SysUtils, System.UITypes, System.Math, Vcl.Graphics, Winapi.Windows,
  SYNC_MusicStudio_Controls, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_ProjectData,
  SYNC_MusicStudio_PatternSettingsForm, SYNC_MusicStudio_SharedLibraryEditor,
  SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_TimingFrame, SYNC_MusicStudio_LayerStepData, SYNC_MusicStudio_DrumData,
  SYNC_MusicStudio_InstrumentFrame, SYNC_MusicStudio_InstrumentData,
  SYNC_MusicStudio_PerformanceKinds,
  SYNC_MusicStudio_PerformerPsd, SYNC_MusicStudio_PerformerEditor, SYNC_MusicStudio_PerformanceEditor,
  SYNC_MusicStudio_SmallSlotData, SYNC_MusicStudio_FileDropList, SYNC_MusicStudio_PsdImport;

{$R *.dfm}

const SLOT_KINDS: array[0..13] of string = ('audio','psd','singing','emotion','animation','instrument','performance','rhythm','generic','tempo','face','pose','symbol','customExpression');

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
  ToolbarPanel.Visible := False;
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
  InfoPanel.Top := 0;
  InfoLabel := LabelAt(Self, InfoPanel, 16, 10,
    '右のスロットを選択 → 左の一覧を右クリックで追加・設定 → ドラッグで配置');
  InfoLabel.AutoSize := False;
  InfoLabel.Width := InfoPanel.Width - 32;
  InfoLabel.Anchors := [akLeft, akTop, akRight];
  WorkPanel := Panel(Self, Self, alClient, 0);
  PatternPanel := Panel(Self, WorkPanel, alLeft, 268);
  PatternPanel.Constraints.MinWidth := 230;
  PatternPanel.Constraints.MaxWidth := 360;
  Header := Panel(Self, PatternPanel, alTop, 82);
  FLibraryTabs[0] := Button(Self,Header,8,46,74,'PSD',LibraryTabClick); FLibraryTabs[0].Tag := 0;
  FLibraryTabs[1] := Button(Self,Header,88,46,74,'演奏',LibraryTabClick); FLibraryTabs[1].Tag := 1;
  FLibraryTabs[2] := Button(Self,Header,168,46,74,'歌唱',LibraryTabClick); FLibraryTabs[2].Tag := 2;
  LibraryLabel := LabelAt(Self, Header, 16, 17, 'スロットを選択');
  AddButton := Button(Self, Header, Header.Width - 50, 10, 34, '＋', AddButtonClick);
  AddButton.Anchors := [akTop, akRight];
  Footer := Panel(Self, PatternPanel, alBottom, 92);
  Footer.Visible := False;
  EditButton := Button(Self, Footer, 16, 12, 142, '選択パターンを設定', EditButtonClick);
  DeleteButton := Button(Self, Footer, 166, 12, 86, '削除', DeleteButtonClick);
  PatternList := TMusicStudioFileDropList.Create(Self);
  TMusicStudioFileDropList(PatternList).OnFilesDropped := LibraryFilesDropped;
  PatternList.Parent := PatternPanel;
  PatternList.Align := alClient;
  PatternList.Style := lbOwnerDrawFixed;
  PatternList.ItemHeight := MulDiv(58, CurrentPPI, 96);
  PatternList.BorderStyle := bsNone;
  PatternList.OnClick := PatternListClick;
  PatternList.OnDblClick := EditButtonClick;
  PatternList.OnDrawItem := PatternListDrawItem;
  PatternList.OnKeyDown := PatternListKeyDown;
  PatternList.OnContextPopup := PatternContext;
  PatternList.DragMode := dmAutomatic;
  ApplySyncMusicStudioDarkListBox(PatternList);
  Splitter := TSplitter.Create(Self);
  Splitter.Parent := WorkPanel;
  Splitter.Left := PatternPanel.Width;
  Splitter.Width := 6;
  Splitter.MinSize := 230;
  CenterPanel := Panel(Self, WorkPanel, alClient, 0);
  Overview := Panel(Self, WorkPanel, alTop, 240); Overview.Top := 0;
  Splitter := TSplitter.Create(Self); Splitter.Parent := WorkPanel; Splitter.Align := alTop; Splitter.Top := 240; Splitter.Height := 5; Splitter.MinSize := 120;
  FOverview := Overview;
  FPreview := TMusicStudioPreviewFrame.Create(Self); FPreview.Parent := Overview;
  FPreview.Align := alClient; PreviewBox := FPreview.Stage;
  FPreview.DockTransport(Self);
  TrackHeader := Panel(Self, CenterPanel, alTop, 44);
  TrackHeader.Top := 0;
  TrackAddButton := Button(Self, TrackHeader, 12, 7, 120, 'トラック＋', TrackAddClick);
  SlotAddButton := Button(Self,TrackHeader,140,7,112,'スロット＋',SlotMenuClick);
  FTempoButton.Parent := TrackHeader; FTempoButton.SetBounds(264,7,130,30);
  Button(Self,TrackHeader,402,7,88,'元に戻す',HistoryButtonClick).Tag := 0;
  Button(Self,TrackHeader,496,7,88,'やり直す',HistoryButtonClick).Tag := 1;
  LabelControl := LabelAt(Self,TrackHeader,592,14,'時間目盛りをドラッグで横移動 / ホイールで拡縮');
  LabelControl.AutoSize := False; LabelControl.Width := Max(1,TrackHeader.Width - 608);
  LabelControl.Anchors := [akLeft,akTop,akRight];
  TimelineBox := TMusicStudioArrangementView.Create(Self);
  FPreview.SharedVisualCache := TimelineBox.VisualCache;
  TimelineBox.SceneCache := FPreview.SceneCache;
  TimelineBox.Parent := CenterPanel;
  TimelineBox.Align := alClient;
  TimelineBox.OnDragOver := TimelineDragOver; TimelineBox.OnDragDrop := TimelineDragDrop;
  TimelineBox.OnDblClick := TimelineDblClick; TimelineBox.OnClipMove := TimelineClipMove;
  TimelineBox.OnClipResize := TimelineClipResize;
  TimelineBox.OnTrackMove := TimelineTrackMove; TimelineBox.OnDelete := TimelineDelete;
  TimelineBox.OnVisibility := FPreview.VisibilityCommand; TimelineBox.OnTrackVisible := FPreview.TrackVisible;
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
  FPatternMenu := TPopupMenu.Create(Self); FPatternMenu.OnPopup := PatternMenuPopup; PatternList.PopupMenu := FPatternMenu;
  FPatternAdd := TMenuItem.Create(FPatternMenu); FPatternAdd.Caption := '追加…'; FPatternAdd.OnClick := AddButtonClick; FPatternMenu.Items.Add(FPatternAdd);
  FPatternEdit := TMenuItem.Create(FPatternMenu); FPatternEdit.Caption := '設定…'; FPatternEdit.OnClick := EditButtonClick; FPatternMenu.Items.Add(FPatternEdit);
  FPatternDelete := TMenuItem.Create(FPatternMenu); FPatternDelete.Caption := '削除…'; FPatternDelete.OnClick := DeleteButtonClick; FPatternMenu.Items.Add(FPatternDelete);
  TrackAddMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(TrackAddMenu); Item.Caption := '音楽トラック';
  Item.OnClick := AddAudioTrackClick; TrackAddMenu.Items.Add(Item);
  Item := TMenuItem.Create(TrackAddMenu); Item.Caption := '演奏者トラック';
  Item.OnClick := AddPsdTrackClick; TrackAddMenu.Items.Add(Item);
  ArrangementMenu := TPopupMenu.Create(Self); ArrangementMenu.OnPopup := ArrangementMenuPopup;
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := '音楽トラックを追加';
  Item.OnClick := AddAudioTrackClick; ArrangementMenu.Items.Add(Item);
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := '演奏者トラックを追加';
  Item.OnClick := AddPsdTrackClick; ArrangementMenu.Items.Add(Item);
  FTrackSettingsItem := TMenuItem.Create(ArrangementMenu); FTrackSettingsItem.Caption := 'トラック設定…';
  FTrackSettingsItem.OnClick := TrackSettingsClick; ArrangementMenu.Items.Add(FTrackSettingsItem);
  FTrackDeleteItem := TMenuItem.Create(ArrangementMenu); FTrackDeleteItem.Caption := 'トラックを削除…';
  FTrackDeleteItem.OnClick := TrackDeleteClick; ArrangementMenu.Items.Add(FTrackDeleteItem);
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := 'トラックをコピー'; Item.OnClick := CopyTrackClick; ArrangementMenu.Items.Add(Item);
  Item := TMenuItem.Create(ArrangementMenu); Item.Caption := 'トラックをペースト'; Item.OnClick := PasteTrackClick; ArrangementMenu.Items.Add(Item);
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
  FEditHistory := TMusicStudioEditHistory.Create; FEditHistory.OnApply := ApplyPerformanceHistory;
  FPendingPerformanceChange := -1;
  FSharedLibrary := TMusicStudioSharedPsdLibrary.Create; FDocument.AssetResolver := FSharedLibrary.ResolvePath;
  ApplySyncMusicStudioDarkForm(Self);
  ApplyMusicStudioEditorFont(Self);
  BuildUI;
  FSmallEditor := TMusicStudioSmallSlotEditor.Create(Self,TimelineBox,FDocument,CommitMutation);
  FSmallEditor.Store := FSharedLibrary; TimelineBox.OnSmallMenu := FSmallEditor.ShowMenu;
  FLibraryThumbnails := TMusicStudioLibraryThumbnails.Create(PatternList,TimelineBox.VisualCache);
  FLibraryThumbnails.OnMetadataChange := LibraryMetadataChanged;
  KeyPreview := True; OnKeyDown := TransportKeyDown; OnKeyUp := TransportKeyUp;
  OnDeactivate := TransportDeactivate;
  OnMouseWheel := PreviewWheel;
  FPreview.SharedLibrary := FSharedLibrary;
  FTempoRuler := TMusicStudioTempoRulerEditor.Create(Self,FDocument,CommitMutation);
  TimelineBox.OnTempoMenu := TempoRulerMenu;
  FPreview.PlacementEditor.OnCommit := PlacementCommit;
  OnResize := FitPreview; FitPreview(nil);
end;

procedure TFormMusicStudioSettings.FitPreview(Sender: TObject);
begin
  if not Assigned(FOverview) then Exit;
  FOverview.Height := Min(MulDiv(220,CurrentPPI,96),Max(MulDiv(144,CurrentPPI,96),WorkPanel.ClientHeight div 4));
end;
procedure TFormMusicStudioSettings.PatternContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  if MousePos.Y>=0 then PatternList.ItemIndex := PatternList.ItemAtPos(MousePos,True);
  PatternListClick(nil);
end;
procedure TFormMusicStudioSettings.PatternMenuPopup(Sender: TObject);
begin
  PatternListClick(nil); FPatternAdd.Enabled := AddButton.Enabled;
  FPatternEdit.Enabled := EditButton.Enabled; FPatternDelete.Enabled := DeleteButton.Enabled;
end;
procedure TFormMusicStudioSettings.PreviewWheel(Sender: TObject; Shift: TShiftState; Delta: Integer; MousePos: TPoint; var Handled: Boolean);
var Point: TPoint;
begin
  Handled := False; if FPreview=nil then Exit;
  Point := FPreview.Stage.ScreenToClient(MousePos);
  if PtInRect(FPreview.Stage.ClientRect,Point) then begin FPreview.ZoomAt(Delta,Point); Handled := True; end;
end;

destructor TFormMusicStudioSettings.Destroy;
begin
  FValid := False;
  TimelineBox.OnSmallMenu := nil; FreeAndNil(FSmallEditor);
  FreeAndNil(FTempoRuler); FreeAndNil(FLibraryThumbnails); FreeAndNil(FEditHistory); FreeAndNil(FPerformanceHistory);
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
    if ActiveControl=TimelineBox then begin
      if Key=VK_DELETE then begin TimelineDelete(TimelineBox); Key := 0; Exit; end;
      if (Key=Ord('C')) and (Shift=[ssCtrl]) then begin CopyTrackClick(nil); Key := 0; Exit; end;
      if (Key=Ord('V')) and (Shift=[ssCtrl]) then begin PasteTrackClick(nil); Key := 0; Exit; end;
    end;
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
  FreeAndNil(FPerformanceHistory); FEditHistory.Clear;
  FSharedLibrary := TMusicStudioSharedPsdLibrary.Create(Value); FDocument.AssetResolver := FSharedLibrary.ResolvePath;
  FSmallEditor.Store := FSharedLibrary; FPreview.SharedLibrary := FSharedLibrary;
  if FValid then begin TimelineBox.Bind(FDocument); FPreview.Bind(FDocument); end;
  UpdateLibrary;
end;
procedure TFormMusicStudioSettings.LibraryTabClick(Sender: TObject);
const Kinds: array[0..2] of string = ('psd','performance','singing');
var I: Integer; T: TMusicStudioTrack; K: string;
begin
  if not FValid or (TimelineBox.SelectedTrack<0) then Exit;
  T := FDocument.TrackAt(TimelineBox.SelectedTrack); if T.Kind='audio' then Exit;
  K := Kinds[TButton(Sender).Tag];
  for I := 0 to High(T.Slots) do if T.Slots[I].Kind=K then begin
    TimelineBox.SelectSlot(TimelineBox.SelectedTrack,I); Exit;
  end;
  FLibraryContext := K; UpdateLibrary;
end;
procedure TFormMusicStudioSettings.HistoryButtonClick(Sender: TObject);
begin if TButton(Sender).Tag=0 then UndoEdit else RedoEdit; end;
procedure TFormMusicStudioSettings.UpdateLibrary;
var I,N: Integer; SelectedID,Kind,AssetID,K: string; T: TMusicStudioTrack; S: TMusicStudioSlot; Item: TMenuItem;
  Assets: TArray<TMusicStudioPsdAsset>; Emotions: TArray<TMusicStudioLibraryItem>; P: TMusicStudioPattern;
begin
  T := Default(TMusicStudioTrack);
  SelectedID := VisiblePattern(PatternList.ItemIndex).ID; Kind := ''; AssetID := ''; FPerformanceAttribute := '';
  FAvailableKinds := nil; S := Default(TMusicStudioSlot);
  if FValid and (TimelineBox.SelectedTrack >= 0) and (TimelineBox.SelectedTrack<FDocument.TrackCount) and (TimelineBox.SelectedSlot >= 0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack); AssetID := T.PsdAssetID;
    FPerformanceAttribute := T.PerformanceAttribute;
    if TimelineBox.SelectedSlot<Length(T.Slots) then begin
      S := T.Slots[TimelineBox.SelectedSlot]; Kind := S.Kind;
      FAvailableKinds := MusicStudioLibraryKinds(S.Accepts,AssetID,T.Kind='psd');
      if MusicStudioSmallSlot(S.Kind) then FAvailableKinds := nil;
      if Length(FAvailableKinds)=1 then Kind := FAvailableKinds[0]
      else if Length(FAvailableKinds)>1 then Kind := 'generic';
    end;
  end;
  if FValid and (TimelineBox.SelectedTrack>=0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack); AssetID := T.PsdAssetID;
    FPerformanceAttribute := T.PerformanceAttribute;
    if (T.Kind='audio') and (TimelineBox.SelectionScope=mssTrack) then begin Kind := 'audio'; FAvailableKinds := ['audio']; end
    else if FLibraryContext<>'' then begin Kind := FLibraryContext; FAvailableKinds := [Kind]; end
    else if (Kind='') and (T.Kind='psd') then begin Kind := 'psd'; FAvailableKinds := ['psd']; end;
  end;
  FLibraryKind := Kind;
  for I := 0 to High(FLibraryTabs) do FLibraryTabs[I].Enabled := FValid and (TimelineBox.SelectedTrack>=0) and (T.Kind<>'audio');
  PatternList.ShowHint := (Kind='psd') or (Kind='audio');
  if Kind='audio' then PatternList.Hint := 'WAV / MP3をここへドロップして音声パターンを登録。ダブルクリックでファイルを設定できます。'
  else PatternList.Hint := 'PSDファイルをここへドラッグして共有一覧へ登録。登録後、演奏者へドラッグして割り当てます。';
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
  if Kind='audio' then LibraryLabel.Caption := '音声 / パターン';
  if Kind='performance' then LibraryLabel.Caption := PerformanceKindName(FPerformanceAttribute)+' / 共通演奏';
  if Kind='singing' then LibraryLabel.Caption := '歌唱 / プロジェクト共有';
  if (S.Kind='animation') and (S.Name='ポーズ') then LibraryLabel.Caption := 'ポーズ';
  if S.Kind='customExpression' then LibraryLabel.Caption := '表情カスタム';
  if FValid then FLibraryItems := MusicStudioLibraryItems(FDocument,FSharedLibrary,FAvailableKinds,AssetID,FPerformanceAttribute) else FLibraryItems := nil;
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
  if Kind='performance' then AddButton.Enabled := AddButton.Enabled and (FPerformanceAttribute<>'') and (AssetID<>'');
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
var I: Integer; T: TMusicStudioTrack; Profile: TMusicStudioPerformerProfile; Error: string; Changed: Boolean;
begin
  Changed := False;
  if FValid then begin
    // 共有PSD/母音/プリセットの明示保存後だけ能力を更新。欠損時は既存配置を保持する。
    for I := 0 to FDocument.TrackCount-1 do begin
      T := FDocument.TrackAt(I);
      if (T.Kind='psd') and (T.PsdAssetID<>'') and ReadMusicStudioPerformer(FSharedLibrary,T.PsdAssetID,Profile,Error) then begin
        if T.PerformanceAttribute<>'' then Profile.Attribute := T.PerformanceAttribute;
        FDocument.SetPerformer(I,Profile.Attribute,Profile.Slots,True,Profile.SelectionsJSON); Changed := True;
      end;
    end;
    if Changed then CommitMutation else begin FPreview.Bind(FDocument); TimelineBox.Refresh; end;
  end;
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
function TFormMusicStudioSettings.CanDropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; out Reason: string): Boolean;
var P: TMusicStudioPattern; T: TMusicStudioTrack;
begin
  Result := False; Reason := 'ドロップ先スロットを選択してください。';
  if not FValid or (ItemIndex<0) or (ItemIndex>=Length(FLibraryItems)) or
    (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) then Exit;
  P := VisiblePattern(ItemIndex); T := FDocument.TrackAt(TrackIndex);
  if P.Kind='psd' then begin
    if T.Kind<>'psd' then begin Reason := 'PSDは演奏者トラックへ割り当ててください。'; Exit; end;
    if SlotIndex=-1 then begin
      if FLibraryItems[ItemIndex].Missing then Reason := '共有PSDが欠損しています。設定から復旧してください。'
      else begin Result := True; Reason := ''; end;
      Exit;
    end;
  end;
  if (SlotIndex<0) or (SlotIndex>=Length(T.Slots)) then Exit;
  if not MusicStudioSlotCompatible(P.Kind,T.Slots[SlotIndex],Reason) then Exit;
  if FLibraryItems[ItemIndex].Missing then begin Reason := '共有PSDが欠損しています。設定から復旧してください。'; Exit; end;
  if (P.AssetID<>'') and (P.Kind<>'psd') and (P.AssetID<>T.PsdAssetID) then begin Reason := '配置先PSDと共有パターンのPSDが一致しません。'; Exit; end;
  if (P.Kind='performance') and (P.PerformanceAttribute<>'') and (P.PerformanceAttribute<>T.PerformanceAttribute) then begin
    Reason := '配置先の演奏属性が一致しません。'; Exit;
  end;
  Result := True; Reason := '';
end;
function TFormMusicStudioSettings.DropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex: Integer; StartSeconds: Double; out Reason: string): Boolean;
var P: TMusicStudioPattern; Index: Integer; RestoreError: string;
begin
  Result := False;
  if not CanDropLibraryItemAt(ItemIndex,TrackIndex,SlotIndex,Reason) then Exit;
  P := VisiblePattern(ItemIndex);
  if P.Kind='psd' then begin
    Result := AssignPerformerPSD(TrackIndex,P.AssetID,Reason); Exit;
  end;
  Index := FLibraryItems[ItemIndex].PatternIndex;
  if (P.Kind='performance') and (P.PerformanceAttribute<>'') then begin
    Index := FDocument.ImportPerformance(P);
  end;
  if P.AssetID<>'' then Index := FDocument.AddReference(P);
  Result := DropPatternAt(Index,TrackIndex,SlotIndex,StartSeconds,Reason);
  if not Result and ((P.AssetID<>'') or (P.PerformanceAttribute<>'')) then begin FDocument.TryLoad(JSONMemo.Text,RestoreError); UpdateLibrary; end;
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
  Beat,EndBeat: Double; Resume: Boolean;
begin
  if not FDocument.TrySave(Text, ErrorText) then raise Exception.Create(ErrorText);
  // 配置更新でPSDシーンを再Bindしても、再生位置/表示範囲/再生状態を維持する。
  Beat := FDocument.SecondsToBeat(FPreview.Position); EndBeat := FDocument.SecondsToBeat(FPreview.EndSeconds);
  Resume := FPreview.IsPlaying;
  FSyncing := True;
  try JSONMemo.Text := Text; finally FSyncing := False; end;
  FPreview.Bind(FDocument);
  FPreview.RestoreMusicalCursor(Beat,EndBeat,Resume);
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
  if (TimelineBox.SelectedTrack>=0) and (TimelineBox.SelectedSlot>=0) then
    if FDocument.TrackAt(TimelineBox.SelectedTrack).Slots[TimelineBox.SelectedSlot].Kind='customExpression' then begin
      FSmallEditor.EditCustomAt(TimelineBox.SelectedTrack,TimelineBox.SelectedSlot,-1,FPreview.Position); Exit;
    end;
  if Kind='performance' then EditCommonPerformance(True)
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
procedure TFormMusicStudioSettings.DrumPreview(Sender: TObject; Beat: Double;
  State: TDrumTransport; Emotion,Motion: Integer);
const States: array[TDrumTransport] of string = ('停止','再生','一時停止');
begin
  // ドラムのローカル拍を既存プレビューへ渡す。音声のPlayを呼ばない。
  FPreview.RestoreMusicalCursor(Beat,TMusicStudioDrumFrame(Sender).Data.LengthBeats,False);
  StatusLabel.Caption := Format('ドラム %s / %.2f拍 / 表情: %s / モーション: %s',
    [States[State],Beat,DrumKindName(0,Emotion),DrumKindName(1,Motion)]);
end;

procedure TFormMusicStudioSettings.InstrumentPreview(Sender: TObject);
begin
  FPreview.Pause;
  FPreview.RestoreMusicalCursor(TMusicStudioInstrumentFrame(Sender).Position,TMusicStudioInstrumentFrame(Sender).Data.LengthBeats,False);
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
  DeleteButton.Enabled := Selected and (((VisiblePattern(PatternList.ItemIndex).Kind='psd') and
    FLibraryItems[PatternList.ItemIndex].Shared) or ((SelectedPatternIndex>=0) and not FLibraryItems[PatternList.ItemIndex].Shared));
end;

procedure TFormMusicStudioSettings.EditButtonClick(Sender: TObject);
var
  Dialog: TMusicStudioPatternSettings;
  Pattern: TMusicStudioPattern;
  Asset: TMusicStudioPsdAsset; AssetID,Error: string;
  SharedError: string; SavedPosition: Double; DrumEditor: Boolean;
begin
  if not FValid or (PatternList.ItemIndex < 0) then Exit;
  if not EditButton.Enabled then Exit;
  Pattern := VisiblePattern(PatternList.ItemIndex);
  if (Pattern.Kind='performance') and FLibraryItems[PatternList.ItemIndex].Shared then begin EditCommonPerformance(False); Exit; end;
  if Pattern.AssetID<>'' then begin
    if not EditMusicStudioSharedItem(Self,FSharedLibrary,Pattern,SharedError) then begin
      if SharedError<>'' then MessageDlg(SharedError,mtError,[mbOK],0); Exit;
    end;
    if SelectedPatternIndex>=0 then begin Pattern.ID := FDocument.PatternAt(SelectedPatternIndex).ID; FDocument.UpdatePattern(Pattern); CommitMutation; end;
    SharedLibraryChanged; Exit;
  end;
  if (Pattern.Kind <> 'audio') and (Pattern.Kind <> 'singing') and (Pattern.Kind<>'performance') and (Pattern.Kind<>'tempo') then Exit;
  Dialog := TMusicStudioPatternSettings.Create(Self);
  SavedPosition := FPreview.Position; DrumEditor := False;
  try
    Dialog.SilentVisualMode := FSilentVisualMode;
    Dialog.OnInstrumentPosition := InstrumentPreview;
    if (Pattern.Kind='performance') and (MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) or MusicStudioHasInstrumentTimeline(Pattern.ConfigJSON)) then begin
      AssetID := MusicStudioPerformanceLayerAsset(Pattern.ConfigJSON);
      if (AssetID='') and (TimelineBox.SelectedTrack>=0) then AssetID := FDocument.TrackAt(TimelineBox.SelectedTrack).PsdAssetID;
      Asset := Default(TMusicStudioPsdAsset);
      if AssetID<>'' then FSharedLibrary.TryRead(AssetID,Asset,Error);
      Dialog.LoadPerformanceSteps(Pattern,AssetID,Asset.FilePath,Asset.ConfigJSON,FDocument.Timing.BPMAt(0),FDocument.Timing.TimingJSON);
    end else Dialog.LoadPattern(Pattern);
    if Dialog.DrumFrame<>nil then begin
      DrumEditor := True; FPreview.Pause;
      Dialog.DrumFrame.TempoBPM := FDocument.Timing.BPMAt(0);
      Dialog.DrumFrame.OnPreview := DrumPreview;
    end;
    while Dialog.ShowModal=mrOK do begin
      try Dialog.ReadPattern(Pattern); FDocument.UpdatePattern(Pattern);
      except on E: Exception do begin MessageDlg(E.Message,mtWarning,[mbOK],0); Continue; end; end;
      if CommitMutation then Break;
    end;
  finally
    if Dialog.InstrumentFrame<>nil then begin Dialog.InstrumentFrame.OnPositionChange := nil; DrumEditor := True; end;
    if Dialog.DrumFrame<>nil then Dialog.DrumFrame.OnPreview := nil;
    Dialog.Free;
    if DrumEditor then FPreview.Seek(SavedPosition);
  end;
end;

procedure TFormMusicStudioSettings.DeleteButtonClick(Sender: TObject);
var ErrorText: string;
begin
  if not FValid or (PatternList.ItemIndex < 0) then Exit;
  if not DeleteButton.Enabled then Exit;
  if (VisiblePattern(PatternList.ItemIndex).Kind='psd') and FLibraryItems[PatternList.ItemIndex].Shared then begin
    if MessageDlg('「'+VisiblePattern(PatternList.ItemIndex).Name+'」を共有PSD一覧から削除しますか？'+sLineBreak+
      '原本と既存作品の割当は保持します。同じPSDを再登録すると一覧へ戻せます。'+sLineBreak+
      '共有一覧の変更は作品の取消/Undoとは独立して保存します。',mtConfirmation,[mbYes,mbNo],0)<>mrYes then Exit;
    if not RemoveSelectedLibraryPsd(ErrorText) then StatusLabel.Caption := ErrorText;
    Exit;
  end;
  if FDocument.PatternInUse(FDocument.PatternAt(SelectedPatternIndex).ID) then begin
    StatusLabel.Caption := '配置中のパターンです。先にトラック上の配置を削除してください。'; Exit;
  end;
  if MessageDlg('選択したパターンを削除しますか？ 音源ファイルは保持します。',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FDocument.RemovePattern(SelectedPatternIndex);
  SyncMemo;
end;

function TFormMusicStudioSettings.RemoveSelectedLibraryPsd(out ErrorText: string): Boolean;
var P: TMusicStudioPattern;
begin
  Result := False; ErrorText := '共有PSDを選択してください。';
  if not FValid or (PatternList.ItemIndex<0) or (PatternList.ItemIndex>=Length(FLibraryItems)) then Exit;
  P := VisiblePattern(PatternList.ItemIndex);
  if (P.Kind<>'psd') or not FLibraryItems[PatternList.ItemIndex].Shared then Exit;
  Result := FSharedLibrary.TryHide(P.AssetID,P.LibraryRevision,ErrorText);
  UpdateLibrary;
  if Result then StatusLabel.Caption := '共有PSD一覧から削除しました。原本と既存作品の割当は保持しています。';
end;

function TFormMusicStudioSettings.ImportDroppedPsd(const Path: string; out ErrorText: string): Boolean;
var A: TMusicStudioPsdAsset; Duplicate: Boolean; I: Integer;
begin
  Result := False; ErrorText := '演奏者のPSD割当スロットを選択し、左のPSD一覧へドロップしてください。';
  if not FValid or (FLibraryKind<>'psd') then Exit;
  if not ImportMusicStudioPsdFile(FSharedLibrary,Path,A,Duplicate,ErrorText) then Exit;
  UpdateLibrary;
  for I := 0 to High(FLibraryItems) do if (FLibraryItems[I].Pattern.Kind='psd') and
    (FLibraryItems[I].Pattern.AssetID=A.ID) then begin PatternList.ItemIndex := I; Break; end;
  PatternListClick(nil);
  if Duplicate then StatusLabel.Caption := '同じPSDを選択しました。演奏者へドラッグして割り当ててください。'
  else StatusLabel.Caption := 'PSDを登録しました。演奏者へドラッグして割り当ててください。';
  Result := True;
end;

function TFormMusicStudioSettings.ImportDroppedAudio(const Path: string; out ErrorText: string): Boolean;
var Index: Integer; P: TMusicStudioPattern; Ext,Before: string;
begin
  Result := False; ErrorText := '';
  if not FValid or (FLibraryKind<>'audio') then begin ErrorText := '音声トラックを選択してください。'; Exit; end;
  Ext := ExtractFileExt(Path);
  if not SameText(Ext,'.wav') and not SameText(Ext,'.mp3') then begin ErrorText := 'WAV / MP3を指定してください。'; Exit; end;
  if not TFile.Exists(Path) then begin ErrorText := 'ファイルが見つかりません。'; Exit; end;
  if not FDocument.TrySave(Before,ErrorText) then Exit;
  try
    Index := FDocument.AddAudio; P := FDocument.PatternAt(Index);
    P.FilePath := TPath.GetFullPath(Path); P.Name := ChangeFileExt(ExtractFileName(Path),'');
    FDocument.UpdatePattern(P);
    if not CommitMutation then begin ErrorText := StatusLabel.Caption; Exit; end;
    SelectPatternIndex(Index); Result := True;
  except
    on E: Exception do begin FDocument.TryLoad(Before,ErrorText); ErrorText := E.Message; end;
  end;
end;

procedure TFormMusicStudioSettings.LibraryFilesDropped(const Paths: TArray<string>);
var Path,ErrorText,Errors,LabelText: string; Count: Integer; AudioList,Imported: Boolean;
begin
  AudioList := FLibraryKind='audio';
  if AudioList then LabelText := '音声' else LabelText := 'PSD';
  Count := 0; Errors := '';
  for Path in Paths do begin
    try
      if AudioList then Imported := ImportDroppedAudio(Path,ErrorText)
      else Imported := ImportDroppedPsd(Path,ErrorText);
      if Imported then Inc(Count)
      else Errors := Errors+ExtractFileName(Path)+': '+ErrorText+sLineBreak;
    except on E: Exception do Errors := Errors+ExtractFileName(Path)+': '+E.Message+sLineBreak; end;
  end;
  if Errors<>'' then StatusLabel.Caption := Format('%s登録 %d件。一部を登録できません: %s',[LabelText,Count,Trim(Errors)])
  else if AudioList then StatusLabel.Caption := Format('音声 %d件を登録しました。タイムラインへドラッグして配置できます。',[Count])
  else StatusLabel.Caption := Format('PSD %d件を登録/選択しました。演奏者へドラッグして割り当ててください。',[Count]);
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
    if Pattern.PerformanceAttribute<>'' then Detail := PerformanceKindName(Pattern.PerformanceAttribute)+' · 共通ライブラリ'
    else if MusicStudioHasInstrumentTimeline(Pattern.ConfigJSON) then Detail := '演奏 · 区間パターン'
    else if MusicStudioPerformanceHasLayerSteps(Pattern.ConfigJSON) then Detail := '演奏 · 拍レイヤーstep'
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
  try SyncMemo; FEditHistory.RecordChange(BeforeText,JSONMemo.Text,FPendingPerformanceChange); FPendingPerformanceChange := -1; Result := True;
  except on E: Exception do begin
      if FPendingPerformanceChange>=0 then begin
        ApplyPerformanceHistory(FPendingPerformanceChange,True); FPendingPerformanceChange := -1;
      end;
      FDocument.TryLoad(BeforeText, ErrorText);
      FSyncing := True; try JSONMemo.Text := BeforeText; finally FSyncing := False; end;
      FPreview.Bind(FDocument);
    RefreshPatterns; StatusLabel.Caption := '変更を反映できません: ' + E.Message;
  end; end;
end;
function TFormMusicStudioSettings.ApplyPerformanceHistory(Index: Integer; Undo: Boolean): Boolean;
var Error: string;
begin
  Result := Assigned(FPerformanceHistory) and FPerformanceHistory.Apply(Index,Undo,Error);
  if not Result then StatusLabel.Caption := 'Undo/Redoを適用できません: '+Error;
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
var TrackID,SlotID,ClipID: string; T: TMusicStudioTrack; I,S,C: Integer; Scope: TMusicStudioSelectionScope;
begin
  Scope := TimelineBox.SelectionScope; TrackID := ''; SlotID := ''; ClipID := '';
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
    TimelineBox.SelectTrack(I); if Scope=mssTrack then Break;
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
procedure TFormMusicStudioSettings.AddPsdTrackClick(Sender: TObject);
begin AddTrack('performer'); end;
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

function TFormMusicStudioSettings.DropSlotAt(X,Y: Integer): Integer;
var TrackIndex,I: Integer; Reason: string; T: TMusicStudioTrack;
begin
  Result := TimelineBox.SlotAtPoint(X,Y); TrackIndex := TimelineBox.TrackAtPoint(X,Y);
  if (TrackIndex<0) or TimelineBox.TrackExpanded(TrackIndex) or (X<TimelineBox.HeaderWidth) then Exit;
  T := FDocument.TrackAt(TrackIndex);
  // 折りたたみ概要では、ドラッグ中の候補の受入条件から枠を選ぶ。
  if CanDropLibraryItemAt(PatternList.ItemIndex,TrackIndex,Result,Reason) then Exit;
  for I := 0 to High(T.Slots) do
    if CanDropLibraryItemAt(PatternList.ItemIndex,TrackIndex,I,Reason) then Exit(I);
end;
procedure TFormMusicStudioSettings.TimelineDragOver(Sender, Source: TObject; X,Y: Integer;
  State: TDragState; var Accept: Boolean);
var TrackIndex,SlotIndex: Integer; Reason: string; P: TMusicStudioPattern;
begin
  Accept := False;
  if not FValid or (Source <> PatternList) or (PatternList.ItemIndex < 0) then Exit;
  TrackIndex := TimelineBox.TrackAtPoint(X,Y);
  SlotIndex := DropSlotAt(X,Y);
  P := VisiblePattern(PatternList.ItemIndex);
  if (P.Kind<>'psd') and (X<TimelineBox.HeaderWidth) then Reason := 'パターンはスロットの時間領域へドロップしてください。'
  else Accept := CanDropLibraryItemAt(PatternList.ItemIndex,TrackIndex,SlotIndex,Reason);
  if Accept and (P.Kind='psd') then StatusLabel.Caption := '演奏者へPSDを割り当てられます。'
  else if Accept then StatusLabel.Caption := Format('%.2f秒へ配置できます。',[TimelineBox.SecondsAtSlot(X,TrackIndex,SlotIndex)])
  else StatusLabel.Caption := Reason;
end;

procedure TFormMusicStudioSettings.TimelineDragDrop(Sender, Source: TObject; X,Y: Integer);
var Reason: string; Accept: Boolean;
begin
  // hover後の一覧更新や欠損も含め、実際のdrop座標で同じ条件を再確認する。
  TimelineDragOver(Sender,Source,X,Y,dsDragMove,Accept);
  if not Accept then Exit;
  if not DropLibraryItemAt(PatternList.ItemIndex,TimelineBox.TrackAtPoint(X,Y),
    DropSlotAt(X,Y),TimelineBox.SecondsAtSlot(X,TimelineBox.TrackAtPoint(X,Y),DropSlotAt(X,Y)),Reason) then begin
    if Reason<>'' then StatusLabel.Caption := Reason;
  end;
end;

procedure TFormMusicStudioSettings.ArrangementMenuPopup(Sender: TObject);
var Selected,TrackMenu,SlotMenu,ClipMenu: Boolean; T: TMusicStudioTrack;
begin
  TrackMenu := TimelineBox.SelectionScope=mssTrack; SlotMenu := TimelineBox.SelectionScope=mssSlot; ClipMenu := TimelineBox.SelectionScope=mssClip;
  Selected := FValid and (TimelineBox.SelectedTrack >= 0);
  if Selected then begin T := FDocument.TrackAt(TimelineBox.SelectedTrack);
    Selected := (T.Kind = 'audio') or (T.Kind = 'psd'); end;
  ArrangementMenu.Items[0].Visible := TrackMenu; ArrangementMenu.Items[1].Visible := TrackMenu;
  ArrangementMenu.Items[4].Visible := TrackMenu; ArrangementMenu.Items[5].Visible := TrackMenu;
  FTrackSettingsItem.Visible := TrackMenu; FTrackDeleteItem.Visible := TrackMenu;
  FSlotSettingsItem.Visible := SlotMenu; FSlotDeleteItem.Visible := SlotMenu;
  FSlotUpItem.Visible := SlotMenu; FSlotDownItem.Visible := SlotMenu;
  FSlotAddItem.Visible := TrackMenu or SlotMenu; FClipEditItem.Visible := ClipMenu; FClipDeleteItem.Visible := ClipMenu;
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
    if (T.Kind='psd') and not ChooseMusicStudioAttribute(Self,T.PerformanceAttribute) then Exit;
    if T.Kind='psd' then FDocument.SetPerformer(Index,T.PerformanceAttribute,nil,False);
    FDocument.UpdateTrack(Index,T.Name,T.Color,T.PsdPath); CommitMutation;
  finally D.Free; end;
end;

procedure TFormMusicStudioSettings.SlotMenuClick(Sender: TObject);
var P: TPoint; T: TMusicStudioTrack; I: Integer; K: string;
begin
  if not FValid or (TimelineBox.SelectedTrack < 0) then begin StatusLabel.Caption := '先にトラックを選択してください。'; Exit; end;
  T := FDocument.TrackAt(TimelineBox.SelectedTrack);
  if (T.Kind <> 'audio') and (T.Kind <> 'psd') then Exit;
  for I := 0 to High(SLOT_KINDS) do begin
    SlotAddMenu.Items[I].Enabled := ((T.Kind='audio') and ((SLOT_KINDS[I]='audio') or (SLOT_KINDS[I]='tempo'))) or
      ((T.Kind='psd') and (T.PsdAssetID<>'') and (SLOT_KINDS[I]='customExpression'));
    for K in T.ProvidedSlots do if SLOT_KINDS[I]=K then SlotAddMenu.Items[I].Enabled := True;
    SlotAddMenu.Items[I].Visible := SlotAddMenu.Items[I].Enabled;
  end;
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
  if not ConfirmDelete('スロット「'+FDocument.TrackAt(TIndex).Slots[SIndex].Name+'」と中の配置を削除しますか？ 他のスロット・元パターン・参照ファイルは保持します。') then Exit;
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

function TFormMusicStudioSettings.ConfirmDelete(const Text: string): Boolean;
begin
  if Assigned(FOnConfirmDelete) then Result := FOnConfirmDelete(Text)
  else Result := MessageDlg(Text,mtConfirmation,[mbYes,mbNo],0)=mrYes;
end;
procedure TFormMusicStudioSettings.TrackDeleteClick(Sender: TObject);
var Index: Integer;
begin
  Index := TimelineBox.SelectedTrack; if not FValid or (Index < 0) then Exit;
  if not ConfirmDelete('トラック「'+FDocument.TrackAt(Index).Name+'」と、その中の配置を削除しますか？ 左の元パターンと素材ファイルは保持します。') then Exit;
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
  if (TimelineBox.SelectionScope<>mssTrack) and (TimelineBox.SelectedTrack>=0) and (TimelineBox.SelectedSlot>=0) then
    if FDocument.TrackAt(TimelineBox.SelectedTrack).Slots[TimelineBox.SelectedSlot].Kind='customExpression' then begin
      FSmallEditor.EditCustomAt(TimelineBox.SelectedTrack,TimelineBox.SelectedSlot,TimelineBox.SelectedClip,FPreview.Position); Exit;
    end;
  if TimelineBox.SelectionScope=mssTrack then begin TrackSettingsClick(nil); Exit; end;
  if TimelineBox.SelectedClip >= 0 then ClipEditClick(nil)
  else if TimelineBox.SelectedSlot >= 0 then SlotSettingsClick(nil) else TrackSettingsClick(nil);
end;
procedure TFormMusicStudioSettings.TimelineTrackMove(FromIndex,ToIndex: Integer);
begin
  FDocument.ReorderTrack(FromIndex,ToIndex); if CommitMutation then TimelineBox.SelectTrack(ToIndex);
end;
procedure TFormMusicStudioSettings.TimelineDelete(Sender: TObject);
begin
  case TimelineBox.SelectionScope of
    mssTrack: TrackDeleteClick(Sender);
    mssSlot: SlotDeleteClick(Sender);
    mssClip: ClipDeleteClick(Sender);
  end;
end;
procedure TFormMusicStudioSettings.TimelineSelectionChange(Sender: TObject);
var T: TMusicStudioTrack; PlacementTrack: Integer; Supported: Boolean; K: string;
begin
  FLibraryContext := ''; PlacementTrack := -1;
  if FValid and (TimelineBox.SelectedTrack>=0) then begin
    T := FDocument.TrackAt(TimelineBox.SelectedTrack); if T.Kind='psd' then PlacementTrack := TimelineBox.SelectedTrack;
  end;
  FPreview.PlacementEditor.SelectTrack(PlacementTrack);
  UpdateLibrary;
  SlotAddButton.Enabled := False;
  if not FValid then begin InfoLabel.Caption := 'JSONを修復するか、キャンセルしてください。'; Exit; end;
  if TimelineBox.SelectedTrack < 0 then begin
    InfoLabel.Caption := 'トラック＋ → スロットを選択 → 左の一覧を右クリックで追加・設定 → 配置 → 適用'; Exit;
  end;
  T := FDocument.TrackAt(TimelineBox.SelectedTrack);
  SlotAddButton.Enabled := (T.Kind = 'audio') or (T.Kind = 'psd');
  InfoLabel.Caption := '選択トラック: '+T.Name;
  if T.Kind='psd' then InfoLabel.Caption := InfoLabel.Caption+' / 演奏属性: '+PerformanceKindName(T.PerformanceAttribute);
  if TimelineBox.SelectedSlot >= 0 then InfoLabel.Caption := InfoLabel.Caption+
    '  /  スロット: '+T.Slots[TimelineBox.SelectedSlot].Name;
  InfoLabel.Caption := InfoLabel.Caption+'  ・  右クリックで設定 / 並べ替え / 削除';
  if (TimelineBox.SelectedSlot>=0) and T.HasCapabilityMetadata then begin
    K := T.Slots[TimelineBox.SelectedSlot].Kind; Supported := (K='psd') or (K='customExpression');
    for K in T.ProvidedSlots do if K=T.Slots[TimelineBox.SelectedSlot].Kind then Supported := True;
    if not Supported then InfoLabel.Caption := InfoLabel.Caption+' / 割当PSDは未対応です。配置は保持しています。';
  end;
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

function TFormMusicStudioSettings.AssignPerformerPSD(TrackIndex: Integer; const AssetID: string; out ErrorText: string): Boolean;
var Profile: TMusicStudioPerformerProfile; Asset: TMusicStudioPsdAsset; Track: TMusicStudioTrack; Transform: TMusicStudioPsdTransform;
begin
  Result := False;
  if not ReadMusicStudioPerformer(FSharedLibrary,AssetID,Profile,ErrorText) then Exit;
  if Profile.Attribute='' then begin
    Profile.Attribute := FDocument.TrackAt(TrackIndex).PerformanceAttribute;
    if not ChooseMusicStudioAttribute(Self,Profile.Attribute) then begin ErrorText := 'PSD割当を取り消しました。'; Exit; end;
  end;
  Track := FDocument.TrackAt(TrackIndex);
  FDocument.AssignPsd(TrackIndex,AssetID);
  if FSharedLibrary.TryRead(AssetID,Asset,ErrorText) then
    if Asset.OriginalPath<>'' then FDocument.UpdateTrack(TrackIndex,ChangeFileExt(ExtractFileName(Asset.OriginalPath),''),Track.Color,'')
    else FDocument.UpdateTrack(TrackIndex,Asset.Name,Track.Color,'');
  Transform := Track.PsdTransform;
  if not Transform.HasBounds and not Transform.HasStage then begin
    Transform.HasStage := True; Transform.Scale := 1; FDocument.UpdatePsdTransform(TrackIndex,Transform);
  end;
  FDocument.SetPerformer(TrackIndex,Profile.Attribute,Profile.Slots,True,Profile.SelectionsJSON);
  Result := CommitMutation;
  if Result then begin
    if Length(Profile.Slots)=0 then StatusLabel.Caption := 'PSDを割り当てましたが、利用できる演奏・歌唱・演出枠が見つかりません。PSDのレイヤー名を確認してください。'
    else StatusLabel.Caption := 'PSDを割り当て、演奏属性と利用できる枠を更新しました。';
  end;
end;

procedure TFormMusicStudioSettings.CopyTrackClick(Sender: TObject);
begin
  if FValid and (TimelineBox.SelectedTrack>=0) then begin
    FTrackClipboard := FDocument.CopyTrack(TimelineBox.SelectedTrack); StatusLabel.Caption := 'トラックをコピーしました。';
  end;
end;

procedure TFormMusicStudioSettings.PasteTrackClick(Sender: TObject);
var Index: Integer;
begin
  if not FValid or (FTrackClipboard='') then Exit;
  try Index := FDocument.PasteTrack(FTrackClipboard);
  except on E: Exception do begin StatusLabel.Caption := 'トラックを貼り付けられません: '+E.Message; Exit; end; end;
  if CommitMutation then TimelineBox.SelectTrack(Index);
end;

procedure TFormMusicStudioSettings.EditCommonPerformance(NewPattern: Boolean);
var Store: TMusicStudioPerformanceLibrary; P,BeforePattern: TMusicStudioPattern; Error,AssetID: string; I: Integer;
begin
  if (TimelineBox.SelectedTrack<0) or (FPerformanceAttribute='') then Exit;
  AssetID := FDocument.TrackAt(TimelineBox.SelectedTrack).PsdAssetID;
  if NewPattern then begin
    P := Default(TMusicStudioPattern); P.Kind := 'performance'; P.Name := PerformanceKindName(FPerformanceAttribute)+' 演奏';
    P.Color := '#EDBA70'; P.PerformanceAttribute := FPerformanceAttribute; P.ConfigJSON := '{"lengthBeats":16,"notes":[]}';
  end else P := VisiblePattern(PatternList.ItemIndex);
  BeforePattern := P;
  if not EditMusicStudioPerformance(Self,FSharedLibrary,AssetID,FSilentVisualMode,FDocument.Timing.BPMAt(0),P,Error) then begin
    if Error<>'' then StatusLabel.Caption := Error; Exit;
  end;
  if not NewPattern and SameMusicStudioPerformance(BeforePattern,P) then Exit;
  Store := TMusicStudioPerformanceLibrary.Create(FSharedLibrary.Root);
  try
    if not Store.TrySave(P,Error) then begin MessageDlg(Error,mtWarning,[mbOK],0); Exit; end;
  finally Store.Free; end;
  if FPerformanceHistory=nil then FPerformanceHistory := TMusicStudioPerformanceHistory.Create(FSharedLibrary.Root);
  FPendingPerformanceChange := FPerformanceHistory.RecordSaved(BeforePattern,P);
  try
    FDocument.RefreshPerformanceSnapshots(P);
  except on E: Exception do begin
    ApplyPerformanceHistory(FPendingPerformanceChange,True); FPendingPerformanceChange := -1;
    StatusLabel.Caption := '作品へ反映できません: '+E.Message; Exit;
  end; end;
  if not CommitMutation then Exit;
  UpdateLibrary;
  for I := 0 to High(FLibraryItems) do if FLibraryItems[I].Pattern.SharedPatternID=P.SharedPatternID then PatternList.ItemIndex := I;
  PatternListClick(nil); StatusLabel.Caption := '共通演奏を保存し、この作品の配置へ反映しました。';
end;

end.
