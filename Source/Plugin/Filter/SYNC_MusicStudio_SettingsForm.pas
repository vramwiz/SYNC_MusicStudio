unit SYNC_MusicStudio_SettingsForm;

// 参照元の同期編集フォームから複製した、設定JSONを管理する初期画面。

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls;

type
  TMusicStudioApplyJSONEvent = function(const JSONText: string; out ErrorText: string): Boolean of object;

  TFormMusicStudioSettings = class(TForm)
    ToolbarPanel: TPanel;
    ImportButton: TButton;
    ExportButton: TButton;
    RestoreButton: TButton;
    FooterPanel: TPanel;
    ApplyButton: TButton;
    CancelButton: TButton;
    InfoPanel: TPanel;
    InfoLabel: TLabel;
    StatusLabel: TLabel;
    JSONMemo: TMemo;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ImportButtonClick(Sender: TObject);
    procedure ExportButtonClick(Sender: TObject);
    procedure RestoreButtonClick(Sender: TObject);
    procedure CancelButtonClick(Sender: TObject);
    procedure JSONMemoChange(Sender: TObject);
  private
    FCancelRequested: Boolean;
    FInitialText: string;
    FOnApplyJSON: TMusicStudioApplyJSONEvent;
    function ReadDocument(out JSONText: string): Boolean;
  public
    // 不正な既存JSONも編集可能なまま表示する。キャンセル時はホストへ書き戻さない。
    procedure LoadDocument(const JSONText: string);
    property OnApplyJSON: TMusicStudioApplyJSONEvent read FOnApplyJSON write FOnApplyJSON;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.UITypes,
  SYNC_MusicStudio_DarkTheme,
  SYNC_MusicStudio_ProjectData;

{$R *.dfm}

procedure TFormMusicStudioSettings.FormCreate(Sender: TObject);
begin
  ApplySyncMusicStudioDarkForm(Self);
  ApplySyncMusicStudioDarkPanel(ToolbarPanel);
  ApplySyncMusicStudioDarkPanel(FooterPanel);
  ApplySyncMusicStudioDarkPanel(InfoPanel);
  ApplySyncMusicStudioDarkMemo(JSONMemo);
  ApplySyncMusicStudioDarkButton(ImportButton);
  ApplySyncMusicStudioDarkButton(ExportButton);
  ApplySyncMusicStudioDarkButton(RestoreButton);
  ApplySyncMusicStudioDarkButton(ApplyButton);
  ApplySyncMusicStudioDarkButton(CancelButton);
  InfoLabel.Caption := '設定JSONを編集・読込・保存できます。WAV、MIDI、PSDはファイル参照として保持します。';
end;

procedure TFormMusicStudioSettings.LoadDocument(const JSONText: string);
begin
  FCancelRequested := False;
  FInitialText := JSONText;
  if Trim(FInitialText) = '' then
    FInitialText := MUSIC_STUDIO_DEFAULT_JSON;
  JSONMemo.Text := FInitialText;
  JSONMemoChange(nil);
end;

function TFormMusicStudioSettings.ReadDocument(out JSONText: string): Boolean;
var
  ErrorText: string;
begin
  Result := TryNormalizeMusicStudioJSON(JSONMemo.Text, JSONText, ErrorText);
  if not Result then
  begin
    MessageDlg(ErrorText, mtError, [mbOK], 0);
    JSONMemo.SetFocus;
  end;
end;

procedure TFormMusicStudioSettings.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  ErrorText: string;
  JSONText: string;
begin
  CanClose := True;
  // VCLのタイトルバーの閉じる操作もmrCancelになるため、明示取消だけを区別する。
  if FCancelRequested then
    Exit;
  CanClose := False;
  try
    if not ReadDocument(JSONText) then
      Exit;
    if Assigned(FOnApplyJSON) then
      if not FOnApplyJSON(JSONText, ErrorText) then
      begin
        MessageDlg(ErrorText, mtError, [mbOK], 0);
        Exit;
      end;
    CanClose := True;
  except
    on E: Exception do
      MessageDlg('設定を保存できませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMusicStudioSettings.ImportButtonClick(Sender: TObject);
var
  ErrorText: string;
  JSONText: string;
begin
  if not OpenDialog.Execute then
    Exit;
  try
    if not TryNormalizeMusicStudioJSON(TFile.ReadAllText(OpenDialog.FileName, TEncoding.UTF8),
      JSONText, ErrorText) then
    begin
      MessageDlg(ErrorText, mtError, [mbOK], 0);
      Exit;
    end;
    JSONMemo.Text := JSONText;
  except
    on E: Exception do
      MessageDlg('JSONファイルを読み込めませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMusicStudioSettings.ExportButtonClick(Sender: TObject);
var
  JSONText: string;
begin
  if not ReadDocument(JSONText) or not SaveDialog.Execute then
    Exit;
  try
    TFile.WriteAllText(SaveDialog.FileName, JSONText, TEncoding.UTF8);
  except
    on E: Exception do
      MessageDlg('JSONファイルを保存できませんでした: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TFormMusicStudioSettings.RestoreButtonClick(Sender: TObject);
begin
  JSONMemo.Text := FInitialText;
end;

procedure TFormMusicStudioSettings.CancelButtonClick(Sender: TObject);
begin
  FCancelRequested := True;
end;

procedure TFormMusicStudioSettings.JSONMemoChange(Sender: TObject);
begin
  StatusLabel.Caption := Format('編集中: %d文字 / 保存上限: 単行化後32,767文字', [Length(JSONMemo.Text)]);
end;

end.
