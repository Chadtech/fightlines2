port module Game.Checks.Turn exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.BuildingKind as BuildingKind
import Api.Enum.CombatKind as CombatKind
import Api.Enum.Direction as Direction
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
import Audio
import Game.Camera as Camera
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot exposing (Depot)
import Game.Direction as Direction
import Game.IndirectImpact as IndirectImpact exposing (IndirectImpact)
import Game.Map as Map
import Game.PlaybackPresentation as PlaybackPresentation
import Game.Shot as Shot exposing (Shot)
import Game.Terrain as Terrain
import Game.Turn as Turn
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Location as Location
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitLoss as UnitLoss
import Game.UnitLoss.Cause as LossCause
import Game.UnitResources as UnitResources
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatExplosion as CombatExplosion
import Game.View.CombatFormation as CombatFormation
import Game.View.CombatTheater as CombatTheater
import Platform
import Point exposing (Point)


port results : List String -> Cmd msg


setFrameDurationMs : Int -> TurnPlayback.Frame -> TurnPlayback.Frame
setFrameDurationMs durationMs model =
    { model | durationMs = durationMs }


setFrameIndirectImpacts : List IndirectImpact -> TurnPlayback.Frame -> TurnPlayback.Frame
setFrameIndirectImpacts indirectImpacts model =
    { model | indirectImpacts = indirectImpacts }


setFrameSabotages : List Coordinate -> TurnPlayback.Frame -> TurnPlayback.Frame
setFrameSabotages sabotages model =
    { model | sabotages = sabotages }


setPlaybackCurrent : TurnPlayback.Frame -> TurnPlayback.Playback -> TurnPlayback.Playback
setPlaybackCurrent current model =
    { model | current = current }


setPlaybackRemaining : List TurnPlayback.Frame -> TurnPlayback.Playback -> TurnPlayback.Playback
setPlaybackRemaining remaining model =
    { model | remaining = remaining }


setShotOrigin : Coordinate -> Shot -> Shot
setShotOrigin origin model =
    { model | origin = origin }


setShotDestination : Coordinate -> Shot -> Shot
setShotDestination destination model =
    { model | destination = destination }


setShotAttacker : Unit -> Shot -> Shot
setShotAttacker attacker model =
    { model | attacker = attacker }


setShotTarget : Unit -> Shot -> Shot
setShotTarget target model =
    { model | target = target }


setShotKind : CombatKind.CombatKind -> Shot -> Shot
setShotKind kind model =
    { model | kind = kind }


setShotDamage : Int -> Shot -> Shot
setShotDamage damage model =
    { model | damage = damage }


setEventUnitId : UnitId -> Turn.Event -> Turn.Event
setEventUnitId unitId model =
    { model | unitId = unitId }


setEventKind : EventKind.TurnEventKind -> Turn.Event -> Turn.Event
setEventKind kind model =
    { model | kind = kind }


setEventPath : List Coordinate -> Turn.Event -> Turn.Event
setEventPath path model =
    { model | path = path }


setEventInitialSpriteFacing : SpriteFacing.SpriteFacing -> Turn.Event -> Turn.Event
setEventInitialSpriteFacing initialSpriteFacing model =
    { model | initialSpriteFacing = initialSpriteFacing }


setEventInitialDirection : Maybe Direction.Direction -> Turn.Event -> Turn.Event
setEventInitialDirection initialDirection model =
    { model | initialDirection = initialDirection }


setPanelElapsed : Float -> TurnPlayback.Panel -> TurnPlayback.Panel
setPanelElapsed elapsed model =
    { model | elapsed = elapsed }


setPanelEncounter : TurnPlayback.Encounter -> TurnPlayback.Panel -> TurnPlayback.Panel
setPanelEncounter encounter model =
    { model | encounter = encounter }


setImpactAttacker : Maybe IndirectImpact.Attacker -> IndirectImpact -> IndirectImpact
setImpactAttacker attacker model =
    { model | attacker = attacker }


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    case ( UnitId.parse "1", UnitId.parse "2" ) of
        ( Ok first, Ok second ) ->
            playbackChecks first second ++ truckPlaybackChecks first ++ transportPlaybackChecks first second ++ spriteFacingChecks first ++ deathPlaybackChecks first ++ deathFocusChecks first second ++ combatPlaybackChecks first second ++ combatDeathChecks first second ++ cameraChecks ++ combatTheaterChecks ++ lossDetailsChecks first second ++ carrierLossEventChecks first second

        _ ->
            [ "could not construct fixture IDs" ]


impactEncounter : IndirectImpact -> TurnPlayback.Encounter
impactEncounter impact =
    TurnPlayback.Impact
        { destination = impact.destination
        , attackers = impact.attacker |> Maybe.map List.singleton |> Maybe.withDefault []
        , target = impact.target
        , depot = impact.depot
        }


playbackChecks : UnitId -> UnitId -> List String
playbackChecks first second =
    let
        units : List Unit
        units =
            [ { destroyed = False
              , combatState = Nothing
              , combatRules =
                    { range = 1
                    , indirectRange = 0
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , digInCost = 64
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = first
              , playerNumber = PlayerNumber.Player1
              , entrenchment = Entrenchment.Exposed
              , spriteFacing = SpriteFacing.Right
              , direction = Just Direction.East
              , kind = Kind.Infantry
              , location =
                    Location.OnMap
                        { x = 1
                        , y = 0
                        }
              , resources =
                    Just
                        { supplyCargo = []
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
                        }
              }
            , { destroyed = False
              , combatState = Nothing
              , combatRules =
                    { range = 1
                    , indirectRange = 0
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , digInCost = 64
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = second
              , playerNumber = PlayerNumber.Player2
              , entrenchment = Entrenchment.Exposed
              , spriteFacing = SpriteFacing.Left
              , direction = Just Direction.West
              , kind = Kind.Infantry
              , location =
                    Location.OnMap
                        { x = 1
                        , y = 1
                        }
              , resources =
                    Just
                        { supplyCargo = []
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
                        }
              }
            ]

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , outcome = Nothing
            , resolution =
                Just
                    { number = 1
                    , report = Nothing
                    , events =
                        [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialSpriteFacing = SpriteFacing.Right, initialDirection = Just Direction.South, unitId = first, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ] }
                        , { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialSpriteFacing = SpriteFacing.Right, initialDirection = Just Direction.North, unitId = second, path = [ { x = 2, y = 1 }, { x = 1, y = 1 } ] }
                        ]
                    }
            }

        rewound : List Unit
        rewound =
            Turn.rewind snapshot units

        initial : Turn.Playback
        initial =
            Turn.start snapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( halfway, halfwayUnits ) =
            Turn.tick 90 initial rewound

        ( next, firstFinished ) =
            Turn.tick 180 initial rewound

        ( finished, finalUnits ) =
            next |> Maybe.map (\playing -> Turn.tick 180 playing firstFinished) |> Maybe.withDefault ( Nothing, firstFinished )

        rotation : Turn.Event
        rotation =
            { rotationDirection = Just Direction.West, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Ambush, initialSpriteFacing = SpriteFacing.Right, initialDirection = Just Direction.East, unitId = first, path = [ { x = 1, y = 0 } ] }

        rotationSnapshot : Turn.Snapshot
        rotationSnapshot =
            { snapshot | resolution = Just { number = 1, report = Nothing, events = [ rotation ] } }

        rotationUnits : List Unit
        rotationUnits =
            Turn.rewind rotationSnapshot units

        rotationPlayback : Turn.Playback
        rotationPlayback =
            Turn.start rotationSnapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( rotationPending, rotationHalfway ) =
            Turn.tick 90 rotationPlayback rotationUnits

        ( rotationFinished, rotatedUnits ) =
            Turn.tick 180 rotationPlayback rotationUnits

        cornerPath : List { x : Int, y : Int }
        cornerPath =
            [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ]

        cornerPlayback : Turn.Playback
        cornerPlayback =
            { events = [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, unitId = first, initialSpriteFacing = SpriteFacing.Right, initialDirection = Just Direction.West, path = cornerPath } ]
            , elapsed = 0
            }

        ( _, cornerUnits ) =
            Turn.tick 180 cornerPlayback rewound

        ( cornerFinished, cornerFinalUnits ) =
            Turn.tick 360 cornerPlayback rewound

        firstFrame : TurnPlayback.Frame
        firstFrame =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = rewound
            , visibleTiles =
                [ { x = 0
                  , y = 0
                  }
                ]
            }

        lastFrame : TurnPlayback.Frame
        lastFrame =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = units
            , visibleTiles =
                [ { x = 1
                  , y = 0
                  }
                ]
            }

        advanceFirstUnit : Unit -> Unit
        advanceFirstUnit unit =
            if unit.id == first then
                List.head units |> Maybe.withDefault unit

            else
                unit

        middleFrame : TurnPlayback.Frame
        middleFrame =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units =
                List.map advanceFirstUnit rewound
            , visibleTiles = lastFrame.visibleTiles
            }

        sharedPlayback : TurnPlayback.Playback
        sharedPlayback =
            { current = firstFrame
            , remaining = [ middleFrame, lastFrame ]
            , acknowledgedLosses = []
            , presentation = TurnPlayback.Battlefield
            , elapsed = 0
            }

        ( sharedHalfway, sharedFrame ) =
            TurnPlayback.tick 90 sharedPlayback

        ( sharedFinished, sharedFinal ) =
            TurnPlayback.tick 360 sharedPlayback

        hiddenFrame : TurnPlayback.Frame
        hiddenFrame =
            firstFrame
                |> TurnPlayback.setFrameUnits (List.filter (\unit -> unit.id == first) firstFrame.units)

        ( entering, _ ) =
            TurnPlayback.tick 90
                (sharedPlayback
                    |> setPlaybackCurrent hiddenFrame
                )

        ( leaving, _ ) =
            TurnPlayback.tick 90
                (sharedPlayback
                    |> setPlaybackRemaining
                        [ middleFrame
                            |> TurnPlayback.setFrameUnits (List.filter (\unit -> unit.id == first) lastFrame.units)
                        ]
                )

        exitFrame : TurnPlayback.Frame
        exitFrame =
            { firstFrame | departures = [ { unitId = second, direction = Direction.East } ] }

        ( departing, departingFrame ) =
            TurnPlayback.tick 90
                (sharedPlayback
                    |> setPlaybackCurrent exitFrame
                    |> setPlaybackRemaining
                        [ hiddenFrame ]
                )

        ( surplus, surplusFrame ) =
            TurnPlayback.tick 270 sharedPlayback

        ( timedHalfway, _ ) =
            TurnPlayback.tick 210
                (sharedPlayback
                    |> setPlaybackRemaining
                        [ lastFrame
                            |> setFrameDurationMs 420
                        ]
                )

        continueFirstUnit : Unit -> Unit
        continueFirstUnit unit =
            if unit.id == first then
                Unit.setOnMap { x = 1, y = 1 } unit

            else
                unit

        continuingFrame : TurnPlayback.Frame
        continuingFrame =
            middleFrame
                |> TurnPlayback.setFrameUnits (List.map continueFirstUnit middleFrame.units)

        longRoute : Maybe TurnPlayback.Playback
        longRoute =
            TurnPlayback.start
                [ firstFrame
                , middleFrame
                , continuingFrame
                , continuingFrame
                    |> setFrameDurationMs 180
                ]

        afterBoundary : Maybe TurnPlayback.Playback
        afterBoundary =
            longRoute |> Maybe.andThen (TurnPlayback.tick 270 >> Tuple.first)

        afterMovement : Maybe TurnPlayback.Playback
        afterMovement =
            longRoute |> Maybe.andThen (TurnPlayback.tick 400 >> Tuple.first)

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ movementAudioChecks firstFrame lastFrame
        , expect "camera subjects follow interpolated visible movers"
            (Maybe.map TurnPlayback.focusPositions timedHalfway == Just [ { x = 0.5, y = 0 }, { x = 1.5, y = 1 } ])
        , expect "camera subjects exclude routes entering or leaving fog"
            (Maybe.map TurnPlayback.focusPositions entering == Just [ { x = 0.5, y = 0 } ] && Maybe.map TurnPlayback.focusPositions leaving == Just [ { x = 0.5, y = 0 } ])
        , expect "camera subjects track visible movement across tile boundaries"
            (Maybe.map TurnPlayback.focusPositions afterBoundary == Just [ { x = 1, y = 0.5 } ])
        , expect "idle frames do not request a return pan"
            (Maybe.map TurnPlayback.focusPositions afterMovement == Just [])
        , expect "camera subjects update when another unit starts moving"
            (Maybe.map TurnPlayback.focusPositions surplus == Just [ { x = 1.5, y = 1 } ])
        , expect "camera subjects include only the projected fog departure"
            (Maybe.map TurnPlayback.focusPositions departing == Just (List.map .position (TurnPlayback.movingPositions departing)))
        , expect "camera frames projected indirect impacts even without a hit"
            (TurnPlayback.focusPositions
                (sharedPlayback
                    |> setPlaybackCurrent
                        (firstFrame
                            |> setFrameIndirectImpacts
                                [ { destination = { x = 8, y = 9 }, attacker = Nothing, target = Nothing, depot = Nothing } ]
                        )
                    |> setPlaybackRemaining []
                )
                == [ { x = 8, y = 9 } ]
            )
        , expect "all simultaneous arrivals interpolate using server frame duration"
            (TurnPlayback.movingPositions timedHalfway == [ { unitId = first, position = { x = 0.5, y = 0 } }, { unitId = second, position = { x = 1.5, y = 1 } } ])
        , expect "only the first unit interpolates during its route"
            (TurnPlayback.movingPositions sharedHalfway == [ { unitId = first, position = { x = 0.5, y = 0 } } ])
        , expect "waiting unit preserves its facing during the first route"
            (List.map .direction sharedFrame.units == [ Just Direction.East, Just Direction.North ])
        , expect "fog changes only at shared tile boundaries"
            (sharedFrame.visibleTiles == firstFrame.visibleTiles && sharedFinal == lastFrame && sharedFinished == Nothing)
        , expect "entering and leaving sight never interpolate a hidden route"
            (List.map .unitId (TurnPlayback.movingPositions entering) == [ first ] && List.map .unitId (TurnPlayback.movingPositions leaving) == [ first ])
        , expect "departures animate only to the visible square edge and fade without a hidden destination"
            (TurnPlayback.movingPositions departing
                == [ { unitId = second, position = { x = 2.25, y = 1 } } ]
                && TurnPlayback.unitOpacity departing second
                == 0.5
                && TurnPlayback.unitOpacity departing first
                == 1
                && List.map .id departingFrame.units
                == List.map .id firstFrame.units
            )
        , expect "shared playback carries surplus frame time forward"
            (Maybe.map .elapsed surplus == Just 90 && surplusFrame.visibleTiles == middleFrame.visibleTiles && TurnPlayback.movingPositions surplus == [ { unitId = second, position = { x = 1.5, y = 1 } } ])
        , expect "rotation rewinds facing and stays still until its event completes" (rotationPending /= Nothing && rotationHalfway == rotationUnits && Turn.movingPosition rotationPending == Nothing)
        , expect "ambush playback applies the chosen facing without moving" (rotationFinished == Nothing && List.map .direction rotatedUnits == [ Just Direction.West, Just Direction.West ] && List.map .location rotatedUnits == List.map .location units)
        , expect "rewind restores the event origins" (List.map Unit.mapPosition rewound == [ Just { x = 0, y = 0 }, Just { x = 2, y = 1 } ])
        , expect "halfway position interpolates the first unit only" (Turn.movingPosition halfway == Just { unitId = first, position = { x = 0.5, y = 0 } })
        , expect "animation never mutates authoritative cell positions mid-edge" (List.map Unit.mapPosition halfwayUnits == List.map Unit.mapPosition rewound)
        , expect "second event starts after the first finishes" (Turn.movingPosition next == Just { unitId = second, position = { x = 2, y = 1 } })
        , expect "rewind restores initial facing" (List.map .direction rewound == [ Just Direction.South, Just Direction.North ])
        , expect "moving unit turns while waiting unit keeps its facing" (List.map .direction halfwayUnits == [ Just Direction.East, Just Direction.North ])
        , expect "turning a corner faces down during the second edge" (List.map .direction cornerUnits == [ Just Direction.South, Just Direction.North ])
        , expect "final facing follows the last edge" (cornerFinished == Nothing && List.map .direction cornerFinalUnits == [ Just Direction.South, Just Direction.North ])
        , expect "all cardinal path directions are supported"
            (List.map (\destination -> Direction.between { x = 1, y = 1 } destination)
                [ { x = 1, y = 0 }, { x = 2, y = 1 }, { x = 1, y = 2 }, { x = 0, y = 1 } ]
                == [ Just Direction.North, Just Direction.East, Just Direction.South, Just Direction.West ]
            )
        , expect "holding preserves facing" (Direction.alongPath [ { x = 1, y = 1 } ] (Just Direction.North) == Just Direction.North)
        , expect "playback ends at the resolved board" (finished == Nothing && finalUnits == units)
        ]


