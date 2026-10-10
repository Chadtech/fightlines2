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
            playbackChecks first second

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
                [ { id = first, side = Side.West, direction = Direction.East, kind = Kind.Infantry, position = { x = 1, y = 0 } }
                , { id = second, side = Side.East, direction = Direction.West, kind = Kind.Infantry, position = { x = 1, y = 1 } }
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
                        [ { kind = EventKind.Move, initialDirection = Direction.South, unitId = first, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ] }
                        , { kind = EventKind.Move, initialDirection = Direction.North, unitId = second, path = [ { x = 2, y = 1 }, { x = 1, y = 1 } ] }
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
            { events = [ { kind = EventKind.Move, unitId = first, initialDirection = Direction.West, path = cornerPath } ]
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
        , expect "rewind restores initial facing" (List.map .direction rewound.units == [ Direction.South, Direction.North ])
        , expect "moving unit turns while waiting unit keeps its facing" (List.map .direction halfwayBoard.units == [ Direction.East, Direction.North ])
        , expect "turning a corner faces down during the second edge" (List.map .direction cornerBoard.units == [ Direction.South, Direction.North ])
        , expect "final facing follows the last edge" (cornerFinished == Nothing && List.map .direction cornerFinalBoard.units == [ Direction.South, Direction.North ])
        , expect "all cardinal path directions are supported"
            (List.map (\destination -> Direction.between { x = 1, y = 1 } destination)
                [ { x = 1, y = 0 }, { x = 2, y = 1 }, { x = 1, y = 2 }, { x = 0, y = 1 } ]
                == [ Just Direction.North, Just Direction.East, Just Direction.South, Just Direction.West ]
            )
        , expect "holding preserves facing" (Direction.alongPath [ { x = 1, y = 1 } ] Direction.North == Direction.North)
        , expect "playback ends at the resolved board" (finished == Nothing && finalBoard == board)
        ]
