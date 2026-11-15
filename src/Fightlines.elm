module Fightlines exposing (main)

import Analytics
import ApiRequest
    exposing
        ( Response
        )
import Audio
import Browser
import Browser.Navigation as Navigation
import Deployment
import DevPanel
import Effect as E
    exposing
        ( Eff
        )
import Error
import Fightlines.Flags as Flags
import Fightlines.GameOrigin
    exposing
        ( GameOrigin
        )
import Fightlines.MatchMaking.VisitId exposing (VisitId)
import Fightlines.Page.GameLoadFailed as GameLoadFailed
import Fightlines.Page.GamePage as GamePage
import Fightlines.Page.Home as Home
import Fightlines.Page.JoinLobby as JoinLobby
import Fightlines.Page.LobbyLoadFailed as LobbyLoadFailed
import Fightlines.Page.LobbyPage as LobbyPage
import Fightlines.Page.MatchMaking as MatchMaking
import Fightlines.Page.NewLobby as NewLobby
import Fightlines.Route as Route
    exposing
        ( Route
        )
import Fightlines.View.MobileBattlefield as MobileBattlefield
import Fightlines.View.TurnIntroduction as TurnIntroduction
import Fightlines.View.WelcomeBriefing as WelcomeBriefing
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import Json.Encode as Encode
import KeyCmd
import LobbyId
    exposing
        ( LobbyId
        )
import LocalStorage exposing (LocalStorage)
import Ports.Js.From as FromJs
import SessionId
import Shared
import Style as S
import Subscriptions
import Time
import Url
    exposing
        ( Url
        )
import View.AppControls as AppControls
import View.AppInitError as AppInitError
import View.AppShell as AppShell
import View.Aria as Aria
import View.AudioMute as AudioMute
import View.Button as Button
import View.Card as Card
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = AppInitError Navigation.Key Decode.Error
    | Home Home.Model
    | NewLobby NewLobby.Model
    | LoadingMatchMaking Shared.Model VisitId
    | MatchMakingLoadFailed Shared.Model MatchMaking.Error
    | MatchMaking MatchMaking.Model
    | LoadingLobby Shared.Model LobbyId LobbyPage.Location
    | LobbyLoadFailed LobbyId LobbyLoadFailed.Model
    | JoinLobby LobbyId JoinLobby.Model
    | Lobby LobbyId LobbyPage.Model
    | LoadingGame Shared.Model LobbyId GameOrigin
    | GameLoadFailed LobbyId GameLoadFailed.Model
    | Game LobbyId GamePage.Model
    | NotFound Shared.Model


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | NewLobbyMsg NewLobby.Msg
    | MatchMakingMsg VisitId MatchMaking.Msg
    | MatchMakingResponseReceived VisitId (Response MatchMaking.Flags)
    | MatchMakingRetryButtonClicked
    | JoinLobbyMsg LobbyId JoinLobby.Msg
    | LobbyMsg LobbyId LobbyPage.Location LobbyPage.Msg
    | LobbyResponseReceived LobbyId LobbyPage.Location (Response LobbyPage.Flags)
    | LobbyLoadFailedMsg LobbyId LobbyLoadFailed.Msg
    | GameMsg LobbyId GamePage.Msg
    | GameResponseReceived LobbyId (Response GamePage.Flags)
    | GameLoadFailedMsg LobbyId GameLoadFailed.Msg
    | ReturnHomeButtonClicked
    | HomeMsg Home.Msg
    | GotSharedMsg Shared.Msg
    | DeploymentPollTimerElapsed Time.Posix
    | DeploymentStatusReceived (Response Deployment.Status)
    | AnalyticsResponseReceived (Response Bool)



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
                superUpdate msg page
                    |> Tuple.mapSecond (E.toCmd (getKey page))
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
                    Shared.init
                        flags.now
                        flags.seed
                        flags.sessionId
                        flags.operatingSystem
                        flags.screenSize
                        flags.localStorage
                        url
                        key
            in
            url
                |> Route.fromUrl
                |> handleRoute shared
                |> E.and (E.request DeploymentStatusReceived Deployment.load)
                |> E.and (E.audio (Audio.SetMute shared.audioMute))
                |> E.and (E.audio (Audio.SetVolumes shared.audioVolumes))
                |> E.andThen (recordAnalytics (Analytics.noData "page viewed"))

        Err error ->
            ( AppInitError key error, E.none )



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


