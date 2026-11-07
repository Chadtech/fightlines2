module Admin.Page.Login exposing
    ( Model
    , Msg(..)
    , init
    , setShared
    , update
    , view
    )

import Api.Enum.SessionStatus exposing (SessionStatus)
import Api.Mutation
import ApiRequest exposing (Response)
import Effect as E exposing (Eff)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
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
    , password : String
    , request : Request
    }


type Request
    = Idle
    | Submitting
    | Failed String


type Msg
    = PasswordInputChanged String
    | LoginSubmitted
    | LoginResponseReceived (Response SessionStatus)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Model
init shared =
    { shared = shared
    , password = ""
    , request = Idle
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        PasswordInputChanged value ->
            { model
                | password = value
            }
                |> E.withOut

        LoginSubmitted ->
            let
                canSubmit : Bool
                canSubmit =
                    (model.request /= Submitting) && not (String.isEmpty model.password)
            in
            if not canSubmit then
                model |> E.withOut

            else
                ( { model
                    | request = Submitting
                  }
                , Api.Mutation.adminLogin
                    { password = model.password
                    }
                    |> ApiRequest.mutationRequest
                    |> E.request LoginResponseReceived
                )

        LoginResponseReceived (Err error) ->
            { model
                | request = Failed (ApiRequest.errorMessage error)
            }
                |> E.withOut

        LoginResponseReceived (Ok _) ->
            { model
                | password = ""
                , request = Idle
            }
                |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        pending : Bool
        pending =
            model.request == Submitting

        button : Button.Button Msg
        button =
            if pending then
                Button.disabled "checking password…"

            else
                Button.primary "log in" LoginSubmitted

        feedback : List (Html Msg)
        feedback =
            case model.request of
                Failed error ->
                    [ H.p
                        [ Aria.role Aria.Alert
                        ]
                        [ H.text error
                        ]
                    ]

                _ ->
                    []

        fields : List (Html Msg)
        fields =
            [ H.label
                [ A.for passwordHtmlId
                ]
                [ H.text "admin password"
                ]
            , TextField.password model.password PasswordInputChanged
                |> TextField.withHtmlId passwordHtmlId
                |> TextField.disabled pending
                |> TextField.withAutofocus
                |> TextField.toHtml
            , Button.toHtml button
            ]
                ++ feedback
    in
    [ H.div
        [ A.css
            [ S.wFull
            , S.maxW96
            , S.selfCenter
            , S.mt16
            ]
        ]
        [ Card.toHtml (Card.simple |> Card.withHeader (CardHeader.simple "admin login"))
            [ H.form
                [ Ev.onSubmit LoginSubmitted
                , A.css
                    [ S.col
                    , S.g3
                    ]
                ]
                fields
            ]
        ]
    ]


passwordHtmlId : String
passwordHtmlId =
    "admin-password"
