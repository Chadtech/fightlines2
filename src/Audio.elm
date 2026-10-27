module Audio exposing
    ( Audio(..)
    , Event(..)
    , MovingVehicle
    , Vehicle(..)
    , encodeEvent
    , fieldGunFire
    , none
    , syncMovement
    , tankFire
    , uiAffirm
    , uiCancel
    , uiConfirm
    )

import Game.UnitId as UnitId exposing (UnitId)
import Json.Encode as Je


type Event
    = None
    | Play Audio
    | SyncMovement (List MovingVehicle)


type Vehicle
    = Truck
    | Tank


type alias MovingVehicle =
    { unitId : UnitId
    , vehicle : Vehicle
    }


{-| Refresh active movement while any vehicle moves, including after a hidden
tab returns. An empty snapshot stops the last voices without idle port traffic.
-}
syncMovement : { before : List MovingVehicle, after : List MovingVehicle } -> Event
syncMovement vehicles =
    if List.isEmpty vehicles.before && List.isEmpty vehicles.after then
        None

    else
        SyncMovement vehicles.after


type Audio
    = UiAffirm
    | UiCancel
    | UiConfirm
    | TankFire
    | FieldGunFire


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


encodeEvent : Event -> Je.Value
encodeEvent event =
    case event of
        None ->
            Je.null

        Play audio ->
            Je.object
                [ Tuple.pair "play" <| Je.string <| audioToName audio ]

        SyncMovement vehicles ->
            Je.object
                [ ( "movement", Je.list encodeMovingVehicle vehicles ) ]


encodeMovingVehicle : MovingVehicle -> Je.Value
encodeMovingVehicle moving =
    let
        sound : String
        sound =
            case moving.vehicle of
                Truck ->
                    "truck"

                Tank ->
                    "tank"
    in
    Je.object
        [ ( "unitId", Je.string (UnitId.toString moving.unitId) )
        , ( "vehicle", Je.string sound )
        ]
