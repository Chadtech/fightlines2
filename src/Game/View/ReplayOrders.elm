module Game.View.ReplayOrders exposing (toSvg)

import Api.Enum.Direction as Direction exposing (Direction)
import Api.Enum.UnitOrderKind as OrderKind
import Game.CombatState as CombatState
import Game.Coordinate exposing (Coordinate)
import Game.RecordedOrder exposing (RecordedOrder)
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.MovementRoute as MovementRoute
import Html.Attributes as HA
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as A


toSvg : Maybe UnitId -> List RecordedOrder -> Svg msg
toSvg selected orders =
    Svg.g
        [ A.pointerEvents "none"
        , HA.attribute "data-replay-orders" (String.fromInt (List.length orders))
        ]
        (List.map (orderView selected) orders)


orderView : Maybe UnitId -> RecordedOrder -> Svg msg
orderView selected order =
    let
        opacity : String
        opacity =
            if (selected == Nothing) || (selected == Just order.unitId) then
                "1"

            else
                "0.35"

        purpose : MovementRoute.Purpose
        purpose =
            if order.kind == OrderKind.AttackMove then
                order.direction
                    |> Maybe.map MovementRoute.DirectedAttack
                    |> Maybe.withDefault MovementRoute.Attack

            else
                MovementRoute.Travel

        endpoint : List (Svg msg)
        endpoint =
            case List.reverse order.path |> List.head of
                Just destination ->
                    let
                        facing : List (Svg msg)
                        facing =
                            order.direction
                                |> Maybe.map (facingMarker destination >> List.singleton)
                                |> Maybe.withDefault []

                        stationaryLabel : List (Svg msg)
                        stationaryLabel =
                            if List.length order.path == 1 then
                                [ label destination (stationaryLabelText order) ]

                            else
                                []

                        unloading : List (Svg msg)
                        unloading =
                            List.concatMap unloadRoute order.unloads

                        unloadRoute : Coordinate -> List (Svg msg)
                        unloadRoute position =
                            MovementRoute.planned MovementRoute.Travel [ destination, position ]
                    in
                    stationaryLabel ++ facing ++ unloading

                Nothing ->
                    []

        target : List (Svg msg)
        target =
            order.target
                |> Maybe.map (\position -> [ label position "◎" ])
                |> Maybe.withDefault []

        content : List (Svg msg)
        content =
            MovementRoute.planned purpose order.path ++ endpoint ++ target ++ stopped

        stopped : List (Svg msg)
        stopped =
            order.stoppedAt |> Maybe.map (\position -> [ label position "stopped" ]) |> Maybe.withDefault []

        title : Svg msg
        title =
            Svg.title
                []
                [ Svg.text (UnitId.toString order.unitId ++ ": " ++ CombatState.orderLabel order.kind) ]
    in
    Svg.g
        [ A.opacity opacity
        , HA.attribute "data-order-unit" (UnitId.toString order.unitId)
        ]
        (title :: content)


label : Coordinate -> String -> Svg msg
label position text =
    Svg.text_
        [ A.x (String.fromInt (position.x * 16 + 8))
        , A.y (String.fromInt (position.y * 16 + 17))
        , A.textAnchor "middle"
        , A.fontSize "3.5"
        , A.fill S.yellow5Str
        , A.stroke S.gray0Str
        , A.strokeWidth "0.7"
        , HA.attribute "paint-order" "stroke"
        ]
        [ Svg.text text ]


stationaryLabelText : RecordedOrder -> String
stationaryLabelText order =
    case order.kind of
        OrderKind.Hold ->
            "hold"

        OrderKind.StandGround ->
            "stand"

        OrderKind.DigIn ->
            "dig in"

        _ ->
            CombatState.orderLabel order.kind


facingMarker : Coordinate -> Direction -> Svg msg
facingMarker position direction =
    let
        angle : String
        angle =
            case direction of
                Direction.East ->
                    "0"

                Direction.South ->
                    "90"

                Direction.West ->
                    "180"

                Direction.North ->
                    "270"
    in
    Svg.polygon
        [ A.points "8,0 4,-2.5 4,2.5"
        , A.transform ("translate(" ++ String.fromInt (position.x * 16 + 8) ++ " " ++ String.fromInt (position.y * 16 + 8) ++ ") rotate(" ++ angle ++ ")")
        , A.fill S.red1Str
        , A.stroke S.gray0Str
        , A.strokeWidth "0.5"
        ]
        []
