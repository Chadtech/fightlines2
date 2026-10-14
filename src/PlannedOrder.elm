module PlannedOrder exposing
    ( Action(..)
    , CrateUnload
    , MovePlan
    , PlannedOrder
    , Rotation
    , StationaryUnload
    , SupplyHandling(..)
    , SupplyPlan
    , UnloadOrder
    , crateUnloads
    , destination
    , isAttackMove
    , isMoving
    , loadingCrates
    , path
    , toInput
    , unloadingCrates
    , unloads
    )

import Api.Enum.Direction exposing (Direction)
import Api.InputObject
import Coordinate exposing (Coordinate)
import Graphql.OptionalArgument as OptionalArgument exposing (OptionalArgument)
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
    | StandGround Coordinate
    | IndirectFire Bombardment
    | Unload StationaryUnload
    | SupplyTransfer SupplyPlan


type alias Bombardment =
    { position : Coordinate
    , target : Coordinate
    }


type alias SupplyPlan =
    { route : List Coordinate
    , destination : Coordinate
    , handling : SupplyHandling
    , passengers : List UnloadOrder
    }


type SupplyHandling
    = LoadingCrates Int
    | UnloadingCrates (List CrateUnload)


type alias CrateUnload =
    { cargoIndex : Int
    , destination : Coordinate
    }


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
        SupplyTransfer plan ->
            plan.destination

        IndirectFire fire ->
            fire.position

        StandGround position ->
            position

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
        SupplyTransfer plan ->
            plan.route

        IndirectFire fire ->
            [ fire.position ]

        StandGround position ->
            [ position ]

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
        SupplyTransfer plan ->
            plan.passengers

        Move plan ->
            plan.unloads

        Unload plan ->
            plan.unloads

        AttackMove _ ->
            []

        Hold _ ->
            []

        IndirectFire _ ->
            []

        StandGround _ ->
            []

        Ambush _ ->
            []

        Rotate _ ->
            []


isMoving : PlannedOrder -> Bool
isMoving order =
    case order.action of
        SupplyTransfer plan ->
            List.length plan.route > 1

        Move plan ->
            List.length plan.move.path > 1

        AttackMove move ->
            List.length move.path > 1

        Hold _ ->
            False

        IndirectFire _ ->
            False

        StandGround _ ->
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

        crateUnloadInput : CrateUnload -> Api.InputObject.CrateUnloadInput
        crateUnloadInput unload =
            Api.InputObject.buildCrateUnloadInput
                { cargoIndex = unload.cargoIndex
                , destination = Api.InputObject.buildCoordinateInput unload.destination
                }

        direction : OptionalArgument Direction
        direction =
            case order.action of
                SupplyTransfer _ ->
                    OptionalArgument.Absent

                Ambush ambush ->
                    OptionalArgument.Present ambush.direction

                Rotate rotation ->
                    OptionalArgument.Present rotation.direction

                IndirectFire _ ->
                    OptionalArgument.Absent

                StandGround _ ->
                    OptionalArgument.Absent

                Hold _ ->
                    OptionalArgument.Absent

                AttackMove _ ->
                    OptionalArgument.Absent

                Move _ ->
                    OptionalArgument.Absent

                Unload _ ->
                    OptionalArgument.Absent
    in
    Api.InputObject.buildMoveOrderInput
        { unitId = UnitId.toString order.unitId
        , path = List.map Api.InputObject.buildCoordinateInput (path order)
        }
        (\optionals ->
            { optionals
                | unloads = OptionalArgument.Present (List.map unloadInput (unloads order))
                , direction = direction
                , indirectFire = indirectTarget order
                , standGround = OptionalArgument.Present (isStandingGround order)
                , ambush = OptionalArgument.Present (isAmbush order)
                , attackMove = OptionalArgument.Present (isAttackMove order)
                , loadCrates =
                    OptionalArgument.Present
                        (supplyPlan order
                            |> Maybe.map loadingCrates
                            |> Maybe.withDefault 0
                        )
                , crateUnloads =
                    OptionalArgument.Present
                        (supplyPlan order
                            |> Maybe.map (unloadingCrates >> List.map crateUnloadInput)
                            |> Maybe.withDefault []
                        )
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


supplyPlan : PlannedOrder -> Maybe SupplyPlan
supplyPlan order =
    case order.action of
        SupplyTransfer plan ->
            Just plan

        _ ->
            Nothing


crateUnloads : PlannedOrder -> List CrateUnload
crateUnloads order =
    supplyPlan order
        |> Maybe.map unloadingCrates
        |> Maybe.withDefault []


loadingCrates : SupplyPlan -> Int
loadingCrates plan =
    case plan.handling of
        LoadingCrates count ->
            count

        UnloadingCrates _ ->
            0


unloadingCrates : SupplyPlan -> List CrateUnload
unloadingCrates plan =
    case plan.handling of
        UnloadingCrates exits ->
            exits

        LoadingCrates _ ->
            []


isStandingGround : PlannedOrder -> Bool
isStandingGround order =
    case order.action of
        StandGround _ ->
            True

        _ ->
            False


indirectTarget : PlannedOrder -> OptionalArgument Api.InputObject.CoordinateInput
indirectTarget order =
    case order.action of
        IndirectFire fire ->
            OptionalArgument.Present (Api.InputObject.buildCoordinateInput fire.target)

        _ ->
            OptionalArgument.Absent
