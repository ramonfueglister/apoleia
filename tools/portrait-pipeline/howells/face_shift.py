# Per-origin shift of the founders' face genes from Howells's craniometric
# data (Howells, 1973, 1989, 1995; data via web.utk.edu/~auerbach/HOWL.htm).
# usage: python3 -I face_shift.py HOWELL.CSV|summary.csv baseline.txt > face_shift.json
#   (summary.csv: pop,sex,trait,n,mean,sd per population and sex)
#   baseline.txt: lines "origin MEANS zy go nme snme al nsn snprn ch pup pog"
#   from face_measure ORIGIN=o with no shifts (what the three base types do
#   already, so it is not counted twice).
# Traits (skull -> portrait gene): ZYB bizygomatic breadth -> headW (zy-zy),
# NPH upper face height -> headH (n-me), NLB nasal breadth -> noseW (al-al),
# NLH nasal height -> noseL, OBH orbit height -> eyeS, DKB interorbital
# breadth -> eyeD (skipped if absent). Missing values are 0 in the data. Shift in allele units: one within-population sd of a
# trait = 24 units (sd of the expressed face gene).
# Origins with data: Aegyptus = EGYPT (Late Period, Giza), Germania = NORSE
# and BERG pooled (medieval Oslo, 19th-c. Austria: later proxies).
# PLACEHOLDER: Gallia, Italia, Graecia, Syria, Africa interpolated by
# latitude between BERG (47.5 N) and EGYPT (30 N); craniofacial form follows
# climate in part (Roseman, 2004; Hubbe et al., 2009; not verified online).
import csv, json, sys, statistics as st
path, base = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(path, newline='', encoding='latin-1')))
cols = {k.strip().upper(): k for k in rows[0].keys()}
SUMMARY = set(cols) >= {'POP', 'SEX', 'TRAIT', 'N', 'MEAN', 'SD'}
popk = next((cols[c] for c in ('POPULATION', 'POP', 'POPNAME', 'POPULATIONNAME') if c in cols), None)
sexk = next((cols[c] for c in ('SEX',) if c in cols), None)
if popk is None or sexk is None:
    sys.exit(f'columns not found: {list(cols)[:20]}')
pops = sorted({r[popk].strip().upper() for r in rows})
print('populations:', pops, file=sys.stderr)
TRAITS = [('ZYB', 'headW', 0), ('NPH', 'headH', 2), ('NLB', 'noseW', 4), ('NLH', 'noseL', None), ('OBH', 'eyeS', None), ('DKB', 'eyeD', None)]
def val(r, t):
    try:
        v = float(r[cols[t]])
        return v if v > 0 else None
    except (KeyError, ValueError):
        return None
def sexcode(r):
    s = r[sexk].strip().upper()
    return 'M' if s in ('M', '1', 'MALE') else 'F' if s in ('F', '2', 'FEMALE') else None
stats = {}   # (pop, sex, trait) -> (mean, sd, n)
if SUMMARY:
    # already summarised per population, sex and trait (pop,sex,trait,n,mean,sd)
    for r in rows:
        stats[(r[cols['POP']].strip().upper(), r[cols['SEX']].strip().upper(), r[cols['TRAIT']].strip().upper())] = (float(r[cols['MEAN']]), float(r[cols['SD']]), int(r[cols['N']]))
for p in ([] if SUMMARY else pops):
    for sx in 'MF':
        for t, _, _ in TRAITS:
            v = [val(r, t) for r in rows if r[popk].strip().upper() == p and sexcode(r) == sx]
            v = [x for x in v if x is not None]
            if len(v) >= 5:
                stats[(p, sx, t)] = (st.mean(v), st.stdev(v), len(v))
def pooled_sd(t, sx):
    num = sum((n - 1) * sd * sd for (p, s, tt), (m, sd, n) in stats.items() if tt == t and s == sx)
    den = sum(n - 1 for (p, s, tt), (m, sd, n) in stats.items() if tt == t and s == sx)
    return (num / den) ** 0.5
