module Game.View.UnitStatus exposing
    ( Action(..)
    , toHtml
    )

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.UnitKind exposing (UnitKind)
import Css
import Game.Unit as Unit exposing (Unit)
import Game.Unit.Fuel exposing (Fuel)
import Game.Unit.HitPoints exposing (HitPoints)
import Game.Unit.Supplies exposing (Supplies)
import Game.UnitKind as UnitKindUtil
import Game.UnitResources as UnitResources exposing (UnitResources)
import Game.View.CombatReadiness as CombatReadiness
import Game.View.InspectionHelp as InspectionHelp exposing (Events, Help(..))
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Button as Button
import View.Layout as Layout exposing (Layout)



-- Resource levels come from the authoritative Rust unit state.


type alias Level =
    { current : Int
    , maximum : Int
    }


type Resource
    = HitPoints HitPoints
    | Supply Supplies
    | Fuel Fuel


type Action msg
    = RevokeOrder msg
    | CancelOrder msg


toHtml :
    Layout
    -> Events msg
    -> String
    -> Unit
    -> Maybe (Action msg)
    -> Html msg
toHtml layout events playerName unit action =
    case action of
        Just portraitAction ->
            Lazy.lazy5
                actionableStatusView
                layout
                events
                playerName
                unit
                portraitAction

        Nothing ->
            Lazy.lazy4
                inspectionStatusView
                layout
                events
                playerName
                unit


inspectionStatusView : Layout -> Events msg -> String -> Unit -> Html msg
inspectionStatusView layout events playerName unit =
    statusView layout events playerName unit []


actionableStatusView :
    Layout
    -> Events msg
    -> String
    -> Unit
    -> Action msg
    -> Html msg
actionableStatusView layout events playerName unit action =
    let
        button : Button.Button msg
        button =
            case action of
                RevokeOrder onRevoke ->
                    Button.primary "revoke order" onRevoke

                CancelOrder onCancel ->
                    Button.danger "cancel order (esc)" onCancel
    in
    statusView
        layout
        events
        playerName
        unit
        [ button
            |> Button.fullWidth
            |> Button.toHtml
        ]


statusView :
    Layout
    -> Events msg
    -> String
    -> Unit
    -> List (Html msg)
    -> Html msg
statusView layout events playerName unit actions =
    let
        identityContent : List (Html msg)
        identityContent =
            case layout of
                Layout.Desktop ->
                    [ unitHeader events playerName unit
                    , portrait playerName unit
                    ]

                Layout.Mobile ->
                    [ unitHeader events playerName unit ]

        gap : Css.Style
        gap =
            case layout of
                Layout.Desktop ->
                    S.g3

                Layout.Mobile ->
                    S.g1

        resourceContent : List (Html msg)
        resourceContent =
            [ CombatReadiness.toHtml unit.combatState
            , exhaustionStatus unit
            , resourcesView
                layout
                events
                unit.kind
                unit.resources
            ]

        content : List (Html msg)
        content =
            identityContent ++ actions ++ resourceContent
    in
    H.div
        [ A.css
            [ S.col
            , gap
            , S.textGray5
            ]
        ]
        content


exhaustionStatus : Unit -> Html msg
exhaustionStatus unit =
    let
        remaining : Maybe Int
        remaining =
            if Unit.isDying unit then
                Nothing

            else
                unit.resources |> Maybe.andThen .exhaustionTurnsRemaining
    in
    case remaining of
        Just turns ->
            let
                timeLeft : String
                timeLeft =
                    if turns == 1 then
                        "1 turn"

                    else
                        String.fromInt turns ++ " turns"
            in
            H.p
                [ A.css
                    [ S.textYellow5
                    ]
                ]
                [ H.text ("exhausted · resupply within " ++ timeLeft)
                ]

        Nothing ->
            H.text ""


resourcesView :
    Layout
    -> Events msg
    -> UnitKind
    -> Maybe UnitResources
    -> Html msg
resourcesView layout events kind maybeResources =
    let
        gaugeGap : Css.Style
        gaugeGap =
            case layout of
                Layout.Desktop ->
                    S.g3

                Layout.Mobile ->
                    S.g1

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
            , gaugeGap
            ]
        ]
        (List.map (gauge events kind) resources)


portrait : String -> Unit -> Html msg
portrait playerName unit =
    H.div
        [ Aria.role Aria.Image
        , Aria.label (playerName ++ " " ++ unitTitle unit)
        , A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.p3
            , S.compactViewport
                [ S.p1
                ]
            ]
        ]
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth (UnitSprite.appearance unit)) ++ " 16")
            , SA.width "100%"
            , SA.height "128"
            , SA.css
                [ S.block
                , S.compactViewport
                    [ S.h16
                    ]
                ]
            ]
            [ UnitSprite.portraitToSvg (UnitSprite.appearance unit)
            ]
        ]


unitHeader : Events msg -> String -> Unit -> Html msg
unitHeader events playerName unit =
    H.div
        [ A.css
            [ S.row
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
            , InspectionHelp.button
                events
                ("about " ++ UnitKindUtil.label unit.kind)
                (UnitHelp (UnitSprite.appearance unit))
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


gauge : Events msg -> UnitKind -> Resource -> Html msg
gauge events kind resource =
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

        labelChildren : List (Html msg)
        labelChildren =
            case resource of
                HitPoints _ ->
                    [ H.text label ]

                Supply _ ->
                    [ H.text label
                    , InspectionHelp.button events "about supply" SupplyHelp
                    ]

                Fuel _ ->
                    [ H.text label
                    , InspectionHelp.button events "about fuel" FuelHelp
                    ]

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
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ header
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


unitTitle : Unit -> String
unitTitle unit =
    if unit.entrenchment == Entrenchment.Entrenched then
        "entrenched " ++ UnitKindUtil.label unit.kind

    else
        UnitKindUtil.label unit.kind
