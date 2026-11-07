module Game.Archive exposing
    ( ArchiveReadError
    , Entry(..)
    , Game
    , LoggedGameStatus(..)
    , Player
    , entrySelection
    , playerLabel
    , selection
    , startedAtLabel
    , statusLabel
    )

import Api.Enum.Controller as Controller exposing (Controller)
import Api.Enum.LoggedGameStatusKind as StatusKind
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Object
import Api.Object.ArchivePlayer as PlayerApi
import Api.Object.ArchiveReadError as ReadErrorApi
import Api.Object.LoggedGame as GameApi
import Api.Object.LoggedGameStatus as StatusApi
import Api.Scalar exposing (MapId)
import Api.Union
import Api.Union.LoggedGameEntry as EntryApi
import Game.LogId as GameLogId exposing (GameLogId)
import Game.PlayerNumber as PlayerNumber
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Time



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Game =
    { id : GameLogId
    , name : String
    , mapType : MapId
    , startedAt : String
    , players : List Player
    , turnCount : Int
    , status : LoggedGameStatus
    }


type Entry
    = Readable Game
    | Unreadable ArchiveReadError


type alias ArchiveReadError =
    { id : GameLogId
    , message : String
    }


type LoggedGameStatus
    = Unfinished
    | PlayerWon PlayerNumber
    | Draw


type alias Player =
    { name : String
    , playerNumber : PlayerNumber
    , controller : Controller
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


selection : SelectionSet Game Api.Object.LoggedGame
selection =
    let
        player : SelectionSet Player Api.Object.ArchivePlayer
        player =
            SS.succeed Player
                |> SS.with PlayerApi.name
                |> SS.with PlayerApi.playerNumber
                |> SS.with PlayerApi.controller
    in
    SS.succeed Game
        |> SS.with (GameApi.id |> SS.mapOrFail GameLogId.parse)
        |> SS.with GameApi.name
        |> SS.with GameApi.mapType
        |> SS.with GameApi.startedAt
        |> SS.with (GameApi.players player)
        |> SS.with GameApi.turnCount
        |> SS.with (GameApi.status statusSelection)


entrySelection : SelectionSet Entry Api.Union.LoggedGameEntry
entrySelection =
    let
        readError : SelectionSet ArchiveReadError Api.Object.ArchiveReadError
        readError =
            SS.succeed ArchiveReadError
                |> SS.with (ReadErrorApi.id |> SS.mapOrFail GameLogId.parse)
                |> SS.with ReadErrorApi.message
    in
    EntryApi.fragments
        { onLoggedGame = selection |> SS.map Readable
        , onArchiveReadError = readError |> SS.map Unreadable
        }


statusSelection : SelectionSet LoggedGameStatus Api.Object.LoggedGameStatus
statusSelection =
    let
        decode : StatusKind.LoggedGameStatusKind -> Maybe PlayerNumber -> Result String LoggedGameStatus
        decode kind winner =
            case ( kind, winner ) of
                ( StatusKind.Unfinished, Nothing ) ->
                    Ok Unfinished

                ( StatusKind.PlayerWon, Just player ) ->
                    Ok (PlayerWon player)

                ( StatusKind.Draw, Nothing ) ->
                    Ok Draw

                _ ->
                    Err "logged game status has an inconsistent winner"
    in
    SS.succeed decode
        |> SS.with StatusApi.kind
        |> SS.with StatusApi.winner
        |> SS.mapOrFail identity


statusLabel : LoggedGameStatus -> String
statusLabel status =
    case status of
        Unfinished ->
            "unfinished"

        PlayerWon player ->
            PlayerNumber.label player ++ " won"

        Draw ->
            "draw"


startedAtLabel : String -> String
startedAtLabel timestamp =
    let
        pad : Int -> String
        pad value =
            String.padLeft 2 '0' (String.fromInt value)

        month : Time.Month -> Int
        month value =
            case value of
                Time.Jan ->
                    1

                Time.Feb ->
                    2

                Time.Mar ->
                    3

                Time.Apr ->
                    4

                Time.May ->
                    5

                Time.Jun ->
                    6

                Time.Jul ->
                    7

                Time.Aug ->
                    8

                Time.Sep ->
                    9

                Time.Oct ->
                    10

                Time.Nov ->
                    11

                Time.Dec ->
                    12

        format : Int -> String
        format milliseconds =
            let
                time : Time.Posix
                time =
                    Time.millisToPosix milliseconds
            in
            String.fromInt (Time.toYear Time.utc time) ++ "-" ++ pad (month (Time.toMonth Time.utc time)) ++ "-" ++ pad (Time.toDay Time.utc time) ++ " " ++ pad (Time.toHour Time.utc time) ++ ":" ++ pad (Time.toMinute Time.utc time) ++ " utc"
    in
    timestamp |> String.toInt |> Maybe.map format |> Maybe.withDefault "start time unavailable"


playerLabel : Player -> String
playerLabel player =
    let
        controller : String
        controller =
            case player.controller of
                Controller.Human ->
                    "human"

                Controller.Ai ->
                    "ai"
    in
    PlayerNumber.label player.playerNumber ++ ": " ++ player.name ++ " (" ++ controller ++ ")"
