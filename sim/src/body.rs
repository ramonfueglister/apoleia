//! Body weight as the measure of health (S84, replaces the 0–1000 health
//! of S64/S65): how hunger changes a person's weight, how weight changes
//! the death risk of the life table, and how food changes fertility.
//! Pure functions; crate::people keeps the weight per person.
//!
//! Weight is kept in ‰ of the person's normal weight: for adults the
//! weight at BMI_NORMAL, for children the usual weight for their age.
//!
//! Sources:
//! - Weight change: Hall et al. 2011, "Quantification of the effect of
//!   energy imbalance on bodyweight", The Lancet 378: every lasting
//!   100 kJ per day below need ends in about 1 kg less, half of it after
//!   about a year.
//! - Need per kg: FAO/WHO/UNU 2004, "Human energy requirements" (5.4.1):
//!   adults at a moderately active life 42–47 kcal per kg and day.
//! - Death risk of adults by BMI: Global BMI Mortality Collaboration 2016,
//!   The Lancet 388 (189 studies, 3.95 million never-smokers).
//! - Limit of survival: Henry 2001, "The biology of human starvation",
//!   Nutrition Bulletin 26: 205–211 (after James et al. 1988): men at about
//!   BMI 13, women about 11.
//! - Children under 5: Pelletier, "Potentiating effects of malnutrition on
//!   child mortality" (UNU Food and Nutrition Bulletin; method Pelletier
//!   et al. 1994, J Nutr 124: 2106–2122).
//! - Fertility: Stein and Susser 1975, "Fertility, fecundity, famine",
//!   Human Biology 47 (Dutch famine 1944/45: births follow the ration
//!   below a threshold, r = 0.92), and Cramer and Lumey 2009 (births per
//!   day conceived in the famine 26.4 against 38.1 before, −31 %).

/// BMI of the normal weight (1000 ‰). PLACEHOLDER: Roman bodies are known
/// by height, not weight; 21 is the median BMI FAO/WHO/UNU 2004 use for
/// the needs of adults.
pub const BMI_NORMAL: f64 = 21.0;

/// Energy need per kg of normal weight and day, kJ: 44 kcal (FAO/WHO/UNU
/// 2004, adults 42–47 at PAL 1.75–1.85). PLACEHOLDER for children (their
/// need per kg is higher).
pub const NEED_KJ_PER_KG: f64 = 184.0;

/// Lasting deficit per day that costs one kg in the end (Hall et al. 2011).
pub const HALL_KJ_PER_KG: f64 = 100.0;

/// Share of the way to the target weight gone in a month: half in a year
/// (Hall et al. 2011), 1 − 2^(−1/12).
pub const MONTH_STEP: f64 = 0.056_125_687_3;

/// Death risk multipliers by BMI from the lower bound of each band (Global
/// BMI Mortality Collaboration 2016, never-smokers, reference 20–25).
pub const BMI_RISK: [(f64, f64); 9] = [
    (15.0, 1.51),
    (18.5, 1.13),
    (20.0, 1.00),
    (25.0, 1.07),
    (27.5, 1.20),
    (30.0, 1.45),
    (35.0, 1.94),
    (40.0, 2.76),
    (60.0, 2.76),
];

/// BMI at which a woman and a man die of starvation (Henry 2001).
pub const LIMIT_BMI: [f64; 2] = [11.0, 13.0];

/// Death risk multipliers of children under 5 by weight for age, ‰ of the
/// usual weight, from the lower bound (Pelletier: below 60 % severe 8.4,
/// 60–69 % moderate 4.6, 70–79 % mild 2.4, from 80 % 1).
pub const CHILD_RISK: [(u16, f64); 4] = [(0, 8.4), (600, 4.6), (700, 2.4), (800, 1.0)];

/// Children under this age use CHILD_RISK (Pelletier: 6–59 months).
pub const CHILD_AGE: f64 = 5.0;

/// Fertility: food share of the household (‰ of need) at and above which
/// births are not affected. PLACEHOLDER: Stein and Susser 1975 found such a
/// threshold, its value is in the full paper (not at hand); 650 ‰ is about
/// 1,500 of 2,300 kcal.
pub const FERT_FULL: u16 = 650;

