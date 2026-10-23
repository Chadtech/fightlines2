module Game.PlannedTransport exposing
    ( InvariantViolation(..)
    , Occupancy
    , boardingPassengers
    , cargoRoom
    , hasCargo
    , isDismounting
    , loadingTarget
    , moveOrders
    , moveReceiver
    , nextDismountedUnit
    , occupancy
    , planningUnit
    , receivingLoad
    , withoutStalePassengerHolds
    )

import Api.Enum.UnitKind as Kind
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location
import Game.Unit.Supplies as Supplies exposing (Supplies)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitResources as UnitResources
import InvariantCheck as IC exposing (InvariantCheck)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Destination occupancy for one unit after accounting for saved orders.
Moving units meet compatible boarding partners at their arrival squares.
Departing units free their origins; saved destinations and passenger exits remain reserved.
-}
type alias Occupancy =
    { reserved : List Coordinate
    , units : List Unit
    }


type InvariantViolation
    = CarrierNotFound
        { passengerId : UnitId
        , carrierId : UnitId
        }
    | CarrierNotOnMap
        { passengerId : UnitId
        , carrierId : UnitId
        }
    | ReceiverHasNoPosition UnitId



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


occupancy : List Unit -> Unit -> List PlannedOrder -> Occupancy
occupancy units unit drafts =
    { reserved = reservedDestinations units unit drafts
    , units = destinationUnits units drafts
    }


{-| Project an infantry's planned dismount for local command planning. The board and cargo
remain authoritative until playback; previews reserve the actual unloading cost.
-}
planningUnit : Map -> List PlannedOrder -> Unit -> Unit
planningUnit map drafts unit =
    let
        exit : Maybe PlannedOrder.UnloadOrder
        exit =
            drafts
                |> List.concatMap PlannedOrder.unloads
                |> ListUtil.find (\unload -> unload.unitId == unit.id)

        dismount : PlannedOrder.UnloadOrder -> Unit
        dismount unload =
            let
                spendUnloading : UnitResources.UnitResources -> UnitResources.UnitResources
                spendUnloading resources =
                    let
                        supplies : Supplies
                        supplies =
                            resources.supplies

                        cost : Int
                        cost =
                            Movement.supplyCost
                                map
                                supplies
                                [ unload.destination, unload.destination ]
                    in
                    UnitResources.setSupplies
                        (Supplies.setCurrent (supplies.current - cost) supplies)
                        resources
            in
            unit
                |> Unit.setLocation (Location.dismounting unload.destination)
                |> Unit.mapResources spendUnloading
    in
    if (unit.kind == Kind.Infantry) && (Unit.carrierId unit /= Nothing) then
        exit
            |> Maybe.map dismount
            |> Maybe.withDefault unit

    else
        unit


{-| A projected infantry is on the map while its physical unit is still aboard.
-}
isDismounting : List Unit -> Unit -> Bool
isDismounting units unit =
    let
        wasAboard : Bool
        wasAboard =
            units
                |> ListUtil.find (\original -> original.id == unit.id)
                |> Maybe.andThen Unit.carrierId
                |> (/=) Nothing
    in
    (unit.kind == Kind.Infantry) && Unit.onMap unit && wasAboard


{-| Trucks and passengers meet at their planned destinations, whichever is saved first.
Departing allies free their starting squares while their destinations remain reserved.
-}
loadingTarget : List Unit -> Unit -> Coordinate -> List PlannedOrder -> Maybe Unit
loadingTarget units mover destination drafts =
    destinationUnits units drafts
        |> List.filter (canBoardWithOrder drafts)
        |> (\targets -> Unit.loadingTarget targets mover destination)


