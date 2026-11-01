"""Assemble actual Godot captures. Requires Pillow; no generated/retouched imagery."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys
ROOT=Path(__file__).resolve().parents[2]
RENDERS=ROOT/'build/roman-series-preview/renders'
SLUGS=['domus','insula','villa_rustica','baeckerei','toepferei','schmiede','muehle','curia','macellum','horreum','bibliothek','stadttor','leuchtturm','amphitheater','theater','capitolium','thermen','basilika','rundtempel']
NAMES=['Domus','Insula','Villa rustica','Bäckerei','Töpferei','Schmiede','Mühle','Curia','Macellum','Horreum','Bibliothek','Stadttor','Leuchtturm','Amphitheater','Theater','Capitolium','Thermen','Basilika','Rundtempel']
suffix=sys.argv[1] if len(sys.argv)>1 else ''
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',22)
out=Image.new('RGB',(2250,1950),'#fffbe9');draw=ImageDraw.Draw(out)
for i,(slug,name) in enumerate(zip(SLUGS,NAMES)):
    im=Image.open(RENDERS/(slug+suffix+'.png')).convert('RGB');im.thumbnail((450,450))
    x=i%5*450;y=i//5*487;out.paste(im,(x,y));draw.text((x+22,y+451),name,fill='#4a463c',font=font)
out.save(RENDERS/('all-19'+suffix+'.jpg'),quality=95)
for n in range(0,19,6):
    out=Image.new('RGB',(1500,1060),'#fffbe9');draw=ImageDraw.Draw(out)
    for i,slug in enumerate(SLUGS[n:n+6]):
        im=Image.open(RENDERS/(slug+suffix+'.png')).convert('RGB');im.thumbnail((500,500));x=i%3*500;y=i//3*530;out.paste(im,(x,y));draw.text((x+20,y+504),NAMES[n+i],fill='#4a463c',font=font)
    out.save(RENDERS/('gallery'+suffix+'-'+str(n//6+1)+'.jpg'),quality=94)
