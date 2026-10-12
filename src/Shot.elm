module Shot exposing (Shot, selection)

import Api.Enum.CombatKind exposing (CombatKind)
import Api.Object
import Api.Object.Shot as ShotApi
import CombatHealth exposing (CombatHealth)
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Unit exposing (Unit)


type alias Shot =
    { kind : CombatKind
    , origin : Coordinate
    , destination : Coordinate
    , attacker : Unit
    , target : Unit
    , damage : Int
    , attackerHealth : CombatHealth
    , targetHealth : CombatHealth
    }


selection : SelectionSet Shot Api.Object.Shot
selection =
    SS.succeed Shot
        |> SS.with ShotApi.kind
        |> SS.with (ShotApi.origin Coordinate.selection)
        |> SS.with (ShotApi.destination Coordinate.selection)
        |> SS.with (ShotApi.attacker Unit.selection)
        |> SS.with (ShotApi.target Unit.selection)
        |> SS.with ShotApi.damage
        |> SS.with (ShotApi.attackerHealth CombatHealth.selection)
        |> SS.with (ShotApi.targetHealth CombatHealth.selection)
