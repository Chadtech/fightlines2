module View.LoadingBar exposing (toHtml)

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
                    [ A.class barClass
                    , A.css
                        [ S.absolute
                        , S.hFull
                        , S.bgGray4
                        , Css.width (Css.pct 40)
                        ]
                    ]
                    []
                ]

            else
                []

        children : List (Html msg)
        children =
            styles :: content
    in
    H.div
        [ Aria.hidden True
        , A.css
            [ S.indentStrong
            , S.bgNightwood3
            , S.overflowHidden
            , S.relative
            , Css.height (Css.rem 1.25)
            , Css.width (Css.rem 9)
            , S.maxWFull
            ]
        ]
        children


barClass : String
barClass =
    "fightlines-loading-bar"


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text
            ("." ++ barClass ++ """ { animation: fightlines-loading-sweep 1.8s linear infinite; }
            @keyframes fightlines-loading-sweep {
                from { transform: translateX(-100%); }
                to { transform: translateX(250%); }
            }
            @media (prefers-reduced-motion: reduce) {
                .""" ++ barClass ++ """ { animation: none; left: 30%; }
            }
            """)
        ]
