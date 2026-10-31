//! S134 (Ramon, 31.10.2026, cards B1 to B4 and „Nach den
//! Ausgabengesetzen“ in the planning thread „Regierungseinflüsse nach
//! Vic3-Vorbild“; plan https://claude.ai/artifact/3iFcWf8MZ51uC2YyTt539v,
//! „5 Bauumfang“): the Staatsschuld. A law sets only rules: whether and how
//! much the state may borrow, for how long, what happens when the treasury
//! cannot pay, and the highest rate it may pay. The rate comes from the
//! households' bids, and the state's credit from what each creditor has
//! seen (North & Weingast, 1989; Stasavage, 2011).
//!
//! **Anleihe.** Once a month, when the treasury's cash less what falls
//! due is below half its reserve (S129), and the Schuldengrenze leaves
//! room, the state offers a bond for the gap to the whole reserve; it buys
//! Renten back only beyond the whole reserve (borrowing at 13 % to hold a
//! year's cash would not pay). Households with money beyond a
//! year's food (and a trader's trading money) bid part of it, each at the
//! least rate it wants: what it would earn otherwise, the land rate of
//! S112 for all (Ramon, 31.10.2026 17:15, card „12 % für alle, Höchstzins
//! nur privat“), a premium for the risk it sees (the state's interest bill against its
//! revenue; its own fading memory of losses, else the last Staatsbankrott
//! it heard of) and one for the term. The state takes the cheapest bids
//! until it has enough and pays all it takes the rate of the last bid
//! taken (uniform price). Nobody bids while the interest bill would reach
//! the state's whole revenue. The Zinsgesetz's cap does not bind the state
//! (same card: states were mostly not bound by their own caps; England
//! borrowed at 8 % from the Bank of England in 1694 under a cap of 6 %);
//! it will bind private credit once there is any. The Zinsverbot allows
//! the state only Renten.
//!
//! **Zahlen.** Interest once a year, the face at the end of the term. A
//! Rente has no term; with cash beyond the reserve the state buys Renten
//! back at their face, the dearest first. When the cash does not cover
//! what is due, the law decides: Geldschöpfung mints the rest (S95);
//! Staatsbankrott pays every creditor the same share, the rest is lost;
//! Umschuldung pays the same share and turns the rest into a new Rente at
//! a lower rate. Creditors lost less than half in the median over 300
//! restructurings since 1815 (Meyer et al., 2022); Castile in 1575 paid
//! its bankers 62 % and cut the Renten from 7.14 to 5 % (Drelichman &
//! Voth, 2007).
//!
//! **Ruf.** Each household remembers what it lost, fading (Malmendier &
//! Nagel, 2011: people weigh what they lived through); the memory halves
//! when the head of the household dies, a son founding his own household
//! takes half, and one who joins kin takes none. Larger haircuts cost
//! more and longer (Cruces & Trebesch, 2013).
//!
//! **Zwangsanleihe** (an edict, once): households whose money beyond the
//! year's food reaches FORCED_WAGE_YEARS of the day wage lend a share of
//! it at the edict's rate; what that rate falls short of their own counts
//! as a loss in their memory (Venice from the 12th century, Monte Vecchio
//! 1262 at 5 %).
//!
//! A bond belongs to its household and goes with its money (S97): to the
//! kin it joins; it lapses with those who leave the map; when the
//! household dies out, it falls with the estate to the state and the debt
//! is gone. At the start the law allows no debt: the game runs as before.

use super::*;
use std::collections::BTreeMap;

