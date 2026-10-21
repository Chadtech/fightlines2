module Game.View.TargetSight exposing
    ( State(..)
    , styles
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Svg exposing (Svg)
import Svg.Attributes as SA
import View.Aria as Aria


type State
    = Preview
    | Saved
    | SavedInactive


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-target-lock {
                0% { transform: scale(1.16); filter: sepia(1) saturate(6) hue-rotate(-35deg) brightness(1.5); }
                65% { transform: scale(0.94); }
                100% { transform: scale(1); }
            }
            .fightlines-target-saved {
                transform-box: fill-box;
                transform-origin: center;
                animation: fightlines-target-lock 240ms ease-out;
            }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-target-saved { animation: none; }
            }
        """
        ]


{-| An open center keeps the target visible. The sight never intercepts input.
-}
toSvg : State -> Svg msg
toSvg state =
    let
        stateAttributes : List (Svg.Attribute msg)
        stateAttributes =
            case state of
                Preview ->
                    [ SA.opacity "0.85" ]

                Saved ->
                    [ SA.class "fightlines-target-saved"
                    , SA.opacity "1"
                    ]

                SavedInactive ->
                    [ SA.class "fightlines-target-saved"
                    , SA.opacity "0.5"
                    ]

        imageAttributes : List (Svg.Attribute msg)
        imageAttributes =
            [ SA.x "-0.5"
            , SA.y "-0.5"
            , SA.width "17"
            , SA.height "17"
            , SA.xlinkHref "/assets/target-sight-illustrated-v1.png"
            , SA.pointerEvents "none"
            , Aria.svgHidden True
            ]
    in
    Svg.image
        (imageAttributes ++ stateAttributes)
        []
