module View.TextField exposing
    ( TextField
    , simple
    , toHtml
    )

import Css
import Html.Styled as Html
    exposing
        ( Html
        )
import Html.Styled.Attributes as Attr
import Html.Styled.Events as Ev
import Style as S



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias TextField msg =
    { value : String
    , onChange : String -> msg
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


simple : String -> (String -> msg) -> TextField msg
simple initialValue onChange =
    { value = initialValue
    , onChange = onChange
    }


toHtml : TextField msg -> Html msg
toHtml textField =
    Html.input
        [ Attr.css
            [ S.indent
            , S.bgNightwood1
            , S.textGray4
            , Css.focus
                [ S.textGray5
                ]
            , S.outlineNone
            , S.p2
            , S.wFull
            ]
        , Attr.type_ "text"
        , Attr.value textField.value
        , Ev.onInput textField.onChange
        ]
        []
