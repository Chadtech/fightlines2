module Style exposing
    ( absolute
    , active
    , after
    , animation
    , animationNone
    , appearanceNone
    , aspectRatio
    , backdrop
    , basisFull
    , batch
    , belowHeight
    , belowWidth
    , bgBlack70
    , bgBlue0
    , bgBlue1
    , bgGray0
    , bgGray0_60
    , bgGray1
    , bgGray2
    , bgGray3
    , bgGray4
    , bgGreen1
    , bgNightwood0
    , bgNightwood1
    , bgNightwood2
    , bgNightwood3
    , bgNightwoodGrain
    , bgNone
    , bgRed0
    , bgRed1
    , bgTransparent
    , bgYellow1
    , bgYellow2
    , bgYellow4
    , block
    , blue1Str
    , border
    , border0
    , borderB
    , borderGray2
    , borderGray4
    , borderL
    , borderLg
    , borderNone
    , borderR
    , borderT
    , borderTransparent
    , borderX
    , borderYellow5_20
    , bottom0
    , bottom12
    , bottom16
    , bottom18
    , bottom24
    , bottom4
    , bottom8
    , bottomFull
    , breakSpaces
    , capitalize
    , caretRed1
    , col
    , colReverse
    , colorTransition2
    , containerInlineSize
    , containerSize
    , contentEmpty
    , crosshairCursor
    , cursorPointer
    , d1
    , defaultCursor
    , displayNone
    , evenChildren
    , firstChild
    , fitWithinContainer
    , fixed
    , flex00auto
    , flex1
    , flex1_1_0pct
    , flexP2
    , flexP2_5
    , flexP3
    , flexP4
    , flexP5
    , flexWrap
    , focusVisible
    , fontItalic
    , fontMonospace
    , fontSizeRem
    , fontSizeValue
    , g0p5
    , g1
    , g1p4
    , g2
    , g3
    , g4
    , g8
    , global
    , grabCursor
    , grabbingCursor
    , gray0Str
    , gray3Str
    , gray4Str
    , gray5Str
    , green1Str
    , grid
    , gridCols1
    , gridCols2
    , gridColumnsRem
    , gridRowsRem
    , grow
    , h0
    , h1
    , h11
    , h12
    , h128
    , h128px
    , h16
    , h160Pct
    , h16px
    , h1px
    , h2
    , h2px
    , h3
    , h32
    , h320
    , h4
    , h40
    , h5
    , h6
    , h64
    , h72
    , h75Viewport
    , h7p5
    , h8
    , h80
    , hAuto
    , hFull
    , hFullViewport
    , hViewportInsetRem
    , hideDetailsMarker
    , hover
    , hyphensAuto
    , imageRenderingAuto
    , importantIndent
    , importantOutdent
    , indent
    , indentDark
    , indentStrong
    , inlineBlock
    , inlineCol
    , inlineRow
    , inset0
    , isolate
    , itemsCenter
    , itemsEnd
    , itemsStart
    , justifyCenter
    , justifyEnd
    , justifyItemsCenter
    , justifySpaceAround
    , justifySpaceBetween
    , left0
    , left30Pct
    , left4
    , left50Pct
    , leftNeg128
    , leftValue
    , letterSpacingEm
    , lg
    , lineHeight1
    , link
    , listNone
    , listStyleNone
    , m0
    , m2
    , m4
    , mAuto
    , maxH16
    , maxH18
    , maxH24
    , maxH32
    , maxH40Viewport
    , maxH64
    , maxHContainerInset4
    , maxHViewportInset8
    , maxHViewportInsetRem
    , maxW12
    , maxW120
    , maxW128
    , maxW16
    , maxW160
    , maxW192
    , maxW240
    , maxW256
    , maxW32
    , maxW320
    , maxW64
    , maxW8
    , maxW96
    , maxWContainerInset4
    , maxWFull
    , maxWViewportInsetRem
    , mb1p4
    , mb24
    , mb4
    , md
    , minH0
    , minH14
    , minH24
    , minH32
    , minH36
    , minH76
    , minH96
    , minHFullViewport
    , minW0
    , minW11
    , minW16
    , minW28
    , minW36
    , minW40
    , minW56Clamped
    , minW72
    , minWFitContent
    , mixBlendScreen
    , ml1
    , ml128
    , ml16
    , ml4
    , ml40
    , ml64
    , ml96
    , mlNeg3
    , mr1
    , mr128
    , mr16
    , mr2
    , mr4
    , mr40
    , mr64
    , mr96
    , mrNeg3
    , mt16
    , mt2
    , mt3
    , mt4
    , mx4
    , mx64
    , mx96
    , nightwood2Str
    , nightwood3Str
    , noScrollbar
    , noWrap
    , none
    , notAllowedCursor
    , objectContain
    , opacity
    , opaque
    , outdent
    , outdentDark
    , outdentLeft
    , outdentStrong
    , outdentTopRight
    , outlineCurrent
    , outlineCurrentThick
    , outlineNone
    , outlineOffset3
    , outlineOffsetNeg1
    , outlineOffsetNeg3
    , outlineYellow5
    , outlineYellow5HalfPixel
    , outlineYellow5Thick
    , overflowAuto
    , overflowHidden
    , p0
    , p1
    , p2
    , p2px
    , p3
    , p4
    , paddingRightEm
    , pb0
    , pb128
    , pb16
    , pb2
    , pb24
    , pb32
    , pb4
    , pb48
    , pb96
    , pl16
    , pl2
    , pl4
    , placeContentCenter
    , pointerCursor
    , pointerEventsNone
    , pr1
    , pr16
    , pr2
    , pr3
    , pr4
    , pre
    , pt1
    , pt16
    , pt20
    , pt24
    , pt3
    , pt4
    , px2
    , px3
    , px36
    , px4
    , px6
    , py1
    , py16
    , py2
    , py3
    , py4
    , py6
    , py8
    , red1Str
    , reducedMotion
    , relative
    , right0
    , right1
    , right2
    , right4
    , right5
    , right8
    , rightFull
    , rounded
    , rounded0
    , rounded2
    , rounded2px
    , rounded4
    , rounded6
    , roundedBRNone
    , roundedFull
    , roundedTop
    , row
    , s192
    , s24
    , s6
    , sNeg128
    , selectableListRow
    , selfCenter
    , selfStretch
    , setBgColorVar
    , setPrimaryColorVar
    , shadowMenu
    , shrink0
    , squareBL
    , squareBR
    , tabularNums
    , textAlignCenter
    , textAlignRight
    , textBlue0
    , textBlue1
    , textEllipsis
    , textGray0
    , textGray1
    , textGray2
    , textGray3
    , textGray4
    , textGray5
    , textLeft
    , textNightwood1
    , textPrimary
    , textRed1
    , textYellow4
    , textYellow5
    , textYellow6
    , top0
    , top1
    , top12
    , top16
    , top2
    , top32
    , top4
    , top8
    , topAuto
    , topFull
    , topNeg30Pct
    , topNeg4
    , topValue
    , transform
    , transformOriginTopLeft
    , transformTransition
    , translateXNeg50pct
    , transparent
    , underline
    , uppercase
    , userSelectNone
    , w0
    , w1
    , w104
    , w12
    , w120
    , w128
    , w128px
    , w14
    , w152
    , w16
    , w16px
    , w196
    , w2
    , w20
    , w256
    , w2x
    , w3
    , w30Pct
    , w32
    , w36
    , w4
    , w40
    , w40Pct
    , w48
    , w5
    , w52
    , w6
    , w64
    , w72
    , w7p5
    , w8
    , w96
    , wAuto
    , wFull
    , wFullViewport
    , when
    , whitespacePreWrap
    , widthMinRemVw
    , widthPct
    , widthValue
    , wrapAnywhere
    , yellow1Str
    , yellow5Str
    , z1
    , z2
    , z3
    , z4
    , zoomInCursor
    )

