module LobbyPage exposing
    ( Flags
    , Model
    , Msg
    , init
    , listeners
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.MapType
    exposing
        ( MapType
        )
import Api.Mutation
import Api.Object
import Api.Object.PlayerView as PlayerView
import Api.Object.Snapshot as Snapshot
import Api.Query
import ApiRequest
    exposing
        ( Response
        )
import Effect as E
    exposing
        ( Eff
        )
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import LobbyId
    exposing
        ( LobbyId
        )
import MapType
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import Route
import Shared
import Style as S
import Time
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { id : LobbyId
    , name : String
    , mapType : MapType
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    }


type alias Player =
    { name : String
    , isHost : Bool
    }


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , name : String
    , mapType : MapType
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    , selectedMapType : MapType
    , mapStatus : MapStatus
    , busy : Bool
    , refreshing : Bool
    , error : Maybe String
    , actionError : Maybe String
    , copyStatus : CopyStatus
    }


type MapStatus
    = MapIdle
    | MapSaving
    | MapSaved


type CopyStatus
    = CopyIdle
    | Copying
    | Copied
    | CopyFailed


type alias CopyResult =
    { url : String
    , success : Bool
    }


type Msg
    = MapInputChanged MapType
    | SaveMapButtonClicked
    | MapResponseReceived (Response Flags)
    | StartButtonClicked
    | RetryButtonClicked
    | CopyLinkButtonClicked
    | CopyLinkResultReceived CopyResult
    | CopyFeedbackElapsed
    | PollTimerElapsed Time.Posix
    | LobbyResponseReceived (Response Flags)
    | ActionResponseReceived (Response Flags)



----------------------------------------------------------------
-- SHARED STATE --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> ( Model, Eff Msg )
init shared flags =
    ( { shared = shared
      , id = flags.id
      , name = flags.name
      , mapType = flags.mapType
      , selectedMapType = flags.mapType
      , mapStatus = MapIdle
      , players = flags.players
      , isHost = flags.isHost
      , isMember = flags.isMember
      , gameUrl = flags.gameUrl
      , busy = False
      , refreshing = False
      , error = Nothing
      , actionError = Nothing
      , copyStatus = CopyIdle
      }
    , gameNavigation
        { isMember = flags.isMember
        , gameUrl = flags.gameUrl
        }
        flags.id
    )


load : LobbyId -> Graphql.Http.Request Flags
load id =
    Api.Query.lobby { id = LobbyId.toString id } flagsSelection
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


start : LobbyId -> Graphql.Http.Request Flags
start id =
    Api.Mutation.startGame { id = LobbyId.toString id } flagsSelection
        |> ApiRequest.mutationRequest


