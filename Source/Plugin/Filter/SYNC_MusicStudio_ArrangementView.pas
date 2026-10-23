unit SYNC_MusicStudio_ArrangementView;

// トラックとクリップの表示・座標変換・スクロール。文書は借用し変更操作は親フォームへ返す。
interface

uses
  System.Classes, System.Types, Winapi.Messages, Vcl.Controls, Vcl.StdCtrls, Vcl.Forms, Vcl.ExtCtrls,
  SYNC_MusicStudio_PatternData, SYNC_MusicStudio_ArrangementData, SYNC_MusicStudio_WaveCache,
  SYNC_MusicStudio_VisualCache, SYNC_MusicStudio_PerformanceCache, SYNC_MusicStudio_PsdSceneCache,
  SYNC_MusicStudio_LibraryData, SYNC_MusicStudio_TimelineMetrics;

type
  TMusicStudioClipMoveEvent = procedure(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds: Double) of object;
  TMusicStudioClipResizeEvent = procedure(TrackIndex, SlotIndex, ClipIndex: Integer; StartSeconds,LengthSeconds: Double) of object;
  TMusicStudioSeekEvent = procedure(Seconds: Double) of object;
  TMusicStudioTempoMenuEvent = procedure(Beat: Double) of object;
  TMusicStudioSmallMenuEvent = procedure(TrackIndex,SlotIndex,ClipIndex: Integer; Seconds: Double; const ScreenPoint: TPoint) of object;
  TMusicStudioArrangementRow = record
    TrackIndex, SlotIndex: Integer; // -1は見出し/折りたたみサマリー。展開状態と選択は独立。
  end;
  TMusicStudioArrangementView = class(TCustomControl)
  private
    FDocument: TMusicStudioDocument;
    FHScroll, FVScroll: TScrollBar;
    FSelectedTrack, FSelectedSlot, FSelectedClip, FMovingClip, FMovingTrack, FMovingSlot: Integer;
    FRows: TArray<TMusicStudioArrangementRow>;
    FMouseOffset, FProposedStart, FPixelsPerSecond: Double;
    FDragging: Boolean;
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
    FExpandedTrack: Integer;
    FWaveCache: TMusicStudioWaveCache;
    FVisualCache: TMusicStudioVisualCache;
    FPerformanceCache: TMusicStudioPerformanceCache;
    FSceneCache: TMusicStudioPsdSceneCache; // PreviewFrameが所有。画像を借用するだけ。
    FSceneSerial: Integer;
    FEmotionItems: TArray<TMusicStudioLibraryItem>;
    FWaveTimer: TTimer;
    FLastFileCheck: UInt64;
    procedure SetSilentVisualMode(Value: Boolean);
    function RowSize(Index: Integer): Integer;
    function RowTop(Index: Integer): Integer;
    function SlotVisible(const Track: TMusicStudioTrack; SlotIndex: Integer): Boolean;
    function SummaryOffset(const Track: TMusicStudioTrack; SlotIndex: Integer): Integer;
    procedure SyncWaveSources;
    procedure WaveTimer(Sender: TObject);
    procedure PaintClip(TrackIndex, SlotIndex, ClipIndex: Integer; const Area: TRect; Summary: Boolean);
    procedure PaintPlayhead;
    procedure ScrollChanged(Sender: TObject);
    function Scale(Value: Integer): Integer;
    function FindPattern(const ID: string; out Pattern: TMusicStudioPattern): Boolean;
    function ClipRect(TrackIndex,SlotIndex: Integer; const Clip: TMusicStudioPlacement): TRect;
    function RowAtPoint(X,Y: Integer): Integer;
    function RulerBeatStep: Double;
    function EmotionItem(const Pattern: TMusicStudioPattern; out Item: TMusicStudioLibraryItem): Boolean;
    function Metrics: TMusicStudioTimelineMetrics;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure WMCancelMode(var Message: TMessage); message WM_CANCELMODE;
    procedure WMDeferredCaptureLost(var Message: TMessage); message WM_APP+107;
  protected
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
    function HeaderWidth: Integer;
    function RulerHeight: Integer;
    function RowHeight: Integer;
    procedure SetZoom(PixelsPerSecond: Double);
    procedure SetPlayhead(Seconds: Double);
    procedure PollWaveforms(CheckFiles: Boolean = False);
    procedure ToggleTrack(Index: Integer);
    function TrackExpanded(Index: Integer): Boolean;
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

