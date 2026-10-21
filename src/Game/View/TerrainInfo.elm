module Game.View.TerrainInfo exposing (toHtml)

import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.Terrain as Terrain exposing (Terrain)
import Game.Terrain as Terrain
import Game.View.TerrainTile as TerrainTile
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.InfoMarker as InfoMarker


toHtml : MapTheme -> Terrain -> Html msg
toHtml theme terrain =
    Lazy.lazy2 inspectionView theme terrain


inspectionView : MapTheme -> Terrain -> Html msg
inspectionView theme terrain =
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ terrainView terrain
        , H.div
            [ A.css
                [ S.bgNightwood3
                , S.indentStrong
                , S.p3
                , S.row
                , S.justifyCenter
                ]
            ]
            [ Svg.svg
                [ SA.viewBox "0 0 16 16"
                , Aria.role Aria.Image
                , Aria.label (Terrain.label terrain)
                , A.css
                    [ S.block
                    , S.w128px
                    , S.h128px
                    , S.maxWFull
                    ]
                ]
                [ TerrainTile.toSvg { theme = theme, terrain = terrain } ]
                |> Svg.toUnstyled
                |> H.fromUnstyled
            ]
        ]


terrainView : Terrain -> Html msg
terrainView terrain =
    H.details
        [ A.css
            [ S.textGray4
            ]
        ]
        [ H.summary
            [ Aria.label ("about terrain: " ++ Terrain.label terrain)
            , A.css
                [ S.row
                , S.itemsCenter
                , S.g2
                , S.pointerCursor
                , S.listStyleNone
                , S.hideDetailsMarker
                , S.outlineNone
                , S.focusVisible
                    [ S.underline
                    ]
                ]
            ]
            [ H.text ("terrain: " ++ Terrain.label terrain)
            , InfoMarker.toHtml
            ]
        , H.div
            [ A.css
                [ S.col
                , S.g2
                , S.bgYellow2
                , S.textGray5
                , S.p2
                , S.mt2
                ]
            ]
            [ H.p
                []
                [ H.text (visibilityText terrain)
                ]
            ]
        ]


visibilityText : Terrain -> String
visibilityText terrain =
    case terrain of
        Terrain.Plain ->
            "open ground, units can easily traverse it, but are also easily spotted by enemies."

        Terrain.Hills ->
            "units on top of hills have greater line of sight and can see over obstacles (forests and other hills)."

        Terrain.Mountains ->
            "mountains give +2 line of sight and let infantry see over obstacles. each mountain square costs infantry 2 movement points (1 extra). tanks, trucks, and field guns cannot cross mountains."

        Terrain.Forest ->
            "units inside forests are completely concealed, forests also obstruct line of sight."
