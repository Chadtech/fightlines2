module Effect exposing
    ( Eff
    , after
    , and
    , audio
    , batch
    , focus
    , load
    , map
    , measure
    , none
    , pushUrl
    , request
    , toCmd
    , toJs
    , with
    , withOut
    )

import ApiRequest
    exposing
        ( Response
        )
import Audio
import Browser.Dom
import Browser.Navigation as Navigation
import Graphql.Http
import Ports.Js.To as ToJs
import Process
import Task



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Eff msg
    = None
    | Batch (List (Eff msg))
    | Request (GraphqlRequest msg)
    | After Float msg
    | Focus { htmlId : String } (Result Browser.Dom.Error () -> msg)
    | Measure String (Result Browser.Dom.Error Browser.Dom.Element -> msg)
    | PushUrl String
    | Load String
    | ToJsMsg ToJs.Msg


{-| Only `request` constructs this wrapper, keeping arbitrary commands outside
of the public effect API while capturing the GraphQL response type.
-}
type GraphqlRequest msg
    = GraphqlRequest (() -> Cmd msg)



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


none : Eff msg
none =
    None


{-| Run every effect in the group. As with Cmd.batch, execution order is unspecified.
-}
batch : List (Eff msg) -> Eff msg
batch effects =
    Batch effects


with : Eff msg -> model -> ( model, Eff msg )
with eff model =
    ( model, eff )


withOut : model -> ( model, Eff msg )
withOut model =
    ( model, none )


and : Eff msg -> ( model, Eff msg ) -> ( model, Eff msg )
and effect ( model, eff ) =
    ( model, Batch [ effect, eff ] )


toJs : ToJs.Msg -> Eff msg
toJs =
    ToJsMsg


audio : Audio.Event -> Eff msg
audio sound =
    toJs (ToJs.Audio sound)


request : (Response response -> msg) -> Graphql.Http.Request response -> Eff msg
request toMsg graphqlRequest =
    Request (GraphqlRequest (\() -> Graphql.Http.send toMsg graphqlRequest))


after : Float -> msg -> Eff msg
after =
    After


focus : { htmlId : String } -> (Result Browser.Dom.Error () -> msg) -> Eff msg
focus =
    Focus


{-| Navigate within the current app using an absolute or relative URL.
Typed route modules provide their own `pushUrl` helpers.
-}
pushUrl : String -> Eff msg
pushUrl =
    PushUrl


{-| Load a new document, including navigation between apps.
-}
load : String -> Eff msg
load =
    Load


map : (a -> b) -> Eff a -> Eff b
map toMsg effect =
    case effect of
        None ->
            None

        Batch effects ->
            Batch (List.map (map toMsg) effects)

        Request (GraphqlRequest send) ->
            Request (GraphqlRequest (\() -> Cmd.map toMsg (send ())))

        After milliseconds completed ->
            After milliseconds (toMsg completed)

        Focus element received ->
            Focus element (received >> toMsg)

        Measure htmlId received ->
            Measure htmlId (received >> toMsg)

        PushUrl url ->
            PushUrl url

        Load url ->
            Load url

        ToJsMsg msg ->
            ToJsMsg msg


toCmd : Navigation.Key -> Eff msg -> Cmd msg
toCmd key effect =
    case effect of
        None ->
            Cmd.none

        Batch effects ->
            Cmd.batch (List.map (toCmd key) effects)

        Request (GraphqlRequest send) ->
            send ()

        After milliseconds completed ->
            Process.sleep milliseconds
                |> Task.perform (always completed)

        Focus element received ->
            Browser.Dom.focus element.htmlId
                |> Task.attempt received

        Measure htmlId received ->
            Browser.Dom.getElement htmlId
                |> Task.attempt received

        PushUrl url ->
            Navigation.pushUrl key url

        Load url ->
            Navigation.load url

        ToJsMsg msg ->
            ToJs.toCmd msg


{-| Measure a rendered element after the browser has laid it out.
-}
measure : String -> (Result Browser.Dom.Error Browser.Dom.Element -> msg) -> Eff msg
measure =
    Measure
