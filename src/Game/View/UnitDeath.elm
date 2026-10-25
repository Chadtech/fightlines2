module Game.View.UnitDeath exposing
    ( Msg(..)
    , dialog
    , dialogHtmlId
    , spotlight
    , styles
    , toSvg
    )

import Api.Enum.CombatKind as CombatKind
import Api.Enum.UnitKind as Kind
import Css
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.PlayerNumber as PlayerNumber
import Game.TurnPlayback as TurnPlayback exposing (Loss)
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitKind as UnitKind
import Game.UnitLoss exposing (Details, DetailsError(..))
import Game.UnitLoss.Cause as Cause exposing (Cause, NamedUnit)
import Game.View.CombatExplosion as CombatExplosion
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)


type Msg
    = ContinueClicked UnitId
    | SkipDialogsChanged Bool


type alias DialogConfig =
    { skipDialogs : Bool
    , isOwn : Bool
    , details : Result DetailsError Details
    , passengers : List Unit
    }


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text
            ("""
            @keyframes fightlines-unit-death-vanish {
                0%, 40% { opacity: 1; }
                100% { opacity: 0; }
            }
            .fightlines-death-focus *:not(["""
                ++ CombatExplosion.casualtyAnimationAttribute
                ++ """]):not(.fightlines-combat-impact),
            .fightlines-death-focus *::before,
            .fightlines-death-focus *::after {
                animation-play-state: paused !important;
            }
            .fightlines-loss-focus [data-loss-dim] { opacity: .18; }
        """
            )
        ]


{-| Replace a destroyed unit's artwork with a quick explosion and disappearance.
The projected casualty remains inspectable for its server-timed presentation frame.
-}
toSvg : Int -> Unit -> Svg msg
toSvg column unit =
    Lazy.lazy2 deathAnimation column unit


deathAnimation : Int -> Unit -> Svg msg
deathAnimation column unit =
    Svg.g
        [ SA.pointerEvents "none"
        , Aria.label "unit destroyed"
        ]
        [ Svg.g
            [ A.attribute CombatExplosion.casualtyAnimationAttribute ""
            , A.css
                [ S.animation ("fightlines-unit-death-vanish " ++ String.fromFloat CombatExplosion.spriteDisappearsAt ++ "ms linear both")
                , S.reducedMotion
                    [ Css.property "animation-timing-function" "steps(1, end)"
                    ]
                ]
            ]
            [ UnitSprite.toSvg column unit
            ]
        , CombatExplosion.mapToSvg unit.spriteFacing
        ]


dialog : DialogConfig -> Loss -> Dialog Msg
dialog config loss =
    let
        title : String
        title =
            case config.details of
                Ok _ ->
                    if List.isEmpty config.passengers then
                        "unit lost"

                    else
                        "units lost"

                Err _ ->
                    "unable to display unit loss"

        information : List (Html Msg)
        information =
            case config.details of
                Ok details ->
                    lossDetails config.isOwn config.passengers loss details

                Err (OwnerNotFound missing) ->
                    [ H.p
                        [ A.css
                            [ S.textRed1
                            ]
                        ]
                        [ H.text ("could not find the owner name for " ++ PlayerNumber.label missing.playerNumber ++ ".")
                        ]
                    , H.p
                        []
                        [ H.text "the loss details could not be displayed. continue to resume playback."
                        ]
                    ]

        actions : Html Msg
        actions =
            H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.itemsCenter
                    , S.g3
                    ]
                ]
                [ Button.primary "continue" (ContinueClicked loss.unit.id)
                    |> Button.toHtml
                , Checkbox.new
                    { label = "skip this dialog"
                    , checked = config.skipDialogs
                    , onCheck = SkipDialogsChanged
                    }
                    |> Checkbox.toHtml
                        [ H.text "skip this dialog"
                        ]
                ]

        body : List (Html Msg)
        body =
            information ++ [ actions ]
    in
    Dialog.make (dialogHtmlId loss) title (ContinueClicked loss.unit.id) body
        |> Dialog.atBottom


