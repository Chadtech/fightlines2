port module PlannedOrderChecks exposing (main)

import Api.Enum.Direction as Direction
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import PlannedOrder exposing (Action(..), PlannedOrder)
import Platform
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
    case ( UnitId.parse "1", UnitId.parse "2" ) of
        ( Ok unitId, Ok passengerId ) ->
            orderChecks unitId passengerId

        _ ->
            [ "could not construct order fixture IDs" ]


orderChecks : UnitId -> UnitId -> List String
orderChecks unitId passengerId =
    let
        hold : PlannedOrder
        hold =
            { unitId = unitId, action = Hold { x = 1, y = 1 } }

        rotation : PlannedOrder
        rotation =
            { unitId = unitId, action = Rotate { position = { x = 1, y = 1 }, direction = Direction.West } }

        move : PlannedOrder
        move =
            { unitId = unitId
            , action =
                Move
                    { move = { path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], destination = { x = 2, y = 1 }, cost = 2 }
                    , unloads = [ { unitId = passengerId, destination = { x = 2, y = 2 } } ]
                    }
            }

        stationaryUnload : PlannedOrder
        stationaryUnload =
            { unitId = unitId
            , action =
                Unload
                    { position = { x = 1, y = 1 }
                    , unloads = [ { unitId = passengerId, destination = { x = 1, y = 2 } } ]
                    }
            }
    in
    List.concat
        [ expect "hold submission must have one coordinate and no rotation or unloads"
            (PlannedOrder.toInput hold == { unitId = UnitId.toString unitId, path = [ { x = 1, y = 1 } ], direction = Absent, unloads = Present [] })
        , expect "rotation submission must be stationary and contain only its facing"
            (PlannedOrder.toInput rotation == { unitId = UnitId.toString unitId, path = [ { x = 1, y = 1 } ], direction = Present Direction.West, unloads = Present [] })
        , expect "move submission must preserve the route and passenger exit without adding rotation"
            (PlannedOrder.toInput move == { unitId = UnitId.toString unitId, path = [ { x = 1, y = 1 }, { x = 2, y = 1 } ], direction = Absent, unloads = Present [ { unitId = UnitId.toString passengerId, destination = { x = 2, y = 2 } } ] })
        , expect "only a traversed move may consume a boarding berth or count as a moving receiver"
            (not (PlannedOrder.isMoving hold) && not (PlannedOrder.isMoving rotation) && PlannedOrder.isMoving move && not (PlannedOrder.isMoving stationaryUnload))
        , expect "stationary trucks must retain their unload choices"
            (PlannedOrder.toInput stationaryUnload == { unitId = UnitId.toString unitId, path = [ { x = 1, y = 1 } ], direction = Absent, unloads = Present [ { unitId = UnitId.toString passengerId, destination = { x = 1, y = 2 } } ] })
        , expect "reservations must use the order destination and transport unload exits"
            (PlannedOrder.destination move == { x = 2, y = 1 } && PlannedOrder.destination rotation == { x = 1, y = 1 } && PlannedOrder.destination stationaryUnload == { x = 1, y = 1 } && PlannedOrder.unloads hold == [] && PlannedOrder.unloads rotation == [] && List.length (PlannedOrder.unloads move) == 1)
        ]


expect : String -> Bool -> List String
expect message condition =
    if condition then
        []

    else
        [ message ]
