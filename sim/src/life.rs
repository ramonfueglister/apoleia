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

/// Standard normal quantile (Acklam's rational approximation, relative
/// error below 1.2e-9) from a uniform in (0, 1); only + − × ÷, sqrt and our
/// `ln`, so the same bits on every platform.
pub fn normal(u: f64) -> f64 {
    const A: [f64; 6] = [-3.969683028665376e1, 2.209460984245205e2, -2.759285104469687e2, 1.383577518672690e2, -3.066479806614716e1, 2.506628277459239];
    const B: [f64; 5] = [-5.447609879822406e1, 1.615858368580409e2, -1.556989798598866e2, 6.680131188771972e1, -1.328068155288572e1];
    const C: [f64; 6] = [-7.784894002430293e-3, -3.223964580411365e-1, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783];
    const D: [f64; 4] = [7.784695709041462e-3, 3.224671290700398e-1, 2.445134137142996, 3.754408661907416];
    let u = u.clamp(1e-12, 1.0 - 1e-12);
    let tail = |q: f64| (((((C[0] * q + C[1]) * q + C[2]) * q + C[3]) * q + C[4]) * q + C[5]) / ((((D[0] * q + D[1]) * q + D[2]) * q + D[3]) * q + 1.0);
    if u < 0.02425 {
        tail((-2.0 * ln(u)).sqrt())
    } else if u > 1.0 - 0.02425 {
        -tail((-2.0 * ln(1.0 - u)).sqrt())
    } else {
        let q = u - 0.5;
        let r = q * q;
        (((((A[0] * r + A[1]) * r + A[2]) * r + A[3]) * r + A[4]) * r + A[5]) * q / (((((B[0] * r + B[1]) * r + B[2]) * r + B[3]) * r + B[4]) * r + 1.0)
    }
}

/// Intelligence (IQ scale, mean 100, SD 15 by definition of the scale).
/// The phenotype is genes plus environment with an age-dependent share of
/// the genes (heritability rises with age, the "Wilson effect"):
/// 0.41 at 9, 0.55 at 12, 0.66 at 17 (Haworth et al. 2010, about 11,000
/// twin pairs), levelling off at about 0.8 from 18–20 (Bouchard 2013);
/// linear between the points, 0.2 at birth. PLACEHOLDER: which estimate.
pub const IQ_H2: [(f64, f64); 5] = [(0.0, 0.2), (9.0, 0.41), (12.0, 0.55), (17.0, 0.66), (20.0, 0.8)];

pub fn iq_h2(age: f64) -> f64 {
    let i = IQ_H2.iter().rposition(|&(a, _)| a <= age).unwrap_or(0);
    match IQ_H2.get(i + 1) {
        Some(&(a1, h1)) => {
            let (a0, h0) = IQ_H2[i];
            h0 + (h1 - h0) * (age - a0) / (a1 - a0)
        }
        None => IQ_H2[i].1,
    }
}

/// IQ at `age` from the standardized genetic value `g` and environment `e`
/// (both N(0, 1)): 100 + 15 · (√h² · g + √(1 − h²) · e), so the spread is
/// 15 at every age and only the share of the genes grows.
pub fn iq(g: f64, e: f64, age: f64) -> f64 {
    let h2 = iq_h2(age);
    100.0 + 15.0 * (h2.sqrt() * g + (1.0 - h2).sqrt() * e)
}

/// Partners' IQ correlation the marriage search aims at: r = 0.44
/// (Horwitz et al. 2023, meta-analysis, 17 samples, 5,672 couples).
pub const IQ_MATE_R: f64 = 0.44;

/// Adult heritability (the last point of IQ_H2).
pub const IQ_H2_ADULT: f64 = IQ_H2[IQ_H2.len() - 1].1;

/// Genetic correlation of the partners in the people sim with the S82 gap
/// rule (people::IQ_MATE_GAP) (measured over 30 years, 61,332 marriages: 0.316). It is below
/// IQ_MATE_R · IQ_H2_ADULT = 0.35 because brides are young and their IQ
/// carries less of their genes (IQ_H2 at 15–20).
pub const IQ_MATE_RG: f64 = 0.32;

/// A child's standardized genetic value under additive inheritance: the
/// parents' mean plus Mendelian segregation. Partners with genetic
/// correlation rg add genetic variance each generation; with segregation
/// variance (1 − rg) / 2 the spread stays 1, which is the equilibrium of
/// the infinitesimal model under assortative mating (Crow and Felsenstein
/// 1968). The start population is taken to be in that equilibrium.
pub fn child_gene(father: f64, mother: f64, z: f64) -> f64 {
    child_gene_rg(father, mother, z, IQ_MATE_RG)
}

/// As `child_gene` for partners chosen on adult IQ with correlation r
/// (genetic correlation r · h²).
pub fn child_gene_r(father: f64, mother: f64, z: f64, r: f64) -> f64 {
    child_gene_rg(father, mother, z, r * IQ_H2_ADULT)
}

