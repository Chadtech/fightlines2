module Route exposing
    ( Route(..)
    , fromUrl
    , toString
    )

import LobbyId
    exposing
        ( LobbyId
        )
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
    = NewLobby
    | Lobby LobbyId
    | Game LobbyId


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse parser


parser : Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map NewLobby P.top
        , P.map Lobby (P.s "lobby" </> P.custom "lobbyId" (LobbyId.fromString >> Result.toMaybe))
        , P.map Game (P.s "game" </> P.custom "lobbyId" (LobbyId.fromString >> Result.toMaybe))
        ]


toString : Route -> String
toString route =
    let
        parts : List String
        parts =
            case route of
                NewLobby ->
                    []

                Lobby id ->
                    [ "lobby", LobbyId.toString id ]

                Game id ->
                    [ "game", LobbyId.toString id ]
    in
    Url.Builder.absolute parts []
