module CombatHealth exposing (CombatHealth, selection)

import Api.Object
import Api.Object.CombatHealth as HealthApi
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Unit.HitPoints as HitPoints exposing (HitPoints)


type alias CombatHealth =
    { before : HitPoints
    , after : HitPoints
    }


selection : SelectionSet CombatHealth Api.Object.CombatHealth
selection =
    SS.succeed CombatHealth
        |> SS.with (HealthApi.before HitPoints.selection)
        |> SS.with (HealthApi.after HitPoints.selection)
