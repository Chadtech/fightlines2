module Game.View.BattlefieldWorkspace exposing
    ( controlsHtmlId
    , inspectorHtmlId
    , toHtml
    , viewport
    )

import Browser.Dom
import Css
import Game.Camera as Camera
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Contents msg =
    { loss : Bool
    , combat : Bool
    , dying : Bool
    , header : Maybe (Html msg)
    , battlefield : Html msg
    , orders : Html msg
    , controls : Html msg
    , notification : Maybe (Html msg)
    , inspection : Html msg
    , hasSelection : Bool
    , onCloseInspection : msg
    , combatOverlay : Html msg
    }


controlsHtmlId : String
controlsHtmlId =
    "battlefield-controls"


inspectorHtmlId : String
inspectorHtmlId =
    "game-inspector"


inspectorWidth : String
inspectorWidth =
    "min(15.5rem, 45vw)"


{-| Desktop panels overlay the navigation surface; narrow screens reserve rows
for controls and inspection. Measure only overlap as camera insets.
-}
viewport :
    { battlefield : Browser.Dom.Element
    , inspector : Browser.Dom.Element
    , controls : Browser.Dom.Element
    }
    -> Camera.Viewport
viewport measured =
    let
        battlefieldBottom : Float
        battlefieldBottom =
            measured.battlefield.element.y + measured.battlefield.element.height

        inspectorOverlaps : Bool
        inspectorOverlaps =
            (measured.inspector.element.height > 0)
                && (measured.inspector.element.y < battlefieldBottom)
                && (measured.inspector.element.x < measured.battlefield.element.x + measured.battlefield.element.width)

        rightInset : Float
        rightInset =
            if inspectorOverlaps then
                measured.inspector.element.width

            else
                0
    in
    { size =
        { x = measured.battlefield.element.width
        , y = measured.battlefield.element.height
        }
    , bottomInset = clamp 0 measured.battlefield.element.height (battlefieldBottom - measured.controls.element.y)
    , rightInset = rightInset
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : Contents msg -> List (Html msg)
toHtml model =
    let
        interactionBlocked : Bool
        interactionBlocked =
            model.combat || model.loss

        animationClass : String
        animationClass =
            if model.loss then
                "fightlines-death-focus fightlines-loss-focus"

            else if model.combat then
                "fightlines-combat-focus"

            else if model.dying then
                "fightlines-death-focus"

            else
                ""

        combatAttributes : List (H.Attribute msg)
        combatAttributes =
            if interactionBlocked then
                [ A.attribute "inert" "" ]

            else
                []

        landscapeColumns : String
        landscapeColumns =
            if model.hasSelection then
                "minmax(0, 1fr) minmax(0, 32%)"

            else
                "minmax(0, 1fr)"

        headerWidth : String
        headerWidth =
            if model.hasSelection then
                "68%"

            else
                "100%"

        header : Html msg
        header =
            case model.header of
                Just content ->
                    H.div
                        [ A.attribute "data-loss-dim" ""
                        , A.css
                            [ S.absolute
                            , S.top0
                            , S.selfCenter
                            , S.maxWFull
                            , S.row
                            , S.justifyCenter
                            , S.z3
                            , S.shortLandscape
                                [ S.left0
                                , S.widthValue headerWidth
                                ]
                            ]
                        ]
                        [ content ]

                Nothing ->
                    H.text ""

        workspaceAttributes : List (H.Attribute msg)
        workspaceAttributes =
            [ A.class animationClass
            , A.css
                [ S.fixed
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.col
                , S.overflowHidden
                , S.shortLandscape
                    [ S.grid
                    , S.gridColumns landscapeColumns
                    , Css.property "grid-template-rows" "minmax(0, 1fr) auto"
                    ]
                ]
            ]

        notification : Html msg
        notification =
            case model.notification of
                Just content ->
                    H.div
                        [ A.css
                            [ S.p3
                            , S.maxWFull
                            , S.maxH40Viewport
                            , S.overflowAuto
                            , S.pointerEventsAuto
                            ]
                        ]
                        [ content ]

                Nothing ->
                    H.text ""
    in
    [ H.div
        (workspaceAttributes ++ combatAttributes)
        [ header
        , H.div
            [ A.css
                [ S.relative
                , S.flex1
                , S.minW0
                , S.minH0
                , S.row
                , S.containerSize
                , S.shortLandscape
                    [ Css.property "grid-area" "1 / 1" ]
                ]
            ]
            [ model.battlefield
            , model.orders
            ]
        , H.div
            [ A.attribute "data-loss-dim" ""
            , A.css
                [ S.absolute
                , S.bottom0
                , S.left0
                , S.z2
                , S.col
                , S.itemsStart
                , S.wFitContent
                , S.maxWFull
                , S.pointerEventsNone
                , S.when model.hasSelection
                    (Css.property "max-width" ("calc(100% - " ++ inspectorWidth ++ ")"))
                , S.compactViewport
                    [ S.relative
                    , S.wFull
                    , S.maxWFull
                    , S.shrink0
                    , Css.order (Css.int 2)
                    ]
                , S.shortLandscape
                    [ Css.property "grid-area" "2 / 1 / 3 / -1"
                    ]
                ]
            ]
            [ notification
            , H.div
                [ A.id controlsHtmlId
                , A.css
                    [ S.shrink0
                    , S.maxWFull
                    , Css.maxHeight (Css.vh 50)
                    , S.overflowAuto
                    , S.pointerEventsAuto
                    , S.compactViewport
                        [ S.wFull
                        , Css.maxHeight (Css.vh 35)
                        ]
                    ]
                ]
                [ model.controls ]
            ]
        , H.aside
            [ A.id inspectorHtmlId
            , A.hidden (not model.hasSelection)
            , A.attribute "data-loss-dim" ""
            , Aria.label "game panel"
            , A.css
                [ S.absolute
                , S.right0
                , S.top0
                , S.bottom0
                , S.z2
                , S.bgGray1
                , S.outdentLeft
                , S.col
                , S.justifySpaceBetween
                , S.g3
                , S.p3
                , S.overflowAuto
                , S.wrapAnywhere
                , S.widthValue inspectorWidth
                , S.compactViewport
                    [ S.relative
                    , S.wFull
                    , Css.maxHeight (Css.vh 28)
                    , S.shrink0
                    , Css.order (Css.int 1)
                    , S.outdentTopRight
                    , S.g2
                    , S.shortLandscape
                        [ Css.property "grid-area" "1 / 2"
                        , Css.maxHeight (Css.pct 100)
                        , S.outdentLeft
                        ]
                    ]
                , S.when (not model.hasSelection) S.displayNone
                ]
            ]
            [ model.inspection
            , H.footer
                [ A.css
                    [ S.col
                    , S.borderT
                    , S.borderGray2
                    , S.pt3
                    , S.shrink0
                    ]
                ]
                [ Button.secondary "close" model.onCloseInspection
                    |> Button.fullWidth
                    |> Button.toHtml
                ]
            ]
        ]
    , model.combatOverlay
    ]
