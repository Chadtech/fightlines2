module Game.MapType exposing (label)

import Api.Enum.MapType
    exposing
        ( MapType
        )


label : MapType -> String
label mapType =
    case mapType of
        Api.Enum.MapType.SupplyPoint ->
            "supply point"

        Api.Enum.MapType.ElAlamein ->
            "el alamein"

        Api.Enum.MapType.BloodGulch ->
            "blood gulch"

        Api.Enum.MapType.Arabia ->
            "arabia"

        Api.Enum.MapType.Sidewinder ->
            "sidewinder"

        Api.Enum.MapType.BlackForest ->
            "black forest"

        Api.Enum.MapType.Crossroads ->
            "crossroads"

        Api.Enum.MapType.Ridgeway ->
            "ridgeway"

        Api.Enum.MapType.ThreeCrossings ->
            "three crossings"

        Api.Enum.MapType.LakeOfPennsylvania ->
            "lake of pennsylvania"
