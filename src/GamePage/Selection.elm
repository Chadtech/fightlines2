module GamePage.Selection exposing
    ( CommandMenuState(..)
    , DestinationFeedback(..)
    , FacingPurpose(..)
    , Inspection(..)
    , MovePlanning
    , MovePurpose(..)
    , SelectedUnit
    , Selection(..)
    , UnitInteraction(..)
    , toInspection
    )

import Api.Enum.Direction exposing (Direction)
import Coordinate exposing (Coordinate)
import Movement
import UnitCommand
import UnitId exposing (UnitId)



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
    = CommandMenu CommandMenuState
    | ChoosingMove MovePlanning
    | ChoosingDirection FacingPurpose Direction
    | ChoosingIndirectFire


type CommandMenuState
    = ChoosingCommand (Maybe UnitCommand.MenuOption)
    | ReadingGuide (Maybe UnitCommand.MenuOption)


type FacingPurpose
    = RotationFacing
    | AmbushFacing


type MovePurpose
    = NormalMove
    | AttackMove


type alias MovePlanning =
    { purpose : MovePurpose
    , preview : Movement.Option
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
