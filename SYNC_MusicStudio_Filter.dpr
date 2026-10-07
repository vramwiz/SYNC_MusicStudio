library SYNC_MusicStudio_Filter;

// 演奏スタジオのAviUtl2 DLL境界。移植元の画面類は必要な段階で組み込む。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  SYNC_MusicStudio_DarkTheme in 'Source\Lib\SYNC_MusicStudio_DarkTheme.pas',
  SYNC_MusicStudio_ProjectData in 'Source\Common\Project\SYNC_MusicStudio_ProjectData.pas',
  SYNC_MusicStudio_SettingsForm in 'Source\Plugin\Filter\SYNC_MusicStudio_SettingsForm.pas' {FormMusicStudioSettings},
  SYNC_MusicStudio_FilterPlugin in 'Source\Plugin\Filter\SYNC_MusicStudio_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    GetMusicStudioFilterTable;
    Result := 1;
  except
    // Delphi例外をAviUtl2のCコールバック境界へ漏らさない。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  // この段階ではDLLを超えて保持する描画資源や外部ファイルを持たない。
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetMusicStudioFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
