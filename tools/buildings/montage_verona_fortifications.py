"""Contact sheets of actual Godot captures; requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
RENDERS=ROOT/'build/roman-series-preview/renders'
OUT=ROOT/'docs/handover/verona-fortifications'
GROUPS=[['verona_wall_arm','verona_wall_diagonal','verona_wall_tower'],['verona_gate','verona_gate_crossing'],['verona_gate_link','verona_gate_diagonal_link'],['verona_tombs_altar','verona_tombs_shrine','verona_tombs_garden']]
try:
    font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',17)
except OSError:
    try:
        font=ImageFont.truetype('DejaVuSans.ttf',17)
    except OSError:
        font=ImageFont.load_default()
OUT.mkdir(parents=True,exist_ok=True)
for n,slugs in enumerate(GROUPS,1):
    out=Image.new('RGB',(1350,len(slugs)*480),'#fffbe9');draw=ImageDraw.Draw(out)
    for row,slug in enumerate(slugs):
        for col,(suffix,label) in enumerate([('','Detail'),('-medium','Medium'),('-far','Far')]):
            im=Image.open(RENDERS/(slug+suffix+'.png')).convert('RGB');im.thumbnail((450,450));x=col*450;y=row*480;out.paste(im,(x,y));draw.text((x+12,y+451),slug.removeprefix('verona_')+' · '+label,fill='#4a463c',font=font)
    out.save(OUT/f'asset-lods-{n}.jpg',quality=93)
