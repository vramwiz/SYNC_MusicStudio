# 配布準備

旧SYNC_Lyrics用カタログと配布スクリプトは、現行Filterに不要と確認して削除した。
演奏スタジオのインストーラー・公開用カタログは未作成。公開は行わない。

現行Release成果物はWin64/Release/SYNC_MusicStudio_Filter.auf2。
同じフォルダーのDLLはDelphi/IDEの標準出力として保持するが、配布時はauf2だけを選ぶ。
生成はプロジェクトのビルドイベントからScripts/BuildPlugin.ps1で行う。
Skia/FFmpeg DLLは現行Filterに不要。ユーザーのWAV/MP3/MIDI/PSDを配布物へ含めない。
正式な配布では`DEVELOPMENT.md`の配置規約に従い、検証後に別途配備を行う。

ユーザー承認により、通常ビルドの後処理で既定のC:/ProgramData/aviutl2/Plugin/SYNC_MusicStudio/へauf2だけを配置する。
DCUとDLLは作業プロジェクトのWin64構成フォルダーへ出力し、配備先へ混在させない。
