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
import Game.LogId as GameLogId exposing (GameLogId)
import Game.View.CombatEffects as CombatEffects
import Game.View.CombatTheater as CombatTheater
import Game.View.DepotStock as DepotStock
import Game.View.TargetSight as TargetSight
import Game.View.TerrainTile as TerrainTile
import Game.View.TurnControls as TurnControls
import Game.View.TurnIntroduction as TurnIntroduction
import Game.View.UnitCargo as UnitCargo
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitFacing as UnitFacing
import Game.View.UnitWarnings as UnitWarnings
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import KeyCmd
import LobbyId
    exposing
        ( LobbyId
        )
import LocalStorage exposing (LocalStorage)
import OperatingSystem exposing (OperatingSystem)
import Page.AppInitError as AppInitError
import Page.GameLoadFailed as GameLoadFailed
import Page.GamePage as GamePage
import Page.GameReplay as GameReplay
import Page.Home as Home
import Page.JoinLobby as JoinLobby
import Page.LobbyLoadFailed as LobbyLoadFailed
import Page.LobbyPage as LobbyPage
import Page.LoggedGames as LoggedGames
import Page.MapEditor as MapEditor
import Page.NewLobby as NewLobby
import Ports.Js.From as FromJs
import Random
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
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.Dialog as Dialog exposing (Dialog)
import View.LoadingBar as LoadingBar



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = AppInitError Decode.Error
    | StartingApp Shared.Model
    | Home Home.Model
    | NewLobby NewLobby.Model
    | LoadingLobby Shared.Model LobbyId
    | LobbyLoadFailed LobbyId LobbyLoadFailed.Model
    | JoinLobby LobbyId JoinLobby.Model
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId
    | GameLoadFailed LobbyId GameLoadFailed.Model
    | Game LobbyId GamePage.Model
    | LoadingMapEditor Shared.Model
    | MapEditorLoadFailed Shared.Model String
    | MapEditor MapEditor.Model
    | LoadingLoggedGames Shared.Model
    | LoggedGamesLoadFailed Shared.Model String
    | LoggedGames LoggedGames.Model
    | LoadingReplay Shared.Model GameLogId
    | ReplayLoadFailed Shared.Model GameLogId String
    | Replay GameLogId GameReplay.Model
    | NotFound Shared.Model


