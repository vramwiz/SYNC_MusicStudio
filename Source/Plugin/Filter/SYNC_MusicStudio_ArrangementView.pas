unit SYNC_MusicStudio_ArrangementView;

// トラックとクリップの表示・座標変換・スクロール。文書は借用し変更操作は親フォームへ返す。
interface

uses
  System.Classes, System.Types, System.Generics.Collections, Winapi.Messages, Vcl.Controls, Vcl.StdCtrls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Menus,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_WaveCache,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PerformanceCache, SYNC_MusicStudio_PsdSceneCache,
  SYNC_MusicStudio_LibraryData, SYNC_MusicStudio_TimelineMetrics, SYNC_MusicStudio_DarkScrollBar;

type
  TMusicStudioSelectionScope = (mssTrack,mssSlot,mssClip);
  TMusicStudioTrackMoveEvent = procedure(FromIndex,ToIndex: Integer) of object;
  TMusicStudioTrackVisibilityEvent = procedure(TrackIndex,Mode: Integer) of object;
  TMusicStudioTrackVisible = function(TrackIndex: Integer): Boolean of object;
  TMusicStudioClipMoveEvent = procedure(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds: Double) of object;
  TMusicStudioClipResizeEvent = procedure(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds,LengthSeconds: Double) of object;
  TMusicStudioSeekEvent = procedure(Seconds: Double) of object;
  TMusicStudioTempoMenuEvent = procedure(Beat: Double) of object;
  TMusicStudioSmallMenuEvent = procedure(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint) of object;
  TMusicStudioArrangementRow = record
    TrackIndex, SlotIndex,Height: Integer; // -1は見出し/折りたたみサマリー。展開状態と選択は独立。
  end;
  TMusicStudioArrangementView = class(TCustomControl)
  private
    FDocument: TMusicStudioDocument;
    FHScroll, FVScroll: TMusicStudioDarkScrollBar;
    FSelectedTrack, FSelectedSlot, FSelectedClip, FMovingClip, FMovingTrack, FMovingSlot: Integer;
    FRows: TArray<TMusicStudioArrangementRow>;
    FMouseOffset, FProposedStart, FPixelsPerSecond: Double;
    FDragging: Boolean;
    FRulerPanning: Boolean;
    FRulerStartScroll: Integer;
    FDragStarted: Boolean;
    FMouseDownPoint: TPoint;
    FResizeEdge: Integer; // -1:left, 0:move, 1:right. 文書はmouse-upまで変更しない。
    FOriginalStart,FOriginalLength,FProposedLength: Double;
    FSilentVisualMode: Boolean;
    FOnClipMove: TMusicStudioClipMoveEvent;
    FOnClipResize: TMusicStudioClipResizeEvent;
    FOnSelectionChange: TNotifyEvent;
    FOnSeek: TMusicStudioSeekEvent;
    FOnTempoMenu: TMusicStudioTempoMenuEvent;
    FOnSmallMenu: TMusicStudioSmallMenuEvent;
    FPlayhead: Double;
    FSelectionScope: TMusicStudioSelectionScope;
    FTrackDragging,FTrackDragMoved: Boolean;
    FTrackDragFrom,FTrackInsert: Integer;
    FOnTrackMove: TMusicStudioTrackMoveEvent;
    FOnDelete: TNotifyEvent;
    FOnVisibility: TMusicStudioTrackVisibilityEvent;
    FOnTrackVisible: TMusicStudioTrackVisible;
    FEyeMenu: TPopupMenu;
    FExpandedTracks: TDictionary<string,Boolean>;
    FWaveCache: TMusicStudioWaveCache;
    FVisualCache: TMusicStudioVisualCache;
    FPerformanceCache: TMusicStudioPerformanceCache;
    FSceneCache: TMusicStudioPsdSceneCache; // PreviewFrameが所有。画像を借用するだけ。
    FSceneSerial: Integer;
    FEmotionItems: TArray<TMusicStudioLibraryItem>;
    FWaveTimer: TTimer;
    FLastFileCheck: UInt64;
    procedure EyeCommand(Sender: TObject);
    function TrackBlockHeight(Index: Integer): Integer;
    procedure SetSilentVisualMode(Value: Boolean);
    function RowSize(Index: Integer): Integer;
    function RowTop(Index: Integer): Integer;
    function SlotVisible(const Track: TMusicStudioTrack; SlotIndex: Integer): Boolean;
    procedure SyncWaveSources;
    procedure WaveTimer(Sender: TObject);
    procedure PaintClip(TrackIndex, SlotIndex, ClipIndex: Integer; const Area: TRect; Summary: Boolean);
    procedure PaintPlayhead;
    procedure ScrollChanged(Sender: TObject);
    function Scale(Value: Integer): Integer;
    function FindPattern(const ID: string; out Pattern: TMusicStudioPattern): Boolean;
    function SingingClipAt(X,Y: Integer): Boolean;
    function ActiveDragCursor: TCursor;
    procedure ApplyDragCursor;
    procedure WMSetCursor(var Message: TWMSetCursor); message WM_SETCURSOR;
    function ClipRect(TrackIndex,SlotIndex: Integer; const Clip: TMusicStudioPlacement): TRect;
    function RowAtPoint(X,Y: Integer): Integer;
    function RulerBeatStep: Double;
    function EmotionItem(const Pattern: TMusicStudioPattern; out Item: TMusicStudioLibraryItem): Boolean;
    function Metrics: TMusicStudioTimelineMetrics;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure WMCancelMode(var Message: TMessage); message WM_CANCELMODE;
    procedure WMDeferredCaptureLost(var Message: TMessage); message WM_APP+107;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DblClick; override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Bind(Document: TMusicStudioDocument);
    procedure Refresh; reintroduce;
    procedure SetEmotionItems(const Items: TArray<TMusicStudioLibraryItem>);
    // 選択中の配置の両端。旧公開名を保持し、隣の配置・見出し・スクロール領域を捕捉しない。
    function EmotionResizeEdgeAt(X,Y: Integer): Integer;
    function CancelInteraction: Boolean;
    function TrackAtPoint(X, Y: Integer): Integer;
    function SlotAtPoint(X, Y: Integer): Integer;
    function SlotRowTop(TrackIndex, SlotIndex: Integer): Integer;
    function SlotHeight(const Kind: string): Integer;
    function TrackRowTop(TrackIndex: Integer): Integer;
    procedure SelectTrack(Index: Integer);
    procedure SelectSlot(TrackIndex, SlotIndex: Integer);
    procedure SelectClip(TrackIndex, SlotIndex, ClipIndex: Integer);
    function ClipAtPoint(X, Y: Integer): Integer;
    function SecondsAtPoint(X: Integer): Double;
    function SecondsAtSlot(X,TrackIndex,SlotIndex: Integer): Double;
    function SnapSecondsForSlot(Seconds: Double; TrackIndex,SlotIndex: Integer): Double;
    function BeatSnapStep(Seconds: Double): Double;
    function TrackColumnWidth: Integer;
    function HeaderWidth: Integer;
    function RulerHeight: Integer;
    function RowHeight: Integer;
    procedure SetZoom(PixelsPerSecond: Double);
    procedure SetPlayhead(Seconds: Double);
    procedure PollWaveforms(CheckFiles: Boolean = False);
    procedure ToggleTrack(Index: Integer);
    function TrackExpanded(Index: Integer): Boolean;
    property SelectionScope: TMusicStudioSelectionScope read FSelectionScope;
    property OnTrackMove: TMusicStudioTrackMoveEvent read FOnTrackMove write FOnTrackMove;
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
    property OnVisibility: TMusicStudioTrackVisibilityEvent read FOnVisibility write FOnVisibility;
    property OnTrackVisible: TMusicStudioTrackVisible read FOnTrackVisible write FOnTrackVisible;
    property TrackInsertIndex: Integer read FTrackInsert;
    property SilentVisualMode: Boolean read FSilentVisualMode write SetSilentVisualMode;
    property WaveCache: TMusicStudioWaveCache read FWaveCache;
    property VisualCache: TMusicStudioVisualCache read FVisualCache;
    property PerformanceCache: TMusicStudioPerformanceCache read FPerformanceCache;
    property SceneCache: TMusicStudioPsdSceneCache read FSceneCache write FSceneCache;
    function TrackThumbnailRect(TrackIndex: Integer): TRect;
    function SlotThumbnailRect(TrackIndex,SlotIndex: Integer): TRect;
    property Playhead: Double read FPlayhead;
    property OnSeek: TMusicStudioSeekEvent read FOnSeek write FOnSeek;
    property OnTempoMenu: TMusicStudioTempoMenuEvent read FOnTempoMenu write FOnTempoMenu;
    property OnSmallMenu: TMusicStudioSmallMenuEvent read FOnSmallMenu write FOnSmallMenu;
    property SelectedTrack: Integer read FSelectedTrack;
    property SelectedSlot: Integer read FSelectedSlot;
    property SelectedClip: Integer read FSelectedClip;
    property OnClipMove: TMusicStudioClipMoveEvent read FOnClipMove write FOnClipMove;
    property OnClipResize: TMusicStudioClipResizeEvent read FOnClipResize write FOnClipResize;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnDragOver;
    property OnDragDrop;
    property OnDblClick;
    property PopupMenu;
  end;

implementation

