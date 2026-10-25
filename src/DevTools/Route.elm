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
    = BackdropReview
    | MapEditor
    | LoggedGames
    | Replay GameLogId


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse parser


parser : Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map BackdropReview (P.s "backdrop-review")
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
                LoggedGames ->
                    [ "logged-games" ]

                Replay id ->
                    [ "logged-games", GameLogId.toString id ]

                BackdropReview ->
                    [ "backdrop-review" ]

                MapEditor ->
                    [ "map-editor" ]
    in
    Url.Builder.absolute parts []