pub const DEBT_LAWS: usize = 4;
pub const LIMIT: usize = 0;
pub const TERM: usize = 1;
pub const SHORTFALL: usize = 2;
pub const USURY: usize = 3;
pub const DEBT_LAW_NAMES: [&str; DEBT_LAWS] = ["Schuldengrenze", "Laufzeit neuer Anleihen", "Wenn die Kasse nicht reicht", "Zinsgesetz"];
pub const LIMIT_CHOICES: [&str; 4] = ["keine Schuld", "bis eine Jahreseinnahme", "bis drei Jahreseinnahmen", "ohne Grenze"];
/// Per Schuldengrenze choice: the most the state owes, in years of its
/// revenue (i64::MAX without a limit).
const LIMIT_YEARS: [i64; 4] = [0, 1, 3, i64::MAX];
pub const TERM_CHOICES: [&str; 4] = ["Rente ohne Laufzeit", "5 Jahre", "10 Jahre", "30 Jahre"];
const TERM_YEARS: [i64; 4] = [0, 5, 10, 30];
pub const SHORTFALL_CHOICES: [&str; 3] = ["Geldschöpfung", "Staatsbankrott", "Umschuldung"];
pub const MINT: u8 = 0;
pub const BANKRUPTCY: u8 = 1;
pub const RESCHEDULE: u8 = 2;
/// The Zinsgesetz: free, Rome's centesima usura 12 %, the Reich's 5 % of
/// 1654 (caps for private credit to come), Zinsverbot.
pub const USURY_CHOICES: [&str; 4] = ["frei", "Höchstzins 12 %", "Höchstzins 5 %", "Zinsverbot"];
/// Zinsverbot: only Renten (the purchase of a Rente was a purchase, not
/// a loan), at any rate.
pub const USURY_BAN: u8 = 3;
/// The law at the start: no debt, Renten, Geldschöpfung, 12 % (as before
/// S134; Rome's cap around 300).
pub const DEFAULT_DEBT: [u8; DEBT_LAWS] = [0, 0, 0, 1];
/// A Rente's end: never.
pub const RENTE_END: i64 = i64::MAX;

/// What every bidder earns otherwise, basis points: the land rate of
/// S112 (pricing::INTEREST_PCT_YEAR, PLACEHOLDER 12 %).
const OWN_BP: i64 = pricing::INTEREST_PCT_YEAR * 100;
/// PLACEHOLDER: the term premium per year of term; a Rente counts as
/// RENTE_TERM_YEARS.
const TERM_BP_YEAR: i64 = 5;
const RENTE_TERM_YEARS: i64 = 20;
/// PLACEHOLDER: the risk premium per unit of the interest bill over the
/// revenue (a tenth of the revenue in interest: one per cent more).
const BURDEN_BP: i64 = 1000;
/// PLACEHOLDER: the premium per unit of wealth lost (memory over money
/// and bonds held, at most 1), and the memory's half-life; to calibrate
/// on Cruces & Trebesch (2013).
const LOSS_BP: i64 = 2000;
const MEMORY_HALF_DAYS: i64 = 5 * YEAR;
/// PLACEHOLDER: the share of its spare money a household bids, and the
/// least bid.
const BID_SHARE_PCT: i64 = 50;
const MIN_BID: i64 = 100_000;
/// PLACEHOLDER: an Umschuldung's new Rente pays this share of the old
/// rate (Castile 1575: 7.14 to 5 %).
const RESCHEDULE_PCT: i64 = 70;
/// PLACEHOLDER: a Zwangsanleihe falls on households with money beyond a
/// year's food of at least this many years of their market's day wage.
const FORCED_WAGE_YEARS: i64 = 10;
/// The day in the month (day mod 30) of the debt's monthly turn, after
/// the count (slices 11 to 17).
pub(super) const DEBT_SLICE: i64 = 20;

/// One bond: face (milli-denarii), rate (basis points), the day issued,
/// the day it is due (RENTE_END for a Rente), the day its interest is
/// paid to, and whether a Zwangsanleihe made it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Bond {
    pub amount: i64,
    pub rate: i64,
    pub start: i64,
    pub end: i64,
    pub paid: i64,
    pub forced: bool,
}

/// One creditor as the game shows it (`Grain::creditors`): household,
/// face held, mean rate by face (basis points), bonds.
#[derive(Clone, Copy, Debug)]
pub struct CreditorRow {
    pub household: u32,
    pub amount: i64,
    pub rate: i64,
    pub bonds: u32,
}

/// The state's debt and its creditors' memory (S134).
#[derive(Default)]
pub(super) struct DebtBook {
    /// Bonds by household.
    bonds: BTreeMap<u32, Vec<Bond>>,
    /// Face of all bonds.
    total: i64,
    /// Each household's loss (milli-denarii) and the day it was last
    /// written; it fades as it is read (`faded`).
    memory: BTreeMap<u32, (i64, i64)>,
    /// The head of each household with a memory, from the last count.
    heads: FxHashMap<u32, u32>,
    /// The last Staatsbankrott or Umschuldung: day and the share of what
    /// fell due that creditors lost, per mille.
    last_default: Option<(i64, i64)>,
    /// The revenue of the last full year and the mark it is counted from.
    revenue_mark: Option<(i64, i64)>,
    revenue_year: Option<i64>,
    /// A Zwangsanleihe ordered and not yet raised: share of the money,
    /// rate, per cent.
    forced: Option<(u8, u8)>,
}