uses System.SysUtils, System.Math, System.UITypes, Winapi.Windows, Vcl.Graphics,
  SYNC_MusicStudio_BeatData, SYNC_MusicStudio_TimelineContent, SYNC_MusicStudio_SmallSlotData,
  SYNC_MusicStudio_PerformanceKinds;

function RGBColor(const Hex: string): TColor;
var N: Integer;
begin
  if not TryStrToInt('$' + Copy(Hex,2,6),N) then Exit($00505050);
  Result := ((N and $FF) shl 16) or (N and $FF00) or (N shr 16);
end;

function ClipTextColor(Color: TColor): TColor;
var RGBValue, Luminance: Integer;
begin
  RGBValue := ColorToRGB(Color);
  Luminance := (RGBValue and $FF) * 299 + ((RGBValue shr 8) and $FF) * 587 + ((RGBValue shr 16) and $FF) * 114;
  if Luminance < 140000 then Result := $00EEEEEE else Result := $00202020;
end;
function ClipNoteColor(Color: TColor): TColor;
var Value,R,G,B: Integer;
begin
  Value := ColorToRGB(Color); R := Value and $FF; G := (Value shr 8) and $FF; B := (Value shr 16) and $FF;
  if R*299+G*587+B*114<160000 then begin R := (R+255) div 2; G := (G+255) div 2; B := (B+255) div 2; end;
  Result := RGB(R,G,B);
end;

constructor TMusicStudioArrangementView.Create(AOwner: TComponent);
var Item: TMenuItem; I: Integer;
begin
  inherited;
  FEyeMenu := TPopupMenu.Create(Self);
  for I := 0 to 2 do begin
    Item := TMenuItem.Create(FEyeMenu); Item.Tag := I; Item.OnClick := EyeCommand;
    case I of 0: Item.Caption := 'このトラックを表示 / 非表示'; 1: Item.Caption := '選択トラックだけ表示'; 2: Item.Caption := '全トラックを表示'; end;
    FEyeMenu.Items.Add(Item);
  end;
  FTrackInsert := -1; FSelectionScope := mssTrack;
  DoubleBuffered := True; TabStop := True; Color := $00232323;
  FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1; FMovingClip := -1;
  FExpandedTracks := TDictionary<string,Boolean>.Create; FWaveCache := TMusicStudioWaveCache.Create;
  FVisualCache := TMusicStudioVisualCache.Create;
  FPerformanceCache := TMusicStudioPerformanceCache.Create;
  FPixelsPerSecond := 40;
  FHScroll := TMusicStudioDarkScrollBar.Create(Self); FHScroll.Parent := Self;
  FHScroll.Kind := sbHorizontal; FHScroll.OnChange := ScrollChanged;
  FHScroll.SmallChange := 1; FHScroll.LargeChange := 10;
  FVScroll := TMusicStudioDarkScrollBar.Create(Self); FVScroll.Parent := Self;
  FVScroll.Kind := sbVertical; FVScroll.OnChange := ScrollChanged;
  FWaveTimer := TTimer.Create(Self); FWaveTimer.Interval := 80; FWaveTimer.OnTimer := WaveTimer;
end;

destructor TMusicStudioArrangementView.Destroy;
begin
  FWaveTimer.Enabled := False; FWaveTimer.OnTimer := nil; FDocument := nil;
  FExpandedTracks.Free; FPerformanceCache.Free; FVisualCache.Free; FWaveCache.Free; inherited;
end;

procedure TMusicStudioArrangementView.SetSilentVisualMode(Value: Boolean);
begin
  if FSilentVisualMode=Value then Exit;
  FSilentVisualMode := Value;
  FWaveCache.Clear;
  SyncWaveSources; Invalidate;
end;

procedure TMusicStudioArrangementView.WaveTimer(Sender: TObject);
var CheckFiles: Boolean;
begin
  CheckFiles := GetTickCount64-FLastFileCheck >= 1000;
  if CheckFiles then FLastFileCheck := GetTickCount64;
  PollWaveforms(CheckFiles);
end;
procedure TMusicStudioArrangementView.PollWaveforms(CheckFiles: Boolean);
var WaveChanged,VisualChanged: Boolean;
begin
  WaveChanged := FWaveCache.Poll(CheckFiles); VisualChanged := FVisualCache.Poll(CheckFiles);
  if Assigned(FSceneCache) and (FSceneSerial<>FSceneCache.Serial) then begin
    FSceneSerial := FSceneCache.Serial; VisualChanged := True;
  end;
  if WaveChanged or VisualChanged then Invalidate;
end;

function TMusicStudioArrangementView.SlotVisible(const Track: TMusicStudioTrack; SlotIndex: Integer): Boolean;
var K: string;
begin
  Result := False;
  if Track.Slots[SlotIndex].Kind='psd' then Exit;
  Result := True;
  if (Track.Slots[SlotIndex].Kind='customExpression') or not Track.HasCapabilityMetadata then Exit;
  if not (MusicStudioSmallSlot(Track.Slots[SlotIndex].Kind) or (Track.Slots[SlotIndex].Kind='singing') or (Track.Slots[SlotIndex].Kind='performance')) then Exit;
  Result := Length(Track.Slots[SlotIndex].Clips)>0; for K in Track.ProvidedSlots do if K=Track.Slots[SlotIndex].Kind then Exit(True);
end;
function TMusicStudioArrangementView.SlotHeight(const Kind: string): Integer;
begin
  if (Kind='singing') or (Kind='performance') then Result := Scale(60)
  else if MusicStudioSmallSlot(Kind) or (Kind='customExpression') then Result := Scale(20)
  else if Kind='psd' then Result := Scale(32) else Result := RowHeight;
end;
function TMusicStudioArrangementView.RowSize(Index: Integer): Integer;
begin Result := FRows[Index].Height; end;
function TMusicStudioArrangementView.RowTop(Index: Integer): Integer;
var I: Integer;
begin
  Result := RulerHeight-FVScroll.Position;
  for I := 0 to Index-1 do Inc(Result,RowSize(I));
end;
function TMusicStudioArrangementView.TrackExpanded(Index: Integer): Boolean;
begin
  Result := False;
  if (FDocument<>nil) and (Index>=0) and (Index<FDocument.TrackCount) then
    FExpandedTracks.TryGetValue(FDocument.TrackAt(Index).ID,Result);
end;
procedure TMusicStudioArrangementView.ToggleTrack(Index: Integer);
begin
  if not Assigned(FDocument) or (Index < 0) or (Index >= FDocument.TrackCount) then Exit;
  FExpandedTracks.AddOrSetValue(FDocument.TrackAt(Index).ID,not TrackExpanded(Index));
  if FSelectedTrack<>Index then begin
    FSelectedTrack := Index;
    if Length(FDocument.TrackAt(Index).Slots)>0 then FSelectedSlot := 0 else FSelectedSlot := -1;
  end;
  FSelectedClip := -1; FSelectionScope := mssTrack; Refresh;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TMusicStudioArrangementView.SyncWaveSources;
var AllPaths,VisiblePaths: TList<string>; Requests: TList<TMusicStudioVisualRequest>;
  Request: TMusicStudioVisualRequest; I,J,K,Y,Count: Integer; T: TMusicStudioTrack;
  P: TMusicStudioPattern; S: TMusicStudioSlot; C: TMusicStudioPlacement; R: TRect;
  Item: TMusicStudioLibraryItem;
begin
  AllPaths := TList<string>.Create; VisiblePaths := TList<string>.Create;
  Requests := TList<TMusicStudioVisualRequest>.Create;
  try
    if Assigned(FDocument) then begin
      Count := 0;
      for I := 0 to FDocument.PatternCount-1 do begin
        P := FDocument.PatternAt(I);
        if P.Kind='singing' then begin
          Request := Default(TMusicStudioVisualRequest);
          Request.Kind := vkMidi; Request.Path := P.FilePath; Request.Visible := Count<4;
          Requests.Add(Request); Inc(Count);
        end;
      end;
      Count := 0;
      for I := 0 to FDocument.TrackCount-1 do begin
        T := FDocument.TrackAt(I);
        if T.Kind='psd' then begin
          Request := Default(TMusicStudioVisualRequest);
          Y := TrackRowTop(I); Request.Kind := vkPsd; Request.Path := T.PsdPath;
          Request.Visible := (Count<4) or ((Y<FHScroll.Top) and (Y+RowHeight>RulerHeight));
          if (FSceneCache=nil) or (Count>=4) then Requests.Add(Request);
          Inc(Count);
        end;
        for S in T.Slots do for C in S.Clips do if FindPattern(C.PatternID,P) and (P.Kind = 'audio') then
          AllPaths.Add(P.FilePath);
      end;
      for I := 0 to High(FRows) do begin
        Y := RowTop(I); if Y >= FHScroll.Top then Break;
        if Y+RowSize(I) <= RulerHeight then Continue;
        T := FDocument.TrackAt(FRows[I].TrackIndex);
        for J := 0 to High(T.Slots) do begin
          if not SlotVisible(T,J) then Continue;
          if (FRows[I].SlotIndex >= 0) and (FRows[I].SlotIndex <> J) then Continue;
          if (FRows[I].SlotIndex < 0) and TrackExpanded(FRows[I].TrackIndex) then Continue;
          for K := 0 to High(T.Slots[J].Clips) do begin
            C := T.Slots[J].Clips[K]; R := ClipRect(FRows[I].TrackIndex,J,C);
            if (R.Right <= HeaderWidth) or (R.Left >= FVScroll.Left) then Continue;
            if FindPattern(C.PatternID,P) then begin
              if P.Kind='audio' then VisiblePaths.Add(P.FilePath)
              else if P.Kind='singing' then begin
                Request := Default(TMusicStudioVisualRequest);
                Request.Kind := vkMidi; Request.Path := P.FilePath; Request.Visible := True; Requests.Add(Request);
              end else if (P.Kind='emotion') and EmotionItem(P,Item) and not Item.Missing then begin
                Request := Default(TMusicStudioVisualRequest); Request.Kind := vkPsd;
                Request.Path := Item.Pattern.FilePath; Request.PsdVersion := Item.PsdVersion;
                Request.ConfigJSON := Item.ThumbnailConfigJSON; Request.ExpressionJSON := Item.ExpressionJSON;
                Request.Visible := True; Requests.Add(Request);
              end;
            end;
          end;
        end;
      end;
    end;
    if not FSilentVisualMode then FWaveCache.SetSources(AllPaths.ToArray,VisiblePaths.ToArray)
    else FWaveCache.SetSources(nil,nil);
    FVisualCache.SetSources(Requests.ToArray);
  finally Requests.Free; VisiblePaths.Free; AllPaths.Free; end;
