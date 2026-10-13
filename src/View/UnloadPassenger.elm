module View.UnloadPassenger exposing (toHtml)

import Html.Styled exposing (Html)
import Unit exposing (Unit)
import View.CargoPassenger as CargoPassenger
import View.Checkbox as Checkbox


toHtml : { disabled : Bool, checked : Bool, onCheck : Bool -> msg } -> Unit -> Html msg
toHtml config unit =
    Checkbox.toHtmlDisabled config.disabled
        { label = Unit.label unit
        , checked = config.checked
        , onCheck = config.onCheck
        }
        (CargoPassenger.contents unit)