movementAudioChecks : TurnPlayback.Frame -> TurnPlayback.Frame -> List String
movementAudioChecks before after =
    let
        vehicle : Int -> Unit -> Unit
        vehicle index unit =
            if index == 0 then
                Unit.setKind Kind.Truck unit

            else
                Unit.setKind Kind.Tank unit

        current : TurnPlayback.Frame
        current =
            before |> TurnPlayback.setFrameUnits (List.indexedMap vehicle before.units)

        next : TurnPlayback.Frame
        next =
            after |> TurnPlayback.setFrameUnits (List.indexedMap vehicle after.units)

        animation : TurnPlayback.Playback
        animation =
            { current = current
            , remaining = [ next ]
            , elapsed = 90
            , presentation = TurnPlayback.Battlefield
            , acknowledgedLosses = []
            }

        state : { playback : Maybe TurnPlayback.Playback, paused : Bool, camera : Maybe PlaybackPresentation.PlaybackCamera, skipLossDialogs : Bool }
        state =
            { playback = Just animation, paused = False, camera = Nothing, skipLossDialogs = False }

        vehicles : List Audio.MovingVehicle
        vehicles =
            PlaybackPresentation.movingVehicles state

        hidden : TurnPlayback.Playback
        hidden =
            animation |> setPlaybackCurrent (current |> TurnPlayback.setFrameUnits (List.take 1 current.units))

        leaving : TurnPlayback.Playback
        leaving =
            animation |> setPlaybackRemaining [ next |> TurnPlayback.setFrameUnits (List.take 1 next.units) ]

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ expect "simultaneous truck and tank movement requests separate typed voices" (List.map .vehicle vehicles == [ Audio.Truck, Audio.Tank ])
        , expect "movement voices retain unit identity" (List.map .unitId vehicles == List.map .id current.units)
        , expect "replay pause silences movement" (List.isEmpty (PlaybackPresentation.movingVehicles { state | paused = True }))
        , expect "camera pan silences movement" (List.isEmpty (PlaybackPresentation.movingVehicles { state | camera = Just { camera = { offset = { x = 0, y = 0 }, zoom = 1 }, remainingPanMs = 10 } }))
        , expect "finished playback silences movement" (List.isEmpty (PlaybackPresentation.movingVehicles { state | playback = Nothing }))
        , expect "stationary vehicles stay silent" (List.isEmpty (PlaybackPresentation.movingVehicles { state | playback = Just (animation |> setPlaybackRemaining [ current ]) }))
        , expect "units entering sight have no sound before their visible movement" (List.map .vehicle (PlaybackPresentation.movingVehicles { state | playback = Just hidden }) == [ Audio.Truck ])
        , expect "hidden destinations do not produce movement audio" (List.map .vehicle (PlaybackPresentation.movingVehicles { state | playback = Just leaving }) == [ Audio.Truck ])
        , expect "movement snapshots stop voices when playback ends" (Audio.syncMovement { before = vehicles, after = [] } == Audio.SyncMovement [])
        , expect "idle updates do not send movement snapshots" (Audio.syncMovement { before = [], after = [] } == Audio.none)
        ]


truckPlaybackChecks : UnitId -> List String
truckPlaybackChecks unitId =
    let
        units : List Unit
        units =
            [ { destroyed = False
              , combatState = Nothing
              , combatRules =
                    { range = 1
                    , indirectRange = 0
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , digInCost = 64
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = unitId
              , playerNumber = PlayerNumber.Player1
              , entrenchment = Entrenchment.Exposed
              , spriteFacing = SpriteFacing.Right
              , direction = Nothing
              , kind = Kind.Truck
              , location =
                    Location.OnMap
                        { x = 1
                        , y = 1
                        }
              , resources =
                    Just
                        { supplyCargo = []
                        , hitPoints =
                            { current = 16
                            , maximum = 16
                            }
                        , supplies =
                            { current = 64
                            , maximum = 64
                            , upkeepPerTurn = 1
                            , roughTerrainSurcharge = 0
                            , movementPerTile = 0
                            }
                        , fuel =
                            Just
                                { current = 15
                                , maximum = 64
                                , movementPerTile = 1
                                , movementPerCargoSlot = 0
                                }
                        }
              }
            ]

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , outcome = Nothing
            , resolution = Just { number = 1, report = Nothing, events = [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialSpriteFacing = SpriteFacing.Right, initialDirection = Nothing, unitId = unitId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ] } ] }
            }

        rewound : List Unit
        rewound =
            Turn.rewind snapshot units

        playback : Turn.Playback
        playback =
            Turn.start snapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( _, moving ) =
            Turn.tick 180 playback rewound

        ( finished, finalUnits ) =
            Turn.tick 360 playback rewound

        hasNoDirection : List Unit -> Bool
        hasNoDirection current =
            List.map .direction current == [ Nothing ]
    in
    if List.all hasNoDirection [ rewound, moving, finalUnits ] && finished == Nothing && finalUnits == units then
        []

    else
        [ "truck playback must move without acquiring a direction" ]


transportPlaybackChecks : UnitId -> UnitId -> List String
transportPlaybackChecks passengerId truckId =
    let
        truck : Unit
        truck =
            { id = truckId
            , playerNumber = PlayerNumber.Player1
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Right
            , kind = Kind.Truck
            , direction = Nothing
            , destroyed = False
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , cargoCapacity = 2
            , location =
                Location.OnMap
                    { x = 1
                    , y = 0
                    }
            , resources =
                Just
                    { supplyCargo = []
                    , hitPoints =
                        { current = 16
                        , maximum = 16
                        }
                    , supplies =
                        { current = 62
                        , maximum = 64
                        , upkeepPerTurn = 1
                        , roughTerrainSurcharge = 0
                        , movementPerTile = 0
                        }
                    , fuel =
                        Just
                            { current = 63
                            , maximum = 64
                            , movementPerTile = 1
                            , movementPerCargoSlot = 0
                            }
                    }
            }

        passenger : Unit
        passenger =
            truck
                |> Unit.setId passengerId
                |> Unit.setKind Kind.Infantry
                |> Unit.setDirection (Just Direction.East)
                |> Unit.setDestroyed False
                |> Unit.setCombatRules
                    { range = 1
                    , indirectRange = 0
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , digInCost = 64
                    , shotCost = 2
                    }
                |> Unit.setCargoCapacity 0
                |> Unit.setLocation (Location.Aboard truckId)
                |> Unit.setResources
                    (Maybe.map
                        (\resources ->
                            resources
                                |> UnitResources.setFuel
                                    Nothing
                        )
                        truck.resources
                    )

        units : List Unit
        units =
            [ passenger, truck ]

        event : Turn.Event
        event =
            { kind = EventKind.Move, unitId = truckId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ], initialSpriteFacing = SpriteFacing.Right, initialDirection = Nothing, rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing }

        loading : Turn.Snapshot
        loading =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , outcome = Nothing
            , resolution =
                Just
                    { number = 1
                    , report = Nothing
                    , events =
                        [ event
                            |> setEventUnitId passengerId
                            |> setEventKind EventKind.Hold
                            |> setEventPath
                                [ { x = 1, y = 0 } ]
                            |> setEventInitialSpriteFacing SpriteFacing.Right
                            |> setEventInitialDirection passenger.direction
                        , event
                        , { event | carrierId = Just truckId }
                            |> setEventUnitId passengerId
                            |> setEventKind EventKind.Load
                            |> setEventPath
                                [ { x = 1, y = 0 } ]
                            |> setEventInitialSpriteFacing SpriteFacing.Right
                            |> setEventInitialDirection passenger.direction
                        ]
                    }
            }

        rewound : List Unit
        rewound =
            Turn.rewind loading units

        afterMovement : List Unit
        afterMovement =
            Turn.start loading |> Maybe.map (\playback -> Turn.tick 180 playback rewound |> Tuple.second) |> Maybe.withDefault rewound

        afterLoading : List Unit
        afterLoading =
            Turn.start loading
                |> Maybe.andThen (\playback -> Turn.tick 180 playback rewound |> Tuple.first)
                |> Maybe.map (\playback -> Turn.tick 1 playback afterMovement |> Tuple.second)
                |> Maybe.withDefault afterMovement

        unloading : Turn.Snapshot
        unloading =
            { loading
                | resolution =
                    Just
                        { number = 1
                        , report = Nothing
                        , events =
                            [ { event | initialCarrier = Just truckId }
                                |> setEventKind EventKind.Unload
                                |> setEventUnitId passengerId
                                |> setEventPath
                                    [ { x = 1, y = 0 }, { x = 2, y = 0 } ]
                                |> setEventInitialSpriteFacing SpriteFacing.Right
                                |> setEventInitialDirection passenger.direction
                            ]
                        }
            }

        unloadUnits : List Unit
        unloadUnits =
            [ passenger
                |> Unit.setOnMap { x = 2, y = 0 }
            , truck
            ]

        unloadRewound : List Unit
        unloadRewound =
            Turn.rewind unloading unloadUnits

        afterUnloading : List Unit
        afterUnloading =
            Turn.start unloading |> Maybe.map (\playback -> Turn.tick 180 playback unloadRewound |> Tuple.second) |> Maybe.withDefault unloadRewound

        riding : List Unit
        riding =
            Turn.tick 180
                { events = [ event ], elapsed = 0 }
                [ passenger
                , truck
                    |> Unit.setOnMap { x = 0, y = 0 }
                ]
                |> Tuple.second

        ( sharedUnloading, sharedUnloadFrame ) =
            TurnPlayback.tick 90
                { current =
                    { depots = []
                    , supplyCrates = []
                    , departures = []
                    , sabotages = []
                    , indirectImpacts = []
                    , shots = []
                    , durationMs = 180
                    , units = units
                    , visibleTiles = []
                    }
                , remaining =
                    [ { depots = []
                      , supplyCrates = []
                      , departures = []
                      , sabotages = []
                      , indirectImpacts = []
                      , shots = []
                      , durationMs = 180
                      , units = unloadUnits
                      , visibleTiles = []
                      }
                    ]
                , acknowledgedLosses = []
                , presentation = TurnPlayback.Battlefield
                , elapsed = 0
                }
    in
    List.concat
        [ transportExpect "shared unloading displays the passenger walking from its truck"
            (TurnPlayback.movingPositions sharedUnloading == [ { unitId = passengerId, position = { x = 1.5, y = 0 } } ] && List.map Unit.mapPosition sharedUnloadFrame.units == [ Just { x = 1, y = 0 }, Just { x = 1, y = 0 } ])
        , transportExpect "loading rewind restores passengers to the board" (List.map Unit.carrierId rewound == [ Nothing, Nothing ])
        , transportExpect "load event attaches cargo after movement" (afterLoading == units)
        , transportExpect "riding passengers follow their truck" (riding == units)
        , transportExpect "unload rewind restores cargo" (unloadRewound == units)
        , transportExpect "unload event puts passenger on the board" (afterUnloading == unloadUnits)
        , transportExpect "passengers have no board position" (Unit.mapPosition passenger == Nothing)
        , transportExpect "riding position derives from the moved truck" (Unit.physicalPosition riding passenger == Just { x = 1, y = 0 })
        , transportExpect "missing carriers have no physical position" (Unit.physicalPosition [ passenger ] passenger == Nothing)
        , transportExpect "aboard carriers have no physical position"
            (Unit.physicalPosition
                [ passenger
                , truck
                    |> Unit.setLocation (Location.Aboard passengerId)
                ]
                passenger
                == Nothing
            )
        ]


transportExpect : String -> Bool -> List String
transportExpect name valid =
    if valid then
        []

    else
        [ name ]


spriteFacingChecks : UnitId -> List String
spriteFacingChecks id =
    let
        tank : Unit
        tank =
            { id = id
            , playerNumber = PlayerNumber.Player1
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Right
            , direction = Just Direction.East
            , kind = Kind.Tank
            , destroyed = False
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , cargoCapacity = 0
            , location =
                Location.OnMap
                    { x = 2
                    , y = 2
                    }
            , resources =
                Just
                    { supplyCargo = []
                    , hitPoints =
                        { current = 16
                        , maximum = 16
                        }
                    , supplies =
                        { current = 64
                        , maximum = 64
                        , upkeepPerTurn = 1
                        , roughTerrainSurcharge = 0
                        , movementPerTile = 0
                        }
                    , fuel =
                        Just
                            { current = 64
                            , maximum = 64
                            , movementPerTile = 2
                            , movementPerCargoSlot = 0
                            }
                    }
            }

        west : Unit
        west =
            Unit.faceDirection (Just Direction.West) tank |> Unit.setOnMap { x = 1, y = 2 }

        north : Unit
        north =
            Unit.faceDirection (Just Direction.North) west |> Unit.setOnMap { x = 1, y = 1 }

        south : Unit
        south =
            Unit.faceDirection (Just Direction.South) north |> Unit.setOnMap { x = 1, y = 2 }

        frame : Unit -> TurnPlayback.Frame
        frame unit =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = [ unit ]
            , visibleTiles = []
            }

        playback : TurnPlayback.Playback
        playback =
            { current = frame tank, remaining = [ frame west, frame north, frame south ], elapsed = 0, acknowledgedLosses = [], presentation = TurnPlayback.Battlefield }

        ( _, westFrame ) =
            TurnPlayback.tick 90 playback

        ( _, northFrame ) =
            TurnPlayback.tick 270 playback

        ( _, southFrame ) =
            TurnPlayback.tick 450 playback

        truck : Unit
        truck =
            tank
                |> Unit.setKind Kind.Truck
                |> Unit.setDirection Nothing

        westTruck : Unit
        westTruck =
            truck
                |> Unit.setSpriteFacing SpriteFacing.Left
                |> Unit.setOnMap { x = 1, y = 2 }

        northTruck : Unit
        northTruck =
            Unit.setOnMap { x = 1, y = 1 } westTruck

        southTruck : Unit
        southTruck =
            Unit.setOnMap { x = 1, y = 2 } northTruck

        eastTruck : Unit
        eastTruck =
            truck
                |> Unit.setOnMap { x = 2, y = 2 }

        truckPlayback : TurnPlayback.Playback
        truckPlayback =
            playback
                |> setPlaybackCurrent (frame truck)
                |> setPlaybackRemaining (List.map frame [ westTruck, northTruck, southTruck, eastTruck ])

        truckFrames : List TurnPlayback.Frame
        truckFrames =
            List.map (\elapsed -> TurnPlayback.tick elapsed truckPlayback |> Tuple.second) [ 90, 270, 450, 630 ]

        truckSnapshot : Turn.Snapshot
        truckSnapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , outcome = Nothing
            , resolution =
                Just
                    { number = 1
                    , report = Nothing
                    , events =
                        [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialSpriteFacing = SpriteFacing.Right, initialDirection = Nothing, unitId = id, path = [ { x = 2, y = 2 }, { x = 1, y = 2 }, { x = 1, y = 1 } ] } ]
                    }
            }

        truckEventPlayback : Turn.Playback
        truckEventPlayback =
            Turn.start truckSnapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        rewoundTruck : List Unit
        rewoundTruck =
            Turn.rewind truckSnapshot [ northTruck ]

        ( _, finishedTrucks ) =
            Turn.tick 360 truckEventPlayback rewoundTruck

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    expect "westward playback flips the sprite before arrival" (List.map .spriteFacing westFrame.units == [ SpriteFacing.Left ])
        ++ expect "northward playback retains left sprite facing" (List.map .spriteFacing northFrame.units == [ SpriteFacing.Left ] && List.map .direction northFrame.units == [ Just Direction.North ])
        ++ expect "southward playback retains left sprite facing" (List.map .spriteFacing southFrame.units == [ SpriteFacing.Left ] && List.map .direction southFrame.units == [ Just Direction.South ])
        ++ expect "east rotation then north keeps the right profile" ((west |> Unit.faceDirection (Just Direction.East) |> Unit.faceDirection (Just Direction.North)).spriteFacing == SpriteFacing.Right)
        ++ expect "truck playback follows west and east while retaining facing vertically" (List.concatMap (.units >> List.map .spriteFacing) truckFrames == [ SpriteFacing.Left, SpriteFacing.Left, SpriteFacing.Left, SpriteFacing.Right ])
        ++ expect "truck playback keeps combat direction absent" (List.concatMap (.units >> List.map .direction) truckFrames == [ Nothing, Nothing, Nothing, Nothing ])
        ++ expect "truck rewind restores its starting profile" (rewoundTruck == [ truck ])
        ++ expect "truck event playback retains west facing after northward travel" (finishedTrucks == [ northTruck ])


