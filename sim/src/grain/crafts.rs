//! Craft goods (S105–S110, Ramon 29.10.2026: „Kleidung, Werkzeug, Keramik“,
//! proposal „Handwerk: Kleidung, Werkzeug, Keramik“ approved with its four
//! recommendations). Wool, iron, clothing, tools and pottery each have a
//! store, a price and the regional market's dealers, built like grain:
//! the price is the dealers' quote from their stock (S112, `pricing`), the
//! dealers buy up to DEALER_MAX_DAYS of sales as far as their cash goes
//! (S100), and the cash is the same as for grain (`Market::money`).
//!
//! Who makes what: farms keep sheep on the pasture near their fields and
//! shear them once a year (S106); households not in the state's service
//! and without a farm choose each month the craft that brings most, or
//! day labour (S107); smiths work iron from beyond the map (S98, S108);
//! potters need no bought input (S109). Who uses what: every household
//! wears out clothing and cookware; farms wear out tools (fewer tools,
//! slower work) and storage jars (grain beyond the jars spoils faster).
//! A household makes its own clothing when its time and wool cost less
//! than the market's price (S107). Purchases come out of the money left
//! after a food reserve (budget), so more money buys more goods and moves
//! the price, without a rule.
//!
//! Units: stocks in milli-units (milli-kg, milli-garments), prices in
//! milli-denarii per unit. PLACEHOLDER unless a source is named.

use super::*;

pub const GOODS: usize = 5;
pub const WOOL: usize = 0;
pub const IRON: usize = 1;
pub const CLOTH: usize = 2;
pub const TOOLS: usize = 3;
pub const POTS: usize = 4;
pub const GOOD_KEYS: [&str; GOODS] = ["wool", "iron", "cloth", "tools", "pottery"];
pub const GOOD_NAMES: [&str; GOODS] = ["Wolle", "Eisen", "Kleidung", "Werkzeug", "Keramik"];
pub const GOOD_UNITS: [&str; GOODS] = ["kg", "kg", "Stück", "kg", "kg"];

/// Price per unit on the first day and beyond the map (S98, S112),
/// milli-denarii: wool
/// 25 den./lb (Edict XXV.5, ≈ 76 den./kg); a plain tunic 800 den. (30
/// days of spinning and weaving at 25 den. plus wool; Edict XXVI.75–77:
/// 500–800); iron 20 den./kg and tools 60 den./kg PLACEHOLDER (no iron
/// price in the Edict as translated; tools set so a smith earns about the
/// Edict's 50 den. a day, VII.11); pottery 5 den./kg (Edict XV.78–80 and
/// XV.77: 2 den. for a 2-sextarii jug up to 1,000 den. for a dolium, by
/// guessed weights).
pub(crate) const GOOD_BASE: [i64; GOODS] = [76_000, 20_000, 800_000, 60_000, 5_000];

/// Clothing worn out per adult a year, milli-garments: a tunic every year
/// and a cloak every other year (Cato, De agri cultura 59); a child half.
const CLOTH_YEAR: i64 = 1500;
/// Working days for one garment from washed wool: spinning 127–250 h per
/// kg (Tools and Textiles, Technical Report 1), 83–86 % of the work
/// (Devereaux, after Aldrete et al. 2013), so about 30 days with weaving
/// and fulling (PLACEHOLDER: 1 kg wool per garment).
const CLOTH_DAYS: i64 = 30;
/// Cookware a household keeps, kg, and its wear per year (PLACEHOLDER:
/// lamps last about half a year, Peña 2007; cooking pots open).
const POTS_KG_HH: i64 = 5;
const POTS_WEAR_PCT: i64 = 100;
/// Tools per hectare under grain, kg, and their wear per year; without
/// tools a farm's family works at TOOL_MIN per mille (PLACEHOLDER).
const TOOLS_KG_HA: i64 = 2;
const TOOLS_WEAR_PCT: i64 = 10;
const TOOL_MIN: i64 = 700;
/// Storage jars: kg of grain one kg of fired clay holds (a dolium of
/// 1,000 sextarii ≈ 420 kg of wheat, its weight guessed at 140 kg), their
/// wear per year (a dolium lasts about 25 years, Peña 2007), and the
/// spoilage per year of grain beyond the jars (PLACEHOLDER; in jars
/// SPOIL_PCT_YEAR, S72).
const JAR_GRAIN_KG: i64 = 3;
const JAR_WEAR_PCT: i64 = 4;
pub(super) const SPOIL_OPEN_PCT_YEAR: i64 = 12;
/// Sheep per hectare of pasture (0.6–1.2 in Mediterranean systems:
/// Treacher; Sierra Mágina), at most this many per household member, and
/// wool per sheep and year, kg (about 1 kg, PLACEHOLDER), shorn on this
/// day of the year.
const SHEEP_PER_HA_X10: i64 = 10;
const SHEEP_PER_PERSON: i64 = 5;
const WOOL_KG_SHEEP: i64 = 1;
pub(super) const SHEAR_DOY: i64 = 135;
/// Iron per kg of tools, milli-kg, and tools a smith makes a day, milli-kg
/// (PLACEHOLDER); pottery a potter makes a day, milli-kg (75 den. a day,
/// Edict VII.29, at the base price).
const IRON_PER_TOOL: i64 = 1250;
const TOOLS_DAY: i64 = 1500;
const POTS_DAY: i64 = 15_000;
/// Share of its adults' working days a household can give to home work
/// in a month, per cent (PLACEHOLDER).
const HOME_PCT: i64 = 50;
/// S111: a household keeps this many days of its adults' day wages as
/// savings beyond its food reserve, and of the money beyond it spends this
/// share a month on hired work for money (servants, builders; PLACEHOLDER).
const SAVE_DAYS: i64 = 365;
pub(super) const SERVE_PCT_MONTH: i64 = 2;
/// A craft household changes its work only for this much more income, per
/// cent (PLACEHOLDER: the cost of changing).
const SWITCH_PCT: i64 = 110;
/// Households twice / five times as rich as their clothing's worth keep
/// more of everything (PLACEHOLDER: up to three times the plain need).
const RICH: [i64; 2] = [4, 20];

