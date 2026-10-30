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
}

impl Grain {
    /// The month's levels for `track`.
    pub(super) fn history_extra(&self) -> HistoryExtra {
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
