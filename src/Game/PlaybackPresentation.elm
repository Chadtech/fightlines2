module Game.PlaybackPresentation exposing
    ( Msg(..)
    , PlaybackCamera
    , Preference(..)
    , ambience
    , audioBetween
    , cameraPanDurationMs
    , combatOverlay
    , encodePreference
    , firingInfantry
    , frameCamera
    , limitZoom
    , loadPreference
    , loss
    , lossDialog
    , lossError
    , movingUnits
    , ownerName
    , readyToAutomaticallyClose
    , subscriptions
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Audio
import Browser.Events
import Error exposing (Error)
import Game.ArmyStyle exposing (ArmyStyle)
import Game.BackdropCalibration as BackdropCalibration
import Game.BattlefieldSnapshot as BattlefieldSnapshot exposing (Player)
import Game.Camera as Camera exposing (Camera)
import Game.Map as Map exposing (Map)
import Game.TurnPlayback as TurnPlayback
import Game.Unit as Unit exposing (Unit)
import Game.UnitId exposing (UnitId)
import Game.UnitLoss as UnitLoss
import Game.View.CombatTheater as CombatTheater
import Game.View.UnitDeath as UnitDeath
import Html.Styled as H exposing (Html)
import Json.Decode as Decode
import Json.Encode as Encode
import LocalStorage exposing (LocalStorage)
import Point exposing (Point)
import Preference
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias PlaybackCamera =
    { camera : Camera
    , target : Camera
    , pan : Maybe Pan
    }


type alias Pan =
    { from : Camera
    , elapsedMs : Float
    }


type Preference
    = SkipLossDialogs
    | AutomaticallyCloseCombat


type Msg
    = FrameElapsed Float
    | CombatEnterReleased
    | CombatSeeMapReleased



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


preferenceKey : Preference -> String
preferenceKey preference =
    case preference of
        SkipLossDialogs ->
            "skipUnitLossDialogs"

        AutomaticallyCloseCombat ->
            "automaticallyCloseCombatTheater"



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


limitZoom : Float -> PlaybackCamera -> PlaybackCamera
limitZoom maxZoom held =
    let
        limit : Camera -> Camera
        limit camera =
            Camera.zoomAt { x = 0, y = 0 } (min maxZoom camera.zoom) camera
    in
    { camera = limit held.camera
    , target = limit held.target
    , pan = Maybe.map (\pan -> { pan | from = limit pan.from }) held.pan
    }


cameraPanDurationMs : Float
cameraPanDurationMs =
    1200


{-| Play once when a collision hold starts or the theater clock crosses a cue.
An unchanged clock during a pause cannot replay a cue. A new encounter
or rewind starts a fresh interval instead of catching up old shots.
-}
audioBetween :
    { before : Maybe TurnPlayback.Playback
    , after : Maybe TurnPlayback.Playback
    }
    -> List Audio.Event
audioBetween transition =
    let
        holdingCollision : Maybe TurnPlayback.Playback -> Bool
        holdingCollision =
            Maybe.map TurnPlayback.collisionInProgress >> Maybe.withDefault False
    in
    if holdingCollision transition.after && not (holdingCollision transition.before) then
        [ Audio.movementCollision ]

    else
        combatAudioBetween transition


combatAudioBetween :
    { before : Maybe TurnPlayback.Playback
    , after : Maybe TurnPlayback.Playback
    }
    -> List Audio.Event
combatAudioBetween transition =
    case
        ( transition.before
            |> Maybe.andThen TurnPlayback.panels
        , transition.after
            |> Maybe.andThen TurnPlayback.panels
        )
    of
        ( Just before, Just after ) ->
            let
                advancingEncounter : Bool
                advancingEncounter =
                    (before.encounter == after.encounter) && (after.elapsed > before.elapsed)
            in
            if advancingEncounter then
                let
                    cues : UnitKind -> Audio.Event -> List { startsAt : Float, sound : Audio.Event }
                    cues kind sound =
                        CombatTheater.firingTimes kind after
                            |> List.map (\startsAt -> { startsAt = startsAt, sound = sound })

                    impacts : List { startsAt : Float, sound : Audio.Event }
                    impacts =
                        CombatTheater.impactTimes after
                            |> List.map
                                (\startsAt ->
                                    { startsAt = startsAt
                                    , sound = Audio.combatImpact
                                    }
                                )
                in
                (cues
                    UnitKind.Tank
                    Audio.tankFire
                    ++ cues UnitKind.Infantry Audio.tankFire
                    ++ cues UnitKind.FieldGun Audio.fieldGunFire
                    ++ impacts
                )
                    |> List.sortBy .startsAt
                    |> List.filter
                        (\cue ->
                            (before.elapsed < cue.startsAt) && (cue.startsAt <= after.elapsed)
                        )
                    |> List.map .sound

            else
                []

        _ ->
            []


{-| Keep quiet environment loops under the displayed theater, including map
peeks and held cards. Replay pause and leaving the theater stop the snapshot.
-}
ambience :
    { map : Map
    , playback : Maybe TurnPlayback.Playback
    , paused : Bool
    }
    -> List Audio.AmbientScene
ambience state =
    if state.paused then
        []

    else
        state.playback
            |> Maybe.andThen TurnPlayback.panels
            |> Maybe.map (CombatTheater.ambience state.map)
            |> Maybe.withDefault []


firingInfantry :
    { playback : Maybe TurnPlayback.Playback
    , paused : Bool
    }
    -> List Audio.FiringInfantry
firingInfantry state =
    if state.paused then
        []

    else
        state.playback
            |> Maybe.andThen TurnPlayback.panels
            |> Maybe.map CombatTheater.firingInfantry
            |> Maybe.withDefault []


{-| Follow the same projected movement edges as the sprites. Replay pauses and
casualty dialogs freeze movement and therefore silence it.
-}
movingUnits :
    { playback : Maybe TurnPlayback.Playback
    , paused : Bool
    , skipLossDialogs : Bool
    }
    -> List Audio.MovingUnit
movingUnits state =
    let
        lossHeld : Bool
        lossHeld =
            loss state.skipLossDialogs state.playback /= Nothing

        movementSound : Unit -> Maybe Audio.MovingUnit
        movementSound unit =
            case unit.kind of
                UnitKind.Infantry ->
                    Just { unitId = unit.id, sound = Audio.Infantry }

                UnitKind.Truck ->
                    Just { unitId = unit.id, sound = Audio.Truck }

                UnitKind.Tank ->
                    Just { unitId = unit.id, sound = Audio.Tank }

                UnitKind.FieldGun ->
                    Just { unitId = unit.id, sound = Audio.Infantry }

        moving : TurnPlayback.Playback -> List Audio.MovingUnit
        moving animation =
            if TurnPlayback.collisionInProgress animation then
                []

            else
                let
                    ids : List UnitId
                    ids =
                        TurnPlayback.movingPositions (Just animation) |> List.map .unitId
                in
                animation.current.units
                    |> List.filter (\unit -> List.member unit.id ids && not (Unit.isDying unit))
                    |> List.filterMap movementSound
    in
    if state.paused || lossHeld then
        []

    else
        state.playback |> Maybe.map moving |> Maybe.withDefault []


{-| Ease toward the visible route on the playback clock. Keep the subjects
of the actual frame in view even when a new sighting changes the target.
-}
frameCamera :
    { viewport : Camera.Viewport
    , map : Map
    , projection : Camera.Projection
    , saved : Camera
    , deltaMs : Float
    }
    -> TurnPlayback.Playback
    -> Maybe PlaybackCamera
    -> PlaybackCamera
frameCamera config animation held =
    let
        previous : Camera
        previous =
            held |> Maybe.map .camera |> Maybe.withDefault config.saved

        previousTarget : Camera
        previousTarget =
            held |> Maybe.map .target |> Maybe.withDefault config.saved

        subjects : List Point
        subjects =
            TurnPlayback.focusPositions animation

        keepSubjectsVisible : Camera -> Camera
        keepSubjectsVisible =
            Camera.keepVisible
                config.projection
                config.viewport
                config.map
                subjects

        target : Camera
        target =
            Camera.frame
                config.projection
                config.viewport
                config.map
                (TurnPlayback.cameraPositions animation)
                previousTarget

        pan : Maybe Pan
        pan =
            if target == previousTarget then
                held
                    |> Maybe.andThen .pan
                    |> Maybe.map
                        (\current ->
                            { current | elapsedMs = current.elapsedMs + config.deltaMs }
                        )

            else
                Just { from = keepSubjectsVisible previous, elapsedMs = 0 }

        activePan : Maybe Pan
        activePan =
            case pan of
                Just current ->
                    if current.elapsedMs < cameraPanDurationMs then
                        Just current

                    else
                        Nothing

                Nothing ->
                    Nothing

        camera : Camera
        camera =
            activePan
                |> Maybe.map (easeCamera target)
                |> Maybe.withDefault target
    in
    { camera = keepSubjectsVisible camera
    , target = target
    , pan = activePan
    }


easeCamera : Camera -> Pan -> Camera
easeCamera target pan =
    let
        elapsed : Float
        elapsed =
            pan.elapsedMs / cameraPanDurationMs

        progress : Float
        progress =
            elapsed * elapsed * (3 - 2 * elapsed)

        interpolate : Float -> Float -> Float
        interpolate from to =
            from + (to - from) * progress
    in
    { offset =
        { x = interpolate pan.from.offset.x target.offset.x
        , y = interpolate pan.from.offset.y target.offset.y
        }
    , zoom = interpolate pan.from.zoom target.zoom
    }


loadPreference : Preference -> LocalStorage -> ( Bool, Maybe Error )
loadPreference preference storage =
    Preference.load
        { key = preferenceKey preference
        , decoder = Decode.bool
        , defaultValue = False
        }
        storage


encodePreference : Preference -> Bool -> { key : String, value : Encode.Value }
encodePreference preference enabled =
    { key = preferenceKey preference
    , value = Encode.bool enabled
    }


loss : Bool -> Maybe TurnPlayback.Playback -> Maybe TurnPlayback.Loss
loss skipDialogs playback =
    if skipDialogs then
        Nothing

    else
        playback
            |> Maybe.andThen TurnPlayback.lossEvent
            |> Maybe.map .loss


ownerName : List Player -> Unit -> Maybe String
ownerName players unit =
    players
        |> ListUtil.find (\player -> player.playerNumber == unit.playerNumber)
        |> Maybe.map .name


lossError : List Player -> Maybe TurnPlayback.Loss -> Maybe Error
lossError players casualty =
    case Maybe.map (UnitLoss.resolve (ownerName players)) casualty of
        Just (Err (UnitLoss.OwnerNotFound missing)) ->
            Just (Error.UnitOwnerNotFound missing)

        _ ->
            Nothing


lossDialog :
    { skipDialogs : Bool
    , players : List Player
    , ownPlayer : PlayerNumber
    }
    -> Maybe TurnPlayback.Playback
    -> Maybe (Dialog UnitDeath.Msg)
lossDialog config playback =
    let
        notice : TurnPlayback.Loss -> Dialog UnitDeath.Msg
        notice casualty =
            UnitDeath.dialog
                { skipDialogs = config.skipDialogs
                , isOwn = casualty.unit.playerNumber == config.ownPlayer
                , details = UnitLoss.resolve (ownerName config.players) casualty
                , passengers =
                    playback
                        |> Maybe.andThen TurnPlayback.lossEvent
                        |> Maybe.map .passengers
                        |> Maybe.withDefault []
                }
                casualty
    in
    loss config.skipDialogs playback |> Maybe.map notice


combatOverlay :
    { calibrations : List BackdropCalibration.Entry
    , automaticallyClose : Bool
    , armyStyle : Maybe { style : ArmyStyle, player : PlayerNumber }
    , mobile : Bool
    , players : List Player
    }
    -> Map
    -> Maybe TurnPlayback.Playback
    -> Html CombatTheater.Msg
combatOverlay config map playback =
    let
        overlay : TurnPlayback.Playback -> Maybe (Html CombatTheater.Msg)
        overlay animation =
            TurnPlayback.panels animation
                |> Maybe.map
                    (CombatTheater.toHtml
                        { calibrations = config.calibrations
                        , automaticallyClose = config.automaticallyClose
                        , armyStyle = config.armyStyle
                        , mobile = config.mobile
                        , players = config.players
                        }
                        animation.current
                        map
                    )
    in
    playback
        |> Maybe.andThen overlay
        |> Maybe.withDefault (H.text "")


readyToAutomaticallyClose : Bool -> TurnPlayback.Playback -> Bool
readyToAutomaticallyClose automaticallyClose animation =
    automaticallyClose
        && (TurnPlayback.panels animation
                |> Maybe.map CombatTheater.readyToAutomaticallyClose
                |> Maybe.withDefault False
           )



----------------------------------------------------------------
-- SUBSCRIPTIONS --
----------------------------------------------------------------


subscriptions : Bool -> Maybe TurnPlayback.Playback -> Sub Msg
subscriptions cameraReady playback =
    let
        panel : Maybe TurnPlayback.Panel
        panel =
            playback |> Maybe.andThen TurnPlayback.panels

        animationFrames : Sub Msg
        animationFrames =
            if cameraReady && (playback /= Nothing) then
                Browser.Events.onAnimationFrameDelta FrameElapsed

            else
                Sub.none

        combatKeys : Sub Msg
        combatKeys =
            if panel /= Nothing then
                Browser.Events.onKeyUp
                    (HtmlEvent.enter CombatEnterReleased)

            else
                Sub.none

        mapRelease : Sub Msg
        mapRelease =
            if Maybe.map .mapView panel == Just TurnPlayback.SeeingMap then
                Browser.Events.onMouseUp (Decode.succeed CombatSeeMapReleased)

            else
                Sub.none
    in
    Sub.batch [ animationFrames, combatKeys, mapRelease ]
