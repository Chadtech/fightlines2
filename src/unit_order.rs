//! Accepted unit intentions. Each action carries only the data it can use.
use crate::{
    map::Coordinate,
    scenario::{Direction, UnitId},
    supplies::SupplyOrder,
};
use juniper::GraphQLEnum;

/// Read-only description of an accepted order, shared by replay and combat inspection.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum UnitOrderKind {
    Hold,
    Move,
    Rotate,
    AttackMove,
    Ambush,
    StandGround,
    DigIn,
    Sabotage,
    IndirectFire,
}

#[derive(Clone, Debug)]
pub struct UnloadOrder {
    pub unit_id: UnitId,
    pub destination: Coordinate,
}

/// A moving route always includes an origin and at least one step.
/// Battlefield-dependent legality is checked by turn validation.
#[derive(Clone, Debug)]
pub struct Route {
    coordinates: Vec<Coordinate>,
}

impl Route {
    pub fn new(coordinates: Vec<Coordinate>) -> Result<Self, &'static str> {
        if coordinates.len() < 2 {
            return Err("movement requires an origin and at least one step.");
        }
        Ok(Self { coordinates })
    }

    pub fn coordinates(&self) -> &[Coordinate] {
        &self.coordinates
    }
}

#[derive(Clone, Debug)]
pub enum Journey {
    Stationary(Coordinate),
    Moving(Route),
}

impl Journey {
    pub fn from_path(path: Vec<Coordinate>) -> Result<Self, &'static str> {
        match path.as_slice() {
            [] => Err("an order requires a starting position."),
            [position] => Ok(Self::Stationary(*position)),
            _ => Ok(Self::Moving(Route::new(path)?)),
        }
    }

    pub fn path(&self) -> &[Coordinate] {
        match self {
            Self::Stationary(position) => std::slice::from_ref(position),
            Self::Moving(route) => route.coordinates(),
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum ArrivalFacing {
    AlongRoute,
    Face(Direction),
}

#[derive(Clone, Debug)]
pub struct TransportPlan {
    pub journey: Journey,
    pub unloads: Vec<UnloadOrder>,
    pub supply: SupplyOrder,
}

#[derive(Clone, Debug)]
pub enum OrderAction {
    Hold(Coordinate),
    Move(Route),
    AttackMove {
        route: Route,
        facing: ArrivalFacing,
    },
    Ambush {
        position: Coordinate,
        direction: Direction,
    },
    StandGround {
        position: Coordinate,
        direction: Direction,
    },
    DigIn(Coordinate),
    Sabotage(Coordinate),
    IndirectFire {
        position: Coordinate,
        target: Coordinate,
    },
    Transport(TransportPlan),
}

#[derive(Clone, Debug)]
pub struct UnitOrder {
    pub unit_id: UnitId,
    pub action: OrderAction,
}

impl UnitOrder {
    pub fn hold(unit_id: UnitId, position: Coordinate) -> Self {
        Self {
            unit_id,
            action: OrderAction::Hold(position),
        }
    }

    #[cfg(test)]
    pub fn movement(unit_id: UnitId, path: Vec<Coordinate>) -> Result<Self, &'static str> {
        let action = match Journey::from_path(path)? {
            Journey::Stationary(position) => OrderAction::Hold(position),
            Journey::Moving(route) => OrderAction::Move(route),
        };
        Ok(Self { unit_id, action })
    }

    pub fn path(&self) -> &[Coordinate] {
        match &self.action {
            OrderAction::Hold(position)
            | OrderAction::DigIn(position)
            | OrderAction::Sabotage(position)
            | OrderAction::Ambush { position, .. }
            | OrderAction::StandGround { position, .. }
            | OrderAction::IndirectFire { position, .. } => std::slice::from_ref(position),
            OrderAction::Move(route) | OrderAction::AttackMove { route, .. } => route.coordinates(),
            OrderAction::Transport(plan) => plan.journey.path(),
        }
    }

    pub fn kind(&self) -> UnitOrderKind {
        match self.action {
            OrderAction::Hold(_) => UnitOrderKind::Hold,
            OrderAction::Move(_) => UnitOrderKind::Move,
            OrderAction::AttackMove { .. } => UnitOrderKind::AttackMove,
            OrderAction::Ambush { .. } => UnitOrderKind::Ambush,
            OrderAction::StandGround { .. } => UnitOrderKind::StandGround,
            OrderAction::DigIn(_) => UnitOrderKind::DigIn,
            OrderAction::Sabotage(_) => UnitOrderKind::Sabotage,
            OrderAction::IndirectFire { .. } => UnitOrderKind::IndirectFire,
            OrderAction::Transport(_) => {
                if self.path().len() == 1 {
                    UnitOrderKind::Hold
                } else {
                    UnitOrderKind::Move
                }
            }
        }
    }

    /// Initial readiness facing; attack-move arrival facing applies later.
    pub fn direction(&self) -> Option<Direction> {
        match self.action {
            OrderAction::Ambush { direction, .. } | OrderAction::StandGround { direction, .. } => {
                Some(direction)
            }
            _ => None,
        }
    }

    pub fn arrival_direction(&self) -> Option<Direction> {
        match self.action {
            OrderAction::AttackMove {
                facing: ArrivalFacing::Face(direction),
                ..
            } => Some(direction),
            _ => None,
        }
    }

    pub fn unloads(&self) -> &[UnloadOrder] {
        match &self.action {
            OrderAction::Transport(plan) => &plan.unloads,
            _ => &[],
        }
    }

    pub fn supply(&self) -> Option<&SupplyOrder> {
        match &self.action {
            OrderAction::Transport(plan) => Some(&plan.supply),
            _ => None,
        }
    }

    pub fn permits_boarding(&self) -> bool {
        match self.action {
            OrderAction::Hold(_) | OrderAction::Move(_) | OrderAction::Transport(_) => true,
            OrderAction::AttackMove { .. }
            | OrderAction::Ambush { .. }
            | OrderAction::StandGround { .. }
            | OrderAction::DigIn(_)
            | OrderAction::Sabotage(_)
            | OrderAction::IndirectFire { .. } => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn moving_routes_reject_missing_travel() {
        let position = Coordinate::new(2, 3);
        assert!(Route::new(Vec::new()).is_err());
        assert!(Route::new(vec![position]).is_err());
        assert!(Journey::from_path(Vec::new()).is_err());
        assert!(Route::new(vec![position, Coordinate::new(3, 3)]).is_ok());
    }
}
