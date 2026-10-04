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
import LobbyId
    exposing
        ( LobbyId
        )
import LobbyPage
import NewLobby
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
    | LobbyLoadFailed Shared.Model LobbyId (Graphql.Http.Error LobbyPage.Flags)
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId
    | GameLoadFailed Shared.Model LobbyId (Graphql.Http.Error GamePage.Flags)
    | Game LobbyId GamePage.Model
    | NotFound Shared.Model


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | NewLobbyMsg NewLobby.Msg
    | LobbyMsg LobbyId LobbyPage.Msg
    | LobbyResponseReceived LobbyId (Response LobbyPage.Flags)
    | LobbyRetryButtonClicked
    | GameResponseReceived LobbyId (Response GamePage.Flags)
    | GameRetryButtonClicked
    | ReturnHomeButtonClicked



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

        LobbyLoadFailed shared _ _ ->
            shared

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

        LobbyLoadFailed _ id error ->
            LobbyLoadFailed shared id error

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
                                LobbyPage.init shared flags
                                    |> Tuple.mapFirst (Lobby id)
                                    |> Tuple.mapSecond (E.map (LobbyMsg id))

                            Err error ->
                                ( LobbyLoadFailed shared id error, E.none )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        LobbyRetryButtonClicked ->
            case page of
                LobbyLoadFailed shared id _ ->
                    loadLobby shared id

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
    { title = "FightLines"
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
                            [ H.text "Loading lobby…"
                            ]
                      ]
                        |> Card.toHtml Card.simple
                    ]

                LobbyLoadFailed _ _ error ->
                    LobbyPage.loadFailedView error LobbyRetryButtonClicked

                Lobby id model ->
                    List.map (H.map (LobbyMsg id)) (LobbyPage.view model)

                LoadingGame _ _ ->
                    [ [ H.p
                            [ A.attribute "role" "status"
                            ]
                            [ H.text "Loading game…"
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
                            [ H.text "Page not found."
                            ]
                      , Button.primary "Return home" ReturnHomeButtonClicked
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
            [ S.bgNightwood1
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
    case page of
        Lobby id model ->
            LobbyPage.subscriptions model |> Sub.map (LobbyMsg id)

        _ ->
            Sub.none
