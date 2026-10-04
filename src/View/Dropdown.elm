module View.Dropdown exposing
    ( Dropdown
    , Option
    , globalStyles
    , option
    , simple
    , toHtml
    , withHtmlId
    )

import Css.Global
import Html.Styled as Html
    exposing
        ( Attribute
        , Html
        )
import Html.Styled.Attributes as Attr
import Html.Styled.Events as Ev
import Json.Decode as JD
import Style as S



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Dropdown msg =
    { label : String
    , onClick : msg
    , htmlId : Maybe String
    }


type alias Option msg =
    { label : String
    , onClick : msg
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


globalStyles : Css.Global.Snippet
globalStyles =
    Css.Global.selector ".dropdown:hover"
        [ Css.Global.children
            [ Css.Global.class "dropdown-label"
                [ S.textGray5
                ]
            ]
        ]


simple : String -> msg -> Dropdown msg
simple label onClick =
    { label = label
    , onClick = onClick
    , htmlId = Nothing
    }


withHtmlId : String -> Dropdown msg -> Dropdown msg
withHtmlId htmlId dropdown =
    { dropdown
        | htmlId = Just htmlId
    }


option : String -> msg -> Option msg
option label onClick =
    { label = label
    , onClick = onClick
    }


toHtml : Maybe (List (Option msg)) -> Dropdown msg -> Html msg
toHtml maybeOptions dropdown =
    let
        chevronCharacter : Char
        chevronCharacter =
            if maybeOptions == Nothing then
                Char.fromCode 0x25BC

            else
                Char.fromCode 0x25B2

        optionToHtml : Option msg -> Html msg
        optionToHtml opt =
            Html.div
                [ Ev.stopPropagationOn "click" <| JD.succeed ( opt.onClick, True )
                , Attr.css
                    [ S.hover
                        [ S.textGray5
                        , S.bgNightwood2
                        ]
                    , S.p2
                    ]
                ]
                [ Html.text opt.label
                ]

        optionsHtml : Html msg
        optionsHtml =
            case maybeOptions of
                Nothing ->
                    Html.text ""

                Just options ->
                    Html.div
                        [ Attr.css
                            [ S.absolute
                            , S.topFull
                            , S.left0
                            , S.border
                            , S.right0
                            , S.bgNightwood1
                            , S.p2
                            , S.z1
                            ]
                        ]
                        (List.map optionToHtml options)

        baseAttrs : List (Attribute msg)
        baseAttrs =
            [ Attr.css
                [ S.border
                , S.borderGray2
                , S.bgNightwood1
                , S.textGray4
                , S.p2
                , S.relative
                , S.row
                , S.justifySpaceBetween
                , S.pointerCursor
                , S.w48
                ]
            , Attr.class "dropdown"
            , Ev.onClick dropdown.onClick
            ]

        conditionalAttrs : List (Attribute msg)
        conditionalAttrs =
            [ Maybe.map Attr.id dropdown.htmlId
            ]
                |> List.filterMap identity
    in
    Html.div
        (baseAttrs ++ conditionalAttrs)
        [ Html.div
            [ Attr.class "dropdown-label"
            ]
            [ Html.text dropdown.label
            ]
        , Html.div
            []
            [ Html.text <| String.fromChar chevronCharacter
            ]
        , optionsHtml
        ]
