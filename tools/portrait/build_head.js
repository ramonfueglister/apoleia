// Builds app/assets/portrait/head.bin.zst, the head and shoulders the
// portraits are made from (sim/portrait, docs/kit2/PORTRAITS.md), out of
// the MakeHuman base mesh and its morph targets (CC0, see
// app/assets/portrait/LICENSE.md).
//
//   npm install --prefix /tmp/mh meshoptimizer@0.21.0
//   NODE_PATH=/tmp/mh/node_modules node tools/portrait/build_head.js <data> [out]
//
// <data> is MakeHuman's makehuman/data folder (github.com/makehumancommunity/
// makehuman, branch master) or a copy with 3dobjs/base.obj,
// modifiers/modeling_modifiers.json and the targets/<group>/<name>.target
// files listed below. Kept: everything above y = 3.4 within |x| < 2.85
// (head, neck, shoulders), the body in four levels of detail (meshoptimizer,
// borders locked), the clothing helper ("tights") in two, the eyes; the
// targets of the face groups and the macro targets (sex × age × base type,
// sex × age × muscle × weight) from baby to old, deltas rounded to 1/3000
// (the largest, a baby's, still fits an i16).
//
// File layout, little endian: "APOLHEAD" | version u32 | vertex count u32 |
// positions f32 × 3 | part count u32 | per part: name (u8 length + UTF-8),
// level count u32, per level: index count u32, indices u16 | target count
// u32 | per target: name, count u32, vertex ids u16 × count, deltas
// i16 × 3 × count; all of it one zstd frame.
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const { MeshoptSimplifier } = require('meshoptimizer');

const GROUPS = ['head', 'forehead', 'eyebrows', 'neck', 'eyes', 'nose', 'mouth', 'ears', 'chin', 'cheek', 'torso'];
const Y0 = 3.4, XM = 2.85, SCALE = 3000;

(async () => {
  const [data, out = path.join(__dirname, '../../app/assets/portrait/head.bin.zst')] = process.argv.slice(2);
  if (!data) throw new Error('usage: build_head.js <makehuman data folder> [out]');
  await MeshoptSimplifier.ready;
  const vs = [], faces = {};
  let g = null;
  for (const l of fs.readFileSync(path.join(data, '3dobjs/base.obj'), 'utf8').split('\n')) {
    if (l.startsWith('v ')) vs.push(l.split(/\s+/).slice(1, 4).map(Number));
    else if (l.startsWith('g ')) g = l.split(/\s+/)[1];
    else if (l.startsWith('f ')) (faces[g] = faces[g] || []).push(l.trim().split(/\s+/).slice(1).map(x => parseInt(x) - 1));
  }
  const keep = f => f.every(i => vs[i][1] > Y0 && Math.abs(vs[i][0]) < XM);
  const parts = { body: faces.body.filter(keep), tights: faces['helper-tights'].filter(keep), hair: faces['helper-hair'], leye: faces['helper-l-eye'], reye: faces['helper-r-eye'] };
  const usedSet = new Set();
  for (const p of Object.values(parts)) for (const f of p) for (const i of f) usedSet.add(i);
  const used = [...usedSet].sort((a, b) => a - b), remap = new Map(used.map((o, n) => [o, n]));
  const N = used.length, pos = new Float32Array(N * 3);
  used.forEach((o, n) => pos.set(vs[o], n * 3));
  const tri = fs => { const r = []; for (const f of fs) { const q = f.map(i => remap.get(i)); for (let k = 1; k + 1 < q.length; k++) r.push(q[0], q[k], q[k + 1]); } return new Uint32Array(r); };

  const chunks = [];
  const u32 = v => { const b = Buffer.alloc(4); b.writeUInt32LE(v); chunks.push(b); };
  const name = s => { const b = Buffer.from(s, 'utf8'); chunks.push(Buffer.from([b.length]), b); };
  const raw = a => chunks.push(Buffer.from(a.buffer, a.byteOffset, a.byteLength));
  chunks.push(Buffer.from('APOLHEAD'));
  u32(1);
  u32(N);
  raw(pos);
  u32(Object.keys(parts).length);
  for (const [k, fsx] of Object.entries(parts)) {
    const idx = tri(fsx);
    const levels = k === 'body' ? [1400, 3000, 6000, idx.length / 3] : k === 'tights' ? [500, idx.length / 3] : [idx.length / 3];
    name(k);
    u32(levels.length);
    for (const L of levels) {
      let r = idx;
      if (L < idx.length / 3) [r] = MeshoptSimplifier.simplify(idx, pos, 3, Math.floor(L) * 3, 0.05, ['LockBorder']);
      u32(r.length);
      raw(new Uint16Array(r));
    }
  }
  // the targets: the face groups' modifiers, then the macro targets
  const mods = JSON.parse(fs.readFileSync(path.join(data, 'modifiers/modeling_modifiers.json'), 'utf8'));
  const files = [];
  for (const gr of mods) {
    if (!GROUPS.includes(gr.group)) continue;
    for (const m of gr.modifiers) {
      if (!m.target) continue;
      if (m.min) files.push(`${gr.group}/${m.target}-${m.min}`, `${gr.group}/${m.target}-${m.max}`);
      else files.push(`${gr.group}/${m.target}`);
    }
  }
  for (const eth of ['african', 'asian', 'caucasian']) for (const gen of ['male', 'female']) for (const age of ['baby', 'child', 'young', 'old']) files.push(`macrodetails/${eth}-${gen}-${age}`);
  for (const gen of ['male', 'female']) for (const age of ['baby', 'child', 'young', 'old']) for (const mu of ['minmuscle', 'averagemuscle', 'maxmuscle']) for (const w of ['minweight', 'averageweight', 'maxweight']) files.push(`macrodetails/universal-${gen}-${age}-${mu}-${w}`);
  const targets = [];
  for (const t of [...new Set(files)].sort()) {
    const file = path.join(data, 'targets', t + '.target');
    if (!fs.existsSync(file)) continue;
    const ids = [], d = [];
    for (const l of fs.readFileSync(file, 'utf8').split('\n')) {
      if (!l || l[0] === '#') continue;
      const a = l.trim().split(/\s+/);
      if (a.length < 4) continue;
      const i = +a[0];
      if (!remap.has(i)) continue;
      const x = +a[1], y = +a[2], z = +a[3];
      if (Math.abs(x) + Math.abs(y) + Math.abs(z) < 1e-4) continue;
      ids.push(remap.get(i));
      d.push(Math.round(x * SCALE), Math.round(y * SCALE), Math.round(z * SCALE));
    }
    if (d.some(v => Math.abs(v) > 32767)) throw new Error(`${t}: a delta does not fit an i16`);
    if (ids.length) targets.push({ t, ids, d });
  }
  u32(targets.length);
  for (const { t, ids, d } of targets) {
    name(t);
    u32(ids.length);
    raw(new Uint16Array(ids));
    raw(new Int16Array(d));
  }
  const all = Buffer.concat(chunks);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, zlib.zstdCompressSync(all, { params: { [zlib.constants.ZSTD_c_compressionLevel]: 19 } }));
  console.log('vertices', N, 'targets', targets.length, 'raw', all.length, 'zstd', fs.statSync(out).size);
})();
