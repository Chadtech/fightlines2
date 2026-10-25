module Page.GameReplay exposing
    ( Flags
    , Model
    , Msg(..)
    , dialog
    , getShared
    , init
    , keyCommands
    , load
    , setShared
    , subscriptions
    , update
    , view
    )

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)
import Api.Enum.TurnEventKind as TurnEventKind
import Api.Object
import Api.Object.GameSnapshot as SnapshotApi
import Api.Query
import ApiRequest
import Browser.Dom
import Browser.Events
import Effect as E exposing (Eff)
import Error
import Game.AnimationFrame as AnimationFrame
import Game.BackdropCalibration as BackdropCalibration
import Game.BattlefieldNavigation as BattlefieldNavigation
import Game.BattlefieldSnapshot as BattlefieldSnapshot
import Game.Camera as Camera
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.LogId as GameLogId exposing (GameLogId)
import Game.PlaybackPresentation as PlaybackPresentation
import Game.RecordedOrder as RecordedOrder exposing (RecordedOrder)
import Game.Turn as Turn
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.Battlefield as Battlefield
import Game.View.BattlefieldInspection as BattlefieldInspection
import Game.View.BattlefieldWorkspace as BattlefieldWorkspace
import Game.View.CombatTheater as CombatTheater
import Game.View.TurnControls as TurnControls
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitStatus as UnitStatus
import Graphql.Http
import Graphql.Operation exposing (RootQuery)
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Json.Decode as Decode
import KeyCmd
import Page.LoggedGames as LoggedGames
import Ports.Js.To as ToJs
import Route
import Shared
import Style as S
import Time
import Util.List as ListUtil
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Position =
    { turn : Int
    , player : PlayerNumber
    , fogOfWar : Bool
    }


type alias RecordedTurn =
    { battlefield : BattlefieldSnapshot.Snapshot
    , frames : List TurnPlayback.Frame
    , resolution : Maybe Turn.Resolution
    , orders : List RecordedOrder
    }


type alias Flags =
    { game : LoggedGames.Game
    , turn : RecordedTurn
    , backdropCalibrations : List BackdropCalibration.Entry
    }


type alias Model =
    { shared : Shared.Model
    , backdropCalibrations : List BackdropCalibration.Entry
    , id : GameLogId
    , game : LoggedGames.Game
    , battlefield : BattlefieldSnapshot.Snapshot
    , frames : List TurnPlayback.Frame
    , resolution : Maybe Turn.Resolution
    , orders : List RecordedOrder
    , showOrders : Bool
    , timeline : Timeline
    , inspection : Maybe Inspection
    , navigation : BattlefieldNavigation.Model
    , viewport : Maybe Camera.Viewport
    , frame : AnimationFrame.Frame
    , skipUnitLossDialogs : Bool
    , automaticallyCloseCombatTheater : Bool
    , position : Position
    , request : TurnRequest
    , playbackIntent : PlaybackIntent
    }


{-| Replay has no planning, submitting, or opponent-waiting state.
-}
type Timeline
    = Ready
    | Playing
        { animation : TurnPlayback.Playback
        , paused : Bool
        , camera : Maybe PlaybackPresentation.PlaybackCamera
        }


type TurnRequest
    = Idle
    | Loading Position
    | Failed Position String


type PlaybackIntent
    = SingleTurnPlayback
    | ContinuousPlayback


type Msg
    = BattlefieldMsg Battlefield.Msg
    | NavigationMsg BattlefieldNavigation.Msg
    | PlaybackMsg PlaybackPresentation.Msg
    | UnitDeathMsg UnitDeath.Msg
    | CombatTheaterMsg CombatTheater.Msg
    | BattlefieldSizeReceived (Result Browser.Dom.Error Browser.Dom.Element)
    | InspectorSizeReceived Browser.Dom.Element (Result Browser.Dom.Error Browser.Dom.Element)
    | WindowResized
    | CameraReturnFinished
    | AnimationTimerElapsed
    | CargoUnitClicked UnitId
    | EscapePressed
    | InspectorCloseClicked
    | PanLeftKeyPressed
    | PanRightKeyPressed
    | PanUpKeyPressed
    | PanDownKeyPressed
    | ZoomInKeyPressed
    | ZoomOutKeyPressed
    | PlayClicked
    | PauseClicked
    | ShowOrdersChanged Bool
    | PreviousClicked
    | NextClicked
    | TurnSelected Int
    | PlayerSelected PlayerNumber
    | FogOfWarChanged Bool
    | RetryClicked
    | TurnResponseReceived Position (ApiRequest.Response RecordedTurn)



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


