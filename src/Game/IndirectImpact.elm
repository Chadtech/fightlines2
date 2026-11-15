module Game.IndirectImpact exposing
    ( Attacker
    , BuildingImpact
    , IndirectImpact
    , Target
    , destroyedUnitId
    , selection
    )

import Api.Enum.BuildingKind exposing (BuildingKind)
import Api.Object
import Api.Object.BuildingImpact as BuildingImpactApi
import Api.Object.IndirectFireAttacker as AttackerApi
import Api.Object.IndirectFireTarget as TargetApi
import Api.Object.IndirectImpact as ImpactApi
import Game.Building as Building
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Unit as Unit exposing (Unit)
import Game.Unit.HitPoints as HitPoints exposing (HitPoints)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias IndirectImpact =
    { destination : Coordinate
    , attacker : Maybe Attacker
    , target : Maybe Target
    , building : Maybe BuildingImpact
    }


type alias BuildingImpact =
    { kind : BuildingKind
    , before : Building.Hp
    , after : Building.Hp
    }


type alias Attacker =
    { unit : Unit
    , health : HitPoints
    }


type alias Target =
    { unit : Unit
    , health : CombatHealth
    }


selection : SelectionSet IndirectImpact Api.Object.IndirectImpact
selection =
    SS.succeed IndirectImpact
        |> SS.with (ImpactApi.destination Coordinate.selection)
        |> SS.with
            (ImpactApi.attacker
                (SS.succeed Attacker
                    |> SS.with (AttackerApi.unit Unit.selection)
                    |> SS.with (AttackerApi.health HitPoints.selection)
                )
            )
        |> SS.with
            (ImpactApi.target
                (SS.succeed Target
                    |> SS.with (TargetApi.unit Unit.selection)
                    |> SS.with (TargetApi.health CombatHealth.selection)
                )
            )
        |> SS.with (ImpactApi.building buildingSelection)


buildingSelection : SelectionSet BuildingImpact Api.Object.BuildingImpact
buildingSelection =
    SS.succeed BuildingImpact
        |> SS.with BuildingImpactApi.kind
        |> SS.with (BuildingImpactApi.before Building.hpSelection)
        |> SS.with (BuildingImpactApi.after Building.hpSelection)


{-| Read the target transition from either a projected shell or a merged landing.
-}
destroyedUnitId : { impact | target : Maybe Target } -> Maybe UnitId
destroyedUnitId impact =
    case impact.target of
        Just target ->
            if (target.health.before.current > 0) && (target.health.after.current == 0) then
                Just target.unit.id

            else
                Nothing

        Nothing ->
            Nothing
