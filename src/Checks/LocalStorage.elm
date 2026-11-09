port module Checks.LocalStorage exposing (main)

import Admin.Flags as AdminFlags
import Audio
import DevTools.Flags as DevToolsFlags
import Error exposing (Error(..))
import Features
import Fightlines.Flags as PlayerFlags
import Fightlines.UserName as UserName
import Json.Decode as JD
import Json.Encode as Encode
import LocalStorage
import Platform
import Preference
import ScreenSize exposing (ScreenSize)
import Time


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results (checks ++ featureChecks ++ clockFlagChecks ++ screenSizeFlagChecks) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    let
        read : String -> JD.Decoder a -> String -> Result JD.Error (Maybe a)
        read key decoder json =
            JD.decodeString LocalStorage.decoder json
                |> Result.andThen (\storage -> LocalStorage.get storage key decoder)

        isError : Result error a -> Bool
        isError result =
            case result of
                Err _ ->
                    True

                Ok _ ->
                    False

        check : String -> Bool -> List String
        check label passed =
            if passed then
                []

            else
                [ label ]

        invalidObjects : List String
        invalidObjects =
            [ "null", "[]", "42", "\"text\"" ]

        readUserName : String -> Result String (Maybe String)
        readUserName json =
            case JD.decodeString LocalStorage.decoder json of
                Ok storage ->
                    UserName.fromLocalStorage storage
                        |> Result.mapError storageErrorDetails

                Err error ->
                    Err (JD.errorToString error)

        storageErrorDetails : Error -> String
        storageErrorDetails error =
            case error of
                TestError ->
                    "unexpected test error while reading local storage"

                LocalStorageDecodeFailed details ->
                    details.key ++ ": " ++ JD.errorToString details.error

                UnitOwnerNotFound _ ->
                    "unexpected unit owner error while reading local storage"

                FromJsFailed _ ->
                    "unexpected JavaScript message error while reading local storage"

                AudioFailed _ ->
                    "unexpected audio error while reading local storage"

                DeploymentStatusFailed _ ->
                    "unexpected deployment status error while reading local storage"

                ElementFocusFailed _ ->
                    "unexpected element focus error while reading local storage"

                ElementScrollFailed _ ->
                    "unexpected element scroll error while reading local storage"

                BattlefieldMeasurementFailed _ ->
                    "unexpected battlefield measurement error while reading local storage"

                OrderPlanningInvariantViolated _ ->
                    "unexpected order planning error while reading local storage"

        readPreference : JD.Decoder value -> value -> String -> Result String ( value, Maybe String )
        readPreference decoder defaultValue json =
            JD.decodeString LocalStorage.decoder json
                |> Result.mapError JD.errorToString
                |> Result.map
                    (Preference.load
                        { key = "preference"
                        , decoder = decoder
                        , defaultValue = defaultValue
                        }
                        >> Tuple.mapSecond (Maybe.map storageErrorDetails)
                    )

        invalidPreferencePreservesError : Bool
        invalidPreferencePreservesError =
            case JD.decodeString JD.bool "42" of
                Err error ->
                    readPreference JD.bool False "{\"preference\":42}"
                        == Ok ( False, Just ("preference: " ++ JD.errorToString error) )

                Ok _ ->
                    False

        readMute : String -> Result String ( Audio.MuteState, Maybe String )
        readMute json =
            JD.decodeString LocalStorage.decoder json
                |> Result.mapError JD.errorToString
                |> Result.map (Audio.loadMutePreference >> Tuple.mapSecond (Maybe.map storageErrorDetails))

        muteRoundTrip : Audio.MuteState -> Bool
        muteRoundTrip state =
            let
                entry : { key : String, value : Encode.Value }
                entry =
                    Audio.encodeMutePreference state
            in
            Encode.object [ ( entry.key, entry.value ) ]
                |> Encode.encode 0
                |> readMute
                |> (==) (Ok ( state, Nothing ))

        invalidMutePreservesError : Bool
        invalidMutePreservesError =
            case JD.decodeString JD.bool "42" of
                Err error ->
                    readMute "{\"audioMuted\":42}"
                        == Ok ( Audio.Unmuted, Just ("audioMuted: " ++ JD.errorToString error) )

                Ok _ ->
                    False

        volumesRoundTrip : Bool
        volumesRoundTrip =
            let
                volumes : Audio.Volumes
                volumes =
                    Audio.defaultVolumes |> Audio.setChannelVolume Audio.Combat 25 |> Audio.setChannelVolume Audio.Environment 0

                entry : { key : String, value : Encode.Value }
                entry =
                    Audio.encodeVolumesPreference volumes
            in
            Encode.object [ ( entry.key, entry.value ) ]
                |> JD.decodeValue LocalStorage.decoder
                |> Result.map Audio.loadVolumesPreference
                |> (==) (Ok ( volumes, Nothing ))

        invalidVolumesRejected : Bool
        invalidVolumesRejected =
            case JD.decodeString LocalStorage.decoder "{\"audioVolumes\":{\"master\":101,\"combat\":100,\"movement\":100,\"ambience\":100,\"interface\":100}}" of
                Ok storage ->
                    case Audio.loadVolumesPreference storage of
                        ( volumes, Just (LocalStorageDecodeFailed failure) ) ->
                            volumes == Audio.defaultVolumes && failure.key == "audioVolumes"

                        _ ->
                            False

                Err _ ->
                    False

        invalidNamePreservesError : Bool
        invalidNamePreservesError =
            case JD.decodeString JD.string "42" of
                Err error ->
                    readUserName "{\"userName\":42}" == Err ("userName: " ++ JD.errorToString error)

                Ok _ ->
                    False
    in
    List.concat
        [ check "volume preferences round trip independently" volumesRoundTrip
        , check "out of range saved volumes retain a diagnostic and use the current mix" invalidVolumesRejected
        , check "missing volumes preserve the existing mix" (Audio.loadVolumesPreference LocalStorage.test == ( Audio.defaultVolumes, Nothing ))
        , check "empty storage has no keys" (LocalStorage.get LocalStorage.test "missing" JD.string == Ok Nothing)
        , check "missing key is distinct from decoding failure" (read "missing" JD.int "{\"count\":2}" == Ok Nothing)
        , check "stored values decode with the caller's decoder" (read "count" JD.int "{\"count\":2}" == Ok (Just 2))
        , check "wrong value type retains decoding failure" (isError (read "count" JD.int "{\"count\":\"two\"}"))
        , check "JSON null is a stored value" (read "value" (JD.null ()) "{\"value\":null}" == Ok (Just ()))
        , check "nested values decode" (read "settings" (JD.field "enabled" JD.bool) "{\"settings\":{\"enabled\":true}}" == Ok (Just True))
        , check "storage requires a JSON object" (List.all (JD.decodeString LocalStorage.decoder >> isError) invalidObjects)
        , check "empty JSON object decodes" (read "missing" JD.string "{}" == Ok Nothing)
        , check "missing remembered name succeeds without a value" (readUserName "{}" == Ok Nothing)
        , check "remembered name preserves spelling" (readUserName "{\"userName\":\"MixedCase\"}" == Ok (Just "MixedCase"))
        , check "malformed remembered name retains its key and decoder error" invalidNamePreservesError
        , check "missing preference uses its configured default" (readPreference JD.bool True "{}" == Ok ( True, Nothing ))
        , check "stored false overrides a true preference default" (readPreference JD.bool True "{\"preference\":false}" == Ok ( False, Nothing ))
        , check "stored true overrides a false preference default" (readPreference JD.bool False "{\"preference\":true}" == Ok ( True, Nothing ))
        , check "preferences support non-Boolean values" (readPreference JD.int 7 "{\"preference\":12}" == Ok ( 12, Nothing ))
        , check "malformed preference retains its key and decoder error" invalidPreferencePreservesError
        , check "missing mute preference defaults to unmuted" (readMute "{}" == Ok ( Audio.Unmuted, Nothing ))
        , check "saved mute is restored" (readMute "{\"audioMuted\":true}" == Ok ( Audio.Muted, Nothing ))
        , check "saved unmute is restored" (readMute "{\"audioMuted\":false}" == Ok ( Audio.Unmuted, Nothing ))
        , check "both mute states survive storage round trips" (List.all muteRoundTrip [ Audio.Muted, Audio.Unmuted ])
        , check "invalid mute defaults to unmuted and retains its decoder error" invalidMutePreservesError
        ]


