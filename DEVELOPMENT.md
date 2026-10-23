# SYNC_MusicStudio 開発・運用ルール

参照元の規約から、本プロジェクトの現行範囲に必要なものを引き継ぐ。

2026-10-10現在、ユーザーの再開連絡まで音声関連テストを停止中。
音声fixture生成、decode、再生/試聴/waveOutとTestEditorStage1全体を実行しない。ミュートによる代替も行わない。
以下の旧音声検証手順は再開後用。現在はTestNoAudioと音声処理を呼ばないFoundationだけを使う。

## 現在の検証方針（2026-10-22 ユーザー指定）

DPIに関する試験は不要。以後はDPI変更/倍率比較/モニター間DPI試験を実行しない。
変更箇所に直接関係する専用ケースと必要最小限のビルド・スモーク確認に絞り、同じ成功ケースやDebug/Releaseで同内容の全体回帰を反復しない。
下記の旧DPI検証手順は過去の記録として保持する。DPI試験を含む全体スイートを通常の入口として実行せず、専用モードを選ぶ。
ドラムUIの --drums はDPI変更を行わない。今回のPSD命名規則は --drum-rules / --drum-psd を使用する。
全楽器共通方式はNoAudioTestsの `<Temp証拠先> --instrument`、素材受信時の診断は `<Temp証拠先> --instrument-psd <PSD絶対パス>`。どちらも音声/DPI試験を行わない。

## 安全性・性能

- AviUtl2のCコールバック境界へDelphi例外を漏らさない。
- ファイル不存在、JSON破損、設定反映失敗でAviUtl2を停止・終了させない。
- 設定変更は検証後に反映し、失敗時は修正できる画面を維持する。
- 設定画面はオブジェクトごとのJSONを扱い、ユーザー設定をDLL共通の可変状態へ保存しない。
- 映像コールバックはSDK値のコピー・描画要求・RGBA転送だけを行い、外部ファイル読込/JSON解析は描画専用ワーカーへ分離する。
  SDKに設定変更時の読込フックがないため、最初の描画要求/JSON変更/設定画面終了時の更新はsnapshot準備の完了も待つ。
  Bind済みsnapshotはファイル監視を停止し、以降のフレームで外部ファイルや設定を再読込しない。
- 並列描画を導入する段階で、キャッシュは読み取り専用データとして設計する。

## 最小映像出力の無音検証

`Scripts/TestVideoOutput.ps1 -PluginPath <無配備auf2> -EvidenceRoot <Temp内証拠先>`。
合成PSD/MIDIと隔離共有rootで固定RGBA、半透明、母音、seek/stop/reopen、複数インスタンス、参照移動後の描画、同JSONの共有設定更新を確認する。
実DLLのSDK callback/lifecycleも独立レイアウトで呼び、元映像の保持、破損/欠損/nil、安全なサイズ境界を検証する。
既知の実共有PSDは読取のみ使用し、作品JSON・MIDI・PNGはTempへ出力する。実PSD/共有metadata/aup2/配備auf2のSHA256を前後比較する。
このホストはAviUtl2本体ではなくSDK呼出の隔離ホスト。GPU/実機の表示、設定→aup2保存再読込はユーザー配備後の確認として区別する。
SDK ABIの根拠は公式2026/10/10版filter2.h。FILTER_PLUGIN_TABLE=72B、button=32B、video=328B、userdata offset=280B (Win64)。
設定背景はPSD合成前のGetFramebufferTexture2Dをエフェクト所有stagingへ読み戻す（Windows D3D11/DXGI標準API、配布用DLL追加なし）。GetImageDataは出力合成用オブジェクト画像として別に維持し、フレームバッファ取得不能時だけ設定背景のfallbackに使う。OBJECT_INFO.effect_layer=offset96は本体2.1.3 (2026/8/2) 追加で、版番号2010300未満では読まない。
設定対象のOBJECT_HANDLEとscene_idへ対応付け、不変画素と世代だけをコピーする。SDK get_object_id/get_effect_id等の新APIは使用しない。
TestVideoOutputには500回の並行コピー、別オブジェクト/シーン、破棄、背景更新30回、破損JSON、API未取得、再オープン、リサイズ/144DPIを含む。
実DLLの設定ボタンも隔離編集APIで開き、背景/半透明PSD一回分のnative画素とキャンセル無反映を確認する。デスクトップ画像を背景には使わない。
透明なオブジェクト＋色付きD3D WARPフレームバッファ、描画EDIT_INFO=nil、初回未取得、再描画なし再オープン/カーソル差も検証する。RGBA/BGRA/UNORM16/FLOAT16、行pitchとstagingリサイズ20回を含む。
画像確認用のキャプチャは検証ホスト所有の設定ウィンドウだけ。ホスト入力が静止画であることと、実AviUtl2のGPU/カーソル挙動は別途実機確認として区別する。