combatPlaybackChecks : UnitId -> UnitId -> List String
combatPlaybackChecks first second =
    let
        attacker : Unit
        attacker =
            { id = first
            , playerNumber = PlayerNumber.Player1
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Right
            , direction = Just Direction.East
            , kind = Kind.Tank
            , destroyed = False
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 8
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , cargoCapacity = 0
            , location = Location.OnMap { x = 2, y = 2 }
            , resources = Nothing
            }

        target : Unit
        target =
            attacker
                |> Unit.setId second
                |> Unit.setPlayerNumber PlayerNumber.Player2
                |> Unit.setOnMap { x = 3, y = 2 }

        before : TurnPlayback.Frame
        before =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = [ attacker, target ]
            , visibleTiles =
                [ { x = 2
                  , y = 2
                  }
                , { x = 3
                  , y = 2
                  }
                ]
            }

        shot : Shot
        shot =
            { kind = CombatKind.Ambush
            , origin = { x = 2, y = 2 }
            , destination = { x = 3, y = 2 }
            , attacker = attacker
            , target = target
            , damage = 8
            , attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
            , targetHealth = { before = { current = 16, maximum = 16 }, after = { current = 8, maximum = 16 } }
            }

        volley : TurnPlayback.Frame
        volley =
            before
                |> setFrameDurationMs 450
                |> TurnPlayback.setFrameShots
                    [ shot
                    , shot
                        |> setShotOrigin shot.destination
                        |> setShotDestination shot.origin
                        |> setShotAttacker target
                        |> setShotTarget attacker
                    ]
                |> TurnPlayback.setFrameUnits
                    [ attacker
                        |> Unit.setDestroyed True
                    , target
                        |> Unit.setDestroyed True
                    ]

        cleanup : TurnPlayback.Frame
        cleanup =
            before
                |> setFrameDurationMs 1400
                |> TurnPlayback.setFrameUnits []

        panelAt : { x : Int, y : Int } -> { x : Int, y : Int } -> TurnPlayback.Panel
        panelAt origin destination =
            { encounter =
                TurnPlayback.Exchange
                    { kind = shot.kind
                    , attacker =
                        attacker
                            |> Unit.setOnMap origin
                    , target =
                        target
                            |> Unit.setOnMap destination
                    , attackerHealth = shot.attackerHealth
                    , targetHealth = shot.targetHealth
                    , targetFired = False
                    }
            , elapsed = 0
            , mapView = TurnPlayback.CardVisible
            }

        concealedSpotlights : TurnPlayback.Playback -> { spotlight : Maybe (List Coordinate), mapPeek : Maybe (List Coordinate) }
        concealedSpotlights playing =
            { spotlight = TurnPlayback.spotlight playing
            , mapPeek =
                playing
                    |> TurnPlayback.tick 300
                    |> Tuple.first
                    |> Maybe.map (TurnPlayback.setMapView TurnPlayback.SeeingMap)
                    |> Maybe.andThen TurnPlayback.spotlight
            }

        readyAt : Kind.UnitKind -> Float -> TurnPlayback.MapView -> Int -> Bool
        readyAt kind elapsed mapView remainingHealth =
            let
                panel : TurnPlayback.Panel
                panel =
                    panelAt shot.origin shot.destination

                exchange : TurnPlayback.CombatExchange
                exchange =
                    { kind = shot.kind
                    , attacker = attacker
                    , target = target
                    , attackerHealth = shot.attackerHealth
                    , targetHealth = shot.targetHealth
                    , targetFired = False
                    }
            in
            CombatTheater.readyToAutomaticallyClose
                ({ panel | mapView = mapView }
                    |> setPanelElapsed elapsed
                    |> setPanelEncounter
                        (TurnPlayback.Exchange
                            { exchange
                                | target =
                                    target
                                        |> Unit.setKind kind
                                , targetHealth =
                                    { before = { current = 16, maximum = 16 }
                                    , after = { current = remainingHealth, maximum = 16 }
                                    }
                            }
                        )
                )

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]

        impactChecks : List String
        impactChecks =
            let
                landing : TurnPlayback.Frame
                landing =
                    before
                        |> TurnPlayback.setFrameUnits
                            [ attacker ]
                        |> setFrameSabotages []
                        |> setFrameIndirectImpacts
                            [ { destination = shot.destination, attacker = Nothing, target = Nothing, depot = Nothing }, { destination = shot.destination, attacker = Nothing, target = Nothing, depot = Nothing } ]

                focus : Maybe TurnPlayback.Playback
                focus =
                    TurnPlayback.start [ before, landing ] |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)

                shown : Maybe TurnPlayback.Playback
                shown =
                    focus |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                continued : Maybe TurnPlayback.Playback
                continued =
                    shown |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map .animation

                confirmed : TurnPlayback.Frame
                confirmed =
                    landing
                        |> TurnPlayback.setFrameShots
                            [ shot
                                |> setShotKind CombatKind.IndirectFire
                            ]

                hit : Maybe TurnPlayback.Playback
                hit =
                    TurnPlayback.start [ before, confirmed ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                afterHit : Maybe TurnPlayback.Playback
                afterHit =
                    hit |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map .animation

                knownImpact : IndirectImpact
                knownImpact =
                    { destination = shot.destination
                    , attacker = Just { unit = attacker, health = shot.attackerHealth.before }
                    , target = Nothing
                    , depot = Nothing
                    }

                knownLanding : TurnPlayback.Frame
                knownLanding =
                    landing
                        |> setFrameIndirectImpacts
                            [ knownImpact ]

                knownShown : Maybe TurnPlayback.Playback
                knownShown =
                    TurnPlayback.start [ before, knownLanding ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                knownPanel : TurnPlayback.Panel
                knownPanel =
                    { encounter = impactEncounter knownImpact
                    , elapsed = 0
                    , mapView = TurnPlayback.CardVisible
                    }

                fieldGunPanel : TurnPlayback.Panel
                fieldGunPanel =
                    knownPanel
                        |> setPanelEncounter
                            (impactEncounter
                                (knownImpact
                                    |> setImpactAttacker (Just { unit = Unit.setKind Kind.FieldGun attacker, health = shot.attackerHealth.before })
                                )
                            )

                observedTarget : IndirectImpact
                observedTarget =
                    { depot = Nothing
                    , destination = shot.destination
                    , attacker = Nothing
                    , target =
                        Just
                            { unit =
                                target
                                    |> Unit.setKind Kind.Infantry
                            , health = shot.targetHealth
                            }
                    }

                showTarget : List IndirectImpact -> Bool -> Maybe TurnPlayback.Playback
                showTarget impacts destroyed =
                    TurnPlayback.start
                        [ before
                            |> TurnPlayback.setFrameUnits
                                [ target ]
                        , landing
                            |> TurnPlayback.setFrameUnits
                                [ target
                                    |> Unit.setDestroyed destroyed
                                ]
                            |> setFrameSabotages []
                            |> setFrameIndirectImpacts impacts
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                targetShown : Maybe TurnPlayback.Playback
                targetShown =
                    showTarget [ observedTarget ] False

                laterImpact : IndirectImpact
                laterImpact =
                    { observedTarget | target = Maybe.map (\known -> { known | health = { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } } }) observedTarget.target }

                combined : Maybe TurnPlayback.Panel
                combined =
                    showTarget [ observedTarget, laterImpact ] True |> Maybe.andThen TurnPlayback.panels

                depotHit : IndirectImpact
                depotHit =
                    { observedTarget
                        | depot =
                            Just
                                { kind = BuildingKind.Supply
                                , before =
                                    { current = 3
                                    , maximum = 3
                                    }
                                , after =
                                    { current = 2
                                    , maximum = 3
                                    }
                                }
                    }

                depotLanding : TurnPlayback.Frame
                depotLanding =
                    { confirmed | indirectImpacts = [ depotHit ] }

                depotPanel : Maybe TurnPlayback.Panel
                depotPanel =
                    TurnPlayback.start [ before, depotLanding ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.panels

                depotReady : Float -> TurnPlayback.MapView -> Bool
                depotReady elapsed mapView =
                    CombatTheater.readyToAutomaticallyClose
                        { encounter = impactEncounter depotHit
                        , elapsed = elapsed
                        , mapView = mapView
                        }

                lethalDepotHit : IndirectImpact
                lethalDepotHit =
                    { depotHit
                        | target =
                            laterImpact.target
                                |> Maybe.map (\observed -> { observed | health = { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } } })
                        , depot =
                            Just
                                { kind = BuildingKind.Fuel
                                , before =
                                    { current = 1
                                    , maximum = 1
                                    }
                                , after =
                                    { current = 0
                                    , maximum = 1
                                    }
                                }
                    }

                lethalDepotShown : Maybe TurnPlayback.Playback
                lethalDepotShown =
                    showTarget [ lethalDepotHit ] True

                depotHeld : Maybe TurnPlayback.Playback
                depotHeld =
                    lethalDepotShown |> Maybe.andThen (TurnPlayback.tick 6000 >> Tuple.first)

                showsDepotAndUnit : TurnPlayback.Panel -> Bool
                showsDepotAndUnit panel =
                    case panel.encounter of
                        TurnPlayback.Impact impact ->
                            impact.depot == depotHit.depot && impact.target == observedTarget.target

                        _ ->
                            False

                targetHealth : TurnPlayback.Panel -> Maybe CombatHealth
                targetHealth panel =
                    case panel.encounter of
                        TurnPlayback.Impact impact ->
                            Maybe.map .health impact.target

                        _ ->
                            Nothing

                ready : Float -> Bool
                ready elapsed =
                    CombatTheater.readyToAutomaticallyClose
                        { encounter = impactEncounter { destination = shot.destination, attacker = Nothing, target = Nothing, depot = Nothing }
                        , elapsed = elapsed
                        , mapView = TurnPlayback.CardVisible
                        }
            in
            expect "a shell hitting a depot and its occupant retains both damage results in one encounter"
                (Maybe.map showsDepotAndUnit depotPanel == Just True)
                ++ expect "depot damage finishes after the occupant animation and before automatic close"
                    (not (depotReady 3469 TurnPlayback.CardVisible)
                        && depotReady 3470 TurnPlayback.CardVisible
                        && not (depotReady 6000 TurnPlayback.SeeingMap)
                    )
                ++ expect "lethal infantry and depot strikes both fit within the panel clock"
                    (Maybe.andThen TurnPlayback.panels depotHeld
                        |> Maybe.map CombatTheater.readyToAutomaticallyClose
                        |> (==) (Just True)
                    )
                ++ expect "automatic close waits for the depot even after all infantry casualties finish"
                    (Maybe.andThen TurnPlayback.panels lethalDepotShown
                        |> Maybe.map
                            (\panel ->
                                not
                                    (CombatTheater.readyToAutomaticallyClose
                                        (panel
                                            |> setPanelElapsed 3949
                                        )
                                    )
                                    && CombatTheater.readyToAutomaticallyClose
                                        (panel
                                            |> setPanelElapsed 3950
                                        )
                            )
                        |> (==) (Just True)
                    )
                ++ expect "continuing after a depot strike preserves the occupant casualty acknowledgment"
                    (depotHeld
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map (.animation >> TurnPlayback.losses >> List.map .cause)
                        |> (==) (Just [ TurnPlayback.ConcealedIndirectFire ])
                    )
                ++ expect "known indirect attacker is retained alongside an unconfirmed landing"
                    (Maybe.andThen TurnPlayback.activeEncounter knownShown
                        == Just (impactEncounter knownImpact)
                        && Maybe.map TurnPlayback.focusPositions knownShown
                        == Just [ { x = 2, y = 2 }, { x = 3, y = 2 } ]
                        && CombatTheater.attackerOnLeft knownPanel
                        && not
                            (CombatTheater.attackerOnLeft
                                (knownPanel
                                    |> setPanelEncounter (impactEncounter { knownImpact | destination = { x = 1, y = 2 } })
                                )
                            )
                    )
                ++ expect "unconfirmed indirect impacts open a theater without invented combatants"
                    (Maybe.andThen TurnPlayback.activeEncounter shown
                        == Just (impactEncounter { destination = shot.destination, attacker = Nothing, target = Nothing, depot = Nothing })
                        && Maybe.andThen TurnPlayback.combat shown
                        == Nothing
                        && Maybe.andThen TurnPlayback.panels shown
                        /= Nothing
                    )
                ++ expect "a concealed gun retains the observed target and authoritative damage"
                    (Maybe.andThen TurnPlayback.activeEncounter targetShown
                        == Just (impactEncounter observedTarget)
                        && Maybe.map TurnPlayback.focusPositions targetShown
                        == Just [ { x = 3, y = 2 } ]
                    )
                ++ expect "observed targets animate their whole health change across duplicate landings"
                    (Maybe.andThen targetHealth combined == Just { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } })
                ++ expect "observed infantry impacts retain the full casualty animation before automatic close"
                    (Maybe.map
                        (\panel ->
                            not
                                (CombatTheater.readyToAutomaticallyClose
                                    (panel
                                        |> setPanelElapsed 2719
                                    )
                                )
                                && CombatTheater.readyToAutomaticallyClose
                                    (panel
                                        |> setPanelElapsed 2720
                                    )
                        )
                        combined
                        == Just True
                    )
                ++ expect "combined concealed gun impacts retain the casualty ID without an attacker"
                    (showTarget [ observedTarget, laterImpact ] True
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map (.animation >> TurnPlayback.losses >> List.map .cause)
                        |> (==) (Just [ TurnPlayback.ConcealedIndirectFire ])
                    )
                ++ expect "impact spotlight and camera frame only the landing"
                    (Maybe.andThen TurnPlayback.spotlight focus
                        == Just [ shot.destination ]
                        && Maybe.map TurnPlayback.focusPositions shown
                        == Just [ { x = 3, y = 2 } ]
                    )
                ++ expect "duplicate impacts on one tile open only one theater"
                    (Maybe.andThen TurnPlayback.activeEncounter continued == Nothing)
                ++ expect "confirmed indirect hits retain their kind and do not open duplicate impact theaters"
                    (Maybe.andThen TurnPlayback.combat hit |> Maybe.map .kind |> (==) (Just CombatKind.IndirectFire))
                ++ expect "confirmed impact theater closes after its exchange"
                    (Maybe.andThen TurnPlayback.activeEncounter afterHit == Nothing)
                ++ expect "impact theaters wait for explosions and the automatic-close delay"
                    (not (ready 2200) && ready 2270)
                ++ expect "visible indirect guns share muzzle-flash sound timing while concealed guns stay silent"
                    (CombatTheater.firingTimes Kind.FieldGun fieldGunPanel
                        == [ 1520, 1610, 1700, 1790 ]
                        && List.isEmpty
                            (CombatTheater.firingTimes Kind.FieldGun
                                (fieldGunPanel
                                    |> setPanelEncounter
                                        (impactEncounter
                                            (knownImpact
                                                |> setImpactAttacker Nothing
                                            )
                                        )
                                )
                            )
                    )
                ++ expect "observable indirect guns finish their firing sequence before impacts and automatic close"
                    (CombatTheater.attackDelay fieldGunPanel
                        == 1210
                        && not
                            (CombatTheater.readyToAutomaticallyClose
                                (fieldGunPanel
                                    |> setPanelElapsed 3479
                                )
                            )
                        && CombatTheater.readyToAutomaticallyClose
                            (fieldGunPanel
                                |> setPanelElapsed 3480
                            )
                    )
                ++ mergedImpactChecks { gun = attacker, target = target, before = before }

        returnFireChecks : List String
        returnFireChecks =
            let
                opening : TurnPlayback.Frame
                opening =
                    before
                        |> setFrameDurationMs 450
                        |> TurnPlayback.setFrameShots
                            [ shot ]

                waiting : TurnPlayback.Frame
                waiting =
                    before
                        |> setFrameDurationMs 600

                returnShot : Shot
                returnShot =
                    shot
                        |> setShotKind CombatKind.AttackMove
                        |> setShotOrigin shot.destination
                        |> setShotDestination shot.origin
                        |> setShotAttacker target
                        |> setShotTarget attacker
                        |> setShotDamage 1
                        |> Shot.setAttackerHealth
                            { before = { current = 8, maximum = 16 }, after = { current = 8, maximum = 16 } }
                        |> Shot.setTargetHealth
                            { before = { current = 16, maximum = 16 }, after = { current = 15, maximum = 16 } }

                returning : TurnPlayback.Frame
                returning =
                    before
                        |> setFrameDurationMs 450
                        |> TurnPlayback.setFrameShots
                            [ returnShot ]

                focused : List TurnPlayback.Frame -> Maybe TurnPlayback.Playback
                focused frames =
                    TurnPlayback.start frames |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                combined : Maybe TurnPlayback.Playback
                combined =
                    focused
                        [ before
                        , opening
                        , waiting
                        , waiting
                            |> setFrameDurationMs 180
                        , returning
                        , waiting
                        ]

                exchange : Maybe TurnPlayback.CombatExchange
                exchange =
                    Maybe.andThen TurnPlayback.combat combined

                resumed : Maybe TurnPlayback.Playback
                resumed =
                    combined
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map .animation

                separate : TurnPlayback.Frame -> Bool
                separate boundary =
                    focused [ before, opening, boundary, returning, waiting ]
                        |> Maybe.andThen TurnPlayback.combat
                        |> Maybe.map (.attackerHealth >> .after >> .current)
                        |> (==) (Just 16)

                delayForShots : List Shot -> Maybe Float
                delayForShots shots =
                    let
                        panelDelay : TurnPlayback.CombatExchange -> Float
                        panelDelay pair =
                            CombatTheater.attackDelay
                                { encounter = TurnPlayback.Exchange pair
                                , elapsed = 0
                                , mapView = TurnPlayback.CardVisible
                                }
                    in
                    focused
                        [ before
                        , opening
                            |> TurnPlayback.setFrameShots shots
                        , waiting
                        ]
                        |> Maybe.andThen TurnPlayback.combat
                        |> Maybe.map panelDelay

                zeroDamage : Shot -> Shot
                zeroDamage fired =
                    { fired
                        | damage = 0
                        , attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                        , targetHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                    }
            in
            expect "stationary return fire shares one card with both health transitions"
                (Maybe.map (.attackerHealth >> .after >> .current) exchange
                    == Just 15
                    && Maybe.map (.targetHealth >> .before >> .current) exchange
                    == Just 16
                    && Maybe.map (.targetHealth >> .after >> .current) exchange
                    == Just 8
                    && Maybe.map .kind exchange
                    == Just CombatKind.AttackMove
                )
                ++ expect "recorded return fire is retained independently of damage"
                    (Maybe.map .targetFired exchange
                        == Just True
                        && delayForShots [ zeroDamage shot, zeroDamage returnShot ]
                        == Just 1035
                    )
                ++ expect "defending tanks do not fire merely because they appear in a theater"
                    (delayForShots
                        [ shot
                            |> setShotAttacker (Unit.setKind Kind.Infantry attacker)
                        ]
                        == Just 0
                        && delayForShots [ shot ]
                        == Just 990
                    )
                ++ expect "fewer firing tanks shorten the firing phase using before-health"
                    (delayForShots
                        [ shot
                            |> Shot.setAttackerHealth
                                { before = { current = 1, maximum = 16 }, after = { current = 0, maximum = 16 } }
                        ]
                        == Just 720
                    )
                ++ expect "returning tanks delay incoming hits even when the primary attacker is infantry"
                    (delayForShots
                        [ shot
                            |> setShotAttacker (Unit.setKind Kind.Infantry attacker)
                        , returnShot
                        ]
                        == Just 1035
                    )
                ++ expect "firing field guns delay both formations' impacts, including zero-damage shots"
                    (delayForShots
                        [ zeroDamage
                            (shot
                                |> setShotAttacker (Unit.setKind Kind.FieldGun attacker)
                            )
                        ]
                        == Just 1210
                    )
                ++ expect "receiving fire does not start a field-gun animation"
                    (delayForShots
                        [ shot
                            |> setShotAttacker (Unit.setKind Kind.Infantry attacker)
                            |> setShotTarget (Unit.setKind Kind.FieldGun target)
                        ]
                        == Just 0
                    )
                ++ expect "recorded field-gun return fire shares the stagger and recovery delay"
                    (delayForShots
                        [ shot
                            |> setShotAttacker (Unit.setKind Kind.Infantry attacker)
                            |> setShotTarget (Unit.setKind Kind.FieldGun target)
                        , returnShot
                            |> setShotAttacker (Unit.setKind Kind.FieldGun target)
                            |> setShotTarget (Unit.setKind Kind.Infantry attacker)
                        ]
                        == Just 1255
                    )
                ++ expect "continuing a combined exchange does not open another theater"
                    (Maybe.andThen TurnPlayback.combat resumed
                        == Nothing
                        && (resumed |> Maybe.andThen (TurnPlayback.tick 2000 >> Tuple.first))
                        == Nothing
                    )
                ++ expect "both players of a combined exchange begin their impacts together"
                    (Maybe.map (\pair -> List.head (CombatFormation.impactStarts pair.attacker.kind pair.attackerHealth) == Just 1200 && List.head (CombatFormation.impactStarts pair.target.kind pair.targetHealth) == Just 1200) exchange == Just True)
                ++ expect "movement between shots keeps separate encounters"
                    (separate
                        (waiting
                            |> TurnPlayback.setFrameUnits
                                [ attacker, Unit.setOnMap { x = 4, y = 2 } target ]
                        )
                    )
                ++ expect "sight changes between shots keep separate encounters"
                    (separate { waiting | visibleTiles = [] })
                ++ expect "intervening casualties keep separate encounters"
                    (separate
                        (waiting
                            |> TurnPlayback.setFrameUnits
                                [ attacker
                                    |> Unit.setDestroyed True
                                , target
                                ]
                        )
                    )
                ++ expect "another volley between shots keeps separate encounters"
                    (separate opening)
                ++ crowdedReturnFireChecks
                    { before = before, opening = shot, returning = returnShot }
    in
    case TurnPlayback.start [ before, volley, cleanup ] of
        Nothing ->
            [ "combat fixture did not start playback" ]

        Just animation ->
            let
                ( paused, frozen ) =
                    TurnPlayback.tick 5000 animation
            in
            case paused of
                Nothing ->
                    [ "a long tick skipped combat focus" ]

                Just focus ->
                    let
                        ( almostSpotlit, _ ) =
                            TurnPlayback.tick 299 focus

                        ( showing, _ ) =
                            TurnPlayback.tick 300 focus

                        atPanelTime : Float -> Maybe TurnPlayback.Playback
                        atPanelTime elapsed =
                            showing |> Maybe.andThen (TurnPlayback.tick elapsed >> Tuple.first)

                        soundsBetween : Float -> Float -> List Audio.Event
                        soundsBetween earlier later =
                            PlaybackPresentation.audioBetween { before = atPanelTime earlier, after = atPanelTime later }

                        fieldGunSounds : Float -> Float -> List Audio.Event
                        fieldGunSounds earlier later =
                            let
                                withFieldGun : TurnPlayback.Playback -> TurnPlayback.Playback
                                withFieldGun playback =
                                    case playback.presentation of
                                        TurnPlayback.Combat combatFocus ->
                                            case combatFocus.encounter of
                                                TurnPlayback.Exchange pair ->
                                                    { playback
                                                        | presentation =
                                                            TurnPlayback.Combat
                                                                { combatFocus
                                                                    | encounter = TurnPlayback.Exchange { pair | attacker = Unit.setKind Kind.FieldGun pair.attacker }
                                                                }
                                                    }

                                                _ ->
                                                    playback

                                        _ ->
                                            playback

                                gunPlayback : Float -> Maybe TurnPlayback.Playback
                                gunPlayback elapsed =
                                    atPanelTime elapsed |> Maybe.map withFieldGun
                            in
                            PlaybackPresentation.audioBetween { before = gunPlayback earlier, after = gunPlayback later }

                        audioChecks : List String
                        audioChecks =
                            expect "muzzle sounds fire at clock crossings, including exact boundaries"
                                (List.isEmpty (soundsBetween 0 1199)
                                    && soundsBetween 1199 1200
                                    == [ Audio.tankFire ]
                                    && List.isEmpty (soundsBetween 1200 1244)
                                    && soundsBetween 1244 1245
                                    == [ Audio.tankFire ]
                                )
                                ++ expect "mixed weapon cues follow muzzle order and field-gun preparation"
                                    (fieldGunSounds 1199 1520
                                        == List.repeat 4 Audio.tankFire
                                        ++ [ Audio.fieldGunFire ]
                                        && fieldGunSounds 1520 1790
                                        == List.repeat 3 Audio.fieldGunFire
                                        && List.isEmpty (fieldGunSounds 1790 6000)
                                    )
                                ++ expect "a delayed tick emits every staggered shot exactly once"
                                    (List.length (soundsBetween 1199 1515)
                                        == 8
                                        && List.isEmpty (soundsBetween 1515 6000)
                                    )
                                ++ expect "paused, held, rewound, and absent theaters never replay old firing cues"
                                    (List.isEmpty (soundsBetween 1300 1300)
                                        && List.isEmpty (soundsBetween 1515 0)
                                        && List.isEmpty (PlaybackPresentation.audioBetween { before = Nothing, after = atPanelTime 1500 })
                                        && List.isEmpty (PlaybackPresentation.audioBetween { before = atPanelTime 1500, after = Nothing })
                                    )

                        ( holding, heldFrame ) =
                            showing |> Maybe.map (TurnPlayback.tick 60000) |> Maybe.withDefault ( Nothing, before )

                        ( resumed, hitFrame ) =
                            showing |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map (\next -> ( Just next.animation, next.frame )) |> Maybe.withDefault ( Nothing, before )

                        ( finished, finalFrame ) =
                            resumed |> Maybe.map (TurnPlayback.tick 1400) |> Maybe.withDefault ( Nothing, before )

                        hidden : TurnPlayback.Frame
                        hidden =
                            volley
                                |> TurnPlayback.setFrameUnits
                                    [ target ]
                                |> TurnPlayback.setFrameShots
                                    [ shot ]

                        hiddenPlayback : Maybe TurnPlayback.Playback
                        hiddenPlayback =
                            TurnPlayback.start [ before, hidden, cleanup ] |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                        ( finalShot, _ ) =
                            TurnPlayback.start [ before, volley ] |> Maybe.map (TurnPlayback.tick 450) |> Maybe.withDefault ( Nothing, before )

                        framesCombatKind : CombatKind.CombatKind -> Bool
                        framesCombatKind kind =
                            TurnPlayback.start
                                [ before
                                , volley
                                    |> TurnPlayback.setFrameShots
                                        [ shot
                                            |> setShotKind kind
                                        ]
                                , cleanup
                                ]
                                |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                                |> Maybe.map TurnPlayback.focusPositions
                                |> (==) (Just [ { x = 2, y = 2 }, { x = 3, y = 2 } ])

                        multipleChecks : List String
                        multipleChecks =
                            case UnitId.parse "3" of
                                Err _ ->
                                    [ "could not construct third combat participant" ]

                                Ok third ->
                                    let
                                        anotherTarget : Unit
                                        anotherTarget =
                                            target
                                                |> Unit.setId third
                                                |> Unit.setOnMap { x = 4, y = 2 }

                                        multiple : TurnPlayback.Frame
                                        multiple =
                                            volley
                                                |> TurnPlayback.setFrameUnits (volley.units ++ [ anotherTarget ])
                                                |> TurnPlayback.setFrameShots
                                                    (volley.shots
                                                        ++ [ shot
                                                                |> setShotDestination
                                                                    { x = 4, y = 2 }
                                                                |> setShotTarget anotherTarget
                                                           ]
                                                    )

                                        firstPause : Maybe TurnPlayback.Playback
                                        firstPause =
                                            TurnPlayback.start [ before, multiple, cleanup ] |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                                        secondPause : Maybe TurnPlayback.Playback
                                        secondPause =
                                            firstPause |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first) |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map .animation

                                        overlap : TurnPlayback.Frame
                                        overlap =
                                            volley
                                                |> TurnPlayback.setFrameShots
                                                    [ shot
                                                    , shot
                                                        |> setShotOrigin
                                                            { x = 4, y = 2 }
                                                        |> setShotAttacker anotherTarget
                                                        |> Shot.setTargetHealth
                                                            { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } }
                                                    ]

                                        overlapFirst : Maybe TurnPlayback.Playback
                                        overlapFirst =
                                            TurnPlayback.start [ before, overlap, cleanup ] |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                                        overlapSecond : Maybe TurnPlayback.Playback
                                        overlapSecond =
                                            overlapFirst |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first) |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map .animation

                                        ( afterPairs, revealed ) =
                                            secondPause |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first) |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map (\next -> ( Just next.animation, next.frame )) |> Maybe.withDefault ( Nothing, before )
                                    in
                                    expect "each distinct combat pair is shown before a shared volley is revealed"
                                        (Maybe.andThen TurnPlayback.combat secondPause |> Maybe.map (.target >> .id) |> (==) (Just third))
                                        ++ expect "overlapping ambush cards preserve successive health losses"
                                            ((Maybe.andThen TurnPlayback.combat overlapFirst |> Maybe.map (.targetHealth >> .after >> .current))
                                                == Just 8
                                                && (Maybe.andThen TurnPlayback.combat overlapSecond |> Maybe.map (.targetHealth >> .before >> .current))
                                                == Just 8
                                                && (Maybe.andThen TurnPlayback.combat overlapSecond |> Maybe.map (.targetHealth >> .after >> .current))
                                                == Just 0
                                            )
                                        ++ expect "multiple pair displays return to one battlefield volley"
                                            (Maybe.andThen TurnPlayback.combat afterPairs == Nothing && revealed == multiple)
                    in
                    audioChecks
                        ++ List.concat
                            [ expect "theater sides preserve horizontal map order and use north first for vertical pairs"
                                (CombatTheater.attackerOnLeft (panelAt { x = 2, y = 2 } { x = 3, y = 2 })
                                    && not (CombatTheater.attackerOnLeft (panelAt { x = 3, y = 2 } { x = 2, y = 2 }))
                                    && CombatTheater.attackerOnLeft (panelAt { x = 2, y = 2 } { x = 2, y = 3 })
                                    && not (CombatTheater.attackerOnLeft (panelAt { x = 2, y = 3 } { x = 2, y = 2 }))
                                )
                            , returnFireChecks
                            , impactChecks
                            , expect "combat holds the pre-hit board and hides shots and movement"
                                (frozen == before && List.isEmpty (TurnPlayback.visibleShots focus) && List.isEmpty (TurnPlayback.movingPositions paused))
                            , expect "combat spotlights participants before opening the panels"
                                (Maybe.andThen TurnPlayback.spotlight almostSpotlit /= Nothing && Maybe.andThen TurnPlayback.panels almostSpotlit == Nothing && Maybe.andThen TurnPlayback.spotlight showing == Nothing && Maybe.andThen TurnPlayback.panels showing /= Nothing)
                            , expect "camera frames combat during both spotlight and theater"
                                (TurnPlayback.focusPositions focus == [ { x = 2, y = 2 }, { x = 3, y = 2 } ] && Maybe.map TurnPlayback.focusPositions showing == Just (TurnPlayback.focusPositions focus))
                            , expect "spotlight and map peek never highlight a concealed theater portrait"
                                (TurnPlayback.start
                                    [ before
                                        |> TurnPlayback.setFrameUnits
                                            [ target ]
                                    , hidden
                                    , cleanup
                                    ]
                                    |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                                    |> Maybe.map concealedSpotlights
                                    |> (==) (Just { spotlight = Just [ { x = 3, y = 2 } ], mapPeek = Just [ { x = 3, y = 2 } ] })
                                )
                            , expect "camera never frames a concealed theater portrait"
                                (TurnPlayback.start
                                    [ before
                                        |> TurnPlayback.setFrameUnits
                                            [ target ]
                                    , hidden
                                    , cleanup
                                    ]
                                    |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                                    |> Maybe.map TurnPlayback.focusPositions
                                    |> (==) (Just [ { x = 3, y = 2 } ])
                                )
                            , expect "camera frames every combat kind"
                                (List.all framesCombatKind
                                    [ CombatKind.Ambush, CombatKind.AttackMove, CombatKind.IndirectFire ]
                                )
                            , expect "combat retains visible participants without requiring enemy resources"
                                (Maybe.map (.attacker >> .id) (TurnPlayback.combat focus) == Just first && Maybe.map (.target >> .id) (TurnPlayback.combat focus) == Just second)
                            , expect "automatic closing waits for two impacts, camera settling, and a half-second pause"
                                (not (readyAt Kind.Tank 2989 TurnPlayback.CardVisible 8) && readyAt Kind.Tank 2990 TurnPlayback.CardVisible 8)
                            , expect "automatic closing lets all four casualty animations finish"
                                (not (readyAt Kind.Tank 3229 TurnPlayback.CardVisible 0) && readyAt Kind.Tank 3230 TurnPlayback.CardVisible 0)
                            , expect "automatic closing waits for all eight infantry casualties and their shake"
                                (not (readyAt Kind.Infantry 3709 TurnPlayback.CardVisible 0)
                                    && readyAt Kind.Infantry 3710 TurnPlayback.CardVisible 0
                                )
                            , expect "automatic closing waits while seeing the map"
                                (not (readyAt Kind.Tank 2500 TurnPlayback.SeeingMap 0))
                            , expect "the panel clock can reach the automatic-close threshold"
                                (Maybe.andThen TurnPlayback.panels holding |> Maybe.map CombatTheater.readyToAutomaticallyClose |> (==) (Just True))
                            , expect "combat panels remain open indefinitely without revealing casualties"
                                (heldFrame == before && Maybe.map .encounter (Maybe.andThen TurnPlayback.panels holding) == Maybe.map .encounter (Maybe.andThen TurnPlayback.panels showing))
                            , expect "map peek only belongs to an open combat card and clears on continuation"
                                (TurnPlayback.setMapView TurnPlayback.SeeingMap focus
                                    == focus
                                    && (showing |> Maybe.map (TurnPlayback.setMapView TurnPlayback.SeeingMap) |> Maybe.andThen TurnPlayback.panels |> Maybe.map .mapView)
                                    == Just TurnPlayback.SeeingMap
                                    && Maybe.andThen TurnPlayback.panels resumed
                                    == Nothing
                                )
                            , expect "reciprocal shots share one pause and reveal both casualties together"
                                (Maybe.andThen TurnPlayback.combat resumed == Nothing && hitFrame == volley && Maybe.map TurnPlayback.visibleShots resumed == Just volley.shots)
                            , expect "continue only advances open panels, never spotlight or ordinary playback"
                                (TurnPlayback.continueCombat animation == Nothing && TurnPlayback.continueCombat focus == Nothing && Maybe.andThen TurnPlayback.continueCombat resumed == Nothing)
                            , expect "combat resumes exactly once and retains battlefield feedback duration"
                                (Maybe.map .elapsed resumed == Just 0 && finished == Nothing && finalFrame == cleanup)
                            , expect "a concealed attacker still opens the theater without appearing on the battlefield"
                                ((Maybe.andThen TurnPlayback.combat hiddenPlayback |> Maybe.map (.attacker >> .id))
                                    == Just first
                                    && (Maybe.map (.current >> .units) hiddenPlayback == Just [ target ])
                                )
                            , expect "a volley in the final frame still receives combat focus"
                                (Maybe.andThen TurnPlayback.combat finalShot /= Nothing)
                            , multipleChecks
                            ]


