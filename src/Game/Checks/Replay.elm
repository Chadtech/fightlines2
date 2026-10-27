port module Game.Checks.Replay exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.CombatKind as CombatKind
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind
import Api.Scalar exposing (MapId(..))
import Browser
import Browser.Dom
import DevTools.Page.GameReplay as GameReplay
import DevTools.Page.LoggedGames as LoggedGames
import DevTools.Shared as Shared
import Effect as E exposing (Eff)
import Game.BattlefieldNavigation as BattlefieldNavigation
import Game.BattlefieldSnapshot as BattlefieldSnapshot
import Game.CombatHealth exposing (CombatHealth)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Inspection exposing (Inspection(..))
import Game.Map as Map
import Game.PlaybackPresentation as PlaybackPresentation
import Game.RecordedOrder exposing (RecordedOrder)
import Game.Terrain as Terrain
import Game.Turn as Turn
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.Battlefield as Battlefield
import Game.View.CombatTheater as CombatTheater
import Game.View.UnitDeath as UnitDeath
import Graphql.Document
import Graphql.Http
import Json.Decode as Decode
import LocalStorage
import OperatingSystem
import Random


port results : List String -> Cmd msg


setBattlefieldUnits : List Unit -> BattlefieldSnapshot.Snapshot -> BattlefieldSnapshot.Snapshot
setBattlefieldUnits units model =
    { model | units = units }


setPositionFogOfWar : Bool -> Position -> Position
setPositionFogOfWar fogOfWar model =
    { model | fogOfWar = fogOfWar }


setPositionTurn : Int -> Position -> Position
setPositionTurn turn model =
    { model | turn = turn }


main : Program () () ()
main =
    Browser.application
        { init =
            \_ _ key ->
                let
                    ( failures, effect ) =
                        checks (Shared.init (Random.initialSeed 0) OperatingSystem.Unknown LocalStorage.test key)
                in
                ( (), Cmd.batch [ results failures, E.toCmd key effect ] )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = \_ -> { title = "replay state checks", body = [] }
        , onUrlChange = \_ -> ()
        , onUrlRequest = \_ -> ()
        }


type alias Position =
    { turn : Int
    , player : PlayerNumber.PlayerNumber
    , fogOfWar : Bool
    }


type alias RecordedTurn =
    { battlefield : BattlefieldSnapshot.Snapshot
    , frames : List TurnPlayback.Frame
    , resolution : Maybe Turn.Resolution
    , orders : List RecordedOrder
    }