load : GameLogId -> Graphql.Http.Request Flags
load id =
    SS.succeed Flags
        |> SS.with (Api.Query.loggedGame { id = GameLogId.toString id } LoggedGames.selection)
        |> SS.with (turnSelection id { turn = 0, player = PlayerNumber.Player1, fogOfWar = True })
        |> SS.with BackdropCalibration.catalogSelection
        |> ApiRequest.queryRequest


init : Shared.Model -> GameLogId -> Flags -> ( Model, Eff Msg )
init shared id flags =
    let
        ( skipLossDialogs, lossError ) =
            PlaybackPresentation.loadPreference PlaybackPresentation.SkipLossDialogs shared

        ( automaticallyClose, combatError ) =
            PlaybackPresentation.loadPreference PlaybackPresentation.AutomaticallyCloseCombat shared

        model : Model
        model =
            { shared = shared |> Shared.addError lossError |> Shared.addError combatError
            , backdropCalibrations = flags.backdropCalibrations
            , id = id
            , game = flags.game
            , battlefield = flags.turn.battlefield
            , frames = flags.turn.frames
            , resolution = flags.turn.resolution
            , orders = flags.turn.orders
            , showOrders = False
            , timeline = Ready
            , inspection = Nothing
            , navigation = BattlefieldNavigation.init
            , viewport = Nothing
            , frame = AnimationFrame.first
            , skipUnitLossDialogs = skipLossDialogs
            , automaticallyCloseCombatTheater = automaticallyClose
            , position = { turn = 0, player = PlayerNumber.Player1, fogOfWar = True }
            , request = Idle
            , playbackIntent = SingleTurnPlayback
            }
    in
    ( model, Battlefield.measure BattlefieldSizeReceived )



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


isLoading : Model -> Bool
isLoading model =
    case model.request of
        Loading _ ->
            True

        _ ->
            False


isPlaying : Model -> Bool
isPlaying model =
    playback model /= Nothing


isPaused : Model -> Bool
isPaused model =
    case model.timeline of
        Playing playing ->
            playing.paused

        Ready ->
            False


playback : Model -> Maybe TurnPlayback.Playback
playback model =
    case model.timeline of
        Playing playing ->
            Just playing.animation

        Ready ->
            Nothing


pause : Model -> Model
pause model =
    case model.timeline of
        Playing playing ->
            { model | timeline = Playing { playing | paused = True } }

        Ready ->
            model


startPlayback : Model -> ( Model, Eff Msg )
startPlayback model =
    case model.timeline of
        Playing playing ->
            { model | timeline = Playing { playing | paused = False } }
                |> updateCamera
                |> E.withOut

        Ready ->
            startTurnPlayback model


startTurnPlayback : Model -> ( Model, Eff Msg )
startTurnPlayback model =
    case ( model.frames, TurnPlayback.start model.frames ) of
        ( first :: _, Just animation ) ->
            let
                ( started, dialogEffect ) =
                    { model
                        | timeline = Playing { animation = animation, paused = False, camera = Nothing }
                        , viewport = Nothing
                    }
                        |> applyFrame first
                        |> updateLossDialog (activeDialogHtmlId model)
            in
            ( started, E.batch [ Battlefield.measure BattlefieldSizeReceived, dialogEffect ] )

        _ ->
            if isPlaying model then
                finishPlayback model

            else
                loadNextTurn model


finishPlayback : Model -> ( Model, Eff Msg )
finishPlayback model =
    let
        ( finished, nextTurnEffect ) =
            { model
                | timeline = Ready
                , navigation = BattlefieldNavigation.startReturn model.navigation
            }
                |> loadNextTurn
    in
    ( finished
    , E.batch
        [ E.after PlaybackPresentation.cameraPanDurationMs CameraReturnFinished
        , nextTurnEffect
        ]
    )


loadNextTurn : Model -> ( Model, Eff Msg )
loadNextTurn model =
    case ( model.playbackIntent, model.request ) of
        ( ContinuousPlayback, Idle ) ->
            loadTurn { turn = model.position.turn + 1, player = model.position.player, fogOfWar = model.position.fogOfWar } model

        _ ->
            model
                |> E.withOut


turnSelection : GameLogId -> Position -> SS.SelectionSet RecordedTurn RootQuery
turnSelection id position =
    Api.Query.loggedTurn
        { id = GameLogId.toString id
        , turnNumber = position.turn
        , playerNumber = position.player
        , fogOfWar = position.fogOfWar
        }
        recordedTurnSelection


recordedTurnSelection : SS.SelectionSet RecordedTurn Api.Object.GameSnapshot
recordedTurnSelection =
    SS.succeed RecordedTurn
        |> SS.with BattlefieldSnapshot.selection
        |> SS.with (TurnPlayback.selection Unit.selection Coordinate.selection)
        |> SS.with (SnapshotApi.lastResolution Turn.resolutionSelection)
        |> SS.with (SnapshotApi.replayOrders RecordedOrder.selection)


