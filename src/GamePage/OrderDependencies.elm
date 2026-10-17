module GamePage.OrderDependencies exposing
    ( InvariantViolation(..)
    , revoke
    )

import Coordinate exposing (Coordinate)
import GamePage.PlannedTransport as PlannedTransport
import InvariantCheck as IC exposing (InvariantCheck)
import PlannedOrder exposing (PlannedOrder)
import Unit exposing (Unit)
import UnitId exposing (UnitId)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type InvariantViolation
    = OrderUnitNotFound UnitId



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Revoking a departure also revokes routes relying on the vacated square.
Every saved order must refer to an existing unit. Validate before removing any
orders so a failed lookup retains the original drafts.
-}
revoke :
    List Unit
    -> List UnitId
    -> List PlannedOrder
    -> InvariantCheck InvariantViolation (List PlannedOrder)
revoke units revokedIds drafts =
    let
        missingUnit : PlannedOrder -> Bool
        missingUnit order =
            not (List.any (\unit -> unit.id == order.unitId) units)
    in
    case ListUtil.find missingUnit drafts of
        Just order ->
            IC.violated (OrderUnitNotFound order.unitId) drafts

        Nothing ->
            IC.happy (revokeValidated units revokedIds drafts)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


{-| All order units have been checked. Each step removes orders, so chains and
cycles terminate. A dismounted passenger may still have no authoritative map position.
-}
revokeValidated : List Unit -> List UnitId -> List PlannedOrder -> List PlannedOrder
revokeValidated units revokedIds drafts =
    let
        removed : List PlannedOrder
        removed =
            List.filter (\plan -> List.member plan.unitId revokedIds) drafts

        origin : PlannedOrder -> Maybe Coordinate
        origin plan =
            if PlannedOrder.isMoving plan then
                units
                    |> ListUtil.find (\unit -> unit.id == plan.unitId)
                    |> Maybe.andThen Unit.mapPosition

            else
                Nothing

        occupiedAgain : List Coordinate
        occupiedAgain =
            List.filterMap origin removed

        retained : List PlannedOrder
        retained =
            List.filter
                (\plan -> not (List.member plan.unitId revokedIds))
                drafts

        dependsOnDeparture : PlannedOrder -> Bool
        dependsOnDeparture plan =
            let
                needsDestination : Bool
                needsDestination =
                    PlannedOrder.isMoving plan && List.member (PlannedOrder.destination plan) occupiedAgain

                needsPassengerExit : Bool
                needsPassengerExit =
                    List.any (\unload -> List.member unload.destination occupiedAgain) (PlannedOrder.unloads plan)

                needsTruck : Bool
                needsTruck =
                    units
                        |> ListUtil.find (\unit -> unit.id == plan.unitId)
                        |> Maybe.andThen boardingTarget
                        |> Maybe.map (\truck -> List.member truck.id revokedIds)
                        |> Maybe.withDefault False

                boardingTarget : Unit -> Maybe Unit
                boardingTarget unit =
                    PlannedTransport.loadingTarget units unit (PlannedOrder.destination plan) drafts

                needsCrateExit : Bool
                needsCrateExit =
                    List.any
                        (\unload -> List.member unload.destination occupiedAgain)
                        (PlannedOrder.crateUnloads plan)

                needsDismount : Bool
                needsDismount =
                    removed
                        |> List.concatMap PlannedOrder.unloads
                        |> List.any (\exit -> exit.unitId == plan.unitId)
            in
            needsDestination
                || needsPassengerExit
                || needsCrateExit
                || needsTruck
                || needsDismount

        dependentIds : List UnitId
        dependentIds =
            retained |> List.filter dependsOnDeparture |> List.map .unitId
    in
    if List.isEmpty dependentIds then
        retained

    else
        revokeValidated units dependentIds retained
