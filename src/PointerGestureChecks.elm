port module PointerGestureChecks exposing (main)

import Browser.Dom
import Game.BattlefieldNavigation as Navigation
import Game.View.Battlefield as Battlefield
import Game.View.BattlefieldWorkspace as Workspace
import Json.Decode as Decode
import Json.Encode as Encode
import Platform
import Point exposing (Point)
import PointerGesture


port results : List String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ -> ( (), results checks )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


checks : List String
checks =
    mouseChecks ++ touchChecks ++ browserTouchChecks ++ viewportChecks


mouseChecks : List String
mouseChecks =
    let
        pressed : PointerGesture.PointerGesture
        pressed =
            PointerGesture.press { start = { x = 10, y = 20 }, origin = { x = 100, y = 200 } }

        belowThreshold : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        belowThreshold =
            PointerGesture.move { x = 13, y = 24 } pressed

        panning : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        panning =
            PointerGesture.move { x = 16, y = 20 } pressed

        returned : { gesture : PointerGesture.PointerGesture, offset : Maybe { x : Float, y : Float } }
        returned =
            PointerGesture.move { x = 10, y = 20 } panning.gesture

        released : PointerGesture.PointerGesture
        released =
            PointerGesture.finish panning.gesture

        routePressed : Navigation.Model
        routePressed =
            Navigation.init |> Navigation.press { x = 10, y = 20 }

        routeDragged : Navigation.Model
        routeDragged =
            routePressed
                |> Navigation.update Navigation.TraceRoute
                    (Navigation.MouseMoved
                        { x = 50
                        , y = 20
                        }
                        1
                    )

        routeReleased : Navigation.Model
        routeReleased =
            routeDragged
                |> Navigation.update Navigation.TraceRoute
                    (Navigation.MouseReleased
                        { x = 50
                        , y = 20
                        }
                    )

        cameraDragged : Navigation.Model
        cameraDragged =
            routePressed
                |> Navigation.update Navigation.PanCamera
                    (Navigation.MouseMoved
                        { x = 50
                        , y = 30
                        }
                        1
                    )

        cameraReleased : Navigation.Model
        cameraReleased =
            cameraDragged
                |> Navigation.update Navigation.PanCamera
                    (Navigation.MouseReleased
                        { x = 60
                        , y = 40
                        }
                    )

        stopped : Navigation.Model
        stopped =
            cameraDragged
                |> Navigation.update Navigation.PanCamera
                    (Navigation.MouseMoved
                        { x = 100
                        , y = 100
                        }
                        0
                    )

        nextPress : PointerGesture.PointerGesture
        nextPress =
            PointerGesture.press { start = { x = 0, y = 0 }, origin = { x = 106, y = 200 } }
    in
    List.concat
        [ expect "route dragging keeps the camera fixed and suppresses its follow-up click"
            (Navigation.camera routeDragged == Navigation.camera routePressed && Navigation.camera routeReleased == Navigation.camera routePressed && Navigation.suppressesClick routeReleased && not (Navigation.active routeReleased))
        , expect "ordinary dragging pans the camera from its press origin"
            ((Navigation.camera cameraDragged).offset
                == { x = 40
                   , y = 10
                   }
                && Navigation.active cameraDragged
            )
        , expect "release applies the final pan position and suppresses the follow-up click"
            ((Navigation.camera cameraReleased).offset
                == { x = 50
                   , y = 20
                   }
                && Navigation.suppressesClick cameraReleased
                && not (Navigation.active cameraReleased)
            )
        , expect "losing mouse buttons ends panning without applying hover movement"
            (Navigation.camera stopped == Navigation.camera cameraDragged && not (Navigation.active stopped) && Navigation.suppressesClick stopped)
        , expect "an ordinary press is active and permits clicks"
            (PointerGesture.active pressed && not (PointerGesture.suppressesClick pressed))
        , expect "movement below six pixels must not pan or suppress a click"
            (belowThreshold.gesture == pressed && belowThreshold.offset == Nothing)
        , expect "six pixels must start panning relative to the camera origin"
            (PointerGesture.active panning.gesture && PointerGesture.suppressesClick panning.gesture && panning.offset == Just { x = 106, y = 200 })
        , expect "a diagonal movement crossing six pixels must start panning"
            (PointerGesture.suppressesClick (PointerGesture.move { x = 15, y = 24 } pressed).gesture)
        , expect "returning to the press position must remain panning and suppress clicks"
            (PointerGesture.suppressesClick returned.gesture && returned.offset == Just { x = 100, y = 200 })
        , expect "release, lost buttons, visibility change, and zoom must stop panning but retain click suppression"
            (not (PointerGesture.active released) && PointerGesture.suppressesClick released && PointerGesture.finish released == released)
        , expect "ending an ordinary press must permit selection"
            (PointerGesture.finish belowThreshold.gesture == PointerGesture.idle)
        , expect "a release position crossing the threshold must still suppress the subsequent click"
            (PointerGesture.suppressesClick (PointerGesture.finish (PointerGesture.move { x = 16, y = 20 } pressed).gesture))
        , expect "a fresh press must clear previous click suppression"
            (PointerGesture.active nextPress && not (PointerGesture.suppressesClick nextPress))
        , expect "reset must stop the gesture and permit clicks"
            (not (PointerGesture.active PointerGesture.idle) && not (PointerGesture.suppressesClick PointerGesture.idle))
        , expect "movement without an active press must not change the camera or suppression"
            ((PointerGesture.move { x = 500, y = 500 } released).offset == Nothing && (PointerGesture.move { x = 500, y = 500 } released).gesture == released && (PointerGesture.move { x = 500, y = 500 } PointerGesture.idle).gesture == PointerGesture.idle)
        ]