loadTurn : Position -> Model -> ( Model, Eff Msg )
loadTurn position model =
    let
        unavailable : Bool
        unavailable =
            isLoading model || (position.turn < 0) || (position.turn > model.game.turnCount)
    in
    if unavailable then
        model
            |> E.withOut

    else
        ( pause { model | request = Loading position }
        , E.request (TurnResponseReceived position) (turnSelection model.id position |> ApiRequest.queryRequest)
        )


getShared : Model -> Shared.Model
getShared model =
    model.shared


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model | shared = shared }


applyFrame : TurnPlayback.Frame -> Model -> Model
applyFrame frame model =
    let
        battlefield : BattlefieldSnapshot.Snapshot
        battlefield =
            model.battlefield
    in
    { model
        | battlefield =
            { battlefield
                | units = frame.units
                , depots = frame.depots
                , supplyCrates = frame.supplyCrates
                , visibleTiles = frame.visibleTiles
            }
    }


mapNavigation : (BattlefieldNavigation.Model -> BattlefieldNavigation.Model) -> Model -> Model
mapNavigation change model =
    case model.timeline of
        Playing playing ->
            if playing.paused then
                let
                    navigation : BattlefieldNavigation.Model
                    navigation =
                        model.navigation

                    camera : Camera.Camera
                    camera =
                        playing.camera
                            |> Maybe.map .camera
                            |> Maybe.withDefault (BattlefieldNavigation.camera navigation)

                    inspecting : BattlefieldNavigation.Model
                    inspecting =
                        { navigation | offset = camera.offset, zoom = camera.zoom }
                in
                { model
                    | navigation = change inspecting |> BattlefieldNavigation.finishReturn
                    , timeline = Playing { playing | camera = Nothing }
                }

            else
                { model | navigation = change model.navigation |> BattlefieldNavigation.finishReturn }
                    |> updateCamera

        Ready ->
            { model | navigation = change model.navigation |> BattlefieldNavigation.finishReturn }


selectUnit : UnitId -> Model -> Model
selectUnit id model =
    case ListUtil.find (\unit -> unit.id == id) model.battlefield.units of
        Just _ ->
            if model.inspection == Just (UnitInspection id) then
                { model | inspection = Nothing }

            else
                { model | inspection = Just (UnitInspection id) }

        Nothing ->
            model


inspectTile : Coordinate -> Model -> Model
inspectTile position model =
    { model | inspection = Just (TileInspection position) }


withInspectionMeasurement : Model -> Model -> ( Model, Eff Msg )
withInspectionMeasurement previous next =
    if (previous.inspection == Nothing) /= (next.inspection == Nothing) then
        ( { next
            | viewport = Nothing
          }
        , Battlefield.measure BattlefieldSizeReceived
        )

    else
        E.withOut next


inspectClick : { detail : Int } -> (Model -> Model) -> Model -> Model
inspectClick click select model =
    if (click.detail /= 0) && BattlefieldNavigation.suppressesClick model.navigation then
        model

    else
        select model


handleBattlefieldMsg : Battlefield.Msg -> Model -> Model
handleBattlefieldMsg msg model =
    case msg of
        Battlefield.PanLeftClicked ->
            mapNavigation BattlefieldNavigation.panLeft model

        Battlefield.PanRightClicked ->
            mapNavigation BattlefieldNavigation.panRight model

        Battlefield.PanUpClicked ->
            mapNavigation BattlefieldNavigation.panUp model

        Battlefield.PanDownClicked ->
            mapNavigation BattlefieldNavigation.panDown model

        Battlefield.ZoomInClicked ->
            mapNavigation BattlefieldNavigation.zoomIn model

        Battlefield.ZoomOutClicked ->
            mapNavigation BattlefieldNavigation.zoomOut model

        Battlefield.ResetViewClicked ->
            mapNavigation BattlefieldNavigation.resetViewport model

        Battlefield.HomePressed ->
            mapNavigation BattlefieldNavigation.resetViewport model

        Battlefield.MousePressed point ->
            mapNavigation (BattlefieldNavigation.press point) model

        Battlefield.WheelScrolled anchor delta ->
            mapNavigation (BattlefieldNavigation.scroll anchor delta) model

        Battlefield.ClickedUnit id click ->
            inspectClick click (selectUnit id) model

        Battlefield.PressedEnterOnUnit id ->
            selectUnit id model

        Battlefield.PressedSpaceOnUnit id ->
            selectUnit id model

        Battlefield.ClickedDepot position click ->
            inspectClick click (inspectTile position) model

        Battlefield.ClickedDepotStock position click ->
            inspectClick click (inspectTile position) model

        Battlefield.ClickedTile position click ->
            inspectClick click (inspectTile position) model

        Battlefield.PressedEnterOnDepot position ->
            inspectTile position model

        Battlefield.PressedSpaceOnDepot position ->
            inspectTile position model

        Battlefield.PressedEnterOnDepotStock position ->
            inspectTile position model

        Battlefield.PressedSpaceOnDepotStock position ->
            inspectTile position model

        Battlefield.PressedEnterOnTile position ->
            inspectTile position model

        Battlefield.PressedSpaceOnTile position ->
            inspectTile position model

        Battlefield.MouseOverUnit _ ->
            model

        Battlefield.MouseOverDepot _ ->
            model

        Battlefield.MouseOverTile _ ->
            model

        Battlefield.FocusedBoardUnit _ ->
            model

        Battlefield.FocusedBoardTile _ ->
            model

        Battlefield.TargetPreviewLeft ->
            model

        Battlefield.RotationChoicesMsg _ ->
            model


