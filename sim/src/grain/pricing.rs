//! Prices from storage and dealers with stock (S112, Ramon 29.10.2026:
//! „okay dann setz es um“ on the proposal „Ökonomische Modelle für die
//! Simulation“, https://claude.ai/artifact/G7VhJisPQZRK3AHLK1zgum). The
//! same rule runs for grain and for each craft good, per market, once a
//! day. There is no base price and no band: the Edict gives only the
//! price on the first day.
//!
//! Observed rules (research):
//! - Competitive storage (Williams & Wright, 1991; Deaton & Laroque, 1992;
//!   Cafiero et al., 2011): while there is stock to carry, the price rises
//!   through the supply year by the cost of carrying it (interest and
//!   spoilage); when the stock runs out it jumps; a large supply pushes it
//!   down. At the new harvest it falls back.
//! - Dealers with stock (Ho & Stoll, 1981; Avellaneda & Stoikov, 2008):
//!   a dealer quotes around his own value of the good and moves the quote
//!   against his stock: above the stock he wants, lower, so that less
//!   comes in and more goes out; below it, higher.
//! - Agent-based markets set prices this way, from their own stock and
//!   sales, without an auctioneer (Lengnick, 2013; Axtell & Farmer, 2025).
//!
//! Built here (own choices, PLACEHOLDER where marked):
//! - The dealers' value is the usual price (`norm`, without the season)
//!   times the season's point on the carrying path. On that path a unit
//!   held for a month is worth the expected price in a month after
//!   interest and spoilage, so holding and selling are worth the same.
//! - The quote moves that value by the square root of planned stock over
//!   stock (planned: TARGET_DAYS of sales; the square root is a frei
//!   gewählt elasticity), with SOFT_DAYS of sales added to both so an
//!   empty store gives a finite, high price. The stock counts only up to
//!   the dealers' limit (DEALER_MAX_DAYS): beyond it they buy nothing, so
//!   a lower price moves nothing more.
//! - The usual price moves only when the stock leaves a band (as the firms
//!   in Lengnick, 2013): below LOW_DAYS of sales it rises by the
//!   shortfall's share, at the dealers' limit (DEALER_MAX_DAYS, where they
//!   turn sellers away) it falls, at most 1/ADJUST_DAYS a day. Within the
//!   band the stock moves the price alone. A market without sales keeps
//!   its usual price: its dealers want no stock and quote as at their
//!   limit, so farms hold their grain instead of being turned away.
//! - The price moves 1/PRICE_STEP of the way to the quote each day.
//!
//! Prices are milli-denarii per unit; `norm` is milli-denarii × 1000.

use super::*;

/// Interest a year, per cent: 1 % a month (centesimae usurae), the usual
/// rate in loan contracts of Roman Egypt and the legal maximum.
/// PLACEHOLDER, from memory: source to check (Rathbone, Temin).
pub(crate) const INTEREST_PCT_YEAR: i64 = 12;
/// The usual price moves by at most 1/ADJUST_DAYS a day (frei gewählt).
const ADJUST_DAYS: i64 = 365;
/// Days of sales added to stock and planned stock (frei gewählt).
const SOFT_DAYS: i64 = 7;
/// Below this many days of sales in store the usual price rises (the
/// band's lower end; the upper end is the dealers' limit, frei gewählt).
const LOW_DAYS: i64 = TARGET_DAYS / 3;

/// Price at `days_since` the last supply (harvest, shearing) relative to
/// the year's mean, per mille: the carrying path, `carry_pct` a year.
pub(crate) fn season(days_since: i64, carry_pct: i64) -> i64 {
    1000 + carry_pct * 10 * (days_since.rem_euclid(YEAR) * 1000 / YEAR - 500) / 1000
}

/// Days of sales in the dealers' store, × 1000, at most their limit
/// (DEALER_MAX_DAYS); without sales they want no stock, so any is at the
/// limit.
fn stock_days_x1000(store: i64, per_day: i64) -> i64 {
    if per_day > 0 {
        (store.max(0) as i128 * 1000 / per_day as i128).min(DEALER_MAX_DAYS as i128 * 1000) as i64
    } else {
        DEALER_MAX_DAYS * 1000
    }
}

