module DevTools.Page.LoggedGames exposing
    ( Flags
    , Game
    , Model
    , init
    , load
    , selection
    , setShared
    , view
    )

import Api.Object
import Api.Query
import ApiRequest
import DevTools.Route as Route
import Game.Archive as Archive exposing (Entry(..))
import Game.LogId as GameLogId
import Game.MapId as MapId
import Graphql.Http
import Graphql.SelectionSet exposing (SelectionSet)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Shared
import Style as S
import View.Aria as Aria
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Game =
    Archive.Game


type alias Flags =
    List Entry


type alias Model =
    { shared : Shared.Model
    , entries : List Entry
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared entries =
    { shared = shared
    , entries = entries
    }


load : Graphql.Http.Request Flags
load =
    Api.Query.loggedGames Archive.entrySelection |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


selection : SelectionSet Game Api.Object.LoggedGame
selection =
    Archive.selection



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html msg)
view model =
    let
        entries : List (Html msg)
        entries =
            if List.isEmpty model.entries then
                [ H.p
                    [ Aria.role Aria.Status ]
                    [ H.text "no logged games yet." ]
                ]

            else
                List.map entryRow model.entries

        content : List (Html msg)
        content =
            [ H.nav
                [ A.css
                    [ S.row
                    , S.g3
                    , S.flexWrap
                    ]
                ]
                [ H.a
                    [ A.href (Route.toString Route.LoggedGames)
                    , A.css [ S.link ]
                    ]
                    [ H.text "refresh" ]
                ]
            ]
                ++ entries
    in
    [ Card.toHtml
        (Card.simple
            |> Card.withHeader (CardHeader.simple "logged games")
        )
        content
    ]


entryRow : Entry -> Html msg
entryRow entry =
    let
        content : List (Html msg)
        content =
            case entry of
                Readable game ->
                    gameContent game

                Unreadable error ->
                    [ H.h2
                        []
                        [ H.text (GameLogId.toString error.id) ]
                    , H.p
                        [ Aria.role Aria.Status ]
                        [ H.text ("unable to read this game: " ++ error.message) ]
                    ]
    in
    H.article
        [ A.css
            [ S.col
            , S.g2
            , S.borderT
            , S.borderGray2
            , S.pt3
            , S.wrapAnywhere
            ]
        ]
        content


gameContent : Game -> List (Html msg)
gameContent game =
    [ H.h2
        []
        [ H.text game.name ]
    , H.p
        []
        [ H.text (Archive.startedAtLabel game.startedAt ++ " · " ++ MapId.label game.mapType) ]
    , H.p
        []
        [ H.text (String.join " · " (List.map Archive.playerLabel game.players)) ]
    , H.p
        []
        [ H.text (String.fromInt game.turnCount ++ " completed turns · " ++ Archive.statusLabel game.status) ]
    , H.a
        [ A.href (Route.toString (Route.Replay game.id))
        , A.css [ S.link ]
        ]
        [ H.text "replay game" ]
    ]
