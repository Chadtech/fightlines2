module Page.Home exposing (view)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Route
import Style as S
import View.Aria as Aria



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : List (Html msg)
view =
    [ H.div
        [ A.css
            [ S.flex1
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            , S.g8
            , S.py8
            ]
        ]
        [ H.h1
            [ A.css
                [ S.wFull
                , S.maxW320
                ]
            ]
            [ H.img
                [ A.src "/assets/fightlines-logo-v1.png"
                , A.alt "fightlines"
                , A.width 2146
                , A.height 732
                , A.css
                    [ S.block
                    , S.wFull
                    , S.hAuto
                    ]
                ]
                []
            ]
        , H.nav
            [ Aria.label "main navigation"
            ]
            [ H.a
                [ A.href (Route.toString Route.NewLobby)
                , A.css
                    [ S.inlineBlock
                    , S.px4
                    , S.py3
                    , S.textYellow5
                    , S.underline
                    , S.hover
                        [ S.textYellow6
                        ]
                    , S.focusVisible
                        [ S.outlineCurrent
                        , S.outlineOffset3
                        ]
                    ]
                ]
                [ H.text "play" ]
            ]
        ]
    ]