/// Goods moves kept for the view (`goods_moves_in`), days.
pub(super) const MOVES_KEEP_DAYS: i64 = 28;

/// Workshops in a box (`Grain::crafts_in`), one entry per craft
/// household: household, craft (CRAFT_NAMES, 1–3), share of the month's
/// work the dealers took (0–255), fine cell and place in world km.
#[derive(Default, Clone, Debug)]
pub struct CraftsView {
    pub household: Vec<i64>,
    pub craft: Vec<u8>,
    pub util: Vec<u8>,
    pub fine: Vec<u32>,
    pub at: Vec<(f32, f32)>,
}

/// Goods carried between markets in the last MOVES_KEEP_DAYS days that
/// start or end in a box (`Grain::goods_moves_in`): day, good (GOOD_KEYS),
/// units, and the two markets' places in world km.
#[derive(Default, Clone, Debug)]
pub struct GoodsMovesView {
    pub day: Vec<i64>,
    pub good: Vec<u8>,
    pub units: Vec<f32>,
    pub from: Vec<(f32, f32)>,
    pub to: Vec<(f32, f32)>,
}

/// A craft: what it makes, how much a day, from what.
struct Craft {
    out: usize,
    per_day: i64,
    /// Input good and milli-units of it per unit made.
    input: Option<(usize, i64)>,
}

const CRAFTS: [Craft; 3] = [
    Craft { out: CLOTH, per_day: 1000 / CLOTH_DAYS, input: Some((WOOL, 1000)) },
    Craft { out: TOOLS, per_day: TOOLS_DAY, input: Some((IRON, IRON_PER_TOOL)) },
    Craft { out: POTS, per_day: POTS_DAY, input: None },
];
/// `HhGoods::craft`: day labour, else CRAFTS[craft - 1].
pub const CRAFT_NAMES: [&str; 4] = ["Taglohn", "Weber", "Schmied", "Töpfer"];

/// A good at a market.
#[derive(Clone, Copy)]
pub struct Ware {
    pub store: i64,
    pub price: i64,
    /// Smoothed sales per day, milli-units × 1000.
    pub(super) demand: i64,
    pub(super) sold_today: i64,
    /// Asked for today and not in store: the dealers count it with their
    /// sales, so a good nobody can buy is not a good nobody wants.
    pub(super) missed_today: i64,
    /// S112: the usual price, milli-denarii × 1000, and what was offered
    /// to the dealers today and not taken.
    pub(super) norm: i64,
    pub(super) turned_today: i64,
    /// Missed and turned away per day, smoothed (view only).
    pub(super) missed_avg: i64,
    pub(super) turned_avg: i64,
}

pub(super) fn wares() -> [Ware; GOODS] {
    std::array::from_fn(|g| Ware { store: 0, price: GOOD_BASE[g], demand: 0, sold_today: 0, missed_today: 0, norm: GOOD_BASE[g] * 1000, turned_today: 0, missed_avg: 0, turned_avg: 0 })
}

fn gsell(w: &Ware) -> i64 {
    w.price * (100 + SPREAD_PCT) / 100
}
fn gbuy(w: &Ware) -> i64 {
    w.price * (100 - SPREAD_PCT) / 100
}
fn room(w: &Ware) -> i64 {
    (w.demand / 1000 * DEALER_MAX_DAYS - w.store).max(0)
}

