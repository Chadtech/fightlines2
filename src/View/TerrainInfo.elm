module View.TerrainInfo exposing (toHtml)

import Api.Enum.Terrain as Terrain exposing (Terrain)
import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Terrain
import View.Aria as Aria
import View.InfoMarker as InfoMarker


toHtml : Terrain -> Html msg
toHtml terrain =
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
                , Css.pseudoElement "-webkit-details-marker"
                    [ S.displayNone
                    ]
                , S.outlineNone
                , Css.pseudoClass "focus-visible"
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
                , Css.marginTop (Css.rem 0.5)
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
        Terrain.GrassPlain ->
            "open ground, units can easily traverse it, but are also easily spotted by enemies."

        Terrain.Hills ->
            "units on top of hills have greater line of sight and can see over obstacles (forests and other hills)."

        Terrain.Forest ->
            "units inside forests are completely concealed, forests also obstruct line of sight."