checks : Shared.Model -> ( List String, Eff () )
checks shared =
    case Decode.decodeString (Graphql.Document.decoder LoggedGames.selection) ("{\"data\":" ++ gameJson ++ "}") of
        Err error ->
            ( [ Decode.errorToString error ], E.none )

        Ok game ->
            let
                opening : RecordedTurn
                opening =
                    recordedTurn []

                turn : RecordedTurn
                turn =
                    recordedTurn [ frame [], frame [ { x = 1, y = 1 } ] ]

                initial : GameReplay.Model
                initial =
                    GameReplay.init shared game.id { game = game, turn = opening, backdropCalibrations = [] } |> Tuple.first

                step : GameReplay.Msg -> GameReplay.Model -> GameReplay.Model
                step msg model =
                    GameReplay.update msg model |> Tuple.first

                redTurn : Int -> { turn : Int, player : PlayerNumber.PlayerNumber, fogOfWar : Bool }
                redTurn number =
                    { turn = number, player = PlayerNumber.Player1, fogOfWar = True }

                tick : GameReplay.Model -> GameReplay.Model
                tick =
                    step (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 1000))

                loading : GameReplay.Model
                loading =
                    step GameReplay.PlayClicked initial

                playing : GameReplay.Model
                playing =
                    step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn)) loading

                paused : GameReplay.Model
                paused =
                    step GameReplay.PauseClicked playing

                framed : GameReplay.Model
                framed =
                    step (GameReplay.InspectorSizeReceived viewportElement (Ok inspectorElement)) playing

                framedPause : GameReplay.Model
                framedPause =
                    step GameReplay.PauseClicked framed

                pannedPause : GameReplay.Model
                pannedPause =
                    step GameReplay.PanRightKeyPressed framedPause

                zoomedPause : GameReplay.Model
                zoomedPause =
                    step (GameReplay.BattlefieldMsg Battlefield.ZoomInClicked) pannedPause

                resumed : GameReplay.Model
                resumed =
                    step GameReplay.PlayClicked paused

                finishedFirst : GameReplay.Model
                finishedFirst =
                    tick resumed

                playingSecond : GameReplay.Model
                playingSecond =
                    step (GameReplay.TurnResponseReceived (redTurn 2) (Ok turn)) finishedFirst

                manual : GameReplay.Model
                manual =
                    initial
                        |> step (GameReplay.TurnSelected 1)
                        |> step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn))
                        |> tick

                failed : GameReplay.Model
                failed =
                    step (GameReplay.TurnResponseReceived (redTurn 1) (Err (Graphql.Http.HttpError Graphql.Http.Timeout))) loading

                retried : GameReplay.Model
                retried =
                    failed
                        |> step GameReplay.RetryClicked
                        |> step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn))

                zoomed : GameReplay.Model
                zoomed =
                    step (GameReplay.BattlefieldMsg Battlefield.ZoomInClicked) initial

                selected : GameReplay.Model
                selected =
                    zoomed
                        |> step (GameReplay.TurnSelected 1)
                        |> step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn))

                blue : { turn : Int, player : PlayerNumber.PlayerNumber, fogOfWar : Bool }
                blue =
                    { turn = 1, player = PlayerNumber.Player2, fogOfWar = True }

                switched : GameReplay.Model
                switched =
                    selected
                        |> step (GameReplay.PlayerSelected PlayerNumber.Player2)
                        |> step (GameReplay.TurnResponseReceived blue (Ok turn))

                inspected : GameReplay.Model
                inspected =
                    initial |> step (GameReplay.BattlefieldMsg (Battlefield.PressedEnterOnTile { x = 1, y = 1 }))

                emptyTurn : GameReplay.Model
                emptyTurn =
                    loading
                        |> step (GameReplay.TurnResponseReceived (redTurn 1) (Ok opening))
                        |> step (GameReplay.TurnResponseReceived (redTurn 2) (Ok turn))

                revealedPosition : { turn : Int, player : PlayerNumber.PlayerNumber, fogOfWar : Bool }
                revealedPosition =
                    { turn = 1, player = PlayerNumber.Player1, fogOfWar = False }

                revealing : GameReplay.Model
                revealing =
                    step (GameReplay.FogOfWarChanged False) manual

                revealed : GameReplay.Model
                revealed =
                    step (GameReplay.TurnResponseReceived revealedPosition (Ok turn)) revealing

                revealedBlue : GameReplay.Model
                revealedBlue =
                    revealed
                        |> step (GameReplay.PlayerSelected PlayerNumber.Player2)
                        |> step
                            (GameReplay.TurnResponseReceived
                                (blue
                                    |> setPositionFogOfWar False
                                )
                                (Ok turn)
                            )

                refogged : GameReplay.Model
                refogged =
                    revealed
                        |> step (GameReplay.FogOfWarChanged True)
                        |> step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn))

                ( lossFailures, lossEffects ) =
                    lossChecks initial

                ( audioFailures, audioEffects ) =
                    audioChecks initial

                unframed : GameReplay.Model
                unframed =
                    { playing
                        | viewport =
                            Just
                                { size =
                                    { x = 800
                                    , y = 600
                                    }
                                , bottomInset = 0
                                , rightInset = 200
                                }
                    }
            in
            ( List.concat
                [ lossFailures
                , audioFailures
                , selectionChecks initial
                , expect "order overlays start hidden" (not initial.showOrders)
                , expect "order overlays toggle without changing playback" ((step (GameReplay.ShowOrdersChanged True) paused).showOrders && (step (GameReplay.ShowOrdersChanged True) paused).timeline == paused.timeline)
                , expect "order overlay preference survives turn responses" (step (GameReplay.ShowOrdersChanged True) revealing |> step (GameReplay.TurnResponseReceived revealedPosition (Ok turn))).showOrders
                , expect "replay starts with fog enabled" initial.position.fogOfWar
                , expect "fog changes reload the same turn and keep the saved camera" (revealed.position == revealedPosition && revealed.navigation.offset == manual.navigation.offset && revealed.navigation.zoom == manual.navigation.zoom)
                , expect "fog requests reject stale responses for the same turn and player" ((step (GameReplay.TurnResponseReceived (redTurn 1) (Ok turn)) revealing).position == manual.position)
                , expect "changing player retains disabled fog"
                    (revealedBlue.position
                        == (blue
                                |> setPositionFogOfWar False
                           )
                    )
                , expect "changing turns retains disabled fog"
                    ((step GameReplay.NextClicked revealed
                        |> step
                            (GameReplay.TurnResponseReceived
                                (revealedPosition
                                    |> setPositionTurn 2
                                )
                                (Ok turn)
                            )
                     ).position
                        == (revealedPosition
                                |> setPositionTurn 2
                           )
                    )
                , expect "fog can be restored to the original player projection" (refogged.position == redTurn 1 && refogged.battlefield == playing.battlefield)
                , expect "loading prevents a second fog request" ((step (GameReplay.FogOfWarChanged False) loading).request == loading.request)
                , expect "viewport measurement initializes the playback camera" (framed.timeline /= playing.timeline)
                , expect "sprite timers and hover events do not initialize the playback camera" ((step GameReplay.AnimationTimerElapsed unframed).timeline == unframed.timeline && (step (GameReplay.BattlefieldMsg (Battlefield.MouseOverTile { x = 1, y = 1 })) unframed).timeline == unframed.timeline)
                , expect "completed playback returns to the saved camera" (BattlefieldNavigation.returning finishedFirst.navigation && not (BattlefieldNavigation.returning (step GameReplay.CameraReturnFinished finishedFirst).navigation))
                , expect "starting board has no live turn introduction or loss dialog" (GameReplay.dialog initial == Nothing)
                , expect "play requests the first recorded turn and rewinds projected sight" (playing.position == redTurn 1 && playing.battlefield.visibleTiles == [])
                , expect "pause freezes animation and projected board state" ((tick paused).timeline == paused.timeline && (tick paused).battlefield == paused.battlefield)
                , expect "paused navigation releases the held playback camera without advancing the board" (pannedPause.timeline /= framedPause.timeline && pannedPause.navigation.offset.x == framedPause.navigation.offset.x - 48 && pannedPause.battlefield == framedPause.battlefield)
                , expect "paused zoom changes the manual view and stays fixed across animation ticks" (zoomedPause.navigation.zoom == 1.25 && (tick zoomedPause).timeline == zoomedPause.timeline && (tick zoomedPause).battlefield == zoomedPause.battlefield)
                , expect "resuming after manual navigation restores automatic framing" ((step GameReplay.PlayClicked zoomedPause).timeline /= zoomedPause.timeline)
                , expect "play resumes a paused turn and reaches its recorded final sight" (finishedFirst.battlefield.visibleTiles == [ { x = 1, y = 1 } ])
                , expect "continuous play requests and accepts the next recorded turn" (playingSecond.position == redTurn 2 && playingSecond.battlefield.visibleTiles == [])
                , expect "continuous play stops at the last recorded turn" ((tick playingSecond |> step (GameReplay.TurnResponseReceived (redTurn 3) (Ok turn))).position == redTurn 2)
                , expect "manual turn selection plays only the selected turn" ((step (GameReplay.TurnResponseReceived (redTurn 2) (Ok turn)) manual).position == redTurn 1)
                , expect "loading blocks duplicate navigation and mismatched responses" ((step GameReplay.NextClicked loading).request == loading.request && (step (GameReplay.TurnResponseReceived (redTurn 2) (Ok turn)) loading).position == initial.position)
                , expect "failed loading preserves the displayed board and allows retry" (failed.battlefield == initial.battlefield && retried.position == redTurn 1)
                , expect "changing turns retains the saved camera" (selected.navigation == zoomed.navigation)
                , expect "changing viewers requests that viewer and preserves camera state" (switched.position == blue && switched.navigation == zoomed.navigation)
                , expect "keyboard inspection can be cleared without entering planning" (inspected.inspection /= Nothing && (step GameReplay.EscapePressed inspected).inspection == Nothing)
                , expect "continuous play advances through a turn with no animation frames" (emptyTurn.position == redTurn 2)
                ]
            , E.batch [ lossEffects, audioEffects ]
            )