crowdedReturnFireChecks : { before : TurnPlayback.Frame, opening : Shot, returning : Shot } -> List String
crowdedReturnFireChecks fixture =
    case ( UnitId.parse "crowded-attacker", UnitId.parse "crowded-target" ) of
        ( Ok third, Ok fourth ) ->
            let
                expect : String -> Bool -> List String
                expect label passed =
                    if passed then
                        []

                    else
                        [ label ]

                unrelated : Shot
                unrelated =
                    fixture.opening
                        |> setShotAttacker (fixture.opening.attacker |> Unit.setId third)
                        |> setShotTarget (fixture.opening.target |> Unit.setId fourth)
                        |> setShotOrigin { x = 5, y = 2 }
                        |> setShotDestination { x = 6, y = 2 }

                waiting : TurnPlayback.Frame
                waiting =
                    fixture.before |> setFrameDurationMs 600

                focus : List Shot -> Maybe TurnPlayback.Playback
                focus shots =
                    TurnPlayback.start
                        [ fixture.before
                        , fixture.before
                            |> setFrameDurationMs 450
                            |> TurnPlayback.setFrameShots [ fixture.opening ]
                        , waiting
                        , fixture.before
                            |> setFrameDurationMs 450
                            |> TurnPlayback.setFrameShots shots
                        , waiting
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                combined : Maybe TurnPlayback.Playback
                combined =
                    focus [ unrelated, fixture.returning ]

                advance : Maybe TurnPlayback.Playback -> Maybe TurnPlayback.Playback
                advance playback =
                    playback
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map .animation

                next : Maybe TurnPlayback.Playback
                next =
                    advance combined

                combinedHealth : Maybe TurnPlayback.Playback -> Maybe Int
                combinedHealth playback =
                    playback
                        |> Maybe.andThen TurnPlayback.combat
                        |> Maybe.map (.attackerHealth >> .after >> .current)

                conflicting : Shot
                conflicting =
                    unrelated |> setShotTarget fixture.opening.target
            in
            expect "stationary return fire shares one card when its volley also contains an unrelated shot"
                (combinedHealth combined
                    == Just 15
                    && combinedHealth (focus [ fixture.returning, unrelated ])
                    == Just 15
                    && (combined |> Maybe.andThen TurnPlayback.combat |> Maybe.map .targetFired)
                    == Just True
                )
                ++ expect "the unrelated encounter retains its own health transition after the combined pair"
                    ((next |> Maybe.andThen TurnPlayback.combat |> Maybe.map (.attacker >> .id))
                        == Just third
                        && (next |> Maybe.andThen TurnPlayback.combat |> Maybe.map .targetHealth)
                        == Just unrelated.targetHealth
                        && (advance next |> Maybe.andThen TurnPlayback.combat)
                        == Nothing
                    )
                ++ expect "combining return fire retains both authoritative shots and the final frame"
                    ((combined |> Maybe.map (.current >> .shots >> List.length))
                        == Just 3
                        && (combined |> Maybe.map (.current >> .units))
                        == Just fixture.before.units
                    )
                ++ expect "a shared participant in the return volley keeps health sequencing in separate encounters"
                    (combinedHealth (focus [ fixture.returning, conflicting ]) == Just 16)
                ++ expect "indirect fire never becomes a direct return-fire exchange"
                    (combinedHealth (focus [ fixture.returning |> setShotKind CombatKind.IndirectFire ]) == Just 16)

        _ ->
            [ "could not construct unrelated return-volley unit IDs" ]


mergedImpactChecks : { gun : Unit, target : Unit, before : TurnPlayback.Frame } -> List String
mergedImpactChecks fixture =
    case UnitId.parse "3" of
        Err _ ->
            [ "could not construct a second indirect gun ID" ]

        Ok third ->
            let
                firstGun : Unit
                firstGun =
                    fixture.gun |> Unit.setKind Kind.FieldGun

                secondGun : Unit
                secondGun =
                    firstGun |> Unit.setId third |> Unit.setOnMap { x = 4, y = 2 }

                hidden : IndirectImpact
                hidden =
                    { destination = { x = 3, y = 2 }, attacker = Nothing, target = Nothing, depot = Nothing }

                visible : IndirectImpact
                visible =
                    hidden
                        |> setImpactAttacker
                            (Just { unit = secondGun, health = { current = 16, maximum = 16 } })

                smaller : IndirectImpact
                smaller =
                    hidden
                        |> setImpactAttacker
                            (Just { unit = firstGun, health = { current = 4, maximum = 16 } })

                fullFirst : IndirectImpact
                fullFirst =
                    hidden
                        |> setImpactAttacker
                            (Just { unit = firstGun, health = { current = 16, maximum = 16 } })

                show : List IndirectImpact -> List Shot -> Maybe TurnPlayback.Playback
                show impacts shots =
                    let
                        initial : TurnPlayback.Frame
                        initial =
                            fixture.before

                        before : TurnPlayback.Frame
                        before =
                            { initial | units = [ firstGun, secondGun, fixture.target ] }
                    in
                    TurnPlayback.start
                        [ before
                        , before
                            |> setFrameIndirectImpacts impacts
                            |> TurnPlayback.setFrameShots shots
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                hiddenFirst : Maybe TurnPlayback.Playback
                hiddenFirst =
                    show [ hidden, visible ] []

                multiple : Maybe TurnPlayback.Playback
                multiple =
                    show [ smaller, visible ] []

                participants : TurnPlayback.Panel -> List UnitId
                participants panel =
                    case panel.encounter of
                        TurnPlayback.Impact impact ->
                            List.map (.unit >> .id) impact.attackers

                        _ ->
                            []

                times : Maybe TurnPlayback.Playback -> Maybe (List Float)
                times playback =
                    playback |> Maybe.andThen TurnPlayback.panels |> Maybe.map (CombatTheater.firingTimes Kind.FieldGun)

                soundsBetween : { before : Float, after : Float } -> Maybe TurnPlayback.Playback -> List Audio.Event
                soundsBetween interval playback =
                    let
                        atTime : Float -> Maybe TurnPlayback.Playback
                        atTime elapsed =
                            playback |> Maybe.andThen (TurnPlayback.tick elapsed >> Tuple.first)
                    in
                    PlaybackPresentation.audioBetween { before = atTime interval.before, after = atTime interval.after }

                firstHealth : CombatHealth
                firstHealth =
                    { before = { current = 16, maximum = 16 }, after = { current = 8, maximum = 16 } }

                lastHealth : CombatHealth
                lastHealth =
                    { before = { current = 8, maximum = 16 }, after = { current = 4, maximum = 16 } }

                firstHit : IndirectImpact
                firstHit =
                    { smaller
                        | target = Just { unit = fixture.target, health = firstHealth }
                        , depot = Just { kind = BuildingKind.Supply, before = { current = 3, maximum = 3 }, after = { current = 2, maximum = 3 } }
                    }

                lastHit : IndirectImpact
                lastHit =
                    { visible
                        | target = Just { unit = fixture.target, health = lastHealth }
                        , depot = Just { kind = BuildingKind.Supply, before = { current = 2, maximum = 3 }, after = { current = 1, maximum = 3 } }
                    }

                confirmed : Shot
                confirmed =
                    { kind = CombatKind.IndirectFire
                    , origin = { x = 4, y = 2 }
                    , destination = visible.destination
                    , attacker = secondGun
                    , target = fixture.target
                    , damage = 4
                    , attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                    , targetHealth = lastHealth
                    }

                damaged : Maybe TurnPlayback.Playback
                damaged =
                    show [ firstHit, lastHit ] [ confirmed ]

                combinedDamage : TurnPlayback.Panel -> Bool
                combinedDamage panel =
                    case panel.encounter of
                        TurnPlayback.Impact impact ->
                            (Maybe.map .health impact.target == Just { before = firstHealth.before, after = lastHealth.after })
                                && (impact.depot == Just { kind = BuildingKind.Supply, before = { current = 3, maximum = 3 }, after = { current = 1, maximum = 3 } })
                                && (participants panel == [ firstGun.id, secondGun.id ])

                        _ ->
                            False

                expect : String -> Bool -> List String
                expect label passed =
                    if passed then
                        []

                    else
                        [ label ]
            in
            List.concat
                [ expect "a visible gun after a concealed landing retains its formation and all four shot times"
                    ((hiddenFirst |> Maybe.andThen TurnPlayback.panels |> Maybe.map participants)
                        == Just [ secondGun.id ]
                        && times hiddenFirst
                        == Just [ 1520, 1610, 1700, 1790 ]
                        && times (show [ visible, hidden ] [])
                        == times hiddenFirst
                    )
                , expect "merged observable guns retain their own health and staggered muzzle times"
                    ((multiple |> Maybe.andThen TurnPlayback.panels |> Maybe.map participants)
                        == Just [ firstGun.id, secondGun.id ]
                        && times multiple
                        == Just [ 1520, 1520, 1610, 1700, 1790 ]
                        && times (show [ fullFirst, visible ] [])
                        == Just [ 1520, 1520, 1610, 1610, 1700, 1700, 1790, 1790 ]
                    )
                , expect "landing impacts wait for the last observable gun to recover"
                    ((multiple |> Maybe.andThen TurnPlayback.panels |> Maybe.map CombatTheater.attackDelay)
                        == Just 1210
                        && (hiddenFirst |> Maybe.andThen TurnPlayback.panels |> Maybe.map CombatTheater.attackDelay)
                        == Just 1210
                    )
                , expect "merged indirect audio emits every observed shot exactly once at its muzzle time"
                    (List.isEmpty (soundsBetween { before = 0, after = 1519 } multiple)
                        && soundsBetween { before = 1519, after = 1520 } multiple
                        == List.repeat 2 Audio.fieldGunFire
                        && soundsBetween { before = 1520, after = 1790 } multiple
                        == List.repeat 3 Audio.fieldGunFire
                        && List.isEmpty (soundsBetween { before = 1790, after = 6000 } multiple)
                    )
                , expect "concealed landing participants are never inferred from battlefield units"
                    ((show [ hidden, hidden ] [] |> Maybe.andThen TurnPlayback.panels |> Maybe.map participants)
                        == Just []
                        && times (show [ hidden, hidden ] [])
                        == Just []
                        && (show [ hidden, hidden ] [] |> Maybe.andThen TurnPlayback.panels |> Maybe.map CombatTheater.attackDelay)
                        == Just 0
                        && (hiddenFirst |> Maybe.map TurnPlayback.focusPositions)
                        == Just [ { x = 4, y = 2 }, { x = 3, y = 2 } ]
                    )
                , expect "merged guns preserve one complete target and depot transition without duplicate hit scenes"
                    ((damaged |> Maybe.andThen TurnPlayback.panels |> Maybe.map combinedDamage)
                        == Just True
                        && (damaged |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map (.animation >> TurnPlayback.activeEncounter))
                        == Just Nothing
                    )
                ]


combatDeathChecks : UnitId -> UnitId -> List String
combatDeathChecks first second =
    case UnitId.parse "3" of
        Err _ ->
            [ "could not construct combat death fixture" ]

        Ok third ->
            let
                attacker : Unit
                attacker =
                    { id = first
                    , playerNumber = PlayerNumber.Player1
                    , entrenchment = Entrenchment.Exposed
                    , spriteFacing = SpriteFacing.Right
                    , direction = Just Direction.East
                    , kind = Kind.Tank
                    , destroyed = False
                    , combatState = Nothing
                    , combatRules =
                        { range = 1
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 8
                        , readinessCost = 2
                        , digInCost = 64
                        , shotCost = 2
                        }
                    , cargoCapacity = 0
                    , location = Location.OnMap { x = 2, y = 2 }
                    , resources = Nothing
                    }

                target : Unit
                target =
                    attacker
                        |> Unit.setId second
                        |> Unit.setPlayerNumber PlayerNumber.Player2
                        |> Unit.setOnMap { x = 3, y = 2 }

                other : Unit
                other =
                    target
                        |> Unit.setId third
                        |> Unit.setOnMap { x = 2, y = 3 }

                before : TurnPlayback.Frame
                before =
                    { units = [ attacker, target, other ]
                    , departures = []
                    , sabotages = []
                    , indirectImpacts = []
                    , shots = []
                    , durationMs = 0
                    , visibleTiles = [ { x = 2, y = 2 }, { x = 3, y = 2 }, { x = 2, y = 3 } ]
                    , depots = []
                    , supplyCrates = []
                    }

                lethalShot : Unit -> Shot
                lethalShot victim =
                    { kind = CombatKind.Ambush, origin = { x = 2, y = 2 }, destination = Unit.mapPosition victim |> Maybe.withDefault { x = 3, y = 2 }, attacker = attacker, target = victim, damage = 8, attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }, targetHealth = { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } } }

                volley : TurnPlayback.Frame
                volley =
                    before
                        |> setFrameDurationMs 450
                        |> TurnPlayback.setFrameUnits
                            [ attacker
                            , target
                                |> Unit.setDestroyed True
                            , other
                                |> Unit.setDestroyed True
                            ]
                        |> TurnPlayback.setFrameShots
                            [ lethalShot target, lethalShot other ]

                cleanup : TurnPlayback.Frame
                cleanup =
                    before
                        |> setFrameDurationMs 1400
                        |> TurnPlayback.setFrameUnits
                            [ attacker ]

                openFirst : Maybe TurnPlayback.Playback
                openFirst =
                    TurnPlayback.start [ before, volley, cleanup ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                firstDeath : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                firstDeath =
                    openFirst |> Maybe.andThen TurnPlayback.continueCombat

                attackMoveCauses : TurnPlayback.Playback -> List TurnPlayback.LossCause
                attackMoveCauses animation =
                    let
                        current : TurnPlayback.Frame
                        current =
                            animation.current

                        attackMoveShot : Shot -> Shot
                        attackMoveShot shot =
                            shot
                                |> setShotKind CombatKind.AttackMove
                    in
                    TurnPlayback.losses
                        (animation
                            |> setPlaybackCurrent
                                (current
                                    |> TurnPlayback.setFrameShots (List.map attackMoveShot current.shots)
                                )
                        )
                        |> List.map .cause

                firstHeld : Maybe TurnPlayback.Frame
                firstHeld =
                    firstDeath |> Maybe.map (.animation >> TurnPlayback.tick 1399 >> Tuple.second)

                nextPair : Maybe ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )
                nextPair =
                    firstDeath |> Maybe.map (.animation >> TurnPlayback.tick 60000)

                secondDeath : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                secondDeath =
                    nextPair |> Maybe.andThen Tuple.first |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first) |> Maybe.andThen TurnPlayback.continueCombat

                cleared : Maybe ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )
                cleared =
                    secondDeath |> Maybe.map (.animation >> TurnPlayback.tick 1400)

                dyingIds : TurnPlayback.Frame -> List UnitId
                dyingIds frame =
                    List.filter Unit.isDying frame.units |> List.map .id

                reciprocal : Shot
                reciprocal =
                    { kind = CombatKind.Ambush, origin = { x = 3, y = 2 }, destination = { x = 2, y = 2 }, attacker = target, target = attacker, damage = 16, attackerHealth = { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } }, targetHealth = { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } } }

                mutual : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                mutual =
                    TurnPlayback.start
                        [ before
                        , volley
                            |> TurnPlayback.setFrameUnits
                                [ attacker
                                    |> Unit.setDestroyed True
                                , target
                                    |> Unit.setDestroyed True
                                , other
                                ]
                            |> TurnPlayback.setFrameShots
                                [ reciprocal
                                    |> setShotOrigin reciprocal.destination
                                    |> setShotDestination reciprocal.origin
                                    |> setShotAttacker attacker
                                    |> setShotTarget target
                                    |> Shot.setAttackerHealth reciprocal.targetHealth
                                    |> Shot.setTargetHealth reciprocal.attackerHealth
                                , reciprocal
                                ]
                        , cleanup
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat

                concealedDeath : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                concealedDeath =
                    TurnPlayback.start
                        [ before
                        , volley
                            |> TurnPlayback.setFrameUnits
                                [ attacker, other ]
                            |> TurnPlayback.setFrameShots
                                [ lethalShot target ]
                        , cleanup
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat

                concealedShell : TurnPlayback.Frame
                concealedShell =
                    volley
                        |> TurnPlayback.setFrameUnits
                            [ attacker
                            , target
                                |> Unit.setDestroyed True
                            , other
                            ]
                        |> TurnPlayback.setFrameShots []
                        |> setFrameSabotages []
                        |> setFrameIndirectImpacts
                            [ { destination = { x = 3, y = 2 }, attacker = Nothing, depot = Nothing, target = Just { unit = target, health = { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } } } } ]

                shellDeath : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                shellDeath =
                    TurnPlayback.start [ before, concealedShell, cleanup ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat

                firingGun : Unit
                firingGun =
                    target |> Unit.setKind Kind.FieldGun

                gunMiss : IndirectImpact
                gunMiss =
                    { destination =
                        { x = 5
                        , y = 4
                        }
                    , attacker =
                        Just
                            { unit = firingGun
                            , health =
                                { current = 16
                                , maximum = 16
                                }
                            }
                    , target = Nothing
                    , depot = Nothing
                    }

                gunKill : Shot
                gunKill =
                    let
                        hit : Shot
                        hit =
                            lethalShot firingGun
                    in
                    { hit
                        | kind = CombatKind.IndirectFire
                        , damage = 16
                        , targetHealth =
                            { before =
                                { current = 16
                                , maximum = 16
                                }
                            , after =
                                { current = 0
                                , maximum = 16
                                }
                            }
                    }

                bombardment : List Shot -> List IndirectImpact -> Maybe TurnPlayback.Playback
                bombardment shots impacts =
                    TurnPlayback.start
                        [ before
                            |> TurnPlayback.setFrameUnits
                                [ attacker
                                , firingGun
                                ]
                        , volley
                            |> TurnPlayback.setFrameUnits
                                [ attacker, firingGun |> Unit.setDestroyed True ]
                            |> TurnPlayback.setFrameShots shots
                            |> setFrameIndirectImpacts impacts
                        , cleanup
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                mixedBombardment : Maybe TurnPlayback.Playback
                mixedBombardment =
                    bombardment [ gunKill ] [ gunMiss ]

                afterGunMiss : Maybe TurnPlayback.Playback
                afterGunMiss =
                    mixedBombardment
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.andThen (.animation >> TurnPlayback.tick 300 >> Tuple.first)

                concealedGunKill : IndirectImpact
                concealedGunKill =
                    { destination = gunKill.destination
                    , attacker = Nothing
                    , target =
                        Just
                            { unit = firingGun
                            , health = gunKill.targetHealth
                            }
                    , depot = Nothing
                    }

                shellCarrierDeath : Maybe TurnPlayback.LossEvent
                shellCarrierDeath =
                    let
                        carrier : Unit
                        carrier =
                            target
                                |> Unit.setKind Kind.Truck

                        passenger : Unit
                        passenger =
                            other
                                |> Unit.setLocation (Location.Aboard second)

                        carriedBefore : TurnPlayback.Frame
                        carriedBefore =
                            before
                                |> TurnPlayback.setFrameUnits
                                    [ attacker, carrier, passenger ]

                        carriedDeath : TurnPlayback.Frame
                        carriedDeath =
                            { concealedShell
                                | units =
                                    [ attacker
                                    , carrier
                                        |> Unit.setDestroyed True
                                    , passenger
                                        |> Unit.setDestroyed True
                                    ]
                            }
                    in
                    TurnPlayback.start [ carriedBefore, carriedDeath, cleanup ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.andThen (.animation >> TurnPlayback.lossEvent)

                overkill : Shot
                overkill =
                    reciprocal
                        |> setShotOrigin
                            { x = 2, y = 3 }
                        |> setShotDestination
                            { x = 3, y = 2 }
                        |> setShotAttacker
                            (other
                                |> Unit.setPlayerNumber PlayerNumber.Player1
                            )
                        |> setShotTarget target
                        |> Shot.setAttackerHealth
                            { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                        |> Shot.setTargetHealth
                            { before = { current = 0, maximum = 16 }, after = { current = 0, maximum = 16 } }

                afterOverkill : Maybe TurnPlayback.Playback
                afterOverkill =
                    TurnPlayback.start
                        [ before
                        , volley
                            |> TurnPlayback.setFrameShots
                                [ lethalShot target, overkill ]
                            |> TurnPlayback.setFrameUnits
                                [ attacker
                                , target
                                    |> Unit.setDestroyed True
                                , other
                                ]
                        , cleanup
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.andThen (.animation >> TurnPlayback.tick 1400 >> Tuple.first)

                singlePair : Shot -> Maybe TurnPlayback.CombatExchange
                singlePair shot =
                    TurnPlayback.start
                        [ before
                        , before
                            |> setFrameDurationMs 450
                            |> TurnPlayback.setFrameShots
                                [ shot ]
                        , cleanup
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.combat

                chainAttacker : Unit
                chainAttacker =
                    target
                        |> Unit.setKind Kind.Infantry

                chainDefender : Unit
                chainDefender =
                    attacker
                        |> Unit.setKind Kind.Infantry

                chainGun : Unit
                chainGun =
                    other
                        |> Unit.setPlayerNumber PlayerNumber.Player1
                        |> Unit.setKind Kind.FieldGun

                chainAttack : Shot
                chainAttack =
                    reciprocal
                        |> setShotKind CombatKind.AttackMove
                        |> setShotAttacker chainAttacker
                        |> setShotTarget chainDefender
                        |> setShotDamage 1
                        |> Shot.setAttackerHealth
                            { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                        |> Shot.setTargetHealth
                            { before = { current = 16, maximum = 16 }, after = { current = 15, maximum = 16 } }

                chain : Bool -> Maybe TurnPlayback.Playback
                chain concealed =
                    let
                        units : List Unit
                        units =
                            if concealed then
                                [ chainDefender, chainGun ]

                            else
                                [ chainDefender, chainAttacker, chainGun ]

                        opening : TurnPlayback.Frame
                        opening =
                            before
                                |> TurnPlayback.setFrameUnits units

                        dying : Unit -> Unit
                        dying unit =
                            unit
                                |> Unit.setDestroyed (unit.id == second)

                        killShot : Shot
                        killShot =
                            lethalShot chainAttacker

                        landing : TurnPlayback.Frame
                        landing =
                            volley
                                |> TurnPlayback.setFrameUnits (List.map dying units)
                                |> TurnPlayback.setFrameShots
                                    [ chainAttack
                                    , killShot
                                        |> setShotAttacker chainGun
                                        |> setShotOrigin
                                            { x = 2, y = 3 }
                                        |> Shot.setTargetHealth
                                            { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } }
                                    ]
                    in
                    TurnPlayback.start [ opening, landing, cleanup ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                chainKillingPair : Maybe TurnPlayback.Playback
                chainKillingPair =
                    chain False
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map .animation

                expect : String -> Bool -> List String
                expect label passed =
                    if passed then
                        []

                    else
                        [ label ]
            in
            List.concat
                [ expect "a previously visible enemy concealed at death never enters the loss queue"
                    (concealedDeath |> Maybe.map (.animation >> TurnPlayback.losses >> List.isEmpty) |> (==) (Just True))
                , expect "concealed artillery casualties retain their cause without an attacker portrait"
                    (Maybe.map (.animation >> TurnPlayback.losses >> List.map .cause) shellDeath == Just [ TurnPlayback.ConcealedIndirectFire ])
                , expect "concealed artillery deaths pause at their own impact scene"
                    (Maybe.map (.frame >> dyingIds) shellDeath == Just [ second ])
                , expect "a gun's simultaneous miss appears before the confirmed hit that destroys it"
                    (Maybe.andThen TurnPlayback.activeEncounter mixedBombardment == Just (impactEncounter gunMiss))
                , expect "merged landings retain the firing dependency of every observable gun"
                    (bombardment [ gunKill ]
                        [ { gunMiss
                            | attacker =
                                Just
                                    { unit = other
                                    , health = { current = 16, maximum = 16 }
                                    }
                          }
                        , gunMiss
                        ]
                        |> Maybe.andThen TurnPlayback.activeEncounter
                        |> (==)
                            (Just
                                (TurnPlayback.Impact
                                    { destination = gunMiss.destination
                                    , attackers =
                                        [ { unit = other, health = { current = 16, maximum = 16 } }
                                        , { unit = firingGun, health = { current = 16, maximum = 16 } }
                                        ]
                                    , target = Nothing
                                    , depot = Nothing
                                    }
                                )
                            )
                    )
                , expect "continuing the gun's shot opens its destruction with the gun still on the board"
                    ((Maybe.andThen TurnPlayback.combat afterGunMiss |> Maybe.map (.target >> .id))
                        == Just second
                        && (Maybe.andThen TurnPlayback.continueCombat afterGunMiss |> Maybe.map (.frame >> dyingIds))
                        == Just [ second ]
                    )
                , expect "a concealed gun's lethal impact waits for the victim's simultaneous miss"
                    (bombardment [] [ concealedGunKill, gunMiss ]
                        |> Maybe.andThen TurnPlayback.activeEncounter
                        |> (==) (Just (impactEncounter gunMiss))
                    )
                , expect "passengers share their carrier's concealed artillery loss event"
                    (Maybe.map (.loss >> .cause) shellCarrierDeath
                        == Just TurnPlayback.ConcealedIndirectFire
                        && Maybe.map (.passengers >> List.map .id) shellCarrierDeath
                        == Just [ third ]
                    )
                , expect "artillery deaths retain acknowledgment and the server casualty pause"
                    (Maybe.map (.animation >> TurnPlayback.tickUntilLoss 60000 >> Tuple.second >> dyingIds) shellDeath
                        == Just [ second ]
                        && Maybe.map (.animation >> TurnPlayback.acknowledgeLoss second >> TurnPlayback.tickUntilLoss 1400 >> Tuple.second >> dyingIds) shellDeath
                        == Just []
                    )
                , expect "overkill does not open an empty encounter after the target's death"
                    (Maybe.andThen TurnPlayback.activeEncounter afterOverkill == Nothing && afterOverkill /= Nothing)
                , expect "zero-damage shots between living combatants still open the theater"
                    (singlePair
                        (overkill
                            |> Shot.setTargetHealth overkill.attackerHealth
                            |> setShotDamage 0
                        )
                        /= Nothing
                    )
                , expect "reciprocal damage is retained even when the other participant already died"
                    (singlePair
                        (overkill
                            |> Shot.setAttackerHealth
                                { before = { current = 16, maximum = 16 }, after = { current = 12, maximum = 16 } }
                        )
                        /= Nothing
                    )
                , expect "a simultaneous attack move starts with the enemy's full formation"
                    (chain False |> Maybe.andThen TurnPlayback.combat |> Maybe.map (.attackerHealth >> .before >> .current >> CombatFormation.figureCount Kind.Infantry) |> (==) (Just 8))
                , expect "a visible attack mover stays on the held board until its later lethal pair"
                    (Maybe.andThen TurnPlayback.spotlight (chain False)
                        == Just [ { x = 2, y = 2 }, { x = 3, y = 2 } ]
                        && (Maybe.andThen TurnPlayback.combat chainKillingPair |> Maybe.map (.attacker >> .id) |> (==) (Just third))
                    )
                , expect "concealed attack movers retain their theater formation without a map spotlight"
                    (Maybe.andThen TurnPlayback.spotlight (chain True)
                        == Just [ { x = 2, y = 2 } ]
                        && (chain True |> Maybe.andThen TurnPlayback.combat |> Maybe.map (.attackerHealth >> .before >> .current) |> (==) (Just 16))
                    )
                , expect "concealed combat casualties never gain a battlefield skull from their portrait"
                    (concealedDeath |> Maybe.map (.frame >> dyingIds >> List.isEmpty) |> (==) (Just True))
                , expect "loss dialog identifies the lethal shot and its attacker"
                    (firstDeath |> Maybe.map (.animation >> TurnPlayback.losses) |> Maybe.map (List.map .cause) |> (==) (Just [ TurnPlayback.Destroyed CombatKind.Ambush attacker ]))
                , expect "loss dialogs distinguish attack move from ambush"
                    (firstDeath |> Maybe.map (.animation >> attackMoveCauses) |> (==) (Just [ TurnPlayback.Destroyed CombatKind.AttackMove attacker ]))
                , expect "loss dialog holds combat casualties through arbitrarily long ticks"
                    (firstDeath |> Maybe.map (.animation >> TurnPlayback.tickUntilLoss 60000 >> Tuple.second >> dyingIds) |> (==) (Just [ second ]))
                , expect "continuing a loss resumes the existing casualty pause"
                    (firstDeath |> Maybe.map (.animation >> TurnPlayback.acknowledgeLoss second >> TurnPlayback.tickUntilLoss 1400 >> Tuple.second >> dyingIds) |> (==) (Just []))
                , expect "reciprocal losses require separate acknowledgments"
                    (mutual |> Maybe.map (.animation >> TurnPlayback.acknowledgeLoss first >> TurnPlayback.losses >> List.map (.unit >> .id)) |> (==) (Just [ second ]))
                , expect "first theater reveals only its own casualty and closes the card"
                    (Maybe.map (.frame >> dyingIds) firstDeath == Just [ second ] && Maybe.andThen (.animation >> TurnPlayback.panels) firstDeath == Nothing)
                , expect "per-pair skull holds for the server pause without movement or early continuation"
                    (Maybe.map dyingIds firstHeld == Just [ second ] && Maybe.map (.animation >> Just >> TurnPlayback.movingPositions) firstDeath == Just [] && Maybe.andThen (.animation >> TurnPlayback.continueCombat) firstDeath == Nothing)
                , expect "long ticks remove the first casualty and stop at the next theater"
                    (Maybe.map (Tuple.second >> .units >> List.map .id) nextPair == Just [ first, third ] && (nextPair |> Maybe.andThen Tuple.first |> Maybe.andThen TurnPlayback.combat |> Maybe.map (.target >> .id)) == Just third)
                , expect "second theater reveals its own skull without resurrecting the first casualty"
                    (Maybe.map (.frame >> dyingIds) secondDeath == Just [ third ] && Maybe.map (.frame >> .units >> List.map .id) secondDeath == Just [ first, third ])
                , expect "finished pair deaths never reappear in the shared volley"
                    (Maybe.map (Tuple.second >> .units >> List.map .id) cleared == Just [ first ] && Maybe.map (Tuple.second >> dyingIds) cleared == Just [])
                , expect "reciprocal lethal shots share their skull pause"
                    (Maybe.map (.frame >> dyingIds) mutual == Just [ first, second ])
                ]


deathPlaybackChecks : UnitId -> List String
deathPlaybackChecks id =
    let
        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]

        dead : Unit
        dead =
            { id = id
            , playerNumber = PlayerNumber.Player1
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Right
            , direction = Just Direction.East
            , kind = Kind.Infantry
            , destroyed = False
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , cargoCapacity = 0
            , location =
                Location.OnMap
                    { x = 2
                    , y = 2
                    }
            , resources =
                Just
                    { supplyCargo = []
                    , hitPoints =
                        { current = 0
                        , maximum = 16
                        }
                    , supplies =
                        { current = 0
                        , maximum = 64
                        , upkeepPerTurn = 1
                        , roughTerrainSurcharge = 0
                        , movementPerTile = 1
                        }
                    , fuel = Nothing
                    }
            }

        dying : TurnPlayback.Frame
        dying =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 180
            , units = [ dead ]
            , visibleTiles =
                [ { x = 2
                  , y = 2
                  }
                ]
            }

        gone : TurnPlayback.Frame
        gone =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 1400
            , units = []
            , visibleTiles = []
            }

        animation : TurnPlayback.Playback
        animation =
            { current = dying, remaining = [ gone ], elapsed = 0, acknowledgedLosses = [], presentation = TurnPlayback.Battlefield }

        ( pending, beforeRemoval ) =
            TurnPlayback.tick 1399 animation

        ( finished, afterRemoval ) =
            TurnPlayback.tick 1400 animation

        alive : Unit
        alive =
            dead
                |> Unit.setResources Nothing

        initial : TurnPlayback.Frame
        initial =
            dying
                |> TurnPlayback.setFrameUnits
                    [ alive ]
                |> setFrameDurationMs 0

        delayed : Maybe ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )
        delayed =
            TurnPlayback.start [ initial, dying, gone ]
                |> Maybe.map (TurnPlayback.tickUntilLoss 60000)

        shown : Maybe TurnPlayback.Playback
        shown =
            delayed |> Maybe.andThen Tuple.first |> Maybe.andThen (TurnPlayback.tickUntilLoss 300 >> Tuple.first)

        continued : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
        continued =
            shown |> Maybe.andThen TurnPlayback.continueCombat

        exhaustionReady : Float -> TurnPlayback.MapView -> Bool
        exhaustionReady elapsed mapView =
            CombatTheater.readyToAutomaticallyClose
                { encounter = TurnPlayback.Exhaustion alive
                , elapsed = elapsed
                , mapView = mapView
                }

        exhaustionKindChecks : Kind.UnitKind -> List String
        exhaustionKindChecks kind =
            let
                living : Unit
                living =
                    Unit.setKind kind alive

                shownKind : Maybe TurnPlayback.Playback
                shownKind =
                    TurnPlayback.start
                        [ initial |> TurnPlayback.setFrameUnits [ living ]
                        , dying |> TurnPlayback.setFrameUnits [ Unit.setKind kind dead ]
                        , gone
                        ]
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 60000 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 300 >> Tuple.first)

                continuedKind : Maybe { animation : TurnPlayback.Playback, frame : TurnPlayback.Frame }
                continuedKind =
                    shownKind |> Maybe.andThen TurnPlayback.continueCombat
            in
            expect "every unit kind opens an exhaustion theater" (shownKind |> Maybe.andThen TurnPlayback.activeEncounter |> (==) (Just (TurnPlayback.Exhaustion living)))
                ++ expect "exhaustion acknowledges once and completes without a second theater"
                    (continuedKind |> Maybe.andThen (.animation >> TurnPlayback.acknowledgeLoss id >> TurnPlayback.tickUntilLoss 60000 >> Tuple.first) |> Maybe.andThen (TurnPlayback.tickUntilLoss 60000 >> Tuple.first) |> (==) Nothing)

        sabotageChecks : BuildingKind.BuildingKind -> List String
        sabotageChecks kind =
            let
                building : Depot
                building =
                    { kind = kind
                    , position = { x = 2, y = 2 }
                    , stock = Nothing
                    , hp = { current = 3, maximum = 3 }
                    }

                sabotageBefore : TurnPlayback.Frame
                sabotageBefore =
                    { initial | depots = [ building ] }

                sabotageFrame : TurnPlayback.Frame
                sabotageFrame =
                    { sabotageBefore
                        | durationMs = 180
                        , sabotages = [ building.position ]
                        , depots = [ { building | hp = { current = 0, maximum = 3 } } ]
                    }

                show : List Unit -> Maybe TurnPlayback.Playback
                show units =
                    TurnPlayback.start
                        [ sabotageBefore |> TurnPlayback.setFrameUnits units
                        , sabotageFrame |> TurnPlayback.setFrameUnits units
                        , gone
                        ]
                        |> Maybe.andThen (TurnPlayback.tick 180 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)

                encounter : TurnPlayback.Encounter
                encounter =
                    TurnPlayback.Sabotage building

                ready : Float -> Bool
                ready elapsed =
                    CombatTheater.readyToAutomaticallyClose
                        { encounter = encounter, elapsed = elapsed, mapView = TurnPlayback.CardVisible }
            in
            expect "sabotage retains the observed building" (show [ alive ] |> Maybe.andThen TurnPlayback.activeEncounter |> (==) (Just encounter))
                ++ expect "sabotage scenes do not depend on a visible infantry occupant" (show [] |> Maybe.andThen TurnPlayback.activeEncounter |> (==) (Just encounter))
                ++ expect "sabotage focuses only its projected tile" (show [] |> Maybe.map TurnPlayback.focusPositions |> (==) (Just [ { x = 2, y = 2 } ]))
                ++ expect "sabotage waits for the dynamite, destruction, and automatic-close delay" (not (ready 3599) && ready 3600)
                ++ expect "sabotage has no firing cues or unit losses" (show [ alive ] |> Maybe.map (\playback -> List.isEmpty (TurnPlayback.losses playback) && (TurnPlayback.panels playback |> Maybe.map (CombatTheater.firingTimes Kind.Tank) |> (==) (Just []))) |> (==) (Just True))

        ( held, heldFrame ) =
            TurnPlayback.tickUntilLoss 60000 animation

        ( acknowledged, acknowledgedFrame ) =
            TurnPlayback.acknowledgeLoss id animation |> TurnPlayback.tickUntilLoss 1400
    in
    expect "dead units remain for the full death animation" (pending /= Nothing && beforeRemoval.units == [ dead ])
        ++ expect "dead units vanish at the server frame boundary" (finished == Nothing && List.isEmpty afterRemoval.units && List.isEmpty afterRemoval.visibleTiles)
        ++ expect "death does not interpolate a movement" (List.isEmpty (TurnPlayback.movingPositions (Just animation)))
        ++ expect "supply death dialogs remain until acknowledged" (held == Just animation && heldFrame.units == [ dead ])
        ++ expect "supply death cause uses the exhaustion frame" (List.map .cause (TurnPlayback.losses animation) == [ TurnPlayback.SuppliesExhausted ])
        ++ expect "delayed ticks stop before the supply-exhaustion theater" (Maybe.map (Tuple.second >> .units) delayed == Just [ alive ])
        ++ expect "acknowledged supply death completes normally" (acknowledged == Nothing && List.isEmpty acknowledgedFrame.units)
        ++ expect "exhaustion opens its theater before acknowledging a loss" (shown |> Maybe.andThen TurnPlayback.activeEncounter |> (==) (Just (TurnPlayback.Exhaustion alive)))
        ++ expect "exhaustion keeps casualty acknowledgment after the theater" (continued |> Maybe.map (.animation >> TurnPlayback.losses >> List.map .cause) |> (==) (Just [ TurnPlayback.SuppliesExhausted ]))
        ++ expect "exhaustion waits for every figure to fade and the close delay" (not (exhaustionReady 3239 TurnPlayback.CardVisible) && exhaustionReady 3240 TurnPlayback.CardVisible && not (exhaustionReady 6000 TurnPlayback.SeeingMap))
        ++ List.concatMap exhaustionKindChecks [ Kind.Infantry, Kind.Tank, Kind.Truck, Kind.FieldGun ]
        ++ List.concatMap sabotageChecks [ BuildingKind.Supply, BuildingKind.Fuel, BuildingKind.Fortress ]


deathFocusChecks : UnitId -> UnitId -> List String
deathFocusChecks first second =
    let
        dead : Unit
        dead =
            { id = first
            , playerNumber = PlayerNumber.Player2
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Left
            , direction = Just Direction.West
            , kind = Kind.Infantry
            , destroyed = True
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , cargoCapacity = 0
            , location = Location.OnMap { x = 2, y = 2 }
            , resources = Nothing
            }

        survivor : Unit
        survivor =
            dead
                |> Unit.setId second
                |> Unit.setDestroyed False
                |> Unit.setOnMap { x = 3, y = 2 }

        dying : TurnPlayback.Frame
        dying =
            { depots = []
            , supplyCrates = []
            , departures = []
            , sabotages = []
            , indirectImpacts = []
            , shots = []
            , durationMs = 450
            , units = [ dead, survivor ]
            , visibleTiles =
                [ { x = 2
                  , y = 2
                  }
                , { x = 3
                  , y = 2
                  }
                ]
            }

        paused : TurnPlayback.Frame
        paused =
            dying
                |> setFrameDurationMs 1400

        moved : TurnPlayback.Frame
        moved =
            dying
                |> setFrameDurationMs 180
                |> TurnPlayback.setFrameUnits
                    [ dead, Unit.setOnMap { x = 4, y = 2 } survivor ]

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]
    in
    case TurnPlayback.start [ dying, paused, moved ] of
        Nothing ->
            [ "death focus playback did not start" ]

        Just animation ->
            let
                ( before, deathFrame ) =
                    TurnPlayback.tick 1399 animation

                ( after, clearedFrame ) =
                    TurnPlayback.tick 1400 animation
            in
            expect "concealed resources still permit a public death marker" (Unit.isDying dead)
                ++ expect "death focus holds the survivor still for the full pause" (deathFrame.units == [ dead, survivor ] && List.isEmpty (TurnPlayback.movingPositions before))
                ++ expect "completed deaths clear before subsequent movement" (List.map .id clearedFrame.units == [ second ] && List.map Unit.mapPosition clearedFrame.units == [ Unit.mapPosition survivor ] && clearedFrame.visibleTiles == paused.visibleTiles)
                ++ expect "surviving units resume their movement after death focus" (List.map .unitId (TurnPlayback.movingPositions after) == [ second ])
                ++ expect "carrier passengers inherit the carrier's loss cause"
                    (TurnPlayback.losses
                        (animation
                            |> setPlaybackCurrent
                                (dying
                                    |> TurnPlayback.setFrameUnits
                                        [ dead
                                        , survivor
                                            |> Unit.setDestroyed True
                                            |> Unit.setLocation (Location.Aboard first)
                                        ]
                                )
                        )
                        |> List.map .cause
                        |> (==) [ TurnPlayback.SuppliesExhausted, TurnPlayback.CarrierLost dead TurnPlayback.SuppliesExhausted ]
                    )
                ++ expect "loss dialogs never invent hidden casualties"
                    (List.isEmpty
                        (TurnPlayback.losses
                            (animation
                                |> setPlaybackCurrent
                                    (dying
                                        |> TurnPlayback.setFrameUnits
                                            [ survivor ]
                                    )
                            )
                        )
                    )


combatTheaterChecks : List String
combatTheaterChecks =
    let
        health : Int -> Int -> CombatHealth
        health before after =
            { before = { current = before, maximum = 16 }
            , after = { current = after, maximum = 16 }
            }

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]

        counts : List Int
        counts =
            List.map (CombatFormation.figureCount Kind.Tank) (List.range 0 16)

        themes : List MapTheme.MapTheme
        themes =
            [ MapTheme.GreenForest, MapTheme.Snow, MapTheme.Desert ]

        paths : MapTheme.MapTheme -> List String
        paths theme =
            List.map (CombatTheater.backdropPath theme) [ Terrain.Forest, Terrain.Hills, Terrain.Plain ]

        names : List String
        names =
            [ "forest", "hills", "plains", "snowy-forest", "snowy-hills", "tundra-plains", "desert-forest", "desert-hills", "desert-plains" ]

        expectedPaths : List String
        expectedPaths =
            List.map (\name -> "/assets/combat-backdrops-anime-v1/" ++ name ++ ".png") names
    in
    List.concat
        [ expect "theater figures each represent a quarter of health, including partially intact quarters"
            (counts == [ 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4 ])
        , expect "infantry has eight two-HP figures, retaining partially intact figures"
            (List.map (CombatFormation.figureCount Kind.Infantry) (List.range 0 16)
                == [ 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8 ]
            )
        , expect "infantry loses one figure per two HP and staggers all eight lethal impacts"
            (CombatFormation.impactStarts Kind.Infantry (health 16 14)
                == [ 1200 ]
                && CombatFormation.impactStarts Kind.Infantry (health 16 0)
                == [ 1200, 1320, 1440, 1560, 1680, 1800, 1920, 2040 ]
                && CombatFormation.impactStarts Kind.Infantry (health 16 15)
                == [ 1200 ]
                && List.isEmpty (CombatFormation.impactStarts Kind.Infantry (health 16 16))
            )
        , expect "eight infantry losses, shake, and automatic-close delay fit the panel clock"
            (CombatFormation.lossStartsAt { surviving = 0, index = 7 } + 20 + 160 + 500 <= 3000)
        , expect "an 8-damage hit on a full unit destroys two figures"
            (CombatFormation.figureCount Kind.Tank 16 - CombatFormation.figureCount Kind.Tank 8 == 2)
        , expect "casualties wait until the card opens and the viewer has a one-second beat"
            (CombatFormation.lossStartsAt { surviving = 2, index = 2 } == 1200)
        , expect "the casualty disappears beneath the impact before the shockwave clears"
            (CombatExplosion.spriteOpacity 20 == 1 && CombatExplosion.spriteOpacity CombatExplosion.spriteDisappearsAt == 0 && CombatExplosion.durationMs > CombatExplosion.spriteDisappearsAt)
        , expect "rumble follows staggered casualties and nonlethal hits, never undamaged figures"
            (CombatFormation.impactStarts Kind.Tank (health 16 8) == [ 1200, 1320 ] && CombatFormation.impactStarts Kind.Tank (health 16 14) == [ 1200 ] && List.isEmpty (CombatFormation.impactStarts Kind.Tank (health 16 16)))
        , expect "all nine theater backdrops follow terrain and visual theme"
            (List.concatMap paths themes == expectedPaths)
        , expect "a full formation's four losses finish before the panel clock caps at 2000ms"
            (CombatFormation.lossStartsAt { surviving = 0, index = 3 } + CombatExplosion.durationMs <= 2000)
        , expect "tank flash precedes recoil by 30ms, then recovery holds the final ready drawing"
            (List.map (CombatAttack.frameAt Kind.Tank) [ -1, 0, 29, 30, 89, 90, 179, 180, 299, 300, 439, 440, 619, 620, 6000 ]
                == [ 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7 ]
            )
        , expect "four tanks fire 90ms apart and finish recovery before any incoming hit"
            (CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.Tank 4
                == 2090
                && CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.Tank 1
                == 1820
                && CombatAttack.firingTimes (CombatAttack.Attacking { startsAt = 1200 }) Kind.Tank 4
                == [ 1200, 1290, 1380, 1470 ]
                && CombatAttack.endsAt CombatAttack.NotAttacking Kind.Tank 4
                == 0
                && CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.Tank 0
                == 0
            )
        , expect "units without firing artwork keep their existing timeline"
            (CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.Infantry 8
                == 0
                && CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.Truck 4
                == 0
            )
        , expect "field-gun crews signal, brace, fire, recoil, recover once, and hold the final drawing"
            (List.map (CombatAttack.frameAt Kind.FieldGun) [ -1, 0, 219, 220, 319, 320, 389, 390, 499, 500, 659, 660, 839, 840, 6000 ]
                == [ 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7 ]
            )
        , expect "field-gun flash timestamps follow the 320ms crew preparation and 90ms figure stagger"
            (CombatAttack.firingTimes (CombatAttack.Attacking { startsAt = 1200 }) Kind.FieldGun 4
                == [ 1520, 1610, 1700, 1790 ]
                && List.isEmpty (CombatAttack.firingTimes CombatAttack.NotAttacking Kind.FieldGun 4)
            )
        , expect "field-gun formations finish after every crew recovers, using their before-health figure count"
            (CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.FieldGun 4
                == 2310
                && CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.FieldGun 1
                == 2040
                && CombatAttack.endsAt CombatAttack.NotAttacking Kind.FieldGun 4
                == 0
                && CombatAttack.endsAt (CombatAttack.Attacking { startsAt = 1200 }) Kind.FieldGun 0
                == 0
            )
        ]


lossDetailsChecks : UnitId -> UnitId -> List String
lossDetailsChecks first second =
    let
        casualty : Unit
        casualty =
            { id = first
            , playerNumber = PlayerNumber.Player1
            , kind = Kind.Infantry
            , direction = Nothing
            , entrenchment = Entrenchment.Exposed
            , spriteFacing = SpriteFacing.Right
            , resources = Nothing
            , cargoCapacity = 0
            , destroyed = True
            , combatState = Nothing
            , combatRules =
                { range = 1
                , indirectRange = 0
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
                , digInCost = 64
                , shotCost = 2
                }
            , location = Location.OnMap { x = 0, y = 0 }
            }

        attacker : Unit
        attacker =
            casualty
                |> Unit.setId second
                |> Unit.setPlayerNumber PlayerNumber.Player2
                |> Unit.setDestroyed False

        carrier : Unit
        carrier =
            casualty
                |> Unit.setId second
                |> Unit.setKind Kind.Truck

        ownerName : Unit -> Maybe String
        ownerName unit =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    Just "Alice"

                PlayerNumber.Player2 ->
                    Just "Bob"

        missingOwner : Unit -> Maybe String
        missingOwner unit =
            if unit.id == second then
                Nothing

            else
                ownerName unit

        missingAttackerOwner : Unit -> Maybe String
        missingAttackerOwner unit =
            if unit.playerNumber == PlayerNumber.Player2 then
                Nothing

            else
                ownerName unit

        resolve : (Unit -> Maybe String) -> TurnPlayback.LossCause -> Result UnitLoss.DetailsError UnitLoss.Details
        resolve lookup cause =
            UnitLoss.resolve lookup { unit = casualty, cause = cause }

        missing : UnitLoss.DetailsError
        missing =
            UnitLoss.OwnerNotFound { unitId = second, playerNumber = PlayerNumber.Player2 }

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]
    in
    List.concat
        [ expect "loss details preserve the casualty's owner and exhaustion cause"
            (resolve ownerName TurnPlayback.SuppliesExhausted == Ok { ownerName = "Alice", cause = LossCause.SuppliesExhausted })
        , expect "loss details preserve attacker ownership and attack kind"
            (resolve ownerName (TurnPlayback.Destroyed CombatKind.AttackMove attacker)
                == Ok { ownerName = "Alice", cause = LossCause.Destroyed CombatKind.AttackMove { unit = attacker, ownerName = "Bob" } }
            )
        , expect "concealed artillery loss details require no attacker owner or portrait"
            (resolve missingAttackerOwner TurnPlayback.ConcealedIndirectFire == Ok { ownerName = "Alice", cause = LossCause.ConcealedIndirectFire })
        , expect "missing casualty owner retains unit ID and player number"
            (resolve (always Nothing) TurnPlayback.SuppliesExhausted
                == Err (UnitLoss.OwnerNotFound { unitId = first, playerNumber = PlayerNumber.Player1 })
            )
        , expect "missing attacker owner retains unit ID and player number"
            (resolve missingOwner (TurnPlayback.Destroyed CombatKind.Ambush attacker) == Err missing)
        , expect "missing carrier owner fails the entire loss notice"
            (resolve missingOwner (TurnPlayback.CarrierLost carrier TurnPlayback.SuppliesExhausted)
                == Err (UnitLoss.OwnerNotFound { unitId = second, playerNumber = PlayerNumber.Player1 })
            )
        , expect "nested carrier cause propagates a missing attacker owner"
            (resolve missingAttackerOwner
                (TurnPlayback.CarrierLost carrier (TurnPlayback.Destroyed CombatKind.Ambush attacker))
                == Err missing
            )
        , expect "nested carrier loss preserves both owner names"
            (resolve ownerName (TurnPlayback.CarrierLost carrier (TurnPlayback.Destroyed CombatKind.Ambush attacker))
                == Ok
                    { ownerName = "Alice"
                    , cause =
                        LossCause.CarrierLost { unit = carrier, ownerName = "Alice" }
                            (LossCause.Destroyed CombatKind.Ambush { unit = attacker, ownerName = "Bob" })
                    }
            )
        ]


