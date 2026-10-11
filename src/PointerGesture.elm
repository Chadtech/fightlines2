module PointerGesture exposing
    ( PointerGesture
    , active
    , finish
    , idle
    , move
    , press
    , suppressesClick
    )

import Drag exposing (Drag)
import Point exposing (Point)


{-| A press becomes panning after six pixels. After panning ends, suppress the
browser's subsequent mouse click until another press or a viewport reset.
-}
type PointerGesture
    = Idle
    | Pressed Drag
    | Panning Drag
    | SuppressingClick


idle : PointerGesture
idle =
    Idle


press : { start : Point, origin : Point } -> PointerGesture
press points =
    Pressed (Drag.startAt points)


active : PointerGesture -> Bool
active gesture =
    case gesture of
        Pressed _ ->
            True

        Panning _ ->
            True

        Idle ->
            False

        SuppressingClick ->
            False


suppressesClick : PointerGesture -> Bool
suppressesClick gesture =
    case gesture of
        Panning _ ->
            True

        SuppressingClick ->
            True

        Idle ->
            False

        Pressed _ ->
            False


finish : PointerGesture -> PointerGesture
finish gesture =
    case gesture of
        Pressed _ ->
            Idle

        Panning _ ->
            SuppressingClick

        Idle ->
            Idle

        SuppressingClick ->
            SuppressingClick


move : Point -> PointerGesture -> { gesture : PointerGesture, offset : Maybe Point }
move point gesture =
    let
        pan : Drag -> { gesture : PointerGesture, offset : Maybe Point }
        pan drag =
            { gesture = Panning drag
            , offset =
                Just
                    { x = (Drag.origin drag).x + (point.x - (Drag.start drag).x)
                    , y = (Drag.origin drag).y + (point.y - (Drag.start drag).y)
                    }
            }
    in
    case gesture of
        Pressed drag ->
            let
                dx : Float
                dx =
                    point.x - (Drag.start drag).x

                dy : Float
                dy =
                    point.y - (Drag.start drag).y
            in
            if dx * dx + dy * dy >= 36 then
                pan drag

            else
                { gesture = gesture, offset = Nothing }

        Panning drag ->
            pan drag

        Idle ->
            { gesture = gesture, offset = Nothing }

        SuppressingClick ->
            { gesture = gesture, offset = Nothing }
