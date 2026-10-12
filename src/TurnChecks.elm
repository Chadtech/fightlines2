port module TurnChecks exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
import Direction
import Platform
import Turn
import TurnPlayback
import Unit exposing (Unit)
import Unit.Location as Location
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
            playbackChecks first second ++ truckPlaybackChecks first ++ transportPlaybackChecks first second ++ spriteFacingChecks first ++ deathPlaybackChecks first ++ deathFocusChecks first second

        _ ->
            [ "could not construct fixture IDs" ]


playbackChecks : UnitId -> UnitId -> List String
playbackChecks first second =
    let
        units : List Unit
        units =
            [ { destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, id = first, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Just Direction.East, kind = Kind.Infantry, location = Location.OnMap { x = 1, y = 0 }, resources = Just { hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing } }
            , { destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, id = second, playerNumber = PlayerNumber.Player2, spriteFacing = SpriteFacing.Left, direction = Just Direction.West, kind = Kind.Infantry, location = Location.OnMap { x = 1, y = 1 }, resources = Just { hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing } }
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
            { shots = []
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
            { shots = []
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
            { shots = []
            , durationMs = 180
            , units =
                List.map advanceFirstUnit rewound
            , visibleTiles = lastFrame.visibleTiles
            }

        sharedPlayback : TurnPlayback.Playback
        sharedPlayback =
            { current = firstFrame
            , remaining = [ middleFrame, lastFrame ]
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
            [ { destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, id = unitId, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Nothing, kind = Kind.Truck, location = Location.OnMap { x = 1, y = 1 }, resources = Just { hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }, fuel = Just { current = 15, maximum = 64 } } } ]

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
            { id = truckId, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, kind = Kind.Truck, direction = Nothing, destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 2, location = Location.OnMap { x = 1, y = 0 }, resources = Just { hitPoints = { current = 16, maximum = 16 }, supplies = { current = 62, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }, fuel = Just { current = 63, maximum = 64 } } }

        passenger : Unit.Unit
        passenger =
            { truck | id = passengerId, kind = Kind.Infantry, direction = Just Direction.East, destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.Aboard truckId, resources = Maybe.map (\resources -> { resources | fuel = Nothing }) truck.resources }

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
                { current = { shots = [], durationMs = 180, units = units, visibleTiles = [] }
                , remaining = [ { shots = [], durationMs = 180, units = unloadUnits, visibleTiles = [] } ]
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
            { id = id, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Just Direction.East, kind = Kind.Tank, destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Just { hitPoints = { current = 16, maximum = 16 }, supplies = { current = 64, maximum = 64, upkeepPerTurn = 1, movementPerTile = 0 }, fuel = Just { current = 64, maximum = 64 } } }

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
            { shots = [], durationMs = 180, units = [ unit ], visibleTiles = [] }

        playback : TurnPlayback.Playback
        playback =
            { current = frame tank, remaining = [ frame west, frame north, frame south ], elapsed = 0 }

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
            { id = id, playerNumber = PlayerNumber.Player1, spriteFacing = SpriteFacing.Right, direction = Just Direction.East, kind = Kind.Infantry, destroyed = False, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Just { hitPoints = { current = 0, maximum = 16 }, supplies = { current = 0, maximum = 64, upkeepPerTurn = 1, movementPerTile = 1 }, fuel = Nothing } }

        dying : TurnPlayback.Frame
        dying =
            { shots = [], durationMs = 180, units = [ dead ], visibleTiles = [ { x = 2, y = 2 } ] }

        gone : TurnPlayback.Frame
        gone =
            { shots = [], durationMs = 600, units = [], visibleTiles = [] }

        animation : TurnPlayback.Playback
        animation =
            { current = dying, remaining = [ gone ], elapsed = 0 }

        ( pending, beforeRemoval ) =
            TurnPlayback.tick 599 animation

        ( finished, afterRemoval ) =
            TurnPlayback.tick 600 animation
    in
    expect "dead units remain for the full death animation" (pending /= Nothing && beforeRemoval.units == [ dead ])
        ++ expect "dead units vanish at the server frame boundary" (finished == Nothing && List.isEmpty afterRemoval.units && List.isEmpty afterRemoval.visibleTiles)
        ++ expect "death does not interpolate a movement" (List.isEmpty (TurnPlayback.movingPositions (Just animation)))


deathFocusChecks : UnitId -> UnitId -> List String
deathFocusChecks first second =
    let
        dead : Unit
        dead =
            { id = first, playerNumber = PlayerNumber.Player2, spriteFacing = SpriteFacing.Left, direction = Just Direction.West, kind = Kind.Infantry, destroyed = True, combatRules = { range = 1, damage = 4, readinessCost = 2, shotCost = 2 }, cargoCapacity = 0, location = Location.OnMap { x = 2, y = 2 }, resources = Nothing }

        survivor : Unit
        survivor =
            { dead | id = second, destroyed = False, location = Location.OnMap { x = 3, y = 2 } }

        dying : TurnPlayback.Frame
        dying =
            { shots = [], durationMs = 450, units = [ dead, survivor ], visibleTiles = [ { x = 2, y = 2 }, { x = 3, y = 2 } ] }

        paused : TurnPlayback.Frame
        paused =
            { dying | durationMs = 600 }

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
                    TurnPlayback.tick 599 animation

                ( after, clearedFrame ) =
                    TurnPlayback.tick 600 animation
            in
            expect "concealed resources still permit a public death marker" (Unit.isDying dead)
                ++ expect "death focus holds the survivor still for the full pause" (deathFrame.units == [ dead, survivor ] && List.isEmpty (TurnPlayback.movingPositions before))
                ++ expect "completed deaths clear before subsequent movement" (List.map .id clearedFrame.units == [ second ] && List.map Unit.boardPosition clearedFrame.units == [ Unit.boardPosition survivor ] && clearedFrame.visibleTiles == paused.visibleTiles)
                ++ expect "surviving units resume their movement after death focus" (List.map .unitId (TurnPlayback.movingPositions after) == [ second ])
