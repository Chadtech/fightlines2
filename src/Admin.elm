module Admin exposing
    ( Model
    , Msg(..)
    , Page(..)
    , PageMsg(..)
    , init
    , main
    , update
    )

import Admin.Flags as Flags
import Admin.Page.Dashboard as Dashboard
import Admin.Page.Login as Login
import Admin.Route as Route exposing (Route)
import Api.Enum.SessionStatus as Session exposing (SessionStatus)
import Api.Mutation
import Api.Query
import ApiRequest exposing (Response)
import Audio
import Browser
import Browser.Navigation as Navigation
import Effect as E exposing (Eff)
import Game.LogId exposing (GameLogId)
import Game.Replay as Replay
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Json.Decode as Decode
import KeyCmd
import Ports.Js.From as FromJs
import Shared
import Style as S
import Subscriptions
import Time
import Url exposing (Url)
import View.AppControls as AppControls
import View.AppInitError as AppInitError
import View.AppShell as AppShell
import View.Aria as Aria
import View.AudioMute as AudioMute
import View.Button as Button
import View.Card as Card
import View.Dialog as Dialog



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = InitError Decode.Error
    | Checking Shared.Model (Maybe Route)
    | Login (Maybe Route) Login.Model
    | LoadingDashboard Shared.Model
    | Dashboard Dashboard.Model
    | LoadingReplay Shared.Model GameLogId
    | Replay Replay.Model
    | SigningOut Shared.Model
    | LogoutFailed Shared.Model String
    | Failed Shared.Model (Maybe Route) String
    | Disabled Shared.Model
    | NotFound Shared.Model


type alias Model =
    { page : Page
    , visitId : VisitId
    }


type VisitId
    = VisitId Int


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | SharedMsg Shared.Msg
    | PageMsg VisitId PageMsg


type PageMsg
    = SessionResponseReceived (Response SessionStatus)
    | LoginMsg Login.Msg
    | DashboardResponseReceived (Response Dashboard.Flags)
    | DashboardMsg Dashboard.Msg
    | ReplayResponseReceived (Response Replay.Flags)
    | ReplayMsg Replay.Msg
    | LogoutResponseReceived (Response Bool)
    | RetryButtonClicked
    | SessionTimerElapsed Time.Posix
    | ReplaySessionResponseReceived (Response SessionStatus)



----------------------------------------------------------------
-- MAIN --
----------------------------------------------------------------


main : Program Decode.Value Model Msg
main =
    Browser.application
        { init = \value url key -> init value url key |> Tuple.mapSecond (E.toCmd key)
        , update = updateWithEffects
        , view = \model -> view model.visitId model.page
        , subscriptions = \model -> subscriptions model.visitId model.page
        , onUrlRequest = LinkClicked
        , onUrlChange = RouteReceived << Route.fromUrl
        }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Decode.Value -> Url -> Navigation.Key -> ( Model, Eff Msg )
init value url key =
    case Decode.decodeValue Flags.decoder value of
        Err error ->
            ( { page = InitError error, visitId = VisitId 0 }, E.none )

        Ok flags ->
            let
                shared : Shared.Model
                shared =
                    Shared.init flags.now flags.seed flags.operatingSystem flags.localStorage url key
            in
            handleRoute shared (Route.fromUrl url)
                |> E.and (E.audio (Audio.SetMute shared.audioMute))
                |> E.and (E.audio (Audio.SetVolumes shared.audioVolumes))
                |> Tuple.mapFirst (\page -> { page = page, visitId = VisitId 0 })
                |> Tuple.mapSecond (E.map (PageMsg (VisitId 0)))



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


getShared : Page -> Maybe Shared.Model
getShared page =
    case page of
        InitError _ ->
            Nothing

        Checking shared _ ->
            Just shared

        Login _ model ->
            Just model.shared

        LoadingDashboard shared ->
            Just shared

        Dashboard model ->
            Just model.shared

        LoadingReplay shared _ ->
            Just shared

        Replay model ->
            Just model.shared

        SigningOut shared ->
            Just shared

        LogoutFailed shared _ ->
            Just shared

        Failed shared _ _ ->
            Just shared

        Disabled shared ->
            Just shared

        NotFound shared ->
            Just shared