getKey : Page -> Navigation.Key
getKey page =
    case page of
        AppInitError key _ ->
            key

        Home model ->
            model.shared.key

        NewLobby model ->
            model.shared.key

        LoadingMatchMaking shared _ ->
            shared.key

        MatchMakingLoadFailed shared _ ->
            shared.key

        MatchMaking model ->
            model.shared.key

        LoadingLobby shared _ _ ->
            shared.key

        LobbyLoadFailed _ model ->
            model.shared.key

        JoinLobby _ model ->
            model.shared.key

        Lobby _ model ->
            model.shared.key

        LoadingGame shared _ _ ->
            shared.key

        GameLoadFailed _ model ->
            model.shared.key

        Game _ model ->
            model.shared.key

        NotFound shared ->
            shared.key


getShared : Page -> Maybe Shared.Model
getShared page =
    case page of
        AppInitError _ _ ->
            Nothing

        Home model ->
            Just model.shared

        NewLobby model ->
            Just model.shared

        LoadingMatchMaking shared _ ->
            Just shared

        MatchMakingLoadFailed shared _ ->
            Just shared

        MatchMaking model ->
            Just model.shared

        LoadingLobby shared _ _ ->
            Just shared

        LobbyLoadFailed _ model ->
            Just model.shared

        JoinLobby _ model ->
            Just model.shared

        Lobby _ model ->
            Just model.shared

        LoadingGame shared _ _ ->
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
        AppInitError _ _ ->
            page

        Home model ->
            Home (Home.setShared shared model)

        NewLobby model ->
            NewLobby (NewLobby.setShared shared model)

        LoadingMatchMaking _ id ->
            LoadingMatchMaking shared id

        MatchMakingLoadFailed _ error ->
            MatchMakingLoadFailed shared error

        MatchMaking model ->
            MatchMaking (MatchMaking.setShared shared model)

        LoadingLobby _ id location ->
            LoadingLobby shared id location

        LobbyLoadFailed id model ->
            LobbyLoadFailed id (LobbyLoadFailed.setShared shared model)

        JoinLobby id model ->
            JoinLobby id (JoinLobby.setShared shared model)

        Lobby id model ->
            Lobby id (LobbyPage.setShared shared model)

        LoadingGame _ id origin ->
            LoadingGame shared id origin

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


loadGame :
    Shared.Model
    -> LobbyId
    -> GameOrigin
    -> ( Page, Eff Msg )
loadGame shared id origin =
    ( LoadingGame shared id origin
    , E.request (GameResponseReceived id) (GamePage.load id)
    )



----------------------------------------------------------------
-- ROUTING --
----------------------------------------------------------------


handleRoute : Shared.Model -> Maybe Route -> ( Page, Eff Msg )
handleRoute shared route =
    case route of
        Just Route.Home ->
            Home.init shared
                |> Tuple.mapBoth Home (E.map HomeMsg)

        Just Route.NewLobby ->
            ( NewLobby (NewLobby.init shared), E.none )

        Just Route.MatchMaking ->
            let
                ( id, nextShared ) =
                    MatchMaking.prepareVisit shared
            in
            ( LoadingMatchMaking nextShared id
            , E.request (MatchMakingResponseReceived id) MatchMaking.load
            )

        Just (Route.Lobby id) ->
            loadLobby LobbyPage.LobbySetup shared id

        Just (Route.LobbyMaps id) ->
            loadLobby LobbyPage.MapLibrary shared id

        Just (Route.Game id origin) ->
            loadGame shared id origin

        Nothing ->
            ( NotFound shared, E.none )



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


superUpdate : Msg -> Page -> ( Page, Eff Msg )
superUpdate msg page =
    update msg page
        |> Dialog.openOnChange dialog page
        |> E.andThen (recordAnalytics (track msg))


recordAnalytics : Analytics.Event -> Page -> ( Page, Eff Msg )
recordAnalytics event page =
    case getShared page of
        Just shared ->
            ( page
            , event
                |> Analytics.withData "sessionId"
                    (Encode.string (SessionId.toString shared.sessionId))
                |> Analytics.withData "page" (Encode.string (analyticsPage page))
                |> withGameLobbyId page
                |> Analytics.toEff AnalyticsResponseReceived
            )

        Nothing ->
            page
                |> E.withOut


