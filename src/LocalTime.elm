module LocalTime exposing
    ( decoder
    , formatSeconds
    , timestampLabel
    )

import Json.Decode as Decode exposing (Decoder)
import Time


decoder : Decoder Time.Zone
decoder =
    Decode.map2 Time.customZone
        (Decode.field "defaultOffset" Decode.int)
        (Decode.field "eras" (Decode.list eraDecoder))


eraDecoder : Decoder { start : Int, offset : Int }
eraDecoder =
    Decode.map2 (\start offset -> { start = start, offset = offset })
        (Decode.field "start" Decode.int)
        (Decode.field "offset" Decode.int)


timestampLabel : Time.Zone -> String -> String
timestampLabel zone timestamp =
    timestamp
        |> String.toInt
        |> Maybe.map (Time.millisToPosix >> formatMinutes zone)
        |> Maybe.withDefault "time unavailable"


formatMinutes : Time.Zone -> Time.Posix -> String
formatMinutes zone time =
    String.fromInt (Time.toYear zone time)
        ++ "-"
        ++ pad (month (Time.toMonth zone time))
        ++ "-"
        ++ pad (Time.toDay zone time)
        ++ " "
        ++ pad (Time.toHour zone time)
        ++ ":"
        ++ pad (Time.toMinute zone time)


formatSeconds : Time.Zone -> Time.Posix -> String
formatSeconds zone time =
    formatMinutes zone time ++ ":" ++ pad (Time.toSecond zone time)


pad : Int -> String
pad value =
    String.padLeft 2 '0' (String.fromInt value)


month : Time.Month -> Int
month value =
    case value of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