selectionChecks : GameReplay.Model -> List String
selectionChecks initial =
    case UnitId.parse "1" of
        Err _ ->
            [ "could not construct replay selection fixture ID" ]

        Ok id ->
            let
                unit : Unit
                unit =
                    fixtureUnit id

                movedUnit : Unit
                movedUnit =
                    { unit | location = Location.OnMap { x = 2, y = 1 } }

                battlefield : BattlefieldSnapshot.Snapshot
                battlefield =
                    initial.battlefield

                opening : GameReplay.Model
                opening =
                    { initial
                        | battlefield =
                            battlefield
                                |> setBattlefieldUnits
                                    [ unit ]
                    }

                firstFrame : TurnPlayback.Frame
                firstFrame =
                    frame []

                turn : RecordedTurn
                turn =
                    { battlefield =
                        battlefield
                            |> setBattlefieldUnits
                                [ movedUnit ]
                    , frames =
                        [ firstFrame
                            |> TurnPlayback.setFrameUnits
                                [ unit ]
                        , firstFrame
                            |> TurnPlayback.setFrameUnits
                                [ movedUnit ]
                        ]
                    , orders = []
                    , resolution = Nothing
                    }

                position : Int -> { turn : Int, player : PlayerNumber.PlayerNumber, fogOfWar : Bool }
                position number =
                    { turn = number, player = PlayerNumber.Player1, fogOfWar = True }

                step : GameReplay.Msg -> GameReplay.Model -> GameReplay.Model
                step msg model =
                    GameReplay.update msg model |> Tuple.first

                tick : GameReplay.Model -> GameReplay.Model
                tick =
                    step (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 1000))

                selected : GameReplay.Model
                selected =
                    step (GameReplay.BattlefieldMsg (Battlefield.ClickedUnit id { detail = 1 })) opening

                playing : GameReplay.Model
                playing =
                    selected
                        |> step GameReplay.NextClicked
                        |> step (GameReplay.TurnResponseReceived (position 1) (Ok turn))

                finished : GameReplay.Model
                finished =
                    tick playing

                continuous : GameReplay.Model
                continuous =
                    selected
                        |> step GameReplay.PlayClicked
                        |> step (GameReplay.TurnResponseReceived (position 1) (Ok turn))
                        |> tick
                        |> step (GameReplay.TurnResponseReceived (position 2) (Ok turn))

                previous : GameReplay.Model
                previous =
                    finished
                        |> step GameReplay.PreviousClicked
                        |> step (GameReplay.TurnResponseReceived (position 0) (Ok { battlefield = opening.battlefield, frames = [], resolution = Nothing, orders = [] }))

                hidden : GameReplay.Model
                hidden =
                    finished
                        |> step (GameReplay.TurnSelected 2)
                        |> step (GameReplay.TurnResponseReceived (position 2) (Ok (recordedTurn [])))

                returned : GameReplay.Model
                returned =
                    hidden
                        |> step (GameReplay.TurnSelected 1)
                        |> step (GameReplay.TurnResponseReceived (position 1) (Ok turn))

                cleared : GameReplay.Model
                cleared =
                    finished
                        |> step GameReplay.EscapePressed
                        |> step GameReplay.NextClicked
                        |> step (GameReplay.TurnResponseReceived (position 2) (Ok turn))
            in
            List.concat
                [ expect "next turn retains the clicked unit through playback start and completion" (playing.inspection == Just (UnitInspection id) && finished.inspection == selected.inspection && finished.battlefield.units == [ movedUnit ])
                , expect "continuous playback retains the same selected unit across turns" (continuous.inspection == selected.inspection)
                , expect "previous turn and restarting playback retain unit selection" (previous.inspection == selected.inspection && (step GameReplay.PlayClicked finished).inspection == selected.inspection)
                , expect "turn jumps retain unit identity without retaining unavailable unit data" (hidden.inspection == selected.inspection && hidden.battlefield.units == [] && returned.inspection == selected.inspection)
                , expect "explicit deselection persists across turns" (cleared.inspection == Nothing && (step (GameReplay.BattlefieldMsg (Battlefield.PressedEnterOnUnit id)) selected).inspection == Nothing)
                ]