/// Fertility at a food share of 300 ‰ (rations of about 500–900 kcal in the
/// Dutch famine): 0.69 (Cramer and Lumey 2009, −31 %). Linear in between and
/// below (Stein and Susser: births follow the ration), never below 0.
pub const FERT_LOW: (u16, f64) = (300, 0.69);

/// Target weight (‰) of someone whose household gets `share` of its need
/// (0–1): normal weight less deficit / HALL_KJ_PER_KG kg (Hall et al. 2011),
/// with the deficit (1 − share) × NEED_KJ_PER_KG per kg of normal weight.
pub fn target(share: f64) -> f64 {
    let s = share.clamp(0.0, 1.0);
    (1000.0 * (1.0 - (1.0 - s) * NEED_KJ_PER_KG / HALL_KJ_PER_KG)).max(0.0)
}

/// Weight (‰) after a month on `share` of the need.
pub fn month(weight: u16, share: f64) -> u16 {
    let w = weight as f64;
    (w + (target(share) - w) * MONTH_STEP).round().clamp(0.0, 1000.0) as u16
}

/// BMI of an adult (or child of 5 and more, PLACEHOLDER: no source for
/// 5–19 found) at `weight` ‰.
pub fn bmi(weight: u16) -> f64 {
    BMI_NORMAL * weight as f64 / 1000.0
}

/// Multiplier on the death hazard of the life table for someone of `age`
/// years and `sex` (0 woman, 1 man) at `weight` ‰, whose base hazard per
/// year is `mu`. Below BMI 15 the yearly death probability rises linearly
/// from that at ×1.51 to 1 at the limit of survival (Ramon's choice of the
/// proposal; a setting, not a measurement); at the limit death is certain
/// (a multiplier of 1e9).
pub fn death_mult(weight: u16, age: f64, sex: u8, mu: f64) -> f64 {
    if age < CHILD_AGE {
        return CHILD_RISK.iter().rev().find(|r| weight >= r.0).map_or(CHILD_RISK[0].1, |r| r.1);
    }
    let b = bmi(weight);
    let low = BMI_RISK[0];
    if b >= low.0 {
        return BMI_RISK.iter().rev().find(|r| b >= r.0).map_or(low.1, |r| r.1);
    }
    let limit = LIMIT_BMI[sex.min(1) as usize];
    if b <= limit || mu <= 0.0 {
        return if b <= limit { 1e9 } else { low.1 };
    }
    let q15 = 1.0 - crate::life::exp_neg(low.1 * mu);
    let q = q15 + (1.0 - q15) * (low.0 - b) / (low.0 - limit);
    (-crate::life::ln(1.0 - q) / mu).min(1e9)
}

/// Band of the death multiplier: a new death draw is due when it changes.
/// The GBMC and Pelletier bands; below BMI 15 every half BMI point.
pub fn death_band(weight: u16, age: f64) -> u16 {
    if age < CHILD_AGE {
        return CHILD_RISK.iter().rposition(|r| weight >= r.0).unwrap_or(0) as u16;
    }
    let b = bmi(weight);
    match BMI_RISK.iter().rposition(|r| b >= r.0) {
        Some(i) => 100 + i as u16,
        None => (b * 2.0) as u16,
    }
}

/// Multiplier on the fertility of the table at a household food share of
/// `fed` ‰ (Stein and Susser 1975; Cramer and Lumey 2009).
pub fn fert_mult(fed: u16) -> f64 {
    if fed >= FERT_FULL {
        return 1.0;
    }
    let slope = (1.0 - FERT_LOW.1) / (FERT_FULL - FERT_LOW.0) as f64;
    (1.0 - slope * (FERT_FULL - fed) as f64).max(0.0)
}

