module View.Button exposing
    ( Button
    , accessibleLabel
    , attention
    , choice
    , compact
    , disabled
    , fullWidth
    , highlighted
    , large
    , onClick
    , primary
    , secondary
    , small
    , square
    , styles
    , tall
    , titleBar
    , toHtml
    , withFeedback
    , withHtmlId
    , withIcon
    )

import Css
import Html.Styled as H
    exposing
        ( Attribute
        , Html
        )
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Style as S
import View.Aria as Aria



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Button msg =
    { accessibleLabel : Maybe String
    , htmlId : Maybe String
    , onClick : Maybe msg
    , label : String
    , variant : Variant
    , size : Size
    , icon : Maybe (Html msg)
    , feedback : Maybe String
    , fullWidth : Bool
    , emphasis : Emphasis
    }


type Variant
    = Variant__Primary
    | Variant__Secondary
    | Disabled
    | Choice Bool


type Size
    = Small
    | Compact
    | Square
    | TitleBar
    | Regular
    | Large
    | Tall


type Emphasis
    = Normal
    | Highlighted
    | Attention



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


fromLabelAndVariant : String -> Variant -> Button msg
fromLabelAndVariant label variant =
    { accessibleLabel = Nothing
    , htmlId = Nothing
    , onClick = Nothing
    , label = label
    , variant = variant
    , size = Regular
    , icon = Nothing
    , feedback = Nothing
    , fullWidth = False
    , emphasis = Normal
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


secondary : String -> msg -> Button msg
secondary label msg =
    fromLabelAndVariant label Variant__Secondary
        |> onClick msg


primary : String -> msg -> Button msg
primary label msg =
    fromLabelAndVariant label Variant__Primary
        |> onClick msg


choice : String -> Bool -> msg -> Button msg
choice label selected msg =
    fromLabelAndVariant label (Choice selected)
        |> onClick msg


withIcon : Html msg -> Button msg -> Button msg
withIcon icon button =
    { button | icon = Just icon }


withHtmlId : String -> Button msg -> Button msg
withHtmlId htmlId button =
    { button
        | htmlId = Just htmlId
    }


{-| Replace the label with feedback while reserving the space for both labels.
-}
withFeedback : Maybe String -> Button msg -> Button msg
withFeedback feedback button =
    { button | feedback = feedback }


onClick : msg -> Button msg -> Button msg
onClick msg button =
    { button
        | onClick = Just msg
    }


accessibleLabel : String -> Button msg -> Button msg
accessibleLabel label button =
    { button | accessibleLabel = Just label }


disabled : String -> Button msg
disabled label =
    fromLabelAndVariant label Disabled


small : Button msg -> Button msg
small button =
    { button
        | size = Small
    }


compact : Button msg -> Button msg
compact button =
    { button
        | size = Compact
    }


square : Button msg -> Button msg
square button =
    { button
        | size = Square
    }


{-| Fill a window title bar vertically without fixing the button's height.
-}
titleBar : Button msg -> Button msg
titleBar button =
    { button | size = TitleBar }


tall : Button msg -> Button msg
tall button =
    { button
        | size = Tall
    }


highlighted : Button msg -> Button msg
highlighted button =
    { button
        | emphasis = Highlighted
    }


attention : Button msg -> Button msg
attention button =
    { button
        | emphasis = Attention
    }


large : Button msg -> Button msg
large button =
    { button | size = Large }


fullWidth : Button msg -> Button msg
fullWidth button =
    { button | fullWidth = True }


toHtml : Button msg -> Html msg
toHtml button =
    let
        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Ev.onClick button.onClick
            , Maybe.map A.id button.htmlId
            , Maybe.map Aria.label button.accessibleLabel
            , Maybe.map A.title button.accessibleLabel
            ]
                |> List.filterMap identity

        selectionAttrs : List (Attribute msg)
        selectionAttrs =
            case button.variant of
                Choice selected ->
                    let
                        pressed : String
                        pressed =
                            if selected then
                                "true"

                            else
                                "false"
                    in
                    [ A.attribute "aria-pressed" pressed
                    ]

                _ ->
                    []

        content : List (Html msg)
        content =
            List.filterMap identity
                [ button.icon
                , Just
                    (H.span
                        [ A.css
                            [ Css.property "display" "inline-grid"
                            ]
                        ]
                        [ H.span
                            [ A.css
                                [ Css.property "grid-area" "1 / 1"
                                , S.when (button.feedback /= Nothing) (Css.visibility Css.hidden)
                                ]
                            ]
                            [ H.text button.label
                            ]
                        , H.span
                            [ A.attribute "aria-live" "polite"
                            , A.css
                                [ Css.property "grid-area" "1 / 1"
                                ]
                            ]
                            [ H.text (Maybe.withDefault "" button.feedback)
                            ]
                        ]
                    )
                ]

        iconStyles : List Css.Style
        iconStyles =
            case button.icon of
                Just _ ->
                    [ S.row
                    , S.itemsCenter
                    , S.justifyCenter
                    , S.g2
                    ]

                Nothing ->
                    []

        baseAttrs : List (Attribute msg)
        baseAttrs =
            let
                variantStyles : List Css.Style
                variantStyles =
                    case button.variant of
                        Disabled ->
                            [ S.bgGray1
                            , S.textGray3
                            , S.indent
                            , Css.cursor Css.notAllowed
                            ]

                        Variant__Primary ->
                            [ S.bgYellow2
                            , S.textYellow5
                            , S.importantOutdent
                            , Css.hover
                                [ S.textYellow6
                                ]
                            , Css.active
                                [ S.textYellow6
                                , S.importantIndent
                                ]
                            ]

                        Choice selected ->
                            [ S.row
                            , S.itemsCenter
                            , S.justifyCenter
                            , S.g2
                            , S.bgGray1
                            , S.textGray4
                            , S.wFull
                            , S.selfStretch
                            , S.when selected
                                (S.batch
                                    [ S.bgNightwood3
                                    , S.textGray5
                                    , S.indentStrong
                                    ]
                                )
                            , S.when (not selected) S.outdentStrong
                            , Css.hover
                                [ S.textGray5
                                ]
                            ]

                        Variant__Secondary ->
                            [ S.bgGray1
                            , S.textGray4
                            , S.outdentStrong
                            , Css.hover
                                [ S.bgGray2
                                , S.textGray5
                                ]
                            , Css.active
                                [ S.bgGray2
                                , S.textGray5
                                , S.indentStrong
                                ]
                            ]

                sizeStyles : List Css.Style
                sizeStyles =
                    case button.size of
                        Small ->
                            [ S.p1
                            ]

                        Compact ->
                            [ S.h6p5
                            , S.minW6p5
                            , S.p0
                            , S.lineHeight1
                            ]

                        Square ->
                            [ S.w6p5
                            , S.h6p5
                            , S.minW6p5
                            , S.p0
                            , S.lineHeight1
                            ]

                        TitleBar ->
                            [ S.w8
                            , S.minW6p5
                            , S.selfStretch
                            , S.shrink0
                            , S.p0
                            , S.lineHeight1
                            ]

                        Regular ->
                            case button.variant of
                                Choice _ ->
                                    [ S.p2
                                    ]

                                _ ->
                                    [ S.px4
                                    , S.py3
                                    ]

                        Large ->
                            [ S.px6
                            , S.py4
                            , S.minH14
                            ]

                        Tall ->
                            [ S.px2
                            , S.py3
                            , S.minH14
                            ]

                emphasisStyles : Css.Style
                emphasisStyles =
                    case button.emphasis of
                        Normal ->
                            S.batch []

                        Highlighted ->
                            S.textYellow5

                        Attention ->
                            attentionStyles
            in
            [ A.disabled (button.variant == Disabled)
            , A.css
                [ Css.alignSelf Css.flexStart
                , S.batch sizeStyles
                , S.batch iconStyles
                , S.when button.fullWidth S.wFull
                , Css.maxWidth (Css.pct 100)
                , S.pointerCursor
                , S.batch variantStyles
                , emphasisStyles
                ]
            ]
    in
    H.button
        (baseAttrs ++ conditionalAttrs ++ selectionAttrs)
        content


attentionStyles : Css.Style
attentionStyles =
    S.batch
        [ S.relative
        , S.overflowHidden
        , S.animation "fightlines-button-attention 1.8s ease-in-out infinite"
        , S.focusVisible
            [ S.outlineCurrentThick
            , S.outlineOffset3
            ]
        , S.after
            [ S.contentEmpty
            , S.absolute
            , S.inset0
            , Css.property "background" "linear-gradient(110deg, transparent 35%, currentColor 50%, transparent 65%)"
            , S.opacity 0.16
            , S.transform "translateX(-150%)"
            , S.animation "fightlines-button-shine 3.6s ease-in-out infinite"
            , S.pointerEventsNone
            ]
        , S.reducedMotion
            [ S.animationNone
            , S.after
                [ S.animationNone
                , S.displayNone
                ]
            ]
        ]


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-button-attention {
                0%, 100% { filter: brightness(1);
                }
                50% { filter: brightness(1.45);
                }
            }
            @keyframes fightlines-button-shine {
                0%, 35% { transform: translateX(-150%);
                }
                75%, 100% { transform: translateX(150%);
                }
            }
        """
        ]
