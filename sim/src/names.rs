//! Names (Ramon, 30.10.2026: "das System muss Namen erlauben bis Neuzeit.
//! Namen sind für Gruppen und Kulturen unterschiedlich, verändern sich";
//! proposal https://claude.ai/artifact/U712QGBqx82ovwuyFb4Eyd, step 1 chosen
//! the same day: names around 300 for the seven origins; docs/kit2/NAMES.md).
//!
//! The parts of the proposal built here: the stock of names
//! (sim/data/names/c0300.tsv: every name a form in its language, with the
//! stems it shares with related names and its weight in each origin), the
//! naming order of each origin (which parts a full name has), the choice of
//! the parents at a birth, and lines with their family name. Bynames from
//! life (step 2) and changes of the naming order (step 3) come later; a new
//! epoch or culture is a new data file, not new code.
//!
//! The choice at a birth, with shares per origin from the data (`param`
//! rows, PLACEHOLDER):
//! 1. a relative's name (`kin`): a boy after his father's father, his
//!    father or his mother's father, a girl after her father's mother, her
//!    mother or her mother's mother; one who died in the last three years
//!    counts 2.7 times (Todd & Coulmont 2021: sons named after a father who
//!    died in the pregnancy 2.7 times as often);
//! 2. a name sharing a stem with a relative's (`var`): Victorinus after
//!    Victor (derived Latin cognomina, Kajanto 1965), Theudericus after
//!    Theudemer (Germanic variation, Mitterauer 1993);
//! 3. else a copy of the names given in the last years, in the region
//!    (`local`) or in the whole culture, each birth counted by the parents'
//!    estate (prestige trickles down, Lieberson 2000), weighed by
//!    frequency-dependent selection: rare names gain, common ones lose
//!    (Newberry & Plotkin 2022); a few (`innov`) take up a rare old name of
//!    the stock (innovation in the copying model of Hahn & Bentley 2003).
//! No living sibling gets the same name.
//!
//! Lines: a child belongs to its father's line and carries its family name
//! (nomen gentilicium); a woman keeps hers when she marries (Salway 1994).
//! In the start population each household is a line.
//!
//! Determinism: names draw from hashes of their own (NAME_SALT), so the rest
//! of the simulation runs the same with them, and a game loaded from its log
//! gets the same names again. Read by the view only, not in the fingerprint.

use crate::life::YEAR;
use std::sync::OnceLock;
use xxhash_rust::xxh3::xxh3_64;

pub const NONE: u32 = u32::MAX;
/// Origins, as crate::dna::ORIGINS.
const N: usize = 7;
/// Not dead (Named::died).
pub const ALIVE: i32 = i32::MAX;

/// How a given name was chosen (Named::how).
pub const START: u8 = 0;
pub const KIN: u8 = 1;
pub const VARIANT: u8 = 2;
pub const LOCAL: u8 = 3;
pub const CULTURE: u8 = 4;
pub const RARE: u8 = 5;
/// Whose name (Named::rel), and DEAD when that one had died at the naming.
pub const FF: u8 = 1;
pub const F: u8 = 2;
pub const MF: u8 = 3;
pub const FM: u8 = 4;
pub const M: u8 = 5;
pub const MM: u8 = 6;
pub const DEAD: u8 = 0x80;

/// PLACEHOLDER: weight of each kin's name for a boy (father's father,
/// father, mother's father) and a girl (father's mother, mother, mother's
/// mother); papponymy first, as in Greek and Roman families.
const KIN_W: [f32; 3] = [3.0, 2.0, 1.0];
/// Todd & Coulmont (2021): a dead relative's name, within DEAD_YEARS.
const DEAD_W: f32 = 2.7;
const DEAD_YEARS: i64 = 3;
/// PLACEHOLDER: a birth counts in the copying pools by the father's estate
/// (rural, city, eques, senator): prestige (Lieberson 2000).
const PRESTIGE: [f32; 4] = [1.0, 2.0, 6.0, 12.0];
/// PLACEHOLDER: the culture's pool is the births of about the last ten
/// years (decays by 1/e in TEN years).
const POOL_YEARS: f32 = 10.0;
/// Newberry & Plotkin (2022): selection per year about +1.4 % for names
/// with a share of 1 in 10,000 and -1.6 % for 1 in 100, taken as linear in
/// log10 of the share and bounded at ±3 %; a pool of POOL_YEARS turns it
/// into a weight of 1 + POOL_YEARS · s per copy.
const SEL_PER_DECADE: f32 = -0.015;
const SEL_MAX: f32 = 0.03;
/// Births remembered per region for the local pool.
const RING: usize = 48;
/// PLACEHOLDER: a child takes its names from the mother's culture instead
/// of the father's with this chance (the line stays the father's).
const MOTHER_POOL: f64 = 0.25;
/// Ages remembered in the local pool at the start (children and youths).
const START_LOCAL_YEARS: i64 = 20;
/// First salt of the name draws, far from every other in crate::people.
const NAME_SALT: u32 = 0x4e41_0000;

