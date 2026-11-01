"""Original stone-arch bridge modules for the measured Verona street graph.

Blender --background --factory-startup --python this_file -- --all
Or -- --model=verona_bridge_span. Blender Z up; X east, Y north.
The authoring origin is the parcel centre. No recentering or axis scaling.
The two stair assets are explicitly pedestrian approaches, not carriage ramps.
"""
import sys, math, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import roman_asset_kit as k
from mathutils import Vector

LENGTH=10.504201680672269
HALF=LENGTH/2
WIDTH=4.40
CLEAR_WIDTH=3.80
ROAD_WIDTH=2.5210084033613445
DECK_BOTTOM=-.45
SPRING=-4.60
ARCH_RX=4.10
ARCH_RZ=3.50
PIER_BOTTOM=-10.0
PARAPET_HEIGHT=1.10
STAIR_START=1.30
STAIR_RISE=6.302521008403361
DESCENT_DROP=8.403361344537815
STONE='Travertine';LIGHT='Limestone_trim';PLASTER='Limewash';DARK='Interior_shadow'
PAVERS=['Paving_0','Paving_1','Paving_2','Paving_3']


def mark():return {key:len(value[0]) for key,value in k.GEO.items()}


def transform_since(starts,fn):
    for key,geometry in k.GEO.items():
        for i in range(starts.get(key,0),len(geometry[0])):
            geometry[0][i]=tuple(fn(*geometry[0][i]))


def box(p,size,mat=STONE,bevel=.012):
    k.box(p,size,mat,bevel)


def xz_prism(poly,depth,mat=STONE,y=0):
    count=len(poly)
    verts=[(x,yy,z) for yy in [y-depth/2,y+depth/2] for x,z in poly]
    faces=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]
    faces.extend((i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count))
    k.mesh(verts,faces,mat,role='structure')


def xy_prism(poly,z0,z1,mat=STONE):
    count=len(poly);verts=[(x,y,z) for z in [z0,z1] for x,y in poly]
    faces=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]
    faces.extend((i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count))
    k.mesh(verts,faces,mat,role='structure')


def slab(x0,x1,y0,y1,top=0,bottom=DECK_BOTTOM):
    """Closed, exactly level deck; adjacent top polygons have no geometric gaps."""
    k.GROUP='Deck';k.ROLE='structure'
    # The bottom and four edges share the top's exact port coordinates.
    v=[(x,y,z) for z in [bottom,top] for x,y in [(x0,y0),(x1,y0),(x1,y1),(x0,y1)]]
    k.mesh(v,[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],STONE,role='structure')
    nx=max(1,math.ceil((x1-x0)/k.lod_count(.67,1.34,2.68)))
    ny=max(1,math.ceil((y1-y0)/k.lod_count(.55,1.10,2.20)))
    for row in range(ny):
        for col in range(nx):
            a=x0+(x1-x0)*col/nx;b=x0+(x1-x0)*(col+1)/nx
            c=y0+(y1-y0)*row/ny;d=y0+(y1-y0)*(row+1)/ny
            k.mesh([(a,c,top),(b,c,top),(b,d,top),(a,d,top)],[(0,1,2,3)],PAVERS[(row+col*3)%4],role='structure')


def face_courses(x0,x1,y,z0,z1,side=1):
    """Masonry remains a veneer over complete structural pier surfaces."""
    if k.LOD=='far':return
    k.ROLE='detail';course=k.lod_count(.48,.96,1.44)
    rows=max(1,math.ceil((z1-z0)/course))
    for row in range(rows):
        bottom=z0+(z1-z0)*row/rows;top=z0+(z1-z0)*(row+1)/rows
        count=max(1,math.ceil((x1-x0)/k.lod_count(.72,1.44,2.88)))
        for col in range(count):
            a=x0+(x1-x0)*col/count;b=x0+(x1-x0)*(col+1)/count
            box(((a+b)/2,y+side*.018,(bottom+top)/2),(b-a-.018,.036,top-bottom-.018),LIGHT if (row+col)%7==0 else STONE,.007)
    k.ROLE='structure'


def cutwater(side,bank_side):
    """Half triangular nose: adjoining cell ends form one complete shared pier."""
    x_port=side*HALF;x_inner=side*ARCH_RX
    y_bank=bank_side*2.20;y_tip=bank_side*3.0
    poly=[(x_inner,y_bank),(x_port,y_bank),(x_port,y_tip)]
    xy_prism(poly,PIER_BOTTOM,-1.55)
    # Sloped stone hood keeps water-facing noses visually lighter than the piers.
    v=[(x,y,-1.55) for x,y in poly]+[(x_inner,y_bank,-.58),(x_port,y_bank,-.58),(x_port,y_tip,-1.32)]
    k.mesh(v,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],LIGHT,role='structure')


