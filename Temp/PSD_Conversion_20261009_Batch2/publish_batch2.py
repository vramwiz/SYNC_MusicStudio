"""Publish batch 2 artifacts and merge the existing progress without losing batch 1."""
import hashlib
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path
from PIL import Image, ImageChops

WORK=Path(__file__).resolve().parent
ROOT=Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
BATCH=json.loads((WORK/'batch.json').read_text(encoding='utf-8-sig'))

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_new(path,data):
    with path.open('x',encoding='utf-8') as f:
        json.dump(data,f,ensure_ascii=False,indent=2)

def contacts():
    source=WORK.parent/'PSD_Conversion_20261009/publish_records.py'
    spec=importlib.util.spec_from_file_location('previous_contact_helpers',source)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for item in BATCH:
        module.contact(item,Path(item['staging'])/'pose-contact.jpg')
    print('Created 7 contact sheets from 28 saved-PSD pose renders.')

def composite_check(actual_path,supplied_path):
    with Image.open(actual_path) as im:
        actual=im.convert('RGBA')
    with Image.open(supplied_path) as im:
        supplied=im.convert('RGBA')
    assert actual.size==supplied.size
    ext=ImageChops.difference(actual,supplied).getextrema()
    raw_a,raw_b=actual.tobytes(),supplied.tobytes()
    alpha_changed=sum(raw_a[i]!=raw_b[i] for i in range(3,len(raw_a),4))
    visible_changes=sum(raw_a[i:i+4]!=raw_b[i:i+4] and (raw_a[i+3] or raw_b[i+3])
                        for i in range(0,len(raw_a),4))
    visible_max=max((max(abs(raw_a[i+j]-raw_b[i+j]) for j in range(3))
                     for i in range(0,len(raw_a),4) if raw_a[i+3] or raw_b[i+3]),default=0)
    display_max=[]
    for color in ('white','black'):
        left=Image.new('RGBA',actual.size,color); left.alpha_composite(actual)
        right=Image.new('RGBA',supplied.size,color); right.alpha_composite(supplied)
        display_max.append(max(v[1] for v in ImageChops.difference(left.convert('RGB'),right.convert('RGB')).getextrema()))
    assert alpha_changed==0 and visible_max<=1 and max(display_max)<=1
    # Same original source layers may have 1-level alpha-compositing rounding
    # differences between tools; record the actual values instead of hiding it.
    return dict(supplied_composite=str(supplied_path),rgba_exact=raw_a==raw_b,
                channel_max_absolute_difference=[maximum for minimum,maximum in ext],
                alpha_changed_pixels=alpha_changed,visible_changed_pixels=visible_changes,
                visible_rgb_max_difference=visible_max,white_black_display_max_difference=display_max,
                note='Alpha identical; visible RGB differs at most 1/255 from compositor rounding. Large raw RGB differences occur only at alpha=0.')

