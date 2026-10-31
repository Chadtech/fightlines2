module Game.View.CombatFormation exposing
    ( Animation
    , TrenchOccupancy(..)
    , exhaustionEndsAt
    , exhaustionToSvg
    , figureCount
    , impactStarts
    , lossStartsAt
    , toSvg
    , toSvgWithCalibration
    , trenchLossEndsAt
    )

import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Game.BackdropCalibration as BackdropCalibration exposing (Calibration)
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatBazooka as CombatBazooka
import Game.View.CombatExplosion as CombatExplosion
import Game.View.CombatInfantry as CombatInfantry
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


type alias Animation =
    { elapsed : Float
    , impactDelay : Float
    , attack : CombatAttack.Attack
    , infantryLoadout : CombatInfantry.Loadout
    , trenchOccupancy : TrenchOccupancy
    }


type TrenchOccupancy
    = Occupied
    | ShelteringUnderground


{-| Theater figures summarize health; they do not change authoritative damage.
The two-man machine-gun team represents four HP; six riflemen each represent two.
Bazooka teams and other unit kinds have four HP per figure.
A partially intact figure stays visible.
-}
figureCount : CombatInfantry.Loadout -> UnitKind -> Int -> Int
figureCount loadout kind hitPoints =
    case kind of
        Kind.Infantry ->
            case loadout of
                CombatInfantry.Bazookas ->
                    clamp 0 4 ((max 0 hitPoints + 3) // 4)

                CombatInfantry.SmallArms ->
                    if hitPoints <= 0 then
                        0

                    else
                        1 + clamp 0 6 ((max 0 (hitPoints - 4) + 1) // 2)

        _ ->
            clamp 0 4 ((max 0 hitPoints + 3) // 4)


lossStartsAt : { surviving : Int, index : Int } -> Float
lossStartsAt config =
    impactStartsAt + toFloat (config.index - config.surviving) * 120


{-| Let the 200ms card expansion finish, then hold the scene for one second.
-}
impactStartsAt : Float
impactStartsAt =
    CombatAttack.anticipationMs


impactStarts : CombatInfantry.Loadout -> UnitKind -> CombatHealth -> List Float
impactStarts loadout kind health =
    let
        beforeCount : Int
        beforeCount =
            figureCount loadout kind health.before.current

        afterCount : Int
        afterCount =
            figureCount loadout kind health.after.current

        damaged : Bool
        damaged =
            health.after.current < health.before.current

        startsAt : Int -> Float
        startsAt index =
            lossStartsAt { surviving = afterCount, index = index }
    in
    if beforeCount > afterCount then
        List.range afterCount (beforeCount - 1) |> List.map startsAt

    else if damaged && beforeCount > 0 then
        [ impactStartsAt ]

    else
        []


type alias Placement =
    { x : Float
    , y : Float
    , size : Float
    }


type alias PlacedFigure =
    { index : Int
    , placement : Placement
    }


type CasualtyEffect
    = ShellImpact
    | SupplyExhaustion


type Layer
    = Combatants
    | Impacts
    | ExhaustionMarkers


placements : UnitKind -> List Placement
placements kind =
    let
        vehiclePlacements : List Placement
        vehiclePlacements =
            [ { x = 6
              , y = 25
              , size = 25
              }
            , { x = 40
              , y = 27
              , size = 25
              }
            , { x = 19
              , y = 32
              , size = 28
              }
            , { x = 57
              , y = 34
              , size = 28
              }
            ]
    in
    case kind of
        Kind.Infantry ->
            [ { x = 28.5
              , y = 7
              , size = 39
              }
            , { x = 5.5
              , y = 1.3
              , size = 25
              }
            , { x = 38
              , y = 4
              , size = 20
              }
            , { x = 8
              , y = 44
              , size = 20
              }
            , { x = 58
              , y = -11.2
              , size = 36
              }
            , { x = 57
              , y = 7.9
              , size = 38
              }
            , { x = 56
              , y = 25
              , size = 40
              }
            ]

        Kind.FieldGun ->
            -- Three small background guns spread across a shallow ground band.
            -- Paint the full-size centered foreground gun last, keeping positions fixed.
            [ { x = 3
              , y = 35
              , size = 25
              }
            , { x = 36
              , y = 34
              , size = 24
              }
            , { x = 65
              , y = 36
              , size = 28
              }
            , { x = 18
              , y = 39
              , size = 60
              }
            ]

        Kind.Tank ->
            vehiclePlacements

        Kind.Truck ->
            vehiclePlacements


combatantToSvg : Int -> Animation -> Appearance -> Svg msg
combatantToSvg index animation unit =
    case unit.kind of
        Kind.Infantry ->
            case animation.infantryLoadout of
                CombatInfantry.Bazookas ->
                    CombatBazooka.toSvg
                        { elapsed = animation.elapsed, figureIndex = index }
                        animation.attack
                        unit

                CombatInfantry.SmallArms ->
                    CombatInfantry.toSvg
                        { elapsed = animation.elapsed, figureIndex = index }
                        animation.attack
                        unit

        _ ->
            CombatAttack.toSvg { elapsed = animation.elapsed, figureIndex = index } animation.attack unit


toSvg : Animation -> CombatHealth -> Appearance -> List (Svg msg)
toSvg =
    layersToSvg ShellImpact Nothing [ Combatants, Impacts ]


toSvgWithCalibration : Maybe Calibration -> Animation -> CombatHealth -> Appearance -> List (Svg msg)
toSvgWithCalibration calibration =
    layersToSvg ShellImpact calibration [ Combatants, Impacts ]


exhaustionPulseDurationMs : Float
exhaustionPulseDurationMs =
    1000


exhaustionFlickerDurationMs : Float
exhaustionFlickerDurationMs =
    3 * exhaustionPulseDurationMs


exhaustionEndsAt : Float
exhaustionEndsAt =
    impactStartsAt + exhaustionFlickerDurationMs


{-| Three slow skull pulses precede simultaneous formation removal.
-}
exhaustionToSvg : Maybe Calibration -> Float -> CombatHealth -> Appearance -> List (Svg msg)
exhaustionToSvg calibration elapsed =
    layersToSvg SupplyExhaustion
        calibration
        [ Combatants, ExhaustionMarkers ]
        { elapsed = elapsed
        , impactDelay = 0
        , attack = CombatAttack.NotAttacking
        , infantryLoadout = CombatInfantry.SmallArms
        , trenchOccupancy = Occupied
        }


formationPlacements : CombatInfantry.Loadout -> Maybe Calibration -> Appearance -> List Placement
formationPlacements loadout calibration unit =
    if usesTrenches loadout unit then
        trenchImpactPlacements calibration

    else
        case calibration of
            Nothing ->
                if (unit.kind == Kind.Infantry) && (loadout == CombatInfantry.Bazookas) then
                    [ { x = 7
                      , y = 5
                      , size = 32
                      }
                    , { x = 49
                      , y = 8
                      , size = 32
                      }
                    , { x = 11
                      , y = 27
                      , size = 36
                      }
                    , { x = 55
                      , y = 29
                      , size = 36
                      }
                    ]

                else
                    placements unit.kind

            Just settings ->
                calibratedPlacements loadout settings unit


usesTrenches : CombatInfantry.Loadout -> Appearance -> Bool
usesTrenches loadout unit =
    (unit.kind == Kind.Infantry)
        && (unit.entrenchment == Entrenchment.Entrenched)
        && (loadout == CombatInfantry.SmallArms)


{-| Each trench resizes around its own bottom footing, preserving the inner gap.
Their size and footing are independent of each other and the exposed formation.
-}
trenchPlacements : Maybe Calibration -> List Placement
trenchPlacements calibration =
    let
        settings : Calibration
        settings =
            Maybe.withDefault BackdropCalibration.suggested calibration

        place : { x : Float, footing : Float, size : Float } -> Placement
        place row =
            let
                width : Float
                width =
                    96 * row.size / 100

                footing : Float
                footing =
                    64 * row.footing / 100
            in
            { x = row.x
            , y = footing - width * 809 / 1945
            , size = width
            }
    in
    List.map place
        [ { x = 44.4 - 96 * settings.trenchSize / 100
          , footing = settings.trenchFooting
          , size = settings.trenchSize
          }
        , { x = 51.6
          , footing = settings.secondTrenchFooting
          , size = settings.secondTrenchSize
          }
        ]


trenchLossEndsAt : CombatInfantry.Loadout -> Appearance -> CombatHealth -> Float
trenchLossEndsAt loadout unit health =
    if usesTrenches loadout unit then
        [ trenchLossAt health 0, trenchLossAt health 1 ]
            |> List.filterMap identity
            |> List.maximum
            |> Maybe.map (\startsAt -> startsAt + CombatExplosion.durationMs + trenchMarkerDurationMs)
            |> Maybe.withDefault 0

    else
        0


trenchMarkerDurationMs : Float
trenchMarkerDurationMs =
    650


{-| Match the four rear and three front hit positions. A segment is lost only
when all of its health groups are gone; partial damage keeps it occupied.
-}
trenchLossAt : CombatHealth -> Int -> Maybe Float
trenchLossAt health row =
    let
        first : Int
        first =
            if row == 0 then
                0

            else
                4

        last : Int
        last =
            if row == 0 then
                3

            else
                6

        before : Int
        before =
            figureCount CombatInfantry.SmallArms Kind.Infantry health.before.current

        after : Int
        after =
            figureCount CombatInfantry.SmallArms Kind.Infantry health.after.current
    in
    if (before > first) && (after <= first) then
        Just (lossStartsAt { surviving = after, index = min last (before - 1) })

    else
        Nothing


trenchToSvg : TrenchOccupancy -> Maybe Calibration -> Float -> CombatHealth -> Appearance -> List (Svg msg)
trenchToSvg occupancy calibration elapsed health unit =
    let
        team : String
        team =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    "red"

                PlayerNumber.Player2 ->
                    "blue"

        trench : Int -> Placement -> Svg msg
        trench row placement =
            let
                firstGroup : Int
                firstGroup =
                    if row == 0 then
                        0

                    else
                        4

                lostBefore : Bool
                lostBefore =
                    figureCount CombatInfantry.SmallArms Kind.Infantry health.before.current <= firstGroup

                lostNow : Bool
                lostNow =
                    trenchLossAt health row
                        |> Maybe.map (\startsAt -> elapsed >= startsAt + CombatExplosion.spriteDisappearsAt)
                        |> Maybe.withDefault False

                path : String
                path =
                    if (occupancy == ShelteringUnderground) || lostBefore || lostNow then
                        "/assets/combat-trench-overlay-anime-v2/empty.png"

                    else
                        "/assets/combat-trench-overlay-anime-v2/" ++ team ++ ".png"
            in
            Svg.image
                [ SA.xlinkHref path
                , SA.x (String.fromFloat placement.x)
                , SA.y (String.fromFloat placement.y)
                , SA.width (String.fromFloat placement.size)
                , SA.height (String.fromFloat (placement.size * 809 / 1945))
                , A.attribute "data-combat-trench" (String.fromInt row)
                , Aria.hidden True
                ]
                []

        facing : String
        facing =
            case unit.spriteFacing of
                SpriteFacing.Left ->
                    "translate(96 0) scale(-1 1)"

                SpriteFacing.Right ->
                    ""
    in
    [ Svg.g
        [ SA.transform facing ]
        (List.indexedMap trench (trenchPlacements calibration))
    ]


{-| Brief segment markers follow their final blast. The final unit marker stays
until the encounter closes. All timing uses the pausable theater clock.
-}
trenchMarkersToSvg : Maybe Calibration -> Float -> CombatHealth -> Appearance -> List (Svg msg)
trenchMarkersToSvg calibration elapsed health unit =
    let
        destroyed : Bool
        destroyed =
            health.after.current <= 0

        finalBlastEndsAt : Float
        finalBlastEndsAt =
            impactStarts CombatInfantry.SmallArms Kind.Infantry health
                |> List.maximum
                |> Maybe.withDefault impactStartsAt
                |> (+) CombatExplosion.durationMs

        marker : String -> Float -> Placement -> Svg msg
        marker name opacity placement =
            let
                size : Float
                size =
                    placement.size * 0.65

                centerX : Float
                centerX =
                    placement.x + placement.size / 2

                x : Float
                x =
                    if unit.spriteFacing == SpriteFacing.Left then
                        96 - centerX - size / 2

                    else
                        centerX - size / 2
            in
            Svg.image
                [ SA.xlinkHref "/assets/death-skull-illustrated-v1.png"
                , SA.x (String.fromFloat x)
                , SA.y (String.fromFloat (placement.y - size * 0.4))
                , SA.width (String.fromFloat size)
                , SA.height (String.fromFloat size)
                , SA.opacity (String.fromFloat opacity)
                , SA.pointerEvents "none"
                , A.attribute "data-trench-loss-marker" name
                , Aria.hidden True
                ]
                []

        segmentMarker : Int -> Placement -> List (Svg msg)
        segmentMarker row placement =
            case trenchLossAt health row of
                Just startsAt ->
                    let
                        age : Float
                        age =
                            elapsed - startsAt - CombatExplosion.durationMs
                    in
                    if (age >= 0) && (age < trenchMarkerDurationMs) then
                        [ marker (String.fromInt row) (1 - age / trenchMarkerDurationMs) placement ]

                    else
                        []

                Nothing ->
                    []
    in
    if destroyed && (elapsed >= finalBlastEndsAt + trenchMarkerDurationMs) then
        [ marker "unit" 1 { x = 28, y = 27, size = 40 } ]

    else
        trenchPlacements calibration
            |> List.indexedMap segmentMarker
            |> List.concat


{-| Keep the existing seven infantry hit cues, positioned inside the two trenches.
Individual losses keep the artwork intact until a whole segment is lost.
-}
trenchImpactPlacements : Maybe Calibration -> List Placement
trenchImpactPlacements calibration =
    let
        soldiers : Int -> Placement -> List Placement
        soldiers row placement =
            let
                offsets : List Float
                offsets =
                    if row == 0 then
                        [ 0.08, 0.29, 0.5, 0.71 ]

                    else
                        [ 0.12, 0.4, 0.68 ]

                soldier : Float -> Placement
                soldier offset =
                    { x = placement.x + placement.size * offset
                    , y = placement.y + placement.size * offset * 0.25
                    , size = placement.size * 8 / 33.6
                    }
            in
            List.map soldier offsets
    in
    trenchPlacements calibration
        |> List.indexedMap soldiers
        |> List.concat


{-| Depth runs from zero at the rear to one at the front. Formation patterns
remain unit-specific; the selected backdrop/unit calibration supplies ground and scale values.
-}
calibratedPlacements : CombatInfantry.Loadout -> Calibration -> Appearance -> List Placement
calibratedPlacements loadout settings unit =
    let
        -- Keep three readable rows around the calibrated ground band's center.
        -- Limit their span to half the scene height on deep terrain calibrations.
        footingAtDepth : Float -> Float
        footingAtDepth depth =
            case unit.kind of
                Kind.Infantry ->
                    let
                        center : Float
                        center =
                            64 * (settings.frontFooting - settings.rowSpacing / 2) / 100

                        span : Float
                        span =
                            min 32 (64 * settings.rowSpacing * 2.6 / 100)
                    in
                    center + (depth - 0.5) * span

                _ ->
                    64 * (settings.frontFooting - settings.rowSpacing * (1 - depth)) / 100

        -- Keep the expanded grid inside the scene on lower-footing backdrops.
        verticalOffset : Float
        verticalOffset =
            case unit.kind of
                Kind.Infantry ->
                    min 0 (63 - footingAtDepth 1)

                _ ->
                    0

        pattern :
            List
                { center : Float
                , depth : Float
                , proportion : Float
                }
        pattern =
            case unit.kind of
                Kind.Infantry ->
                    if loadout == CombatInfantry.Bazookas then
                        [ { center = 24
                          , depth = 0
                          , proportion = 1.3
                          }
                        , { center = 68
                          , depth = 0
                          , proportion = 1.3
                          }
                        , { center = 28
                          , depth = 1
                          , proportion = 1.3
                          }
                        , { center = 74
                          , depth = 1
                          , proportion = 1.3
                          }
                        ]

                    else
                        -- Rows: standing/kneeling/prone; empty/gun team/prone; kneeling/empty/prone.
                        [ { center = 48
                          , depth = 0.5
                          , proportion = 1.58
                          }
                        , { center = 18
                          , depth = 0
                          , proportion = 0.95
                          }
                        , { center = 48
                          , depth = 0
                          , proportion = 0.76
                          }
                        , { center = 18
                          , depth = 1
                          , proportion = 0.76
                          }
                        , { center = 78
                          , depth = 0
                          , proportion = 1.3
                          }
                        , { center = 78
                          , depth = 0.5
                          , proportion = 1.3
                          }
                        , { center = 78
                          , depth = 1
                          , proportion = 1.3
                          }
                        ]

                Kind.FieldGun ->
                    [ { center = 16
                      , depth = 0
                      , proportion = 1
                      }
                    , { center = 48
                      , depth = 0
                      , proportion = 1
                      }
                    , { center = 79
                      , depth = 0
                      , proportion = 1
                      }
                    , { center = 48
                      , depth = 1
                      , proportion = 2.14
                      }
                    ]

                _ ->
                    [ { center = 19
                      , depth = 0
                      , proportion = 1
                      }
                    , { center = 53
                      , depth = 0
                      , proportion = 1
                      }
                    , { center = 33
                      , depth = 1
                      , proportion = 1
                      }
                    , { center = 72
                      , depth = 1
                      , proportion = 1
                      }
                    ]

        place :
            { center : Float
            , depth : Float
            , proportion : Float
            }
            -> Placement
        place position =
            let
                perspective : Float
                perspective =
                    settings.rearScale / 100 + (1 - settings.rearScale / 100) * position.depth

                width : Float
                width =
                    96 * settings.unitSize / 100 * position.proportion * perspective

                footing : Float
                footing =
                    footingAtDepth position.depth + verticalOffset

                center : Float
                center =
                    clamp (width / 2 + 1) (95 - width / 2) position.center
            in
            { x = center - width / 2
            , y = footing - width / UnitSprite.portraitWidth unit * UnitSprite.portraitFooting unit
            , size = width
            }
    in
    List.map place pattern


layersToSvg : CasualtyEffect -> Maybe Calibration -> List Layer -> Animation -> CombatHealth -> Appearance -> List (Svg msg)
layersToSvg effect calibration layers animation health unit =
    let
        elapsed : Float
        elapsed =
            animation.elapsed - animation.impactDelay

        beforeCount : Int
        beforeCount =
            figureCount animation.infantryLoadout unit.kind health.before.current

        afterCount : Int
        afterCount =
            figureCount animation.infantryLoadout unit.kind health.after.current

        figure : Layer -> Int -> Placement -> Svg msg
        figure layer index placement =
            let
                scale : Float
                scale =
                    placement.size / UnitSprite.portraitWidth unit

                needsFlashSpace : Bool
                needsFlashSpace =
                    (unit.kind == Kind.Infantry)
                        && (animation.infantryLoadout == CombatInfantry.SmallArms)
                        && not (usesTrenches animation.infantryLoadout unit)

                placementX : Float
                placementX =
                    if needsFlashSpace then
                        -- Reserve the widest flash's 90/512 extension on ready
                        -- frames too, keeping edge figures still while firing.
                        min placement.x (96 - placement.size * 1.18)

                    else
                        placement.x

                x : Float
                x =
                    if unit.spriteFacing == SpriteFacing.Left then
                        96 - placementX - placement.size

                    else
                        placementX

                lost : Bool
                lost =
                    index >= afterCount

                startsAt : Float
                startsAt =
                    case effect of
                        ShellImpact ->
                            lossStartsAt { surviving = afterCount, index = index }

                        SupplyExhaustion ->
                            impactStartsAt

                visible : Bool
                visible =
                    not lost || elapsed < startsAt + disappearanceDelay

                disappearanceDelay : Float
                disappearanceDelay =
                    case effect of
                        ShellImpact ->
                            CombatExplosion.spriteDisappearsAt

                        SupplyExhaustion ->
                            exhaustionFlickerDurationMs

                spriteOpacity : Float
                spriteOpacity =
                    if lost then
                        case effect of
                            ShellImpact ->
                                CombatExplosion.spriteOpacity (elapsed - startsAt)

                            SupplyExhaustion ->
                                1

                    else
                        1

                sprite : List (Svg msg)
                sprite =
                    if visible then
                        [ Svg.g
                            [ SA.transform
                                ("scale(" ++ String.fromFloat scale ++ ")")
                            , SA.opacity (String.fromFloat spriteOpacity)
                            , SA.class "fightlines-combat-figure"
                            , A.attribute "data-figure-index" (String.fromInt index)
                            ]
                            [ combatantToSvg index animation unit ]
                        ]

                    else
                        []

                hitWithoutLoss : Bool
                hitWithoutLoss =
                    (beforeCount == afterCount)
                        && (health.after.current < health.before.current)
                        && (index == beforeCount - 1)

                impactStart : Float
                impactStart =
                    if hitWithoutLoss then
                        impactStartsAt

                    else
                        startsAt

                showingImpact : Bool
                showingImpact =
                    (lost || hitWithoutLoss)
                        && (elapsed >= impactStart)
                        && (elapsed < impactStart + CombatExplosion.durationMs)

                impactScale : Float
                impactScale =
                    if usesTrenches animation.infantryLoadout unit then
                        scale * 2.5

                    else
                        scale

                impact : List (Svg msg)
                impact =
                    if showingImpact then
                        [ Svg.g
                            [ SA.transform
                                ("translate("
                                    ++ String.fromFloat (placement.size / 2)
                                    ++ " "
                                    ++ String.fromFloat (scale * 8)
                                    ++ ") scale("
                                    ++ String.fromFloat impactScale
                                    ++ ")"
                                )
                            , A.attribute "data-casualty" (String.fromInt index)
                            ]
                            [ CombatExplosion.toSvg unit.spriteFacing (elapsed - impactStart) ]
                        ]

                    else
                        []

                exhaustionMarker : List (Svg msg)
                exhaustionMarker =
                    if lost && visible && (elapsed >= startsAt) then
                        let
                            markerSize : Float
                            markerSize =
                                min (placement.size * 0.7) (scale * UnitSprite.portraitFooting unit)

                            pulseOpacity : Float
                            pulseOpacity =
                                (1 - cos (2 * pi * (elapsed - startsAt) / exhaustionPulseDurationMs)) / 2
                        in
                        [ Svg.image
                            [ SA.x (String.fromFloat ((placement.size - markerSize) / 2))
                            , SA.y (String.fromFloat ((scale * UnitSprite.portraitFooting unit - markerSize) / 2))
                            , SA.width (String.fromFloat markerSize)
                            , SA.height (String.fromFloat markerSize)
                            , SA.xlinkHref "/assets/death-skull-illustrated-v1.png"
                            , SA.opacity (String.fromFloat pulseOpacity)
                            , SA.css [ S.reducedMotion [ S.opacity 1 ] ]
                            , A.attribute "data-exhaustion-marker" (String.fromInt index)
                            ]
                            []
                        ]

                    else
                        []

                content : List (Svg msg)
                content =
                    case layer of
                        Combatants ->
                            sprite

                        Impacts ->
                            impact

                        ExhaustionMarkers ->
                            exhaustionMarker
            in
            Svg.g
                [ SA.transform
                    ("translate("
                        ++ String.fromFloat x
                        ++ " "
                        ++ String.fromFloat placement.y
                        ++ ")"
                    )
                , Aria.hidden True
                ]
                content

        -- Keep casualty identities stable while painting foreground figures over rear ones.
        paintOrder : PlacedFigure -> Float
        paintOrder placed =
            if (unit.kind == Kind.Infantry) && not (usesTrenches animation.infantryLoadout unit) then
                placed.placement.y + placed.placement.size / UnitSprite.portraitWidth unit * UnitSprite.portraitFooting unit

            else
                toFloat placed.index

        visiblePlacements : List PlacedFigure
        visiblePlacements =
            formationPlacements animation.infantryLoadout calibration unit
                |> List.take beforeCount
                |> List.indexedMap PlacedFigure
                |> List.sortBy paintOrder

        renderFigure : Layer -> PlacedFigure -> Svg msg
        renderFigure layer placed =
            figure layer placed.index placed.placement

        showingTrenches : Bool
        showingTrenches =
            usesTrenches animation.infantryLoadout unit && (health.before.current > 0)

        renderLayer : Layer -> List (Svg msg)
        renderLayer layer =
            case layer of
                Combatants ->
                    if showingTrenches then
                        case effect of
                            ShellImpact ->
                                trenchToSvg animation.trenchOccupancy calibration elapsed health unit

                            SupplyExhaustion ->
                                trenchToSvg animation.trenchOccupancy calibration 0 health unit

                    else
                        List.map (renderFigure layer) visiblePlacements

                Impacts ->
                    let
                        impacts : List (Svg msg)
                        impacts =
                            List.map (renderFigure layer) visiblePlacements

                        markers : List (Svg msg)
                        markers =
                            if showingTrenches then
                                trenchMarkersToSvg calibration elapsed health unit

                            else
                                []
                    in
                    impacts ++ markers

                ExhaustionMarkers ->
                    List.map (renderFigure layer) visiblePlacements
    in
    List.concatMap renderLayer layers
