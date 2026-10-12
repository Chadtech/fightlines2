module View.CombatFormation exposing (figureCount, impactStarts, lossStartsAt, toSvg)

import Api.Enum.SpriteFacing as SpriteFacing
import CombatHealth exposing (CombatHealth)
import Html.Styled.Attributes as A
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import Unit exposing (Unit)
import View.Aria as Aria
import View.CombatExplosion as CombatExplosion
import View.UnitSprite as UnitSprite


{-| Theater figures summarize health; they do not change authoritative damage.
Each figure represents four HP; a partially intact quarter stays visible.
-}
figureCount : Int -> Int
figureCount hitPoints =
    clamp 0 4 ((max 0 hitPoints + 3) // 4)


lossStartsAt : { surviving : Int, index : Int } -> Float
lossStartsAt config =
    impactStartsAt + toFloat (config.index - config.surviving) * 120


{-| Let the 200ms card expansion finish, then hold the scene for one second.
-}
impactStartsAt : Float
impactStartsAt =
    1200


impactStarts : CombatHealth -> List Float
impactStarts health =
    let
        beforeCount : Int
        beforeCount =
            figureCount health.before.current

        afterCount : Int
        afterCount =
            figureCount health.after.current

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


placements : List Placement
placements =
    [ { x = 6, y = 25, size = 25 }
    , { x = 40, y = 27, size = 25 }
    , { x = 19, y = 32, size = 28 }
    , { x = 57, y = 34, size = 28 }
    ]


toSvg : Float -> CombatHealth -> Unit -> List (Svg msg)
toSvg elapsed health unit =
    let
        beforeCount : Int
        beforeCount =
            figureCount health.before.current

        afterCount : Int
        afterCount =
            figureCount health.after.current

        figure : Layer -> Int -> Placement -> Svg msg
        figure layer index placement =
            let
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
                                ("scale(" ++ String.fromFloat (placement.size / 16) ++ ")")
                            , SA.opacity (String.fromFloat spriteOpacity)
                            , SA.class "fightlines-combat-figure"
                            , A.attribute "data-figure-index" (String.fromInt index)
                            ]
                            [ UnitSprite.toSvg 0 unit ]
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
                                    ++ String.fromFloat (placement.size / 2)
                                    ++ ") scale("
                                    ++ String.fromFloat (placement.size / 16)
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
            List.take beforeCount placements

        combatants : List (Svg msg)
        combatants =
            List.indexedMap (figure Combatants) visiblePlacements

        impacts : List (Svg msg)
        impacts =
            List.indexedMap (figure Impacts) visiblePlacements
    in
    combatants ++ impacts
