module Main exposing (main)

import ApiRequest
    exposing
        ( Response
        )
import Browser
import Browser.Navigation as Navigation
import Css.Global
import Effect as E
    exposing
        ( Eff
        )
import GamePage
import Graphql.Http
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import JoinLobby
import LobbyId
    exposing
        ( LobbyId
        )
import LobbyLoadFailed
import LobbyPage
import NewLobby
import Ports.Js.From as FromJs
import Route
    exposing
        ( Route
        )
import Shared
import Style as S
import Task
import Url
    exposing
        ( Url
        )
import View.Button as Button
import View.Card as Card
import View.Dropdown as Dropdown



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = Blank Shared.Model
    | NewLobby NewLobby.Model
    | LoadingLobby Shared.Model LobbyId
    | LobbyLoadFailed LobbyId LobbyLoadFailed.Model
    | JoinLobby LobbyId JoinLobby.Model
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId
    | GameLoadFailed Shared.Model LobbyId (Graphql.Http.Error GamePage.Flags)
    | Game LobbyId GamePage.Model
    | NotFound Shared.Model


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | NewLobbyMsg NewLobby.Msg
    | JoinLobbyMsg LobbyId JoinLobby.Msg
    | LobbyMsg LobbyId LobbyPage.Msg
    | LobbyResponseReceived LobbyId (Response LobbyPage.Flags)
    | LobbyLoadFailedMsg LobbyId LobbyLoadFailed.Msg
    | GameResponseReceived LobbyId (Response GamePage.Flags)
    | GameRetryButtonClicked
    | ReturnHomeButtonClicked
    | JsErrorReceived FromJs.Error



----------------------------------------------------------------
-- MAIN --
----------------------------------------------------------------


main : Program () Page Msg
main =
    Browser.application
        { init = init
        , update =
            \msg page ->
                let
                    ( newPage, eff ) =
                        update msg page
                in
                ( newPage, E.toCmd (getShared newPage).key eff )
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = RouteReceived << Route.fromUrl
        }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : () -> Url -> Navigation.Key -> ( Page, Cmd Msg )
init _ url key =
    ( Blank (Shared.init url key)
    , Task.perform RouteReceived (Task.succeed (Route.fromUrl url))
    )



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


getShared : Page -> Shared.Model
getShared page =
    case page of
        Blank shared ->
            shared

        NewLobby model ->
            model.shared

        LoadingLobby shared _ ->
            shared

        LobbyLoadFailed _ model ->
            model.shared

        JoinLobby _ model ->
            model.shared

        Lobby _ model ->
            model.shared

        LoadingGame shared _ ->
            shared

        GameLoadFailed shared _ _ ->
            shared

        Game _ model ->
            model.shared

        NotFound shared ->
            shared


setShared : Shared.Model -> Page -> Page
setShared shared page =
    case page of
        Blank _ ->
            Blank shared

        NewLobby model ->
            NewLobby (NewLobby.setShared shared model)

        LoadingLobby _ id ->
            LoadingLobby shared id

        LobbyLoadFailed id model ->
            LobbyLoadFailed id (LobbyLoadFailed.setShared shared model)

        JoinLobby id model ->
            JoinLobby id (JoinLobby.setShared shared model)

        Lobby id model ->
            Lobby id (LobbyPage.setShared shared model)

        LoadingGame _ id ->
            LoadingGame shared id

        GameLoadFailed _ id error ->
            GameLoadFailed shared id error

        Game id model ->
            Game id (GamePage.setShared shared model)

        NotFound _ ->
            NotFound shared


mapShared : (Shared.Model -> Shared.Model) -> Page -> Page
mapShared transform page =
    setShared (transform (getShared page)) page


loadLobby : Shared.Model -> LobbyId -> ( Page, Eff Msg )
loadLobby shared id =
    ( LoadingLobby shared id
    , E.request (LobbyResponseReceived id) (LobbyPage.load id)
    )


loadGame : Shared.Model -> LobbyId -> ( Page, Eff Msg )
loadGame shared id =
    ( LoadingGame shared id
    , E.request (GameResponseReceived id) (GamePage.load id)
    )



----------------------------------------------------------------
-- ROUTING --
----------------------------------------------------------------


