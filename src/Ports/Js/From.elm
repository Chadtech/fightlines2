port module Ports.Js.From exposing
    ( Error(..)
    , Listener
    , batch
    , data
    , errorToString
    , map
    , noData
    , none
    , subscription
    )

import Json.Decode as JD exposing (Decoder)


port fromJs : (JD.Value -> msg) -> Sub msg



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Listener msg
    = Listener__None
    | Listener__Batch (List (Listener msg))
    | Listener__Data String (Decoder msg)


type Error
    = Error__MsgTypeNotFound { type_ : String }
    | Error__DecodeFailed JD.Error



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


none : Listener msg
none =
    Listener__None


batch : List (Listener msg) -> Listener msg
batch =
    Listener__Batch


map : (a -> b) -> Listener a -> Listener b
map toMsg listener =
    case listener of
        Listener__None ->
            Listener__None

        Listener__Batch listeners ->
            Listener__Batch <| List.map (map toMsg) listeners

        Listener__Data type_ decoder ->
            Listener__Data type_ <| JD.map toMsg decoder


data : String -> Decoder a -> (a -> msg) -> Listener msg
data type_ decoder toMsg =
    Listener__Data type_ (JD.map toMsg decoder)


noData : String -> msg -> Listener msg
noData type_ msg =
    Listener__Data type_ (JD.succeed msg)


errorToString : Error -> String
errorToString error =
    case error of
        Error__MsgTypeNotFound { type_ } ->
            "Msg type not found, " ++ type_

        Error__DecodeFailed decodeError ->
            "Decode failed: " ++ JD.errorToString decodeError


attemptDecoders : String -> JD.Value -> List (Listener msg) -> Result Error msg
attemptDecoders type_ json listeners =
    case listeners of
        first :: rest ->
            case first of
                Listener__None ->
                    attemptDecoders type_ json rest

                Listener__Batch batchedListeners ->
                    attemptDecoders type_ json (batchedListeners ++ rest)

                Listener__Data listenerType decoder ->
                    if type_ == listenerType then
                        JD.decodeValue (JD.field "payload" decoder) json
                            |> Result.mapError Error__DecodeFailed

                    else
                        attemptDecoders type_ json rest

        [] ->
            Err <| Error__MsgTypeNotFound { type_ = type_ }


subscription :
    { listeners : List (Listener msg)
    , onError : Error -> msg
    }
    -> Sub msg
subscription args =
    let
        fromJson : JD.Value -> msg
        fromJson json =
            case JD.decodeValue (JD.field "type" JD.string) json of
                Ok type_ ->
                    case attemptDecoders type_ json args.listeners of
                        Ok msg ->
                            msg

                        Err error ->
                            args.onError error

                Err error ->
                    args.onError <| Error__DecodeFailed error
    in
    fromJs fromJson
