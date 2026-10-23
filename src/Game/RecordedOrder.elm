module Game.RecordedOrder exposing (RecordedOrder, selection)

import Api.Enum.Direction exposing (Direction)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitOrderKind exposing (UnitOrderKind)
import Api.Object
import Api.Object.RecordedOrder as OrderApi
import Api.Object.RecordedUnload as UnloadApi
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.UnitId as UnitId exposing (UnitId)
import Graphql.SelectionSet as SS exposing (SelectionSet)


type alias RecordedOrder =
    { unitId : UnitId
    , playerNumber : PlayerNumber
    , kind : UnitOrderKind
    , path : List Coordinate
    , direction : Maybe Direction
    , target : Maybe Coordinate
    , unloads : List Coordinate
    , stoppedAt : Maybe Coordinate
    }


selection : SelectionSet RecordedOrder Api.Object.RecordedOrder
selection =
    SS.succeed RecordedOrder
        |> SS.with (OrderApi.unitId |> SS.mapOrFail UnitId.parse)
        |> SS.with OrderApi.playerNumber
        |> SS.with OrderApi.kind
        |> SS.with (OrderApi.path Coordinate.selection)
        |> SS.with OrderApi.direction
        |> SS.with (OrderApi.target Coordinate.selection)
        |> SS.with (OrderApi.unloads (UnloadApi.destination Coordinate.selection))
        |> SS.with (OrderApi.stoppedAt Coordinate.selection)
