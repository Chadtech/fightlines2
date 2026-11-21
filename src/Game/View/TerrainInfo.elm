module Game.View.TerrainInfo exposing
    ( helpButton
    , toHtml
    )

import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.Terrain as Terrain exposing (Terrain)
import Game.View.InspectionHelp as InspectionHelp exposing (Help(..))
import Game.View.TerrainTile as TerrainTile
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Html.Styled.Lazy as Lazy
import Style as S
import View.Aria as Aria
import View.InfoMarker as InfoMarker


toHtml : (Help -> msg) -> Map -> Coordinate -> Html msg
toHtml onHelp map position =
    Lazy.lazy3 inspectionView onHelp map position


inspectionView : (Help -> msg) -> Map -> Coordinate -> Html msg
inspectionView onHelp map position =
    H.div
        [ A.css
            [ S.col
            , S.g3
            ]
        ]
        [ helpButton onHelp map position
        , TerrainTile.portrait map position
        ]


helpButton : (Help -> msg) -> Map -> Coordinate -> Html msg
helpButton onHelp map position =
    let
        terrain : Terrain
        terrain =
            Map.terrainAt map position

        help : InspectionHelp.Help
        help =
            TerrainHelp { map = map, position = position }
    in
    H.button
        [ A.type_ "button"
        , A.id (InspectionHelp.buttonHtmlId help)
        , Aria.label ("about terrain: " ++ Terrain.label terrain)
        , A.attribute "aria-haspopup" "dialog"
        , Ev.onClick (onHelp help)
        , A.css
            [ S.row
            , S.itemsCenter
            , S.g2
            , S.p0
            , S.borderTransparent
            , S.bgTransparent
            , S.textGray4
            , S.pointerCursor
            , S.outlineNone
            , S.focusVisible
                [ S.underline
                ]
            ]
        ]
        [ H.text ("terrain: " ++ Terrain.label terrain)
        , InfoMarker.toHtml
        ]
