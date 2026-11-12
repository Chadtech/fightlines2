module View.Checkbox exposing
    ( Checkbox
    , card
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


type Layout
    = Inline
    | Card



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
toHtml =
    view Inline


{-| Make the whole card a label for its native checkbox.
-}
card : List (Html msg) -> Checkbox msg -> Html msg
card =
    view Card


view : Layout -> List (Html msg) -> Checkbox msg -> Html msg
view layout content (Checkbox config) =
    let
        isCard : Bool
        isCard =
            layout == Card

        sizeStyles : List Css.Style
        sizeStyles =
            if isCard then
                [ S.square7
                , S.font5
                , S.absolute
                , S.top2
                , S.right2
                ]

            else
                [ S.w5
                , S.h5
                ]

        checkedFill : Css.Style
        checkedFill =
            if isCard then
                Css.backgroundColor (Css.hex S.yellow5Str)

            else
                S.bgGray4

        inputStyles : List Css.Style
        inputStyles =
            [ S.appearanceNone
            , S.m0
            , S.shrink0
            , S.bgNightwood3
            , S.textGray0
            , S.indentStrong
            , S.pointerCursor
            , S.grid
            , S.placeContentCenter
            , Css.pseudoClass "disabled"
                [ S.opacity0p5
                , S.notAllowedCursor
                ]
            , Css.pseudoClass "checked"
                [ checkedFill

                -- U+2713 draws the checkmark only while checked.
                , Css.pseudoElement "after"
                    [ Css.property "content" "'\\2713'"
                    ]
                ]
            ]
                ++ sizeStyles

        layoutStyles : List Css.Style
        layoutStyles =
            if isCard then
                [ S.relative
                , S.bgGray2
                , S.outdent
                , S.p3
                , S.pt10
                , S.g3
                , S.minW0
                , S.when config.checked
                    [ S.bgYellow1
                    , S.borderYellow5
                    ]
                , S.when config.disabled [ S.notAllowedCursor ]
                ]

            else
                [ S.g2 ]

        labelStyles : List Css.Style
        labelStyles =
            [ S.row
            , S.itemsCenter
            , S.pointerCursor
            ]
                ++ layoutStyles

        checkbox : Html msg
        checkbox =
            H.input
                [ A.type_ "checkbox"
                , Aria.label config.label
                , A.checked config.checked
                , A.disabled config.disabled
                , Ev.onCheck config.onCheck
                , A.css inputStyles
                ]
                []
    in
    H.label
        [ A.css labelStyles
        ]
        (checkbox :: content)
