module Main exposing (main)

import ApiRequest
    exposing
        ( Response
        )
import Browser
import Browser.Navigation as Navigation
import Effect as E
    exposing
        ( Eff
        )
import Flags
import Game.View.TurnIntroduction as TurnIntroduction
import Html.Styled as H
    exposing
        ( Html
        )
import Json.Decode as Decode
import KeyCmd
import LobbyId
    exposing
        ( LobbyId
        )
import LocalStorage exposing (LocalStorage)
import Page.AppInitError as AppInitError
import Page.GameLoadFailed as GameLoadFailed
import Page.GamePage as GamePage
import Page.Home as Home
import Page.JoinLobby as JoinLobby
import Page.LobbyLoadFailed as LobbyLoadFailed
import Page.LobbyPage as LobbyPage
import Page.NewLobby as NewLobby
import Ports.Js.From as FromJs
import Route
    exposing
        ( Route
        )
import Shared
import Url
    exposing
        ( Url
        )
import View.AppShell as AppShell
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = AppInitError Decode.Error
    | Home Home.Model
    | NewLobby NewLobby.Model
    | LoadingLobby Shared.Model LobbyId LobbyPage.Location
    | LobbyLoadFailed LobbyId LobbyLoadFailed.Model
    | JoinLobby LobbyId JoinLobby.Model
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId
    | GameLoadFailed LobbyId GameLoadFailed.Model
    | Game LobbyId GamePage.Model
    | NotFound Shared.Model


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | NewLobbyMsg NewLobby.Msg
    | JoinLobbyMsg LobbyId JoinLobby.Msg
    | LobbyMsg LobbyId LobbyPage.Location LobbyPage.Msg
    | LobbyResponseReceived LobbyId LobbyPage.Location (Response LobbyPage.Flags)
    | LobbyLoadFailedMsg LobbyId LobbyLoadFailed.Msg
    | GameMsg LobbyId GamePage.Msg
    | GameResponseReceived LobbyId (Response GamePage.Flags)
    | GameLoadFailedMsg LobbyId GameLoadFailed.Msg
    | ReturnHomeButtonClicked
    | HomeMsg Home.Msg
    | JsErrorReceived FromJs.Error
    | LocalStorageChanged LocalStorage



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
    case Decode.decodeValue Flags.decoder value of
        Ok flags ->
            let
                shared : Shared.Model
                shared =
                    Shared.init flags.seed flags.operatingSystem flags.localStorage url key
            in
            handleRoute shared (Route.fromUrl url)

        Err error ->
            ( AppInitError error, E.none )



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


getShared : Page -> Maybe Shared.Model
getShared page =
    case page of
        AppInitError _ ->
            Nothing

        Home model ->
            Just model.shared

        NewLobby model ->
            Just model.shared

        LoadingLobby shared _ _ ->
            Just shared

        LobbyLoadFailed _ model ->
            Just model.shared

        JoinLobby _ model ->
            Just model.shared

        Lobby _ model ->
            Just model.shared

        LoadingGame shared _ ->
            Just shared

        GameLoadFailed _ model ->
            Just model.shared

        Game _ model ->
            Just model.shared

        NotFound shared ->
            Just shared


setShared : Shared.Model -> Page -> Page
setShared shared page =
    case page of
        AppInitError _ ->
            page

        Home model ->
            Home (Home.setShared shared model)

        NewLobby model ->
            NewLobby (NewLobby.setShared shared model)

        LoadingLobby _ id location ->
            LoadingLobby shared id location

        LobbyLoadFailed id model ->
            LobbyLoadFailed id (LobbyLoadFailed.setShared shared model)

        JoinLobby id model ->
            JoinLobby id (JoinLobby.setShared shared model)

        Lobby id model ->
            Lobby id (LobbyPage.setShared shared model)

        LoadingGame _ id ->
            LoadingGame shared id

        GameLoadFailed id model ->
            GameLoadFailed id (GameLoadFailed.setShared shared model)

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


loadLobby : LobbyPage.Location -> Shared.Model -> LobbyId -> ( Page, Eff Msg )
loadLobby location shared id =
    ( LoadingLobby shared id location
    , E.request (LobbyResponseReceived id location) (LobbyPage.load id)
    )


loadGame : Shared.Model -> LobbyId -> ( Page, Eff Msg )
loadGame shared id =
    ( LoadingGame shared id
    , E.request (GameResponseReceived id) (GamePage.load id)
    )



----------------------------------------------------------------
-- ROUTING --
----------------------------------------------------------------


