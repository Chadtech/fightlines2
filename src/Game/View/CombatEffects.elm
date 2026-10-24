module Game.View.CombatEffects exposing
    ( explosion
    , impacts
    , mapPeek
    , spotlight
    , styles
    )

import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Shot as Shot exposing (Shot)
import Game.Unit as Unit exposing (Unit)
import Html.Styled as H exposing (Html)
import Style as S
import Svg exposing (Svg)
import Svg.Attributes as SA
import View.Aria as Aria


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-combat-shine {
                from { transform: translateX(-16px); opacity: 0; }
                25% { opacity: 1; }
                to { transform: translateX(16px); opacity: 0; }
            }
            .fightlines-combat-shine {
                animation: fightlines-combat-shine 300ms ease-out both;
            }
            .fightlines-combat-map-peek .fightlines-combat-shine {
                animation: fightlines-combat-shine 900ms ease-in-out infinite;
            }
            @keyframes fightlines-combat-impact {
                0% { transform: scale(.2); opacity: 0; }
                20% { transform: scale(.85); opacity: 1; }
                50% { transform: scale(1.1); opacity: 1; }
                100% { transform: scale(1.5); opacity: 0; }
            }
            .fightlines-combat-impact {
                animation: fightlines-combat-impact 360ms ease-out both;
                transform-box: fill-box;
                transform-origin: center;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-combat-shine,
                .fightlines-combat-map-peek .fightlines-combat-shine { animation: none; opacity: .45; }
                .fightlines-combat-impact { animation: none; opacity: .85; }
            }
        """
        ]


spotlight : Map -> List Coordinate -> Svg msg
spotlight =
    spotlightView ""


mapPeek : Map -> List Coordinate -> Svg msg
mapPeek =
    spotlightView "fightlines-combat-map-peek"


spotlightView : String -> Map -> List Coordinate -> Svg msg
spotlightView className map positions =
    let
        shade : Coordinate -> Svg msg
        shade position =
            Svg.rect
                [ SA.x (String.fromInt (position.x * 16))
                , SA.y (String.fromInt (position.y * 16))
                , SA.width "16"
                , SA.height "16"
                , SA.fill S.nightwood2Str
                , SA.fillOpacity "0.82"
                ]
                []

        highlight : Coordinate -> Svg msg
        highlight position =
            let
                clipHtmlId : String
                clipHtmlId =
                    "combat-shine-" ++ String.fromInt position.x ++ "-" ++ String.fromInt position.y
            in
            Svg.g
                [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
                ]
                [ Svg.defs []
                    [ Svg.clipPath
                        [ SA.id clipHtmlId
                        ]
                        [ Svg.rect
                            [ SA.width "16"
                            , SA.height "16"
                            ]
                            []
                        ]
                    ]
                , Svg.rect
                    [ SA.x "0.5"
                    , SA.y "0.5"
                    , SA.width "15"
                    , SA.height "15"
                    , SA.fill "none"
                    , SA.stroke S.yellow5Str
                    , SA.strokeWidth "0.6"
                    ]
                    []
                , Svg.g
                    [ SA.clipPath ("url(#" ++ clipHtmlId ++ ")")
                    ]
                    [ Svg.rect
                        [ SA.width "16"
                        , SA.height "16"
                        , SA.fill "url(#combat-shine-gradient)"
                        , SA.class "fightlines-combat-shine"
                        ]
                        []
                    ]
                ]

        tiles : List Coordinate
        tiles =
            Map.positions map

        shades : List (Svg msg)
        shades =
            tiles
                |> List.filter
                    (\position -> not (List.member position positions))
                |> List.map shade

        highlights : List (Svg msg)
        highlights =
            List.map highlight positions

        gradient : Svg msg
        gradient =
            Svg.defs []
                [ Svg.linearGradient
                    [ SA.id "combat-shine-gradient"
                    ]
                    [ Svg.stop
                        [ SA.offset "0%"
                        , SA.stopColor S.gray5Str
                        , SA.stopOpacity "0"
                        ]
                        []
                    , Svg.stop
                        [ SA.offset "50%"
                        , SA.stopColor S.gray5Str
                        , SA.stopOpacity "0.8"
                        ]
                        []
                    , Svg.stop
                        [ SA.offset "100%"
                        , SA.stopColor S.gray5Str
                        , SA.stopOpacity "0"
                        ]
                        []
                    ]
                ]

        content : List (Svg msg)
        content =
            gradient :: shades ++ highlights
    in
    Svg.g
        [ SA.pointerEvents "none"
        , Aria.svgLabel "combat participants highlighted"
        , SA.class className
        ]
        content


impacts : List Coordinate -> List Unit -> List Shot -> Svg msg
impacts landings units shots =
    let
        unique : Coordinate -> List Coordinate -> List Coordinate
        unique position positions =
            if List.member position positions then
                positions

            else
                positions
                    ++ [ position
                       ]

        observed : Unit -> Bool
        observed participant =
            List.any (\unit -> unit.id == participant.id) units

        targets : List Coordinate
        targets =
            (landings
                ++ (shots
                        |> List.filter (.target >> observed)
                        |> List.map .destination
                   )
            )
                |> List.foldl unique []

        burst : Coordinate -> Svg msg
        burst position =
            Svg.g
                [ SA.transform
                    ("translate("
                        ++ String.fromInt (position.x * 16 + 8)
                        ++ " "
                        ++ String.fromInt (position.y * 16 + 8)
                        ++ ") scale(0.8)"
                    )
                ]
                [ explosion
                ]

        explosions : List (Svg msg)
        explosions =
            List.map burst targets
    in
    if List.isEmpty explosions then
        Svg.text ""

    else
        Svg.g
            [ SA.pointerEvents "none"
            , Aria.svgLabel "combat impact"
            ]
            explosions


explosion : Svg msg
explosion =
    Svg.g
        [ SA.class "fightlines-combat-impact"
        ]
        [ Svg.polygon
            [ SA.points "0,-7 1.7,-3 5,-5 3,0 7,2 2.5,3 0,7 -1.5,3 -6,5 -3,0 -7,-2 -2.5,-3"
            , SA.fill S.red1Str
            ]
            []
        , Svg.circle
            [ SA.r "3.8"
            , SA.fill S.yellow5Str
            ]
            []
        , Svg.circle
            [ SA.r "1.8"
            , SA.fill S.gray5Str
            ]
            []
        ]
