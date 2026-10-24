module Game.View.BattlefieldWorkspace exposing
    ( inspectorHtmlId
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
    , controls : Html msg
    , inspection : Html msg
    , hasSelection : Bool
    , onCloseInspection : msg
    , combatOverlay : Html msg
    }


inspectorHtmlId : String
inspectorHtmlId =
    "game-inspector"


inspectorWidth : String
inspectorWidth =
    "min(15.5rem, 45vw)"


{-| The controls sit below the navigation surface. The header and inspector
overlay it without changing the map's coordinate system.
-}
viewport :
    { battlefield : Browser.Dom.Element
    , inspector : Browser.Dom.Element
    }
    -> Camera.Viewport
viewport measured =
    { size =
        { x = measured.battlefield.element.width
        , y = measured.battlefield.element.height
        }
    , bottomInset = 0
    , rightInset = measured.inspector.element.width
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

        hasHeader : Bool
        hasHeader =
            case model.header of
                Just _ ->
                    True

                Nothing ->
                    False

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
                ]
            ]
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
                ]
            ]
            [ model.battlefield ]
        , H.div
            [ A.attribute "data-loss-dim" ""
            , A.css
                [ S.shrink0
                , S.maxWFull
                , Css.maxHeight (Css.vh 50)
                , S.overflowAuto
                , S.when model.hasSelection
                    (Css.property "max-width" ("calc(100% - " ++ inspectorWidth ++ ")"))
                ]
            ]
            [ model.controls ]
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
                , S.when hasHeader
                    (S.belowWidth 767
                        [ Css.paddingTop (Css.rem 3.25) ]
                    )
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
