module Deployment exposing
    ( Model
    , Status(..)
    , init
    , load
    , navigation
    , observe
    , receive
    , selection
    )

import Api.Object
import Api.Object.PlayerDeploymentStatus as StatusApi
import Api.Query
import ApiRequest exposing (Response)
import Graphql.Http
import Graphql.SelectionSet as SS exposing (SelectionSet)
import LobbyId exposing (LobbyId)
import Url exposing (Url)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Status
    = AcceptingNewGames
    | Draining (Maybe String)


type alias Model =
    { documentSession : Maybe LobbyId
    , status : Status
    , lastFailure : Maybe (Graphql.Http.Error Status)
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : Url -> Model
init url =
    { documentSession = session url.path
    , status = AcceptingNewGames
    , lastFailure = Nothing
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


{-| The document's session determines which navigation can use its API connection.
Entering another session loads its document so the server resolves ownership.
-}
session : String -> Maybe LobbyId
session path =
    case String.split "/" path of
        [ "", "lobby", id ] ->
            LobbyId.fromString id |> Result.toMaybe

        [ "", "lobby", id, "maps" ] ->
            LobbyId.fromString id |> Result.toMaybe

        [ "", "game", id ] ->
            LobbyId.fromString id |> Result.toMaybe

        _ ->
            Nothing


selection : SelectionSet Status Api.Object.PlayerDeploymentStatus
selection =
    SS.succeed status
        |> SS.with StatusApi.draining
        |> SS.with StatusApi.shutdownAt


status : Bool -> Maybe String -> Status
status draining deadline =
    if draining then
        Draining deadline

    else
        AcceptingNewGames



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


load : Graphql.Http.Request Status
load =
    Api.Query.deploymentStatus selection
        |> ApiRequest.queryRequest


{-| Public destinations stay stable. Crossing a session boundary or leaving a
draining entry document loads the server-selected frontend and API connection.
-}
navigation : Model -> String -> { url : String, fullLoad : Bool }
navigation deployment destination =
    let
        newSession : Bool
        newSession =
            List.member destination [ "/", "/new", "/match-making" ]

        draining : Bool
        draining =
            case deployment.status of
                AcceptingNewGames ->
                    False

                Draining _ ->
                    True

        destinationSession : Maybe LobbyId
        destinationSession =
            session destination

        crossingSession : Bool
        crossingSession =
            destinationSession /= deployment.documentSession
    in
    { url = destination
    , fullLoad = crossingSession || (newSession && draining)
    }


{-| Draining is monotonic, including responses delayed across the transition.
-}
observe : Status -> Model -> Model
observe received model =
    let
        latestStatus : Status
        latestStatus =
            case model.status of
                AcceptingNewGames ->
                    received

                Draining _ ->
                    model.status
    in
    { model | status = latestStatus, lastFailure = Nothing }


{-| Retain the last known status and coalesce consecutive matching polling failures.
A successful observation resets suppression so a later outage is recorded again.
-}
receive : Response Status -> Model -> ( Model, Maybe (Graphql.Http.Error Status) )
receive response model =
    case response of
        Ok received ->
            ( observe received model, Nothing )

        Err error ->
            if ApiRequest.requiresCurrentDeployment error then
                ( observe (Draining Nothing) model, Nothing )

            else
                let
                    repeatedFailure : Bool
                    repeatedFailure =
                        Maybe.map ApiRequest.errorDetails model.lastFailure == Just (ApiRequest.errorDetails error)

                    diagnostic : Maybe (Graphql.Http.Error Status)
                    diagnostic =
                        if repeatedFailure then
                            Nothing

                        else
                            Just error
                in
                ( { model | lastFailure = Just error }, diagnostic )
