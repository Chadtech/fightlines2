module View.Checkbox exposing
    ( Checkbox
    , disabled
    , new
    , toHtml
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import View.Aria as Aria



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Checkbox msg
    = Checkbox
        { label : String
        , checked : Bool
        , onCheck : Bool -> msg
        , disabled : Bool
        }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


new :
    { label : String
    , checked : Bool
    , onCheck : Bool -> msg
    }
    -> Checkbox msg
new config =
    Checkbox
        { label = config.label
        , checked = config.checked
        , onCheck = config.onCheck
        , disabled = False
        }


disabled : Bool -> Checkbox msg -> Checkbox msg
disabled value (Checkbox config) =
    Checkbox { config | disabled = value }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : List (Html msg) -> Checkbox msg -> Html msg
toHtml content (Checkbox config) =
    let
        checkbox : Html msg
        checkbox =
            H.input
                [ A.type_ "checkbox"
                , Aria.label config.label
                , A.checked config.checked
                , A.disabled config.disabled
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
                    , Css.pseudoClass "disabled"
                        [ Css.opacity (Css.num 0.5)
                        , Css.cursor Css.notAllowed
                        ]
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
