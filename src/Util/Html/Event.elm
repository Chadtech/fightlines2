module Util.Html.Event exposing (enter, key)

import Json.Decode as Decode exposing (Decoder)


enter : value -> Decoder value
enter =
    key "Enter"


key : String -> value -> Decoder value
key expected value =
    let
        matchingKey : String -> Decoder value
        matchingKey actual =
            if actual == expected then
                Decode.succeed value

            else
                Decode.fail ("not " ++ expected)
    in
    Decode.field "key" Decode.string |> Decode.andThen matchingKey
