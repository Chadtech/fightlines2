module Audio exposing
    ( Ambience(..)
    , AmbientScene
    , Audio(..)
    , Event(..)
    , FiringInfantry
    , MovementSound(..)
    , MovingUnit
    , MuteState(..)
    , combatImpact
    , encodeEvent
    , encodeMutePreference
    , fieldGunFire
    , loadMutePreference
    , none
    , syncAmbience
    , syncInfantryFire
    , syncMovement
    , tankFire
    , toggleMute
    , uiAffirm
    , uiCancel
    , uiConfirm
    )

import Error exposing (Error)
import Game.UnitId as UnitId exposing (UnitId)
import Json.Decode as Decode
import Json.Encode as Je
import LocalStorage exposing (LocalStorage)
import Preference


type Event
    = None
    | Play Audio
    | SyncMovement (List MovingUnit)
    | SyncAmbience (List AmbientScene)
    | SyncInfantryFire (List FiringInfantry)
    | SetMute MuteState


type MuteState
    = Unmuted
    | Muted


toggleMute : MuteState -> MuteState
toggleMute state =
    case state of
        Unmuted ->
            Muted

        Muted ->
            Unmuted


loadMutePreference : LocalStorage -> ( MuteState, Maybe Error )
loadMutePreference =
    Preference.load
        { key = mutePreferenceKey
        , decoder = Decode.map muteFromBool Decode.bool
        , defaultValue = Unmuted
        }


encodeMutePreference : MuteState -> { key : String, value : Je.Value }
encodeMutePreference state =
    { key = mutePreferenceKey
    , value = Je.bool (state == Muted)
    }


mutePreferenceKey : String
mutePreferenceKey =
    "audioMuted"


muteFromBool : Bool -> MuteState
muteFromBool muted =
    if muted then
        Muted

    else
        Unmuted


type Ambience
    = Plains
    | Forest
    | Snow
    | Desert
    | Beach


type alias AmbientScene =
    { ambience : Ambience
    , pan : Float
    }


syncAmbience : { before : List AmbientScene, after : List AmbientScene } -> Event
syncAmbience scenes =
    if List.isEmpty scenes.before && List.isEmpty scenes.after then
        None

    else
        SyncAmbience scenes.after


type MovementSound
    = Infantry
    | Truck
    | Tank


type alias FiringInfantry =
    { unitId : UnitId
    , elapsedMs : Float
    , remainingMs : Float
    }


syncInfantryFire : { before : List FiringInfantry, after : List FiringInfantry } -> Event
syncInfantryFire units =
    if List.isEmpty units.before && List.isEmpty units.after then
        None

    else
        SyncInfantryFire units.after


type alias MovingUnit =
    { unitId : UnitId
    , sound : MovementSound
    }


{-| Refresh active movement while any unit moves, including after a hidden
tab returns. An empty snapshot stops the last voices without idle port traffic.
-}
syncMovement : { before : List MovingUnit, after : List MovingUnit } -> Event
syncMovement units =
    if List.isEmpty units.before && List.isEmpty units.after then
        None

    else
        SyncMovement units.after


type Audio
    = UiAffirm
    | UiCancel
    | UiConfirm
    | TankFire
    | FieldGunFire
    | CombatImpact


none : Event
none =
    None


uiAffirm : Event
uiAffirm =
    e UiAffirm


uiCancel : Event
uiCancel =
    e UiCancel


uiConfirm : Event
uiConfirm =
    e UiConfirm


tankFire : Event
tankFire =
    e TankFire


fieldGunFire : Event
fieldGunFire =
    e FieldGunFire


combatImpact : Event
combatImpact =
    e CombatImpact


e : Audio -> Event
e audio =
    Play audio


audioToName : Audio -> String
audioToName audio =
    case audio of
        UiAffirm ->
            "uiAffirm"

        UiCancel ->
            "uiCancel"

        UiConfirm ->
            "uiConfirm"

        TankFire ->
            "tankFire"

        FieldGunFire ->
            "fieldGunFire"

        CombatImpact ->
            "combatImpact"


encodeEvent : Event -> Je.Value
encodeEvent event =
    case event of
        None ->
            Je.null

        SetMute state ->
            Je.object
                [ ( "muted", Je.bool (state == Muted) ) ]

        Play audio ->
            Je.object
                [ Tuple.pair "play" <| Je.string <| audioToName audio ]

        SyncMovement units ->
            Je.object
                [ ( "movement", Je.list encodeMovingUnit units ) ]

        SyncAmbience scenes ->
            Je.object
                [ ( "ambience", Je.list encodeAmbientScene scenes ) ]

        SyncInfantryFire units ->
            Je.object
                [ ( "infantryFire", Je.list encodeFiringInfantry units ) ]


encodeFiringInfantry : FiringInfantry -> Je.Value
encodeFiringInfantry unit =
    Je.object
        [ ( "unitId", Je.string (UnitId.toString unit.unitId) )
        , ( "elapsedMs", Je.float unit.elapsedMs )
        , ( "remainingMs", Je.float unit.remainingMs )
        ]


encodeAmbientScene : AmbientScene -> Je.Value
encodeAmbientScene scene =
    let
        name : String
        name =
            case scene.ambience of
                Plains ->
                    "plains"

                Forest ->
                    "forest"

                Snow ->
                    "snow"

                Desert ->
                    "desert"

                Beach ->
                    "beach"
    in
    Je.object
        [ ( "environment", Je.string name )
        , ( "pan", Je.float scene.pan )
        ]


encodeMovingUnit : MovingUnit -> Je.Value
encodeMovingUnit moving =
    let
        sound : String
        sound =
            case moving.sound of
                Infantry ->
                    "infantry"

                Truck ->
                    "truck"

                Tank ->
                    "tank"
    in
    Je.object
        [ ( "unitId", Je.string (UnitId.toString moving.unitId) )
        , ( "sound", Je.string sound )
        ]
