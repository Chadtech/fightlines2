module Game.View.UnitStatus exposing
    ( Action(..)
    , Help
    , buttonHtmlId
    , dialog
    , dialogHtmlId
    , toHtml
    )

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
import Html.Styled.Events as Ev
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
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


type Action msg
    = RevokeOrder msg
    | CancelOrder msg


type Help
    = UnitHelp UnitKind
    | SupplyHelp UnitKind
    | FuelHelp Fuel


type alias Events msg =
    { onHelp : Help -> msg
    }


toHtml : Events msg -> String -> Unit -> Maybe (Action msg) -> Html msg
toHtml events playerName unit action =
    case action of
        Just portraitAction ->
            Lazy.lazy4 actionableStatusView events playerName unit portraitAction

        Nothing ->
            Lazy.lazy3 inspectionStatusView events playerName unit


inspectionStatusView : Events msg -> String -> Unit -> Html msg
inspectionStatusView events playerName unit =
    statusView events playerName unit []


actionableStatusView : Events msg -> String -> Unit -> Action msg -> Html msg
actionableStatusView events playerName unit action =
    let
        button : Button.Button msg
        button =
            case action of
                RevokeOrder onRevoke ->
                    Button.primary "revoke order" onRevoke

                CancelOrder onCancel ->
                    Button.danger "cancel order (esc)" onCancel
    in
    statusView events
        playerName
        unit
        [ button
            |> Button.fullWidth
            |> Button.toHtml
        ]


statusView : Events msg -> String -> Unit -> List (Html msg) -> Html msg
statusView events playerName unit portraitActions =
    let
        identityContent : List (Html msg)
        identityContent =
            [ unitHeader events playerName unit
            , portrait playerName unit
            ]

        resourceContent : List (Html msg)
        resourceContent =
            [ CombatReadiness.toHtml unit.combatState
            , exhaustionStatus unit
            , resourcesView events unit.kind unit.resources
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


resourcesView : Events msg -> UnitKind -> Maybe UnitResources -> Html msg
resourcesView events kind maybeResources =
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
            ]
        ]
        [ Svg.svg
            [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth (UnitSprite.appearance unit)) ++ " 16")
            , SA.width "100%"
            , SA.height "128"
            , SA.css
                [ S.block
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
            , infoButton events ("about " ++ UnitKindUtil.label unit.kind) (UnitHelp unit.kind)
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


infoButton : Events msg -> String -> Help -> Html msg
infoButton events label help =
    H.button
        [ A.type_ "button"
        , A.id (buttonHtmlId help)
        , Aria.label label
        , A.title label
        , A.attribute "aria-haspopup" "dialog"
        , Ev.onClick (events.onHelp help)
        , A.css
            [ S.row
            , S.itemsCenter
            , S.justifyCenter
            , S.shrink0
            , S.w6
            , S.h6
            , S.p0
            , S.borderTransparent
            , S.bgTransparent
            , S.textGray5
            , S.pointerCursor
            , S.focusVisible
                [ S.outlineCurrent ]
            ]
        ]
        [ InfoMarker.toHtml ]


buttonHtmlId : Help -> String
buttonHtmlId help =
    case help of
        UnitHelp _ ->
            "unit-type-info-button"

        SupplyHelp _ ->
            "unit-supply-info-button"

        FuelHelp _ ->
            "unit-fuel-info-button"


dialogHtmlId : String
dialogHtmlId =
    "unit-info-dialog"


dialog : msg -> Help -> Dialog msg
dialog dismissed help =
    let
        title : String
        title =
            case help of
                UnitHelp kind ->
                    "about " ++ UnitKindUtil.label kind

                SupplyHelp _ ->
                    "supply"

                FuelHelp _ ->
                    "fuel"

        content : Html msg
        content =
            case help of
                UnitHelp kind ->
                    unitDescription kind

                SupplyHelp kind ->
                    H.p
                        []
                        [ H.text (supplyExplanation kind) ]

                FuelHelp fuel ->
                    H.p
                        []
                        [ H.text (fuelExplanation fuel) ]
    in
    Dialog.make dialogHtmlId
        title
        dismissed
        [ content
        , Button.secondary "close" dismissed
            |> Button.toHtml
        ]
        |> Dialog.reference
        |> Dialog.withCloseButton


unitDescription : UnitKind -> Html msg
unitDescription kind =
    let
        needs : String
        needs =
            if usesOil kind then
                "watch its supply and fuel levels when planning a move."

            else
                "watch its supply level when planning a move."
    in
    H.dl
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ helpEntry "role" (roleText kind)
        , helpEntry "needs" needs
        , helpEntry "movement" "enemy units block travel. move onto stationary compatible allies to load a truck. an allied square becomes available after its occupant has a move planned; final destinations must stay separate."
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
                    , infoButton events "about supply" (SupplyHelp kind)
                    ]

                Fuel fuel ->
                    [ H.text label
                    , infoButton events "about fuel" (FuelHelp fuel)
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


supplyExplanation : UnitKind -> String
supplyExplanation kind =
    let
        consumption : String
        consumption =
            supplyConsumption kind
    in
    consumption ++ " at 0 supplies, this unit becomes exhausted and cannot fight. it has two full turns to receive supplies before it perishes. supplies must remain after upkeep to clear exhaustion. nearby supply depots, ground crates, and loaded supply trucks replenish provisions automatically before turn upkeep."


supplyConsumption : UnitKind -> String
supplyConsumption kind =
    case kind of
        Kind.Truck ->
            "trucks consume a small amount of supplies each turn."

        Kind.Tank ->
            "tanks consume supplies each turn and for combat readiness and firing. movement uses fuel without spending supplies."

        Kind.Infantry ->
            "infantry consume supplies each turn, while walking, for attack move, stand ground or ambush readiness, when digging in, and when firing. hills, forests, and mountains cost additional walking supplies."

        Kind.FieldGun ->
            "field guns consume a small amount of supplies each turn, and additional supplies when moving, standing ground, attack-moving, and engaging enemies."


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
