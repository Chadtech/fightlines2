port module Checks.LocalStorage exposing (main)

import Audio
import Error exposing (Error(..))
import Fightlines.UserName as UserName
import Json.Decode as JD
import Json.Encode as Encode
import LocalStorage
import Platform
import Preference


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
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

                ElementFocusFailed _ ->
                    "unexpected element focus error while reading local storage"

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

        invalidNamePreservesError : Bool
        invalidNamePreservesError =
            case JD.decodeString JD.string "42" of
                Err error ->
                    readUserName "{\"userName\":42}" == Err ("userName: " ++ JD.errorToString error)

                Ok _ ->
                    False
    in
    List.concat
        [ check "empty storage has no keys" (LocalStorage.get LocalStorage.test "missing" JD.string == Ok Nothing)
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
