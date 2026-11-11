module Fightlines.View.Settings exposing
    ( Config
    , Msg(..)
    , Tab(..)
    , dialog
    , dialogHtmlId
    , tabHtmlId
    )

import Audio
import Css
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
    , mobile : Bool
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


scrollEdge : Css.Style
scrollEdge =
    -- The cover scrolls with the content and hides the shadow at the bottom.
    Css.property "background"
        ("linear-gradient("
            ++ S.nightwood3Str
            ++ ", "
            ++ S.nightwood3Str
            ++ ") bottom / 100% 0.75rem no-repeat local, linear-gradient(transparent, "
            ++ S.blackStr
            ++ ") bottom / 100% 0.625rem no-repeat scroll, "
            ++ S.nightwood3Str
        )


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
            let
                gap : Css.Style
                gap =
                    if config.mobile && (tab == Dialogs) then
                        S.g2

                    else
                        S.g4
            in
            Tabs.panel tabs
                tab
                [ H.div
                    [ A.css
                        [ S.when config.mobile
                            (S.batch
                                [ S.hFull
                                , S.overflowAuto
                                , S.indentStrong
                                , scrollEdge
                                , Css.pseudoElement "-webkit-scrollbar"
                                    [ Css.width (Css.rem 0.625) ]
                                , Css.pseudoElement "-webkit-scrollbar-track"
                                    [ S.bgGray1 ]
                                , Css.pseudoElement "-webkit-scrollbar-thumb"
                                    [ S.bgGray3 ]
                                ]
                            )
                        ]
                    ]
                    [ H.div
                        [ A.css
                            [ S.col
                            , gap
                            , S.textGray5
                            , S.when config.mobile S.p3
                            ]
                        ]
                        content
                    ]
                ]

        done : Html Msg
        done =
            H.div
                [ A.css
                    [ S.row
                    , S.flexWrap
                    , S.itemsCenter
                    , S.g3
                    , S.shrink0
                    , S.when (not config.mobile) S.pt3
                    ]
                ]
                [ Button.primary "done" CloseClicked
                    |> Button.toHtml
                ]

        mobileFooter : List (Html Msg)
        mobileFooter =
            if config.mobile then
                [ done ]

            else
                []

        sectionContent : List (Html Msg)
        sectionContent =
            [ Tabs.toHtml tabs
            , H.div
                [ A.css
                    [ S.when config.mobile
                        (S.batch
                            [ Css.property "grid-area" "1 / 2 / 3 / 3"
                            , S.grid
                            , S.gridRows "minmax(0, 1fr)"
                            ]
                        )
                    ]
                ]
                [ panel Dialogs (dialogPreferences config)
                , panel Audio (audioPreferences config)
                ]
            ]
                ++ mobileFooter

        sections : Html Msg
        sections =
            H.div
                [ A.css
                    [ S.grid
                    , S.gridColumns "8rem minmax(0, 1fr)"
                    , S.g4
                    , S.when config.mobile
                        (S.batch
                            [ S.flex1
                            , S.minH0
                            , S.gridRows "minmax(0, 1fr) auto"
                            ]
                        )
                    , S.when (not config.mobile) S.minH88
                    , S.belowWidth 480
                        [ S.gridColumns "6rem minmax(0, 1fr)"
                        , S.g3
                        ]
                    ]
                ]
                sectionContent

        dialogContent : List (Html Msg)
        dialogContent =
            if config.mobile then
                [ sections ]

            else
                [ sections, done ]

        settings : Dialog Msg
        settings =
            Dialog.make dialogHtmlId
                "settings"
                CloseClicked
                dialogContent
                |> Dialog.workspace
    in
    if config.mobile then
        settings

    else
        Dialog.withCloseButton settings


dialogPreferences : Config -> List (Html Msg)
dialogPreferences config =
    [ H.p
        []
        [ H.text "choose which dialogs to skip." ]
    , preference
        { mobile = config.mobile
        , label = "skip turn introductions"
        , description = "go straight to planning when a new turn begins."
        , checked = config.skipIntroduction
        , onCheck = SkipIntroductionChanged
        }
    , preference
        { mobile = config.mobile
        , label = "skip unit loss dialogs"
        , description = "continue playback when a unit is destroyed."
        , checked = config.skipLosses
        , onCheck = SkipLossesChanged
        }
    , preference
        { mobile = config.mobile
        , label = "skip units without orders warning"
        , description = "submit without a reminder. units with no orders hold position."
        , checked = config.skipOrdersWarning
        , onCheck = SkipOrdersWarningChanged
        }
    , H.p
        [ A.css
            [ S.textGray4
            , S.when (not config.mobile) S.mt3
            ]
        ]
        [ H.text "you can also change these using “skip this dialog” during a game." ]
    ]


preference :
    { mobile : Bool
    , label : String
    , description : String
    , checked : Bool
    , onCheck : Bool -> Msg
    }
    -> Html Msg
preference config =
    let
        gap : Css.Style
        gap =
            if config.mobile then
                S.g1

            else
                S.g2
    in
    Checkbox.new
        { label = config.label
        , checked = config.checked
        , onCheck = config.onCheck
        }
        |> Checkbox.toHtml
            [ H.span
                [ A.css
                    [ S.col
                    , gap
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