import Css
import Css.Global
import Css.Media
import Css.Value
    exposing
        ( Supported
        , Value
        )


basisFull : Css.Style
basisFull =
    Css.flexBasis (Css.pct 100)


animationNone : Css.Style
animationNone =
    Css.property "animation" "none"


pointerEventsNone : Css.Style
pointerEventsNone =
    Css.property "pointer-events" "none"


justifyItemsCenter : Css.Style
justifyItemsCenter =
    Css.property "justify-items" "center"


gridRowsRem : Int -> Float -> Css.Style
gridRowsRem count size =
    Css.property "grid-template-rows" ("repeat(" ++ String.fromInt count ++ ", " ++ String.fromFloat size ++ "rem)")


gridColumnsRem : Int -> Float -> Css.Style
gridColumnsRem count size =
    Css.property "grid-template-columns" ("repeat(" ++ String.fromInt count ++ ", " ++ String.fromFloat size ++ "rem)")


h11 : Css.Style
h11 =
    Css.height (Css.rem 2.75)


minW11 : Css.Style
minW11 =
    Css.minWidth (Css.rem 2.75)


minW36 : Css.Style
minW36 =
    Css.minWidth s36


belowWidth : Float -> List Css.Style -> Css.Style
belowWidth width styles =
    Css.Media.withMedia [ Css.Media.all [ Css.Media.maxWidth (Css.px width) ] ] styles


h40 : Css.Style
h40 =
    Css.height (Css.rem 10)


h80 : Css.Style
h80 =
    Css.height (Css.rem 20)


maxH18 : Css.Style
maxH18 =
    Css.maxHeight (Css.rem 4.5)


maxH24 : Css.Style
maxH24 =
    Css.maxHeight (Css.rem 6)


w120 : Css.Style
w120 =
    Css.width (Css.rem 30)


global : List Css.Global.Snippet
global =
    [ Css.Global.everything
        [ Css.property "box-sizing" "border-box"
        , Css.margin Css.zero
        , Css.padding Css.zero
        , Css.property "font-size" "inherit"
        , Css.property "font-family" "inherit"
        , Css.fontWeight Css.normal
        , Css.property "text-transform" "lowercase"
        ]
    , Css.Global.selector "html"
        [ Css.fontSize (Css.rem 1)
        , Css.lineHeight (Css.num 1.5)
        , fontMonospace
        ]
    , Css.Global.selector "h1, h2, h3, h4, h5, h6"
        [ textGray3 ]
    ]


link : Css.Style
link =
    Css.batch
        [ Css.property "color" "#8CC8FF"
        , underline
        , Css.property "text-underline-offset" "0.2em"
        , Css.hover [ Css.property "color" "#C4E3FF" ]
        , Css.focus
            [ Css.property "color" "#C4E3FF"
            , Css.property "outline" "1px solid currentColor"
            , Css.property "outline-offset" "2px"
            ]
        ]


nightwood0Str : String
nightwood0Str =
    "#030907"


nightwood1Str : String
nightwood1Str =
    "#071D10"


nightwood2Str : String
nightwood2Str =
    "#082208"


nightwood3Str : String
nightwood3Str =
    "#142909"


blue0Str : String
blue0Str =
    "#175CFE"


blue1Str : String
blue1Str =
    "#0ABAB5"


green1Str : String
green1Str =
    "#4BBF63"


red0Str : String
red0Str =
    "#651A20"


red1Str : String
red1Str =
    "#F21D23"


yellow0Str : String
yellow0Str =
    "#161303"


yellow1Str : String
yellow1Str =
    "#302507"


yellow2Str : String
yellow2Str =
    "#5A4F0E"


yellow3Str : String
yellow3Str =
    "#87772D"


yellow4Str : String
yellow4Str =
    "#B39F4B"


yellow5Str : String
yellow5Str =
    "#E3D34B"


yellow6Str : String
yellow6Str =
    "#F1E9A5"


blackStr : String
blackStr =
    "#000000"


gray0Str : String
gray0Str =
    "#131610"


gray1Str : String
gray1Str =
    "#2C2826"


gray2Str : String
gray2Str =
    "#57524F"


gray3Str : String
gray3Str =
    "#807672"


gray4Str : String
gray4Str =
    "#B0A69A"


gray5Str : String
gray5Str =
    "#E0D6CA"


blackColor :
    Value
        { provides
            | hex : Supported
        }
blackColor =
    Css.hex blackStr


gray0Color :
    Value
        { provides
            | hex : Supported
        }
gray0Color =
    Css.hex gray0Str


gray1Color :
    Value
        { provides
            | hex : Supported
        }
gray1Color =
    Css.hex gray1Str


gray2Color :
    Value
        { provides
            | hex : Supported
        }
gray2Color =
    Css.hex gray2Str


gray3Color :
    Value
        { provides
            | hex : Supported
        }
gray3Color =
    Css.hex gray3Str


gray4Color :
    Value
        { provides
            | hex : Supported
        }
gray4Color =
    Css.hex gray4Str


content2Color :
    Value
        { provides
            | hex : Supported
        }
content2Color =
    Css.hex gray2Str


yellow0Color :
    Value
        { provides
            | hex : Supported
        }
yellow0Color =
    Css.hex yellow0Str


yellow1Color :
    Value
        { provides
            | hex : Supported
        }
yellow1Color =
    Css.hex yellow1Str


yellow2Color :
    Value
        { provides
            | hex : Supported
        }
yellow2Color =
    Css.hex yellow2Str


yellow3Color :
    Value
        { provides
            | hex : Supported
        }
yellow3Color =
    Css.hex yellow3Str


yellow4Color :
    Value
        { provides
            | hex : Supported
        }
yellow4Color =
    Css.hex yellow4Str


borderWidth :
    Value
        { provides
            | px : Supported
        }
borderWidth =
    Css.px 1


indent : Css.Style
indent =
    [ Css.borderLeft3 borderWidth Css.solid gray0Color
    , Css.borderTop3 borderWidth Css.solid gray0Color
    , Css.borderRight3 borderWidth Css.solid content2Color
    , Css.borderBottom3 borderWidth Css.solid content2Color
    ]
        |> Css.batch


