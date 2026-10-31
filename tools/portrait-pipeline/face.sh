#!/bin/sh
# face.sh out : 3 faces zoomed (man with beard, veiled-free woman, shaven man) from the clothes test sets
cd /home/claude/work
export TB="910000=short,910001=full,910002=short,910003=shaven,910004=phil,910005=stubble"
CLOTHES=1 PJ=${PJ:-/home/claude/work/kleider_b.json} ./beard.sh /tmp/face_a.png 0,3,5,7,9,10,6,8,1,2,4,11
python3 -I -c "
from PIL import Image
import sys
im=Image.open('/tmp/face_a.png')
xs=[0,350,700,1050,1400,1750]
tiles=[im.crop((x+60,40,x+300,330)).resize((360,435), Image.LANCZOS) for x in xs[:3]]+[im.crop((x+60,475,x+300,765)).resize((360,435), Image.LANCZOS) for x in xs[:3]]
o=Image.new('RGB',(1080,870))
for i,t in enumerate(tiles): o.paste(t,((i%3)*360,(i//3)*435))
o.save(sys.argv[1])" $1
