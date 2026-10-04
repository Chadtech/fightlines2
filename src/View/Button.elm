module View.Button exposing
    ( onClick
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
    { onClick : Maybe msg
    , label : String
    , variant : Variant
    }


type Variant
    = Variant__Primary
    | Variant__Secondary



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


fromLabelAndVariant : String -> Variant -> Button msg
fromLabelAndVariant label variant =
    { onClick = Nothing
    , label = label
    , variant = variant
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
                            [ S.bgYellow1
                            , S.textYellow4
                            , S.importantOutdent
                            , Css.hover
                                [ S.textYellow5
                                ]
                            , Css.active
                                [ S.textYellow5
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
            in
            [ A.css
                [ S.p2
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
