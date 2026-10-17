module GamePage.Selection exposing
    ( CommandMenuState(..)
    , Inspection(..)
    , SelectedUnit
    , Selection(..)
    , UnitInteraction(..)
    , toInspection
    )

import Coordinate exposing (Coordinate)
import GamePage.DirectionPlanning exposing (DirectionPlanning)
import GamePage.IndirectFirePlanning exposing (IndirectFirePlanning)
import GamePage.MovePlanning exposing (MovePlanning)
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
    | ChoosingDirection DirectionPlanning
    | ChoosingIndirectFire IndirectFirePlanning


type CommandMenuState
    = ChoosingCommand (Maybe UnitCommand.MenuOption)
    | ReadingGuide (Maybe UnitCommand.MenuOption)



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
