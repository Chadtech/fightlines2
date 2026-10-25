module View.Range exposing (toHtml)

import Css
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S


toHtml :
    { htmlId : String
    , label : String
    , value : Float
    , minimum : Float
    , maximum : Float
    , onChange : Float -> msg
    }
    -> Html msg
toHtml config =
    let
        decodeValue : String -> Decode.Decoder msg
        decodeValue raw =
            case String.toFloat raw of
                Just value ->
                    Decode.succeed (config.onChange (clamp config.minimum config.maximum value))

                Nothing ->
                    Decode.fail "range value must be a number"
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.label
            [ A.for config.htmlId
            ]
            [ H.text (config.label ++ ": " ++ String.fromFloat config.value ++ "%")
            ]
        , H.input
            [ A.id config.htmlId
            , A.type_ "range"
            , A.min (String.fromFloat config.minimum)
            , A.max (String.fromFloat config.maximum)
            , A.step "1"
            , A.value (String.fromFloat config.value)
            , Ev.on "input"
                (Decode.at [ "target", "value" ] Decode.string
                    |> Decode.andThen decodeValue
                )
            , A.css
                [ S.wFull
                , Css.property "accent-color" S.yellow5Str
                ]
            ]
            []
        ]
