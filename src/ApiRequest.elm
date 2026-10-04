module ApiRequest exposing
    ( Response
    , errorMessage
    , mutationRequest
    , queryRequest
    )

import Graphql.Http
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)


type alias Response v =
    Result (Graphql.Http.Error v) v


queryRequest : SelectionSet response RootQuery -> Graphql.Http.Request response
queryRequest =
    request Graphql.Http.queryRequest


mutationRequest : SelectionSet response RootMutation -> Graphql.Http.Request response
mutationRequest =
    request Graphql.Http.mutationRequest


request : (String -> SelectionSet response scope -> Graphql.Http.Request response) -> SelectionSet response scope -> Graphql.Http.Request response
request makeRequest selectionSet =
    makeRequest "/graphql" selectionSet
        |> Graphql.Http.withTimeout 10000


errorMessage : Graphql.Http.Error response -> String
errorMessage error =
    case error of
        Graphql.Http.GraphqlError _ errors ->
            case errors of
                [] ->
                    "The server could not complete this request."

                _ ->
                    errors
                        |> List.map .message
                        |> String.join " "

        Graphql.Http.HttpError _ ->
            "Could not reach the server. Check your connection and try again."
