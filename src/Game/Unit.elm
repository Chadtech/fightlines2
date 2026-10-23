module Game.Unit exposing
    ( Unit
    , carrierId
    , faceDirection
    , freightCount
    , fuelMovementPerTile
    , isDying
    , label
    , loadingTarget
    , mapPosition
    , mapResources
    , occupiedCargoSlots
    , onMap
    , physicalPosition
    , selection
    , setCargoCapacity
    , setCombatRules
    , setDestroyed
    , setDirection
    , setEntrenchment
    , setId
    , setKind
    , setLocation
    , setOnMap
    , setPlayerNumber
    , setResources
    , setSpriteFacing
    , supplyMovementLimit
    )

import Api.Enum.Direction exposing (Direction)
import Api.Enum.Entrenchment as Entrenchment exposing (Entrenchment)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Api.Enum.SpriteFacing exposing (SpriteFacing)
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Api.Object
import Api.Object.Unit as UnitApi
import Game.CombatRules as CombatRules exposing (CombatRules)
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.PlayerNumber as PlayerNumber
import Game.SpriteFacing as SpriteFacing
import Game.Unit.Location as Location exposing (Location)
import Game.Unit.Supplies exposing (Supplies)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitKind as UnitKindUtil
import Game.UnitResources as UnitResources exposing (UnitResources)
import Graphql.SelectionSet as SS exposing (SelectionSet)
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Unit =
    { id : UnitId
    , playerNumber : PlayerNumber
    , kind : UnitKind
    , direction : Maybe Direction
    , spriteFacing : SpriteFacing
    , resources : Maybe UnitResources
    , cargoCapacity : Int
    , destroyed : Bool
    , combatRules : CombatRules
    , entrenchment : Entrenchment
    , location : Location
    }



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


selection : SelectionSet Unit Api.Object.Unit
selection =
    SS.succeed Unit
        |> SS.with UnitId.selection
        |> SS.with UnitApi.playerNumber
        |> SS.with UnitApi.kind
        |> SS.with UnitApi.direction
        |> SS.with UnitApi.spriteFacing
        |> SS.with (UnitApi.resources UnitResources.selection)
        |> SS.with UnitApi.cargoCapacity
        |> SS.with UnitApi.destroyed
        |> SS.with (UnitApi.combatRules CombatRules.selection)
        |> SS.with UnitApi.entrenchment
        |> SS.with (UnitApi.location Location.selection)


label : Unit -> String
label unit =
    let
        kindLabel : String
        kindLabel =
            if unit.entrenchment == Entrenchment.Entrenched then
                "entrenched " ++ UnitKindUtil.label unit.kind

            else
                UnitKindUtil.label unit.kind
    in
    String.join " "
        [ PlayerNumber.label unit.playerNumber
        , kindLabel
        , UnitId.toString unit.id
        ]


setId : UnitId -> Unit -> Unit
setId value unit =
    { unit | id = value }


setPlayerNumber : PlayerNumber -> Unit -> Unit
setPlayerNumber value unit =
    { unit | playerNumber = value }


setKind : UnitKind -> Unit -> Unit
setKind value unit =
    { unit | kind = value }


{-| Set direction without changing sprite facing. Use faceDirection to turn both.
-}
setDirection : Maybe Direction -> Unit -> Unit
setDirection value unit =
    { unit | direction = value }


setSpriteFacing : SpriteFacing -> Unit -> Unit
setSpriteFacing value unit =
    { unit | spriteFacing = value }


setResources : Maybe UnitResources -> Unit -> Unit
setResources value unit =
    { unit | resources = value }


setCargoCapacity : Int -> Unit -> Unit
setCargoCapacity value unit =
    { unit | cargoCapacity = value }


setDestroyed : Bool -> Unit -> Unit
setDestroyed value unit =
    { unit | destroyed = value }


setCombatRules : CombatRules -> Unit -> Unit
setCombatRules value unit =
    { unit | combatRules = value }


setEntrenchment : Entrenchment -> Unit -> Unit
setEntrenchment value unit =
    { unit | entrenchment = value }


setLocation : Location -> Unit -> Unit
setLocation value unit =
    { unit | location = value }


