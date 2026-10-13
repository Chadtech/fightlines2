module View.Dialog exposing
    ( Dialog
    , atBottom
    , make
    , map
    , toHtml
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import View.Aria as Aria
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
        , placement : Placement
        }


type Placement
    = Centered
    | Bottom



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
        , placement = Centered
        }


atBottom : Dialog msg -> Dialog msg
atBottom (Dialog model) =
    Dialog { model | placement = Bottom }


map : (a -> msg) -> Dialog a -> Dialog msg
map toMsg (Dialog model) =
    Dialog
        { htmlId = model.htmlId
        , title = model.title
        , onCancel = toMsg model.onCancel
        , body = List.map (H.map toMsg) model.body
        , placement = model.placement
        }


{-| Native modal dialogs trap keyboard focus and make the page inert.
Open after Elm renders through the OpenDialog port effect.
-}
toHtml : Dialog msg -> Html msg
toHtml (Dialog model) =
    let
        placementStyles : List Css.Style
        placementStyles =
            case model.placement of
                Centered ->
                    []

                Bottom ->
                    [ Css.position Css.fixed
                    , Css.top Css.auto
                    , Css.bottom (Css.rem 4.5)
                    , Css.maxHeight (Css.calc (Css.vh 100) (Css.minus (Css.rem 6)))
                    , S.overflowAuto
                    , Css.width (Css.rem 26)
                    , Css.pseudoElement "backdrop"
                        [ Css.backgroundColor Css.transparent
                        ]
                    ]

        baseStyles : List Css.Style
        baseStyles =
            [ Css.margin Css.auto
            , Css.maxWidth (Css.calc (Css.vw 100) (Css.minus (Css.rem 2)))
            , Css.width (Css.rem 24)
            , S.p0
            , S.bgGray1
            , S.textGray4
            , S.outdent
            ]

        dialogStyles : List Css.Style
        dialogStyles =
            baseStyles ++ placementStyles
    in
    H.node "dialog"
        [ A.id model.htmlId
        , Aria.labelledBy (model.htmlId ++ "-title")
        , Ev.preventDefaultOn "cancel" (Decode.succeed ( model.onCancel, True ))
        , A.css dialogStyles
        ]
        [ H.div
            [ A.id (model.htmlId ++ "-title")
            , A.css
                [ S.p2px
                ]
            ]
            [ CardHeader.simple model.title
                |> CardHeader.toHtml
            ]
        , H.div
            [ A.css
                [ S.col
                , S.g3
                , S.p3
                ]
            ]
            model.body
        ]
