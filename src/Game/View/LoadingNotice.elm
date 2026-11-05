module Game.View.LoadingNotice exposing (toHtml)

import Game.Unit exposing (Unit)
import Game.UnitKind as UnitKind
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria


toHtml : { passenger : Unit, truck : Unit } -> Html msg
toHtml loading =
    H.div
        [ Aria.role Aria.Status
        , A.css
            [ S.bgYellow2
            , S.textGray5
            , S.p2px
            ]
        ]
        [ H.div
            [ Aria.role Aria.Image
            , Aria.label (UnitKind.label loading.passenger.kind ++ " boarding truck")
            , A.css
                [ S.grid
                , S.gridColumns "minmax(0, 1fr) 1.5rem minmax(0, 1fr)"
                , S.itemsCenter
                , S.bgNightwood3
                , S.py2
                , S.px1
                ]
            ]
            [ portrait loading.passenger
            , H.span
                [ Aria.hidden True
                , A.css
                    [ S.row
                    , S.justifyCenter
                    , S.textGray4
                    ]
                ]
                [ H.text "→" ]
            , portrait loading.truck
            ]
        , H.div
            [ A.css
                [ S.col
                , S.itemsCenter
                , S.justifyCenter
                , S.g1
                , S.minH20
                , S.p3
                ]
            ]
            [ H.p
                []
                [ H.text "boards truck" ]
            , H.p
                []
                [ H.text "when both arrive" ]
            ]
        ]


portrait : Unit -> Html msg
portrait unit =
    let
        appearance : UnitSprite.Appearance
        appearance =
            UnitSprite.appearance unit
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat (UnitSprite.portraitWidth appearance) ++ " 16")
        , SA.width "100%"
        , SA.height "88"
        , Aria.hidden True
        , SA.css
            [ S.block
            , S.minW0
            ]
        ]
        [ UnitSprite.portraitToSvg appearance ]
