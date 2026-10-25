module Common.Ports.Js.Encode exposing
    ( message
    , openDialog
    , setLocalStorage
    )

import Json.Encode as Je


message : String -> List ( String, Je.Value ) -> Je.Value
message tag payload =
    Je.object (( "tag", Je.string tag ) :: payload)


openDialog : { htmlId : String } -> Je.Value
openDialog { htmlId } =
    message "openDialog"
        [ ( "htmlId", Je.string htmlId )
        ]


setLocalStorage : { key : String, value : Je.Value } -> Je.Value
setLocalStorage { key, value } =
    message "setLocalStorage"
        [ ( "key", Je.string key )
        , ( "value", value )
        ]