## ビルド

- Delphi 37.0、Win64のみ。SYNC_MusicStudio_Filter.dprojのDebugとReleaseを検証する。
- IDEではこの.dprojをプロジェクトとして開く。単一DLLのため.groupprojは不要。
  プロジェクトオプションのビルドイベントはDebug/Win64とRelease/Win64をそれぞれ選んで確認する。
- 警告0、エラー0を原則とする。旧Inputと旧歌詞テストは現行ビルド対象外。
- BT_BuildTypeは配布/Provisioning用の種別。コンパイラのRelease構成名を代入しない。Win64テンプレートのDebugを使い、最適化/定義/デバッグ情報はDCC設定で分ける。
- 出力先は作業フォルダーの`Win64/Debug/`・`Win64/Release/`。ユーザー承認によりビルド後に既定プラグインフォルダーへauf2だけをコピーする。
- ビルドイベントは`Scripts/BuildPlugin.ps1`。DebugはDLL/RSMとauf2を保持し、
  ReleaseもDLLをDelphi/IDEの標準出力として保持し、前の構成が残したRSMだけを整理する。
- 現行プロジェクトはSkia/FFmpegを使用しない。MP3はWindowsのwmvcore.dllを読込時に使う。
  将来Skiaを組み込むときは、保存した`Scripts/PrepareSkiaUnit.ps1`と初期化資料を参照し、
  DLLロード中の初期化を避ける。
- Windows PowerShellで使う日本語を含むps1はUTF-8 BOM付きで保存する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "D:\DelphiProg\SYNC_MusicStudio\SYNC_MusicStudio_Filter.dproj" /t:Build /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "D:\DelphiProg\SYNC_MusicStudio\SYNC_MusicStudio_Filter.dproj" /t:Build /p:Config=Release /p:Platform=Win64'
```

このPCの環境だけでビルドする。他PCへビルドを依頼しない。
ビルド後の配置とAviUtl2実機確認は区別する。ロック中のauf2は更新を拒否し、プロセスを強制終了しない。

今回の追加版は配備しない。既存.dprojのBT_BuildType・IDEイベントを維持し、
呼出時だけPostBuildEventをDeployDirectoryなしへ上書きしてDebug→ReleaseをこのPCで直列ビルドする。
再現コマンドは`Scripts/BuildLocal.ps1 -EvidenceRoot <Temp内証拠先>`。既存のIDEイベントを変えず、呼出時のPostBuildEventを無配備へ上書きしてからauf2を生成する。ビルド前後の入力SHA256も照合する。
通常の上記MSBuild/IDEビルドには既存配備指定があるため、無配備確認にはこの上書きを必ず使う。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書き、公開処理には入出力と重要な副作用を説明する。
- 状態、ABI配置、所有権や保存対象を明記する。コードの単純な言い換えコメントを増やさない。
- 日本語文字列を持つpas/dprはUTF-8 BOM付き、改行はCRLFとする。
- 1ユニットが約1,000行を超える前に責務の抽出を検討する。フォームとdfmは同じフォルダーへ置く。
- SDK型の順序、サイズ、配置を変更するときは公式SDKと照合する。
- フォームは操作と画面状態を担当し、JSON検証・解析・同期計算・描画は専用ユニットへ置く。

## 保管・配布

- 元のUIを保管し、必要な処理は複製して適応させる。完成に近づいた段階の不要ファイル削除は必須。
- コピーした旧Inputプロジェクトと旧SYNC_Lyrics配布スクリプトは、現行Filterに不要と確認して削除した。
  継承UI・SongReader等の参照ソース・旧UI検証は移植用に保持し、現在のコンパイル対象へ入れない。
- 配布を整える段階でインストール先は{pluginsDir}、共通の永続データは{dataDir}を使用する。
- JSONはファイル参照のみを持ち、WAV/MIDI/PSDの実データを埋め込まない。
- ソース、dfm、プロジェクト、res、必要な文書・スクリプト・素材を管理対象にする。
- Win32/Win64、dcu、rsm、dll、auf2、IDEローカル設定・履歴はGitへ追加しない。

## 設定・JSON・配備プラグインの検証

ビルド後に次を実行する。JSON保存境界、設定フォーム、指定auf2のロードと登録を検証する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\TestFoundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\TestFoundation.ps1 -PluginPath .\Win64\Release\SYNC_MusicStudio_Filter.auf2
powershell -NoProfile -ExecutionPolicy Bypass -File .\Scripts\TestNoAudio.ps1
```