lossDetails : Bool -> List Unit -> Loss -> Details -> List (Html Msg)
lossDetails isOwn passengers loss details =
    let
        kind : String
        kind =
            UnitKind.label loss.unit.kind

        article : String
        article =
            if loss.unit.kind == Kind.Infantry then
                "an "

            else
                "a "

        subject : String
        subject =
            if isOwn then
                "you"

            else
                details.ownerName

        passengerSummary : String
        passengerSummary =
            case passengers of
                [] ->
                    ""

                first :: remaining ->
                    let
                        sameKind : Unit -> Bool
                        sameKind passenger =
                            passenger.kind == first.kind
                    in
                    if List.all sameKind remaining then
                        " and its "
                            ++ String.fromInt (List.length passengers)
                            ++ " "
                            ++ UnitKind.label first.kind
                            ++ " aboard"

                    else
                        " and its passengers ("
                            ++ String.join
                                ", "
                                (List.map (.kind >> UnitKind.label) passengers)
                            ++ ")"
    in
    [ H.p
        []
        [ H.text (subject ++ " lost " ++ article ++ kind ++ " unit" ++ passengerSummary ++ ".")
        ]
    , H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        (causeDetails details.cause)
    ]


dialogHtmlId : Loss -> String
dialogHtmlId loss =
    "unit-loss-" ++ UnitId.toString loss.unit.id


causeDetails : Cause -> List (Html Msg)
causeDetails cause =
    case cause of
        Cause.Destroyed kind attacker ->
            let
                attack : String
                attack =
                    case kind of
                        CombatKind.IndirectFire ->
                            "indirect fire"

                        CombatKind.Ambush ->
                            "ambush"

                        CombatKind.AttackMove ->
                            "attack move"
            in
            [ detail "attack"
                [ H.text attack
                ]
            , unitDetail "destroyed by" attacker
            ]

        Cause.ConcealedIndirectFire ->
            [ detail "attack"
                [ H.text "indirect fire"
                ]
            , detail "destroyed by"
                [ H.text "a field gun in the fog of war"
                ]
            ]

        Cause.SuppliesExhausted ->
            [ detail "cause"
                [ H.text "ran out of supplies"
                ]
            ]

        Cause.CarrierLost carrier carrierCause ->
            let
                carrierDetails : List (Html Msg)
                carrierDetails =
                    causeDetails carrierCause
            in
            unitDetail "aboard" carrier
                :: carrierDetails


unitDetail : String -> NamedUnit -> Html Msg
unitDetail label namedUnit =
    detail label
        [ portrait namedUnit.unit
        , H.text (namedUnit.ownerName ++ "'s " ++ UnitKind.label namedUnit.unit.kind)
        ]


detail : String -> List (Html Msg) -> Html Msg
detail label content =
    H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.itemsCenter
            , S.g3
            ]
        ]
        [ H.span
            [ A.css
                [ S.textGray4
                , S.minW28
                ]
            ]
            [ H.text label
            ]
        , H.div
            [ A.css
                [ S.row
                , S.itemsCenter
                , S.g2
                , S.flexWrap
                ]
            ]
            content
        ]


portrait : Unit -> Html msg
portrait unit =
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth (UnitSprite.appearance unit)) ++ " 16")
        , Aria.hidden True
        , SA.css
            [ S.w14
            , S.h12
            , S.shrink0
            ]
        ]
        [ UnitSprite.portraitToSvg (UnitSprite.appearance unit)
        ]


{-| Shade the board above its artwork, leaving the casualty's physical tile lit.
Passengers focus their carrier without adding a passenger sprite to the map.
-}
spotlight : Map -> List Unit -> Loss -> Svg msg
spotlight map units loss =
    let
        position : Maybe Coordinate
        position =
            Unit.physicalPosition units loss.unit

        shade : Coordinate -> Svg msg
        shade tile =
            Svg.rect
                [ SA.x (String.fromInt (tile.x * 16))
                , SA.y (String.fromInt (tile.y * 16))
                , SA.width "16"
                , SA.height "16"
                , SA.fill S.nightwood2Str
                , SA.fillOpacity "0.88"
                ]
                []

        outline : Coordinate -> Svg msg
        outline tile =
            Svg.rect
                [ SA.x (String.fromFloat (toFloat tile.x * 16 + 0.5))
                , SA.y (String.fromFloat (toFloat tile.y * 16 + 0.5))
                , SA.width "15"
                , SA.height "15"
                , SA.fill "none"
                , SA.stroke S.yellow5Str
                , SA.strokeWidth "0.5"
                ]
                []

        outsideFocus : Coordinate -> Bool
        outsideFocus tile =
            Just tile /= position

        shades : List (Svg msg)
        shades =
            Map.positions map
                |> List.filter outsideFocus
                |> List.map shade

        highlights : List (Svg msg)
        highlights =
            position
                |> Maybe.map (outline >> List.singleton)
                |> Maybe.withDefault []

        children : List (Svg msg)
        children =
            shades ++ highlights
    in
    Svg.g
        [ SA.pointerEvents "none"
        , Aria.hidden True
        ]
        children
