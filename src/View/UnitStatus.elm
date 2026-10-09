module View.UnitStatus exposing (toHtml)

import Api.Enum.Side as Side
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Side
import Style as S
import Svg
import Svg.Attributes as SA
import Unit exposing (Unit)



-- These quantities are presentation fixtures until Rust owns resource state.


type alias Level =
    { current : Int
    , maximum : Int
    }


type Resource
    = HitPoints
    | Supply
    | Fuel


toHtml : Unit -> Html msg
toHtml unit =
    let
        resources : List Resource
        resources =
            if usesOil unit.kind then
                [ HitPoints
                , Supply
                , Fuel
                ]

            else
                [ HitPoints
                , Supply
                ]
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
        , H.p
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text "sample resource values"
            ]
        ]


portrait : Unit -> Html msg
portrait unit =
    let
        row : Int
        row =
            (case unit.kind of
                Kind.Infantry ->
                    0

                Kind.Tank ->
                    3

                Kind.SupplyTruck ->
                    6

                Kind.FieldGun ->
                    9
            )
                + (case unit.side of
                    Side.West ->
                        0

                    Side.East ->
                        1
                  )

        facing : String
        facing =
            case unit.side of
                Side.West ->
                    ""

                Side.East ->
                    "translate(256 0) scale(-1 1)"
    in
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
            [ SA.viewBox "0 0 256 256"
            , SA.width "100%"
            , SA.height "160"
            , SA.style "display:block"
            ]
            [ Svg.g
                [ SA.transform facing
                ]
                [ Svg.svg
                    [ SA.viewBox ("0 " ++ String.fromInt (row * 256) ++ " 256 256")
                    , SA.width "256"
                    , SA.height "256"
                    , SA.overflow "hidden"
                    ]
                    [ Svg.image
                        [ SA.xlinkHref "/assets/units_illustrated-v4.png"
                        , SA.width "1024"
                        , SA.height "3072"
                        ]
                        []
                    ]
                ]
            ]
            |> H.fromUnstyled
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
                HitPoints ->
                    "hit points"

                Supply ->
                    "supply"

                Fuel ->
                    "fuel"

        level : Level
        level =
            case resource of
                HitPoints ->
                    { current = 82, maximum = 100 }

                Supply ->
                    { current = 34, maximum = 60 }

                Fuel ->
                    { current = 16, maximum = 80 }

        fraction : Float
        fraction =
            toFloat level.current / toFloat level.maximum

        fill : Css.Style
        fill =
            if fraction < 0.25 then
                S.bgRed1

            else if fraction > 0.75 then
                S.bgBlue1

            else
                S.bgYellow4

        explanation : String
        explanation =
            case resource of
                HitPoints ->
                    "how much health the unit has left. the second number is its maximum."

                Supply ->
                    "how many supplies the unit has left. the second number is how much it can carry."

                Fuel ->
                    "how much fuel the unit has left. only units that use oil show this gauge."
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