Tests/Win64内へ検証用EXE/DCUを生成する。AviUtl2本体のaup2保存・再読込は別途実機確認する。
TestNoAudioは隔離したTempライブラリで共有PSD・部位・母音・表情/animation/姿勢・拍・変化テンポ・キャッシュ・GUIを検証する。
120行のPSDサムネイル全域スクロール/LRUとtransport検証も含み、総実行予算は90秒（待機は1秒単位）。
単独ケースはNoAudioTestsの`<証拠root> --ui-thumbnails`。初回欠損PSDの本体だけの復元/再欠損/ドラッグ復帰、70実体同時可視の画像/ジョブ予約64枠・安定した超過placeholder・世代切替中の枠解放を含む。
同サイズ更新/共有revision/100再描画・再Bind、bitmap128件・worker2、96/144DPIと無音時計だけを検証する。
native popup検証中に他ウィンドウへフォーカスが移るとメニューが取消される。失敗はログに残し、ユーザー操作を止めず検証する場合はHISTORYのRunIsolatedNoAudio.ps1/IsolatedUiHost.csで検証ホスト専用desktopを使用する（画面切替しない）。
旧テストからMIDI/JSON/配置/共通GUI回帰を分離。音声テストの過去出力なしでも合成PSDを自前生成して実行できる。
再登録設定の反映、accepts混在一覧と＋、保存競合/atomic失敗時の原状維持、別PSD表情の排除、JSON30回切替を含む。
PSD本体の部分コピー/サイズ不一致/ハッシュ不一致/公開失敗/metadata失敗と再試行も隔離素材で検証する。
同じ実体のrootで2プロセスに同版を読ませて同時保存し、一方だけ成功/他方はrevision競合になることを3回確認する。
専用workerはホストより先に直列コンパイルする。コピー中のworkerだけを意図的に終了し、一時ファイルの無視とロック解放/復旧も確認する。
この子プロセスはテスト所有で、音声/VCL/実ライブラリを使わない。実PSD本体とJSONの原子性は別々のassertで確認する。
PSD表示回帰は正規のtsly追加タグで既定値1/画像上の特殊値0/終端上の0/破損値2を区別し、未知情報の拒否を維持する。
乗算の透明/半透明背景、通常グループmaskの座標/既定値/反転/無効化/不透明度、欠損channelとマスク付きpassの拒否も検証する。
設定画面では非透明合成画素だけでなくnativeチェッカー領域へ描画された実ピクセルと参照バインドを確認する。
開き直し/欠損からの再選択/リサイズ/内部144DPIも確認する。実PSDの個別確認はコンパイル済み無音ホストへ
`<Temp証拠root> --psd-display <読取PSDの絶対パス>`を渡す。コピー先ライブラリはその証拠root内へ隔離する。
実Documentsのキーボードとドラム修正版は読取/合成だけ行い、SHA256前後一致とPNGをTempへ出力する。
このホストは音声fixture/decode/Play/waveOutを呼ばない。NoAudioコンパイル失敗時は古いEXEを実行しない。
母音の個別GUI検証は同ホストの `<Temp出力先> --psd-mouth <読取PSDの絶対パス> [読取asset.jsonのコピー]`。
同名の目/口は完全な階層キーで区別し、12枠のコンボ/レイヤー行/割当ボタン/OK/保存/別Storeの再オープンを通す。
初回・再読込・再オープンはコンボのOnChangeを呼ぶ前に割当行を検証し、そのまま割当/OK保存しても各キーが保持されることを確認する。
合成PSDでは非'*'の体・髪・装飾を別画素に置き、12枠切替後の実プレビューを独立した固定RGBA値でも検証する。
同じテストは統合画面のPSDスロット選択→左共有一覧のダブルクリックからも開き、96/144DPIで12項目の可視性・枠内配置・割当/保存を確認する。
割当はコンボを変更せずレイヤー先選択で行う。実際のネイティブポップアップが開いた状態で、右クリック位置の行・12項目の割当チェック・コールバックを検証する。
メニューキー/Shift+F10/Enterの呼出と矢印キーの行選択、キャンセル不変、選択レイヤーの複数母音解除も確認する。
統合ポップアップは最小幅と狭い一覧で検証。合成PSDには長い実名と別階層の同名を含め、完全な階層のツールチップと独立画素assertを通す。
この入口での音声エンジン未確保/音声decode数0と作品JSON不変も検証する。直接ポップアップを開くテストだけで入口検証を代替しない。
親階層の'*'排他、実プレビュービットマップとチェックの一致、解除後のsmall母音fallback、取消時のmetadata/SHA不変を確認する。
歌唱PSDの行選択は保存JSON不変と最後の世代だけの公開、体/髪/装飾の固定画素で確認する。
固定母音列は未割当/小さい母音割当の前後でnative名前領域の画素が一致し、ラベル領域だけ変わることを検証する。
native wheelのカーソル固定、10～3200%の限界、画像外/画面外座標のドラッグ、capture解除/取消、fit/ダブルクリック、
リサイズと選択/割当の表示位置保持、表示操作の再合成0を確認する。画素確認はバッファ付きプレビュー自身のwindow DCを読む。
素材はTemp内のrootへコピーし、実PSD/実共有設定を書き換えない。通常のTestNoAudioは同じ流れを合成階層PSDで検証する。
統合再生の追加検証はNoAudioTestsの`<証拠root> --psd-playback [実PSD] [隔離用asset.jsonコピー]`。
実MIDI歌詞をSilentVisualModeの表示時計で再生し、統合SceneCache/Stageの連続描画、seek/stop/resume/高速シーク、完成画像とnative体/髪画素を確認する。
同一キャラの合成待ちの空白0、最後の母音世代、破損/合成失敗の旧画像解除、別キャラ/作品切替、再オープン、原本/管理PSD/共有JSON/作品JSON不変を検証する。
音声エンジン未確保とwaveform decode数0を毎pollでassertする。通常TestNoAudioにも合成PSDの再生検証を含める。
noaudio-result.jsonへ実行中/失敗/成功を記録し、コンパイル開始前に標準出力ログをNOT_RUNへ更新する。
ログと通常/最小/内部144DPI画像は`Temp/EditorStage1/slot-library/`。
独立ホストへ`--silent <JSON> --library-root <Temp内のPSDAssets>`を渡すと、音声解析/出力を起動せず確認できる。
具体的な起動例はREADME.md。共有設定の確認は作品の適用/取消とは独立した永続保存なので、検証用rootを使う。

