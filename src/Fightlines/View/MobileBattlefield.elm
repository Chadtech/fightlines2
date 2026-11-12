module Fightlines.View.MobileBattlefield exposing
    ( Tab(..)
    , ordersHelpButtonHtmlId
    , panelHeader
    , portraitDialog
    , rotationStyles
    , tabHtmlId
    , toHtml
    , topBar
    )

import Css
import Css.Media
import Game.View.BattlefieldWorkspace as BattlefieldWorkspace
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import NonEmptyList
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Dialog as Dialog exposing (Dialog)
import View.Tabs as Tabs exposing (Tabs)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Tab
    = Orders
    | Details


type alias TabOption =
    { value : Tab
    , label : String
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


tabHtmlId : Tab -> String
tabHtmlId tab =
    case tab of
        Orders ->
            "mobile-orders-tab"

        Details ->
            "mobile-details-tab"


ordersHelpButtonHtmlId : String
ordersHelpButtonHtmlId =
    Tabs.helpButtonHtmlId (tabHtmlId Orders)



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


panelHeader :
    { tab : Tab
    , ordersAvailable : Bool
    , onTabClick : Tab -> msg
    , onTabNavigate : Tab -> msg
    , onOrdersHelp : msg
    }
    -> Html msg
panelHeader config =
    let
        details : TabOption
        details =
            { value = Details
            , label = "details"
            }

        options : NonEmptyList.NonEmpty TabOption
        options =
            if config.ordersAvailable then
                NonEmptyList.fromCons
                    { value = Orders
                    , label = "orders"
                    }
                    [ details ]

            else
                NonEmptyList.fromCons details []

        tabs : Tabs Tab msg
        tabs =
            Tabs.new
                { label = "selection"
                , selected = config.tab
                , options = options
                , htmlId = tabHtmlId
                , onClick = config.onTabClick
                , onNavigate = config.onTabNavigate
                }
                |> Tabs.horizontal

        withHelp : Tabs Tab msg
        withHelp =
            if config.ordersAvailable then
                tabs
                    |> Tabs.withHelp
                        { tab = Orders
                        , label = "about orders"
                        , onClick = config.onOrdersHelp
                        }

            else
                tabs
    in
    Tabs.toHeader withHelp


{-| Equal-width outer columns keep the central controls centered on the screen.
-}
topBar :
    { surrender : Html msg
    , center : Html msg
    , submit : Html msg
    }
    -> Html msg
topBar controls =
    H.div
        [ Aria.label "turn actions"
        , A.css
            [ S.grid
            , S.gridColumns "minmax(0, 1fr) minmax(0, 21rem) minmax(0, 1fr)"
            , S.itemsCenter
            , S.g2
            , S.p1
            , S.outdent
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.minW0
                ]
            ]
            [ controls.surrender ]
        , controls.center
        , H.div
            [ A.css
                [ S.row
                , S.justifyEnd
                , S.minW0
                ]
            ]
            [ controls.submit ]
        ]


portrait : List Css.Style -> Css.Style
portrait =
    Css.Media.withMediaQuery
        [ "(orientation: portrait)" ]


portraitDialog : msg -> Dialog msg
portraitDialog onCancel =
    Dialog.make "mobile-rotation-notice"
        "rotate your phone"
        onCancel
        [ H.div
            [ A.css
                [ S.col
                , S.g3
                , S.grow
                , S.itemsCenter
                , S.justifyCenter
                , S.textAlignCenter
                ]
            ]
            [ rotationGraphic
            , H.text "turn your phone for landscape orientation"
            ]
        ]
        |> Dialog.fullscreen


