module LobbyPage exposing
    ( Flags
    , Model
    , Msg
    , init
    , load
    , loadFailedView
    , setShared
    , subscriptions
    , update
    , view
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
import LobbyId
    exposing
        ( LobbyId
        )
import Route
import Shared
import Style as S
import Time
import View.Button as Button
import View.Card as Card
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { id : LobbyId
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
    , players : List Player
    , isHost : Bool
    , isMember : Bool
    , gameUrl : Maybe String
    , name : String
    , busy : Bool
    , refreshing : Bool
    , error : Maybe String
    , actionError : Maybe String
    }


type Msg
    = NameInputChanged String
    | JoinButtonClicked
    | StartButtonClicked
    | RefreshButtonClicked
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
      , players = flags.players
      , isHost = flags.isHost
      , isMember = flags.isMember
      , gameUrl = flags.gameUrl
      , name = ""
      , busy = False
      , refreshing = False
      , error = Nothing
      , actionError = Nothing
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


join : LobbyId -> String -> Graphql.Http.Request Flags
join id name =
    Api.Mutation.joinLobby { id = LobbyId.toString id, name = name } flagsSelection
        |> ApiRequest.mutationRequest


start : LobbyId -> Graphql.Http.Request Flags
start id =
    Api.Mutation.startGame { id = LobbyId.toString id } flagsSelection
        |> ApiRequest.mutationRequest


flagsSelection : SelectionSet Flags Api.Object.Snapshot
flagsSelection =
    SS.map5 Flags
        (Snapshot.id |> SS.mapOrFail LobbyId.parse)
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
        NameInputChanged name ->
            ( { model
                | name = name
              }
            , E.none
            )

        JoinButtonClicked ->
            if model.busy || model.refreshing then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , actionError = Nothing
                  }
                , E.request ActionResponseReceived (join model.id model.name)
                )

        StartButtonClicked ->
            if model.busy || model.refreshing then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , actionError = Nothing
                  }
                , E.request ActionResponseReceived (start model.id)
                )

        RefreshButtonClicked ->
            refresh model

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


view : Model -> List (Html Msg)
view model =
    [ [ H.h1
            []
            [ H.text "lobby"
            ]
      , H.label
            [ A.css
                [ S.col
                , S.g2
                ]
            ]
            [ H.text "invite players: copy this link"
            , H.input
                [ A.value (model.shared.origin ++ Route.toString (Route.Lobby model.id))
                , A.readonly True
                , A.css
                    [ S.wFull
                    , S.p2
                    , S.indent
                    , S.bgNightwood1
                    , S.textGray4
                    ]
                ]
                []
            ]
      , lobbyView model
      , H.p
            [ A.attribute "role" "status"
            ]
            [ H.text
                (String.join " "
                    (List.filterMap identity
                        [ model.error
                        , model.actionError
                        ]
                    )
                )
            ]
      , H.fieldset
            [ A.disabled (model.busy || model.refreshing)
            , A.css
                [ S.border0
                ]
            ]
            [ Button.secondary "refresh lobby" RefreshButtonClicked
                |> Button.toHtml
            ]
      ]
        |> Card.toHtml Card.simple
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

            else if model.isHost then
                Button.primary "start game" StartButtonClicked
                    |> Button.toHtml

            else if model.isMember then
                H.p
                    []
                    [ H.text "you have joined. waiting for the host to start the game…"
                    ]

            else
                H.form
                    [ Ev.onSubmit JoinButtonClicked
                    , A.css
                        [ S.col
                        , S.g3
                        ]
                    ]
                    [ H.label
                        []
                        [ H.text "your name"
                        , TextField.simple model.name NameInputChanged
                            |> TextField.toHtml
                        ]
                    , Button.primary "join lobby" JoinButtonClicked
                        |> Button.toHtml
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


loadFailedView : Graphql.Http.Error Flags -> msg -> List (Html msg)
loadFailedView error retryMsg =
    [ [ H.p
            [ A.attribute "role" "status"
            ]
            [ H.text (ApiRequest.errorMessage error)
            ]
      , Button.secondary "retry" retryMsg
            |> Button.toHtml
      ]
        |> Card.toHtml Card.simple
    ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 2000 PollTimerElapsed