audioChecks : GameReplay.Model -> ( List String, Eff () )
audioChecks initial =
    case ( UnitId.parse "1", UnitId.parse "2" ) of
        ( Ok first, Ok second ) ->
            let
                attacker : Unit
                attacker =
                    fixtureUnit first |> Unit.setKind Kind.Tank

                target : Unit
                target =
                    fixtureUnit second |> Unit.setPlayerNumber PlayerNumber.Player2 |> Unit.setOnMap { x = 2, y = 1 }

                health : CombatHealth
                health =
                    { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }

                empty : TurnPlayback.Frame
                empty =
                    frame []

                before : TurnPlayback.Frame
                before =
                    { empty | units = [ attacker, target ] }

                volley : TurnPlayback.Frame
                volley =
                    { before
                        | shots =
                            [ { kind = CombatKind.Ambush
                              , origin = { x = 1, y = 1 }
                              , destination = { x = 2, y = 1 }
                              , attacker = attacker
                              , target = target
                              , damage = 0
                              , attackerHealth = health
                              , targetHealth = health
                              }
                            ]
                    }

                tick : Float -> GameReplay.Model -> ( GameReplay.Model, Eff GameReplay.Msg )
                tick delta =
                    GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed delta))

                showing : GameReplay.Model
                showing =
                    GameReplay.update (GameReplay.TurnSelected 1) initial
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.TurnResponseReceived { turn = 1, player = PlayerNumber.Player1, fogOfWar = True } (Ok (recordedTurn [ before, volley, before ])))
                        |> Tuple.first
                        |> tick 5000
                        |> Tuple.first
                        |> tick 300
                        |> Tuple.first
                        |> tick 1199
                        |> Tuple.first

                ( fired, firstCue ) =
                    tick 1 showing

                ( _, heldCue ) =
                    tick 0 fired

                paused : GameReplay.Model
                paused =
                    GameReplay.update GameReplay.PauseClicked fired |> Tuple.first

                ( held, pausedCue ) =
                    tick 500 paused

                ( _, remainingCues ) =
                    GameReplay.update GameReplay.PlayClicked held |> Tuple.first |> tick 300
            in
            ( expect "paused replay clocks remain frozen through firing timestamps" (held.timeline == paused.timeline)
            , E.batch [ firstCue, heldCue, pausedCue, remainingCues ] |> E.map (always ())
            )

        _ ->
            ( [ "could not construct replay audio fixture IDs" ], E.none )