expect : String -> Bool -> List String
expect label condition =
    if condition then
        []

    else
        [ label ]


touchChecks : List String
touchChecks =
    let
        started : Navigation.Model
        started =
            Navigation.touch (Navigation.TouchStarted [ { x = 10, y = 20 } ]) Navigation.init

        tapped : Navigation.Model
        tapped =
            started
                |> Navigation.touch (Navigation.TouchMoved [ { x = 12, y = 22 } ])
                |> Navigation.touch (Navigation.TouchEnded { remaining = [], released = [ { x = 12, y = 22 } ] })

        dragged : Navigation.Model
        dragged =
            started
                |> Navigation.touch (Navigation.TouchMoved [ { x = 50, y = 30 } ])
                |> Navigation.touch (Navigation.TouchEnded { remaining = [], released = [ { x = 60, y = 40 } ] })

        pinching : Navigation.Model
        pinching =
            Navigation.init
                |> Navigation.touch (Navigation.TouchStarted [ { x = -50, y = 0 }, { x = 50, y = 0 } ])
                |> Navigation.touch (Navigation.TouchMoved [ { x = -90, y = 10 }, { x = 110, y = 10 } ])

        fingerRemaining : Navigation.Model
        fingerRemaining =
            pinching
                |> Navigation.touch (Navigation.TouchEnded { remaining = [ { x = -90, y = 10 } ], released = [ { x = 110, y = 10 } ] })
                |> Navigation.touch (Navigation.TouchMoved [ { x = 200, y = 100 } ])

        pinchEnded : Navigation.Model
        pinchEnded =
            fingerRemaining
                |> Navigation.touch (Navigation.TouchEnded { remaining = [], released = [ { x = 200, y = 100 } ] })

        recontacted : Navigation.Model
        recontacted =
            fingerRemaining
                |> Navigation.touch (Navigation.TouchStarted [ { x = 200, y = 100 }, { x = 300, y = 100 } ])
                |> Navigation.touch (Navigation.TouchMoved [ { x = 100, y = 100 }, { x = 400, y = 100 } ])

        mouseDuringTouch : Navigation.Model
        mouseDuringTouch =
            started
                |> Navigation.update Navigation.PanCamera (Navigation.MouseMoved { x = 100, y = 100 } 0)
                |> Navigation.update Navigation.PanCamera (Navigation.MouseReleased { x = 100, y = 100 })

        freshTap : Navigation.Model
        freshTap =
            pinchEnded
                |> Navigation.touch (Navigation.TouchStarted [ { x = 10, y = 20 } ])
                |> Navigation.touch (Navigation.TouchEnded { remaining = [], released = [ { x = 10, y = 20 } ] })

        cancelled : Navigation.Model
        cancelled =
            started |> Navigation.touch Navigation.TouchCancelled

        touchEvent : String
        touchEvent =
            """{
                "type": "touchstart",
                "currentTarget": { "clientWidth": 400, "clientHeight": 600 },
                "touches": {
                    "0": { "clientX": 100, "clientY": 200, "target": { "id": "battlefield-navigation" } },
                    "1": { "clientX": 300, "clientY": 400, "target": { "id": "battlefield-navigation" } },
                    "length": 2
                }
            }"""
    in
    List.concat
        [ expect "touch tap and small finger jitter permit activation without moving the map"
            (Navigation.camera tapped == Navigation.camera Navigation.init && not (Navigation.suppressesClick tapped) && not (Navigation.active tapped))
        , expect "touch dragging includes the final release position and suppresses activation"
            ((Navigation.camera dragged).offset == { x = 50, y = 20 } && Navigation.suppressesClick dragged && not (Navigation.active dragged))
        , expect "pinching scales the map around the fingers and follows their midpoint"
            (Navigation.camera pinching == { offset = { x = 10, y = 10 }, zoom = 2 } && Navigation.suppressesClick pinching)
        , expect "lifting one pinch finger never jumps the camera or turns into a tap"
            (Navigation.camera pinchEnded == Navigation.camera pinching && Navigation.suppressesClick pinchEnded && not (Navigation.active pinchEnded))
        , expect "adding a finger after a partial pinch release still waits for every finger to lift"
            (Navigation.camera recontacted == Navigation.camera fingerRemaining && Navigation.suppressesClick recontacted && Navigation.active recontacted)
        , expect "late mouse messages cannot finish or move an active touch gesture"
            (mouseDuringTouch == started)
        , expect "a fresh tap after a pinch clears click suppression"
            (not (Navigation.suppressesClick freshTap) && Navigation.camera freshTap == Navigation.camera pinchEnded)
        , expect "cancelled touch never activates a tile and leaves navigation stopped"
            (Navigation.suppressesClick cancelled && not (Navigation.active cancelled))
        , expect "touch list decoding handles browser array-like contacts and centers their coordinates"
            (Decode.decodeString Battlefield.touchInputDecoder touchEvent
                == Ok (Navigation.TouchStarted [ { x = -100, y = -100 }, { x = 100, y = 100 } ])
            )
        , expect "native mouse presses still begin map navigation"
            (Decode.decodeString Battlefield.pointerPressedDecoder "{\"pointerType\":\"mouse\",\"button\":0,\"clientX\":10,\"clientY\":20}"
                == Ok (Battlefield.PointerPressed { x = 10, y = 20 })
            )
        , expect "touch pointers and synthetic legacy mouse presses never reset swipe suppression"
            (Result.toMaybe (Decode.decodeString Battlefield.pointerPressedDecoder "{\"pointerType\":\"touch\",\"button\":0,\"clientX\":10,\"clientY\":20}")
                == Nothing
                && (Result.toMaybe (Decode.decodeString Battlefield.pointerPressedDecoder "{\"button\":0,\"clientX\":10,\"clientY\":20}") == Nothing)
            )
        , expect "touch cancellation does not require live target geometry"
            (Decode.decodeString Battlefield.touchInputDecoder "{\"type\":\"touchcancel\"}" == Ok Navigation.TouchCancelled)
        , expect "touch reset clears the active gesture and restores camera and click behavior"
            (Navigation.resetViewport pinching == Navigation.init)
        ]


