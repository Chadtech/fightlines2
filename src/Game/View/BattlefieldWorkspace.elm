module Game.View.BattlefieldWorkspace exposing (toHtml)

import Game.View.BattlefieldInspection as BattlefieldInspection
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Contents msg =
    { loss : Bool
    , combat : Bool
    , dying : Bool
    , battlefield : Html msg
    , controls : Html msg
    , inspection : Html msg
    , hasSelection : Bool
    , combatOverlay : Html msg
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : Contents msg -> List (Html msg)
toHtml model =
    let
        hasUnitLoss : Bool
        hasUnitLoss =
            model.loss

        hasCombatEncounter : Bool
        hasCombatEncounter =
            model.combat

        interactionBlocked : Bool
        interactionBlocked =
            hasCombatEncounter || hasUnitLoss

        animationClass : String
        animationClass =
            if hasUnitLoss then
                "fightlines-death-focus fightlines-loss-focus"

            else if hasCombatEncounter then
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

        workspaceAttributes : List (H.Attribute msg)
        workspaceAttributes =
            [ A.class animationClass
            , A.css
                [ S.fixed
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.row
                ]
            ]
    in
    [ H.div
        (workspaceAttributes ++ combatAttributes)
        [ H.div
            [ A.css
                [ S.relative
                , S.flex1
                , S.minW0
                , S.hFull
                , S.col
                ]
            ]
            [ model.battlefield
            , H.div
                [ A.attribute "data-loss-dim" ""
                ]
                [ model.controls
                ]
            ]
        , H.aside
            [ A.attribute "data-loss-dim" ""
            , Aria.label "game panel"
            , A.css
                [ S.bgGray1
                , S.outdentLeft
                , S.col
                , S.justifySpaceBetween
                , S.g3
                , S.p3
                , S.shrink0
                , S.hFull
                , S.overflowAuto
                , S.wrapAnywhere
                , S.widthMinRemVw 18 45
                ]
            ]
            [ model.inspection
            , BattlefieldInspection.footer model.hasSelection
            ]
        ]
    , model.combatOverlay
    ]
