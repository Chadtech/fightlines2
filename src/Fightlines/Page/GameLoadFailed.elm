module Fightlines.Page.GameLoadFailed exposing
    ( Model
    , Msg
    , init
    , setShared
    , update
    , view
    )

import ApiRequest
import Fightlines.Effect as E
    exposing
        ( Eff
        )
import Fightlines.Page.GamePage as GamePage
import Fightlines.Route as Route
import Fightlines.Shared as Shared
import Graphql.Http
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import LobbyId
    exposing
        ( LobbyId
        )
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , error : String
    }


type Msg
    = RetryButtonClicked
    | ReturnHomeButtonClicked



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> LobbyId -> Graphql.Http.Error GamePage.Flags -> Model
init shared id error =
    { shared = shared
    , id = id
    , error = ApiRequest.errorMessage error
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> Eff Msg
update msg model =
    case msg of
        RetryButtonClicked ->
            E.navigate (Route.Game model.id)

        ReturnHomeButtonClicked ->
            E.navigate Route.Home



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
                    [ Aria.role Aria.Status
                    ]
                    [ H.text model.error
                    ]
              , H.div
                    [ A.css
                        [ S.row
                        , S.g2
                        , S.flexWrap
                        ]
                    ]
                    [ Button.primary "return home" ReturnHomeButtonClicked
                        |> Button.toHtml
                    , Button.secondary "retry" RetryButtonClicked
                        |> Button.toHtml
                    ]
              ]
                |> Card.toHtml
                    (Card.simple
                        |> Card.withHeader (CardHeader.simple "lobby unavailable")
                    )
            ]
        ]
    ]