browserTouchChecks : List String
browserTouchChecks =
    let
        battlefield : Encode.Value
        battlefield =
            Encode.object
                [ ( "id", Encode.string Battlefield.htmlId ) ]

        tile : Encode.Value
        tile =
            Encode.object
                [ ( "id", Encode.string "" )
                , ( "parentElement", battlefield )
                ]

        unit : Encode.Value
        unit =
            Encode.object
                [ ( "id", Encode.string "unit" )
                , ( "parentElement", tile )
                ]

        controls : Encode.Value
        controls =
            Encode.object
                [ ( "id", Encode.string Workspace.controlsHtmlId )
                , ( "parentElement", Encode.null )
                ]

        contact : Encode.Value -> Point -> Encode.Value
        contact target position =
            Encode.object
                [ ( "target", target )
                , ( "clientX", Encode.float (200 + position.x) )
                , ( "clientY", Encode.float (300 + position.y) )
                ]

        first : Encode.Value
        first =
            contact tile { x = -50, y = 0 }

        second : Encode.Value
        second =
            contact unit { x = 50, y = 0 }

        movedFirst : Encode.Value
        movedFirst =
            contact tile { x = -90, y = 10 }

        movedSecond : Encode.Value
        movedSecond =
            contact unit { x = 110, y = 10 }

        outside : Encode.Value
        outside =
            contact controls { x = 180, y = 350 }

        event :
            String
            ->
                { touches : List Encode.Value
                , targetTouches : List Encode.Value
                , changedTouches : List Encode.Value
                }
            -> Encode.Value
        event eventType touches =
            Encode.object
                [ ( "type", Encode.string eventType )
                , ( "currentTarget"
                  , Encode.object
                        [ ( "clientWidth", Encode.int 400 )
                        , ( "clientHeight", Encode.int 600 )
                        ]
                  )
                , ( "touches", Encode.list identity touches.touches )
                , ( "targetTouches", Encode.list identity touches.targetTouches )
                , ( "changedTouches", Encode.list identity touches.changedTouches )
                ]

        applyEvent : Encode.Value -> Result Decode.Error Navigation.Model -> Result Decode.Error Navigation.Model
        applyEvent value result =
            Result.map2 Navigation.touch
                (Decode.decodeValue Battlefield.touchInputDecoder value)
                result

        pinched : Result Decode.Error Navigation.Model
        pinched =
            Ok Navigation.init
                |> applyEvent
                    (event "touchstart"
                        { touches = [ first, outside ]
                        , targetTouches = [ first ]
                        , changedTouches = [ first ]
                        }
                    )
                |> applyEvent
                    (event "touchstart"
                        { touches = [ first, second, outside ]
                        , targetTouches = [ second ]
                        , changedTouches = [ second ]
                        }
                    )
                |> applyEvent
                    (event "touchmove"
                        { touches = [ movedFirst, movedSecond, outside ]
                        , targetTouches = [ movedFirst ]
                        , changedTouches = [ movedFirst, movedSecond ]
                        }
                    )

        oneReleased : Result Decode.Error Navigation.Model
        oneReleased =
            pinched
                |> applyEvent
                    (event "touchend"
                        { touches = [ movedSecond, outside ]
                        , targetTouches = []
                        , changedTouches = [ movedFirst ]
                        }
                    )

        ended : Result Decode.Error Navigation.Model
        ended =
            oneReleased
                |> applyEvent
                    (event "touchend"
                        { touches = [ outside ]
                        , targetTouches = []
                        , changedTouches = [ movedSecond ]
                        }
                    )
    in
    List.concat
        [ expect "fingers on different SVG descendants pinch together, excluding contacts on controls"
            (Result.map Navigation.camera pinched == Ok { offset = { x = 10, y = 10 }, zoom = 2 })
        , expect "lifting one finger from a different target keeps touch navigation active"
            (Result.map Navigation.active oneReleased == Ok True)
        , expect "lifting all battlefield fingers ends navigation even while another contact remains on controls"
            (Result.map Navigation.active ended == Ok False)
        , expect "cross-target pinch release preserves the camera and suppresses tile activation"
            (Result.map Navigation.camera ended == Result.map Navigation.camera pinched && (Result.map Navigation.suppressesClick ended == Ok True))
        ]