/// The dealers' quote for one good at one market, one day: `price` moves
/// towards the usual price on the carrying path, shifted by the stock;
/// the stock against the planned stock moves the usual price `norm`.
pub(crate) fn quote(price: &mut i64, norm: &mut i64, store: i64, per_day: i64, season: i64) {
    let days = stock_days_x1000(store, per_day);
    let ratio_x1e6 = ((TARGET_DAYS + SOFT_DAYS) * 1000) as i128 * 1_000_000 / (days + SOFT_DAYS * 1000) as i128;
    let shift_x1000 = ratio_x1e6.isqrt() as i64;
    if per_day > 0 {
        // Outside the band: below LOW_DAYS up by the shortfall's share,
        // at the dealers' limit down.
        let gap = if days < LOW_DAYS * 1000 {
            (LOW_DAYS * 1000 - days) as i128 * 1000 / (LOW_DAYS * 1000) as i128
        } else if days >= DEALER_MAX_DAYS * 1000 {
            -1000
        } else {
            0
        };
        let d = *norm as i128 * gap / (1000 * ADJUST_DAYS as i128);
        *norm = (*norm as i128 + d).max(1000) as i64;
    }
    let target = (*norm as i128 * season as i128 * shift_x1000 as i128 / 1_000_000_000) as i64;
    let gap = target - *price;
    let step = if gap / PRICE_STEP != 0 { gap / PRICE_STEP } else { gap.signum() };
    *price = (*price + step).max(1);
}

/// Planned stock over stock and the usual price for a view, from the same
/// numbers as `quote`: (ratio, usual price in milli-denarii).
pub(crate) fn reasons(norm: i64, store: i64, per_day: i64) -> (f64, i64) {
    let days = stock_days_x1000(store, per_day);
    ((TARGET_DAYS + SOFT_DAYS) as f64 * 1000.0 / (days + SOFT_DAYS * 1000) as f64, norm / 1000)
}

/// One good at one market, for the market window and tables (read only):
/// the numbers behind the price and a sentence why.
#[derive(Clone, Debug, Default)]
pub struct GoodLook {
    /// "grain" or GOOD_KEYS, German name and unit.
    pub key: &'static str,
    pub name: &'static str,
    pub unit: &'static str,
    /// Price, the dealers' buying and selling price and the usual price at
    /// this time of year, denarii per unit.
    pub price: f64,
    pub buy: f64,
    pub sell: f64,
    pub usual: f64,
    /// Where the season is on the carrying path, per cent of the year's
    /// mean (100 for goods made all year).
    pub season_pct: f64,
    /// Store in units, sales per day (with what buyers found missing),
    /// days of sales in store and the days the dealers plan to hold.
    pub store: f64,
    pub sales_day: f64,
    pub stock_days: f64,
    pub planned_days: f64,
    /// Units a day buyers found missing and sellers were turned away with.
    pub missed_day: f64,
    pub turned_day: f64,
    /// Why the price is where it is, in German.
    pub why: String,
}

/// A market for the market window: dealers' cash and its goods, grain
/// first (`Grain::market_look`).
#[derive(Clone, Debug, Default)]
pub struct MarketLook {
    pub name: String,
    pub people: u32,
    /// Dealers' cash, denarii.
    pub money: f64,
    pub goods: Vec<GoodLook>,
}

/// Market table columns per good (static keys, GOOD_KEYS order).
const PRICE_COLS: [(&str, &str); GOODS] = [("price_wool", "Preis Wolle"), ("price_iron", "Preis Eisen"), ("price_cloth", "Preis Kleidung"), ("price_tools", "Preis Werkzeug"), ("price_pottery", "Preis Keramik"), ("price_pork", "Preis Schweinefleisch")];
const STORE_COLS: [(&str, &str); GOODS] = [("store_wool", "Lager Wolle"), ("store_iron", "Lager Eisen"), ("store_cloth", "Lager Kleidung"), ("store_tools", "Lager Werkzeug"), ("store_pottery", "Lager Keramik"), ("store_pork", "Lager Schweinefleisch")];
const WHY_COLS: [(&str, &str); GOODS] = [("why_wool", "Warum Preis Wolle"), ("why_iron", "Warum Preis Eisen"), ("why_cloth", "Warum Preis Kleidung"), ("why_tools", "Warum Preis Werkzeug"), ("why_pottery", "Warum Preis Keramik"), ("why_pork", "Warum Preis Schweinefleisch")];

