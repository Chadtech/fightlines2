module View.UnitFacing exposing
    ( styles
    , toSvg
    )

import Api.Enum.Direction as Direction
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-unit-facing-pulse {
                0%, 12%, 100% { opacity: 0; }
                50%, 62% { opacity: 1; }
            }
            .fightlines-unit-facing {
                animation: fightlines-unit-facing-pulse 2s ease-in-out infinite;
            }
            .fightlines-rotation-preview .fightlines-unit-facing {
                animation: none; opacity: 1;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-unit-facing { animation: none; opacity: 1; }
            }
        """
        ]


toSvg : Bool -> Unit -> Svg msg
toSvg selected unit =
    case unit.direction of
        Nothing ->
            Svg.g [] []

        Just direction ->
            marker selected direction


marker : Bool -> Direction.Direction -> Svg msg
marker selected direction =
    let
        angle : String
        angle =
            case direction of
                Direction.North ->
                    "0"

                Direction.East ->
                    "90"

                Direction.South ->
                    "180"

                Direction.West ->
                    "270"

        color : String
        color =
            if selected then
                S.yellow5Str

            else
                S.gray5Str
    in
    Svg.g
        [ SA.transform ("rotate(" ++ angle ++ " 8 8)")
        , SA.pointerEvents "none"
        , A.attribute "aria-hidden" "true"
        ]
        [ Svg.path
            [ SA.d "M6.4 2.24L8 0.48L9.6 2.24Z"
            , SA.fill color
            , SA.stroke S.gray0Str
            , SA.strokeWidth "0.4"
            , SA.strokeLinejoin "round"
            , SA.class "fightlines-unit-facing"
            , SA.style "paint-order: stroke fill"
            ]
            []
        ]
