module Game.MovePlanning exposing
    ( MovePlanning
    , MovePurpose(..)
    , canStop
    , extendPath
    , previewTo
    , setDestinationFeedback
    , start
    , traceTo
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.UnitKind as Kind
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.Direction as Direction
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.PlannedTransport as PlannedTransport
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Supplies as Supplies exposing (Supplies)
import Game.UnitResources as UnitResources



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type MovePurpose
    = NormalMove
    | AttackMove


type alias MovePlanning =
    { purpose : MovePurpose
    , preview : Movement.Option
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| The caller resolves the unit's physical origin before starting a route.
-}
start :
    MovePurpose
    -> Map
    -> List Unit
    -> List Movement.Rule
    -> List PlannedOrder
    -> Unit
    -> Coordinate
    -> MovePlanning
start purpose map units movementRules drafts unit origin =
    let
        destinations : PlannedTransport.Occupancy
        destinations =
            PlannedTransport.occupancy units unit drafts

        dismounting : Bool
        dismounting =
            PlannedTransport.isDismounting units unit
    in
    { purpose = purpose
    , preview = Movement.start origin
    , options =
        Movement.optionsAvoiding [] movementRules map units (movementUnit purpose unit)
            |> List.filter (canStopAt purpose destinations dismounting unit)
    , destinationFeedback = NoDestinationFeedback
    }


traceTo :
    Map
    -> List Unit
    -> List Movement.Rule
    -> Unit
    -> Coordinate
    -> MovePlanning
    -> Maybe Movement.Option
traceTo map units movementRules unit destination planning =
    Movement.preview movementRules map units (movementUnit planning.purpose unit) planning.preview destination


previewTo :
    Map
    -> List Unit
    -> List Movement.Rule
    -> Unit
    -> Coordinate
    -> MovePlanning
    -> Maybe MovePlanning
previewTo map units movementRules unit destination planning =
    let
        withPreview : Movement.Option -> MovePlanning
        withPreview preview =
            { planning | preview = preview }
                |> setDestinationFeedback
                    NoDestinationFeedback
    in
    traceTo map units movementRules unit destination planning
        |> Maybe.map withPreview


extendPath :
    Map
    -> List Unit
    -> List Movement.Rule
    -> Unit
    -> Direction
    -> MovePlanning
    -> Maybe MovePlanning
extendPath map units movementRules unit direction planning =
    previewTo map units movementRules unit (Direction.step planning.preview.destination direction) planning


setDestinationFeedback : DestinationFeedback -> MovePlanning -> MovePlanning
setDestinationFeedback feedback planning =
    { planning | destinationFeedback = feedback }


canStop :
    MovePurpose
    -> List Unit
    -> Unit
    -> List PlannedOrder
    -> Movement.Option
    -> Bool
canStop purpose units unit drafts option =
    canStopAt purpose
        (PlannedTransport.occupancy units unit drafts)
        (PlannedTransport.isDismounting units unit)
        unit
        option


{-| Resolve transport reservations once when filtering a unit's destinations.
They depend on the saved orders, not on the candidate route.
-}
canStopAt : MovePurpose -> PlannedTransport.Occupancy -> Bool -> Unit -> Movement.Option -> Bool
canStopAt purpose destinations dismounting unit option =
    case purpose of
        NormalMove ->
            let
                endsOnTruck : Bool
                endsOnTruck =
                    destinations.units
                        |> List.any
                            (\other ->
                                (other.kind == Kind.Truck)
                                    && (Unit.mapPosition other == Just option.destination)
                            )
            in
            not (dismounting && endsOnTruck)
                && Movement.canStop
                    destinations.reserved
                    destinations.units
                    unit
                    option

        AttackMove ->
            let
                alliedOccupants : List Unit
                alliedOccupants =
                    List.filter (\other -> other.playerNumber == unit.playerNumber) destinations.units

                occupied : Bool
                occupied =
                    List.any
                        (\other -> Unit.mapPosition other == Just option.destination)
                        alliedOccupants
            in
            (option.cost > 0)
                && not occupied
                && not (List.member option.destination destinations.reserved)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


movementUnit : MovePurpose -> Unit -> Unit
movementUnit purpose unit =
    let
        reserveCombatSupplies : UnitResources.UnitResources -> UnitResources.UnitResources
        reserveCombatSupplies resources =
            let
                supplies : Supplies
                supplies =
                    resources.supplies
            in
            UnitResources.setSupplies
                (Supplies.setCurrent
                    (supplies.current - unit.combatRules.readinessCost - unit.combatRules.shotCost)
                    supplies
                )
                resources
    in
    case purpose of
        NormalMove ->
            unit

        AttackMove ->
            unit
                |> Unit.mapResources reserveCombatSupplies
