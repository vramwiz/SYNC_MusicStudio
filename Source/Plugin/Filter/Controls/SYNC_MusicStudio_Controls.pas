unit SYNC_MusicStudio_Controls;

// 統合編集UIのネイティブボタン互換ダーク描画。クリック/フォーカス/ModalResultはVCLが管理する。
interface
uses System.Classes, System.Types, Vcl.StdCtrls, Vcl.Controls, Winapi.Messages;
const MUSIC_STUDIO_TEXT_HEIGHT = 13; // 96DPI: 従来の小さい本文12pxから1px拡大。
// フォーム/属性フレームの基準を共有し、子部品は親の書体/高さを継承する。
procedure ApplyMusicStudioEditorFont(Control: TControl);
// 無音は空、最大は全面。Y座標は下端を固定して上へ伸ばす。
function MusicStudioPeakFillRect(const Bounds: TRect; Peak: Single): TRect;
type
  TMusicStudioButton = class(TButton)
  private
    FHot: Boolean;
    procedure DrawItem(var Message: TWMDrawItem); message CN_DRAWITEM;
    procedure MouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure MouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure PrintClient(var Message: TMessage); message WM_PRINTCLIENT;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure SetButtonStyle(ADefault: Boolean); override;
  end;
implementation
uses Winapi.Windows, System.Math, Vcl.Graphics;
type TMusicStudioFontAccess = class(TControl);
procedure ApplyMusicStudioEditorFont(Control: TControl);
begin
  TMusicStudioFontAccess(Control).Font.Name := 'Yu Gothic UI';
  TMusicStudioFontAccess(Control).Font.Height := -MulDiv(MUSIC_STUDIO_TEXT_HEIGHT,Control.CurrentPPI,96);
end;
function MusicStudioPeakFillRect(const Bounds: TRect; Peak: Single): TRect;
begin
  Result := Bounds;
  if IsNan(Peak) or IsInfinite(Peak) then Peak := 0;
  Result.Top := Result.Bottom-Round(EnsureRange(Peak,0.0,1.0)*Max(0,Bounds.Height));
end;
procedure TMusicStudioButton.CreateParams(var Params: TCreateParams);
begin
  inherited; Params.Style := (Params.Style and not $000F) or BS_OWNERDRAW;
end;
procedure TMusicStudioButton.SetButtonStyle(ADefault: Boolean);
begin
  if HandleAllocated then SendMessage(Handle,BM_SETSTYLE,BS_OWNERDRAW,1);
end;
procedure TMusicStudioButton.MouseEnter(var Message: TMessage);
begin FHot := True; Invalidate; inherited; end;
procedure TMusicStudioButton.MouseLeave(var Message: TMessage);
begin FHot := False; Invalidate; inherited; end;
procedure TMusicStudioButton.PrintClient(var Message: TMessage);
var Item: TDrawItemStruct; DrawMessage: TWMDrawItem;
begin
  // VCLのGetFormImage/WM_PRINTでも実画面と同じowner drawボタンを描画する。
  FillChar(Item,SizeOf(Item),0); FillChar(DrawMessage,SizeOf(DrawMessage),0);
  Item.hDC := HDC(Message.WParam); Item.rcItem := ClientRect;
  if not Enabled then Item.itemState := ODS_DISABLED;
  if Focused then Item.itemState := Item.itemState or ODS_FOCUS;
  DrawMessage.DrawItemStruct := @Item; DrawItem(DrawMessage); Message.Result := 1;
end;
procedure TMusicStudioButton.DrawItem(var Message: TWMDrawItem);
var C: TCanvas; R: TRect; State: Cardinal;
begin
  C := TCanvas.Create;
  try
    C.Handle := Message.DrawItemStruct.hDC; R := Message.DrawItemStruct.rcItem;
    State := Message.DrawItemStruct.itemState;
    if State and ODS_SELECTED <> 0 then C.Brush.Color := $00595348
    else if FHot then C.Brush.Color := $004F4F4F else C.Brush.Color := $003B3B3B;
    C.Pen.Color := $00606060; C.Rectangle(R);
    C.Font.Assign(Font);
    if State and ODS_DISABLED <> 0 then C.Font.Color := $00808080 else C.Font.Color := $00E3E3E3;
    C.Brush.Style := bsClear;
    if State and ODS_SELECTED <> 0 then OffsetRect(R,1,1);
    DrawText(C.Handle,PChar(Caption),Length(Caption),R,DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    if State and ODS_FOCUS <> 0 then begin InflateRect(R,-4,-4); C.DrawFocusRect(R); end;
    C.Handle := 0;
  finally C.Free; end;
  Message.Result := 1;
end;
end.