withGameLobbyId : Page -> Analytics.Event -> Analytics.Event
withGameLobbyId page event =
    case page of
        LoadingGame _ id _ ->
            withLobbyId id event

        GameLoadFailed id _ ->
            withLobbyId id event

        Game id _ ->
            withLobbyId id event

        _ ->
            event


withLobbyId : LobbyId -> Analytics.Event -> Analytics.Event
withLobbyId id event =
    Analytics.withData "lobbyId"
        (Encode.string (LobbyId.toString id))
        event


track : Msg -> Analytics.Event
track msg =
    case msg of
        LinkClicked _ ->
            Analytics.none

        RouteReceived _ ->
            Analytics.noData "page viewed"

        NewLobbyMsg pageMsg ->
            NewLobby.track pageMsg

        MatchMakingMsg _ pageMsg ->
            MatchMaking.track pageMsg

        MatchMakingResponseReceived _ _ ->
            Analytics.none

        MatchMakingRetryButtonClicked ->
            Analytics.noData "retry clicked"

        JoinLobbyMsg _ pageMsg ->
            JoinLobby.track pageMsg

        LobbyMsg _ _ pageMsg ->
            LobbyPage.track pageMsg

        LobbyResponseReceived _ _ _ ->
            Analytics.none

        LobbyLoadFailedMsg _ pageMsg ->
            LobbyLoadFailed.track pageMsg

        GameMsg _ pageMsg ->
            GamePage.track pageMsg

        GameResponseReceived _ _ ->
            Analytics.none

        GameLoadFailedMsg _ pageMsg ->
            GameLoadFailed.track pageMsg

        ReturnHomeButtonClicked ->
            Analytics.noData "return home clicked"

        HomeMsg pageMsg ->
            Home.track pageMsg

        GotSharedMsg _ ->
            Analytics.none

        DeploymentPollTimerElapsed _ ->
            Analytics.none

        DeploymentStatusReceived _ ->
            Analytics.none

        AnalyticsResponseReceived _ ->
            Analytics.none


analyticsPage : Page -> String
analyticsPage page =
    case page of
        AppInitError _ _ ->
            "app init error"

        Home _ ->
            "home"

        NewLobby _ ->
            "new lobby"

        LoadingMatchMaking _ _ ->
            "matchmaking"

        MatchMakingLoadFailed _ _ ->
            "matchmaking load failed"

        MatchMaking _ ->
            "matchmaking"

        LoadingLobby _ _ location ->
            lobbyAnalyticsPage location

        LobbyLoadFailed _ _ ->
            "lobby load failed"

        JoinLobby _ _ ->
            "join lobby"

        Lobby _ model ->
            lobbyAnalyticsPage (LobbyPage.currentLocation model)

        LoadingGame _ _ _ ->
            "game"

        GameLoadFailed _ _ ->
            "game load failed"

        Game _ _ ->
            "game"

        NotFound _ ->
            "not found"


lobbyAnalyticsPage : LobbyPage.Location -> String
lobbyAnalyticsPage location =
    case location of
        LobbyPage.LobbySetup ->
            "lobby"

        LobbyPage.MapLibrary ->
            "lobby maps"