/// What `amount` lost on `day` is worth on `today`: halved each
/// MEMORY_HALF_DAYS, straight between (no floats: replays are the same
/// on every machine).
fn faded(amount: i64, day: i64, today: i64) -> i64 {
    let d = (today - day).max(0);
    let k = d / MEMORY_HALF_DAYS;
    if k >= 62 {
        return 0;
    }
    let v = amount >> k;
    v - v * (d % MEMORY_HALF_DAYS) / (2 * MEMORY_HALF_DAYS)
}

/// The choices of debt law `law`.
pub fn debt_choices(law: usize) -> &'static [&'static str] {
    match law {
        LIMIT => &LIMIT_CHOICES,
        TERM => &TERM_CHOICES,
        SHORTFALL => &SHORTFALL_CHOICES,
        _ => &USURY_CHOICES,
    }
}

/// Interest on `amount` at `rate` (basis points) for `days`.
fn interest(amount: i64, rate: i64, days: i64) -> i64 {
    (amount as i128 * rate as i128 * days.max(0) as i128 / (YEAR as i128 * 10_000)) as i64
}

impl Grain {
    /// Sets one part of the debt law (`build::Command::Debt`); a law or
    /// choice out of range changes nothing.
    pub fn set_debt(&mut self, law: u8, choice: u8) {
        if (law as usize) < DEBT_LAWS && (choice as usize) < debt_choices(law as usize).len() {
            self.debt[law as usize] = choice;
        }
    }

    /// The debt law as the game shows it (rows like the spending laws).
    pub fn debt_rows(&self) -> Vec<SpendRow> {
        (0..DEBT_LAWS).map(|k| SpendRow { law: k as u8, name: DEBT_LAW_NAMES[k], choice: self.debt[k], choices: debt_choices(k) }).collect()
    }

    /// Orders a Zwangsanleihe (`build::Command::ForcedLoan`): `share` per
    /// cent of their spare money at `rate` per cent, raised at the next
    /// monthly turn within the Schuldengrenze; out of range (share 1 to
    /// 100, rate up to 100) it changes nothing.
    pub fn forced_loan(&mut self, share: u8, rate: u8) {
        if (1..=100).contains(&share) && rate <= 100 {
            self.debt_book.forced = Some((share, rate));
        }
    }

    /// The face of all bonds, milli-denarii.
    pub fn debt_total(&self) -> i64 {
        self.debt_book.total
    }

    /// The state's interest a year on all bonds, milli-denarii.
    pub fn interest_year(&self) -> i64 {
        self.debt_book.bonds.values().flatten().map(|b| interest(b.amount, b.rate, YEAR)).sum()
    }

    /// The revenue of the last full year (Verkauf aus Staatsspeichern,
    /// Pacht, Grundsteuer, Kopfsteuer, erbloser Nachlass), None in the
    /// first year.
    pub fn revenue_year(&self) -> Option<i64> {
        self.debt_book.revenue_year
    }

    /// The creditors, most held first (ties by household).
    pub fn creditors(&self) -> Vec<CreditorRow> {
        let mut v: Vec<CreditorRow> = self
            .debt_book
            .bonds
            .iter()
            .map(|(&id, bs)| {
                let amount: i64 = bs.iter().map(|b| b.amount).sum();
                let rate = (bs.iter().map(|b| b.amount as i128 * b.rate as i128).sum::<i128>() / (amount.max(1) as i128)) as i64;
                CreditorRow { household: id, amount, rate, bonds: bs.len() as u32 }
            })
            .collect();
        v.sort_by_key(|c| (Reverse(c.amount), c.household));
        v
    }

    /// The bonds household `id` holds.
    pub fn bonds_of(&self, id: u32) -> Vec<Bond> {
        self.debt_book.bonds.get(&id).cloned().unwrap_or_default()
    }

    /// Household `id`'s memory of losses today, milli-denarii.
    pub fn loss_memory(&self, id: u32) -> i64 {
        self.debt_book.memory.get(&id).map_or(0, |&(a, d)| faded(a, d, self.today))
    }

    fn remember(&mut self, id: u32, loss: i64) {
        if loss <= 0 {
            return;
        }
        let today = self.today;
        let e = self.debt_book.memory.entry(id).or_insert((0, today));
        *e = (faded(e.0, e.1, today) + loss, today);
    }

