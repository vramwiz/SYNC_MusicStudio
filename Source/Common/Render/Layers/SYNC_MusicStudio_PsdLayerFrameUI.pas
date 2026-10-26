// Builds the PSD-specific controls; common pattern name and color live in the caller.
unit SYNC_MusicStudio_PsdLayerFrameUI;

interface

uses System.Classes, System.Types, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Menus;

type
  TMusicStudioPsdLayerList = class(TListBox)
  private
    FChecks: TArray<Boolean>;
    FCheckMode: Boolean;
    FOnClickCheck: TNotifyEvent;
    function GetChecked(Index: Integer): Boolean;
    procedure SetChecked(Index: Integer; Value: Boolean);
    procedure ToggleCheck;
  protected
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    property Checked[Index: Integer]: Boolean read GetChecked write SetChecked;
    property CheckMode: Boolean read FCheckMode write FCheckMode;
    property OnClickCheck: TNotifyEvent read FOnClickCheck write FOnClickCheck;
    property OnMouseWheel;
  end;
  TMusicStudioPsdPreviewSurface = class(TCustomControl)
  private
    FOnPaint, FOnCaptureLost: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMCaptureChanged(var Message: TMessage); message WM_CAPTURECHANGED;
    procedure WMCancelMode(var Message: TMessage); message WM_CANCELMODE;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Canvas;
    property DoubleBuffered;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property OnCaptureLost: TNotifyEvent read FOnCaptureLost write FOnCaptureLost;
    property OnMouseWheel;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnDblClick;
    property OnResize;
  end;
  TMusicStudioPsdLayerControls = record
    Header, Toolbar, Footer, LeftPane: TPanel;
    PathLabel, StateLabel, HintLabel, MappingLabel, SelectionLabel: TLabel;
    LayerList: TMusicStudioPsdLayerList;
    MouthCombo: TComboBox;
    AssignButton, ClearButton, ReloadButton, CancelButton: TButton;
    MouthMenu: TPopupMenu;
    PreviewPane, PreviewToolbar: TPanel;
    FitButton: TButton;
    ZoomLabel: TLabel;
    Preview: TMusicStudioPsdPreviewSurface;
  end;

procedure BuildMusicStudioPsdLayerControls(Frame: TFrame; out UI: TMusicStudioPsdLayerControls);
procedure SetMusicStudioPsdLayerMode(var UI: TMusicStudioPsdLayerControls; ExpressionMode: Boolean);

implementation

uses System.SysUtils,
  SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;

function TMusicStudioPsdLayerList.GetChecked(Index: Integer): Boolean;
begin Result := (Index>=0) and (Index<Length(FChecks)) and FChecks[Index]; end;
procedure TMusicStudioPsdLayerList.SetChecked(Index: Integer; Value: Boolean);
begin
  if (Index<0) or (Index>=Items.Count) then Exit;
  if Length(FChecks)<>Items.Count then SetLength(FChecks,Items.Count);
  if FChecks[Index]<>Value then begin FChecks[Index] := Value; Invalidate; end;
end;
procedure TMusicStudioPsdLayerList.ToggleCheck;
begin
  if not FCheckMode or (ItemIndex<0) then Exit;
  Checked[ItemIndex] := not Checked[ItemIndex];
  if Assigned(FOnClickCheck) then FOnClickCheck(Self);
end;
procedure TMusicStudioPsdLayerList.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var I: Integer;
begin
  inherited;
  if FCheckMode and (Button=mbLeft) and (X<MulDiv(20,Abs(Font.Height),13)) then begin
    I := ItemAtPos(Point(X,Y),True); if I>=0 then begin ItemIndex := I; ToggleCheck; end;
  end;
end;
procedure TMusicStudioPsdLayerList.KeyDown(var Key: Word; Shift: TShiftState);
begin inherited; if FCheckMode and (Key=VK_SPACE) then begin ToggleCheck; Key := 0; end; end;
constructor TMusicStudioPsdPreviewSurface.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ParentBackground := False; TabStop := True;
  // The preview owns native capture; avoid VCL's separate automatic click capture.
  ControlStyle := ControlStyle-[csCaptureMouse];
