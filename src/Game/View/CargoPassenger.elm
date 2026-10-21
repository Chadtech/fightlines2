module Game.View.CargoPassenger exposing
    ( contents
    , toHtml
    )

import Css
import Game.Unit as Unit exposing (Unit)
import Game.UnitKind as UnitKindUtil
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria


type ResourceKind
    = Health
    | Supplies


toHtml : { onSelect : msg } -> Unit -> Html msg
toHtml config unit =
    H.button
        [ A.type_ "button"
        , Aria.label ("inspect " ++ Unit.label unit)
        , Ev.onClick config.onSelect
        , A.css
            [ S.row
            , S.itemsCenter
            , S.g2
            , S.wFull
            , S.p1
            , S.border0
            , S.textGray4
            , Css.backgroundColor Css.transparent
            , Css.textAlign Css.left_
            , S.pointerCursor
            , Css.hover
                [ S.textGray5
                , S.bgNightwood2
                ]
            , Css.pseudoClass "focus-visible"
                [ Css.outline3 (Css.px 1) Css.solid (Css.hex S.yellow5Str)
                , Css.outlineOffset (Css.px 1)
                ]
            ]
        ]
        (contents unit)


contents : Unit -> List (Html msg)
contents unit =
    let
        resourceMeters : List (Html msg)
        resourceMeters =
            case unit.resources of
                Just details ->
                    [ resource Health details.hitPoints
                    , resource Supplies
                        { current = details.supplies.current
                        , maximum = details.supplies.maximum
                        }
                    ]

                Nothing ->
                    []
    in
    [ Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.width "48"
        , SA.height "48"
        , Aria.hidden True
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
            [ H.text (UnitKindUtil.label unit.kind)
            ]
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.g2
                ]
            ]
            resourceMeters
        ]
    ]


resource :
    ResourceKind
    ->
        { current : Int
        , maximum : Int
        }
    -> Html msg
resource kind level =
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
            case kind of
                Health ->
                    "hp"

                Supplies ->
                    "supply"

        label : String
        label =
            case kind of
                Health ->
                    "health"

                Supplies ->
                    "supplies"

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
            [ Aria.role Aria.Meter
            , Aria.label label
            , Aria.valueMin 0
            , Aria.valueMax level.maximum
            , Aria.valueNow level.current
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
