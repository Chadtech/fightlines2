module Game.UnloadPlanning exposing
    ( InvariantViolation(..)
    , Step(..)
    , UnloadChoice
    , UnloadPlanning
    , availableOptions
    , canConfirm
    , canSelectCargo
    , confirm
    , options
    , orders
    , saveDestination
    , startChoice
    , toggleCargo
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.DestinationFeedback exposing (DestinationFeedback(..))
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.PlannedTransport exposing (Occupancy)
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnloadCargo as UnloadCargo exposing (UnloadCargo)
import Game.UnloadingTruck as UnloadingTruck exposing (UnloadingTruck)
import InvariantCheck as IC exposing (InvariantCheck)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias UnloadChoice =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , checked : List UnloadCargo
    }


type alias UnloadPlanning =
    { truck : UnloadingTruck
    , otherOrders : List PlannedOrder
    , cargo : UnloadCargo
    , remaining : List UnloadCargo
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }


{-| Progression owns only unloading. The caller chooses what follows completion.
-}
type Step
    = ChoosingExit UnloadPlanning
    | Finished UnloadingTruck (List PlannedOrder)


type InvariantViolation
    = PassengerNotFound UnitId



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


startChoice : UnloadingTruck -> List PlannedOrder -> UnloadChoice
startChoice truck drafts =
    { truck = truck
    , otherOrders =
        List.filter
            (\order -> order.unitId /= UnloadingTruck.unitId truck)
            drafts
    , checked = []
    }


toggleCargo : UnloadCargo -> Bool -> UnloadChoice -> UnloadChoice
toggleCargo cargo checked choice =
    let
        retained : List UnloadCargo
        retained =
            List.filter ((/=) cargo) choice.checked

        selected : List UnloadCargo
        selected =
            if checked then
                cargo :: retained

            else
                retained
    in
    { choice | checked = selected }


{-| Check the entire selection, including scarce exits and passenger supplies.
Checked cargo always remains removable.
-}
canSelectCargo :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> UnloadCargo
    -> UnloadChoice
    -> InvariantCheck error Bool
canSelectCargo rawOptions cargo choice =
    if List.member cargo choice.checked then
        IC.happy True

    else
        toggleCargo cargo True choice
            |> canConfirm rawOptions


canConfirm :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> UnloadChoice
    -> InvariantCheck error Bool
canConfirm rawOptions choice =
    confirm rawOptions choice |> IC.andThen (canComplete rawOptions)


confirm :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> UnloadChoice
    -> InvariantCheck error Step
confirm exitOptions choice =
    next exitOptions choice.truck choice.otherOrders (List.reverse choice.checked)


saveDestination :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> Coordinate
    -> UnloadPlanning
    -> InvariantCheck error Step
saveDestination exitOptions destination planning =
    if List.any (\option -> option.destination == destination) planning.options then
        next exitOptions
            (UnloadCargo.saveExit destination planning.cargo planning.truck)
            planning.otherOrders
            planning.remaining

    else
        IC.happy (ChoosingExit { planning | destinationFeedback = DestinationUnavailable })


orders : UnloadPlanning -> List PlannedOrder
orders planning =
    UnloadingTruck.toOrder planning.truck :: planning.otherOrders


{-| Offer only exits that leave a complete legal placement for remaining cargo.
Simulation uses raw options, so it does not recurse through the filtered picker.
-}
availableOptions :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> UnloadPlanning
    -> InvariantCheck error (List Movement.Option)
availableOptions rawOptions planning =
    let
        completes : Movement.Option -> InvariantCheck error Bool
        completes option =
            saveDestination rawOptions
                option.destination
                (planning
                    |> setOptions
                        [ option ]
                )
                |> IC.andThen (canComplete rawOptions)

        keepCompleting :
            Movement.Option
            -> InvariantCheck error (List Movement.Option)
            -> InvariantCheck error (List Movement.Option)
        keepCompleting option retained =
            let
                keepIfComplete : Bool -> InvariantCheck error (List Movement.Option)
                keepIfComplete possible =
                    if possible then
                        IC.map ((::) option) retained

                    else
                        retained
            in
            completes option |> IC.andThen keepIfComplete
    in
    rawOptions planning
        |> IC.andThen (List.foldr keepCompleting (IC.happy []))


options :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Movement.Rule
    -> List Supply.GroundCrate
    -> (Unit -> List PlannedOrder -> Occupancy)
    -> UnloadPlanning
    -> InvariantCheck InvariantViolation (List Movement.Option)
