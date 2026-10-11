port module OrderPlanningChecks exposing (main)

import Api.Enum.Direction as Facing
import Api.Enum.MapTheme as Theme
import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Coordinate exposing (Coordinate)
import GamePage.OrderPlanning as OrderPlanning
import GamePage.Selection exposing (DestinationFeedback(..), Inspection(..), Selection(..))
import Movement
import PlannedOrder
import Platform
import TurnLifecycle
import Unit exposing (Unit)
import Unit.Location as Location exposing (Location)
import UnitCommand
import UnitId exposing (UnitId)


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    case ( UnitId.parse "1", UnitId.parse "2", UnitId.parse "3" ) of
        ( Ok infantryId, Ok truckId, Ok passengerId ) ->
            planningChecks infantryId truckId passengerId

        _ ->
            [ "could not construct planning fixture IDs" ]


planningChecks : UnitId -> UnitId -> UnitId -> List String
planningChecks infantryId truckId passengerId =
    let
        infantry : Unit
        infantry =
            unit infantryId Kind.Infantry (Location.OnMap { x = 1, y = 1 })

        truck : Unit
        truck =
            unit truckId Kind.Truck (Location.OnMap { x = 3, y = 1 })

        context : OrderPlanning.Context
        context =
            board [ infantry, truck ]

        moving : OrderPlanning.Model
        moving =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.extendPath context Facing.South

        saved : OrderPlanning.Model
        saved =
            OrderPlanning.confirmPath context moving

        reserved : OrderPlanning.Model
        reserved =
            saved
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 1, y = 2 }

        loading : OrderPlanning.Model
        loading =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Move
                |> OrderPlanning.selectTile context { x = 3, y = 1 }

        receiving : OrderPlanning.Model
        receiving =
            OrderPlanning.selectUnit context truckId loading

        revoked : OrderPlanning.Model
        revoked =
            loading
                |> OrderPlanning.revokeSelectedOrder context
                |> OrderPlanning.selectUnit context truckId
                |> OrderPlanning.revokeSelectedOrder context

        rotated : OrderPlanning.Model
        rotated =
            OrderPlanning.init
                |> OrderPlanning.selectUnit context infantryId
                |> OrderPlanning.applyCommand context UnitCommand.Rotate
                |> OrderPlanning.previewRotation Facing.West
                |> OrderPlanning.saveRotation context Facing.West

        cargoContext : OrderPlanning.Context
        cargoContext =
            board
                [ truck
                , unit infantryId Kind.Infantry (Location.Aboard truckId)
                , unit passengerId Kind.FieldGun (Location.Aboard truckId)
                ]

        checklist : OrderPlanning.Model
        checklist =
            OrderPlanning.init
                |> OrderPlanning.selectUnit cargoContext truckId
                |> OrderPlanning.applyCommand cargoContext UnitCommand.HoldPosition

        exits : OrderPlanning.Model
        exits =
            checklist
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.toggleUnloadPassenger passengerId True
                |> OrderPlanning.confirmPassengers cargoContext

        firstExit : OrderPlanning.Model
        firstExit =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } exits

        rejectedExit : OrderPlanning.Model
        rejectedExit =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 3, y = 2 } firstExit

        completed : OrderPlanning.Model
        completed =
            OrderPlanning.chooseUnloadSquare cargoContext { x = 4, y = 1 } rejectedExit

        truckMove : OrderPlanning.Model
        truckMove =
            OrderPlanning.init
                |> OrderPlanning.selectUnit cargoContext truckId
                |> OrderPlanning.applyCommand cargoContext UnitCommand.Move
                |> OrderPlanning.selectTile cargoContext { x = 4, y = 1 }
                |> OrderPlanning.toggleUnloadPassenger infantryId True
                |> OrderPlanning.confirmPassengers cargoContext
                |> OrderPlanning.chooseUnloadSquare cargoContext { x = 5, y = 1 }

        submitted : TurnLifecycle.Phase
        submitted =
            TurnLifecycle.startSubmission 1 (TurnLifecycle.Planning saved)

        ordersForSubmission : List PlannedOrder.PlannedOrder
        ordersForSubmission =
            OrderPlanning.submissionOrders cargoContext (OrderPlanning.orders completed)
    in
    List.concat
        [ expect "path confirmation saves the traced route and closes editing"
            (List.map PlannedOrder.path (OrderPlanning.orders saved) == [ [ { x = 1, y = 1 }, { x = 1, y = 2 } ] ] && OrderPlanning.pathPreview saved == Nothing)
        , expect "another unit cannot claim a reserved destination and receives feedback"
            (OrderPlanning.orders reserved == OrderPlanning.orders saved && OrderPlanning.destinationFeedback reserved == DestinationUnavailable)
        , expect "loading saves the mover and a holding receiver"
            (List.length (OrderPlanning.orders loading) == 2 && OrderPlanning.receivingLoad context truck (OrderPlanning.orders loading))
        , expect "a receiving truck is inspection only"
            (OrderPlanning.commandMenuUnit context receiving == Nothing && OrderPlanning.selection receiving == Just (Inspecting (UnitInspection truckId)))
        , expect "revoking loading and receiver holds restores truck commands"
            (List.isEmpty (OrderPlanning.orders revoked) && OrderPlanning.commandMenuUnit context revoked == Just truck)
        , expect "rotation becomes a revocable draft without moving"
            (List.map .action (OrderPlanning.orders rotated) == [ PlannedOrder.Rotate { position = { x = 1, y = 1 }, direction = Facing.West } ])
        , expect "holding a loaded truck opens its stationary unload checklist"
            (OrderPlanning.unloadChoice checklist /= Nothing)
        , expect "each unload exit reserves its square for the next passenger"
            (OrderPlanning.orders firstExit == OrderPlanning.orders rejectedExit && OrderPlanning.destinationFeedback rejectedExit == DestinationUnavailable)
        , expect "stationary unloading completes with both passengers and releases the workflow"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders completed) == [ { unitId = infantryId, destination = { x = 3, y = 2 } }, { unitId = passengerId, destination = { x = 4, y = 1 } } ] && OrderPlanning.unloadPlanning completed == Nothing)
        , expect "moving truck exits use the planned truck destination"
            (List.concatMap PlannedOrder.unloads (OrderPlanning.orders truckMove) == [ { unitId = infantryId, destination = { x = 5, y = 1 } } ])
        , expect "cargo needs no explicit ready order but receives holds for submission"
            (List.isEmpty (OrderPlanning.missingOrders cargoContext (OrderPlanning.orders completed)) && List.length ordersForSubmission == 3)
        , expect "lifecycle gating prevents editing submitted drafts"
            (TurnLifecycle.mapPlanning (OrderPlanning.selectTile context { x = 2, y = 2 }) submitted == submitted)
        ]


