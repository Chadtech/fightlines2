module DevTools.Page.CombatChart exposing
    ( Flags
    , Model
    , Msg(..)
    , Status(..)
    , TerrainColumns(..)
    , init
    , load
    , setShared
    , update
    , view
    )

import Api.Enum.AttackAspect as Aspect
import Api.Enum.CombatChartCover as Cover
import Api.Enum.CombatChartDefense as Defense
import Api.Enum.CombatKind as Attack exposing (CombatKind)
import Api.Enum.CombatReadyOrder as ReadyOrder
import Api.Enum.UnitKind as Kind
import Api.InputObject
import Api.Object
import Api.Object.CombatChartHit as HitApi
import Api.Object.DamageCalculation as CalculationApi
import Api.Object.DamageFactors as FactorsApi
import Api.Query
import ApiRequest
import DevTools.CombatChart as Chart
    exposing
        ( Calculation
        , Chart
        , Factors
        , Hit
        , Key
        , Settings
        )
import DevTools.Route as Route
import DevTools.Shared as Shared
import DevTools.View.CombatChart as ChartView
import Effect as E exposing (Eff)
import Graphql.Http
import Graphql.Operation exposing (RootQuery)
import Graphql.SelectionSet as SS
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Random
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox
import View.Select as Select



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Model =
    { shared : Shared.Model
    , settings : Settings
    , status : Status
    , terrainColumns : TerrainColumns
    , selected : Maybe Key
    }


type Status
    = Current Chart
    | Loading RequestId Chart
    | Failed String Chart


type RequestId
    = RequestId Int


type TerrainColumns
    = CompareTerrain
    | OpenGroundOnly
    | HillsForestOnly


type Msg
    = AttackChanged CombatKind
    | AttackerHpChanged String
    | DefenderHpChanged String
    | AimChanged Aspect.AttackAspect
    | ReadyOrderChanged ReadyOrder.CombatReadyOrder
    | TrenchesChanged Bool
    | FortressChanged Bool
    | TerrainColumnsChanged TerrainColumns
    | HitClicked Key
    | RetryClicked
    | ChartResponseReceived RequestId Settings (ApiRequest.Response (List Hit))



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


type alias Flags =
    { hits : List Hit
    }


init : Shared.Model -> Flags -> Model
init shared flags =
    { shared = shared
    , settings = Chart.defaultSettings
    , status =
        Current
            { settings = Chart.defaultSettings
            , hits = flags.hits
            }
    , terrainColumns = CompareTerrain
    , selected = preferredHit flags.hits
    }


load : Graphql.Http.Request Flags
load =
    SS.succeed Flags
        |> SS.with (chartSelection Chart.defaultSettings)
        |> ApiRequest.queryRequest



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


setShared : Shared.Model -> Model -> Model
setShared shared model =
    { model
        | shared = shared
    }


loadChart : Settings -> Graphql.Http.Request (List Hit)
loadChart settings =
    chartSelection settings
        |> ApiRequest.queryRequest


chartSelection : Settings -> SS.SelectionSet (List Hit) RootQuery
chartSelection settings =
    let
        hitSelection : SS.SelectionSet Hit Api.Object.CombatChartHit
        hitSelection =
            let
                factorsSelection : SS.SelectionSet Factors Api.Object.DamageFactors
                factorsSelection =
                    SS.succeed Factors
                        |> SS.with FactorsApi.basePower
                        |> SS.with FactorsApi.relativeHealth
                        |> SS.with FactorsApi.matchup
                        |> SS.with FactorsApi.readiness
                        |> SS.with FactorsApi.defenderFacing
                        |> SS.with FactorsApi.attackerAim
                        |> SS.with FactorsApi.cover
                        |> SS.with FactorsApi.ambush
                        |> SS.with FactorsApi.entrenchment
                        |> SS.with FactorsApi.fortification
            in
            SS.succeed Hit
                |> SS.with HitApi.attacker
                |> SS.with HitApi.defender
                |> SS.with HitApi.defense
                |> SS.with HitApi.cover
                |> SS.with
                    (HitApi.calculation
                        (SS.succeed Calculation
                            |> SS.with CalculationApi.damage
                            |> SS.with (CalculationApi.factors factorsSelection)
                        )
                    )
                |> SS.with HitApi.remainingHp
    in
    Api.Query.combatChart
        { input = Api.InputObject.buildCombatChartInput settings
        }
        hitSelection


currentChart : Model -> Chart
currentChart model =
    case model.status of
        Current chart ->
            chart

        Loading _ chart ->
            chart

        Failed _ chart ->
            chart


preferredHit : List Hit -> Maybe Key
preferredHit hits =
    let
        preferred : Hit -> Bool
        preferred hit =
            (hit.cover == Cover.OpenGround)
                && (hit.defense == Defense.Flank)
                && (hit.attacker == Kind.Infantry)
                && (hit.defender == Kind.Tank)
    in
    case List.head (List.filter preferred hits) of
        Just hit ->
            Just (Chart.key hit)

        Nothing ->
            List.head hits |> Maybe.map Chart.key


