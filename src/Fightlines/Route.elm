module Fightlines.Route exposing
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
    = Home
    | NewLobby
    | Lobby LobbyId
    | LobbyMaps LobbyId
    | Game LobbyId


fromUrl : Url -> Maybe Route
fromUrl =
    P.parse parser


parser : Parser (Route -> a) a
parser =
    P.oneOf
        [ P.map Home P.top
        , P.map NewLobby (P.s "new")
        , P.map LobbyMaps (P.s "lobby" </> P.custom "lobbyId" (LobbyId.fromString >> Result.toMaybe) </> P.s "maps")
        , P.map Lobby (P.s "lobby" </> P.custom "lobbyId" (LobbyId.fromString >> Result.toMaybe))
        , P.map Game (P.s "game" </> P.custom "lobbyId" (LobbyId.fromString >> Result.toMaybe))
        ]


toString : Route -> String
toString route =
    let
        parts : List String
        parts =
            case route of
                Home ->
                    []

                NewLobby ->
                    [ "new" ]

                Lobby id ->
                    [ "lobby", LobbyId.toString id ]

                LobbyMaps id ->
                    [ "lobby", LobbyId.toString id, "maps" ]

                Game id ->
                    [ "game", LobbyId.toString id ]
    in
    Url.Builder.absolute parts []
