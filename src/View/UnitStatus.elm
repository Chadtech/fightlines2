module View.UnitStatus exposing (toHtml)

import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Side
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.UnitSprite as UnitSprite



-- Resource levels come from the authoritative Rust unit state.


type alias Level =
    { current : Int
    , maximum : Int
    }


type Resource
    = HitPoints Unit.HitPoints
    | Supply Unit.Supplies
    | Fuel Unit.Fuel


toHtml : Unit -> Html msg
toHtml unit =
    let
        fuelResources : List Resource
        fuelResources =
            unit.fuel |> Maybe.map (\fuel -> [ Fuel fuel ]) |> Maybe.withDefault []

        resources : List Resource
        resources =
            [ HitPoints unit.hitPoints, Supply unit.supplies ] ++ fuelResources
    in
    H.div
        [ A.css
            [ S.col
            , S.g3
            , S.textGray5
            ]
        ]
        [ portrait unit
        , unitHelp unit
        , H.div
            [ A.css
                [ S.col
                , S.g3
                ]
            ]
            (List.map gauge resources)
        ]


portrait : Unit -> Html msg
portrait unit =
    H.div
        [ A.attribute "role" "img"
        , A.attribute "aria-label" (Side.label unit.side ++ " " ++ kindLabel unit.kind)
        , A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.p3
            ]
        ]
        [ Svg.svg
            [ SA.viewBox "0 0 16 16"
            , SA.width "100%"
            , SA.height "160"
            , SA.css
                [ S.block
                ]
            ]
            [ UnitSprite.toSvg 0 unit
            ]
        ]


unitHelp : Unit -> Html msg
unitHelp unit =
    H.details
        []
        [ H.summary
            [ A.attribute "aria-label" ("about " ++ kindLabel unit.kind)
            , A.title "about this unit"
            , A.css summaryStyles
            ]
            [ H.div
                [ A.css
                    [ S.row
                    , S.itemsCenter
                    , S.g2
                    ]
                ]
                [ H.h3
                    [ A.css
                        [ S.textGray5
                        ]
                    ]
                    [ H.text (kindLabel unit.kind)
                    ]
                , infoMarker
                ]
            , H.p
                [ A.css
                    [ S.textGray4
                    , Css.marginTop (Css.rem 0.25)
                    ]
                ]
                [ H.text (Side.label unit.side)
                ]
            ]
        , H.section
            [ A.attribute "aria-label" "about this unit"
            , A.css
                [ S.bgNightwood3
                , Css.marginTop (Css.rem 0.75)
                , Css.marginLeft (Css.rem -0.75)
                , Css.marginRight (Css.rem -0.75)
                ]
            ]
            [ H.h3
                [ A.css
                    [ S.bgYellow2
                    , S.textYellow5
                    , S.p2
                    , S.px3
                    ]
                ]
                [ H.text "about this unit"
                ]
            , H.dl
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
                , helpEntry "movement" "enemy units block travel. occupied squares cannot be destinations."
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
    , Css.property "list-style" "none"
    , Css.pseudoElement "-webkit-details-marker"
        [ S.displayNone
        ]
    ]


infoMarker : Html msg
infoMarker =
    H.span
        [ A.attribute "aria-hidden" "true"
        , A.css
            [ S.textGray4
            , S.shrink0
            ]
        ]
        [ H.text "ⓘ"
        ]


gauge : Resource -> Html msg
gauge resource =
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

        explanation : String
        explanation =
            case resource of
                HitPoints _ ->
                    "how much health the unit has left. the second number is its maximum. damage and healing are not implemented yet."

                Supply supplies ->
                    "provisions for this unit: " ++ String.fromInt supplies.upkeepPerTurn ++ " per resolved turn plus " ++ String.fromInt supplies.movementPerTile ++ " per traversed tile. holds and canceled moves still pay upkeep. supplies cannot be replenished yet."

                Fuel _ ->
                    "each traversed tile uses 1 fuel. holds and canceled moves use none. end a turn on your home depot to fill the tank."
    in
    H.div
        [ A.css
            [ S.col
            , S.g1
            ]
        ]
        [ H.details
            []
            [ H.summary
                [ A.attribute "aria-label" ("about " ++ label)
                , A.title explanation
                , A.css
                    [ S.batch summaryStyles
                    , S.row
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
                    [ H.text label
                    , infoMarker
                    ]
                , H.span
                    [ A.css
                        [ Css.property "white-space" "nowrap"
                        , Css.property "font-variant-numeric" "tabular-nums"
                        ]
                    ]
                    [ H.text (String.fromInt level.current ++ " / " ++ String.fromInt level.maximum)
                    ]
                ]
            , H.p
                [ A.css
                    [ S.textGray4
                    , Css.paddingTop (Css.rem 0.5)
                    ]
                ]
                [ H.text explanation
                ]
            ]
        , H.div
            [ A.attribute "role" "meter"
            , A.attribute "aria-label" label
            , A.attribute "aria-valuemin" "0"
            , A.attribute "aria-valuemax" (String.fromInt level.maximum)
            , A.attribute "aria-valuenow" (String.fromInt level.current)
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


usesOil : UnitKind -> Bool
usesOil kind =
    case kind of
        Kind.Tank ->
            True

        Kind.SupplyTruck ->
            True

        Kind.Infantry ->
            False

        Kind.FieldGun ->
            False


kindLabel : UnitKind -> String
kindLabel kind =
    case kind of
        Kind.Infantry ->
            "infantry"

        Kind.Tank ->
            "tank"

        Kind.SupplyTruck ->
            "supply truck"

        Kind.FieldGun ->
            "field gun"


roleText : UnitKind -> String
roleText kind =
    case kind of
        Kind.Infantry ->
            "a ground unit made up of soldiers."

        Kind.Tank ->
            "an armored ground unit."

        Kind.SupplyTruck ->
            "a vehicle for carrying supplies."

        Kind.FieldGun ->
            "a ground unit with a crew-operated gun."
