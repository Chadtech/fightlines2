module View.LoadingBar exposing
    ( styles
    , sweep
    , toHtml
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria


{-| An indeterminate activity track. Keep the empty track visible while idle.
Provide textual activity feedback alongside it; the animation is decorative.
-}
toHtml : Bool -> Html msg
toHtml active =
    let
        content : List (Html msg)
        content =
            if active then
                [ H.div
                    [ A.css
                        [ S.bgGray4
                        , sweep
                        ]
                    ]
                    []
                ]

            else
                []
    in
    H.div
        [ Aria.hidden True
        , A.css
            [ S.indentStrong
            , S.bgNightwood3
            , S.overflowHidden
            , S.relative
            , S.h5
            , S.w36
            , S.maxWFull
            ]
        ]
        content


sweep : Css.Style
sweep =
    S.batch
        [ S.absolute
        , S.inset0
        , S.w40Pct
        , S.animation "fightlines-loading-sweep 1.8s linear infinite"
        , S.reducedMotion
            [ S.animationNone
            , S.left30Pct
            ]
        ]


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-loading-sweep {
                from { transform: translateX(-100%); }
                to { transform: translateX(250%); }
            }
        """
        ]
