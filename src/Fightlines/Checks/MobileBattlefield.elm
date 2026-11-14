port module Fightlines.Checks.MobileBattlefield exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.Direction as Direction
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind
import Api.Scalar exposing (MapId(..))
import Browser
import Browser.Dom
import Error
import Fightlines.Page.GamePage as GamePage
import Fightlines.View.MobileBattlefield as MobileBattlefield
import Fightlines.View.OrderMenu as OrderMenu
import Game.CurrentTurn as CurrentTurn
import Game.Inactivity as Inactivity
import Game.Map as Map
import Game.Movement as Movement
import Game.OrderPlanning as OrderPlanning
import Game.Outcome as GameOutcome
import Game.Selection exposing (Selection(..), UnitInteraction(..))
import Game.Terrain as Terrain
import Game.Turn as Turn
import Game.TurnLifecycle as TurnLifecycle
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitOrder as UnitOrder
import Game.View.Battlefield as Battlefield
import Game.View.Chat as ChatView
import Game.View.TurnControls as TurnControls
import LobbyId exposing (LobbyId)
import LocalStorage
import OperatingSystem
import Random
import Shared
import Time
import View.Dialog as Dialog


port results : List String -> Cmd msg


main : Program () () ()
main =
    Browser.application
        { init =
            \_ url key ->
                let
                    shared : Shared.Model
                    shared =
                        Shared.init
                            (Time.millisToPosix 1700000000000)
                            (Random.initialSeed 42)
                            OperatingSystem.Unknown
                            { width = 852
                            , height = 393
                            }
                            LocalStorage.test
                            url
                            key

                    failures : List String
                    failures =
                        case
                            ( LobbyId.fromString "00000000000000000000000000000001"
                            , UnitId.parse "friendly"
                            , UnitId.parse "enemy"
                            )
                        of
                            ( Ok lobbyId, Ok friendlyId, Ok enemyId ) ->
                                checks lobbyId
                                    friendlyId
                                    enemyId
                                    shared

                            _ ->
                                [ "invalid mobile battlefield fixture identifiers" ]
                in
                ( ()
                , results failures
                )
        , update =
            \_ model ->
                ( model
                , Cmd.none
                )
        , subscriptions = \_ -> Sub.none
        , view =
            \_ ->
                { title = "mobile battlefield checks"
                , body = []
                }
        , onUrlChange = \_ -> ()
        , onUrlRequest = \_ -> ()
        }


