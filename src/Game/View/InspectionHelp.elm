module Game.View.InspectionHelp exposing
    ( Events
    , Help(..)
    , button
    , buttonHtmlId
    , dialog
    , dialogHtmlId
    )

import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Terrain as Terrain exposing (Terrain)
import Game.UnitKind as UnitKindUtil
import Game.UnitStats exposing (UnitStats)
import Game.View.TerrainTile as TerrainTile
import Game.View.UnitStats as UnitStatsView
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import Util.List as ListUtil
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
import View.InfoMarker as InfoMarker


type Help
    = UnitHelp UnitKind
    | SupplyHelp
    | FuelHelp
    | CargoHelp
    | TerrainHelp TerrainLocation


type alias TerrainLocation =
    { map : Map
    , position : Coordinate
    }


type alias Events msg =
    { onHelp : Help -> msg
    }


button : Events msg -> String -> Help -> Html msg
button events label help =
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
            , S.coarsePointer
                [ S.w11
                , S.h11
                ]
            , S.belowWidth 767
                [ S.w11
                , S.h11
                ]
            ]
        ]
        [ InfoMarker.toHtml ]


buttonHtmlId : Help -> String
buttonHtmlId help =
    case help of
        UnitHelp _ ->
            "unit-type-info-button"

        SupplyHelp ->
            "unit-supply-info-button"

        FuelHelp ->
            "unit-fuel-info-button"

        CargoHelp ->
            "unit-cargo-info-button"

        TerrainHelp _ ->
            "terrain-info-button"


dialogHtmlId : String
dialogHtmlId =
    "inspection-info-dialog"


dialog : List UnitStats -> msg -> Help -> Dialog msg
dialog stats dismissed help =
    let
        title : String
        title =
            case help of
                UnitHelp kind ->
                    "about " ++ UnitKindUtil.label kind

                SupplyHelp ->
                    "supply"

                FuelHelp ->
                    "fuel"

                CargoHelp ->
                    "cargo"

                TerrainHelp location ->
                    "about terrain: " ++ Terrain.label (Map.terrainAt location.map location.position)

        content : Html msg
        content =
            case help of
                UnitHelp kind ->
                    unitReference stats kind

                SupplyHelp ->
                    H.p
                        []
                        [ H.text supplyExplanation ]

                FuelHelp ->
                    H.p
                        []
                        [ H.text fuelExplanation ]

                CargoHelp ->
                    H.p
                        []
                        [ H.text "supplies refill provisions; fuel drums refill vehicles before upkeep, while stock lasts" ]

                TerrainHelp location ->
                    terrainReference location
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


unitReference : List UnitStats -> UnitKind -> Html msg
unitReference stats kind =
    let
        statistics : List (Html msg)
        statistics =
            case ListUtil.find (\entry -> entry.movement.kind == kind) stats of
                Just entry ->
                    [ UnitStatsView.toHtml entry ]

                Nothing ->
                    [ H.p
                        []
                        [ H.text "unit statistics unavailable"
                        ]
                    ]

        content : List (Html msg)
        content =
            H.p
                []
                [ H.text (unitDescription kind)
                ]
                :: statistics
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        content


terrainReference : TerrainLocation -> Html msg
terrainReference location =
    let
        terrain : Terrain
        terrain =
            Map.terrainAt location.map location.position
    in
    H.div
        [ A.css
            [ S.row
            , S.itemsStart
            , S.g4
            , S.belowWidth 360
                [ S.col
                , S.itemsCenter
                ]
            ]
        ]
        [ H.figure
            [ A.css
                [ S.col
                , S.g2
                , S.m0
                , S.w40
                , S.maxWFull
                , S.shrink0
                ]
            ]
            [ TerrainTile.portrait location.map location.position
            , H.figcaption
                [ A.css
                    [ S.textGray5
                    , S.textAlignCenter
                    ]
                ]
                [ H.text (Terrain.label terrain) ]
            ]
        , H.p
            [ A.css
                [ S.flex1
                , S.minW0
                , S.m0
                ]
            ]
            [ H.text (terrainDescription terrain) ]
        ]


unitDescription : UnitKind -> String
unitDescription kind =
    case kind of
        Kind.Infantry ->
            """a group of soldiers. One of the most basic units. infantry are slow moving and consume supplies while walking or attacking. they are
generally unaffected by terrain and are the only unit that can cross mountains. infantry can entrench themselves into the ground, greatly improving
their defenses. they can also sabotage depots and fortresses, destroying
them from within in a single turn."""

        Kind.Tank ->
            """tanks are highly mobile and powerful ground attack units. they pretty much obliterate anything they run into and are the only
thing effective at destroying entrenched infantry. watch their supply and fuel levels though, as they consume resources quickly."""

        Kind.Truck ->
            """a fast moving logistics vehicle that can carry cargo but cannot attack. It is highly vulnerable and will suffer devastating losses
in any engagement it finds itself in. trucks can carry supply crates, fuel drums, infantry units, and field guns and have a cargo space of two."""

        Kind.FieldGun ->
            """teams of men operating artillery pieces, field guns powerful units that can fire at a long range. field guns can hit positions indirectly and have a large ambush area. Field guns don't move fast, so they generally need to be positioned by trucks."""


supplyExplanation : String
supplyExplanation =
    "units use supplies for attacking and they also consume a small amount of supplies each turn. They consume more supplies per turn when engaged in an attacking move, compared to sitting idle or moving. Some units, such as infantry, consume supplies by moving as well. at 0 supplies, units becomes exhausted and cannot fight. After two turns of exhaustion, units perish. units can replenish their supplies by standing next to supply depots, supply crates, or trucks containing supply crates."


fuelExplanation : String
fuelExplanation =
    "some units, such as tanks and trucks, consume fuel by moving. When these units run out of fuel they cannot move and remain stuck where they are. units can replenish their fuel by standing next to fuel depots, fuel drums, or trucks containing fuel drums."


terrainDescription : Terrain -> String
terrainDescription terrain =
    case terrain of
        Terrain.Plain ->
            "open ground, units can easily traverse it, but are also easily spotted by enemies."

        Terrain.Hills ->
            "units on top of hills have greater line of sight and can see over obstacles (forests and other hills)."

        Terrain.Mountains ->
            "mountains give +2 line of sight and let infantry see over obstacles. infantry are slowed down traversing mountains, while tanks, trucks, and field guns cannot cross mountains at all."

        Terrain.Forest ->
            "units inside forests are completely concealed, forests also obstruct line of sight."

        Terrain.Water ->
            "water cannot be entered or crossed by infantry, tanks, trucks, or field guns, including when unloading."

        Terrain.Beach ->
            "a sandy shore with a gentle water edge."

        Terrain.Road _ ->
            "a paved road with ordinary plain movement and supply costs. vehicles use less fuel when traversing road squares."