pub fn child_gene_rg(father: f64, mother: f64, z: f64, rg: f64) -> f64 {
    (father + mother) / 2.0 + ((1.0 - rg) / 2.0).sqrt() * z
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
    fn normal_quantiles() {
        for (u, z) in [(0.5, 0.0), (0.975, 1.959964), (0.025, -1.959964), (0.9772499, 2.0), (0.001, -3.090232)] {
            assert!((normal(u) - z).abs() < 1e-5, "{u}");
        }
    }

    fn draw(i: u64, s: u64) -> f64 {
        normal(unit(xxhash_rust::xxh3::xxh3_64(&(i * 16 + s).to_le_bytes())))
    }

    /// Pearson correlation.
    fn corr(x: &[f64], y: &[f64]) -> f64 {
        let n = x.len() as f64;
        let (mx, my) = (x.iter().sum::<f64>() / n, y.iter().sum::<f64>() / n);
        let (mut sxy, mut sxx, mut syy) = (0.0, 0.0, 0.0);
        for (a, b) in x.iter().zip(y) {
            sxy += (a - mx) * (b - my);
            sxx += (a - mx).powi(2);
            syy += (b - my).powi(2);
        }
        sxy / (sxx * syy).sqrt()
    }

    fn sd(x: &[f64]) -> f64 {
        let n = x.len() as f64;
        let m = x.iter().sum::<f64>() / n;
        (x.iter().map(|v| (v - m).powi(2)).sum::<f64>() / n).sqrt()
    }

    /// Adult IQ from random draws has mean 100 and SD 15 at every age.
    #[test]
    fn iq_scale_at_every_age() {
        for age in [0.0, 5.0, 9.0, 14.0, 17.0, 20.0, 50.0] {
            let v: Vec<f64> = (0..100_000).map(|i| iq(draw(i, 0), draw(i, 1), age)).collect();
            let m = v.iter().sum::<f64>() / v.len() as f64;
            assert!((m - 100.0).abs() < 0.2 && (sd(&v) - 15.0).abs() < 0.15, "{age}: {m} {}", sd(&v));
        }
    }

    /// Heritability by age is the table: 0.41 at 9, 0.55 at 12, 0.66 at
    /// 17, 0.8 from 20, rising in between.
    #[test]
    fn heritability_by_age() {
        assert!((iq_h2(9.0) - 0.41).abs() < 1e-12 && (iq_h2(12.0) - 0.55).abs() < 1e-12);
        assert!((iq_h2(17.0) - 0.66).abs() < 1e-12 && (iq_h2(60.0) - 0.8).abs() < 1e-12);
        let mut last = 0.0;
        for a in 0..80 {
            let h = iq_h2(a as f64);
            assert!(h >= last && (0.0..=1.0).contains(&h));
            last = h;
        }
    }

    /// Regression to the mean: the child's adult IQ on the mid-parent IQ
    /// has slope h² = 0.8 (random pairing here), and two parents of 130
    /// give children of 124 on average.
    #[test]
    fn regression_to_the_mean() {
        let n = 200_000u64;
        let (mut mid, mut kid) = (Vec::new(), Vec::new());
        for i in 0..n {
            let (gf, gm) = (draw(i, 0), draw(i, 1));
            mid.push((iq(gf, draw(i, 2), 40.0) + iq(gm, draw(i, 3), 40.0)) / 2.0);
            kid.push(iq(child_gene(gf, gm, draw(i, 4)), draw(i, 5), 40.0));
        }
        let slope = corr(&mid, &kid) * sd(&kid) / sd(&mid);
        assert!((slope - IQ_H2_ADULT).abs() < 0.02, "{slope}");
        // E[g | IQ 130] = √h² · 2; expected child IQ = 100 + 15 · √h² · that.
        let e = 100.0 + 15.0 * IQ_H2_ADULT.sqrt() * (IQ_H2_ADULT.sqrt() * 2.0);
        assert!((e - 124.0).abs() < 1e-9);
    }

    /// Ten generations with partners matched on adult IQ at r = 0.44: the
    /// genetic spread stays 1 and adult IQ stays 100 / 15, the partner
    /// correlation is the target. With the segregation of random mating
    /// instead, the spread would grow (control).
    #[test]
    fn assortative_mating_equilibrium() {
        let n = 60_000usize;
        let h = IQ_H2_ADULT.sqrt();
        // Matching on IQ plus noise of variance 1/r − 1 gives r.
        let noise = (1.0 / IQ_MATE_R - 1.0).sqrt();
        let run = |r_seg: f64| {
            let mut g: Vec<f64> = (0..2 * n as u64).map(|i| draw(i, 0)).collect();
            let mut last = (0.0, 0.0, 0.0);
            for gen in 0..10u64 {
                let p: Vec<f64> = (0..2 * n).map(|i| h * g[i] + (1.0 - h * h).sqrt() * draw(i as u64 + gen * 1_000_000, 1)).collect();
                let key = |i: usize| p[i] + noise * draw(i as u64 + gen * 1_000_000, 2);
                let mut men: Vec<usize> = (0..n).collect();
                let mut women: Vec<usize> = (n..2 * n).collect();
                men.sort_by(|&a, &b| key(a).total_cmp(&key(b)));
                women.sort_by(|&a, &b| key(a).total_cmp(&key(b)));
                let pm: Vec<f64> = men.iter().map(|&i| p[i]).collect();
                let pw: Vec<f64> = women.iter().map(|&i| p[i]).collect();
                // Two children per couple keep the size.
                let mut next = Vec::with_capacity(2 * n);
                for k in 0..2 {
                    for (j, (&m, &w)) in men.iter().zip(&women).enumerate() {
                        next.push(child_gene_r(g[m], g[w], draw((j + k * n) as u64 + gen * 1_000_000, 3), r_seg));
                    }
                }
                let iqs: Vec<f64> = p.iter().map(|x| 100.0 + 15.0 * x).collect();
                last = (corr(&pm, &pw), sd(&g), sd(&iqs));
                g = next;
            }
            (last, sd(&g))
        };
        let ((r, _, iq_sd), g_sd) = run(IQ_MATE_R);
        assert!((r - IQ_MATE_R).abs() < 0.02, "partner r {r}");
        assert!((g_sd - 1.0).abs() < 0.03, "genetic sd {g_sd}");
        assert!((iq_sd - 15.0).abs() < 0.4, "iq sd {iq_sd}");
        let (_, g_sd0) = run(0.0);
        assert!(g_sd0 > 1.1, "control: random-mating segregation under assortative mating {g_sd0}");
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
