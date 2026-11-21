module Game.Camera exposing
    ( Camera
    , Projection(..)
    , Viewport
    , anchor
    , boardTransform
    , boardWidth
    , centerOn
    , coordinateAt
    , frame
    , keepVisible
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


type Projection
    = Overhead
    | Tilted


{-| Keep the full navigation surface for board scaling. Insets describe
overlays without changing the camera's coordinate system.
-}
type alias Viewport =
    { size : Point
    , bottomInset : Float
    , rightInset : Float
    }


type Framing
    = CenterSubjects
    | KeepOffset


type alias Bounds =
    { left : Float
    , right : Float
    , top : Float
    , bottom : Float
    }


includePoint : Point -> Bounds -> Bounds
includePoint point bounds =
    { left = min bounds.left point.x
    , right = max bounds.right point.x
    , top = min bounds.top point.y
    , bottom = max bounds.bottom point.y
    }


boundsAt : Point -> Bounds
boundsAt point =
    { left = point.x
    , right = point.x
    , top = point.y
    , bottom = point.y
    }


projectBounds : Projection -> Map -> Bounds -> Bounds
projectBounds projection map bounds =
    let
        corner : Float -> Float -> Point
        corner x y =
            project projection map { x = x, y = y }
    in
    corner bounds.left bounds.top
        |> boundsAt
        |> includePoint (corner (bounds.right + 1) bounds.top)
        |> includePoint (corner bounds.left (bounds.bottom + 1))
        |> includePoint (corner (bounds.right + 1) (bounds.bottom + 1))


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
boardWidth : Projection -> Map -> Camera -> String
boardWidth projection map camera =
    "calc(" ++ overviewWidth projection map ++ " * " ++ String.fromFloat camera.zoom ++ ")"


{-| The element's width container keeps the perspective proportional to
the board's rendered width, even as the camera animates between zoom levels.
-}
boardTransform : Projection -> Map -> String
boardTransform projection map =
    case projection of
        Overhead ->
            "none"

        Tilted ->
            "perspective("
                ++ String.fromFloat (100 * perspectiveDepth map / toFloat map.width)
                ++ "cqw) rotateX("
                ++ String.fromFloat tiltDegrees
                ++ "deg)"


{-| Get the screen position of a point measured in tiles from the map origin.
-}
anchor :
    Projection
    -> Map
    -> Camera
    -> Point
    -> { x : String, y : String }
anchor projection map camera tile =
    let
        position : Point
        position =
            project projection map tile

        axis : String -> Float -> Float -> String
        axis center tiles offset =
            "calc("
                ++ center
                ++ " + "
                ++ overviewWidth projection map
                ++ " * "
                ++ String.fromFloat (tiles / toFloat map.width * camera.zoom)
                ++ " + "
                ++ String.fromFloat offset
                ++ "px)"
    in
    { x = axis "50cqw" position.x camera.offset.x
    , y = axis "50cqh" position.y camera.offset.y
    }


overviewWidth : Projection -> Map -> String
overviewWidth projection map =
    let
        scale : Point
        scale =
            overviewScale projection map
    in
    "min("
        ++ String.fromFloat (100 * scale.x)
        ++ "cqw, "
        ++ String.fromFloat (100 * scale.y)
        ++ "cqh)"


overviewScale : Projection -> Map -> Point
overviewScale projection map =
    case projection of
        Overhead ->
            { x = 0.92, y = 0.98 }

        Tilted ->
            let
                nearCorner : Point
                nearCorner =
                    project Tilted
                        map
                        { x = toFloat map.width, y = toFloat map.height }

                halfWidth : Float
                halfWidth =
                    toFloat map.width / 2
            in
            { x = 0.92 * halfWidth / max halfWidth nearCorner.x
            , y = 0.98 * halfWidth / max halfWidth nearCorner.y
            }


boardPixels : Projection -> Map -> Point -> Float
boardPixels projection map size =
    let
        scale : Point
        scale =
            overviewScale projection map
    in
    min (scale.x * size.x) (scale.y * size.y)


tiltDegrees : Float
tiltDegrees =
    10


perspectiveDepth : Map -> Float
perspectiveDepth map =
    2 * toFloat (max map.width map.height)


{-| Apply the CSS perspective transform in tile units around the board's center.
-}
project : Projection -> Map -> Point -> Point
project projection map tile =
    let
        x : Float
        x =
            tile.x - toFloat map.width / 2

        y : Float
        y =
            tile.y - toFloat map.height / 2
    in
    case projection of
        Overhead ->
            { x = x, y = y }

        Tilted ->
            let
                scale : Float
                scale =
                    1 - y * sin (degrees tiltDegrees) / perspectiveDepth map
            in
            { x = x / scale
            , y = y * cos (degrees tiltDegrees) / scale
            }


unproject : Projection -> Map -> Point -> Point
unproject projection map point =
    let
        centered : Point
        centered =
            case projection of
                Overhead ->
                    point

                Tilted ->
                    let
                        angle : Float
                        angle =
                            degrees tiltDegrees

                        y : Float
                        y =
                            point.y / (cos angle + point.y * sin angle / perspectiveDepth map)
                    in
                    { x = point.x * (1 - y * sin angle / perspectiveDepth map)
                    , y = y
                    }
    in
    { x = centered.x + toFloat map.width / 2
    , y = centered.y + toFloat map.height / 2
    }


{-| Convert a point relative to the navigation surface's center to a map tile.
-}
coordinateAt :
    Projection
    -> Point
    -> Map
    -> Camera
    -> Point
    -> Maybe Coordinate
coordinateAt projection size map camera point =
    let
        tilePixels : Float
        tilePixels =
            boardPixels projection map size * camera.zoom / toFloat map.width

        tile : Point
        tile =
            unproject projection
                map
                { x = (point.x - camera.offset.x) / tilePixels
                , y = (point.y - camera.offset.y) / tilePixels
                }

        position : Coordinate
        position =
            { x = floor tile.x, y = floor tile.y }

        insideViewport : Bool
        insideViewport =
            (abs point.x < size.x / 2) && (abs point.y < size.y / 2)

        insideMap : Bool
        insideMap =
            (tile.x >= 0)
                && (tile.x < toFloat map.width)
                && (tile.y >= 0)
                && (tile.y < toFloat map.height)
    in
    if insideViewport && insideMap then
        Just position

    else
        Nothing


centerOn :
    Projection
    -> Viewport
    -> Map
    -> Coordinate
    -> Camera
    -> Camera
centerOn projection viewport map position camera =
    let
        tilePixels : Float
        tilePixels =
            boardPixels projection map viewport.size * camera.zoom / toFloat map.width

        tile : Point
        tile =
            project projection
                map
                { x = toFloat position.x + 0.5
                , y = toFloat position.y + 0.5
                }
    in
    setOffset
        { x = -tile.x * tilePixels - viewport.rightInset / 2
        , y = -tile.y * tilePixels - viewport.bottomInset / 2
        }
        camera


{-| Keep the view unless a subject tile is clipped. Reframe with one tile of
breathing room, reducing zoom only when the group cannot fit the viewport.
Viewport dimensions and offsets are in pixels; subject positions are in tiles.
-}
frame :
    Projection
    -> Viewport
    -> Map
    -> List Point
    -> Camera
    -> Camera
frame =
    frameWith CenterSubjects


{-| Keep the current subject tiles on screen while moving toward a framing
target. Shift only as far as needed and zoom out only if shifting cannot fit
the group.
-}
keepVisible :
    Projection
    -> Viewport
    -> Map
    -> List Point
    -> Camera
    -> Camera
keepVisible =
    frameWith KeepOffset


frameWith :
    Framing
    -> Projection
    -> Viewport
    -> Map
    -> List Point
    -> Camera
    -> Camera
frameWith framing projection viewport map positions camera =
    case positions of
        [] ->
            camera

        first :: rest ->
            let
                bounds : Bounds
                bounds =
                    List.foldl includePoint (boundsAt first) rest
                        |> projectBounds projection map

                width : Float
                width =
                    toFloat map.width

                widthPixels : Float
                widthPixels =
                    boardPixels projection map viewport.size

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
                    bounds.left * tilePixels + camera.offset.x

                right : Float
                right =
                    bounds.right * tilePixels + camera.offset.x

                top : Float
                top =
                    bounds.top * tilePixels + camera.offset.y

                bottom : Float
                bottom =
                    bounds.bottom * tilePixels + camera.offset.y

                paddingTiles : Float
                paddingTiles =
                    case framing of
                        CenterSubjects ->
                            2

                        KeepOffset ->
                            0

                fittedZoom : Float
                fittedZoom =
                    min camera.zoom
                        (min
                            (visibleWidth * width / (widthPixels * (bounds.right - bounds.left + paddingTiles)))
                            (visibleHeight * width / (widthPixels * (bounds.bottom - bounds.top + paddingTiles)))
                        )

                subjectsVisible : Bool
                subjectsVisible =
                    (left >= -viewport.size.x / 2)
                        && (right <= viewport.size.x / 2 - viewport.rightInset)
                        && (top >= -viewport.size.y / 2)
                        && (bottom <= viewport.size.y / 2 - viewport.bottomInset)

                needsZoomOut : Bool
                needsZoomOut =
                    ((right - left) > visibleWidth) || ((bottom - top) > visibleHeight)
            in
            if subjectsVisible then
                camera

            else if (framing == KeepOffset) && not needsZoomOut then
                { camera
                    | offset =
                        { x =
                            camera.offset.x
                                + clamp
                                    (-viewport.size.x / 2 - left)
                                    (viewport.size.x / 2 - viewport.rightInset - right)
                                    0
                        , y =
                            camera.offset.y
                                + clamp
                                    (-viewport.size.y / 2 - top)
                                    (viewport.size.y / 2 - viewport.bottomInset - bottom)
                                    0
                        }
                }

            else
                { zoom = fittedZoom
                , offset =
                    { x =
                        -(bounds.left + bounds.right) / 2 * widthPixels * fittedZoom / width - viewport.rightInset / 2
                    , y =
                        -(bounds.top + bounds.bottom) / 2 * widthPixels * fittedZoom / width - viewport.bottomInset / 2
                    }
                }
