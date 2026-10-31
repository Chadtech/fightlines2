module View.TextField exposing
    ( TextField
    , simple
    , toHtml
    , withHtmlId
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
    , htmlId : Maybe String
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


simple : String -> (String -> msg) -> TextField msg
simple initialValue onChange =
    { value = initialValue
    , onChange = onChange
    , htmlId = Nothing
    }


withHtmlId : String -> TextField msg -> TextField msg
withHtmlId htmlId textField =
    { textField | htmlId = Just htmlId }


toHtml : TextField msg -> Html msg
toHtml textField =
    let
        idAttributes : List (Html.Attribute msg)
        idAttributes =
            case textField.htmlId of
                Nothing ->
                    []

                Just htmlId ->
                    [ Attr.id htmlId ]

        fieldAttributes : List (Html.Attribute msg)
        fieldAttributes =
            [ Attr.css
                [ S.indentStrong
                , S.bgNightwood3
                , S.textGray5
                , S.caretRed1
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
    in
    Html.input
        (fieldAttributes ++ idAttributes)
        []