viewportChecks : List String
viewportChecks =
    let
        element : { x : Float, y : Float, width : Float, height : Float } -> Browser.Dom.Element
        element bounds =
            { scene = { width = 1000, height = 800 }
            , viewport = { x = 0, y = 0, width = 1000, height = 800 }
            , element = bounds
            }

        desktop : GameViewport
        desktop =
            { battlefield = element { x = 0, y = 0, width = 1000, height = 800 }
            , controls = element { x = 0, y = 680, width = 752, height = 120 }
            , inspector = element { x = 752, y = 0, width = 248, height = 800 }
            }

        landscape : GameViewport
        landscape =
            { battlefield = element { x = 0, y = 0, width = 574, height = 289 }
            , controls = element { x = 0, y = 289, width = 844, height = 101 }
            , inspector = element { x = 574, y = 0, width = 270, height = 289 }
            }

        phone : GameViewport
        phone =
            { battlefield = element { x = 0, y = 0, width = 390, height = 460 }
            , controls = element { x = 0, y = 650, width = 390, height = 150 }
            , inspector = element { x = 0, y = 460, width = 390, height = 190 }
            }
    in
    List.concat
        [ expect "desktop camera insets account for overlaid controls and inspector"
            (Workspace.viewport desktop == { size = { x = 1000, y = 800 }, bottomInset = 120, rightInset = 248 })
        , expect "landscape camera does not subtract an adjacent inspector or reserved turn strip"
            (Workspace.viewport landscape == { size = { x = 574, y = 289 }, bottomInset = 0, rightInset = 0 })
        , expect "phone camera does not subtract panels already outside its map surface"
            (Workspace.viewport phone == { size = { x = 390, y = 460 }, bottomInset = 0, rightInset = 0 })
        ]


type alias GameViewport =
    { battlefield : Browser.Dom.Element
    , controls : Browser.Dom.Element
    , inspector : Browser.Dom.Element
    }
