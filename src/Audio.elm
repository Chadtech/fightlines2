module Audio exposing
    ( Audio(..)
    , Event(..)
    , encodeEvent
    , none
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


encodeEvent : Event -> Je.Value
encodeEvent event =
    case event of
        None ->
            Je.null

        Play audio ->
            Je.object
                [ Tuple.pair "play" <| Je.string <| audioToName audio ]