flagsSelection : SelectionSet Flags Api.Object.Snapshot
flagsSelection =
    SS.map7 Flags
        (Snapshot.id |> SS.mapOrFail LobbyId.parse)
        Snapshot.name
        Snapshot.mapType
        (Snapshot.players (SS.map2 Player PlayerView.name PlayerView.isHost))
        Snapshot.isHost
        Snapshot.isMember
        Snapshot.gameUrl



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        MapInputChanged mapType ->
            ( { model
                | selectedMapType = mapType
                , mapStatus = MapIdle
              }
            , E.none
            )

        SaveMapButtonClicked ->
            if model.busy || model.refreshing || not model.isHost || model.gameUrl /= Nothing then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , actionError = Nothing
                    , mapStatus = MapSaving
                  }
                , Api.Mutation.setLobbyMap
                    { id = LobbyId.toString model.id
                    , mapType = model.selectedMapType
                    }
                    flagsSelection
                    |> ApiRequest.mutationRequest
                    |> E.request MapResponseReceived
                )

        MapResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | busy = False
                        , actionError = Nothing
                        , mapStatus = MapSaved
                    }
                        |> receive flags

                Err error ->
                    ( { model
                        | busy = False
                        , actionError = Just (ApiRequest.errorMessage error)
                        , mapStatus = MapIdle
                      }
                    , E.none
                    )

        StartButtonClicked ->
            if model.busy || model.refreshing || List.length model.players /= 2 then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , actionError = Nothing
                  }
                , E.request ActionResponseReceived (start model.id)
                )

        RetryButtonClicked ->
            refresh model

        CopyLinkButtonClicked ->
            if model.copyStatus == Copying || model.copyStatus == Copied then
                ( model, E.none )

            else
                ( { model | copyStatus = Copying }
                , E.toJs (ToJs.CopyLink (inviteUrl model))
                )

        CopyLinkResultReceived result ->
            if result.url /= inviteUrl model || model.copyStatus /= Copying then
                ( model, E.none )

            else if result.success then
                ( { model | copyStatus = Copied }
                , E.after 2000 CopyFeedbackElapsed
                )

            else
                ( { model | copyStatus = CopyFailed }, E.none )

        CopyFeedbackElapsed ->
            ( { model | copyStatus = CopyIdle }, E.none )

        PollTimerElapsed _ ->
            refresh model

        LobbyResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | refreshing = False
                    }
                        |> receive flags

                Err error ->
                    { model
                        | refreshing = False
                        , error = Just (ApiRequest.errorMessage error)
                    }
                        |> E.withOut

        ActionResponseReceived result ->
            case result of
                Ok flags ->
                    { model
                        | busy = False
                        , actionError = Nothing
                    }
                        |> receive flags

                Err error ->
                    ( { model
                        | busy = False
                        , actionError = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )


refresh : Model -> ( Model, Eff Msg )
refresh model =
    if model.refreshing || model.busy then
        ( model, E.none )

    else
        ( { model
            | refreshing = True
          }
        , E.request LobbyResponseReceived (load model.id)
        )


receive : Flags -> Model -> ( Model, Eff Msg )
receive flags model =
    ( { model
        | id = flags.id
        , name = flags.name
        , mapType = flags.mapType
        , players = flags.players
        , isHost = flags.isHost
        , isMember = flags.isMember
        , gameUrl = flags.gameUrl
        , error = Nothing
      }
    , gameNavigation
        { isMember = flags.isMember
        , gameUrl = flags.gameUrl
        }
        flags.id
    )


gameNavigation : { isMember : Bool, gameUrl : Maybe String } -> LobbyId -> Eff msg
gameNavigation args lobbyId =
    if args.isMember && args.gameUrl /= Nothing then
        E.navigate (Route.Game lobbyId)

    else
        E.none



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


inviteUrl : Model -> String
inviteUrl model =
    model.shared.origin ++ Route.toString (Route.Lobby model.id)


view : Model -> List (Html Msg)
view model =
    let
        errorNotice : Html msg
        errorNotice =
            let
                notice =
                    [ model.error
                    , model.actionError
                    ]
                        |> List.filterMap identity
                        |> String.join " "
                        |> String.trim
            in
            if String.isEmpty notice then
                H.text ""

            else
                H.p
                    [ A.attribute "role" "status"
                    ]
                    [ H.text notice
                    ]
    in
    [ H.div
        [ A.css
            [ S.wFull
            , S.maxW160
            , S.selfCenter
            ]
        ]
        [ [ inviteView model
          , mapView model
          , lobbyView model
          , errorNotice
          , case model.error of
                Just _ ->
                    H.fieldset
                        [ A.disabled (model.busy || model.refreshing)
                        , A.css [ S.border0 ]
                        ]
                        [ Button.secondary "retry" RetryButtonClicked
                            |> Button.toHtml
                        ]

                Nothing ->
                    H.text ""
          ]
            |> Card.toHtml
                (Card.simple
                    |> Card.withHeader (CardHeader.simple model.name)
                )
        ]
    ]


inviteView : Model -> Html Msg
inviteView model =
    H.div
        [ A.css [ S.col, S.g1 ]
        ]
        [ H.label
            [ A.for "invite-link" ]
            [ H.text "invite players" ]
        , H.div
            [ A.css [ S.row, S.g2, S.flexWrap ] ]
            [ H.input
                [ A.id "invite-link"
                , A.type_ "text"
                , A.value (inviteUrl model)
                , A.readonly True
                , A.css
                    [ S.flex1
                    , S.minW0
                    , S.minW40
                    , S.maxWFull
                    , S.p2
                    , S.indentStrong
                    , S.bgNightwood3
                    , S.textGray5
                    ]
                ]
                []
            , H.fieldset
                [ A.disabled (model.copyStatus == Copying || model.copyStatus == Copied)
                , A.css [ S.border0, S.shrink0 ]
                ]
                [ Button.secondary "copy link" CopyLinkButtonClicked
                    |> Button.toHtml
                ]
            ]
        , H.p
            [ A.attribute "role" "status" ]
            [ H.text
                (case model.copyStatus of
                    Copied ->
                        "copied"

                    CopyFailed ->
                        "could not copy. select the link and copy it manually."

                    _ ->
                        ""
                )
            ]
        ]


mapView : Model -> Html Msg
mapView model =
    if model.isHost && model.gameUrl == Nothing then
        H.div
            [ A.css
                [ S.col
                , S.g1
                ]
            ]
            [ H.label
                [ A.for "map-type"
                ]
                [ H.text "map"
                ]
            , H.select
                [ A.id "map-type"
                , A.disabled model.busy
                , A.css
                    [ S.indentStrong
                    , S.bgNightwood3
                    , S.textGray5
                    , S.p2
                    , S.maxW96
                    ]
                , Ev.on "change"
                    (Decode.at [ "target", "value" ] Api.Enum.MapType.decoder
                        |> Decode.map MapInputChanged
                    )
                ]
                (List.map
                    (\mapType ->
                        H.option
                            [ A.value (Api.Enum.MapType.toString mapType)
                            , A.selected (mapType == model.selectedMapType)
                            ]
                            [ H.text (MapType.label mapType)
                            ]
                    )
                    Api.Enum.MapType.list
                )
            , H.fieldset
                [ A.disabled (model.busy || model.refreshing)
                , A.css
                    [ S.border0
                    ]
                ]
                [ Button.secondary "save map" SaveMapButtonClicked
                    |> Button.toHtml
                ]
            , H.p
                [ A.attribute "role" "status"
                ]
                [ H.text
                    (case model.mapStatus of
                        MapIdle ->
                            ""

                        MapSaving ->
                            "saving map…"

                        MapSaved ->
                            "map saved"
                    )
                ]
            ]

    else
        H.p
            []
            [ H.text ("map: " ++ MapType.label model.mapType)
            ]


lobbyView : Model -> Html Msg
lobbyView model =
    let
        controls : Html Msg
        controls =
            if model.gameUrl /= Nothing then
                H.p
                    []
                    [ H.text "this game has started. joining is closed."
                    ]

            else if List.length model.players < 2 then
                H.p
                    []
                    [ H.text "this map needs two players. share the invite link to fill the other side."
                    ]

            else if model.isHost then
                Button.primary "start game" StartButtonClicked
                    |> Button.toHtml

            else
                H.p
                    []
                    [ H.text "you have joined. waiting for the host to start the game…"
                    ]
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ H.h2
            []
            [ H.text ("players (" ++ String.fromInt (List.length model.players) ++ ")")
            ]
        , H.ul
            [ A.css
                [ S.col
                , S.g2
                , S.listNone
                ]
            ]
            (List.map playerView model.players)
        , H.fieldset
            [ A.disabled (model.busy || model.refreshing)
            , A.css
                [ S.border0
                ]
            ]
            [ controls
            ]
        ]


playerView : Player -> Html msg
playerView player =
    let
        suffix : String
        suffix =
            if player.isHost then
                " (host)"

            else
                ""
    in
    H.li
        []
        [ H.text (player.name ++ suffix)
        ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 2000 PollTimerElapsed


listeners : FromJs.Listener Msg
listeners =
    FromJs.data "copyLinkResult"
        (Decode.map2 CopyResult
            (Decode.field "url" Decode.string)
            (Decode.field "success" Decode.bool)
        )
        CopyLinkResultReceived