clockFlagChecks : List String
clockFlagChecks =
    let
        commonFlags : List ( String, Encode.Value )
        commonFlags =
            [ ( "isProduction", Encode.bool False )
            , ( "screenSize"
              , Encode.object
                    [ ( "width", Encode.int 1280 )
                    , ( "height", Encode.int 800 )
                    ]
              )
            , ( "operatingSystem", Encode.string "test" )
            , ( "localStorage", Encode.object [] )
            , ( "seed", Encode.int 42 )
            ]

        flags : Encode.Value
        flags =
            Encode.object (( "now", Encode.int 1700000000123 ) :: commonFlags)

        missingClock : Encode.Value
        missingClock =
            Encode.object commonFlags

        clockRequired : Bool
        clockRequired =
            case ( JD.decodeValue PlayerFlags.decoder missingClock, JD.decodeValue DevToolsFlags.decoder missingClock ) of
                ( Err _, Err _ ) ->
                    True

                _ ->
                    False

        expected : Time.Posix
        expected =
            Time.millisToPosix 1700000000123

        playerTime : Result JD.Error Time.Posix
        playerTime =
            JD.decodeValue PlayerFlags.decoder flags |> Result.map .now

        toolsTime : Result JD.Error Time.Posix
        toolsTime =
            JD.decodeValue DevToolsFlags.decoder flags |> Result.map .now
    in
    if (playerTime == Ok expected) && (toolsTime == Ok expected) && clockRequired then
        []

    else
        [ "both applications must decode the required JavaScript startup clock" ]