{-| Include arriving passengers and waiting pickups at the truck's destination.
Existing passengers remain separate because unloading does not free a berth yet.
-}
boardingPassengers : List Unit -> UnitId -> List PlannedOrder -> List UnitId
boardingPassengers units truckId drafts =
    let
        boardsTruck : PlannedOrder -> Bool
        boardsTruck plan =
            let
                receiver : Unit -> Maybe Unit
                receiver passenger =
                    loadingTarget units passenger (PlannedOrder.destination plan) drafts

                targetId : Maybe UnitId
                targetId =
                    units
                        |> ListUtil.find (\unit -> unit.id == plan.unitId)
                        |> Maybe.andThen receiver
                        |> Maybe.map .id
            in
            (plan.unitId /= truckId)
                && not (PlannedOrder.isAttackMove plan)
                && (targetId == Just truckId)
    in
    drafts
        |> List.filter boardsTruck
        |> List.map .unitId


{-| Shared berths available for freight after existing cargo and planned
boarding. Passenger exits do not free berths for loading in the same turn.
-}
cargoRoom : List Unit -> Unit -> List PlannedOrder -> Int
cargoRoom units truck drafts =
    let
        passengers : Int
        passengers =
            List.filter (\passenger -> Unit.carrierId passenger == Just truck.id) units
                |> List.length

        incoming : Int
        incoming =
            boardingPassengers units truck.id drafts
                |> List.length
    in
    max 0 (truck.cargoCapacity - passengers - Unit.freightCount truck - incoming)


receivingLoad : List Unit -> Unit -> List PlannedOrder -> Bool
receivingLoad units unit drafts =
    let
        receives : PlannedOrder -> Bool
        receives plan =
            if not (PlannedOrder.isMoving plan) || PlannedOrder.isAttackMove plan then
                False

            else
                case ListUtil.find (\mover -> mover.id == plan.unitId) units of
                    Just mover ->
                        if Unit.carrierId mover == Just unit.id then
                            True

                        else
                            loadingTarget
                                units
                                mover
                                (PlannedOrder.destination plan)
                                drafts
                                |> Maybe.map .id
                                |> (==) (Just unit.id)

                    Nothing ->
                        False
    in
    List.any receives drafts


hasCargo : List Unit -> Unit -> Bool
hasCargo units truck =
    let
        hasPassengers : Bool
        hasPassengers =
            List.any (\passenger -> Unit.carrierId passenger == Just truck.id) units

        hasFreight : Bool
        hasFreight =
            Unit.freightCount truck > 0
    in
    hasPassengers || hasFreight


{-| Save the mover and its receiving order together. A broken required carrier
or receiving hold keeps the existing drafts and reports the failed assumption.
A move without a boarding partner is an ordinary successful move.
-}
moveOrders :
    List Unit
    -> Unit
    -> Movement.Option
    -> List PlannedOrder
    -> InvariantCheck InvariantViolation (List PlannedOrder)
moveOrders units unit move drafts =
    let
        saveWithReceiver : Maybe Unit -> InvariantCheck InvariantViolation (List PlannedOrder)
        saveWithReceiver receiver =
            let
                retained : List PlannedOrder
                retained =
                    List.filter
                        (\plan ->
                            (plan.unitId /= unit.id)
                                && (Just plan.unitId /= Maybe.map .id receiver)
                        )
                        drafts

                order : PlannedOrder
                order =
                    { unitId = unit.id
                    , action = PlannedOrder.Move { move = move, unloads = [] }
                    }

                receiverOrder : Unit -> Maybe PlannedOrder
                receiverOrder target =
                    case ListUtil.find (\plan -> plan.unitId == target.id) drafts of
                        Just plan ->
                            case plan.action of
                                PlannedOrder.SupplyTransfer _ ->
                                    Just plan

                                _ ->
                                    if PlannedOrder.isMoving plan then
                                        Just plan

                                    else
                                        PlannedOrder.hold units target

                        Nothing ->
                            PlannedOrder.hold units target
            in
            case receiver of
                Just target ->
                    case receiverOrder target of
                        Just receivingOrder ->
                            IC.happy (order :: receivingOrder :: retained)

                        Nothing ->
                            IC.violated (ReceiverHasNoPosition target.id) drafts

                Nothing ->
                    case Unit.carrierId unit of
                        Just _ ->
                            -- The carrier lookup already retains its diagnostic.
                            -- Without it, there is no transport move to save.
                            IC.happy drafts

                        Nothing ->
                            IC.happy (order :: retained)
    in
    moveReceiver units unit move drafts |> IC.andThen saveWithReceiver


