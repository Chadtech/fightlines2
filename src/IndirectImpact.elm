module IndirectImpact exposing (Attacker, IndirectImpact, selection)

import Api.Object
import Api.Object.IndirectFireAttacker as AttackerApi
import Api.Object.IndirectImpact as ImpactApi
import Coordinate exposing (Coordinate)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Unit exposing (Unit)
import Unit.HitPoints as HitPoints exposing (HitPoints)


type alias IndirectImpact =
    { destination : Coordinate
    , attacker : Maybe Attacker
    }


type alias Attacker =
    { unit : Unit
    , health : HitPoints
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
