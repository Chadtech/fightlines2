module View.SupplyCrate exposing
    ( toHtml
    , toSvg
    )

import Api.Enum.DepotKind exposing (DepotKind)
import Html.Attributes as A
import Html.Lazy as Lazy
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as HA
import Style as S
import Supply
import Svg exposing (Svg)
import Svg.Attributes as SA
import View.Aria as Aria
import View.StockGauge as StockGauge


{-| Illustrated neutral freight. Interaction belongs to its tile.
-}
toSvg : DepotKind -> Svg msg
toSvg kind =
    Lazy.lazy crateView kind


crateView : DepotKind -> Svg msg
crateView kind =
    Svg.image
        [ SA.x "2"
        , SA.y "2"
        , SA.width "12"
        , SA.height "12"
        , SA.xlinkHref (Supply.cargoImage kind)
        , A.style "image-rendering" "auto"
        , SA.pointerEvents "none"
        , Aria.svgHidden True
        ]
        []


toHtml : { lastSeen : Bool } -> Supply.CargoStock -> Html msg
toHtml observation stock =
    let
        description : String
        description =
            "refills "
                ++ Supply.resourceLabel stock.kind
                ++ " on or beside this square before upkeep, while stock lasts. trucks with cargo room collect it by ending on its square."

        observationDetails : List (Html msg)
        observationDetails =
            if observation.lastSeen then
                [ H.p
                    []
                    [ H.text "last seen" ]
                ]

            else
                []

        contents : List (Html msg)
        contents =
            [ H.h2
                []
                [ H.text (Supply.cargoLabel stock.kind)
                ]
            , H.div
                [ HA.css
                    [ S.bgNightwood3
                    , S.indentStrong
                    , S.p3
                    , S.row
                    , S.justifyCenter
                    ]
                ]
                [ H.img
                    [ HA.src (Supply.cargoImage stock.kind)
                    , HA.alt (Supply.cargoLabel stock.kind)
                    , HA.css
                        [ S.block
                        , S.w128px
                        , S.h128px
                        , S.maxWFull
                        , S.objectContain
                        ]
                    ]
                    []
                ]
            , StockGauge.toHtml
                { label = Supply.resourceLabel stock.kind
                , accessibleLabel = Supply.cargoLabel stock.kind ++ " " ++ Supply.resourceLabel stock.kind
                , description = description
                }
                { current = stock.current
                , maximum = stock.maximum
                }
            ]
    in
    H.div
        [ HA.css
            [ S.col
            , S.g3
            , S.textGray5
            ]
        ]
        (contents ++ observationDetails)