update : Msg -> Page -> ( Page, Eff Msg )
update msg page =
    case msg of
        AnalyticsResponseReceived result ->
            case result of
                Ok _ ->
                    page |> E.withOut

                Err error ->
                    page
                        |> mapShared (Shared.addError (Just (Error.AnalyticsRecordingFailed error)))
                        |> E.withOut

        DeploymentPollTimerElapsed _ ->
            ( page, E.request DeploymentStatusReceived Deployment.load )

        DeploymentStatusReceived result ->
            case getShared page of
                Just shared ->
                    let
                        ( deployment, failure ) =
                            Deployment.receive result shared.deployment

                        updatedShared : Shared.Model
                        updatedShared =
                            { shared | deployment = deployment }
                                |> Shared.addError (Maybe.map Error.DeploymentStatusFailed failure)
                    in
                    ( setShared updatedShared page, E.none )

                Nothing ->
                    ( page, E.none )

        ReturnHomeButtonClicked ->
            case getShared page of
                Just shared ->
                    ( page, Route.navigate shared.deployment Route.Home )

                Nothing ->
                    ( page, E.none )

        HomeMsg homeMsg ->
            case page of
                Home model ->
                    let
                        ( nextModel, eff ) =
                            Home.update homeMsg model
                    in
                    ( Home nextModel, E.map HomeMsg eff )

                _ ->
                    page
                        |> E.withOut

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    case Route.fromUrl url of
                        Just route ->
                            case getShared page of
                                Just shared ->
                                    ( page, Route.navigate shared.deployment route )

                                Nothing ->
                                    ( page, E.none )

                        Nothing ->
                            ( page, E.loadUrl (Url.toString url) )

                Browser.External url ->
                    ( page, E.loadUrl url )

        RouteReceived route ->
            case getShared page of
                Just shared ->
                    let
                        departure : Eff Msg
                        departure =
                            case page of
                                Game _ model ->
                                    GamePage.stopPlaybackAudio model

                                MatchMaking model ->
                                    if route == Just Route.MatchMaking then
                                        E.none

                                    else
                                        MatchMaking.leave model
                                            |> E.map (MatchMakingMsg (MatchMaking.visitId model))

                                _ ->
                                    E.none
                    in
                    handleRoute shared route
                        |> E.and departure

                Nothing ->
                    page
                        |> E.withOut

        NewLobbyMsg pageMsg ->
            case page of
                NewLobby model ->
                    NewLobby.update pageMsg model
                        |> Tuple.mapFirst NewLobby
                        |> Tuple.mapSecond (E.map NewLobbyMsg)

                _ ->
                    ( page, E.none )

        MatchMakingResponseReceived id result ->
            case page of
                LoadingMatchMaking shared current ->
                    if id == current then
                        case result of
                            Ok flags ->
                                MatchMaking.init id shared flags
                                    |> Tuple.mapFirst MatchMaking
                                    |> Tuple.mapSecond (E.map (MatchMakingMsg id))

                            Err error ->
                                ( MatchMakingLoadFailed shared (MatchMaking.fromLoadError error)
                                , if ApiRequest.requiresCurrentDeployment error then
                                    Route.load Route.MatchMaking

                                  else
                                    E.none
                                )

                    else
                        ( page, E.none )

                _ ->
                    ( page, E.none )

        MatchMakingRetryButtonClicked ->
            case page of
                MatchMakingLoadFailed shared _ ->
                    ( page, Route.navigate shared.deployment Route.MatchMaking )

                _ ->
                    ( page, E.none )

        MatchMakingMsg id pageMsg ->
            case page of
                MatchMaking model ->
                    if id == MatchMaking.visitId model then
                        MatchMaking.update pageMsg model
                            |> Tuple.mapFirst MatchMaking
                            |> Tuple.mapSecond (E.map (MatchMakingMsg id))

                    else
                        ( page, E.none )

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
                LoadingGame shared currentId origin ->
                    if id == currentId then
                        case result of
                            Ok flags ->
                                let
                                    ( model, eff ) =
                                        GamePage.init shared origin flags
                                in
                                ( Game id model
                                , E.map (GameMsg id) eff
                                )

                            Err error ->
                                ( GameLoadFailed id
                                    (GameLoadFailed.init shared id origin error)
                                , E.none
                                )

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

        GotSharedMsg subMsg ->
            case getShared page of
                Just shared ->
                    let
                        ( newShared, effect ) =
                            Shared.update subMsg shared
                    in
                    ( setShared newShared page
                    , E.map GotSharedMsg effect
                    )

                Nothing ->
                    page
                        |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Page -> Browser.Document Msg
view page =
    let
        shared : Maybe Shared.Model
        shared =
            getShared page

        overlayContent : List (Html Msg)
        overlayContent =
            [ AppControls.toHtml
                (Maybe.map .operatingSystem shared)
                audioContent
            ]

        audioContent : List (Html Msg)
        audioContent =
            case shared of
                Just model ->
                    [ AudioMute.toHtml
                        { mute = model.audioMute
                        , onClick = GotSharedMsg Shared.audioMuteButtonClicked
                        }
                    ]

                Nothing ->
                    []

        dialogContent : List (Html Msg)
        dialogContent =
            case
                ( dialog page
                , shared
                )
            of
                ( Just activeDialog, Just model ) ->
                    [ activeDialog
                        |> Dialog.withOverlay overlayContent
                        |> Dialog.toHtml model.operatingSystem
                    ]

                _ ->
                    overlayContent

        content : List (Html Msg)
        content =
            shell page ++ dialogContent
    in
    { title = "fightlines"
    , body = List.map H.toUnstyled content
    }


