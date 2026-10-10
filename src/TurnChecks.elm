port module TurnChecks exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.MapTheme as MapTheme
import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
import Direction
import GameBoard exposing (GameBoard)
import Platform
import Turn
import TurnPlayback
import Unit exposing (Unit)
import UnitId exposing (UnitId)


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
            playbackChecks first second ++ truckPlaybackChecks first ++ transportPlaybackChecks first second

        _ ->
            [ "could not construct fixture IDs" ]


playbackChecks : UnitId -> UnitId -> List String
playbackChecks first second =
    let
        board : GameBoard
        board =
            { map = { width = 3, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }
            , depots = []
            , units =
                [ { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing, id = first, side = Side.Player1, direction = Just Direction.East, kind = Kind.Infantry, location = Unit.OnMap { x = 1, y = 0 } }
                , { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing, id = second, side = Side.Player2, direction = Just Direction.West, kind = Kind.Infantry, location = Unit.OnMap { x = 1, y = 1 } }
                ]
            }

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , resolution =
                Just
                    { number = 1
                    , events =
                        [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialDirection = Just Direction.South, unitId = first, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ] }
                        , { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialDirection = Just Direction.North, unitId = second, path = [ { x = 2, y = 1 }, { x = 1, y = 1 } ] }
                        ]
                    }
            }

        rewound : GameBoard
        rewound =
            Turn.rewind snapshot board

        initial : Turn.Playback
        initial =
            Turn.start snapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( halfway, halfwayBoard ) =
            Turn.tick 90 initial rewound

        ( next, firstFinished ) =
            Turn.tick 180 initial rewound

        ( finished, finalBoard ) =
            next |> Maybe.map (\playing -> Turn.tick 180 playing firstFinished) |> Maybe.withDefault ( Nothing, firstFinished )

        rotation : Turn.Event
        rotation =
            { rotationDirection = Just Direction.West, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Rotate, initialDirection = Just Direction.East, unitId = first, path = [ { x = 1, y = 0 } ] }

        rotationSnapshot : Turn.Snapshot
        rotationSnapshot =
            { snapshot | resolution = Just { number = 1, events = [ rotation ] } }

        rotationBoard : GameBoard
        rotationBoard =
            Turn.rewind rotationSnapshot board

        rotationPlayback : Turn.Playback
        rotationPlayback =
            Turn.start rotationSnapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( rotationPending, rotationHalfway ) =
            Turn.tick 90 rotationPlayback rotationBoard

        ( rotationFinished, rotatedBoard ) =
            Turn.tick 180 rotationPlayback rotationBoard

        cornerPath : List { x : Int, y : Int }
        cornerPath =
            [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ]

        cornerPlayback : Turn.Playback
        cornerPlayback =
            { events = [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, unitId = first, initialDirection = Just Direction.West, path = cornerPath } ]
            , elapsed = 0
            }

        ( _, cornerBoard ) =
            Turn.tick 180 cornerPlayback rewound

        ( cornerFinished, cornerFinalBoard ) =
            Turn.tick 360 cornerPlayback rewound

        firstFrame : TurnPlayback.Frame
        firstFrame =
            { units = rewound.units
            , visibleTiles =
                [ { x = 0
                  , y = 0
                  }
                ]
            }

        lastFrame : TurnPlayback.Frame
        lastFrame =
            { units = board.units
            , visibleTiles =
                [ { x = 1
                  , y = 0
                  }
                ]
            }

        advanceFirstUnit : Unit -> Unit
        advanceFirstUnit unit =
            if unit.id == first then
                List.head board.units |> Maybe.withDefault unit

            else
                unit

        middleFrame : TurnPlayback.Frame
        middleFrame =
            { units =
                List.map advanceFirstUnit rewound.units
            , visibleTiles = lastFrame.visibleTiles
            }

        sharedPlayback : TurnPlayback.Playback
        sharedPlayback =
            { current = firstFrame
            , remaining = [ middleFrame, lastFrame ]
            , elapsed = 0
            }

        ( sharedHalfway, sharedBoard ) =
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

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ expect "only the first unit interpolates during its route"
            (TurnPlayback.movingPositions sharedHalfway == [ { unitId = first, position = { x = 0.5, y = 0 } } ])
        , expect "waiting unit preserves its facing during the first route"
            (List.map .direction sharedBoard.units == [ Just Direction.East, Just Direction.North ])
        , expect "fog changes only at shared tile boundaries"
            (sharedBoard.visibleTiles == firstFrame.visibleTiles && sharedFinal == lastFrame && sharedFinished == Nothing)
        , expect "entering and leaving sight never interpolate a hidden route"
            (List.map .unitId (TurnPlayback.movingPositions entering) == [ first ] && List.map .unitId (TurnPlayback.movingPositions leaving) == [ first ])
        , expect "shared playback carries surplus frame time forward"
            (Maybe.map .elapsed surplus == Just 90 && surplusFrame.visibleTiles == middleFrame.visibleTiles && TurnPlayback.movingPositions surplus == [ { unitId = second, position = { x = 1.5, y = 1 } } ])
        , expect "rotation rewinds facing and stays still until its event completes" (rotationPending /= Nothing && rotationHalfway == rotationBoard && Turn.movingPosition rotationPending == Nothing)
        , expect "rotation playback applies the chosen facing without moving" (rotationFinished == Nothing && List.map .direction rotatedBoard.units == [ Just Direction.West, Just Direction.West ] && List.map .location rotatedBoard.units == List.map .location board.units)
        , expect "rewind restores the event origins" (List.map Unit.boardPosition rewound.units == [ Just { x = 0, y = 0 }, Just { x = 2, y = 1 } ])
        , expect "halfway position interpolates the first unit only" (Turn.movingPosition halfway == Just { unitId = first, position = { x = 0.5, y = 0 } })
        , expect "animation never mutates authoritative cell positions mid-edge" (List.map Unit.boardPosition halfwayBoard.units == List.map Unit.boardPosition rewound.units)
        , expect "second event starts after the first finishes" (Turn.movingPosition next == Just { unitId = second, position = { x = 2, y = 1 } })
        , expect "rewind restores initial facing" (List.map .direction rewound.units == [ Just Direction.South, Just Direction.North ])
        , expect "moving unit turns while waiting unit keeps its facing" (List.map .direction halfwayBoard.units == [ Just Direction.East, Just Direction.North ])
        , expect "turning a corner faces down during the second edge" (List.map .direction cornerBoard.units == [ Just Direction.South, Just Direction.North ])
        , expect "final facing follows the last edge" (cornerFinished == Nothing && List.map .direction cornerFinalBoard.units == [ Just Direction.South, Just Direction.North ])
        , expect "all cardinal path directions are supported"
            (List.map (\destination -> Direction.between { x = 1, y = 1 } destination)
                [ { x = 1, y = 0 }, { x = 2, y = 1 }, { x = 1, y = 2 }, { x = 0, y = 1 } ]
                == [ Just Direction.North, Just Direction.East, Just Direction.South, Just Direction.West ]
            )
        , expect "holding preserves facing" (Direction.alongPath [ { x = 1, y = 1 } ] (Just Direction.North) == Just Direction.North)
        , expect "playback ends at the resolved board" (finished == Nothing && finalBoard == board)
        ]


