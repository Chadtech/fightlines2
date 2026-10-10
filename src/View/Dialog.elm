module View.Dialog exposing
    ( Dialog
    , first
    , fromBody
    , map
    , modal
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
import Html.Styled.Events as Ev
import Json.Decode as Decode
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


{-| Native modal dialogs trap keyboard focus and make the board inert.
Open after Elm renders through the OpenDialog port effect.
-}
modal : String -> String -> msg -> List (Html msg) -> Html msg
modal id title onCancel body =
    Html.node "dialog"
        [ Attr.id id
        , Attr.attribute "aria-labelledby" (id ++ "-title")
        , Ev.preventDefaultOn "cancel" (Decode.succeed ( onCancel, True ))
        , Attr.css
            [ Css.margin Css.auto
            , Css.maxWidth (Css.calc (Css.vw 100) (Css.minus (Css.rem 2)))
            , Css.width (Css.rem 24)
            , S.p3
            , S.bgGray1
            , S.textGray4
            , S.outdent
            ]
        ]
        [ Html.div
            [ Attr.css
                [ S.col
                , S.g3
                ]
            ]
            (Html.h2
                [ Attr.id (id ++ "-title")
                , Attr.css [ S.textGray5 ]
                ]
                [ Html.text title
                ]
                :: body
            )
        ]
