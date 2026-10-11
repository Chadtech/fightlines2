module PlannedOrder exposing
    ( Action(..)
    , MovePlan
    , PlannedOrder
    , Rotation
    , UnloadOrder
    , destination
    , isMoving
    , path
    , toInput
    , unloads
    )

import Api.Enum.Direction exposing (Direction)
import Api.InputObject
import Coordinate exposing (Coordinate)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Movement
import UnitId exposing (UnitId)


type alias PlannedOrder =
    { unitId : UnitId
    , action : Action
    }


type Action
    = Hold Coordinate
    | Move MovePlan
    | Rotate Rotation


type alias MovePlan =
    { move : Movement.Option
    , unloads : List UnloadOrder
    }


type alias Rotation =
    { position : Coordinate
    , direction : Direction
    }


type alias UnloadOrder =
    { unitId : UnitId
    , destination : Coordinate
    }


destination : PlannedOrder -> Coordinate
destination order =
    case order.action of
        Hold position ->
            position

        Move plan ->
            plan.move.destination

        Rotate rotation ->
            rotation.position


path : PlannedOrder -> List Coordinate
path order =
    case order.action of
        Hold position ->
            [ position ]

        Move plan ->
            plan.move.path

        Rotate rotation ->
            [ rotation.position ]


unloads : PlannedOrder -> List UnloadOrder
unloads order =
    case order.action of
        Move plan ->
            plan.unloads

        Hold _ ->
            []

        Rotate _ ->
            []


isMoving : PlannedOrder -> Bool
isMoving order =
    case order.action of
        Move plan ->
            List.length plan.move.path > 1

        Hold _ ->
            False

        Rotate _ ->
            False


{-| Convert a saved order to the existing wire contract at submission time.
Only movement can carry unloads; rotation always uses a stationary path.
-}
toInput : PlannedOrder -> Api.InputObject.MoveOrderInput
toInput order =
    let
        unloadInput : UnloadOrder -> Api.InputObject.UnloadOrderInput
        unloadInput unload =
            Api.InputObject.buildUnloadOrderInput
                { unitId = UnitId.toString unload.unitId
                , destination = Api.InputObject.buildCoordinateInput unload.destination
                }

        direction : OptionalArgument Direction
        direction =
            case order.action of
                Rotate rotation ->
                    Present rotation.direction

                Hold _ ->
                    Absent

                Move _ ->
                    Absent
    in
    Api.InputObject.buildMoveOrderInput
        { unitId = UnitId.toString order.unitId
        , path = List.map Api.InputObject.buildCoordinateInput (path order)
        }
        (\optionals ->
            { optionals
                | unloads = Present (List.map unloadInput (unloads order))
                , direction = direction
            }
        )