indentDark : Css.Style
indentDark =
    [ Css.borderLeft3 borderWidth Css.solid blackColor
    , Css.borderTop3 borderWidth Css.solid blackColor
    , Css.borderRight3 borderWidth Css.solid gray1Color
    , Css.borderBottom3 borderWidth Css.solid gray1Color
    ]
        |> Css.batch


indentStrong : Css.Style
indentStrong =
    [ Css.borderLeft3 borderWidth Css.solid gray0Color
    , Css.borderTop3 borderWidth Css.solid gray0Color
    , Css.borderRight3 borderWidth Css.solid gray3Color
    , Css.borderBottom3 borderWidth Css.solid gray3Color
    ]
        |> Css.batch


outdent : Css.Style
outdent =
    [ Css.borderLeft3 borderWidth Css.solid content2Color
    , Css.borderTop3 borderWidth Css.solid content2Color
    , Css.borderRight3 borderWidth Css.solid gray0Color
    , Css.borderBottom3 borderWidth Css.solid gray0Color
    ]
        |> Css.batch


outdentDark : Css.Style
outdentDark =
    [ Css.borderLeft3 borderWidth Css.solid gray1Color
    , Css.borderTop3 borderWidth Css.solid gray1Color
    , Css.borderRight3 borderWidth Css.solid blackColor
    , Css.borderBottom3 borderWidth Css.solid blackColor
    ]
        |> Css.batch


outdentStrong : Css.Style
outdentStrong =
    [ Css.borderLeft3 borderWidth Css.solid gray3Color
    , Css.borderTop3 borderWidth Css.solid gray3Color
    , Css.borderRight3 borderWidth Css.solid gray0Color
    , Css.borderBottom3 borderWidth Css.solid gray0Color
    ]
        |> Css.batch


outdentLeft : Css.Style
outdentLeft =
    Css.borderLeft3 borderWidth Css.solid content2Color


outdentTopRight : Css.Style
outdentTopRight =
    Css.batch
        [ Css.borderTop3 borderWidth Css.solid content2Color
        , Css.borderRight3 borderWidth Css.solid gray0Color
        ]


importantOutdent : Css.Style
importantOutdent =
    [ Css.borderLeft3 borderWidth Css.solid yellow3Color
    , Css.borderTop3 borderWidth Css.solid yellow3Color
    , Css.borderRight3 borderWidth Css.solid yellow1Color
    , Css.borderBottom3 borderWidth Css.solid yellow1Color
    ]
        |> Css.batch


importantIndent : Css.Style
importantIndent =
    [ Css.borderLeft3 borderWidth Css.solid yellow1Color
    , Css.borderTop3 borderWidth Css.solid yellow1Color
    , Css.borderRight3 borderWidth Css.solid yellow3Color
    , Css.borderBottom3 borderWidth Css.solid yellow3Color
    ]
        |> Css.batch


none : Css.Style
none =
    batch []


batch : List Css.Style -> Css.Style
batch =
    Css.batch


when : Bool -> Css.Style -> Css.Style
when condition style =
    if condition then
        style

    else
        Css.batch []


hover : List Css.Style -> Css.Style
hover =
    Css.hover


transparent : Css.Style
transparent =
    Css.opacity <| Css.num 0


opaque : Css.Style
opaque =
    Css.opacity <| Css.num 1


border : Css.Style
border =
    Css.border2 borderWidth Css.solid


borderLg : Css.Style
borderLg =
    border


border0 : Css.Style
border0 =
    Css.border (Css.px 0)


borderNone : Css.Style
borderNone =
    Css.borderStyle Css.none


borderGray2 : Css.Style
borderGray2 =
    Css.borderColor gray2Color


borderGray4 : Css.Style
borderGray4 =
    Css.borderColor gray4Color


borderT : Css.Style
borderT =
    Css.borderTop2 borderWidth Css.solid


borderB : Css.Style
borderB =
    Css.borderBottom2 borderWidth Css.solid


borderR : Css.Style
borderR =
    Css.borderRight2 borderWidth Css.solid


borderL : Css.Style
borderL =
    Css.borderLeft2 borderWidth Css.solid


borderX : Css.Style
borderX =
    batch
        [ borderL
        , borderR
        ]


roundingSize :
    Value
        { provides
            | rem : Supported
        }
roundingSize =
    Css.rem 0.375


rounded : Css.Style
rounded =
    Css.borderRadius roundingSize


userSelectNone : Css.Style
userSelectNone =
    Css.property "user-select" "none"


roundedTop : Css.Style
roundedTop =
    Css.batch
        [ Css.borderTopLeftRadius roundingSize
        , Css.borderTopRightRadius roundingSize
        ]


rounded2 : Css.Style
rounded2 =
    Css.borderRadius s2


rounded4 : Css.Style
rounded4 =
    Css.borderRadius s4


rounded6 : Css.Style
rounded6 =
    Css.borderRadius s6


rounded2px : Css.Style
rounded2px =
    Css.borderRadius <| Css.px 2


squareBR : Css.Style
squareBR =
    Css.borderBottomRightRadius Css.zero


squareBL : Css.Style
squareBL =
    Css.borderBottomLeftRadius Css.zero


roundedFull : Css.Style
roundedFull =
    Css.borderRadius (Css.pct 50)


roundedBRNone : Css.Style
roundedBRNone =
    Css.borderBottomRightRadius Css.zero


pointerCursor : Css.Style
pointerCursor =
    Css.cursor Css.pointer


zoomInCursor : Css.Style
zoomInCursor =
    Css.cursor Css.zoomIn


crosshairCursor : Css.Style
crosshairCursor =
    Css.cursor Css.crosshair


defaultCursor : Css.Style
defaultCursor =
    Css.cursor Css.default_


borderBox : Css.Style
borderBox =
    Css.boxSizing Css.borderBox


w0 : Css.Style
w0 =
    Css.width Css.zero


w16px : Css.Style
w16px =
    Css.width <| Css.px 16


w1 : Css.Style
w1 =
    Css.width s1


w2 : Css.Style
w2 =
    Css.width s2


w3 : Css.Style
w3 =
    Css.width s3


w4 : Css.Style
w4 =
    Css.width s4


w5 : Css.Style
w5 =
    Css.width s5


w6 : Css.Style
w6 =
    Css.width s6


w8 : Css.Style
w8 =
    Css.width s8


w12 : Css.Style
w12 =
    Css.width s12


w16 : Css.Style
w16 =
    Css.width s16


w20 : Css.Style
w20 =
    Css.width s20


w32 : Css.Style
w32 =
    Css.width s32


w40 : Css.Style
w40 =
    Css.width s40


w48 : Css.Style
w48 =
    Css.width s48


w64 : Css.Style
w64 =
    Css.width s64


w72 : Css.Style
w72 =
    Css.width s72


w128 : Css.Style
w128 =
    Css.width s128


w152 : Css.Style
w152 =
    Css.width (Css.rem 38)