end;
procedure TMusicStudioPsdPreviewSurface.Paint;
begin if Assigned(FOnPaint) then FOnPaint(Self); end;
procedure TMusicStudioPsdPreviewSurface.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin Message.Result := 1; end;
procedure TMusicStudioPsdPreviewSurface.WMCaptureChanged(var Message: TMessage);
begin inherited; if (HWND(Message.LParam)<>Handle) and Assigned(FOnCaptureLost) then FOnCaptureLost(Self); end;
procedure TMusicStudioPsdPreviewSurface.WMCancelMode(var Message: TMessage);
begin inherited; if Assigned(FOnCaptureLost) then FOnCaptureLost(Self); end;

procedure TMusicStudioPsdLayerList.CMDialogKey(var Message: TCMDialogKey);
var Key: Word;
begin
  if Message.CharCode=VK_RETURN then begin
    Key := VK_RETURN; KeyDown(Key,[]);
    if Key=0 then begin Message.Result := 1; Exit; end;
  end;
  inherited;
end;

function Panel(Frame: TFrame; Parent: TWinControl; Align: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Frame); Result.Parent := Parent; Result.BevelOuter := bvNone;
  Result.ShowCaption := False; // Names identify containers; labels own all visible text.
  Result.Align := Align; if Align=alLeft then Result.Width := Size else Result.Height := Size;
  ApplySyncMusicStudioDarkPanel(Result);
end;

function LabelOn(Frame: TFrame; Parent: TWinControl; X,Y,W,H: Integer): TLabel;
begin
  Result := TLabel.Create(Frame); Result.Parent := Parent; Result.AutoSize := False;
  Result.SetBounds(X,Y,W,H); Result.Anchors := [akLeft,akTop,akRight];
  Result.WordWrap := True;
end;

function ButtonOn(Frame: TFrame; Parent: TWinControl; X,W: Integer; const Text: string): TButton;
begin
  Result := TMusicStudioButton.Create(Frame); Result.Parent := Parent;
  Result.SetBounds(X,4,W,28); Result.Caption := Text;
end;