    fn revenue_sum(&self) -> i64 {
        let t = &self.treasury;
        t.tax + t.rent + t.land_tax + t.head_tax + t.estates
    }

    /// Money household `id` can spare: beyond a trader's trading money and
    /// a year's food at its market's buying price.
    fn spare_money(&self, id: u32, s: &HhState) -> i64 {
        let mk = self.info.get(&id).map_or(NONE, |i| self.cell_market[i.home as usize]);
        if s.own_food || mk == NONE {
            return 0;
        }
        let food = self.need_day(id) * YEAR * Self::buy_price(&self.markets[mk as usize]);
        self.money_of(id) - if s.kind == TRADER { TRADER_MONEY } else { 0 } - food
    }

    /// The least rate household `id` (wealth `wealth`) lends at for a term
    /// of `years` (0 a Rente), basis points: what it earns otherwise
    /// (OWN_BP), the risk it sees in an interest bill `bill` against `revenue`, and the
    /// term; None if it would not lend at all.
    fn least_rate(&self, id: u32, wealth: i64, bill: i64, revenue: i64, years: i64, hearsay: i64) -> Option<i64> {
        if revenue <= 0 || bill >= revenue {
            return None;
        }
        let burden = (bill as i128 * BURDEN_BP as i128 / revenue as i128) as i64;
        let lost = (self.loss_memory(id) as i128 * LOSS_BP as i128 / wealth.max(1) as i128).min(LOSS_BP as i128) as i64;
        let term = TERM_BP_YEAR * if years == 0 { RENTE_TERM_YEARS } else { years };
        Some(OWN_BP + burden + lost.max(hearsay) + term)
    }

    /// What the last default tells those who lost nothing, basis points.
    fn hearsay(&self) -> i64 {
        self.debt_book.last_default.map_or(0, |(d, share)| faded(share * LOSS_BP / 1000, d, self.today))
    }

    fn bond_event(&mut self, kind: u8, id: u32, amount: i64, rate: i64) {
        let (cell, fine) = (self.info.get(&id).map_or(NONE, |i| i.home), self.hh.get(&id).map_or(NONE, |s| s.fine));
        self.events.push(crate::events::Event { day: self.today, kind, household: id, pid: NONE, cell, to: NONE, fine, other: rate.clamp(0, u32::MAX as i64 - 1) as u32, amount: amount / 1000 });
    }

    /// The debt's monthly turn (DEBT_SLICE): revenue counted, then, while
    /// the law allows debt or bonds are out, a bond for what the treasury
    /// lacks, what falls due paid, Renten bought back from a surplus, and
    /// a Zwangsanleihe raised.
    pub(super) fn debt_month(&mut self, day: i64) {
        // the year's revenue, counted always (booking only)
        let sum = self.revenue_sum();
        match self.debt_book.revenue_mark {
            None => self.debt_book.revenue_mark = Some((day, sum)),
            Some((d, s)) if day - d >= YEAR => {
                self.debt_book.revenue_year = Some(sum - s);
                self.debt_book.revenue_mark = Some((day, sum));
            }
            _ => {}
        }
        if self.debt[LIMIT] == 0 && self.debt_book.bonds.is_empty() && self.debt_book.forced.is_none() {
            return;
        }
        let reserve = self.works_reserve(day);
        // planning thread 17:14 (the probe's to and fro): a bond only once
        // the cash falls below half the reserve, for the gap to the whole;
        // Renten bought back only beyond the whole reserve
        // what falls due: the year's interest in the last month of the
        // year, a bond's face (and interest to date) at its end
        let year_end = (day / MONTH) % 12 == 11;
        let mut due: Vec<(u32, usize, i64, i64)> = Vec::new();
        for (&id, bs) in &self.debt_book.bonds {
            for (k, b) in bs.iter().enumerate() {
                let ends = b.end <= day;
                if ends || year_end {
                    due.push((id, k, interest(b.amount, b.rate, day - b.paid), if ends { b.amount } else { 0 }));
                }
            }
        }
        let owed: i64 = due.iter().map(|d| d.2 + d.3).sum();
        if let Some(r) = reserve {
            if self.treasury.cash - owed < r / 2 {
                self.issue(day, r + owed - self.treasury.cash);
            }
        }
        self.pay_due(day, due, owed);
        if let Some(r) = reserve {
            let surplus = self.treasury.cash - r;
            if surplus > (r / 12).max(MIN_BID) {
                self.buy_back(day, surplus);
            }
        }
        if let Some((share, rate)) = self.debt_book.forced.take() {
            self.raise_forced(day, share, rate);
        }
        self.treasury.debt = self.debt_book.total;
        self.treasury.creditors = self.debt_book.bonds.len() as i64;
    }

