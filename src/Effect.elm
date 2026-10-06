module Effect exposing
    ( Eff
    , after
    , load
    , map
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
import Browser.Navigation as Navigation
import Graphql.Http
import Ports.Js.To as ToJs
import Process
import Route
    exposing
        ( Route
        )
import Task exposing (Task)


type Eff msg
    = None
    | Request (Task Never msg)
    | Navigate Route
    | PushUrl String
    | Load String
    | ToJsMsg ToJs.Msg


none : Eff msg
none =
    None


withOut : model -> ( model, Eff msg )
withOut model =
    ( model, none )


toJs : ToJs.Msg -> Eff msg
toJs =
    ToJsMsg


request : (Response response -> msg) -> Graphql.Http.Request response -> Eff msg
request toMsg graphqlRequest =
    graphqlRequest
        |> Graphql.Http.toTask
        |> Task.map (Ok >> toMsg)
        |> Task.onError (Err >> toMsg >> Task.succeed)
        |> Request


after : Float -> msg -> Eff msg
after milliseconds msg =
    Process.sleep milliseconds
        |> Task.map (always msg)
        |> Request


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

        Request task ->
            Request (Task.map toMsg task)

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

        Request task ->
            Task.perform identity task

        Navigate route ->
            Navigation.pushUrl key (Route.toString route)

        PushUrl url ->
            Navigation.pushUrl key url

        Load url ->
            Navigation.load url

        ToJsMsg msg ->
            ToJs.toCmd msg
