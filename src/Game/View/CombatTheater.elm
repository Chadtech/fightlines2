module Game.View.CombatTheater exposing
    ( Msg(..)
    , ambience
    , attackDelay
    , attackerOnLeft
    , backdropPath
    , firingInfantry
    , firingTimes
    , impactTimes
    , preview
    , readyToAutomaticallyClose
    , styles
    , toHtml
    )

import Api.Enum.BuildingKind as BuildingKind
import Api.Enum.CombatKind as CombatKind
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.MapTheme as MapTheme exposing (MapTheme)
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.SpriteFacing as SpriteFacing exposing (SpriteFacing)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Audio
import Css
import Game.BackdropCalibration as BackdropCalibration
import Game.CombatHealth as CombatHealth exposing (CombatHealth)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.IndirectImpact exposing (Attacker, BuildingImpact)
import Game.Map as Map exposing (Map)
import Game.Terrain as Terrain exposing (Terrain)
import Game.TurnPlayback as TurnPlayback
    exposing
        ( Encounter(..)
        , ImpactEncounter
        , MapView(..)
        , Panel
        )
import Game.Unit as Unit exposing (Unit)
import Game.Unit.HitPoints exposing (HitPoints)
import Game.UnitKind as UnitKindLabel
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatBazooka as CombatBazooka
import Game.View.CombatExplosion as CombatExplosion
import Game.View.CombatFormation as CombatFormation
import Game.View.CombatInfantry as CombatInfantry
import Game.View.CombatReadiness as CombatReadiness
import Game.View.UnitSprite as UnitSprite exposing (Appearance)
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Html.Styled.Lazy as Lazy
import Json.Decode as Decode
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import View.Aria as Aria
import View.Button as Button
import View.Card as Card
import View.CardHeader as CardHeader
import View.Checkbox as Checkbox


type Msg
    = ContinueClicked
    | SeeMapPressed
    | SeeMapReleased
    | AutomaticallyCloseChanged Bool


type alias Scenery =
    { map : Map
    , calibrations : List BackdropCalibration.Entry
    , depots : List Depot
    }


type alias DepotDamage =
    { depot : Depot
    , elapsed : Float
    }


