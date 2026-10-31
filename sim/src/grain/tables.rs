//! The game's statistics beyond the grain (Ramon, 30.10.2026, card "Alles,
//! mit neuen Sim-Tabellen"): who is rich and who is poor, the craft goods,
//! wages and the granaries over the months. Read only: these functions
//! count what the simulation already keeps (the yearly line of
//! bin/grain.rs), they change nothing.

use super::*;

/// The household kinds of `HhState::kind` (KIND_NAMES) as the statistics name them.
const CLASS_NAMES: [&str; 5] = ["Hofleute", "Im Zelt", "Lohnarbeit", "Händler", "Oberschicht"];

/// The history's columns of each good's price and of each class's grain
/// eaten (keys are 'static for `Table`), in GOOD_KEYS and CLASS_NAMES order.
const GOOD_PRICE_KEYS: [&str; GOODS] = ["good_wool", "good_iron", "good_cloth", "good_tools", "good_pottery", "good_pork"];
const GOOD_PRICE_NAMES: [&str; GOODS] = ["Preis Wolle", "Preis Eisen", "Preis Kleidung", "Preis Werkzeug", "Preis Keramik", "Preis Schweinefleisch"];
const FED_KEYS: [&str; 5] = ["fed_court", "fed_tent", "fed_wage", "fed_trader", "fed_elite"];
const FED_NAMES: [&str; 5] = ["Gegessen: Hofleute", "Gegessen: Im Zelt", "Gegessen: Lohnarbeit", "Gegessen: Händler", "Gegessen: Oberschicht"];
const GINI_KEYS: [&str; 5] = ["gini_court", "gini_tent", "gini_wage", "gini_trader", "gini_elite"];
const GINI_NAMES: [&str; 5] = ["Gini: Hofleute", "Gini: Im Zelt", "Gini: Lohnarbeit", "Gini: Händler", "Gini: Oberschicht"];
const LORENZ_KEYS: [&str; 9] = ["lorenz_10", "lorenz_20", "lorenz_30", "lorenz_40", "lorenz_50", "lorenz_60", "lorenz_70", "lorenz_80", "lorenz_90"];

/// The month's levels that are not flows of `History`, for the history
/// table. Wages are over the markets with people, by market.
#[derive(Clone, Copy, Debug, Default)]
pub struct HistoryExtra {
    /// Day wage p50, denarii; real wage (the day wage in grain at the
    /// market's price) p10 / p50 / p90, kg.
    pub wage: f64,
    pub real_wage: (f64, f64, f64),
    /// What a wage earner must earn per work day to feed their share of
    /// the household: its grain need over its adults' work days (median of
    /// the wage households), kg. The line the real wage must reach.
    pub need_wage: f64,
    /// Last week's work days asked for and not found, offered and not taken.
    pub vacant: i64,
    pub idle: i64,
    /// Grain in the state's and the landlords' granaries, kg.
    pub horrea_kg: i64,
    pub lords_kg: i64,
    /// Clothing held of the plain need over all households, per cent.
    pub clothes: f64,
    /// Money of the upper class (elite) of all households' money, share.
    pub elite_money: f64,
    /// Since the start: grain spoiled, sold beyond the map, kg.
    pub spoiled_kg: i64,
    pub export_kg: i64,
    /// Since the start, by household kind: grain eaten and needed, kg.
    pub eaten_by: [i64; 5],
    pub need_by: [i64; 5],
    /// Each good's median price over the markets (by people), denarii.
    pub goods_price: [f64; GOODS],
    /// What the player had built by then: farms, road lots, field lots.
    pub built: (i64, i64, i64),
    /// Arm und Reich (Ramon, 30.10.2026): the Gini of money per head over
    /// all people, within each household kind, and the Lorenz curve: the
    /// share of all money the poorest 10 %, 20 % … 90 % of the people hold.
    pub gini: f64,
    pub gini_by: [f64; 5],
    pub lorenz: [f64; 9],
    /// The treasury's account since the start (S94; S129 public works),
    /// whose month the history shows.
    pub state: Treasury,
    /// S131: the households' Steuerrückstand, milli-denarii, and how many
    /// households owe.
    pub arrears: i64,
    pub arrears_households: i64,
}

/// One market's month in the history (Ramon, 30.10.2026, "Verlauf je
/// Markt"), f32 so a century of all markets stays small.
#[derive(Clone, Copy, Debug, Default)]
pub struct MarketMonth {
    /// Grain price, denarii per kg; share of the people who buy their
    /// food that went hungry; grain in the dealers' store, t; grain sold
    /// in the month, t; day wage and dealers' cash, denarii.
    pub price: f32,
    pub hungry: f32,
    pub store_t: f32,
    pub sold_t: f32,
    pub wage: f32,
    pub money: f32,
    /// People of the region, of them in tents.
    pub people: u32,
    pub tents: u32,
    /// Gini of money per head over the region's people.
    pub gini: f32,
    /// Each good's price, denarii (GOOD_KEYS order).
    pub goods: [f32; GOODS],
    /// S129: public works hired here in the month, days and denarii paid.
    pub public_days: f32,
    pub public_wage: f32,
    /// S131: Grundsteuer and Kopfsteuer paid here in the month, denarii;
    /// the Zehnt delivered here in the month, t.
    pub tax_d: f32,
    pub tithe_t: f32,
}

