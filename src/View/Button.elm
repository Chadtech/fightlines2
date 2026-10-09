module View.Button exposing
    ( disabled
    , large
    , onClick
    , primary
    , secondary
    , toHtml
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



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Button msg =
    { disabled : Bool
    , onClick : Maybe msg
    , label : String
    , variant : Variant
    , size : Size
    }


type Variant
    = Variant__Primary
    | Variant__Secondary


type Size
    = Regular
    | Large



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


fromLabelAndVariant : String -> Variant -> Button msg
fromLabelAndVariant label variant =
    { disabled = False
    , onClick = Nothing
    , label = label
    , variant = variant
    , size = Regular
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


onClick : msg -> Button msg -> Button msg
onClick msg button =
    { button
        | onClick = Just msg
    }


disabled : Bool -> Button msg -> Button msg
disabled value button =
    { button | disabled = value }


large : Button msg -> Button msg
large button =
    { button | size = Large }


toHtml : Button msg -> Html msg
toHtml button =
    let
        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Ev.onClick button.onClick
            ]
                |> List.filterMap identity

        baseAttrs : List (Attribute msg)
        baseAttrs =
            let
                variantStyles : List Css.Style
                variantStyles =
                    case button.variant of
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

                        Variant__Secondary ->
                            [ S.bgGray1
                            , S.textGray4
                            , S.outdent
                            , Css.hover
                                [ S.textGray5
                                ]
                            , Css.active
                                [ S.textGray5
                                , S.indent
                                ]
                            ]

                sizeStyles : List Css.Style
                sizeStyles =
                    case button.size of
                        Regular ->
                            [ S.p2 ]

                        Large ->
                            [ S.px4
                            , S.py3
                            , Css.minHeight (Css.rem 3)
                            ]
            in
            [ A.disabled button.disabled
            , A.css
                [ S.batch sizeStyles
                , Css.alignSelf Css.flexStart
                , Css.maxWidth (Css.pct 100)
                , S.pointerCursor
                , S.batch variantStyles
                ]
            ]
    in
    H.button
        (baseAttrs ++ conditionalAttrs)
        [ H.text button.label
        ]