def arch_structure():
    k.GROUP='BarrelVault';k.ROLE='structure'
    segments=k.lod_count(28,18,12);outer_x=ARCH_RX+.42;outer_z=ARCH_RZ+.45
    outer=[(outer_x*math.cos(i*math.pi/segments),SPRING+outer_z*math.sin(i*math.pi/segments)) for i in range(segments+1)]
    inner=[(ARCH_RX*math.cos(i*math.pi/segments),SPRING+ARCH_RZ*math.sin(i*math.pi/segments)) for i in range(segments,-1,-1)]
    xz_prism(outer+inner,WIDTH)
    # This is the complete curved wall above the vault, with a true intrados.
    underside=list(reversed(outer))
    xz_prism(underside+[(outer_x,DECK_BOTTOM),(-outer_x,DECK_BOTTOM)],WIDTH,PLASTER)
    k.GROUP='Piers'
    for side in [-1,1]:
        a,b=sorted((side*ARCH_RX,side*HALF))
        box(((a+b)/2,0,(PIER_BOTTOM+DECK_BOTTOM)/2),(b-a,WIDTH,DECK_BOTTOM-PIER_BOTTOM),STONE,0)
        for bank_side in [-1,1]:
            cutwater(side,bank_side)
            face_courses(a,b,bank_side*2.2,-7.0,-.55,bank_side)
    # Articulated arch stones on both facades, backed by the solid barrel.
    if k.LOD!='far':
        k.GROUP='Voussoirs';k.ROLE='detail'
        for side in [-1,1]:
            for i in range(segments):
                a=i*math.pi/segments+.004;b=(i+1)*math.pi/segments-.004
                poly=[(ARCH_RX*math.cos(a),SPRING+ARCH_RZ*math.sin(a)),(ARCH_RX*math.cos(b),SPRING+ARCH_RZ*math.sin(b)),(outer_x*math.cos(b),SPRING+outer_z*math.sin(b)),(outer_x*math.cos(a),SPRING+outer_z*math.sin(a))]
                xz_prism(poly,.065,LIGHT,side*2.225)
            # A keystone and a thin continuous cornice reinforce the rhythm.
            box((0,side*2.225,-.83),(.42,.075,.43),LIGHT,.012)
    k.GROUP='Cornice';k.ROLE='structure'
    for side in [-1,1]:
        box((0,side*2.17,-.23),(LENGTH,.06,.18),LIGHT,.008)


def parapet(x0,x1,y,width=.30,top=PARAPET_HEIGHT):
    k.GROUP='Parapets';k.ROLE='structure';length=x1-x0
    box(((x0+x1)/2,y,.46),(length,width-.04,.92),STONE,0)
    box(((x0+x1)/2,y,.08),(length,width,.16),LIGHT,.01)
    box(((x0+x1)/2,y,top-.09),(length,width,.18),LIGHT,.01)
    if k.LOD!='far':
        k.ROLE='detail';rows=k.lod_count(3,2,1)
        cols=max(1,math.ceil(length/k.lod_count(.70,1.40,2.80)))
        for row in range(rows):
            z=.17+(row+.5)*.74/rows
            for col in range(cols):
                x=x0+(col+.5)*length/cols
                for side in [-1,1]:
                    box((x,y+side*(width/2-.01),z),(length/cols-.018,.02,.74/rows-.016),STONE if (col+row)%5 else PLASTER,.005)
    k.ROLE='structure'


def rotated_parapet(y0,y1,x,width=.30):
    starts=mark();parapet(y0,y1,-x,width)
    transform_since(starts,lambda xx,yy,z:(-yy,xx,z))


def main_deck_and_rails(junction=False,end=False):
    slab(-HALF,HALF,-2.20,2.20)
    parapet(-HALF,HALF,-2.05)
    if junction:
        parapet(-HALF,-2.20,2.05);parapet(2.20,HALF,2.05)
        slab(-2.20,2.20,2.20,HALF)
        rotated_parapet(2.20,HALF,-2.05);rotated_parapet(2.20,HALF,2.05)
        # The bank-side support starts outside the free transverse river channel.
        k.GROUP='JunctionAbutment';k.ROLE='structure'
        box((0,(4.1+HALF)/2,(PIER_BOTTOM+DECK_BOTTOM)/2),(WIDTH,HALF-4.1,DECK_BOTTOM-PIER_BOTTOM),STONE,0)
        # Pair of structural corbels, wholly north of the +/-3.2 m clear channel.
        for side in [-1,1]:
            starts=mark()
            xz_prism([(3.25,DECK_BOTTOM),(4.1,DECK_BOTTOM),(4.1,-3.2)],.34,LIGHT,side*2.03)
            transform_since(starts,lambda x,y,z:(-y,x,z))
    else:
        parapet(-HALF,HALF,2.05)
    if end:
        # No invented east road exit: a closed cap forms the landing terminus.
        rotated_parapet(-2.20,2.20,4.75)


def span():
    arch_structure();main_deck_and_rails()


def junction():
    arch_structure();main_deck_and_rails(junction=True)


def end():
    arch_structure();main_deck_and_rails(end=True)


