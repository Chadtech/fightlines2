module View.CombatFormation exposing
    ( figureCount
    , impactStarts
    , impactsToSvg
    , lossStartsAt
    , toSvg
    )

import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as Kind exposing (UnitKind)
import CombatHealth exposing (CombatHealth)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.Aria as Aria
import View.CombatExplosion as CombatExplosion
import View.UnitSprite as UnitSprite


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
    1200


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


type Layer
    = Combatants
    | Impacts


placements : UnitKind -> List Placement
placements kind =
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

        _ ->
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


toSvg : Float -> CombatHealth -> Unit -> List (Svg msg)
toSvg =
    layersToSvg [ Combatants, Impacts ]


impactsToSvg : Float -> CombatHealth -> Unit -> List (Svg msg)
impactsToSvg =
    layersToSvg [ Impacts ]


layersToSvg : List Layer -> Float -> CombatHealth -> Unit -> List (Svg msg)
layersToSvg layers elapsed health unit =
    let
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
                    not lost || elapsed < startsAt + CombatExplosion.spriteDisappearsAt

                spriteOpacity : Float
                spriteOpacity =
                    if lost then
                        CombatExplosion.spriteOpacity (elapsed - startsAt)

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
                            [ UnitSprite.portraitToSvg unit ]
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
            List.take beforeCount (placements unit.kind)

        renderLayer : Layer -> List (Svg msg)
        renderLayer layer =
            List.indexedMap (figure layer) visiblePlacements
    in
    List.concatMap renderLayer layers
