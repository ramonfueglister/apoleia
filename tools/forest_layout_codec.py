"""DRAFT external storage backend/verifier. No engine, sampler, or source loader.
All tests use synthetic rows; production provider and publication are not implemented.
"""
from __future__ import annotations
import hashlib, json, math, os, struct, tempfile
from pathlib import Path

MAGIC=b"V19LAY01"
HEADER=struct.Struct("<8s6I6Q32s4i") # 128 bytes
INDEX=struct.Struct("<iiII4Q32s32s16s") # 128 bytes
ROW=struct.Struct("<ii7d") #64 bytes
FULL=(-42,-18,40,20) # x0,z0,x1,z1; half-open
ROOT=(-1017,-428,969,492)
ROOT_COUNT=(ROOT[2]-ROOT[0])*(ROOT[3]-ROOT[1])
MAX_CELLS=3116
MAX_ROWS=ROOT_COUNT
MAX_CELL_ROWS=1369 # Product's existing conservative cap, not inferred accepted count.
MAX_META=4096
MAX_FILE=HEADER.size+MAX_CELLS*INDEX.size+MAX_ROWS*ROW.size+MAX_CELLS*MAX_META
MAX_MANIFEST=1024*1024
STRIDES=(0,1,2,4,8,16,32,64,128)

def cells(bounds=FULL):
    x0,z0,x1,z1=bounds
    if not (FULL[0]<=x0<x1<=FULL[2] and FULL[1]<=z0<z1<=FULL[3]):raise ValueError("bounds")
    return ((x,z) for z in range(z0,z1) for x in range(x0,x1))

def canonical_binding(value):
    """Canonical ASCII JSON; floats use exact explicit binary64-LE tags."""
    def convert(x):
        if isinstance(x,float):
            if not math.isfinite(x):raise ValueError("nonfinite binding")
            return {"$f64le":struct.pack("<d",x).hex()}
        if isinstance(x,dict):
            if not all(isinstance(k,str) for k in x):raise ValueError("binding keys")
            return {k:convert(v) for k,v in x.items()}
        if isinstance(x,(list,tuple)):return [convert(v) for v in x]
        if x is None or isinstance(x,(str,bool,int)):return x
        raise ValueError("binding type")
    return json.dumps(convert(value),sort_keys=True,ensure_ascii=True,separators=(",",":"),allow_nan=False).encode("ascii")

DIGEST_FIELDS=("source_manifest_sha256","upload_manifest_sha256","source_sampler_sha256","canonical_surface_identity_sha256","ground_sampler_sha256","sampling_callbacks_sha256","style_sha256","template_arrays_sha256","compact_module_sha256")
def validate_binding(raw):
    if not raw or len(raw)>MAX_MANIFEST:raise ValueError("missing/oversized binding")
    value=json.loads(raw,parse_constant=lambda x:(_ for _ in ()).throw(ValueError("nonfinite JSON")))
    if not isinstance(value,dict) or value.get("format")!="v19-layout-binding-r1":raise ValueError("binding schema")
    for key in DIGEST_FIELDS:
        text=value.get(key,"")
        if not isinstance(text,str) or len(text)!=64 or any(c not in "0123456789abcdef" for c in text):raise ValueError("missing binding dependency "+key)
    if not value.get("engine_build") or not value.get("policy") or not value.get("numerics"):raise ValueError("missing engine/policy/numerics")
    region=value.get("region",{})
    if region.get("chunk_bounds")!=list(FULL) or region.get("root_bounds")!=list(ROOT) or not region.get("world_min") or not region.get("world_size"):raise ValueError("full region binding")
    return value

def digest(raw):return hashlib.sha256(raw).digest()
def bounded_span(offset,size,limit):
    # Explicit subtraction avoids addition overflow in future native/GDScript ports.
    if not isinstance(offset,int) or not isinstance(size,int) or offset<0 or size<0 or offset>limit or size>limit-offset:raise ValueError("offset/size overflow")
    return offset,offset+size

