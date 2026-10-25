module Game.Outcome exposing
    ( GameOutcome(..)
    , isResignation
    , selection
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.GameOutcome as OutcomeApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type GameOutcome
    = Victory PlayerNumber
    | Resignation PlayerNumber
    | Draw


selection : SelectionSet GameOutcome Api.Object.GameOutcome
selection =
    SS.succeed fromResult
        |> SS.with OutcomeApi.winner
        |> SS.with OutcomeApi.resigned


fromResult : Maybe PlayerNumber -> Bool -> GameOutcome
fromResult winner resigned =
    case winner of
        Just player ->
            if resigned then
                Resignation player

            else
                Victory player

        Nothing ->
            Draw


isResignation : Maybe GameOutcome -> Bool
isResignation outcome =
    case outcome of
        Just (Resignation _) ->
            True

        _ ->
            False
