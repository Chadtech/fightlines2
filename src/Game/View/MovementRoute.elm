module Game.View.MovementRoute exposing (Purpose(..), planned, preview)

import Api.Enum.Direction exposing (Direction)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Direction as Direction
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as A


type Purpose
    = Travel
    | Attack
    | DirectedAttack Direction


planned : Purpose -> List Coordinate -> List (Svg msg)
planned purpose path =
    route purpose [ A.strokeDasharray "2 1", A.strokeWidth "1.25" ] path


preview : Purpose -> List Coordinate -> List (Svg msg)
preview purpose path =
    route purpose [ A.strokeWidth "1.5" ] path


color : Purpose -> String
color purpose =
    case purpose of
        Travel ->
            S.yellow5Str

        Attack ->
            S.red1Str

        DirectedAttack _ ->
            S.red1Str


point : Coordinate -> String
point position =
    String.fromInt (position.x * 16 + 8) ++ "," ++ String.fromInt (position.y * 16 + 8)


route : Purpose -> List (Svg.Attribute msg) -> List Coordinate -> List (Svg msg)
route purpose lineAttributes path =
    if List.length path < 2 then
        []

    else
        let
            advances : List (Svg msg)
            advances =
                case purpose of
                    Travel ->
                        []

                    _ ->
                        diagonalMarkers path

            attributes : List (Svg.Attribute msg)
            attributes =
                [ A.points (String.join " " (List.map point path))
                , A.fill "none"
                , A.stroke (color purpose)
                ]
                    ++ lineAttributes

            endpoint : List (Svg msg)
            endpoint =
                case List.reverse path of
                    destination :: previous :: _ ->
                        let
                            arrivalFrom : Coordinate
                            arrivalFrom =
                                case purpose of
                                    DirectedAttack direction ->
                                        let
                                            ahead : Coordinate
                                            ahead =
                                                Direction.step destination direction
                                        in
                                        { x = 2 * destination.x - ahead.x, y = 2 * destination.y - ahead.y }

                                    _ ->
                                        previous
                        in
                        [ marker purpose (bearing (delta arrivalFrom destination)) destination ]

                    _ ->
                        []
        in
        Svg.polyline attributes [] :: (advances ++ endpoint)


{-| Match the resolver's staircase rule using the submitted route's geometry.
-}
diagonalMarkers : List Coordinate -> List (Svg msg)
diagonalMarkers path =
    case path of
        from :: corner :: across :: onward :: _ ->
            let
                first : Coordinate
                first =
                    delta from corner

                second : Coordinate
                second =
                    delta corner across

                perpendicular : Bool
                perpendicular =
                    first.x * second.x + first.y * second.y == 0
            in
            if perpendicular && first == delta across onward then
                let
                    heading : Coordinate
                    heading =
                        { x = first.x + second.x, y = first.y + second.y }

                    remaining : List Coordinate
                    remaining =
                        afterStaircase first second path
                in
                marker Attack (bearing heading) corner :: diagonalMarkers remaining

            else
                diagonalMarkers (List.drop 1 path)

        _ ->
            []


afterStaircase : Coordinate -> Coordinate -> List Coordinate -> List Coordinate
afterStaircase next following path =
    case path of
        from :: to :: tail ->
            if delta from to == next then
                afterStaircase following next (to :: tail)

            else
                path

        _ ->
            path


delta : Coordinate -> Coordinate -> Coordinate
delta from to =
    { x = to.x - from.x, y = to.y - from.y }


bearing : Coordinate -> String
bearing direction =
    atan2 (toFloat direction.y) (toFloat direction.x)
        * 180
        / pi
        |> String.fromFloat


marker : Purpose -> String -> Coordinate -> Svg msg
marker purpose angle destination =
    let
        transform : String
        transform =
            "translate("
                ++ String.fromInt (destination.x * 16 + 8)
                ++ " "
                ++ String.fromInt (destination.y * 16 + 8)
                ++ ") rotate("
                ++ angle
                ++ ")"

        shape : Svg msg
        shape =
            case purpose of
                Travel ->
                    Svg.circle
                        [ A.r "2"
                        , A.fill (color purpose)
                        ]
                        []

                _ ->
                    Svg.polygon
                        [ A.points "3.5,0 -2.5,-3 -1.2,0 -2.5,3"
                        , A.fill (color purpose)
                        ]
                        []
    in
    Svg.g
        [ A.transform transform ]
        [ shape ]
