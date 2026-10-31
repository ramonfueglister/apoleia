//! S131 Steuergesetz, Schritt 1 (Ramon, 31.10.2026: Steuern und Haushalt
//! zuerst; Zehnt, Grundsteuer und Kopfsteuer; wer nicht zahlt, kommt in
//! den Steuerrückstand, nach einem Jahr folgt die Pfändung, nach einem
//! weiteren die Zwangsversteigerung des Hofs). Plan:
//! https://claude.ai/artifact/12Sa2gxdKcWjYqJdMoSr8F, section 4b.
//!
//! A law changes only rules and money flows of real households: who pays
//! is set here, who bears the tax (Zahllast against Traglast) is left to
//! the economy (Kleven et al., 2016; Besley & Persson, 2014). Each tax has
//! six levels, as Victoria 3's tax levels; the player changes a level with
//! a command (`build::Command::Law`) that takes effect from the next due
//! date. The terms are the ones that carry from Rome to 1900 (Ramon,
//! 31.10.2026: no Roman-only words): Zehnt, Grundsteuer, Kopfsteuer,
//! Steuerrückstand, Pfändung, Zwangsversteigerung, Domäne.
//!
//! - Zehnt: in grain at the harvest, as before (S115), at the level's share
//!   of the net crop instead of a fixed tenth.
//! - Grundsteuer: denarii a year per hectare of the farm's own fields, the
//!   level's share of the usual net crop of a hectare at the farm's market
//!   at the usual buying price there. The farm that works the land pays it
//!   (the occupier, as under English rates); state land is the state's and
//!   pays none (leased state fields S116, the Lex Manciana S92, farms whose
//!   landlord is the state).
//! - Kopfsteuer: denarii a year per adult (15–60), the level's days of the
//!   usual day wage at the household's market.
//!
//! Due once a year: a farm household right after its harvest, every other
//! household on HEAD_DOY. What a household cannot pay from its money is
//! its Steuerrückstand; a farm sells grain for it (down to its food until
//! the next harvest and the seed, whatever the price: taxes in money drove
//! farms to the market, Hopkins, 1980), and every household pays it off
//! from its money at its monthly meal count before it buys goods (the
//! planner's default: tax before the food money of S130). Arrears a year
//! old at the next due date bring the Pfändung: the bailiff takes the
//! money and the grain beyond the food until the next harvest and the seed
//! (the planner's default), the grain at the dealers' buying price into the
//! state granary. Arrears two years old bring the Zwangsversteigerung of a
//! family farm: the land is worth its yield value, the rent a tenant pays
//! over the interest rate (Clark, 2002), but no more than clearing the same
//! land costs where free land is left at the market; the household of the
//! market with the highest bid it can pay from its money beyond a year's
//! food gets it at the second-highest bid, at least half the value (the
//! minimum bid of § 85a ZVG); the arrears go to the treasury and the rest
//! to the family, which stays on the farm as the buyer's tenant (the
//! planner's default). Without a bidder the farm falls to the state as a
//! Domäne and the family becomes the state's tenant. A household without a
//! family farm of its own (tenants, estates, the landless) loses only what
//! the Pfändung takes; what is left after two years is written off as
//! uncollectable. Values are PLACEHOLDERS (decision D3 of the plan).

use super::*;
use std::collections::BTreeMap;

pub const LAWS: usize = 3;
pub const TITHE: usize = 0;
pub const LAND: usize = 1;
pub const HEAD: usize = 2;
pub const LAW_NAMES: [&str; LAWS] = ["Zehnt", "Grundsteuer", "Kopfsteuer"];
pub const LAW_LEVELS: usize = 6;
pub const LEVEL_NAMES: [&str; LAW_LEVELS] = ["keine", "sehr niedrig", "niedrig", "mittel", "hoch", "sehr hoch"];
/// Per level: the Zehnt's share of the net crop, per cent (PLACEHOLDER;
/// the plan's range 5–30 %, the default 10 % as before S131).
pub const TITHE_PCT: [i64; LAW_LEVELS] = [0, 5, 10, 15, 20, 30];
/// Per level: the Grundsteuer's share of the usual net crop value of a
/// hectare a year, per cent (PLACEHOLDER).
pub const LAND_PCT: [i64; LAW_LEVELS] = [0, 5, 10, 15, 20, 30];
/// Per level: the Kopfsteuer per adult and year in days of the usual day
/// wage (PLACEHOLDER).
pub const HEAD_DAYS: [i64; LAW_LEVELS] = [0, 2, 5, 10, 15, 20];
/// The law at the start: the Zehnt at 10 %, no tax in money (as before S131).
pub const DEFAULT_LAW: [u8; LAWS] = [2, 0, 0];
pub const UNITS: [&str; LAWS] = ["% der Ernte", "% des üblichen Hektarertrags", "Taglöhne je Erwachsenen und Jahr"];
/// Day of the year the Kopfsteuer of households without a farm is due
/// (PLACEHOLDER: 1 January).
const HEAD_DOY: i64 = 0;
/// Minimum bid at the Zwangsversteigerung, per cent of the value (§ 85a
/// ZVG: half the value in the first auction).
const RESERVE_PCT: i64 = 50;
/// Age of the arrears at a due date that brings the Pfändung and the
/// Zwangsversteigerung (a year and two years, less a month for the farms
/// whose harvest ends a few days earlier than last year).
const SEIZE_AFTER: i64 = YEAR - MONTH;
const AUCTION_AFTER: i64 = 2 * YEAR - MONTH;