/// What a household owns of the goods.
#[derive(Clone, Copy, Default)]
pub(super) struct HhGoods {
    pub clothes: i64,
    pub pots: i64,
    /// 0 day labour, else a craft (CRAFT_NAMES).
    pub craft: u8,
    /// Days of home work (spinning, weaving) this month; they come off
    /// the days it offers as day labour first.
    pub home_days: i64,
    /// S111: days of work it hires for money this month, still open.
    pub serve_days: i64,
    /// For the view only (`crafts_in`): share of this month's working days
    /// whose goods the dealers took, × 255.
    pub util: u8,
}

/// What a farm owns of the goods.
#[derive(Clone, Copy, Default)]
pub(super) struct FarmGoods {
    pub tools: i64,
    pub jars: i64,
    pub wool: i64,
    pub sheep: i64,
}

/// S110: the state wage goes only to soldiers, officers and officials.
pub(super) fn state_job(job: u8) -> bool {
    matches!(job, crate::groups::SOLDATEN | crate::groups::OFFIZIERE | crate::groups::BEAMTE)
}

/// Cash the dealers keep to buy TARGET_DAYS of each good's sales.
pub(super) fn dealer_buffer(m: &Market) -> i64 {
    m.goods.iter().map(|w| w.demand / 1000 * TARGET_DAYS * gbuy(w) / 1000).sum()
}

/// A household that lives from its own work outside farming: wage
/// households outside the state's service, and trader households while
/// their trader is at home (S107).
pub(super) fn free_worker(s: &HhState, i: &HhInfo) -> bool {
    !s.own_food && ((s.kind == WAGE && !state_job(i.job)) || (s.kind == TRADER && !s.trading))
}

/// Counters per good, reset with GrainStats.
#[derive(Default, Clone, Copy, Debug)]
pub struct GoodsStats {
    /// Made by craft households and sold to the dealers, milli-units.
    pub made: [i64; GOODS],
    /// Bought by households and farms for their own use.
    pub bought: [i64; GOODS],
    /// Carried from one market to another by its dealers.
    pub moved: [i64; GOODS],
    pub out_export: [i64; GOODS],
    pub out_import: [i64; GOODS],
    /// Clothing made at home, milli-garments; wool shorn, milli-kg.
    pub home_cloth: i64,
    pub shorn: i64,
    /// Household months by work (CRAFT_NAMES), and in the state's service.
    pub crafts: [u64; 4],
    pub state_months: u64,
    /// Clothing short of the plain need at the monthly count, summed over
    /// the households, milli-garments, and the need.
    pub clothes_short: i64,
    pub clothes_need: i64,
    /// S111: days hired for money and the money paid, milli-denarii.
    pub serve_days: i64,
    pub serve_paid: i64,
    /// Of it, paid by the markets' dealers.
    pub dealer_paid: i64,
}

impl Grain {
    /// Pasture per cell (S106): hectares of grassland per hectare of
    /// farmland, × 1000, from land cover shares (`clearable` of the grass
    /// and farm columns). Without it every farm has as much pasture as
    /// fields.
    pub fn set_pasture(&mut self, p: &People, grass: &Clearable, farm: &Clearable) {
        for (&(r, c), &g) in grass {
            let Some(i) = p.grid.index(r, c) else { continue };
            let f = farm.get(&(r, c)).copied().unwrap_or(0.0).max(0.05);
            self.pasture[i as usize] = (g / f * 1000.0).clamp(0.0, 5000.0) as u16;
        }
    }

    fn tools_need(&self, f: usize) -> i64 {
        self.cropped(self.farms[f].area) * TOOLS_KG_HA / 10
    }

    /// Share of a farm family's work its tools allow, per mille.
    pub(super) fn tool_factor(&self, f: u32) -> i64 {
        if f == NONE || !self.goods_on {
            return 1000;
        }
        let need = self.tools_need(f as usize);
        if need == 0 {
            return 1000;
        }
        TOOL_MIN + (1000 - TOOL_MIN) * self.farms[f as usize].goods.tools.min(need) / need
    }

    /// Grain a farm loses in store this month: in jars SPOIL_PCT_YEAR,
    /// beyond them SPOIL_OPEN_PCT_YEAR.
    pub(super) fn farm_spoil(&self, f: usize) -> i64 {
        let fm = &self.farms[f];
        let store = fm.store.max(0);
        let held = store.min(fm.goods.jars * JAR_GRAIN_KG / 1000);
        held * SPOIL_PCT_YEAR / 1200 + (store - held) * SPOIL_OPEN_PCT_YEAR / 1200
    }