uses System.SysUtils, System.Math, System.UITypes, System.Generics.Collections, Winapi.Windows, Vcl.Graphics,
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
begin
  inherited;
  DoubleBuffered := True; TabStop := True; Color := $00232323;
  FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1; FMovingClip := -1;
  FExpandedTrack := -1; FWaveCache := TMusicStudioWaveCache.Create;
  FVisualCache := TMusicStudioVisualCache.Create;
  FPerformanceCache := TMusicStudioPerformanceCache.Create;
  FPixelsPerSecond := 40;
  FHScroll := TScrollBar.Create(Self); FHScroll.Parent := Self;
  FHScroll.Kind := sbHorizontal; FHScroll.OnChange := ScrollChanged;
  FHScroll.SmallChange := 1; FHScroll.LargeChange := 10;
  FVScroll := TScrollBar.Create(Self); FVScroll.Parent := Self;
  FVScroll.Kind := sbVertical; FVScroll.OnChange := ScrollChanged;
  FWaveTimer := TTimer.Create(Self); FWaveTimer.Interval := 80; FWaveTimer.OnTimer := WaveTimer;
end;

destructor TMusicStudioArrangementView.Destroy;
begin
  FWaveTimer.Enabled := False; FWaveTimer.OnTimer := nil; FDocument := nil;
  FPerformanceCache.Free; FVisualCache.Free; FWaveCache.Free; inherited;
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
  Result := True;
  if not Track.HasCapabilityMetadata then Exit;
  if not (MusicStudioSmallSlot(Track.Slots[SlotIndex].Kind) or (Track.Slots[SlotIndex].Kind='singing') or (Track.Slots[SlotIndex].Kind='performance')) then Exit;
  Result := False; for K in Track.ProvidedSlots do if K=Track.Slots[SlotIndex].Kind then Exit(True);
end;
function TMusicStudioArrangementView.SummaryOffset(const Track: TMusicStudioTrack; SlotIndex: Integer): Integer;
var I: Integer;
begin Result := 0; for I := 0 to SlotIndex-1 do if SlotVisible(Track,I) then Inc(Result,Scale(48)); end;
function TMusicStudioArrangementView.SlotHeight(const Kind: string): Integer;
begin
  if (Kind='singing') or (Kind='performance') then Result := Scale(104)
  else if MusicStudioSmallSlot(Kind) then Result := Scale(28)
  else if Kind='psd' then Result := Scale(32) else Result := RowHeight;
end;
function TMusicStudioArrangementView.RowSize(Index: Integer): Integer;
var T: TMusicStudioTrack;
begin
  T := FDocument.TrackAt(FRows[Index].TrackIndex);
  if FRows[Index].SlotIndex>=0 then Exit(SlotHeight(T.Slots[FRows[Index].SlotIndex].Kind));
  Result := RowHeight;
  if T.Kind='psd' then Result := Scale(104);
  if (FRows[Index].SlotIndex < 0) and not TrackExpanded(FRows[Index].TrackIndex) then begin
    Result := Max(Result,SummaryOffset(T,Length(T.Slots)));
  end;
end;
function TMusicStudioArrangementView.RowTop(Index: Integer): Integer;
var I: Integer;
begin
  Result := RulerHeight-FVScroll.Position;
  for I := 0 to Index-1 do Inc(Result,RowSize(I));
end;
function TMusicStudioArrangementView.TrackExpanded(Index: Integer): Boolean;
begin Result := Index = FExpandedTrack; end;
procedure TMusicStudioArrangementView.ToggleTrack(Index: Integer);
begin
  if not Assigned(FDocument) or (Index < 0) or (Index >= FDocument.TrackCount) then Exit;
  if TrackExpanded(Index) then FExpandedTrack := -1 else FExpandedTrack := Index;
  if FSelectedTrack<>Index then begin
    FSelectedTrack := Index;
    if Length(FDocument.TrackAt(Index).Slots)>0 then FSelectedSlot := 0 else FSelectedSlot := -1;
  end;
  FSelectedClip := -1; Refresh;
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
function TMusicStudioArrangementView.HeaderWidth: Integer;
begin Result := Scale(180); end;
function TMusicStudioArrangementView.RulerHeight: Integer;
begin Result := Scale(32); end;
function TMusicStudioArrangementView.RowHeight: Integer;
begin Result := Scale(58); end;

