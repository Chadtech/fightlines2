port module DevTools.Ports.Js.To exposing
    ( Msg(..)
    , toCmd
    )

import Json.Encode as Je


type Msg
    = OpenDialog { htmlId : String }
    | GenerateMapThumbnail { htmlId : String, requestId : Int }
    | SetLocalStorage { key : String, value : Je.Value }


toCmd : Msg -> Cmd msg
toCmd message =
    toJs (encode message)


tagName : Msg -> String
tagName msg =
    case msg of
        SetLocalStorage _ ->
            "setLocalStorage"

        OpenDialog _ ->
            "openDialog"

        GenerateMapThumbnail _ ->
            "generateMapThumbnail"


encode : Msg -> Je.Value
encode message =
    let
        payload : List ( String, Je.Value )
        payload =
            case message of
                SetLocalStorage { key, value } ->
                    [ ( "key", Je.string key )
                    , ( "value", value )
                    ]

                OpenDialog { htmlId } ->
                    [ ( "htmlId", Je.string htmlId )
                    ]

                GenerateMapThumbnail { htmlId, requestId } ->
                    [ ( "htmlId", Je.string htmlId )
                    , ( "requestId", Je.int requestId )
                    ]
    in
    Je.object (( "tag", Je.string <| tagName message ) :: payload)


port toJs : Je.Value -> Cmd msg