/// Months each market keeps one by one (ten years); the years before
/// are kept as their mean, so a century of 1,800 markets stays near 20 MB.
const MARKET_MONTHS: usize = 120;

impl MarketMonth {
    /// The mean of some months.
    fn mean(v: &[MarketMonth]) -> MarketMonth {
        let n = v.len().max(1) as f32;
        let sum = |f: &dyn Fn(&MarketMonth) -> f32| v.iter().map(f).sum::<f32>() / n;
        MarketMonth {
            price: sum(&|x| x.price),
            hungry: sum(&|x| x.hungry),
            store_t: sum(&|x| x.store_t),
            sold_t: sum(&|x| x.sold_t),
            wage: sum(&|x| x.wage),
            money: sum(&|x| x.money),
            people: sum(&|x| x.people as f32).round() as u32,
            tents: sum(&|x| x.tents as f32).round() as u32,
            gini: sum(&|x| x.gini),
            goods: std::array::from_fn(|g| sum(&|x| x.goods[g])),
            public_days: sum(&|x| x.public_days),
            public_wage: sum(&|x| x.public_wage),
            tax_d: sum(&|x| x.tax_d),
            tithe_t: sum(&|x| x.tithe_t),
        }
    }
}

impl History {
    /// Keeps the markets' month of `day`; once more than ten years are kept
    /// month by month, the oldest twelve months become one entry, their
    /// mean, on the last one's day.
    pub(super) fn keep_markets(&mut self, day: i64, months: Vec<MarketMonth>) {
        self.markets.push((day, months));
        let at = self.market_years;
        if self.markets.len() - at < MARKET_MONTHS + 12 {
            return;
        }
        let year: Vec<(i64, Vec<MarketMonth>)> = self.markets.drain(at..at + 12).collect();
        let n = year.iter().map(|y| y.1.len()).max().unwrap_or(0);
        let mean = (0..n).map(|k| MarketMonth::mean(&year.iter().filter_map(|y| y.1.get(k).copied()).collect::<Vec<_>>())).collect();
        self.markets.insert(at, (year[11].0, mean));
        self.market_years += 1;
    }
}

/// How money and food are spread over the people, from one pass over the
/// households: Gini and Lorenz curve over all, Gini by household kind and
/// by market, the hungry share of each market's buyers.
pub(super) struct Spread {
    gini: f64,
    gini_by: [f64; 5],
    lorenz: [f64; 9],
    pub(super) market_gini: Vec<f64>,
    pub(super) hungry: Vec<f64>,
}

/// Gini and the Lorenz curve at 10 % … 90 % of the people of money per
/// head; `v` holds (money per head, people) of each household. Debts count
/// as nothing. No money at all: everyone equal.
fn gini_lorenz(v: &mut [(i64, i64)]) -> (f64, [f64; 9]) {
    v.sort_unstable();
    let people: i64 = v.iter().map(|x| x.1).sum();
    let money: f64 = v.iter().map(|x| x.0.max(0) as f64 * x.1 as f64).sum();
    let mut lorenz = std::array::from_fn(|q| (q + 1) as f64 / 10.0);
    if people == 0 || money <= 0.0 {
        return (0.0, lorenz);
    }
    let (mut p_acc, mut m_acc, mut area, mut q) = (0i64, 0.0, 0.0, 0usize);
    for &(x, n) in v.iter() {
        let (p0, m0) = (p_acc as f64 / people as f64, m_acc / money);
        p_acc += n;
        m_acc += x.max(0) as f64 * n as f64;
        let (p1, m1) = (p_acc as f64 / people as f64, m_acc / money);
        area += (p1 - p0) * (m0 + m1);
        while q < 9 && p1 >= (q + 1) as f64 / 10.0 {
            lorenz[q] = m0 + (m1 - m0) * ((q + 1) as f64 / 10.0 - p0) / (p1 - p0).max(1e-12);
            q += 1;
        }
    }
    ((1.0 - area).clamp(0.0, 1.0), lorenz)
}

/// What the game shows of a household (read only), for the person window.
#[derive(Clone, Debug)]
pub struct HouseholdLook {
    /// Index into KIND_NAMES.
    pub kind: u8,
    /// Share of its need the household ate at the last meal count, ‰.
    pub fed: u16,
    pub pantry_kg: i64,
    /// Money, milli-denarii (farmers: with their farm's); per head.
    pub money: i64,
    pub money_head: i64,
    /// Its farm: kind (FARM_KIND_NAMES) and field area in m², if it has one.
    pub farm: Option<(u8, i64)>,
    /// That farm's index (`Grain::farm_look`).
    pub farm_id: Option<u32>,
    /// Its market (index, name), the grain price and the day wage there,
    /// milli-denarii.
    pub market: Option<(u32, String)>,
    pub grain_price: i64,
    pub wage: i64,
    /// People and adults; grain they need a month, kg.
    pub size: u16,
    pub adults: u16,
    pub need_month_kg: i64,
    /// Person ids of the household, from the last count.
    pub members: Vec<u32>,
    /// Its work (CRAFT_NAMES) and what it earned a month, milli-denarii
    /// (craft households, smoothed).
    pub craft: u8,
    pub earned: i64,
    /// At the last weekly labour exchange: days it worked on others'
    /// farms, days its farm hired.
    pub worked_days: i64,
    pub hired_days: i64,
    /// Clothing held of the plain need, per cent.
    pub clothes_pct: i64,
    /// Share of the people with less money per head, on the map and in
    /// its market (0..1).
    pub rank_all: f64,
    pub rank_market: f64,
}

