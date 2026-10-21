module Game.UnloadingTruck exposing
    ( UnloadingTruck
    , addCrateExit
    , addPassengerExit
    , destination
    , moving
    , stationary
    , toOrder
    , unitId
    )

import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder
    exposing
        ( MovePlan
        , PlannedOrder
        , StationaryUnload
        )
import Game.UnitId as UnitId exposing (UnitId)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| A pending truck order. All passenger and crate exits travel with its plan.
Only this module can change the moving/stationary representation.
-}
type UnloadingTruck
    = UnloadingTruck
        { truckId : UnitId
        , crateUnloads : List PlannedOrder.CrateUnload
        , plan : TruckPlan
        }


type TruckPlan
    = MovingTruck MovePlan
    | StationaryTruck StationaryUnload



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


moving : UnitId -> Movement.Option -> UnloadingTruck
moving id move =
    UnloadingTruck
        { truckId = id
        , crateUnloads = []
        , plan = MovingTruck { move = move, unloads = [] }
        }


stationary : UnitId -> Coordinate -> UnloadingTruck
stationary id position =
    UnloadingTruck
        { truckId = id
        , crateUnloads = []
        , plan = StationaryTruck { position = position, unloads = [] }
        }


unitId : UnloadingTruck -> UnitId
unitId (UnloadingTruck truck) =
    truck.truckId


destination : UnloadingTruck -> Coordinate
destination truck =
    PlannedOrder.destination (toOrder truck)


addPassengerExit : PlannedOrder.UnloadOrder -> UnloadingTruck -> UnloadingTruck
addPassengerExit exit (UnloadingTruck truck) =
    let
        plan : TruckPlan
        plan =
            case truck.plan of
                MovingTruck movingPlan ->
                    MovingTruck { movingPlan | unloads = movingPlan.unloads ++ [ exit ] }

                StationaryTruck stationaryPlan ->
                    StationaryTruck { stationaryPlan | unloads = stationaryPlan.unloads ++ [ exit ] }
    in
    UnloadingTruck { truck | plan = plan }


addCrateExit : PlannedOrder.CrateUnload -> UnloadingTruck -> UnloadingTruck
addCrateExit exit (UnloadingTruck truck) =
    UnloadingTruck { truck | crateUnloads = truck.crateUnloads ++ [ exit ] }


toOrder : UnloadingTruck -> PlannedOrder
toOrder (UnloadingTruck truck) =
    let
        action : PlannedOrder.Action
        action =
            case truck.plan of
                MovingTruck plan ->
                    PlannedOrder.Move plan

                StationaryTruck plan ->
                    if List.isEmpty plan.unloads then
                        PlannedOrder.Hold plan.position

                    else
                        PlannedOrder.Unload plan
    in
    if List.isEmpty truck.crateUnloads then
        { unitId = truck.truckId
        , action = action
        }

    else
        let
            order : PlannedOrder
            order =
                { unitId = truck.truckId
                , action = action
                }
        in
        { unitId = truck.truckId
        , action =
            PlannedOrder.SupplyTransfer
                { route = PlannedOrder.path order
                , destination = PlannedOrder.destination order
                , handling = PlannedOrder.UnloadingCrates truck.crateUnloads
                , passengers = PlannedOrder.unloads order
                }
        }
