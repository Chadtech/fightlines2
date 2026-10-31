module View.Dialog exposing
    ( Dialog
    , announcement
    , atBottom
    , htmlId
    , make
    , map
    , onCancel
    , reference
    , toHtml
    , withCloseButton
    , withOverlay
    , workspace
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import View.Aria as Aria
import View.Button as Button
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
        , showCloseButton : Bool
        , overlay : List (Html msg)
        }


type Placement
    = Centered
    | Bottom
    | Announcement
    | Reference
    | Workspace



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setPlacement : Placement -> Dialog msg -> Dialog msg
setPlacement placement (Dialog model) =
    Dialog { model | placement = placement }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


htmlId : Dialog msg -> String
htmlId (Dialog model) =
    model.htmlId


make : String -> String -> msg -> List (Html msg) -> Dialog msg
make dialogHtmlId title canceled body =
    Dialog
        { htmlId = dialogHtmlId
        , title = title
        , onCancel = canceled
        , body = body
        , placement = Centered
        , showCloseButton = False
        , overlay = []
        }


{-| Keep viewport controls in the native top layer while the page is inert.
-}
withOverlay : List (Html msg) -> Dialog msg -> Dialog msg
withOverlay overlay (Dialog model) =
    Dialog { model | overlay = overlay }


withCloseButton : Dialog msg -> Dialog msg
withCloseButton (Dialog model) =
    Dialog { model | showCloseButton = True }


onCancel : msg -> Dialog msg -> Dialog msg
onCancel canceled (Dialog model) =
    Dialog { model | onCancel = canceled }


announcement : Dialog msg -> Dialog msg
announcement =
    setPlacement Announcement


reference : Dialog msg -> Dialog msg
reference =
    setPlacement Reference


{-| A dialog with room for navigation beside a working pane.
-}
workspace : Dialog msg -> Dialog msg
workspace =
    setPlacement Workspace


atBottom : Dialog msg -> Dialog msg
atBottom =
    setPlacement Bottom


map : (a -> msg) -> Dialog a -> Dialog msg
map toMsg (Dialog model) =
    Dialog
        { htmlId = model.htmlId
        , title = model.title
        , onCancel = toMsg model.onCancel
        , body = List.map (H.map toMsg) model.body
        , placement = model.placement
        , showCloseButton = model.showCloseButton
        , overlay = List.map (H.map toMsg) model.overlay
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

                Workspace ->
                    [ S.w196
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

                Workspace ->
                    [ A.tabindex -1
                    , A.autofocus True
                    ]

                _ ->
                    []

        titleAttributes : List (H.Attribute msg)
        titleAttributes =
            [ A.id (model.htmlId ++ "-title")
            , A.css
                [ S.p2px
                , S.when (model.placement == Workspace) S.outlineNone
                ]
            ]
                ++ titleFocusAttributes

        titleContent : Html msg
        titleContent =
            H.div
                titleAttributes
                [ CardHeader.simple model.title
                    |> CardHeader.toHtml
                ]

        headerContent : Html msg
        headerContent =
            if model.showCloseButton then
                H.div
                    [ A.css
                        [ S.row
                        , S.itemsCenter
                        , S.bgGray3
                        , S.p2px
                        ]
                    ]
                    [ H.div
                        [ A.css
                            [ S.flex1
                            , S.minW0
                            ]
                        ]
                        [ titleContent ]
                    , Button.secondary "×" model.onCancel
                        |> Button.titleBar
                        |> Button.accessibleLabel ("close " ++ model.title)
                        |> Button.toHtml
                    ]

            else
                titleContent

        dialogStyles : List Css.Style
        dialogStyles =
            baseStyles ++ placementStyles

        content : List (Html msg)
        content =
            [ headerContent
            , H.div
                [ A.css
                    [ S.col
                    , S.g3
                    , S.p3
                    ]
                ]
                model.body
            ]
                ++ model.overlay
    in
    H.node "dialog"
        [ A.id model.htmlId
        , Aria.labelledBy (model.htmlId ++ "-title")
        , Ev.preventDefaultOn "cancel" (Decode.succeed ( model.onCancel, True ))
        , A.css dialogStyles
        ]
        content
