module PlannedOrder exposing
    ( Action(..)
    , MovePlan
    , PlannedOrder
    , Rotation
    , StationaryUnload
    , UnloadOrder
    , destination
    , isAttackMove
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
    | AttackMove Movement.Option
    | Rotate Rotation
    | Ambush Rotation
    | Unload StationaryUnload


type alias MovePlan =
    { move : Movement.Option
    , unloads : List UnloadOrder
    }


type alias StationaryUnload =
    { position : Coordinate
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

        AttackMove move ->
            move.destination

        Move plan ->
            plan.move.destination

        Ambush ambush ->
            ambush.position

        Rotate rotation ->
            rotation.position

        Unload plan ->
            plan.position


path : PlannedOrder -> List Coordinate
path order =
    case order.action of
        Hold position ->
            [ position ]

        AttackMove move ->
            move.path

        Move plan ->
            plan.move.path

        Ambush ambush ->
            [ ambush.position ]

        Rotate rotation ->
            [ rotation.position ]

        Unload plan ->
            [ plan.position ]


unloads : PlannedOrder -> List UnloadOrder
unloads order =
    case order.action of
        Move plan ->
            plan.unloads

        Unload plan ->
            plan.unloads

        AttackMove _ ->
            []

        Hold _ ->
            []

        Ambush _ ->
            []

        Rotate _ ->
            []


isMoving : PlannedOrder -> Bool
isMoving order =
    case order.action of
        Move plan ->
            List.length plan.move.path > 1

        AttackMove move ->
            List.length move.path > 1

        Hold _ ->
            False

        Ambush _ ->
            False

        Rotate _ ->
            False

        Unload _ ->
            False


{-| Convert a saved order to the existing wire contract at submission time.
Moving and stationary trucks can carry unloads; rotation has only a facing.
-}
toInput : PlannedOrder -> Api.InputObject.MoveOrderInput
toInput order =
    let
        unloadInput : UnloadOrder -> Api.InputObject.UnloadOrderInput
        unloadInput unload =
            Api.InputObject.buildUnloadOrderInput
                { unitId = UnitId.toString unload.unitId
                , destination =
                    Api.InputObject.buildCoordinateInput unload.destination
                }

        direction : OptionalArgument Direction
        direction =
            case order.action of
                Ambush ambush ->
                    Present ambush.direction

                Rotate rotation ->
                    Present rotation.direction

                Hold _ ->
                    Absent

                AttackMove _ ->
                    Absent

                Move _ ->
                    Absent

                Unload _ ->
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
                , ambush = Present (isAmbush order)
                , attackMove = Present (isAttackMove order)
            }
        )


isAmbush : PlannedOrder -> Bool
isAmbush order =
    case order.action of
        Ambush _ ->
            True

        _ ->
            False


isAttackMove : PlannedOrder -> Bool
isAttackMove order =
    case order.action of
        AttackMove _ ->
            True

        _ ->
            False
