port module TurnChecks exposing (main)

import Api.Enum.Side as Side
import Api.Enum.Terrain as Terrain
import Api.Enum.TurnEventKind as EventKind
import Api.Enum.UnitKind as Kind
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
                [ { id = first, side = Side.West, kind = Kind.Infantry, position = { x = 1, y = 0 } }
                , { id = second, side = Side.East, kind = Kind.Infantry, position = { x = 1, y = 1 } }
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
                        [ { kind = EventKind.Move, unitId = first, path = [ { x = 0, y = 0 }, { x = 1, y = 0 } ] }
                        , { kind = EventKind.Move, unitId = second, path = [ { x = 2, y = 1 }, { x = 1, y = 1 } ] }
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
        , expect "animation never mutates authoritative cell positions mid-edge" (halfwayBoard == rewound)
        , expect "second event starts after the first finishes" (Turn.movingPosition next == Just { unitId = second, position = { x = 2, y = 1 } })
        , expect "playback ends at the resolved board" (finished == Nothing && finalBoard == board)
        ]
