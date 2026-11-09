module View.Dialog exposing
    ( Dialog
    , announcement
    , article
    , atBottom
    , form
    , fullscreen
    , htmlId
    , make
    , map
    , onCancel
    , onOpened
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
import View.CardHeader as CardHeader exposing (CardHeader)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Dialog msg
    = Dialog
        { htmlId : String
        , title : String
        , onCancel : msg
        , onOpened : Maybe msg
        , body : List (Html msg)
        , placement : Placement
        , fullscreen : Bool
        , showCloseButton : Bool
        , overlay : List (Html msg)
        }


type Placement
    = Centered
    | Bottom
    | Announcement
    | Reference
    | Article
    | Workspace
    | Form



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
        , onOpened = Nothing
        , body = body
        , placement = Centered
        , fullscreen = False
        , showCloseButton = False
        , overlay = []
        }


{-| Keep viewport controls in the native top layer while the page is inert.
-}
withOverlay : List (Html msg) -> Dialog msg -> Dialog msg
withOverlay overlay (Dialog model) =
    Dialog { model | overlay = model.overlay ++ overlay }


withCloseButton : Dialog msg -> Dialog msg
withCloseButton (Dialog model) =
    Dialog { model | showCloseButton = True }


onCancel : msg -> Dialog msg -> Dialog msg
onCancel canceled (Dialog model) =
    Dialog { model | onCancel = canceled }


{-| Notify the page after the native dialog becomes visible.
-}
onOpened : msg -> Dialog msg -> Dialog msg
onOpened opened (Dialog model) =
    Dialog { model | onOpened = Just opened }


announcement : Dialog msg -> Dialog msg
announcement =
    setPlacement Announcement


reference : Dialog msg -> Dialog msg
reference =
    setPlacement Reference


{-| A wide reading surface bounded below its title. Content owns its scrolling areas.
-}
article : Dialog msg -> Dialog msg
article =
    setPlacement Article


{-| A dialog with room for navigation beside a working pane.
-}
workspace : Dialog msg -> Dialog msg
workspace =
    setPlacement Workspace


{-| Fill the viewport while retaining the dialog's content and focus policy.
Long bodies scroll beneath the title.
-}
fullscreen : Dialog msg -> Dialog msg
fullscreen (Dialog model) =
    Dialog { model | fullscreen = True }


atBottom : Dialog msg -> Dialog msg
atBottom =
    setPlacement Bottom


form : Dialog msg -> Dialog msg
form =
    setPlacement Form


map : (a -> msg) -> Dialog a -> Dialog msg
map toMsg (Dialog model) =
    Dialog
        { htmlId = model.htmlId
        , title = model.title
        , onCancel = toMsg model.onCancel
        , onOpened = Maybe.map toMsg model.onOpened
        , body = List.map (H.map toMsg) model.body
        , placement = model.placement
        , fullscreen = model.fullscreen
        , showCloseButton = model.showCloseButton
        , overlay = List.map (H.map toMsg) model.overlay
        }


{-| Native modal dialogs trap keyboard focus and make the page inert.
Open after Elm renders through the OpenDialog port effect.
-}
toHtml : Dialog msg -> Html msg
toHtml (Dialog model) =
    let
        openedAttributes : List (H.Attribute msg)
        openedAttributes =
            case model.onOpened of
                Just opened ->
                    let
                        whenOpen : String -> Decode.Decoder msg
                        whenOpen state =
                            if state == "open" then
                                Decode.succeed opened

                            else
                                Decode.fail "dialog closed"
                    in
                    [ Ev.on "toggle" (Decode.field "newState" Decode.string |> Decode.andThen whenOpen) ]

                Nothing ->
                    []

        placementStyles : List Css.Style
        placementStyles =
            case model.placement of
                Form ->
                    [ S.w170
                    , S.maxHViewportInset8
                    , S.overflowAuto
                    , S.backdrop [ S.bgTransparent ]
                    ]

                Centered ->
                    []

                Reference ->
                    [ S.w152
                    , S.maxHViewportInset8
                    , S.overflowAuto
                    ]

                Article ->
                    [ S.w256
                    , S.maxHViewportInset8
                    , Css.property "max-height" "calc(100dvh - 2rem)"
                    , S.overflowHidden
                    , Css.pseudoClass "is([open])"
                        [ S.grid
                        , S.gridRows "auto minmax(0, 1fr)"
                        ]
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
            , S.maxHViewportInset8
            , S.overflowAuto
            ]

        header : CardHeader msg
        header =
            CardHeader.simple model.title
                |> CardHeader.withHtmlId (model.htmlId ++ "-title")

        focusedHeader : CardHeader msg
        focusedHeader =
            case model.placement of
                Reference ->
                    header
                        |> CardHeader.focusOnOpen

                Article ->
                    header
                        |> CardHeader.focusOnOpen

                Workspace ->
                    header
                        |> CardHeader.focusOnOpen

                _ ->
                    header

        headerContent : Html msg
        headerContent =
            if model.showCloseButton then
                focusedHeader
                    |> CardHeader.withActions
                        [ Button.secondary "×" model.onCancel
                            |> Button.iconOnly ("close " ++ model.title)
                            |> Button.toHtml
                        ]
                    |> CardHeader.toHtml

            else
                focusedHeader
                    |> CardHeader.toHtml

        fullscreenStyles : List Css.Style
        fullscreenStyles =
            if model.fullscreen then
                [ S.fixed
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.w100vw
                , S.h100dvh
                , S.maxWFull
                , S.maxH100vh
                , S.maxH100dvh
                , S.m0
                , S.overflowHidden
                , Css.pseudoClass "is([open])"
                    [ S.col ]
                ]

            else
                []

        dialogStyles : List Css.Style
        dialogStyles =
            baseStyles ++ placementStyles ++ fullscreenStyles

        placementBodyStyles : List Css.Style
        placementBodyStyles =
            case model.placement of
                Article ->
                    [ S.minH0
                    , S.overflowHidden
                    ]

                _ ->
                    []

        fullscreenBodyStyles : List Css.Style
        fullscreenBodyStyles =
            if model.fullscreen then
                [ S.flex1
                , S.minH0
                , S.overflowAuto
                ]

            else
                []

        bodyStyles : List Css.Style
        bodyStyles =
            [ S.col
            , S.g3
            , S.p3
            ]
                ++ placementBodyStyles
                ++ fullscreenBodyStyles

        content : List (Html msg)
        content =
            [ H.div
                [ A.css
                    [ S.p2px
                    , S.when model.fullscreen S.shrink0
                    ]
                ]
                [ headerContent ]
            , H.div
                [ A.css bodyStyles
                ]
                model.body
            ]
                ++ model.overlay

        attributes : List (H.Attribute msg)
        attributes =
            [ A.id model.htmlId
            , Aria.labelledBy (model.htmlId ++ "-title")
            , Ev.preventDefaultOn "cancel" (Decode.succeed ( model.onCancel, True ))
            , A.css dialogStyles
            ]
                ++ openedAttributes
    in
    H.node "dialog"
        attributes
        content
