module Game.View.UnitStatus exposing (toHtml)

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Fuel exposing (Fuel)
import Game.Unit.HitPoints exposing (HitPoints)
import Game.Unit.Supplies exposing (Supplies)
import Game.UnitKind as UnitKindUtil
import Game.UnitResources as UnitResources exposing (UnitResources)
import Game.View.CombatReadiness as CombatReadiness
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Button as Button
import View.InfoMarker as InfoMarker



-- Resource levels come from the authoritative Rust unit state.


type alias Level =
    { current : Int
    , maximum : Int
    }


type Resource
    = HitPoints HitPoints
    | Supply Supplies
    | Fuel Fuel


toHtml : String -> Unit -> Maybe msg -> Html msg
toHtml playerName unit revoke =
    case revoke of
        Just onRevoke ->
            Lazy.lazy3 revocableStatusView playerName unit onRevoke

        Nothing ->
            Lazy.lazy2 inspectionStatusView playerName unit


inspectionStatusView : String -> Unit -> Html msg
inspectionStatusView playerName unit =
    statusView playerName unit []


revocableStatusView : String -> Unit -> msg -> Html msg
revocableStatusView playerName unit onRevoke =
    statusView playerName
        unit
        [ Button.primary "revoke order" onRevoke
            |> Button.fullWidth
            |> Button.toHtml
        ]


statusView : String -> Unit -> List (Html msg) -> Html msg
statusView playerName unit portraitActions =
    let
        identityContent : List (Html msg)
        identityContent =
            [ unitHelp playerName unit
            , portrait playerName unit
            ]

        resourceContent : List (Html msg)
        resourceContent =
            [ CombatReadiness.toHtml unit.combatState
            , resourcesView unit.kind unit.resources
            ]

        content : List (Html msg)
        content =
            identityContent ++ portraitActions ++ resourceContent
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.textGray5
            ]
        ]
        content


resourcesView : UnitKind -> Maybe UnitResources -> Html msg
resourcesView kind maybeResources =
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
            maybeResources
                |> Maybe.map visibleResources
                |> Maybe.withDefault []
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        (List.map (gauge kind) resources)


portrait : String -> Unit -> Html msg
portrait playerName unit =
    H.div
        [ Aria.role Aria.Image
        , Aria.label (playerName ++ " " ++ unitTitle unit)
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
                    [ H.text (unitTitle unit)
                    ]
                , InfoMarker.toHtml
                ]
            , H.span
                [ A.css
                    [ S.textGray4
                    , S.textAlignRight
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
                , S.mt3
                , S.mlNeg3
                , S.mrNeg3
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
    , S.hideDetailsMarker
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
                    { current = fuel.current
                    , maximum = fuel.maximum
                    }

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

                Fuel fuel ->
                    Just (fuelExplanation fuel)

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
                        [ S.noWrap
                        , S.tabularNums
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
                                , S.mt2
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
                , S.h3
                ]
            ]
            [ H.div
                [ A.css
                    [ fill
                    , S.hFull
                    , S.widthPct (fraction * 100)
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
    consumption ++ " nearby supply depots, ground crates, and loaded supply trucks replenish provisions automatically before turn upkeep."


supplyConsumption : UnitKind -> String
supplyConsumption kind =
    case kind of
        Kind.Truck ->
            "trucks consume a small amount of supplies each turn. when supplies reach 0, this unit perishes."

        Kind.Tank ->
            "tanks consume supplies each turn and for combat readiness and firing. movement uses fuel without spending supplies. when supplies reach 0, this unit perishes."

        Kind.Infantry ->
            "infantry consume supplies each turn, while walking, for attack move, stand ground or ambush readiness, when digging in, and when firing. hills, forests, and mountains cost additional walking supplies. when supplies reach 0, this unit perishes."

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
            "a vehicle with two cargo berths shared by infantry, field guns, supply crates, and fuel drums. neutral freight refills nearby provisions or vehicle fuel. drive onto ground freight to choose whether to pick it up, or onto a depot to choose how many loads to take."

        Kind.FieldGun ->
            "a ground unit with a crew-operated gun."


fuelExplanation : Fuel -> String
fuelExplanation fuel =
    let
        cargoCost : String
        cargoCost =
            if fuel.movementPerCargoSlot > 0 then
                ", plus "
                    ++ String.fromInt fuel.movementPerCargoSlot
                    ++ " for each occupied cargo slot (passenger, supply crate, or fuel drum) at departure"

            else
                ""
    in
    "each traversed non-road tile uses "
        ++ String.fromInt fuel.movementPerTile
        ++ " fuel"
        ++ cargoCost
        ++ ". roads use less fuel. loading and unloading happen after movement. holds and canceled moves use none. nearby fuel depots and ground or carried fuel drums refill vehicle tanks at turn end."


unitTitle : Unit -> String
unitTitle unit =
    if unit.entrenchment == Entrenchment.Entrenched then
        "entrenched " ++ UnitKindUtil.label unit.kind

    else
        UnitKindUtil.label unit.kind
