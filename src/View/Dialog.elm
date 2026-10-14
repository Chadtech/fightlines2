module View.Dialog exposing
    ( Dialog
    , announcement
    , atBottom
    , make
    , map
    , reference
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
    | Announcement
    | Reference



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


announcement : Dialog msg -> Dialog msg
announcement (Dialog model) =
    Dialog { model | placement = Announcement }


reference : Dialog msg -> Dialog msg
reference (Dialog model) =
    Dialog { model | placement = Reference }


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

                Reference ->
                    [ S.w152
                    , S.maxHViewportInset8
                    , S.overflowAuto
                    ]

                Announcement ->
                    [ S.w152
                    , S.maxHViewportInset8
                    , S.overflowAuto
                    , S.backdrop
                        [ S.bgBlack70
                        ]
                    ]

                Bottom ->
                    [ S.fixed
                    , S.topAuto
                    , S.bottom18
                    , S.maxHViewportInsetRem 6
                    , S.overflowAuto
                    , S.w104
                    , S.backdrop
                        [ S.bgTransparent
                        ]
                    ]

        baseStyles : List Css.Style
        baseStyles =
            [ S.mAuto
            , S.maxWViewportInsetRem 2
            , S.w96
            , S.p0
            , S.bgGray1
            , S.textGray4
            , S.outdent
            ]

        titleFocusAttributes : List (H.Attribute msg)
        titleFocusAttributes =
            case model.placement of
                Reference ->
                    [ A.tabindex -1
                    , A.autofocus True
                    ]

                _ ->
                    []

        titleAttributes : List (H.Attribute msg)
        titleAttributes =
            [ A.id (model.htmlId ++ "-title")
            , A.css
                [ S.p2px ]
            ]
                ++ titleFocusAttributes

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
            titleAttributes
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