w196 : Css.Style
w196 =
    Css.width s192


wFull : Css.Style
wFull =
    Css.width <| Css.pct 100


w2x : Css.Style
w2x =
    Css.width <| Css.pct 200


wFullViewport : Css.Style
wFullViewport =
    Css.width <| Css.vw 100


maxW8 : Css.Style
maxW8 =
    Css.maxWidth s8


maxW12 : Css.Style
maxW12 =
    Css.maxWidth s12


maxW16 : Css.Style
maxW16 =
    Css.maxWidth s16


maxW32 : Css.Style
maxW32 =
    Css.maxWidth s32


maxW64 : Css.Style
maxW64 =
    Css.maxWidth s64


maxW96 : Css.Style
maxW96 =
    Css.maxWidth s96


maxW128 : Css.Style
maxW128 =
    Css.maxWidth (Css.rem 32)


maxW160 : Css.Style
maxW160 =
    Css.maxWidth (Css.rem 40)


maxWFull : Css.Style
maxWFull =
    Css.maxWidth (Css.pct 100)


selfCenter : Css.Style
selfCenter =
    Css.alignSelf Css.center


maxW192 : Css.Style
maxW192 =
    Css.maxWidth s192


maxW240 : Css.Style
maxW240 =
    Css.maxWidth s240


maxW320 : Css.Style
maxW320 =
    Css.maxWidth s320


{-| Leave a two-rem total gutter above and below viewport-height content.
-}
maxHViewportInset8 : Css.Style
maxHViewportInset8 =
    Css.maxHeight (Css.calc (Css.vh 100) (Css.minus (Css.rem 2)))


maxH64 : Css.Style
maxH64 =
    Css.maxHeight s64


maxH16 : Css.Style
maxH16 =
    Css.maxHeight s16


maxH32 : Css.Style
maxH32 =
    Css.maxHeight s32


h0 : Css.Style
h0 =
    Css.height Css.zero


h1px : Css.Style
h1px =
    Css.height <| Css.px 1


h2px : Css.Style
h2px =
    Css.height <| Css.px 2


h1 : Css.Style
h1 =
    Css.height s1


h16px : Css.Style
h16px =
    Css.height <| Css.px 16


h2 : Css.Style
h2 =
    Css.height s2


h3 : Css.Style
h3 =
    Css.height s3


h4 : Css.Style
h4 =
    Css.height s4


h5 : Css.Style
h5 =
    Css.height s5


h6 : Css.Style
h6 =
    Css.height s6


h8 : Css.Style
h8 =
    Css.height s8


h12 : Css.Style
h12 =
    Css.height s12


h16 : Css.Style
h16 =
    Css.height s16


h32 : Css.Style
h32 =
    Css.height s32


h64 : Css.Style
h64 =
    Css.height s64


h72 : Css.Style
h72 =
    Css.height s72


h128 : Css.Style
h128 =
    Css.height s128


h320 : Css.Style
h320 =
    Css.height s320


hFull : Css.Style
hFull =
    Css.height <| Css.pct 100


hFullViewport : Css.Style
hFullViewport =
    Css.height <| Css.vh 100


h75Viewport : Css.Style
h75Viewport =
    Css.height (Css.vh 75)


hAuto : Css.Style
hAuto =
    Css.height Css.auto


wAuto : Css.Style
wAuto =
    Css.width Css.auto


minH0 : Css.Style
minH0 =
    Css.minHeight Css.zero


minH14 : Css.Style
minH14 =
    Css.minHeight (Css.rem 3.5)


minH32 : Css.Style
minH32 =
    Css.minHeight s32


minH96 : Css.Style
minH96 =
    Css.minHeight s96


minHFullViewport : Css.Style
minHFullViewport =
    Css.minHeight (Css.vh 100)


minW0 : Css.Style
minW0 =
    Css.minWidth Css.zero


minW16 : Css.Style
minW16 =
    Css.minWidth s16


minW40 : Css.Style
minW40 =
    Css.minWidth s40


minW72 : Css.Style
minW72 =
    Css.minWidth s72


flex1_1_0pct : Css.Style
flex1_1_0pct =
    Css.flex3 (Css.num 1) (Css.num 1) (Css.pct 0)


flex00auto : Css.Style
flex00auto =
    Css.property "flex" "0 0 auto"


flex1 : Css.Style
flex1 =
    Css.flex (Css.num 1)


flexP5 : Css.Style
flexP5 =
    Css.property "flex" "0.5"


flexP4 : Css.Style
flexP4 =
    Css.property "flex" "0.4"


flexP3 : Css.Style
flexP3 =
    Css.property "flex" "0.3"


flexP2_5 : Css.Style
flexP2_5 =
    Css.property "flex" "0.25"


flexP2 : Css.Style
flexP2 =
    Css.property "flex" "0.2"


grow : Css.Style
grow =
    Css.property "flex" "1 0 auto"


shrink0 : Css.Style
shrink0 =
    Css.flexShrink <| Css.num 0


breakSpaces : Css.Style
breakSpaces =
    Css.property "white-space" "break-spaces"


row : Css.Style
row =
    Css.batch
        [ Css.display Css.flex_
        , Css.flexDirection Css.row
        ]


grid : Css.Style
grid =
    Css.display Css.grid_


placeContentCenter : Css.Style
placeContentCenter =
    Css.property "place-content" "center"


appearanceNone : Css.Style
appearanceNone =
    Css.property "appearance" "none"


inlineBlock : Css.Style
inlineBlock =
    Css.display Css.inlineBlock


inlineRow : Css.Style
inlineRow =
    Css.batch
        [ Css.display Css.inlineFlex
        , Css.flexDirection Css.row
        ]


inlineCol : Css.Style
inlineCol =
    Css.batch
        [ Css.display Css.inlineFlex
        , Css.flexDirection Css.column
        ]


col : Css.Style
col =
    Css.batch
        [ Css.display Css.flex_
        , Css.flexDirection Css.column
        ]


colReverse : Css.Style
colReverse =
    Css.batch
        [ Css.display Css.flex_
        , Css.flexDirection Css.columnReverse
        ]


justifyCenter : Css.Style
justifyCenter =
    Css.justifyContent Css.center


justifyEnd : Css.Style
justifyEnd =
    Css.justifyContent Css.flexEnd


justifySpaceBetween : Css.Style
justifySpaceBetween =
    Css.justifyContent Css.spaceBetween


justifySpaceAround : Css.Style
justifySpaceAround =
    Css.justifyContent Css.spaceAround


itemsStart : Css.Style
itemsStart =
    Css.alignItems Css.flexStart


itemsCenter : Css.Style
itemsCenter =
    Css.alignItems Css.center


cursorPointer : Css.Style
cursorPointer =
    Css.cursor Css.pointer


p0 : Css.Style
p0 =
    Css.padding Css.zero


p2px : Css.Style
p2px =
    Css.padding <| Css.px 2


p1 : Css.Style
p1 =
    Css.padding s1


p2 : Css.Style
p2 =
    Css.padding s2


