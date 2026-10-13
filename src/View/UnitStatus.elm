module View.UnitStatus exposing (toHtml)

import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import Unit.Fuel exposing (Fuel)
import Unit.HitPoints exposing (HitPoints)
import Unit.Supplies exposing (Supplies)
import UnitResources exposing (UnitResources)
import Util.UnitKind as UnitKindUtil
import View.Aria as Aria
import View.InfoMarker as InfoMarker
import View.UnitSprite as UnitSprite



-- Resource levels come from the authoritative Rust unit state.


type alias Level =
    { current : Int
    , maximum : Int
    }


type Resource
    = HitPoints HitPoints
    | Supply Supplies
    | Fuel Fuel


toHtml : String -> Unit -> Html msg
toHtml playerName unit =
    let
        visibleResources : UnitResources -> List Resource
        visibleResources details =
            let
                fuelResources : List Resource
                fuelResources =
                    details.fuel |> Maybe.map (\fuel -> [ Fuel fuel ]) |> Maybe.withDefault []
            in
            [ HitPoints details.hitPoints, Supply details.supplies ] ++ fuelResources

        resources : List Resource
        resources =
            unit.resources |> Maybe.map visibleResources |> Maybe.withDefault []
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.textGray5
            ]
        ]
        [ unitHelp playerName unit
        , portrait playerName unit
        , H.div
            [ A.css
                [ S.col
                , S.g3
                ]
            ]
            (List.map (gauge unit.kind) resources)
        ]


portrait : String -> Unit -> Html msg
portrait playerName unit =
    H.div
        [ Aria.role Aria.Image
        , Aria.label (playerName ++ " " ++ UnitKindUtil.label unit.kind)
        , A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.p3
            ]
        ]
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth unit) ++ " 16")
            , SA.width "100%"
            , SA.height "128"
            , SA.css
                [ S.block
                ]
            ]
            [ UnitSprite.portraitToSvg unit
            ]
        ]


unitHelp : String -> Unit -> Html msg
unitHelp playerName unit =
    H.details
        []
        [ H.summary
            [ Aria.label ("about " ++ UnitKindUtil.label unit.kind)
            , A.title "about this unit"
            , A.css
                [ S.batch summaryStyles
                , S.row
                , S.itemsCenter
                , S.justifySpaceBetween
                , S.g2
                ]
            ]
            [ H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g2
                    ]
                ]
                [ H.h2
                    [ A.css
                        [ S.textGray5
                        ]
                    ]
                    [ H.text (UnitKindUtil.label unit.kind)
                    ]
                , InfoMarker.toHtml
                ]
            , H.span
                [ A.css
                    [ S.textGray4
                    , Css.textAlign Css.right_
                    ]
                ]
                [ H.text playerName
                ]
            ]
        , H.section
            [ Aria.label "about this unit"
            , A.css
                [ S.bgYellow2
                , S.textGray5
                , Css.marginTop (Css.rem 0.75)
                , Css.marginLeft (Css.rem -0.75)
                , Css.marginRight (Css.rem -0.75)
                ]
            ]
            [ H.dl
                [ A.css
                    [ S.col
                    , S.g3
                    , S.p3
                    ]
                ]
                [ helpEntry "role" (roleText unit.kind)
                , helpEntry "needs"
                    (if usesOil unit.kind then
                        "watch its supply and fuel levels when planning a move."

                     else
                        "watch its supply level when planning a move."
                    )
                , helpEntry "movement" "enemy units block travel. move onto stationary compatible allies to load a truck. an allied square becomes available after its occupant has a move planned; final destinations must stay separate."
                ]
            ]
        ]


helpEntry : String -> String -> Html msg
helpEntry label description =
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.dt
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text label
            ]
        , H.dd
            [ A.css
                [ S.m0
                ]
            ]
            [ H.text description
            ]
        ]


summaryStyles : List Css.Style
summaryStyles =
    [ S.pointerCursor
    , S.listStyleNone
    , Css.pseudoElement "-webkit-details-marker"
        [ S.displayNone
        ]
    ]


