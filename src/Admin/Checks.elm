port module Admin.Checks exposing (main)

import Admin exposing (Model, Msg(..), Page(..), PageMsg(..))
import Admin.Page.Login as Login
import Admin.Route as Route
import Api.Enum.SessionStatus as Session
import Browser
import Browser.Navigation as Navigation
import Game.LogId as GameLogId
import Graphql.Http
import Json.Encode as Encode
import Url exposing (Url)


port results : List String -> Cmd msg


main : Program () () ()
main =
    Browser.application
        { init = initialize
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = \_ -> { title = "admin state checks", body = [] }
        , onUrlChange = \_ -> ()
        , onUrlRequest = \_ -> ()
        }


initialize : () -> Url -> Navigation.Key -> ( (), Cmd () )
initialize _ url key =
    ( (), results (checks url key) )


checks : Url -> Navigation.Key -> List String
checks url key =
    case
        ( GameLogId.parse "00000000000000000000000000000001-1700000000000"
        , GameLogId.parse "00000000000000000000000000000002-1700000000001"
        )
    of
        ( Ok firstId, Ok secondId ) ->
            let
                flags : Encode.Value
                flags =
                    Encode.object
                        [ ( "now", Encode.int 1700000000000 )
                        , ( "seed", Encode.int 17 )
                        , ( "operatingSystem", Encode.string "unknown" )
                        , ( "localStorage", Encode.object [] )
                        ]

                initial : Model
                initial =
                    Admin.init flags url key |> Tuple.first

                step : Msg -> Model -> Model
                step msg model =
                    Admin.update msg model |> Tuple.first

                send : PageMsg -> Model -> Model
                send event model =
                    step (PageMsg model.visitId event) model

                first : Model
                first =
                    initial
                        |> step (RouteReceived (Just (Route.Replay firstId)))
                        |> send (SessionResponseReceived (Ok Session.SignedIn))

                second : Model
                second =
                    first
                        |> step (RouteReceived (Just (Route.Replay secondId)))
                        |> send (SessionResponseReceived (Ok Session.SignedIn))

                delayedFailure : Model
                delayedFailure =
                    second
                        |> step (PageMsg first.visitId (ReplayResponseReceived (Err (Graphql.Http.HttpError Graphql.Http.Timeout))))

                delayedSession : Model
                delayedSession =
                    first
                        |> step (RouteReceived (Just (Route.Replay secondId)))
                        |> step (PageMsg initial.visitId (SessionResponseReceived (Ok Session.SignedOut)))

                failed : Model
                failed =
                    second
                        |> send (ReplayResponseReceived (Err (Graphql.Http.HttpError Graphql.Http.Timeout)))

                retry : Model
                retry =
                    failed |> send RetryButtonClicked

                login : Model
                login =
                    initial
                        |> step (RouteReceived (Just Route.Dashboard))
                        |> send (SessionResponseReceived (Ok Session.SignedOut))

                signedOut : Model
                signedOut =
                    login
                        |> step (RouteReceived (Just Route.SignOut))
                        |> send (LogoutResponseReceived (Ok True))

                staleLogin : Model
                staleLogin =
                    signedOut
                        |> step (PageMsg login.visitId (LoginMsg (Login.LoginResponseReceived (Ok Session.SignedIn))))

                isSecondLoading : Model -> Bool
                isSecondLoading model =
                    case model.page of
                        LoadingReplay _ id ->
                            id == secondId

                        _ ->
                            False

                retryKeepsRoute : Bool
                retryKeepsRoute =
                    case retry.page of
                        Checking _ route ->
                            route == Just (Route.Replay secondId)

                        _ ->
                            False

                staysSignedOut : Bool
                staysSignedOut =
                    case staleLogin.page of
                        Login _ _ ->
                            True

                        _ ->
                            False

                checksWithLabels : List ( String, Bool )
                checksWithLabels =
                    [ ( "a delayed replay response must not replace the next replay", isSecondLoading delayedFailure )
                    , ( "a delayed session response must not replace a newer session check", isChecking delayedSession )
                    , ( "retry must keep the failed replay route", retryKeepsRoute )
                    , ( "a login response from before logout must be ignored", staysSignedOut )
                    ]
            in
            List.filterMap failedCheck checksWithLabels

        ( Err error, _ ) ->
            [ error ]

        ( _, Err error ) ->
            [ error ]


isChecking : Model -> Bool
isChecking model =
    case model.page of
        Checking _ _ ->
            True

        _ ->
            False


failedCheck : ( String, Bool ) -> Maybe String
failedCheck ( label, passed ) =
    if passed then
        Nothing

    else
        Just label