procedure TMusicStudioArrangementView.Bind(Document: TMusicStudioDocument);
begin
  FDocument := nil; FRows := nil; FEmotionItems := nil;
  FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1; FExpandedTrack := -1;
  CancelInteraction;
  FWaveCache.Clear;
  FVisualCache.Clear;
  FDocument := Document; FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1;
  if Assigned(Document) and (Document.TrackCount > 0) then begin
    FSelectedTrack := 0;
    if Length(Document.TrackAt(0).Slots)>0 then FSelectedSlot := 0;
  end;
  FExpandedTrack := FSelectedTrack;
  FVScroll.Position := 0; Refresh;
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
var I,J,N,TrackCount,HeightUsed: Integer; T: TMusicStudioTrack; S: TMusicStudioSlot; C: TMusicStudioPlacement; EndTime: Double;
begin
  EndTime := 60; TrackCount := 0; FRows := nil;
  if Assigned(FDocument) then TrackCount := FDocument.TrackCount;
  if FSelectedTrack >= TrackCount then begin FSelectedTrack := -1; FSelectedSlot := -1; FSelectedClip := -1; end;
  if FExpandedTrack >= TrackCount then FExpandedTrack := -1;
  if Assigned(FDocument) then begin
    if FSelectedTrack >= 0 then begin
      T := FDocument.TrackAt(FSelectedTrack);
      if FSelectedSlot >= Length(T.Slots) then begin FSelectedSlot := -1; FSelectedClip := -1; end;
      if (FSelectedSlot>=0) and not SlotVisible(T,FSelectedSlot) then begin FSelectedSlot := -1; FSelectedClip := -1; end;
      if FSelectedSlot >= 0 then if FSelectedClip >= Length(T.Slots[FSelectedSlot].Clips) then FSelectedClip := -1;
    end;
    for I := 0 to TrackCount - 1 do begin
      T := FDocument.TrackAt(I);
      N := Length(FRows); SetLength(FRows,N+1); FRows[N].TrackIndex := I; FRows[N].SlotIndex := -1;
      for S in T.Slots do for C in S.Clips do EndTime := Max(EndTime,C.StartSeconds+C.LengthSeconds+30);
      if TrackExpanded(I) then begin
        for J := 0 to High(T.Slots) do begin
          if not SlotVisible(T,J) then Continue;
          N := Length(FRows); SetLength(FRows,N+1); FRows[N].TrackIndex := I; FRows[N].SlotIndex := J;
        end;
      end;
    end;
  end;
  if FDocument<>nil then FHScroll.Max := Min(MaxInt-1024,Ceil(FDocument.SecondsToBeat(EndTime)*64)) else FHScroll.Max := 0;
  HeightUsed := 0;
  for I := 0 to High(FRows) do Inc(HeightUsed,RowSize(I));
  FVScroll.Max := Max(0,HeightUsed-Max(1,ClientHeight-RulerHeight-Scale(17)));
  FVScroll.SmallChange := RowHeight;
  FVScroll.LargeChange := Max(1,ClientHeight-RulerHeight-Scale(17));
  FVScroll.Visible := FVScroll.Max > 0;
  if Assigned(FWaveCache) then SyncWaveSources;
  if Assigned(FPerformanceCache) then FPerformanceCache.SetPatterns(FDocument);
  Invalidate;
end;

procedure TMusicStudioArrangementView.SelectTrack(Index: Integer);
begin
  if not Assigned(FDocument) or (Index < 0) or (Index >= FDocument.TrackCount) then Exit;
  FExpandedTrack := Index;
  if FSelectedTrack<>Index then begin
    FSelectedTrack := Index;
    if Length(FDocument.TrackAt(Index).Slots)>0 then FSelectedSlot := 0 else FSelectedSlot := -1;
  end;
  FSelectedClip := -1; Refresh;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;
