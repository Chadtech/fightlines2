module DevTools exposing (main)

import ApiRequest
    exposing
        ( Response
        )
import Browser
import Browser.Navigation as Navigation
import DevPanel
import DevTools.Flags as Flags
import DevTools.Page.BackdropReview as BackdropReview
import DevTools.Page.GameReplay as GameReplay
import DevTools.Page.LoggedGames as LoggedGames
import DevTools.Page.MapEditor as MapEditor
import DevTools.Route as Route
    exposing
        ( Route
        )
import DevTools.Shared as Shared
import Effect as E
    exposing
        ( Eff
        )
import Game.LogId exposing (GameLogId)
import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Json.Decode as Decode
import KeyCmd
import Ports.Js.From as FromJs
import Ports.Js.To as ToJs
import Random
import Style as S
import Subscriptions
import Url
    exposing
        ( Url
        )
import View.AppInitError as AppInitError
import View.AppShell as AppShell
import View.Aria as Aria
import View.Card as Card
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Page
    = AppInitError Decode.Error
    | LoadingBackdropReview Shared.Model BackdropReviewLoadId
    | BackdropReviewLoadFailed Shared.Model String
    | BackdropReview BackdropReview.Model
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


type BackdropReviewLoadId
    = BackdropReviewLoadId Int


type Msg
    = LinkClicked Browser.UrlRequest
    | RouteReceived (Maybe Route)
    | BackdropReviewResponseReceived BackdropReviewLoadId (Response BackdropReview.Flags)
    | MapEditorResponseReceived (ApiRequest.Response MapEditor.Flags)
    | MapEditorMsg MapEditor.Msg
    | BackdropReviewMsg BackdropReview.Msg
    | LoggedGamesResponseReceived (Response LoggedGames.Flags)
    | ReplayResponseReceived GameLogId (Response GameReplay.Flags)
    | ReplayMsg GameLogId GameReplay.Msg
    | GotSharedMsg Shared.Msg



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
                            |> restorePageDialog page
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
                    Shared.init flags.seed flags.operatingSystem flags.localStorage key
            in
            handleRoute shared (Route.fromUrl url)

        Err error ->
            ( AppInitError error, E.none )



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


{-| Restore the page dialog only when the higher-priority dev panel closes.
-}
restorePageDialog : Page -> ( Page, Eff Msg ) -> ( Page, Eff Msg )
restorePageDialog previous ( page, effect ) =
    let
        panelClosed : Bool
        panelClosed =
            (Maybe.map .devPanelOpen (getShared previous) == Just True)
                && (Maybe.map .devPanelOpen (getShared page) == Just False)

        result : ( Page, Eff Msg )
        result =
            ( page, effect )
    in
    if panelClosed then
        case pageDialog page of
            Just activeDialog ->
                result
                    |> E.and (E.toJs (ToJs.OpenDialog { htmlId = Dialog.htmlId activeDialog }))

            Nothing ->
                result

    else
        result


getShared : Page -> Maybe Shared.Model
getShared page =
    case page of
        AppInitError _ ->
            Nothing

        LoadingBackdropReview shared _ ->
            Just shared

        BackdropReviewLoadFailed shared _ ->
            Just shared

        BackdropReview model ->
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

        LoadingBackdropReview _ requestId ->
            LoadingBackdropReview shared requestId

        BackdropReviewLoadFailed _ error ->
            BackdropReviewLoadFailed shared error

        BackdropReview model ->
            BackdropReview (BackdropReview.setShared shared model)

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


loadBackdropReview : Shared.Model -> ( Page, Eff Msg )
loadBackdropReview shared =
    let
        ( value, seed ) =
            Random.step (Random.int 0 2147483647) shared.seed

        requestId : BackdropReviewLoadId
        requestId =
            BackdropReviewLoadId value
    in
    ( LoadingBackdropReview (Shared.setSeed seed shared) requestId
    , E.request (BackdropReviewResponseReceived requestId) BackdropReview.load
    )



----------------------------------------------------------------
-- ROUTING --
----------------------------------------------------------------


