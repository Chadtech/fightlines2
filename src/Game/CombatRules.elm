module Game.CombatRules exposing (CombatRules, selection)

import Api.Enum.AmbushShape exposing (AmbushShape)
import Api.Object
import Api.Object.CombatRules as RulesApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias CombatRules =
    { range : Int
    , indirectRange : Int
    , shape : AmbushShape
    , damage : Int
    , readinessCost : Int
    , digInCost : Int
    , shotCost : Int
    }


selection : SelectionSet CombatRules Api.Object.CombatRules
selection =
    SS.succeed CombatRules
        |> SS.with RulesApi.range
        |> SS.with RulesApi.indirectRange
        |> SS.with RulesApi.shape
        |> SS.with RulesApi.damage
        |> SS.with RulesApi.readinessCost
        |> SS.with RulesApi.digInCost
        |> SS.with RulesApi.shotCost
