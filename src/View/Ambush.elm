module View.Ambush exposing (coverage, shots)

import Api.Enum.Direction exposing (Direction)
import Coordinate exposing (Coordinate)
import Direction
import Map exposing (Map)
import Shot exposing (Shot)
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA


coverage : Map -> Coordinate -> Direction -> Int -> Svg msg
coverage map origin facing range =
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

        positions : List Coordinate
        positions =
            List.range 1 range
                |> List.map positionAtDistance
                |> List.filter isOnMap

        tile : Coordinate -> Svg msg
        tile position =
            Svg.rect
                [ SA.x (String.fromInt (position.x * 16 + 1))
                , SA.y (String.fromInt (position.y * 16 + 1))
                , SA.width "14"
                , SA.height "14"
                , SA.fill S.yellow5Str
                , SA.fillOpacity "0.15"
                , SA.stroke S.yellow5Str
                , SA.strokeWidth "0.5"
                , SA.strokeDasharray "2 1"
                ]
                []
    in
    Svg.g
        [ SA.pointerEvents "none"
        ]
        (List.map tile positions)


shots : List Shot -> Svg msg
shots volley =
    let
        shot : Shot -> Svg msg
        shot fired =
            Svg.g
                []
                [ Svg.line
                    [ SA.x1 (String.fromInt (fired.origin.x * 16 + 8))
                    , SA.y1 (String.fromInt (fired.origin.y * 16 + 8))
                    , SA.x2 (String.fromInt (fired.destination.x * 16 + 8))
                    , SA.y2 (String.fromInt (fired.destination.y * 16 + 8))
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "1"
                    ]
                    []
                , Svg.text_
                    [ SA.x (String.fromInt (fired.destination.x * 16 + 8))
                    , SA.y (String.fromInt (fired.destination.y * 16 + 5))
                    , SA.textAnchor "middle"
                    , SA.fontSize "5"
                    , SA.fill S.yellow5Str
                    , SA.stroke S.gray0Str
                    , SA.strokeWidth "0.2"
                    ]
                    [ Svg.text ("−" ++ String.fromInt fired.damage)
                    ]
                ]
    in
    Svg.g
        [ SA.pointerEvents "none"
        ]
        (List.map shot volley)