continueCombat : Model -> ( Model, Eff Msg )
continueCombat model =
    case model.timeline of
        Playing playing ->
            case TurnPlayback.continueCombat playing.animation of
                Just next ->
                    { model | timeline = Playing { playing | animation = next.animation } }
                        |> applyFrame next.frame
                        |> updateCamera
                        |> updateLossDialog (activeDialogHtmlId model)

                Nothing ->
                    model
                        |> E.withOut

        Ready ->
            model
                |> E.withOut


setCombatMapView : TurnPlayback.MapView -> Model -> Model
setCombatMapView mapView model =
    case model.timeline of
        Playing playing ->
            { model | timeline = Playing { playing | animation = TurnPlayback.setMapView mapView playing.animation } }

        Ready ->
            model


cameraSettling : Maybe PlaybackPresentation.PlaybackCamera -> Bool
cameraSettling camera =
    (camera |> Maybe.map .remainingPanMs |> Maybe.withDefault 0) > 0


advancePlayback : Float -> Model -> ( Model, Eff Msg )
advancePlayback delta model =
    case model.timeline of
        Playing playing ->
            if playing.paused then
                model
                    |> E.withOut

            else if cameraSettling playing.camera then
                { model
                    | timeline =
                        Playing
                            { playing
                                | camera =
                                    Maybe.map
                                        (\held -> { held | remainingPanMs = max 0 (held.remainingPanMs - delta) })
                                        playing.camera
                            }
                }
                    |> E.withOut

            else
                let
                    advance : Float -> TurnPlayback.Playback -> ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )
                    advance =
                        if model.skipUnitLossDialogs then
                            TurnPlayback.tick

                        else
                            TurnPlayback.tickUntilLoss

                    ( remaining, frame ) =
                        advance delta playing.animation
                in
                case remaining of
                    Nothing ->
                        model
                            |> applyFrame frame
                            |> finishPlayback

                    Just animation ->
                        let
                            updated : Model
                            updated =
                                { model | timeline = Playing { playing | animation = animation } }
                                    |> applyFrame frame
                        in
                        if PlaybackPresentation.readyToAutomaticallyClose model.automaticallyCloseCombatTheater animation then
                            continueCombat updated

                        else
                            updated
                                |> updateCamera
                                |> updateLossDialog (activeDialogHtmlId model)

        Ready ->
            model
                |> E.withOut


updateCamera : Model -> Model
updateCamera model =
    case ( model.timeline, model.viewport ) of
        ( Playing playing, Just viewport ) ->
            if playing.paused then
                model

            else
                { model
                    | timeline =
                        Playing
                            { playing
                                | camera =
                                    Just
                                        (PlaybackPresentation.frameCamera
                                            viewport
                                            model.battlefield.map
                                            (BattlefieldNavigation.camera model.navigation)
                                            playing.animation
                                            playing.camera
                                        )
                            }
                }

        _ ->
            model


unitLoss : Model -> Maybe TurnPlayback.Loss
unitLoss model =
    PlaybackPresentation.loss model.skipUnitLossDialogs (playback model)


activeDialogHtmlId : Model -> Maybe String
activeDialogHtmlId model =
    unitLoss model |> Maybe.map UnitDeath.dialogHtmlId


