module Audio exposing
    ( Ambience(..)
    , AmbientScene
    , Audio(..)
    , Channel(..)
    , Event(..)
    , FiringInfantry
    , MovementSound(..)
    , MovingUnit
    , MuteState(..)
    , Volumes
    , affirm
    , cancel
    , channelVolume
    , chatReceived
    , combatImpact
    , confirm
    , defaultVolumes
    , encodeEvent
    , encodeMutePreference
    , encodeVolumesPreference
    , fieldGunFire
    , loadMutePreference
    , loadVolumesPreference
    , none
    , setChannelVolume
    , syncAmbience
    , syncInfantryFire
    , syncMovement
    , tankFire
    , toggleMute
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
    | SetVolumes Volumes


{-| Percentages from 0 to 100. Defaults preserve the existing audio mix.
-}
type alias Volumes =
    { master : Float
    , combat : Float
    , movement : Float
    , ambience : Float
    , interface : Float
    }


type Channel
    = Master
    | Combat
    | Movement
    | Environment
    | Interface


defaultVolumes : Volumes
defaultVolumes =
    { master = 50
    , combat = 100
    , movement = 100
    , ambience = 100
    , interface = 100
    }


channelVolume : Channel -> Volumes -> Float
channelVolume channel volumes =
    case channel of
        Master ->
            volumes.master

        Combat ->
            volumes.combat

        Movement ->
            volumes.movement

        Environment ->
            volumes.ambience

        Interface ->
            volumes.interface


setChannelVolume : Channel -> Float -> Volumes -> Volumes
setChannelVolume channel raw volumes =
    let
        value : Float
        value =
            clamp 0 100 raw
    in
    case channel of
        Master ->
            { volumes | master = value }

        Combat ->
            { volumes | combat = value }

        Movement ->
            { volumes | movement = value }

        Environment ->
            { volumes | ambience = value }

        Interface ->
            { volumes | interface = value }


loadVolumesPreference : LocalStorage -> ( Volumes, Maybe Error )
loadVolumesPreference =
    let
        percentage : Decode.Decoder Float
        percentage =
            Decode.float |> Decode.andThen validPercentage

        validPercentage : Float -> Decode.Decoder Float
        validPercentage value =
            if (value >= 0) && (value <= 100) then
                Decode.succeed value

            else
                Decode.fail "audio volume must be between 0 and 100"
    in
    Preference.load
        { key = "audioVolumes"
        , decoder =
            Decode.map5 Volumes
                (Decode.field "master" percentage)
                (Decode.field "combat" percentage)
                (Decode.field "movement" percentage)
                (Decode.field "ambience" percentage)
                (Decode.field "interface" percentage)
        , defaultValue = defaultVolumes
        }


encodeVolumes : Volumes -> Je.Value
encodeVolumes volumes =
    Je.object
        [ ( "master", Je.float volumes.master )
        , ( "combat", Je.float volumes.combat )
        , ( "movement", Je.float volumes.movement )
        , ( "ambience", Je.float volumes.ambience )
        , ( "interface", Je.float volumes.interface )
        ]


encodeVolumesPreference : Volumes -> { key : String, value : Je.Value }
encodeVolumesPreference volumes =
    { key = "audioVolumes"
    , value = encodeVolumes volumes
    }


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
    = Affirm
    | Cancel
    | Confirm
    | ChatReceived
    | TankFire
    | FieldGunFire
    | CombatImpact


none : Event
none =
    None


affirm : Event
affirm =
    e Affirm


cancel : Event
cancel =
    e Cancel


confirm : Event
confirm =
    e Confirm


chatReceived : Event
chatReceived =
    e ChatReceived


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
        Affirm ->
            "affirm"

        Cancel ->
            "cancel"

        Confirm ->
            "confirm"

        ChatReceived ->
            "chatReceived"

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

        SetVolumes volumes ->
            Je.object [ ( "volumes", encodeVolumes volumes ) ]

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