carrierLossEventChecks : UnitId -> UnitId -> List String
carrierLossEventChecks first second =
    case ( UnitId.parse "3", UnitId.parse "4" ) of
        ( Ok third, Ok fourth ) ->
            let
                truck : Unit
                truck =
                    { id = first
                    , playerNumber = PlayerNumber.Player2
                    , entrenchment = Entrenchment.Exposed
                    , spriteFacing = SpriteFacing.Left
                    , direction = Nothing
                    , kind = Kind.Truck
                    , destroyed = True
                    , combatState = Nothing
                    , combatRules =
                        { range = 0
                        , indirectRange = 0
                        , shape = AmbushShape.Line
                        , damage = 0
                        , readinessCost = 0
                        , digInCost = 64
                        , shotCost = 0
                        }
                    , cargoCapacity = 2
                    , location = Location.OnMap { x = 2, y = 2 }
                    , resources = Nothing
                    }

                passenger : Unit
                passenger =
                    truck
                        |> Unit.setId second
                        |> Unit.setKind Kind.Infantry
                        |> Unit.setCargoCapacity 0
                        |> Unit.setLocation (Location.Aboard first)

                otherPassenger : Unit
                otherPassenger =
                    passenger
                        |> Unit.setId third

                independent : Unit
                independent =
                    passenger
                        |> Unit.setId fourth
                        |> Unit.setOnMap { x = 3, y = 2 }

                frame : TurnPlayback.Frame
                frame =
                    { units = [ passenger, independent, truck, otherPassenger ]
                    , durationMs = 1400
                    , departures = []
                    , sabotages = []
                    , indirectImpacts = []
                    , shots = []
                    , visibleTiles = [ { x = 2, y = 2 }, { x = 3, y = 2 } ]
                    , depots = []
                    , supplyCrates = []
                    }

                animation : TurnPlayback.Playback
                animation =
                    { current = frame
                    , remaining =
                        [ frame
                            |> TurnPlayback.setFrameUnits []
                        ]
                    , elapsed = 0
                    , presentation = TurnPlayback.Battlefield
                    , acknowledgedLosses = []
                    }

                shot : Shot
                shot =
                    { kind = CombatKind.AttackMove
                    , origin = { x = 1, y = 2 }
                    , destination = { x = 2, y = 2 }
                    , attacker =
                        independent
                            |> Unit.setDestroyed False
                            |> Unit.setPlayerNumber PlayerNumber.Player1
                    , target = truck
                    , damage = 16
                    , attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }
                    , targetHealth = { before = { current = 16, maximum = 16 }, after = { current = 0, maximum = 16 } }
                    }

                combatAnimation : TurnPlayback.Playback
                combatAnimation =
                    animation
                        |> setPlaybackCurrent
                            (frame
                                |> TurnPlayback.setFrameShots
                                    [ shot ]
                            )

                exhaustionTheater : Maybe TurnPlayback.Playback
                exhaustionTheater =
                    TurnPlayback.start
                        [ frame |> TurnPlayback.setFrameUnits (List.map (Unit.setDestroyed False) frame.units)
                        , frame
                        , frame |> TurnPlayback.setFrameUnits []
                        ]
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 1400 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 300 >> Tuple.first)

                afterIndependent : Maybe TurnPlayback.Playback
                afterIndependent =
                    exhaustionTheater
                        |> Maybe.andThen TurnPlayback.continueCombat
                        |> Maybe.map .animation
                        |> Maybe.map (TurnPlayback.acknowledgeLoss fourth)
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 1400 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tickUntilLoss 300 >> Tuple.first)

                acknowledged : TurnPlayback.Playback
                acknowledged =
                    TurnPlayback.acknowledgeLoss first animation

                expect : String -> Bool -> List String
                expect label passed =
                    if passed then
                        []

                    else
                        [ label ]
            in
            List.concat
                [ expect "simultaneous exhaustion queues independent units without passenger theaters"
                    ((exhaustionTheater |> Maybe.andThen TurnPlayback.activeEncounter)
                        == Just (TurnPlayback.Exhaustion (Unit.setDestroyed False independent))
                        && (afterIndependent |> Maybe.andThen TurnPlayback.activeEncounter)
                        == Just (TurnPlayback.Exhaustion (Unit.setDestroyed False truck))
                    )
                , expect "a truck and two passengers form one event even when passengers precede the truck"
                    (TurnPlayback.lossEvent animation == Just { loss = { unit = truck, cause = TurnPlayback.SuppliesExhausted }, passengers = [ passenger, otherPassenger ] })
                , expect "the grouped event preserves the lethal attack and attacker"
                    (TurnPlayback.lossEvent combatAnimation |> Maybe.map (.loss >> .cause) |> (==) (Just (TurnPlayback.Destroyed CombatKind.AttackMove shot.attacker)))
                , expect "combat carrier acknowledgment covers both passengers"
                    (List.map (.unit >> .id) (TurnPlayback.losses (TurnPlayback.acknowledgeLoss first combatAnimation)) == [ fourth ])
                , expect "continuing acknowledges the truck and both passengers together"
                    (List.map (.unit >> .id) (TurnPlayback.losses acknowledged) == [ fourth ])
                , expect "an unrelated simultaneous casualty still has its own dialog"
                    (TurnPlayback.lossEvent acknowledged == Just { loss = { unit = independent, cause = TurnPlayback.SuppliesExhausted }, passengers = [] })
                , expect "one continuation releases playback when only the carrier event remains"
                    (Tuple.first (TurnPlayback.tickUntilLoss 60000 (TurnPlayback.acknowledgeLoss fourth acknowledged)) == Nothing)
                , expect "concealed passengers are never added to the event"
                    (TurnPlayback.lossEvent
                        (animation
                            |> setPlaybackCurrent
                                (frame
                                    |> TurnPlayback.setFrameUnits
                                        [ truck ]
                                )
                        )
                        == Just { loss = { unit = truck, cause = TurnPlayback.SuppliesExhausted }, passengers = [] }
                    )
                ]

        _ ->
            [ "could not construct carrier loss fixture IDs" ]


