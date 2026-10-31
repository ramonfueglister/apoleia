//! S133 (Ramon, 31.10.2026, cards A1 and A2 in the planning thread
//! „Regierungseinflüsse nach Vic3-Vorbild“; plan
//! https://claude.ai/artifact/5gxoCKStw7cF3PVYMAiZMA, „Bauumfang“): the
//! state's spending laws. A law changes rules and money flows; what they
//! do comes out of the simulation, as with the taxes (S131).
//!
//! **Vorratshaltung** (keine / bis 1 Monat / bis 3 Monate / bis 1 Jahr):
//! once a week, with the granaries' sales, a market's state granary buys
//! grain from the dealers with the treasury's cash beyond its reserve
//! (S129), by the same rule as every private storer (S123): only while
//! what it pays is below the price at which holding pays this season
//! (the expected price, less interest and spoilage, less the spread), up
//! to the law's months of the market's yearly sales (S125) in the
//! granary. It sells as before (S115, S126). State stockholding smooths
//! the price peaks and crowds out private stocks; the mean price moves
//! little (Miranda & Helmberger, 1988).
//!
//! **Armenpflege** (keine / Notstandsarbeit / Spende an Bedürftige):
//! Notstandsarbeit hires the households that lack the money for a month's
//! food first for the public works (S129); only those in real need take
//! such work, so it reaches them (Besley & Coate, 1992). Spende an
//! Bedürftige gives a household that is short of food at its meal and
//! cannot pay for what it lacks the rest of its month's food from the
//! state granary of its market, as far as the granary goes. At the start
//! both laws are „keine“, as before (S72: no corn dole for Rome).

use super::*;

pub const SPEND_LAWS: usize = 2;
pub const STOCK: usize = 0;
pub const RELIEF: usize = 1;
pub const SPEND_LAW_NAMES: [&str; SPEND_LAWS] = ["Vorratshaltung", "Armenpflege"];
pub const STOCK_CHOICES: [&str; 4] = ["keine", "bis 1 Monat", "bis 3 Monate", "bis 1 Jahr"];
/// Per Vorratshaltung choice: the most the state granary of a market buys
/// up to, in days of the market's sales.
pub const STOCK_DAYS: [i64; 4] = [0, 30, 90, 360];
pub const RELIEF_CHOICES: [&str; 3] = ["keine", "Notstandsarbeit", "Spende an Bedürftige"];
pub const RELIEF_WORK: u8 = 1;
pub const RELIEF_DOLE: u8 = 2;
/// The laws at the start: none (as before S133).
pub const DEFAULT_SPEND: [u8; SPEND_LAWS] = [0, 0];
/// PLACEHOLDER: a market's state granary buys at most this many days of
/// the market's sales a week.
const STOCK_WEEK_DAYS: i64 = 7;

/// The choices of spending law `law`.
pub fn spend_choices(law: usize) -> &'static [&'static str] {
    match law {
        STOCK => &STOCK_CHOICES,
        _ => &RELIEF_CHOICES,
    }
}

/// One spending law as the game shows it (`Grain::spend_rows`).
#[derive(Clone, Copy, Debug)]
pub struct SpendRow {
    pub law: u8,
    pub name: &'static str,
    pub choice: u8,
    pub choices: &'static [&'static str],
}

impl Grain {
    /// Sets one spending law (`build::Command::Spend`); a law or choice
    /// out of range changes nothing.
    pub fn set_spend(&mut self, law: u8, choice: u8) {
        if (law as usize) < SPEND_LAWS && (choice as usize) < spend_choices(law as usize).len() {
            self.spend[law as usize] = choice;
        }
    }

    /// The spending laws as the game shows them.
    pub fn spend_rows(&self) -> Vec<SpendRow> {
        (0..SPEND_LAWS).map(|k| SpendRow { law: k as u8, name: SPEND_LAW_NAMES[k], choice: self.spend[k], choices: spend_choices(k) }).collect()
    }

    /// Vorratshaltung at market `mi` (with its granary's weekly sale):
    /// buys from the dealers while holding pays, with the treasury's cash
    /// beyond `reserve` (none in the first year, as the public works).
    pub(super) fn stockpile(&mut self, mi: usize, reserve: Option<i64>) {
        let days = STOCK_DAYS[self.spend[STOCK] as usize];
        let Some(reserve) = reserve else { return };
        if days == 0 {
            return;
        }
        let m = &self.markets[mi];
        let per_day = m.demand / 1000;
        let price = Self::sell_price(m).max(1);
        if m.horreum >= per_day * days || price * 100 >= self.hold_price(m) * (100 - SPREAD_PCT) {
            return;
        }
        let spare = (self.treasury.cash - reserve).max(0);
        let kg = (per_day * days - m.horreum).min(per_day * STOCK_WEEK_DAYS).min(m.store.max(0)).min(spare / price);
        if kg <= 0 {
            return;
        }
        let m = &mut self.markets[mi];
        m.store -= kg;
        m.horreum += kg;
        m.money += kg * price;
        self.treasury.cash -= kg * price;
        self.treasury.stock_paid += kg * price;
        self.treasury.stock_kg += kg;
        self.stats.stock_kg += kg;
    }

    /// Armenpflege: household `id` lacks the money for a month's food at
    /// `food` (milli-denarii per kg) beyond the grain it has.
    pub(super) fn needy(&self, id: u32, food: i64) -> bool {
        let Some(s) = self.hh.get(&id) else { return false };
        let have = if s.farm != NONE { self.farms[s.farm as usize].store } else { s.pantry };
        have.max(0) + self.money_of(id).max(0) / food.max(1) < self.need_day(id) * MONTH
    }

    /// Spende an Bedürftige: what household `s` (at market `mk`), short
    /// `short` kg of its month's food, gets from the state granary if it
    /// cannot pay for it, kg.
    pub(super) fn dole(&mut self, s: &HhState, mk: u32, short: i64) -> i64 {
        if self.spend[RELIEF] != RELIEF_DOLE || short <= 0 || mk == NONE {
            return 0;
        }
        let money = if s.farm != NONE { self.farms[s.farm as usize].money } else { s.money };
        let m = &mut self.markets[mk as usize];
        if money >= short * Self::sell_price(m) {
            return 0;
        }
        let kg = short.min(m.horreum).max(0);
        m.horreum -= kg;
        self.treasury.dole_kg += kg;
        self.treasury.dole_worth += kg * Self::buy_price(&self.markets[mk as usize]);
        self.stats.dole_kg += kg;
        kg
    }
}