options map units playerNumbers movementRules supplyCrates occupancy planning =
    let
        projectTruck : Unit -> Unit
        projectTruck unit =
            if unit.id == UnloadingTruck.unitId planning.truck then
                Unit.setOnMap (UnloadingTruck.destination planning.truck) unit

            else
                unit

        projectedUnits : List Unit
        projectedUnits =
            List.map projectTruck units

        drafts : List PlannedOrder
        drafts =
            orders planning
    in
    case planning.cargo of
        UnloadCargo.Passenger passengerId ->
            case ListUtil.find (\unit -> unit.id == passengerId) projectedUnits of
                Just passenger ->
                    let
                        destinations : Occupancy
                        destinations =
                            occupancy passenger drafts
                    in
                    Movement.optionsAvoiding [] movementRules map projectedUnits passenger
                        |> List.filter
                            (Movement.canStop
                                destinations.reserved
                                (List.map projectTruck destinations.units)
                                passenger
                            )
                        |> IC.happy

                Nothing ->
                    IC.violated (PassengerNotFound passengerId) []

        UnloadCargo.Crate _ ->
            IC.happy (crateExitOptions map units playerNumbers supplyCrates planning drafts)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setOptions : List Movement.Option -> UnloadPlanning -> UnloadPlanning
setOptions value model =
    { model | options = value }


next :
    (UnloadPlanning -> InvariantCheck error (List Movement.Option))
    -> UnloadingTruck
    -> List PlannedOrder
    -> List UnloadCargo
    -> InvariantCheck error Step
next exitOptions truck otherOrders cargoes =
    case cargoes of
        [] ->
            IC.happy (Finished truck otherOrders)

        cargo :: remaining ->
            let
                planning : UnloadPlanning
                planning =
                    { truck = truck
                    , otherOrders = otherOrders
                    , cargo = cargo
                    , remaining = remaining
                    , options = []
                    , destinationFeedback = NoDestinationFeedback
                    }

                withOptions : List Movement.Option -> Step
                withOptions choices =
                    ChoosingExit
                        (planning
                            |> setOptions choices
                        )
            in
            exitOptions planning |> IC.map withOptions


{-| Trucks carry at most two cargo items, bounding the placement search.
-}
canComplete :
    (UnloadPlanning
     -> InvariantCheck error (List Movement.Option)
    )
    -> Step
    -> InvariantCheck error Bool
canComplete rawOptions step =
    case step of
        Finished _ _ ->
            IC.happy True

        ChoosingExit planning ->
            let
                tryOptions : List Movement.Option -> InvariantCheck error Bool
                tryOptions choices =
                    case choices of
                        [] ->
                            IC.happy False

                        option :: remaining ->
                            let
                                tryRemaining : Bool -> InvariantCheck error Bool
                                tryRemaining completes =
                                    if completes then
                                        IC.happy True

                                    else
                                        tryOptions remaining
                            in
                            saveDestination rawOptions
                                option.destination
                                (planning
                                    |> setOptions
                                        [ option ]
                                )
                                |> IC.andThen (canComplete rawOptions)
                                |> IC.andThen tryRemaining
            in
            rawOptions planning |> IC.andThen tryOptions


crateExitOptions :
    Map
    -> List Unit
    -> List PlayerNumber
    -> List Supply.GroundCrate
    -> UnloadPlanning
    -> List PlannedOrder
    -> List Movement.Option
crateExitOptions map units playerNumbers supplyCrates planning plans =
    let
        origin : Coordinate
        origin =
            UnloadingTruck.destination planning.truck

        reserved : List Coordinate
        reserved =
            List.concatMap (PlannedOrder.crateUnloads >> List.map .destination) plans

        available : Coordinate -> Bool
        available exit =
            let
                insideMap : Bool
                insideMap =
                    (exit.x >= 0)
                        && (exit.y >= 0)
                        && (exit.x < map.width)
                        && (exit.y < map.height)

                blocksExit : Unit -> Bool
                blocksExit unit =
                    not (List.member unit.playerNumber playerNumbers) && Unit.mapPosition unit == Just exit

                hasUnit : Bool
                hasUnit =
                    List.any blocksExit units

                hasCrate : Bool
                hasCrate =
                    List.any (\crate -> crate.position == exit) supplyCrates
            in
            insideMap && not (List.member exit reserved) && not hasUnit && not hasCrate

        option : Coordinate -> Movement.Option
        option exit =
            { destination = exit
            , path =
                [ origin
                , exit
                ]
            , cost = 0
            }
    in
    [ { x = origin.x
      , y = origin.y - 1
      }
    , { x = origin.x + 1
      , y = origin.y
      }
    , { x = origin.x
      , y = origin.y + 1
      }
    , { x = origin.x - 1
      , y = origin.y
      }
    ]
        |> List.filter available
        |> List.map option