rotationStyles : Html msg
rotationStyles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-phone-turn {
                from { transform: rotate(0deg); }
                to { transform: rotate(90deg); }
            }
        """
        ]


rotationGraphic : Html msg
rotationGraphic =
    Svg.svg
        [ Aria.hidden True
        , SA.viewBox "0 0 224 148"
        , SA.width "224"
        , SA.css
            [ Css.maxWidth (Css.pct 100)
            , Css.height Css.auto
            , S.shrink0
            ]
        , SA.stroke S.yellow5Str
        , SA.strokeWidth "2"
        ]
        [ Svg.path
            [ SA.d "M134 21 H149 A37 37 0 0 1 186 58 V63 M179 56 L186 63 L193 56"
            , SA.fill "none"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            []
        , Svg.g
            [ SA.css
                [ Css.property "transform-origin" "104px 81px"
                , Css.property "transform" "rotate(90deg)"
                , S.animation "fightlines-phone-turn 850ms ease-in-out 250ms both"
                , S.reducedMotion
                    [ S.animationNone ]
                ]
            ]
            [ Svg.rect
                [ SA.x "72"
                , SA.y "26"
                , SA.width "64"
                , SA.height "110"
                , SA.rx "12"
                , SA.fill S.nightwood3Str
                ]
                []
            , Svg.rect
                [ SA.x "79"
                , SA.y "33"
                , SA.width "50"
                , SA.height "96"
                , SA.rx "5"
                , SA.fill S.nightwood2Str
                , SA.stroke S.gray3Str
                , SA.strokeWidth "1"
                ]
                []
            , Svg.path
                [ SA.d "M98 34 H110"
                , SA.strokeLinecap "round"
                ]
                []
            ]
        ]


{-| The rail has an independently scrolling task area and a persistent footer.
The rail overlays the battlefield without changing its measured surface.
-}
toHtml :
    { header : Html msg
    , battlefield : Html msg
    , hasSelection : Bool
    , tab : Tab
    , panelHeader : Html msg
    , panel : Html msg
    , close : Html msg
    , notification : Maybe (Html msg)
    , focus : BattlefieldWorkspace.PlaybackFocus
    , combatOverlay : Html msg
    }
    -> List (Html msg)
toHtml contents =
    let
        interactionBlocked : Bool
        interactionBlocked =
            contents.focus.loss || contents.focus.combat

        interactionAttributes : List (H.Attribute msg)
        interactionAttributes =
            if interactionBlocked then
                [ A.attribute "inert" "" ]

            else
                []

        notification : Html msg
        notification =
            case contents.notification of
                Just content ->
                    H.div
                        [ A.css
                            [ S.absolute
                            , S.left0
                            , S.bottom0
                            , S.z3
                            , S.p2
                            , S.maxWFull
                            , S.maxH40Viewport
                            , S.overflowAuto
                            ]
                        ]
                        [ content ]

                Nothing ->
                    H.text ""

        panelPadding : Css.Style
        panelPadding =
            case contents.tab of
                Orders ->
                    S.p2

                Details ->
                    Css.batch
                        [ S.px2
                        , S.pb2
                        ]

        panel : Html msg
        panel =
            if contents.hasSelection then
                H.aside
                    [ A.id BattlefieldWorkspace.inspectorHtmlId
                    , Aria.label "selection panel"
                    , A.attribute "data-loss-dim" ""
                    , A.css
                        [ S.absolute
                        , S.top0
                        , S.bottom0
                        , S.right0
                        , S.z2
                        , S.col
                        , S.bgGray1
                        , S.outdentLeft
                        , S.shrink0
                        , S.widthValue "clamp(16rem, 30vw, 19rem)"
                        , S.minH0
                        , S.prSafeArea
                        , S.pbSafeArea
                        ]
                    ]
                    [ contents.panelHeader
                    , H.div
                        [ A.css
                            [ S.flex1
                            , S.minH0
                            , S.overflowAuto
                            , panelPadding
                            , S.col
                            , S.g2
                            ]
                        ]
                        [ contents.panel ]
                    , H.footer
                        [ A.id BattlefieldWorkspace.controlsHtmlId
                        , A.css
                            [ S.shrink0
                            , S.p2
                            , S.borderT
                            , S.borderGray2
                            ]
                        ]
                        [ contents.close ]
                    ]

            else
                H.text ""

        workspaceAttributes : List (H.Attribute msg)
        workspaceAttributes =
            [ Aria.label "mobile battlefield"
            , A.class (BattlefieldWorkspace.focusClass contents.focus)
            , A.css
                [ S.fixed
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.col
                , S.overflowHidden
                , portrait
                    [ S.displayNone ]
                ]
            ]
    in
    [ H.div
        (workspaceAttributes ++ interactionAttributes)
        [ H.header
            [ A.attribute "data-loss-dim" ""
            , A.css
                [ S.bgGray1
                , S.shrink0
                , S.plSafeArea
                , S.prSafeArea
                ]
            ]
            [ contents.header ]
        , H.div
            [ A.css
                [ S.relative
                , S.row
                , S.flex1
                , S.minH0
                ]
            ]
            [ H.div
                [ A.css
                    [ S.relative
                    , S.flex1
                    , S.minW0
                    , S.minH0
                    , S.row
                    , S.containerSize
                    ]
                ]
                [ contents.battlefield
                , notification
                ]
            , panel
            ]
        ]
    , contents.combatOverlay
    ]