handleRoute : Maybe Route -> Page -> ( Page, Eff Msg )
handleRoute route page =
    let
        shared : Shared.Model
        shared =
            getShared page
    in
    case route of
        Just Route.NewLobby ->
            ( NewLobby (NewLobby.init shared), E.none )

        Just (Route.Lobby id) ->
            loadLobby shared id

        Just (Route.Game id) ->
            loadGame shared id

        Nothing ->
            ( NotFound shared, E.none )



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Page -> ( Page, Eff Msg )
update msg page =
    case msg of
        JsErrorReceived _ ->
            ( page, E.none )

        ReturnHomeButtonClicked ->
            ( page, E.navigate Route.NewLobby )

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    ( page, E.pushUrl (Url.toString url) )

                Browser.External url ->
                    ( page, E.load url )

        RouteReceived route ->
            handleRoute route page

        NewLobbyMsg pageMsg ->
            case page of
                NewLobby model ->
                    NewLobby.update pageMsg model
                        |> Tuple.mapFirst NewLobby
                        |> Tuple.mapSecond (E.map NewLobbyMsg)

                _ ->
                    ( page, E.none )

        JoinLobbyMsg id pageMsg ->
            case page of
                JoinLobby currentId model ->
                    if id == currentId then
                        JoinLobby.update pageMsg model
                            |> Tuple.mapFirst (JoinLobby id)
                            |> Tuple.mapSecond (E.map (JoinLobbyMsg id))

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        LobbyMsg id pageMsg ->
            case page of
                Lobby currentId model ->
                    if id == currentId then
                        LobbyPage.update pageMsg model
                            |> Tuple.mapFirst (Lobby id)
                            |> Tuple.mapSecond (E.map (LobbyMsg id))

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        LobbyResponseReceived id result ->
            case page of
                LoadingLobby shared currentId ->
                    if id == currentId then
                        case result of
                            Ok flags ->
                                if flags.isMember then
                                    LobbyPage.init shared flags
                                        |> Tuple.mapFirst (Lobby id)
                                        |> Tuple.mapSecond (E.map (LobbyMsg id))

                                else
                                    ( JoinLobby id
                                        (JoinLobby.init
                                            shared
                                            { id = flags.id
                                            , gameUrl = flags.gameUrl
                                            }
                                        )
                                    , E.none
                                    )

                            Err error ->
                                ( LobbyLoadFailed id (LobbyLoadFailed.init shared id error), E.none )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        LobbyLoadFailedMsg id pageMsg ->
            case page of
                LobbyLoadFailed currentId model ->
                    if id == currentId then
                        ( page
                        , LobbyLoadFailed.update pageMsg model
                            |> E.map (LobbyLoadFailedMsg id)
                        )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        GameResponseReceived id result ->
            case page of
                LoadingGame shared currentId ->
                    if id == currentId then
                        case result of
                            Ok flags ->
                                ( Game id (GamePage.init shared flags), E.none )

                            Err error ->
                                ( GameLoadFailed shared id error, E.none )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        GameRetryButtonClicked ->
            case page of
                GameLoadFailed shared id _ ->
                    loadGame shared id

                _ ->
                    ( page, E.none )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Page -> Browser.Document Msg
view page =
    { title = "fightlines"
    , body = List.map H.toUnstyled (shell page)
    }


shell : Page -> List (Html Msg)
shell page =
    let
        content : List (Html Msg)
        content =
            case page of
                Blank _ ->
                    []

                NewLobby model ->
                    List.map (H.map NewLobbyMsg) (NewLobby.view model)

                LoadingLobby _ _ ->
                    [ [ H.p
                            [ A.attribute "role" "status"
                            ]
                            [ H.text "loading lobby…"
                            ]
                      ]
                        |> Card.toHtml Card.simple
                    ]

                LobbyLoadFailed id model ->
                    List.map (H.map (LobbyLoadFailedMsg id)) (LobbyLoadFailed.view model)

                JoinLobby id model ->
                    List.map (H.map (JoinLobbyMsg id)) (JoinLobby.view model)

                Lobby id model ->
                    List.map (H.map (LobbyMsg id)) (LobbyPage.view model)

                LoadingGame _ _ ->
                    [ [ H.p
                            [ A.attribute "role" "status"
                            ]
                            [ H.text "loading game…"
                            ]
                      ]
                        |> Card.toHtml Card.simple
                    ]

                GameLoadFailed _ id error ->
                    GamePage.loadFailedView id error GameRetryButtonClicked

                Game _ model ->
                    GamePage.view model

                NotFound _ ->
                    [ [ H.p
                            []
                            [ H.text "page not found."
                            ]
                      , Button.primary "return home" ReturnHomeButtonClicked
                            |> Button.toHtml
                      ]
                        |> Card.toHtml Card.simple
                    ]

        globalStyles : Html Msg
        globalStyles =
            Css.Global.global
                (S.global
                    ++ [ Dropdown.globalStyles
                       ]
                )
    in
    [ H.main_
        [ A.css
            [ S.bgNightwood2
            , S.minHFullViewport
            , S.p4
            , S.textGray4
            , S.col
            , S.g3
            ]
        ]
        (globalStyles :: content)
    ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Page -> Sub Msg
subscriptions page =
    Sub.batch
        [ case page of
            Lobby id model ->
                LobbyPage.subscriptions model |> Sub.map (LobbyMsg id)

            _ ->
                Sub.none
        , FromJs.subscription
            { listeners = [ listeners page ]
            , onError = JsErrorReceived
            }
        ]


listeners : Page -> FromJs.Listener Msg
listeners page =
    case page of
        Lobby id _ ->
            LobbyPage.listeners |> FromJs.map (LobbyMsg id)

        _ ->
            FromJs.none
