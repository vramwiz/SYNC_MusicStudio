"""Publish previews, source mapping and honest stage-one verification records."""
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WORK = Path(__file__).resolve().parent
ROOT = Path(r'C:\Users\zan12\Documents\SYNC_MusicStudio\Characters\PNG\東北きりたん')
BATCH = json.loads((WORK/'batch.json').read_text(encoding='utf-8-sig'))
FONT = ImageFont.truetype('C:/Windows/Fonts/meiryo.ttc', 16)

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_new(path, data):
    with path.open('x', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def contact(item, destination):
    vertical=item['canvas_wh'][1]>item['canvas_wh'][0]
    cell=(300,470) if vertical else (450,340)
    columns=4 if vertical else 3
    poses=item['poses']
    sheet=Image.new('RGB',(cell[0]*columns,cell[1]*((len(poses)+columns-1)//columns)),'#d9dce0')
    draw=ImageDraw.Draw(sheet)
    for n,pose in enumerate(poses):
        x,y=(n%columns)*cell[0],(n//columns)*cell[1]
        with Image.open(Path(item['staging'])/'previews'/(pose['pose_id']+'.png')) as original:
            im=original.convert('RGBA')
        im.thumbnail((cell[0]-12,cell[1]-65),Image.Resampling.LANCZOS)
        sheet.paste(im,(x+(cell[0]-im.width)//2,y+53+(cell[1]-65-im.height)//2),im)
        draw.text((x+8,y+6),pose['pose_id'],font=FONT,fill='#15202b')
        draw.text((x+8,y+28),pose['label_ja'][:23],font=FONT,fill='#15202b')
    sheet.save(destination,quality=94)

def prepare_contacts():
    for item in BATCH:
        contact(item,Path(item['staging'])/'pose-contact.jpg')
    print('Created four contact sheets from actual saved-PSD renders.')

LIMITS = {
    'keyboard': ('本体・スタンドは固定化の候補。ただし手／鍵盤の接触と隠れ面を壊す自動分離は未実施。'
                 '演奏13・14の小離鍵を中間候補として収録し、保持時間・再生順は未定。'),
    'guitar': ('手・袖・ネック・ストラップが重なるため独立分離は難しい。補完なしの分解を行っていない。'
               'Eの中間ストロークは提供素材であり、他の新しい中間画像は作成していない。'),
    'bass': ('手と楽器の分離には隠れ面と接触部の補完が必要。交互指・新規中間コマは未収録。'
             '待機Dの首穴は原素材のまま。補修D3への自動置換はしていない。'),
    'drums': ('人物と脚間スネアを常に一体で保持。下半身の露出を生む分離はしていない。'
              'イス・太鼓類・シンバルを個別の固定／可動レイヤーへ分離する工程は未実施。'
              'Cのシンバル角度差は一体姿勢内に保存。C2/Fは予備動作で、未接触を接触済みとは扱わない。'),
}

def publish():
    sources=read(WORK/'source-hashes-before.json')
    changed=[name for name,h in sources.items() if digest(Path(name))!=h]
    if changed:
        raise ValueError(('Source changed',changed))
    progress=[]
    for item in BATCH:
        stage=Path(item['staging'])
        native=read(stage/'native-verification.json')
        app=read(stage/'app-verification.json')
        assert native['passed'] and app['passed']
        assert app['selected_pose_count']==item['pose_count']
        assert digest(Path(item['destination']))==app['file_sha256']
        hashes={x['key']:x['rgba_sha256'] for x in native['layers']}
        for pose in item['poses']:
            assert hashes[pose['key']]==pose['rgba_sha256'],pose['source']
        with Image.open(item['head_source']) as im:
            assert hashlib.sha256(im.convert('RGBA').tobytes()).hexdigest()==hashes['head']
        with Image.open(stage/'app-default-preview.png') as a, Image.open(stage/'previews'/(item['poses'][0]['pose_id']+'.png')) as b:
            assert a.size==b.size and a.convert('RGBA').tobytes()==b.convert('RGBA').tobytes()
        record=Path(item['record_directory'])
        record.mkdir(exist_ok=False)
        previews=record/'プレビュー'
        previews.mkdir()
        for pose in item['poses']:
            shutil.copyfile(stage/'previews'/(pose['pose_id']+'.png'),previews/(pose['pose_id']+'.png'))
        shutil.copyfile(stage/'pose-contact.jpg',record/'全姿勢一覧.jpg')
        for filename in ('native-verification.json','app-verification.json','app-document-after.json'):
            shutil.copyfile(stage/filename,record/filename)
        mapping={**item,'status':'integrated_pose_psd_verified; vocal_face_layer_migration_pending',
                 'psd_sha256':app['file_sha256'],'source_files_unchanged':True,
                 'every_pose_selected_in_actual_application':True,
                 'every_preview_rendered_from_saved_psd':True,
                 'visual_review':'all 36 poses reviewed on contact sheets; source issues retained',
                 'vocal_head_expression_reuse':'not yet migrated; supplied flattened fixed head used without transformation',
                 'separation_assessment_ja':LIMITS[item['instrument']]}
        write_new(record/'元画像とPSDの対応.json',mapping)
        structure=[]
        for row in native['layers']:
            structure.append(('ON ' if row['visible'] else 'OFF')+' '+row['path'])
        (record/'レイヤー構造.txt').write_text('\n'.join(structure)+'\n',encoding='utf-8-sig')
        guide=item['guide']
        report=(f"2026-10-09 {item['name_ja']} 一体差分PSD・第1バッチ\n\n"
                f"PSD: {item['destination']}\n"
                f"キャンバス: {item['canvas_wh'][0]} x {item['canvas_wh'][1]} / 透過RGBA8\n"
                f"姿勢数: {item['pose_count']} / 基本のみ初期表示 / 全画像レイヤー原点(0,0)・原寸\n\n"
                "検証済み\n"
                "- AIArtToPSDの実コードでPSDを作成し、保存・再読込後のRGBA、座標、階層、表示状態を照合。\n"
                "- 保存PSDから各姿勢を排他選択して全プレビューを描画。頭＋該当首下の2層合成と完全一致。\n"
                "- AIArtToPSD実アプリで全姿勢を1枚ずつ選択し、最大1枚ONと全レイヤー画素不変を確認。\n"
                "- 実アプリで新規名保存・再読込。初期表示を基本へ戻し、合成プレビューも完全一致。\n"
                "- 元PNG・ボーカルPSDをSHA-256照合し、変更なし。元素材にない画像は生成していない。\n\n"
                "構造上の留保・未完了要件\n"
                "- 頭部は付属の固定頭PNGを独立レイヤーとして原寸保持。目・眉・口・髪は合成済み。\n"
                "- 既存ボーカルの個別頭部・表情レイヤー移植は未完了。固定頭のサイズ・接続を優先し、未検証の一律置換／再変換はしない。\n"
                "- 楽器名 → 演奏属性 → 楽器正式名は識別用の画素なしグループ。描画用楽器は首下一体差分内。\n"
                "- 楽器_前・楽器_後は未分離なので作成していない。各一体差分を同時表示しない。\n"
                "- 素材番号・一覧順は再生順や時間指定ではない。MIDI・時間制御・MusicStudio実登録は未検証。\n\n"
                "原素材の制約（PSD化で修正していない）\n"+
                '\n'.join('- '+x for x in guide['limits_ja'])+'\n\n'+
                '使用候補: '+guide['integrated_use_ja']+'\n\n'+
                '将来の分離可能性: '+LIMITS[item['instrument']]+'\n\n'+
                "残る制作: 既存頭部・表情差分との対応検証、原素材の不整合の判断。個別部位分割は別段階。\n"
                "全姿勢一覧.jpgとプレビュー/は保存PSDから描画した確認画像。PNGプレビューは透過背景。\n")
        (record/'作業報告.txt').write_text(report,encoding='utf-8-sig')
        progress.append(dict(instrument=item['instrument'],name_ja=item['name_ja'],pose_count=item['pose_count'],
                             psd=item['destination'],psd_sha256=app['file_sha256'],record_directory=str(record),
                             status='一体差分PSD保存・全姿勢切替検証済み。表情移植は未完了'))
    write_new(ROOT/'PSD変換進捗.json',dict(updated_at='2026-10-09',batch_1=progress,
              completed_core_instruments=4,completed_core_poses=36,remaining_core_instruments=15,
              remaining_core_poses=61,
              next='05_アコーディオン以降。通常配置マリンバ・補修候補・任意頭・箏構図用は別枠。',
              remaining_requirements='既存ボーカル頭部・表情レイヤーの移植、原素材の不整合判断。第2段階部位分割は未実施。',
              source_files_unchanged=True))
    print('Published four PSD records, 36 transparent previews and progress manifest. All source hashes unchanged.')

if __name__=='__main__':
    import sys
    if len(sys.argv)>1 and sys.argv[1]=='contacts':
        prepare_contacts()
    else:
        publish()