    /// Room under the Schuldengrenze, None while the revenue is unknown.
    fn debt_room(&self) -> Option<i64> {
        let revenue = self.debt_book.revenue_year?;
        let years = LIMIT_YEARS[self.debt[LIMIT] as usize];
        let limit = if years == i64::MAX { i64::MAX } else { revenue.max(0).saturating_mul(years) };
        Some(limit.saturating_sub(self.debt_book.total).max(0))
    }

    fn term_years(&self) -> i64 {
        if self.debt[USURY] == USURY_BAN {
            0
        } else {
            TERM_YEARS[self.debt[TERM] as usize]
        }
    }

    fn add_bond(&mut self, id: u32, b: Bond) {
        self.debt_book.total += b.amount;
        self.debt_book.bonds.entry(id).or_default().push(b);
    }

    /// A bond for `need`: bids from the households, the cheapest taken.
    fn issue(&mut self, day: i64, need: i64) {
        let Some(room) = self.debt_room() else { return };
        let Some(revenue) = self.debt_book.revenue_year else { return };
        let amount = need.min(room);
        if amount < MIN_BID {
            return;
        }
        let years = self.term_years();
        let bill = self.interest_year();
        let hearsay = self.hearsay();
        let mut bids: Vec<(i64, u32, i64)> = Vec::new();
        for id in sorted_keys(&self.hh) {
            let s = self.hh[&id];
            let spare = self.spare_money(id, &s);
            if spare < 2 * MIN_BID {
                continue;
            }
            let offer = spare * BID_SHARE_PCT / 100;
            let wealth = self.money_of(id) + self.debt_book.bonds.get(&id).map_or(0, |v| v.iter().map(|b| b.amount).sum());
            // the bill with this bond, at what bidders earn otherwise
            let Some(rate) = self.least_rate(id, wealth, bill + interest(amount, OWN_BP, YEAR), revenue, years, hearsay) else { continue };
            bids.push((rate, id, offer));
        }
        bids.sort_unstable();
        let mut taken: Vec<(u32, i64)> = Vec::new();
        let (mut got, mut stop) = (0i64, 0i64);
        for &(rate, id, offer) in &bids {
            if got >= amount {
                break;
            }
            let take = offer.min(amount - got);
            taken.push((id, take));
            got += take;
            stop = rate;
        }
        if got == 0 {
            return;
        }
        let end = if years == 0 { RENTE_END } else { day + years * YEAR };
        for (id, take) in taken {
            self.pay(id, take);
            self.treasury.cash += take;
            self.add_bond(id, Bond { amount: take, rate: stop, start: day, end, paid: day, forced: false });
            self.bond_event(crate::events::BOND, id, take, stop);
        }
        self.treasury.debt_issued += got;
        self.treasury.debt_rate = stop;
        self.treasury.bond_issues += 1;
    }

