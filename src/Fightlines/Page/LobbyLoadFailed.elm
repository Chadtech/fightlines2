module Fightlines.Page.LobbyLoadFailed exposing
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
import Fightlines.Page.LobbyPage as LobbyPage
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


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , location : LobbyPage.Location
    , error : String
    }


type Msg
    = RetryButtonClicked
    | ReturnHomeButtonClicked


init : Shared.Model -> LobbyId -> LobbyPage.Location -> Graphql.Http.Error LobbyPage.Flags -> Model
init shared id location error =
    { shared = shared
    , id = id
    , location = location
    , error = ApiRequest.errorMessage error
    }


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


update : Msg -> Model -> Eff Msg
update msg model =
    case msg of
        RetryButtonClicked ->
            case model.location of
                LobbyPage.LobbySetup ->
                    E.navigate (Route.Lobby model.id)

                LobbyPage.MapLibrary ->
                    E.navigate (Route.LobbyMaps model.id)

        ReturnHomeButtonClicked ->
            E.navigate Route.Home


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
