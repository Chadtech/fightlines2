module DevTools.View.CombatChart exposing
    ( detail
    , table
    )

import Api.Enum.CombatChartCover as Cover exposing (CombatChartCover)
import Api.Enum.CombatChartDefense as Defense exposing (CombatChartDefense)
import Api.Enum.CombatKind as Attack
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import DevTools.CombatChart as Chart exposing (Chart, Hit, Key)
import Game.UnitKind as UnitKind
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import View.Aria as Aria
import View.Card as Card
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Config msg =
    { chart : Chart
    , covers : List CombatChartCover
    , selected : Maybe Key
    , disabled : Bool
    , onSelect : Key -> msg
    }


type Legend
    = DamageShare
    | LethalHit



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


table : Config msg -> Html msg
table config =
    let
        defenses : List CombatChartDefense
        defenses =
            Chart.defenses config.chart.settings

        groups : List (Html msg)
        groups =
            List.map (defenderGroup config defenses)
                [ Kind.Infantry
                , Kind.Tank
                , Kind.FieldGun
                , Kind.Truck
                ]

        header : CombatChartDefense -> Html msg
        header defense =
            let
                matches : Hit -> Bool
                matches hit =
                    hit.defense == defense

                multiplier : List (Html msg)
                multiplier =
                    case List.head (List.filter matches config.chart.hits) of
                        Just hit ->
                            let
                                value : Float
                                value =
                                    if defense == Defense.Unready then
                                        hit.calculation.factors.readiness

                                    else
                                        hit.calculation.factors.defenderFacing
                            in
                            [ H.div
                                []
                                [ H.text ("×" ++ String.fromFloat value)
                                ]
                            ]

                        Nothing ->
                            []

                content : List (Html msg)
                content =
                    H.div
                        []
                        [ H.text (Chart.defenseLabel defense)
                        ]
                        :: multiplier
            in
            H.th
                [ A.colspan (List.length config.covers)
                , A.scope "colgroup"
                , A.css
                    [ S.p2
                    , S.borderB
                    , S.borderGray2
                    , S.textAlignCenter
                    ]
                ]
                content

        terrainHeader : CombatChartCover -> Html msg
        terrainHeader cover =
            H.th
                [ A.scope "col"
                , A.css
                    [ S.p2
                    , S.borderB
                    , S.borderGray2
                    , S.textAlignCenter
                    ]
                ]
                [ H.text (coverLabel cover)
                ]

        terrainHeaders : List (Html msg)
        terrainHeaders =
            List.concatMap (always (List.map terrainHeader config.covers)) defenses

        firstHeader : Html msg
        firstHeader =
            H.th
                [ A.rowspan 2
                , A.scope "col"
                , A.css
                    [ S.p2
                    , S.w52
                    , S.textLeft
                    ]
                ]
                [ H.text "attacker → defender"
                ]

        headers : List (Html msg)
        headers =
            firstHeader :: List.map header defenses

        tableContent : List (Html msg)
        tableContent =
            H.thead
                []
                [ H.tr
                    []
                    headers
                , H.tr
                    []
                    terrainHeaders
                ]
                :: groups

        minimumWidth : Float
        minimumWidth =
            13 + toFloat (List.length defenses * List.length config.covers) * 5.5
    in
    [ H.div
        [ A.css
            [ S.overflowAuto
            , S.minW0
            ]
        ]
        [ H.table
            [ Aria.label "damage by matchup, readiness, facing, and terrain"
            , A.css
                [ S.wFull
                , S.tabularNums
                , S.borderCollapse
                , S.tableFixed
                , S.minWidthRem minimumWidth
                ]
            ]
            tableContent
        ]
    , H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g4
            ]
        ]
        [ legend DamageShare
        , legend LethalHit
        , H.span
            []
            [ H.text "— no ready defense"
            ]
        ]
    ]
        |> Card.toHtml
            (Card.simple
                |> Card.withHeader
                    (CardHeader.simple "all matchups · conditions side by side"
                        |> CardHeader.withCaption "damage / hit"
                    )
            )


defenderGroup : Config msg -> List CombatChartDefense -> UnitKind -> Html msg
defenderGroup config defenses defender =
    H.tbody
        []
        (defenderRows config defenses defender)


