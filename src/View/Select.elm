module View.Select exposing
    ( Select
    , disabled
    , new
    , toHtml
    , withHtmlId
    )

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode exposing (Decoder)
import Style as S



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Select msg
    = Select
        { htmlId : Maybe String
        , disabled : Bool
        , options : List (Option msg)
        }


type alias Option msg =
    { value : String
    , label : String
    , selected : Bool
    , message : msg
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


new :
    { selected : value
    , options : List { value : value, label : String }
    , onChange : value -> msg
    }
    -> Select msg
new config =
    let
        encodeOption : Int -> { value : value, label : String } -> Option msg
        encodeOption index option =
            -- The DOM uses an option index; domain values stay in Elm.
            { value = String.fromInt index
            , label = option.label
            , selected = option.value == config.selected
            , message = config.onChange option.value
            }
    in
    Select
        { htmlId = Nothing
        , disabled = False
        , options = List.indexedMap encodeOption config.options
        }


withHtmlId : String -> Select msg -> Select msg
withHtmlId htmlId (Select config) =
    Select
        { config
            | htmlId = Just htmlId
        }


disabled : Bool -> Select msg -> Select msg
disabled value (Select config) =
    Select
        { config
            | disabled = value
        }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : Select msg -> Html msg
toHtml (Select config) =
    let
        optionToHtml : Option msg -> Html msg
        optionToHtml option =
            H.option
                [ A.value option.value
                , A.selected option.selected
                ]
                [ H.text option.label
                ]

        decodeSelection : String -> Decoder msg
        decodeSelection value =
            let
                matches : Option msg -> Bool
                matches option =
                    option.value == value
            in
            case List.head (List.filter matches config.options) of
                Just option ->
                    Decode.succeed option.message

                Nothing ->
                    Decode.fail "unknown select option"

        idAttributes : List (H.Attribute msg)
        idAttributes =
            case config.htmlId of
                Nothing ->
                    []

                Just htmlId ->
                    [ A.id htmlId ]

        chevron : String
        chevron =
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='m1 1 5 5 5-5' fill='none' stroke='%23"
                ++ String.dropLeft 1 S.gray4Str
                ++ "' stroke-width='1.5'/%3E%3C/svg%3E\")"

        attributes : List (H.Attribute msg)
        attributes =
            [ A.disabled config.disabled
            , Ev.on "change"
                (Decode.at [ "target", "value" ] Decode.string
                    |> Decode.andThen decodeSelection
                )
            , A.css
                [ S.indentStrong
                , S.bgNightwood3
                , S.textGray5
                , S.p2
                , S.wFull
                , S.minW0
                , S.appearanceNone
                , Css.property "padding-right" "2.5rem"
                , Css.property "background-image" chevron
                , Css.property "background-repeat" "no-repeat"
                , Css.property "background-position" "right 0.75rem center"
                ]
            ]
    in
    H.select
        (attributes ++ idAttributes)
        (List.map optionToHtml config.options)
