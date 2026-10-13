port module TurnChecks exposing (main)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.CombatKind as CombatKind
import Api.Enum.Direction as Direction
import Api.Enum.MapTheme as MapTheme
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.Terrain as Terrain
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
import CombatHealth exposing (CombatHealth)
import Direction
import Platform
import Shot exposing (Shot)
import Turn
import TurnPlayback
import Unit exposing (Unit)
import Unit.Location as Location
import UnitId exposing (UnitId)
import UnitLoss
import View.CombatExplosion as CombatExplosion
import View.CombatFormation as CombatFormation
import View.CombatTheater as CombatTheater


port results : List String -> Cmd msg


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
            playbackChecks first second ++ truckPlaybackChecks first ++ transportPlaybackChecks first second ++ spriteFacingChecks first ++ deathPlaybackChecks first ++ deathFocusChecks first second ++ combatPlaybackChecks first second ++ combatDeathChecks first second ++ combatTheaterChecks ++ lossDetailsChecks first second

        _ ->
            [ "could not construct fixture IDs" ]


playbackChecks : UnitId -> UnitId -> List String
playbackChecks first second =
    let
        units : List Unit
        units =
            [ { destroyed = False
              , combatRules =
                    { range = 1
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = first
              , playerNumber = PlayerNumber.Player1
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
                            , movementPerTile = 1
                            }
                        , fuel = Nothing
                        }
              }
            , { destroyed = False
              , combatRules =
                    { range = 1
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = second
              , playerNumber = PlayerNumber.Player2
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
            , resolution =
                Just
                    { number = 1
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
            { rotationDirection = Just Direction.West, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Rotate, initialSpriteFacing = SpriteFacing.Right, initialDirection = Just Direction.East, unitId = first, path = [ { x = 1, y = 0 } ] }

        rotationSnapshot : Turn.Snapshot
        rotationSnapshot =
            { snapshot | resolution = Just { number = 1, events = [ rotation ] } }

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
            { firstFrame | units = List.filter (\unit -> unit.id == first) firstFrame.units }

        ( entering, _ ) =
            TurnPlayback.tick 90 { sharedPlayback | current = hiddenFrame }

        ( leaving, _ ) =
            TurnPlayback.tick 90 { sharedPlayback | remaining = [ { middleFrame | units = List.filter (\unit -> unit.id == first) lastFrame.units } ] }

        ( surplus, surplusFrame ) =
            TurnPlayback.tick 270 sharedPlayback

        ( timedHalfway, _ ) =
            TurnPlayback.tick 210 { sharedPlayback | remaining = [ { lastFrame | durationMs = 420 } ] }

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ expect "all simultaneous arrivals interpolate using server frame duration"
            (TurnPlayback.movingPositions timedHalfway == [ { unitId = first, position = { x = 0.5, y = 0 } }, { unitId = second, position = { x = 1.5, y = 1 } } ])
        , expect "only the first unit interpolates during its route"
            (TurnPlayback.movingPositions sharedHalfway == [ { unitId = first, position = { x = 0.5, y = 0 } } ])
        , expect "waiting unit preserves its facing during the first route"
            (List.map .direction sharedFrame.units == [ Just Direction.East, Just Direction.North ])
        , expect "fog changes only at shared tile boundaries"
            (sharedFrame.visibleTiles == firstFrame.visibleTiles && sharedFinal == lastFrame && sharedFinished == Nothing)
        , expect "entering and leaving sight never interpolate a hidden route"
            (List.map .unitId (TurnPlayback.movingPositions entering) == [ first ] && List.map .unitId (TurnPlayback.movingPositions leaving) == [ first ])
        , expect "shared playback carries surplus frame time forward"
            (Maybe.map .elapsed surplus == Just 90 && surplusFrame.visibleTiles == middleFrame.visibleTiles && TurnPlayback.movingPositions surplus == [ { unitId = second, position = { x = 1.5, y = 1 } } ])
        , expect "rotation rewinds facing and stays still until its event completes" (rotationPending /= Nothing && rotationHalfway == rotationUnits && Turn.movingPosition rotationPending == Nothing)
        , expect "rotation playback applies the chosen facing without moving" (rotationFinished == Nothing && List.map .direction rotatedUnits == [ Just Direction.West, Just Direction.West ] && List.map .location rotatedUnits == List.map .location units)
        , expect "rewind restores the event origins" (List.map Unit.boardPosition rewound == [ Just { x = 0, y = 0 }, Just { x = 2, y = 1 } ])
        , expect "halfway position interpolates the first unit only" (Turn.movingPosition halfway == Just { unitId = first, position = { x = 0.5, y = 0 } })
        , expect "animation never mutates authoritative cell positions mid-edge" (List.map Unit.boardPosition halfwayUnits == List.map Unit.boardPosition rewound)
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


truckPlaybackChecks : UnitId -> List String
truckPlaybackChecks unitId =
    let
        units : List Unit
        units =
            [ { destroyed = False
              , combatRules =
                    { range = 1
                    , shape = AmbushShape.Line
                    , damage = 4
                    , readinessCost = 2
                    , shotCost = 2
                    }
              , cargoCapacity = 0
              , id = unitId
              , playerNumber = PlayerNumber.Player1
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
                            , movementPerTile = 0
                            }
                        , fuel =
                            Just
                                { current = 15
                                , maximum = 64
                                }
                        }
              }
            ]

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , resolution = Just { number = 1, events = [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialSpriteFacing = SpriteFacing.Right, initialDirection = Nothing, unitId = unitId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ] } ] }
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
        truck : Unit.Unit
        truck =
            { id = truckId
            , playerNumber = PlayerNumber.Player1
            , spriteFacing = SpriteFacing.Right
            , kind = Kind.Truck
            , direction = Nothing
            , destroyed = False
            , combatRules =
                { range = 1
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
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
                        , movementPerTile = 0
                        }
                    , fuel =
                        Just
                            { current = 63
                            , maximum = 64
                            }
                    }
            }

        passenger : Unit.Unit
        passenger =
            { truck | id = passengerId, kind = Kind.Infantry, direction = Just Direction.East, destroyed = False, combatRules = { range = 1, shape = AmbushShape.Line, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.Aboard truckId, resources = Maybe.map (\resources -> { resources | fuel = Nothing }) truck.resources }

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
            , resolution =
                Just
                    { number = 1
                    , events =
                        [ { event | unitId = passengerId, kind = EventKind.Hold, path = [ { x = 1, y = 0 } ], initialSpriteFacing = SpriteFacing.Right, initialDirection = passenger.direction }
                        , event
                        , { event | unitId = passengerId, kind = EventKind.Load, path = [ { x = 1, y = 0 } ], carrierId = Just truckId, initialSpriteFacing = SpriteFacing.Right, initialDirection = passenger.direction }
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
            { loading | resolution = Just { number = 1, events = [ { event | kind = EventKind.Unload, unitId = passengerId, path = [ { x = 1, y = 0 }, { x = 2, y = 0 } ], initialCarrier = Just truckId, initialSpriteFacing = SpriteFacing.Right, initialDirection = passenger.direction } ] } }

        unloadUnits : List Unit
        unloadUnits =
            [ { passenger | location = Location.OnMap { x = 2, y = 0 } }, truck ]

        unloadRewound : List Unit
        unloadRewound =
            Turn.rewind unloading unloadUnits

        afterUnloading : List Unit
        afterUnloading =
            Turn.start unloading |> Maybe.map (\playback -> Turn.tick 180 playback unloadRewound |> Tuple.second) |> Maybe.withDefault unloadRewound

        riding : List Unit
        riding =
            Turn.tick 180 { events = [ event ], elapsed = 0 } [ passenger, { truck | location = Location.OnMap { x = 0, y = 0 } } ] |> Tuple.second

        ( sharedUnloading, sharedUnloadFrame ) =
            TurnPlayback.tick 90
                { current =
                    { depots = []
                    , supplyCrates = []
                    , shots = []
                    , durationMs = 180
                    , units = units
                    , visibleTiles = []
                    }
                , remaining =
                    [ { depots = []
                      , supplyCrates = []
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
            (TurnPlayback.movingPositions sharedUnloading == [ { unitId = passengerId, position = { x = 1.5, y = 0 } } ] && List.map Unit.boardPosition sharedUnloadFrame.units == [ Just { x = 1, y = 0 }, Just { x = 1, y = 0 } ])
        , transportExpect "loading rewind restores passengers to the board" (List.map Unit.carrierId rewound == [ Nothing, Nothing ])
        , transportExpect "load event attaches cargo after movement" (afterLoading == units)
        , transportExpect "riding passengers follow their truck" (riding == units)
        , transportExpect "unload rewind restores cargo" (unloadRewound == units)
        , transportExpect "unload event puts passenger on the board" (afterUnloading == unloadUnits)
        , transportExpect "passengers have no board position" (Unit.boardPosition passenger == Nothing)
        , transportExpect "riding position derives from the moved truck" (Unit.physicalPosition riding passenger == Just { x = 1, y = 0 })
        , transportExpect "missing carriers have no physical position" (Unit.physicalPosition [ passenger ] passenger == Nothing)
        , transportExpect "aboard carriers have no physical position" (Unit.physicalPosition [ passenger, { truck | location = Location.Aboard passengerId } ] passenger == Nothing)
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
            , spriteFacing = SpriteFacing.Right
            , direction = Just Direction.East
            , kind = Kind.Tank
            , destroyed = False
            , combatRules =
                { range = 1
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
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
                        , movementPerTile = 0
                        }
                    , fuel =
                        Just
                            { current = 64
                            , maximum = 64
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


combatPlaybackChecks : UnitId -> UnitId -> List String
combatPlaybackChecks first second =
    let
        attacker : Unit
        attacker =
            { id = first, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Just Direction.East, kind = Kind.Tank, destroyed = False, combatRules = { range = 1, shape = AmbushShape.Line, damage = 8, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Nothing }

        target : Unit
        target =
            { attacker | id = second, playerNumber = PlayerNumber.Player2, location = Location.OnMap { x = 3, y = 2 } }

        before : TurnPlayback.Frame
        before =
            { depots = []
            , supplyCrates = []
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
            { before | durationMs = 450, shots = [ shot, { shot | origin = shot.destination, destination = shot.origin, attacker = target, target = attacker } ], units = [ { attacker | destroyed = True }, { target | destroyed = True } ] }

        cleanup : TurnPlayback.Frame
        cleanup =
            { before | durationMs = 1400, units = [] }

        panelAt : { x : Int, y : Int } -> { x : Int, y : Int } -> TurnPlayback.Panel
        panelAt origin destination =
            { exchange =
                { kind = shot.kind
                , attacker = { attacker | location = Location.OnMap origin }
                , target = { target | location = Location.OnMap destination }
                , attackerHealth = shot.attackerHealth
                , targetHealth = shot.targetHealth
                }
            , elapsed = 0
            , mapView = TurnPlayback.CardVisible
            }

        readyAt : Float -> TurnPlayback.MapView -> Int -> Bool
        readyAt elapsed mapView remainingHealth =
            let
                panel : TurnPlayback.Panel
                panel =
                    panelAt shot.origin shot.destination

                exchange : TurnPlayback.Exchange
                exchange =
                    panel.exchange
            in
            CombatTheater.readyToAutomaticallyClose
                { panel
                    | elapsed = elapsed
                    , mapView = mapView
                    , exchange =
                        { exchange
                            | targetHealth =
                                { before = { current = 16, maximum = 16 }
                                , after = { current = remainingHealth, maximum = 16 }
                                }
                        }
                }

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]
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

                        ( holding, heldFrame ) =
                            showing |> Maybe.map (TurnPlayback.tick 60000) |> Maybe.withDefault ( Nothing, before )

                        ( resumed, hitFrame ) =
                            showing |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map (\next -> ( Just next.animation, next.frame )) |> Maybe.withDefault ( Nothing, before )

                        ( finished, finalFrame ) =
                            resumed |> Maybe.map (TurnPlayback.tick 1400) |> Maybe.withDefault ( Nothing, before )

                        hidden : TurnPlayback.Frame
                        hidden =
                            { volley | units = [ target ], shots = [ shot ] }

                        hiddenPlayback : Maybe TurnPlayback.Playback
                        hiddenPlayback =
                            TurnPlayback.start [ before, hidden, cleanup ] |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                        ( finalShot, _ ) =
                            TurnPlayback.start [ before, volley ] |> Maybe.map (TurnPlayback.tick 450) |> Maybe.withDefault ( Nothing, before )

                        multipleChecks : List String
                        multipleChecks =
                            case UnitId.parse "3" of
                                Err _ ->
                                    [ "could not construct third combat participant" ]

                                Ok third ->
                                    let
                                        anotherTarget : Unit
                                        anotherTarget =
                                            { target | id = third, location = Location.OnMap { x = 4, y = 2 } }

                                        multiple : TurnPlayback.Frame
                                        multiple =
                                            { volley | units = volley.units ++ [ anotherTarget ], shots = volley.shots ++ [ { shot | destination = { x = 4, y = 2 }, target = anotherTarget } ] }

                                        firstPause : Maybe TurnPlayback.Playback
                                        firstPause =
                                            TurnPlayback.start [ before, multiple, cleanup ] |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)

                                        secondPause : Maybe TurnPlayback.Playback
                                        secondPause =
                                            firstPause |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first) |> Maybe.andThen TurnPlayback.continueCombat |> Maybe.map .animation

                                        overlap : TurnPlayback.Frame
                                        overlap =
                                            { volley
                                                | shots =
                                                    [ shot
                                                    , { shot
                                                        | origin = { x = 4, y = 2 }
                                                        , attacker = anotherTarget
                                                        , targetHealth = { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } }
                                                      }
                                                    ]
                                            }

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
                    List.concat
                        [ expect "theater sides preserve horizontal map order and use north first for vertical pairs"
                            (CombatTheater.attackerOnLeft (panelAt { x = 2, y = 2 } { x = 3, y = 2 })
                                && not (CombatTheater.attackerOnLeft (panelAt { x = 3, y = 2 } { x = 2, y = 2 }))
                                && CombatTheater.attackerOnLeft (panelAt { x = 2, y = 2 } { x = 2, y = 3 })
                                && not (CombatTheater.attackerOnLeft (panelAt { x = 2, y = 3 } { x = 2, y = 2 }))
                            )
                        , expect "combat holds the pre-hit board and hides shots and movement"
                            (frozen == before && List.isEmpty (TurnPlayback.visibleShots focus) && List.isEmpty (TurnPlayback.movingPositions paused))
                        , expect "combat spotlights participants before opening the panels"
                            (Maybe.andThen TurnPlayback.spotlight almostSpotlit /= Nothing && Maybe.andThen TurnPlayback.panels almostSpotlit == Nothing && Maybe.andThen TurnPlayback.spotlight showing == Nothing && Maybe.andThen TurnPlayback.panels showing /= Nothing)
                        , expect "combat retains visible participants without requiring enemy resources"
                            (Maybe.map (.attacker >> .id) (TurnPlayback.combat focus) == Just first && Maybe.map (.target >> .id) (TurnPlayback.combat focus) == Just second)
                        , expect "automatic closing waits for two impacts, camera settling, and a half-second pause"
                            (not (readyAt 1999 TurnPlayback.CardVisible 8) && readyAt 2000 TurnPlayback.CardVisible 8)
                        , expect "automatic closing lets all four casualty animations finish"
                            (not (readyAt 2239 TurnPlayback.CardVisible 0) && readyAt 2240 TurnPlayback.CardVisible 0)
                        , expect "automatic closing waits while seeing the map"
                            (not (readyAt 2500 TurnPlayback.SeeingMap 0))
                        , expect "the panel clock can reach the automatic-close threshold"
                            (Maybe.andThen TurnPlayback.panels holding |> Maybe.map CombatTheater.readyToAutomaticallyClose |> (==) (Just True))
                        , expect "combat panels remain open indefinitely without revealing casualties"
                            (heldFrame == before && Maybe.map .exchange (Maybe.andThen TurnPlayback.panels holding) == Maybe.map .exchange (Maybe.andThen TurnPlayback.panels showing))
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


combatDeathChecks : UnitId -> UnitId -> List String
combatDeathChecks first second =
    case UnitId.parse "3" of
        Err _ ->
            [ "could not construct combat death fixture" ]

        Ok third ->
            let
                attacker : Unit
                attacker =
                    { id = first, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Just Direction.East, kind = Kind.Tank, destroyed = False, combatRules = { range = 1, shape = AmbushShape.Line, damage = 8, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Nothing }

                target : Unit
                target =
                    { attacker | id = second, playerNumber = PlayerNumber.Player2, location = Location.OnMap { x = 3, y = 2 } }

                other : Unit
                other =
                    { target | id = third, location = Location.OnMap { x = 2, y = 3 } }

                before : TurnPlayback.Frame
                before =
                    { units = [ attacker, target, other ], shots = [], durationMs = 0, visibleTiles = [ { x = 2, y = 2 }, { x = 3, y = 2 }, { x = 2, y = 3 } ], depots = [], supplyCrates = [] }

                lethalShot : Unit -> Shot
                lethalShot victim =
                    { kind = CombatKind.Ambush, origin = { x = 2, y = 2 }, destination = Unit.boardPosition victim |> Maybe.withDefault { x = 3, y = 2 }, attacker = attacker, target = victim, damage = 8, attackerHealth = { before = { current = 16, maximum = 16 }, after = { current = 16, maximum = 16 } }, targetHealth = { before = { current = 8, maximum = 16 }, after = { current = 0, maximum = 16 } } }

                volley : TurnPlayback.Frame
                volley =
                    { before | durationMs = 450, units = [ attacker, { target | destroyed = True }, { other | destroyed = True } ], shots = [ lethalShot target, lethalShot other ] }

                cleanup : TurnPlayback.Frame
                cleanup =
                    { before | durationMs = 1400, units = [ attacker ] }

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
                            { shot | kind = CombatKind.AttackMove }
                    in
                    TurnPlayback.losses { animation | current = { current | shots = List.map attackMoveShot current.shots } }
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
                    TurnPlayback.start [ before, { volley | shots = [ { reciprocal | origin = reciprocal.destination, destination = reciprocal.origin, attacker = attacker, target = target, attackerHealth = reciprocal.targetHealth, targetHealth = reciprocal.attackerHealth }, reciprocal ] }, cleanup ]
                        |> Maybe.andThen (TurnPlayback.tick 450 >> Tuple.first)
                        |> Maybe.andThen (TurnPlayback.tick 300 >> Tuple.first)
                        |> Maybe.andThen TurnPlayback.continueCombat

                expect : String -> Bool -> List String
                expect label passed =
                    if passed then
                        []

                    else
                        [ label ]
            in
            List.concat
                [ expect "loss dialog identifies the lethal shot and its attacker"
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
                    (Maybe.map (Tuple.second >> .units >> List.map .id) nextPair == Just [ first, third ] && (nextPair |> Maybe.andThen Tuple.first |> Maybe.andThen TurnPlayback.spotlight |> Maybe.map (.target >> .id)) == Just third)
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
            , spriteFacing = SpriteFacing.Right
            , direction = Just Direction.East
            , kind = Kind.Infantry
            , destroyed = False
            , combatRules =
                { range = 1
                , shape = AmbushShape.Line
                , damage = 4
                , readinessCost = 2
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
                        , movementPerTile = 1
                        }
                    , fuel = Nothing
                    }
            }

        dying : TurnPlayback.Frame
        dying =
            { depots = []
            , supplyCrates = []
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
            { dead | resources = Nothing }

        initial : TurnPlayback.Frame
        initial =
            { dying | units = [ alive ], durationMs = 0 }

        delayed : Maybe ( Maybe TurnPlayback.Playback, TurnPlayback.Frame )
        delayed =
            TurnPlayback.start [ initial, dying, gone ]
                |> Maybe.map (TurnPlayback.tickUntilLoss 60000)

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
        ++ expect "delayed ticks cannot skip a supply loss" (Maybe.map (Tuple.second >> .units) delayed == Just [ dead ])
        ++ expect "acknowledged supply death completes normally" (acknowledged == Nothing && List.isEmpty acknowledgedFrame.units)


deathFocusChecks : UnitId -> UnitId -> List String
deathFocusChecks first second =
    let
        dead : Unit
        dead =
            { id = first, playerNumber = PlayerNumber.Player2, spriteFacing = SpriteFacing.Left, direction = Just Direction.West, kind = Kind.Infantry, destroyed = True, combatRules = { range = 1, shape = AmbushShape.Line, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Nothing }

        survivor : Unit
        survivor =
            { dead | id = second, destroyed = False, location = Location.OnMap { x = 3, y = 2 } }

        dying : TurnPlayback.Frame
        dying =
            { depots = []
            , supplyCrates = []
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
            { dying | durationMs = 1400 }

        moved : TurnPlayback.Frame
        moved =
            { dying | durationMs = 180, units = [ dead, Unit.setOnMap { x = 4, y = 2 } survivor ] }

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
                ++ expect "completed deaths clear before subsequent movement" (List.map .id clearedFrame.units == [ second ] && List.map Unit.boardPosition clearedFrame.units == [ Unit.boardPosition survivor ] && clearedFrame.visibleTiles == paused.visibleTiles)
                ++ expect "surviving units resume their movement after death focus" (List.map .unitId (TurnPlayback.movingPositions after) == [ second ])
                ++ expect "carrier passengers inherit the carrier's loss cause"
                    (TurnPlayback.losses { animation | current = { dying | units = [ dead, { survivor | destroyed = True, location = Location.Aboard first } ] } }
                        |> List.map .cause
                        |> (==) [ TurnPlayback.SuppliesExhausted, TurnPlayback.CarrierLost dead TurnPlayback.SuppliesExhausted ]
                    )
                ++ expect "loss dialogs never invent hidden casualties"
                    (List.isEmpty (TurnPlayback.losses { animation | current = { dying | units = [ survivor ] } }))


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
            List.map CombatFormation.figureCount (List.range 0 16)

        themes : List MapTheme.MapTheme
        themes =
            [ MapTheme.GreenForest, MapTheme.Snow, MapTheme.Desert ]

        paths : MapTheme.MapTheme -> List String
        paths theme =
            List.map (CombatTheater.backdropPath theme) [ Terrain.Forest, Terrain.Hills, Terrain.GrassPlain ]

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
        , expect "an 8-damage hit on a full unit destroys two figures"
            (CombatFormation.figureCount 16 - CombatFormation.figureCount 8 == 2)
        , expect "casualties wait until the card opens and the viewer has a one-second beat"
            (CombatFormation.lossStartsAt { surviving = 2, index = 2 } == 1200)
        , expect "the casualty disappears beneath the impact before the shockwave clears"
            (CombatExplosion.spriteOpacity 20 == 1 && CombatExplosion.spriteOpacity CombatExplosion.spriteDisappearsAt == 0 && CombatExplosion.durationMs > CombatExplosion.spriteDisappearsAt)
        , expect "rumble follows staggered casualties and nonlethal hits, never undamaged figures"
            (CombatFormation.impactStarts (health 16 8) == [ 1200, 1320 ] && CombatFormation.impactStarts (health 16 14) == [ 1200 ] && List.isEmpty (CombatFormation.impactStarts (health 16 16)))
        , expect "all nine theater backdrops follow terrain and visual theme"
            (List.concatMap paths themes == expectedPaths)
        , expect "a full formation's four losses finish before the panel clock caps at 2000ms"
            (CombatFormation.lossStartsAt { surviving = 0, index = 3 } + CombatExplosion.durationMs <= 2000)
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
            , spriteFacing = SpriteFacing.Right
            , resources = Nothing
            , cargoCapacity = 0
            , destroyed = True
            , combatRules = { range = 1, shape = AmbushShape.Line, damage = 4, readinessCost = 2, shotCost = 2 }
            , location = Location.OnMap { x = 0, y = 0 }
            }

        attacker : Unit
        attacker =
            { casualty | id = second, playerNumber = PlayerNumber.Player2, destroyed = False }

        carrier : Unit
        carrier =
            { casualty | id = second, kind = Kind.Truck }

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
            UnitLoss.OwnerNotFound { unitId = second, side = PlayerNumber.Player2 }

        expect : String -> Bool -> List String
        expect label passed =
            if passed then
                []

            else
                [ label ]
    in
    List.concat
        [ expect "loss details preserve the casualty's owner and exhaustion cause"
            (resolve ownerName TurnPlayback.SuppliesExhausted == Ok { ownerName = "Alice", cause = UnitLoss.SuppliesExhausted })
        , expect "loss details preserve attacker ownership and attack kind"
            (resolve ownerName (TurnPlayback.Destroyed CombatKind.AttackMove attacker)
                == Ok { ownerName = "Alice", cause = UnitLoss.Destroyed CombatKind.AttackMove { unit = attacker, ownerName = "Bob" } }
            )
        , expect "missing casualty owner retains unit ID and side"
            (resolve (always Nothing) TurnPlayback.SuppliesExhausted
                == Err (UnitLoss.OwnerNotFound { unitId = first, side = PlayerNumber.Player1 })
            )
        , expect "missing attacker owner retains unit ID and side"
            (resolve missingOwner (TurnPlayback.Destroyed CombatKind.Ambush attacker) == Err missing)
        , expect "missing carrier owner fails the entire loss notice"
            (resolve missingOwner (TurnPlayback.CarrierLost carrier TurnPlayback.SuppliesExhausted)
                == Err (UnitLoss.OwnerNotFound { unitId = second, side = PlayerNumber.Player1 })
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
                        UnitLoss.CarrierLost { unit = carrier, ownerName = "Alice" }
                            (UnitLoss.Destroyed CombatKind.Ambush { unit = attacker, ownerName = "Bob" })
                    }
            )
        ]
