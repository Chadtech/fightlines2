port module Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Json.Encode as Je


type Msg
    = CopyLink String


toCmd : Msg -> Cmd msg
toCmd message =
    toJs (encode message)


tagName : Msg -> String
tagName msg =
    case msg of
        CopyLink _ ->
            "copyLink"


encode : Msg -> Je.Value
encode message =
    let
        payload : List ( String, Je.Value )
        payload =
            case message of
                CopyLink url ->
                    [ ( "url", Je.string url )
                    ]
    in
    Je.object (( "tag", Je.string <| tagName message ) :: payload)


port toJs : Je.Value -> Cmd msg
