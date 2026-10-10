module KeyCmd exposing
    ( KeyCmd
    , a
    , backQuote
    , batch
    , cmd
    , comma
    , ctrl
    , downArrow
    , enter
    , escape
    , leftArrow
    , map
    , none
    , period
    , rightArrow
    , shift
    , subscriptions
    , upArrow
    )

import Browser.Events
import Json.Decode as Decode exposing (Decoder)
import OperatingSystem exposing (OperatingSystem)



--------------------------------------------------------------------------------
-- TYPES --
--------------------------------------------------------------------------------


type KeyCmd msg
    = Single (Model msg)
    | Batch (List (KeyCmd msg))


type alias Model msg =
    { msg : msg
    , command : Command
    , shift : Shift
    , keys : List String
    }


type Command
    = Command Bool


type Cmd
    = Cmd Bool


type Shift
    = Shift Bool


type Ctrl
    = Ctrl Bool



--------------------------------------------------------------------------------
-- IMPLEMENTATION --
--------------------------------------------------------------------------------


mapModels : (Model a -> Model msg) -> KeyCmd a -> KeyCmd msg
mapModels f keyCmd =
    case keyCmd of
        Single model ->
            Single (f model)

        Batch keyCmds ->
            Batch <| List.map (mapModels f) keyCmds


fromKeys : List String -> msg -> KeyCmd msg
fromKeys keys msg =
    Single
        { keys = keys
        , msg = msg
        , command = Command False
        , shift = Shift False
        }



--------------------------------------------------------------------------------
-- API --
--------------------------------------------------------------------------------


none : KeyCmd msg
none =
    batch []


batch : List (KeyCmd msg) -> KeyCmd msg
batch =
    Batch


map : (a -> msg) -> KeyCmd a -> KeyCmd msg
map toMsg keyCmd =
    case keyCmd of
        Single model ->
            Single
                { msg = toMsg model.msg
                , command = model.command
                , shift = model.shift
                , keys = model.keys
                }

        Batch keyCmds ->
            Batch <| List.map (map toMsg) keyCmds


cmd : KeyCmd msg -> KeyCmd msg
cmd =
    mapModels (\model -> { model | command = Command True })


ctrl : msg -> KeyCmd msg
ctrl =
    fromKeys [ "Control", "ctrl" ]


shift : KeyCmd msg -> KeyCmd msg
shift =
    mapModels (\model -> { model | shift = Shift True })


period : msg -> KeyCmd msg
period =
    fromKeys [ "period", "." ]


enter : msg -> KeyCmd msg
enter =
    fromKeys [ "Enter" ]


escape : msg -> KeyCmd msg
escape =
    fromKeys [ "Escape", "escape" ]


backQuote : msg -> KeyCmd msg
backQuote =
    fromKeys [ "`" ]


comma : msg -> KeyCmd msg
comma =
    fromKeys [ "comma", ",", "Comma" ]


a : msg -> KeyCmd msg
a =
    fromKeys [ "a" ]


rightArrow : msg -> KeyCmd msg
rightArrow =
    fromKeys [ "ArrowRight" ]


leftArrow : msg -> KeyCmd msg
leftArrow =
    fromKeys [ "ArrowLeft" ]


upArrow : msg -> KeyCmd msg
upArrow =
    fromKeys [ "ArrowUp" ]


downArrow : msg -> KeyCmd msg
downArrow =
    fromKeys [ "ArrowDown" ]


subscriptions : OperatingSystem -> List (KeyCmd msg) -> Sub msg
subscriptions os keyCmds =
    let
        fromEvent : KeyCmd msg -> Cmd -> Shift -> String -> Ctrl -> Maybe msg
        fromEvent remaining (Cmd eventCmdKey) eventShiftKey eventKey (Ctrl eventCtrlKey) =
            case remaining of
                Single model ->
                    let
                        cmdKeyPressed : Bool
                        cmdKeyPressed =
                            if os == OperatingSystem.MacOS || os == OperatingSystem.IOS then
                                eventCmdKey

                            else
                                eventCtrlKey
                    in
                    if
                        List.member eventKey model.keys
                            && model.command
                            == Command cmdKeyPressed
                            && model.shift
                            == eventShiftKey
                    then
                        Just model.msg

                    else
                        Nothing

                Batch [] ->
                    Nothing

                Batch (first :: rest) ->
                    case fromEvent first (Cmd eventCmdKey) eventShiftKey eventKey (Ctrl eventCtrlKey) of
                        Just msg ->
                            Just msg

                        Nothing ->
                            fromEvent (Batch rest) (Cmd eventCmdKey) eventShiftKey eventKey (Ctrl eventCtrlKey)

        fromMaybe : Maybe msg -> Decoder msg
        fromMaybe maybeMsg =
            case maybeMsg of
                Just msg ->
                    Decode.succeed msg

                Nothing ->
                    Decode.fail "Key Down event did not match any I was listening for"
    in
    Decode.map4
        (fromEvent <| batch keyCmds)
        (Decode.field "metaKey" Decode.bool
            |> Decode.map Cmd
        )
        (Decode.field "shiftKey" Decode.bool
            |> Decode.map Shift
        )
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool
            |> Decode.map Ctrl
        )
        |> Decode.andThen fromMaybe
        |> Browser.Events.onKeyDown
