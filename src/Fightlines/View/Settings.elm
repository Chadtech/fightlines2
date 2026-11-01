module Fightlines.View.Settings exposing
    ( Config
    , Msg(..)
    , Tab(..)
    , dialog
    , dialogHtmlId
    , tabHtmlId
    )

import Audio
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import NonEmptyList
import Style as S
import View.Button as Button
import View.Checkbox as Checkbox
import View.Dialog as Dialog exposing (Dialog)
import View.Range as Range
import View.Tabs as Tabs



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Tab
    = Dialogs
    | Audio


type Msg
    = CloseClicked
    | TabClicked Tab
    | TabNavigationPressed Tab
    | SkipIntroductionChanged Bool
    | SkipLossesChanged Bool
    | SkipOrdersWarningChanged Bool
    | MuteChanged Bool
    | VolumeChanged Audio.Channel Float


type alias Config =
    { tab : Tab
    , skipIntroduction : Bool
    , skipLosses : Bool
    , skipOrdersWarning : Bool
    , mute : Audio.MuteState
    , volumes : Audio.Volumes
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


dialogHtmlId : String
dialogHtmlId =
    "settings"


tabHtmlId : Tab -> String
tabHtmlId tab =
    case tab of
        Dialogs ->
            "settings-dialogs-tab"

        Audio ->
            "settings-audio-tab"


dialog : Config -> Dialog Msg
dialog config =
    let
        tabs : Tabs.Tabs Tab Msg
        tabs =
            Tabs.new
                { label = "settings sections"
                , selected = config.tab
                , options =
                    NonEmptyList.fromCons
                        { value = Dialogs
                        , label = "dialogs"
                        }
                        [ { value = Audio
                          , label = "audio"
                          }
                        ]
                , htmlId = tabHtmlId
                , onClick = TabClicked
                , onNavigate = TabNavigationPressed
                }

        panel : Tab -> List (Html Msg) -> Html Msg
        panel tab content =
            Tabs.panel tabs
                tab
                [ H.div
                    [ A.css
                        [ S.col
                        , S.g4
                        , S.textGray5
                        ]
                    ]
                    content
                ]
    in
    Dialog.make dialogHtmlId
        "settings"
        CloseClicked
        [ H.div
            [ A.css
                [ S.grid
                , S.gridColumns "8rem minmax(0, 1fr)"
                , S.g4
                , S.minH88
                , S.belowWidth 480
                    [ S.gridColumns "6rem minmax(0, 1fr)"
                    , S.g3
                    ]
                ]
            ]
            [ tabs
                |> Tabs.toHtml
            , panel Dialogs (dialogPreferences config)
            , panel Audio (audioPreferences config)
            ]
        , H.div
            [ A.css
                [ S.row
                , S.flexWrap
                , S.itemsCenter
                , S.justifySpaceBetween
                , S.g3
                , S.pt3
                ]
            ]
            [ H.span
                []
                [ H.text "saved on this device" ]
            , Button.primary "done" CloseClicked
                |> Button.toHtml
            ]
        ]
        |> Dialog.workspace
        |> Dialog.withCloseButton


dialogPreferences : Config -> List (Html Msg)
dialogPreferences config =
    [ H.p
        []
        [ H.text "choose which dialogs to skip." ]
    , preference
        { label = "skip turn introductions"
        , description = "go straight to planning when a new turn begins."
        , checked = config.skipIntroduction
        , onCheck = SkipIntroductionChanged
        }
    , preference
        { label = "skip unit loss dialogs"
        , description = "continue playback when a unit is destroyed."
        , checked = config.skipLosses
        , onCheck = SkipLossesChanged
        }
    , preference
        { label = "skip units without orders warning"
        , description = "submit without a reminder. units with no orders hold position."
        , checked = config.skipOrdersWarning
        , onCheck = SkipOrdersWarningChanged
        }
    , H.p
        [ A.css
            [ S.textGray4
            , S.mt3
            ]
        ]
        [ H.text "you can also change these using “skip this dialog” during a game." ]
    ]


preference :
    { label : String
    , description : String
    , checked : Bool
    , onCheck : Bool -> Msg
    }
    -> Html Msg
preference config =
    Checkbox.new
        { label = config.label
        , checked = config.checked
        , onCheck = config.onCheck
        }
        |> Checkbox.toHtml
            [ H.span
                [ A.css
                    [ S.col
                    , S.g2
                    ]
                ]
                [ H.span
                    []
                    [ H.text config.label ]
                , H.span
                    [ A.css
                        [ S.textGray4
                        ]
                    ]
                    [ H.text config.description ]
                ]
            ]


audioPreferences : Config -> List (Html Msg)
audioPreferences config =
    [ Checkbox.new
        { label = "mute all audio"
        , checked = config.mute == Audio.Muted
        , onCheck = MuteChanged
        }
        |> Checkbox.toHtml
            [ H.text "mute all audio" ]
    , H.fieldset
        [ A.disabled (config.mute == Audio.Muted)
        , A.css
            [ S.col
            , S.g4
            , S.minW0
            , S.p0
            , S.m0
            , S.border0
            , S.when (config.mute == Audio.Muted) (S.opacity 0.5)
            ]
        ]
        [ volumeControl config.volumes Audio.Master "master volume"
        , volumeControl config.volumes Audio.Combat "combat"
        , volumeControl config.volumes Audio.Movement "movement"
        , volumeControl config.volumes Audio.Environment "ambience"
        , volumeControl config.volumes Audio.Interface "interface"
        ]
    ]


volumeControl : Audio.Volumes -> Audio.Channel -> String -> Html Msg
volumeControl volumes channel label =
    Range.toHtml
        { htmlId = "settings-volume-" ++ String.replace " " "-" label
        , label = label
        , value = Audio.channelVolume channel volumes
        , minimum = 0
        , maximum = 100
        , onChange = VolumeChanged channel
        }
