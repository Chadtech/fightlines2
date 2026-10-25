module Common exposing
    ( Request
    , after
    , focus
    , mapRequest
    , measure
    , request
    , sendRequest
    )

import ApiRequest
    exposing
        ( Response
        )
import Browser.Dom
import Graphql.Http
import Process
import Task



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| A pending GraphQL request. The private sender captures its response type,
which can differ between requests. Only `request` can construct one, and the
GraphQL command is created when `sendRequest` runs.
-}
type Request msg
    = GraphqlRequest (() -> Cmd msg)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


request : (Response response -> msg) -> Graphql.Http.Request response -> Request msg
request received graphqlRequest =
    GraphqlRequest (\() -> Graphql.Http.send received graphqlRequest)


mapRequest : (a -> b) -> Request a -> Request b
mapRequest toMsg (GraphqlRequest send) =
    GraphqlRequest (\() -> Cmd.map toMsg (send ()))


sendRequest : Request msg -> Cmd msg
sendRequest (GraphqlRequest send) =
    send ()


{-| Deliver a message after the given number of milliseconds.
-}
after : Float -> msg -> Cmd msg
after milliseconds completed =
    Process.sleep milliseconds
        |> Task.perform (always completed)


{-| Attempt to focus an element, then notify completion even if it is missing.
-}
focus : { htmlId : String } -> msg -> Cmd msg
focus { htmlId } completed =
    Browser.Dom.focus htmlId
        |> Task.attempt (always completed)


{-| Measure a rendered element after layout and report success or failure.
-}
measure : String -> (Result Browser.Dom.Error Browser.Dom.Element -> msg) -> Cmd msg
measure htmlId received =
    Browser.Dom.getElement htmlId
        |> Task.attempt received
