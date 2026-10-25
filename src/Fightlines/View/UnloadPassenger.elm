module Fightlines.View.UnloadPassenger exposing (toHtml)

import Game.Unit as Unit exposing (Unit)
import Game.View.CargoPassenger as CargoPassenger
import Html.Styled exposing (Html)
import View.Checkbox as Checkbox


toHtml : { disabled : Bool, checked : Bool, onCheck : Bool -> msg } -> Unit -> Html msg
toHtml config unit =
    Checkbox.new
        { label = Unit.label unit
        , checked = config.checked
        , onCheck = config.onCheck
        }
        |> Checkbox.disabled config.disabled
        |> Checkbox.toHtml (CargoPassenger.contents unit)
