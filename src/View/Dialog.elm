module View.Dialog exposing
    ( Dialog
    , make
    , map
    , toHtml
    )

import Css
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import View.CardHeader as CardHeader



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Dialog msg
    = Dialog
        { htmlId : String
        , title : String
        , onCancel : msg
        , body : List (Html msg)
        }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


make : String -> String -> msg -> List (Html msg) -> Dialog msg
make htmlId title onCancel body =
    Dialog
        { htmlId = htmlId
        , title = title
        , onCancel = onCancel
        , body = body
        }


map : (a -> msg) -> Dialog a -> Dialog msg
map toMsg (Dialog model) =
    Dialog
        { htmlId = model.htmlId
        , title = model.title
        , onCancel = toMsg model.onCancel
        , body = List.map (Html.map toMsg) model.body
        }


{-| Native modal dialogs trap keyboard focus and make the page inert.
Open after Elm renders through the OpenDialog port effect.
-}
toHtml : Dialog msg -> Html msg
toHtml (Dialog model) =
    Html.node "dialog"
        [ Attr.id model.htmlId
        , Attr.attribute "aria-labelledby" (model.htmlId ++ "-title")
        , Ev.preventDefaultOn "cancel" (Decode.succeed ( model.onCancel, True ))
        , Attr.css
            [ Css.margin Css.auto
            , Css.maxWidth (Css.calc (Css.vw 100) (Css.minus (Css.rem 2)))
            , Css.width (Css.rem 24)
            , S.p0
            , S.bgGray1
            , S.textGray4
            , S.outdent
            ]
        ]
        [ Html.div
            [ Attr.id (model.htmlId ++ "-title")
            , Attr.css [ S.p2px ]
            ]
            [ CardHeader.simple model.title
                |> CardHeader.toHtml
            ]
        , Html.div
            [ Attr.css
                [ S.col
                , S.g3
                , S.p3
                ]
            ]
            model.body
        ]
