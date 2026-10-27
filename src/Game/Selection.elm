module Game.Selection exposing
    ( CommandMenuState(..)
    , SelectedUnit
    , Selection(..)
    , UnitInteraction(..)
    , setInteraction
    , toInspection
    )

import Game.DirectionPlanning exposing (DirectionPlanning)
import Game.IndirectFirePlanning exposing (IndirectFirePlanning)
import Game.Inspection as Inspection exposing (Inspection(..))
import Game.MovePlanning exposing (MovePlanning)
import Game.UnitCommand as UnitCommand
import Game.UnitId as UnitId exposing (UnitId)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Selection
    = Inspecting Inspection
    | UnitSelection SelectedUnit


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


setInteraction : UnitInteraction -> SelectedUnit -> SelectedUnit
setInteraction interaction model =
    { model | interaction = interaction }


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
