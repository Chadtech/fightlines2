module Side exposing (label)

import Api.Enum.Side as Side exposing (Side)


label : Side -> String
label side =
    case side of
        Side.Player1 ->
            "player 1"

        Side.Player2 ->
            "player 2"