cameraChecks : List String
cameraChecks =
    let
        map : Map.Map
        map =
            Map.fromFeatures { width = 17, height = 17, baseTile = Terrain.Plain, theme = MapTheme.GreenForest, features = [] }

        viewport : Camera.Viewport
        viewport =
            { size =
                { x = 1000
                , y = 600
                }
            , bottomInset = 0
            , rightInset = 0
            }

        withControls : Camera.Viewport
        withControls =
            { viewport | bottomInset = 150 }

        withInspector : Camera.Viewport
        withInspector =
            { viewport
                | rightInset = 248
            }

        overview : Camera.Camera
        overview =
            { offset = { x = 0, y = 0 }, zoom = 1 }

        zoomed : Camera.Camera
        zoomed =
            { overview | zoom = 3 }

        offscreen : List Point
        offscreen =
            [ { x = 16, y = 0 } ]

        panned : Camera.Camera
        panned =
            Camera.frame viewport map offscreen zoomed

        group : List Point
        group =
            [ { x = 0, y = 0 }, { x = 16, y = 16 } ]

        fitted : Camera.Camera
        fitted =
            Camera.frame viewport map group zoomed

        southernUnit : List Point
        southernUnit =
            [ { x = 8, y = 16 } ]

        aboveControls : Camera.Camera
        aboveControls =
            Camera.frame withControls map southernUnit overview

        fittedAboveControls : Camera.Camera
        fittedAboveControls =
            Camera.frame withControls map group zoomed

        besideInspector : Camera.Camera
        besideInspector =
            Camera.frame withInspector map offscreen zoomed

        fittedBesideInspector : Camera.Camera
        fittedBesideInspector =
            Camera.frame withInspector map group zoomed

        narrowViewport : Camera.Viewport
        narrowViewport =
            { size =
                { x = 320
                , y = 900
                }
            , bottomInset = 340
            , rightInset = 144
            }

        narrowFit : Camera.Camera
        narrowFit =
            Camera.frame narrowViewport map group zoomed

        tilesClearPanels : Camera.Viewport -> List Point -> Camera.Camera -> Bool
        tilesClearPanels view positions camera =
            let
                tilePixels : Float
                tilePixels =
                    min (0.92 * view.size.x) (0.98 * view.size.y) * camera.zoom / 17

                tileIsClear : Point -> Bool
                tileIsClear position =
                    let
                        left : Float
                        left =
                            view.size.x / 2 + camera.offset.x + (position.x - 8.5) * tilePixels

                        top : Float
                        top =
                            view.size.y / 2 + camera.offset.y + (position.y - 8.5) * tilePixels
                    in
                    (left >= 0)
                        && (left + tilePixels <= view.size.x - view.rightInset)
                        && (top >= 0)
                        && (top + tilePixels <= view.size.y - view.bottomInset)
            in
            List.all tileIsClear positions

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ expect "overview stays fixed as subjects switch between opposite map corners"
            (Camera.frame viewport map group overview == overview)
        , expect "visible unit does not recenter a zoomed view"
            (Camera.frame viewport map [ { x = 9, y = 8 } ] zoomed == zoomed)
        , expect "offscreen unit triggers a pan without unnecessary zoom"
            (panned.offset /= zoomed.offset && panned.zoom == zoomed.zoom)
        , expect "new visible subject retains the previous playback pan"
            (Camera.frame viewport map [ { x = 15, y = 1 } ] panned == panned)
        , expect "idle frames retain the last camera"
            (Camera.frame viewport map [] panned == panned)
        , expect "distant simultaneous subjects fit together without repeated reframing"
            (fitted.zoom < zoomed.zoom && Camera.frame viewport map group fitted == fitted)
        , expect "narrow viewport uses its horizontal bounds"
            (Camera.frame
                { size =
                    { x = 320
                    , y = 900
                    }
                , bottomInset = 0
                , rightInset = 0
                }
                map
                group
                zoomed
                /= zoomed
            )
        , expect "a southern tile covered by controls pans into the clear area without changing zoom"
            (not (tilesClearPanels withControls southernUnit overview)
                && tilesClearPanels withControls southernUnit aboveControls
                && (aboveControls.zoom == overview.zoom)
            )
        , expect "an unobscured tile retains the view with controls present"
            (Camera.frame withControls map [ { x = 8, y = 8 } ] overview == overview)
        , expect "a pan above controls settles without repeated reframing"
            (Camera.frame withControls map southernUnit aboveControls == aboveControls)
        , expect "simultaneous subjects fit above the controls and beside the right panel"
            (tilesClearPanels withControls group fittedAboveControls
                && (Camera.frame withControls map group fittedAboveControls == fittedAboveControls)
            )
        , expect "wrapped controls and a narrow battlefield keep every subject clear of both panels"
            (tilesClearPanels narrowViewport group narrowFit
                && (Camera.frame narrowViewport map group narrowFit == narrowFit)
            )
        , expect "an eastern subject pans clear of the inspector without unnecessary zoom"
            (tilesClearPanels withInspector offscreen besideInspector
                && (besideInspector.zoom == zoomed.zoom)
                && (Camera.frame withInspector map offscreen besideInspector == besideInspector)
            )
        , expect "simultaneous subjects fit beside the inspector and keep the full viewport coordinate system"
            (tilesClearPanels withInspector group fittedBesideInspector
                && (Camera.frame withInspector map group fittedBesideInspector == fittedBesideInspector)
            )
        ]