setShared : Shared.Model -> Page -> Page
setShared shared page =
    case page of
        InitError error ->
            InitError error

        Checking _ route ->
            Checking shared route

        Login route model ->
            Login route (Login.setShared shared model)

        LoadingDashboard _ ->
            LoadingDashboard shared

        Dashboard model ->
            Dashboard (Dashboard.setShared shared model)

        LoadingReplay _ id ->
            LoadingReplay shared id

        Replay model ->
            Replay (Replay.setShared shared model)

        SigningOut _ ->
            SigningOut shared

        LogoutFailed _ error ->
            LogoutFailed shared error

        Failed _ route error ->
            Failed shared route error

        Disabled _ ->
            Disabled shared

        NotFound _ ->
            NotFound shared


handleRoute : Shared.Model -> Maybe Route -> ( Page, Eff PageMsg )
handleRoute shared route =
    case route of
        Just Route.SignOut ->
            loadRoute shared route

        _ ->
            ( Checking shared route
            , Api.Query.adminSession
                |> ApiRequest.queryRequest
                |> E.request SessionResponseReceived
            )


loadRoute : Shared.Model -> Maybe Route -> ( Page, Eff PageMsg )
loadRoute shared route =
    case route of
        Just Route.Dashboard ->
            ( LoadingDashboard shared, Dashboard.load |> E.request DashboardResponseReceived )

        Just (Route.Replay id) ->
            ( LoadingReplay shared id, Replay.load id |> E.request ReplayResponseReceived )

        Just Route.SignOut ->
            ( SigningOut shared
            , Api.Mutation.adminLogout
                |> ApiRequest.mutationRequest
                |> E.request LogoutResponseReceived
            )

        Nothing ->
            ( NotFound shared, E.none )


loginPage : Shared.Model -> Maybe Route -> Page
loginPage shared route =
    Login route (Login.init shared)


replayNeedsLogin : Replay.Msg -> Bool
replayNeedsLogin msg =
    case msg of
        Replay.TurnResponseReceived _ (Err error) ->
            ApiRequest.requiresAdminLogin error

        _ ->
            False


playbackAudio : Page -> Page -> Eff PageMsg
playbackAudio before after =
    let
        moving : Page -> List Audio.MovingUnit
        moving page =
            case page of
                Replay model ->
                    Replay.movingUnits model

                _ ->
                    []

        ambient : Page -> List Audio.AmbientScene
        ambient page =
            case page of
                Replay model ->
                    Replay.ambience model

                _ ->
                    []

        firing : Page -> List Audio.FiringInfantry
        firing page =
            case page of
                Replay model ->
                    Replay.firingInfantry model

                _ ->
                    []
    in
    E.batch
        [ E.audio
            (Audio.syncMovement
                { before = moving before
                , after = moving after
                }
            )
        , E.audio
            (Audio.syncAmbience
                { before = ambient before
                , after = ambient after
                }
            )
        , E.audio
            (Audio.syncInfantryFire
                { before = firing before
                , after = firing after
                }
            )
        ]


updateWithEffects : Msg -> Model -> ( Model, Cmd Msg )
updateWithEffects msg model =
    let
        ( next, effect ) =
            update msg model

        audio : Eff Msg
        audio =
            playbackAudio model.page next.page
                |> E.map (PageMsg next.visitId)
    in
    case getShared next.page of
        Just shared ->
            ( next
            , E.toCmd shared.key
                (E.batch
                    [ effect
                    , audio
                    ]
                )
            )

        Nothing ->
            ( next, Cmd.none )


nextVisitId : VisitId -> VisitId
nextVisitId (VisitId value) =
    VisitId (value + 1)