board : List Unit -> OrderPlanning.Context
board units =
    { map = { width = 7, height = 7, baseTile = Terrain.GrassPlain, theme = Theme.GreenForest, features = [] }
    , units = units
    , movementRules = List.map movementRule [ Kind.Infantry, Kind.Truck, Kind.FieldGun ]
    , playerSides = [ Side.Player1 ]
    }


movementRule : UnitKind -> Movement.Rule
movementRule kind =
    { kind = kind, budget = 12, terrainCosts = [ { terrain = Terrain.GrassPlain, cost = 2 } ] }


unit : UnitId -> UnitKind -> Location -> Unit
unit id kind location =
    let
        vehicle : Bool
        vehicle =
            kind == Kind.Truck

        direction : Maybe Facing.Direction
        direction =
            if vehicle then
                Nothing

            else
                Just Facing.North

        fuel : Maybe { current : Int, maximum : Int }
        fuel =
            if vehicle then
                Just { current = 64, maximum = 64 }

            else
                Nothing

        capacity : Int
        capacity =
            if vehicle then
                2

            else
                0
    in
    { id = id
    , side = Side.Player1
    , kind = kind
    , direction = direction
    , hitPoints = { current = 16, maximum = 16 }
    , supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }
    , fuel = fuel
    , cargoCapacity = capacity
    , location = location
    }


expect : String -> Bool -> List String
expect label condition =
    if condition then
        []

    else
        [ label ]