    /// Pays what falls due (`due`: household, bond, interest, face;
    /// `owed` in all) from the cash, as far as it goes; then by the law.
    fn pay_due(&mut self, day: i64, due: Vec<(u32, usize, i64, i64)>, owed: i64) {
        if due.is_empty() {
            return;
        }
        let cash = self.treasury.cash.max(0);
        let law = self.debt[SHORTFALL];
        let full = cash >= owed || law == MINT;
        if !full {
            let lost = owed - cash;
            let kept = if law == RESCHEDULE { lost * RESCHEDULE_PCT / 100 } else { 0 };
            self.debt_book.last_default = Some((day, (lost - kept) * 1000 / owed.max(1)));
        }
        let mut gone: Vec<(u32, usize)> = Vec::new();
        for &(id, k, int, face) in &due {
            let all = int + face;
            let paid = if full { all } else { (all as i128 * cash as i128 / owed.max(1) as i128) as i64 };
            let out = paid.min(self.treasury.cash.max(0));
            self.treasury.cash -= out;
            self.money.minted += paid - out;
            self.treasury.interest_minted += (paid - out).min(int);
            self.earn(id, paid);
            let paid_int = paid.min(int);
            self.treasury.interest += paid_int;
            self.treasury.debt_repaid += paid - paid_int;
            let short = all - paid;
            if short > 0 {
                if law == RESCHEDULE {
                    let old = self.debt_book.bonds[&id][k].rate;
                    let rate = old * RESCHEDULE_PCT / 100;
                    self.add_bond(id, Bond { amount: short, rate, start: day, end: RENTE_END, paid: day, forced: false });
                    self.treasury.debt_rescheduled += short;
                    // the loss: the rate cut on what was not paid
                    self.remember(id, short * (100 - RESCHEDULE_PCT) / 100);
                    self.bond_event(crate::events::DEBT_RESCHEDULE, id, short, rate);
                } else {
                    self.treasury.debt_lost += short;
                    self.remember(id, short);
                    self.bond_event(crate::events::DEBT_DEFAULT, id, short, 0);
                }
            }
            let b = &mut self.debt_book.bonds.get_mut(&id).unwrap()[k];
            b.paid = day;
            if face > 0 {
                gone.push((id, k));
            }
        }
        // matured bonds leave the books (highest index first per household)
        gone.sort_unstable_by_key(|&(id, k)| (id, Reverse(k)));
        for (id, k) in gone {
            let bs = self.debt_book.bonds.get_mut(&id).unwrap();
            self.debt_book.total -= bs[k].amount;
            bs.remove(k);
            if bs.is_empty() {
                self.debt_book.bonds.remove(&id);
            }
        }
    }

    /// Buys Renten back at their face (and interest to date) with
    /// `surplus`, the dearest first.
    fn buy_back(&mut self, day: i64, mut surplus: i64) {
        let mut renten: Vec<(Reverse<i64>, u32, usize)> = Vec::new();
        for (&id, bs) in &self.debt_book.bonds {
            for (k, b) in bs.iter().enumerate() {
                if b.end == RENTE_END {
                    renten.push((Reverse(b.rate), id, k));
                }
            }
        }
        if renten.is_empty() {
            return;
        }
        renten.sort_unstable();
        let mut emptied: Vec<(u32, usize)> = Vec::new();
        for (_, id, k) in renten {
            if surplus <= 0 {
                break;
            }
            let b = self.debt_book.bonds[&id][k];
            let per = b.amount + interest(b.amount, b.rate, day - b.paid);
            let part = if per <= surplus { b.amount } else { (b.amount as i128 * surplus as i128 / per as i128) as i64 };
            if part <= 0 {
                break;
            }
            let int = interest(part, b.rate, day - b.paid);
            let pay = part + int;
            surplus -= pay;
            self.treasury.cash -= pay;
            self.earn(id, pay);
            self.treasury.interest += int;
            self.treasury.debt_bought += part;
            self.treasury.debt_repaid += part;
            self.debt_book.total -= part;
            let bm = &mut self.debt_book.bonds.get_mut(&id).unwrap()[k];
            bm.amount -= part;
            if bm.amount == 0 {
                emptied.push((id, k));
            }
        }
        emptied.sort_unstable_by_key(|&(id, k)| (id, Reverse(k)));
        for (id, k) in emptied {
            let bs = self.debt_book.bonds.get_mut(&id).unwrap();
            bs.remove(k);
            if bs.is_empty() {
                self.debt_book.bonds.remove(&id);
            }
        }
    }

