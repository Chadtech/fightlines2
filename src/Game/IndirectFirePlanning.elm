module Game.IndirectFirePlanning exposing
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

import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import InvariantCheck as IC exposing (InvariantCheck)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Targeting begins only after resolving a map position. Its origin and range
remain fixed during order selection; saving rechecks the current firing unit.
-}
type IndirectFirePlanning
    = IndirectFirePlanning
        { origin : Coordinate
        , range : Int
        , preview : Maybe Coordinate
        }


type InvariantViolation
    = OrderUnitNotOnMap UnitId



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setPreview : Maybe Coordinate -> IndirectFirePlanning -> IndirectFirePlanning
setPreview preview (IndirectFirePlanning planning) =
    IndirectFirePlanning { planning | preview = preview }



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
            IC.violated (OrderUnitNotOnMap unit.id) Nothing


previewTo : Map -> Coordinate -> IndirectFirePlanning -> IndirectFirePlanning
previewTo map target state =
    if List.member target (targets map state) then
        setPreview (Just target) state

    else
        clearPreview state


clearPreview : IndirectFirePlanning -> IndirectFirePlanning
clearPreview =
    setPreview Nothing


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
    Map.positions map |> List.filter (Coordinate.inRange origin range)


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
            IC.violated (OrderUnitNotOnMap unit.id) Nothing