{-| Transform visible resources while preserving concealed resources as Nothing.
-}
mapResources : (UnitResources -> UnitResources) -> Unit -> Unit
mapResources transform unit =
    setResources (Maybe.map transform unit.resources) unit


setOnMap : Coordinate -> Unit -> Unit
setOnMap position unit =
    setLocation (Location.OnMap position) unit


{-| Upkeep is reserved before spending supplies on movement.
Units with no per-tile supply consumption have no supply movement limit.
-}
supplyMovementLimit : Supplies -> Maybe Int
supplyMovementLimit supplies =
    if supplies.movementPerTile > 0 then
        Just (max 0 (supplies.current - supplies.upkeepPerTurn) // supplies.movementPerTile)

    else
        Nothing


{-| Use the physical cargo at departure, before destination loading or unloading.
-}
fuelMovementPerTile : List Unit -> Unit -> Int
fuelMovementPerTile units unit =
    unit.resources
        |> Maybe.andThen .fuel
        |> Maybe.map (\fuel -> fuel.movementPerTile + occupiedCargoSlots units unit * fuel.movementPerCargoSlot)
        |> Maybe.withDefault 0


occupiedCargoSlots : List Unit -> Unit -> Int
occupiedCargoSlots units unit =
    let
        passengers : Int
        passengers =
            units |> List.filter (\passenger -> carrierId passenger == Just unit.id) |> List.length
    in
    passengers + freightCount unit


onMap : Unit -> Bool
onMap unit =
    mapPosition unit /= Nothing


isDying : Unit -> Bool
isDying unit =
    unit.destroyed
        || (unit.resources
                |> Maybe.map
                    (\resources ->
                        resources.supplies.current == 0 || resources.hitPoints.current == 0
                    )
                |> Maybe.withDefault False
           )


loadingTarget : List Unit -> Unit -> Coordinate -> Maybe Unit
loadingTarget units mover destination =
    let
        compatible : Unit -> Bool
        compatible target =
            let
                hasRoom : Unit -> Bool
                hasRoom truck =
                    let
                        passengers : List Unit
                        passengers =
                            List.filter (\passenger -> carrierId passenger == Just truck.id) units

                        occupiedBerths : Int
                        occupiedBerths =
                            List.length passengers + freightCount truck
                    in
                    (truck.kind == UnitKind.Truck)
                        && (occupiedBerths < truck.cargoCapacity)

                portable : Unit -> Bool
                portable unit =
                    unit.kind == UnitKind.Infantry || unit.kind == UnitKind.FieldGun

                alliedTarget : Bool
                alliedTarget =
                    mapPosition target == Just destination && target.id /= mover.id && target.playerNumber == mover.playerNumber

                loadingAllowed : Bool
                loadingAllowed =
                    (hasRoom mover && portable target) || (portable mover && hasRoom target)
            in
            alliedTarget && onMap mover && onMap target && loadingAllowed
    in
    ListUtil.find compatible units


mapPosition : Unit -> Maybe Coordinate
mapPosition unit =
    case unit.location of
        Location.Dismounting position ->
            Just position

        Location.OnMap position ->
            Just position

        Location.Aboard _ ->
            Nothing


carrierId : Unit -> Maybe UnitId
carrierId unit =
    case unit.location of
        Location.Dismounting _ ->
            Nothing

        Location.OnMap _ ->
            Nothing

        Location.Aboard carrier ->
            Just carrier


{-| Resolve a passenger through its carrier's board position. Missing carriers
and carriers that are themselves aboard have no physical position.
-}
physicalPosition : List Unit -> Unit -> Maybe Coordinate
physicalPosition units unit =
    case unit.location of
        Location.Dismounting position ->
            Just position

        Location.OnMap position ->
            Just position

        Location.Aboard carrier ->
            ListUtil.find (\truck -> truck.id == carrier) units
                |> Maybe.andThen mapPosition


faceDirection : Maybe Direction -> Unit -> Unit
faceDirection direction unit =
    unit
        |> setDirection direction
        |> setSpriteFacing (SpriteFacing.turn direction unit.spriteFacing)


{-| Count carried supply crates and fuel drums, excluding passengers.
-}
freightCount : Unit -> Int
freightCount unit =
    unit.resources
        |> Maybe.map (.supplyCargo >> List.length)
        |> Maybe.withDefault 0
