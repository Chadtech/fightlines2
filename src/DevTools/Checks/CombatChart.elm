port module DevTools.Checks.CombatChart exposing (main)

import Api.Enum.CombatChartCover as Cover
import Api.Enum.CombatChartDefense as Defense
import Api.Enum.CombatKind as Attack
import Api.Enum.UnitKind as Kind
import Browser
import Browser.Navigation as Navigation
import DevTools.CombatChart as Chart
import DevTools.Page.CombatChart as Page
import DevTools.Route as Route
import DevTools.Shared as Shared
import Graphql.Http
import LocalStorage
import OperatingSystem
import Random
import Url



----------------------------------------------------------------
-- CHECKS --
----------------------------------------------------------------


port results : List String -> Cmd msg


main : Program () () ()
main =
    Browser.application
        { init = initialize
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , view = view
        , onUrlChange = \_ -> ()
        , onUrlRequest = \_ -> ()
        }


initialize : () -> Url.Url -> Navigation.Key -> ( (), Cmd () )
initialize _ _ key =
    ( (), results (checks (Shared.init (Random.initialSeed 17) OperatingSystem.Unknown LocalStorage.test key)) )


view : () -> Browser.Document ()
view _ =
    { title = "combat chart checks"
    , body = []
    }


checks : Shared.Model -> List String
checks shared =
    let
        initial : Page.Model
        initial =
            Page.init shared
                { hits =
                    [ hit
                    ]
                }

        step : Page.Msg -> Page.Model -> Page.Model
        step msg model =
            Page.update msg model |> Tuple.first

        first : Page.Model
        first =
            step (Page.AttackerHpChanged "8") initial

        latest : Page.Model
        latest =
            step (Page.AttackerHpChanged "4") first

        staleResponse : Page.Model
        staleResponse =
            respond (Ok []) first latest

        loaded : Page.Model
        loaded =
            respond
                (Ok
                    [ hit
                    ]
                )
                latest
                latest

        failed : Page.Model
        failed =
            respond (Err (Graphql.Http.HttpError Graphql.Http.NetworkError)) latest latest

        retry : Page.Model
        retry =
            step Page.RetryClicked failed

        validCurrent : Page.Model -> Bool
        validCurrent model =
            case model.status of
                Page.Current chart ->
                    (chart.settings.attackerHp == 4)
                        && (chart.hits
                                == [ hit
                                   ]
                           )

                _ ->
                    False

        preservesPrevious : Bool
        preservesPrevious =
            case failed.status of
                Page.Failed _ chart ->
                    (chart.settings.attackerHp == 16)
                        && (chart.hits
                                == [ hit
                                   ]
                           )

                _ ->
                    False

        retryPreservesSettings : Bool
        retryPreservesSettings =
            case retry.status of
                Page.Loading _ _ ->
                    retry.settings.attackerHp == 4

                _ ->
                    False

        coverSelected : Page.Model
        coverSelected =
            step (Page.TerrainColumnsChanged Page.HillsForestOnly) initial

        indirectPending : Page.Model
        indirectPending =
            step (Page.AttackChanged Attack.IndirectFire) coverSelected

        indirectHits : List Chart.Hit
        indirectHits =
            [ { hit
                | attacker = Kind.FieldGun
                , defense = Defense.Ready
              }
            , { hit
                | attacker = Kind.FieldGun
                , defense = Defense.Ready
                , cover = Cover.HillsForest
              }
            ]

        indirectLoaded : Page.Model
        indirectLoaded =
            respond (Ok indirectHits) indirectPending indirectPending

        indirectSelectionVisible : Bool
        indirectSelectionVisible =
            Maybe.map .cover indirectLoaded.selected == Just Cover.HillsForest

        expectedSelection : Chart.Key
        expectedSelection =
            { attacker = Kind.Infantry
            , defender = Kind.Tank
            , defense = Defense.Flank
            , cover = Cover.HillsForest
            }

        route : Maybe Route.Route
        route =
            Url.fromString "http://localhost/dev/combat-chart" |> Maybe.andThen Route.fromUrl
    in
    List.filterMap identity
        [ expect "older slider responses cannot overwrite newer settings" (staleResponse == latest)
        , expect "latest response updates results with its matching settings" (validCurrent loaded)
        , expect "failed refresh retains the previous chart" preservesPrevious
        , expect "retry preserves edited settings" retryPreservesSettings
        , expect "terrain columns keep selection in the visible columns" (coverSelected.selected == Just expectedSelection)
        , expect "new attack types keep selection in filtered terrain columns" indirectSelectionVisible
        , expect "invalid health text is ignored" (step (Page.AttackerHpChanged "bad") initial == initial)
        , expect "health controls clamp to legal values" ((step (Page.DefenderHpChanged "90") initial).settings.defenderHp == 16)
        , expect "indirect chart has only readiness columns"
            (Chart.defenses
                { defaultSettings
                    | attack = Attack.IndirectFire
                }
                == [ Defense.Unready
                   , Defense.Ready
                   ]
            )
        , expect "combat chart route round-trips" ((route == Just Route.CombatChart) && (Route.toString Route.CombatChart == "/dev/combat-chart"))
        ]


defaultSettings : Chart.Settings
defaultSettings =
    Chart.defaultSettings


respond : Result (Graphql.Http.Error (List Chart.Hit)) (List Chart.Hit) -> Page.Model -> Page.Model -> Page.Model
respond result source target =
    case source.status of
        Page.Loading requestId _ ->
            Page.update (Page.ChartResponseReceived requestId source.settings result) target |> Tuple.first

        _ ->
            target


expect : String -> Bool -> Maybe String
expect label condition =
    if condition then
        Nothing

    else
        Just label


hit : Chart.Hit
hit =
    { attacker = Kind.Infantry
    , defender = Kind.Tank
    , defense = Defense.Flank
    , cover = Cover.OpenGround
    , remainingHp = 8
    , calculation =
        { damage = 8
        , factors =
            { basePower = 4
            , relativeHealth = 1
            , matchup = 0.25
            , readiness = 1
            , defenderFacing = 1.5
            , attackerAim = 1
            , cover = 1
            , ambush = 5
            , entrenchment = 1
            , fortification = 1
            }
        }
    }