/// One household's Steuerrückstand: Grundsteuer and Kopfsteuer owed,
/// milli-denarii, and the day since when it owes.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct Arrears {
    pub land: i64,
    pub head: i64,
    pub since: i64,
}

impl Arrears {
    fn total(&self) -> i64 {
        self.land + self.head
    }
}

/// One law as the game shows it (`Grain::law_rows`): its level, the rate
/// of that level in `unit`, and what that is in milli-denarii (median over
/// the markets, per hectare or per adult and year; 0 for the Zehnt).
#[derive(Clone, Copy, Debug)]
pub struct LawRow {
    pub law: u8,
    pub name: &'static str,
    pub level: u8,
    pub rate: i64,
    pub unit: &'static str,
    pub denar: i64,
}

impl Grain {
    /// Sets one law's level (`build::Command::Law`); a law or level out of
    /// range changes nothing.
    pub fn set_law(&mut self, law: u8, level: u8) {
        if (law as usize) < LAWS && (level as usize) < LAW_LEVELS {
            self.law[law as usize] = level;
        }
    }

    /// The Zehnt's share of the net crop now, per cent.
    pub(super) fn tithe_pct(&self) -> i64 {
        TITHE_PCT[self.law[TITHE] as usize]
    }

    /// The laws as the game shows them.
    pub fn law_rows(&self) -> Vec<LawRow> {
        (0..LAWS)
            .map(|k| {
                let level = self.law[k] as usize;
                let (rate, denar) = match k {
                    TITHE => (TITHE_PCT[level], 0),
                    LAND => (LAND_PCT[level], self.tax_view.0 * LAND_PCT[level] / 100),
                    _ => (HEAD_DAYS[level], self.tax_view.1 * HEAD_DAYS[level]),
                };
                LawRow { law: k as u8, name: LAW_NAMES[k], level: level as u8, rate, unit: UNITS[k], denar }
            })
            .collect()
    }

    /// The usual buying price at a market over the year, milli-denarii.
    fn usual_bid(m: &Market) -> i64 {
        m.norm / 1000 * (100 - SPREAD_PCT) / 100
    }

    /// The Grundsteuer base of farm `f`: its own fields, m² (none on state
    /// land).
    fn land_base(&self, f: usize) -> i64 {
        let fm = &self.farms[f];
        let state_tenant = fm.kind == TENANT && (fm.landlord == NONE || !self.hh.contains_key(&fm.landlord));
        if fm.manciana || state_tenant {
            0
        } else {
            (fm.area - fm.state).max(0)
        }
    }

    /// The usual net crop value of a hectare a year at market `m` (the
    /// share under grain of a hectare at the market's usual yield, at the
    /// usual buying price), milli-denarii.
    fn ha_value(&self, m: &Market) -> i64 {
        m.yield_ha * self.crop_pct / 100 * Self::usual_bid(m)
    }

    /// The Grundsteuer of farm `f` for a year, milli-denarii.
    pub(super) fn land_due(&self, f: usize) -> i64 {
        let pct = LAND_PCT[self.law[LAND] as usize];
        if pct == 0 {
            return 0;
        }
        let m = &self.markets[self.farms[f].market as usize];
        self.land_base(f) * self.ha_value(m) / 10_000 * pct / 100
    }

    /// The Kopfsteuer of household `id` at market `mk` for a year.
    pub(super) fn head_due(&self, id: u32, mk: usize) -> i64 {
        let days = HEAD_DAYS[self.law[HEAD] as usize];
        let adults = self.info.get(&id).map_or(0, |i| i.adults as i64);
        adults * days * self.markets[mk].wage_year
    }