handleRoute : Shared.Model -> Maybe Route -> ( Page, Eff Msg )
handleRoute shared route =
    case route of
        Just Route.LoggedGames ->
            ( LoadingLoggedGames shared, E.request LoggedGamesResponseReceived LoggedGames.load )

        Just (Route.Replay id) ->
            ( LoadingReplay shared id, E.request (ReplayResponseReceived id) (GameReplay.load id) )

        Just Route.BackdropReview ->
            loadBackdropReview shared

        Just Route.MapEditor ->
            ( LoadingMapEditor shared
            , MapEditor.load
                |> E.request MapEditorResponseReceived
            )

        Nothing ->
            ( NotFound shared, E.none )



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Page -> ( Page, Eff Msg )
update msg page =
    case msg of
        BackdropReviewResponseReceived requestId result ->
            case page of
                LoadingBackdropReview shared currentId ->
                    if requestId /= currentId then
                        ( page, E.none )

                    else
                        case result of
                            Ok flags ->
                                ( BackdropReview (BackdropReview.init shared flags), E.none )

                            Err error ->
                                ( BackdropReviewLoadFailed shared (ApiRequest.errorMessage error), E.none )

                _ ->
                    ( page, E.none )

        BackdropReviewMsg reviewMsg ->
            case page of
                BackdropReview model ->
                    BackdropReview.update reviewMsg model
                        |> Tuple.mapFirst BackdropReview
                        |> Tuple.mapSecond (E.map BackdropReviewMsg)

                _ ->
                    ( page, E.none )

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

        GotSharedMsg subMsg ->
            case getShared page of
                Just shared ->
                    let
                        ( newShared, effect ) =
                            Shared.update subMsg shared
                    in
                    ( setShared newShared page, E.map GotSharedMsg effect )

                Nothing ->
                    page
                        |> E.withOut



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
            AppShell.toHtml (shell page) ++ dialogContent
    in
    { title = "fightlines dev tools"
    , body = List.map H.toUnstyled content
    }


{-| The dev panel takes priority over the active page's dialog.
-}
dialog : Page -> Maybe (Dialog Msg)
dialog page =
    case getShared page of
        Just shared ->
            if shared.devPanelOpen then
                DevPanel.dialog (Shared.devPanelErrors shared) shared.devPanel
                    |> Dialog.map (Shared.devPanelMsg >> GotSharedMsg)
                    |> Just

            else
                pageDialog page

        Nothing ->
            Nothing


pageDialog : Page -> Maybe (Dialog Msg)
pageDialog page =
    case page of
        Replay id model ->
            GameReplay.dialog model
                |> Maybe.map (Dialog.map (ReplayMsg id))

        _ ->
            Nothing


shell : Page -> List (Html Msg)
shell page =
    case page of
        AppInitError error ->
            AppInitError.view error

        LoadingBackdropReview _ _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "loading backdrop review…"
                ]
            ]

        BackdropReviewLoadFailed _ error ->
            loadFailure Route.BackdropReview error

        BackdropReview model ->
            List.map (H.map BackdropReviewMsg) (BackdropReview.view model)

        LoadingMapEditor _ ->
            [ H.p
                []
                [ H.text "loading map editor…"
                ]
            ]

        MapEditorLoadFailed _ error ->
            [ H.p
                []
                [ H.text error
                ]
            , H.a
                [ A.href (Route.toString Route.MapEditor)
                ]
                [ H.text "retry"
                ]
            ]

        MapEditor model ->
            List.map (H.map MapEditorMsg) (MapEditor.view model)

        LoadingLoggedGames _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "loading logged games…"
                ]
            ]

        LoggedGamesLoadFailed _ error ->
            loadFailure Route.LoggedGames error

        LoggedGames model ->
            LoggedGames.view model

        LoadingReplay _ _ ->
            [ H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "loading replay…"
                ]
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
              ]
                |> Card.toHtml Card.simple
            ]


loadFailure : Route -> String -> List (Html msg)
loadFailure route error =
    [ Card.toHtml Card.simple
        [ H.p
            [ Aria.role Aria.Status
            ]
            [ H.text error
            ]
        , H.a
            [ A.href (Route.toString route)
            , A.css
                [ S.link
                ]
            ]
            [ H.text "retry"
            ]
        , H.a
            [ A.href (Route.toString Route.LoggedGames)
            , A.css
                [ S.link
                ]
            ]
            [ H.text "logged games"
            ]
        ]
    ]



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Page -> Sub Msg
subscriptions page =
    [ case getShared page of
        Just shared ->
            Subscriptions.common
                { operatingSystem = shared.operatingSystem
                , keyCommands = keyCommands page
                , listeners = listeners page
                , onFromJsError =
                    GotSharedMsg << Shared.gotFromJsError
                }

        Nothing ->
            Sub.none
    , pageSubscriptions page
    ]
        |> Sub.batch


pageSubscriptions : Page -> Sub Msg
pageSubscriptions page =
    case page of
        MapEditor model ->
            MapEditor.subscriptions model
                |> Sub.map MapEditorMsg

        Replay id model ->
            GameReplay.subscriptions model
                |> Sub.map (ReplayMsg id)

        _ ->
            Sub.none


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
        Replay id model ->
            GameReplay.keyCommands model
                |> KeyCmd.map (ReplayMsg id)

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
        MapEditor _ ->
            MapEditor.listeners
                |> FromJs.map MapEditorMsg

        _ ->
            FromJs.none
