module Game.Matchup exposing (Matchup, fromPlayers, players)

import Api.Enum.PlayerNumber as PlayerNumber
import Game.BattlefieldSnapshot
    exposing
        ( Player
        )


type alias Matchup =
    { you : Player
    , opponent : Player
    }


fromPlayers : List Player -> Result String Matchup
fromPlayers roster =
    case List.partition .isYou roster of
        ( [ you ], [ opponent ] ) ->
            if you.playerNumber == opponent.playerNumber then
                Err "the game roster assigned both players to the same side."

            else
                Ok (Matchup you opponent)

        _ ->
            Err "the game roster must contain one player on your side and one opponent."


players : Matchup -> List Player
players matchup =
    case matchup.you.playerNumber of
        PlayerNumber.Player1 ->
            [ matchup.you, matchup.opponent ]

        PlayerNumber.Player2 ->
            [ matchup.opponent, matchup.you ]