impl Grain {
    /// Money per head (milli-denarii) and people of each counted household
    /// with its market (NONE if none) and kind; farmers with their farm's money.
    fn money_heads(&self) -> Vec<(i64, i64, u32, u8)> {
        self.info
            .iter()
            .filter_map(|(id, i)| {
                let s = self.hh.get(id)?;
                let money = s.money + if s.farm != NONE { self.farms[s.farm as usize].money } else { 0 };
                (i.size > 0).then(|| (money / i.size as i64, i.size as i64, self.cell_market[i.home as usize], s.kind))
            })
            .collect()
    }

    /// How money and food are spread (`Spread`).
    pub(super) fn spread(&self) -> Spread {
        let n = self.markets.len();
        let heads = self.money_heads();
        let mut all: Vec<(i64, i64)> = heads.iter().map(|h| (h.0, h.1)).collect();
        let (gini, lorenz) = gini_lorenz(&mut all);
        let mut by: [Vec<(i64, i64)>; 5] = Default::default();
        let mut at: Vec<Vec<(i64, i64)>> = vec![Vec::new(); n];
        for &(x, size, mk, kind) in &heads {
            by[kind as usize].push((x, size));
            if mk != NONE {
                at[mk as usize].push((x, size));
            }
        }
        let (mut hungry, mut counted) = (vec![0i64; n], vec![0i64; n]);
        for (id, i) in self.info.iter() {
            let mk = self.cell_market[i.home as usize];
            let Some(s) = self.hh.get(id) else { continue };
            if mk == NONE || s.own_food {
                continue;
            }
            counted[mk as usize] += i.size as i64;
            if s.fed < NEED_FED {
                hungry[mk as usize] += i.size as i64;
            }
        }
        Spread {
            gini,
            gini_by: std::array::from_fn(|k| gini_lorenz(&mut by[k]).0),
            lorenz,
            market_gini: at.iter_mut().map(|v| gini_lorenz(v).0).collect(),
            hungry: (0..n).map(|m| if counted[m] > 0 { hungry[m] as f64 / counted[m] as f64 } else { 0.0 }).collect(),
        }
    }

    /// The month's levels for `track`, and each market's month (`sold` is
    /// the grain each market sold in the month, kg).
    pub(super) fn history_extra(&self, sold: &[i64]) -> (HistoryExtra, Vec<MarketMonth>) {
        let spread = self.spread();
        let months = self
            .markets
            .iter()
            .enumerate()
            .map(|(k, m)| MarketMonth {
                price: m.price as f32 / 1e3,
                hungry: spread.hungry[k] as f32,
                store_t: m.store as f32 / 1e3,
                sold_t: sold.get(k).copied().unwrap_or(0) as f32 / 1e3,
                wage: m.wage as f32 / 1e3,
                money: m.money as f32 / 1e3,
                people: m.people,
                tents: m.tent_people,
                gini: spread.market_gini[k] as f32,
                goods: std::array::from_fn(|g| m.goods[g].price as f32 / 1e3),
                public_days: m.public_days as f32,
                public_wage: m.public_paid as f32 / 1e3,
                tax_d: m.tax_paid as f32 / 1e3,
                tithe_t: m.tithe_kg as f32 / 1e3,
            })
            .collect();
        (self.history_levels(&spread), months)
    }

    fn history_levels(&self, spread: &Spread) -> HistoryExtra {
        let ms: Vec<&Market> = self.markets.iter().filter(|m| m.people > 0).collect();
        let at = |v: &[i64], q: f64| if v.is_empty() { 0.0 } else { v[((v.len() - 1) as f64 * q) as usize] as f64 / 1e3 };
        let mut wage: Vec<i64> = ms.iter().map(|m| m.wage).collect();
        wage.sort_unstable();
        let mut real: Vec<i64> = ms.iter().map(|m| m.wage * 1000 / m.price.max(1)).collect();
        real.sort_unstable();
        let mut need: Vec<i64> = self
            .hh
            .iter()
            .filter(|(_, s)| s.kind == WAGE)
            .filter_map(|(id, _)| self.info.get(id))
            .filter(|i| i.adults > 0)
            .map(|i| i.need_w as i64 * KG_PER_ADULT_YEAR * 100 / (i.adults as i64 * WORK_DAYS_YEAR))
            .collect();
        need.sort_unstable();
        let clothes = self.clothes_by_kind();
        let held: f64 = clothes.iter().map(|c| c.0 * c.1 as f64).sum();
        let homes: usize = clothes.iter().map(|c| c.1).sum();
        let (money, _) = self.money_by_kind();
        let all: f64 = money.iter().sum();
        let (_, _, goods_price) = self.goods_report();
        let (arrears, arrears_households) = self.arrears_now();
        HistoryExtra {
            wage: at(&wage, 0.5),
            real_wage: (at(&real, 0.1), at(&real, 0.5), at(&real, 0.9)),
            need_wage: at(&need, 0.5),
            vacant: ms.iter().map(|m| m.vacant_week).sum(),
            idle: ms.iter().map(|m| m.idle_week).sum(),
            horrea_kg: self.markets.iter().map(|m| m.horreum).sum(),
            lords_kg: self.markets.iter().flat_map(|m| m.lords.iter().map(|l| l.1)).sum(),
            clothes: if homes > 0 { held / homes as f64 } else { 0.0 },
            elite_money: if all > 0.0 { money[4] / all } else { 0.0 },
            spoiled_kg: self.stats.spoiled_kg,
            export_kg: self.stats.out_export_kg,
            eaten_by: self.stats.eaten_by,
            need_by: self.stats.need_by,
            goods_price,
            built: (self.stats.built_farms, self.road_lots.len() as i64, self.field_lots.len() as i64),
            gini: spread.gini,
            gini_by: spread.gini_by,
            lorenz: spread.lorenz,
            state: self.treasury,
            arrears,
            arrears_households,
        }
    }