    /// A Zwangsanleihe of `share` per cent at `rate` per cent, within the
    /// Schuldengrenze (all shares cut alike to fit).
    fn raise_forced(&mut self, day: i64, share: u8, rate: u8) {
        let Some(room) = self.debt_room() else { return };
        let revenue = self.debt_book.revenue_year.unwrap_or(0);
        let years = self.term_years();
        let bill = self.interest_year();
        let hearsay = self.hearsay();
        let mut lend: Vec<(u32, i64, Option<i64>)> = Vec::new();
        for id in sorted_keys(&self.hh) {
            let s = self.hh[&id];
            let Some(i) = self.info.get(&id) else { continue };
            let mk = self.cell_market[i.home as usize];
            if mk == NONE {
                continue;
            }
            let spare = self.spare_money(id, &s);
            if spare < FORCED_WAGE_YEARS * self.markets[mk as usize].wage_year.max(1) {
                continue;
            }
            let wealth = self.money_of(id) + self.debt_book.bonds.get(&id).map_or(0, |v| v.iter().map(|b| b.amount).sum());
            let own = self.least_rate(id, wealth, bill, revenue, years, hearsay);
            lend.push((id, spare * share as i64 / 100, own));
        }
        let total: i64 = lend.iter().map(|l| l.1).sum();
        if total <= 0 {
            return;
        }
        let fit = total.min(room);
        let rate = rate as i64 * 100;
        let end = if years == 0 { RENTE_END } else { day + years * YEAR };
        let mut raised = 0;
        for (id, want, own) in lend {
            let amount = (want as i128 * fit as i128 / total as i128) as i64;
            if amount <= 0 {
                continue;
            }
            self.pay(id, amount);
            self.treasury.cash += amount;
            raised += amount;
            self.add_bond(id, Bond { amount, rate, start: day, end, paid: day, forced: true });
            // the rate short of its own counts as lost: on a Rente the
            // value it loses, on a term what the gap costs over it
            // (never more than the Rente's); with no rate of its own
            // (it would not lend at all) the whole sum
            let loss = match own {
                Some(o) if o > rate => {
                    let rente = (amount as i128 * (o - rate) as i128 / o as i128) as i64;
                    if years == 0 { rente } else { interest(amount, o - rate, years * YEAR).min(rente) }
                }
                Some(_) => 0,
                None => amount,
            };
            self.remember(id, loss);
            self.bond_event(crate::events::FORCED_LOAN, id, amount, rate);
        }
        self.treasury.debt_issued += raised;
        self.treasury.debt_forced += raised;
    }

    /// A household is gone (S97): its bonds go with its money to the kin
    /// it joined (`heir`), lapse with those who left the map, or fall with
    /// the estate to the state, which owes them no more. Its memory goes
    /// with it.
    pub(super) fn debt_gone(&mut self, id: u32, heir: u32, left: bool) {
        self.debt_book.memory.remove(&id);
        self.debt_book.heads.remove(&id);
        let Some(bs) = self.debt_book.bonds.remove(&id) else { return };
        let face: i64 = bs.iter().map(|b| b.amount).sum();
        if heir != NONE {
            self.debt_book.bonds.entry(heir).or_default().extend(bs);
            return;
        }
        self.debt_book.total -= face;
        if left {
            self.treasury.debt_lapsed += face;
        } else {
            self.treasury.debt_escheated += face;
        }
    }

    /// After a count: a son who founded his own household (`log`: old,
    /// son) takes half his father's household's memory; a household whose
    /// head died keeps half (the head: the eldest man of 15 or more, else
    /// the eldest).
    pub(super) fn debt_count(&mut self, p: &People, log: &[(u32, u32)]) {
        if self.debt_book.memory.is_empty() {
            return;
        }
        for &(old, son) in log {
            let m = self.loss_memory(old);
            if m > 0 && son != old {
                self.debt_book.memory.insert(son, (m / 2, self.today));
            }
        }
        let ids: Vec<u32> = self.debt_book.memory.keys().copied().collect();
        let day = self.today;
        for id in ids {
            let Some(i) = self.info.get(&id) else { continue };
            let members = &self.members[i.at as usize..(i.at + i.size as u32) as usize];
            let mut head: Option<(bool, i32, u32)> = None;
            for &m in members {
                let Some(e) = p.alive_entity(m) else { continue };
                let born = p.world.get::<Born>(e).unwrap().0;
                let man = p.world.get::<Sex>(e).unwrap().0 == 1 && day - born as i64 >= 15 * YEAR;
                let key = (man, -born, m);
                if head.is_none_or(|h| (key.0, key.1, Reverse(key.2)) > (h.0, h.1, Reverse(h.2))) {
                    head = Some(key);
                }
            }
            let Some((_, _, now)) = head else { continue };
            if let Some(&was) = self.debt_book.heads.get(&id) {
                if was != now && p.alive_entity(was).is_none() {
                    let (a, d) = self.debt_book.memory[&id];
                    self.debt_book.memory.insert(id, (faded(a, d, day) / 2, day));
                }
            }
            self.debt_book.heads.insert(id, now);
        }
        self.debt_book.memory.retain(|_, v| v.0 > 0);
    }