selectionForColumns : TerrainColumns -> Maybe Key -> Maybe Key
selectionForColumns columns selected =
    let
        withCover : Cover.CombatChartCover -> Key -> Key
        withCover cover key =
            { key
                | cover = cover
            }
    in
    case columns of
        CompareTerrain ->
            selected

        OpenGroundOnly ->
            Maybe.map (withCover Cover.OpenGround) selected

        HillsForestOnly ->
            Maybe.map (withCover Cover.HillsForest) selected


refresh : Settings -> Model -> ( Model, Eff Msg )
refresh settings model =
    let
        ( value, seed ) =
            Random.step (Random.int 0 2147483647) model.shared.seed

        requestId : RequestId
        requestId =
            RequestId value
    in
    ( { model
        | settings = settings
        , shared = Shared.setSeed seed model.shared
        , status = Loading requestId (currentChart model)
      }
    , E.request
        (ChartResponseReceived requestId settings)
        (loadChart settings)
    )


updateHealth : (Int -> Settings -> Settings) -> String -> Model -> ( Model, Eff Msg )
updateHealth change raw model =
    case String.toInt raw of
        Just value ->
            refresh (change (clamp 1 16 value) model.settings) model

        Nothing ->
            model
                |> E.withOut


setAttackerHp : Int -> Settings -> Settings
setAttackerHp value settings =
    { settings
        | attackerHp = value
    }


setDefenderHp : Int -> Settings -> Settings
setDefenderHp value settings =
    { settings
        | defenderHp = value
    }



----------------------------------------------------------------
-- UPDATE --
----------------------------------------------------------------


update : Msg -> Model -> ( Model, Eff Msg )
update msg model =
    let
        settings : Settings
        settings =
            model.settings
    in
    case msg of
        AttackChanged attack ->
            refresh
                { settings
                    | attack = attack
                }
                model

        AttackerHpChanged raw ->
            updateHealth setAttackerHp raw model

        DefenderHpChanged raw ->
            updateHealth setDefenderHp raw model

        AimChanged aim ->
            refresh
                { settings
                    | attackerAim = aim
                }
                model

        ReadyOrderChanged readyOrder ->
            refresh
                { settings
                    | readyOrder = readyOrder
                }
                model

        TrenchesChanged value ->
            refresh
                { settings
                    | entrenchedInfantry = value
                }
                model

        FortressChanged value ->
            refresh
                { settings
                    | fortress = value
                }
                model

        TerrainColumnsChanged columns ->
            { model
                | terrainColumns = columns
                , selected = selectionForColumns columns model.selected
            }
                |> E.withOut

        HitClicked selected ->
            { model
                | selected = Just selected
            }
                |> E.withOut

        RetryClicked ->
            refresh settings model

        ChartResponseReceived requestId requested result ->
            case model.status of
                Loading currentId previous ->
                    if requestId /= currentId then
                        model
                            |> E.withOut

                    else
                        case result of
                            Ok hits ->
                                let
                                    containsSelected : Hit -> Bool
                                    containsSelected hit =
                                        Just (Chart.key hit) == model.selected

                                    selected : Maybe Key
                                    selected =
                                        if List.any containsSelected hits then
                                            model.selected

                                        else
                                            preferredHit hits
                                in
                                { model
                                    | status =
                                        Current
                                            { settings = requested
                                            , hits = hits
                                            }
                                    , selected = selectionForColumns model.terrainColumns selected
                                }
                                    |> E.withOut

                            Err error ->
                                { model
                                    | status = Failed (ApiRequest.errorMessage error) previous
                                }
                                    |> E.withOut

                _ ->
                    model
                        |> E.withOut



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


view : Model -> List (Html Msg)
view model =
    let
        chart : Chart
        chart =
            currentChart model

        covers : List Cover.CombatChartCover
        covers =
            case model.terrainColumns of
                CompareTerrain ->
                    [ Cover.OpenGround
                    , Cover.HillsForest
                    ]

                OpenGroundOnly ->
                    [ Cover.OpenGround
                    ]

                HillsForestOnly ->
                    [ Cover.HillsForest
                    ]

        stale : Bool
        stale =
            case model.status of
                Current _ ->
                    False

                _ ->
                    True
    in
    [ H.div
        [ A.css
            [ S.col
            , S.g4
            , S.minW0
            , S.wFull
            ]
        ]
        [ H.a
            [ A.href (Route.toString Route.Home)
            , A.css
                [ S.link
                , S.wFitContent
                , S.ml16
                ]
            ]
            [ H.text "dev tools / combat chart"
            ]
        , controls model
        , statusView model
        , ChartView.table
            { chart = chart
            , covers = covers
            , selected = model.selected
            , disabled = stale
            , onSelect = HitClicked
            }
        , ChartView.detail chart model.selected
        , H.p
            []
            [ H.text "trucks cannot fire · damage assumes a legal hit · firing coverage and return fire are separate"
            ]
        ]
    ]


