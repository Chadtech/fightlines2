module Game.View.MapPreview exposing
    ( buildingToSvg
    , definitionToHtml
    , toHtml
    , unitToSvg
    )

import Api.Enum.Direction as Direction
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.UnitKind as UnitKind
import Api.Scalar exposing (MapId)
import EditableMap
    exposing
        ( BuildingPlacement
        , Definition
        , NamedMap
        , UnitPlacement
        )
import Game.Building as Building
import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Game.MapId as MapId
import Game.View.TerrainTile as TerrainTile
import Html.Styled exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Lazy as Lazy
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Sprite as Sprite


{-| An inert overview of authored terrain, buildings, and starting forces.
The caller owns its dimensions. Artwork stays still and is shared with the game.
-}
toHtml : NamedMap -> Html msg
toHtml map =
    definitionToHtml
        { mapType = map.mapType
        , definition = map.definition
        }


{-| Render a submitted editor snapshot before it has a saved thumbnail URL.
-}
definitionToHtml : { mapType : MapId, definition : Definition } -> Html msg
definitionToHtml map =
    Svg.svg
        [ SA.width "100%"
        , SA.height "100%"
        , SA.viewBox ("0 0 " ++ String.fromInt (map.definition.width * 16) ++ " " ++ String.fromInt (map.definition.height * 16))
        , Aria.role Aria.Image
        , Aria.label (MapId.label map.mapType ++ ": terrain and starting forces")
        , A.css
            [ S.block
            , S.wFull
            , S.hFull
            , S.pointerEventsNone
            ]
        ]
        [ Lazy.lazy artwork map.definition
        ]


artwork : Definition -> Svg msg
artwork definition =
    let
        map : Map
        map =
            EditableMap.map definition

        terrainAt : Coordinate -> Svg msg
        terrainAt position =
            placed position (TerrainTile.stillOnMap map position)

        buildingAt : BuildingPlacement -> Svg msg
        buildingAt building =
            placed building.position (buildingToSvg building)

        unitAt : UnitPlacement -> Svg msg
        unitAt unit =
            placed unit.position (unitToSvg unit)

        terrain : List (Svg msg)
        terrain =
            List.map terrainAt (Map.positions map)

        buildings : List (Svg msg)
        buildings =
            List.map buildingAt definition.buildings

        units : List (Svg msg)
        units =
            List.map unitAt definition.units
    in
    Svg.g
        []
        (terrain ++ buildings ++ units)


placed : Coordinate -> Svg msg -> Svg msg
placed position image =
    Svg.g
        [ SA.transform ("translate(" ++ String.fromInt (position.x * 16) ++ " " ++ String.fromInt (position.y * 16) ++ ")")
        ]
        [ image
        ]


buildingToSvg : BuildingPlacement -> Svg msg
buildingToSvg building =
    Svg.image
        [ SA.xlinkHref (Building.kindImage building.kind)
        , SA.width "16"
        , SA.height "16"
        , SA.pointerEvents "none"
        ]
        []


unitToSvg : UnitPlacement -> Svg msg
unitToSvg unit =
    let
        baseRow : Int
        baseRow =
            case unit.kind of
                UnitKind.Infantry ->
                    0

                UnitKind.Tank ->
                    3

                UnitKind.Truck ->
                    6

                UnitKind.FieldGun ->
                    9

        playerRow : Int
        playerRow =
            case unit.playerNumber of
                PlayerNumber.Player1 ->
                    0

                PlayerNumber.Player2 ->
                    1

        facesLeft : Bool
        facesLeft =
            case unit.direction of
                Just Direction.East ->
                    False

                Just Direction.West ->
                    True

                _ ->
                    unit.playerNumber == PlayerNumber.Player2

        transform : String
        transform =
            if facesLeft then
                "translate(16 0) scale(-1 1)"

            else
                ""
    in
    Svg.g
        [ SA.transform transform
        , SA.pointerEvents "none"
        ]
        [ Sprite.toSvg
            { path = "assets/units_illustrated-v4.png"
            , sheetWidth = 64
            , sheetHeight = 192
            , column = 0
            , row = baseRow + playerRow
            }
        ]