以下は音声テスト再開後の既存回帰検証手順。
旧TestEditorStage1のスロット番号はkind/追加戻り値から解決し、一覧選択は固定IDとスロット文脈へ更新済み。
音声ホストはコンパイルのみで、全回帰は未実施。再開許可後だけTestEditorStage1.ps1の-AllowAudioTestsを使う。
引数なしのスクリプトとEXE直接起動はフォーム/fixture前に停止する。
Scripts/TestAudioGate.ps1はコンパイルと拒否経路（終了2・素材出力フォルダー未生成）だけを無音で検証する。
TestEditorStage1は合成WAV/MP3/MIDI・参照JSON・GUI画像を`Temp/EditorStage1/verification/`に生成する。
独立ホスト`Tests/Win64/SYNC_MusicStudio_EditorPreview.exe`で編集UIを手動確認できる。
通常/最小サイズの画像はVCLフォームそのものから保存し、配置・文字を目視確認する。
144DPI画像は96DPIの実モニター上でVCL内部倍率を切替えた独立レイアウト検証。
実モニター間のDPI移動やAviUtl2側のDPI認識は別途確認する。

仮想プロジェクトは`Samples/Debug/`。独立EXEの第1引数、「サンプルJSON…」、通常の「JSON読込」から開く。
`generic-slots.json`は実素材不要、`legacy-tracks.json`は旧形式移行、`unsupported-version.json`は拒否確認用。
スロットID/順番/受入属性/slotId、複数枠の独立編集・削除影響、欠損参照はTestNoAudioでも検証する。
手順と未実装の範囲は`Samples/Debug/README.md`を参照。