gauge : UnitKind -> Resource -> Html msg
gauge kind resource =
    let
        label : String
        label =
            case resource of
                HitPoints _ ->
                    "hit points"

                Supply _ ->
                    "supply"

                Fuel _ ->
                    "fuel"

        level : Level
        level =
            case resource of
                HitPoints hitPoints ->
                    hitPoints

                Supply supplies ->
                    { current = supplies.current, maximum = supplies.maximum }

                Fuel fuel ->
                    fuel

        fraction : Float
        fraction =
            toFloat level.current / toFloat level.maximum

        fill : Css.Style
        fill =
            if fraction < 0.25 then
                S.bgRed1

            else if fraction > 0.75 then
                S.bgGreen1

            else
                S.bgYellow4

        explanation : Maybe String
        explanation =
            case resource of
                HitPoints _ ->
                    Nothing

                Supply _ ->
                    Just (supplyExplanation kind)

                Fuel _ ->
                    Just "each traversed tile uses 1 fuel. holds and canceled moves use none. fuel cannot be replenished."

        labelChildren : List (Html msg)
        labelChildren =
            case explanation of
                Nothing ->
                    [ H.text label ]

                Just _ ->
                    [ H.text label, InfoMarker.toHtml ]

        header : Html msg
        header =
            H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.justifySpaceBetween
                    , S.flexWrap
                    , S.g1
                    ]
                ]
                [ H.span
                    [ A.css
                        [ S.row
                        , S.itemsCenter
                        , S.g2
                        ]
                    ]
                    labelChildren
                , H.span
                    [ A.css
                        [ Css.property "white-space" "nowrap"
                        , Css.property "font-variant-numeric" "tabular-nums"
                        ]
                    ]
                    [ H.text (String.fromInt level.current ++ " / " ++ String.fromInt level.maximum)
                    ]
                ]

        resourceHelp : Html msg
        resourceHelp =
            case explanation of
                Nothing ->
                    header

                Just info ->
                    H.details
                        []
                        [ H.summary
                            [ Aria.label ("about " ++ label)
                            , A.title info
                            , A.css summaryStyles
                            ]
                            [ header ]
                        , H.p
                            [ A.css
                                [ S.bgYellow2
                                , S.textGray5
                                , S.p2
                                , Css.marginTop (Css.rem 0.5)
                                ]
                            ]
                            [ H.text info ]
                        ]
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ resourceHelp
        , H.div
            [ Aria.role Aria.Meter
            , Aria.label label
            , Aria.valueMin 0
            , Aria.valueMax level.maximum
            , Aria.valueNow level.current
            , A.css
                [ S.bgGray0
                , Css.height (Css.rem 0.75)
                ]
            ]
            [ H.div
                [ A.css
                    [ fill
                    , S.hFull
                    , Css.width (Css.pct (fraction * 100))
                    ]
                ]
                []
            ]
        ]


supplyExplanation : UnitKind -> String
supplyExplanation kind =
    let
        consumption : String
        consumption =
            supplyConsumption kind
    in
    consumption ++ " nearby depots, ground crates, and loaded supply trucks replenish provisions automatically before turn upkeep."


supplyConsumption : UnitKind -> String
supplyConsumption kind =
    case kind of
        Kind.Truck ->
            "trucks consume a small amount of supplies each turn. when supplies reach 0, this unit perishes."

        Kind.Tank ->
            "tanks consume a small amount of supplies each turn, and additional supplies when attack-moving, standing ground, and engaging enemies. when supplies reach 0, this unit perishes."

        Kind.Infantry ->
            "infantry consume 1 supply each turn, 3 per grass tile, 4 per hill or forest tile, 2 for attack move or ambush readiness, and 3 when firing. when supplies reach 0, this unit perishes."

        Kind.FieldGun ->
            "field guns consume a small amount of supplies each turn, and additional supplies when moving, standing ground, attack-moving, and engaging enemies. when supplies reach 0, this unit perishes."


usesOil : UnitKind -> Bool
usesOil kind =
    case kind of
        Kind.Tank ->
            True

        Kind.Truck ->
            True

        Kind.Infantry ->
            False

        Kind.FieldGun ->
            False


roleText : UnitKind -> String
roleText kind =
    case kind of
        Kind.Infantry ->
            "a ground unit made up of soldiers."

        Kind.Tank ->
            "an armored ground unit."

        Kind.Truck ->
            "a vehicle with two cargo berths shared by infantry, field guns, and supply crates. crates are neutral and automatically replenish nearby units of either side. drive onto a ground crate to collect it, or onto a depot to choose how many to load."

        Kind.FieldGun ->
            "a ground unit with a crew-operated gun."