def publish():
    visual=read(WORK/'visual-review.json')
    assert visual['all_28_pose_previews_reviewed']
    sources=read(WORK/'source-hashes-before.json')
    changed=[name for name,h in sources.items() if digest(Path(name))!=h]
    if changed:
        raise ValueError(('Source or previous output changed; do not overwrite',changed))
    progress_path=ROOT/'PSD変換進捗.json'
    assert digest(progress_path)==digest(WORK/'progress-before.json'),'Progress changed concurrently'
    prior=read(progress_path)
    assert 'batch_2' not in prior,'Existing batch 2 is protected'
    entries=[]
    for item in BATCH:
        stage=Path(item['staging'])
        native=read(stage/'native-verification.json')
        app=read(stage/'app-verification.json')
        assert native['passed'] and app['passed']
        assert app['selected_pose_count']==item['pose_count']
        assert digest(Path(item['destination']))==app['file_sha256']
        layer_hashes={row['key']:row['rgba_sha256'] for row in native['layers']}
        for pose in item['poses']:
            assert layer_hashes[pose['key']]==pose['rgba_sha256']
        with Image.open(item['head_source']) as im:
            assert hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest()==layer_hashes['head']
        with Image.open(stage/'app-default-preview.png') as a,Image.open(stage/'previews'/(item['poses'][0]['pose_id']+'.png')) as b:
            assert a.size==b.size and a.convert('RGBA').tobytes()==b.convert('RGBA').tobytes()
        comparisons=[]
        for pose in item['poses']:
            if pose.get('supplied_composite'):
                comparisons.append(composite_check(stage/'previews'/(pose['pose_id']+'.png'),Path(pose['supplied_composite'])))
        record=Path(item['record_directory'])
        record.mkdir(exist_ok=False)
        (record/'プレビュー').mkdir()
        for pose in item['poses']:
            shutil.copyfile(stage/'previews'/(pose['pose_id']+'.png'),record/pose['preview_file'])
        shutil.copyfile(stage/'pose-contact.jpg',record/'全姿勢一覧.jpg')
        for name in ('native-verification.json','app-verification.json','app-document-after.json'):
            shutil.copyfile(stage/name,record/name)
        notes=visual['instruments'][item['instrument']]
        mapping={**item,'status':'integrated_pose_psd_verified; vocal_face_layer_migration_pending',
                 'psd_sha256':app['file_sha256'],'source_files_unchanged':True,
                 'every_pose_selected_in_actual_application':True,'every_preview_rendered_from_saved_psd':True,
                 'visual_review_observations_ja':notes,'supplied_composite_comparisons':comparisons,
                 'vocal_head_expression_reuse':'not yet migrated; supplied flattened fixed head used without transformation'}
        write_new(record/'元画像とPSDの対応.json',mapping)
        structure='\n'.join(('ON ' if row['visible'] else 'OFF')+' '+row['path'] for row in native['layers'])+'\n'
        (record/'レイヤー構造.txt').write_text(structure,encoding='utf-8-sig')
        guide=item['guide']
        report=(f"2026-10-09 {item['name_ja']} 一体差分PSD・第2バッチ\n\n"
                f"PSD: {item['destination']}\n"
                f"キャンバス: {item['canvas_wh'][0]} x {item['canvas_wh'][1]} / 透過RGBA8\n"
                f"姿勢数: {item['pose_count']} / 基本のみ初期表示 / 全画像原点(0,0)・原寸\n\n"
                "検証済み\n"
                "- AIArtToPSDの既存コードで作成。保存・再読込後のRGBA・座標・階層・表示状態が一致。\n"
                "- 保存PSDから全姿勢を排他選択して透過プレビューを描画。頭＋該当首下の2層合成と完全一致。\n"
                "- 実アプリで全姿勢を1枚ずつ選択し、常に1姿勢ONと全層画素不変を確認。\n"
                "- 基本へ戻して新規名保存・再読込。既定プレビューもネイティブ検証画像とRGBA完全一致。\n"
                "- 原PNG・ボーカルPSD・前回4点のPSDはハッシュ照合で変更なし。新規画像生成・補完・トリミング・再拡縮なし。\n\n"
                "目視した内容\n"+'\n'.join('- '+line for line in notes)+'\n\n'+
                "原素材の留保（PSD化で修正していない）\n"+'\n'.join('- '+line for line in guide['limits_ja'])+'\n\n'+
                '使用候補: '+guide['integrated_use_ja']+'\n\n'+
                '将来の分離可能性: '+guide['separation_outlook_ja']+'\n\n'+
                '残る制作: '+' / '.join(guide['remaining_work_ja'])+'\n\n'+
                "構造上の相違・未完了要件\n"
                "- 頭部は付属固定頭。顔・目・眉・口・髪は合成済みで、既存ボーカルの個別レイヤー移植は未完了。\n"
                "- 楽器名 → 演奏属性 → 正式名は画素なし識別群。人物・手足・楽器の描画は首下一体差分内。\n"
                "- 前後機材群は未分離なので作成していない。椅子が描かれた素材では椅子も一体のまま保持。\n"
                "- 専用中間コマは新作していない。提供姿勢を保存しただけで、素材番号・表示順は再生順や時間指定ではない。\n"
                "- 個別部位分割は第二段階。MIDI・タイムライン・MusicStudio実登録・外部PSDホスト互換は未検証。\n")
        if item['source_group']=='normal_marimba':
            report+=('\n通常配置マリンバはcore97姿勢と別管理。付属の固定頭合成済みPNGとalpha完全一致。\n'
                     '可視RGB・白黒背景への表示差は合成丸めによる最大1/255。完全透明部のRGB差は表示に影響しない。\n'
                     '実測値は対応JSONに記録。頭と首下の元レイヤーRGBAは変更していない。\n')
        if item['instrument']=='marimba':
            report+='\n非標準配置マリンバは黒窓群00/Aと透明窓群B/C/Dを混ぜたループにしない。AR補修候補への自動置換は未実施。\n'
        (record/'作業報告.txt').write_text(report,encoding='utf-8-sig')
        entries.append(dict(instrument=item['instrument'],source_group=item['source_group'],name_ja=item['name_ja'],
                            pose_count=item['pose_count'],psd=item['destination'],psd_sha256=app['file_sha256'],
                            record_directory=str(record),status='一体差分PSD保存・全姿勢切替検証済み。表情移植は未完了'))
    updated={**prior,'batch_2':entries,'updated_at':'2026-10-09',
             'completed_core_instruments':10,'completed_core_poses':61,
             'remaining_core_instruments':9,'remaining_core_poses':36,
             'completed_supplement_psds':1,'completed_supplement_poses':3,
             'total_verified_psds':11,'total_verified_poses':64,
             'next':'11_トライアングル以降のcore9楽器36姿勢。補修候補・任意頭・箏構図用は別枠。',
             'source_files_unchanged':True}
    temporary=progress_path.with_name('PSD変換進捗.batch2.tmp')
    write_new(temporary,updated)
    assert digest(progress_path)==digest(WORK/'progress-before.json'),'Progress changed concurrently'
    os.replace(temporary,progress_path)
    write_new(WORK/'publication-verification.json',dict(passed=True,published_psds=len(entries),published_poses=28,
               source_files_unchanged=len(sources),existing_batch_preserved=updated['batch_1']==prior['batch_1'],
               total_psds=11,total_poses=64))
    print('Published 7 PSD records / 28 previews. Total 11 PSDs / 64 poses; remaining core 9 / 36.')

if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='contacts': contacts()
    else: publish()
