module View.Select exposing (toHtml)

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S


toHtml :
    { htmlId : String
    , disabled : Bool
    , selected : value
    , options : List { value : value, label : String }
    , toValue : value -> String
    , decoder : Decode.Decoder value
    , onChange : value -> msg
    }
    -> Html msg
toHtml config =
    let
        optionToHtml : { value : value, label : String } -> Html msg
        optionToHtml option =
            H.option
                [ A.value (config.toValue option.value)
                , A.selected (option.value == config.selected)
                ]
                [ H.text option.label
                ]

        chevron : String
        chevron =
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='m1 1 5 5 5-5' fill='none' stroke='%23"
                ++ String.dropLeft 1 S.gray4Str
                ++ "' stroke-width='1.5'/%3E%3C/svg%3E\")"
    in
    H.select
        [ A.id config.htmlId
        , A.disabled config.disabled
        , Ev.on "change"
            (Decode.at [ "target", "value" ] config.decoder
                |> Decode.map config.onChange
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
        (List.map optionToHtml config.options)
