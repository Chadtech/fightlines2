module Features exposing
    ( Feature(..)
    , Model
    , all
    , armyStyle
    , enabled
    , encodePreference
    , init
    , label
    , setEnabled
    )

import Error exposing (Error)
import Game.ArmyStyle as ArmyStyle exposing (ArmyStyle)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import LocalStorage exposing (LocalStorage)
import Preference
import Util.List as ListUtil



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Feature
    = Placeholder
    | Army ArmyStyle


type alias Model =
    { enabled : List Feature
    }



----------------------------------------------------------------
-- INIT --
----------------------------------------------------------------


init : LocalStorage -> ( Model, Maybe Error )
init storage =
    let
        ( features, error ) =
            Preference.load
                { key = "features"
                , decoder = Decode.map (List.filterMap identity) (Decode.list decoder)
                , defaultValue = []
                }
                storage
    in
    ( { enabled = features }
    , error
    )



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


all : List Feature
all =
    Placeholder :: List.map Army ArmyStyle.priority


armyStyle : Model -> Maybe ArmyStyle
armyStyle model =
    ArmyStyle.priority
        |> ListUtil.find (\style -> enabled (Army style) model)


enabled : Feature -> Model -> Bool
enabled feature model =
    List.member feature model.enabled


setEnabled : Feature -> Bool -> Model -> Model
setEnabled feature isEnabled model =
    let
        others : List Feature
        others =
            List.filter ((/=) feature) model.enabled

        features : List Feature
        features =
            if isEnabled then
                feature :: others

            else
                others
    in
    { model | enabled = features }


label : Feature -> String
label feature =
    case feature of
        Placeholder ->
            "placeholder"

        Army style ->
            ArmyStyle.label style ++ " army style"


encodePreference : Model -> { key : String, value : Encode.Value }
encodePreference model =
    { key = "features"
    , value = Encode.list (toString >> Encode.string) model.enabled
    }



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


toString : Feature -> String
toString feature =
    case feature of
        Placeholder ->
            "placeholder"

        Army style ->
            "army-" ++ ArmyStyle.slug style


decoder : Decoder (Maybe Feature)
decoder =
    Decode.string |> Decode.andThen decodeFeature


decodeFeature : String -> Decoder (Maybe Feature)
decodeFeature value =
    case value of
        "mobileLandscape" ->
            Decode.succeed Nothing

        _ ->
            case ListUtil.find (\feature -> toString feature == value) all of
                Just feature ->
                    Decode.succeed (Just feature)

                Nothing ->
                    Decode.fail ("unknown feature: " ++ value)