    /// At the start: households hold their plain need of clothing and
    /// cookware, farms their tools and jars; the dealers hold TARGET_DAYS
    /// of the sales that need implies; wage households outside the state's
    /// service start with 60 days of the old state wage (PLACEHOLDER), so
    /// they can buy food until their first sales.
    pub(super) fn goods_start(&mut self) {
        self.goods_on = true;
        let mut need = vec![[0i64; GOODS]; self.markets.len()];
        for (id, i) in self.info.iter() {
            let Some(s) = self.hh.get_mut(id) else { continue };
            if s.own_food {
                continue;
            }
            s.goods.clothes = i.need_w as i64 * 100;
            s.goods.pots = POTS_KG_HH * 1000;
            if s.kind == WAGE && !state_job(i.job) {
                s.money += i.adults as i64 * STATE_WAGE * 60;
            }
            let mk = self.cell_market[i.home as usize];
            if mk == NONE {
                continue;
            }
            let n = &mut need[mk as usize];
            n[CLOTH] += i.need_w as i64 * CLOTH_YEAR / 10 / YEAR;
            n[WOOL] += i.need_w as i64 * CLOTH_YEAR / 10 / YEAR;
            n[POTS] += POTS_KG_HH * 1000 * POTS_WEAR_PCT / 100 / YEAR;
        }
        for f in 0..self.farms.len() {
            let tools = self.tools_need(f);
            let fm = &mut self.farms[f];
            if fm.hh == NONE {
                continue;
            }
            fm.goods.tools = tools;
            fm.goods.jars = fm.store.max(0) * 1000 / JAR_GRAIN_KG;
            let n = &mut need[fm.market as usize];
            n[TOOLS] += tools * TOOLS_WEAR_PCT / 100 / YEAR;
            n[IRON] += tools * TOOLS_WEAR_PCT / 100 / YEAR * IRON_PER_TOOL / 1000;
            n[POTS] += fm.goods.jars * JAR_WEAR_PCT / 100 / YEAR;
        }
        for (m, n) in self.markets.iter_mut().zip(need) {
            for g in 0..GOODS {
                m.goods[g].demand = n[g] * 1000;
                m.goods[g].store = n[g] * TARGET_DAYS;
            }
        }
    }

    /// The goods' prices, as grain's (`prices`, S112): wool comes once a
    /// year and is carried like grain (interest only), the others are made
    /// or brought all year and have no carrying path.
    pub(super) fn goods_prices(&mut self) {
        let wool = pricing::season(doy(self.today) - SHEAR_DOY, pricing::INTEREST_PCT_YEAR);
        for m in self.markets.iter_mut() {
            for (g, w) in m.goods.iter_mut().enumerate() {
                w.demand += ((w.sold_today + w.missed_today) * 1000 - w.demand) / MONTH;
                w.missed_avg += (w.missed_today * 1000 - w.missed_avg) / MONTH;
                w.turned_avg += (w.turned_today * 1000 - w.turned_avg) / MONTH;
                w.sold_today = 0;
                w.missed_today = 0;
                w.turned_today = 0;
                let season = if g == WOOL { wool } else { 1000 };
                pricing::quote(&mut w.price, &mut w.norm, w.store, w.demand / 1000, season);
            }
        }
    }

    /// The dealers buy up to `want` milli-units of good `g`, as far as
    /// their room and cash go; returns the amount and what they paid.
    fn dealer_take(&mut self, mk: usize, g: usize, want: i64) -> (i64, i64) {
        let m = &mut self.markets[mk];
        let price = gbuy(&m.goods[g]);
        let q = want.min(room(&m.goods[g])).min(m.money.max(0) * 1000 / price.max(1)).max(0);
        let pay = q * price / 1000;
        m.goods[g].store += q;
        m.goods[g].turned_today += want - q;
        m.money -= pay;
        (q, pay)
    }

    /// The dealers sell up to `want` milli-units of good `g` to a buyer
    /// with `budget`; returns the amount and its cost.
    fn dealer_give(&mut self, mk: usize, g: usize, want: i64, budget: i64) -> (i64, i64) {
        let m = &mut self.markets[mk];
        let w = &mut m.goods[g];
        let price = gsell(w);
        let wanted = want.min(budget.max(0) * 1000 / price.max(1)).max(0);
        let q = wanted.min(w.store.max(0));
        w.missed_today += wanted - q;
        let cost = q * price / 1000;
        w.store -= q;
        w.sold_today += q;
        m.money += cost;
        (q, cost)
    }

    /// What craft `c` brings in `days` at market `mk` now, milli-denarii,
    /// and the milli-units it can make and sell: output price less input,
    /// as far as the dealers' room and cash and the input in store go;
    /// last the milli-units it could make if the input were in store.
    fn craft_take(&self, mk: usize, c: &Craft, days: i64) -> (i64, i64, i64) {
        let m = &self.markets[mk];
        let out = &m.goods[c.out];
        let unit = gbuy(out) - c.input.map_or(0, |(g, per)| gsell(&m.goods[g]) * per / 1000);
        if unit <= 0 {
            return (0, 0, 0);
        }
        let inp = c.input.map_or(i64::MAX, |(g, per)| m.goods[g].store.max(0) * 1000 / per);
        let free = (days * c.per_day).min(room(out)).min(m.money.max(0) * 1000 / unit).max(0);
        let q = free.min(inp);
        (q * unit / 1000, q, free)
    }

