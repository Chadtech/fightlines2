module CombatRules exposing (CombatRules, selection)

import Api.Object
import Api.Object.CombatRules as RulesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias CombatRules =
    { range : Int
    , damage : Int
    , readinessCost : Int
    , shotCost : Int
    }


selection : SelectionSet CombatRules Api.Object.CombatRules
selection =
    SS.succeed CombatRules
        |> SS.with RulesApi.range
        |> SS.with RulesApi.damage
        |> SS.with RulesApi.readinessCost
        |> SS.with RulesApi.shotCost