/// Band of the fertility multiplier (twentieths): a new birth draw is due
/// when it changes.
pub fn fert_band(fed: u16) -> u16 {
    (fert_mult(fed) * 20.0) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minnesota Starvation Experiment (Keys et al. 1950): about 1,570 of
    /// 3,200 kcal a day for 24 weeks cost the men about a quarter of their
    /// weight. Monthly steps: after 5 months between 18 and 30 % less.
    #[test]
    fn minnesota_semistarvation() {
        let share = 1570.0 / 3200.0;
        let mut w = 1000u16;
        for _ in 0..5 {
            w = month(w, share);
        }
        let mut w6 = w;
        w6 = month(w6, share);
        let lost = (1000 - (w + w6) / 2) as f64 / 10.0;
        assert!((18.0..30.0).contains(&lost), "lost {lost} % in 24 weeks");
    }

    /// Hall et al. 2011: 100 kJ a day less ends in 1 kg less; half in a
    /// year, 95 % in about 3 years (52 months, a 70 kg adult).
    #[test]
    fn hall_rule() {
        let kg = 70.0;
        let need = NEED_KJ_PER_KG * kg;
        // 1,000 kJ a day less: 10 kg less in the end.
        let share = 1.0 - 1000.0 / need;
        let end = target(share);
        assert!(((1000.0 - end) / 1000.0 * kg - 10.0).abs() < 1e-9);
        let mut w = 1000u16;
        for _ in 0..12 {
            w = month(w, share);
        }
        let half = (1000.0 - w as f64) / (1000.0 - end);
        assert!((half - 0.5).abs() < 0.03, "after a year {half}");
        for _ in 12..36 {
            w = month(w, share);
        }
        let most = (1000.0 - w as f64) / (1000.0 - end);
        assert!((0.85..0.92).contains(&most), "after 3 years {most}");
        // Back on full food the weight comes back the same way.
        for _ in 0..120 {
            w = month(w, 1.0);
        }
        assert!(w >= 990);
    }

    #[test]
    fn adult_risk_by_bmi() {
        let w = |b: f64| (b / BMI_NORMAL * 1000.0).round() as u16;
        let mu = 0.02;
        assert_eq!(death_mult(1000, 30.0, 1, mu), 1.0);
        assert_eq!(death_mult(w(19.0), 30.0, 1, mu), 1.13);
        assert_eq!(death_mult(w(16.0), 30.0, 0, mu), 1.51);
        // Below 15 the yearly probability rises linearly to 1 at the limit.
        let q = |m: f64| 1.0 - (-m * mu).exp();
        let q15 = q(1.51);
        let mid_m = death_mult(w(14.0), 30.0, 1, mu);
        assert!((q(mid_m) - (q15 + (1.0 - q15) * 0.5)).abs() < 0.01, "BMI 14, man: q {}", q(mid_m));
        let mid_f = death_mult(w(13.0), 30.0, 0, mu);
        assert!((q(mid_f) - (q15 + (1.0 - q15) * 0.5)).abs() < 0.01, "BMI 13, woman: q {}", q(mid_f));
        assert!(death_mult(w(12.9), 30.0, 1, mu) >= 1e9);
        assert!(death_mult(w(12.9), 30.0, 0, mu) < 1e9);
        assert!(death_mult(w(10.9), 30.0, 0, mu) >= 1e9);
        // Never lower when thinner.
        let mut last = 0.0;
        for k in (0..=1000u16).rev() {
            let m = death_mult(k, 30.0, 1, mu);
            assert!(m >= last, "weight {k}");
            last = m;
        }
    }

    #[test]
    fn child_risk_by_weight_for_age() {
        assert_eq!(death_mult(1000, 2.0, 0, 0.05), 1.0);
        assert_eq!(death_mult(800, 2.0, 0, 0.05), 1.0);
        assert_eq!(death_mult(750, 2.0, 0, 0.05), 2.4);
        assert_eq!(death_mult(650, 2.0, 1, 0.05), 4.6);
        assert_eq!(death_mult(500, 2.0, 1, 0.05), 8.4);
        assert_ne!(death_band(750, 2.0), death_band(650, 2.0));
        assert_eq!(death_band(900, 2.0), death_band(1000, 2.0));
    }

    #[test]
    fn fertility_by_food() {
        assert_eq!(fert_mult(1000), 1.0);
        assert_eq!(fert_mult(FERT_FULL), 1.0);
        assert!((fert_mult(300) - 0.69).abs() < 1e-12);
        assert!(fert_mult(0) >= 0.0 && fert_mult(0) < 0.69);
        for k in 1..=1000u16 {
            assert!(fert_mult(k) >= fert_mult(k - 1));
        }
    }

    /// Who eats enough keeps the life table: weight stays at 1000 ‰.
    #[test]
    fn full_food_keeps_the_table() {
        assert_eq!(month(1000, 1.0), 1000);
        assert_eq!(death_mult(month(1000, 1.0), 40.0, 1, 0.02), 1.0);
        assert_eq!(fert_mult(1000), 1.0);
    }
}