procedure TMusicStudioArrangementView.SelectSlot(TrackIndex,SlotIndex: Integer);
var I,Top: Integer;
begin
  if not Assigned(FDocument) or (TrackIndex < 0) or (TrackIndex >= FDocument.TrackCount) then Exit;
  SelectTrack(TrackIndex);
  if (SlotIndex < 0) or (SlotIndex >= Length(FDocument.TrackAt(TrackIndex).Slots)) then Exit;
  FSelectedSlot := SlotIndex;
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
begin Result := SlotRowTop(TrackIndex,-1); end;
function TMusicStudioArrangementView.TrackThumbnailRect(TrackIndex: Integer): TRect;
var Y: Integer;
begin
  Result := Rect(0,0,0,0);
  if (FDocument=nil) or (TrackIndex<0) or (TrackIndex>=FDocument.TrackCount) then Exit;
  if FDocument.TrackAt(TrackIndex).Kind<>'psd' then Exit;
  Y := TrackRowTop(TrackIndex); Result := Rect(Scale(8),Y+Scale(34),Scale(76),Y+Scale(100));
end;
function TMusicStudioArrangementView.SlotThumbnailRect(TrackIndex,SlotIndex: Integer): TRect;
begin
  // 旧公開入口は残し、PSD画像はトラック見出しへ集約する。
  Result := Rect(0,0,0,0);
end;

procedure TMusicStudioArrangementView.SetZoom(PixelsPerSecond: Double);
begin CancelInteraction; FPixelsPerSecond := EnsureRange(PixelsPerSecond,10.0,1536.0); SyncWaveSources; Invalidate; end;
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
var I,J: Integer; T: TMusicStudioTrack;
begin
  Result := -1; I := RowAtPoint(X,Y); if I < 0 then Exit;
  Result := FRows[I].SlotIndex;
  if (Result < 0) and (X >= HeaderWidth) and not TrackExpanded(FRows[I].TrackIndex) then begin
    T := FDocument.TrackAt(FRows[I].TrackIndex);
    for J := 0 to High(T.Slots) do if SlotVisible(T,J) and
      (Y-RowTop(I)>=SummaryOffset(T,J)) and (Y-RowTop(I)<SummaryOffset(T,J)+Scale(48)) then Exit(J);
  end;
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
  if not TrackExpanded(TrackIndex) then begin
    H := Scale(48); Y := TrackRowTop(TrackIndex)+SummaryOffset(Track,SlotIndex);
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
  FrameColor := $00606060;
  if (TrackIndex = FSelectedTrack) and (SlotIndex = FSelectedSlot) and (ClipIndex = FSelectedClip) then FrameColor := clWhite;
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Area.Left,Area.Top,Area.Right,Area.Bottom);
    Canvas.Brush.Color := TitleColor; Canvas.Pen.Color := FrameColor;
    Canvas.Rectangle(R);
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := ClipTextColor(TitleColor);
    if MusicStudioSmallSlot(T.Slots[SlotIndex].Kind) and not Summary then begin
      TextRect := R; Inc(TextRect.Left,Scale(6)); Inc(TextRect.Top,Scale(4));
      DrawLabel(Canvas,TextRect,P.Name); Exit;
    end;
    TextRect := R; TextRect.Left := Max(Area.Left+Scale(4),R.Left+Scale(7));
    TextRect.Right := Min(Area.Right,R.Right-Scale(4)); TextRect.Top := R.Top+Scale(1);
    TextRect.Bottom := R.Top+Scale(16);
    Detail := P.Name;
    if Summary and (Length(T.Slots) > 1) then Detail := Format('%d:%s / %s',[SlotIndex+1,T.Slots[SlotIndex].Name,P.Name]);
    DrawLabel(Canvas,TextRect,Detail);
    WaveRect := R; Inc(WaveRect.Left); Dec(WaveRect.Right);
    WaveRect.Top := TextRect.Bottom; Dec(WaveRect.Bottom);
    Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := Background; Canvas.FillRect(WaveRect);
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
      if Detail='' then DrawMusicStudioTimelineContent(Canvas,Metrics,C,P,WaveRect,Area,FWaveCache,FVisualCache,FPerformanceCache,CurrentPPI,Background,Foreground)
      else begin TextRect.Top := WaveRect.Top; TextRect.Bottom := WaveRect.Bottom; DrawLabel(Canvas,TextRect,Detail); end;
    end else if P.Kind='performance' then begin
      // 大型枠の本文は将来の演奏内容表示用に確保する。
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
    Canvas.Brush.Style := bsClear; Canvas.Pen.Color := FrameColor; Canvas.Rectangle(R);
    if (R.Width>0) and (TrackIndex=FSelectedTrack) and (SlotIndex=FSelectedSlot) and (ClipIndex=FSelectedClip) then begin
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