lossChecks : GameReplay.Model -> ( List String, Eff () )
lossChecks initial =
    case ( UnitId.parse "1", UnitId.parse "2" ) of
        ( Ok first, Ok second ) ->
            let
                living : List Unit
                living =
                    List.map fixtureUnit [ first, second ]

                alive : TurnPlayback.Frame
                alive =
                    frame []

                loss : Unit -> TurnPlayback.Loss
                loss unit =
                    { unit = unit, cause = TurnPlayback.SuppliesExhausted }

                deaths : TurnPlayback.Frame
                deaths =
                    alive
                        |> TurnPlayback.setFrameUnits (List.map (Unit.setDestroyed True) living)
                        |> TurnPlayback.setFrameLosses (List.map loss living)

                position : { turn : Int, player : PlayerNumber.PlayerNumber, fogOfWar : Bool }
                position =
                    { turn = 1, player = PlayerNumber.Player1, fogOfWar = True }

                loading : GameReplay.Model
                loading =
                    GameReplay.update (GameReplay.TurnSelected 1) initial |> Tuple.first

                playing : GameReplay.Model
                playing =
                    GameReplay.update
                        (GameReplay.TurnResponseReceived position
                            (Ok
                                (recordedTurn
                                    [ alive
                                        |> TurnPlayback.setFrameUnits living
                                    , deaths
                                    , alive
                                    ]
                                )
                            )
                        )
                        loading
                        |> Tuple.first

                ( lost, firstDialog ) =
                    playing
                        |> GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 1000))
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 300))
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.CombatTheaterMsg CombatTheater.ContinueClicked)

                ( held, heldDialog ) =
                    GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 1000)) lost

                ( hovered, hoverDialog ) =
                    GameReplay.update (GameReplay.BattlefieldMsg (Battlefield.MouseOverTile { x = 1, y = 1 })) held

                ( acknowledged, secondDialog ) =
                    hovered
                        |> GameReplay.update (GameReplay.UnitDeathMsg (UnitDeath.ContinueClicked first))
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 1000))
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.PlaybackMsg (PlaybackPresentation.FrameElapsed 300))
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.CombatTheaterMsg CombatTheater.ContinueClicked)

                skipped : GameReplay.Model
                skipped =
                    GameReplay.update (GameReplay.UnitDeathMsg (UnitDeath.SkipDialogsChanged True)) acknowledged |> Tuple.first

                restored : GameReplay.Model
                restored =
                    GameReplay.update (GameReplay.UnitDeathMsg (UnitDeath.SkipDialogsChanged False)) skipped |> Tuple.first

                initialLoss : GameReplay.Model
                initialLoss =
                    GameReplay.update (GameReplay.TurnResponseReceived position (Ok (recordedTurn [ deaths, alive ]))) loading |> Tuple.first

                emptyReplacement : GameReplay.Model
                emptyReplacement =
                    playing
                        |> GameReplay.update (GameReplay.TurnSelected 2)
                        |> Tuple.first
                        |> GameReplay.update (GameReplay.TurnResponseReceived { position | turn = 2 } (Ok (recordedTurn [])))
                        |> Tuple.first
            in
            ( List.concat
                [ expect "playback opens an initial loss and reports its missing owner once" (GameReplay.dialog initialLoss /= Nothing && List.length initialLoss.shared.errors.errors == 1)
                , expect "playback stops at the loss and repeated ticks do not repeat its diagnostic" (GameReplay.dialog lost /= Nothing && List.length lost.shared.errors.errors == 1 && held.shared.errors == lost.shared.errors && held.timeline == lost.timeline)
                , expect "unrelated events leave the pending loss and diagnostics unchanged" (hovered == held)
                , expect "continuing the next exhaustion theater opens its independent loss and reports its owner" (GameReplay.dialog acknowledged /= Nothing && List.length acknowledged.shared.errors.errors == 2)
                , expect "skipping hides the pending loss and reenabling restores it" (GameReplay.dialog skipped == Nothing && GameReplay.dialog restored /= Nothing && List.length restored.shared.errors.errors == 3)
                , expect "loading an empty turn stops the old playback and restores the saved view" (GameReplay.dialog emptyReplacement == Nothing && BattlefieldNavigation.returning emptyReplacement.navigation && emptyReplacement.battlefield.units == [])
                ]
            , E.batch [ firstDialog, heldDialog, hoverDialog, secondDialog ] |> E.map (always ())
            )

        _ ->
            ( [ "could not construct replay loss fixture IDs" ], E.none )


