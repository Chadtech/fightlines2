module Analytics exposing
    ( Event
    , data
    , noData
    , none
    , toEff
    , withData
    )

import Api.Mutation
import ApiRequest
import Effect as E exposing (Eff)
import Json.Encode as Encode



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Event
    = None
    | Event String (List ( String, Encode.Value ))



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


none : Event
none =
    None


noData : String -> Event
noData name =
    data name []


data : String -> List ( String, Encode.Value ) -> Event
data =
    Event


{-| Set a field on a recorded event, replacing any value for that key.
-}
withData : String -> Encode.Value -> Event -> Event
withData key value event =
    case event of
        None ->
            None

        Event name fields ->
            Event name
                (( key, value )
                    :: List.filter (Tuple.first >> (/=) key) fields
                )


toEff :
    (ApiRequest.Response Bool -> msg)
    -> Event
    -> Eff msg
toEff onResponse event =
    case event of
        None ->
            E.none

        Event name fields ->
            Api.Mutation.recordAnalytics
                { input =
                    { name = name
                    , data = Encode.encode 0 (Encode.object fields)
                    }
                }
                |> ApiRequest.mutationRequest
                |> E.request onResponse
