port module Checks.Deployment exposing (main)

import Admin.Route as AdminRoute
import ApiRequest exposing (Response)
import Deployment
import DevTools.Route as DevToolsRoute
import Dict
import Fightlines.Route as Route
import Game.LogId as GameLogId
import Graphql.Http
import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Url


port results : List String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    case Url.fromString "https://fightlines.online/match-making" of
        Nothing ->
            [ "invalid URL fixture" ]

        Just url ->
            let
                accepting : Deployment.Model
                accepting =
                    Deployment.init url

                draining : Deployment.Model
                draining =
                    { accepting | status = Deployment.Draining (Just "1800000000000") }

                check : String -> Bool -> List String
                check description passed =
                    if passed then
                        []

                    else
                        [ description ]

                roundTrips : (Url.Url -> Maybe route) -> (route -> String) -> route -> Bool
                roundTrips parse toString route =
                    let
                        parses : String -> Bool
                        parses path =
                            Url.fromString ("https://fightlines.online" ++ path)
                                |> Maybe.andThen parse
                                |> (==) (Just route)
                    in
                    parses (toString route)

                gamePath : String
                gamePath =
                    "/game/0123456789abcdef0123456789abcdef"

                lobbyPath : String
                lobbyPath =
                    "/lobby/0123456789abcdef0123456789abcdef"

                gameDocument : Deployment.Model
                gameDocument =
                    Deployment.init { url | path = lobbyPath }

                adminRoundTrips : AdminRoute.Route -> Bool
                adminRoundTrips =
                    roundTrips AdminRoute.fromUrl AdminRoute.toString

                devToolsRoundTrips : DevToolsRoute.Route -> Bool
                devToolsRoundTrips =
                    roundTrips DevToolsRoute.fromUrl DevToolsRoute.toString

                replayRoutesParse : Bool
                replayRoutesParse =
                    case GameLogId.parse "0123456789abcdef0123456789abcdef-1800000000000000000" of
                        Ok id ->
                            adminRoundTrips (AdminRoute.Replay id) && devToolsRoundTrips (DevToolsRoute.Replay id)

                        Err _ ->
                            False
            in
            List.concat
                [ check "stable matchmaking parses" (Route.fromUrl url == Just Route.MatchMaking)
                , check "admin dashboard and sign-out use stable routes" (List.all adminRoundTrips [ AdminRoute.Dashboard, AdminRoute.SignOut ])
                , check "dev tools use stable routes" (List.all devToolsRoundTrips [ DevToolsRoute.Home, DevToolsRoute.CombatChart, DevToolsRoute.BackdropReview, DevToolsRoute.MapEditor, DevToolsRoute.LoggedGames ])
                , check "replay routes remain stable" replayRoutesParse
                , check "accepting home remains an SPA navigation" (Deployment.navigation accepting "/" == { url = "/", fullLoad = False })
                , check "draining home loads current document" (Deployment.navigation draining "/" == { url = "/", fullLoad = True })
                , check "draining matchmaking loads canonical entry" (Deployment.navigation draining "/match-making" == { url = "/match-making", fullLoad = True })
                , check "delayed responses cannot undo draining" (Deployment.observe Deployment.AcceptingNewGames draining == draining)
                , check "entering a game loads its owner-selected document" (Deployment.navigation accepting gamePath == { url = gamePath, fullLoad = True })
                , check "lobby to game stays on the same connection" (Deployment.navigation gameDocument gamePath == { url = gamePath, fullLoad = False })
                , check "game documents identify their session" (Deployment.init { url | path = gamePath } == gameDocument)
                , check "map documents identify their session" (Deployment.init { url | path = lobbyPath ++ "/maps" } == gameDocument)
                , check "lobby maps stay on the same connection" (Deployment.navigation gameDocument (lobbyPath ++ "/maps") == { url = lobbyPath ++ "/maps", fullLoad = False })
                , check "draining does not interrupt same-game navigation" (Deployment.navigation { gameDocument | status = Deployment.Draining Nothing } gamePath == { url = gamePath, fullLoad = False })
                , check "another game's invite loads its own document" (Deployment.navigation gameDocument "/lobby/abcdef0123456789abcdef0123456789ab" == { url = "/lobby/abcdef0123456789abcdef0123456789ab", fullLoad = True })
                , check "leaving a game loads the current entry document" (Deployment.navigation gameDocument "/new" == { url = "/new", fullLoad = True })
                , pollingChecks gameDocument
                ]


pollingChecks : Deployment.Model -> List String
pollingChecks initial =
    let
        unavailable : String -> Graphql.Http.Error Deployment.Status
        unavailable date =
            Graphql.Http.HttpError
                (Graphql.Http.BadStatus
                    { url = "https://fightlines.online/graphql"
                    , statusCode = 503
                    , statusText = "service unavailable"
                    , headers = Dict.singleton "date" date
                    }
                    "service unavailable"
                )

        malformed : Graphql.Http.Error Deployment.Status
        malformed =
            Graphql.Http.HttpError
                (Graphql.Http.BadPayload
                    (Decode.Field "draining" (Decode.Failure "expected a boolean" (Encode.string "invalid")))
                )

        gone : Graphql.Http.Error Deployment.Status
        gone =
            Graphql.Http.HttpError
                (Graphql.Http.BadStatus
                    { url = "https://fightlines.online/graphql"
                    , statusCode = 410
                    , statusText = "gone"
                    , headers = Dict.empty
                    }
                    "this session has ended"
                )

        responses : List (Response Deployment.Status)
        responses =
            [ Err (unavailable "first poll")
            , Err (unavailable "second poll")
            , Err malformed
            , Err malformed
            , Ok (Deployment.Draining (Just "1800000000000"))
            , Err (unavailable "new outage")
            , Err gone
            , Ok Deployment.AcceptingNewGames
            ]

        receive : Response Deployment.Status -> ( Deployment.Model, List String ) -> ( Deployment.Model, List String )
        receive response ( model, details ) =
            let
                ( updated, failure ) =
                    Deployment.receive response model

                newDetails : List String
                newDetails =
                    failure
                        |> Maybe.map (ApiRequest.errorDetails >> List.singleton)
                        |> Maybe.withDefault []
            in
            ( updated, details ++ newDetails )

        ( final, diagnostics ) =
            List.foldl receive ( initial, [] ) responses

        ( failed, _ ) =
            Deployment.receive (Err (unavailable "failed poll")) initial

        expectedDetails : List String
        expectedDetails =
            [ ApiRequest.errorDetails (unavailable "first poll")
            , ApiRequest.errorDetails malformed
            , ApiRequest.errorDetails (unavailable "new outage")
            ]

        passed : Bool
        passed =
            (diagnostics == expectedDetails)
                && String.contains "draining" (ApiRequest.errorDetails malformed)
                && String.contains "expected a boolean" (ApiRequest.errorDetails malformed)
                && (failed.status == initial.status)
                && (failed.documentSession == initial.documentSession)
                && (final.documentSession == initial.documentSession)
                && (final.status == Deployment.Draining (Just "1800000000000"))
                && (final.lastFailure == Nothing)
    in
    if passed then
        []

    else
        [ "deployment polling must preserve status and decoder details, coalesce failures, reset after recovery, and treat retirement as a handoff" ]