procedure TMusicStudioArrangementView.Paint;
var
  I, J, K, Y, H, LabelY, TextRight, X, Saved, SavedHeader, SavedRow,TrackIndex,SlotIndex,NextLabelX: Integer;
  T: TMusicStudioTrack;
  Slot: TMusicStudioSlot;
  Area: TRect; Detail: string; Beat,LastBeat,BeatStep,Factor,NextMeasureBeat: Double;
  Visual: TMusicStudioVisualSource; Thumb: TBitmap; ThumbRect: TRect; HeaderColor: TColor;
begin
  Canvas.Brush.Color := $00232323; Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font); Canvas.Font.Color := $00BFBFBF;
  Canvas.Brush.Color := $00313131; Canvas.FillRect(Rect(0,0,ClientWidth,RulerHeight));
  DrawLabel(Canvas,Rect(Scale(14),Scale(7),HeaderWidth - 4,RulerHeight),'トラック  /  右クリック');
  Area := Rect(HeaderWidth,RulerHeight,FVScroll.Left,FHScroll.Top);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle,Area.Left,0,Area.Right,Area.Bottom);
    if FDocument<>nil then begin
      BeatStep := RulerBeatStep; Beat := Floor(Metrics.FirstBeat/BeatStep)*BeatStep;
      LastBeat := Metrics.BeatAtX(Area.Right); NextLabelX := Area.Left;
      while Beat<=LastBeat+BeatStep do begin
        X := Metrics.XAtBeat(Beat); Canvas.Pen.Color := $003A3A3A;
        if Abs(FDocument.Timing.BeatInMeasure(Beat))<1E-8 then Canvas.Pen.Color := $00605A50;
        Canvas.MoveTo(X,RulerHeight); Canvas.LineTo(X,Area.Bottom);
        if X>=NextLabelX then begin
          DrawLabel(Canvas,Rect(X+Scale(4),Scale(7),X+Scale(88),RulerHeight),Metrics.BeatLabel(Beat)); NextLabelX := X+Scale(64);
        end;
        NextMeasureBeat := FDocument.Timing.MeasureStart(FDocument.Timing.MeasureAtBeat(Beat)+1);
        if (NextMeasureBeat>Beat+1E-8) and (NextMeasureBeat<Beat+BeatStep) and
          (Metrics.PixelsPerBeat*FDocument.Timing.MeasureLengthAtBeat(Beat)>=12) then Beat := NextMeasureBeat
        else Beat := Beat+BeatStep;
      end;
    end;
  finally RestoreDC(Canvas.Handle,Saved); end;
  if not Assigned(FDocument) or (FDocument.TrackCount = 0) then begin
    Canvas.Brush.Style := bsClear;
    DrawLabel(Canvas,Rect(HeaderWidth + Scale(24),RulerHeight + Scale(30),ClientWidth - Scale(30),FHScroll.Top),
      '「トラック＋」から音声 / PSDトラックを追加し、左のパターンをドラッグします。', DT_WORDBREAK);
    Canvas.Brush.Style := bsSolid; PaintPlayhead; Exit;
  end;
  for I := 0 to High(FRows) do begin
    Y := RowTop(I); H := RowSize(I);
    if Y >= FHScroll.Top then Break;
    if Y+H <= RulerHeight then Continue;
    TrackIndex := FRows[I].TrackIndex; SlotIndex := FRows[I].SlotIndex;
    T := FDocument.TrackAt(TrackIndex);
    SavedRow := SaveDC(Canvas.Handle);
    try
    IntersectClipRect(Canvas.Handle,0,RulerHeight,Area.Right,Area.Bottom);
    SavedHeader := SaveDC(Canvas.Handle);
    IntersectClipRect(Canvas.Handle,0,RulerHeight,HeaderWidth,Area.Bottom);
    LabelY := Max(Y,RulerHeight);
    if (TrackIndex = FSelectedTrack) and (SlotIndex = FSelectedSlot) and (SlotIndex >= 0) then Canvas.Brush.Color := $00564D41
    else if TrackIndex = FSelectedTrack then Canvas.Brush.Color := $00433F38 else Canvas.Brush.Color := $002D2D2D;
    HeaderColor := Canvas.Brush.Color; TextRight := HeaderWidth-Scale(8);
    if SlotIndex<0 then ThumbRect := TrackThumbnailRect(TrackIndex) else ThumbRect := Rect(0,0,0,0);
    Canvas.FillRect(Rect(0,Y,HeaderWidth,Y + H));
    if SlotIndex >= 0 then begin Slot := T.Slots[SlotIndex]; Detail := Slot.Color; end else Detail := T.Color;
    Canvas.Brush.Color := RGBColor(Detail); Canvas.FillRect(Rect(0,Y,Scale(4),Y + H));
    Canvas.Brush.Style := bsClear; Canvas.Font.Color := $00EEEEEE;
    if SlotIndex < 0 then begin
      if TrackExpanded(TrackIndex) then Detail := '▼ '+T.Name else Detail := '▶ '+T.Name;
    end else Detail := '  '+Slot.Name;
    DrawLabel(Canvas,Rect(Scale(14),LabelY + Min(Scale(10),Max(Scale(3),(H-Scale(18)) div 2)),TextRight,LabelY + H),Detail);
    Canvas.Font.Color := $00AAAAAA;
    if SlotIndex<0 then begin
      if T.Kind='psd' then begin
        DrawLabel(Canvas,Rect(Scale(84),LabelY+Scale(36),TextRight,LabelY+Scale(60)),PerformanceKindName(T.PerformanceAttribute));
        Detail := 'PSD未割当';
        if FSceneCache<>nil then Detail := FSceneCache.StatusForTrack(TrackIndex)
        else if T.PsdPath<>'' then Detail := '演奏者';
        DrawLabel(Canvas,Rect(Scale(84),LabelY+Scale(64),TextRight,LabelY+Scale(100)),Detail);
      end else DrawLabel(Canvas,Rect(Scale(14),LabelY+Scale(36),TextRight,LabelY+H),'音楽');
    end;
    if not IsRectEmpty(ThumbRect) then begin
      Visual := FVisualCache.Find(vkPsd,T.PsdPath);
      Thumb := FVisualCache.Thumbnail(Visual,ThumbRect.Width,ThumbRect.Height,CurrentPPI,HeaderColor);
      if Assigned(FSceneCache) and Assigned(FSceneCache.ImageForTrack(TrackIndex)) then Thumb := FSceneCache.ImageForTrack(TrackIndex);
      if Assigned(Thumb) then begin
        Factor := Min(ThumbRect.Width/Thumb.Width,ThumbRect.Height/Thumb.Height);
        ThumbRect := Rect(ThumbRect.Left+(ThumbRect.Width-Round(Thumb.Width*Factor)) div 2,
          ThumbRect.Top+(ThumbRect.Height-Round(Thumb.Height*Factor)) div 2,
          ThumbRect.Left+(ThumbRect.Width+Round(Thumb.Width*Factor)) div 2,
          ThumbRect.Top+(ThumbRect.Height+Round(Thumb.Height*Factor)) div 2);
        Canvas.StretchDraw(ThumbRect,Thumb);
      end;
    end;
    Canvas.Brush.Style := bsSolid;
    RestoreDC(Canvas.Handle,SavedHeader); Canvas.Refresh;
    if SlotIndex < 0 then begin
      if not TrackExpanded(TrackIndex) and (Length(T.Slots) > 0) then begin
        for K := 0 to High(T.Slots) do begin
          if not SlotVisible(T,K) then Continue;
          if Length(T.Slots[K].Clips) = 0 then begin
            Canvas.Brush.Style := bsClear; Canvas.Font.Color := $007C7C7C;
            DrawLabel(Canvas,Rect(HeaderWidth+Scale(8),Max(RulerHeight,Y+SummaryOffset(T,K))+Scale(10),Area.Right,
              Min(Area.Bottom,Y+SummaryOffset(T,K)+Scale(48))),Format('%d:%s（空）',[K+1,T.Slots[K].Name]));
            Canvas.Brush.Style := bsSolid;
          end;
          for J := 0 to High(T.Slots[K].Clips) do PaintClip(TrackIndex,K,J,Area,True);
          if Length(T.Slots) > 1 then begin
            Canvas.Pen.Color := $00444444;
            Canvas.MoveTo(HeaderWidth,Y+SummaryOffset(T,K)+Scale(48)); Canvas.LineTo(Area.Right,Y+SummaryOffset(T,K)+Scale(48));
          end;
        end;
      end else begin
        Canvas.Brush.Style := bsClear; Canvas.Font.Color := $007C7C7C;
        Detail := 'スロット＋ / 右クリックで種類別の枠を追加できます。';
        DrawLabel(Canvas,Rect(HeaderWidth+Scale(14),Y+Scale(20),Area.Right,Y+H),Detail);
        Canvas.Brush.Style := bsSolid;
      end;
      Continue;
    end;
    Saved := SaveDC(Canvas.Handle);
    try
      IntersectClipRect(Canvas.Handle,Area.Left,Area.Top,Area.Right,Area.Bottom);
      for J := 0 to High(Slot.Clips) do PaintClip(TrackIndex,SlotIndex,J,Area,False);
      Canvas.Pen.Color := $00444444; Canvas.MoveTo(0,Y + H); Canvas.LineTo(ClientWidth,Y + H);
    finally RestoreDC(Canvas.Handle,Saved); end;
    finally RestoreDC(Canvas.Handle,SavedRow); Canvas.Refresh; end;
  end;
  PaintPlayhead;
