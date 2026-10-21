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
                        [ marker purpose arrivalFrom destination ]

                    _ ->
                        []
        in
        Svg.polyline attributes [] :: endpoint


marker : Purpose -> Coordinate -> Coordinate -> Svg msg
marker purpose previous destination =
    let
        angle : String
        angle =
            if destination.x > previous.x then
                "0"

            else if destination.x < previous.x then
                "180"

            else if destination.y > previous.y then
                "90"

            else
                "270"

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
