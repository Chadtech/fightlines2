module View.UnitWarnings exposing
    ( label
    , styles
    , toSvg
    )

import Html.Styled as H exposing (Html)
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import UnitResources exposing (UnitResources)
import View.Aria as Aria


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-unit-warning-blink {
                0%, 100% { opacity: 1; }
                50% { opacity: 0; }
            }
        """
        ]


type Warning
    = LowHitPoints
    | LowSupplies
    | LowFuel


warnings : Unit -> List Warning
warnings unit =
    if Unit.isDying unit then
        []

    else
        unit.resources
            |> Maybe.map resourceWarnings
            |> Maybe.withDefault []


resourceWarnings : UnitResources -> List Warning
resourceWarnings resources =
    let
        isLow : { a | current : Int, maximum : Int } -> Bool
        isLow resource =
            resource.maximum > 0 && resource.current * 4 <= resource.maximum

        candidates : List ( Warning, Bool )
        candidates =
            [ ( LowHitPoints, isLow resources.hitPoints )
            , ( LowSupplies, isLow resources.supplies )
            , ( LowFuel, resources.fuel |> Maybe.map isLow |> Maybe.withDefault False )
            ]

        activeWarning : ( Warning, Bool ) -> Maybe Warning
        activeWarning ( warning, active ) =
            if active then
                Just warning

            else
                Nothing
    in
    List.filterMap activeWarning candidates


label : Unit -> String
label unit =
    warnings unit
        |> List.map warningLabel
        |> String.join ", "


warningLabel : Warning -> String
warningLabel warning =
    case warning of
        LowHitPoints ->
            "low hp"

        LowSupplies ->
            "low supplies"

        LowFuel ->
            "low fuel"


{-| Pack active warnings from the upper-left corner in health/supplies/fuel order.
They sit above ordered-sprite dimming and leave the cargo corners free.
-}
toSvg : Unit -> Svg msg
toSvg unit =
    Svg.g
        [ SA.css
            [ S.animation "fightlines-unit-warning-blink 2s step-end infinite"
            , S.reducedMotion
                [ S.animationNone
                , S.opaque
                ]
            ]
        , SA.pointerEvents "none"
        , Aria.hidden True
        ]
        (List.indexedMap badge (warnings unit))


badge : Int -> Warning -> Svg msg
badge index warning =
    let
        foreground : String
        foreground =
            case warning of
                LowHitPoints ->
                    S.red1Str

                LowSupplies ->
                    S.yellow1Str

                LowFuel ->
                    S.red1Str

        background : String
        background =
            case warning of
                LowHitPoints ->
                    S.gray5Str

                LowSupplies ->
                    S.yellow5Str

                LowFuel ->
                    S.gray0Str

        border : { color : String, opacity : String }
        border =
            case warning of
                LowSupplies ->
                    { color = S.gray0Str
                    , opacity = "1"
                    }

                _ ->
                    { color = foreground
                    , opacity = "0.55"
                    }

        symbol : Svg msg
        symbol =
            case warning of
                LowHitPoints ->
                    Svg.path
                        [ SA.d "M20 5.5a5 5 0 0 0-7 0L12 6.5l-1-1a5 5 0 0 0-7 7L12 21l8-8.5a5 5 0 0 0 0-7Z"
                        , SA.fill foreground
                        ]
                        []

                LowSupplies ->
                    Svg.g
                        [ SA.fill "none"
                        , SA.stroke foreground
                        , SA.strokeWidth "2.4"
                        ]
                        [ Svg.circle
                            [ SA.cx "12"
                            , SA.cy "12"
                            , SA.r "5.3"
                            ]
                            []
                        , Svg.path
                            [ SA.d "M6.5 19L17.5 5"
                            ]
                            []
                        ]

                LowFuel ->
                    Svg.path
                        [ SA.d "M17 6H8V18H17M8 12H15"
                        , SA.fill "none"
                        , SA.stroke foreground
                        , SA.strokeWidth "2.6"
                        ]
                        []
    in
    Svg.svg
        [ SA.x (String.fromFloat (0.64 + toFloat index * 3.44))
        , SA.y "0.64"
        , SA.width "3.2"
        , SA.height "3.2"
        , SA.viewBox "0 0 24 24"
        ]
        [ Svg.rect
            [ SA.x "0.6"
            , SA.y "0.6"
            , SA.width "22.8"
            , SA.height "22.8"
            , SA.fill background
            , SA.stroke border.color
            , SA.strokeOpacity border.opacity
            , SA.strokeWidth "1.2"
            ]
            []
        , symbol
        ]