updateLossDialog : Maybe String -> Model -> ( Model, Eff Msg )
updateLossDialog previousHtmlId model =
    case unitLoss model of
        Just loss ->
            let
                htmlId : String
                htmlId =
                    UnitDeath.dialogHtmlId loss
            in
            if previousHtmlId == Just htmlId then
                model
                    |> E.withOut

            else
                ( { model
                    | shared =
                        Shared.addError (PlaybackPresentation.lossError model.battlefield.players (Just loss)) model.shared
                  }
                , E.toJs (ToJs.OpenDialog { htmlId = htmlId })
                )

        Nothing ->
            model
                |> E.withOut



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    case msg of
        BattlefieldMsg battlefieldMsg ->
            model
                |> handleBattlefieldMsg battlefieldMsg
                |> withInspectionMeasurement model

        NavigationMsg navigationMsg ->
            model
                |> mapNavigation (BattlefieldNavigation.update BattlefieldNavigation.PanCamera navigationMsg)
                |> E.withOut

        CargoUnitClicked id ->
            { model | inspection = Nothing }
                |> selectUnit id
                |> withInspectionMeasurement model

        EscapePressed ->
            { model | inspection = Nothing }
                |> withInspectionMeasurement model

        InspectorCloseClicked ->
            { model
                | inspection = Nothing
            }
                |> withInspectionMeasurement model

        PanLeftKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panLeft
                |> E.withOut

        PanRightKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panRight
                |> E.withOut

        PanUpKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panUp
                |> E.withOut

        PanDownKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.panDown
                |> E.withOut

        ZoomInKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomIn
                |> E.withOut

        ZoomOutKeyPressed ->
            model
                |> mapNavigation BattlefieldNavigation.zoomOut
                |> E.withOut

        CameraReturnFinished ->
            { model | navigation = BattlefieldNavigation.finishReturn model.navigation }
                |> E.withOut

        WindowResized ->
            ( model, Battlefield.measure BattlefieldSizeReceived )

        BattlefieldSizeReceived result ->
            case result of
                Ok battlefield ->
                    ( model, E.measure BattlefieldWorkspace.inspectorHtmlId (InspectorSizeReceived battlefield) )

                Err error ->
                    { model | shared = Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared }
                        |> E.withOut

        InspectorSizeReceived battlefield result ->
            case result of
                Ok inspector ->
                    { model
                        | viewport =
                            Just
                                (BattlefieldWorkspace.viewport
                                    { battlefield = battlefield
                                    , inspector = inspector
                                    }
                                )
                    }
                        |> updateCamera
                        |> E.withOut

                Err error ->
                    { model | shared = Shared.addError (Just (Error.BattlefieldMeasurementFailed error)) model.shared }
                        |> E.withOut

        AnimationTimerElapsed ->
            if
                List.any
                    (\unit -> Unit.onMap unit && Unit.isDying unit)
                    model.battlefield.units
                    || ((playback model |> Maybe.andThen TurnPlayback.activeEncounter) /= Nothing)
            then
                model
                    |> E.withOut

            else
                { model | frame = AnimationFrame.next model.frame }
                    |> E.withOut

        PlaybackMsg playbackMsg ->
            case playbackMsg of
                PlaybackPresentation.FrameElapsed delta ->
                    model
                        |> advancePlayback delta

                PlaybackPresentation.CombatEnterReleased ->
                    model
                        |> continueCombat

                PlaybackPresentation.CombatSeeMapReleased ->
                    model
                        |> setCombatMapView TurnPlayback.CardVisible
                        |> E.withOut

        UnitDeathMsg lossMsg ->
            case lossMsg of
                UnitDeath.ContinueClicked id ->
                    case model.timeline of
                        Playing playing ->
                            { model | timeline = Playing { playing | animation = TurnPlayback.acknowledgeLoss id playing.animation } }
                                |> updateCamera
                                |> updateLossDialog (activeDialogHtmlId model)

                        Ready ->
                            model
                                |> E.withOut

                UnitDeath.SkipDialogsChanged skip ->
                    { model | skipUnitLossDialogs = skip }
                        |> updateLossDialog (activeDialogHtmlId model)
                        |> E.and
                            (PlaybackPresentation.rememberPreference PlaybackPresentation.SkipLossDialogs skip)

        CombatTheaterMsg theaterMsg ->
            case theaterMsg of
                CombatTheater.AutomaticallyCloseChanged enabled ->
                    ( { model | automaticallyCloseCombatTheater = enabled }
                    , PlaybackPresentation.rememberPreference PlaybackPresentation.AutomaticallyCloseCombat enabled
                    )

                CombatTheater.ContinueClicked ->
                    model
                        |> continueCombat

                CombatTheater.SeeMapPressed ->
                    model
                        |> setCombatMapView TurnPlayback.SeeingMap
                        |> E.withOut

                CombatTheater.SeeMapReleased ->
                    model
                        |> setCombatMapView TurnPlayback.CardVisible
                        |> E.withOut

        PlayClicked ->
            if isLoading model then
                model
                    |> E.withOut

            else if model.position.turn == 0 then
                loadTurn
                    { turn = 1
                    , player = model.position.player
                    , fogOfWar = model.position.fogOfWar
                    }
                    { model | playbackIntent = ContinuousPlayback }

            else
                startPlayback { model | playbackIntent = ContinuousPlayback }

        PauseClicked ->
            model
                |> pause
                |> E.withOut

        ShowOrdersChanged enabled ->
            { model | showOrders = enabled }
                |> E.withOut

        PreviousClicked ->
            loadTurn
                { turn = model.position.turn - 1
                , player = model.position.player
                , fogOfWar = model.position.fogOfWar
                }
                { model | playbackIntent = SingleTurnPlayback }

        NextClicked ->
            loadTurn
                { turn = model.position.turn + 1
                , player = model.position.player
                , fogOfWar = model.position.fogOfWar
                }
                { model | playbackIntent = SingleTurnPlayback }

        TurnSelected turn ->
            loadTurn
                { turn = turn
                , player = model.position.player
                , fogOfWar = model.position.fogOfWar
                }
                { model | playbackIntent = SingleTurnPlayback }

        PlayerSelected player ->
            loadTurn
                { turn = model.position.turn
                , player = player
                , fogOfWar = model.position.fogOfWar
                }
                model

        FogOfWarChanged enabled ->
            loadTurn
                { turn = model.position.turn
                , player = model.position.player
                , fogOfWar = enabled
                }
                model

        RetryClicked ->
            case model.request of
                Failed position _ ->
                    loadTurn position model

                _ ->
                    model
                        |> E.withOut

        TurnResponseReceived position result ->
            if model.request /= Loading position then
                model
                    |> E.withOut

            else
                case result of
                    Err error ->
                        { model | request = Failed position (ApiRequest.errorMessage error) }
                            |> E.withOut

                    Ok recorded ->
                        { model
                            | battlefield = recorded.battlefield
                            , frames = recorded.frames
                            , resolution = recorded.resolution
                            , orders = recorded.orders
                            , navigation = BattlefieldNavigation.finishReturn model.navigation
                            , position = position
                            , request = Idle
                        }
                            |> startTurnPlayback



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