end;

function TMusicStudioArrangementView.EmotionItem(const Pattern: TMusicStudioPattern;
  out Item: TMusicStudioLibraryItem): Boolean;
var Current: TMusicStudioLibraryItem;
begin
  for Current in FEmotionItems do
    if (Current.Pattern.AssetID=Pattern.AssetID) and (Current.Pattern.SharedPatternID=Pattern.SharedPatternID) and
      ((Pattern.SharedPatternID<>'') or (Current.Pattern.ID=Pattern.ID)) then begin Item := Current; Exit(True); end;
  Item := Default(TMusicStudioLibraryItem); Result := False;
end;
procedure TMusicStudioArrangementView.SetEmotionItems(const Items: TArray<TMusicStudioLibraryItem>);
begin FEmotionItems := Copy(Items); SyncWaveSources; Invalidate; end;

function TMusicStudioArrangementView.Scale(Value: Integer): Integer;
begin Result := MulDiv(Value, CurrentPPI, 96); end;
function TMusicStudioArrangementView.TrackColumnWidth: Integer;
begin Result := Scale(180); end;
function TMusicStudioArrangementView.HeaderWidth: Integer;
begin Result := TrackColumnWidth+Scale(100); end;
function TMusicStudioArrangementView.RulerHeight: Integer;
begin Result := Scale(32); end;
function TMusicStudioArrangementView.RowHeight: Integer;
begin Result := Scale(42); end;

procedure TMusicStudioArrangementView.Bind(Document: TMusicStudioDocument);
begin
  FDocument := nil; FRows := nil; FEmotionItems := nil;
  FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1;
  CancelInteraction;
  FWaveCache.Clear;
  FVisualCache.Clear;
  FDocument := Document; FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1;
  if Assigned(Document) and (Document.TrackCount > 0) then begin
    FSelectedTrack := 0;
    if Length(Document.TrackAt(0).Slots)>0 then FSelectedSlot := 0;
  end;
  FVScroll.Position := 0; Refresh;
end;

procedure TMusicStudioArrangementView.CreateParams(var Params: TCreateParams);
begin inherited; Params.Style := Params.Style or WS_CLIPCHILDREN; end;
function TMusicStudioArrangementView.ActiveDragCursor: TCursor;
begin
  if FTrackDragging and FTrackDragMoved then Result := crSizeNS
  else if FRulerPanning then Result := crHandPoint
  else if FDragging then begin if FResizeEdge<>0 then Result := crSizeWE else Result := crSizeAll; end
  else Result := crDefault;
end;
procedure TMusicStudioArrangementView.ApplyDragCursor;
var Value: TCursor;
begin
  Value := ActiveDragCursor; Cursor := Value;
  // capture中のWM_SETCURSORや子window通過でOS側だけ戻った場合も更新する。
  if Value<>crDefault then Winapi.Windows.SetCursor(Screen.Cursors[Value]);
end;
procedure TMusicStudioArrangementView.WMSetCursor(var Message: TWMSetCursor);
begin
  if FDragging or FRulerPanning or (FTrackDragging and FTrackDragMoved) then begin ApplyDragCursor; Message.Result := 1; end
  else inherited;
end;
procedure TMusicStudioArrangementView.Resize;
var S: Integer;
begin
  inherited;
  if not Assigned(FHScroll) then Exit;
  CancelInteraction;
  S := Scale(17);
  FHScroll.SetBounds(HeaderWidth, ClientHeight - S, Max(1, ClientWidth - HeaderWidth - S), S);
  FVScroll.SetBounds(ClientWidth - S, RulerHeight, S, Max(1,ClientHeight - RulerHeight - S));
  Refresh;
end;

procedure TMusicStudioArrangementView.Refresh;
var I,J,N,First,Pass,Rank,TrackCount,HeightUsed,BlockHeight: Integer; T: TMusicStudioTrack; S: TMusicStudioSlot; C: TMusicStudioPlacement; EndTime: Double;
begin
  EndTime := 60; TrackCount := 0; FRows := nil;
  if Assigned(FDocument) then TrackCount := FDocument.TrackCount;
  if FSelectedTrack >= TrackCount then begin FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1; end;
  if Assigned(FDocument) then begin
    if FSelectedTrack >= 0 then begin
      T := FDocument.TrackAt(FSelectedTrack);
      if FSelectedSlot >= Length(T.Slots) then begin FSelectedSlot := -1; FSelectedClip := -1; end;
      if (FSelectedSlot>=0) and (T.Slots[FSelectedSlot].Kind<>'psd') and not SlotVisible(T,FSelectedSlot) then begin FSelectedSlot := -1; FSelectedClip := -1; end;
      if FSelectedSlot >= 0 then if FSelectedClip >= Length(T.Slots[FSelectedSlot].Clips) then FSelectedClip := -1;
    end;
    for I := 0 to TrackCount - 1 do begin
      T := FDocument.TrackAt(I);
      N := Length(FRows); SetLength(FRows,N+1); FRows[N].TrackIndex := I; FRows[N].SlotIndex := -1;
      for S in T.Slots do for C in S.Clips do EndTime := Max(EndTime,C.StartSeconds+C.LengthSeconds+30);
      if TrackExpanded(I) or ((T.Kind='audio') and (Length(T.Slots)=1)) then begin
        First := N;
        for Pass := 0 to 3 do for J := 0 to High(T.Slots) do begin
          if not SlotVisible(T,J) then Continue;
          if T.Slots[J].Kind='singing' then Rank := 0
          else if T.Slots[J].Kind='performance' then Rank := 1
          else if MusicStudioSmallSlot(T.Slots[J].Kind) or (T.Slots[J].Kind='customExpression') then Rank := 2 else Rank := 3;
          if Rank<>Pass then Continue;
          if FRows[First].SlotIndex<0 then FRows[First].SlotIndex := J
          else begin N := Length(FRows); SetLength(FRows,N+1); FRows[N].TrackIndex := I; FRows[N].SlotIndex := J; end;
        end;
      end;
    end;
  end;
  for I := 0 to High(FRows) do begin
    if FRows[I].SlotIndex<0 then FRows[I].Height := RowHeight
    else FRows[I].Height := SlotHeight(FDocument.TrackAt(FRows[I].TrackIndex).Slots[FRows[I].SlotIndex].Kind);
  end;
  // 小型枠だけの演奏者でも、サムネイルと2行のトラック名が次のトラックへはみ出さない。
  for I := 0 to High(FRows) do if (I=0) or (FRows[I-1].TrackIndex<>FRows[I].TrackIndex) then begin
    BlockHeight := 0; J := I;
    while (J<Length(FRows)) and (FRows[J].TrackIndex=FRows[I].TrackIndex) do begin Inc(BlockHeight,FRows[J].Height); Inc(J); end;
    if BlockHeight<RowHeight then Inc(FRows[I].Height,RowHeight-BlockHeight);
  end;
  if FDocument<>nil then FHScroll.Max := Min(MaxInt-1024,Ceil(FDocument.SecondsToBeat(EndTime)*64)) else FHScroll.Max := 0;
  HeightUsed := 0;
  for I := 0 to High(FRows) do Inc(HeightUsed,RowSize(I));
  FVScroll.Max := Max(0,HeightUsed-Max(1,ClientHeight-RulerHeight-Scale(17)));
  FVScroll.SmallChange := RowHeight;
  FVScroll.LargeChange := Max(1,ClientHeight-RulerHeight-Scale(17));
  FVScroll.Visible := FVScroll.Max > 0;
  FVScroll.PageSize := FVScroll.LargeChange;
  FHScroll.PageSize := Max(1,Round(Max(1,FHScroll.Width)/Metrics.PixelsPerBeat*64));
  FHScroll.LargeChange := FHScroll.PageSize;
  if Assigned(FWaveCache) then SyncWaveSources;
  if Assigned(FPerformanceCache) then FPerformanceCache.SetPatterns(FDocument);
  Invalidate;
end;