{-| No boarding partner is expected on an ordinary move. An explicit carrier
identity, however, must resolve to a carrier on the map.
-}
moveReceiver :
    List Unit
    -> Unit
    -> Movement.Option
    -> List PlannedOrder
    -> InvariantCheck InvariantViolation (Maybe Unit)
moveReceiver units unit move drafts =
    case Unit.carrierId unit of
        Just carrierId ->
            let
                relationship :
                    { passengerId : UnitId
                    , carrierId : UnitId
                    }
                relationship =
                    { passengerId = unit.id
                    , carrierId = carrierId
                    }
            in
            case ListUtil.find (\truck -> truck.id == carrierId) units of
                Just carrier ->
                    if Unit.onMap carrier then
                        IC.happy (Just carrier)

                    else
                        IC.violated (CarrierNotOnMap relationship) Nothing

                Nothing ->
                    IC.violated (CarrierNotFound relationship) Nothing

        Nothing ->
            IC.happy (loadingTarget units unit move.destination drafts)


{-| Drop aboard holds superseded by an infantry command from a planned exit.
Other units' orders remain unchanged.
-}
withoutStalePassengerHolds : Map -> List Unit -> List PlannedOrder -> List PlannedOrder
withoutStalePassengerHolds map units drafts =
    let
        staleHold : PlannedOrder -> Bool
        staleHold order =
            case ListUtil.find (\unit -> unit.id == order.unitId) units of
                Just unit ->
                    let
                        planned : Unit
                        planned =
                            planningUnit map drafts unit
                    in
                    (Unit.carrierId unit /= Nothing)
                        && Unit.onMap planned
                        && (List.head (PlannedOrder.path order) /= Unit.mapPosition planned)

                Nothing ->
                    False
    in
    List.filter (not << staleHold) drafts


nextDismountedUnit : Map -> List Unit -> List PlannedOrder -> Maybe Unit
nextDismountedUnit map units drafts =
    let
        needsCommand : Unit -> Bool
        needsCommand unit =
            (Unit.carrierId unit /= Nothing)
                && Unit.onMap (planningUnit map drafts unit)
                && not (List.any (\order -> order.unitId == unit.id) drafts)
    in
    ListUtil.find needsCommand units



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


destinationUnits : List Unit -> List PlannedOrder -> List Unit
destinationUnits units drafts =
    let
        destinationUnit : Unit -> Maybe Unit
        destinationUnit unit =
            let
                departure : PlannedOrder -> Bool
                departure plan =
                    (plan.unitId == unit.id) && PlannedOrder.isMoving plan
            in
            case ListUtil.find departure drafts of
                Just plan ->
                    if Unit.onMap unit then
                        Just (Unit.setOnMap (PlannedOrder.destination plan) unit)

                    else
                        Nothing

                Nothing ->
                    Just unit
    in
    List.filterMap destinationUnit units


{-| Passengers board only with ordinary movement and holds. Other commands
keep their destination reserved, even when the unit could otherwise ride.
-}
canBoardWithOrder : List PlannedOrder -> Unit -> Bool
canBoardWithOrder drafts unit =
    case ListUtil.find (\order -> order.unitId == unit.id) drafts of
        Nothing ->
            True

        Just order ->
            case order.action of
                PlannedOrder.Hold _ ->
                    True

                PlannedOrder.Move _ ->
                    True

                PlannedOrder.SupplyTransfer _ ->
                    unit.kind == Kind.Truck

                PlannedOrder.Unload _ ->
                    unit.kind == Kind.Truck

                _ ->
                    False


