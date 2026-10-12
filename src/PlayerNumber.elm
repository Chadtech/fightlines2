module PlayerNumber exposing (label)

import Api.Enum.PlayerNumber as PlayerNumber exposing (PlayerNumber)


label : PlayerNumber -> String
label side =
    case side of
        PlayerNumber.Player1 ->
            "player 1"

        PlayerNumber.Player2 ->
            "player 2"