procedure TMusicStudioArrangementView.SelectTrack(Index: Integer);
begin
  if (FDocument=nil) or (Index<0) or (Index>=FDocument.TrackCount) then Exit;
  FSelectedTrack := Index; FSelectedSlot := -1; FSelectedClip := -1; FSelectionScope := mssTrack; Refresh;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;
procedure TMusicStudioArrangementView.SelectSlot(TrackIndex,SlotIndex: Integer);
var I,Top: Integer;
begin
  if not Assigned(FDocument) or (TrackIndex < 0) or (TrackIndex >= FDocument.TrackCount) then Exit;
  SelectTrack(TrackIndex);
  if (SlotIndex < 0) or (SlotIndex >= Length(FDocument.TrackAt(TrackIndex).Slots)) then Exit;
  FSelectedSlot := SlotIndex; FSelectionScope := mssSlot;
  for I := 0 to High(FRows) do if (FRows[I].TrackIndex = TrackIndex) and (FRows[I].SlotIndex = SlotIndex) then begin
    Top := RowTop(I);
    if Top < RulerHeight then FVScroll.Position := Max(0,FVScroll.Position+Top-RulerHeight)
    else if Top+RowSize(I) > FHScroll.Top then FVScroll.Position := Min(FVScroll.Max,FVScroll.Position+Top+RowSize(I)-FHScroll.Top);
    Break;
  end;
  Invalidate;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;
procedure TMusicStudioArrangementView.SelectClip(TrackIndex, SlotIndex, ClipIndex: Integer);
begin
  SelectSlot(TrackIndex,SlotIndex);
  if (FSelectedTrack<>TrackIndex) or (FSelectedSlot<>SlotIndex) then Exit;
  if (ClipIndex>=0) and (ClipIndex<Length(FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Clips)) then FSelectedClip := ClipIndex
  else FSelectedClip := -1;
  if FSelectedClip>=0 then FSelectionScope := mssClip;
  Invalidate; if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;
function TMusicStudioArrangementView.SlotRowTop(TrackIndex,SlotIndex: Integer): Integer;
var I: Integer;
begin
  for I := 0 to High(FRows) do if (FRows[I].TrackIndex = TrackIndex) and (FRows[I].SlotIndex = SlotIndex) then
    Exit(RowTop(I));
  Result := -1;
end;
function TMusicStudioArrangementView.TrackRowTop(TrackIndex: Integer): Integer;
var I: Integer;
begin Result := -1; for I := 0 to High(FRows) do if FRows[I].TrackIndex=TrackIndex then Exit(RowTop(I)); end;
function TMusicStudioArrangementView.TrackThumbnailRect(TrackIndex: Integer): TRect;
var Y: Integer;
begin
  Result := Rect(0,0,0,0);
  if (FDocument=nil) or (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) then Exit;
  if FDocument.TrackAt(TrackIndex).Kind<>'psd' then Exit;
  Y := TrackRowTop(TrackIndex); Result := Rect(Scale(48),Y+Scale(5),Scale(80),Y+Scale(37));
end;
function TMusicStudioArrangementView.SlotThumbnailRect(TrackIndex,SlotIndex: Integer): TRect;
begin
  // 旧公開入口は残し、PSD画像はトラック見出しへ集約する。
  Result := Rect(0,0,0,0);
end;

procedure TMusicStudioArrangementView.SetZoom(PixelsPerSecond: Double);
begin CancelInteraction; FPixelsPerSecond := EnsureRange(PixelsPerSecond,10.0,1536.0);
  FHScroll.PageSize := Max(1,Round(Max(1,FHScroll.Width)/Metrics.PixelsPerBeat*64)); FHScroll.LargeChange := FHScroll.PageSize; SyncWaveSources; Invalidate; end;
function TMusicStudioArrangementView.Metrics: TMusicStudioTimelineMetrics;
begin Result.Document := FDocument; Result.Header := HeaderWidth; Result.ScrollTicks := FHScroll.Position;
  Result.PPI := CurrentPPI; Result.Zoom := FPixelsPerSecond; end;

procedure TMusicStudioArrangementView.SetPlayhead(Seconds: Double);
var VisibleBeats,Beat: Double;
begin
  FPlayhead := Max(0.0,Seconds);
  if FDocument=nil then Exit; Beat := FDocument.SecondsToBeat(FPlayhead);
  VisibleBeats := Max(1.0,(ClientWidth-HeaderWidth-Scale(17))/Metrics.PixelsPerBeat);
    FHScroll.Max := Max(FHScroll.Max,Min(MaxInt-1024,Ceil((Beat+VisibleBeats)*64)));
  if (Beat<Metrics.FirstBeat) or (Beat>Metrics.FirstBeat+VisibleBeats) then
    FHScroll.Position := Min(FHScroll.Max,Floor(Max(0.0,Beat-VisibleBeats*0.2)*64));
  Invalidate;
end;
procedure TMusicStudioArrangementView.PaintPlayhead;
var X,Saved: Integer;
begin
  X := Metrics.XAtSeconds(FPlayhead);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,HeaderWidth,0,FVScroll.Left,FHScroll.Top);
    Canvas.Pen.Color := $00457AFE; Canvas.Pen.Width := Scale(2);
    Canvas.MoveTo(X,0); Canvas.LineTo(X,FHScroll.Top); Canvas.Pen.Width := 1;
  finally RestoreDC(Canvas.Handle,Saved); end;
end;

procedure TMusicStudioArrangementView.ScrollChanged(Sender: TObject);
begin if Assigned(FWaveCache) then SyncWaveSources; Invalidate; end;

function TMusicStudioArrangementView.RowAtPoint(X,Y: Integer): Integer;
var I,Top: Integer;
begin
  Result := -1;
  if not Assigned(FDocument) or (Y < RulerHeight) or (Y >= FHScroll.Top) or
    (X < 0) or (X >= FVScroll.Left) then Exit;
  Top := RulerHeight-FVScroll.Position;
  for I := 0 to High(FRows) do begin
    if (Y >= Top) and (Y < Top+RowSize(I)) then Exit(I);
    Inc(Top,RowSize(I)); if Top > Y then Break;
  end;
end;
function TMusicStudioArrangementView.TrackAtPoint(X,Y: Integer): Integer;
var I: Integer;
begin I := RowAtPoint(X,Y); if I < 0 then Result := -1 else Result := FRows[I].TrackIndex; end;
function TMusicStudioArrangementView.SlotAtPoint(X,Y: Integer): Integer;
var I,J,Pass: Integer; T: TMusicStudioTrack; C: TMusicStudioPlacement;
begin
  Result := -1; I := RowAtPoint(X,Y); if I<0 then Exit;
  T := FDocument.TrackAt(FRows[I].TrackIndex);
  if X<TrackColumnWidth then begin
    // 見出し画像はPSD一覧への入口。展開操作とは分離する。
    if PtInRect(TrackThumbnailRect(FRows[I].TrackIndex),Point(X,Y)) then
      for J := 0 to High(T.Slots) do if T.Slots[J].Kind='psd' then Exit(J);
    Exit;
  end;
  Result := FRows[I].SlotIndex; if Result>=0 then Exit;
  if X<HeaderWidth then Exit;
  if TrackExpanded(FRows[I].TrackIndex) then Exit;
  // 重なった概要は歌唱を最優先でhit。空白は選択中の大型枠へ配置できる。
  for Pass := 0 to 1 do for J := 0 to High(T.Slots) do begin
    if not SlotVisible(T,J) then Continue;
    if ((Pass=0) and (T.Slots[J].Kind<>'singing')) or
       ((Pass=1) and (T.Slots[J].Kind<>'performance') and (T.Slots[J].Kind<>'audio')) then Continue;
    for C in T.Slots[J].Clips do if PtInRect(ClipRect(FRows[I].TrackIndex,J,C),Point(X,Y)) then Exit(J);
  end;
  if (FSelectedTrack=FRows[I].TrackIndex) and (FSelectedSlot>=0) then
    if (T.Slots[FSelectedSlot].Kind='singing') or (T.Slots[FSelectedSlot].Kind='performance') or
       (T.Slots[FSelectedSlot].Kind='audio') then Exit(FSelectedSlot);
  for J := 0 to High(T.Slots) do if SlotVisible(T,J) and
    ((T.Slots[J].Kind='singing') or (T.Slots[J].Kind='performance') or (T.Slots[J].Kind='audio')) then Exit(J);
end;

function TMusicStudioArrangementView.SecondsAtPoint(X: Integer): Double;
begin
  Result := SecondsAtSlot(X,FSelectedTrack,FSelectedSlot);
end;
function TMusicStudioArrangementView.BeatSnapStep(Seconds: Double): Double;
begin
  Result := Metrics.SnapStep;
end;
function TMusicStudioArrangementView.RulerBeatStep: Double;
begin Result := Metrics.SnapStep; end;
function TMusicStudioArrangementView.SnapSecondsForSlot(Seconds: Double; TrackIndex,SlotIndex: Integer): Double;
begin
  if FDocument=nil then Exit(Max(0.0,Seconds));
  Result := FDocument.BeatToSeconds(Metrics.SnapBeat(FDocument.SecondsToBeat(Seconds)));
