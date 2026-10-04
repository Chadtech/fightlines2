module View.Dialog exposing
    ( Dialog
    , first
    , fromBody
    , map
    , none
    , toHtml
    , withHtmlId
    )

import Css
import Html.Styled as Html
    exposing
        ( Html
        )
import Html.Styled.Attributes as Attr
import Style as S



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Dialog msg
    = Open (Model msg)
    | None


type alias Model msg =
    { body : List (Html msg)
    , style : List Css.Style
    , htmlId : Maybe String
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


none : Dialog msg
none =
    None


fromBody : List Css.Style -> List (Html msg) -> Dialog msg
fromBody styles rows =
    Open
        { body = rows
        , style = styles
        , htmlId = Nothing
        }


map : (a -> msg) -> Dialog a -> Dialog msg
map toMsg dialog =
    case dialog of
        Open model ->
            Open
                { body = List.map (Html.map toMsg) model.body
                , style = model.style
                , htmlId = model.htmlId
                }

        None ->
            None


withHtmlId : String -> Dialog msg -> Dialog msg
withHtmlId id dialog =
    case dialog of
        Open model ->
            Open
                { body = model.body
                , style = model.style
                , htmlId = Just id
                }

        None ->
            None


first : List (() -> Dialog msg) -> Dialog msg
first dialogFns =
    case dialogFns of
        dialogFn :: rest ->
            case dialogFn () of
                None ->
                    first rest

                dialog ->
                    dialog

        [] ->
            None


toHtml : Dialog msg -> Html msg
toHtml dialog =
    case dialog of
        Open model ->
            let
                baseAttrs : List (Html.Attribute msg)
                baseAttrs =
                    [ Attr.css
                        [ S.absolute
                        , Css.left (Css.pct 50)
                        , Css.top (Css.pct 50)
                        , Css.transform (Css.translate2 (Css.pct -50) (Css.pct -50))
                        , S.p4
                        , S.border
                        , S.batch model.style
                        ]
                    ]

                conditionalAttrs : List (Html.Attribute msg)
                conditionalAttrs =
                    [ Maybe.map Attr.id model.htmlId
                    ]
                        |> List.filterMap identity
            in
            Html.div
                (baseAttrs ++ conditionalAttrs)
                model.body

        None ->
            Html.text ""
