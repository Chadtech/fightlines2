module Admin.Page.Dashboard.Analytics.RequestId exposing
    ( RequestId
    , generator
    , toString
    )

import Random


type RequestId
    = RequestId Int


generator : Random.Generator RequestId
generator =
    Random.int 0 Random.maxInt
        |> Random.map RequestId


toString : RequestId -> String
toString (RequestId value) =
    String.fromInt value