end;
function TMusicStudioArrangementView.SecondsAtSlot(X,TrackIndex,SlotIndex: Integer): Double;
begin Result := Metrics.SecondsAtX(X); end;
function TMusicStudioArrangementView.ClipRect(TrackIndex,SlotIndex: Integer; const Clip: TMusicStudioPlacement): TRect;
var Y,H: Integer; Pattern: TMusicStudioPattern; Track: TMusicStudioTrack;
begin
  Track := FDocument.TrackAt(TrackIndex);
  Y := SlotRowTop(TrackIndex,SlotIndex);
  H := SlotHeight(Track.Slots[SlotIndex].Kind);
  if not TrackExpanded(TrackIndex) and (Track.Kind<>'audio') then begin
    H := RowHeight; Y := TrackRowTop(TrackIndex);
  end;
  Result := Rect(Metrics.XAtSeconds(Clip.StartSeconds), Y + Scale(1),
    Metrics.XAtSeconds(Clip.StartSeconds+Clip.LengthSeconds), Y + H - Scale(1));
  if FindPattern(Clip.PatternID,Pattern) and ((Pattern.Kind='selection') or (Pattern.Kind='emotion') or (Pattern.Kind='performance') or (Pattern.Kind='tempo')) then
    Result.Right := Max(Result.Right,Result.Left+Scale(9));
end;

function TMusicStudioArrangementView.ClipAtPoint(X, Y: Integer): Integer;
var I,TrackIndex,SlotIndex: Integer; T: TMusicStudioTrack; R: TRect;
begin
  Result := -1; if X < HeaderWidth then Exit;
  TrackIndex := TrackAtPoint(X,Y); if TrackIndex < 0 then Exit;
  SlotIndex := SlotAtPoint(X,Y); if SlotIndex < 0 then Exit;
  T := FDocument.TrackAt(TrackIndex);
  // 最小幅を補った表情より、隣の配置の実時間範囲を先に判定する。
  for I := High(T.Slots[SlotIndex].Clips) downto 0 do begin
    R := ClipRect(TrackIndex,SlotIndex,T.Slots[SlotIndex].Clips[I]);
    R.Right := Metrics.XAtSeconds(T.Slots[SlotIndex].Clips[I].StartSeconds+T.Slots[SlotIndex].Clips[I].LengthSeconds);
    if PtInRect(R,Point(X,Y)) then Exit(I);
  end;
  for I := High(T.Slots[SlotIndex].Clips) downto 0 do
    if PtInRect(ClipRect(TrackIndex,SlotIndex,T.Slots[SlotIndex].Clips[I]),Point(X,Y)) then Exit(I);
end;

function TMusicStudioArrangementView.FindPattern(const ID: string; out Pattern: TMusicStudioPattern): Boolean;
var I: Integer;
begin
  for I := 0 to FDocument.PatternCount - 1 do begin
    Pattern := FDocument.PatternAt(I); if Pattern.ID = ID then Exit(True);
  end;
  Result := False;
end;

procedure DrawLabel(C: TCanvas; R: TRect; const Text: string; Flags: Cardinal = DT_SINGLELINE or DT_END_ELLIPSIS);
begin
  // SaveDC/RestoreDC後にもVCLのFont値とGDIの選択状態を一致させる。
  SelectObject(C.Handle,C.Font.Handle); SetTextColor(C.Handle,ColorToRGB(C.Font.Color)); SetBkMode(C.Handle,TRANSPARENT);
  DrawText(C.Handle,PChar(Text),Length(Text),R,Flags);
end;

procedure TMusicStudioArrangementView.PaintClip(TrackIndex, SlotIndex, ClipIndex: Integer; const Area: TRect; Summary: Boolean);
var T: TMusicStudioTrack; P: TMusicStudioPattern; C: TMusicStudioPlacement;
  R,TextRect,WaveRect,ThumbRect: TRect; Detail: string; Source: TMusicStudioWaveSource; Saved,Size: Integer;
  Background,Foreground,TitleColor,FrameColor: TColor;
  Visual: TMusicStudioVisualSource;
  Item: TMusicStudioLibraryItem; Thumb: TBitmap;
begin
  T := FDocument.TrackAt(TrackIndex); C := T.Slots[SlotIndex].Clips[ClipIndex];
  if FDragging and (TrackIndex = FMovingTrack) and (SlotIndex = FMovingSlot) and (ClipIndex = FMovingClip) then begin
    C.StartSeconds := FProposedStart;
    C.LengthSeconds := FProposedLength;
    if C.TimeBase='beats' then C.StartBeat := FDocument.SecondsToBeat(C.StartSeconds);
  end;
  R := ClipRect(TrackIndex,SlotIndex,C);
  if (R.Right <= Area.Left) or (R.Left >= Area.Right) or not FindPattern(C.PatternID,P) then Exit;
  TitleColor := RGBColor(P.Color); Background := $00282828;
  if P.Kind='audio' then Foreground := $00D4D4D4 else Foreground := ClipNoteColor(TitleColor);
  if Summary and (P.Kind='singing') then Foreground := $00F4F4F4;
  FrameColor := $00606060;
  if (TrackIndex = FSelectedTrack) and (SlotIndex = FSelectedSlot) and (ClipIndex = FSelectedClip) then FrameColor := clWhite;
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Area.Left,Area.Top,Area.Right,Area.Bottom);
    Canvas.Brush.Color := TitleColor; Canvas.Pen.Color := FrameColor;
    if not Summary then Canvas.Rectangle(R);
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := ClipTextColor(TitleColor);
    if (MusicStudioSmallSlot(T.Slots[SlotIndex].Kind) or (T.Slots[SlotIndex].Kind='customExpression')) and not Summary then begin
      TextRect := R; Inc(TextRect.Left,Scale(6)); Inc(TextRect.Top,Scale(4));
      DrawLabel(Canvas,TextRect,P.Name); Exit;
    end;
    TextRect := R; TextRect.Left := Max(Area.Left+Scale(4),R.Left+Scale(7));
    TextRect.Right := Min(Area.Right,R.Right-Scale(4)); TextRect.Top := R.Top+Scale(1);
    TextRect.Bottom := R.Top+Scale(16);
    Detail := P.Name;
    if Summary and (Length(T.Slots) > 1) then Detail := Format('%d:%s / %s',[SlotIndex+1,T.Slots[SlotIndex].Name,P.Name]);
    if not Summary then DrawLabel(Canvas,TextRect,Detail);
    WaveRect := R; Inc(WaveRect.Left); Dec(WaveRect.Right);
    if not Summary then WaveRect.Top := TextRect.Bottom; Dec(WaveRect.Bottom);
    Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := Background; if not Summary then Canvas.FillRect(WaveRect);
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := $00EEEEEE;
    if P.Kind = 'audio' then begin
      Source := FWaveCache.Find(P.FilePath);
      // 音源0秒は配置の左端。枠内余白を時間軸へ加算しない。
      WaveRect.Left := R.Left;
      if Assigned(Source) and (Source.Status in [wsReady,wsSilent]) then begin
        DrawMusicStudioTimelineContent(Canvas,Metrics,C,P,WaveRect,Area,FWaveCache,FVisualCache,FPerformanceCache,CurrentPPI,Background,Foreground);
        Detail := '';
        if P.Volume = 0 then Detail := 'ミュート' else if Source.Status = wsSilent then Detail := '無音';
        if Detail <> '' then begin TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail); end;
      end else begin
        if FSilentVisualMode then Detail := '音声解析停止（無音確認）'
        else if Assigned(Source) then Detail := Source.Message else Detail := '波形を準備中…';
        TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail);
      end;
    end else if P.Kind='singing' then begin
      Visual := FVisualCache.Find(vkMidi,P.FilePath); Detail := FVisualCache.MidiMessage(Visual,P.SourceTrack);
      WaveRect.Left := R.Left;
      if Detail='' then DrawMusicStudioTimelineContent(Canvas,Metrics,C,P,WaveRect,Area,FWaveCache,FVisualCache,FPerformanceCache,CurrentPPI,Background,Foreground,Summary)
      else begin TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail); end;
    end else if P.Kind='performance' then begin
      WaveRect.Left := R.Left;
      DrawMusicStudioTimelineContent(Canvas,Metrics,C,P,WaveRect,Area,FWaveCache,FVisualCache,FPerformanceCache,CurrentPPI,Background,Foreground);
    end else if P.Kind='tempo' then begin
      WaveRect.Left := R.Left;
      DrawMusicStudioTimelineContent(Canvas,Metrics,C,P,WaveRect,Area,FWaveCache,FVisualCache,FPerformanceCache,CurrentPPI,Background,Foreground);
      Detail := FPerformanceCache.PatternMessage(P.ID);
      if Detail<>'' then begin TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail); end;
    end else if P.Kind='emotion' then begin
      Thumb := nil; Detail := '表情未割当';
      Size := Min(WaveRect.Height-Scale(4),WaveRect.Width-Scale(4));
      Size := Min(Size,Min(WaveRect.Right,Area.Right)-Max(WaveRect.Left,Area.Left)-Scale(4));
      if EmotionItem(P,Item) then begin
        Visual := FVisualCache.Find(vkPsd,Item.Pattern.FilePath,Item.PsdVersion);
        if Item.Missing then Detail := '表情の参照先がありません'
        else if Size>0 then begin
          Thumb := FVisualCache.Thumbnail(Visual,Size,Size,CurrentPPI,Background);
          if Visual<>nil then Detail := Visual.Message else Detail := '表情を準備中…';
        end;
      end;
      if (Thumb<>nil) and (Size>0) then begin
        ThumbRect := Rect(Max(WaveRect.Left,Area.Left)+Scale(2),WaveRect.Top+Scale(2),0,0);
        Canvas.Draw(ThumbRect.Left,ThumbRect.Top,Thumb);
      end else begin TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail); end;
    end else begin
      TextRect.Top := TextRect.Bottom; TextRect.Bottom := R.Bottom-Scale(4);
      DrawLabel(Canvas,TextRect,Format('%.1f s  ・  %.1f s',[C.StartSeconds,C.LengthSeconds]));
    end;
    Canvas.Brush.Style := bsClear; Canvas.Pen.Color := FrameColor; if not Summary then Canvas.Rectangle(R);
    if (R.Width>0) and (P.Kind='singing') then begin
      // 歌唱は配置全体の移動のみ。開始線を実際の開始Xに置き、伸縮gripと区別する。
      Canvas.Pen.Color := $00FFD060; Canvas.Pen.Width := Max(2,Scale(2));
      Canvas.MoveTo(R.Left,R.Top+Scale(3)); Canvas.LineTo(R.Left,R.Bottom-Scale(3)); Canvas.Pen.Width := 1;
    end else if (R.Width>0) and (TrackIndex=FSelectedTrack) and (SlotIndex=FSelectedSlot) and (ClipIndex=FSelectedClip) then begin
      Canvas.Pen.Color := clWhite;
      Size := Min(R.Right-1,R.Left+Scale(2));
      Canvas.MoveTo(Size,R.Top+Scale(5)); Canvas.LineTo(Size,R.Bottom-Scale(5));
      Size := Max(R.Left,R.Right-Scale(3));
      Canvas.MoveTo(Size,R.Top+Scale(5)); Canvas.LineTo(Size,R.Bottom-Scale(5));
    end;
  finally
    Canvas.Brush.Style := bsSolid; RestoreDC(Canvas.Handle,Saved); Canvas.Refresh;
  end;