statusView : Model -> Html Msg
statusView model =
    case model.status of
        Current _ ->
            H.text ""

        Loading _ _ ->
            H.p
                [ Aria.role Aria.Status
                ]
                [ H.text "updating damage values… showing the previous settings until ready."
                ]

        Failed error _ ->
            H.div
                [ A.css
                    [ S.col
                    , S.g2
                    ]
                , Aria.role Aria.Alert
                ]
                [ H.p
                    []
                    [ H.text (error ++ " showing the previous results.")
                    ]
                , Button.secondary "retry" RetryClicked
                    |> Button.small
                    |> Button.toHtml
                ]


controls : Model -> Html Msg
controls model =
    let
        settings : Settings
        settings =
            model.settings

        aimControls : List (Html Msg)
        aimControls =
            if settings.attack == Attack.IndirectFire then
                []

            else
                [ select "attacker aim"
                    settings.attackerAim
                    [ { value = Aspect.Front
                      , label = "front"
                      }
                    , { value = Aspect.Flank
                      , label = "side"
                      }
                    , { value = Aspect.Rear
                      , label = "rear"
                      }
                    ]
                    AimChanged
                ]

        attackControls : List (Html Msg)
        attackControls =
            [ select "attack type"
                settings.attack
                [ { value = Attack.Ambush
                  , label = "ambush"
                  }
                , { value = Attack.AttackMove
                  , label = "attack move"
                  }
                , { value = Attack.IndirectFire
                  , label = "indirect fire"
                  }
                ]
                AttackChanged
            , health "attacker health" settings.attackerHp AttackerHpChanged
            , health "defender health" settings.defenderHp DefenderHpChanged
            ]

        defenseControls : List (Html Msg)
        defenseControls =
            [ select "ready defender order"
                settings.readyOrder
                [ { value = ReadyOrder.StandGround
                  , label = "stand ground"
                  }
                , { value = ReadyOrder.Ambush
                  , label = "ambush"
                  }
                , { value = ReadyOrder.AttackMove
                  , label = "attack move"
                  }
                ]
                ReadyOrderChanged
            , select "terrain columns"
                model.terrainColumns
                [ { value = CompareTerrain
                  , label = "open ground + hills / forest"
                  }
                , { value = OpenGroundOnly
                  , label = "open ground"
                  }
                , { value = HillsForestOnly
                  , label = "hills / forest"
                  }
                ]
                TerrainColumnsChanged
            ]

        fields : List (Html Msg)
        fields =
            attackControls ++ aimControls ++ defenseControls
    in
    [ H.div
        [ A.css
            [ S.grid
            , S.gridColumns "repeat(3, minmax(0, 1fr))"
            , S.g4
            , S.belowWidth 850
                [ S.gridColumns "repeat(auto-fit, minmax(min(100%, 18rem), 1fr))"
                ]
            ]
        ]
        fields
    , H.div
        [ A.css
            [ S.row
            , S.flexWrap
            , S.g4
            , S.pt3
            , S.borderT
            , S.borderGray2
            ]
        ]
        [ Checkbox.new
            { label = "entrenched infantry defenders"
            , checked = settings.entrenchedInfantry
            , onCheck = TrenchesChanged
            }
            |> Checkbox.toHtml
                [ H.text "entrenched infantry defenders"
                ]
        , Checkbox.new
            { label = "defenders inside a fortress"
            , checked = settings.fortress
            , onCheck = FortressChanged
            }
            |> Checkbox.toHtml
                [ H.text "defenders inside a fortress"
                ]
        ]
    ]
        |> Card.toHtml (Card.simple |> Card.withHeader (CardHeader.simple "combat chart"))


select :
    String
    -> value
    ->
        List
            { value : value
            , label : String
            }
    -> (value -> Msg)
    -> Html Msg
select label selected options onChange =
    H.label
        [ A.css
            [ S.col
            , S.g2
            , S.minW0
            ]
        ]
        [ H.span
            []
            [ H.text label
            ]
        , Select.new
            { selected = selected
            , options = options
            , onChange = onChange
            }
            |> Select.toHtml
        ]


health : String -> Int -> (String -> Msg) -> Html Msg
health label value onChange =
    H.label
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.span
            [ A.css
                [ S.row
                , S.justifySpaceBetween
                , S.g2
                ]
            ]
            [ H.text label
            , H.output
                [ A.css
                    [ S.tabularNums
                    , S.textGray5
                    ]
                ]
                [ H.text (String.fromInt value ++ " / 16 hp")
                ]
            ]
        , H.input
            [ A.type_ "range"
            , A.min "1"
            , A.max "16"
            , A.step "1"
            , A.value (String.fromInt value)
            , Aria.label label
            , Ev.onInput onChange
            , A.css
                [ S.wFull
                , S.accentYellow5
                ]
            ]
            []
        ]