{-| Keep async events with their loaded page; entering a loading, login or failure
state starts a new visit, including when navigating back to the same route.
-}
transition : Model -> ( Page, Eff PageMsg ) -> ( Model, Eff Msg )
transition model ( page, effect ) =
    let
        visitId : VisitId
        visitId =
            case ( model.page, page ) of
                ( Login _ _, Login _ _ ) ->
                    model.visitId

                ( Dashboard _, Dashboard _ ) ->
                    model.visitId

                ( Replay _, Replay _ ) ->
                    model.visitId

                _ ->
                    nextVisitId model.visitId
    in
    ( { model | page = page, visitId = visitId }
    , E.map (PageMsg visitId) effect
    )


requiresCurrentDeployment : PageMsg -> Bool
requiresCurrentDeployment event =
    case event of
        SessionResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        DashboardResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        DashboardMsg inner ->
            Dashboard.requiresCurrentDeployment inner

        ReplayResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        ReplayMsg (Replay.TurnResponseReceived _ (Err error)) ->
            ApiRequest.requiresCurrentDeployment error

        ReplaySessionResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        LogoutResponseReceived (Err error) ->
            ApiRequest.requiresCurrentDeployment error

        LoginMsg (Login.LoginResponseReceived (Err error)) ->
            ApiRequest.requiresCurrentDeployment error

        _ ->
            False



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    case Route.fromUrl url of
                        Just route ->
                            ( model, Route.pushUrl route )

                        Nothing ->
                            ( model, E.loadUrl (Url.toString url) )

                Browser.External url ->
                    ( model, E.loadUrl url )

        RouteReceived route ->
            case getShared model.page of
                Nothing ->
                    model |> E.withOut

                Just shared ->
                    transition model (handleRoute shared route)

        SharedMsg inner ->
            case getShared model.page of
                Nothing ->
                    model |> E.withOut

                Just shared ->
                    Shared.superUpdate inner shared
                        |> Tuple.mapFirst (\next -> { model | page = setShared next model.page })
                        |> Tuple.mapSecond (E.map SharedMsg)

        PageMsg visitId subMsg ->
            if visitId /= model.visitId then
                model |> E.withOut

            else if requiresCurrentDeployment subMsg then
                ( model, Route.load Route.Dashboard )

            else
                let
                    page : Page
                    page =
                        model.page

                    pageUpdate : ( Page, Eff PageMsg )
                    pageUpdate =
                        case subMsg of
                            SessionResponseReceived result ->
                                case page of
                                    Checking shared route ->
                                        case result of
                                            Ok Session.SignedIn ->
                                                loadRoute shared route

                                            Ok Session.SignedOut ->
                                                loginPage shared route |> E.withOut

                                            Ok Session.Disabled ->
                                                Disabled shared |> E.withOut

                                            Err error ->
                                                Failed shared route (ApiRequest.errorMessage error) |> E.withOut

                                    _ ->
                                        page |> E.withOut

                            LoginMsg inner ->
                                case page of
                                    Login route login ->
                                        case inner of
                                            Login.LoginResponseReceived (Ok Session.SignedIn) ->
                                                loadRoute login.shared route

                                            _ ->
                                                Login.update inner login
                                                    |> Tuple.mapFirst (Login route)
                                                    |> Tuple.mapSecond (E.map LoginMsg)

                                    _ ->
                                        page |> E.withOut

                            DashboardResponseReceived result ->
                                case page of
                                    LoadingDashboard shared ->
                                        case result of
                                            Ok flags ->
                                                Dashboard (Dashboard.init shared flags) |> E.withOut

                                            Err error ->
                                                if ApiRequest.requiresAdminLogin error then
                                                    loginPage shared (Just Route.Dashboard) |> E.withOut

                                                else
                                                    Failed shared (Just Route.Dashboard) (ApiRequest.errorMessage error) |> E.withOut

                                    _ ->
                                        page |> E.withOut

                            DashboardMsg inner ->
                                case page of
                                    Dashboard dashboard ->
                                        if Dashboard.needsLogin inner then
                                            loginPage dashboard.shared (Just Route.Dashboard) |> E.withOut

                                        else
                                            Dashboard.update inner dashboard
                                                |> Tuple.mapFirst Dashboard
                                                |> Tuple.mapSecond (E.map DashboardMsg)

                                    _ ->
                                        page |> E.withOut

                            ReplayResponseReceived result ->
                                case page of
                                    LoadingReplay shared id ->
                                        case result of
                                            Ok flags ->
                                                Replay.init
                                                    { returnUrl = Route.toString Route.Dashboard
                                                    }
                                                    shared
                                                    id
                                                    flags
                                                    |> Tuple.mapFirst Replay
                                                    |> Tuple.mapSecond (E.map ReplayMsg)

                                            Err error ->
                                                if ApiRequest.requiresAdminLogin error then
                                                    loginPage shared (Just (Route.Replay id)) |> E.withOut

                                                else
                                                    Failed shared (Just (Route.Replay id)) (ApiRequest.errorMessage error) |> E.withOut

                                    _ ->
                                        page |> E.withOut

                            ReplayMsg inner ->
                                case page of
                                    Replay replay ->
                                        if replayNeedsLogin inner then
                                            loginPage replay.shared (Just (Route.Replay replay.id)) |> E.withOut

                                        else
                                            Replay.update inner replay
                                                |> Tuple.mapFirst Replay
                                                |> Tuple.mapSecond (E.map ReplayMsg)

                                    _ ->
                                        page |> E.withOut

                            LogoutResponseReceived result ->
                                case page of
                                    SigningOut shared ->
                                        case result of
                                            Ok _ ->
                                                ( loginPage shared (Just Route.Dashboard)
                                                , E.replaceUrl (Route.toString Route.Dashboard)
                                                )

                                            Err error ->
                                                LogoutFailed
                                                    shared
                                                    ("could not log out. " ++ ApiRequest.errorMessage error)
                                                    |> E.withOut

                                    _ ->
                                        page |> E.withOut

                            RetryButtonClicked ->
                                case page of
                                    Failed shared route _ ->
                                        handleRoute shared route

                                    _ ->
                                        page |> E.withOut

                            SessionTimerElapsed _ ->
                                case page of
                                    Replay _ ->
                                        ( page
                                        , Api.Query.adminSession
                                            |> ApiRequest.queryRequest
                                            |> E.request ReplaySessionResponseReceived
                                        )

                                    _ ->
                                        page |> E.withOut

                            ReplaySessionResponseReceived result ->
                                case page of
                                    Replay replay ->
                                        case result of
                                            Ok Session.SignedOut ->
                                                loginPage replay.shared (Just (Route.Replay replay.id)) |> E.withOut

                                            Ok Session.Disabled ->
                                                Disabled replay.shared |> E.withOut

                                            _ ->
                                                page |> E.withOut

                                    _ ->
                                        page |> E.withOut
                in
                transition model pageUpdate



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : VisitId -> Page -> Browser.Document Msg
view visitId page =
    let
        controls : List (Html Msg)
        controls =
            getShared page
                |> Maybe.map
                    (\shared ->
                        [ AudioMute.toHtml
                            { mute = shared.audioMute
                            , onClick = SharedMsg Shared.audioMuteButtonClicked
                            }
                        ]
                    )
                |> Maybe.withDefault []

        overlays : List (Html Msg)
        overlays =
            [ AppControls.toHtml controls
            ]

        dialog : List (Html Msg)
        dialog =
            case page of
                Replay replay ->
                    Replay.dialog replay
                        |> Maybe.map
                            (Dialog.map (PageMsg visitId << ReplayMsg)
                                >> Dialog.withOverlay overlays
                                >> Dialog.toHtml
                                >> List.singleton
                            )
                        |> Maybe.withDefault []

                _ ->
                    []

        logout : List (Html PageMsg)
        logout =
            case page of
                Replay _ ->
                    [ H.header
                        [ A.css
                            [ S.row
                            , S.justifyEnd
                            ]
                        ]
                        [ Card.toHtml Card.simple
                            [ H.a
                                [ A.href (Route.toString Route.SignOut)
                                , A.css
                                    [ S.link
                                    ]
                                ]
                                [ H.text "log out"
                                ]
                            ]
                        ]
                    ]

                _ ->
                    []

        pageContent : List (Html Msg)
        pageContent =
            List.map (H.map (PageMsg visitId)) (logout ++ pageView page)

        content : List (Html Msg)
        content =
            [ H.div
                [ A.css
                    [ S.col
                    , S.g4
                    , S.pt12
                    , S.belowWidth 400
                        [ S.pt24
                        ]
                    ]
                ]
                pageContent
            ]

        shell : List (Html Msg)
        shell =
            AppShell.toHtml content ++ overlays ++ dialog
    in
    { title = "fightlines admin"
    , body = List.map H.toUnstyled shell
    }