end;

function TMusicStudioArrangementView.TrackBlockHeight(Index: Integer): Integer;
var I: Integer;
begin Result := 0; for I := 0 to High(FRows) do if FRows[I].TrackIndex=Index then Inc(Result,RowSize(I)); end;
procedure TMusicStudioArrangementView.EyeCommand(Sender: TObject);
begin if Assigned(FOnVisibility) then begin FOnVisibility(FSelectedTrack,TMenuItem(Sender).Tag); Invalidate; end; end;
procedure TMusicStudioArrangementView.Paint;
var I,J,K,Pass,Y,H,X,Saved,NextLabel: Integer; T: TMusicStudioTrack; Slot: TMusicStudioSlot;
  Area,R,ThumbR: TRect; Beat,LastBeat,Step,Factor: Double; Text: string; Thumb: TBitmap; Visual: TMusicStudioVisualSource;
begin
  Canvas.Font.Assign(Font); Canvas.Brush.Color := $00232323; Canvas.FillRect(ClientRect);
  Canvas.Brush.Color := $00313131; Canvas.FillRect(Rect(0,0,ClientWidth,RulerHeight)); Canvas.Font.Color := clSilver;
  DrawLabel(Canvas,Rect(Scale(8),Scale(8),TrackColumnWidth,RulerHeight),'トラック');
  DrawLabel(Canvas,Rect(TrackColumnWidth+Scale(8),Scale(8),HeaderWidth,RulerHeight),'スロット');
  Area := Rect(HeaderWidth,RulerHeight,FVScroll.Left,FHScroll.Top);
  if FDocument=nil then Exit;
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Area.Left,0,Area.Right,Area.Bottom);
    Step := RulerBeatStep; Beat := Floor(Metrics.FirstBeat/Step)*Step;
    LastBeat := Metrics.BeatAtX(Area.Right); NextLabel := Area.Left;
    while Beat<=LastBeat+Step do begin
      X := Metrics.XAtBeat(Beat); Canvas.Pen.Color := $003A3A3A;
      if Abs(FDocument.Timing.BeatInMeasure(Beat))<1E-8 then Canvas.Pen.Color := $00605A50;
      Canvas.MoveTo(X,RulerHeight); Canvas.LineTo(X,Area.Bottom);
      if X>=NextLabel then begin DrawLabel(Canvas,Rect(X+Scale(4),Scale(7),X+Scale(88),RulerHeight),Metrics.BeatLabel(Beat)); NextLabel := X+Scale(64); end;
      Beat := Beat+Step;
    end;
  finally RestoreDC(Canvas.Handle,Saved); Canvas.Refresh; end;
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,0,RulerHeight,Area.Right,Area.Bottom);
    for I := 0 to High(FRows) do begin
      Y := RowTop(I); H := RowSize(I); if Y>=Area.Bottom then Break; if Y+H<=Area.Top then Continue;
      T := FDocument.TrackAt(FRows[I].TrackIndex); J := FRows[I].SlotIndex;
      Canvas.Brush.Color := $002D2D2D;
      if (FSelectedTrack=FRows[I].TrackIndex) and (FSelectedSlot=J) and (FSelectionScope<>mssTrack) then Canvas.Brush.Color := $00564D41;
      Canvas.FillRect(Rect(TrackColumnWidth,Y,HeaderWidth,Y+H)); Canvas.Font.Color := $00EEEEEE;
      if J>=0 then Text := T.Slots[J].Name else if T.Kind='audio' then Text := '音声'
      else begin
        Text := '';
        for K := 0 to High(T.Slots) do if SlotVisible(T,K) and ((T.Slots[K].Kind='singing') or (T.Slots[K].Kind='performance')) then begin
          if Text<>'' then Text := Text+' / '; if T.Slots[K].Kind='singing' then Text := Text+'歌唱' else Text := Text+'演奏';
        end;
        if Text='' then if (T.PsdAssetID='') and (T.PsdPath='') then Text := 'PSD未割当' else Text := '演出';
      end;
      DrawLabel(Canvas,Rect(TrackColumnWidth+Scale(7),Y+Scale(6),HeaderWidth-Scale(4),Y+H),Text);
      if J>=0 then begin
        Slot := T.Slots[J]; for K := 0 to High(Slot.Clips) do PaintClip(FRows[I].TrackIndex,J,K,Area,False);
      end else for Pass := 0 to 1 do for J := 0 to High(T.Slots) do begin
        if not SlotVisible(T,J) then Continue;
        if ((Pass=0) and (T.Slots[J].Kind<>'performance') and (T.Slots[J].Kind<>'audio')) or
           ((Pass=1) and (T.Slots[J].Kind<>'singing')) then Continue;
        for K := 0 to High(T.Slots[J].Clips) do PaintClip(FRows[I].TrackIndex,J,K,Area,True);
      end;
      Canvas.Pen.Color := $00444444; Canvas.MoveTo(TrackColumnWidth,Y+H); Canvas.LineTo(Area.Right,Y+H);
    end;
    // トラック列は配下スロット全体にまたがる。時間軸用の空見出し行を作らない。
    for I := 0 to FDocument.TrackCount-1 do begin
      Y := TrackRowTop(I); H := TrackBlockHeight(I); if (Y+H<=Area.Top) or (Y>=Area.Bottom) then Continue;
      T := FDocument.TrackAt(I); Canvas.Brush.Color := $002D2D2D;
      if FSelectedTrack=I then if FSelectionScope=mssTrack then Canvas.Brush.Color := $00564D41 else Canvas.Brush.Color := $003A3630;
      Canvas.FillRect(Rect(0,Y,TrackColumnWidth,Y+H)); Canvas.Brush.Color := RGBColor(T.Color); Canvas.FillRect(Rect(0,Y,Scale(4),Y+H));
      Canvas.Font.Color := clWhite; if TrackExpanded(I) then Text := '−' else Text := '+';
      DrawLabel(Canvas,Rect(Scale(7),Y+Scale(7),Scale(24),Y+Scale(28)),Text);
      if T.Kind='psd' then begin
        Canvas.Pen.Color := $00CCCCCC; Canvas.Brush.Style := bsClear;
        Canvas.Ellipse(Scale(26),Y+Scale(12),Scale(43),Y+Scale(23));
        if not Assigned(FOnTrackVisible) or FOnTrackVisible(I) then begin Canvas.Brush.Color := $00CCCCCC; Canvas.Ellipse(Scale(32),Y+Scale(15),Scale(37),Y+Scale(20)); Canvas.Brush.Style := bsClear; end;
        if Assigned(FOnTrackVisible) and not FOnTrackVisible(I) then begin Canvas.MoveTo(Scale(26),Y+Scale(24)); Canvas.LineTo(Scale(43),Y+Scale(10)); end;
        Canvas.Brush.Style := bsSolid; ThumbR := TrackThumbnailRect(I); Visual := FVisualCache.Find(vkPsd,T.PsdPath);
        Thumb := FVisualCache.Thumbnail(Visual,ThumbR.Width,ThumbR.Height,CurrentPPI,$002D2D2D);
        if (FSceneCache<>nil) and (FSceneCache.ImageForTrack(I)<>nil) then Thumb := FSceneCache.ImageForTrack(I);
        if Thumb<>nil then begin
          Factor := Min(ThumbR.Width/Thumb.Width,ThumbR.Height/Thumb.Height); R := ThumbR;
          R.Right := R.Left+Max(1,Round(Thumb.Width*Factor)); R.Bottom := R.Top+Max(1,Round(Thumb.Height*Factor)); Canvas.StretchDraw(R,Thumb);
        end;
        X := Scale(85);
      end else X := Scale(28);
      Canvas.Brush.Style := bsClear; Canvas.Font.Color := clWhite;
      DrawLabel(Canvas,Rect(X,Y+Scale(4),TrackColumnWidth-Scale(4),Y+Scale(23)),T.Name);
      Canvas.Font.Color := clSilver; if T.Kind='psd' then Text := PerformanceKindName(T.PerformanceAttribute) else Text := '音声';
      DrawLabel(Canvas,Rect(X,Y+Scale(23),TrackColumnWidth-Scale(4),Y+Scale(40)),Text);
      Canvas.Brush.Style := bsSolid; Canvas.Pen.Color := $00505050; Canvas.MoveTo(0,Y+H); Canvas.LineTo(TrackColumnWidth,Y+H);
    end;
    if FTrackDragging and FTrackDragMoved and (FTrackInsert>=0) then begin
      if FTrackInsert<FDocument.TrackCount then Y := TrackRowTop(FTrackInsert)
      else if FDocument.TrackCount>0 then Y := TrackRowTop(FDocument.TrackCount-1)+TrackBlockHeight(FDocument.TrackCount-1) else Y := RulerHeight;
      Canvas.Pen.Color := $0055DFFF; Canvas.Pen.Width := Scale(3); Canvas.MoveTo(0,Y); Canvas.LineTo(Area.Right,Y); Canvas.Pen.Width := 1;
    end;
  finally RestoreDC(Canvas.Handle,Saved); Canvas.Refresh; end;
  PaintPlayhead;