    /// Money taxes paid by household `id` (`cash`, milli-denarii, already
    /// taken from it) against its arrears, Grundsteuer first, into the
    /// treasury, counted at market `mk`.
    fn book_tax(&mut self, a: &mut Arrears, cash: i64, mk: usize) {
        let land = cash.min(a.land);
        a.land -= land;
        let head = (cash - land).min(a.head);
        a.head -= head;
        self.treasury.cash += cash;
        self.treasury.land_tax += land;
        self.treasury.head_tax += head;
        self.markets[mk].tax_paid += cash;
    }

    /// Household `id` pays what it owes from its money, as far as it goes;
    /// returns what it still owes.
    pub(super) fn pay_arrears(&mut self, id: u32, mk: usize) -> i64 {
        let Some(mut a) = self.arrears.get(&id).copied() else { return 0 };
        let cash = self.money_of(id).max(0).min(a.total());
        if cash > 0 {
            self.pay(id, cash);
            self.book_tax(&mut a, cash, mk);
        }
        self.keep_arrears(id, a)
    }

    fn keep_arrears(&mut self, id: u32, a: Arrears) -> i64 {
        if a.total() <= 0 {
            self.arrears.remove(&id);
            0
        } else {
            self.arrears.insert(id, a);
            a.total()
        }
    }

    /// A year's taxes come due for household `id`.
    fn assess(&mut self, id: u32, land: i64, head: i64, day: i64) {
        if land + head <= 0 {
            return;
        }
        let a = self.arrears.entry(id).or_insert(Arrears { land: 0, head: 0, since: day });
        if a.total() <= 0 {
            a.since = day;
        }
        a.land += land;
        a.head += head;
    }

    /// Arrears of household `id` that cannot be collected are written off.
    fn write_off(&mut self, id: u32) {
        if let Some(a) = self.arrears.remove(&id) {
            self.treasury.written_off += a.total();
        }
    }

    /// At a due date: old arrears of household `id` bring the Pfändung (a
    /// year) and then the Zwangsversteigerung of its family farm `farm` or
    /// the write-off (two years). `keep` is the grain the Pfändung leaves
    /// on the farm, kg.
    fn enforce(&mut self, id: u32, farm: Option<usize>, mk: usize, keep: i64, day: i64) {
        let Some(a) = self.arrears.get(&id).copied() else { return };
        let age = day - a.since;
        if age >= SEIZE_AFTER && self.seizure && a.total() > 0 {
            self.seize(id, farm, mk, keep);
        }
        if age < AUCTION_AFTER || !self.arrears.contains_key(&id) {
            return;
        }
        let own = farm.filter(|&f| {
            let fm = &self.farms[f];
            fm.kind == FAMILY && !fm.manciana && fm.hh == id && fm.area > fm.state
        });
        match own {
            Some(f) if self.auction => self.auction_farm(f, id, mk, day),
            _ => self.write_off(id),
        }
    }

    /// The Pfändung: the money of household `id` and the grain of its farm
    /// beyond `keep`, as far as the arrears go.
    fn seize(&mut self, id: u32, farm: Option<usize>, mk: usize, keep: i64) {
        let Some(mut a) = self.arrears.get(&id).copied() else { return };
        let cash = self.money_of(id).max(0).min(a.total());
        if cash > 0 {
            self.pay(id, cash);
            self.book_tax(&mut a, cash, mk);
        }
        let mut kg = 0;
        let mut worth = 0;
        if let Some(f) = farm {
            let price = Self::buy_price(&self.markets[mk]).max(1);
            let rest = a.total();
            kg = (self.farms[f].store - keep).max(0).min((rest + price - 1) / price);
            if kg > 0 {
                self.farms[f].store -= kg;
                self.markets[mk].horreum += kg;
                worth = (kg * price).min(rest);
                // the grain pays the arrears at its worth; its money comes
                // when the state granary sells it (`Treasury::tax`)
                let land = worth.min(a.land);
                a.land -= land;
                a.head -= worth - land;
            }
        }
        self.treasury.seized += cash + worth;
        self.treasury.seized_kg += kg;
        self.keep_arrears(id, a);
        if cash + worth > 0 {
            let (cell, fine) = self.info.get(&id).map_or((NONE, NONE), |i| (i.home, farm.map_or(NONE, |f| self.farms[f].fine)));
            self.events.push(crate::events::Event { day: self.today, kind: crate::events::SEIZURE, household: id, pid: NONE, cell, to: NONE, fine, other: NONE, amount: (cash + worth) / 1000 });
        }
    }

