module View.AudioMute exposing (toHtml)

import Audio exposing (MuteState(..))
import Css.Media
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Events as Ev
import Json.Decode as Decode
import Style as S
import Svg.Styled as Svg exposing (Svg)
import Svg.Styled.Attributes as SA
import View.Aria as Aria


{-| Keep keyboard activation from also issuing battlefield shortcuts.
Prevent the native click so each activation toggles exactly once.
-}
activationKey : msg -> Decode.Decoder { message : msg, stopPropagation : Bool, preventDefault : Bool }
activationKey onClick =
    let
        fromKey : String -> Decode.Decoder { message : msg, stopPropagation : Bool, preventDefault : Bool }
        fromKey key =
            if (key == "Enter") || (key == " ") then
                Decode.succeed
                    { message = onClick
                    , stopPropagation = True
                    , preventDefault = True
                    }

            else
                Decode.fail "not a speaker activation key"
    in
    Decode.field "key" Decode.string
        |> Decode.andThen fromKey


toHtml : { mute : MuteState, onClick : msg } -> Html msg
toHtml options =
    let
        label : String
        label =
            case options.mute of
                Muted ->
                    "unmute all audio"

                Unmuted ->
                    "mute all audio"

        pressed : String
        pressed =
            if options.mute == Muted then
                "true"

            else
                "false"
    in
    H.button
        [ A.type_ "button"
        , Aria.label label
        , A.title label
        , A.attribute "aria-pressed" pressed
        , Ev.onClick options.onClick
        , Ev.custom "keydown" (activationKey options.onClick)
        , A.css
            [ S.fixed
            , S.top1
            , S.left1
            , S.z4
            , S.w9
            , S.h9
            , S.p0
            , S.border0
            , S.bgTransparent
            , S.textGray4
            , S.row
            , S.itemsCenter
            , S.justifyCenter
            , S.pointerCursor
            , S.opacity 0.8
            , S.hover
                [ S.textGray5
                , S.opacity 1
                ]
            , S.focusVisible
                [ S.outlineCurrent
                , S.textGray5
                , S.opacity 1
                ]
            , Css.Media.withMediaQuery [ "(pointer: coarse)" ]
                [ S.w11
                , S.h11
                ]
            ]
        ]
        [ icon options.mute ]


icon : MuteState -> Svg msg
icon mute =
    let
        sound : List (Svg msg)
        sound =
            case mute of
                Muted ->
                    [ Svg.path
                        [ SA.d "m16 9 6 6m0-6-6 6" ]
                        []
                    ]

                Unmuted ->
                    [ Svg.path
                        [ SA.d "M15.5 8.5a5 5 0 0 1 0 7m3-10a9 9 0 0 1 0 13" ]
                        []
                    ]

        content : List (Svg msg)
        content =
            Svg.path
                [ SA.d "M11 5 6 9H3v6h3l5 4Z" ]
                []
                :: sound
    in
    Svg.svg
        [ SA.width "18"
        , SA.height "18"
        , SA.viewBox "0 0 24 24"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "1.75"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        , A.attribute "aria-hidden" "true"
        ]
        content
