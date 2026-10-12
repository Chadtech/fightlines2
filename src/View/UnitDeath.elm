module View.UnitDeath exposing
    ( styles
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.Aria as Aria


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-unit-death-flash {
                0%, 24%, 50%, 100% { opacity: 1; }
                25%, 49% { opacity: 0; }
            }
            .fightlines-unit-death {
                animation: fightlines-unit-death-flash 400ms steps(1) 1 forwards;
            }
            .fightlines-death-focus *:not(.fightlines-unit-death):not(.fightlines-combat-impact),
            .fightlines-death-focus *::before,
            .fightlines-death-focus *::after {
                animation-play-state: paused !important;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-unit-death { animation: none; opacity: 1; }
            }
        """
        ]


{-| Destroyed units remain visible for their server-timed presentation frame.
Playback transitions own their lifetime rather than a separate marker timer.
-}
toSvg : Unit -> Svg msg
toSvg unit =
    if not (Unit.isDying unit) then
        Svg.text ""

    else
        Svg.g
            [ SA.class "fightlines-unit-death"
            , SA.pointerEvents "none"
            , Aria.label "unit destroyed"
            ]
            [ Svg.image
                [ SA.x "0"
                , SA.y "0"
                , SA.width "16"
                , SA.height "16"
                , SA.xlinkHref "/assets/death-skull-illustrated-v1.png"
                ]
                []
            ]