/// One name in its language: text, the Greek genitive for father's names
/// (empty if none), sex, language, the stems it shares with related names,
/// its weight in each origin, a note.
pub struct Form {
    pub text: String,
    pub gen: String,
    pub female: bool,
    pub lang: String,
    pub elems: Vec<u16>,
    pub w: [f32; N],
    pub note: String,
}

/// A family name: Latin and Greek form (masculine), weights of commoners'
/// and of senators' and equites' lines by origin, a note.
pub struct Nomen {
    pub lat: String,
    pub grc: String,
    pub w: [f32; N],
    pub elite: [f32; N],
    pub note: String,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Part {
    Praenomen,
    Nomen,
    NomenGreek,
    Given,
    FatherGen,
    FatherBar,
}

/// Forms (indices) and their running weights, for a draw.
#[derive(Default)]
struct Pick {
    ids: Vec<u16>,
    cum: Vec<f64>,
}

impl Pick {
    fn new(items: impl Iterator<Item = (u16, f64)>) -> Pick {
        let mut p = Pick::default();
        let mut sum = 0.0;
        for (id, w) in items.filter(|x| x.1 > 0.0) {
            sum += w;
            p.ids.push(id);
            p.cum.push(sum);
        }
        p
    }

    fn draw(&self, u: f64) -> Option<u16> {
        let total = *self.cum.last()?;
        let k = self.cum.partition_point(|&c| c <= u * total).min(self.ids.len() - 1);
        Some(self.ids[k])
    }
}

/// The stock of names of an epoch (one data file).
pub struct Stock {
    pub forms: Vec<Form>,
    pub nomina: Vec<Nomen>,
    praenomina: Vec<(String, f32)>,
    /// Per origin the parts of a full name, and whether a part is for
    /// senators and equites only.
    order: [Vec<(Part, bool)>; N],
    kin: [f64; N],
    var: [f64; N],
    local: [f64; N],
    innov: [f64; N],
    /// Forms by origin and sex (0 male, 1 female), and family names by
    /// origin for commoners and the elite.
    pick: Vec<Pick>,
    nomen_pick: Vec<Pick>,
    elite_pick: Vec<Pick>,
}

const DATA_0300: &str = include_str!("../data/names/c0300.tsv");

/// The stock of names around 300 (sim/data/names/c0300.tsv).
pub fn stock() -> &'static Stock {
    static S: OnceLock<Stock> = OnceLock::new();
    S.get_or_init(|| Stock::parse(DATA_0300).expect("sim/data/names/c0300.tsv"))
}

fn weights(cols: &[&str]) -> Result<[f32; N], String> {
    let mut w = [0.0; N];
    for (o, c) in cols.iter().take(N).enumerate() {
        w[o] = c.parse().map_err(|_| format!("weight {c}"))?;
    }
    Ok(w)
}

