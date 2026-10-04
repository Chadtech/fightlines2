module View.PersonProfile exposing (view)

import Html.Styled as H
    exposing
        ( Html
        )
import Html.Styled.Attributes as A
import Style as S


view :
    { name : String
    , id : String
    }
    -> List (Html msg)
    -> Html msg
view person controls =
    H.div
        [ A.css
            [ S.minHFullViewport
            , S.itemsStart
            , S.justifyCenter
            , S.p4
            , S.row
            , S.wFull
            ]
        ]
        [ H.article
            [ A.css
                [ S.bgGray1
                , S.col
                , S.g3
                , S.outdent
                , S.p3
                , S.wFull
                , S.minW0
                , S.wrapAnywhere
                ]
            ]
            ([ H.h1
                [ A.css
                    [ S.textGray3
                    ]
                ]
                [ H.text person.name
                ]
             , H.dl
                [ A.css
                    [ S.col
                    , S.g2
                    ]
                ]
                [ detail "Name" person.name
                , detail "ID" person.id
                ]
             ]
                ++ controls
            )
        ]


detail : String -> String -> H.Html msg
detail label value =
    H.div
        [ A.css
            [ S.g2
            , S.row
            , S.flexWrap
            ]
        ]
        [ H.dt
            [ A.css
                [ S.textGray3
                ]
            ]
            [ H.text label
            ]
        , H.dd
            [ A.css
                [ S.textGray4
                ]
            ]
            [ H.text value
            ]
        ]