selectedUnit : Model -> Maybe Unit
selectedUnit model =
    case model.inspection of
        Just (UnitInspection id) ->
            ListUtil.find (\unit -> unit.id == id) model.battlefield.units

        _ ->
            Nothing


inspectionPosition : Model -> Maybe Coordinate
inspectionPosition model =
    case model.inspection of
        Just (TileInspection position) ->
            Just position

        _ ->
            selectedUnit model |> Maybe.andThen (Unit.physicalPosition model.battlefield.units)


facingUnits : Model -> List UnitId
facingUnits model =
    if isPlaying model then
        model.resolution
            |> Maybe.map (.events >> List.filter (\event -> List.member event.kind [ TurnEventKind.Ambush, TurnEventKind.StandGround ]) >> List.map .unitId)
            |> Maybe.withDefault []

    else
        []


battlefieldPresentation : Model -> Battlefield.Presentation
battlefieldPresentation model =
    let
        visibleOrders : List RecordedOrder
        visibleOrders =
            if model.showOrders then
                model.orders

            else
                []

        playing : Maybe Battlefield.PlaybackView
        playing =
            playback model |> Maybe.map playbackView

        playbackView : TurnPlayback.Playback -> Battlefield.PlaybackView
        playbackView animation =
            { animation = animation
            , loss = unitLoss model
            }
    in
    Battlefield.Reviewing { playback = playing, orders = visibleOrders }


battlefieldView : Model -> Html Msg
battlefieldView model =
    let
        heldCamera : Maybe Camera.Camera
        heldCamera =
            case model.timeline of
                Playing playing ->
                    playing.camera |> Maybe.map .camera

                Ready ->
                    Nothing

        presentation : Battlefield.Presentation
        presentation =
            battlefieldPresentation model

        args : Battlefield.Args
        args =
            { map = model.battlefield.map
            , units = model.battlefield.units
            , depots = model.battlefield.depots
            , supplyCrates = model.battlefield.supplyCrates
            , visibleTiles = model.battlefield.visibleTiles
            , frame = model.frame
            , selected = inspectionPosition model
            , selectedUnitId = selectedUnit model |> Maybe.map .id
            , facingUnits = facingUnits model
            , presentation = presentation
            }

        viewportAttributes : List (H.Attribute Msg)
        viewportAttributes =
            Battlefield.viewportAttributes
                { dragging = BattlefieldNavigation.active model.navigation
                , interaction = Battlefield.interaction presentation
                }
                |> List.map (A.map BattlefieldMsg)
    in
    H.div
        viewportAttributes
        [ Battlefield.camera
            { camera =
                Maybe.withDefault
                    (BattlefieldNavigation.camera model.navigation)
                    heldCamera
            , transitioning =
                (heldCamera /= Nothing) || BattlefieldNavigation.returning model.navigation
            }
            [ Battlefield.toSvg args
                |> H.fromUnstyled
            ]
            |> H.map BattlefieldMsg
        ]