    /// The history's columns from `HistoryExtra` by good and by class: each
    /// good's price, what the player had built (the statistics mark the
    /// months they grew), and the grain each class ate of its need that month.
    pub(super) fn history_by_good_and_class(&self, t: &mut Table) {
        let rows = &self.history.rows;
        for g in 0..GOODS {
            t.float(GOOD_PRICE_KEYS[g], GOOD_PRICE_NAMES[g], "Denar", rows.iter().map(|r| r.extra.goods_price[g]).collect());
        }
        t.int("farms_built", "Gebaute Höfe", "", rows.iter().map(|r| r.extra.built.0).collect())
            .int("roads_built", "Gebaute Strassenstücke", "", rows.iter().map(|r| r.extra.built.1).collect())
            .int("fields_built", "Angelegte Feldstücke", "", rows.iter().map(|r| r.extra.built.2).collect());
        for k in 0..5 {
            let fed = (0..rows.len())
                .map(|i| {
                    let (e, n) = (rows[i].extra.eaten_by[k], rows[i].extra.need_by[k]);
                    let (e0, n0) = if i > 0 { (rows[i - 1].extra.eaten_by[k], rows[i - 1].extra.need_by[k]) } else { (0, 0) };
                    if n > n0 { ((e - e0) as f64 / (n - n0) as f64).clamp(0.0, 1.0) } else { 1.0 }
                })
                .collect();
            t.float(FED_KEYS[k], FED_NAMES[k], "%", fed);
        }
        t.float("gini", "Gini des Geldes", "", rows.iter().map(|r| r.extra.gini).collect());
        for k in 0..5 {
            t.float(GINI_KEYS[k], GINI_NAMES[k], "", rows.iter().map(|r| r.extra.gini_by[k]).collect());
        }
        // the Lorenz curve of each month, for the statistics only
        for q in 0..9 {
            t.hidden_float(LORENZ_KEYS[q], "%", rows.iter().map(|r| r.extra.lorenz[q]).collect());
        }
    }

    /// One market's history (`MarketMonth`), one row per month (before
    /// the last ten years one per year, the year's mean): what the market
    /// window draws, with the median price and the Gini of all markets
    /// beside. None if there is no such market.
    pub fn market_history_table(&self, m: usize, day: i64) -> Option<Table> {
        self.markets.get(m)?;
        let h = &self.history;
        let months: Vec<MarketMonth> = h.markets.iter().map(|v| v.1.get(m).copied().unwrap_or_default()).collect();
        let col = |f: &dyn Fn(&MarketMonth) -> f32| months.iter().map(|x| f(x) as f64).collect::<Vec<f64>>();
        // the realm's months up to each entry's day, as their mean
        let (mut price_all, mut gini_all, mut r, mut prev) = (Vec::new(), Vec::new(), 0, i64::MIN);
        for &(d, _) in &h.markets {
            let (mut p, mut g, mut n) = (0.0, 0.0, 0.0);
            while r < h.rows.len() && h.rows[r].day <= d {
                if h.rows[r].day > prev {
                    p += h.rows[r].price.1;
                    g += h.rows[r].extra.gini;
                    n += 1.0;
                }
                r += 1;
            }
            price_all.push(if n > 0.0 { p / n } else { 0.0 });
            gini_all.push(if n > 0.0 { g / n } else { 0.0 });
            prev = d;
        }
        let mut t = Table::new("market_history", "Verlauf des Marktes", day);
        t.id((0..months.len() as i64).collect());
        t.int("day", "Tag", "", h.markets.iter().map(|v| v.0).collect())
            .float("price", "Kornpreis", "Denar/kg", col(&|x| x.price))
            .float("price_all", "Kornpreis Median aller Märkte", "Denar/kg", price_all)
            .float("share_hungry", "Hungernd", "%", col(&|x| x.hungry))
            .float("store_t", "Marktlager", "t", col(&|x| x.store_t))
            .float("sold_t", "Verkauft im Monat", "t", col(&|x| x.sold_t))
            .float("wage", "Taglohn", "Denar", col(&|x| x.wage))
            .float("real_wage", "Reallohn", "kg", col(&|x| if x.price > 0.0 { x.wage / x.price } else { 0.0 }))
            .float("money", "Händlergeld", "Denar", col(&|x| x.money))
            .int("persons", "Menschen", "", months.iter().map(|x| x.people as i64).collect())
            .int("tent_persons", "Im Zelt", "", months.iter().map(|x| x.tents as i64).collect())
            .float("gini", "Gini des Geldes", "", col(&|x| x.gini))
            .float("gini_all", "Gini des Geldes aller Märkte", "", gini_all)
            .float("public_days", "Öffentliche Arbeit", "Tage", col(&|x| x.public_days))
            .float("public_wage", "Lohn für öffentliche Arbeit", "Denar", col(&|x| x.public_wage))
            .float("tax_d", "Grund- und Kopfsteuer im Monat", "Denar", col(&|x| x.tax_d))
            .float("tithe_t", "Zehnt im Monat", "t", col(&|x| x.tithe_t));
        for g in 0..GOODS {
            t.float(GOOD_PRICE_KEYS[g], GOOD_PRICE_NAMES[g], "Denar", col(&|x| x.goods[g]));
        }
        Some(t)
    }

