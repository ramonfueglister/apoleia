//! Demography building blocks for the people prototype (S62–S67): a model
//! life table, a marital fertility schedule, waiting-time sampling and an
//! event calendar.
//!
//! Method (continuous-time microsimulation as in Modgen/OpenM++): births and
//! deaths are not rolled every day for every person. Each person draws the
//! time of their next death (and, for married women, next birth) once from
//! a piecewise-constant hazard and puts it in a calendar. A day then only
//! touches the people whose event falls on it. When a state that changes the
//! hazard changes (health band, marriage, widowhood) the old event is
//! invalidated by bumping a generation counter and a new one is drawn; the
//! hazards are memoryless, so redrawing from the current age is exact.
//!
//! Determinism: draws come from hashes, and `ln` uses only + − × ÷ and the
//! exponent bits (no libm), so a draw gives the same day on every platform.

/// Days per simulated year (12 months of 30 days, as in the prototype).
pub const YEAR: i64 = 360;

/// Start of each age interval in years (Coale–Demeny layout: 0, 1, 5, 10 … 95).
pub const AGES: [f64; 21] = [
    0.0, 1.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0,
    90.0, 95.0,
];

/// Coale–Demeny Model West, level 3, as a constant yearly hazard per age
/// interval (−ln(1 − nqx)/n; open interval 95+ as l95/T95). Female e0 = 25.0,
/// male e0 = 22.9, q0 = 0.306 / 0.352: the table Frier uses for the Roman
/// Empire. Computed with the demogR `cdmltw` coefficients (Coale, Demeny and
/// Vaughan 1983, with Oeppen's 2018 corrections) by
/// docs/kit2/run-people/west3.py.
pub const MU_F: [f64; 21] = [
    0.36465, 0.06078, 0.0125, 0.00971, 0.0127, 0.01594, 0.01791, 0.02031, 0.02228, 0.02382, 0.02549, 0.03318,
    0.04243, 0.06335, 0.08565, 0.12747, 0.18734, 0.26548, 0.40051, 0.60421, 0.81049,
];
pub const MU_M: [f64; 21] = [
    0.43346, 0.06043, 0.01158, 0.00825, 0.01124, 0.01613, 0.01815, 0.02111, 0.02484, 0.03009, 0.0348, 0.04414,
    0.05369, 0.07394, 0.09953, 0.14024, 0.20965, 0.28734, 0.42646, 0.63294, 0.83692,
];

/// Age intervals of the fertility schedule (15–19 … 45–49, then none).
pub const FERT_AGES: [f64; 8] = [15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0];
/// Births per married woman and year: the Coale–Trussell natural fertility
/// shape n(a) scaled so that 20–24 gives 0.343, the marital fertility peak
/// in the Roman Egyptian census returns (Bagnall and Frier 1994). Proposal,
/// to be checked against the book.
pub const FERT: [f64; 8] = [0.307, 0.343, 0.321, 0.295, 0.239, 0.125, 0.018, 0.0];

/// Natural log for x > 0 with only + − × ÷ and the exponent bits.
pub fn ln(x: f64) -> f64 {
    let bits = x.to_bits();
    let e = ((bits >> 52) & 0x7ff) as i64 - 1023;
    let m = f64::from_bits((bits & ((1u64 << 52) - 1)) | (1023u64 << 52));
    let s = (m - 1.0) / (m + 1.0);
    let s2 = s * s;
    let mut term = s;
    let mut sum = 0.0;
    let mut k = 1.0;
    // s ≤ 1/3, so 20 terms are far below f64 precision.
    for _ in 0..20 {
        sum += term / k;
        term *= s2;
        k += 2.0;
    }
    e as f64 * std::f64::consts::LN_2 + 2.0 * sum
}

/// e^(−x) for 0 ≤ x ≤ 2 by Taylor series (no libm, same bits everywhere).
pub fn exp_neg(x: f64) -> f64 {
    let (mut term, mut sum) = (1.0, 1.0);
    for k in 1..40 {
        term *= -x / k as f64;
        sum += term;
    }
    sum
}

/// A uniform draw in (0, 1] from 53 bits of a hash.
pub fn unit(h: u64) -> f64 {
    ((h >> 11) + 1) as f64 / (1u64 << 53) as f64
}

/// Years until the next event under a piecewise-constant yearly hazard
/// (`rate[i]` from `ages[i]`, the last interval open-ended) times `mult`,
/// for someone aged `age` years, from one uniform draw (inverse of the
/// cumulative hazard). None if the hazard is zero from there on.
pub fn wait(ages: &[f64], rate: &[f64], age: f64, mult: f64, h: u64) -> Option<f64> {
    let mut need = -ln(unit(h));
    let mut i = ages.iter().rposition(|&a| a <= age)?;
    let mut t = age;
    loop {
        let r = rate[i] * mult;
        let end = ages.get(i + 1).copied().unwrap_or(f64::INFINITY);
        if r > 0.0 {
            let have = r * (end - t);
            if need <= have {
                return Some(t + need / r - age);
            }
            need -= have;
        }
        if end.is_infinite() {
            return None;
        }
        t = end;
        i += 1;
    }
}

