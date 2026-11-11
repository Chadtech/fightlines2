module Fightlines.View.About exposing
    ( Section(..)
    , all
    , dialog
    , htmlId
    )

import Css.Global
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
import View.Prose as Prose



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Section
    = Game
    | Intro
    | Contact
    | Code
    | Pacifism
    | PrivacyPolicy



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


all : List Section
all =
    [ Game
    , Intro
    , Contact
    , Code
    , Pacifism
    , PrivacyPolicy
    ]


htmlId : String
htmlId =
    "about-fightlines-dialog"


sectionTitle : Section -> String
sectionTitle section =
    case section of
        Game ->
            "the game"

        Intro ->
            "intro"

        Pacifism ->
            "pacifism"

        Contact ->
            "contact"

        Code ->
            "code"

        PrivacyPolicy ->
            "privacy policy"


aboutPhotoSource : String
aboutPhotoSource =
    "assets/creator-portrait.jpg"


aboutPhotoCaption : String
aboutPhotoCaption =
    "me standing next to a statue of George Washington, the general who oversaw the glorious retreat from long island during the American Revolutionary war. Running away is one of my favorite military tactics"



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


dialog : { onClose : msg } -> Dialog msg
dialog events =
    Dialog.make htmlId
        "about fightlines"
        events.onClose
        [ H.div
            [ Aria.label "about fightlines text"
            , A.tabindex 0
            , A.css
                [ S.block
                , S.p3
                , S.bgNightwood3
                , S.indentStrong
                , S.minH0
                , S.overflowAuto
                ]
            ]
            (List.map sectionView all)
        , Button.secondary "close" events.onClose
            |> Button.toHtml
        ]
        |> Dialog.article


creatorPhoto : Html msg
creatorPhoto =
    H.figure
        [ A.css
            [ S.block
            , S.floatLeft
            , S.wFull
            , S.maxW64
            , S.mr4
            , S.mb4
            , S.belowWidth 600
                [ S.floatNone
                , S.m0
                , S.mb4
                ]
            ]
        ]
        [ H.img
            [ A.src aboutPhotoSource
            , A.alt "the creator of fightlines"
            , A.css
                [ S.block
                , S.wFull
                , S.hAuto
                , S.outdent
                ]
            ]
            []
        , H.figcaption
            [ A.css
                [ S.mt2
                , S.fontSizeRem 0.875
                , S.textGray4
                , S.wrapAnywhere
                ]
            ]
            [ H.text aboutPhotoCaption ]
        ]


{-| Fill in each section here. Blank lines separate paragraphs.
-}
sectionBody : Section -> List (Html msg)
sectionBody section =
    case section of
        Game ->
            Prose.paragraphs """fightlines is a turn based strategy game about logistics, supply, and transportation.
command infantry, tanks, field guns, and trucks. both players plan their orders at the same time,
then watch them play out together.

keeping your army supplied is part of the fight. without supplies and fuel, your army will quickly become ineffective
or perish. anticipating where you need to transport supplies is key. use terrain and fog of war to hide your approach,
set ambushes, and cut off enemy supply lines. winning a firefight means little if your army
runs out of supplies and becomes stranded.
"""

        Intro ->
            [ creatorPhoto
            , H.p
                [ A.css
                    [ S.wrapAnywhere
                    ]
                ]
                [ H.text """Hi. Thanks for playing my game. My name is Chad ("Chadtech" online). I am a programmer and father of three.
I made this game for free and I don't have a patreon or any way for you to give me money."""
                ]
            , H.p
                [ A.css
                    [ S.wrapAnywhere
                    ]
                ]
                [ H.text """I'm an arizonan. i got my degree in economics. my favorite philosopher is wittgenstein.
i practice brazilian jiu jitsu. I pretty much believe everything economists """
                , externalLink
                    { label = "bryan caplan"
                    , href = "https://www.betonit.ai/"
                    }
                , H.text " and "
                , externalLink
                    { label = "robin hanson"
                    , href = "https://www.overcomingbias.com/"
                    }
                , H.text " have to say on their blogs."
                ]
            ]

        Contact ->
            [ H.p
                [ A.css
                    [ S.wrapAnywhere
                    ]
                ]
                [ H.text "email me at "
                , externalLink
                    { label = "chadtech0@gmail.com"
                    , href = "mailto:chadtech0@gmail.com"
                    }
                , H.text ". follow me on x dot come at "
                , externalLink
                    { label = "@TheRealChadtech"
                    , href = "https://x.com/TheRealChadtech"
                    }
                , H.text ". my github username is "
                , externalLink
                    { label = "chadtech"
                    , href = "https://github.com/chadtech"
                    }
                ]
            ]

        Code ->
            [ """I made this game using the Elm programming language. I love Elm and have been using it for over a decade. The
backend is written in Rust, another great programming language I really like"""
            ]
                |> List.concatMap Prose.paragraphs

        Pacifism ->
            [ """This is a war game. isn't it interesting how much violence is in media and entertainment despite the fact that
war and violence are really really bad? i mean it's fine to have fun. i don't want to spoil people enjoying violent media, but
it's still striking to me the gap between how exciting violence in the abstract can be with how clearly morally wrong it is.
So i am just going to take this opportunity here, in this obscure part of this website, to share my thoughts.

War is really bad. I don't mean just regrettably bad, as if it was just a difficult struggle, or it was bad but also unfortunately necessary.
I mean it's just bad. A very large majority of all the decisions to take part in a war, even in defense, have been really dumb. In some extreme
circumstances, violence can be justified, like in self defense or the defense of others, or maybe to protect your home or business.
Do wars resemble those cases of self defense? Not at all. Most wars were easily avoidable. Most of the time the horrors of war were
not justified by the cause or the aims of the war. Most of the time, it would be better of either side just gave up and surrendered immediately."""
            ]
                |> List.concatMap Prose.paragraphs

        PrivacyPolicy ->
            Prose.paragraphs """I retain a log of every game, including the chat messages. I use this for debugging, when there are errors
and also so that I can understand people's user experience better and improve the game. I don't record any
other info right now"""


externalLink : { label : String, href : String } -> Html msg
externalLink link =
    H.a
        [ A.href link.href
        , A.target "_blank"
        , A.rel "noopener noreferrer"
        , A.css
            [ S.link
            ]
        ]
        [ H.text link.label ]


sectionView : Section -> Html msg
sectionView section =
    let
        header : Html msg
        header =
            H.h2
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text (sectionTitle section) ]
    in
    H.section
        [ A.css
            [ S.block
            , S.mb4
            , Css.Global.children
                [ Css.Global.selector "p"
                    [ S.mt2
                    ]
                ]
            ]
        ]
        (header :: sectionBody section)