    /// The yield value of farm `f`'s own fields: the rent a tenant pays a
    /// year (RENT_PCT of the net crop at full work, at the usual buying
    /// price) over the interest rate (Clark, 2002), at most the cost of
    /// clearing as much land where the market still has free land.
    pub(super) fn land_value(&self, f: usize) -> i64 {
        let fm = &self.farms[f];
        let m = &self.markets[fm.market as usize];
        let base = (fm.area - fm.state).max(0);
        let net = if fm.area > 0 { ((fm.area - fm.poor) * fm.net_kg_ha + fm.poor * NET_POOR) / fm.area } else { fm.net_kg_ha };
        let rent = self.cropped(base) * net / 10_000 * RENT_PCT / 100 * Self::usual_bid(m);
        let value = rent * 100 / pricing::INTEREST_PCT_YEAR;
        if m.free_area >= base {
            value.min(base * sites::FIELD_CLEAR_DAYS_HA / 10_000 * m.wage_year)
        } else {
            value
        }
    }

    /// The Zwangsversteigerung of family farm `f` of household `id` for
    /// its arrears.
    fn auction_farm(&mut self, f: usize, id: u32, mk: usize, day: i64) {
        let value = self.land_value(f);
        let reserve = (value * RESERVE_PCT / 100).max(1);
        let bid_kg = Self::buy_price(&self.markets[mk]);
        // (highest bid, its household), second-highest bid; ties go to
        // the lowest household id (`market_hh` is sorted)
        let mut best = (0i64, NONE);
        let mut second = 0i64;
        for &b in &self.market_hh[mk] {
            if b == id || self.arrears.contains_key(&b) {
                continue;
            }
            let Some(s) = self.hh.get(&b) else { continue };
            if s.own_food {
                continue;
            }
            let food = self.need_day(b) * YEAR * bid_kg;
            let spare = self.money_of(b) - if s.kind == TRADER { TRADER_MONEY } else { 0 } - food;
            let max = spare.min(value);
            if max < reserve {
                continue;
            }
            if max > best.0 {
                second = best.0;
                best = (max, b);
            } else if max > second {
                second = max;
            }
        }
        let owed = self.arrears.get(&id).map_or(0, |a| a.total());
        let (fine, area) = (self.farms[f].fine, (self.farms[f].area - self.farms[f].state).max(0));
        let cell = self.info.get(&id).map_or(NONE, |i| i.home);
        let fm = &mut self.farms[f];
        fm.kind = TENANT;
        if best.1 == NONE {
            // the state takes the farm: a Domäne, the family its tenant
            fm.landlord = NONE;
            self.treasury.domains += 1;
            self.write_off(id);
            self.events.push(crate::events::Event { day, kind: crate::events::DOMAIN, household: id, pid: NONE, cell, to: NONE, fine, other: NONE, amount: owed / 1000 });
            return;
        }
        fm.landlord = best.1;
        let price = second.max(reserve);
        self.pay(best.1, price);
        let mut a = self.arrears.get(&id).copied().unwrap_or_default();
        let tax = price.min(a.total());
        self.book_tax(&mut a, tax, mk);
        self.keep_arrears(id, a);
        self.write_off(id);
        self.earn(id, price - tax);
        self.treasury.auctions += 1;
        self.treasury.auction_paid += price;
        self.treasury.auction_m2 += area;
        self.events.push(crate::events::Event { day, kind: crate::events::AUCTION, household: id, pid: NONE, cell, to: NONE, fine, other: best.1, amount: price / 1000 });
    }

    /// After farm `f`'s harvest: the year's Grundsteuer and Kopfsteuer of
    /// its household `id` come due, after the Pfändung or Zwangsversteigerung
    /// of old arrears. `keep` is the food until the next harvest and the
    /// seed, kg. Returns what the household still owes.
    pub(super) fn farm_taxes(&mut self, f: usize, id: u32, day: i64, keep: i64) -> i64 {
        if self.law[LAND] == 0 && self.law[HEAD] == 0 && self.arrears.is_empty() {
            return 0;
        }
        let mk = self.farms[f].market as usize;
        self.enforce(id, Some(f), mk, keep, day);
        if self.farms[f].hh != id {
            return 0;
        }
        let (land, head) = (self.land_due(f), self.head_due(id, mk));
        self.assess(id, land, head, day);
        self.pay_arrears(id, mk)
    }

    /// A farm that owes taxes sells grain for them: as much as pays them at
    /// the dealers' buying price, down to `keep`, whatever the price.
    pub(super) fn tax_sale(&mut self, f: usize, owed: i64, keep: i64) {
        let price = Self::buy_price(&self.markets[self.farms[f].market as usize]).max(1);
        let fm = &mut self.farms[f];
        let kg = ((owed + price - 1) / price).min((fm.store - keep).max(0));
        fm.to_sell = fm.to_sell.max(kg);
    }