boardingSpace : List Unit -> Unit -> Unit -> List PlannedOrder -> Bool
boardingSpace units mover target drafts =
    let
        truck : Unit
        truck =
            if mover.kind == Kind.Truck then
                mover

            else
                target

        alreadyAboard : Int
        alreadyAboard =
            List.length
                (List.filter
                    (\unit -> Unit.carrierId unit == Just truck.id)
                    units
                )

        incomingPassengers : Int
        incomingPassengers =
            let
                boardsAtDestination : Unit -> Bool
                boardsAtDestination passenger =
                    Unit.mapPosition target
                        |> Maybe.andThen (Unit.loadingTarget [ passenger ] truck)
                        |> (/=) Nothing
            in
            destinationUnits units drafts
                |> List.filter (canBoardWithOrder drafts)
                |> List.filter (\passenger -> passenger.id /= mover.id)
                |> List.filter boardsAtDestination
                |> List.length

        movingPassenger : Int
        movingPassenger =
            if mover.kind == Kind.Truck then
                0

            else
                1

        plannedCrates : Int
        plannedCrates =
            ListUtil.find (\order -> order.unitId == truck.id) drafts
                |> Maybe.map loadingCount
                |> Maybe.withDefault 0

        loadingCount : PlannedOrder -> Int
        loadingCount order =
            case order.action of
                PlannedOrder.SupplyTransfer plan ->
                    PlannedOrder.loadingBerths plan

                _ ->
                    0

        fitsCargo : Bool
        fitsCargo =
            alreadyAboard
                + Unit.freightCount truck
                + plannedCrates
                + incomingPassengers
                + movingPassenger
                <= truck.cargoCapacity

        compatible : Bool
        compatible =
            Unit.mapPosition target
                |> Maybe.andThen
                    (\destination ->
                        loadingTarget units mover destination drafts
                    )
                |> Maybe.map .id
                |> (==) (Just target.id)
    in
    compatible && fitsCargo


reservedDestinations : List Unit -> Unit -> List PlannedOrder -> List Coordinate
reservedDestinations units unit drafts =
    let
        reserves : PlannedOrder -> Bool
        reserves plan =
            let
                destinationTarget : Maybe Unit
                destinationTarget =
                    loadingTarget
                        units
                        unit
                        (PlannedOrder.destination plan)
                        drafts

                isWaitingTarget : Unit -> Bool
                isWaitingTarget target =
                    (target.id == plan.unitId)
                        && not (receivingLoad units target drafts && target.cargoCapacity == 0)
                        && (target.cargoCapacity == 0 || boardingSpace units unit target drafts)

                waitingTarget : Bool
                waitingTarget =
                    not
                        (PlannedOrder.isMoving plan)
                        && (destinationTarget |> Maybe.map isWaitingTarget |> Maybe.withDefault False)

                boardingDestination : Bool
                boardingDestination =
                    destinationTarget
                        |> Maybe.map (\target -> boardingSpace units unit target drafts)
                        |> Maybe.withDefault False
            in
            plan.unitId /= unit.id && not waitingTarget && not boardingDestination

        unavailableReceiver : Unit -> Bool
        unavailableReceiver target =
            let
                boardingTarget : Coordinate -> Maybe Unit
                boardingTarget position =
                    loadingTarget units unit position drafts

                hasBoardingSpace : Unit -> Bool
                hasBoardingSpace truck =
                    boardingSpace units unit truck drafts

                canBoardAtTarget : Bool
                canBoardAtTarget =
                    Unit.mapPosition target
                        |> Maybe.andThen boardingTarget
                        |> Maybe.map hasBoardingSpace
                        |> Maybe.withDefault False
            in
            (target.id /= unit.id)
                && receivingLoad units target drafts
                && not canBoardAtTarget

        unavailableReceivers : List Coordinate
        unavailableReceivers =
            destinationUnits units drafts
                |> List.filter unavailableReceiver
                |> List.filterMap Unit.mapPosition

        savedDestinations : List Coordinate
        savedDestinations =
            destinations ++ passengerExits

        destinations : List Coordinate
        destinations =
            List.map PlannedOrder.destination (List.filter reserves drafts)

        otherPassengerExits : PlannedOrder -> List Coordinate
        otherPassengerExits order =
            PlannedOrder.unloads order
                |> List.filter (\exit -> exit.unitId /= unit.id)
                |> List.map .destination

        passengerExits : List Coordinate
        passengerExits =
            List.concatMap otherPassengerExits drafts
    in
    savedDestinations ++ unavailableReceivers