impl Stock {
    pub fn parse(text: &str) -> Result<Stock, String> {
        let mut elems: Vec<String> = Vec::new();
        let mut elem = |e: &str| -> u16 {
            match elems.iter().position(|x| x == e) {
                Some(i) => i as u16,
                None => {
                    elems.push(e.to_owned());
                    (elems.len() - 1) as u16
                }
            }
        };
        let mut forms = Vec::new();
        let mut nomina: Vec<Nomen> = Vec::new();
        let mut praenomina = Vec::new();
        let mut pre: Vec<(String, u16, [f32; N])> = Vec::new();
        let mut post: Vec<(bool, String, u16, f32)> = Vec::new();
        let mut order: [Vec<(Part, bool)>; N] = Default::default();
        let (mut kin, mut var, mut local, mut innov) = ([0.0; N], [0.0; N], [0.0; N], [0.0; N]);
        for line in text.lines().filter(|l| !l.is_empty() && !l.starts_with('#') && !l.starts_with("kind\t")) {
            let c: Vec<&str> = line.split('\t').collect();
            if c.len() < 13 {
                return Err(format!("short row: {line}"));
            }
            let note = c.get(13).copied().filter(|n| *n != "-").unwrap_or("").to_owned();
            let w = || weights(&c[6..13]);
            match c[0] {
                "given" => forms.push(Form {
                    text: c[3].to_owned(),
                    gen: if c[4] == "-" { String::new() } else { c[4].to_owned() },
                    female: c[1] == "f",
                    lang: c[2].to_owned(),
                    elems: c[5].split(',').map(&mut elem).collect(),
                    w: w()?,
                    note,
                }),
                "pre" => pre.push((c[3].to_owned(), elem(c[5]), w()?)),
                "post" => post.push((c[1] == "f", c[3].to_owned(), elem(c[5]), w()?[2])),
                "nomen" | "elite" => {
                    let at = match nomina.iter().position(|n| n.lat == c[3]) {
                        Some(i) => i,
                        None => {
                            nomina.push(Nomen { lat: c[3].to_owned(), grc: c[4].to_owned(), w: [0.0; N], elite: [0.0; N], note: String::new() });
                            nomina.len() - 1
                        }
                    };
                    if c[0] == "nomen" {
                        nomina[at].w = w()?;
                        nomina[at].note = note;
                    } else {
                        nomina[at].elite = w()?;
                    }
                }
                "praenomen" => praenomina.push((c[3].to_owned(), w()?[0])),
                "order" => {
                    for (o, spec) in c[6..13].iter().enumerate() {
                        let mut parts: Vec<(Part, bool)> = Vec::new();
                        for ch in spec.chars() {
                            let part = match ch {
                                'P' => Part::Praenomen,
                                'N' => Part::Nomen,
                                'H' => Part::NomenGreek,
                                'G' => Part::Given,
                                'F' => Part::FatherGen,
                                'B' => Part::FatherBar,
                                '?' => {
                                    if let Some(last) = parts.last_mut() {
                                        *last = (last.0, true);
                                    }
                                    continue;
                                }
                                _ => return Err(format!("order {spec}")),
                            };
                            parts.push((part, false));
                        }
                        order[o] = parts;
                    }
                }
                "param" => {
                    let w = w()?.map(|x| x as f64);
                    match c[3] {
                        "kin" => kin = w,
                        "var" => var = w,
                        "local" => local = w,
                        "innov" => innov = w,
                        p => return Err(format!("param {p}")),
                    }
                }
                k => return Err(format!("kind {k}")),
            }
        }
        // Germanic names: each fore-element with each hind-element of the
        // sex (not twice the same stem), weighted as the fore-element times
        // the hind-element's share among its sex.
        for female in [false, true] {
            let total: f32 = post.iter().filter(|p| p.0 == female).map(|p| p.3).sum();
            for (pt, pe, pw) in &pre {
                for (_, qt, qe, qw) in post.iter().filter(|p| p.0 == female && p.2 != *pe) {
                    forms.push(Form {
                        text: format!("{pt}{qt}"),
                        gen: String::new(),
                        female,
                        lang: "ger".to_owned(),
                        elems: vec![*pe, *qe],
                        w: pw.map(|x| x * qw / total),
                        note: String::new(),
                    });
                }
            }
        }
        if forms.len() >= u16::MAX as usize || order.iter().any(|o| o.is_empty()) {
            return Err("too many names or an origin without an order".to_owned());
        }
        let mut pick = Vec::new();
        for o in 0..N {
            for female in [false, true] {
                pick.push(Pick::new(forms.iter().enumerate().filter(|f| f.1.female == female).map(|(i, f)| (i as u16, f.w[o] as f64))));
            }
        }
        let nomen_pick = (0..N).map(|o| Pick::new(nomina.iter().enumerate().map(|(i, n)| (i as u16, n.w[o] as f64)))).collect();
        let elite_pick = (0..N).map(|o| Pick::new(nomina.iter().enumerate().map(|(i, n)| (i as u16, n.elite[o] as f64)))).collect();
        Ok(Stock { forms, nomina, praenomina, order, kin, var, local, innov, pick, nomen_pick, elite_pick })
    }

    fn draw(&self, origin: u8, female: bool, u: f64) -> u16 {
        let o = (origin as usize).min(N - 1);
        self.pick[2 * o + female as usize].draw(u).or_else(|| self.pick[female as usize].draw(u)).unwrap_or(0)
    }

    fn share_stem(&self, a: u16, b: u16) -> bool {
        let (ea, eb) = (&self.forms[a as usize].elems, &self.forms[b as usize].elems);
        ea.iter().any(|e| eb.contains(e))
    }
}

/// A person's name: the given name and the father's (both forms of the
/// stock), the line, how the given name was chosen and after whom, and the
/// day of death (ALIVE while living or gone from the map).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Named {
    pub given: u16,
    pub pat: u16,
    pub line: u32,
    pub from: u32,
    pub how: u8,
    pub rel: u8,
    pub died: i32,
}

const UNNAMED: Named = Named { given: 0, pat: 0, line: NONE, from: NONE, how: START, rel: 0, died: ALIVE };

/// A line: its family name (Stock::nomina), the origin whose names and
/// naming order it keeps, whether it is of senators or equites, its first
/// member and the day it began.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Line {
    pub nomen: u16,
    pub origin: u8,
    pub elite: bool,
    pub founder: u32,
    pub since: i32,
}