    /// The month of a household's goods, after its meal (`eat`): wear,
    /// shearing and wool for sale, craft work, purchases and home work.
    pub(super) fn goods_month(&mut self, id: u32, info: &HhInfo, mk: usize, day: i64) {
        let Some(s) = self.hh.get(&id).copied() else { return };
        let mut g = s.goods;
        let need_w = info.need_w as i64;
        g.clothes = (g.clothes - need_w * CLOTH_YEAR / 10 / 12).max(0);
        g.home_days = 0;
        g.pots -= g.pots * POTS_WEAR_PCT / 1200;
        let (grain_buy, grain_sell) = (Self::buy_price(&self.markets[mk]), Self::sell_price(&self.markets[mk]));
        // A day of work is worth what day labour pays (S114: the wage).
        let day_value = self.markets[mk].wage;
        let need_day = need_w * KG_PER_ADULT_YEAR / 10 / YEAR;
        let reserve = need_day * RESERVE_DAYS * grain_sell;
        let f = s.farm;
        if f != NONE {
            let fu = f as usize;
            let tools_need = self.tools_need(fu);
            let fm = &mut self.farms[fu];
            fm.goods.tools -= fm.goods.tools * TOOLS_WEAR_PCT / 1200;
            fm.goods.jars -= fm.goods.jars * JAR_WEAR_PCT / 1200;
            // S106: shearing once a year; the flock follows the pasture
            // near the fields, fallow included, and the family's hands.
            if (SHEAR_DOY..SHEAR_DOY + MONTH).contains(&doy(day)) {
                let ha_x1000 = fm.area / 10;
                let sheep = (ha_x1000 * self.pasture[fm.cell as usize] as i64 / 1000 * SHEEP_PER_HA_X10 / 10_000).min(SHEEP_PER_PERSON * info.size as i64);
                fm.goods.sheep = sheep;
                fm.goods.wool += sheep * WOOL_KG_SHEEP * 1000;
                self.stats.goods.shorn += sheep * WOOL_KG_SHEEP * 1000;
            }
            // Wool beyond a year of the family's own clothing is sold.
            let keep = need_w * CLOTH_YEAR / 10;
            let surplus = self.farms[fu].goods.wool - keep;
            if surplus > 0 {
                let (q, pay) = self.dealer_take(mk, WOOL, surplus);
                self.farms[fu].goods.wool -= q;
                self.earn(id, pay);
                self.stats.goods.made[WOOL] += q;
            }
            let mut budget = self.money_of(id) - reserve;
            // Tools while they pay for themselves: a kg keeps 1/TOOLS_KG_HA
            // ha at full work, (1000 - TOOL_MIN) per mille of DAYS_PER_HA.
            let short = tools_need - self.farms[fu].goods.tools;
            let price = gsell(&self.markets[mk].goods[TOOLS]);
            if short > 0 && price * TOOLS_WEAR_PCT * TOOLS_KG_HA * 10 < (1000 - TOOL_MIN) * DAYS_PER_HA * day_value {
                let (q, cost) = self.dealer_give(mk, TOOLS, short, budget);
                self.farms[fu].goods.tools += q;
                self.pay(id, cost);
                budget -= cost;
                self.stats.goods.bought[TOOLS] += q;
            }
            // Jars for the store with a fifth to spare, while the grain
            // they save is worth their wear.
            let want = self.farms[fu].store.max(0) * 1200 / JAR_GRAIN_KG;
            let short = want - self.farms[fu].goods.jars;
            let price = gsell(&self.markets[mk].goods[POTS]);
            if short > 0 && price * JAR_WEAR_PCT < JAR_GRAIN_KG * grain_buy * (SPOIL_OPEN_PCT_YEAR - SPOIL_PCT_YEAR) {
                let (q, cost) = self.dealer_give(mk, POTS, short, budget);
                self.farms[fu].goods.jars += q;
                self.pay(id, cost);
                self.stats.goods.bought[POTS] += q;
            }
        }
        // S107: a household outside the state's service and without land
        // works at the craft that brings most this month, or as a day
        // labourer (`labour`), changing only for SWITCH_PCT more.
        let state = state_job(info.job);
        if free_worker(&s, info) {
            let days = info.adults as i64 * WORK_DAYS_YEAR / 12 * work_of_fed(s.fed) / 1000;
            let labour = day_value * days * self.markets[mk].hire_x1000 / 1000;
            let mut best = (if g.craft == 0 { labour * SWITCH_PCT / 100 } else { labour }, 0u8);
            // The craft that would pay most if its input were in store:
            // the household asks the dealers for that input.
            let mut wish = (best.0, 0usize, 0i64);
            for (k, c) in CRAFTS.iter().enumerate() {
                let (income, q, free) = self.craft_take(mk, c, days);
                let bonus = |x: i64| if g.craft as usize == k + 1 { x * SWITCH_PCT / 100 } else { x };
                if bonus(income) > best.0 {
                    best = (bonus(income), k as u8 + 1);
                }
                let could = if q > 0 { income * free / q } else { free * (gbuy(&self.markets[mk].goods[c.out]) - c.input.map_or(0, |(gi, per)| gsell(&self.markets[mk].goods[gi]) * per / 1000)) / 1000 };
                if free > q && bonus(could) > wish.0 {
                    wish = (bonus(could), k + 1, free - q);
                }
            }
            if wish.1 > 0 && wish.1 != best.1 as usize {
                if let Some((gi, per)) = CRAFTS[wish.1 - 1].input {
                    self.markets[mk].goods[gi].missed_today += wish.2 * per / 1000;
                }
            }
            g.craft = best.1;
            self.stats.goods.crafts[g.craft as usize] += 1;
            if g.craft > 0 {
                let c = &CRAFTS[g.craft as usize - 1];
                let (_, q, free) = self.craft_take(mk, c, days);
                let m = &mut self.markets[mk];
                let mut net = -(q * gbuy(&m.goods[c.out]) / 1000);
                m.goods[c.out].store += q;
                // S112: work the dealers had no room or cash for.
                m.goods[c.out].turned_today += days * c.per_day - free;
                if let Some((gi, per)) = c.input {
                    let units = q * per / 1000;
                    net += units * gsell(&m.goods[gi]) / 1000;
                    m.goods[gi].store -= units;
                    m.goods[gi].sold_today += units;
                }
                m.money += net;
                self.earn(id, -net);
                self.stats.goods.made[c.out] += q;
                g.util = (q * 255 / (days * c.per_day).max(1)).clamp(0, 255) as u8;
            } else {
                g.util = 0;
            }
        } else if state {
            self.stats.goods.state_months += 1;
        }
        let budget = self.money_of(id) - reserve;
        // Richer households keep more (RICH).
        let plain = need_w * 100;
        let worth = plain * gsell(&self.markets[mk].goods[CLOTH]) / 1000;
        let rich = 1 + RICH.iter().filter(|&&k| budget > k * worth).count() as i64;
        let mut budget = budget;
        self.stats.goods.clothes_short += (plain - g.clothes).max(0);
        self.stats.goods.clothes_need += plain;
        let mut short = (plain * rich - g.clothes).max(0);
        if short > 0 {
            // Make or buy (S107): the household's days and wool against
            // the dealers' price.
            let can_make = matches!(s.kind, FARM | TENT) || (free_worker(&s, info) && g.craft == 0);
            let cap = info.adults as i64 * WORK_DAYS_YEAR / 12 * HOME_PCT / 100 * 1000 / CLOTH_DAYS;
            let own_wool = if f != NONE { self.farms[f as usize].goods.wool } else { 0 };
            let wool_cost = if own_wool > 0 { gbuy(&self.markets[mk].goods[WOOL]) } else { gsell(&self.markets[mk].goods[WOOL]) };
            if can_make && CLOTH_DAYS * day_value + wool_cost < gsell(&self.markets[mk].goods[CLOTH]) {
                let own = own_wool.min(short).min(cap);
                if f != NONE {
                    self.farms[f as usize].goods.wool -= own;
                }
                let (bought, cost) = self.dealer_give(mk, WOOL, short.min(cap) - own, budget);
                self.pay(id, cost);
                budget -= cost;
                self.stats.goods.bought[WOOL] += bought;
                let made = own + bought;
                g.clothes += made;
                g.home_days += made * CLOTH_DAYS / 1000;
                self.stats.goods.home_cloth += made;
                short -= made;
            }
            if short > 0 {
                let (q, cost) = self.dealer_give(mk, CLOTH, short, budget);
                g.clothes += q;
                self.pay(id, cost);
                budget -= cost;
                self.stats.goods.bought[CLOTH] += q;
            }
        }
        let short = (POTS_KG_HH * 1000 * rich - g.pots).max(0);
        if short > 0 {
            let (q, cost) = self.dealer_give(mk, POTS, short, budget);
            g.pots += q;
            self.pay(id, cost);
            self.stats.goods.bought[POTS] += q;
        }
        // S111: money beyond the savings hires work.
        let save = SAVE_DAYS * day_value * (info.adults as i64).max(1);
        let spare = self.money_of(id) - reserve - save;
        let days = if spare > 0 { spare * SERVE_PCT_MONTH / 100 / day_value.max(1) } else { 0 };
        if days > 0 && g.serve_days == 0 {
            self.markets[mk].servers.push(id);
        }
        g.serve_days = days;
        if let Some(s) = self.hh.get_mut(&id) {
            s.goods = g;
        }
    }