/// The S112 columns of the markets table, rows in `order`: the grain
/// price's reasons, then price and store of each good.
pub(super) fn market_columns(g: &Grain, t: &mut Table, order: &[usize]) {
    let looks: Vec<MarketLook> = order.iter().map(|&m| g.market_look(m).unwrap_or_default()).collect();
    let col = |k: usize, f: &dyn Fn(&GoodLook) -> f64| looks.iter().map(|l| l.goods.get(k).map_or(0.0, f)).collect::<Vec<f64>>();
    t.float("usual_price", "Üblicher Preis", "Denar/kg", col(0, &|l| l.usual))
        .float("stock_days", "Lager", "Tage", col(0, &|l| l.stock_days))
        .float("season", "Jahreszeit", "× Jahresmittel", col(0, &|l| l.season_pct / 100.0))
        .float("missed_day", "Käufer ohne Ware", "kg/Tag", col(0, &|l| l.missed_day))
        .float("turned_day", "Verkäufer abgewiesen", "kg/Tag", col(0, &|l| l.turned_day))
        .text("why", "Warum Preis Getreide", looks.iter().map(|l| l.goods.first().map_or(String::new(), |g| g.why.clone())).collect());
    // S115, S119: the state's and the landlords' granaries at the market.
    t.float("granary_state", "Staatsspeicher", "t", order.iter().map(|&m| g.markets[m].horreum as f64 / 1e3).collect())
        .float("granary_lords", "Speicher der Grundherren", "t", order.iter().map(|&m| g.markets[m].lords.iter().map(|l| l.1).sum::<i64>() as f64 / 1e3).collect());
    for k in 0..GOODS {
        t.float(PRICE_COLS[k].0, PRICE_COLS[k].1, "Denar", col(k + 1, &|l| l.price));
        t.float(STORE_COLS[k].0, STORE_COLS[k].1, GOOD_UNITS[k], col(k + 1, &|l| l.store));
    }
    for k in 0..GOODS {
        t.text(WHY_COLS[k].0, WHY_COLS[k].1, looks.iter().map(|l| l.goods.get(k + 1).map_or(String::new(), |g| g.why.clone())).collect());
    }
}

/// The sentence for a good's price from its numbers.
fn why(l: &GoodLook, seasonal: Option<&str>) -> String {
    let mut out = Vec::new();
    if l.sales_day < 1.0 {
        out.push("Kaum Handel: Es gilt der übliche Preis.".to_string());
    } else {
        let shift = ((l.planned_days + SOFT_DAYS as f64) / (l.stock_days.min(DEALER_MAX_DAYS as f64) + SOFT_DAYS as f64)).sqrt();
        let pct = (shift - 1.0) * 100.0;
        if pct >= 5.0 {
            out.push(format!("Lager knapp: {:.0} Tage statt geplant {:.0}, darum {:.0} % über dem üblichen Preis, und der übliche Preis steigt.", l.stock_days, l.planned_days, pct));
        } else if pct <= -5.0 {
            out.push(format!("Lager voll: {:.0} Tage statt geplant {:.0}, darum {:.0} % unter dem üblichen Preis, und der übliche Preis sinkt.", l.stock_days, l.planned_days, -pct));
        } else {
            out.push(format!("Lager wie geplant ({:.0} Tage).", l.stock_days));
        }
    }
    if let Some(since) = seasonal {
        let d = l.season_pct - 100.0;
        if d >= 0.0 {
            out.push(format!("{since}: Lagerkosten heben den Preis um {d:.0} % über das Jahresmittel."));
        } else {
            out.push(format!("{since}: frische Ware, {:.0} % unter dem Jahresmittel.", -d));
        }
    }
    if l.missed_day >= 0.5 && l.missed_day >= l.turned_day {
        out.push(format!("Käufer fanden {:.0} {} am Tag nicht.", l.missed_day, l.unit));
    } else if l.turned_day >= 0.5 {
        out.push(format!("Händler wiesen {:.0} {} am Tag ab, ihr Lager ist voll.", l.turned_day, l.unit));
    }
    out.join(" ")
}

