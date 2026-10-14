module View.UnitDeath exposing
    ( Msg(..)
    , dialog
    , dialogHtmlId
    , spotlight
    , styles
    , toSvg
    )

import Api.Enum.CombatKind as CombatKind
import Api.Enum.UnitKind as Kind
import Coordinate exposing (Coordinate)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Map exposing (Map)
import PlayerNumber
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import TurnPlayback exposing (Loss)
import Unit exposing (Unit)
import UnitId exposing (UnitId)
import UnitLoss exposing (Cause(..), Details, DetailsError(..), NamedUnit)
import Util.UnitKind as UnitKind
import View.Aria as Aria
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)
import View.UnitSprite as UnitSprite


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
        [ H.text """
            @keyframes fightlines-unit-death-flash {
                0% { opacity: 0; }
                25%, 100% { opacity: 1; }
            }
            .fightlines-unit-death {
                opacity: 1;
                animation: fightlines-unit-death-flash 800ms steps(1) 600ms 1 forwards;
            }
            .fightlines-death-focus *:not(.fightlines-unit-death):not(.fightlines-combat-impact),
            .fightlines-death-focus *::before,
            .fightlines-death-focus *::after {
                animation-play-state: paused !important;
            }
            .fightlines-loss-focus [data-loss-dim] { opacity: .18; }
            .fightlines-loss-focus .fightlines-unit-death { animation: none; opacity: 1; }
            .fightlines-loss-focus .fightlines-unit-death image { width: 10px; height: 10px; transform: translate(9px, -5px); }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-unit-death { animation: none; opacity: 1; }
            }
        """
        ]


{-| Destroyed units remain visible for their server-timed presentation frame.
Playback transitions own their lifetime rather than a separate marker timer.
-}
toSvg : Unit -> Svg msg
toSvg unit =
    if not (Unit.isDying unit) then
        Svg.text ""

    else
        Svg.g
            [ SA.class "fightlines-unit-death"
            , SA.pointerEvents "none"
            , Aria.label "unit destroyed"
            ]
            [ Svg.image
                [ SA.x "0"
                , SA.y "0"
                , SA.width "16"
                , SA.height "16"
                , SA.xlinkHref "/assets/death-skull-illustrated-v1.png"
                ]
                []
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
                , Checkbox.toHtml
                    { label = "skip this dialog"
                    , checked = config.skipDialogs
                    , onCheck = SkipDialogsChanged
                    }
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
                        " and its " ++ String.fromInt (List.length passengers) ++ " " ++ UnitKind.label first.kind ++ " aboard"

                    else
                        " and its passengers (" ++ String.join ", " (List.map (.kind >> UnitKind.label) passengers) ++ ")"
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
        Destroyed kind attacker ->
            let
                attack : String
                attack =
                    case kind of
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

        SuppliesExhausted ->
            [ detail "cause"
                [ H.text "ran out of supplies"
                ]
            ]

        CarrierLost carrier carrierCause ->
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
        [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth unit) ++ " 16")
        , Aria.hidden True
        , SA.css
            [ S.w14
            , S.h12
            , S.shrink0
            ]
        ]
        [ UnitSprite.portraitToSvg unit
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

        lossMarker : Coordinate -> Svg msg
        lossMarker tile =
            Svg.g
                [ SA.transform
                    ("translate("
                        ++ String.fromInt (tile.x * 16)
                        ++ " "
                        ++ String.fromInt (tile.y * 16)
                        ++ ")"
                    )
                ]
                [ toSvg loss.unit
                ]

        lossMarkers : List (Svg msg)
        lossMarkers =
            position
                |> Maybe.map (lossMarker >> List.singleton)
                |> Maybe.withDefault []

        children : List (Svg msg)
        children =
            shades ++ highlights ++ lossMarkers
    in
    Svg.g
        [ SA.pointerEvents "none"
        , Aria.hidden True
        ]
        children
