module GamePage.EditingSelection exposing
    ( EditingSelection(..)
    , MovePlanning
    , SelectedUnit
    , UnitInteraction(..)
    , UnloadPlanning
    )

import Api.Enum.Direction exposing (Direction)
import Movement
import UnitId exposing (UnitId)
import View.UnitCommands as UnitCommands



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type EditingSelection
    = EditingUnit SelectedUnit
    | EditingUnload UnloadPlanning


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
    }


type alias UnloadPlanning =
    { truckId : UnitId
    , passengerId : UnitId
    , remaining : List UnitId
    , options : List Movement.Option
    }