{-| The dev panel takes priority over the active page's dialog.
-}
dialog : Page -> Maybe (Dialog Msg)
dialog page =
    case getShared page of
        Just shared ->
            if shared.devPanelOpen then
                DevPanel.dialog
                    (Shared.devPanelErrors shared)
                    shared.features
                    shared.devPanel
                    |> Dialog.map (Shared.devPanelMsg >> GotSharedMsg)
                    |> Just

            else
                pageDialog page

        Nothing ->
            Nothing


pageDialog : Page -> Maybe (Dialog Msg)
pageDialog page =
    case page of
        Home model ->
            Home.dialog model
                |> Maybe.map (Dialog.map HomeMsg)

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
                AppInitError _ error ->
                    AppInitError.view error

                Home model ->
                    List.map (H.map HomeMsg) (Home.view model)

                NewLobby model ->
                    List.map (H.map NewLobbyMsg) (NewLobby.view model)

                LoadingMatchMaking _ _ ->
                    MatchMaking.loadingView

                MatchMakingLoadFailed _ error ->
                    MatchMaking.loadFailedView
                        { error = error
                        , onRetry = MatchMakingRetryButtonClicked
                        }

                MatchMaking model ->
                    List.map (H.map (MatchMakingMsg (MatchMaking.visitId model))) (MatchMaking.view model)

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

                LoadingGame _ _ _ ->
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
    AppShell.toHtml
        (Home.styles
            :: MobileBattlefield.rotationStyles
            :: TurnIntroduction.styles
            :: WelcomeBriefing.styles
            :: content
        )



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Page -> Sub Msg
subscriptions page =
    [ case getShared page of
        Just shared ->
            Sub.batch
                [ Time.every 10000 DeploymentPollTimerElapsed
                , Shared.subscriptions |> Sub.map GotSharedMsg
                , Subscriptions.common
                    { operatingSystem = shared.operatingSystem
                    , keyCommands = keyCommands page
                    , listeners = listeners page
                    , onFromJsError =
                        Shared.gotFromJsError >> GotSharedMsg
                    }
                ]

        Nothing ->
            Sub.none
    , pageSubscriptions page
    ]
        |> Sub.batch


pageSubscriptions : Page -> Sub Msg
pageSubscriptions page =
    Sub.batch
        [ case page of
            Home _ ->
                Home.subscriptions |> Sub.map HomeMsg

            MatchMaking model ->
                MatchMaking.subscriptions model
                    |> Sub.map (MatchMakingMsg (MatchMaking.visitId model))

            Lobby id model ->
                LobbyPage.subscriptions model
                    |> Sub.map (LobbyMsg id (LobbyPage.currentLocation model))

            Game id model ->
                GamePage.subscriptions model
                    |> Sub.map (GameMsg id)

            _ ->
                Sub.none
        ]


keyCommands : Page -> KeyCmd.KeyCmd Msg
keyCommands page =
    let
        panelCommands : KeyCmd.KeyCmd Msg
        panelCommands =
            Shared.keyCommands
                |> KeyCmd.map GotSharedMsg

        activePageCommands : KeyCmd.KeyCmd Msg
        activePageCommands =
            case getShared page of
                Just shared ->
                    if shared.devPanelOpen then
                        KeyCmd.none

                    else
                        pageKeyCommands page

                Nothing ->
                    KeyCmd.none
    in
    KeyCmd.batch [ panelCommands, activePageCommands ]


pageKeyCommands : Page -> KeyCmd.KeyCmd Msg
pageKeyCommands page =
    case page of
        Game id model ->
            GamePage.keyCommands model |> KeyCmd.map (GameMsg id)

        _ ->
            KeyCmd.none


listeners : Page -> List (FromJs.Listener Msg)
listeners page =
    [ Shared.listeners
        |> FromJs.map GotSharedMsg
    , pageListeners page
    ]


pageListeners : Page -> FromJs.Listener Msg
pageListeners page =
    case page of
        Lobby id model ->
            LobbyPage.listeners
                |> FromJs.map (LobbyMsg id (LobbyPage.currentLocation model))

        _ ->
            FromJs.none