view : Model -> List (Html Msg)
view model =
    BattlefieldWorkspace.toHtml
        { loss = unitLoss model /= Nothing
        , combat = (playback model |> Maybe.andThen TurnPlayback.activeEncounter) /= Nothing
        , dying = List.any (\unit -> Unit.onMap unit && Unit.isDying unit) model.battlefield.units
        , battlefield = battlefieldView model
        , header = Nothing
        , controls = controls model
        , inspection = selectionView model
        , hasSelection = model.inspection /= Nothing
        , onCloseInspection = InspectorCloseClicked
        , combatOverlay =
            PlaybackPresentation.combatOverlay
                model.backdropCalibrations
                model.automaticallyCloseCombatTheater
                model.battlefield.map
                (playback model)
                |> H.map CombatTheaterMsg
        }


selectionView : Model -> Html Msg
selectionView model =
    let
        inspectedUnit : Maybe Unit
        inspectedUnit =
            case selectedUnit model of
                Just unit ->
                    Just unit

                Nothing ->
                    inspectionPosition model
                        |> Maybe.andThen (\position -> ListUtil.find (\unit -> Unit.mapPosition unit == Just position) model.battlefield.units)

        unitContent : Unit -> { unit : Unit, content : List (Html Msg) }
        unitContent unit =
            { unit = unit
            , content =
                [ UnitStatus.toHtml (PlaybackPresentation.ownerName model.battlefield.players unit |> Maybe.withDefault "") unit Nothing
                , BattlefieldInspection.cargo
                    { units = model.battlefield.units
                    , ownPlayers = [ model.position.player ]
                    , orders = []
                    , onSelectPassenger = CargoUnitClicked
                    }
                    unit
                ]
            }
    in
    BattlefieldInspection.toHtml
        { map = model.battlefield.map
        , depots = model.battlefield.depots
        , supplyCrates = model.battlefield.supplyCrates
        , visibleTiles = model.battlefield.visibleTiles
        , position = inspectionPosition model
        , unit = Maybe.map unitContent inspectedUnit
        }


