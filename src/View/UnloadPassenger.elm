module View.UnloadPassenger exposing (toHtml)

import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.Checkbox as Checkbox
import View.UnitSprite as UnitSprite


toHtml : { checked : Bool, onCheck : Bool -> msg } -> Unit -> Html msg
toHtml config unit =
    Checkbox.toHtml
        { label = kindLabel unit.kind
        , checked = config.checked
        , onCheck = config.onCheck
        }
        [ Svg.svg
            [ SA.viewBox "0 0 16 16"
            , SA.width "48"
            , SA.height "48"
            , A.attribute "aria-hidden" "true"
            , SA.css
                [ S.shrink0
                , S.bgNightwood3
                , S.indentStrong
                ]
            ]
            [ UnitSprite.toSvg 0 unit
            ]
        , H.div
            [ A.css
                [ S.col
                , S.g1
                , S.flex1
                , S.minW0
                ]
            ]
            [ H.span
                []
                [ H.text (kindLabel unit.kind)
                ]
            , H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.g2
                    ]
                ]
                [ resource "health" unit.hitPoints
                , resource "supplies" { current = unit.supplies.current, maximum = unit.supplies.maximum }
                ]
            ]
        ]


resource : String -> { current : Int, maximum : Int } -> Html msg
resource label level =
    let
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

        compactLabel : String
        compactLabel =
            if label == "health" then
                "hp"

            else
                "supply"

        description : String
        description =
            compactLabel ++ " " ++ String.fromInt level.current ++ "/" ++ String.fromInt level.maximum

        status : String
        status =
            if fraction < 0.25 then
                "low " ++ description

            else
                description
    in
    H.div
        [ A.title status
        , A.css
            [ S.col
            , S.g1
            , Css.width (Css.rem 8)
            ]
        ]
        [ H.span
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text status
            ]
        , H.div
            [ A.attribute "role" "meter"
            , A.attribute "aria-label" label
            , A.attribute "aria-valuemin" "0"
            , A.attribute "aria-valuemax" (String.fromInt level.maximum)
            , A.attribute "aria-valuenow" (String.fromInt level.current)
            , A.css
                [ S.bgGray0
                , Css.height (Css.rem 0.25)
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


kindLabel : UnitKind -> String
kindLabel kind =
    case kind of
        Kind.Infantry ->
            "infantry"

        Kind.FieldGun ->
            "field gun"

        Kind.Tank ->
            "tank"

        Kind.Truck ->
            "truck"