defenderRows : Config msg -> List CombatChartDefense -> UnitKind -> List (Html msg)
defenderRows config defenses defender =
    let
        attackers : List UnitKind
        attackers =
            if config.chart.settings.attack == Attack.IndirectFire then
                [ Kind.FieldGun
                ]

            else
                [ Kind.Infantry
                , Kind.Tank
                , Kind.FieldGun
                ]

        exposed : Bool
        exposed =
            (defender == Kind.FieldGun) || (defender == Kind.Truck)

        caption : List (Html msg)
        caption =
            if exposed then
                [ H.span
                    []
                    [ H.text "always exposed"
                    ]
                ]

            else
                []

        groupContent : List (Html msg)
        groupContent =
            H.span
                []
                [ H.text (UnitKind.label defender ++ " defender")
                ]
                :: caption

        row : UnitKind -> Html msg
        row attacker =
            let
                cell : CombatChartDefense -> CombatChartCover -> Html msg
                cell defense cover =
                    hitCell config
                        { attacker = attacker
                        , defender = defender
                        , defense = defense
                        , cover = cover
                        }

                cells : List (Html msg)
                cells =
                    List.concatMap cellsForDefense defenses

                cellsForDefense : CombatChartDefense -> List (Html msg)
                cellsForDefense defense =
                    List.map (cell defense) config.covers

                rowLabel : Html msg
                rowLabel =
                    H.th
                        [ A.scope "row"
                        , A.css
                            [ S.p2
                            , S.borderB
                            , S.borderGray2
                            , S.textLeft
                            ]
                        ]
                        [ H.text (UnitKind.label attacker ++ " → " ++ UnitKind.label defender)
                        ]
            in
            H.tr
                []
                (rowLabel :: cells)
    in
    H.tr
        []
        [ H.th
            [ A.colspan (1 + List.length defenses * List.length config.covers)
            , A.scope "rowgroup"
            , A.css
                [ S.bgNightwood3
                , S.p2
                , S.textGray5
                ]
            ]
            [ H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.g2
                    , S.justifySpaceBetween
                    ]
                ]
                groupContent
            ]
        ]
        :: List.map row attackers


hitCell : Config msg -> Key -> Html msg
hitCell config key =
    let
        matching : Hit -> Bool
        matching hit =
            Chart.key hit == key

        hitContent : Html msg
        hitContent =
            case List.head (List.filter matching config.chart.hits) of
                Nothing ->
                    H.span
                        [ Aria.label "no ready defense"
                        , A.css
                            [ S.block
                            , S.p2
                            , S.textAlignCenter
                            ]
                        ]
                        [ H.text "—"
                        ]

                Just hit ->
                    let
                        selected : Bool
                        selected =
                            config.selected == Just key

                        lethal : Bool
                        lethal =
                            hit.remainingHp == 0

                        share : Float
                        share =
                            min 100 (100 * toFloat hit.calculation.damage / toFloat config.chart.settings.defenderHp)

                        accessibleLabel : String
                        accessibleLabel =
                            String.join ", "
                                [ UnitKind.label hit.attacker ++ " against " ++ UnitKind.label hit.defender
                                , Chart.defenseLabel hit.defense
                                , coverLabel hit.cover
                                , String.fromInt hit.calculation.damage ++ " damage"
                                , String.fromInt hit.remainingHp ++ " hp left"
                                ]
                    in
                    H.button
                        [ A.type_ "button"
                        , A.disabled config.disabled
                        , Ev.onClick (config.onSelect key)
                        , Aria.label accessibleLabel
                        , A.attribute "aria-pressed" (boolText selected)
                        , A.css
                            [ S.wFull
                            , S.col
                            , S.g1
                            , S.p1
                            , S.minH11
                            , S.border
                            , S.borderTransparent
                            , S.bgTransparent
                            , S.textGray5
                            , S.pointerCursor
                            , S.when lethal S.bgRed0
                            , S.when selected S.borderYellow5
                            , S.focusVisible
                                [ S.outlineYellow5Thick
                                ]
                            , S.hover
                                [ S.importantIndent
                                ]
                            ]
                        ]
                        [ H.span
                            [ A.css
                                [ S.wFull
                                , S.textAlignCenter
                                ]
                            ]
                            [ H.text (String.fromInt hit.calculation.damage)
                            ]
                        , H.span
                            [ Aria.hidden True
                            , A.css
                                [ S.wFull
                                , S.bgNightwood3
                                , S.h3px
                                ]
                            ]
                            [ H.span
                                [ A.css
                                    [ S.block
                                    , S.h3px
                                    , S.widthPct share
                                    , S.bgYellow4
                                    , S.when lethal S.bgGray4
                                    ]
                                ]
                                []
                            ]
                        ]
    in
    H.td
        [ A.css
            [ S.p1
            , S.borderB
            , S.borderGray2
            ]
        ]
        [ hitContent
        ]