p3 : Css.Style
p3 =
    Css.padding s3


p4 : Css.Style
p4 =
    Css.padding s4


pb0 : Css.Style
pb0 =
    Css.paddingBottom Css.zero


pb2 : Css.Style
pb2 =
    Css.paddingBottom s2


pb4 : Css.Style
pb4 =
    Css.paddingBottom s4


pb16 : Css.Style
pb16 =
    Css.paddingBottom s16


pb48 : Css.Style
pb48 =
    Css.paddingBottom s48


pb96 : Css.Style
pb96 =
    Css.paddingBottom s96


pb128 : Css.Style
pb128 =
    Css.paddingBottom s128


py16 : Css.Style
py16 =
    Css.batch
        [ Css.paddingTop s16
        , Css.paddingBottom s16
        ]


pt1 : Css.Style
pt1 =
    Css.paddingTop s1


pt4 : Css.Style
pt4 =
    Css.paddingTop s4


pt16 : Css.Style
pt16 =
    Css.paddingTop s16


pt20 : Css.Style
pt20 =
    Css.paddingTop s20


pt24 : Css.Style
pt24 =
    Css.paddingTop s24


pb32 : Css.Style
pb32 =
    Css.paddingBottom s32


pb24 : Css.Style
pb24 =
    Css.paddingBottom s24


pl2 : Css.Style
pl2 =
    Css.paddingLeft s2


pl4 : Css.Style
pl4 =
    Css.paddingLeft s4


pl16 : Css.Style
pl16 =
    Css.paddingLeft s16


px2 : Css.Style
px2 =
    Css.batch
        [ pl2
        , pr2
        ]


px3 : Css.Style
px3 =
    Css.batch
        [ Css.paddingLeft s3
        , Css.paddingRight s3
        ]


px4 : Css.Style
px4 =
    Css.batch
        [ pl4
        , pr4
        ]


px6 : Css.Style
px6 =
    Css.batch
        [ Css.paddingLeft s6
        , Css.paddingRight s6
        ]


px36 : Css.Style
px36 =
    Css.batch
        [ Css.paddingLeft s36
        , Css.paddingRight s36
        ]


py1 : Css.Style
py1 =
    Css.batch
        [ Css.paddingTop s1
        , Css.paddingBottom s1
        ]


py2 : Css.Style
py2 =
    Css.batch
        [ Css.paddingTop s2
        , Css.paddingBottom s2
        ]


py3 : Css.Style
py3 =
    Css.batch
        [ pt3
        , Css.paddingBottom s3
        ]


py4 : Css.Style
py4 =
    Css.batch
        [ Css.paddingTop s4
        , Css.paddingBottom s4
        ]


pt3 : Css.Style
pt3 =
    Css.paddingTop s3


g0p5 : Css.Style
g0p5 =
    Css.property "gap" "0.125rem"


g1 : Css.Style
g1 =
    Css.property "gap" "0.25rem"


g2 : Css.Style
g2 =
    Css.property "gap" "0.5rem"


g3 : Css.Style
g3 =
    Css.property "gap" "0.75rem"


g4 : Css.Style
g4 =
    Css.property "gap" "1rem"


g8 : Css.Style
g8 =
    Css.property "gap" "2rem"


bgNone : Css.Style
bgNone =
    Css.property "background" "none"


bgYellow1 : Css.Style
bgYellow1 =
    Css.property "background" yellow1Str


bgYellow2 : Css.Style
bgYellow2 =
    Css.property "background" yellow2Str


bgYellow4 : Css.Style
bgYellow4 =
    Css.property "background" yellow4Str


bgBlue0 : Css.Style
bgBlue0 =
    Css.property "background" blue0Str


bgBlue1 : Css.Style
bgBlue1 =
    Css.property "background" blue1Str


bgGreen1 : Css.Style
bgGreen1 =
    Css.property "background" green1Str


bgRed1 : Css.Style
bgRed1 =
    Css.property "background" red1Str


bgNightwood0 : Css.Style
bgNightwood0 =
    Css.property "background" nightwood0Str


bgNightwoodGrain : Css.Style
bgNightwoodGrain =
    Css.batch
        [ Css.property "background-color" nightwood0Str
        , Css.property "background-image"
            "radial-gradient(ellipse at 18% 12%, rgba(20, 41, 9, 0.2), transparent 38%), repeating-linear-gradient(96deg, rgba(87, 82, 79, 0.035) 0, rgba(87, 82, 79, 0.035) 1px, transparent 1px, transparent 8px), linear-gradient(145deg, #071d10 0%, #030907 48%, #07150c 100%)"
        ]


bgNightwood1 : Css.Style
bgNightwood1 =
    Css.property "background" nightwood1Str


bgNightwood2 : Css.Style
bgNightwood2 =
    Css.property "background" nightwood2Str


bgNightwood3 : Css.Style
bgNightwood3 =
    Css.property "background" nightwood3Str


bgRed0 : Css.Style
bgRed0 =
    Css.property "background" red0Str


bgBlack70 : Css.Style
bgBlack70 =
    Css.backgroundColor (Css.rgba 0 0 0 0.7)


backdrop : List Css.Style -> Css.Style
backdrop =
    Css.pseudoElement "backdrop"


bgGray0 : Css.Style
bgGray0 =
    Css.property "background" gray0Str


bgGray1 : Css.Style
bgGray1 =
    Css.property "background" gray1Str


bgGray2 : Css.Style
bgGray2 =
    Css.property "background" gray2Str


bgGray3 : Css.Style
bgGray3 =
    Css.property "background" gray3Str


bgGray4 : Css.Style
bgGray4 =
    Css.property "background" gray4Str


textGray0 : Css.Style
textGray0 =
    Css.property "color" gray0Str


textGray1 : Css.Style
textGray1 =
    Css.property "color" gray1Str


textGray2 : Css.Style
textGray2 =
    Css.property "color" gray2Str


textGray3 : Css.Style
textGray3 =
    Css.property "color" gray3Str


textGray4 : Css.Style
textGray4 =
    Css.property "color" gray4Str


textGray5 : Css.Style
textGray5 =
    Css.property "color" gray5Str


textNightwood1 : Css.Style
textNightwood1 =
    Css.property "color" nightwood1Str


textBlue0 : Css.Style
textBlue0 =
    Css.property "color" blue0Str


textBlue1 : Css.Style
textBlue1 =
    Css.property "color" blue1Str


textYellow4 : Css.Style
textYellow4 =
    Css.property "color" yellow4Str


textYellow5 : Css.Style
textYellow5 =
    Css.property "color" yellow5Str


textYellow6 : Css.Style
textYellow6 =
    Css.property "color" yellow6Str


caretRed1 : Css.Style
caretRed1 =
    Css.property "caret-color" red1Str


textRed1 : Css.Style
textRed1 =
    Css.property "color" red1Str


setBgColorVar : String -> Css.Style
setBgColorVar color =
    Css.property "--bg-color" color


setPrimaryColorVar : String -> Css.Style
setPrimaryColorVar color =
    Css.property "--primary-color" color


