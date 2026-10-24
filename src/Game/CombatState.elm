module Game.CombatState exposing (CombatState, orderLabel, selection)

import Api.Enum.DefenseReadiness exposing (DefenseReadiness)
import Api.Enum.UnitOrderKind as OrderKind exposing (UnitOrderKind)
import Api.Enum.WeaponReadiness exposing (WeaponReadiness)
import Api.Object
import Api.Object.CombatState as StateApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias CombatState =
    { order : UnitOrderKind
    , defense : DefenseReadiness
    , weapon : WeaponReadiness
    }


selection : SelectionSet CombatState Api.Object.CombatState
selection =
    SS.succeed CombatState
        |> SS.with StateApi.order
        |> SS.with StateApi.defense
        |> SS.with StateApi.weapon


orderLabel : UnitOrderKind -> String
orderLabel order =
    case order of
        OrderKind.Hold ->
            "hold position"

        OrderKind.Move ->
            "move"

        OrderKind.Rotate ->
            "change facing"

        OrderKind.AttackMove ->
            "attack move"

        OrderKind.Ambush ->
            "ambush"

        OrderKind.StandGround ->
            "stand ground"

        OrderKind.Sabotage ->
            "sabotage"

        OrderKind.DigIn ->
            "dig in"

        OrderKind.IndirectFire ->
            "indirect fire"