legend : Legend -> Html msg
legend variant =
    let
        label : String
        label =
            case variant of
                DamageShare ->
                    "damage as a share of defender hp"

                LethalHit ->
                    "lethal hit"
    in
    H.span
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g2
            ]
        ]
        [ H.span
            [ Aria.hidden True
            , A.css
                [ S.w4
                , S.h2
                , S.when (variant == DamageShare) S.bgYellow4
                , S.when (variant == LethalHit) S.bgRed0
                ]
            ]
            []
        , H.text label
        ]


detail : Chart -> Maybe Key -> Html msg
detail chart selected =
    let
        matching : Hit -> Bool
        matching hit =
            Just (Chart.key hit) == selected

        content : List (Html msg)
        content =
            case List.head (List.filter matching chart.hits) of
                Nothing ->
                    [ H.p
                        []
                        [ H.text "select a damage value to inspect the hit."
                        ]
                    ]

                Just hit ->
                    [ H.div
                        [ A.css
                            [ S.row
                            , S.flexWrap
                            , S.g3
                            , S.justifySpaceBetween
                            ]
                        , A.attribute "aria-live" "polite"
                        ]
                        [ H.div
                            []
                            [ H.p
                                []
                                [ H.text (UnitKind.label hit.attacker ++ " → " ++ UnitKind.label hit.defender)
                                ]
                            , H.p
                                []
                                [ H.text
                                    (String.fromInt chart.settings.attackerHp
                                        ++ " vs "
                                        ++ String.fromInt chart.settings.defenderHp
                                        ++ " hp · "
                                        ++ Chart.defenseLabel hit.defense
                                        ++ " · "
                                        ++ coverLabel hit.cover
                                    )
                                ]
                            ]
                        , H.p
                            [ A.css
                                [ S.textYellow5
                                , S.tabularNums
                                ]
                            ]
                            [ H.text
                                (String.fromInt
                                    hit.calculation.damage
                                    ++ " damage · "
                                    ++ String.fromInt hit.remainingHp
                                    ++ " hp left"
                                )
                            ]
                        ]
                    , H.details
                        [ A.css
                            [ S.pt3
                            , S.borderT
                            , S.borderGray2
                            ]
                        ]
                        [ H.summary
                            [ A.css
                                [ S.pointerCursor
                                ]
                            ]
                            [ H.text "damage factors"
                            ]
                        , factorBreakdown hit
                        ]
                    ]
    in
    Card.toHtml
        (Card.simple |> Card.withHeader (CardHeader.simple "selected hit"))
        content


factorBreakdown : Hit -> Html msg
factorBreakdown hit =
    let
        factors : Chart.Factors
        factors =
            hit.calculation.factors

        factor : ( String, Float ) -> Html msg
        factor ( label, value ) =
            H.span
                []
                [ H.text (label ++ " ×" ++ String.fromFloat value)
                ]

        multipliers : List ( String, Float )
        multipliers =
            [ ( "relative health", factors.relativeHealth )
            , ( "matchup", factors.matchup )
            , ( "readiness", factors.readiness )
            , ( "defender facing", factors.defenderFacing )
            , ( "attacker aim", factors.attackerAim )
            , ( "terrain", factors.cover )
            , ( "ambush", factors.ambush )
            , ( "trenches", factors.entrenchment )
            ]

        base : Html msg
        base =
            H.span
                []
                [ H.text ("base power " ++ String.fromInt factors.basePower)
                ]

        values : List (Html msg)
        values =
            base :: List.map factor multipliers
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.pt3
            , S.wrapAnywhere
            , S.tabularNums
            ]
        ]
        [ H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g3
                ]
            ]
            values
        , H.p
            []
            [ H.text ("cap at 16 hp → fortress ×" ++ String.fromFloat factors.fortification ++ " → round → minimum 1 hp")
            ]
        ]


coverLabel : CombatChartCover -> String
coverLabel cover =
    case cover of
        Cover.OpenGround ->
            "open ground"

        Cover.HillsForest ->
            "hills / forest"


boolText : Bool -> String
boolText value =
    if value then
        "true"

    else
        "false"
