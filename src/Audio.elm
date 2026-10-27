module Audio exposing
    ( Audio(..)
    , Event(..)
    , encodeEvent
    , fieldGunFire
    , none
    , tankFire
    , uiAffirm
    , uiCancel
    , uiConfirm
    )

import Json.Encode as Je


type Event
    = None
    | Play Audio


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
