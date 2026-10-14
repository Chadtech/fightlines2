module View.UnitCargo exposing
    ( styles
    , supplyToSvg
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-unit-cargo-pulse {
                0%, 20%, 100% { opacity: 1; }
                50%, 70% { opacity: 0.65; }
            }
        """
        ]


type CargoKind
    = Passengers
    | SupplyCrates


{-| Cargo is derived from the board's current passenger locations, including
load and unload transitions during playback. Zero means no badge.
-}
toSvg : Int -> Svg msg
toSvg =
    badge Passengers


{-| Supply cargo uses the same badge treatment on the opposite corner.
-}
supplyToSvg : Int -> Svg msg
supplyToSvg =
    badge SupplyCrates


badge : CargoKind -> Int -> Svg msg
badge kind count =
    if count <= 0 then
        Svg.text ""

    else
        let
            badgeScale : Float
            badgeScale =
                1.4

            width : Float
            width =
                if count > 1 then
                    4.8

                else
                    3.52

            countMarker : List (Svg msg)
            countMarker =
                if count > 1 then
                    [ Svg.text_
                        [ SA.x "3.65"
                        , SA.y "2.72"
                        , SA.style "font-size: 2.6px"
                        , SA.textAnchor "middle"
                        ]
                        [ Svg.text (String.fromInt count)
                        ]
                    ]

                else
                    []

            background : String
            background =
                case kind of
                    Passengers ->
                        S.yellow5Str

                    SupplyCrates ->
                        S.blue1Str

            left : Float
            left =
                case kind of
                    Passengers ->
                        15.26 - width * badgeScale

                    SupplyCrates ->
                        0.74

            graphic : List (Svg msg)
            graphic =
                case kind of
                    Passengers ->
                        [ Svg.circle
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

                    SupplyCrates ->
                        [ Svg.path
                            [ SA.d "M0.6 0.8H2.92V2.88H0.6ZM0.6 1.38H2.92M1.18 0.8V2.88M2.34 0.8V2.88"
                            , SA.fill "none"
                            , SA.stroke S.nightwood3Str
                            , SA.strokeWidth "0.24"
                            ]
                            []
                        ]

            artwork : List (Svg msg)
            artwork =
                [ Svg.rect
                    [ SA.width (String.fromFloat width)
                    , SA.height "3.52"
                    , SA.fill background
                    , SA.stroke S.nightwood3Str
                    , SA.strokeWidth "0.2"
                    ]
                    []
                ]

            content : List (Svg msg)
            content =
                artwork ++ graphic ++ countMarker
        in
        Svg.g
            [ SA.transform ("translate(" ++ String.fromFloat left ++ " " ++ String.fromFloat (15.26 - 3.52 * badgeScale) ++ ") scale(" ++ String.fromFloat badgeScale ++ ")")
            , SA.fill S.nightwood3Str
            , SA.css
                [ S.animation "fightlines-unit-cargo-pulse 2s ease-in-out infinite"
                , S.reducedMotion
                    [ S.animationNone
                    , S.opaque
                    ]
                ]
            , SA.pointerEvents "none"
            , Aria.hidden True
            ]
            content
