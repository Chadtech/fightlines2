module View.UnitCargo exposing
    ( styles
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-unit-cargo-pulse {
                0%, 20%, 100% { opacity: 1; }
                50%, 70% { opacity: 0.3; }
            }
            .fightlines-unit-cargo {
                animation: fightlines-unit-cargo-pulse 2s ease-in-out infinite;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-unit-cargo { animation: none; opacity: 1; }
            }
        """
        ]


{-| Cargo is derived from the board's current passenger locations, including
load and unload transitions during playback. Zero means no badge.
-}
toSvg : Int -> Svg msg
toSvg passengerCount =
    if passengerCount <= 0 then
        Svg.text ""

    else
        let
            width : Float
            width =
                if passengerCount > 1 then
                    4.8

                else
                    3.52

            countMarker : List (Svg msg)
            countMarker =
                if passengerCount > 1 then
                    [ Svg.text_
                        [ SA.x "3.65"
                        , SA.y "2.72"
                        , SA.style "font-size: 2.6px"
                        , SA.textAnchor "middle"
                        ]
                        [ Svg.text (String.fromInt passengerCount)
                        ]
                    ]

                else
                    []

            artwork : List (Svg msg)
            artwork =
                [ Svg.rect
                    [ SA.width (String.fromFloat width)
                    , SA.height "3.52"
                    , SA.fill S.gray0Str
                    , SA.stroke S.gray5Str
                    , SA.strokeWidth "0.2"
                    ]
                    []
                , Svg.circle
                    [ SA.cx "1.76"
                    , SA.cy "1.12"
                    , SA.r "0.56"
                    ]
                    []
                , Svg.path
                    [ SA.d "M0.64 2.96V2.8a1.12 1.12 0 0 1 2.24 0v0.16Z"
                    ]
                    []
                ]

            content : List (Svg msg)
            content =
                artwork ++ countMarker
        in
        Svg.g
            [ SA.transform ("translate(" ++ String.fromFloat (15.26 - width) ++ " 11.74)")
            , SA.fill S.gray5Str
            , SA.class "fightlines-unit-cargo"
            , SA.pointerEvents "none"
            , A.attribute "aria-hidden" "true"
            ]
            content