type alias Flags =
    { operatingSystem : OperatingSystem
    , localStorage : LocalStorage
    , seed : Random.Seed
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
    | GameLoadFailedMsg LobbyId GameLoadFailed.Msg
    | MapEditorResponseReceived (ApiRequest.Response MapEditor.Flags)
    | MapEditorMsg MapEditor.Msg
    | LoggedGamesResponseReceived (Response LoggedGames.Flags)
    | ReplayResponseReceived GameLogId (Response GameReplay.Flags)
    | ReplayMsg GameLogId GameReplay.Msg
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
    case Decode.decodeValue flagsDecoder value of
        Ok flags ->
            let
                shared : Shared.Model
                shared =
                    Shared.init flags.seed flags.operatingSystem flags.localStorage url key
            in
            handleRoute
                shared
                (Route.fromUrl url)
                (StartingApp shared)

        Err error ->
            ( AppInitError error, E.none )


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map3 Flags
        (Decode.field "operatingSystem" OperatingSystem.decoder)
        (Decode.field "localStorage" LocalStorage.decoder)
        (Decode.field "seed" (Decode.map Random.initialSeed Decode.int))



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

        Home model ->
            Just model.shared

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

        GameLoadFailed _ model ->
            Just model.shared

        Game _ model ->
            Just model.shared

        LoadingMapEditor shared ->
            Just shared

        MapEditorLoadFailed shared _ ->
            Just shared

        MapEditor model ->
            Just model.shared

        LoadingLoggedGames shared ->
            Just shared

        LoggedGamesLoadFailed shared _ ->
            Just shared

        LoggedGames model ->
            Just model.shared

        LoadingReplay shared _ ->
            Just shared

        ReplayLoadFailed shared _ _ ->
            Just shared

        Replay _ model ->
            Just (GameReplay.getShared model)

        NotFound shared ->
            Just shared


setShared : Shared.Model -> Page -> Page
setShared shared page =
    case page of
        AppInitError _ ->
            page

        StartingApp _ ->
            StartingApp shared

        Home model ->
            Home (Home.setShared shared model)

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

        GameLoadFailed id model ->
            GameLoadFailed id (GameLoadFailed.setShared shared model)

        Game id model ->
            Game id (GamePage.setShared shared model)

        LoadingMapEditor _ ->
            LoadingMapEditor shared

        MapEditorLoadFailed _ error ->
            MapEditorLoadFailed shared error

        MapEditor model ->
            MapEditor (MapEditor.setShared shared model)

        LoadingLoggedGames _ ->
            LoadingLoggedGames shared

        LoggedGamesLoadFailed _ error ->
            LoggedGamesLoadFailed shared error

        LoggedGames model ->
            LoggedGames (LoggedGames.setShared shared model)

        LoadingReplay _ id ->
            LoadingReplay shared id

        ReplayLoadFailed _ id error ->
            ReplayLoadFailed shared id error

        Replay id model ->
            Replay id (GameReplay.setShared shared model)

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
        Just Route.LoggedGames ->
            ( LoadingLoggedGames shared, E.request LoggedGamesResponseReceived LoggedGames.load )

        Just (Route.Replay id) ->
            ( LoadingReplay shared id, E.request (ReplayResponseReceived id) (GameReplay.load id) )

        Just Route.MapEditor ->
            ( LoadingMapEditor shared
            , MapEditor.load
                |> E.request MapEditorResponseReceived
            )

        Just Route.Home ->
            ( Home (Home.init shared), E.none )

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
        LoggedGamesResponseReceived result ->
            case page of
                LoadingLoggedGames shared ->
                    case result of
                        Ok flags ->
                            ( LoggedGames (LoggedGames.init shared flags), E.none )

                        Err error ->
                            ( LoggedGamesLoadFailed shared (ApiRequest.errorMessage error), E.none )

                _ ->
                    E.withOut page

        ReplayResponseReceived id result ->
            case page of
                LoadingReplay shared currentId ->
                    if id /= currentId then
                        E.withOut page

                    else
                        case result of
                            Ok flags ->
                                GameReplay.init shared id flags
                                    |> Tuple.mapFirst (Replay id)
                                    |> Tuple.mapSecond (E.map (ReplayMsg id))

                            Err error ->
                                E.withOut (ReplayLoadFailed shared id (ApiRequest.errorMessage error))

                _ ->
                    E.withOut page

        ReplayMsg id replayMsg ->
            case page of
                Replay currentId model ->
                    if id /= currentId then
                        E.withOut page

                    else
                        GameReplay.update replayMsg model
                            |> Tuple.mapFirst (Replay id)
                            |> Tuple.mapSecond (E.map (ReplayMsg id))

                _ ->
                    E.withOut page

        MapEditorResponseReceived result ->
            case page of
                LoadingMapEditor shared ->
                    case result of
                        Ok flags ->
                            MapEditor.init shared flags
                                |> Tuple.mapFirst MapEditor
                                |> Tuple.mapSecond (E.map MapEditorMsg)

                        Err error ->
                            ( MapEditorLoadFailed shared (ApiRequest.errorMessage error), E.none )

                _ ->
                    ( page, E.none )

        MapEditorMsg editorMsg ->
            case page of
                MapEditor model ->
                    MapEditor.update editorMsg model
                        |> Tuple.mapFirst MapEditor
                        |> Tuple.mapSecond (E.map MapEditorMsg)

                _ ->
                    ( page, E.none )

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
        Replay id model ->
            GameReplay.dialog model |> Maybe.map (Dialog.map (ReplayMsg id))

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

                StartingApp _ ->
                    []

                Home model ->
                    List.map (H.map HomeMsg) (Home.view model)

                NewLobby model ->
                    List.map (H.map NewLobbyMsg) (NewLobby.view model)

                LoadingLobby _ _ ->
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
                    List.map (H.map (LobbyMsg id)) (LobbyPage.view model)

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

                LoadingMapEditor _ ->
                    [ H.p [] [ H.text "loading map editor…" ] ]

                MapEditorLoadFailed _ error ->
                    [ H.p [] [ H.text error ]
                    , H.a [ A.href (Route.toString Route.MapEditor) ] [ H.text "retry" ]
                    ]

                MapEditor model ->
                    List.map (H.map MapEditorMsg) (MapEditor.view model)

                LoadingLoggedGames _ ->
                    [ H.p
                        [ Aria.role Aria.Status ]
                        [ H.text "loading logged games…" ]
                    ]

                LoggedGamesLoadFailed _ error ->
                    loadFailure Route.LoggedGames error

                LoggedGames model ->
                    LoggedGames.view model

                LoadingReplay _ _ ->
                    [ H.p
                        [ Aria.role Aria.Status ]
                        [ H.text "loading replay…" ]
                    ]

                ReplayLoadFailed _ id error ->
                    loadFailure (Route.Replay id) error

                Replay id model ->
                    List.map (H.map (ReplayMsg id)) (GameReplay.view model)

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
            Css.Global.global S.global

        shellContent : List (Html Msg)
        shellContent =
            [ globalStyles
            , LoadingBar.styles
            , Home.styles
            , TargetSight.styles
            , TerrainTile.styles
            , TerrainTile.definitions
            , UnitFacing.styles
            , UnitCargo.styles
            , UnitWarnings.styles
            , UnitDeath.styles
            , CombatTheater.styles
            , CombatEffects.styles
            , DepotStock.styles
            , TurnControls.styles
            , TurnIntroduction.styles
            ]
                ++ content
    in
    [ H.main_
        [ A.class TerrainTile.clockClass
        , A.css
            [ S.bgNightwood2
            , S.minHFullViewport
            , S.p4
            , S.textGray4
            , S.col
            , S.g3
            ]
        ]
        shellContent
    ]


loadFailure : Route -> String -> List (Html msg)
loadFailure route error =
    [ Card.toHtml Card.simple
        [ H.p
            [ Aria.role Aria.Status ]
            [ H.text error ]
        , H.a
            [ A.href (Route.toString route)
            , A.css [ S.link ]
            ]
            [ H.text "retry" ]
        , H.a
            [ A.href (Route.toString Route.LoggedGames)
            , A.css [ S.link ]
            ]
            [ H.text "logged games" ]
        , H.a
            [ A.href (Route.toString Route.Home)
            , A.css [ S.link ]
            ]
            [ H.text "home" ]
        ]
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
                LobbyPage.subscriptions model
                    |> Sub.map (LobbyMsg id)

            MapEditor model ->
                MapEditor.subscriptions model |> Sub.map MapEditorMsg

            Replay id model ->
                GameReplay.subscriptions model |> Sub.map (ReplayMsg id)

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
        Replay id model ->
            GameReplay.keyCommands model |> KeyCmd.map (ReplayMsg id)

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
