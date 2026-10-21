module Game.DirectionPlanning exposing
    ( DirectionPlanning(..)
    , InvariantViolation(..)
    , StationaryPurpose(..)
    , ambush
    , attackMove
    , attackOrder
    , preview
    , standGround
    , stationaryOrder
    )

import Api.Enum.Direction as DirectionEnum exposing (Direction)
import Game.Direction as Direction
import Game.Movement as Movement
import Game.PlannedOrder as PlannedOrder exposing (PlannedOrder)
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import InvariantCheck as IC exposing (InvariantCheck)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type DirectionPlanning
    = Stationary StationaryPurpose Direction
    | AttackMove Movement.Option Direction


type StationaryPurpose
    = AmbushPurpose
    | StandGroundPurpose


type InvariantViolation
    = CommandUnitNotOnMap UnitId



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


ambush : Unit -> DirectionPlanning
ambush unit =
    Stationary AmbushPurpose (Maybe.withDefault DirectionEnum.North unit.direction)


standGround : Unit -> DirectionPlanning
standGround unit =
    Stationary StandGroundPurpose (Maybe.withDefault DirectionEnum.North unit.direction)


attackMove : Movement.Option -> Unit -> DirectionPlanning
attackMove move unit =
    AttackMove move (Direction.alongPath move.path unit.direction |> Maybe.withDefault DirectionEnum.North)


{-| Reverse attack facing is an unavailable choice, so it leaves the preview unchanged.
-}
preview : Direction -> DirectionPlanning -> DirectionPlanning
preview direction planning =
    case planning of
        Stationary purpose _ ->
            Stationary purpose direction

        AttackMove move _ ->
            if Direction.reversesPath move.path direction then
                planning

            else
                AttackMove move direction


{-| Stationary commands require a map position. A broken assumption retains no
order to save; the coordinator keeps the current drafts and selection.
-}
stationaryOrder :
    StationaryPurpose
    -> Unit
    -> Direction
    -> InvariantCheck InvariantViolation (Maybe PlannedOrder)
stationaryOrder purpose unit direction =
    case Unit.mapPosition unit of
        Just position ->
            let
                action : PlannedOrder.Action
                action =
                    case purpose of
                        AmbushPurpose ->
                            PlannedOrder.Ambush { position = position, direction = direction }

                        StandGroundPurpose ->
                            PlannedOrder.StandGround { position = position, direction = direction }
            in
            IC.happy
                (Just
                    { unitId = unit.id
                    , action = action
                    }
                )

        Nothing ->
            IC.violated (CommandUnitNotOnMap unit.id) Nothing


{-| The selected identity and confirmed route suffice to construct an attack
order. Reverse facing is an unavailable choice rather than an invariant violation.
-}
attackOrder : UnitId -> Movement.Option -> Direction -> Maybe PlannedOrder
attackOrder unitId move direction =
    if Direction.reversesPath move.path direction then
        Nothing

    else
        Just
            { unitId = unitId
            , action =
                PlannedOrder.AttackMove
                    { move = move
                    , direction = direction
                    }
            }
