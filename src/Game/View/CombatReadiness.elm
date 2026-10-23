module Game.View.CombatReadiness exposing (toHtml)

import Api.Enum.DefenseReadiness as Defense
import Api.Enum.WeaponReadiness as Weapon
import Game.CombatState as CombatState exposing (CombatState)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


toHtml : Maybe CombatState -> Html msg
toHtml maybeState =
    case maybeState of
        Nothing ->
            H.text ""

        Just state ->
            H.div
                [ A.attribute "data-combat-readiness" ""
                , A.css
                    [ S.col
                    , S.g1
                    , S.textGray5
                    ]
                ]
                [ H.p
                    []
                    [ H.text ("order: " ++ CombatState.orderLabel state.order) ]
                , H.p
                    []
                    [ H.text ("defense: " ++ defenseLabel state) ]
                , H.p
                    []
                    [ H.text ("weapon: " ++ weaponLabel state) ]
                ]


defenseLabel : CombatState -> String
defenseLabel state =
    case state.defense of
        Defense.Ready ->
            "ready"

        Defense.Exposed ->
            "unready — always exposed"

        Defense.Unready ->
            "unready"


weaponLabel : CombatState -> String
weaponLabel state =
    case state.weapon of
        Weapon.CanFire ->
            "can fire"

        Weapon.AlreadyFired ->
            "already fired"

        Weapon.InsufficientSupplies ->
            "insufficient supplies"

        Weapon.NotOrdered ->
            "not ordered to fire"

        Weapon.Aboard ->
            "aboard transport"

        Weapon.Destroyed ->
            "destroyed"

        Weapon.Unarmed ->
            "unarmed"
