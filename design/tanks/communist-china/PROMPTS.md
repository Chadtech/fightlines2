# Recorded generation prompts

The approved static Communist China tank concept is [v5](concept-v5.png).
The selection includes its cooler, matte olive finish.

## v1

Built-in ImageGen edits with transparent output. The result is
[concept-v1.png](concept-v1.png).

### Shape draft

The sole input was the [high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png).
ImageGen saved the intermediate as `exec-1ee53651-6352-45bf-81cc-e645f6d3d291.png`.
The draft introduced the red star, which the final edit retained as a faction marking.

```text
Use case: precise-object-edit. Make one static Communist China tank map sprite for FightLines. The supplied neutral tank is the image to edit.

Treat the source as a full-size underdrawing. Keep the bottom, top, left and right extrema of the substantial painted body very close to where they are in the source, so the vehicle fills almost the whole tile in both directions with the same transparent margins. Keep the baseline of the track and the positions of the front and rear track ends. Keep the highest point of the new armored cupola near the source's highest solid roof fitting. The tank as a whole should be almost as tall as it is wide. Retain the source's right-facing almost-side view and its sharply foreshortened, nearly horizontal gun with the muzzle visible on the right. Keep the whole vehicle and its short fittings inside the square transparent canvas.

Redraw the armored shapes in the visual language of a modern Soviet main battle tank, using a low compact flattened-dome turret with beveled armor cheeks, a flush cupola and inset optics. To make the turret genuinely low while keeping its top near the same canvas height, raise the turret ring by putting it on a deep, solid hull. The hull should be clearly the largest block of solid mass, with deep sloping upper armor, substantial armored side plates and a chunky front shoulder. Use a deep exposed track loop with large distinct road wheels to anchor the bottom half. Preserve the source's tall, compressed game-sprite proportions through these big shapes. Do not add a tall antenna. Keep the gun distinct with a dark muzzle, stopping near the front edge of the track.

Hand-drawn high-detail 1980s anime mechanical illustration. Muted olive armor, warm khaki edge light, dark charcoal steel tracks, ink contours, and painted cel shadows. Make the armor planes and the dark break under the turret readable when the sprite is rendered at 48 pixels. Use genuine alpha transparency everywhere outside the tank. No scenery, ground, shadows outside the vehicle, crew, text, effects or extra objects.
```

### Final framing edit

The inputs were the shape draft and the high-resolution neutral tank, in that order.

```text
Use case: precise-object-edit. Edit image 1, the latest Communist China tank sprite for FightLines. Image 2 is the original neutral tank and is the template for placement and scale. Preserve the modern Soviet-style low, flattened, faceted turret, muted olive paint, warm khaki edge light, small painted red star, substantial armored hull and dark exposed tracks from image 1. Preserve the right-facing, nearly broadside camera with a strongly foreshortened gun.

Correct the silhouette and framing in this edit. The tank currently nearly touches both sides of the canvas and sits too low. Bring the rear of the track slightly right, bring the front of the track and the muzzle slightly left, and raise the turret roof into the currently empty space above the tank. The bottom track line stays at about the same height. Build the additional height into the upper hull armor and the track loops so the turret stays short relative to the vehicle. Keep the wheels distinct and keep the turret ring legible. The finished tank from solid turret roof to tread should be nearly as tall as it is wide, matching image 2. On a 1254-pixel square, leave about 60 pixels on the left, 35 on the right, 120 above the highest solid fitting and 85 below the tracks, similar to the visible neutral tank. Use those margins as composition guides. The whole painted outline, including the track ends and muzzle, should be comfortably inside the frame.

Keep the hand-drawn high-detail 1980s anime mechanical rendering, with decisive ink outlines and painted cel shadows that read at 48 pixels. One intact tank centered on a square true-alpha PNG. Outside the tank is entirely transparent. No long antenna, background, scenery, cast shadow, crew, effects, text or extra objects.
```

## v2

Built-in ImageGen edit with transparent output. The sole input was the
[high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png).
The result is [concept-v2.png](concept-v2.png).