controls : Model -> Html Msg
controls model =
    let
        busy : Bool
        busy =
            isLoading model

        fogOfWar : Bool
        fogOfWar =
            case model.request of
                Loading position ->
                    position.fogOfWar

                _ ->
                    model.position.fogOfWar

        playing : Bool
        playing =
            isPlaying model && not (isPaused model)

        playButton : Button.Button Msg
        playButton =
            if busy || (model.game.turnCount == 0) then
                Button.disabled "play"

            else if playing then
                Button.primary "pause" PauseClicked

            else
                Button.primary "play" PlayClicked

        previous : Button.Button Msg
        previous =
            if busy || (model.position.turn == 0) then
                Button.disabled "previous"

            else
                Button.secondary "previous" PreviousClicked

        next : Button.Button Msg
        next =
            if busy || (model.position.turn >= model.game.turnCount) then
                Button.disabled "next"

            else
                Button.secondary "next" NextClicked

        turnOption : Int -> { value : Int, label : String }
        turnOption turn =
            { value = turn
            , label =
                if turn == 0 then
                    "starting board"

                else
                    "turn " ++ String.fromInt turn
            }

        playerDecoder : Decode.Decoder PlayerNumber
        playerDecoder =
            Decode.string |> Decode.andThen decodePlayer

        decodePlayer : String -> Decode.Decoder PlayerNumber
        decodePlayer value =
            case value of
                "1" ->
                    Decode.succeed PlayerNumber.Player1

                "2" ->
                    Decode.succeed PlayerNumber.Player2

                _ ->
                    Decode.fail "invalid replay player"

        playerValue : PlayerNumber -> String
        playerValue player =
            case player of
                PlayerNumber.Player1 ->
                    "1"

                PlayerNumber.Player2 ->
                    "2"

        turnDecoder : Decode.Decoder Int
        turnDecoder =
            Decode.string |> Decode.andThen decodeTurn

        decodeTurn : String -> Decode.Decoder Int
        decodeTurn value =
            case String.toInt value of
                Just turn ->
                    Decode.succeed turn

                Nothing ->
                    Decode.fail "invalid replay turn"

        loadingStatus : String
        loadingStatus =
            if busy then
                "loading turn…"

            else
                ""

        feedback : Html Msg
        feedback =
            case model.request of
                Failed _ message ->
                    H.div
                        []
                        [ H.p
                            [ Aria.role Aria.Status ]
                            [ H.text message ]
                        , Button.secondary "retry" RetryClicked
                            |> Button.toHtml
                        ]

                _ ->
                    H.p
                        [ Aria.role Aria.Status
                        , A.css [ S.h6 ]
                        ]
                        [ H.text loadingStatus ]

        turnSelector : Html Msg
        turnSelector =
            H.label
                [ A.css
                    [ S.col
                    , S.g1
                    , S.flex1
                    , S.minW0
                    ]
                ]
                [ H.text "turn"
                , Select.toHtml
                    { htmlId = "replay-turn"
                    , disabled = busy
                    , selected = model.position.turn
                    , options = List.map turnOption (List.range 0 model.game.turnCount)
                    , toValue = String.fromInt
                    , decoder = turnDecoder
                    , onChange = TurnSelected
                    }
                ]

        playerSelector : Html Msg
        playerSelector =
            H.label
                [ A.css
                    [ S.col
                    , S.g1
                    , S.flex1
                    , S.minW0
                    ]
                ]
                [ H.text "view"
                , Select.toHtml
                    { htmlId = "replay-player"
                    , disabled = busy
                    , selected = model.position.player
                    , options =
                        [ { value = PlayerNumber.Player1
                          , label = "player 1 (red)"
                          }
                        , { value = PlayerNumber.Player2
                          , label = "player 2 (blue)"
                          }
                        ]
                    , toValue = playerValue
                    , decoder = playerDecoder
                    , onChange = PlayerSelected
                    }
                ]
    in
    TurnControls.replayPanel
        [ H.div
            [ A.css
                [ S.col
                , S.g2
                , S.minW0
                , S.flex1
                ]
            ]
            [ H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.justifySpaceBetween
                    , S.g2
                    ]
                ]
                [ H.p
                    []
                    [ H.text model.game.name ]
                , H.a
                    [ A.href (Route.toString Route.LoggedGames)
                    , A.css [ S.link ]
                    ]
                    [ H.text "logged games" ]
                ]
            , H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.g2
                    ]
                ]
                [ Button.toHtml previous
                , Button.toHtml playButton
                , Button.toHtml next
                ]
            , H.div
                [ A.css
                    [ S.row
                    , S.g2
                    ]
                ]
                [ turnSelector
                , playerSelector
                ]
            , Checkbox.new
                { label = "fog of war"
                , checked = fogOfWar
                , onCheck = FogOfWarChanged
                }
                |> Checkbox.disabled busy
                |> Checkbox.toHtml [ H.text "fog of war" ]
            , Checkbox.new
                { label = "show orders"
                , checked = model.showOrders
                , onCheck = ShowOrdersChanged
                }
                |> Checkbox.toHtml [ H.text "show orders" ]
            , feedback
            ]
        , Battlefield.navigationControls (round (model.navigation.zoom * 100))
            |> H.map BattlefieldMsg
        ]


dialog : Model -> Maybe (Dialog Msg)
dialog model =
    PlaybackPresentation.lossDialog
        { skipDialogs = model.skipUnitLossDialogs
        , players = model.battlefield.players
        , ownPlayers = [ model.position.player ]
        }
        (playback model)
        |> Maybe.map (Dialog.map UnitDeathMsg)



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\_ _ -> WindowResized)
        , Time.every 400 (\_ -> AnimationTimerElapsed)
        , PlaybackPresentation.subscriptions (playback model) |> Sub.map PlaybackMsg
        , BattlefieldNavigation.subscriptions model.navigation |> Sub.map NavigationMsg
        ]


keyCommands : Model -> KeyCmd.KeyCmd Msg
keyCommands model =
    let
        blocked : Bool
        blocked =
            (dialog model /= Nothing) || ((playback model |> Maybe.andThen TurnPlayback.activeEncounter) /= Nothing)
    in
    if blocked then
        KeyCmd.none

    else
        KeyCmd.batch
            [ KeyCmd.escape EscapePressed
            , KeyCmd.plus ZoomInKeyPressed
            , KeyCmd.minus ZoomOutKeyPressed
            , KeyCmd.batch [ KeyCmd.leftArrow PanLeftKeyPressed, KeyCmd.a PanLeftKeyPressed ]
            , KeyCmd.batch [ KeyCmd.rightArrow PanRightKeyPressed, KeyCmd.d PanRightKeyPressed ]
            , KeyCmd.batch [ KeyCmd.upArrow PanUpKeyPressed, KeyCmd.w PanUpKeyPressed ]
            , KeyCmd.batch [ KeyCmd.downArrow PanDownKeyPressed, KeyCmd.s PanDownKeyPressed ]
            ]