textPrimary : Css.Style
textPrimary =
    Css.property "color" "var(--primary-color)"


textAlignCenter : Css.Style
textAlignCenter =
    Css.textAlign Css.center


textAlignRight : Css.Style
textAlignRight =
    Css.textAlign Css.right_


textEllipsis : Css.Style
textEllipsis =
    batch
        [ Css.textOverflow Css.ellipsis
        , Css.overflow Css.hidden
        , Css.whiteSpace Css.nowrap
        ]


fontItalic : Css.Style
fontItalic =
    Css.fontStyle Css.italic


fontMonospace : Css.Style
fontMonospace =
    Css.fontFamilyMany
        [ "Ubuntu Mono"
        , "SFMono-Regular"
        , "SF Mono"
        , "Menlo"
        , "Monaco"
        , "Consolas"
        , "Liberation Mono"
        ]
        Css.monospace


uppercase : Css.Style
uppercase =
    Css.textTransform Css.uppercase


md : List Css.Style -> Css.Style
md =
    Css.Media.withMediaQuery [ "(min-width: 768px)" ]


lg : List Css.Style -> Css.Style
lg =
    Css.Media.withMediaQuery [ "(min-width: 1156px)" ]


pr1 : Css.Style
pr1 =
    Css.paddingRight s1


pr2 : Css.Style
pr2 =
    Css.paddingRight s2


pr3 : Css.Style
pr3 =
    Css.paddingRight s3


pr4 : Css.Style
pr4 =
    Css.paddingRight s4


pr16 : Css.Style
pr16 =
    Css.paddingRight s16


hyphensAuto : Css.Style
hyphensAuto =
    Css.property "hyphens" "auto"


m0 : Css.Style
m0 =
    Css.margin Css.zero


m2 : Css.Style
m2 =
    Css.margin s2


m4 : Css.Style
m4 =
    Css.margin s4


ml1 : Css.Style
ml1 =
    Css.marginLeft s1


ml4 : Css.Style
ml4 =
    Css.marginLeft s4


ml16 : Css.Style
ml16 =
    Css.marginLeft s16


mr1 : Css.Style
mr1 =
    Css.marginRight s1


mr16 : Css.Style
mr16 =
    Css.marginRight s16


mr2 : Css.Style
mr2 =
    Css.marginRight s2


mr4 : Css.Style
mr4 =
    Css.marginRight s4


mr40 : Css.Style
mr40 =
    Css.marginRight s40


ml40 : Css.Style
ml40 =
    Css.marginLeft s40


mr128 : Css.Style
mr128 =
    Css.marginRight s128


ml128 : Css.Style
ml128 =
    Css.marginLeft s128


mr96 : Css.Style
mr96 =
    Css.marginRight s96


ml96 : Css.Style
ml96 =
    Css.marginLeft s96


mx96 : Css.Style
mx96 =
    Css.batch
        [ ml96
        , mr96
        ]


ml64 : Css.Style
ml64 =
    Css.marginLeft s64


mr64 : Css.Style
mr64 =
    Css.marginRight s64


mx64 : Css.Style
mx64 =
    Css.batch
        [ ml64
        , mr64
        ]


mx4 : Css.Style
mx4 =
    Css.batch
        [ Css.marginLeft s4
        , Css.marginRight s4
        ]


mb4 : Css.Style
mb4 =
    Css.marginBottom s4


mb24 : Css.Style
mb24 =
    Css.marginBottom s24


mt3 : Css.Style
mt3 =
    Css.marginBottom s3


mt4 : Css.Style
mt4 =
    Css.marginTop s4


mt16 : Css.Style
mt16 =
    Css.marginTop s16


sNeg4 :
    Value
        { provides
            | rem : Supported
        }
sNeg4 =
    Css.rem -1


sNeg128 :
    Value
        { provides
            | rem : Supported
        }
sNeg128 =
    Css.rem -32


s1 :
    Value
        { provides
            | rem : Supported
        }
s1 =
    Css.rem 0.25


s2 :
    Value
        { provides
            | rem : Supported
        }
s2 =
    Css.rem 0.5


s3 :
    Value
        { provides
            | rem : Supported
        }
s3 =
    Css.rem 0.75


s4 :
    Value
        { provides
            | rem : Supported
        }
s4 =
    Css.rem 1


s5 :
    Value
        { provides
            | rem : Supported
        }
s5 =
    Css.rem 1.25


s6 :
    Value
        { provides
            | rem : Supported
        }
s6 =
    Css.rem 1.5


s8 :
    Value
        { provides
            | rem : Supported
        }
s8 =
    Css.rem 2


s12 :
    Value
        { provides
            | rem : Supported
        }
s12 =
    Css.rem 3


s16 :
    Value
        { provides
            | rem : Supported
        }
s16 =
    Css.rem 4


s20 :
    Value
        { provides
            | rem : Supported
        }
s20 =
    Css.rem 5


s24 :
    Value
        { provides
            | rem : Supported
        }
s24 =
    Css.rem 6


s32 :
    Value
        { provides
            | rem : Supported
        }
s32 =
    Css.rem 8


s36 :
    Value
        { provides
            | rem : Supported
        }
s36 =
    Css.rem 9


s40 :
    Value
        { provides
            | rem : Supported
        }
s40 =
    Css.rem 10


s48 :
    Value
        { provides
            | rem : Supported
        }
s48 =
    Css.rem 12


s64 :
    Value
        { provides
            | rem : Supported
        }
s64 =
    Css.rem 16


s72 :
    Value
        { provides
            | rem : Supported
        }
s72 =
    Css.rem 18


s96 :
    Value
        { provides
            | rem : Supported
        }
s96 =
    Css.rem 24


s128 :
    Value
        { provides
            | rem : Supported
        }
s128 =
    Css.rem 32


s192 :
    Value
        { provides
            | rem : Supported
        }
s192 =
    Css.rem 48


s240 :
    Value
        { provides
            | rem : Supported
        }
s240 =
    Css.rem 60


s320 :
    Value
        { provides
            | rem : Supported
        }
s320 =
    Css.rem 80


fixed : Css.Style
fixed =
    Css.position Css.fixed


absolute : Css.Style
absolute =
    Css.position Css.absolute


relative : Css.Style
relative =
    Css.position Css.relative


rightFull : Css.Style
rightFull =
    Css.right <| Css.pct 100


right0 : Css.Style
right0 =
    Css.right Css.zero


right1 : Css.Style
right1 =
    Css.right s1


right2 : Css.Style
right2 =
    Css.right s2


right4 : Css.Style
right4 =
    Css.right s4


right5 : Css.Style
right5 =
    Css.right s5


right8 : Css.Style
right8 =
    Css.right s8


topNeg4 : Css.Style
topNeg4 =
    Css.top sNeg4


top0 : Css.Style
top0 =
    Css.top Css.zero


top1 : Css.Style
top1 =
    Css.top s1


top2 : Css.Style
top2 =
    Css.top s2