end;

function TMusicStudioArrangementView.EmotionResizeEdgeAt(X,Y: Integer): Integer;
var T: TMusicStudioTrack; C: TMusicStudioPlacement; P: TMusicStudioPattern; R: TRect; Grip: Integer;
begin
  Result := 0;
  if (FDocument=nil) or (FSelectedTrack<0) or (FSelectedSlot<0) or (FSelectedClip<0) then Exit;
  T := FDocument.TrackAt(FSelectedTrack);
  if (FSelectedSlot>=Length(T.Slots)) or (FSelectedClip>=Length(T.Slots[FSelectedSlot].Clips)) then Exit;
  C := T.Slots[FSelectedSlot].Clips[FSelectedClip];
  if not FindPattern(C.PatternID,P) then Exit;
  R := ClipRect(FSelectedTrack,FSelectedSlot,C);
  if ClipAtPoint(X,Y)<>FSelectedClip then Exit;
  if (X<HeaderWidth) or (X>=FVScroll.Left) or (Y<RulerHeight) or (Y>=FHScroll.Top) or not PtInRect(R,Point(X,Y)) then Exit;
  Grip := Min(Scale(7),Max(1,(R.Width-1) div 3));
  if X-R.Left<Grip then Result := -1 else if R.Right-1-X<Grip then Result := 1;