```text
Use case: precise-object-edit. Create one static Communist China faction tank sprite for FightLines by editing the supplied high-resolution neutral tank. Use the supplied PNG as the actual base artwork. This is a close faction variant of that same vehicle, with changes concentrated inside its existing outlines.

Lock the overall geometry, nearly side-on right-facing angle, placement, zoom, and transparent margins. Preserve the turret's actual size, height, position, outer shape, and chunky faceted profile from the input. Its rear shoulder, upper fittings, two dark optical windows, broad near-side face, forward cheek and lower edge should remain immediately recognizable. Preserve the gun's geometry especially closely: the same short, stout, strongly foreshortened tube, same horizontal axis and mount location, same alternating thick collar and recessed rings, same wide cylindrical muzzle with a narrow dark opening at the right. The muzzle should reach the same place on the canvas and have the same diameter as the source. The gun should be visually traceable onto the input with almost no change. Preserve the hull and track outline, road wheel spacing, track baseline and entire vehicle footprint.

Put the faction character into the finish and small surface details. Repaint the armor a slightly deeper, cooler military olive green with muted khaki edge highlights and charcoal tracks. Within the original broad turret face, suggest modern Soviet armor with two or three shallow beveled armor panel divisions that follow the existing planes and with restrained recessed fastener details. Keep the silhouette continuous. Paint one small muted red five-point star on the broad near-side turret panel. Add a few subtle panel joints to the existing hull side plates. Keep the faction treatment quiet and readable at a 48-pixel map tile.

Use high-detail hand-drawn 1980s anime mechanical rendering with decisive ink contours and painted cel shadows. Preserve the source's square framing and near-square visible footprint. Return one complete tank in a square PNG with true transparent alpha, with the barrel and tracks fully inside the frame and the same breathing room as the original. No ground, cast shadow, people, text, effects, or extra objects.
```

## v3

Built-in ImageGen edit with transparent output. The sole input was the
[high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png).
The result is [concept-v3.png](concept-v3.png).

```text
Use case: precise-object-edit. Create one static Communist China faction tank sprite for FightLines. Edit the supplied high-resolution neutral tank.

Give the tank a distinctive smoothly rounded Soviet-inspired cast turret. The main turret should read as one low, broad, hemispherical dome with a continuous curved shoulder, like an inverted bowl. Draw a clear arc across the top and round the front, near side, and rear into a single balanced volume. Carry the same curvature and visual thickness around its circumference so the turret reads as armored all around. Keep the dome taller through its center so it remains a substantial, legible shape at 48 pixels. Replace the neutral turret's big flat plates and stacked box shapes with this genuinely curved mass. Set one compact modern sight and a flush hatch close to the roof; neither should interrupt the arc much. Keep the painted armor completely unmarked: no star, emblem, numbers, lettering, or insignia.

Preserve the neutral tank's right-facing near-broadside view and the recognizable short, stout, foreshortened barrel. Keep the gun level, with roughly the same outer diameter, reach, and dark visible muzzle. Seat its thick collar neatly into the curved front of the dome. Keep the original track footprint, baseline, large road wheels and broad, nearly square composition. Give the hull a subtly rounded shoulder to echo the turret while retaining a substantial mass over the tracks. Keep the tank large inside the square canvas, with breathing room at all four edges. The whole silhouette, including the muzzle and both track ends, fits inside the frame.

Render as a high-detail hand-drawn 1980s anime mechanical illustration. Use olive green armor, warm khaki rim lights, and dark steel tracks. Follow the turret's curvature with broad bands of painted cel shading so the dome reads clearly at map scale. Use deliberate ink contours and restrained painted wear. The tank is contemporary faction art with a rounded cast-turret silhouette. One complete tank on a genuinely transparent square PNG, with no ground, cast shadow, scenery, crew, or effects.
```

## v4

Built-in ImageGen edit of [concept-v3.png](concept-v3.png) with transparent
output. The result is [concept-v4.png](concept-v4.png).

