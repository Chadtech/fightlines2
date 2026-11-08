module Fightlines.Page.NewLobby exposing
    ( Model
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
import Shared
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.TextField as TextField



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { shared : Shared.Model
    , name : String
    , lobbyName : String
    , busy : Bool
    , error : Maybe String
    }


type Msg
    = NameInputChanged String
    | LobbyNameInputChanged String
    | CreateButtonClicked
    | CreateResponseReceived (Response LobbyId)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Model
init shared =
    let
        ( name, maybeError ) =
            case UserName.fromLocalStorage shared.localStorage of
                Ok savedName ->
                    ( Maybe.withDefault "" savedName, Nothing )

                Err error ->
                    ( "", Just error )
    in
    { shared = Shared.addError maybeError shared
    , name = name
    , lobbyName = ""
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


setBusy : Bool -> Model -> Model
setBusy busy model =
    { model | busy = busy }


setError : Maybe String -> Model -> Model
setError error model =
    { model | error = error }


create : { name : String, lobbyName : String } -> Graphql.Http.Request LobbyId
create input =
    let
        lobbyIdSelection : SelectionSet LobbyId Api.Object.Snapshot
        lobbyIdSelection =
            Snapshot.id |> SS.mapOrFail LobbyId.parse
    in
    Api.Mutation.createLobby input lobbyIdSelection
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
            , UserName.remember name
            )

        LobbyNameInputChanged lobbyName ->
            ( { model | lobbyName = lobbyName }
            , E.none
            )

        CreateButtonClicked ->
            if model.busy then
                ( model, E.none )

            else
                ( model
                    |> setBusy True
                    |> setError Nothing
                , E.request
                    CreateResponseReceived
                    (create
                        { name = model.name
                        , lobbyName = model.lobbyName
                        }
                    )
                )

        CreateResponseReceived result ->
            case result of
                Ok lobbyId ->
                    ( model
                        |> setBusy False
                    , Route.pushUrl (Route.Lobby lobbyId)
                    )

                Err error ->
                    ( model
                        |> setBusy False
                        |> setError (Just (ApiRequest.errorMessage error))
                    , if ApiRequest.requiresCurrentDeployment error then
                        Route.load Route.NewLobby

                      else
                        E.none
                    )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        errorArea : Html Msg
        errorArea =
            case model.error of
                Just error ->
                    H.p
                        [ Aria.role Aria.Status
                        , A.css
                            [ S.bgRed0
                            , S.textGray5
                            , S.p2
                            ]
                        ]
                        [ H.text error
                        ]

                Nothing ->
                    H.text ""
    in
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
            [ Card.toHtml
                (Card.simple
                    |> Card.withHeader (CardHeader.simple "start a lobby")
                )
                [ H.p
                    []
                    [ H.text "create a lobby, then share its invite link."
                    ]
                , H.form
                    [ Ev.onSubmit CreateButtonClicked
                    ]
                    [ H.fieldset
                        [ A.disabled model.busy
                        , A.css
                            [ S.border0
                            , S.col
                            , S.g3
                            ]
                        ]
                        [ H.label
                            [ A.css
                                [ S.col
                                , S.g1
                                ]
                            ]
                            [ H.text "user name"
                            , TextField.simple model.name NameInputChanged
                                |> TextField.toHtml
                            ]
                        , H.label
                            [ A.css
                                [ S.col
                                , S.g1
                                ]
                            ]
                            [ H.text "lobby name"
                            , TextField.simple model.lobbyName LobbyNameInputChanged
                                |> TextField.toHtml
                            ]
                        , Button.primary "create lobby" CreateButtonClicked
                            |> Button.toHtml
                        ]
                    ]
                , errorArea
                ]
            ]
        ]
    ]
