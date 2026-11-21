module DevTools.Page.LoggedGames exposing
    ( Flags
    , Model
    , init
    , load
    , setShared
    , view
    )

import Api.Object.RecordingsPage as RecordingsApi
import Api.Query
import ApiRequest
import DevTools.Route as Route
import Game.Archive as Archive exposing (Entry(..), Game)
import Game.LogId as GameLogId
import Game.MapId as MapId
import Graphql.Http
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import LocalTime
import Shared
import Style as S
import Time
import View.Aria as Aria
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { entries : List Entry
    , total : Int
    , nextOffset : Maybe Int
    , previousOffset : Maybe Int
    }


type alias Model =
    { shared : Shared.Model
    , offset : Int
    , entries : List Entry
    , total : Int
    , nextOffset : Maybe Int
    , previousOffset : Maybe Int
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Int -> Flags -> Model
init shared offset flags =
    { shared = shared
    , offset = offset
    , entries = flags.entries
    , total = flags.total
    , nextOffset = flags.nextOffset
    , previousOffset = flags.previousOffset
    }


load : Int -> Graphql.Http.Request Flags
load offset =
    SS.succeed Flags
        |> SS.with (RecordingsApi.entries Archive.entrySelection)
        |> SS.with RecordingsApi.total
        |> SS.with RecordingsApi.nextOffset
        |> SS.with RecordingsApi.previousOffset
        |> Api.Query.loggedGamesPage { offset = offset }
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


listLink : String -> Int -> Html msg
listLink label offset =
    H.a
        [ A.href
            (Route.toString (Route.LoggedGames { recordingOffset = offset }))
        , A.css [ S.link ]
        ]
        [ H.text label ]



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html msg)
view model =
    let
        entries : List (Html msg)
        entries =
            if model.total == 0 then
                [ H.p
                    [ Aria.role Aria.Status ]
                    [ H.text "no logged games yet." ]
                ]

            else if List.isEmpty model.entries then
                [ H.p
                    [ Aria.role Aria.Status ]
                    [ H.text "no logged games on this page." ]
                ]

            else
                List.map (entryRow model.offset model.shared.timeZone)
                    model.entries

        links : List (Html msg)
        links =
            List.filterMap identity
                [ Maybe.map (listLink "newer games") model.previousOffset
                , Maybe.map (listLink "older games") model.nextOffset
                ]

        refresh : Html msg
        refresh =
            listLink "refresh" model.offset

        controls : Html msg
        controls =
            H.nav
                [ A.css
                    [ S.row
                    , S.g3
                    , S.flexWrap
                    ]
                ]
                (refresh :: links)

        content : List (Html msg)
        content =
            controls :: entries
    in
    [ Card.toHtml
        (Card.simple
            |> Card.withHeader (CardHeader.simple "logged games")
        )
        content
    ]


entryRow : Int -> Time.Zone -> Entry -> Html msg
entryRow offset zone entry =
    let
        content : List (Html msg)
        content =
            case entry of
                Readable game ->
                    gameContent offset zone game

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


gameContent : Int -> Time.Zone -> Game -> List (Html msg)
gameContent offset zone game =
    [ H.h2
        []
        [ H.text game.name ]
    , H.p
        []
        [ H.text (LocalTime.timestampLabel zone game.startedAt ++ " · " ++ MapId.label game.mapType) ]
    , H.p
        []
        [ H.text (String.join " · " (List.map Archive.playerLabel game.players)) ]
    , H.p
        []
        [ H.text (String.fromInt game.turnCount ++ " completed turns · " ++ Archive.statusLabel game.status) ]
    , H.a
        [ A.href
            (Route.toString (Route.Replay game.id { recordingOffset = offset }))
        , A.css [ S.link ]
        ]
        [ H.text "replay game" ]
    ]