    /// For the fingerprint: the bonds and the memory (nothing while there
    /// are none, so a game without debt keeps its fingerprint).
    pub(super) fn debt_bytes(&self, b: &mut Vec<u8>) {
        for (&id, bs) in &self.debt_book.bonds {
            for x in bs {
                for v in [id as i64, x.amount, x.rate, x.end, x.paid] {
                    b.extend_from_slice(&v.to_le_bytes());
                }
            }
        }
        for (&id, &(a, d)) in &self.debt_book.memory {
            for v in [id as i64, a, d] {
                b.extend_from_slice(&v.to_le_bytes());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_fades_by_half_lives() {
        assert_eq!(faded(1000, 0, 0), 1000);
        assert_eq!(faded(1000, 0, MEMORY_HALF_DAYS), 500);
        assert_eq!(faded(1000, 0, 2 * MEMORY_HALF_DAYS), 250);
        assert_eq!(faded(1000, 0, MEMORY_HALF_DAYS / 2), 750);
        assert_eq!(faded(1000, 0, 100 * MEMORY_HALF_DAYS), 0);
    }

    #[test]
    fn bonds_keep_the_books() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let mut g = Grain::new(&inp, &mut p);
        for _ in 0..40 {
            p.day();
            g.day(&mut p);
        }
        // the start law: no debt, the monthly turn changes nothing
        assert!(g.debt_book.bonds.is_empty());
        let day = g.today;
        g.set_debt(LIMIT as u8, 3);
        g.debt_book.revenue_year = Some(1_000_000_000_000);
        let cash = g.treasury.cash;
        g.issue(day, 50_000_000);
        let total = g.debt_total();
        assert!(total > 0 && total <= 50_000_000);
        assert_eq!(g.treasury.cash - cash, total);
        assert_eq!(g.money_unbooked(), 0);
        assert_eq!(g.debt_book.bonds.values().flatten().map(|b| b.amount).sum::<i64>(), total);
        // a Rente: the land rate, the term premium, a little for the bill
        assert!(g.treasury.debt_rate >= OWN_BP + TERM_BP_YEAR * RENTE_TERM_YEARS);
        assert!(g.debt_book.bonds.values().flatten().all(|b| b.end == RENTE_END && b.rate == g.treasury.debt_rate));
        // a year's interest with an empty treasury, Staatsbankrott: all
        // of it lost, no money moves, the creditors remember
        g.set_debt(SHORTFALL as u8, BANKRUPTCY);
        g.money.start -= g.treasury.cash;
        g.treasury.cash = 0;
        let held = g.money_held();
        let due: Vec<(u32, usize, i64, i64)> = g.debt_book.bonds.iter().flat_map(|(&id, bs)| bs.iter().enumerate().map(move |(k, b)| (id, k, interest(b.amount, b.rate, YEAR), 0))).collect();
        let owed: i64 = due.iter().map(|d| d.2).sum();
        let ids: Vec<u32> = due.iter().map(|d| d.0).collect();
        g.pay_due(day + YEAR, due, owed);
        assert_eq!(g.treasury.debt_lost, owed);
        assert_eq!(g.money_held(), held);
        assert_eq!(g.money_unbooked(), 0);
        assert_eq!(g.debt_book.last_default.map(|d| d.1), Some(1000));
        assert!(ids.iter().all(|&id| g.loss_memory(id) > 0));
        assert!(g.hearsay() > 0);
        // Geldschöpfung: paid in full, minted
        g.set_debt(SHORTFALL as u8, MINT);
        let minted = g.money.minted;
        let due: Vec<(u32, usize, i64, i64)> = g.debt_book.bonds.iter().flat_map(|(&id, bs)| bs.iter().enumerate().map(move |(k, b)| (id, k, 0, b.amount))).collect();
        g.pay_due(day + YEAR, due, total);
        assert_eq!(g.money.minted - minted, total);
        assert_eq!(g.debt_total(), 0);
        assert!(g.debt_book.bonds.is_empty());
        assert_eq!(g.money_unbooked(), 0);
        // a household gone without heirs: its bonds fall to the state
        g.add_bond(ids[0], Bond { amount: 1000, rate: 500, start: day, end: RENTE_END, paid: day, forced: false });
        g.debt_gone(ids[0], NONE, false);
        assert_eq!((g.debt_total(), g.treasury.debt_escheated), (0, 1000));
        assert_eq!(g.loss_memory(ids[0]), 0);
    }

    #[test]
    fn interest_is_by_the_day() {
        assert_eq!(interest(1_000_000, 500, YEAR), 50_000);
        assert_eq!(interest(1_000_000, 500, YEAR / 2), 25_000);
        assert_eq!(interest(1_000_000, 500, -5), 0);
    }
}
