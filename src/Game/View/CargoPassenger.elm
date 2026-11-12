module Game.View.CargoPassenger exposing
    ( cardContents
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


type Layout
    = Compact
    | Card


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
            ]
        ]
        (contents Compact unit)


cardContents : Unit -> List (Html msg)
cardContents =
    contents Card


contents : Layout -> Unit -> List (Html msg)
contents layout unit =
    let
        isCard : Bool
        isCard =
            layout == Card

        resourceLayout : Css.Style
        resourceLayout =
            if isCard then
                S.col

            else
                S.row

        resourceMeters : List (Html msg)
        resourceMeters =
            case unit.resources of
                Just details ->
                    [ resource layout Health details.hitPoints
                    , resource layout
                        Supplies
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
            , S.when isCard
                [ S.widthValue "clamp(3.5rem, 13vw, 7rem)"
                , S.hAuto
                ]
            ]
        ]
        [ UnitSprite.toSvg 0 unit
        ]
    , H.span
        [ A.css
            [ S.col
            , S.g1
            , S.flex1
            , S.minW0
            , S.when isCard [ S.g2 ]
            ]
        ]
        [ H.span
            [ A.css
                [ S.when isCard [ S.textGray5 ]
                , S.when isCard [ S.fontSizeRem 1.25 ]
                ]
            ]
            [ H.text (UnitKindUtil.label unit.kind)
            ]
        , H.span
            [ A.css
                [ resourceLayout
                , S.flexWrap
                , S.g2
                ]
            ]
            resourceMeters
        ]
    ]


resource :
    Layout
    -> ResourceKind
    ->
        { current : Int
        , maximum : Int
        }
    -> Html msg
resource layout kind level =
    let
        width : Css.Style
        width =
            case layout of
                Compact ->
                    S.w32

                Card ->
                    S.wFull

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
    H.span
        [ A.title status
        , A.css
            [ S.col
            , S.g1
            , width
            ]
        ]
        [ H.span
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text status
            ]
        , H.span
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
            [ H.span
                [ A.css
                    [ fill
                    , S.hFull
                    , Css.width (Css.pct (fraction * 100))
                    ]
                ]
                []
            ]
        ]