pageView : Page -> List (Html PageMsg)
pageView page =
    case page of
        InitError error ->
            AppInitError.view error

        Checking _ _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "checking admin session…"
                ]
            ]

        Login _ model ->
            List.map (H.map LoginMsg) (Login.view model)

        LoadingDashboard _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "loading dashboard…"
                ]
            ]

        Dashboard model ->
            List.map (H.map DashboardMsg) (Dashboard.view model)

        LoadingReplay _ _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "loading replay…"
                ]
            ]

        Replay model ->
            List.map (H.map ReplayMsg) (Replay.view model)

        SigningOut _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "logging out…"
                ]
            ]

        LogoutFailed _ error ->
            [ H.p
                [ Aria.role Aria.Alert
                ]
                [ H.text error
                ]
            , H.a
                [ A.href (Route.toString Route.SignOut)
                , A.css
                    [ S.link
                    ]
                ]
                [ H.text "retry logout"
                ]
            ]

        Failed _ _ error ->
            [ H.p
                [ Aria.role Aria.Alert
                ]
                [ H.text error
                ]
            , Button.secondary "retry" RetryButtonClicked
                |> Button.toHtml
            ]

        Disabled _ ->
            [ H.p
                []
                [ H.text "admin access has not been configured on this server."
                ]
            ]

        NotFound _ ->
            [ H.p
                []
                [ H.text "admin page not found."
                ]
            ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : VisitId -> Page -> Sub Msg
subscriptions visitId page =
    let
        common : Sub Msg
        common =
            case getShared page of
                Nothing ->
                    Sub.none

                Just shared ->
                    Sub.batch
                        [ Shared.subscriptions |> Sub.map SharedMsg
                        , Subscriptions.common
                            { operatingSystem = shared.operatingSystem
                            , keyCommands = pageKeyCommands page |> KeyCmd.map (PageMsg visitId)
                            , listeners =
                                [ Shared.listeners |> FromJs.map SharedMsg
                                ]
                            , onFromJsError = SharedMsg << Shared.gotFromJsError
                            }
                        ]

        pageSubscriptions : Sub PageMsg
        pageSubscriptions =
            case page of
                Dashboard _ ->
                    Dashboard.subscriptions |> Sub.map DashboardMsg

                Replay replay ->
                    Sub.batch
                        [ Replay.subscriptions replay |> Sub.map ReplayMsg
                        , Time.every 30000 SessionTimerElapsed
                        ]

                _ ->
                    Sub.none
    in
    Sub.batch
        [ common
        , pageSubscriptions |> Sub.map (PageMsg visitId)
        ]


pageKeyCommands : Page -> KeyCmd.KeyCmd PageMsg
pageKeyCommands page =
    case page of
        Replay replay ->
            Replay.keyCommands replay |> KeyCmd.map ReplayMsg

        _ ->
            KeyCmd.none
