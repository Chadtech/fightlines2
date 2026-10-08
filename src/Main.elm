module Main exposing (main)

import ApiRequest
    exposing
        ( Response
        )
import AppInitError
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
import Json.Decode as Decode
import KeyCmd
import LobbyId
    exposing
        ( LobbyId
        )
import LobbyLoadFailed
import LobbyPage
import NewLobby
import OperatingSystem exposing (OperatingSystem)
import Ports.Js.From as FromJs
import Route
    exposing
        ( Route
        )
import Shared
import Style as S
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
    = AppInitError Decode.Error
    | StartingApp Shared.Model
    | NewLobby NewLobby.Model
    | LoadingLobby Shared.Model LobbyId
    | LobbyLoadFailed LobbyId LobbyLoadFailed.Model
    | JoinLobby LobbyId JoinLobby.Model
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId
    | GameLoadFailed Shared.Model LobbyId (Graphql.Http.Error GamePage.Flags)
    | Game LobbyId GamePage.Model
    | NotFound Shared.Model


type alias Flags =
    { operatingSystem : OperatingSystem
    }


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | NewLobbyMsg NewLobby.Msg
    | JoinLobbyMsg LobbyId JoinLobby.Msg
    | LobbyMsg LobbyId LobbyPage.Msg
    | LobbyResponseReceived LobbyId (Response LobbyPage.Flags)
    | LobbyLoadFailedMsg LobbyId LobbyLoadFailed.Msg
    | GameMsg LobbyId GamePage.Msg
    | GameResponseReceived LobbyId (Response GamePage.Flags)
    | GameRetryButtonClicked
    | ReturnHomeButtonClicked
    | JsErrorReceived FromJs.Error



----------------------------------------------------------------
-- MAIN --
----------------------------------------------------------------


main : Program Decode.Value Page Msg
main =
    Browser.application
        { init =
            \value url key ->
                init value url key
                    |> Tuple.mapSecond (E.toCmd key)
        , update =
            \msg page ->
                let
                    ( newPage, eff ) =
                        update msg page
                in
                case getShared newPage of
                    Just shared ->
                        ( newPage, E.toCmd shared.key eff )

                    Nothing ->
                        ( newPage, Cmd.none )
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = RouteReceived << Route.fromUrl
        }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Decode.Value -> Url -> Navigation.Key -> ( Page, Eff Msg )
init value url key =
    case Decode.decodeValue flagsDecoder value of
        Ok flags ->
            let
                shared : Shared.Model
                shared =
                    Shared.init flags.operatingSystem url key
            in
            handleRoute
                shared
                (Route.fromUrl url)
                (StartingApp shared)

        Err error ->
            ( AppInitError error, E.none )


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map Flags
        (Decode.field "operatingSystem" OperatingSystem.decoder)



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


getShared : Page -> Maybe Shared.Model
getShared page =
    case page of
        AppInitError _ ->
            Nothing

        StartingApp shared ->
            Just shared

        NewLobby model ->
            Just model.shared

        LoadingLobby shared _ ->
            Just shared

        LobbyLoadFailed _ model ->
            Just model.shared

        JoinLobby _ model ->
            Just model.shared

        Lobby _ model ->
            Just model.shared

        LoadingGame shared _ ->
            Just shared

        GameLoadFailed shared _ _ ->
            Just shared

        Game _ model ->
            Just model.shared

        NotFound shared ->
            Just shared


setShared : Shared.Model -> Page -> Page
setShared shared page =
    case page of
        AppInitError _ ->
            page

        StartingApp _ ->
            StartingApp shared

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
    case getShared page of
        Just shared ->
            setShared (transform shared) page

        Nothing ->
            page


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


handleRoute : Shared.Model -> Maybe Route -> Page -> ( Page, Eff Msg )
handleRoute shared route page =
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
            case getShared page of
                Just shared ->
                    handleRoute shared route page

                Nothing ->
                    page |> E.withOut

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
                                            , lobbyName = flags.name
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

        GameMsg id pageMsg ->
            case page of
                Game currentId model ->
                    if id == currentId then
                        GamePage.update pageMsg model
                            |> Tuple.mapFirst (Game id)
                            |> Tuple.mapSecond (E.map (GameMsg id))

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
                AppInitError error ->
                    AppInitError.view error

                StartingApp _ ->
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

                Game id model ->
                    List.map (H.map (GameMsg id)) (GamePage.view model)

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
    case getShared page of
        Just shared ->
            pageSubscriptions shared page

        Nothing ->
            Sub.none


pageSubscriptions : Shared.Model -> Page -> Sub Msg
pageSubscriptions shared page =
    Sub.batch
        [ case page of
            Lobby id model ->
                LobbyPage.subscriptions model |> Sub.map (LobbyMsg id)

            Game id model ->
                GamePage.subscriptions model |> Sub.map (GameMsg id)

            _ ->
                Sub.none
        , FromJs.subscription
            { listeners = [ listeners page ]
            , onError = JsErrorReceived
            }
        , KeyCmd.subscriptions shared.operatingSystem [ keyCommands page ]
        ]


keyCommands : Page -> KeyCmd.KeyCmd Msg
keyCommands page =
    case page of
        Game id model ->
            GamePage.keyCommands model |> KeyCmd.map (GameMsg id)

        _ ->
            KeyCmd.none


listeners : Page -> FromJs.Listener Msg
listeners page =
    case page of
        Lobby id _ ->
            LobbyPage.listeners |> FromJs.map (LobbyMsg id)

        _ ->
            FromJs.none
