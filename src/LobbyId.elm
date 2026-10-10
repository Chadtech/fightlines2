module LobbyId exposing
    ( LobbyId
    , fromString
    , parse
    , toString
    )

import ListUtil


type LobbyId
    = LobbyId String


fromString : String -> Result String LobbyId
fromString value =
    if String.length value /= 32 then
        Err ("Invalid lobby ID: expected 32 characters, got " ++ String.fromInt (String.length value) ++ ".")

    else
        case String.toList value |> ListUtil.find (\char -> not (String.contains (String.fromChar char) "0123456789abcdef")) of
            Just char ->
                Err ("Invalid lobby ID: invalid character '" ++ String.fromChar char ++ "'; expected lowercase hexadecimal characters (0-9, a-f).")

            Nothing ->
                Ok (LobbyId value)


parse : String -> Result String LobbyId
parse =
    fromString


toString : LobbyId -> String
toString (LobbyId value) =
    value
