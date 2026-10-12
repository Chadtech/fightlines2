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
                0%, 49% { opacity: 1; }
                50%, 100% { opacity: 0; }
            }
            .fightlines-unit-death {
                animation: fightlines-unit-death-flash 400ms steps(1) 3;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-unit-death { animation: none; opacity: 1; }
            }
        """
        ]


{-| Zero-supply units exist only in the server's final death presentation frame.
The following frame removes them, so no local timer owns their lifetime.
-}
toSvg : Unit -> Svg msg
toSvg unit =
    if unit.supplies.current > 0 then
        Svg.text ""

    else
        Svg.g
            [ SA.class "fightlines-unit-death"
            , SA.pointerEvents "none"
            , Aria.label "died from exhausted supplies"
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