impl Grain {
    /// The market window's numbers and reasons for market `m` (S112).
    pub fn market_look(&self, m: usize) -> Option<MarketLook> {
        let mk = self.markets.get(m)?;
        let today = doy(self.today);
        let mut goods = Vec::with_capacity(GOODS + 1);
        let per_day = mk.demand / 1000;
        let since = (today - mk.harvest_doy).rem_euclid(YEAR);
        let season_g = season(since, INTEREST_PCT_YEAR + SPOIL_PCT_YEAR);
        let mut l = GoodLook {
            key: "grain",
            name: "Getreide",
            unit: "kg",
            price: mk.price as f64 / 1e3,
            buy: Self::buy_price(mk) as f64 / 1e3,
            sell: Self::sell_price(mk) as f64 / 1e3,
            usual: (mk.norm as f64 / 1e6) * season_g as f64 / 1e3,
            season_pct: season_g as f64 / 10.0,
            store: mk.store as f64,
            sales_day: mk.demand as f64 / 1e3,
            stock_days: if per_day > 0 { mk.store as f64 / per_day as f64 } else { 0.0 },
            planned_days: TARGET_DAYS as f64,
            missed_day: mk.missed_avg as f64 / 1e3,
            turned_day: mk.turned_avg as f64 / 1e3,
            why: String::new(),
        };
        l.why = why(&l, Some(&format!("{since} Tage seit der Ernte")));
        goods.push(l);
        let wool_since = (today - crafts::SHEAR_DOY).rem_euclid(YEAR);
        for (g, w) in mk.goods.iter().enumerate() {
            let s = if g == crafts::WOOL { season(wool_since, INTEREST_PCT_YEAR) } else { 1000 };
            let per_day = w.demand / 1000;
            let mut l = GoodLook {
                key: GOOD_KEYS[g],
                name: GOOD_NAMES[g],
                unit: GOOD_UNITS[g],
                price: w.price as f64 / 1e3,
                buy: w.price as f64 * (100 - SPREAD_PCT) as f64 / 1e5,
                sell: w.price as f64 * (100 + SPREAD_PCT) as f64 / 1e5,
                usual: (w.norm as f64 / 1e6) * s as f64 / 1e3,
                season_pct: s as f64 / 10.0,
                store: w.store as f64 / 1e3,
                sales_day: w.demand as f64 / 1e6,
                stock_days: if per_day > 0 { w.store as f64 / per_day as f64 } else { 0.0 },
                planned_days: TARGET_DAYS as f64,
                missed_day: w.missed_avg as f64 / 1e6,
                turned_day: w.turned_avg as f64 / 1e6,
                why: String::new(),
            };
            let seasonal = (g == crafts::WOOL).then(|| format!("{wool_since} Tage seit der Schur"));
            l.why = why(&l, seasonal.as_deref());
            goods.push(l);
        }
        Some(MarketLook { name: mk.name.clone(), people: mk.people, money: mk.money as f64 / 1e3, goods })
    }

    /// Debug line (PRICE_DEBUG): markets by planned stock over stock,
    /// dealers' stock and sales, what farms owe and hold back.
    pub fn price_debug(&self) -> String {
        let ms: Vec<&Market> = self.markets.iter().filter(|m| m.people > 0).collect();
        let mut r: Vec<f64> = ms.iter().map(|m| reasons(m.norm, m.store, m.demand / 1000).0).collect();
        r.sort_by(f64::total_cmp);
        let q = |x: f64| r.get(((r.len() as f64 - 1.0) * x) as usize).copied().unwrap_or(0.0);
        let capped = ms.iter().filter(|m| m.store >= m.demand / 1000 * DEALER_MAX_DAYS).count();
        let store: i64 = ms.iter().map(|m| m.store).sum();
        let sales: i64 = ms.iter().map(|m| m.demand / 1000).sum();
        let (mut held, mut retry) = (0i64, 0usize);
        for f in self.farms.iter().filter(|f| f.hh != NONE) {
            held += f.store;
            retry += f.retry as usize;
        }
        let horrea: i64 = self.markets.iter().map(|m| m.horreum).sum();
        let lords: i64 = self.markets.iter().flat_map(|m| m.lords.iter().map(|l| l.1)).sum();
        let mut norm: Vec<i64> = ms.iter().map(|m| m.norm / 1000).collect();
        norm.sort_unstable();
        // By sales: the usual price where the grain is bought.
        let mut by: Vec<(i64, i64)> = ms.iter().map(|m| (m.norm / 1000, m.demand / 1000)).collect();
        by.sort_unstable();
        let half = by.iter().map(|x| x.1).sum::<i64>() / 2;
        let mut acc = 0;
        let by_sales = by.iter().find(|x| {
            acc += x.1;
            acc > half
        }).map_or(0, |x| x.0);
        format!(
            "      prices (S112): planned/stock p10 {:.2} p50 {:.2} p90 {:.2} | at dealer cap {}/{} | dealer stock t {} sales t/d {:.1} | granaries state/lords t {}/{} | farms hold t {} retry {} | usual price p50 {:.2} by sales {:.2}\n",
            q(0.1), q(0.5), q(0.9), capped, ms.len(), store / 1000, sales as f64 / 1000.0, horrea / 1000, lords / 1000, held / 1000, retry, norm[norm.len() / 2] as f64 / 1000.0, by_sales as f64 / 1000.0
        ) + &self.city_debug(&ms)
    }

