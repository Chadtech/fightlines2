module Game.Outcome exposing
    ( GameOutcome(..)
    , interruptsPlayback
    , selection
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.GameOutcome as OutcomeApi
import Graphql.SelectionSet as SS exposing (SelectionSet)


type GameOutcome
    = Victory PlayerNumber
    | Resignation PlayerNumber
    | Inactivity (Maybe PlayerNumber)
    | Draw


type alias OutcomeDetails =
    { winner : Maybe PlayerNumber
    , resigned : Bool
    , inactive : Bool
    }


selection : SelectionSet GameOutcome Api.Object.GameOutcome
selection =
    SS.succeed OutcomeDetails
        |> SS.with OutcomeApi.winner
        |> SS.with OutcomeApi.resigned
        |> SS.with OutcomeApi.inactive
        |> SS.map fromResult


fromResult : OutcomeDetails -> GameOutcome
fromResult details =
    if details.inactive then
        Inactivity details.winner

    else
        case details.winner of
            Just player ->
                if details.resigned then
                    Resignation player

                else
                    Victory player

            Nothing ->
                Draw


interruptsPlayback : Maybe GameOutcome -> Bool
interruptsPlayback outcome =
    case outcome of
        Just (Resignation _) ->
            True

        Just (Inactivity _) ->
            True

        _ ->
            False