procedure BuildMusicStudioPsdLayerControls(Frame: TFrame; out UI: TMusicStudioPsdLayerControls);
var Splitter: TSplitter;
begin
  UI := Default(TMusicStudioPsdLayerControls);
  UI.Header := Panel(Frame,Frame,alTop,70); UI.Header.Top := 0;
  UI.Header.Name := 'PsdHeader';
  UI.PathLabel := LabelOn(Frame,UI.Header,12,4,Frame.Width-24,24);
  UI.PathLabel.WordWrap := False; UI.PathLabel.EllipsisPosition := epPathEllipsis;
  UI.PathLabel.ShowHint := True;
  UI.StateLabel := LabelOn(Frame,UI.Header,12,31,Frame.Width-24,34);
  UI.Toolbar := Panel(Frame,Frame,alTop,38); UI.Toolbar.Top := 70;
  UI.Toolbar.Name := 'PsdToolbar';
  UI.MouthCombo := TComboBox.Create(Frame); UI.MouthCombo.Parent := UI.Toolbar;
  UI.MouthCombo.Name := 'PsdMouthCombo';
  UI.MouthCombo.SetBounds(12,5,136,26); UI.MouthCombo.Style := csDropDownList;
  UI.MouthCombo.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  UI.MouthCombo.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR;
  UI.AssignButton := ButtonOn(Frame,UI.Toolbar,12,142,'母音へ割当…');
  UI.AssignButton.Name := 'PsdAssignButton';
  UI.ClearButton := ButtonOn(Frame,UI.Toolbar,162,128,'確認母音を解除');
  UI.ClearButton.Name := 'PsdClearButton';
  UI.ReloadButton := ButtonOn(Frame,UI.Toolbar,368,84,'再読込');
  UI.ReloadButton.Name := 'PsdReloadButton';
  UI.CancelButton := ButtonOn(Frame,UI.Toolbar,460,84,'読込取消');
  UI.CancelButton.Name := 'PsdCancelButton';
  UI.MouthCombo.Hint := '表示確認する母音。割当は先にレイヤーを選び、右クリックから選びます。';
  UI.MouthCombo.ShowHint := True;
  UI.MouthMenu := TPopupMenu.Create(Frame);
  UI.Footer := Panel(Frame,Frame,alBottom,89);
  UI.SelectionLabel := LabelOn(Frame,UI.Footer,12,3,Frame.Width-24,22);
  UI.SelectionLabel.WordWrap := False; UI.SelectionLabel.EllipsisPosition := epEndEllipsis;
  UI.SelectionLabel.ShowHint := True;
  UI.MappingLabel := LabelOn(Frame,UI.Footer,12,25,Frame.Width-24,22);
  UI.MappingLabel.WordWrap := False; UI.MappingLabel.EllipsisPosition := epEndEllipsis;
  UI.MappingLabel.ShowHint := True;
  UI.HintLabel := LabelOn(Frame,UI.Footer,12,49,Frame.Width-24,34);
  UI.LeftPane := Panel(Frame,Frame,alLeft,270); UI.LeftPane.Constraints.MinWidth := 170;
  UI.LayerList := TMusicStudioPsdLayerList.Create(Frame); UI.LayerList.Parent := UI.LeftPane;
  UI.LayerList.Align := alClient; UI.LayerList.Color := SYNC_MUSIC_STUDIO_DARK_CONTROL_COLOR;
  UI.LayerList.Font.Color := SYNC_MUSIC_STUDIO_DARK_TEXT_COLOR; UI.LayerList.ItemHeight := 24;
  UI.LayerList.Style := lbOwnerDrawFixed;
  UI.LayerList.Hint := '行を選ぶと表情をプレビュー。左列は割当母音、右クリックまたはEnterで割当を変更。完全な階層と割当はツールチップで確認できます。';
  UI.LayerList.ShowHint := True;
  Splitter := TSplitter.Create(Frame); Splitter.Parent := Frame;
  Splitter.Align := alLeft; Splitter.Left := 270; Splitter.Width := 6; Splitter.MinSize := 170;
  UI.PreviewPane := Panel(Frame,Frame,alClient,0);
  UI.PreviewToolbar := Panel(Frame,UI.PreviewPane,alTop,34);
  UI.FitButton := ButtonOn(Frame,UI.PreviewToolbar,8,100,'全体表示');
  UI.ZoomLabel := LabelOn(Frame,UI.PreviewToolbar,116,7,160,22);
  UI.Preview := TMusicStudioPsdPreviewSurface.Create(Frame); UI.Preview.Parent := UI.PreviewPane; UI.Preview.Align := alClient;
  UI.Preview.Hint := 'ホイールでカーソル基準の拡縮、左ドラッグで移動、ダブルクリックまたは全体表示で戻す。'; UI.Preview.ShowHint := True;
  SetMusicStudioPsdLayerMode(UI,False);
end;

procedure SetMusicStudioPsdLayerMode(var UI: TMusicStudioPsdLayerControls; ExpressionMode: Boolean);
begin
  UI.LayerList.CheckMode := ExpressionMode;
  UI.Toolbar.Visible := False;
  UI.MouthCombo.Visible := False; UI.AssignButton.Visible := False;
  UI.ClearButton.Visible := False; UI.ReloadButton.Visible := False; UI.CancelButton.Visible := False;
  if ExpressionMode then begin
    UI.ReloadButton.Left := 12; UI.CancelButton.Left := 104;
    UI.HintLabel.Caption := 'チェックした表示状態を表情として保存します。右クリックで再読込・読込取消。PSD原本は書き換えません。';
  end else begin
    UI.ReloadButton.Left := 368; UI.CancelButton.Left := 460;
    UI.HintLabel.Caption := '行選択で差分を排他的にプレビュー。右クリックで母音の割当・解除・表示確認。左列: 通常 / あ～ん / 小あ～小お。小さい母音の未割当は通常の同母音を使用。';
  end;
end;

end.