```text
Use case: precise-object-edit. Refine the supplied FightLines Communist China tank concept v3. Keep its distinctive unmarked Soviet-inspired domed turret. Change the dome's contour and paint so it reads as a heavy armored steel casting.

Give the turret the regular geometry of a low circular armored cupola: a broad, evenly arched crown, a short gently flattened area near the center of the roof, and curved shoulders that meet a defined lower rim. Shape the rear shoulder and the visible front cheek as parts of the same deliberate circular arc. Remove the bulbous belly and the soft bulging lower contour. Define the bottom of the casting with a crisp, nearly horizontal edge above the turret ring, a shallow continuous bevel, and a thin shadow seam. Keep the dome broad and substantial at roughly the current height and width. Keep the little hatch, compact sight and robust ringed barrel. The turret's distinctive exterior should still be round, with continuous cast curves and a small number of deliberate machined edges. No extra armor boxes or angular plate arrays.

Repaint the tank in matte, slightly gray olive drab. Use soft, diffuse light on the roof, quiet olive midtones, and a clear ink contour with a firm cel shadow below the rim. Remove the pale shiny ribbons and the broad curved bands of reflected light across the turret. Add very fine, subtle cast-steel texture and a little dry edge wear. Reduce the golden shine across the gun, fenders, wheels, and hull while keeping readable separation between the large shapes. Keep the high-detail 1980s hand-drawn anime mechanical illustration style. The armor is unmarked: no star, badge, number, lettering or emblem.

Preserve the near-broadside right-facing angle, the short, stout, foreshortened barrel, the large wheels and intact tracks, and the broad square tile-filling footprint. Keep the same apparent scale and enough clear margin around the whole tank, especially the front track and muzzle. Return one complete tank on a square PNG with genuine alpha transparency. No ground, cast shadow outside the vehicle, scenery, crew, or effects.
```

## v5

Built-in ImageGen edit of [concept-v4.png](concept-v4.png) with transparent
output. The result is [concept-v5.png](concept-v5.png).

```text
Use case: precise-object-edit. Edit the supplied FightLines Communist China tank v4 in two small regions only.

1. Rotate the small rectangular periscope on top of the turret immediately to the right of the round hatch, near the marked point at x 61%, y 18%. Its optical face currently points toward the viewer. Turn the periscope to face straight ahead along the barrel axis, toward screen right. Keep it on the same roof mount and roughly the same size. From this nearly side-on viewing angle, show a broad solid olive side panel toward the viewer and just a narrow dark-blue sliver of glass on the forward, screen-right end of the housing. Place no window on the broad side facing the viewer. Keep the neighboring round hatch intact.
2. Remove the prominent orange lamp on the front hull just above the right fender, near the marked point at x 90%, y 52%. Remove the entire external lamp housing, its frame, and its mounting bracket. Cleanly continue the existing olive armor edge and the top line of the fender behind it. Leave the space above that edge transparent and do not add a replacement light or fitting.

Match the original image everywhere outside those two regions, including the unmarked matte olive dome, its hard lower rim, the short stout ringed barrel, the tow loops, wheels, treads, viewing angle, exact position and scale, and transparent square canvas. Preserve the hand-painted 1980s anime mechanical illustration and matte finish. Return one intact tank with genuine alpha transparency.
```

## v6

Built-in ImageGen edit of [concept-v5.png](concept-v5.png) with transparent
output. [Concept v6](concept-v6.png) explores a continuous slope at the front of
the hull.

```text
Use case: precise-object-edit. Edit the supplied FightLines Communist China tank v5. Make one localized change to the front hull and front fender on the right, around the marked point at x 92.5%, y 58.3%.

Join the upper front hull and front fender into one uninterrupted sloping nose. Starting just in front of the forward tow loop below the turret, draw a single clean diagonal upper contour descending to the right all the way to the existing tip above the front of the track. Merge the two rounded shoulders into one continuous olive armor surface. Remove the ledge and abrupt change in angle where the upper hull meets the top of the fender. Use a consistent slope, with only a small bevel where it ends at the nose. Carry one subtle edge highlight down this slope. The connected hull and fender should read as one wedge from the side. Smooth any little fittings directly in the path of that sloped edge. Keep the tow loop farther back, the lower fender edge, and the front of the track in place. The headlight area stays clear.

Keep everything else as close to v5 as possible. Preserve the large unmarked matte olive dome, the compact forward-facing periscope, hatch, short stout ringed barrel, left-side hull and stowage, wheels and tracks. Preserve the right-facing nearly broadside camera, palette, 1980s hand-painted anime rendering, original scale, placement, and tile-filling footprint. One complete tank on a square PNG with genuine alpha transparency. No star, text, background, crew, or cast shadow.
```