編集プレビューの検証もTestEditorStage1に含む。実waveOut出力と時計、PCM/MP3、配置時刻/音量/重なり、
自然終了、20分WAVの終端付近シーク、連打/JSON切替/取消/破棄時の所有出力0を確認する。
RGB8 PSDのraw/RLEと既存PSDの読取・SHA256不変、MIDI歌詞の配置ローカル時刻を検証する。
preview-demo.json・preview-playing.png・preview-existing-psd.pngを同じverificationフォルダーに生成する。
実機での音の聴取、AviUtl2背景/映像への描画、実モニター間DPI移動はこの自動検証に含めない。
### IDEの前処理・後処理

DelphiではSYNC_MusicStudio_Filter.dprojを開く。単一DLLのため.groupprojは不要。
プロジェクトオプションのビルドイベントでDebug/Win64とRelease/Win64を個別に選ぶ。
IDE用Cfg_1_Win64/Cfg_2_Win64にコマンドを格納し、Import後の同内容の定義でMSBuildの出力マクロを遅延評価する。
Debug/Releaseのコンパイラ設定もCfg_1/Cfg_2の専用グループに置き、IDE保存時に失われない構成にする。

Debug/Win64の前処理:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File "$(PROJECTDIR)\Scripts\BuildPlugin.ps1" -Stage Prepare -Config Debug -ProjectName "SYNC_MusicStudio_Filter" -LibraryPath "$(OUTPUTPATH)"
```

Debug/Win64の後処理:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File "$(PROJECTDIR)\Scripts\BuildPlugin.ps1" -Stage Complete -Config Debug -ProjectName "SYNC_MusicStudio_Filter" -LibraryPath "$(OUTPUTPATH)" -DeployDirectory "C:\ProgramData\aviutl2\Plugin\SYNC_MusicStudio"
```

Release/Win64はConfig DebugをConfig Releaseへ変更する。OUTPUTPATHは実DLLの完全パス。
PrepareはDLLの出力フォルダーを作成。Completeは同じDLLから同名auf2を生成し、指定配備先へauf2だけをコピーする。
配備先はGit初期設定と既存フォルダーで確認したC:/ProgramData/aviutl2/Plugin/SYNC_MusicStudio。
ユーザーがプロジェクトを閉じ、正しい出力先・配備へ修正するよう承認したことに基づく。

