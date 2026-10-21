module Game.View.Cliff exposing
    ( corner
    , edge
    )

import Api.Enum.Direction as Direction exposing (Direction)
import Game.Shoreline exposing (Corner(..))
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA


{-| Direction points from the water cell toward its neighboring land. The camera
stays south of the board: land to the north exposes its south-facing cliff wall.
-}
edge : Direction -> Svg msg
edge towardLand =
    case towardLand of
        Direction.North ->
            artwork "front-edge"

        Direction.South ->
            artwork "back-edge"
                |> transformed "translate(0 16) scale(1 0.5) translate(0 -16)"

        Direction.West ->
            sideEdge

        Direction.East ->
            sideEdge |> mirrored


corner : Corner -> Svg msg
corner location =
    case location of
        NorthWest ->
            frontCorner

        NorthEast ->
            frontCorner |> mirrored

        SouthWest ->
            backCorner

        SouthEast ->
            backCorner |> mirrored


sideEdge : Svg msg
sideEdge =
    artwork "side-edge"
        |> transformed "scale(0.7 1)"


frontCorner : Svg msg
frontCorner =
    artwork "front-corner"
        |> transformed "scale(0.5 0.85)"


backCorner : Svg msg
backCorner =
    artwork "back-corner"
        |> transformed "translate(0 16) scale(0.5 0.3) translate(0 -16)"


mirrored : Svg msg -> Svg msg
mirrored =
    transformed "translate(16 0) scale(-1 1)"


transformed : String -> Svg msg -> Svg msg
transformed transform graphic =
    Svg.g
        [ SA.transform transform
        , SA.pointerEvents "none"
        ]
        [ graphic ]


artwork : String -> Svg msg
artwork name =
    Svg.image
        [ SA.width "16"
        , SA.height "16"
        , SA.xlinkHref ("/assets/coast-illustrated-v2/cliff-" ++ name ++ ".png")
        , SA.pointerEvents "none"
        ]
        []
