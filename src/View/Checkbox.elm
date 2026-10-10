module View.Checkbox exposing (toHtml)

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S


toHtml : { label : String, checked : Bool, onCheck : Bool -> msg } -> List (Html msg) -> Html msg
toHtml config content =
    let
        checkbox : Html msg
        checkbox =
            H.input
                [ A.type_ "checkbox"
                , A.attribute "aria-label" config.label
                , A.checked config.checked
                , Ev.onCheck config.onCheck
                , A.css
                    [ S.appearanceNone
                    , S.w5
                    , S.h5
                    , S.m0
                    , S.shrink0
                    , S.bgNightwood3
                    , S.textGray0
                    , S.indentStrong
                    , S.pointerCursor
                    , S.grid
                    , S.placeContentCenter
                    , Css.pseudoClass "checked"
                        [ S.bgGray4

                        -- U+2713 draws the checkmark only while checked.
                        , Css.pseudoElement "after"
                            [ Css.property "content" "'\\2713'"
                            ]
                        ]
                    , Css.pseudoClass "focus-visible"
                        [ Css.outline3 (Css.px 1) Css.solid (Css.hex S.yellow5Str)
                        , Css.outlineOffset (Css.px 3)
                        ]
                    ]
                ]
                []
    in
    H.label
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g2
            , S.pointerCursor
            ]
        ]
        (checkbox :: content)
