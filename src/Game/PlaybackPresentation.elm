module Game.PlaybackPresentation exposing
    ( Msg(..)
    , PlaybackCamera
    , Preference(..)
    , audioBetween
    , cameraPanDurationMs
    , combatOverlay
    , encodePreference
    , frameCamera
    , loadPreference
    , loss
    , lossDialog
    , lossError
    , movingVehicles
    , ownerName
    , readyToAutomaticallyClose
    , setRemainingPanMs
    , subscriptions
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Audio
import Browser.Events
import Error exposing (Error)
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
import Preference
import Util.Html.Event as HtmlEvent
import Util.List as ListUtil
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias PlaybackCamera =
    { camera : Camera
    , remainingPanMs : Float
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


setRemainingPanMs : Float -> PlaybackCamera -> PlaybackCamera
setRemainingPanMs remainingPanMs camera =
    { camera | remainingPanMs = remainingPanMs }


cameraPanDurationMs : Float
cameraPanDurationMs =
    1200


{-| Fire once as the presentation clock crosses each muzzle-flash timestamp.
An unchanged clock (pause or camera hold) cannot replay a cue. A new encounter
or rewind starts a fresh interval instead of catching up old shots.
-}
audioBetween :
    { before : Maybe TurnPlayback.Playback
    , after : Maybe TurnPlayback.Playback
    }
    -> List Audio.Event
audioBetween transition =
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
                in
                (cues UnitKind.Tank Audio.tankFire ++ cues UnitKind.FieldGun Audio.fieldGunFire)
                    |> List.sortBy .startsAt
                    |> List.filter (\cue -> (before.elapsed < cue.startsAt) && (cue.startsAt <= after.elapsed))
                    |> List.map .sound

            else
                []

        _ ->
            []


{-| Follow the same projected movement edges as the sprites. Camera holds,
replay pauses and casualty dialogs freeze movement and therefore silence it.
-}
movingVehicles :
    { playback : Maybe TurnPlayback.Playback
    , paused : Bool
    , camera : Maybe PlaybackCamera
    , skipLossDialogs : Bool
    }
    -> List Audio.MovingVehicle
movingVehicles state =
    let
        cameraSettling : Bool
        cameraSettling =
            (state.camera |> Maybe.map .remainingPanMs |> Maybe.withDefault 0) > 0

        lossHeld : Bool
        lossHeld =
            loss state.skipLossDialogs state.playback /= Nothing

        vehicle : Unit -> Maybe Audio.MovingVehicle
        vehicle unit =
            case unit.kind of
                UnitKind.Truck ->
                    Just { unitId = unit.id, vehicle = Audio.Truck }

                UnitKind.Tank ->
                    Just { unitId = unit.id, vehicle = Audio.Tank }

                _ ->
                    Nothing

        moving : TurnPlayback.Playback -> List Audio.MovingVehicle
        moving animation =
            let
                ids : List UnitId
                ids =
                    TurnPlayback.movingPositions (Just animation) |> List.map .unitId
            in
            animation.current.units
                |> List.filter (\unit -> List.member unit.id ids && not (Unit.isDying unit))
                |> List.filterMap vehicle
    in
    if state.paused || cameraSettling || lossHeld then
        []

    else
        state.playback |> Maybe.map moving |> Maybe.withDefault []


frameCamera : Camera.Viewport -> Map -> Camera -> TurnPlayback.Playback -> Maybe PlaybackCamera -> PlaybackCamera
frameCamera viewport map saved animation held =
    let
        previous : Camera
        previous =
            held |> Maybe.map .camera |> Maybe.withDefault saved

        target : Camera
        target =
            Camera.frame viewport map (TurnPlayback.focusPositions animation) previous

        remainingPanMs : Float
        remainingPanMs =
            if target /= previous then
                cameraPanDurationMs

            else
                held |> Maybe.map .remainingPanMs |> Maybe.withDefault 0
    in
    { camera = target, remainingPanMs = remainingPanMs }


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
    , ownPlayers : List PlayerNumber
    }
    -> Maybe TurnPlayback.Playback
    -> Maybe (Dialog UnitDeath.Msg)
lossDialog config playback =
    let
        notice : TurnPlayback.Loss -> Dialog UnitDeath.Msg
        notice casualty =
            UnitDeath.dialog
                { skipDialogs = config.skipDialogs
                , isOwn = List.member casualty.unit.playerNumber config.ownPlayers
                , details = UnitLoss.resolve (ownerName config.players) casualty
                , passengers = playback |> Maybe.andThen TurnPlayback.lossEvent |> Maybe.map .passengers |> Maybe.withDefault []
                }
                casualty
    in
    loss config.skipDialogs playback |> Maybe.map notice


combatOverlay : List BackdropCalibration.Entry -> Bool -> Map -> Maybe TurnPlayback.Playback -> Html CombatTheater.Msg
combatOverlay calibrations automaticallyClose map playback =
    let
        overlay : TurnPlayback.Playback -> Maybe (Html CombatTheater.Msg)
        overlay animation =
            TurnPlayback.panels animation
                |> Maybe.map
                    (CombatTheater.toHtml
                        { calibrations = calibrations
                        , automaticallyClose = automaticallyClose
                        , visibleTiles = animation.current.visibleTiles
                        }
                        animation.current.depots
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


subscriptions : Maybe TurnPlayback.Playback -> Sub Msg
subscriptions playback =
    let
        panel : Maybe TurnPlayback.Panel
        panel =
            playback |> Maybe.andThen TurnPlayback.panels

        animationFrames : Sub Msg
        animationFrames =
            if playback /= Nothing then
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