truckPlaybackChecks : UnitId -> List String
truckPlaybackChecks unitId =
    let
        board : GameBoard
        board =
            { map = { width = 3, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }
            , depots = []
            , units = [ { cargoCapacity = 0, hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }, fuel = Just { current = 15, maximum = 64 }, id = unitId, side = Side.Player1, direction = Nothing, kind = Kind.Truck, location = Unit.OnMap { x = 1, y = 1 } } ]
            }

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , resolution = Just { number = 1, events = [ { rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing, kind = EventKind.Move, initialDirection = Nothing, unitId = unitId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ] } ] }
            }

        rewound : GameBoard
        rewound =
            Turn.rewind snapshot board

        playback : Turn.Playback
        playback =
            Turn.start snapshot |> Maybe.withDefault { events = [], elapsed = 0 }

        ( _, moving ) =
            Turn.tick 180 playback rewound

        ( finished, finalBoard ) =
            Turn.tick 360 playback rewound

        hasNoDirection : GameBoard -> Bool
        hasNoDirection current =
            List.map .direction current.units == [ Nothing ]
    in
    if List.all hasNoDirection [ rewound, moving, finalBoard ] && finished == Nothing && finalBoard == board then
        []

    else
        [ "truck playback must move without acquiring a direction" ]


transportPlaybackChecks : UnitId -> UnitId -> List String
transportPlaybackChecks passengerId truckId =
    let
        truck : Unit.Unit
        truck =
            { id = truckId
            , side = Side.Player1
            , kind = Kind.Truck
            , direction = Nothing
            , hitPoints = { current = 16, maximum = 16 }
            , supplies = { current = 62, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }
            , fuel = Just { current = 63, maximum = 64 }
            , cargoCapacity = 2
            , location = Unit.OnMap { x = 1, y = 0 }
            }

        passenger : Unit.Unit
        passenger =
            { truck | id = passengerId, kind = Kind.Infantry, direction = Just Direction.East, fuel = Nothing, cargoCapacity = 0, location = Unit.Aboard truckId }

        board : GameBoard
        board =
            { map = { width = 3, height = 3, baseTile = Terrain.GrassPlain, theme = MapTheme.GreenForest, features = [] }, depots = [], units = [ passenger, truck ] }

        event : Turn.Event
        event =
            { kind = EventKind.Move, unitId = truckId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ], initialDirection = Nothing, rotationDirection = Nothing, initialCarrier = Nothing, carrierId = Nothing }

        loading : Turn.Snapshot
        loading =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , resolution =
                Just
                    { number = 1
                    , events =
                        [ { event | unitId = passengerId, kind = EventKind.Hold, path = [ { x = 1, y = 0 } ], initialDirection = passenger.direction }
                        , event
                        , { event | unitId = passengerId, kind = EventKind.Load, path = [ { x = 1, y = 0 } ], carrierId = Just truckId, initialDirection = passenger.direction }
                        ]
                    }
            }

        rewound : GameBoard
        rewound =
            Turn.rewind loading board

        afterMovement : GameBoard
        afterMovement =
            Turn.start loading |> Maybe.map (\playback -> Turn.tick 180 playback rewound |> Tuple.second) |> Maybe.withDefault rewound

        afterLoading : GameBoard
        afterLoading =
            Turn.start loading
                |> Maybe.andThen (\playback -> Turn.tick 180 playback rewound |> Tuple.first)
                |> Maybe.map (\playback -> Turn.tick 1 playback afterMovement |> Tuple.second)
                |> Maybe.withDefault afterMovement

        unloading : Turn.Snapshot
        unloading =
            { loading | resolution = Just { number = 1, events = [ { event | kind = EventKind.Unload, unitId = passengerId, path = [ { x = 1, y = 0 }, { x = 2, y = 0 } ], initialCarrier = Just truckId, initialDirection = passenger.direction } ] } }

        unloadBoard : GameBoard
        unloadBoard =
            { board | units = [ { passenger | location = Unit.OnMap { x = 2, y = 0 } }, truck ] }

        unloadRewound : GameBoard
        unloadRewound =
            Turn.rewind unloading unloadBoard

        afterUnloading : GameBoard
        afterUnloading =
            Turn.start unloading |> Maybe.map (\playback -> Turn.tick 180 playback unloadRewound |> Tuple.second) |> Maybe.withDefault unloadRewound

        riding : GameBoard
        riding =
            Turn.tick 180 { events = [ event ], elapsed = 0 } { board | units = [ passenger, { truck | location = Unit.OnMap { x = 0, y = 0 } } ] } |> Tuple.second

        ( sharedUnloading, sharedUnloadFrame ) =
            TurnPlayback.tick 90
                { current = { units = board.units, visibleTiles = [] }
                , remaining = [ { units = unloadBoard.units, visibleTiles = [] } ]
                , elapsed = 0
                }
    in
    List.concat
        [ transportExpect "shared unloading displays the passenger walking from its truck"
            (TurnPlayback.movingPositions sharedUnloading == [ { unitId = passengerId, position = { x = 1.5, y = 0 } } ] && List.map Unit.boardPosition sharedUnloadFrame.units == [ Just { x = 1, y = 0 }, Just { x = 1, y = 0 } ])
        , transportExpect "loading rewind restores passengers to the board" (List.map Unit.carrierId rewound.units == [ Nothing, Nothing ])
        , transportExpect "load event attaches cargo after movement" (afterLoading == board)
        , transportExpect "riding passengers follow their truck" (riding == board)
        , transportExpect "unload rewind restores cargo" (unloadRewound == board)
        , transportExpect "unload event puts passenger on the board" (afterUnloading == unloadBoard)
        , transportExpect "passengers have no board position" (Unit.boardPosition passenger == Nothing)
        , transportExpect "riding position derives from the moved truck" (Unit.physicalPosition riding.units passenger == Just { x = 1, y = 0 })
        , transportExpect "missing carriers have no physical position" (Unit.physicalPosition [ passenger ] passenger == Nothing)
        , transportExpect "aboard carriers have no physical position" (Unit.physicalPosition [ passenger, { truck | location = Unit.Aboard passengerId } ] passenger == Nothing)
        ]


transportExpect : String -> Bool -> List String
transportExpect name valid =
    if valid then
        []

    else
        [ name ]
