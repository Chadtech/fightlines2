module OperatingSystem exposing
    ( OperatingSystem(..)
    , decoder
    , isMobile
    )

import Json.Decode as Decode exposing (Decoder)


type OperatingSystem
    = MacOS
    | Windows
    | Linux
    | ChromeOS
    | Android
    | IOS
    | Unknown


decoder : Decoder OperatingSystem
decoder =
    Decode.map fromPlatform Decode.string


isMobile : OperatingSystem -> Bool
isMobile operatingSystem =
    case operatingSystem of
        Android ->
            True

        IOS ->
            True

        _ ->
            False


fromPlatform : String -> OperatingSystem
fromPlatform platform =
    let
        contains : String -> Bool
        contains name =
            String.contains name (String.toLower platform)
    in
    if contains "android" then
        Android

    else if contains "iphone" || contains "ipad" || contains "ipod" || contains "ios" then
        IOS

    else if contains "cros" || contains "chrome os" then
        ChromeOS

    else if contains "win" then
        Windows

    else if contains "mac" then
        MacOS

    else if contains "linux" then
        Linux

    else
        Unknown