    /// Who lives at market `m`: one row per household kind with
    /// households, people, money and money per head, and the share of its
    /// people who buy their food and went hungry. None if no such market.
    pub fn market_classes_table(&self, m: usize, day: i64) -> Option<Table> {
        self.markets.get(m)?;
        let (mut hh, mut ppl, mut money, mut hungry, mut buyers) = ([0i64; 5], [0i64; 5], [0i64; 5], [0i64; 5], [0i64; 5]);
        for (id, i) in self.info.iter() {
            let Some(s) = self.hh.get(id) else { continue };
            if self.cell_market[i.home as usize] != m as u32 {
                continue;
            }
            let k = s.kind as usize;
            hh[k] += 1;
            ppl[k] += i.size as i64;
            money[k] += s.money + if s.farm != NONE { self.farms[s.farm as usize].money } else { 0 };
            if !s.own_food {
                buyers[k] += i.size as i64;
                hungry[k] += if s.fed < NEED_FED { i.size as i64 } else { 0 };
            }
        }
        let mut t = Table::new("market_classes", "Wer am Markt lebt", day);
        t.id((0..5).collect());
        t.text("kind", "Schicht", CLASS_NAMES.iter().map(|s| s.to_string()).collect())
            .int("households", "Haushalte", "", hh.to_vec())
            .int("persons", "Menschen", "", ppl.to_vec())
            .float("money", "Geld", "Denar", money.iter().map(|&x| x as f64 / 1e3).collect())
            .float("money_head", "Geld je Kopf", "Denar", (0..5).map(|k| money[k] as f64 / 1e3 / ppl[k].max(1) as f64).collect())
            .float("share_hungry", "Hungernd", "%", (0..5).map(|k| if buyers[k] > 0 { hungry[k] as f64 / buyers[k] as f64 } else { 0.0 }).collect());
        Some(t)
    }

    /// A household as the person window shows it, if the grain economy
    /// knows it (it counts the households once a month).
    pub fn household(&self, hh: u32) -> Option<HouseholdLook> {
        let s = self.hh.get(&hh)?;
        let i = self.info.get(&hh);
        let farm = (s.farm != NONE).then(|| self.farms.get(s.farm as usize)).flatten().filter(|f| f.hh == hh);
        let money = s.money + farm.map_or(0, |f| f.money);
        let size = i.map_or(1, |i| i.size.max(1));
        let head = money / size as i64;
        let mk = i.map_or(NONE, |i| self.cell_market[i.home as usize]);
        // where its money per head stands among all people and its market's
        let (mut below, mut all, mut below_m, mut all_m) = (0.0, 0.0, 0.0, 0.0);
        for (x, n, at, _) in self.money_heads() {
            let w = if x < head { n as f64 } else if x == head { n as f64 / 2.0 } else { 0.0 };
            below += w;
            all += n as f64;
            if at == mk {
                below_m += w;
                all_m += n as f64;
            }
        }
        let (mut worked, mut hired) = (0, 0);
        if mk != NONE {
            for &(w, f, days, _) in &self.markets[mk as usize].work {
                worked += if w == hh { days } else { 0 };
                hired += if s.farm != NONE && f == s.farm { days } else { 0 };
            }
        }
        let members = i.map_or(Vec::new(), |i| self.members.get(i.at as usize..i.at as usize + i.size as usize).map_or(Vec::new(), |v| v.to_vec()));
        Some(HouseholdLook {
            kind: s.kind,
            fed: s.fed,
            pantry_kg: s.pantry,
            money,
            money_head: head,
            farm: farm.map(|f| (f.kind, f.area)),
            farm_id: farm.map(|_| s.farm),
            market: (mk != NONE).then(|| (mk, self.markets[mk as usize].name.clone())),
            grain_price: if mk != NONE { self.markets[mk as usize].price } else { 0 },
            wage: if mk != NONE { self.markets[mk as usize].wage } else { 0 },
            size,
            adults: i.map_or(0, |i| i.adults),
            need_month_kg: i.map_or(0, |i| i.need_w as i64 * KG_PER_ADULT_YEAR / 10 / 12),
            members,
            craft: s.goods.craft,
            earned: s.goods.earned,
            worked_days: worked,
            hired_days: hired,
            clothes_pct: i.map_or(0, |i| s.goods.clothes * 100 / (i.need_w as i64 * 100).max(1)),
            rank_all: if all > 0.0 { below / all } else { 0.0 },
            rank_market: if all_m > 0.0 { below_m / all_m } else { 0.0 },
        })
    }

