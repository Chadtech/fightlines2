module Game.LogId exposing
    ( GameLogId
    , parse
    , toString
    )

import LobbyId exposing (LobbyId)


type GameLogId
    = GameLogId LobbyId String


parse : String -> Result String GameLogId
parse value =
    case String.split "-" value of
        [ id, timestamp ] ->
            if not (String.isEmpty timestamp) && String.all Char.isDigit timestamp then
                LobbyId.parse id |> Result.map (\parsed -> GameLogId parsed timestamp)

            else
                Err "invalid logged game timestamp"

        _ ->
            Err "invalid logged game id"


toString : GameLogId -> String
toString (GameLogId id timestamp) =
    LobbyId.toString id ++ "-" ++ timestamp
