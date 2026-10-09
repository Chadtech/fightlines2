module AnimationFrame exposing (Frame, first, next, unitColumn)

import UnitId exposing (UnitId)


type Frame
    = First
    | Second
    | Third
    | Fourth


first : Frame
first =
    First


next : Frame -> Frame
next frame =
    case frame of
        First ->
            Second

        Second ->
            Third

        Third ->
            Fourth

        Fourth ->
            First


frameColumn : Frame -> Int
frameColumn frame =
    case frame of
        First ->
            0

        Second ->
            1

        Third ->
            2

        Fourth ->
            3


unitColumn : Frame -> UnitId -> Int
unitColumn frame unitId =
    let
        phase : Int
        phase =
            UnitId.toString unitId
                |> String.toList
                |> List.foldl
                    (\character value ->
                        modBy 4 (value * 31 + Char.toCode character)
                    )
                    0
    in
    modBy 4 (frameColumn frame + phase)