def descent():
    # Source-level engineering profile: runtime must not grade these treads.
    def grade(x):return -DESCENT_DROP*(x+HALF)/LENGTH
    starts=mark();arch_structure()
    parapet(-HALF,HALF,-2.05);parapet(-HALF,HALF,2.05)
    transform_since(starts,lambda x,y,z:(x,y,z+grade(x)))
    k.GROUP='HorizontalTreads';k.ROLE='structure'
    risers=math.ceil(DESCENT_DROP/.20);treads=risers+1;run=LENGTH/treads
    for i in range(treads):
        z=-DESCENT_DROP*i/risers
        box((-HALF+(i+.5)*run,0,z-.275),(run,WIDTH,.55),PAVERS[i%4],0)


def stairs():
    # A steep but explicitly pedestrian-only route to the existing northern bank.
    run=HALF-STAIR_START;risers=math.ceil(STAIR_RISE/.20);treads=risers+1;step=run/treads
    def grade(y):return STAIR_RISE*(y-STAIR_START)/run
    k.GROUP='StairStringer';k.ROLE='structure'
    starts=mark()
    # Keep the sloping support below every horizontal tread, including the
    # lowest first tread (maximum riser .197 m plus a .043 m clearance).
    xz_prism([(STAIR_START,-.65),(HALF,-.65),(HALF,-.24),(STAIR_START,-.24)],3.0,STONE)
    transform_since(starts,lambda x,y,z:(-y,x,z+grade(x)))
    for side in [-1,1]:
        starts=mark();rotated_parapet(STAIR_START,HALF,side*(ROAD_WIDTH/2+(3.0-ROAD_WIDTH)/4),(3.0-ROAD_WIDTH)/2)
        transform_since(starts,lambda x,y,z:(x,y,z+grade(y)))
    k.GROUP='HorizontalTreads';k.ROLE='structure'
    # The junction deck supplies station 0 at Z0. Do not duplicate its paving:
    # the first authored tread is one riser above that shared lower landing.
    for i in range(1,treads):
        z=STAIR_RISE*i/risers
        box((0,STAIR_START+(i+.5)*step,z-.275),(3.0,step,.55),PAVERS[i%4],0)

BUILDERS={'verona_bridge_span':span,'verona_bridge_junction':junction,'verona_bridge_end':end,'verona_bridge_stairs':stairs,'verona_bridge_descent':descent}


def finish_asset(slug):
    k.configure(slug);BUILDERS[slug]();k.finish(slug,rebuilder=BUILDERS[slug])
    path=k.OUT/'model.json';data=json.loads(path.read_text())
    data.update({'family':'verona_bridges','origin_policy':'authored','authored_origin_xyz':[0,0,0],
                 'source_axes':{'x':'east','y':'north','z':'up'},'parcel_length_m':LENGTH,
                 'road_width_m':ROAD_WIDTH,'deck_width_m':WIDTH,'clear_width_m':CLEAR_WIDTH,
                 'parapet_height_m':PARAPET_HEIGHT,'deck_top_z_m':0.0,
                 'historical_status':'Original artistic Roman bridge typology; not an archaeological reconstruction.'})
    if slug!='verona_bridge_stairs':
        data['arch']={'half_span_m':ARCH_RX,'spring_z_m':SPRING,'rise_m':ARCH_RZ,'crown_z_m':SPRING+ARCH_RZ,'deck_underside_z_m':DECK_BOTTOM,'pier_bottom_relative_deck_m':PIER_BOTTOM,'cutwater_half_width_m':3.0}
        data['ports']=['west','east']
        data['source_deck_profile']={'type':'flat','runtime_grade_allowed':True}
    if slug=='verona_bridge_junction':data['ports']=['west','east','north']
    if slug=='verona_bridge_end':
        data['ports']=['west'];data['east_barrier_x_m']=[4.60,4.90]
    if slug=='verona_bridge_stairs':
        risers=math.ceil(STAIR_RISE/.20)
        data.update({'ports':['south','north'],'deck_width_m':3.0,'clear_width_m':ROAD_WIDTH,
                     'pedestrian_only':True,'source_deck_profile':{'type':'stairs','axis':'y','start_m':STAIR_START,'end_m':HALF,'start_z_m':0.0,'end_z_m':STAIR_RISE,'risers':risers,'treads':risers+1,'total_levels':risers+1,'authored_treads':risers,'first_authored_tread_index':1,'lower_landing':'junction_deck','lower_landing_asset':'verona_bridge_junction','lower_landing_bounds_m':{'x':[-1.5,1.5],'y':[STAIR_START,STAIR_START+(HALF-STAIR_START)/(risers+1)],'z':0.0},'runtime_grade_allowed':False}})
    if slug=='verona_bridge_descent':
        risers=math.ceil(DESCENT_DROP/.20)
        data.update({'pedestrian_only':True,'source_deck_profile':{'type':'stairs','axis':'x','start_m':-HALF,'end_m':HALF,'start_z_m':0.0,'end_z_m':-DESCENT_DROP,'risers':risers,'treads':risers+1,'runtime_grade_allowed':False}})
    path.write_text(json.dumps(data,indent=2)+'\n')
    print('VERONA_BRIDGE_ASSET '+json.dumps(data))

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['--all']
    chosen=list(BUILDERS) if '--all' in args else [next(a.split('=',1)[1] for a in args if a.startswith('--model='))]
    for slug in chosen:finish_asset(slug)