    /// Once a week per market (1/7 a day): the dealers carry each good
    /// from the neighbour (S71 graph) where it costs, with freight, most
    /// below their own price (they earn their spread when they sell), and
    /// trade with the markets beyond the
    /// map at gate markets (S98) as grain does; iron comes in only that way
    /// (S108). PLACEHOLDER: the goods arrive the same day, without trips.
    pub(super) fn goods_trade(&mut self, day: i64) {
        let wd = day.rem_euclid(7) as usize;
        self.goods_moves.retain(|m| m.0 > day - MOVES_KEEP_DAYS);
        for mi in (wd..self.markets.len()).step_by(7) {
            let gate = self.markets[mi].out_cost > 0;
            let out_cost = self.freight(self.markets[mi].out_cost, mi);
            for g in 0..GOODS {
                if gate {
                    let m = &mut self.markets[mi];
                    let w = &mut m.goods[g];
                    let out_buy = GOOD_BASE[g] * (100 - SPREAD_PCT) / 100 - out_cost;
                    let out_sell = GOOD_BASE[g] * (100 + SPREAD_PCT) / 100 + out_cost;
                    if out_buy > gsell(w) {
                        let q = (w.store / 4).max(0);
                        let pay = q * out_buy / 1000;
                        w.store -= q;
                        m.money += pay;
                        self.money.exports += pay;
                        self.stats.goods.out_export[g] += q;
                    } else if out_sell < gbuy(w) {
                        let q = (w.demand / 1000 * 7).min(room(w)).min(m.money.max(0) * 1000 / out_sell.max(1)).max(0);
                        let cost = q * out_sell / 1000;
                        w.store += q;
                        m.money -= cost;
                        self.money.imports += cost;
                        self.stats.goods.out_import[g] += q;
                    }
                }
                let here = &self.markets[mi];
                let mid = here.goods[g].price;
                let mut best: Option<(i64, usize, i64)> = None;
                for nb in &here.neigh {
                    let o = &self.markets[nb.m as usize].goods[g];
                    if o.store <= 0 {
                        continue;
                    }
                    let cost = self.freight(nb.cost, mi);
                    let margin = mid - gsell(o) - cost;
                    if margin > 0 && best.is_none_or(|b| margin > b.0) {
                        best = Some((margin, nb.m as usize, cost));
                    }
                }
                let Some((_, src, cost)) = best else { continue };
                let price = gsell(&self.markets[src].goods[g]);
                let w = &self.markets[mi].goods[g];
                let q = (self.markets[src].goods[g].store / 4).min(w.demand / 1000 * 7).min(room(w)).min(self.markets[mi].money.max(0) * 1000 / (price + cost)).max(0);
                if q == 0 {
                    continue;
                }
                let (pay, freight) = (q * price / 1000, q * cost / 1000);
                let s = &mut self.markets[src];
                s.goods[g].store -= q;
                s.goods[g].sold_today += q;
                s.money += pay;
                let m = &mut self.markets[mi];
                m.goods[g].store += q;
                m.money -= pay + freight;
                self.money.freight += freight;
                self.stats.goods.moved[g] += q;
                self.goods_moves.push((day, src as u32, mi as u32, g as u8, q));
            }
        }
    }

