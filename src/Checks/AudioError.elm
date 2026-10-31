port module Checks.AudioError exposing (main)

import Browser
import DevPanel
import Fightlines.Shared as Shared
import LocalStorage
import OperatingSystem
import Ports.Js.From as FromJs
import Random


port diagnostics : List { title : String, details : String } -> Cmd msg


type Msg
    = SharedMsg Shared.Msg
    | NavigationIgnored


main : Program () Shared.Model Msg
main =
    Browser.application
        { init =
            \_ url key ->
                ( Shared.init (Random.initialSeed 42) OperatingSystem.Unknown LocalStorage.test url key
                , Cmd.none
                )
        , update = update
        , subscriptions =
            \_ ->
                FromJs.subscription
                    { listeners = [ FromJs.map SharedMsg Shared.listeners ]
                    , onError = Shared.gotFromJsError >> SharedMsg
                    }
        , view = \_ -> { title = "audio error checks", body = [] }
        , onUrlChange = \_ -> NavigationIgnored
        , onUrlRequest = \_ -> NavigationIgnored
        }


update : Msg -> Shared.Model -> ( Shared.Model, Cmd Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            recordErrors sharedMsg model

        NavigationIgnored ->
            ( model, Cmd.none )


recordErrors : Shared.Msg -> Shared.Model -> ( Shared.Model, Cmd Msg )
recordErrors msg model =
    let
        updated : Shared.Model
        updated =
            Shared.superUpdate msg model
                |> Tuple.first

        toDetails : DevPanel.Error -> { title : String, details : String }
        toDetails (DevPanel.Error details) =
            details
    in
    ( updated
    , Shared.devPanelErrors updated
        |> List.map toDetails
        |> diagnostics
    )