end;

function TMusicStudioArrangementView.SingingClipAt(X,Y: Integer): Boolean;
var T,S,C: Integer; P: TMusicStudioPattern;
begin
  Result := False;
  if (X>=FVScroll.Left) or (Y<RulerHeight) or (Y>=FHScroll.Top) then Exit;
  C := ClipAtPoint(X,Y); if C<0 then Exit;
  T := TrackAtPoint(X,Y); S := SlotAtPoint(X,Y);
  Result := FindPattern(FDocument.TrackAt(T).Slots[S].Clips[C].PatternID,P) and (P.Kind='singing');
end;
function TMusicStudioArrangementView.EmotionResizeEdgeAt(X,Y: Integer): Integer;
var T: TMusicStudioTrack; C: TMusicStudioPlacement; P: TMusicStudioPattern; R: TRect; Grip: Integer;
begin
  Result := 0;
  if (FDocument=nil) or (FSelectedTrack<0) or (FSelectedSlot<0) or (FSelectedClip<0) then Exit;
  T := FDocument.TrackAt(FSelectedTrack);
  if (FSelectedSlot>=Length(T.Slots)) or (FSelectedClip>=Length(T.Slots[FSelectedSlot].Clips)) then Exit;
  C := T.Slots[FSelectedSlot].Clips[FSelectedClip];
  if not FindPattern(C.PatternID,P) or (P.Kind='singing') then Exit;
  R := ClipRect(FSelectedTrack,FSelectedSlot,C);
  if ClipAtPoint(X,Y)<>FSelectedClip then Exit;
  if (X<HeaderWidth) or (X>=FVScroll.Left) or (Y<RulerHeight) or (Y>=FHScroll.Top) or not PtInRect(R,Point(X,Y)) then Exit;
  Grip := Min(Scale(7),Max(1,(R.Width-1) div 3));
  if X-R.Left<Grip then Result := -1 else if R.Right-1-X<Grip then Result := 1;
end;
function TMusicStudioArrangementView.CancelInteraction: Boolean;
begin
  Result := FDragging or FRulerPanning or FTrackDragging; FTrackDragging := False; FTrackDragMoved := False; FTrackInsert := -1; FDragging := False; FRulerPanning := False; FDragStarted := False; FResizeEdge := 0;
  MouseCapture := False; Cursor := crDefault; if Result then Invalidate;
end;
procedure TMusicStudioArrangementView.WMCaptureChanged(var Message: TMessage);
begin inherited; if (FDragging or FRulerPanning or FTrackDragging) and (HWND(Message.LParam)<>Handle) then PostMessage(Handle,WM_APP+107,0,0); end;
procedure TMusicStudioArrangementView.WMDeferredCaptureLost(var Message: TMessage);
begin if (FDragging or FRulerPanning or FTrackDragging) and (GetCapture<>Handle) then CancelInteraction; end;
procedure TMusicStudioArrangementView.WMCancelMode(var Message: TMessage);
begin inherited; if FDragging or FRulerPanning or FTrackDragging then CancelInteraction; end;
procedure TMusicStudioArrangementView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key=VK_ESCAPE) and CancelInteraction then Key := 0;
  if (Key=VK_DELETE) and Assigned(FOnDelete) then begin FOnDelete(Self); Key := 0; end;
  inherited;
end;
procedure TMusicStudioArrangementView.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var T: TMusicStudioTrack; TrackIndex,SlotIndex,ClipIndex,Edge: Integer;
begin
  inherited;
  CancelInteraction;
  if (Button=mbRight) and (Y<RulerHeight) and (X>=HeaderWidth) then Exit;
  if (Button=mbLeft) and (Y<RulerHeight) and (X>=HeaderWidth) then begin
    FRulerPanning := True; FRulerStartScroll := FHScroll.Position; FMouseDownPoint := Point(X,Y);
    FDragStarted := False; MouseCapture := True; Cursor := crHandPoint; Exit;
  end;
  TrackIndex := TrackAtPoint(X,Y); SlotIndex := SlotAtPoint(X,Y); ClipIndex := ClipAtPoint(X,Y);
  if (TrackIndex>=0) and (X<TrackColumnWidth) then begin
    if (Button=mbLeft) and (X<Scale(24)) and (Y>=TrackRowTop(TrackIndex)+Scale(5)) and (Y<TrackRowTop(TrackIndex)+Scale(30)) and not (ssDouble in Shift) then begin ToggleTrack(TrackIndex); Exit; end;
    SelectTrack(TrackIndex);
    if (X>=Scale(24)) and (X<Scale(46)) and (Y>=TrackRowTop(TrackIndex)+Scale(5)) and (Y<TrackRowTop(TrackIndex)+Scale(30)) and (FDocument.TrackAt(TrackIndex).Kind='psd') then begin
      if (Button=mbLeft) and Assigned(FOnVisibility) then FOnVisibility(TrackIndex,0); Invalidate; Exit;
    end;
    if SlotIndex>=0 then FSelectedSlot := SlotIndex; // PSD画像クリックの一覧文脈だけ保持する。
    if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
    if (Button=mbLeft) and not (ssDouble in Shift) then begin
      FTrackDragging := True; FTrackDragMoved := False; FTrackDragFrom := TrackIndex;
      FMouseDownPoint := Point(X,Y); MouseCapture := True;
    end;
    Exit;
  end;
  FSelectedTrack := TrackIndex; FSelectedSlot := SlotIndex; FSelectedClip := ClipIndex;
  if X<HeaderWidth then begin FSelectedClip := -1; FSelectionScope := mssSlot; end
  else if ClipIndex>=0 then FSelectionScope := mssClip else FSelectionScope := mssSlot;
  Refresh;
  Edge := EmotionResizeEdgeAt(X,Y);
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
  if (Button=mbLeft) and (ClipIndex<0) and (SlotIndex>=0) and (X>=HeaderWidth) then
    if MusicStudioSmallSlot(FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Kind) and Assigned(FOnSeek) then FOnSeek(SecondsAtSlot(X,TrackIndex,SlotIndex));
  // VCLはDblClickでモーダル設定を閉じた後にもssDouble付きMouseDownを呼ぶ。
  // そのMouseDownで再捕捉すると、設定終了後にドラッグ状態が残ってしまう。
  if (Button = mbLeft) and not (ssDouble in Shift) and (FSelectedClip >= 0) then begin
    T := FDocument.TrackAt(FSelectedTrack);
    FMovingTrack := FSelectedTrack; FMovingSlot := FSelectedSlot; FMovingClip := FSelectedClip;
    FProposedStart := T.Slots[FSelectedSlot].Clips[FSelectedClip].StartSeconds;
    FOriginalStart := FProposedStart; FOriginalLength := T.Slots[FSelectedSlot].Clips[FSelectedClip].LengthSeconds;
    FProposedLength := FOriginalLength; FResizeEdge := Edge;
    FMouseOffset := Metrics.BeatAtX(X)-FDocument.SecondsToBeat(FProposedStart);
    if Edge<>0 then begin
      if Edge>0 then FMouseOffset := Metrics.BeatAtX(X)-FDocument.SecondsToBeat(FOriginalStart+FOriginalLength);
    end;
    FMouseDownPoint := Point(X,Y); FDragStarted := False; FDragging := True; MouseCapture := True;
    ApplyDragCursor;
  end;
  Invalidate;
end;

procedure TMusicStudioArrangementView.DblClick;
begin
  CancelInteraction;
  if (FDocument<>nil) and (FSelectedTrack>=0) and (FSelectedSlot>=0) then
    if MusicStudioSmallSlot(FDocument.TrackAt(FSelectedTrack).Slots[FSelectedSlot].Kind) then Exit;
  inherited;
end;