handleRoute : Shared.Model -> Maybe Route -> ( Page, Eff Msg )
handleRoute shared route =
    case route of
        Just Route.Home ->
            ( Home (Home.init shared), E.none )

        Just Route.NewLobby ->
            ( NewLobby (NewLobby.init shared), E.none )

        Just (Route.Lobby id) ->
            loadLobby LobbyPage.LobbySetup shared id

        Just (Route.LobbyMaps id) ->
            loadLobby LobbyPage.MapLibrary shared id

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
        LocalStorageChanged storage ->
            let
                updateStorage : Shared.Model -> Shared.Model
                updateStorage shared =
                    { shared | localStorage = storage }
            in
            ( mapShared updateStorage page, E.none )

        JsErrorReceived _ ->
            ( page, E.none )

        ReturnHomeButtonClicked ->
            ( page, E.navigate Route.Home )

        HomeMsg homeMsg ->
            case page of
                Home model ->
                    let
                        ( nextModel, eff ) =
                            Home.update homeMsg model
                    in
                    ( Home nextModel, E.map HomeMsg eff )

                _ ->
                    E.withOut page

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    case Route.fromUrl url of
                        Just _ ->
                            ( page, E.pushUrl (Url.toString url) )

                        Nothing ->
                            ( page, E.load (Url.toString url) )

                Browser.External url ->
                    ( page, E.load url )

        RouteReceived route ->
            case getShared page of
                Just shared ->
                    handleRoute shared route

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

        LobbyMsg id location pageMsg ->
            case page of
                Lobby currentId model ->
                    let
                        belongsToCurrentLocation : Bool
                        belongsToCurrentLocation =
                            (id == currentId) && (location == LobbyPage.currentLocation model)
                    in
                    if belongsToCurrentLocation then
                        LobbyPage.update pageMsg model
                            |> Tuple.mapFirst (Lobby id)
                            |> Tuple.mapSecond (E.map (LobbyMsg id location))

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        LobbyResponseReceived id location result ->
            case page of
                LoadingLobby shared currentId currentLocation ->
                    let
                        belongsToCurrentLocation : Bool
                        belongsToCurrentLocation =
                            (id == currentId) && (location == currentLocation)
                    in
                    if belongsToCurrentLocation then
                        case result of
                            Ok flags ->
                                if flags.lobby.isMember then
                                    LobbyPage.init location shared flags
                                        |> Tuple.mapFirst (Lobby id)
                                        |> Tuple.mapSecond (E.map (LobbyMsg id location))

                                else
                                    ( JoinLobby id
                                        (JoinLobby.init
                                            shared
                                            { id = flags.lobby.id
                                            , lobbyName = flags.lobby.name
                                            , gameUrl = flags.lobby.gameUrl
                                            }
                                        )
                                    , E.none
                                    )

                            Err error ->
                                ( LobbyLoadFailed id (LobbyLoadFailed.init shared id location error), E.none )

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
                        GamePage.superUpdate id pageMsg model
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
                                let
                                    ( model, eff ) =
                                        GamePage.init shared flags
                                in
                                ( Game id model
                                , E.map (GameMsg id) eff
                                )

                            Err error ->
                                ( GameLoadFailed id (GameLoadFailed.init shared id error), E.none )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        GameLoadFailedMsg id pageMsg ->
            case page of
                GameLoadFailed currentId model ->
                    if id == currentId then
                        ( page
                        , GameLoadFailed.update pageMsg model
                            |> E.map (GameLoadFailedMsg id)
                        )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Page -> Browser.Document Msg
view page =
    let
        dialogContent : List (Html Msg)
        dialogContent =
            case
                dialog page
            of
                Just activeDialog ->
                    [ Dialog.toHtml activeDialog ]

                Nothing ->
                    []

        content : List (Html Msg)
        content =
            shell page ++ dialogContent
    in
    { title = "fightlines"
    , body = List.map H.toUnstyled content
    }


{-| Map the active page's dialog into the application's message type.
-}
dialog : Page -> Maybe (Dialog Msg)
dialog page =
    case page of
        Game id model ->
            GamePage.dialog model
                |> Maybe.map (Dialog.map (GameMsg id))

        _ ->
            Nothing


shell : Page -> List (Html Msg)
shell page =
    let
        content : List (Html Msg)
        content =
            case page of
                AppInitError error ->
                    AppInitError.view error

                Home model ->
                    List.map (H.map HomeMsg) (Home.view model)

                NewLobby model ->
                    List.map (H.map NewLobbyMsg) (NewLobby.view model)

                LoadingLobby _ _ _ ->
                    [ [ H.p
                            [ Aria.role Aria.Status
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
                    List.map (H.map (LobbyMsg id (LobbyPage.currentLocation model))) (LobbyPage.view model)

                LoadingGame _ _ ->
                    [ [ H.p
                            [ Aria.role Aria.Status
                            ]
                            [ H.text "loading game…"
                            ]
                      ]
                        |> Card.toHtml Card.simple
                    ]

                GameLoadFailed id model ->
                    List.map (H.map (GameLoadFailedMsg id)) (GameLoadFailed.view model)

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
    in
    AppShell.toHtml (Home.styles :: TurnIntroduction.styles :: content)



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
                LobbyPage.subscriptions model
                    |> Sub.map (LobbyMsg id (LobbyPage.currentLocation model))

            Game id model ->
                GamePage.subscriptions model
                    |> Sub.map (GameMsg id)

            _ ->
                Sub.none
        , FromJs.subscription
            { listeners =
                [ FromJs.data "local storage changed" LocalStorage.decoder LocalStorageChanged
                , listeners page
                ]
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
        Lobby id model ->
            LobbyPage.listeners |> FromJs.map (LobbyMsg id (LobbyPage.currentLocation model))

        _ ->
            FromJs.none