/// Age in years (rounded down to the interval) where the stable population
/// of a life table puts quantile `u`: used to give the start population a
/// plausible age structure (stationary population, growth 0).
pub fn stable_age(mu: &[f64], u: f64) -> f64 {
    // Person-years lived in each year of age 0..100 (fine enough for a start).
    let mut l = 1.0;
    let mut lived = [0.0f64; 100];
    for (a, slot) in lived.iter_mut().enumerate() {
        let i = AGES.iter().rposition(|&x| x <= a as f64).unwrap();
        let s = exp_neg(mu[i]);
        *slot = l * (1.0 + s) / 2.0;
        l *= s;
    }
    let total: f64 = lived.iter().sum();
    let mut acc = 0.0;
    for (a, &v) in lived.iter().enumerate() {
        acc += v / total;
        if u <= acc {
            return a as f64 + (acc - u) / (v / total);
        }
    }
    99.0
}

/// Event kinds.
pub const DEATH: u8 = 0;
pub const BIRTH: u8 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Ev {
    pub kind: u8,
    pub pid: u32,
    /// Generation of the person's schedule for this kind when the event was
    /// drawn; a mismatch means it was replaced.
    pub gen: u16,
}

/// Two-level timing wheel (Varghese and Lauck 1987): one bucket per day of
/// the current year and one per later year. Push and pop are O(1); at a new
/// year that year's bucket is spread over the days.
pub struct Calendar {
    year0: i64,
    days: Vec<Vec<(i64, Ev)>>,
    years: std::collections::VecDeque<Vec<(i64, Ev)>>,
    pub len: usize,
}

impl Calendar {
    pub fn new(today: i64) -> Calendar {
        Calendar {
            year0: today.div_euclid(YEAR) * YEAR,
            days: (0..YEAR).map(|_| Vec::new()).collect(),
            years: Default::default(),
            len: 0,
        }
    }

    pub fn push(&mut self, day: i64, ev: Ev) {
        let d = day.max(self.year0);
        self.len += 1;
        let off = d - self.year0;
        if off < YEAR {
            self.days[off as usize].push((d, ev));
        } else {
            let y = (off / YEAR - 1) as usize;
            while self.years.len() <= y {
                self.years.push_back(Vec::new());
            }
            self.years[y].push((d, ev));
        }
    }

    /// All events of `day` (call once per day, days in order), sorted so
    /// the result does not depend on push order.
    pub fn take(&mut self, day: i64) -> Vec<Ev> {
        while day >= self.year0 + YEAR {
            self.year0 += YEAR;
            let next = self.years.pop_front().unwrap_or_default();
            for (d, ev) in next {
                self.days[(d - self.year0) as usize].push((d, ev));
            }
        }
        let mut out: Vec<Ev> = std::mem::take(&mut self.days[(day - self.year0) as usize])
            .into_iter()
            .map(|(_, e)| e)
            .collect();
        self.len -= out.len();
        out.sort_unstable();
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ln_matches() {
        for x in [1e-9, 0.001, 0.37, 1.0, 2.5, 1234.5] {
            assert!((ln(x) - x.ln()).abs() < 1e-12, "{x}");
        }
    }

    /// Life expectancy from many draws matches the table (25.0 / 22.9).
    #[test]
    fn e0_from_draws() {
        for (mu, e0) in [(&MU_F, 25.03), (&MU_M, 22.89)] {
            let n = 200_000u64;
            let s: f64 = (0..n)
                .map(|i| wait(&AGES, mu, 0.0, 1.0, xxhash_rust::xxh3::xxh3_64(&i.to_le_bytes())).unwrap())
                .sum();
            assert!((s / n as f64 - e0).abs() < 0.2, "{}", s / n as f64);
        }
    }

    #[test]
    fn calendar_order() {
        let mut c = Calendar::new(0);
        c.push(700, Ev { kind: 0, pid: 2, gen: 0 });
        c.push(700, Ev { kind: 0, pid: 1, gen: 0 });
        c.push(5, Ev { kind: 1, pid: 9, gen: 0 });
        assert_eq!(c.take(5).len(), 1);
        for d in 6..700 {
            assert!(c.take(d).is_empty());
        }
        let v = c.take(700);
        assert_eq!(v.iter().map(|e| e.pid).collect::<Vec<_>>(), vec![1, 2]);
        assert_eq!(c.len, 0);
    }
}