end;
function TMusicStudioArrangementView.CancelInteraction: Boolean;
begin
  Result := FDragging; FDragging := False; FDragStarted := False; FResizeEdge := 0;
  MouseCapture := False; Cursor := crDefault; if Result then Invalidate;
end;
procedure TMusicStudioArrangementView.WMCaptureChanged(var Message: TMessage);
begin inherited; if FDragging and (HWND(Message.LParam)<>Handle) then PostMessage(Handle,WM_APP+107,0,0); end;
procedure TMusicStudioArrangementView.WMDeferredCaptureLost(var Message: TMessage);
begin if FDragging and (GetCapture<>Handle) then CancelInteraction; end;
procedure TMusicStudioArrangementView.WMCancelMode(var Message: TMessage);
begin inherited; if FDragging then CancelInteraction; end;
procedure TMusicStudioArrangementView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key=VK_ESCAPE) and CancelInteraction then Key := 0;
  inherited;
end;
procedure TMusicStudioArrangementView.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var T: TMusicStudioTrack; TrackIndex,SlotIndex,ClipIndex,Edge: Integer;
begin
  inherited;
  CancelInteraction;
  if (Button=mbRight) and (Y<RulerHeight) and (X>=HeaderWidth) then Exit;
  if (Button=mbLeft) and (Y<RulerHeight) and (X>=HeaderWidth) then begin
    if Assigned(FOnSeek) then FOnSeek(SecondsAtPoint(X)); Exit;
  end;
  TrackIndex := TrackAtPoint(X,Y); SlotIndex := SlotAtPoint(X,Y); ClipIndex := ClipAtPoint(X,Y);
  if (Button = mbLeft) and (X < HeaderWidth) and (SlotIndex < 0) and not (ssDouble in Shift) then begin
    ToggleTrack(TrackIndex); Exit;
  end;
  FSelectedTrack := TrackIndex; FSelectedSlot := SlotIndex; FSelectedClip := ClipIndex; Refresh;
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
  end;
  Invalidate;
