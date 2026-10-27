module Fightlines.View.MapChoice exposing (toHtml)

import EditableMap exposing (NamedMap)
import Game.MapId as MapId
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import View.Aria as Aria


toHtml : { map : NamedMap, selected : Bool, onSelect : msg } -> Html msg
toHtml args =
    let
        pressed : String
        pressed =
            if args.selected then
                "true"

            else
                "false"

        mark : Html msg
        mark =
            if args.selected then
                H.span
                    [ Aria.hidden True
                    , A.css
                        [ S.textYellow5
                        , S.shrink0
                        ]
                    ]
                    [ H.text "✓"
                    ]

            else
                H.text ""
    in
    H.button
        [ A.type_ "button"
        , Ev.onClick args.onSelect
        , A.attribute "aria-pressed" pressed
        , Aria.label ("preview " ++ MapId.label args.map.mapType)
        , A.css
            [ S.row
            , S.itemsCenter
            , S.g3
            , S.p2
            , S.wFull
            , S.bgNightwood3
            , S.evenChildren
                [ S.bgNightwood2
                ]
            , S.textLeft
            , S.textGray5
            , S.border
            , S.borderTransparent
            , S.pointerCursor
            , S.hover
                [ S.bgGray2
                ]
            , S.when args.selected
                (S.batch
                    [ S.bgGray2
                    , S.evenChildren
                        [ S.bgGray2
                        ]
                    , S.outlineYellow5
                    , S.outlineOffsetNeg1
                    ]
                )
            , S.focusVisible
                [ S.outlineYellow5
                , S.outlineOffsetNeg3
                ]
            ]
        ]
        [ H.span
            [ Aria.hidden True
            , A.css
                [ S.w20
                , S.h16
                , S.shrink0
                , S.bgNightwood2
                ]
            ]
            [ H.img
                [ A.src args.map.thumbnailUrl
                , A.alt ""
                , A.css
                    [ S.block
                    , S.wFull
                    , S.hFull
                    , S.objectContain
                    ]
                ]
                []
            ]
        , H.span
            [ A.css
                [ S.col
                , S.g1
                , S.flex1
                , S.minW0
                ]
            ]
            [ H.span
                []
                [ H.text (MapId.label args.map.mapType)
                ]
            , H.span
                [ A.css
                    [ S.textGray4
                    ]
                ]
                [ H.text (String.fromInt args.map.definition.width ++ " × " ++ String.fromInt args.map.definition.height)
                ]
            ]
        , mark
        ]
