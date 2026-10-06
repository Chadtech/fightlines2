module LobbyLoadFailed exposing
    ( Model
    , Msg
    , init
    , setShared
    , update
    , view
    )

import ApiRequest
import Effect as E
    exposing
        ( Eff
        )
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
import LobbyPage
import Route
import Shared
import Style as S
import View.Button as Button
import View.Card as Card


type alias Model =
    { shared : Shared.Model
    , id : LobbyId
    , error : String
    }


type Msg
    = RetryButtonClicked
    | ReturnHomeButtonClicked


init : Shared.Model -> LobbyId -> Graphql.Http.Error LobbyPage.Flags -> Model
init shared id error =
    { shared = shared
    , id = id
    , error = ApiRequest.errorMessage error
    }


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


update : Msg -> Model -> Eff Msg
update msg model =
    case msg of
        RetryButtonClicked ->
            E.navigate (Route.Lobby model.id)

        ReturnHomeButtonClicked ->
            E.navigate Route.NewLobby


view : Model -> List (Html Msg)
view model =
    [ H.div
        [ A.css
            [ S.col
            , S.itemsCenter
            ]
        ]
        [ [ H.p
                [ A.attribute "role" "status"
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
            |> Card.toHtml Card.compactForm
        ]
    ]