end;

procedure TMusicStudioArrangementView.DblClick;
begin
  FDragging := False; FDragStarted := False; MouseCapture := False;
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
  if (MousePos.Y>=0) and (MousePos.Y<RulerHeight) and (MousePos.X>=HeaderWidth) and Assigned(FOnTempoMenu) then begin
    CancelInteraction; FOnTempoMenu(Metrics.BeatAtX(MousePos.X)); Handled := True;
  end else begin
    TrackIndex := TrackAtPoint(MousePos.X,MousePos.Y); SlotIndex := SlotAtPoint(MousePos.X,MousePos.Y);
    if (FDocument<>nil) and (TrackIndex>=0) and (SlotIndex>=0) and (MousePos.X>=HeaderWidth) and Assigned(FOnSmallMenu) then
      if MusicStudioSmallSlot(FDocument.TrackAt(TrackIndex).Slots[SlotIndex].Kind) then begin
        CancelInteraction; Handled := True;
        FOnSmallMenu(TrackIndex,SlotIndex,ClipAtPoint(MousePos.X,MousePos.Y),SecondsAtSlot(MousePos.X,TrackIndex,SlotIndex),ClientToScreen(MousePos)); Exit;
      end;
    inherited;
  end;
end;

procedure TMusicStudioArrangementView.MouseMove(Shift: TShiftState; X,Y: Integer);
var EdgeBeat,EdgeTime,EndTime,MinimumLength,StartBeat,EndBeat: Double; Clip: TMusicStudioPlacement;
begin
  inherited;
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
      if FResizeEdge<0 then begin
        FProposedStart := EnsureRange(EdgeTime,0.0,Max(0.0,EndTime-MinimumLength));
        FProposedLength := Max(MinimumLength,EndTime-FProposedStart);
      end else begin
        FProposedStart := FOriginalStart;
        FProposedLength := Max(MinimumLength,EnsureRange(EdgeTime,FOriginalStart+MinimumLength,604800.0)-FOriginalStart);
      end;
      Cursor := crSizeWE; Invalidate; Exit;
    end;
    Clip := FDocument.TrackAt(FMovingTrack).Slots[FMovingSlot].Clips[FMovingClip];
    StartBeat := Metrics.SnapBeat(Max(0.0,Metrics.BeatAtX(X)-FMouseOffset));
    FProposedStart := EnsureRange(FDocument.BeatToSeconds(StartBeat),0.0,604800.0-FOriginalLength);
    FProposedLength := FOriginalLength;
    if Clip.TimeBase='beats' then begin
      EndBeat := StartBeat+Clip.LengthBeats; FProposedLength := FDocument.BeatToSeconds(EndBeat)-FProposedStart;
    end;
    Invalidate;
  end else if EmotionResizeEdgeAt(X,Y)<>0 then Cursor := crSizeWE else Cursor := crDefault;
end;

procedure TMusicStudioArrangementView.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if (Button <> mbLeft) or not FDragging then Exit;
  MouseMove(Shift,X,Y);
  if not FDragStarted then begin CancelInteraction; Exit; end;
  FDragging := False; FDragStarted := False; MouseCapture := False;
  if FResizeEdge<>0 then begin
    if Assigned(FOnClipResize) then FOnClipResize(FMovingTrack,FMovingSlot,FMovingClip,FProposedStart,FProposedLength);
  end else if Assigned(FOnClipMove) then FOnClipMove(FMovingTrack,FMovingSlot,FMovingClip,FProposedStart);
  FResizeEdge := 0; Cursor := crDefault;
  Invalidate;
end;

end.
