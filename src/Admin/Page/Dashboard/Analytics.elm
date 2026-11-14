module Admin.Page.Dashboard.Analytics exposing
    ( Analytics(..)
    , accepts
    , begin
    , receive
    )

import Admin.Page.Dashboard.Analytics.LoadedResults as LoadedResults exposing (LoadedResults)
import Admin.Page.Dashboard.Analytics.Location exposing (Location)
import Admin.Page.Dashboard.Analytics.QueryResults exposing (QueryResults)
import Admin.Page.Dashboard.Analytics.RequestId as RequestId exposing (RequestId)
import ApiRequest exposing (Response)
import Random



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Analytics
    = NotLoaded
    | Loaded LoadedResults
    | Loading Pending
    | Failed
        { location : Location
        , previous : Maybe LoadedResults
        , error : String
        }


type alias Pending =
    { id : RequestId
    , location : Location
    , previous : Maybe LoadedResults
    }


type alias Started =
    { id : RequestId
    , seed : Random.Seed
    , analytics : Analytics
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


pendingRequest : RequestId -> Analytics -> Maybe Pending
pendingRequest id analytics =
    case analytics of
        Loading pending ->
            if id == pending.id then
                Just pending

            else
                Nothing

        _ ->
            Nothing



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


accepts : RequestId -> Analytics -> Bool
accepts id analytics =
    case pendingRequest id analytics of
        Just _ ->
            True

        Nothing ->
            False


begin : Location -> Random.Seed -> Analytics -> Maybe Started
begin location seed analytics =
    let
        start : Maybe LoadedResults -> Maybe Started
        start previous =
            let
                ( id, nextSeed ) =
                    Random.step RequestId.generator seed
            in
            Just
                { id = id
                , seed = nextSeed
                , analytics =
                    Loading
                        { id = id
                        , location = location
                        , previous = previous
                        }
                }
    in
    case analytics of
        NotLoaded ->
            start Nothing

        Loaded loaded ->
            start (Just loaded)

        Loading _ ->
            Nothing

        Failed failure ->
            start failure.previous


receive :
    RequestId
    -> Response QueryResults
    -> Analytics
    -> Maybe Analytics
receive id response analytics =
    let
        complete : Pending -> Analytics
        complete pending =
            case response of
                Ok results ->
                    Loaded
                        (LoadedResults.init id pending.location results)

                Err error ->
                    Failed
                        { location = pending.location
                        , previous = pending.previous
                        , error = ApiRequest.errorMessage error
                        }
    in
    pendingRequest id analytics
        |> Maybe.map complete