top4 : Css.Style
top4 =
    Css.top s4


top8 : Css.Style
top8 =
    Css.top s8


top12 : Css.Style
top12 =
    Css.top s12


top16 : Css.Style
top16 =
    Css.top s16


top32 : Css.Style
top32 =
    Css.top s32


topFull : Css.Style
topFull =
    Css.top <| Css.pct 100


bottomFull : Css.Style
bottomFull =
    Css.bottom <| Css.pct 100


bottom0 : Css.Style
bottom0 =
    Css.bottom Css.zero


bottom4 : Css.Style
bottom4 =
    Css.bottom s4


bottom8 : Css.Style
bottom8 =
    Css.bottom s8


bottom12 : Css.Style
bottom12 =
    Css.bottom s12


bottom16 : Css.Style
bottom16 =
    Css.bottom s16


bottom24 : Css.Style
bottom24 =
    Css.bottom s24


left0 : Css.Style
left0 =
    Css.left Css.zero


leftNeg128 : Css.Style
leftNeg128 =
    Css.left sNeg128


left4 : Css.Style
left4 =
    Css.left s4


left50Pct : Css.Style
left50Pct =
    Css.left <| Css.pct 50


z1 : Css.Style
z1 =
    Css.zIndex (Css.int 10)


z2 : Css.Style
z2 =
    Css.zIndex (Css.int 20)


z3 : Css.Style
z3 =
    Css.zIndex (Css.int 30)


d1 : Float
d1 =
    100


translateXNeg50pct : Css.Style
translateXNeg50pct =
    Css.transform <| Css.translateX <| Css.pct -50


colorTransition2 : Css.Style
colorTransition2 =
    Css.property "transition" "color 0.2s ease-in-out"


wrapAnywhere : Css.Style
wrapAnywhere =
    Css.property "overflow-wrap" "anywhere"


overflowAuto : Css.Style
overflowAuto =
    Css.overflow Css.auto


noScrollbar : Css.Style
noScrollbar =
    Css.property "scrollbar-width" "none"


overflowHidden : Css.Style
overflowHidden =
    Css.overflow Css.hidden


outlineNone : Css.Style
outlineNone =
    Css.outline Css.none


textLeft : Css.Style
textLeft =
    Css.textAlign Css.left_


displayNone : Css.Style
displayNone =
    Css.display Css.none


block : Css.Style
block =
    Css.display Css.block


listNone : Css.Style
listNone =
    listStyleNone


listStyleNone : Css.Style
listStyleNone =
    Css.property "list-style" "none"


whitespacePreWrap : Css.Style
whitespacePreWrap =
    Css.whiteSpace Css.preWrap


pre : Css.Style
pre =
    Css.whiteSpace Css.pre


noWrap : Css.Style
noWrap =
    Css.whiteSpace Css.nowrap


underline : Css.Style
underline =
    Css.textDecoration Css.underline


capitalize : Css.Style
capitalize =
    Css.textTransform Css.capitalize


flexWrap : Css.Style
flexWrap =
    Css.flexWrap Css.wrap


selectableListRow : Int -> Css.Style
selectableListRow index =
    let
        background : Css.Style
        background =
            if modBy 2 index == 0 then
                bgNightwood0

            else
                bgNightwood1
    in
    batch
        [ background
        , p2
        , wrapAnywhere
        , pointerCursor
        , Css.hover
            [ bgNightwood3
            , textGray5
            ]
        , Css.focus
            [ bgNightwood3
            , textGray5
            ]
        ]


z4 : Css.Style
z4 =
    Css.zIndex (Css.int 40)


transformOriginTopLeft : Css.Style
transformOriginTopLeft =
    Css.property "transform-origin" "top left"


aspectRatio : { width : Int, height : Int } -> Css.Style
aspectRatio ratio =
    Css.property "aspect-ratio"
        (String.fromInt ratio.width ++ " / " ++ String.fromInt ratio.height)


shadowMenu : Css.Style
shadowMenu =
    Css.property "box-shadow" "3px 5px 0 rgba(0, 0, 0, 0.3)"


objectContain : Css.Style
objectContain =
    Css.objectFit Css.contain_


grabbingCursor : Css.Style
grabbingCursor =
    Css.cursor Css.grabbing


grabCursor : Css.Style
grabCursor =
    Css.cursor Css.grab


notAllowedCursor : Css.Style
notAllowedCursor =
    Css.cursor Css.notAllowed


containerSize : Css.Style
containerSize =
    Css.property "container-type" "size"


containerInlineSize : Css.Style
containerInlineSize =
    Css.property "container-type" "inline-size"


selfStretch : Css.Style
selfStretch =
    Css.alignSelf Css.stretch


isolate : Css.Style
isolate =
    Css.property "isolation" "isolate"


contentEmpty : Css.Style
contentEmpty =
    Css.property "content" "''"


inset0 : Css.Style
inset0 =
    Css.property "inset" "0"


mixBlendScreen : Css.Style
mixBlendScreen =
    Css.property "mix-blend-mode" "screen"


lineHeight1 : Css.Style
lineHeight1 =
    Css.lineHeight (Css.num 1)


gridCols2 : Css.Style
gridCols2 =
    Css.property "grid-template-columns" "repeat(2, minmax(0, 1fr))"


gridCols1 : Css.Style
gridCols1 =
    Css.property "grid-template-columns" "1fr"


mAuto : Css.Style
mAuto =
    Css.margin Css.auto


topAuto : Css.Style
topAuto =
    Css.top Css.auto


bgTransparent : Css.Style
bgTransparent =
    Css.backgroundColor Css.transparent


borderTransparent : Css.Style
borderTransparent =
    Css.border3 (Css.px 1) Css.solid (Css.rgba 0 0 0 0)


outlineCurrent : Css.Style
outlineCurrent =
    Css.outline3 (Css.px 1) Css.solid Css.currentcolor


outlineYellow5 : Css.Style
outlineYellow5 =
    Css.outline3 (Css.px 1) Css.solid (Css.hex yellow5Str)


outlineYellow5Thick : Css.Style
outlineYellow5Thick =
    Css.property "outline" ("2px solid " ++ yellow5Str)


outlineYellow5HalfPixel : Css.Style
outlineYellow5HalfPixel =
    Css.property "outline" ("0.5px solid " ++ yellow5Str)


outlineCurrentThick : Css.Style
outlineCurrentThick =
    Css.property "outline" "2px solid currentColor"


outlineOffset3 : Css.Style
outlineOffset3 =
    Css.property "outline-offset" "3px"


outlineOffsetNeg1 : Css.Style
outlineOffsetNeg1 =
    Css.property "outline-offset" "-1px"


outlineOffsetNeg3 : Css.Style
outlineOffsetNeg3 =
    Css.outlineOffset (Css.px -3)


rounded0 : Css.Style
rounded0 =
    Css.property "border-radius" "0"


imageRenderingAuto : Css.Style
imageRenderingAuto =
    Css.property "image-rendering" "auto"