def pack_row(record):
    if len(record)!=10:raise ValueError("ten-field record")
    # Ground at r7 is deliberately excluded; all other original values are copied.
    return ROW.pack(record[0],record[1],*record[2:7],*record[8:10])
def restore_row(row,ground):
    # No rounding beyond the eventual existing Godot Vector3/Transform packing.
    r=list(row);return r[:7]+[ground]+r[7:]

def validate_row(row,cell,seen):
    x,z,px,pz,height,phase,width,sx,sz=row
    if not all(math.isfinite(v) for v in row[2:]):raise ValueError("nonfinite row")
    if not (ROOT[0]<=x<ROOT[2] and ROOT[1]<=z<ROOT[3]):raise ValueError("root range")
    if not (cell[0]*128.0<=px<(cell[0]+1)*128.0 and cell[1]*128.0<=pz<(cell[1]+1)*128.0):raise ValueError("wrong final cell")
    if not (.25<=height<=8.6 and 0.0<=phase<=math.tau and width in (1.,1.18)):raise ValueError("V19 value range")
    # Existing Vector2 values must be representable exactly as current Float32.
    if any(struct.unpack("<f",struct.pack("<f",v))[0]!=v for v in (px,pz,sx,sz)):raise ValueError("not original Vector2F32")
    key=(z-ROOT[1])*(ROOT[2]-ROOT[0])+x-ROOT[0]
    byte,bit=divmod(key,8)
    if seen[byte] & (1<<bit):raise ValueError("duplicate root")
    seen[byte]|=1<<bit