/// The last births of a region: form and prestige weight.
#[derive(Clone, Copy)]
struct Ring {
    next: u8,
    len: u8,
    form: [u16; RING],
    w: [u8; RING],
}

const EMPTY_RING: Ring = Ring { next: 0, len: 0, form: [0; RING], w: [0; RING] };

impl Ring {
    fn push(&mut self, form: u16, w: f32) {
        self.form[self.next as usize] = form;
        self.w[self.next as usize] = w.round().clamp(1.0, 255.0) as u8;
        self.next = ((self.next as usize + 1) % RING) as u8;
        self.len = (self.len as usize + 1).min(RING) as u8;
    }
}

/// One person of the start population.
pub struct StartPerson {
    pub pid: u32,
    pub female: bool,
    pub household: u32,
    pub stand: u8,
    pub origin: u8,
    /// Dense region index (crate::people) or NONE.
    pub region: u32,
    pub born: i32,
}

/// A birth: the child, its parents, the parents of everyone by person id,
/// the living siblings, the region of the home, the father's estate.
pub struct Birth<'a> {
    pub pid: u32,
    pub female: bool,
    pub father: u32,
    pub mother: u32,
    pub parents: &'a [(u32, u32)],
    pub siblings: &'a [u32],
    pub region: u32,
    pub stand: u8,
    pub day: i64,
}

/// Every person's name, the lines, and what the parents copy from.
#[derive(Default)]
pub struct Names {
    pub people: Vec<Named>,
    pub lines: Vec<Line>,
    /// Births of the last years per origin and form (prestige weighted,
    /// decaying), with the totals per origin and sex.
    pool: Vec<f32>,
    total: [[f32; 2]; N],
    local: Vec<Ring>,
    year: i64,
    seed: u64,
    /// Choices at births so far, by Named::how.
    pub chosen: [u64; 6],
}

fn u(seed: u64, id: u32, k: u32, day: i64) -> f64 {
    let mut b = [0u8; 24];
    b[..8].copy_from_slice(&seed.to_le_bytes());
    b[8..12].copy_from_slice(&id.to_le_bytes());
    b[12..16].copy_from_slice(&(NAME_SALT + k).to_le_bytes());
    b[16..24].copy_from_slice(&day.to_le_bytes());
    crate::life::unit(xxh3_64(&b))
}

/// Weight of a copy for a name with this share of its culture's births.
fn fashion(share: f32) -> f32 {
    let s = (SEL_PER_DECADE * (share.max(1e-5).log10() + 3.0)).clamp(-SEL_MAX, SEL_MAX);
    1.0 + POOL_YEARS * s
}

impl Names {
    /// Names for the start population (in any order) of `regions` regions.
    pub fn start(seed: u64, people: &[StartPerson], regions: usize) -> Names {
        let s = stock();
        let n = people.iter().map(|p| p.pid as usize + 1).max().unwrap_or(0);
        let mut names = Names {
            people: vec![UNNAMED; n],
            pool: vec![0.0; N * s.forms.len()],
            local: vec![EMPTY_RING; regions],
            seed,
            ..Default::default()
        };
        let mut order: Vec<&StartPerson> = people.iter().collect();
        order.sort_unstable_by_key(|p| p.pid);
        // a household's line is of the elite when one of it is
        let mut elite: rustc_hash::FxHashMap<u32, bool> = rustc_hash::FxHashMap::default();
        for p in &order {
            *elite.entry(p.household).or_default() |= p.stand >= crate::people::EQUES;
        }
        let mut line_of: rustc_hash::FxHashMap<u32, u32> = rustc_hash::FxHashMap::default();
        for p in &order {
            let line = *line_of.entry(p.household).or_insert_with(|| {
                let o = (p.origin as usize).min(N - 1);
                let e = elite[&p.household];
                let pick = if e { &s.elite_pick[o] } else { &s.nomen_pick[o] };
                let nomen = pick.draw(u(seed, p.household, 1, 0)).or_else(|| s.nomen_pick[o].draw(0.0)).unwrap_or(0);
                names.lines.push(Line { nomen, origin: p.origin, elite: e, founder: p.pid, since: 0 });
                (names.lines.len() - 1) as u32
            });
            let given = s.draw(p.origin, p.female, u(seed, p.pid, 2, 0));
            let pat = s.draw(p.origin, false, u(seed, p.pid, 3, 0));
            names.people[p.pid as usize] = Named { given, pat, line, from: NONE, how: START, rel: 0, died: ALIVE };
            names.count(p.origin, given, 1.0);
        }
        // the young of each region, the eldest first, as its last births
        order.sort_unstable_by_key(|p| (p.born, p.pid));
        for p in order.iter().filter(|p| -(p.born as i64) < START_LOCAL_YEARS * YEAR) {
            if let Some(r) = names.local.get_mut(p.region as usize) {
                r.push(names.people[p.pid as usize].given, 1.0);
            }
        }
        names
    }

