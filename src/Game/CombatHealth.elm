module Game.CombatHealth exposing (CombatHealth, selection)

import Api.Object
import Api.Object.CombatHealth as HealthApi
import Game.Unit.HitPoints as HitPoints exposing (HitPoints)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias CombatHealth =
    { before : HitPoints
    , after : HitPoints
    }


selection : SelectionSet CombatHealth Api.Object.CombatHealth
selection =
    SS.succeed CombatHealth
        |> SS.with (HealthApi.before HitPoints.selection)
        |> SS.with (HealthApi.after HitPoints.selection)