type alias AttackTiming =
    { impactsReadyAt : Float
    , endsAt : Float
    }


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-combat-pop {
                0% { transform: scale(.65); opacity: 0; }
                70% { transform: scale(1.04); opacity: 1; }
                100% { transform: scale(1); opacity: 1; }
            }
            .fightlines-combat-focus *:not(.fightlines-combat-shine),
            .fightlines-combat-focus *::before,
            .fightlines-combat-focus *::after { animation-play-state: paused !important; }
            @media (prefers-reduced-motion: reduce) {
                .fightlines-combat-figure { opacity: 1 !important; }
                .fightlines-combat-rumble { transform: none !important; }
            }
        """
        ]


{-| Preserve horizontal map order; for vertical encounters, north appears left.
-}
attackerOnLeft : Panel -> Bool
attackerOnLeft panel =
    case panel.encounter of
        Exchange exchange ->
            case ( Unit.mapPosition exchange.attacker, Unit.mapPosition exchange.target ) of
                ( Just attacker, Just target ) ->
                    (attacker.x < target.x)
                        || ((attacker.x == target.x) && (attacker.y <= target.y))

                _ ->
                    True

        Impact impact ->
            List.head impact.attackers
                |> Maybe.map (impactAttackerOnLeft impact.destination)
                |> Maybe.withDefault True

        Sabotage _ ->
            True

        Exhaustion _ ->
            True


impactAttackerOnLeft : Coordinate -> Attacker -> Bool
impactAttackerOnLeft destination attacker =
    case Unit.mapPosition attacker.unit of
        Just origin ->
            Coordinate.key origin <= Coordinate.key destination

        Nothing ->
            True


{-| Let the final impact and its camera shake settle, then pause for half a second.
Keeping the map button held always keeps the encounter open.
-}
readyToAutomaticallyClose : Panel -> Bool
readyToAutomaticallyClose panel =
    let
        animationEndsAt : Float
        animationEndsAt =
            case panel.encounter of
                Sabotage _ ->
                    sabotageBlastAt + 700

                Exhaustion _ ->
                    CombatFormation.exhaustionEndsAt

                _ ->
                    ordinaryAnimationEndsAt panel
    in
    (panel.mapView == CardVisible) && (panel.elapsed >= animationEndsAt + automaticCloseDelayMs)


ordinaryAnimationEndsAt : Panel -> Float
ordinaryAnimationEndsAt panel =
    case depotSceneStartsAt panel of
        Just startsAt ->
            startsAt + depotImpactStartsAt + impactContactDelayMs + rumbleDurationMs

        Nothing ->
            participantsEndAt panel


{-| Hit clocks are shifted together so shots, casualties, and rumble agree.
Small arms keep firing through impacts; other attacks finish before impacts.
-}
attackDelay : Panel -> Float
attackDelay panel =
    let
        readyAt : Float
        readyAt =
            attackTimings panel
                |> List.map .impactsReadyAt
                |> List.maximum
                |> Maybe.withDefault 0
    in
    if readyAt > 0 then
        readyAt - CombatAttack.anticipationMs + 100

    else
        0


attackTimings : Panel -> List AttackTiming
attackTimings panel =
    let
        timingFor : Unit -> Int -> AttackTiming
        timingFor unit health =
            let
                loadout : CombatInfantry.Loadout
                loadout =
                    infantryLoadout panel unit

                figures : Int
                figures =
                    CombatFormation.figureCount loadout unit.kind health

                exposedInfantry : Bool
                exposedInfantry =
                    (unit.kind == UnitKind.Infantry) && (unit.entrenchment == Entrenchment.Exposed)

                attack : CombatAttack.Attack
                attack =
                    attackFor panel unit

                endsAt : Float
                endsAt =
                    case loadout of
                        CombatInfantry.Bazookas ->
                            CombatBazooka.endsAt attack figures

                        CombatInfantry.SmallArms ->
                            if exposedInfantry then
                                CombatInfantry.endsAt attack figures

                            else
                                CombatAttack.endsAt attack unit.kind figures

                impactsReadyAt : Float
                impactsReadyAt =
                    if exposedInfantry && (loadout == CombatInfantry.SmallArms) then
                        CombatInfantry.impactsStartAt attack figures

                    else
                        endsAt
            in
            { impactsReadyAt = impactsReadyAt, endsAt = endsAt }
    in
    case panel.encounter of
        Exchange exchange ->
            [ timingFor exchange.attacker exchange.attackerHealth.before.current
            , timingFor exchange.target exchange.targetHealth.before.current
            ]

        Impact impact ->
            List.map
                (\attacker -> timingFor attacker.unit attacker.health.current)
                impact.attackers

        Sabotage _ ->
            []

        Exhaustion _ ->
            []


attackFor : Panel -> Unit -> CombatAttack.Attack
attackFor panel unit =
    case panel.encounter of
        Exchange exchange ->
            if unit.id == exchange.attacker.id then
                CombatAttack.Attacking { startsAt = CombatAttack.anticipationMs }

            else if (unit.id == exchange.target.id) && exchange.targetFired then
                CombatAttack.Attacking { startsAt = CombatAttack.anticipationMs + 45 }

            else
                CombatAttack.NotAttacking

        Impact impact ->
            if List.any (\attacker -> attacker.unit.id == unit.id) impact.attackers then
                CombatAttack.Attacking { startsAt = CombatAttack.anticipationMs }

            else
                CombatAttack.NotAttacking

        Sabotage _ ->
            CombatAttack.NotAttacking

        Exhaustion _ ->
            CombatAttack.NotAttacking


infantryLoadout : Panel -> Unit -> CombatInfantry.Loadout
infantryLoadout panel unit =
    let
        targetKind : Maybe UnitKind
        targetKind =
            case panel.encounter of
                Exchange exchange ->
                    if unit.id == exchange.attacker.id then
                        Just exchange.target.kind

                    else if unit.id == exchange.target.id then
                        Just exchange.attacker.kind

                    else
                        Nothing

                _ ->
                    Nothing
    in
    CombatInfantry.loadoutFor
        { kind = unit.kind
        , attack = attackFor panel unit
        , targetKind = targetKind
        }


{-| Sound cues use the same formation clocks and before-health as the flash.
Only recorded firing participants of the requested kind contribute timestamps.
-}
firingTimes : UnitKind -> Panel -> List Float
firingTimes kind panel =
    let
        starts : Unit -> Int -> List Float
        starts unit health =
            if unit.kind == kind then
                CombatAttack.firingTimes (attackFor panel unit) unit.kind (CombatFormation.figureCount (infantryLoadout panel unit) unit.kind health)

            else
                []
    in
    case panel.encounter of
        Exchange exchange ->
            starts exchange.attacker exchange.attackerHealth.before.current
                ++ starts exchange.target exchange.targetHealth.before.current
                |> List.sort

        Impact impact ->
            impact.attackers
                |> List.concatMap (\attacker -> starts attacker.unit attacker.health.current)
                |> List.sort

        Sabotage _ ->
            []

        Exhaustion _ ->
            []


{-| Use the small-arms animation's exact window and recorded firing participants.
Hidden cards and formations whose last figure has disappeared stay silent.
-}
firingInfantry : Panel -> List Audio.FiringInfantry
firingInfantry panel =
    if panel.mapView /= CardVisible then
        []

    else
        let
            firing : Unit -> CombatHealth -> Maybe Audio.FiringInfantry
            firing unit health =
                let
                    figures : Int
                    figures =
                        CombatFormation.figureCount
                            CombatInfantry.SmallArms
                            unit.kind
                            health.before.current

                    attack : CombatAttack.Attack
                    attack =
                        attackFor panel unit

                    lastFigureDisappearsAt : Float
                    lastFigureDisappearsAt =
                        if health.after.current <= 0 then
                            CombatFormation.lossStartsAt { surviving = 0, index = figures - 1 }
                                + attackDelay panel
                                + CombatExplosion.spriteDisappearsAt

                        else
                            CombatInfantry.endsAt attack figures

                    endsAt : Float
                    endsAt =
                        min (CombatInfantry.endsAt attack figures) lastFigureDisappearsAt
                in
                case attack of
                    CombatAttack.Attacking timing ->
                        let
                            usesSmallArmsAnimation : Bool
                            usesSmallArmsAnimation =
                                (unit.kind == UnitKind.Infantry)
                                    && (unit.entrenchment == Entrenchment.Exposed)
                                    && (infantryLoadout panel unit == CombatInfantry.SmallArms)
                        in
                        if
                            usesSmallArmsAnimation
                                && (figures > 0)
                                && (panel.elapsed >= timing.startsAt)
                                && (panel.elapsed < endsAt)
                        then
                            Just
                                { unitId = unit.id
                                , elapsedMs = panel.elapsed - timing.startsAt
                                , remainingMs = endsAt - panel.elapsed
                                }

                        else
                            Nothing

                    CombatAttack.NotAttacking ->
                        Nothing
        in
        case panel.encounter of
            Exchange exchange ->
                List.filterMap identity
                    [ firing exchange.attacker exchange.attackerHealth
                    , firing exchange.target exchange.targetHealth
                    ]

            _ ->
                []


{-| Include both stages regardless of the current elapsed time so a delayed
tick cannot skip participant hits when it crosses into the building scene.
Sounds begin at contact, after the projectile's short approach.
-}
impactTimes : Panel -> List Float
impactTimes panel =
    let
        buildingStarts : List Float
        buildingStarts =
            depotSceneStartsAt panel
                |> Maybe.map (\startsAt -> [ startsAt + depotImpactStartsAt ])
                |> Maybe.withDefault []
    in
    (participantImpactStarts panel ++ buildingStarts)
        |> List.map ((+) impactContactDelayMs)
        |> List.sort


{-| Use exactly the displayed scene positions, including the later building
cut. Concealed firing origins never contribute an environment or stereo side.
-}
ambience : Map -> Panel -> List Audio.AmbientScene
ambience map panel =
    let
        participantPositions : List (Maybe Coordinate)
        participantPositions =
            case panel.encounter of
                Exchange exchange ->
                    if attackerOnLeft panel then
                        [ Unit.mapPosition exchange.attacker
                        , Unit.mapPosition exchange.target
                        ]

                    else
                        [ Unit.mapPosition exchange.target
                        , Unit.mapPosition exchange.attacker
                        ]

                Impact impact ->
                    impact.destination
                        :: List.map
                            (\attacker ->
                                Unit.mapPosition attacker.unit
                                    |> Maybe.withDefault impact.destination
                            )
                            impact.attackers
                        |> List.sortBy Coordinate.key
                        |> List.map Just

                Sabotage building ->
                    [ Just building.position ]

                Exhaustion unit ->
                    [ Unit.mapPosition unit ]

        positions : List (Maybe Coordinate)
        positions =
            case depotDamageAt panel of
                Just damage ->
                    [ Just damage.depot.position ]

                Nothing ->
                    participantPositions

        sceneCount : Int
        sceneCount =
            List.length positions

        ambientScene : Int -> Maybe Coordinate -> Audio.AmbientScene
        ambientScene index position =
            let
                terrain : Terrain
                terrain =
                    position |> Maybe.map (Map.terrainAt map) |> Maybe.withDefault map.baseTile

                pan : Float
                pan =
                    if sceneCount > 1 then
                        -0.35 + 0.7 * toFloat index / toFloat (sceneCount - 1)

                    else
                        0
            in
            { ambience = environment map.theme terrain, pan = pan }
    in
    List.indexedMap ambientScene positions


environment : MapTheme -> Terrain -> Audio.Ambience
environment theme terrain =
    case ( theme, terrain ) of
        ( _, Terrain.Water ) ->
            Audio.Beach

        ( _, Terrain.Beach ) ->
            Audio.Beach

        ( MapTheme.Snow, _ ) ->
            Audio.Snow

        ( MapTheme.Desert, _ ) ->
            Audio.Desert

        ( MapTheme.GreenForest, Terrain.Forest ) ->
            Audio.Forest

        ( MapTheme.GreenForest, _ ) ->
            Audio.Plains


participantImpactStarts : Panel -> List Float
participantImpactStarts panel =
    List.map ((+) (attackDelay panel)) (participantBaseImpactStarts panel)


participantBaseImpactStarts : Panel -> List Float
participantBaseImpactStarts panel =
    case panel.encounter of
        Exchange exchange ->
            CombatFormation.impactStarts
                (infantryLoadout panel exchange.attacker)
                exchange.attacker.kind
                exchange.attackerHealth
                ++ CombatFormation.impactStarts
                    (infantryLoadout panel exchange.target)
                    exchange.target.kind
                    exchange.targetHealth

        Impact { target } ->
            case target of
                Just observed ->
                    CombatFormation.impactStarts (infantryLoadout panel observed.unit) observed.unit.kind observed.health

                Nothing ->
                    List.map ((+) CombatAttack.anticipationMs) [ 0, 130, 260, 390 ]

        Sabotage _ ->
            [ sabotageBlastAt ]

        Exhaustion _ ->
            []


participantsEndAt : Panel -> Float
participantsEndAt panel =
    let
        impactsEndAt : Float
        impactsEndAt =
            participantImpactStarts panel
                |> List.maximum
                |> Maybe.withDefault (CombatAttack.anticipationMs + attackDelay panel)
                |> (+) (impactContactDelayMs + rumbleDurationMs)

        attacksEndAt : Float
        attacksEndAt =
            attackTimings panel
                |> List.map .endsAt
                |> List.maximum
                |> Maybe.withDefault 0
    in
    max impactsEndAt attacksEndAt


{-| Finish the participant hits before cutting to the building as a whole.
The depot scene uses the same panel clock, including during map peeks.
-}
depotSceneStartsAt : Panel -> Maybe Float
depotSceneStartsAt panel =
    case panel.encounter of
        Impact impact ->
            impact.depot |> Maybe.map (\_ -> participantsEndAt panel + 350)

        _ ->
            Nothing


depotDamageAt : Panel -> Maybe DepotDamage
depotDamageAt panel =
    case ( panel.encounter, depotSceneStartsAt panel ) of
        ( Impact impact, Just startsAt ) ->
            let
                elapsed : Float
                elapsed =
                    panel.elapsed - startsAt

                building : BuildingImpact -> DepotDamage
                building damage =
                    let
                        hp : Depot.Hp
                        hp =
                            if elapsed >= depotImpactStartsAt + CombatExplosion.spriteDisappearsAt then
                                damage.after

                            else
                                damage.before
                    in
                    { depot =
                        { kind = damage.kind
                        , position = impact.destination
                        , stock = Nothing
                        , hp = hp
                        }
                    , elapsed = elapsed
                    }
            in
            if elapsed >= 0 then
                Maybe.map building impact.depot

            else
                Nothing

        _ ->
            Nothing


impactStarts : Panel -> List Float
impactStarts panel =
    case ( depotSceneStartsAt panel, depotDamageAt panel ) of
        ( Just startsAt, Just _ ) ->
            [ startsAt + depotImpactStartsAt ]

        _ ->
            participantImpactStarts panel


depotImpactStartsAt : Float
depotImpactStartsAt =
    700


impactContactDelayMs : Float
impactContactDelayMs =
    20


rumbleDurationMs : Float
rumbleDurationMs =
    160


automaticCloseDelayMs : Float
automaticCloseDelayMs =
    500


toHtml :
    { calibrations : List BackdropCalibration.Entry
    , automaticallyClose : Bool
    , visibleTiles : List Coordinate
    }
    -> List Depot
    -> Map
    -> Panel
    -> Html Msg
toHtml config depots map panel =
    Lazy.lazy6 theaterView config.calibrations config.automaticallyClose config.visibleTiles depots map panel


theaterView : List BackdropCalibration.Entry -> Bool -> List Coordinate -> List Depot -> Map -> Panel -> Html Msg
theaterView calibrations automaticallyClose visibleTiles depots map panel =
    let
        scenery : Scenery
        scenery =
            { map = map
            , calibrations = calibrations
            , depots = depots
            }

        participantPortraits : List (Html Msg)
        participantPortraits =
            case panel.encounter of
                Exchange exchange ->
                    let
                        attacker : Unit
                        attacker =
                            exchange.attacker

                        target : Unit
                        target =
                            exchange.target

                        attackerView : SpriteFacing -> Html Msg
                        attackerView facing =
                            portrait
                                scenery
                                panel
                                exchange.attackerHealth
                                (attacker
                                    |> Unit.setSpriteFacing facing
                                )

                        targetView : SpriteFacing -> Html Msg
                        targetView facing =
                            portrait
                                scenery
                                panel
                                exchange.targetHealth
                                (target
                                    |> Unit.setSpriteFacing facing
                                )
                    in
                    if attackerOnLeft panel then
                        [ attackerView SpriteFacing.Right
                        , targetView SpriteFacing.Left
                        ]

                    else
                        [ targetView SpriteFacing.Right
                        , attackerView SpriteFacing.Left
                        ]

                Impact impact ->
                    impactPortraits visibleTiles scenery panel impact

                Sabotage sabotage ->
                    [ sabotageScene scenery panel sabotage ]

                Exhaustion unit ->
                    [ exhaustionScene scenery panel unit ]

        portraits : List (Html Msg)
        portraits =
            case depotDamageAt panel of
                Just damage ->
                    [ depotScene scenery panel damage ]

                Nothing ->
                    participantPortraits

        title : String
        title =
            case panel.encounter of
                Sabotage _ ->
                    "sabotage"

                Exhaustion _ ->
                    "out of supplies"

                Impact { target } ->
                    case target of
                        Just _ ->
                            "indirect fire"

                        Nothing ->
                            "indirect fire impact"

                Exchange exchange ->
                    case exchange.kind of
                        CombatKind.IndirectFire ->
                            "indirect fire"

                        CombatKind.Ambush ->
                            "ambush"

                        CombatKind.AttackMove ->
                            "attack move"

        explanation : Html Msg
        explanation =
            case panel.encounter of
                Impact impact ->
                    let
                        source : String
                        source =
                            case impact.attackers of
                                [] ->
                                    "an enemy field gun fired from an unknown location at this space."

                                [ _ ] ->
                                    "a field gun fired indirectly at this space."

                                _ ->
                                    "field guns fired indirectly at this space."

                        outcome : String
                        outcome =
                            case impact.target of
                                Just target ->
                                    if target.health.after.current == 0 then
                                        " a unit was destroyed at this space."

                                    else
                                        " a unit was hit at this space."

                                Nothing ->
                                    if impact.depot == Nothing then
                                        " no target or damage could be confirmed."

                                    else
                                        ""

                        depotOutcome : String
                        depotOutcome =
                            case depotDamageAt panel of
                                Just damage ->
                                    if Depot.isDestroyed damage.depot then
                                        " the depot was destroyed."

                                    else if damage.elapsed < depotImpactStartsAt then
                                        " the shell also struck the depot."

                                    else
                                        " the depot was damaged."

                                Nothing ->
                                    ""
                    in
                    H.p
                        []
                        [ H.text (source ++ outcome ++ depotOutcome) ]

                Exchange _ ->
                    H.text ""

                Sabotage sabotage ->
                    H.p
                        []
                        [ H.text ("infantry sabotaged the " ++ Depot.kindLabel sabotage.kind ++ ".") ]

                Exhaustion unit ->
                    H.p
                        []
                        [ H.text (UnitKindLabel.label unit.kind ++ " ran out of supplies.") ]

        sceneColumns : Css.Style
        sceneColumns =
            case portraits of
                [ _ ] ->
                    -- Match one column of the paired layout, including its S.g3 gap.
                    Css.property "grid-template-columns" "minmax(0, calc((100% - 0.75rem) / 2))"

                [ _, _ ] ->
                    S.gridCols2

                _ ->
                    Css.property "grid-template-columns" "repeat(3, minmax(0, 1fr))"

        card : Card.Card
        card =
            Card.simple
                |> Card.withHeader (CardHeader.simple title)

        cardOpacity : Float
        cardOpacity =
            case panel.mapView of
                CardVisible ->
                    1

                SeeingMap ->
                    0

        shadeOpacity : Float
        shadeOpacity =
            case panel.mapView of
                CardVisible ->
                    0.85

                SeeingMap ->
                    0
    in
    H.div
        [ A.attribute "data-combat-panels" ""
        , Aria.role Aria.Group
        , Aria.label title
        , A.css
            [ S.fixed
            , S.top0
            , S.bottom0
            , S.left0
            , S.right0
            , S.z4
            , S.col
            , S.itemsCenter
            , S.justifyCenter
            , S.p3
            ]
        ]
        [ H.div
            [ Aria.hidden True
            , A.css
                [ S.absolute
                , S.top0
                , S.bottom0
                , S.left0
                , S.right0
                , S.bgNightwood2
                , S.opacity shadeOpacity
                ]
            ]
            []
        , H.div
            [ A.css
                [ S.relative
                , S.wFull
                , S.textGray5
                , S.maxW256
                , S.opacity cardOpacity
                , S.maxHViewportInsetRem 1.5
                , S.overflowAuto
                ]
            ]
            [ H.div
                [ A.css
                    [ S.animation "fightlines-combat-pop 200ms ease-out both"
                    , S.reducedMotion
                        [ S.animationNone ]
                    ]
                ]
                [ Card.toHtml card
                    [ explanation
                    , H.div
                        [ A.css
                            [ S.grid
                            , S.g3
                            , S.justifyCenter
                            , sceneColumns
                            ]
                        ]
                        portraits
                    , H.div
                        [ A.css
                            [ S.row
                            , S.g3
                            , S.flexWrap
                            , S.itemsCenter
                            ]
                        ]
                        [ H.div
                            [ Ev.preventDefaultOn "keydown" (HtmlEvent.enter ( SeeMapReleased, True ))
                            , Ev.stopPropagationOn "keyup" (HtmlEvent.enter ( ContinueClicked, True ))
                            ]
                            [ Button.primary "continue" ContinueClicked |> Button.toHtml
                            ]
                        , H.div
                            [ Ev.onMouseDown SeeMapPressed
                            , Ev.onMouseUp SeeMapReleased
                            , Ev.onMouseLeave SeeMapReleased
                            , Ev.on "focusout" (Decode.succeed SeeMapReleased)
                            , Ev.custom "keydown" (seeMapKey SeeMapPressed)
                            , Ev.custom "keyup" (seeMapKey SeeMapReleased)
                            ]
                            [ Button.secondary "see map" SeeMapReleased |> Button.toHtml
                            ]
                        , Checkbox.new
                            { label = "automatically close"
                            , checked = automaticallyClose
                            , onCheck = AutomaticallyCloseChanged
                            }
                            |> Checkbox.toHtml
                                [ H.text "automatically close" ]
                        ]
                    ]
                ]
            ]
        ]


seeMapKey : Msg -> Decode.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
seeMapKey message =
    let
        handled : Msg -> { message : Msg, stopPropagation : Bool, preventDefault : Bool }
        handled event =
            { message = event
            , stopPropagation = True
            , preventDefault = True
            }
    in
    Decode.oneOf
        [ HtmlEvent.enter message
        , HtmlEvent.key " " message
        ]
        |> Decode.map handled


backdropAt : Scenery -> Coordinate -> String
backdropAt scenery position =
    let
        atPosition : Depot -> Bool
        atPosition depot =
            depot.position == position
    in
    case ListUtil.find atPosition scenery.depots of
        Just depot ->
            case ( scenery.map.theme, depot.kind ) of
                ( MapTheme.Snow, BuildingKind.Fortress ) ->
                    "/assets/combat-backdrops-anime-v1/snowy-fortress.png"

                ( _, BuildingKind.Fortress ) ->
                    "/assets/combat-backdrops-anime-v1/fortress.png"

                ( MapTheme.Snow, _ ) ->
                    "/assets/combat-backdrops-anime-v1/snowy-depot.png"

                _ ->
                    "/assets/combat-backdrops-anime-v1/depot.png"

        Nothing ->
            backdropPath scenery.map.theme (Map.terrainAt scenery.map position)


backdropPath : MapTheme -> Terrain -> String
backdropPath theme terrain =
    let
        name : String
        name =
            case ( theme, terrain ) of
                ( MapTheme.Snow, Terrain.Road _ ) ->
                    "snowy-road"

                ( _, Terrain.Road _ ) ->
                    "road"

                ( _, Terrain.Water ) ->
                    "water"

                ( _, Terrain.Beach ) ->
                    "beach-ocean"

                ( MapTheme.GreenForest, Terrain.Forest ) ->
                    "forest"

                ( MapTheme.Snow, Terrain.Forest ) ->
                    "snowy-forest"

                ( MapTheme.Desert, Terrain.Forest ) ->
                    "desert-forest"

                ( MapTheme.GreenForest, Terrain.Hills ) ->
                    "hills"

                ( MapTheme.Snow, Terrain.Hills ) ->
                    "snowy-hills"

                ( MapTheme.Desert, Terrain.Hills ) ->
                    "desert-hills"

                ( MapTheme.GreenForest, Terrain.Mountains ) ->
                    "mountains"

                ( MapTheme.Snow, Terrain.Mountains ) ->
                    "snowy-mountains"

                ( MapTheme.Desert, Terrain.Mountains ) ->
                    "desert-mountains"

                ( MapTheme.GreenForest, _ ) ->
                    "plains"

                ( MapTheme.Snow, _ ) ->
                    "tundra-plains"

                ( MapTheme.Desert, _ ) ->
                    "desert-plains"
    in
    "/assets/combat-backdrops-anime-v1/" ++ name ++ ".png"


{-| Both scenes share a camera kick at contact, then settle over 160ms.
Use the presentation clock instead of restarting a CSS animation on each render.
-}
rumbleTransform : Panel -> String
rumbleTransform panel =
    let
        contactStarts : List Float
        contactStarts =
            impactStarts panel
                |> List.map ((+) impactContactDelayMs)
                |> List.filter (\startsAt -> startsAt <= panel.elapsed)

        transform : Float -> String
        transform startsAt =
            let
                age : Float
                age =
                    panel.elapsed - startsAt

                strength : Float
                strength =
                    (1 - clamp 0 1 (age / rumbleDurationMs)) ^ 2

                x : Float
                x =
                    2.4 * strength * cos (age * 0.15)

                y : Float
                y =
                    1.5 * strength * sin (age * 0.21)

                rotation : Float
                rotation =
                    0.7 * strength * cos (age * 0.12)
            in
            "translate("
                ++ String.fromFloat x
                ++ "px, "
                ++ String.fromFloat y
                ++ "px) rotate("
                ++ String.fromFloat rotation
                ++ "deg)"
    in
    contactStarts
        |> List.maximum
        |> Maybe.map transform
        |> Maybe.withDefault "none"


impactAttacker : Scenery -> Panel -> Attacker -> SpriteFacing -> Html Msg
impactAttacker scenery panel attacker facing =
    let
        unit : Unit
        unit =
            attacker.unit
    in
    portrait scenery
        panel
        { before = attacker.health, after = attacker.health }
        (unit
            |> Unit.setSpriteFacing facing
        )


{-| Render each observed gun and a single landing in horizontal map order.
All formations share one panel clock and the combined target health transition.
-}
impactPortraits : List Coordinate -> Scenery -> Panel -> ImpactEncounter -> List (Html Msg)
impactPortraits visibleTiles scenery panel impact =
    let
        attackerView : Attacker -> { position : Coordinate, view : Html Msg }
        attackerView attacker =
            let
                facing : SpriteFacing
                facing =
                    if impactAttackerOnLeft impact.destination attacker then
                        SpriteFacing.Right

                    else
                        SpriteFacing.Left
            in
            { position = Unit.mapPosition attacker.unit |> Maybe.withDefault impact.destination
            , view = impactAttacker scenery panel attacker facing
            }

        targetFacing : SpriteFacing
        targetFacing =
            if attackerOnLeft panel then
                SpriteFacing.Left

            else
                SpriteFacing.Right

        target : { position : Coordinate, view : Html Msg }
        target =
            { position = impact.destination
            , view = impactTarget visibleTiles scenery panel impact targetFacing
            }

        positionKey : { position : Coordinate, view : Html Msg } -> Coordinate.Key
        positionKey positioned =
            Coordinate.key positioned.position
    in
    (target :: List.map attackerView impact.attackers)
        |> List.sortBy positionKey
        |> List.map .view


impactTarget : List Coordinate -> Scenery -> Panel -> ImpactEncounter -> SpriteFacing -> Html Msg
impactTarget visibleTiles scenery panel impact facing =
    case impact.target of
        Just target ->
            let
                unit : Unit
                unit =
                    target.unit
            in
            portrait scenery
                panel
                target.health
                (unit
                    |> Unit.setSpriteFacing facing
                )

        Nothing ->
            impactScene visibleTiles scenery panel impact.destination


impactScene : List Coordinate -> Scenery -> Panel -> Coordinate -> Html Msg
impactScene visibleTiles scenery panel position =
    let
        burst : Int -> Float -> Maybe (Svg.Svg Msg)
        burst index startsAt =
            let
                age : Float
                age =
                    panel.elapsed - startsAt
            in
            if (age >= 0) && (age <= CombatExplosion.durationMs) then
                Just
                    (Svg.g
                        [ SA.transform
                            ("translate("
                                ++ String.fromInt (24 + index * 16)
                                ++ " "
                                ++ String.fromInt (40 + modBy 2 index * 8)
                                ++ ")"
                            )
                        ]
                        [ CombatExplosion.toSvg SpriteFacing.Left age ]
                    )

            else
                Nothing

        explosions : List (Svg.Svg Msg)
        explosions =
            impactStarts panel
                |> List.indexedMap burst
                |> List.filterMap identity

        concealed : Bool
        concealed =
            not (List.member position visibleTiles)

        description : String
        description =
            if concealed then
                "indirect fire impact; target outside sight; no confirmed target"

            else
                "indirect fire impact; no confirmed target"

        content : List (Svg.Svg Msg)
        content =
            if concealed then
                unconfirmedFog :: explosions

            else
                explosions
    in
    scene
        (Just (backdropAt scenery position))
        (rumbleTransform panel)
        description
        content


depotScene : Scenery -> Panel -> DepotDamage -> Html Msg
depotScene scenery panel damage =
    let
        age : Float
        age =
            damage.elapsed - depotImpactStartsAt

        explosion : List (Svg.Svg Msg)
        explosion =
            if (age >= 0) && (age < CombatExplosion.durationMs) then
                [ Svg.g
                    [ SA.transform "translate(48 32) scale(2.2)" ]
                    [ CombatExplosion.toSvg SpriteFacing.Left age ]
                ]

            else
                []

        artwork : List (Svg.Svg Msg)
        artwork =
            [ Svg.image
                [ SA.x "24"
                , SA.y "8"
                , SA.width "48"
                , SA.height "48"
                , SA.xlinkHref (Depot.image damage.depot)
                ]
                []
            ]
                ++ explosion

        description : String
        description =
            Depot.label damage.depot ++ "; struck by indirect fire"
    in
    H.div
        [ A.attribute "data-depot-damage" ""
        , A.css
            [ S.row
            , S.justifyCenter
            ]
        ]
        [ H.div
            [ A.css
                [ S.wFull
                , S.maxW128
                ]
            ]
            [ scene
                (Just (backdropPath scenery.map.theme (Map.terrainAt scenery.map damage.depot.position)))
                (rumbleTransform panel)
                description
                artwork
            ]
        ]


sabotageBlastAt : Float
sabotageBlastAt =
    2400


exhaustionHealth : Unit -> CombatHealth
exhaustionHealth unit =
    let
        before : HitPoints
        before =
            unit.resources
                |> Maybe.map .hitPoints
                |> Maybe.withDefault { current = 16, maximum = 16 }
    in
    { before = before
    , after = { current = 0, maximum = before.maximum }
    }


exhaustionScene : Scenery -> Panel -> Unit -> Html Msg
exhaustionScene scenery panel unit =
    let
        path : String
        path =
            Unit.mapPosition unit
                |> Maybe.map (backdropAt scenery)
                |> Maybe.withDefault (backdropPath scenery.map.theme scenery.map.baseTile)

        appearance : Appearance
        appearance =
            unit
                |> Unit.setEntrenchment Entrenchment.Exposed
                |> UnitSprite.appearance
    in
    scene
        (Just path)
        "none"
        (Unit.label unit ++ "; ran out of supplies")
        (CombatFormation.exhaustionToSvg
            (BackdropCalibration.find { backdrop = path, unitKind = unit.kind } scenery.calibrations)
            panel.elapsed
            (exhaustionHealth unit)
            appearance
        )


sabotageScene : Scenery -> Panel -> Depot -> Html Msg
sabotageScene scenery panel building =
    let
        age : Float
        age =
            panel.elapsed - sabotageBlastAt

        shownBuilding : Depot
        shownBuilding =
            if age >= CombatExplosion.spriteDisappearsAt then
                { building | hp = { current = 0, maximum = building.hp.maximum } }

            else
                building

        charge : List (Svg.Svg Msg)
        charge =
            if (panel.elapsed >= 1350) && (age < 0) then
                [ Svg.image
                    [ SA.x "35"
                    , SA.y "42"
                    , SA.width "10"
                    , SA.height "10"
                    , SA.xlinkHref "/assets/commands-anime-v1/sabotage.png"
                    ]
                    []
                ]

            else
                []

        blast : List (Svg.Svg Msg)
        blast =
            if (age >= 0) && (age < CombatExplosion.durationMs) then
                [ Svg.g
                    [ SA.transform "translate(52 34) scale(2.2)" ]
                    [ CombatExplosion.toSvg SpriteFacing.Left age ]
                ]

            else
                []

        artwork : List (Svg.Svg Msg)
        artwork =
            [ Svg.image
                [ SA.x "29"
                , SA.y "9"
                , SA.width "48"
                , SA.height "48"
                , SA.xlinkHref (Depot.image shownBuilding)
                ]
                []
            ]
                ++ charge
                ++ blast
    in
    scene
        (Just (backdropPath scenery.map.theme (Map.terrainAt scenery.map building.position)))
        (rumbleTransform panel)
        (Depot.kindLabel building.kind ++ "; destroyed by infantry sabotage")
        artwork


unconfirmedFog : Svg.Svg Msg
unconfirmedFog =
    Svg.g
        [ Aria.hidden True ]
        [ Svg.rect
            [ SA.x "-4"
            , SA.y "-4"
            , SA.width "104"
            , SA.height "72"
            , SA.fill S.gray3Str
            , SA.opacity "0.8"
            ]
            []
        , Svg.text_
            [ SA.x "48"
            , SA.y "32"
            , SA.dy "0.35em"
            , SA.textAnchor "middle"
            , SA.fontSize "28"
            , SA.fill S.gray5Str
            , SA.stroke S.gray0Str
            , SA.strokeWidth "0.5"
            ]
            [ Svg.text "?" ]
        ]


portrait : Scenery -> Panel -> CombatHealth -> Unit -> Html Msg
portrait scenery panel health unit =
    let
        hasFlankBonus : Bool
        hasFlankBonus =
            case panel.encounter of
                Exchange exchange ->
                    if unit.id == exchange.attacker.id then
                        exchange.attackerFlankBonus

                    else if unit.id == exchange.target.id then
                        exchange.targetFlankBonus

                    else
                        False

                _ ->
                    False

        corner : Css.Style
        corner =
            case unit.spriteFacing of
                SpriteFacing.Right ->
                    S.left2

                SpriteFacing.Left ->
                    S.right2

        flankChip : Html Msg
        flankChip =
            if hasFlankBonus then
                H.span
                    [ A.attribute "data-flank-bonus" ""
                    , A.css
                        [ S.absolute
                        , S.top2
                        , corner
                        , S.px2
                        , S.py1
                        , S.bgYellow1
                        , S.textYellow6
                        , S.border
                        , S.borderGray4
                        , S.noWrap
                        , S.pointerEventsNone
                        ]
                    ]
                    [ H.text "flank bonus" ]

            else
                H.text ""
    in
    H.div
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.div
            [ A.css
                [ S.relative ]
            ]
            [ portraitScene scenery panel health unit
            , flankChip
            ]
        , CombatReadiness.toHtml unit.combatState
        ]


{-| Both confirmed exchanges and landings from concealed guns can have observed
targets. Only the bombarded participant shelters; firing guns keep their artwork.
-}
trenchOccupancy : Panel -> Unit -> CombatFormation.TrenchOccupancy
trenchOccupancy panel unit =
    let
        entrenchedInfantry : Bool
        entrenchedInfantry =
            (unit.kind == UnitKind.Infantry) && (unit.entrenchment == Entrenchment.Entrenched)

        underIndirectFire : Bool
        underIndirectFire =
            case panel.encounter of
                Exchange exchange ->
                    (exchange.kind == CombatKind.IndirectFire) && (unit.id == exchange.target.id)

                Impact impact ->
                    Maybe.map (.unit >> .id) impact.target == Just unit.id

                _ ->
                    False
    in
    if entrenchedInfantry && underIndirectFire then
        CombatFormation.ShelteringUnderground

    else
        CombatFormation.Occupied


portraitScene : Scenery -> Panel -> CombatHealth -> Unit -> Html Msg
portraitScene scenery panel health unit =
    let
        animation : CombatFormation.Animation
        animation =
            { elapsed = panel.elapsed
            , impactDelay = attackDelay panel
            , attack = attackFor panel unit
            , infantryLoadout = infantryLoadout panel unit
            , trenchOccupancy = trenchOccupancy panel unit
            }

        path : String
        path =
            Unit.mapPosition unit
                |> Maybe.map (backdropAt scenery)
                |> Maybe.withDefault (backdropPath scenery.map.theme scenery.map.baseTile)

        formationLabel : String
        formationLabel =
            case animation.infantryLoadout of
                CombatInfantry.Bazookas ->
                    ": two-person bazooka teams; "

                CombatInfantry.SmallArms ->
                    case animation.trenchOccupancy of
                        CombatFormation.ShelteringUnderground ->
                            ": sheltering underground in empty trenches; "

                        CombatFormation.Occupied ->
                            ": "

        description : String
        description =
            Unit.label unit
                ++ formationLabel
                ++ String.fromInt
                    (CombatFormation.figureCount
                        animation.infantryLoadout
                        unit.kind
                        health.before.current
                    )
                ++ " before combat, "
                ++ String.fromInt
                    (CombatFormation.figureCount
                        animation.infantryLoadout
                        unit.kind
                        health.after.current
                    )
                ++ " remaining"
    in
    scene
        (Just path)
        (rumbleTransform panel)
        description
        (CombatFormation.toSvgWithCalibration
            (BackdropCalibration.find
                { backdrop = path
                , unitKind = unit.kind
                }
                scenery.calibrations
            )
            animation
            health
            (UnitSprite.appearance unit)
        )


{-| Review artwork with the exact gameplay crop, sprites, and formation placements.
The preview holds an undamaged formation still, without inventing a combat event.
-}
preview : Maybe BackdropCalibration.Calibration -> String -> Int -> Appearance -> Html msg
preview calibration path hitPoints unit =
    let
        health : CombatHealth
        health =
            { before = { current = hitPoints, maximum = 16 }
            , after = { current = hitPoints, maximum = 16 }
            }
    in
    scene (Just path)
        "none"
        (UnitKindLabel.label unit.kind)
        (CombatFormation.toSvgWithCalibration calibration
            { elapsed = 0
            , impactDelay = 0
            , attack = CombatAttack.NotAttacking
            , infantryLoadout = CombatInfantry.SmallArms
            , trenchOccupancy = CombatFormation.Occupied
            }
            health
            unit
        )


scene : Maybe String -> String -> String -> List (Svg.Svg msg) -> Html msg
scene path transform description figures =
    let
        background : String -> Svg.Svg msg
        background imagePath =
            Svg.image
                [ SA.xlinkHref imagePath
                , SA.x "-4"
                , SA.y "-4"
                , SA.width "104"
                , SA.height "72"
                , SA.preserveAspectRatio "xMidYMid slice"
                , Aria.hidden True
                ]
                []

        content : List (Svg.Svg msg)
        content =
            case path of
                Nothing ->
                    figures

                Just imagePath ->
                    background imagePath :: figures
    in
    Svg.svg
        [ SA.viewBox "0 0 96 64"
        , Aria.role Aria.Image
        , Aria.label description
        , A.attribute "data-combat-backdrop" (Maybe.withDefault "" path)
        , SA.css
            [ S.block
            , S.wFull
            , S.minW0
            , S.bgNightwood3
            , S.indentStrong
            , S.aspectRatio { width = 3, height = 2 }
            ]
        ]
        [ Svg.g
            [ SA.class "fightlines-combat-rumble"
            , SA.css
                [ S.transform transform
                , Css.property "transform-origin" "48px 32px"
                ]
            ]
            content
        ]
