module GamePage.Selection exposing
    ( DestinationFeedback(..)
    , Inspection(..)
    , MovePlanning
    , SelectedUnit
    , Selection(..)
    , UnitInteraction(..)
    , toInspection
    )

import Api.Enum.Direction exposing (Direction)
import Coordinate exposing (Coordinate)
import Movement
import UnitId exposing (UnitId)
import View.UnitCommands as UnitCommands



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Selection
    = Inspecting Inspection
    | UnitSelection SelectedUnit


type Inspection
    = UnitInspection UnitId
    | TileInspection Coordinate


type alias SelectedUnit =
    { id : UnitId
    , interaction : UnitInteraction
    }


type UnitInteraction
    = CommandMenu (Maybe UnitCommands.MenuOption)
    | ChoosingMove MovePlanning
    | ChoosingDirection Direction


type alias MovePlanning =
    { preview : Movement.Option
    , options : List Movement.Option
    , destinationFeedback : DestinationFeedback
    }


type DestinationFeedback
    = NoDestinationFeedback
    | DestinationUnavailable



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


{-| Drop editable interaction data when entering a locked phase. The selected
object is retained, without storing a second copy of its identity.
-}
toInspection : Selection -> Inspection
toInspection selection =
    case selection of
        Inspecting inspection ->
            inspection

        UnitSelection unit ->
            UnitInspection unit.id
