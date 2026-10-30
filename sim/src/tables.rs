//! Tables for the game's overview panels (EU5-style lists of markets,
//! people and farms, and the state's account). Read only, like `view` (S45): building a table changes
//! neither the state nor the fingerprint. A table is a list of columns of
//! equal length, each with a name and a unit, so the game can sort and
//! filter without knowing the simulation.

/// The values of one column.
#[derive(Clone, Debug, PartialEq)]
pub enum Values {
    Int(Vec<i64>),
    Float(Vec<f64>),
    Text(Vec<String>),
}

impl Values {
    pub fn len(&self) -> usize {
        match self {
            Values::Int(v) => v.len(),
            Values::Float(v) => v.len(),
            Values::Text(v) => v.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Column {
    /// Key for the game (stable, ASCII).
    pub key: &'static str,
    /// Header as shown.
    pub name: &'static str,
    /// Unit as shown ("" for none). "%" marks a share, given as 0..1. A key
    /// with "mean" is a mean per person, weighted by `persons` when rows
    /// are summed up.
    pub unit: &'static str,
    /// Data the game uses but does not show (id, place for the camera).
    pub hidden: bool,
    pub values: Values,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Table {
    pub key: &'static str,
    pub name: &'static str,
    /// Simulation day the table was built on.
    pub day: i64,
    pub columns: Vec<Column>,
}

impl Table {
    pub fn new(key: &'static str, name: &'static str, day: i64) -> Table {
        Table { key, name, day, columns: Vec::new() }
    }

    pub fn int(&mut self, key: &'static str, name: &'static str, unit: &'static str, v: Vec<i64>) -> &mut Self {
        self.push(Column { key, name, unit, hidden: false, values: Values::Int(v) })
    }

    pub fn float(&mut self, key: &'static str, name: &'static str, unit: &'static str, v: Vec<f64>) -> &mut Self {
        self.push(Column { key, name, unit, hidden: false, values: Values::Float(v) })
    }

    pub fn text(&mut self, key: &'static str, name: &'static str, v: Vec<String>) -> &mut Self {
        self.push(Column { key, name, unit: "", hidden: false, values: Values::Text(v) })
    }

    /// The stable id of each row (hidden).
    pub fn id(&mut self, v: Vec<i64>) -> &mut Self {
        self.push(Column { key: "id", name: "id", unit: "", hidden: true, values: Values::Int(v) })
    }

    pub fn hidden_float(&mut self, key: &'static str, unit: &'static str, v: Vec<f64>) -> &mut Self {
        self.push(Column { key, name: key, unit, hidden: true, values: Values::Float(v) })
    }

    fn push(&mut self, c: Column) -> &mut Self {
        if let Some(first) = self.columns.first() {
            assert_eq!(first.values.len(), c.values.len(), "column {} of table {}", c.key, self.key);
        }
        self.columns.push(c);
        self
    }

    /// Number of rows.
    pub fn rows(&self) -> usize {
        self.columns.first().map_or(0, |c| c.values.len())
    }

    pub fn column(&self, key: &str) -> Option<&Column> {
        self.columns.iter().find(|c| c.key == key)
    }
}

/// The tables the game can ask for, by key.
pub const TABLES: [&str; 8] = ["markets", "population", "farms", "state", "history", "classes", "goods", "outside"];
