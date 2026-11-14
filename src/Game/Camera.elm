module Game.Camera exposing
    ( Camera
    , Viewport
    , anchor
    , boardWidth
    , centerOn
    , coordinateAt
    , frame
    , setOffset
    , zoomAt
    )

import Game.Coordinate exposing (Coordinate)
import Game.Map as Map exposing (Map)
import Point exposing (Point)


type alias Camera =
    { offset : Point
    , zoom : Float
    }


{-| Keep the full navigation surface for board scaling. Insets describe
overlays without changing the camera's coordinate system.
-}
type alias Viewport =
    { size : Point
    , bottomInset : Float
    , rightInset : Float
    }


setOffset : Point -> Camera -> Camera
setOffset offset model =
    { model | offset = offset }


{-| Change the zoom while keeping the map point under the anchor fixed.
-}
zoomAt : Point -> Float -> Camera -> Camera
zoomAt anchorPoint zoom camera =
    let
        ratio : Float
        ratio =
            zoom / camera.zoom
    in
    { zoom = zoom
    , offset =
        { x = anchorPoint.x - (anchorPoint.x - camera.offset.x) * ratio
        , y = anchorPoint.y - (anchorPoint.y - camera.offset.y) * ratio
        }
    }


{-| The rendered board width, including the camera's zoom.
-}
boardWidth : Camera -> String
boardWidth camera =
    "calc(" ++ overviewWidth ++ " * " ++ String.fromFloat camera.zoom ++ ")"


overviewWidth : String
overviewWidth =
    "min(92cqw, 98cqh)"


anchor : Camera -> Point -> { x : String, y : String }
anchor camera fraction =
    let
        projected : { x : String, y : String }
        projected =
            displacement camera fraction
    in
    { x = "calc(50cqw + " ++ projected.x ++ ")"
    , y = "calc(50cqh + " ++ projected.y ++ ")"
    }


displacement : Camera -> Point -> { x : String, y : String }
displacement camera fraction =
    let
        axis : Float -> Float -> String
        axis boardFraction offset =
            "calc("
                ++ overviewWidth
                ++ " * "
                ++ String.fromFloat (boardFraction * camera.zoom)
                ++ " + "
                ++ String.fromFloat offset
                ++ "px)"
    in
    { x = axis fraction.x camera.offset.x
    , y = axis fraction.y camera.offset.y
    }


boardPixels : Point -> Float
boardPixels size =
    min (0.92 * size.x) (0.98 * size.y)


{-| Convert a point relative to the navigation surface's center to a map tile.
-}
coordinateAt : Point -> Map -> Camera -> Point -> Maybe Coordinate
coordinateAt size map camera point =
    let
        tilePixels : Float
        tilePixels =
            boardPixels size * camera.zoom / toFloat map.width

        position : Coordinate
        position =
            { x = floor ((point.x - camera.offset.x) / tilePixels + toFloat map.width / 2)
            , y = floor ((point.y - camera.offset.y) / tilePixels + toFloat map.height / 2)
            }

        insideViewport : Bool
        insideViewport =
            (abs point.x < size.x / 2) && (abs point.y < size.y / 2)

        insideMap : Bool
        insideMap =
            (position.x >= 0)
                && (position.x < map.width)
                && (position.y >= 0)
                && (position.y < map.height)
    in
    if insideViewport && insideMap then
        Just position

    else
        Nothing


centerOn : Viewport -> Map -> Coordinate -> Camera -> Camera
centerOn viewport map position camera =
    let
        tilePixels : Float
        tilePixels =
            boardPixels viewport.size * camera.zoom / toFloat map.width
    in
    setOffset
        { x =
            (toFloat map.width / 2 - toFloat position.x - 0.5)
                * tilePixels
                - viewport.rightInset
                / 2
        , y =
            (toFloat map.height / 2 - toFloat position.y - 0.5)
                * tilePixels
                - viewport.bottomInset
                / 2
        }
        camera


{-| Keep the view unless a subject tile is clipped. Reframe with one tile of
breathing room, reducing zoom only when the group cannot fit the viewport.
Viewport dimensions and offsets are in pixels; subject positions are in tiles.
-}
frame : Viewport -> Map -> List Point -> Camera -> Camera
frame viewport map positions camera =
    case positions of
        [] ->
            camera

        first :: rest ->
            let
                bounds : { left : Float, right : Float, top : Float, bottom : Float }
                bounds =
                    List.foldl
                        (\position current ->
                            { left = min current.left position.x
                            , right = max current.right position.x
                            , top = min current.top position.y
                            , bottom = max current.bottom position.y
                            }
                        )
                        { left = first.x, right = first.x, top = first.y, bottom = first.y }
                        rest

                width : Float
                width =
                    toFloat map.width

                widthPixels : Float
                widthPixels =
                    boardPixels viewport.size

                visibleWidth : Float
                visibleWidth =
                    max 1 (viewport.size.x - viewport.rightInset)

                visibleHeight : Float
                visibleHeight =
                    max 1 (viewport.size.y - viewport.bottomInset)

                tilePixels : Float
                tilePixels =
                    widthPixels * camera.zoom / width

                left : Float
                left =
                    (bounds.left - width / 2) * tilePixels + camera.offset.x

                right : Float
                right =
                    (bounds.right + 1 - width / 2) * tilePixels + camera.offset.x

                top : Float
                top =
                    (bounds.top - toFloat map.height / 2) * tilePixels + camera.offset.y

                bottom : Float
                bottom =
                    (bounds.bottom + 1 - toFloat map.height / 2) * tilePixels + camera.offset.y

                zoom : Float
                zoom =
                    min camera.zoom
                        (min
                            (visibleWidth * width / (widthPixels * (bounds.right - bounds.left + 3)))
                            (visibleHeight * width / (widthPixels * (bounds.bottom - bounds.top + 3)))
                        )

                subjectsVisible : Bool
                subjectsVisible =
                    (left >= -viewport.size.x / 2)
                        && (right <= viewport.size.x / 2 - viewport.rightInset)
                        && (top >= -viewport.size.y / 2)
                        && (bottom <= viewport.size.y / 2 - viewport.bottomInset)
            in
            if subjectsVisible then
                camera

            else
                { zoom = zoom
                , offset =
                    { x =
                        -(bounds.left + bounds.right + 1 - width) / 2 * widthPixels * zoom / width - viewport.rightInset / 2
                    , y =
                        -(bounds.top + bounds.bottom + 1 - toFloat map.height) / 2 * widthPixels * zoom / width - viewport.bottomInset / 2
                    }
                }
