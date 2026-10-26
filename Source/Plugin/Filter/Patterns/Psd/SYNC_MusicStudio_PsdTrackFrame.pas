unit SYNC_MusicStudio_PsdTrackFrame;

// PSDトラックの外部参照UI。ヘッダーを読み取り検証するだけで元PSDへ書き込まない。
interface
uses System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Dialogs;
type
  TMusicStudioPsdTrackFrame = class(TFrame)
  private
    FPath: string;
    FDialog: TOpenDialog;
    FStatus: TLabel;
    procedure BrowseClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
  protected
    procedure SetParent(AParent: TWinControl); override;
  public
    PathEdit: TEdit;
    constructor Create(AOwner: TComponent); override;
    procedure SelectFile(const Path: string);
    property FilePath: string read FPath;
  end;
implementation
uses System.SysUtils, System.IOUtils, SYNC_MusicStudio_DarkTheme, SYNC_MusicStudio_Controls;
{$R *.dfm}
constructor TMusicStudioPsdTrackFrame.Create(AOwner: TComponent);
var B: TButton; L: TLabel;
begin
  inherited;
  ApplySyncMusicStudioDarkFrame(Self);
  ApplyMusicStudioEditorFont(Self);
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(16,12,600,22);
  L.Caption := 'このトラックに割り当てるPSD（1トラック / 1PSD）';
  PathEdit := TEdit.Create(Self); PathEdit.Parent := Self;
  PathEdit.SetBounds(16,42,Width - 236,26); PathEdit.Anchors := [akLeft,akTop,akRight];
  PathEdit.ReadOnly := True; ApplySyncMusicStudioDarkEdit(PathEdit);
  B := TMusicStudioButton.Create(Self); B.Parent := Self;
  B.SetBounds(Width - 212,41,100,28); B.Anchors := [akTop,akRight];
  B.Caption := 'PSDを選択…'; B.OnClick := BrowseClick;
  B := TMusicStudioButton.Create(Self); B.Parent := Self;
  B.SetBounds(Width - 104,41,88,28); B.Anchors := [akTop,akRight];
  B.Caption := '参照を解除'; B.OnClick := ClearClick;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self;
  FStatus.SetBounds(16,86,Width - 32,70); FStatus.AutoSize := False;
  FStatus.WordWrap := True; FStatus.Anchors := [akLeft,akTop,akRight];
  L := TLabel.Create(Self); L.Parent := Self; L.SetBounds(16,166,Width - 32,110);
  L.AutoSize := False; L.WordWrap := True; L.Anchors := [akLeft,akTop,akRight];
  L.Caption := '歌唱パターンを配置できます。PSD画像の描画と口レイヤー切替は未実装です。' + #13#10 +
    '必須レイヤー名は未確定のため検証条件にしていません。素材は参照のみで、PSDを編集しません。';
  FDialog := TOpenDialog.Create(Self); FDialog.Filter := 'Photoshop PSD (*.psd)|*.psd';
  FDialog.Options := [ofFileMustExist,ofPathMustExist,ofEnableSizing];
end;
procedure TMusicStudioPsdTrackFrame.SetParent(AParent: TWinControl);
var C: TComponent;
begin
  inherited; if AParent = nil then Exit;
  for C in Self do if C is TButton then ApplySyncMusicStudioDarkButton(TButton(C));
end;
procedure TMusicStudioPsdTrackFrame.BrowseClick(Sender: TObject);
begin
  FDialog.FileName := FPath;
  if FDialog.Execute then SelectFile(TPath.GetFullPath(FDialog.FileName));
end;
procedure TMusicStudioPsdTrackFrame.ClearClick(Sender: TObject);
begin SelectFile(''); end;
procedure TMusicStudioPsdTrackFrame.SelectFile(const Path: string);
var S: TFileStream; H: array[0..25] of Byte; W,Y: Cardinal; Ch, Depth, Mode: Word; I: Integer;
begin
  FPath := Path; PathEdit.Text := Path; PathEdit.Hint := Path; PathEdit.ShowHint := True;
  if Path = '' then begin FStatus.Caption := 'PSDは未選択です。歌唱配置とJSON保存は可能です。'; Exit; end;
  if not TFile.Exists(Path) then begin FStatus.Caption := '参照先のPSDが見つかりません。再選択してください。'; Exit; end;
  try
    S := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try S.ReadBuffer(H,SizeOf(H)); finally S.Free; end;
    if (H[0] <> Ord('8')) or (H[1] <> Ord('B')) or (H[2] <> Ord('P')) or (H[3] <> Ord('S')) or
      (H[4] <> 0) or (H[5] <> 1) then raise Exception.Create('PSDバージョン1のヘッダーではありません。');
    for I := 6 to 11 do if H[I] <> 0 then raise Exception.Create('PSD予約領域が不正です。');
    Ch := (Word(H[12]) shl 8) or H[13];
    Y := (Cardinal(H[14]) shl 24) or (Cardinal(H[15]) shl 16) or (Cardinal(H[16]) shl 8) or H[17];
    W := (Cardinal(H[18]) shl 24) or (Cardinal(H[19]) shl 16) or (Cardinal(H[20]) shl 8) or H[21];
    Depth := (Word(H[22]) shl 8) or H[23]; Mode := (Word(H[24]) shl 8) or H[25];
    if (Ch = 0) or (Ch > 56) or (W = 0) or (W > 30000) or (Y = 0) or (Y > 30000) or
      not (Depth in [1,8,16,32]) or (Mode > 9) then raise Exception.Create('PSDヘッダーの値が範囲外です。');
    FStatus.Caption := Format('%d × %d px  ・  %d ch  ・  %d bit  ・  color mode %d' + #13#10 +
      'ヘッダー確認のみ。レイヤー／画素データの確認と表示は次段階です。',[W,Y,Ch,Depth,Mode]);
  except on E: Exception do FStatus.Caption := 'PSDヘッダーを確認できません: ' + E.Message; end;
end;
end.
