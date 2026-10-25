module DevTools.Effect exposing
    ( Eff
    , after
    , and
    , batch
    , focus
    , load
    , map
    , measure
    , navigate
    , none
    , pushUrl
    , request
    , toCmd
    , toJs
    , withOut
    )

import ApiRequest
    exposing
        ( Response
        )
import Browser.Dom
import Browser.Navigation as Navigation
import Common
import DevTools.Ports.Js.To as ToJs
import DevTools.Route as Route
    exposing
        ( Route
        )
import Graphql.Http


type Eff msg
    = None
    | Batch (List (Eff msg))
    | Request (Common.Request msg)
    | After Float msg
    | Focus { htmlId : String } msg
    | Measure String (Result Browser.Dom.Error Browser.Dom.Element -> msg)
    | Navigate Route
    | PushUrl String
    | Load String
    | ToJsMsg ToJs.Msg


none : Eff msg
none =
    None


{-| Run every effect in the group. As with Cmd.batch, execution order is unspecified.
-}
batch : List (Eff msg) -> Eff msg
batch effects =
    Batch effects


withOut : model -> ( model, Eff msg )
withOut model =
    ( model, none )


and : Eff msg -> ( model, Eff msg ) -> ( model, Eff msg )
and effect ( model, eff ) =
    ( model, Batch [ effect, eff ] )


toJs : ToJs.Msg -> Eff msg
toJs =
    ToJsMsg


request : (Response response -> msg) -> Graphql.Http.Request response -> Eff msg
request toMsg graphqlRequest =
    Request (Common.request toMsg graphqlRequest)


after : Float -> msg -> Eff msg
after =
    After


focus : { htmlId : String } -> msg -> Eff msg
focus =
    Focus


navigate : Route -> Eff msg
navigate =
    Navigate


pushUrl : String -> Eff msg
pushUrl =
    PushUrl


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

        Request pending ->
            Request (Common.mapRequest toMsg pending)

        After milliseconds completed ->
            After milliseconds (toMsg completed)

        Focus element completed ->
            Focus element (toMsg completed)

        Measure htmlId received ->
            Measure htmlId (received >> toMsg)

        Navigate route ->
            Navigate route

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

        Request pending ->
            Common.sendRequest pending

        After milliseconds completed ->
            Common.after milliseconds completed

        Focus element completed ->
            Common.focus element completed

        Measure htmlId received ->
            Common.measure htmlId received

        Navigate route ->
            Navigation.pushUrl key (Route.toString route)

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