| 用途 | 場所 |
| --- | --- |
| DCU（ユニット出力） | Win64/Debug/DCU、Win64/Release/DCU |
| DLL（標準出力） | Win64/Debug、Win64/Release |
| 生成auf2 | 同じDLL出力フォルダーのSYNC_MusicStudio_Filter.auf2 |
| AviUtl2へ配置するauf2 | C:/ProgramData/aviutl2/Plugin/SYNC_MusicStudio/SYNC_MusicStudio_Filter.auf2 |

DCU出力を変更してもDLLの出力/配置先は変わらない。新しいフォルダー等のプラグイン領域をDCU出力に使わない。
DLLはDebug/Releaseとも保持する。配布物へ選ぶのはauf2。旧SYNC_LyricsのSetupスクリプトは使用しない。
ログのPLUGIN_OUTPUT_PREPARED / PLUGIN_OUTPUT_COPIED / PLUGIN_DEPLOYEDと3ファイルのSHA256一致を成功条件とする。
後処理はAlways。ロック・読取専用等のコピー失敗では非0を返し、IDE/MSBuildのビルドを失敗として扱う。
ファイル属性解除・AviUtl2強制終了・ロック強制解除は行わない。

IDEで以前開いていた場合は、編集を保存してこの.dprojを開き直し、Win64のDebug/Releaseで通常のビルドを行う。
rsvars.bat読込後のmsbuild .\SYNC_MusicStudio_Filter.dproj /t:Buildも、既定Release/Win64として検証する。
IDE実画面の読込/欄表示は、接続にcomputer-useのnode_replが提供されていないため未検証。
波形キャッシュの追加検証もTestEditorStage1に含む。同一音源共有、再描画100回/ズーム/DPIで解析増加なし、
更新日時/同サイズ更新/欠損復旧、世代破棄、音源時間範囲、0/75/200%の表示を検証する。
折りたたみの複数スロット、選択/移動/D&D/シーク、16スロットの縦スクロール、通常/最小/144DPI画像を確認する。
画像はverification/waveform-*.png。実モニター間DPI移動とAviUtl2内の操作は別途実機確認。
ピアノロール/PSD共有キャッシュ検証もTestEditorStage1に含む。テンポ変化/音高/使用トラック/配置長さ、透過/縦横比、
100回再描画で解析/画像生成の増加なし、LRU、同サイズ更新、完了直前の旧世代排除、取消/破棄を検証する。
横スクロールで固定列サムネイルが動かないこと、折りたたみ/復元、並べ替え/削除/JSON切替、通常/最小/144DPIも確認する。
試用JSONはverification/piano-psd-demo.json、画像はverification/piano-psd-*.png。
音域fitは単音/狭音域/空/音高0・127/全音域、1～64pxの本文高、96/144DPI、横タイル/スクロールを追加検証する。
選択トラック切替と同サイズMIDI更新、100回再描画、折りたたみ/JSON不変も確認。試用JSONはverification/pitch-range-demo.json。
フレーズ別音域はTestNoAudioの`<証拠root> --phrase-roll`で個別検証する。通常の全無音回帰にも含める。
実MIDIを非同期解析し、連続音/和音/持続音の橋渡し/1tickの休符/単音/0・127を含む8フレーズの音域とnativeピアノロール画素を検証する。
タイル境界/スクロール/ズーム/配置途中切断/高さ1～64px/96・144DPIで音域と音程差を維持し、100回描画で解析/画像生成が増えないことを確認する。
選択MIDIトラック変更と同サイズファイル更新の世代再生成、統合歌唱クリップ/折りたたみ/作品JSON・MIDI不変、音声エンジン未確保とdecode0も検証する。
試用JSONと実フォームPNGは各実行のphrase-roll-<GUID>/phrase-roll-demo.json・phrase-roll-integrated-*.png。実モニター間DPIは別途確認する。
今回の追加版はPostBuildEventを呼出時だけDeployDirectoryなしのCompleteへ上書きしてローカルauf2を生成する。
.dprojのIDEビルドイベントは保持する。この検証版を既定配備先へ上書きするには別途承認を得る。