    fn city_debug(&self, ms: &[&Market]) -> String {
        let mut wage: Vec<i64> = ms.iter().map(|m| m.wage).collect();
        wage.sort_unstable();
        let mut real: Vec<i64> = ms.iter().map(|m| m.wage * 1000 / m.price.max(1)).collect();
        real.sort_unstable();
        let (vac, idle): (i64, i64) = ms.iter().fold((0, 0), |a, m| (a.0 + m.vacant_week, a.1 + m.idle_week));
        let (mut miss, mut turn) = (0i64, 0i64);
        for m in ms {
            miss += m.missed_avg / 1000;
            turn += m.turned_avg / 1000;
        }
        let mut s = format!(
            "      in t farm/gate/fetch/trader/granary {:?} | fetched/sent by dealers t {:.0}/{:.0} | out/in beyond the map t {:.0}/{:.0} | sown/full {:.0} % | wage den p50 {:.2} | real wage kg p10 {:.2} p50 {:.2} p90 {:.2} | vacant/idle days a week {}/{} | missed/turned t/d {:.1}/{:.1}\n",
            self.stats.inflow.map(|x| x / 1000), self.stats.arbitrage_kg as f64 / 1e3, self.stats.pushed_kg as f64 / 1e3, self.stats.out_export_kg as f64 / 1e3, self.stats.out_import_kg as f64 / 1e3, self.stats.plan_m2 as f64 * 100.0 / self.stats.plan_full_m2.max(1) as f64, wage[wage.len() / 2] as f64 / 1e3, real[real.len() / 10] as f64 / 1e3, real[real.len() / 2] as f64 / 1e3, real[real.len() * 9 / 10] as f64 / 1e3, vac, idle, miss as f64 / 1e3, turn as f64 / 1e3
        );
        let mut big: Vec<&&Market> = ms.iter().collect();
        big.sort_by_key(|m| std::cmp::Reverse(m.people));
        for m in big.iter().take(6) {
            let pd = m.demand / 1000;
            s += &format!(
                "        {:<22} ppl {:>5} price {:>6.2} usual {:>6.2} days {:>4} sales/d {:>5} missed/d {:>5} turned/d {:>5} wage {:>6.2} gate {}\n",
                m.name.chars().take(22).collect::<String>(), m.people, m.price as f64 / 1e3, m.norm as f64 / 1e6, if pd > 0 { m.store / pd } else { -1 }, pd, m.missed_avg / 1000, m.turned_avg / 1000, m.wage as f64 / 1e3, m.out_cost
            );
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn season_mean_is_one() {
        let sum: i64 = (0..YEAR).map(|d| season(d, 16)).sum();
        assert!((sum / YEAR - 1000).abs() <= 1);
        assert_eq!(season(0, 16), 920);
        assert!(season(YEAR - 1, 16) > 1075);
    }

    #[test]
    fn stock_moves_the_price() {
        let (mut p, mut n) = (8_750, 8_750_000);
        // Planned stock held: price and usual price stay.
        for _ in 0..400 {
            quote(&mut p, &mut n, 9_000, 100, 1000);
        }
        assert!((p - 8_750).abs() < 100 && n == 8_750_000, "{p} {n}");
        // Empty store: the price rises, and the usual price with it.
        for _ in 0..200 {
            quote(&mut p, &mut n, 0, 100, 1000);
        }
        assert!(p > 30_000 && n > 12_000_000, "{p} {n}");
        // A store far above plan: both fall.
        let n0 = n;
        for _ in 0..200 {
            quote(&mut p, &mut n, 40_000, 100, 1000);
        }
        assert!(n < n0 * 3 / 4 && p < n / 1000, "{p} {n}");
        // No sales at all: the usual price stays, the dealers quote as at
        // their limit.
        let n1 = n;
        for _ in 0..400 {
            quote(&mut p, &mut n, 5_000, 0, 1000);
        }
        let at_limit = ((n1 / 1000) as f64 * ((TARGET_DAYS + SOFT_DAYS) as f64 / (DEALER_MAX_DAYS + SOFT_DAYS) as f64).sqrt()) as i64;
        assert!(n == n1 && (p - at_limit).abs() < 100, "{p} {n} {at_limit}");
    }
}
