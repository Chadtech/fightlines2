module Common.Effect exposing
    ( GraphqlRequest
    , after
    , focus
    , graphqlRequest
    , mapGraphqlRequest
    , measure
    , sendGraphqlRequest
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
which can differ between requests. Only `graphqlRequest` can construct one, and the
GraphQL command is created when `sendGraphqlRequest` runs.
-}
type GraphqlRequest msg
    = GraphqlRequest (() -> Cmd msg)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


graphqlRequest : (Response response -> msg) -> Graphql.Http.Request response -> GraphqlRequest msg
graphqlRequest received pending =
    GraphqlRequest (\() -> Graphql.Http.send received pending)


mapGraphqlRequest : (a -> b) -> GraphqlRequest a -> GraphqlRequest b
mapGraphqlRequest toMsg (GraphqlRequest send) =
    GraphqlRequest (\() -> Cmd.map toMsg (send ()))


sendGraphqlRequest : GraphqlRequest msg -> Cmd msg
sendGraphqlRequest (GraphqlRequest send) =
    send ()


{-| Deliver a message after the given number of milliseconds.
-}
after : Float -> msg -> Cmd msg
after milliseconds completed =
    Process.sleep milliseconds
        |> Task.perform (always completed)


{-| Attempt to focus an element and report success or failure.
-}
focus : { htmlId : String } -> (Result Browser.Dom.Error () -> msg) -> Cmd msg
focus { htmlId } received =
    Browser.Dom.focus htmlId
        |> Task.attempt received


{-| Measure a rendered element after layout and report success or failure.
-}
measure : String -> (Result Browser.Dom.Error Browser.Dom.Element -> msg) -> Cmd msg
measure htmlId received =
    Browser.Dom.getElement htmlId
        |> Task.attempt received