    fn count(&mut self, origin: u8, form: u16, w: f32) {
        let s = stock();
        let o = (origin as usize).min(N - 1);
        self.pool[o * s.forms.len() + form as usize] += w;
        self.total[o][s.forms[form as usize].female as usize] += w;
    }

    fn share(&self, origin: usize, form: u16) -> f32 {
        let s = stock();
        let t = self.total[origin][s.forms[form as usize].female as usize];
        if t <= 0.0 {
            0.0
        } else {
            self.pool[origin * s.forms.len() + form as usize] / t
        }
    }

    fn get(&self, pid: u32) -> Option<&Named> {
        self.people.get(pid as usize).filter(|n| n.line != NONE)
    }

    /// The child's name, chosen by its parents (module docs).
    pub fn birth(&mut self, b: &Birth) {
        let s = stock();
        let seed = self.seed;
        let r = |k: u32| u(seed, b.pid, k, b.day);
        // a new year: the pools forget a little
        let year = b.day.div_euclid(YEAR);
        while self.year < year {
            let keep = (-1.0 / POOL_YEARS).exp();
            self.pool.iter_mut().for_each(|x| *x *= keep);
            self.total.iter_mut().flatten().for_each(|x| *x *= keep);
            self.year += 1;
        }
        let (Some(&fa), Some(&mo)) = (self.get(b.father), self.get(b.mother)) else { return };
        let line = fa.line;
        let mut origin = self.lines[line as usize].origin;
        if r(0) < MOTHER_POOL {
            origin = self.lines[mo.line as usize].origin;
        }
        let o = (origin as usize).min(N - 1);
        let taken: Vec<u16> = b.siblings.iter().filter_map(|&k| self.get(k)).filter(|n| n.died == ALIVE).map(|n| n.given).collect();
        let free = |f: u16| !taken.contains(&f) && s.forms[f as usize].female == b.female;
        // the relatives a name may come from: (form, rel, pid, weight)
        let parents = |p: u32| b.parents.get(p as usize).copied().unwrap_or((NONE, NONE));
        let (ff, fm) = parents(b.father);
        let (mf, mm) = parents(b.mother);
        let mut kin: Vec<(u16, u8, u32, f32)> = Vec::new();
        let mut add = |form: u16, rel: u8, pid: u32, w: f32| {
            let dead = pid != NONE && self.get(pid).is_some_and(|n| n.died != ALIVE);
            let recent = dead && self.get(pid).is_some_and(|n| b.day - (n.died as i64) < DEAD_YEARS * YEAR);
            kin.push((form, rel | if dead { DEAD } else { 0 }, pid, w * if recent { DEAD_W } else { 1.0 }));
        };
        let given_of = |pid: u32, or: u16| self.get(pid).map_or(or, |n| n.given);
        if b.female {
            if fm != NONE {
                add(given_of(fm, 0), FM, fm, KIN_W[0]);
            }
            add(mo.given, M, b.mother, KIN_W[1]);
            if mm != NONE {
                add(given_of(mm, 0), MM, mm, KIN_W[2]);
            }
        } else {
            add(given_of(ff, fa.pat), FF, if ff != NONE && self.get(ff).is_some() { ff } else { NONE }, KIN_W[0]);
            add(fa.given, F, b.father, KIN_W[1]);
            add(given_of(mf, mo.pat), MF, if mf != NONE && self.get(mf).is_some() { mf } else { NONE }, KIN_W[2]);
        }
        // a relative of the other sex gives the form of the child's sex with
        // the same stem in the same language, the most frequent
        let fit = |form: u16| -> Option<u16> {
            if free(form) {
                return Some(form);
            }
            let f = &s.forms[form as usize];
            (0..s.forms.len() as u16)
                .filter(|&g| g != form && free(g) && s.forms[g as usize].lang == f.lang && s.forms[g as usize].elems.first() == f.elems.first())
                .max_by(|&x, &y| s.forms[x as usize].w[o].total_cmp(&s.forms[y as usize].w[o]).then(y.cmp(&x)))
        };
        let x = r(1);
        let mut chosen: Option<(u16, u8, u8, u32)> = None; // form, how, rel, from
        if x < s.kin[o] {
            let fits: Vec<(u16, u8, u32, f64)> = kin.iter().filter_map(|&(f, rel, pid, w)| fit(f).map(|g| (g, rel, pid, w as f64))).collect();
            let pick = Pick::new(fits.iter().enumerate().map(|(i, k)| (i as u16, k.3)));
            if let Some(i) = pick.draw(r(2)) {
                let k = fits[i as usize];
                chosen = Some((k.0, KIN, k.1, k.2));
            }
        } else if x < s.kin[o] + s.var[o] {
            // all forms of the child's sex that share a stem with a
            // relative's name and are not that name, by weight in the origin
            let mut c: Vec<(u16, u8, u32, f64)> = Vec::new();
            for g in 0..s.forms.len() as u16 {
                let w = s.forms[g as usize].w[o] as f64;
                if w <= 0.0 || !free(g) || kin.iter().any(|k| k.0 == g) {
                    continue;
                }
                if let Some(k) = kin.iter().find(|k| s.share_stem(g, k.0)) {
                    c.push((g, k.1, k.2, w));
                }
            }
            let pick = Pick::new(c.iter().enumerate().map(|(i, k)| (i as u16, k.3)));
            if let Some(i) = pick.draw(r(3)) {
                let k = c[i as usize];
                chosen = Some((k.0, VARIANT, k.1, k.2));
            }
        }
        if chosen.is_none() {
            let ring = self.local.get(b.region as usize).filter(|r| r.len > 0);
            // a name of the stock by its weight in the origin, among the free
            let from_stock = |x: f64| Pick::new((0..s.forms.len() as u16).filter(|&f| free(f)).map(|f| (f, s.forms[f as usize].w[o] as f64))).draw(x);
            if r(4) < s.innov[o] {
                if let Some(f) = from_stock(r(5)) {
                    chosen = Some((f, RARE, 0, NONE));
                }
            } else if ring.is_some() && r(9) < s.local[o] {
                let ring = ring.unwrap();
                let pick = Pick::new((0..ring.len as usize).filter(|&k| free(ring.form[k])).map(|k| (k as u16, ring.w[k] as f64 * fashion(self.share(o, ring.form[k])) as f64)));
                if let Some(k) = pick.draw(r(10)) {
                    chosen = Some((ring.form[k as usize], LOCAL, 0, NONE));
                }
            }
            if chosen.is_none() {
                let base = o * s.forms.len();
                let pick = Pick::new((0..s.forms.len() as u16).filter(|&f| free(f)).map(|f| (f, self.pool[base + f as usize] as f64 * fashion(self.share(o, f)) as f64)));
                let f = pick.draw(r(11)).or_else(|| from_stock(r(12))).unwrap_or_else(|| s.draw(origin, b.female, r(12)));
                chosen = Some((f, CULTURE, 0, NONE));
            }
        }
        let (given, how, rel, from) = chosen.unwrap();
        if self.people.len() <= b.pid as usize {
            self.people.resize(b.pid as usize + 1, UNNAMED);
        }
        self.people[b.pid as usize] = Named { given, pat: fa.given, line, from, how, rel, died: ALIVE };
        self.chosen[how as usize] += 1;
        let w = PRESTIGE[(b.stand as usize).min(3)];
        self.count(self.lines[line as usize].origin, given, w);
        if let Some(ring) = self.local.get_mut(b.region as usize) {
            ring.push(given, w);
        }
    }