    /// Goods held, for the yearly line: households' clothing and cookware,
    /// farms' tools, jars, wool and sheep, and the markets' stores by good
    /// (all in units).
    pub fn goods_report(&self) -> ([f64; 6], [f64; GOODS], [f64; GOODS]) {
        let mut held = [0i64; 6];
        for s in self.hh.values() {
            held[0] += s.goods.clothes;
            held[1] += s.goods.pots;
        }
        for f in self.farms.iter().filter(|f| f.hh != NONE) {
            held[2] += f.goods.tools;
            held[3] += f.goods.jars;
            held[4] += f.goods.wool;
            held[5] += f.goods.sheep * 1000;
        }
        let mut store = [0i64; GOODS];
        let mut prices: [Vec<(i64, i64)>; GOODS] = Default::default();
        for m in &self.markets {
            for g in 0..GOODS {
                store[g] += m.goods[g].store;
                prices[g].push((m.goods[g].price, m.people as i64));
            }
        }
        // Median price by people.
        let med = |v: &mut Vec<(i64, i64)>| {
            v.sort_unstable();
            let total: i64 = v.iter().map(|x| x.1).sum();
            let mut acc = 0;
            for &(p, n) in v.iter() {
                acc += n;
                if acc * 2 >= total {
                    return p as f64 / 1000.0;
                }
            }
            0.0
        };
        (held.map(|x| x as f64 / 1000.0), store.map(|x| x as f64 / 1000.0), std::array::from_fn(|g| med(&mut prices[g])))
    }
}

