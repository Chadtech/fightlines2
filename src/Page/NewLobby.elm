module Page.NewLobby exposing
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
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import LobbyId exposing (LobbyId)
import Route
import Shared
import Style as S
import UserName
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
    | CreateResponseReceived String (Response LobbyId)



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
    { shared =
        shared
            |> Shared.addError maybeError
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


create : String -> String -> Graphql.Http.Request LobbyId
create name lobbyName =
    let
        lobbyIdSelection : SelectionSet LobbyId Api.Object.Snapshot
        lobbyIdSelection =
            Snapshot.id |> SS.mapOrFail LobbyId.parse
    in
    Api.Mutation.createLobby { name = name, lobbyName = lobbyName } lobbyIdSelection
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

        LobbyNameInputChanged lobbyName ->
            ( { model | lobbyName = lobbyName }, E.none )

        CreateButtonClicked ->
            if model.busy then
                ( model, E.none )

            else
                ( { model
                    | busy = True
                    , error = Nothing
                  }
                , E.request (CreateResponseReceived model.name) (create model.name model.lobbyName)
                )

        CreateResponseReceived submittedName result ->
            case result of
                Ok lobbyId ->
                    ( { model
                        | busy = False
                      }
                    , E.batch
                        [ UserName.remember submittedName
                        , E.navigate (Route.Lobby lobbyId)
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
        [ [ H.p
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
          , case model.error of
                Just error ->
                    H.p
                        [ Aria.role Aria.Status
                        ]
                        [ H.text error
                        ]

                Nothing ->
                    H.text ""
          , H.a
                [ A.href (Route.toString Route.LoggedGames)
                , A.css [ S.link ]
                ]
                [ H.text "logged games" ]
          ]
            |> Card.toHtml
                (Card.compactForm
                    |> Card.withHeader (CardHeader.simple "start a lobby")
                )
        ]
    ]
