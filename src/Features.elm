module Features exposing
    ( Feature(..)
    , Model
    , all
    , enabled
    , encodePreference
    , init
    , label
    , setEnabled
    )

import Error exposing (Error)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import LocalStorage exposing (LocalStorage)
import Preference



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Feature
    = MobileLandscape


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
                , decoder = Decode.list decoder
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
    [ MobileLandscape ]


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
        MobileLandscape ->
            "mobile view"


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
        MobileLandscape ->
            "mobileLandscape"


decoder : Decoder Feature
decoder =
    Decode.string |> Decode.andThen decodeFeature


decodeFeature : String -> Decoder Feature
decodeFeature value =
    case value of
        "mobileLandscape" ->
            Decode.succeed MobileLandscape

        _ ->
            Decode.fail ("unknown feature: " ++ value)
