module View.TextField exposing
    ( TextField
    , accessibleLabel
    , disabled
    , simple
    , toHtml
    , withAutofocus
    , withHtmlId
    , withoutAutocomplete
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
    , accessibleLabel : Maybe String
    , isDisabled : Bool
    , autofocus : Bool
    , autocomplete : Bool
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


simple : String -> (String -> msg) -> TextField msg
simple initialValue onChange =
    { value = initialValue
    , onChange = onChange
    , htmlId = Nothing
    , accessibleLabel = Nothing
    , isDisabled = False
    , autofocus = False
    , autocomplete = True
    }


withHtmlId : String -> TextField msg -> TextField msg
withHtmlId htmlId textField =
    { textField | htmlId = Just htmlId }


accessibleLabel : String -> TextField msg -> TextField msg
accessibleLabel label textField =
    { textField | accessibleLabel = Just label }


disabled : Bool -> TextField msg -> TextField msg
disabled isDisabled textField =
    { textField | isDisabled = isDisabled }


withAutofocus : TextField msg -> TextField msg
withAutofocus textField =
    { textField | autofocus = True }


withoutAutocomplete : TextField msg -> TextField msg
withoutAutocomplete textField =
    { textField | autocomplete = False }


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
                    , S.outlineYellow5
                    ]
                , S.outlineNone
                , S.p2
                , S.wFull
                ]
            , Attr.type_ "text"
            , Attr.disabled textField.isDisabled
            , Attr.autofocus textField.autofocus
            , Attr.value textField.value
            , Ev.onInput textField.onChange
            ]

        accessibleLabelAttributes : List (Html.Attribute msg)
        accessibleLabelAttributes =
            case textField.accessibleLabel of
                Just label ->
                    [ Attr.attribute "aria-label" label ]

                Nothing ->
                    []

        autocompleteAttributes : List (Html.Attribute msg)
        autocompleteAttributes =
            if textField.autocomplete then
                []

            else
                [ Attr.autocomplete False ]
    in
    Html.input
        (fieldAttributes ++ idAttributes ++ accessibleLabelAttributes ++ autocompleteAttributes)
        []
