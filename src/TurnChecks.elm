port module TurnChecks exposing (main)

import Api.Enum.Direction as Direction
import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
import Direction
import GameBoard exposing (GameBoard)
import Platform
import Turn
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
            playbackChecks first second ++ truckPlaybackChecks first

        _ ->
            [ "could not construct fixture IDs" ]


playbackChecks : UnitId -> UnitId -> List String
playbackChecks first second =
    let
        board : GameBoard
        board =
            { map = { width = 3, height = 3, baseTile = Terrain.GrassPlain, features = [] }
            , depots = []
            , units =
                [ { fuel = Nothing, id = first, side = Side.West, direction = Just Direction.East, kind = Kind.Infantry, position = { x = 1, y = 0 } }
                , { fuel = Nothing, id = second, side = Side.East, direction = Just Direction.West, kind = Kind.Infantry, position = { x = 1, y = 1 } }
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
                        [ { kind = EventKind.Move, initialDirection = Just Direction.South, unitId = first, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ] }
                        , { kind = EventKind.Move, initialDirection = Just Direction.North, unitId = second, path = [ { x = 2, y = 1 }, { x = 1, y = 1 } ] }
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

        cornerPath : List { x : Int, y : Int }
        cornerPath =
            [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ]

        cornerPlayback : Turn.Playback
        cornerPlayback =
            { events = [ { kind = EventKind.Move, unitId = first, initialDirection = Just Direction.West, path = cornerPath } ]
            , elapsed = 0
            }

        ( _, cornerBoard ) =
            Turn.tick 180 cornerPlayback rewound

        ( cornerFinished, cornerFinalBoard ) =
            Turn.tick 360 cornerPlayback rewound

        expect : String -> Bool -> List String
        expect name passed =
            if passed then
                []

            else
                [ name ]
    in
    List.concat
        [ expect "rewind restores the event origins" (List.map .position rewound.units == [ { x = 0, y = 0 }, { x = 2, y = 1 } ])
        , expect "halfway position interpolates the first unit only" (Turn.movingPosition halfway == Just { unitId = first, position = { x = 0.5, y = 0 } })
        , expect "animation never mutates authoritative cell positions mid-edge" (List.map .position halfwayBoard.units == List.map .position rewound.units)
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
            { map = { width = 3, height = 3, baseTile = Terrain.GrassPlain, features = [] }
            , depots = []
            , units = [ { fuel = Just { current = 15, maximum = 16 }, id = unitId, side = Side.West, direction = Nothing, kind = Kind.SupplyTruck, position = { x = 1, y = 1 } } ]
            }

        snapshot : Turn.Snapshot
        snapshot =
            { number = 2
            , submitted = False
            , opponentSubmitted = False
            , resolution = Just { number = 1, events = [ { kind = EventKind.Move, initialDirection = Nothing, unitId = unitId, path = [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } ] } ] }
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
