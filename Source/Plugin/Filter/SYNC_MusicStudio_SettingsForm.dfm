object FormMusicStudioSettings: TFormMusicStudioSettings
  Left = 0
  Top = 0
  Caption = '演奏スタジオ - 設定'
  ClientHeight = 548
  ClientWidth = 990
  Color = clBtnFace
  Constraints.MinHeight = 420
  Constraints.MinWidth = 740
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  object ToolbarPanel: TPanel
    Left = 0
    Top = 0
    Width = 990
    Align = alTop
    Height = 48
    BevelOuter = bvNone
    TabOrder = 0
    object ImportButton: TButton
      Left = 12
      Top = 10
      Width = 110
      Height = 28
      Caption = 'JSON読込'
      TabOrder = 0
      OnClick = ImportButtonClick
    end
    object ExportButton: TButton
      Left = 130
      Top = 10
      Width = 110
      Height = 28
      Caption = 'JSON保存'
      TabOrder = 1
      OnClick = ExportButtonClick
    end
    object RestoreButton: TButton
      Left = 256
      Top = 10
      Width = 180
      Height = 28
      Caption = '開いた時点に戻す'
      TabOrder = 2
      OnClick = RestoreButtonClick
    end
  end
  object FooterPanel: TPanel
    Left = 0
    Top = 500
    Width = 990
    Align = alBottom
    Height = 48
    BevelOuter = bvNone
    TabOrder = 3
    object ApplyButton: TButton
      Left = 12
      Top = 10
      Width = 150
      Height = 28
      Caption = '適用して閉じる'
      ModalResult = 1
      TabOrder = 0
    end
    object CancelButton: TButton
      Left = 174
      Top = 10
      Width = 110
      Height = 28
      Cancel = True
      Caption = 'キャンセル'
      ModalResult = 2
      TabOrder = 1
      OnClick = CancelButtonClick
    end
  end
  object InfoPanel: TPanel
    Left = 0
    Top = 48
    Width = 990
    Align = alTop
    Height = 64
    BevelOuter = bvNone
    TabOrder = 1
    object InfoLabel: TLabel
      Left = 12
      Top = 8
      Width = 962
      Height = 20
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
    end
    object StatusLabel: TLabel
      Left = 12
      Top = 36
      Width = 962
      Height = 20
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
    end
  end
  object JSONMemo: TMemo
    Left = 0
    Top = 112
    Width = 990
    Height = 388
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -14
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssBoth
    TabOrder = 2
    WantTabs = True
    WordWrap = False
    OnChange = JSONMemoChange
  end
  object OpenDialog: TOpenDialog
    DefaultExt = 'json'
    Filter = 'JSONファイル (*.json)|*.json'
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Title = '演奏スタジオのJSONを読み込む'
    Left = 704
    Top = 16
  end
  object SaveDialog: TSaveDialog
    DefaultExt = 'json'
    FileName = 'SYNC_MusicStudio.json'
    Filter = 'JSONファイル (*.json)|*.json'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Title = '演奏スタジオのJSONを保存する'
    Left = 752
    Top = 16
  end
end
