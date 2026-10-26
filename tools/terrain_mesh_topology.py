"""Exact existing-F32-vertex edge noding; geometric IDs are separate from normal corners."""
import bisect, collections
import numpy as np

def node_existing_edges(vertices,normals,parent_y,indices):
    v=np.asarray(vertices,dtype='<f4');norm=np.asarray(normals,dtype='<f4');py=np.asarray(parent_y,dtype='<f4');ix=np.asarray(indices,dtype='<i4').reshape(-1,3)
    positions={};canonical=[];mapping=[]
    for i,p in enumerate(v):
        key=(float(p[0]),float(p[2]))
        if key not in positions:positions[key]=len(canonical);canonical.append(i)
        gid=positions[key];first=canonical[gid]
        if v[i,1].tobytes()!=v[first,1].tobytes() or py[i].tobytes()!=py[first].tobytes():raise ValueError('incompatible geometric endpoint identity')
        mapping.append(gid)
    mapping=np.asarray(mapping,dtype='<i4');unique=v[canonical][:,[0,2]];edges=collections.Counter(tuple(sorted((int(a),int(b)))) for t in mapping[ix] for a,b in [(t[0],t[1]),(t[1],t[2]),(t[2],t[0])])
    rows=collections.defaultdict(list);cols=collections.defaultdict(list)
    for gid,(x,z) in enumerate(unique):rows[float(z)].append((float(x),gid));cols[float(x)].append((float(z),gid))
    for line in list(rows.values())+list(cols.values()):line.sort()
    partitions={}
    for edge,count in edges.items():
        if count!=1:continue
        a,b=edge;p,q=unique[a],unique[b];line=None;axis=0
        if p[1]==q[1]:line=rows[float(p[1])]
        elif p[0]==q[0]:line=cols[float(p[0])];axis=1
        if line is None:continue
        lo,hi=sorted((float(p[axis]),float(q[axis])));start=bisect.bisect_right(line,(lo,2**63));end=bisect.bisect_left(line,(hi,-1));middle=[gid for _,gid in line[start:end]]
        if middle:partitions[edge]=middle if p[axis]<q[axis] else middle[::-1]
    if not partitions:return v,norm,py,ix.reshape(-1),mapping,{'noded_edges':0,'added_corners':0}
    points=v.tolist();normals_out=norm.tolist();parents=py.tolist();ids=mapping.tolist();out=[]
    def cross(a,b,c):return (float(b[0])-float(a[0]))*(float(c[2])-float(a[2]))-(float(b[2])-float(a[2]))*(float(c[0])-float(a[0]))
    def earclip(poly):
        pending=list(poly);result=[]
        while len(pending)>3:
            found=False
            for k in range(len(pending)):
                a,b,c=pending[k-1],pending[k],pending[(k+1)%len(pending)]
                if cross(points[a],points[b],points[c])<=0:continue
                if any(cross(points[a],points[b],points[t])>=0 and cross(points[b],points[c],points[t])>=0 and cross(points[c],points[a],points[t])>=0 for t in pending if t not in (a,b,c)):continue
                result.extend((a,b,c));pending.pop(k);found=True;break
            if not found:raise ValueError('non-simple or collapsed noding polygon')
        if cross(points[pending[0]],points[pending[1]],points[pending[2]])<=0:raise ValueError('collapsed final noding triangle')
        result.extend(pending);return result
    for face in ix:
        poly=[];changed=False
        for k in range(3):
            a=int(face[k]);b=int(face[(k+1)%3]);poly.append(a);ga,gb=int(mapping[a]),int(mapping[b]);edge=tuple(sorted((ga,gb)));middle=partitions.get(edge,[])
            if ga>gb:middle=middle[::-1]
            if not middle:continue
            changed=True;axis=0 if v[a,0]!=v[b,0] else 2
            for gid in middle:
                original=canonical[gid];t=(float(v[original,axis])-float(v[a,axis]))/(float(v[b,axis])-float(v[a,axis]));normal=(norm[a].astype('f8')*(1-t)+norm[b].astype('f8')*t).astype('<f4')
                poly.append(len(points));points.append(v[original].tolist());normals_out.append(normal.tolist());parents.append(float(py[original]));ids.append(gid)
        if changed:out.extend(earclip(poly))
        else:out.extend(int(i) for i in face)
    return np.asarray(points,dtype='<f4'),np.asarray(normals_out,dtype='<f4'),np.asarray(parents,dtype='<f4'),np.asarray(out,dtype='<i4'),np.asarray(ids,dtype='<i4'),{'noded_edges':len(partitions),'added_corners':len(points)-len(v)}

def topology(vertices,indices,geometry_ids):
    v=np.asarray(vertices);tri=np.asarray(geometry_ids)[np.asarray(indices).reshape(-1,3)];used=set(tri.flat);ed=collections.Counter(tuple(sorted((int(a),int(b)))) for t in tri for a,b in [(t[0],t[1]),(t[1],t[2]),(t[2],t[0])]);position={int(g):v[i,[0,2]] for i,g in enumerate(geometry_ids)};lo=v[:,[0,2]].min(0);hi=v[:,[0,2]].max(0);inner=0
    for (a,b),count in ed.items():
        if count==1 and not any(position[a][k]==position[b][k] and position[a][k] in (lo[k],hi[k]) for k in (0,1)):inner+=1
    return {'Euler':len(used)-len(ed)+len(tri),'inner_unpaired_edges':inner,'nonmanifold_edges':sum(c>2 for c in ed.values()),'geometry_vertices':len(used),'faces':len(tri)}
