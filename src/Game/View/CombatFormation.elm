module Game.View.CombatFormation exposing
    ( Animation
    , exhaustionEndsAt
    , exhaustionToSvg
    , figureCount
    , impactStarts
    , impactsToSvg
    , lossStartsAt
    , toSvg
    , toSvgWithCalibration
    )

import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import Game.BackdropCalibration exposing (Calibration)
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatExplosion as CombatExplosion
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
    }


{-| Theater figures summarize health; they do not change authoritative damage.
Infantry figures represent two HP; other figures represent four HP.
A partially intact figure stays visible.
-}
figureCount : UnitKind -> Int -> Int
figureCount kind hitPoints =
    let
        hitPointsPerFigure : Int
        hitPointsPerFigure =
            case kind of
                Kind.Infantry ->
                    2

                _ ->
                    4
    in
    clamp 0 (16 // hitPointsPerFigure) ((max 0 hitPoints + hitPointsPerFigure - 1) // hitPointsPerFigure)


lossStartsAt : { surviving : Int, index : Int } -> Float
lossStartsAt config =
    impactStartsAt + toFloat (config.index - config.surviving) * 120


{-| Let the 200ms card expansion finish, then hold the scene for one second.
-}
impactStartsAt : Float
impactStartsAt =
    CombatAttack.anticipationMs


impactStarts : UnitKind -> CombatHealth -> List Float
impactStarts kind health =
    let
        beforeCount : Int
        beforeCount =
            figureCount kind health.before.current

        afterCount : Int
        afterCount =
            figureCount kind health.after.current

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


type CasualtyEffect
    = ShellImpact
    | SupplyExhaustion


type Layer
    = Combatants
    | Impacts


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
            [ { x = 7
              , y = 29
              , size = 17
              }
            , { x = 31
              , y = 30
              , size = 17
              }
            , { x = 56
              , y = 28
              , size = 17
              }
            , { x = 19
              , y = 36
              , size = 18
              }
            , { x = 45
              , y = 35
              , size = 18
              }
            , { x = 69
              , y = 37
              , size = 18
              }
            , { x = 8
              , y = 43
              , size = 20
              }
            , { x = 39
              , y = 44
              , size = 20
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


toSvg : Animation -> CombatHealth -> Appearance -> List (Svg msg)
toSvg =
    layersToSvg ShellImpact Nothing [ Combatants, Impacts ]


impactsToSvg : Animation -> CombatHealth -> Appearance -> List (Svg msg)
impactsToSvg =
    layersToSvg ShellImpact Nothing [ Impacts ]


toSvgWithCalibration : Maybe Calibration -> Animation -> CombatHealth -> Appearance -> List (Svg msg)
toSvgWithCalibration calibration =
    layersToSvg ShellImpact calibration [ Combatants, Impacts ]


exhaustionFadeDurationMs : Float
exhaustionFadeDurationMs =
    700


exhaustionEndsAt : UnitKind -> Int -> Float
exhaustionEndsAt kind health =
    impactStartsAt + toFloat (max 0 (figureCount kind health - 1)) * 120 + exhaustionFadeDurationMs


{-| Exhaustion removes the formation without inventing incoming fire.
-}
exhaustionToSvg : Maybe Calibration -> Float -> CombatHealth -> Appearance -> List (Svg msg)
exhaustionToSvg calibration elapsed =
    layersToSvg SupplyExhaustion
        calibration
        [ Combatants ]
        { elapsed = elapsed, impactDelay = 0, attack = CombatAttack.NotAttacking }


formationPlacements : Maybe Calibration -> Appearance -> List Placement
formationPlacements calibration unit =
    case calibration of
        Nothing ->
            placements unit.kind

        Just settings ->
            calibratedPlacements settings unit


{-| Depth runs from zero at the rear to one at the front. Formation patterns
remain unit-specific; the selected backdrop/unit calibration supplies ground and scale values.
-}
calibratedPlacements : Calibration -> Appearance -> List Placement
calibratedPlacements settings unit =
    let
        pattern :
            List
                { center : Float
                , depth : Float
                , proportion : Float
                }
        pattern =
            case unit.kind of
                Kind.Infantry ->
                    [ { center = 16
                      , depth = 0
                      , proportion = 0.7
                      }
                    , { center = 40
                      , depth = 0
                      , proportion = 0.7
                      }
                    , { center = 67
                      , depth = 0
                      , proportion = 0.7
                      }
                    , { center = 28
                      , depth = 0.5
                      , proportion = 0.7
                      }
                    , { center = 54
                      , depth = 0.5
                      , proportion = 0.7
                      }
                    , { center = 78
                      , depth = 0.5
                      , proportion = 0.7
                      }
                    , { center = 18
                      , depth = 1
                      , proportion = 0.7
                      }
                    , { center = 49
                      , depth = 1
                      , proportion = 0.7
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
                    64 * (settings.frontFooting - settings.rowSpacing * (1 - position.depth)) / 100

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
            figureCount unit.kind health.before.current

        afterCount : Int
        afterCount =
            figureCount unit.kind health.after.current

        figure : Layer -> Int -> Placement -> Svg msg
        figure layer index placement =
            let
                scale : Float
                scale =
                    placement.size / UnitSprite.portraitWidth unit

                x : Float
                x =
                    if unit.spriteFacing == SpriteFacing.Left then
                        96 - placement.x - placement.size

                    else
                        placement.x

                lost : Bool
                lost =
                    index >= afterCount

                startsAt : Float
                startsAt =
                    lossStartsAt { surviving = afterCount, index = index }

                visible : Bool
                visible =
                    not lost || elapsed < startsAt + disappearanceDelay

                disappearanceDelay : Float
                disappearanceDelay =
                    case effect of
                        ShellImpact ->
                            CombatExplosion.spriteDisappearsAt

                        SupplyExhaustion ->
                            exhaustionFadeDurationMs

                collapse : Float
                collapse =
                    if lost && (effect == SupplyExhaustion) then
                        clamp 0 1 ((elapsed - startsAt) / exhaustionFadeDurationMs)

                    else
                        0

                collapseTransform : String
                collapseTransform =
                    "translate(0 " ++ String.fromFloat (UnitSprite.portraitFooting unit) ++ ") rotate(" ++ String.fromFloat (collapse * 16) ++ ") scale(1 " ++ String.fromFloat (1 - collapse * 0.35) ++ ") translate(0 " ++ String.fromFloat (0 - UnitSprite.portraitFooting unit) ++ ")"

                spriteOpacity : Float
                spriteOpacity =
                    if lost then
                        case effect of
                            ShellImpact ->
                                CombatExplosion.spriteOpacity (elapsed - startsAt)

                            SupplyExhaustion ->
                                1 - collapse

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
                            [ Svg.g
                                [ SA.transform collapseTransform
                                , SA.css [ S.reducedMotion [ S.transform "none" ] ]
                                ]
                                [ CombatAttack.toSvg { elapsed = animation.elapsed, figureIndex = index } animation.attack unit ]
                            ]
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
                                    ++ String.fromFloat scale
                                    ++ ")"
                                )
                            , A.attribute "data-casualty" (String.fromInt index)
                            ]
                            [ CombatExplosion.toSvg unit.spriteFacing (elapsed - impactStart) ]
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

        visiblePlacements : List Placement
        visiblePlacements =
            List.take beforeCount (formationPlacements calibration unit)

        renderLayer : Layer -> List (Svg msg)
        renderLayer layer =
            List.indexedMap (figure layer) visiblePlacements
    in
    List.concatMap renderLayer layers