    /// At the monthly meal count of household `id` (before it buys goods):
    /// it pays its arrears from its money; a farm that still owes and is at
    /// home sells grain for them.
    pub(super) fn tax_month(&mut self, p: &mut People, id: u32, mk: usize, day: i64) {
        if !self.arrears.contains_key(&id) {
            return;
        }
        let owed = self.pay_arrears(id, mk);
        let Some(s) = self.hh.get(&id).copied() else { return };
        if owed <= 0 || s.farm == NONE || s.busy {
            return;
        }
        let f = s.farm as usize;
        if self.farms[f].to_sell > 0 {
            return;
        }
        let keep = self.need_day(id) * (doy_until(day + 1, self.farms[f].harvest_doy) + 1) + self.seed_due(f, day);
        self.tax_sale(f, owed, keep);
        if self.farms[f].to_sell > 0 {
            self.start_carry(p, day, id, SELL);
        }
    }

    /// On HEAD_DOY: the Kopfsteuer of the households without a farm (farm
    /// households pay theirs after the harvest), after the Pfändung of old
    /// arrears; the arrears of households gone are written off.
    pub(super) fn taxes_day(&mut self, day: i64) {
        if doy(day) != HEAD_DOY || (self.law[HEAD] == 0 && self.arrears.is_empty()) {
            return;
        }
        let gone: Vec<u32> = self.arrears.keys().copied().filter(|id| !self.hh.contains_key(id)).collect();
        for id in gone {
            self.write_off(id);
        }
        for id in sorted_keys(&self.hh) {
            let s = self.hh[&id];
            if s.farm != NONE || s.own_food {
                continue;
            }
            let Some(i) = self.info.get(&id) else { continue };
            let mk = self.cell_market[i.home as usize];
            if mk == NONE {
                continue;
            }
            let mk = mk as usize;
            self.enforce(id, None, mk, 0, day);
            let head = self.head_due(id, mk);
            self.assess(id, 0, head, day);
            self.pay_arrears(id, mk);
        }
    }

    /// The arrears of households alive: total, milli-denarii, and how many
    /// households owe.
    pub(super) fn arrears_now(&self) -> (i64, i64) {
        self.arrears.iter().filter(|(id, _)| self.hh.contains_key(id)).fold((0, 0), |acc, (_, a)| (acc.0 + a.total(), acc.1 + 1))
    }

    /// For `law_rows`, once a month after the count: the median over the
    /// markets with people of the usual net crop value of a hectare and of
    /// the usual day wage, milli-denarii.
    pub(super) fn tax_view_update(&mut self) {
        let mut ha: Vec<i64> = self.markets.iter().filter(|m| m.people > 0 && m.yield_ha > 0).map(|m| self.ha_value(m)).collect();
        let mut wage: Vec<i64> = self.markets.iter().filter(|m| m.people > 0).map(|m| m.wage_year).collect();
        ha.sort_unstable();
        wage.sort_unstable();
        let mid = |v: &[i64]| if v.is_empty() { 0 } else { v[v.len() / 2] };
        self.tax_view = (mid(&ha), mid(&wage));
    }
}

impl Grain {
    /// One line on the taxes since the start for the yearly run
    /// (bin/grain.rs), denarii.
    pub fn tax_report(&self) -> String {
        let (t, (arrears, owing)) = (self.treasury, self.arrears_now());
        let den = |x: i64| x as f64 / 1e3;
        let levels: Vec<String> = (0..LAWS).map(|k| format!("{} {}", LAW_NAMES[k], LEVEL_NAMES[self.law[k] as usize])).collect();
        format!(
            "      taxes (S131): {} | tithe t {:.0} worth {:.0} | land tax {:.0} head tax {:.0} | seized {:.0} (grain t {:.0}) | auctions {} paid {:.0} for ha {:.0} | domains {} | written off {:.0} | arrears {:.0} of {} households\n",
            levels.join(", "),
            t.grain_kg as f64 / 1e3,
            den(t.tithe_worth),
            den(t.land_tax),
            den(t.head_tax),
            den(t.seized),
            t.seized_kg as f64 / 1e3,
            t.auctions,
            den(t.auction_paid),
            t.auction_m2 as f64 / 1e4,
            t.domains,
            den(t.written_off),
            den(arrears),
            owing
        )
    }
}

pub(super) type ArrearsMap = BTreeMap<u32, Arrears>;