    /// Rich and poor: one row per household kind with households, people,
    /// money (farms with their farm), money per head, grain eaten of the
    /// need in the last month, clothing held of the need, households with
    /// less than half their clothing.
    pub(super) fn class_table(&self, day: i64) -> Table {
        let (hh, ppl, _, _) = self.kinds_report();
        let (money, _) = self.money_by_kind();
        let clothes = self.clothes_by_kind();
        let rows = self.history.rows.len();
        let eaten: Vec<f64> = (0..5)
            .map(|k| {
                let now = self.history.rows.last().map(|r| (r.extra.eaten_by[k], r.extra.need_by[k]));
                let before = if rows > 1 { Some((self.history.rows[rows - 2].extra.eaten_by[k], self.history.rows[rows - 2].extra.need_by[k])) } else { None };
                match (now, before) {
                    (Some(n), Some(b)) if n.1 > b.1 => ((n.0 - b.0) as f64 / (n.1 - b.1) as f64).min(1.0),
                    (Some(n), _) if n.1 > 0 => (n.0 as f64 / n.1 as f64).min(1.0),
                    _ => 1.0,
                }
            })
            .collect();
        let mut t = Table::new("classes", "Arm und Reich", day);
        t.id((0..5).collect());
        t.text("kind", "Schicht", CLASS_NAMES.iter().map(|s| s.to_string()).collect())
            .int("households", "Haushalte", "", hh.iter().map(|&x| x as i64).collect())
            .int("persons", "Menschen", "", ppl.iter().map(|&x| x as i64).collect())
            .float("money", "Geld", "Denar", money.to_vec())
            .float("money_head", "Geld je Kopf", "Denar", (0..5).map(|k| money[k] / ppl[k].max(1) as f64).collect())
            .float("eaten", "Gegessen vom Bedarf", "%", eaten)
            .float("clothes", "Kleidung vom Bedarf", "%", clothes.iter().map(|c| c.0 / 100.0).collect())
            .int("ragged", "Haushalte unter halber Kleidung", "", clothes.iter().map(|c| c.2 as i64).collect());
        t
    }

    /// The craft goods: one row per good with the median price (by
    /// people), the markets' stock, and since the start what was made,
    /// bought, carried between markets, and sold or bought beyond the map.
    pub(super) fn goods_table(&self, day: i64) -> Table {
        let (_, store, price) = self.goods_report();
        let g = &self.stats.goods;
        let units = |v: [i64; GOODS]| v.iter().map(|&x| x as f64 / 1e3).collect::<Vec<f64>>();
        let mut t = Table::new("goods", "Waren", day);
        t.id((0..GOODS as i64).collect());
        t.text("good", "Ware", GOOD_NAMES.iter().map(|s| s.to_string()).collect())
            .text("unit", "Einheit", GOOD_UNITS.iter().map(|s| s.to_string()).collect())
            .float("price", "Preis", "Denar", price.to_vec())
            .float("store", "Marktlager", "", store.to_vec())
            .float("made", "Hergestellt seit Start", "", units(g.made))
            .float("bought", "Gekauft seit Start", "", units(g.bought))
            .float("moved", "Zwischen Märkten seit Start", "", units(g.moved))
            .float("imported", "Von ausserhalb seit Start", "", units(g.out_import))
            .float("exported", "Nach ausserhalb seit Start", "", units(g.out_export));
        t
    }
}

/// A farm as its window shows it (people_dots.rs take_farm), as of now.
#[derive(Clone, Debug, Default)]
pub struct FarmLook {
    /// Index into FARM_KIND_NAMES.
    pub kind: u8,
    /// The household that works it and the one it pays rent to (NONE for
    /// none); the people of the first.
    pub hh: u32,
    pub landlord: u32,
    pub members: Vec<u32>,
    /// Its market (index, name).
    pub market: (u32, String),
    /// The farmhouse's fine tile centre and how far its fields reach from
    /// it, world km.
    pub at_km: (f64, f64),
    pub reach_km: f64,
    /// Fields, of them cleared land, sown, state land leased (m²); fine
    /// tiles they lie on.
    pub area: i64,
    pub poor: i64,
    pub sown: i64,
    pub state: i64,
    pub plots: usize,
    /// Net kg per ha; grain in store and money (milli-denarii); grain
    /// held back to sell, kg.
    pub net_kg_ha: i64,
    pub store: i64,
    pub money: i64,
    pub to_sell: i64,
    /// Day of the year of harvest and sowing.
    pub harvest_doy: i64,
    pub sow_doy: i64,
    /// Work outside the peaks since the last harvest: needed and done, days.
    pub off_need: i64,
    pub off_done: i64,
    /// Cleared under the Lex Manciana; years in a row unsown.
    pub manciana: bool,
    pub idle: u8,
    /// Tools (kg) and the share of the family's work they allow (0..1),
    /// storage jars, wool (kg), sheep, pork fattened a year (kg).
    pub tools_kg: f64,
    pub tools_share: f64,
    pub jars: f64,
    pub wool_kg: f64,
    pub sheep: i64,
    pub pork_kg_year: f64,
    /// Who worked here at the last weekly labour exchange: (household,
    /// days, WORK_SOW / WORK_HARVEST / WORK_OFF / WORK_SURPLUS).
    pub workers: Vec<(u32, i64, u8)>,
}

