module Game.UnitStats exposing (UnitStats, selection)

import Api.Object
import Api.Object.UnitStats as StatsApi
import Game.CombatRules as CombatRules exposing (CombatRules)
import Game.Movement as Movement
import Game.Unit.Fuel as Fuel exposing (Fuel)
import Game.Unit.Supplies as Supplies exposing (Supplies)
import Graphql.SelectionSet as SS exposing (SelectionSet)


{-| Public type statistics, never a unit's current or concealed resources.
-}
type alias UnitStats =
    { movement : Movement.Rule
    , supplies : Supplies
    , fuel : Maybe Fuel
    , combat : CombatRules
    , maximumHitPoints : Int
    , cargoCapacity : Int
    }


selection : SelectionSet UnitStats Api.Object.UnitStats
selection =
    SS.succeed UnitStats
        |> SS.with (StatsApi.movement Movement.ruleSelection)
        |> SS.with (StatsApi.supplies Supplies.selection)
        |> SS.with (StatsApi.fuel Fuel.selection)
        |> SS.with (StatsApi.combat CombatRules.selection)
        |> SS.with StatsApi.maximumHitPoints
        |> SS.with StatsApi.cargoCapacity
