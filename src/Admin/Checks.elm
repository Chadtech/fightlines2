port module Admin.Checks exposing (main)

import Admin exposing (Msg(..), Page(..))
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
    case GameLogId.parse "00000000000000000000000000000001-1700000000000" of
        Ok id ->
            let
                flags : Encode.Value
                flags =
                    Encode.object
                        [ ( "now", Encode.int 1700000000000 )
                        , ( "seed", Encode.int 17 )
                        , ( "screenSize"
                          , Encode.object
                                [ ( "width", Encode.int 1280 )
                                , ( "height", Encode.int 800 )
                                ]
                          )
                        , ( "operatingSystem", Encode.string "unknown" )
                        , ( "localStorage", Encode.object [] )
                        ]

                initial : Page
                initial =
                    Admin.init flags url key |> Tuple.first

                step : Msg -> Page -> Page
                step msg page =
                    Admin.superUpdate msg page |> Tuple.first

                loadingReplay : Page
                loadingReplay =
                    initial
                        |> step (RouteReceived (Just (Route.Replay id)))
                        |> step (SessionResponseReceived (Ok Session.SignedIn))

                retry : Page
                retry =
                    loadingReplay
                        |> step (ReplayResponseReceived (Err (Graphql.Http.HttpError Graphql.Http.Timeout)))
                        |> step RetryButtonClicked

                login : Page
                login =
                    initial
                        |> step (RouteReceived (Just Route.Dashboard))
                        |> step (SessionResponseReceived (Ok Session.SignedOut))

                signedIn : Page
                signedIn =
                    login
                        |> step (LoginMsg (Login.LoginResponseReceived (Ok Session.SignedIn)))

                signedOut : Page
                signedOut =
                    login
                        |> step (RouteReceived (Just Route.SignOut))
                        |> step (LogoutResponseReceived (Ok True))

                replayKeepsRoute : Bool
                replayKeepsRoute =
                    case loadingReplay of
                        LoadingReplay _ loadedId ->
                            loadedId == id

                        _ ->
                            False

                retryKeepsRoute : Bool
                retryKeepsRoute =
                    case retry of
                        Checking _ route ->
                            route == Just (Route.Replay id)

                        _ ->
                            False

                loginLoadsDashboard : Bool
                loginLoadsDashboard =
                    case signedIn of
                        LoadingDashboard _ ->
                            True

                        _ ->
                            False

                logoutReturnsToLogin : Bool
                logoutReturnsToLogin =
                    case signedOut of
                        Login route _ ->
                            route == Just Route.Dashboard

                        _ ->
                            False

                checksWithLabels : List ( String, Bool )
                checksWithLabels =
                    [ ( "an authenticated replay route must load the requested archive", replayKeepsRoute )
                    , ( "retry must keep the failed replay route", retryKeepsRoute )
                    , ( "successful login must load the dashboard", loginLoadsDashboard )
                    , ( "successful logout must return to dashboard login", logoutReturnsToLogin )
                    ]
            in
            List.filterMap failedCheck checksWithLabels

        Err error ->
            [ error ]


failedCheck : ( String, Bool ) -> Maybe String
failedCheck ( label, passed ) =
    if passed then
        Nothing

    else
        Just label