impl Grain {
    /// How far the farms' fields lie from their farmstead (for the scale
    /// across the zoom levels, Ramon 31.10.2026; read only): the share of
    /// all field area 0, 1, 2, 3–4, 5–6, 7–8 and more than 8 fine tiles
    /// away (centre to centre, a tile 1.5625 world km), the median and the
    /// 90th percentile by area in world km, and the farms with fields 7 or
    /// more tiles away (near FIELD_RADIUS, where taking land stops unless
    /// it is the start's own 25 km cell).
    pub fn field_report(&self) -> String {
        let at = PlotsAt::new(self, 0);
        let mut v: Vec<(f64, i64)> = Vec::new();
        let (mut farms, mut edge) = (0usize, 0usize);
        for fm in &self.farms {
            let (r0, c0) = ((fm.fine as i32 / self.cols_f) as f64, (fm.fine as i32 % self.cols_f) as f64);
            let mut far = false;
            let n = v.len();
            at.farm(fm, &mut |fine, m2, _, _| {
                let (r, c) = ((fine as i32 / self.cols_f) as f64, (fine as i32 % self.cols_f) as f64);
                let d = (r - r0).hypot(c - c0);
                far |= d >= 6.5;
                v.push((d, m2 as i64));
            });
            farms += usize::from(v.len() > n);
            edge += usize::from(far);
        }
        let total: i64 = v.iter().map(|x| x.1).sum::<i64>().max(1);
        let bins = [(0.0, 0.5), (0.5, 1.5), (1.5, 2.5), (2.5, 4.5), (4.5, 6.5), (6.5, 8.5), (8.5, f64::MAX)];
        let shares: Vec<String> = bins
            .iter()
            .zip(["0", "1", "2", "3-4", "5-6", "7-8", ">8"])
            .map(|(&(a, b), name)| format!("{name}: {:.1} %", 100.0 * v.iter().filter(|x| x.0 >= a && x.0 < b).map(|x| x.1).sum::<i64>() as f64 / total as f64))
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        let quantile = |q: f64| {
            let mut acc = 0;
            for x in &v {
                acc += x.1;
                if acc as f64 >= q * total as f64 {
                    return x.0 * crate::settle::FINE_KM;
                }
            }
            0.0
        };
        // the nearest field of each farm (near_field: the walk to the field)
        let mut near: Vec<f64> = self
            .farms
            .iter()
            .filter_map(|fm| {
                let ((x, z), _) = self.near_field(fm.hh)?;
                let (hx, hz) = self.settle.fine_centre_km(fm.fine);
                Some((x - hx).hypot(z - hz))
            })
            .collect();
        near.sort_by(|a, b| a.total_cmp(b));
        let near_q = |q: f64| near.get(((near.len() as f64 - 1.0) * q).round() as usize).copied().unwrap_or(0.0);
        format!(
            "fields by distance from the farmstead (fine tiles, share of the area): {} | median {:.2} km, p90 {:.2} km (world) | farms {farms}, with fields 7+ tiles away {edge} ({:.1} %) | nearest field of a farm: on its own tile {:.0} %, median {:.2} km, p75 {:.2} km, p90 {:.2} km\n",
            shares.join(", "),
            quantile(0.5),
            quantile(0.9),
            100.0 * edge as f64 / farms.max(1) as f64,
            100.0 * near.iter().filter(|&&d| d < 0.5).count() as f64 / near.len().max(1) as f64,
            near_q(0.5),
            near_q(0.75),
            near_q(0.9)
        )
    }

    /// Where the household `hh` goes to work its fields (Bauplan B step 4,
    /// Ramon 31.10.2026 «Felder bleiben, Weg schneller»): the centre of the
    /// fine tile with its farm's own or leased fields nearest the farmhouse
    /// tile (world km; on a tie the bigger piece of field, then the lower
    /// tile) and the m² of that piece. None without a farm it works or fields. The
    /// parcels inside the tile are the view's (sim_fields.gdshaderinc).
    pub fn near_field(&self, hh: u32) -> Option<((f64, f64), u32)> {
        let s = self.hh.get(&hh)?;
        let fm = self.farms.get(s.farm as usize).filter(|fm| s.farm != NONE && fm.hh == hh)?;
        let (r0, c0) = (fm.fine as i32 / self.cols_f, fm.fine as i32 % self.cols_f);
        let mut best: Option<(i32, std::cmp::Reverse<u32>, u32)> = None;
        PlotsAt::new(self, 0).farm(fm, &mut |fine, m2, _, _| {
            let (r, c) = (fine as i32 / self.cols_f, fine as i32 % self.cols_f);
            let key = ((r - r0).pow(2) + (c - c0).pow(2), std::cmp::Reverse(m2), fine);
            if best.is_none_or(|b| key < b) {
                best = Some(key);
            }
        });
        best.map(|(_, std::cmp::Reverse(m2), fine)| (self.settle.fine_centre_km(fine), m2))
    }