screenSizeFlagChecks : List String
screenSizeFlagChecks =
    let
        baseFields : List ( String, Encode.Value )
        baseFields =
            [ ( "now"
              , Encode.int 1700000000123
              )
            , ( "isProduction"
              , Encode.bool False
              )
            , ( "operatingSystem"
              , Encode.string "test"
              )
            , ( "localStorage"
              , Encode.object []
              )
            , ( "seed"
              , Encode.int 42
              )
            ]

        withSize : Encode.Value -> Encode.Value
        withSize size =
            Encode.object
                (( "screenSize"
                 , size
                 )
                    :: baseFields
                )

        validFlags : Encode.Value
        validFlags =
            withSize
                (Encode.object
                    [ ( "width"
                      , Encode.int 852
                      )
                    , ( "height"
                      , Encode.int 393
                      )
                    ]
                )

        invalidFlags : List Encode.Value
        invalidFlags =
            [ Encode.object baseFields
            , withSize Encode.null
            , withSize (Encode.object [])
            , withSize
                (Encode.object
                    [ ( "width"
                      , Encode.int 852
                      )
                    ]
                )
            , withSize
                (Encode.object
                    [ ( "width"
                      , Encode.string "852"
                      )
                    , ( "height"
                      , Encode.int 393
                      )
                    ]
                )
            ]

        expected : ScreenSize
        expected =
            { width = 852
            , height = 393
            }

        validDecoder : JD.Decoder ScreenSize -> Bool
        validDecoder decoder =
            let
                rejectsInvalid : Encode.Value -> Bool
                rejectsInvalid flags =
                    case JD.decodeValue decoder flags of
                        Err _ ->
                            True

                        Ok _ ->
                            False
            in
            (JD.decodeValue decoder validFlags == Ok expected)
                && List.all
                    rejectsInvalid
                    invalidFlags

        decoders : List (JD.Decoder ScreenSize)
        decoders =
            [ JD.map .screenSize PlayerFlags.decoder
            , JD.map .screenSize DevToolsFlags.decoder
            , JD.map .screenSize AdminFlags.decoder
            ]
    in
    if List.all validDecoder decoders then
        []

    else
        [ "all applications must require a complete numeric screen size in startup flags" ]


featureChecks : List String
featureChecks =
    let
        load : String -> Result JD.Error ( Features.Model, Maybe Error )
        load json =
            JD.decodeString LocalStorage.decoder json
                |> Result.map Features.init

        off : Features.Model
        off =
            { enabled = [] }

        on : Features.Model
        on =
            Features.setEnabled Features.MobileLandscape True off

        entry : { key : String, value : Encode.Value }
        entry =
            Features.encodePreference on

        roundTrip : Bool
        roundTrip =
            Encode.object [ ( entry.key, entry.value ) ]
                |> JD.decodeValue LocalStorage.decoder
                |> Result.map Features.init
                |> (==) (Ok ( on, Nothing ))

        invalid : String -> Bool
        invalid json =
            case load json of
                Ok ( model, Just (LocalStorageDecodeFailed details) ) ->
                    (model == off) && (details.key == "features")

                _ ->
                    False

        check : String -> Bool -> List String
        check description passes =
            if passes then
                []

            else
                [ description ]
    in
    List.concat
        [ check "features default to disabled" (load "{}" == Ok ( off, Nothing ))
        , check "saved mobile feature is restored"
            (load "{\"features\":[\"mobileLandscape\"]}" == Ok ( on, Nothing ))
        , check "empty feature list disables mobile view"
            (load "{\"features\":[]}" == Ok ( off, Nothing ))
        , check "feature storage round trips" roundTrip
        , check "feature enabling checks list membership"
            (Features.enabled Features.MobileLandscape on)
        , check "enabling a feature twice adds no duplicate"
            (Features.setEnabled Features.MobileLandscape True on == on)
        , check "disabling removes the feature"
            (Features.setEnabled Features.MobileLandscape False on == off)
        , check "invalid feature lists retain a diagnostic"
            (List.all invalid
                [ "{\"features\":true}"
                , "{\"features\":[42]}"
                , "{\"features\":[\"unknown\"]}"
                ]
            )
        ]