impl Grain {
    /// Debug: clothing held against the plain need by household kind, and
    /// how many households of each kind hold less than half.
    pub fn clothes_by_kind(&self) -> [(f64, usize, usize); 5] {
        let mut out = [(0.0, 0usize, 0usize); 5];
        let mut need = [0i64; 5];
        let mut held = [0i64; 5];
        for (id, i) in self.info.iter() {
            let Some(s) = self.hh.get(id) else { continue };
            if s.own_food {
                continue;
            }
            let k = s.kind as usize;
            need[k] += i.need_w as i64 * 100;
            held[k] += s.goods.clothes.min(i.need_w as i64 * 100);
            out[k].1 += 1;
            if s.goods.clothes * 2 < i.need_w as i64 * 100 {
                out[k].2 += 1;
            }
        }
        for k in 0..5 {
            out[k].0 = 100.0 * held[k] as f64 / need[k].max(1) as f64;
        }
        out
    }
}

impl Grain {
    /// Debug: money held by household kind (farms with their farm), and by
    /// the dealers, in denarii.
    pub fn money_by_kind(&self) -> ([f64; 5], f64) {
        let mut out = [0i64; 5];
        for s in self.hh.values() {
            out[s.kind as usize] += s.money + if s.farm != NONE { self.farms[s.farm as usize].money } else { 0 };
        }
        (out.map(|x| x as f64 / 1000.0), self.markets.iter().map(|m| m.money).sum::<i64>() as f64 / 1000.0)
    }
}

impl Grain {
    /// Craft households (workshops) in the box (world km). Read only.
    pub fn crafts_in(&self, min: (f64, f64), max: (f64, f64)) -> CraftsView {
        let mut v = CraftsView::default();
        for (&id, s) in self.hh.iter() {
            if s.goods.craft == 0 || !matches!(s.kind, WAGE | TRADER) {
                continue;
            }
            let (x, z) = self.settle.fine_centre_km(s.fine);
            if x < min.0 || x > max.0 || z < min.1 || z > max.1 {
                continue;
            }
            v.household.push(id as i64);
            v.craft.push(s.goods.craft);
            v.util.push(s.goods.util);
            v.fine.push(s.fine);
            v.at.push((x as f32, z as f32));
        }
        v
    }

    /// Every market's square (world km) and the store (units) and price
    /// (denarii per unit) of every good there, in market order
    /// (`Grain::markets`). Read only.
    pub fn market_goods(&self) -> Vec<((f32, f32), [(f32, f32); GOODS])> {
        self.markets
            .iter()
            .map(|m| {
                let (x, z) = self.settle.fine_centre_km(m.fine);
                ((x as f32, z as f32), m.goods.map(|w| (w.store as f32 / 1000.0, w.price as f32 / 1000.0)))
            })
            .collect()
    }

    /// Goods the dealers carried between markets lately, where either
    /// market lies in the box (world km). Read only.
    pub fn goods_moves_in(&self, min: (f64, f64), max: (f64, f64)) -> GoodsMovesView {
        let mut v = GoodsMovesView::default();
        let inside = |(x, z): (f64, f64)| x >= min.0 && x <= max.0 && z >= min.1 && z <= max.1;
        for &(day, from, to, g, q) in &self.goods_moves {
            let a = self.settle.fine_centre_km(self.markets[from as usize].fine);
            let b = self.settle.fine_centre_km(self.markets[to as usize].fine);
            if !inside(a) && !inside(b) {
                continue;
            }
            v.day.push(day);
            v.good.push(g);
            v.units.push(q as f32 / 1000.0);
            v.from.push((a.0 as f32, a.1 as f32));
            v.to.push((b.0 as f32, b.1 as f32));
        }
        v
    }

    /// Grain the dealers fetched between markets lately (S114), as
    /// `goods_moves_in` with `good` u8::MAX and `units` in kg. Read only.
    pub fn grain_moves_in(&self, min: (f64, f64), max: (f64, f64)) -> GoodsMovesView {
        let mut v = GoodsMovesView::default();
        let inside = |(x, z): (f64, f64)| x >= min.0 && x <= max.0 && z >= min.1 && z <= max.1;
        for &(day, from, to, kg) in &self.grain_moves {
            let a = self.settle.fine_centre_km(self.markets[from as usize].fine);
            let b = self.settle.fine_centre_km(self.markets[to as usize].fine);
            if !inside(a) && !inside(b) {
                continue;
            }
            v.day.push(day);
            v.good.push(u8::MAX);
            v.units.push(kg as f32);
            v.from.push((a.0 as f32, a.1 as f32));
            v.to.push((b.0 as f32, b.1 as f32));
        }
        v
    }
}
