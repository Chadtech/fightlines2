module View.Ambush exposing (coverage)

import Api.Enum.AmbushShape as AmbushShape
import Api.Enum.Direction as DirectionEnum exposing (Direction)
import CombatRules exposing (CombatRules)
import Coordinate exposing (Coordinate)
import Direction
import Map exposing (Map)
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA


coverage : Map -> Coordinate -> Direction -> CombatRules -> Svg msg
coverage map origin facing rules =
    let
        stepForward : Direction -> Coordinate -> Coordinate
        stepForward direction position =
            Direction.step position direction

        positionAtDistance : Int -> Coordinate
        positionAtDistance distance =
            List.repeat distance facing
                |> List.foldl stepForward origin

        isOnMap : Coordinate -> Bool
        isOnMap position =
            (position.x >= 0)
                && (position.y >= 0)
                && (position.x < map.width)
                && (position.y < map.height)

        line : List Coordinate
        line =
            List.range 1 rules.range
                |> List.map positionAtDistance

        center : Coordinate
        center =
            positionAtDistance ((rules.range + 1) // 2)

        arms : List Coordinate
        arms =
            case rules.shape of
                AmbushShape.Line ->
                    []

                AmbushShape.Cross ->
                    case facing of
                        DirectionEnum.North ->
                            [ Direction.step center DirectionEnum.West, Direction.step center DirectionEnum.East ]

                        DirectionEnum.South ->
                            [ Direction.step center DirectionEnum.West, Direction.step center DirectionEnum.East ]

                        DirectionEnum.East ->
                            [ Direction.step center DirectionEnum.North, Direction.step center DirectionEnum.South ]

                        DirectionEnum.West ->
                            [ Direction.step center DirectionEnum.North, Direction.step center DirectionEnum.South ]

        positions : List Coordinate
        positions =
            (line ++ arms)
                |> List.filter isOnMap

        tile : Coordinate -> Svg msg
        tile position =
            Svg.rect
                [ SA.x (String.fromInt (position.x * 16 + 1))
                , SA.y (String.fromInt (position.y * 16 + 1))
                , SA.width "14"
                , SA.height "14"
                , SA.fill S.red1Str
                , SA.fillOpacity "0.24"
                , SA.stroke S.red1Str
                , SA.strokeWidth "0.85"
                , SA.strokeDasharray "1 1"
                ]
                []
    in
    Svg.g
        [ SA.pointerEvents "none"
        ]
        (List.map tile positions)
