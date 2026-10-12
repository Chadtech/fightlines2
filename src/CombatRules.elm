module CombatRules exposing (CombatRules, selection)

import Api.Enum.AmbushShape exposing (AmbushShape)
import Api.Object
import Api.Object.CombatRules as RulesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias CombatRules =
    { range : Int
    , shape : AmbushShape
    , damage : Int
    , readinessCost : Int
    , shotCost : Int
    }


selection : SelectionSet CombatRules Api.Object.CombatRules
selection =
    SS.succeed CombatRules
        |> SS.with RulesApi.range
        |> SS.with RulesApi.shape
        |> SS.with RulesApi.damage
        |> SS.with RulesApi.readinessCost
        |> SS.with RulesApi.shotCost
