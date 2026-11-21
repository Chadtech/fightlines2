module DevTools.Route exposing
    ( Route(..)
    , fromUrl
    , load
    , pushUrl
    , toString
    )

import Effect as E exposing (Eff)
import Game.LogId as GameLogId exposing (GameLogId)
import Url
    exposing
        ( Url
        )
import Url.Builder
import Url.Parser as P
    exposing
        ( (</>)
        , (<?>)
        , Parser
        )
import Url.Parser.Query as Query


type Route
    = Home
    | CombatChart
    | BackdropReview
    | MapEditor
    | LoggedGames RecordingQuery
    | Replay GameLogId RecordingQuery


type alias RecordingQuery =
    { recordingOffset : Int
    }


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse (P.s "dev" </> parser)


parser : Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map Home P.top
        , P.map CombatChart (P.s "combat-chart")
        , P.map BackdropReview (P.s "backdrop-review")
        , P.map LoggedGames (P.s "logged-games" <?> recordingQuery)
        , P.map Replay
            (P.s "logged-games"
                </> P.custom "gameLogId" (GameLogId.parse >> Result.toMaybe)
                <?> recordingQuery
            )
        , P.map MapEditor (P.s "map-editor")
        ]


recordingQuery : Query.Parser RecordingQuery
recordingQuery =
    Query.int "offset"
        |> Query.map (Maybe.withDefault 0 >> max 0 >> RecordingQuery)


load : Route -> Eff msg
load route =
    E.loadUrl (toString route)


pushUrl : Route -> Eff msg
pushUrl route =
    E.pushUrl (toString route)


toString : Route -> String
toString route =
    let
        parts : List String
        parts =
            case route of
                Home ->
                    []

                LoggedGames _ ->
                    [ "logged-games" ]

                Replay id _ ->
                    [ "logged-games", GameLogId.toString id ]

                CombatChart ->
                    [ "combat-chart" ]

                BackdropReview ->
                    [ "backdrop-review" ]

                MapEditor ->
                    [ "map-editor" ]

        offset : Int
        offset =
            case route of
                LoggedGames { recordingOffset } ->
                    recordingOffset

                Replay _ { recordingOffset } ->
                    recordingOffset

                _ ->
                    0

        query : List Url.Builder.QueryParameter
        query =
            if offset > 0 then
                [ Url.Builder.int "offset" offset ]

            else
                []
    in
    Url.Builder.absolute ("dev" :: parts) query