function TMusicStudioArrangementView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var P: TPoint; AnchorBeat: Double;
begin
  Result := True;
  if WheelDelta = 0 then Exit;
  if ssShift in Shift then begin
    if WheelDelta > 0 then FVScroll.Position := Max(0,FVScroll.Position - RowHeight)
    else FVScroll.Position := Min(FVScroll.Max,FVScroll.Position + RowHeight);
    Exit;
  end;
  P := ScreenToClient(MousePos);
  AnchorBeat := Metrics.BeatAtX(P.X);
  if WheelDelta > 0 then SetZoom(FPixelsPerSecond * 1.25) else SetZoom(FPixelsPerSecond / 1.25);
  FHScroll.Position := EnsureRange(Round((AnchorBeat-Max(0,P.X-HeaderWidth)/Metrics.PixelsPerBeat)*64),0,FHScroll.Max);
end;
procedure TMusicStudioArrangementView.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var TrackIndex,SlotIndex: Integer;
begin
  if (FSelectedTrack>=0) and (MousePos.Y>=RulerHeight) and (MousePos.Y>=TrackRowTop(FSelectedTrack)+Scale(5)) and (MousePos.Y<TrackRowTop(FSelectedTrack)+Scale(30)) and (MousePos.X>=Scale(24)) and (MousePos.X<Scale(46)) and
    (FDocument<>nil) and (FDocument.TrackAt(FSelectedTrack).Kind='psd') then begin
    CancelInteraction; Handled := True; FEyeMenu.Popup(ClientToScreen(MousePos).X,ClientToScreen(MousePos).Y); Exit;
  end;
  if (MousePos.Y>=0) and (MousePos.Y<RulerHeight) and (MousePos.X>=HeaderWidth) and Assigned(FOnTempoMenu) then begin
    CancelInteraction; FOnTempoMenu(Metrics.BeatAtX(MousePos.X)); Handled := True;
  end else begin
    TrackIndex := TrackAtPoint(MousePos.X,MousePos.Y); SlotIndex := SlotAtPoint(MousePos.X,MousePos.Y);
    if (FDocument<>nil) and (TrackIndex>=0) and (SlotIndex>=0) and (MousePos.X>=HeaderWidth) and Assigned(FOnSmallMenu) then
      if MusicStudioSmallSlot(FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Kind) or
         (FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Kind='customExpression') then begin
        CancelInteraction; Handled := True;
        FOnSmallMenu(TrackIndex,SlotIndex,ClipAtPoint(MousePos.X,MousePos.Y),SecondsAtSlot(MousePos.X,TrackIndex,SlotIndex),ClientToScreen(MousePos)); Exit;
      end;
    inherited;
  end;
end;

procedure TMusicStudioArrangementView.MouseMove(Shift: TShiftState; X,Y: Integer);
var Index: Integer; EdgeBeat,EdgeTime,EndTime,MinimumLength,StartBeat,EndBeat,PatternLimit: Double; Clip: TMusicStudioPlacement;
begin
  inherited;
  if FTrackDragging then begin
    if (Abs(X-FMouseDownPoint.X)+Abs(Y-FMouseDownPoint.Y))>Scale(4) then FTrackDragMoved := True;
    if not FTrackDragMoved then Exit;
    if Y<RulerHeight+Scale(12) then FVScroll.Position := Max(0,FVScroll.Position-Scale(12))
    else if Y>FHScroll.Top-Scale(12) then FVScroll.Position := Min(FVScroll.Max,FVScroll.Position+Scale(12));
    FTrackInsert := FDocument.TrackCount;
    for Index := 0 to FDocument.TrackCount-1 do
      if Y<TrackRowTop(Index)+TrackBlockHeight(Index) div 2 then begin FTrackInsert := Index; Break; end;
    ApplyDragCursor; Invalidate; Exit;
  end;
  if FRulerPanning then begin
    if Abs(X-FMouseDownPoint.X)>Scale(3) then FDragStarted := True;
    if FDragStarted then FHScroll.Position := EnsureRange(FRulerStartScroll-Round((X-FMouseDownPoint.X)/Metrics.PixelsPerBeat*64),0,FHScroll.Max);
    Exit;
  end;
  if FDragging and Assigned(FDocument) then begin
    if not FDragStarted then begin
      if Abs(X-FMouseDownPoint.X)<Max(Scale(3),GetSystemMetrics(SM_CXDRAG)) then Exit;
      FDragStarted := True;
    end;
    if X=FMouseDownPoint.X then begin FProposedStart := FOriginalStart; FProposedLength := FOriginalLength; Invalidate; Exit; end;
    if FResizeEdge<>0 then begin
      EdgeBeat := Max(0.0,Metrics.BeatAtX(X)-FMouseOffset); EdgeTime := FDocument.BeatToSeconds(EdgeBeat);
      EndTime := FOriginalStart+FOriginalLength;
      MinimumLength := 0.001;
      Clip := FDocument.TrackAt(FMovingTrack).Slots[FMovingSlot].Clips[FMovingClip];
      if Clip.TimeBase='beats' then begin
        if FResizeEdge<0 then MinimumLength := Max(1E-9,EndTime-
          FDocument.BeatToSeconds(FDocument.SecondsToBeat(EndTime)-0.001000001))
        else MinimumLength := Max(1E-9,FDocument.BeatToSeconds(
          FDocument.SecondsToBeat(FOriginalStart)+0.001000001)-FOriginalStart);
      end;
      if ((FResizeEdge<0) and (Abs(EdgeTime-FOriginalStart)<1E-9)) or
        ((FResizeEdge>0) and (Abs(EdgeTime-EndTime)<1E-9)) then begin
        FProposedStart := FOriginalStart; FProposedLength := FOriginalLength; Invalidate; Exit;
      end;
      EdgeTime := FDocument.BeatToSeconds(Metrics.SnapBeat(EdgeBeat));
      PatternLimit := FDocument.PatternLengthBeats(Clip.PatternID);
      if FResizeEdge<0 then begin
        if (Clip.TimeBase='beats') and (PatternLimit>0) then
          EdgeTime := Max(EdgeTime,FDocument.BeatToSeconds(Max(0.0,Clip.StartBeat+Clip.LengthBeats-PatternLimit)));
        FProposedStart := EnsureRange(EdgeTime,0.0,Max(0.0,EndTime-MinimumLength));
        FProposedLength := Max(MinimumLength,EndTime-FProposedStart);
      end else begin
        if (Clip.TimeBase='beats') and (PatternLimit>0) then
          EdgeTime := Min(EdgeTime,FDocument.BeatToSeconds(Clip.StartBeat+PatternLimit));
        FProposedStart := FOriginalStart;
        FProposedLength := Max(MinimumLength,EnsureRange(EdgeTime,FOriginalStart+MinimumLength,604800.0)-FOriginalStart);
      end;
      ApplyDragCursor; Invalidate; Exit;
    end;
    Clip := FDocument.TrackAt(FMovingTrack).Slots[FMovingSlot].Clips[FMovingClip];
    StartBeat := Metrics.SnapBeat(Max(0.0,Metrics.BeatAtX(X)-FMouseOffset));
    FProposedStart := EnsureRange(FDocument.BeatToSeconds(StartBeat),0.0,604800.0-FOriginalLength);
    FProposedLength := FOriginalLength;
    if Clip.TimeBase='beats' then begin
      EndBeat := StartBeat+Clip.LengthBeats; FProposedLength := FDocument.BeatToSeconds(EndBeat)-FProposedStart;
    end;
    ApplyDragCursor;
    Invalidate;
  end else if (Y<RulerHeight) and (X>=HeaderWidth) then Cursor := crHandPoint
  else if SingingClipAt(X,Y) then Cursor := crSizeAll
  else if EmotionResizeEdgeAt(X,Y)<>0 then Cursor := crSizeWE else Cursor := crDefault;
end;

procedure TMusicStudioArrangementView.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var Click: Boolean; FromIndex,ToIndex: Integer;
begin
  inherited;
  if (Button=mbLeft) and FTrackDragging then begin
    MouseMove(Shift,X,Y); FromIndex := FTrackDragFrom; ToIndex := FTrackInsert; Click := FTrackDragMoved; CancelInteraction;
    if Click and (ToIndex>=0) then begin
      if ToIndex>FromIndex then Dec(ToIndex);
      if (ToIndex<>FromIndex) and Assigned(FOnTrackMove) then FOnTrackMove(FromIndex,ToIndex);
    end; Exit;
  end;
  if (Button=mbLeft) and FRulerPanning then begin
    MouseMove(Shift,X,Y); Click := not FDragStarted; CancelInteraction;
    if Click and Assigned(FOnSeek) then FOnSeek(SecondsAtPoint(X)); Exit;
  end;
  if (Button <> mbLeft) or not FDragging then Exit;
  MouseMove(Shift,X,Y);
  if not FDragStarted then begin CancelInteraction; MouseMove([],X,Y); Exit; end;
  FDragging := False; FDragStarted := False; MouseCapture := False;
  if FResizeEdge<>0 then begin
    if Assigned(FOnClipResize) then FOnClipResize(FMovingTrack,FMovingSlot,FMovingClip,FProposedStart,FProposedLength);
  end else if Assigned(FOnClipMove) then FOnClipMove(FMovingTrack,FMovingSlot,FMovingClip,FProposedStart);
  FResizeEdge := 0;
  if SingingClipAt(X,Y) then Cursor := crSizeAll else Cursor := crDefault;
  Invalidate;
end;

end.
