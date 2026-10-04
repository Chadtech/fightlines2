module GamePage exposing
    ( Flags
    , Model
    , init
    , load
    , loadFailedView
    , setShared
    , view
    )

import Api.Object
import Api.Object.PlayerView as PlayerView
import Api.Object.Snapshot as Snapshot
import Api.Query
import ApiRequest
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import LobbyId
    exposing
        ( LobbyId
        )
import Route
import Shared
import Style as S
import View.Button as Button
import View.Card as Card



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Flags =
    { playerNames : List String
    }


type alias Model =
    { shared : Shared.Model
    , playerNames : List String
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Shared.Model -> Flags -> Model
init shared flags =
    { shared = shared
    , playerNames = flags.playerNames
    }


load : LobbyId -> Graphql.Http.Request Flags
load id =
    let
        selection : SelectionSet Flags Api.Object.Snapshot
        selection =
            SS.map Flags (Snapshot.players PlayerView.name)
    in
    Api.Query.game { id = LobbyId.toString id } selection
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html msg)
view model =
    [ [ H.h1
            []
            [ H.text "game"
            ]
      , H.p
            []
            [ H.text "the game has started. game mechanics will be added here."
            ]
      , H.p
            []
            [ H.text ("players: " ++ String.join ", " model.playerNames)
            ]
      ]
        |> Card.toHtml Card.simple
    ]


loadFailedView : LobbyId -> Graphql.Http.Error Flags -> msg -> List (Html msg)
loadFailedView id error retryMsg =
    let
        message : String
        message =
            ApiRequest.errorMessage error
    in
    [ [ H.p
            [ A.attribute "role" "status"
            ]
            [ H.text message
            ]
      , H.a
            [ A.href (Route.toString (Route.Lobby id))
            , A.css
                [ S.link
                ]
            ]
            [ H.text "return to lobby"
            ]
      , Button.secondary "retry" retryMsg
            |> Button.toHtml
      ]
        |> Card.toHtml Card.simple
    ]
