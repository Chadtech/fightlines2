module Fightlines.Page.GameLoadFailed exposing
    ( Model
    , Msg
    , init
    , setShared
    , track
    , update
    , view
    )

import Analytics
import ApiRequest
import Effect
    exposing
        ( Eff
        )
import Fightlines.GameOrigin
    exposing
        ( GameOrigin
        )
import Fightlines.Page.GamePage as GamePage
import Fightlines.Route as Route
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
import Shared
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
    , origin : GameOrigin
    , error : String
    }


type Msg
    = RetryButtonClicked
    | ReturnHomeButtonClicked



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init :
    Shared.Model
    -> LobbyId
    -> GameOrigin
    -> Graphql.Http.Error GamePage.Flags
    -> Model
init shared id origin error =
    { shared = shared
    , id = id
    , origin = origin
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


track : Msg -> Analytics.Event
track msg =
    case msg of
        RetryButtonClicked ->
            Analytics.noData "retry clicked"

        ReturnHomeButtonClicked ->
            Analytics.noData "return home clicked"


update : Msg -> Model -> Eff Msg
update msg model =
    case msg of
        RetryButtonClicked ->
            Route.navigate
                model.shared.deployment
                (Route.Game model.id model.origin)

        ReturnHomeButtonClicked ->
            Route.navigate model.shared.deployment Route.Home



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
