module View.Button exposing
    ( Button
    , accessibleLabel
    , choice
    , disabled
    , large
    , onClick
    , primary
    , secondary
    , toHtml
    , withFeedback
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
    , onClick : Maybe msg
    , label : String
    , variant : Variant
    , size : Size
    , icon : Maybe (Html msg)
    , feedback : Maybe String
    }


type Variant
    = Variant__Primary
    | Variant__Secondary
    | Disabled
    | Choice Bool


type Size
    = Regular
    | Large



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


fromLabelAndVariant : String -> Variant -> Button msg
fromLabelAndVariant label variant =
    { accessibleLabel = Nothing
    , onClick = Nothing
    , label = label
    , variant = variant
    , size = Regular
    , icon = Nothing
    , feedback = Nothing
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


large : Button msg -> Button msg
large button =
    { button | size = Large }


toHtml : Button msg -> Html msg
toHtml button =
    let
        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Ev.onClick button.onClick
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
            in
            [ A.disabled (button.variant == Disabled)
            , A.css
                [ S.batch sizeStyles
                , S.batch iconStyles
                , Css.alignSelf Css.flexStart
                , Css.maxWidth (Css.pct 100)
                , S.pointerCursor
                , S.batch variantStyles
                ]
            ]
    in
    H.button
        (baseAttrs ++ conditionalAttrs ++ selectionAttrs)
        content