    /// The farm `f` (an index into the farms, as `HouseholdLook::farm_id`),
    /// if there is one and someone works it.
    pub fn farm_look(&self, f: usize) -> Option<FarmLook> {
        let fm = self.farms.get(f).filter(|fm| fm.hh != NONE)?;
        let at_km = self.settle.fine_centre_km(fm.fine);
        let mut reach_km = 0.0f64;
        PlotsAt::new(self, 0).farm(fm, &mut |fine, _, _, _| {
            let (x, z) = self.settle.fine_centre_km(fine);
            reach_km = reach_km.max((x - at_km.0).hypot(z - at_km.1));
        });
        let reach_km = reach_km + crate::settle::FINE_KM * 0.5;
        let members = self.info.get(&fm.hh).map_or(Vec::new(), |i| self.members.get(i.at as usize..i.at as usize + i.size as usize).map_or(Vec::new(), |v| v.to_vec()));
        let mk = fm.market as usize;
        let workers = self.markets.get(mk).map_or(Vec::new(), |m| m.work.iter().filter(|w| w.1 as usize == f && w.1 != NONE).map(|&(w, _, days, kind)| (w, days, kind)).collect());
        Some(FarmLook {
            kind: fm.kind,
            hh: fm.hh,
            landlord: fm.landlord,
            members,
            market: (fm.market, self.markets.get(mk).map_or(String::new(), |m| m.name.clone())),
            at_km,
            reach_km,
            area: fm.area,
            poor: fm.poor,
            sown: fm.sown,
            state: fm.state,
            plots: fm.plots.len() + fm.state_plots.len(),
            net_kg_ha: fm.net_kg_ha,
            store: fm.store,
            money: fm.money,
            to_sell: fm.to_sell,
            harvest_doy: fm.harvest_doy,
            sow_doy: fm.sow_doy,
            off_need: fm.off_need,
            off_done: fm.off_done,
            manciana: fm.manciana,
            idle: fm.idle,
            tools_kg: fm.goods.tools as f64 / 1000.0,
            tools_share: self.tool_factor(f as u32) as f64 / 1000.0,
            jars: fm.goods.jars as f64 / 1000.0,
            wool_kg: fm.goods.wool as f64 / 1000.0,
            sheep: fm.goods.sheep,
            pork_kg_year: fm.goods.pork_year as f64 / 1000.0,
            workers,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::{gini_lorenz, History, MarketMonth, MARKET_MONTHS};

    /// Ten years month by month, the years before as their mean on their
    /// last month's day.
    #[test]
    fn markets_thin_to_years() {
        let mut h = History::default();
        let month = |i: i64| vec![MarketMonth { price: i as f32, people: 10, ..Default::default() }; 3];
        for i in 0..(MARKET_MONTHS as i64 + 30) {
            h.keep_markets(i * 30, month(i));
        }
        assert_eq!(h.market_years, 2);
        assert_eq!(h.markets.len(), 2 + MARKET_MONTHS + 6);
        assert_eq!(h.markets[0].0, 11 * 30);
        assert!((h.markets[0].1[2].price - 5.5).abs() < 1e-6 && h.markets[1].1[0].price == 17.5 && h.markets[0].1[0].people == 10);
        assert_eq!(h.markets[2].0, 24 * 30);
        assert!(h.markets.windows(2).all(|w| w[0].0 < w[1].0));
    }

    /// Everyone equal: Gini 0 and the Lorenz curve on the diagonal; one
    /// household with all the money among ten of the same size: 0.9.
    #[test]
    fn gini_and_lorenz() {
        let (g, l) = gini_lorenz(&mut vec![(5, 2); 10]);
        assert!(g.abs() < 1e-9 && l.iter().enumerate().all(|(q, x)| (x - (q + 1) as f64 / 10.0).abs() < 1e-9));
        let mut v = vec![(0, 1); 9];
        v.push((1000, 1));
        let (g, l) = gini_lorenz(&mut v);
        assert!((g - 0.9).abs() < 1e-9, "{g}");
        assert!(l.iter().all(|&x| x.abs() < 1e-9));
        assert_eq!(gini_lorenz(&mut []).0, 0.0);
    }

    /// A farm's window reads it, finds it again from its household and
    /// changes nothing.
    #[test]
    fn farm_look_read_only() {
        use super::{Grain, People, NONE};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let mut g = Grain::new(&inp, &mut p);
        let before = g.fingerprint();
        let f = g.farms.iter().position(|f| f.hh != NONE).unwrap();
        let l = g.farm_look(f).unwrap();
        assert_eq!(l.hh, g.farms[f].hh);
        assert!(l.area > 0 && l.reach_km > 0.0 && l.market.0 == g.farms[f].market);
        assert_eq!(g.household(l.hh).and_then(|h| h.farm_id), Some(f as u32));
        assert!(g.farm_look(g.farms.len()).is_none());
        assert_eq!(before, g.fingerprint());
    }
}
