module Side exposing (label)

import Api.Enum.Side as Side exposing (Side)


label : Side -> String
label side =
    case side of
        Side.West ->
            "red / west"

        Side.East ->
            "blue / east"