    /// Marks a death (for the 2.7 of Todd & Coulmont and the hints).
    pub fn died(&mut self, pid: u32, day: i64) {
        if let Some(n) = self.people.get_mut(pid as usize) {
            n.died = day as i32;
        }
    }

    /// The full name, empty if the person has none.
    pub fn full(&self, pid: u32) -> String {
        self.shown(pid).map(|s| s.full).unwrap_or_default()
    }

    /// The name as the view shows it: the full name and each part with
    /// what it is and where it comes from.
    pub fn shown(&self, pid: u32) -> Option<Shown> {
        let s = stock();
        let n = *self.get(pid)?;
        let line = self.lines[n.line as usize];
        let o = (line.origin as usize).min(N - 1);
        let form = &s.forms[n.given as usize];
        let female = form.female;
        let nomen = &s.nomina[line.nomen as usize];
        let pat = &s.forms[n.pat as usize];
        let child = if female { "Tochter" } else { "Sohn" };
        let mut parts: Vec<NamePart> = Vec::new();
        let mut full = String::new();
        for &(part, elite_only) in &s.order[o] {
            if elite_only && !line.elite {
                continue;
            }
            let (text, role, about) = match part {
                Part::Praenomen => {
                    if female {
                        continue;
                    }
                    let total: f32 = s.praenomina.iter().map(|p| p.1).sum();
                    let mut x = u(self.seed, pid, 100, 0) as f32 * total;
                    let name = s.praenomina.iter().find(|p| {
                        x -= p.1;
                        x < 0.0
                    });
                    let name = name.or(s.praenomina.last()).map(|p| p.0.clone()).unwrap_or_default();
                    (name, "Vorname", "Vorname (Praenomen). Um 300 führen ihn fast nur noch Senatoren und Ritter.".to_owned())
                }
                Part::Nomen | Part::NomenGreek => {
                    let text = feminine(if part == Part::Nomen { &nomen.lat } else { &nomen.grc }, female);
                    let mut about = if female {
                        "Familienname (Gentilname) ihres Vaters in weiblicher Form; sie behält ihn auch nach der Heirat.".to_owned()
                    } else {
                        "Familienname (Gentilname) der Linie, vom Vater geerbt.".to_owned()
                    };
                    if !nomen.note.is_empty() {
                        about += &format!(" {}: {}.", nomen.lat, nomen.note);
                    }
                    (text, "Familienname", about)
                }
                Part::Given => (form.text.clone(), "Rufname", self.about_given(&n, female)),
                Part::FatherGen => {
                    if pat.gen.is_empty() {
                        (format!("{child} des {}", pat.text), "Vatersname", format!("{child} des {}.", pat.text))
                    } else {
                        (pat.gen.clone(), "Vatersname", format!("{child} des {}: der Name des Vaters im Genitiv, wie in griechischen Urkunden.", pat.text))
                    }
                }
                Part::FatherBar => {
                    let w = if female { "bat" } else { "bar" };
                    (format!("{w} {}", pat.text), "Vatersname", format!("{child} des {}: aramäisch bar, Sohn, und bat, Tochter.", pat.text))
                }
            };
            if !full.is_empty() {
                full.push(if text.starts_with(child) { ',' } else { ' ' });
                if text.starts_with(child) {
                    full.push(' ');
                }
            }
            full += &text;
            parts.push(NamePart { text, role, about });
        }
        Some(Shown { full, parts, line: plural(&nomen.lat), origin: crate::dna::ORIGINS[o], line_id: n.line, founder: line.founder, since: line.since })
    }