mt2 : Css.Style
mt2 =
    Css.marginTop (Css.rem 0.5)


mlNeg3 : Css.Style
mlNeg3 =
    Css.marginLeft (Css.rem -0.75)


mrNeg3 : Css.Style
mrNeg3 =
    Css.marginRight (Css.rem -0.75)


mb1p4 : Css.Style
mb1p4 =
    Css.marginBottom (Css.rem 0.35)


g1p4 : Css.Style
g1p4 =
    Css.property "gap" ".35rem"


tabularNums : Css.Style
tabularNums =
    Css.property "font-variant-numeric" "tabular-nums"


w128px : Css.Style
w128px =
    Css.width (Css.px 128)


h128px : Css.Style
h128px =
    Css.height (Css.px 128)


w7p5 : Css.Style
w7p5 =
    Css.width (Css.rem 1.875)


h7p5 : Css.Style
h7p5 =
    Css.height (Css.rem 1.875)


w52 : Css.Style
w52 =
    Css.width (Css.rem 13)


w36 : Css.Style
w36 =
    Css.width (Css.rem 9)


w104 : Css.Style
w104 =
    Css.width (Css.rem 26)


w96 : Css.Style
w96 =
    Css.width (Css.rem 24)


maxW120 : Css.Style
maxW120 =
    Css.maxWidth (Css.rem 30)


minW28 : Css.Style
minW28 =
    Css.minWidth (Css.rem 7)


w14 : Css.Style
w14 =
    Css.width (Css.rem 3.5)


h160Pct : Css.Style
h160Pct =
    Css.height (Css.pct 160)


left30Pct : Css.Style
left30Pct =
    Css.left (Css.pct 30)


topNeg30Pct : Css.Style
topNeg30Pct =
    Css.top (Css.pct -30)


w30Pct : Css.Style
w30Pct =
    Css.width (Css.pct 30)


w40Pct : Css.Style
w40Pct =
    Css.width (Css.pct 40)


minH76 : Css.Style
minH76 =
    Css.minHeight (Css.rem 19)


minH36 : Css.Style
minH36 =
    Css.minHeight (Css.rem 9)


minH24 : Css.Style
minH24 =
    Css.minHeight (Css.rem 6)


minW56Clamped : Css.Style
minW56Clamped =
    Css.property "min-width" "min(14rem, 100%)"


maxWContainerInset4 : Css.Style
maxWContainerInset4 =
    Css.property "max-width" "calc(100cqw - 1rem)"


maxHContainerInset4 : Css.Style
maxHContainerInset4 =
    Css.property "max-height" "calc(100cqh - 1rem)"


py6 : Css.Style
py6 =
    Css.batch [ Css.paddingTop (Css.rem 1.5), Css.paddingBottom (Css.rem 1.5) ]


py8 : Css.Style
py8 =
    Css.batch [ Css.paddingTop (Css.rem 2), Css.paddingBottom (Css.rem 2) ]


opacity : Float -> Css.Style
opacity value =
    Css.opacity (Css.num value)


widthPct : Float -> Css.Style
widthPct value =
    Css.width (Css.pct value)


maxHViewportInsetRem : Float -> Css.Style
maxHViewportInsetRem inset =
    Css.maxHeight (Css.calc (Css.vh 100) (Css.minus (Css.rem inset)))


maxWViewportInsetRem : Float -> Css.Style
maxWViewportInsetRem inset =
    Css.maxWidth (Css.calc (Css.vw 100) (Css.minus (Css.rem inset)))


widthMinRemVw : Float -> Float -> Css.Style
widthMinRemVw width viewportWidth =
    Css.property "width" ("min(" ++ String.fromFloat width ++ "rem, " ++ String.fromFloat viewportWidth ++ "vw)")


widthValue : String -> Css.Style
widthValue value =
    Css.property "width" value


leftValue : String -> Css.Style
leftValue value =
    Css.property "left" value


topValue : String -> Css.Style
topValue value =
    Css.property "top" value


transform : String -> Css.Style
transform value =
    Css.property "transform" value


focusVisible : List Css.Style -> Css.Style
focusVisible styles =
    Css.pseudoClass "focus-visible" styles


reducedMotion : List Css.Style -> Css.Style
reducedMotion styles =
    Css.Media.withMediaQuery [ "(prefers-reduced-motion: reduce)" ] styles


w256 : Css.Style
w256 =
    Css.width (Css.rem 64)


maxW256 : Css.Style
maxW256 =
    Css.maxWidth (Css.rem 64)


bottom18 : Css.Style
bottom18 =
    Css.bottom (Css.rem 4.5)


bgGray0_60 : Css.Style
bgGray0_60 =
    Css.property "background" (gray0Str ++ "99")


borderYellow5_20 : Css.Style
borderYellow5_20 =
    Css.property "border" ("1px solid " ++ yellow5Str ++ "33")


active : List Css.Style -> Css.Style
active styles =
    Css.active styles


hideDetailsMarker : Css.Style
hideDetailsMarker =
    Css.pseudoElement "-webkit-details-marker" [ displayNone ]


letterSpacingEm : Float -> Css.Style
letterSpacingEm value =
    Css.letterSpacing (Css.em value)


paddingRightEm : Float -> Css.Style
paddingRightEm value =
    Css.paddingRight (Css.em value)


fontSizeRem : Float -> Css.Style
fontSizeRem value =
    Css.fontSize (Css.rem value)


fontSizeValue : String -> Css.Style
fontSizeValue value =
    Css.property "font-size" value


belowHeight : Float -> List Css.Style -> Css.Style
belowHeight height styles =
    Css.Media.withMediaQuery [ "(max-height: " ++ String.fromFloat height ++ "px)" ] styles


animation : String -> Css.Style
animation value =
    Css.property "animation" value


after : List Css.Style -> Css.Style
after styles =
    Css.after styles


evenChildren : List Css.Style -> Css.Style
evenChildren styles =
    Css.pseudoClass "nth-child(even)" styles


firstChild : List Css.Style -> Css.Style
firstChild styles =
    Css.firstChild styles


itemsEnd : Css.Style
itemsEnd =
    Css.alignItems Css.flexEnd


minWFitContent : Css.Style
minWFitContent =
    Css.property "min-width" "fit-content"


fitWithinContainer : { width : Int, height : Int } -> Css.Style
fitWithinContainer ratio =
    Css.batch
        [ Css.property "width"
            ("min(100cqw, calc(100cqh * "
                ++ String.fromFloat (toFloat ratio.width / toFloat ratio.height)
                ++ "))"
            )
        , Css.height Css.auto
        ]


hViewportInsetRem : Float -> Css.Style
hViewportInsetRem inset =
    Css.height (Css.calc (Css.vh 100) (Css.minus (Css.rem inset)))


maxH40Viewport : Css.Style
maxH40Viewport =
    Css.maxHeight (Css.vh 40)


transformTransition : Float -> Css.Style
transformTransition milliseconds =
    Css.property "transition" ("transform " ++ String.fromFloat milliseconds ++ "ms ease-in-out")
