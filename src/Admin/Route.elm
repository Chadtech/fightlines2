module Admin.Route exposing
    ( Route(..)
    , fromUrl
    , load
    , pushUrl
    , toString
    )

import Effect as E exposing (Eff)
import Game.LogId as GameLogId exposing (GameLogId)
import Url exposing (Url)
import Url.Parser as P exposing ((</>))


type Route
    = Dashboard
    | Replay GameLogId
    | SignOut


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse
        (P.s "admin"
            </> P.oneOf
                    [ P.map Dashboard P.top
                    , P.map Replay (P.s "recordings" </> P.custom "gameLogId" (GameLogId.parse >> Result.toMaybe))
                    , P.map SignOut (P.s "sign-out")
                    ]
        )


toString : Route -> String
toString route =
    case route of
        Dashboard ->
            "/admin"

        Replay id ->
            "/admin/recordings/" ++ GameLogId.toString id

        SignOut ->
            "/admin/sign-out"


load : Route -> Eff msg
load route =
    E.loadUrl (toString route)


pushUrl : Route -> Eff msg
pushUrl route =
    E.pushUrl (toString route)
