module Fightlines.Page.JoinLobby exposing
    ( Flags
    , Model
    , Msg
    , init
    , setShared
    , update
    , view
    )

import Api.Mutation
import Api.Object
import Api.Object.Snapshot as Snapshot
import ApiRequest
    exposing
        ( Response
        )
import Effect as E
    exposing
        ( Eff
        )
import Fightlines.Route as Route
import Fightlines.Shared as Shared
import Fightlines.UserName as UserName
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import LobbyId exposing (LobbyId)
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { id : LobbyId
    , lobbyName : String
    , gameUrl : Maybe String
    }


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , lobbyName : String
    , joiningClosed : Bool
    , name : String
    , busy : Bool
    , error : Maybe String
    }


type Msg
    = NameInputChanged String
    | JoinButtonClicked
    | JoinResponseReceived String (Response LobbyId)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared flags =
    let
        ( name, maybeError ) =
            case UserName.fromLocalStorage shared.localStorage of
                Ok savedName ->
                    ( Maybe.withDefault "" savedName, Nothing )

                Err error ->
                    ( "", Just error )
    in
    { shared =
        shared
            |> Shared.addError maybeError
    , id = flags.id
    , lobbyName = flags.lobbyName
    , joiningClosed = flags.gameUrl /= Nothing
    , name = name
    , busy = False
    , error = Nothing
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


join : LobbyId -> String -> Graphql.Http.Request LobbyId
join id name =
    let
        lobbyIdSelection : SelectionSet LobbyId Api.Object.Snapshot
        lobbyIdSelection =
            Snapshot.id |> SS.mapOrFail LobbyId.parse
    in
    Api.Mutation.joinLobby { id = LobbyId.toString id, name = name } lobbyIdSelection
        |> ApiRequest.mutationRequest



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
            if model.busy || model.joiningClosed then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , error = Nothing
                  }
                , E.request (JoinResponseReceived model.name) (join model.id model.name)
                )

        JoinResponseReceived submittedName result ->
            case result of
                Ok lobbyId ->
                    ( { model
                        | busy = False
                      }
                    , E.batch
                        [ UserName.remember submittedName
                        , Route.pushUrl (Route.Lobby lobbyId)
                        ]
                    )

                Err error ->
                    ( { model
                        | busy = False
                        , error = Just (ApiRequest.errorMessage error)
                      }
                    , E.none
                    )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.flex1
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            ]
        ]
        [ H.div
            [ A.css
                [ S.wFull
                , S.maxW96
                ]
            ]
            [ [ H.p
                    []
                    [ H.text "enter your name to join this lobby."
                    ]
              , if model.joiningClosed then
                    H.p
                        []
                        [ H.text "this game has started. joining is closed."
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
                            [ A.css
                                [ S.col
                                , S.g1
                                ]
                            ]
                            [ H.text "your name"
                            , TextField.simple model.name NameInputChanged
                                |> TextField.toHtml
                            ]
                        , H.fieldset
                            [ A.disabled model.busy
                            , A.css [ S.border0 ]
                            ]
                            [ Button.primary "join lobby" JoinButtonClicked
                                |> Button.toHtml
                            ]
                        ]
              , case model.error of
                    Just error ->
                        H.p
                            [ Aria.role Aria.Status
                            ]
                            [ H.text error
                            ]

                    Nothing ->
                        H.text ""
              ]
                |> Card.toHtml
                    (Card.simple
                        |> Card.withHeader (CardHeader.simple model.lobbyName)
                    )
            ]
        ]
    ]