fixtureUnit : UnitId -> Unit
fixtureUnit id =
    { id = id
    , playerNumber = PlayerNumber.Player1
    , kind = Kind.Infantry
    , direction = Nothing
    , spriteFacing = SpriteFacing.Right
    , resources = Nothing
    , cargoCapacity = 0
    , destroyed = False
    , combatState = Nothing
    , combatRules =
        { range = 1
        , indirectRange = 0
        , shape = AmbushShape.Line
        , damage = 4
        , readinessCost = 8
        , digInCost = 64
        , shotCost = 12
        }
    , entrenchment = Entrenchment.Exposed
    , location = Location.OnMap { x = 1, y = 1 }
    }


viewportElement : Browser.Dom.Element
viewportElement =
    { scene = { width = 800, height = 600 }
    , viewport = { x = 0, y = 0, width = 800, height = 600 }
    , element = { x = 0, y = 0, width = 800, height = 600 }
    }


inspectorElement : Browser.Dom.Element
inspectorElement =
    { viewportElement
        | element =
            { x = 600
            , y = 0
            , width = 200
            , height = 600
            }
    }


expect : String -> Bool -> List String
expect label passed =
    if passed then
        []

    else
        [ label ]


recordedTurn : List TurnPlayback.Frame -> RecordedTurn
recordedTurn frames =
    { battlefield =
        { name = "replay fixture"
        , mapType = MapId "supply-point"
        , players = []
        , map = Map.fromFeatures { width = 3, height = 3, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }
        , units = []
        , depots = []
        , supplyCrates = []
        , visibleTiles = []
        }
    , frames = frames
    , orders = []
    , resolution = Nothing
    }


frame : List Coordinate -> TurnPlayback.Frame
frame visible =
    { durationMs = 180
    , units = []
    , departures = []
    , losses = []
    , sabotages = []
    , indirectImpacts = []
    , shots = []
    , visibleTiles = visible
    , depots = []
    , supplyCrates = []
    }


gameJson : String
gameJson =
    """{"id":"00000000000000000000000000000001-1","name":"replay fixture","mapType":"supply-point","startedAt":"0","players":[],"turnCount":2,"status":{"kind":"UNFINISHED","winner":null}}"""
