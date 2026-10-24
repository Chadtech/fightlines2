module Game.PlannedOrder exposing
    ( Action(..)
    , AttackPlan
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
    , hold
    , isAttackMove
    , isMoving
    , loadingBerths
    , loadingCrates
    , path
    , toInput
    , unloadingCrates
    , unloads
    )

import Api.Enum.DepotKind exposing (DepotKind)
import Api.Enum.Direction exposing (Direction)
import Api.InputObject
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Movement as Movement
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.OptionalArgument as OptionalArgument exposing (OptionalArgument)


type alias PlannedOrder =
    { unitId : UnitId
    , action : Action
    }


type Action
    = Hold Coordinate
    | DigIn Coordinate
    | Sabotage Coordinate
    | Move MovePlan
    | AttackMove AttackPlan
    | Ambush Rotation
    | StandGround Rotation
    | IndirectFire Bombardment
    | Unload StationaryUnload
    | SupplyTransfer SupplyPlan


type alias AttackPlan =
    { move : Movement.Option
    , direction : Direction
    }


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
    | PickingUpGroundFreight DepotKind


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


{-| Hold at a unit's physical position, resolving passengers through their carrier.
A missing carrier or board position leaves no legal hold to construct.
-}
hold : List Unit -> Unit -> Maybe PlannedOrder
hold units unit =
    Unit.physicalPosition units unit
        |> Maybe.map
            (\position ->
                { unitId = unit.id
                , action = Hold position
                }
            )


destination : PlannedOrder -> Coordinate
destination order =
    case order.action of
        SupplyTransfer plan ->
            plan.destination

        IndirectFire fire ->
            fire.position

        StandGround facing ->
            facing.position

        Sabotage position ->
            position

        DigIn position ->
            position

        Hold position ->
            position

        AttackMove attack ->
            attack.move.destination

        Move plan ->
            plan.move.destination

        Ambush ambush ->
            ambush.position

        Unload plan ->
            plan.position


path : PlannedOrder -> List Coordinate
path order =
    case order.action of
        SupplyTransfer plan ->
            plan.route

        IndirectFire fire ->
            [ fire.position ]

        StandGround facing ->
            [ facing.position ]

        Sabotage position ->
            [ position ]

        DigIn position ->
            [ position ]

        Hold position ->
            [ position ]

        AttackMove attack ->
            attack.move.path

        Move plan ->
            plan.move.path

        Ambush ambush ->
            [ ambush.position ]

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

        Sabotage _ ->
            []

        DigIn _ ->
            []

        Hold _ ->
            []

        IndirectFire _ ->
            []

        StandGround _ ->
            []

        Ambush _ ->
            []


isMoving : PlannedOrder -> Bool
isMoving order =
    case order.action of
        SupplyTransfer plan ->
            List.length plan.route > 1

        Move plan ->
            List.length plan.move.path > 1

        AttackMove attack ->
            List.length attack.move.path > 1

        Sabotage _ ->
            False

        DigIn _ ->
            False

        Hold _ ->
            False

        IndirectFire _ ->
            False

        StandGround _ ->
            False

        Ambush _ ->
            False

        Unload _ ->
            False


{-| Convert a saved order to the existing wire contract at submission time.
Moving and stationary trucks can carry unloads; ambush and stand ground have a
required facing.
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

                IndirectFire _ ->
                    OptionalArgument.Absent

                StandGround facing ->
                    OptionalArgument.Present facing.direction

                Sabotage _ ->
                    OptionalArgument.Absent

                DigIn _ ->
                    OptionalArgument.Absent

                Hold _ ->
                    OptionalArgument.Absent

                AttackMove attack ->
                    OptionalArgument.Present attack.direction

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
                , digIn = OptionalArgument.Present (isDiggingIn order)
                , sabotage = OptionalArgument.Present (isSabotaging order)
                , standGround = OptionalArgument.Present (isStandingGround order)
                , ambush = OptionalArgument.Present (isAmbush order)
                , attackMove = OptionalArgument.Present (isAttackMove order)
                , loadCrates =
                    OptionalArgument.Present
                        (supplyPlan order
                            |> Maybe.map loadingCrates
                            |> Maybe.withDefault 0
                        )
                , pickupGroundFreight =
                    case supplyPlan order |> Maybe.map .handling of
                        Just (PickingUpGroundFreight kind) ->
                            OptionalArgument.Present kind

                        _ ->
                            OptionalArgument.Absent
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

        PickingUpGroundFreight _ ->
            0


{-| Ground pickup reserves one berth just like a depot load.
-}
loadingBerths : SupplyPlan -> Int
loadingBerths plan =
    case plan.handling of
        PickingUpGroundFreight _ ->
            1

        _ ->
            loadingCrates plan


unloadingCrates : SupplyPlan -> List CrateUnload
unloadingCrates plan =
    case plan.handling of
        UnloadingCrates exits ->
            exits

        LoadingCrates _ ->
            []

        PickingUpGroundFreight _ ->
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


isDiggingIn : PlannedOrder -> Bool
isDiggingIn order =
    case order.action of
        DigIn _ ->
            True

        _ ->
            False


isSabotaging : PlannedOrder -> Bool
isSabotaging order =
    case order.action of
        Sabotage _ ->
            True

        _ ->
            False