def write_layout(path,provider,binding_bytes,*,bounds=FULL):
    """Storage-only draft compiler. provider yields (cell, ten-field rows, metadata).
    Must be called only for authorized synthetic fixtures until a separately reviewed
    Godot directAPI provider exists. One chunk records+metadata in flight at a time.
    Caller owns atomic publication/resume; no READY/production manifest emitted.
    """
    validate_binding(binding_bytes)
    order=list(cells(bounds));count=len(order);record_start=128+128*count
    seen=bytearray((ROOT_COUNT+7)//8);entries=[];nrows=0
    path=Path(path)
    with path.open("xb+") as out,tempfile.TemporaryFile() as meta:
        out.seek(record_start)
        iterator=iter(provider)
        for cell in order:
            try:actual,records,metadata=next(iterator)
            except StopIteration as exc:raise ValueError("missing cell") from exc
            if tuple(actual)!=cell:raise ValueError("missing/duplicate/out-of-order cell")
            if len(records)>MAX_CELL_ROWS:raise ValueError("cell row limit")
            start=out.tell();h=hashlib.sha256();previous=None
            for record in records:
                raw=pack_row(record);row=ROW.unpack(raw);validate_row(row,cell,seen)
                key=(row[1],row[0])
                if previous is not None and key<=previous:raise ValueError("root scan order")
                previous=key;out.write(raw);h.update(raw);nrows+=1
                if nrows>MAX_ROWS:raise ValueError("global row limit")
            metadata_raw=json.dumps(metadata,sort_keys=True,separators=(",",":"),ensure_ascii=True,allow_nan=False).encode("ascii")
            if len(metadata_raw)>MAX_META:raise ValueError("metadata limit")
            mo=meta.tell();meta.write(metadata_raw)
            entries.append((cell[0],cell[1],1|(2 if not records else 0),len(records),start,out.tell()-start,mo,len(metadata_raw),h.digest(),digest(metadata_raw),bytes(16)))
        try:next(iterator)
        except StopIteration:pass
        else:raise ValueError("extra/duplicate cell")
        meta_start=out.tell();meta.seek(0)
        while block:=meta.read(64*1024):out.write(block)
        size=out.tell()
        if size>MAX_FILE:raise ValueError("file byte limit")
        out.seek(0);out.write(HEADER.pack(MAGIC,1,0,128,64,128,0,count,nrows,128,record_start,meta_start,size,digest(binding_bytes),*bounds))
        for row in entries:
            row=list(row);row[6]+=meta_start;out.write(INDEX.pack(*row))
        out.flush();os.fsync(out.fileno())
    return {"format":"v19-layout64-le-r1-draft","file_bytes":size,"rows":nrows,"cells":count,"binding_sha256":digest(binding_bytes).hex()}

def verify_layout(path,expected_binding,*,expected_bounds=FULL,byte_budget=256*1024):
    """Strict bounded reads; validates all cells including empty, digests and ranges.
    Output is aggregate only; real loader must release chunks under queue ownership.
    """
    validate_binding(expected_binding)
    if not 128<=byte_budget<=16*1024*1024:raise ValueError("reader byte budget")
    path=Path(path);actual_size=path.stat().st_size
    if actual_size<128 or actual_size>MAX_FILE:raise ValueError("file byte limit")
    seen=bytearray((ROOT_COUNT+7)//8);total=0;max_read=0;accepted=hashlib.sha256()
    with path.open("rb") as f:
        h=HEADER.unpack(f.read(128))
        magic,version,flags,hsize,rsize,isize,reserved,ncells,nrows,index_start,record_start,meta_start,file_size,binding,*bounds=h
        expected=list(cells(tuple(expected_bounds)))
        if (magic,version,flags,hsize,rsize,isize,reserved)!=(MAGIC,1,0,128,64,128,0):raise ValueError("header format")
        if tuple(bounds)!=tuple(expected_bounds) or ncells!=len(expected) or ncells>MAX_CELLS or nrows>MAX_ROWS:raise ValueError("coverage/count")
        if binding!=digest(expected_binding):raise ValueError("binding mismatch (source/G/code/engine/policy)")
        if index_start!=128 or record_start!=128+ncells*128 or meta_start!=record_start+nrows*64 or file_size!=actual_size:raise ValueError("header offsets")
        bounded_span(record_start,nrows*64,file_size);bounded_span(meta_start,file_size-meta_start,file_size)
        next_row=record_start;next_meta=meta_start
        for ordinal,cell in enumerate(expected):
            f.seek(128+ordinal*128);raw_index=f.read(128)
            x,z,flags,count,offset,nbytes,mo,mb,sha,msha,reserved=INDEX.unpack(raw_index)
            if (x,z)!=cell or flags!=(1|(2 if count==0 else 0)) or reserved!=bytes(16):raise ValueError("cell order/coverage/flags")
            if count>MAX_CELL_ROWS or nbytes!=count*64 or nbytes>byte_budget or mb>MAX_META or mb>byte_budget:raise ValueError("cell byte budget/count")
            if offset!=next_row or mo!=next_meta:raise ValueError("overlap/gap/order")
            bounded_span(offset,nbytes,meta_start);bounded_span(mo,mb,file_size)
            f.seek(offset);raw=f.read(nbytes);max_read=max(max_read,len(raw))
            if len(raw)!=nbytes or digest(raw)!=sha:raise ValueError("row hash/short read")
            accepted.update(raw);previous=None
            for pos in range(0,nbytes,64):
                row=ROW.unpack_from(raw,pos);validate_row(row,cell,seen);key=(row[1],row[0])
                if previous is not None and key<=previous:raise ValueError("row order")
                previous=key
            f.seek(mo);metadata_raw=f.read(mb);max_read=max(max_read,len(metadata_raw))
            if len(metadata_raw)!=mb or digest(metadata_raw)!=msha:raise ValueError("metadata hash/short read")
            metadata=json.loads(metadata_raw,parse_constant=lambda x:(_ for _ in ()).throw(ValueError("nonfinite metadata JSON")))
            if not isinstance(metadata,dict):raise ValueError("metadata shape")
            next_row+=nbytes;next_meta+=mb;total+=count
        if total!=nrows or next_row!=meta_start or next_meta!=file_size:raise ValueError("totals/trailing bytes")
    return {"cells":ncells,"rows":total,"accepted_layout_records_sha256":accepted.hexdigest(),"maximum_single_read":max_read,"duplicate_root_bitset_bytes":len(seen)}
