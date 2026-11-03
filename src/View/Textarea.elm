module View.Textarea exposing
    ( Textarea
    , readOnly
    , simple
    , toHtml
    , withAutofocus
    , withHtmlId
    )

import Css
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
    , htmlId : Maybe String
    , autofocus : Bool
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


simple : String -> (String -> msg) -> Textarea msg
simple value onInput =
    { value = value
    , onInput = Just onInput
    , htmlId = Nothing
    , autofocus = False
    }


readOnly : String -> Textarea msg
readOnly value =
    { value = value
    , onInput = Nothing
    , htmlId = Nothing
    , autofocus = False
    }


withHtmlId : String -> Textarea msg -> Textarea msg
withHtmlId htmlId textarea =
    { textarea | htmlId = Just htmlId }


withAutofocus : Textarea msg -> Textarea msg
withAutofocus textarea =
    { textarea | autofocus = True }


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
                , S.p2
                , Css.property "resize" "none"
                ]
            , Attr.autofocus textarea.autofocus
            , Attr.value textarea.value
            , Attr.readonly (textarea.onInput == Nothing)
            ]

        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Ev.onInput textarea.onInput
            , Maybe.map Attr.id textarea.htmlId
            ]
                |> List.filterMap identity
    in
    Html.textarea
        (baseAttrs ++ conditionalAttrs)
        []
