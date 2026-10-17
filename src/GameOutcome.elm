module GameOutcome exposing
    ( GameOutcome(..)
    , selection
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.GameOutcome as OutcomeApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type GameOutcome
    = Victory PlayerNumber
    | Draw


selection : SelectionSet GameOutcome Api.Object.GameOutcome
selection =
    OutcomeApi.winner |> SS.map fromWinner


fromWinner : Maybe PlayerNumber -> GameOutcome
fromWinner winner =
    case winner of
        Just player ->
            Victory player

        Nothing ->
            Draw