def mean_of(plist, t, sx):
    v = [stats[(p, sx, t)][0] for p in plist if (p, sx, t) in stats]
    if not v:
        sys.exit(f'no data for {plist} {t} {sx}')
    return st.mean(v)
need = ['EGYPT', 'NORSE', 'BERG']
for p in need:
    if p not in pops:
        sys.exit(f'population {p} not in data: {pops}')
ORIG = ['Italia', 'Gallia', 'Germania', 'Graecia', 'Syria', 'Aegyptus', 'Africa']
LAT = {'Italia': 42.0, 'Gallia': 46.0, 'Graecia': 38.0, 'Syria': 35.0, 'Africa': 36.0}
out = {'source': 'Howells craniometric data; Germania NORSE+BERG, Aegyptus EGYPT; others PLACEHOLDER by latitude', 'z': {}, 'shift': {}}
bl = {}
for line in open(base):
    f = line.split()
    if len(f) > 2 and f[1] == 'MEANS':
        bl[int(f[0])] = [float(x) for x in f[2:]]
# the portrait's genes move several measures at once (headW also widens the
# nose): the three measured traits are solved together from the genes'
# mm per allele unit (gene_sens.txt, face_measure GENE_SENS at gain 1.6) and
# the within-origin sd at gain 1.6 (face_measure)
SENS = {}
import os
sp = os.path.join(os.path.dirname(os.path.abspath(base)), 'gene_sens.txt')
for line in open(sp):
    f = line.split()
    if len(f) == 9:
        SENS[f[0]] = [float(x) for x in f[1:]]
SDG = {0: 8.01, 2: 9.08, 4: 3.88}
solved = {}
for t, gene, mi in TRAITS:
    if not any(k[2] == t for k in stats):
        print(f'trait {t} not in data, skipped', file=sys.stderr)
        continue
    zs = {}
    for sx in 'MF':
        sd = pooled_sd(t, sx)
        eg, ge, be = mean_of(['EGYPT'], t, sx), mean_of(['NORSE', 'BERG'], t, sx), mean_of(['BERG'], t, sx)
        m = {'Aegyptus': eg, 'Germania': ge}
        for o, lat in LAT.items():
            w = min(max((lat - 30.0) / 17.5, 0.0), 1.0)
            m[o] = eg + (be - eg) * w
        g = st.mean(m.values())
        for o in ORIG:
            zs.setdefault(o, []).append((m[o] - g) / sd)
    z = {o: st.mean(v) for o, v in zs.items()}
    out['z'][t] = {o: round(z[o], 3) for o in ORIG}
    for k, o in enumerate(ORIG):
        if mi is not None and bl:
            gb = st.mean(bl[j][mi] for j in bl)
            # wanted change in mm: the data's difference at gain 1.6 minus what the base types give
            solved.setdefault(o, {})[gene] = (mi, z[o] * SDG[mi] - (bl[k][mi] - gb))
        else:
            out['shift'].setdefault(o, {})[gene] = round(z[o] * 24)
for o, want in solved.items():
    genes = list(want)
    import itertools
    # Gauss elimination on the small system  sum_g S[g][mi] * s_g = d_mi
    A = [[SENS[g][want[h][0]] for g in genes] for h in genes]
    b = [want[h][1] for h in genes]
    n = len(genes)
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(A[r][c]))
        A[c], A[piv], b[c], b[piv] = A[piv], A[c], b[piv], b[c]
        for r in range(n):
            if r != c:
                f_ = A[r][c] / A[c][c]
                A[r] = [x - f_ * y for x, y in zip(A[r], A[c])]
                b[r] -= f_ * b[c]
    for i, g in enumerate(genes):
        out['shift'][o][g] = round(b[i] / A[i][i])
json.dump(out, sys.stdout, indent=1)
print('\n// Rust (sim/src/dna.rs FACE_SHIFT):', file=sys.stderr)
print('const FACE_SHIFT: [&[(&str, i32)]; 7] = [' + ', '.join('&[' + ', '.join(f'("{g}", {v})' for g, v in out['shift'][o].items()) + ']' for o in ORIG) + '];', file=sys.stderr)
