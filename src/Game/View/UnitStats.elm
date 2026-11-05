module Game.View.UnitStats exposing (toHtml)

import Game.Unit.Fuel exposing (Fuel)
import Game.UnitStats exposing (UnitStats)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria


type alias Stat =
    { label : String
    , value : String
    }


toHtml : UnitStats -> Html msg
toHtml stats =
    let
        supplies : List Stat
        supplies =
            [ { label = "supplies / turn"
              , value = String.fromInt stats.supplies.upkeepPerTurn
              }
            , { label = "supplies / tile moved"
              , value = walkingSupplies stats
              }
            ]

        fuel : List Stat
        fuel =
            case stats.fuel of
                Just rates ->
                    [ { label = "fuel / tile moved"
                      , value = fuelConsumption stats rates
                      }
                    ]

                Nothing ->
                    []

        special : List Stat
        special =
            if stats.combat.digInCost > 0 then
                [ { label = "dig in"
                  , value = String.fromInt stats.combat.digInCost ++ " supplies + turn upkeep; takes the whole turn"
                  }
                ]

            else if stats.cargoCapacity > 0 then
                [ { label = "cargo capacity"
                  , value = String.fromInt stats.cargoCapacity ++ " slots (passengers or freight)"
                  }
                ]

            else
                []

        rows : List Stat
        rows =
            supplies ++ fuel ++ combatStats stats ++ special
    in
    H.div
        [ A.css
            [ S.indentStrong
            , S.bgNightwood3
            ]
        ]
        [ H.table
            [ Aria.label "unit statistics"
            , A.css
                [ S.wFull
                , S.borderCollapse
                , S.tableFixed
                ]
            ]
            [ H.tbody
                []
                (List.map statRow rows)
            ]
        ]


statRow : Stat -> Html msg
statRow stat =
    H.tr
        [ A.css
            [ S.borderB
            , S.borderGray2
            ]
        ]
        [ H.th
            [ A.scope "row"
            , A.css
                [ S.p1
                , S.textGray4
                , S.textLeft
                , S.verticalAlignTop
                , S.w40Pct
                ]
            ]
            [ H.text stat.label
            ]
        , H.td
            [ A.css
                [ S.p1
                , S.textGray5
                , S.verticalAlignTop
                ]
            ]
            [ H.text stat.value
            ]
        ]


walkingSupplies : UnitStats -> String
walkingSupplies stats =
    let
        base : String
        base =
            String.fromInt stats.supplies.movementPerTile
    in
    if stats.supplies.roughTerrainSurcharge > 0 then
        base
            ++ " on plain, beach, roads; "
            ++ String.fromInt (stats.supplies.movementPerTile + stats.supplies.roughTerrainSurcharge)
            ++ " in hills, forest, mountains"

    else
        base


fuelConsumption : UnitStats -> Fuel -> String
fuelConsumption stats fuel =
    let
        cargo : String
        cargo =
            if fuel.movementPerCargoSlot > 0 then
                " + " ++ String.fromInt fuel.movementPerCargoSlot ++ " per occupied cargo slot"

            else
                ""

        roadCargo : String
        roadCargo =
            if stats.movement.roadFuelPerCargoSlot > 0 then
                " + " ++ String.fromInt stats.movement.roadFuelPerCargoSlot ++ " per occupied slot"

            else
                ""
    in
    String.fromInt fuel.movementPerTile
        ++ cargo
        ++ "; roads: "
        ++ String.fromInt stats.movement.roadFuelPerTile
        ++ roadCargo


combatStats : UnitStats -> List Stat
combatStats stats =
    if stats.combat.range == 0 then
        []

    else
        let
            indirect : List Stat
            indirect =
                if stats.combat.indirectRange > 0 then
                    [ { label = "indirect fire range"
                      , value = String.fromInt stats.combat.indirectRange ++ " tiles (radius)"
                      }
                    ]

                else
                    []

            armed : List Stat
            armed =
                [ { label = "supplies / attack"
                  , value = String.fromInt stats.combat.shotCost
                  }
                , { label = "supplies / readiness"
                  , value = String.fromInt stats.combat.readinessCost
                  }
                ]
        in
        armed ++ indirect
