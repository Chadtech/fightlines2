module View.Textarea exposing
    ( Textarea
    , readOnly
    , simple
    , toHtml
    )

import Html.Styled as Html
    exposing
        ( Attribute
        , Html
        )
import Html.Styled.Attributes as Attr
import Html.Styled.Events as Ev
import Style as S



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Textarea msg =
    { value : String
    , onInput : Maybe (String -> msg)
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


simple : String -> (String -> msg) -> Textarea msg
simple value onInput =
    { value = value
    , onInput = Just onInput
    }


readOnly : String -> Textarea msg
readOnly value =
    { value = value
    , onInput = Nothing
    }


toHtml : Textarea msg -> Html msg
toHtml textarea =
    let
        baseAttrs : List (Attribute msg)
        baseAttrs =
            [ Attr.css
                [ S.outlineNone
                , S.indent
                , S.bgNightwood1
                , S.wFull
                , S.hFull
                , S.textGray4
                ]
            , Attr.value textarea.value
            ]

        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Ev.onInput textarea.onInput
            ]
                |> List.filterMap identity
    in
    Html.textarea
        (baseAttrs ++ conditionalAttrs)
        []