checks : LobbyId -> UnitId -> UnitId -> Shared.Model -> List String
checks lobbyId friendlyId enemyId shared =
    let
        flags : GamePage.Flags
        flags =
            { messages = []
            , snapshot =
                { inactivity = Inactivity.Disabled
                , battlefield =
                    { name = "mobile fixture"
                    , mapType = MapId "fixture"
                    , unitStats = []
                    , players =
                        [ { name = "commander"
                          , playerNumber = PlayerNumber.Player1
                          , isYou = True
                          }
                        ]
                    , map =
                        Map.fromFeatures
                            { width = 4
                            , height = 4
                            , baseTile = Terrain.Plain
                            , theme = MapTheme.GreenForest
                            , features = []
                            }
                    , units =
                        [ unit friendlyId PlayerNumber.Player1 0
                        , unit enemyId PlayerNumber.Player2 3
                        ]
                    , depots = []
                    , supplyCrates = []
                    , visibleTiles = []
                    }
                , supplyRules =
                    { depotCapacity = 100
                    , crateCapacity = 10
                    , fuelDepotCapacity = 100
                    , fuelDrumCapacity = 10
                    }
                , movementRules =
                    [ { kind = Kind.Infantry
                      , budget = 8
                      , terrainCosts =
                            [ { terrain = Terrain.Plain
                              , cost = 2
                              }
                            ]
                      , roadFuelPerTile = 0
                      , roadFuelPerCargoSlot = 0
                      }
                    ]
                , turn =
                    { number = 1
                    , outcome = Nothing
                    , submitted = False
                    , opponentSubmitted = False
                    , resolution = Nothing
                    }
                , playbackFrames = []
                }
            }

        initial : GamePage.Model
        initial =
            GamePage.init shared flags
                |> Tuple.first
                |> step GamePage.WelcomeBriefingDismissed

        step : GamePage.Msg -> GamePage.Model -> GamePage.Model
        step msg model =
            GamePage.superUpdate lobbyId msg model |> Tuple.first

        portrait : GamePage.Model
        portrait =
            GamePage.setShared
                { shared | screenSize = { width = 393, height = 852 } }
                initial

        landscapeAgain : GamePage.Model
        landscapeAgain =
            portrait
                |> step GamePage.RotationNoticeCanceled
                |> GamePage.setShared shared

        ready : GamePage.Model
        ready =
            { initial | currentTurn = CurrentTurn.acknowledgeIntroduction initial.currentTurn }

        awaitingActivity : GamePage.Model
        awaitingActivity =
            { ready | inactivity = Inactivity.init shared.now (Inactivity.Enabled (Just 30)) }

        leavesInactivityAlone : GamePage.Msg -> Bool
        leavesInactivityAlone msg =
            (step msg awaitingActivity).inactivity == awaitingActivity.inactivity

        afterWarningAcknowledgment : GamePage.Model
        afterWarningAcknowledgment =
            step GamePage.StillHereClicked awaitingActivity

        select : UnitId -> GamePage.Model -> GamePage.Model
        select id =
            step (GamePage.BattlefieldMsg (Battlefield.ClickedUnit id { detail = 1 }))

        selected : GamePage.Model
        selected =
            select friendlyId ready

        moving : GamePage.Model
        moving =
            step (GamePage.OrderMenuMsg (OrderMenu.OrderPicked UnitOrder.Move)) selected

        details : GamePage.Model
        details =
            step (GamePage.MobileTabClicked MobileBattlefield.Details) moving

        orders : GamePage.Model
        orders =
            step (GamePage.MobileTabNavigationPressed MobileBattlefield.Orders) details

        desktopShared : Shared.Model
        desktopShared =
            { shared | screenSize = { width = 1440, height = 900 } }

        desktop : GamePage.Model
        desktop =
            moving
                |> GamePage.setShared desktopShared
                |> GamePage.resize { layoutChanged = True }
                |> Tuple.first

        mobileAgain : GamePage.Model
        mobileAgain =
            desktop
                |> GamePage.setShared shared
                |> GamePage.resize { layoutChanged = True }
                |> Tuple.first

        playbackFrame : TurnPlayback.Frame
        playbackFrame =
            { units = ready.units
            , visibleTiles = ready.visibleTiles
            , depots = []
            , supplyCrates = []
            , departures = []
            , losses = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            }

        mobileCamera : TurnLifecycle.PlaybackCamera
        mobileCamera =
            { camera =
                { zoom = 1.25
                , offset = { x = 50, y = -25 }
                }
            , remainingPanMs = 100
            }

        playbackResized : Bool
        playbackResized =
            case TurnLifecycle.startTurn False [ playbackFrame, playbackFrame ] of
                TurnLifecycle.Playing playing ->
                    let
                        currentTurn : CurrentTurn.Model
                        currentTurn =
                            ready.currentTurn
                                |> CurrentTurn.setPhase
                                    (TurnLifecycle.Playing
                                        (TurnLifecycle.setPlaybackCamera
                                            (Just mobileCamera)
                                            playing
                                        )
                                    )

                        resized : GamePage.Model
                        resized =
                            { ready | currentTurn = currentTurn }
                                |> GamePage.setShared desktopShared
                                |> GamePage.resize { layoutChanged = True }
                                |> Tuple.first

                        desktopCamera : TurnLifecycle.PlaybackCamera
                        desktopCamera =
                            { camera =
                                { zoom = 1
                                , offset = { x = 40, y = -20 }
                                }
                            , remainingPanMs = mobileCamera.remainingPanMs
                            }
                    in
                    case resized.currentTurn.phase of
                        TurnLifecycle.Playing next ->
                            (next.camera == Just desktopCamera)
                                && (next.animation == playing.animation)

                        _ ->
                            False

                _ ->
                    False

        desktopPlanning : GamePage.Model
        desktopPlanning =
            select friendlyId
                (GamePage.setShared desktopShared ready)
                |> step (GamePage.OrderMenuMsg (OrderMenu.OrderPicked UnitOrder.Move))

        desktopHelp : GamePage.Model
        desktopHelp =
            step (GamePage.OrderMenuMsg OrderMenu.InfoClicked)
                (select friendlyId (GamePage.setShared desktopShared ready))

        helped : GamePage.Model
        helped =
            step (GamePage.OrderMenuMsg OrderMenu.InfoClicked) moving

        closed : GamePage.Model
        closed =
            step GamePage.InspectorCloseClicked orders

        enemy : GamePage.Model
        enemy =
            select enemyId (step GamePage.InspectorCloseClicked details)

        nextFriendly : GamePage.Model
        nextFriendly =
            select friendlyId enemy

        submissionRequested : GamePage.Model
        submissionRequested =
            step (GamePage.TurnControlsMsg TurnControls.SubmitClicked) ready

        warnedBeforeSubmission : Bool
        warnedBeforeSubmission =
            case submissionRequested.currentTurn.phase of
                TurnLifecycle.Planning (OrderPlanning.ConfirmingSubmission _) ->
                    True

                _ ->
                    False

        surrenderRequested : GamePage.Model
        surrenderRequested =
            step (GamePage.TurnControlsMsg TurnControls.SurrenderClicked) ready

        saved : GamePage.Model
        saved =
            step
                (GamePage.OrderMenuMsg
                    (OrderMenu.OrderPicked UnitOrder.HoldPosition)
                )
                selected

        savedThenClosed : GamePage.Model
        savedThenClosed =
            step GamePage.InspectorCloseClicked saved

        unloadWithMissingRule : GamePage.Model
        unloadWithMissingRule =
            let
                truck : Unit
                truck =
                    unit friendlyId PlayerNumber.Player1 0
                        |> Unit.setKind Kind.Truck

                passenger : Unit
                passenger =
                    unit enemyId PlayerNumber.Player1 1
                        |> Unit.setLocation (Location.Aboard friendlyId)

                missingRule : GamePage.Model
                missingRule =
                    { ready | movementRules = [] }
            in
            missingRule
                |> GamePage.setUnits [ truck, passenger ]
                |> select friendlyId
                |> step (GamePage.OrderMenuMsg (OrderMenu.OrderPicked UnitOrder.HoldPosition))

        unloadViolation : OrderPlanning.InvariantViolation
        unloadViolation =
            OrderPlanning.MovementInvariantViolated
                (Movement.RuleNotFound { unitId = enemyId, kind = Kind.Infantry })

        orphanedPassenger : Unit
        orphanedPassenger =
            unit enemyId PlayerNumber.Player1 3
                |> Unit.setLocation (Location.Aboard enemyId)

        failedPreparation : GamePage.Model
        failedPreparation =
            savedThenClosed
                |> GamePage.setUnits
                    [ unit friendlyId PlayerNumber.Player1 0
                    , orphanedPassenger
                    ]
                |> step (GamePage.TurnControlsMsg TurnControls.SubmitClicked)

        reportTime : Int
        reportTime =
            Time.posixToMillis shared.now + 1000

        reportTick : Int -> GamePage.Model -> GamePage.Model
        reportTick millis =
            step (GamePage.PlanningErrorReportTick (Time.millisToPosix millis))

        reported : GamePage.Model
        reported =
            reportTick reportTime failedPreparation

        repeatedFailure : GamePage.Model
        repeatedFailure =
            reported
                |> step (GamePage.TurnControlsMsg TurnControls.SubmitClicked)

        distinctFailure : GamePage.Model
        distinctFailure =
            let
                fresh : GamePage.Model
                fresh =
                    { ready | movementRules = [], planningReports = repeatedFailure.planningReports }
            in
            fresh
                |> select friendlyId
                |> step (GamePage.OrderMenuMsg (OrderMenu.OrderPicked UnitOrder.Move))

        resolvedFlags : GamePage.Flags
        resolvedFlags =
            let
                { snapshot } =
                    flags

                turn : Turn.Snapshot
                turn =
                    snapshot.turn
            in
            { flags
                | snapshot =
                    { snapshot
                        | turn = { turn | number = 2 }
                        , playbackFrames =
                            [ { durationMs = 0
                              , units = []
                              , departures = []
                              , losses = []
                              , sabotages = []
                              , indirectImpacts = []
                              , shots = []
                              , visibleTiles = []
                              , depots = []
                              , supplyCrates = []
                              }
                            ]
                    }
            }

        advanced : GamePage.Model
        advanced =
            step (GamePage.PollResponseReceived (Ok resolvedFlags.snapshot)) savedThenClosed

        resigned : GamePage.Model
        resigned =
            let
                { snapshot } =
                    resolvedFlags

                turn : Turn.Snapshot
                turn =
                    snapshot.turn
            in
            step
                (GamePage.PollResponseReceived
                    (Ok
                        { snapshot
                            | turn = { turn | outcome = Just (GameOutcome.Resignation PlayerNumber.Player1) }
                            , playbackFrames = []
                        }
                    )
                )
                savedThenClosed

        battlefieldElement : Browser.Dom.Element
        battlefieldElement =
            { scene =
                { width = 852
                , height = 393
                }
            , viewport =
                { x = 0
                , y = 0
                , width = 852
                , height = 393
                }
            , element =
                { x = 0
                , y = 48
                , width = 852
                , height = 345
                }
            }

        measuredWithoutSelection : GamePage.Model
        measuredWithoutSelection =
            step (GamePage.BattlefieldSizeReceived (Ok battlefieldElement)) ready

        viewportWithoutSelection : Bool
        viewportWithoutSelection =
            case measuredWithoutSelection.battlefieldViewport of
                Just viewport ->
                    (viewport.origin == { x = 0, y = 48 })
                        && (viewport.camera.size == { x = 852, y = 345 })
                        && (viewport.camera.bottomInset == 0)
                        && (viewport.camera.rightInset == 0)

                Nothing ->
                    False

        choosingMove : Bool
        choosingMove =
            case TurnLifecycle.selection moving.currentTurn.phase of
                Just (UnitSelection { interaction }) ->
                    case interaction of
                        ChoosingMove _ ->
                            True

                        _ ->
                            False

                _ ->
                    False
    in
    List.concat
        [ expect "wide viewports use the desktop layout"
            (not (Shared.isMobileView desktop.shared))
        , expect "switching to desktop updates the navigation zoom cap"
            (desktop.navigation /= moving.navigation)
        , expect "switching to desktop clamps the held playback camera"
            playbackResized
        , expect "resizing to desktop and back preserves draft orders and navigation"
            ((desktop.currentTurn == moving.currentTurn)
                && (mobileAgain.currentTurn == moving.currentTurn)
                && (mobileAgain.navigation == moving.navigation)
            )
        , expect "desktop order selection retains the ordinary planning flow"
            (desktopPlanning.currentTurn == moving.currentTurn)
        , expect "desktop order help still opens its planning dialog"
            (GamePage.dialog desktopHelp /= Nothing)
        , expect "portrait uses an independent rotation dialog"
            (Maybe.map Dialog.htmlId (GamePage.dialog portrait)
                == Just "mobile-rotation-notice"
            )
        , expect "landscape does not show the rotation notice"
            (Maybe.map Dialog.htmlId (GamePage.dialog initial)
                /= Just "mobile-rotation-notice"
            )
        , expect "rotation and cancel preserve the pending page dialog"
            (Maybe.map Dialog.htmlId (GamePage.dialog landscapeAgain)
                == Maybe.map Dialog.htmlId (GamePage.dialog initial)
            )
        , expect "mobile viewport updates without a mounted selection panel" viewportWithoutSelection
        , expect "hover, focus, dialog open, and polling leave the inactivity clock alone"
            (List.all leavesInactivityAlone
                [ GamePage.BattlefieldMsg (Battlefield.MouseOverUnit friendlyId)
                , GamePage.FocusCompleted (Ok ())
                , GamePage.ChatMsg ChatView.DialogOpened
                , GamePage.CurrentTurnMsg CurrentTurn.PollTimerElapsed
                ]
            )
        , expect "selecting a unit renews activity during a warning"
            (Inactivity.pending (select friendlyId awaitingActivity).inactivity)
        , expect "typing in chat renews activity during a warning"
            (Inactivity.pending
                (step (GamePage.ChatMsg (ChatView.TextChanged "hi")) awaitingActivity).inactivity
            )
        , expect "acknowledging the warning renews activity"
            (Inactivity.pending afterWarningAcknowledgment.inactivity)
        , expect "direct submission retains the missing-orders warning" warnedBeforeSubmission
        , expect "opening an unload checklist queues the passenger rule error without a checkbox event"
            ((Maybe.map Dialog.htmlId (GamePage.dialog unloadWithMissingRule) == Just "unload-passengers")
                && (unloadWithMissingRule.shared.errors.errors == [ Error.OrderPlanningInvariantViolated unloadViolation ])
                && (unloadWithMissingRule.planningReports.pending == [ { turnNumber = 1, violation = unloadViolation } ])
            )
        , expect "a missing default hold leaves saved drafts editable and reports the unit"
            ((failedPreparation.currentTurn.phase == savedThenClosed.currentTurn.phase)
                && (failedPreparation.currentTurn.error /= Nothing)
                && (failedPreparation.shared.errors.errors
                        == [ Error.OrderPlanningInvariantViolated (OrderPlanning.OrderUnitHasNoPosition enemyId) ]
                   )
            )
        , expect "a planning violation is queued once even when the action fails again after sending"
            ((List.length failedPreparation.planningReports.pending == 1)
                && List.isEmpty repeatedFailure.planningReports.pending
                && (repeatedFailure.shared.errors == failedPreparation.shared.errors)
            )
        , expect "another violation waits for the reporting interval"
            ((List.length distinctFailure.planningReports.pending == 1)
                && ((reportTick (reportTime + 59999) distinctFailure).planningReports
                        == distinctFailure.planningReports
                   )
                && List.isEmpty (reportTick (reportTime + 60000) distinctFailure).planningReports.pending
            )
        , expect "a new resolved turn with one frame displays the snapshot board and records a single error"
            ((advanced.currentTurn.number == 2)
                && (advanced.units == resolvedFlags.snapshot.battlefield.units)
                && (TurnLifecycle.playback advanced.currentTurn.phase == Nothing)
                && ((step (GamePage.PollResponseReceived (Ok resolvedFlags.snapshot)) advanced).shared.errors.errors
                        == [ Error.TurnPlaybackInvariantViolated (TurnPlayback.TooFewFrames { resolvedTurn = 1, frameCount = 1 }) ]
                   )
            )
        , expect "resignation needs no new playback frames"
            ((resigned.currentTurn.outcome /= Nothing) && List.isEmpty resigned.shared.errors.errors)
        , expect "surrender opens confirmation without changing the turn"
            ((GamePage.dialog surrenderRequested /= Nothing)
                && (surrenderRequested.currentTurn == ready.currentTurn)
            )
        , expect "closing the rail preserves saved orders"
            (not (List.isEmpty (TurnLifecycle.orders saved.currentTurn.phase))
                && (TurnLifecycle.orders savedThenClosed.currentTurn.phase == TurnLifecycle.orders saved.currentTurn.phase)
            )
        , expect "friendly selection opens orders" (selected.mobileTab == MobileBattlefield.Orders)
        , expect "fixture enters route planning" choosingMove
        , expect "details preserves active route planning" ((details.mobileTab == MobileBattlefield.Details) && (details.currentTurn == moving.currentTurn))
        , expect "returning to orders preserves active route planning" ((orders.mobileTab == MobileBattlefield.Orders) && (orders.currentTurn == moving.currentTurn))
        , expect "mobile order help preserves active route planning" (helped.currentTurn == moving.currentTurn && GamePage.dialog helped /= Nothing)
        , expect "close deselects the unit" (TurnLifecycle.selection closed.currentTurn.phase == Nothing)
        , expect "enemy selection opens details" (enemy.mobileTab == MobileBattlefield.Details)
        , expect "selecting a friendly unit again resets to orders" (nextFriendly.mobileTab == MobileBattlefield.Orders)
        ]


expect : String -> Bool -> List String
expect label passes =
    if passes then
        []

    else
        [ label ]


unit : UnitId -> PlayerNumber.PlayerNumber -> Int -> Unit
unit id playerNumber x =
    { id = id
    , playerNumber = playerNumber
    , kind = Kind.Infantry
    , direction = Just Direction.North
    , spriteFacing = SpriteFacing.Right
    , entrenchment = Entrenchment.Exposed
    , destroyed = False
    , combatState = Nothing
    , cargoCapacity = 0
    , location =
        Location.OnMap
            { x = x
            , y = 0
            }
    , combatRules =
        { range = 1
        , indirectRange = 0
        , shape = AmbushShape.Line
        , damage = 4
        , readinessCost = 2
        , digInCost = 16
        , shotCost = 2
        }
    , resources =
        Just
            { exhaustionTurnsRemaining = Nothing
            , hitPoints =
                { current = 16
                , maximum = 16
                }
            , supplies =
                { current = 64
                , maximum = 64
                , upkeepPerTurn = 1
                , roughTerrainSurcharge = 0
                , movementPerTile = 1
                }
            , fuel = Nothing
            , supplyCargo = []
            }
    }
