port module Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Json.Encode as Je


type Msg
    = CopyLink { url : String }
    | OpenDialog { htmlId : String }


toCmd : Msg -> Cmd msg
toCmd message =
    toJs (encode message)


tagName : Msg -> String
tagName msg =
    case msg of
        OpenDialog _ ->
            "openDialog"

        CopyLink _ ->
            "copyLink"


encode : Msg -> Je.Value
encode message =
    let
        payload : List ( String, Je.Value )
        payload =
            case message of
                OpenDialog { htmlId } ->
                    [ ( "htmlId", Je.string htmlId )
                    ]

                CopyLink { url } ->
                    [ ( "url", Je.string url )
                    ]
    in
    Je.object (( "tag", Je.string <| tagName message ) :: payload)


port toJs : Je.Value -> Cmd msg
