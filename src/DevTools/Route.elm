module DevTools.Route exposing
    ( Route(..)
    , fromUrl
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
        , Parser
        )


type Route
    = Home
    | CombatChart
    | BackdropReview
    | MapEditor
    | LoggedGames
    | Replay GameLogId


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse (P.s "dev" </> parser)


parser : Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map Home P.top
        , P.map CombatChart (P.s "combat-chart")
        , P.map BackdropReview (P.s "backdrop-review")
        , P.map LoggedGames (P.s "logged-games")
        , P.map Replay (P.s "logged-games" </> P.custom "gameLogId" (GameLogId.parse >> Result.toMaybe))
        , P.map MapEditor (P.s "map-editor")
        ]


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

                LoggedGames ->
                    [ "logged-games" ]

                Replay id ->
                    [ "logged-games", GameLogId.toString id ]

                CombatChart ->
                    [ "combat-chart" ]

                BackdropReview ->
                    [ "backdrop-review" ]

                MapEditor ->
                    [ "map-editor" ]
    in
    Url.Builder.absolute ("dev" :: parts) []
