module GamePage.IndirectFirePlanning exposing
    ( IndirectFirePlanning
    , InvariantViolation(..)
    , clearPreview
    , order
    , previewTo
    , start
    , targetPreview
    , targets
    , targetsInRange
    )

import Coordinate exposing (Coordinate)
import InvariantCheck as IC exposing (InvariantCheck)
import Map exposing (Map)
import PlannedOrder exposing (PlannedOrder)
import Unit exposing (Unit)
import UnitId exposing (UnitId)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Targeting begins only after resolving a map position. Its origin and range
remain fixed during command selection; saving rechecks the current firing unit.
-}
type IndirectFirePlanning
    = IndirectFirePlanning
        { origin : Coordinate
        , range : Int
        , preview : Maybe Coordinate
        }


type InvariantViolation
    = CommandUnitNotOnMap UnitId



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


start : Unit -> InvariantCheck InvariantViolation (Maybe IndirectFirePlanning)
start unit =
    case Unit.mapPosition unit of
        Just origin ->
            IC.happy
                (Just
                    (IndirectFirePlanning
                        { origin = origin
                        , range = unit.combatRules.indirectRange
                        , preview = Nothing
                        }
                    )
                )

        Nothing ->
            IC.violated (CommandUnitNotOnMap unit.id) Nothing


previewTo : Map -> Coordinate -> IndirectFirePlanning -> IndirectFirePlanning
previewTo map target ((IndirectFirePlanning planning) as state) =
    if List.member target (targets map state) then
        IndirectFirePlanning { planning | preview = Just target }

    else
        clearPreview state


clearPreview : IndirectFirePlanning -> IndirectFirePlanning
clearPreview (IndirectFirePlanning planning) =
    IndirectFirePlanning { planning | preview = Nothing }


targetPreview : IndirectFirePlanning -> Maybe Coordinate
targetPreview (IndirectFirePlanning planning) =
    planning.preview


targets : Map -> IndirectFirePlanning -> List Coordinate
targets map (IndirectFirePlanning planning) =
    targetsInRange map planning.origin planning.range


{-| Targeting ignores visibility, terrain and occupancy. Only map bounds and
circular range constrain a target, including the firing unit's own square.
-}
targetsInRange : Map -> Coordinate -> Int -> List Coordinate
targetsInRange map origin range =
    let
        inRange : Coordinate -> Bool
        inRange target =
            ((target.x - origin.x) ^ 2 + (target.y - origin.y) ^ 2) <= (range ^ 2)
    in
    Map.positions map |> List.filter inRange


{-| An unavailable target saves no order. A missing required map position reports
an invariant violation while retaining no order for the coordinator to save.
-}
order :
    Map
    -> Unit
    -> Coordinate
    -> InvariantCheck InvariantViolation (Maybe PlannedOrder)
order map unit target =
    case Unit.mapPosition unit of
        Just origin ->
            if List.member target (targetsInRange map origin unit.combatRules.indirectRange) then
                IC.happy
                    (Just
                        { unitId = unit.id
                        , action = PlannedOrder.IndirectFire { position = origin, target = target }
                        }
                    )

            else
                IC.happy Nothing

        Nothing ->
            IC.violated (CommandUnitNotOnMap unit.id) Nothing
