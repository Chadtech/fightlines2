module ApiRequest exposing
    ( Response
    , errorDetails
    , errorMessage
    , mutationRequest
    , queryRequest
    , requiresAdminLogin
    , requiresCurrentDeployment
    )

import Dict
import Graphql.Http
import Graphql.Http.GraphqlError exposing (GraphqlError)
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode


type alias Response v =
    Result (Graphql.Http.Error v) v


queryRequest : SelectionSet response RootQuery -> Graphql.Http.Request response
queryRequest =
    request Graphql.Http.queryRequest


mutationRequest : SelectionSet response RootMutation -> Graphql.Http.Request response
mutationRequest =
    request Graphql.Http.mutationRequest


requiresAdminLogin : Graphql.Http.Error response -> Bool
requiresAdminLogin =
    hasErrorCode "ADMIN_LOGIN_REQUIRED"


hasErrorCode : String -> Graphql.Http.Error response -> Bool
hasErrorCode code error =
    let
        matches : GraphqlError -> Bool
        matches item =
            item.details
                |> Dict.get "extensions"
                |> Maybe.map (Decode.decodeValue (Decode.field "code" Decode.string))
                |> Maybe.andThen Result.toMaybe
                |> (==) (Just code)
    in
    case error of
        Graphql.Http.GraphqlError _ errors ->
            List.any matches errors

        _ ->
            False


request : (String -> SelectionSet response scope -> Graphql.Http.Request response) -> SelectionSet response scope -> Graphql.Http.Request response
request makeRequest selectionSet =
    makeRequest "graphql" selectionSet
        |> Graphql.Http.withTimeout 10000


errorMessage : Graphql.Http.Error response -> String
errorMessage error =
    case error of
        Graphql.Http.GraphqlError _ errors ->
            case errors of
                [] ->
                    "the server could not complete this request."

                _ ->
                    errors
                        |> List.map .message
                        |> String.join " "

        Graphql.Http.HttpError httpError ->
            case httpError of
                Graphql.Http.Timeout ->
                    "the server took too long to respond. try again."

                Graphql.Http.NetworkError ->
                    "could not reach the server. check your connection and try again."

                Graphql.Http.BadStatus metadata _ ->
                    "the server returned http " ++ String.fromInt metadata.statusCode ++ ". try again."

                Graphql.Http.BadPayload _ ->
                    "the server returned an unexpected response. reload the page and try again."

                Graphql.Http.BadUrl _ ->
                    "the server address is invalid."


{-| Preserve decoder and address details for diagnostics without changing user-facing copy.
-}
errorDetails : Graphql.Http.Error response -> String
errorDetails error =
    case error of
        Graphql.Http.HttpError (Graphql.Http.BadPayload details) ->
            Decode.errorToString details

        Graphql.Http.HttpError (Graphql.Http.BadUrl url) ->
            "invalid server address: " ++ url

        _ ->
            errorMessage error


requiresCurrentDeployment : Graphql.Http.Error response -> Bool
requiresCurrentDeployment error =
    case error of
        Graphql.Http.HttpError (Graphql.Http.BadStatus metadata _) ->
            metadata.statusCode == 410

        _ ->
            hasErrorCode "DEPLOYMENT_DRAINING" error
