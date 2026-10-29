//! Events for the game's notices and map markers: hunger deaths, moves,
//! thefts, alms, farms taken over or given to heirs (S94: show what the
//! simulation does). Read only, like `view`: logging changes neither the
//! state nor the fingerprint. People and grain each keep the events of
//! the last KEEP_DAYS days; `Grain::events_in` reads both.

pub const HUNGER_DEATH: u8 = 0;
/// A household moved to another cell (yearly or, buyers in need, monthly).
pub const MOVED: u8 = 1;
pub const LEFT_MAP: u8 = 2;
/// A household with nobody of working age joined a relative (S79).
pub const JOINED: u8 = 3;
pub const THEFT: u8 = 4;
pub const ALMS: u8 = 5;
/// A tent household moved to a market with more work and alms (S75).
pub const TENT_MOVED: u8 = 6;
/// A landless household took a free farm (S69).
pub const FARM_TAKEN: u8 = 7;
/// A son got his share of the father's farm (S83).
pub const HEIR: u8 = 8;
/// A household without workers went to the tents (S79).
pub const TO_TENT: u8 = 9;
/// A landless household cleared a farm under the Lex Manciana (S92).
pub const MANCIANA: u8 = 10;
pub const FARM_LEFT: u8 = 11;

pub const NAMES: [&str; 12] = [
    "Hungertod",
    "Umzug",
    "Verlässt die Karte",
    "Zieht zu Verwandten",
    "Diebstahl",
    "Almosen",
    "Zelt zieht um",
    "Hof übernommen",
    "Erbteil",
    "Ins Zelt",
    "Hof nach Lex Manciana",
    "Hof verlassen",
];

/// Days an event is kept.
pub const KEEP_DAYS: i64 = 60;

/// One event. `cell` is the 25 km cell where it happened (for a move the
/// one left), `to` the cell moved to, `fine` the fine tile where it is
/// known (farmstead, NONE else), `other` a second household (the farm
/// robbed, the father), `amount` kg for thefts and alms.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Event {
    pub day: i64,
    pub kind: u8,
    pub household: u32,
    pub pid: u32,
    pub cell: u32,
    pub to: u32,
    pub fine: u32,
    pub other: u32,
    pub amount: i64,
}

/// Drops the events older than KEEP_DAYS.
pub fn prune(v: &mut Vec<Event>, day: i64) {
    v.retain(|e| e.day > day - KEEP_DAYS);
}
