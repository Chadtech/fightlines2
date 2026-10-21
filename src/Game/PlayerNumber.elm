module Game.PlayerNumber exposing (label)

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)


label : PlayerNumber -> String
label playerNumber =
    case playerNumber of
        PlayerNumber.Player1 ->
            "player 1"

        PlayerNumber.Player2 ->
            "player 2"