    fn about_given(&self, n: &Named, female: bool) -> String {
        let s = stock();
        let form = &s.forms[n.given as usize];
        let whose = |rel: u8| match rel & !DEAD {
            FF => "des Grossvaters väterlicherseits",
            F => "des Vaters",
            MF => "des Grossvaters mütterlicherseits",
            FM => "der Grossmutter väterlicherseits",
            M => "der Mutter",
            _ => "der Grossmutter mütterlicherseits",
        };
        let who = |rel: u8| {
            let mut t = whose(rel).to_owned();
            if n.from != NONE {
                let name = self.full(n.from);
                if !name.is_empty() {
                    t += &format!(", {name}");
                }
            }
            if rel & DEAD != 0 {
                t += if matches!(rel & !DEAD, FM | M | MM) { ", die schon gestorben war" } else { ", der schon gestorben war" };
            }
            t
        };
        let mut t = match n.how {
            KIN => format!("Rufname, der Name {}.", who(n.rel)),
            VARIANT => format!("Rufname, abgeleitet vom Namen {}: beide teilen einen Stamm.", who(n.rel)),
            LOCAL => "Rufname, in der Nachbarschaft gerade oft gegeben.".to_owned(),
            CULTURE => format!("Rufname, in {} Kultur gerade in Mode.", if female { "ihrer" } else { "seiner" }),
            RARE => "Rufname, ein seltener alter Name, neu aufgegriffen.".to_owned(),
            _ => "Rufname, schon bei Spielbeginn getragen.".to_owned(),
        };
        let lang = match form.lang.as_str() {
            "lat" => "lateinisch",
            "grc" => "griechisch",
            "arc" => "aramäisch",
            "egy" => "ägyptisch",
            "pun" => "punisch",
            "lib" => "libysch",
            "cel" => "keltisch",
            "ger" => "germanisch, aus zwei Gliedern",
            "thr" => "thrakisch",
            "ill" => "illyrisch",
            _ => "",
        };
        let word = lang.split(',').next().unwrap_or("");
        if !lang.is_empty() && !form.note.starts_with(word) {
            t += &format!(" Der Name ist {lang}.");
        }
        if !form.note.is_empty() {
            t += &format!(" {}: {}.", form.text, form.note);
        }
        t
    }

    /// The line of a person, if named.
    pub fn line_of(&self, pid: u32) -> Option<u32> {
        self.get(pid).map(|n| n.line)
    }
}

/// A name as the view shows it.
#[derive(Clone, Debug, Default)]
pub struct Shown {
    pub full: String,
    pub parts: Vec<NamePart>,
    /// The line's family name in the plural ("Aurelii"), its origin.
    pub line: String,
    pub origin: &'static str,
    pub line_id: u32,
    pub founder: u32,
    pub since: i32,
}

