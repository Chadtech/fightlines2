module View.DepotStock exposing
    ( label
    , styles
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Style as S
import Supply
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-depot-stock-blink {
                0%, 100% { opacity: 1; }
                50% { opacity: 0; }
            }
            .fightlines-depot-stock-low {
                animation: fightlines-depot-stock-blink 2s step-end infinite;
            }
            .fightlines-depot-stock-target { cursor: pointer; outline: none; }
            .fightlines-depot-stock-target:focus-visible {
                outline: 0.5px solid var(--depot-focus-color);
                outline-offset: -0.5px;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-depot-stock-low { animation: none; opacity: 1; }
            }
        """
        ]


label : Supply.Stock -> String
label stock =
    let
        warning : String
        warning =
            if stock.current == 0 then
                " · empty"

            else if stock.current * 4 <= stock.maximum then
                " · low"

            else
                ""
    in
    "supply depot · "
        ++ String.fromInt stock.current
        ++ " / "
        ++ String.fromInt stock.maximum
        ++ warning


{-| The bottom-edge stock bar stays above occupying units. Its event target is
provided by the page and remains present during the warning's hidden phase.
-}
toSvg : Supply.Stock -> Svg msg
toSvg stock =
    let
        fraction : Float
        fraction =
            if stock.maximum > 0 then
                clamp 0 1 (toFloat stock.current / toFloat stock.maximum)

            else
                0

        color : String
        color =
            if stock.current == 0 then
                S.red1Str

            else if fraction <= 0.25 then
                S.yellow5Str

            else
                S.green1Str

        warningClass : String
        warningClass =
            if stock.current > 0 && fraction <= 0.25 then
                "fightlines-depot-stock-low"

            else
                ""

        emptySymbol : List (Svg msg)
        emptySymbol =
            if stock.current == 0 then
                [ Svg.rect
                    [ SA.x "6.4"
                    , SA.y "12.5"
                    , SA.width "3.2"
                    , SA.height "3.2"
                    , SA.fill S.gray0Str
                    ]
                    []
                , Svg.circle
                    [ SA.cx "8"
                    , SA.cy "14.1"
                    , SA.r "1"
                    ]
                    []
                , Svg.path
                    [ SA.d "M6.85 15.4L9.15 12.8"
                    ]
                    []
                ]

            else
                []
    in
    Svg.g
        [ SA.pointerEvents "none"
        , Aria.hidden True
        ]
        [ Svg.rect
            [ SA.x "0.6"
            , SA.y "13.65"
            , SA.width "14.8"
            , SA.height "1.9"
            , SA.fill S.gray0Str
            , SA.stroke S.gray0Str
            , SA.strokeWidth "0.3"
            ]
            []
        , Svg.g
            [ SA.class warningClass
            ]
            [ Svg.rect
                [ SA.x "0.8"
                , SA.y "13.85"
                , SA.width "14.4"
                , SA.height "1.5"
                , SA.fill "none"
                , SA.stroke color
                , SA.strokeWidth "0.25"
                ]
                []
            , Svg.rect
                [ SA.x "0.95"
                , SA.y "14"
                , SA.width (String.fromFloat (14.1 * fraction))
                , SA.height "1.2"
                , SA.fill color
                ]
                []
            ]
        , Svg.g
            [ SA.fill "none"
            , SA.stroke color
            , SA.strokeWidth "0.22"
            ]
            emptySymbol
        ]