/// A part of a name: its text, what it is ("Rufname"), where it comes from.
#[derive(Clone, Debug)]
pub struct NamePart {
    pub text: String,
    pub role: &'static str,
    pub about: String,
}

/// The woman's form of a family name: Aurelius, Aurelios → Aurelia.
fn feminine(nomen: &str, female: bool) -> String {
    if !female {
        return nomen.to_owned();
    }
    match nomen.strip_suffix("us").or_else(|| nomen.strip_suffix("os")) {
        Some(stem) => format!("{stem}a"),
        None => nomen.to_owned(),
    }
}

/// The plural of a Latin family name: Aurelius → Aurelii.
fn plural(nomen: &str) -> String {
    match nomen.strip_suffix("us") {
        Some(stem) => format!("{stem}i"),
        None => nomen.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_stock_parses_and_every_origin_has_names() {
        let s = stock();
        assert!(s.forms.len() > 300, "{}", s.forms.len());
        for o in 0..N {
            for female in [false, true] {
                assert!(s.pick[2 * o + female as usize].ids.len() >= 10, "origin {o} female {female}");
            }
            assert!(!s.nomen_pick[o].ids.is_empty() && !s.elite_pick[o].ids.is_empty());
        }
        // composed Germanic names, as attested ones
        for n in ["Theudericus", "Alaricus", "Arbogastes", "Merobaudes", "Amalasuintha", "Ermanaricus"] {
            assert!(s.forms.iter().any(|f| f.text == n), "{n}");
        }
        assert!(!s.forms.iter().any(|f| f.text == "Hildehildis"));
        assert_eq!(feminine("Aurelius", true), "Aurelia");
        assert_eq!(feminine("Aurelios", true), "Aurelia");
        assert_eq!(plural("Valerius"), "Valerii");
    }

    #[test]
    fn rare_names_gain_and_common_names_lose() {
        assert!(fashion(1e-4) > 1.1 && fashion(1e-4) < 1.2);
        assert!(fashion(1e-2) < 0.9 && fashion(1e-2) > 0.8);
        assert!((fashion(1e-3) - 1.0).abs() < 1e-4);
        assert!(fashion(0.0) <= 1.0 + POOL_YEARS * SEL_MAX + 1e-6);
    }

    fn start_four() -> Names {
        let p = |pid, female, household, origin| StartPerson { pid, female, household, stand: 0, origin, region: 0, born: -30 * YEAR as i32 };
        // two households: a Greek one (0, 1) and a Syrian one (2, 3)
        Names::start(7, &[p(0, false, 0, 3), p(1, true, 0, 3), p(2, false, 1, 4), p(3, true, 1, 4)], 1)
    }

    #[test]
    fn names_follow_the_order_of_their_origin() {
        let names = start_four();
        assert_eq!(names.lines.len(), 2);
        assert_eq!(names.people[0].line, names.people[1].line);
        let greek = names.shown(0).unwrap();
        // family name, given name, father's name in the genitive
        assert_eq!(greek.parts.len(), 3);
        assert_eq!(greek.parts[0].role, "Familienname");
        assert_eq!(greek.parts[2].role, "Vatersname");
        let syrian = names.shown(3).unwrap();
        assert!(syrian.parts[2].text.starts_with("bat "), "{}", syrian.full);
        assert!(names.shown(1).unwrap().parts[0].text.ends_with('a'), "a woman's family name is feminine");
    }

    #[test]
    fn children_take_the_line_and_no_sibling_shares_a_name() {
        let mut names = start_four();
        let parents = vec![(NONE, NONE); 4];
        let mut kids = Vec::new();
        for k in 0..12u32 {
            let pid = 4 + k;
            let mut par = parents.clone();
            par.resize(pid as usize, (0, 1));
            names.birth(&Birth { pid, female: k % 2 == 1, father: 0, mother: 1, parents: &par, siblings: &kids, region: 0, stand: 0, day: 400 + 400 * k as i64 });
            kids.push(pid);
            assert_eq!(names.people[pid as usize].line, names.people[0].line);
            assert_eq!(names.people[pid as usize].pat, names.people[0].given);
        }
        let mut seen: Vec<u16> = kids.iter().map(|&k| names.people[k as usize].given).collect();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), kids.len(), "siblings all differ");
        for k in kids {
            let n = names.people[k as usize];
            assert_eq!(stock().forms[n.given as usize].female, (k - 4) % 2 == 1);
            assert!(!names.full(k).is_empty());
        }
    }

    #[test]
    fn same_seed_same_names() {
        let a = start_four();
        let b = start_four();
        assert_eq!(a.people, b.people);
        assert_eq!(a.lines, b.lines);
    }
}
