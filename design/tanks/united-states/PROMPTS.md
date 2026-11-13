# Recorded generation prompts

The selected United States tank concept is [v24](concept-v24.png).

Both passes used the built-in ImageGen editor with transparent output.
The finished static concept is [concept-v1.png](concept-v1.png).

## v1 draft

Inputs, in order:

1. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), the edit target.
2. [Approved United States infantry v3](../../infantry/united-states/concept-v3.png), for style and palette only.

```text
Use case: precise-object-edit
Asset type: a static United States tank concept for FightLines, a strategy game with small map sprites.
Edit target: the first input, the high-resolution olive neutral FightLines tank. The second input is the approved United States infantry illustration; use it only for the hand-painted anime art direction and muted olive-drab and khaki palette. Do not include a person or copy the infantry's equipment onto the tank.

Redesign the illustrated vehicle into a compact, modern M1 Abrams-inspired tank. Make the Abrams identity visible in the broad angular turret with projecting sloped cheeks and a dark recessed mantlet, the shallow wedge front hull, and the substantial segmented side skirts covering the top of the track assembly. Keep the upper profile clean, with small low modern optics and hatches. Give the barrel a clean tapered silhouette and a compact end; shorten its overhang to fit the existing sprite footprint. Keep the armored vehicle dense and broadly square in its projected overall silhouette, with a substantial full-height hull and turret. Retain the nearly side-on right-facing view of the neutral tank: show the near track as one long horizontal band, only a sliver of the front and upper planes, and aim the barrel straight to the right. Do not rotate into a dramatic three-quarter view or foreshorten the near track. Retain the neutral's bottom track line and full tile-filling placement, with approximately 5% clear space left, 3% right, 9% above, and 7% below. Keep the entire gun and both visible track ends inside the image. Use the turret body, deck and hull mass to fill the silhouette, not tall antennas.

Render as a high-detail hand-drawn 1980s anime mechanical illustration: decisive dark ink contours, distinct painted cel-shadow shapes, warm desaturated olive-drab armor with subdued khaki highlights, and small blue-gray optical glass. Keep the main light and shadow masses distinct at 32–64 px. Show the lower arc of road wheels and tracks beneath the skirts. Keep fine seams, paint wear, and hardware subordinate to the big shapes. One isolated right-facing tank on a square canvas with genuine transparent alpha all around it. No floor, cast shadow, background, text, people, or visual effects.
```

## v1 final framing pass

Inputs, in order:

1. The draft from the first pass, retained locally by ImageGen as `exec-7eee301d-2387-481b-b1e6-f4372d2c5372.png` in generation `01a1ce70-6ac2-7dc0-9a7c-fffef35ae187`.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), the framing reference.

```text
Use case: precise-object-edit
Asset: one static, right-facing United States tank sprite for the strategy game FightLines, on a SQUARE transparent PNG.
Input 1 is the preliminary Abrams-inspired draft to revise. Input 2 is the original neutral tank; it is the strict reference for the vehicle's framing, silhouette mass and nearly side-on viewing angle.

Make a focused proportion and framing edit to input 1. Its silhouette is too low and wide, too close to the left edge, and leaves excessive transparent space above the turret. Match the broad, almost-square shape of the second image: on the square canvas the tank should run from about x=5% to x=97%, y=9% to y=93%, counting the whole silhouette. Align the bottom of the tracks to the original neutral's bottom track line. Give the Abrams turret a taller, substantial angled armor body while keeping a broad wedge cheek, low modern optics, and the dark recessed mantlet. Build height into the armor itself. Keep the clean taper of the shortened barrel; point it horizontally to the right and keep the muzzle fully inside the margin. Keep the flat hull deck, solid segmented side skirts and one near track running horizontally, with multiple road wheels clearly visible below the armor. Keep the distinctive Abrams armor shapes. Show just a little of the roof and frontal plane, as in the second image. No major pose, subject, color, or style changes.

Keep the hand-drawn high-detail 1980s anime mechanical illustration, strong dark contours, painted cel shadows, broad readable olive-drab and khaki planes, and blue-gray optics. Deliver just the isolated tank, with truly transparent alpha and uninterrupted clear padding on every side. No floor, cast shadow, lettering, people, or effects.
```

The saved PNG is the final ImageGen output with its original alpha. The map-scale
comparison uses the separate [256 px neutral map master](../../../artwork/units/illustrated/rigged/tank-neutral.png),
with both canvases resized equally and without cropping.

## v2 stout barrel

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v1](concept-v1.png), the edit target.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), for the barrel profile.

Output [concept-v2.png](concept-v2.png).

```text
Use case: precise-object-edit
Asset: United States tank v2, one static right-facing FightLines game sprite on a square transparent PNG.
Input 1 is United States concept v1, the edit target. Input 2 is the original neutral tank, the exact visual reference for the barrel only.

Replace only the exposed olive barrel in input 1 with the squat, chunky barrel shape from input 2. Match the original neutral barrel's proportions and profile closely: a short, thick cylinder with a wide base collar, a very short and thick nearly parallel-sided middle section, and a large rounded cylindrical muzzle collar nearly as tall as the base collar. The barrel should look about as deep from top to bottom as it projects forward from the turret. Make the muzzle collar a bold shape with an oval dark bore, as in input 2. Avoid the narrow tapered tube and small muzzle of v1. Keep the axis pointed straight right at the existing height, and keep the muzzle near its current horizontal endpoint with clear space before the edge. Blend the replacement barrel into v1's dark recessed mantlet with v1's olive-drab paint, khaki highlights, and hand-inked 1980s anime mechanical rendering.

Keep input 1's angular turret cheeks, optics, turret roof, recessed dark mantlet, hull, segmented side skirts, wheels, and tracks in the same positions, proportions and style. Preserve the right-facing nearly side-on camera, the square framing, and real transparent alpha all around the vehicle. The only visible change should be the stout neutral-style barrel. No additional objects, effects or background.
```

## v3 straight side profile

Built-in ImageGen edit of [United States tank v2](concept-v2.png) using transparent output.
Output [concept-v3.png](concept-v3.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v3, one static right-facing FightLines strategy-game sprite on a square transparent PNG. The supplied image is United States tank concept v2, the edit target.

Redraw the turret and its optics in a strict orthographic right-facing SIDE ELEVATION, seen squarely from the near side, perpendicular to the tank's length. Align the turret straight forward along the hull, with the gun axis running horizontally and parallel to the near track. In v2 a large dark frontal face of the mantlet is visible and the large foreground armor cheek recedes toward a separate front plane, giving a three-quarter view. Remove that perspective. Show the near broadside armor as a single broad flat side plane, with its upper edge and base running horizontally, a substantial rear bustle at left, and an angular sloping nose at right. Define the Abrams-inspired angular wedge with its SIDE OUTLINE and with bevel shading. Do not show a second face of the turret front or rear, a receding roof plane, or any far-side parts. Show the dark recessed gun mount only as a small edge-on collar or recess at the right outline where the barrel emerges. Show all optics and hatch fittings from the same exact side elevation, with their forward-facing faces hidden. The turret should still occupy roughly the same area as in v2.

Preserve the very short, fat, cylindrical barrel from v2 with its large rounded muzzle collar and nearly parallel-sided middle. Keep its dimensions, horizontal aim, attachment height and tip position. Show the muzzle collar from the side so the bore is edge-on. Keep the v2 lower hull, segmented side skirts, wheels, tracks, and olive and khaki 1980s anime ink and cel shading. Match the square framing and clear margins of v2. Keep genuine transparent alpha all around the tank. No background, lettering, cast shadow or effects.
```

## v4 shallow viewing angle

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v3](concept-v3.png), the edit target.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), for the viewing angle only.

Output [concept-v4.png](concept-v4.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v4, one static right-facing FightLines game sprite on a square transparent PNG.
Input 1 is the approved-looking United States tank v3 and is the edit target. Input 2 is the original neutral tank and is the viewing-angle reference only. Keep the tank design from input 1.

Nudge the turret view in input 1 just a few degrees from exact side profile toward the front, only to the very shallow angle visible in input 2. The clearest change should be at the right tip of the barrel: reveal a tiny sliver of the muzzle lip and dark opening as a very skinny vertical ellipse tucked into the extreme right edge, just as in input 2. Keep the opening so narrow it reads as a short dark line at tile size. The barrel remains horizontal and keeps the same very short, thick cylinder, wide end collar, size, and attachment height as input 1. Give the turret's front bevel and small roof fittings the same tiny amount of depth to make the perspective consistent. The turret should still read as a single broad side plane with a horizontal upper edge and base. Keep the dark gun mount almost edge-on and avoid exposing a separate broad front face or a three-quarter view. This is an angle correction of v3, not a redesign or a return to the earlier, more angled US turret.

Keep the hull, armor skirts, tracks, wheels, and nearly square tile-filling composition of input 1. Preserve its muted olive paint, ink contours and painted cel shading. Keep the entire tank inside the square with clear margins and genuine transparent alpha all around. No background, ground shadow, lettering or effects.
```

## v5 simplified turret roof

Built-in ImageGen edit of [United States tank v4](concept-v4.png) using transparent output.
Output [concept-v5.png](concept-v5.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v5, a static right-facing FightLines game sprite. The input is United States tank concept v4, the edit target.

Simplify the turret roof. The marked area at about x=42%, y=17% is the tall central stack of fittings. Remove that entire stack, the neighboring small boxes, the front roof box, and the protruding loop handles across the turret roof. Leave a mostly bare, clean, continuous armor roof line with just one simple, very shallow closed hatch set into the roof near the marked area. The hatch should be a single low lid, barely raised, with no stack, raised housing, handle, antenna or new accessory. Leave open roof space around it. The simplified roof silhouette should read clearly at map scale.

Edit the roof only. Preserve the main broad armored turret side, angular forward bevel, neutral reference's very slight viewing angle, tiny visible sliver of muzzle lip, and the same short thick barrel. Keep the hull, skirt panels, wheels, tracks, ink contours, olive and khaki painted cel shading, scale and positions of all the other parts from v4. Keep the original square canvas and make the cleared space above the roof truly transparent. No scene, ground, text, cast shadow or effects.
```

## v6 Abrams armor profile

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v5](concept-v5.png), the edit target.
2. The user-supplied Abrams side-view screenshot (`Screenshot 2026-11-12 at 2.10.47 AM.png`), for hull and turret geometry.

Output [concept-v6.png](concept-v6.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v6, a static right-facing FightLines strategy-game sprite. Input 1 is the United States tank v5 artwork to revise. Input 2 is the user's photograph of an Abrams, used only as a reference for the hull and turret shapes. The photograph faces LEFT. Translate its geometry into the RIGHT-facing pose of input 1, so the rear is at image LEFT and the nose and gun are at image RIGHT.

Rebuild the armor shapes in v5 so the profile is clearly closer to the photographed Abrams. Make two distinct sloping silhouettes, one on the hull and one on the turret. For the hull, make the engine deck at the rear (left) visibly taller above the horizontal side skirts, then drop to a lower forward deck and a longer, shallow descending glacis toward the pointed front (right). Keep the bottom track run level. For the turret, use a raised, projecting rear bustle (left), separated from the rear deck by a small dark gap. The turret's lower edge should rise diagonally toward the rear bustle, as in the photo, and sit lower near the front at the gun mount. Give the upper silhouette a modest rise toward the rear and a distinct forward slope into the gun. Design an oblique front armor cheek, angled both down toward the gun and inward toward the barrel centerline. Use a crisp diagonal seam and a broad shaded armor facet so the wedge can read from the same very slight angle as v5. Replace v5's long rectangular turret side with these clearly sloped upper and lower armor lines. Keep a single low closed hatch, with a clean roof and open space.

Keep v5's right-facing, almost side-on view, with only a tiny sliver of the muzzle lip visible. Preserve the deliberately fat, very short barrel with the large collar. Adapt the reference shapes to v5's compact, full-tile footprint and its bold near track and substantial side skirts. Use v5's olive and khaki painted cel shading, crisp dark ink contours, and high-detail 1980s anime mechanical illustration. Do not import the photo's long gun, desert paint, markings, raised roof equipment, or stowage. Deliver one complete isolated tank on a square PNG with genuine alpha transparency and space around the full barrel and tracks. No lettering, background, effects, or ground shadow.
```

## v7 thicker turret nose

Built-in ImageGen edit of [United States tank v6](concept-v6.png) using transparent output.
Output [concept-v7.png](concept-v7.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v7, a static right-facing FightLines game sprite. The supplied United States tank v6 is the edit target.

Make a localized shape correction to the FRONT of the turret, immediately left of the stout barrel. In v6 the angled cheek tapers to a small nose where the barrel attaches, making the large barrel look tacked on. Give the front armor a visibly deeper, more substantial shoulder at the gun mount. Thicken that last part of the turret vertically around the existing gun axis: carry more of the upper cheek forward before it slopes down, and retain a deeper lower armor edge under the attachment. Bring the upper and lower armor planes around the recessed base of the barrel so the joint is visibly supported above and below. Use a short angular face or bevel in the same olive armor that flows into the existing diagonal cheek, with a slim dark recess where the collar seats. The turret nose at the attachment should be clearly taller than the base collar. Keep the same slight viewing angle, and do not turn the new face toward the viewer. The added mass must read as one continuous part of the turret armor at tile scale. Do not add a separate box, attachment, or equipment.

Keep the barrel itself the same size, length, horizontal position, stout collar, and tiny visible muzzle lip. Preserve the v6 turret's sloping armor and raised rear bustle, the bare roof and low hatch, the raised rear engine deck and sloping glacis, and the hull, skirts and tracks. Keep the same olive-drab and khaki colors, 1980s anime ink and cel shading, scale, and square framing. Deliver the complete tank on genuine transparent alpha, with no background, lettering, shadow or effects.
```

## v8 forward turret hatch

Built-in ImageGen edit of [United States tank v7](concept-v7.png) using transparent output.
Output [concept-v8.png](concept-v8.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v8, a static right-facing FightLines game sprite. The supplied United States tank v7 is the edit target.

Add one modest closed crew hatch on the turret roof at the user's indicated spot, centered around x=58% of the square image, just to the right of the existing very low hatch and directly above the main angled turret cheek. The mark is at y=24%, just above the current sloping roof line. Seat the hatch on that roof so it looks built in, with the lid rising into the empty space at the mark. Give it a compact, wide, shallow profile: a small olive armored base, a beveled lid with a visible dark seam, and a tiny hinge if needed. Let it stand up slightly higher than the existing low hatch so it breaks the roof silhouette and remains readable at 64 px. Match the turret's very slight right-facing perspective, dark ink contours, warm olive paint, and restrained khaki highlights. Keep plenty of open roof around it. No stacked boxes, optics tower, antenna, weapon, person, or other additional roof fitting.

Make this a local roof edit. Preserve the original low hatch to the left, the raised rear and sloping turret armor, the newly thickened turret nose, the short stout barrel with the tiny sliver of muzzle lip, and the hull and tracks. Keep v7's scale, positions, proportions, hand-painted 1980s anime style, square framing and genuine alpha transparency. No scenery, ground shadow, lettering, or effects.
```

## v9 enlarged forward hatch

Built-in ImageGen edit of [United States tank v8](concept-v8.png) using transparent output.
Output [concept-v9.png](concept-v9.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v9, one static right-facing FightLines game sprite. The supplied United States tank v8 is the edit target.

Enlarge only the newly added forward crew hatch, centered at about x=58%, y=25%, to the right of the original low hatch. Keep its base in the same location on the sloping turret roof. Make the closed beveled lid and its integrated base about 20–25% wider and about 50% taller above the roof. Exaggerate the lid's silhouette enough to stand out at 64 px. Give the lid a gently domed, angular upper edge, a crisp ink outline and a broad khaki bevel over olive-drab armor, following the same very slight right-facing view. Keep it a single, closed hatch with the existing dark seam and compact hinge treatment. Keep space between the two hatches. Do not enlarge the low hatch on its left or add any fittings.

Keep the rest of v8 in place, including the sloping turret, thickened turret nose, short thick barrel with the thin visible muzzle lip, armor skirts and tracks. Preserve its high-detail 1980s anime cel shading, square canvas and true alpha transparency. No background, shadow, lettering or effects.
```

## v10 neutral and v9 hybrid

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v9](concept-v9.png), for the hull and tracks.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), for turret mass and barrel shape.

Output [concept-v10.png](concept-v10.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v10, one static right-facing FightLines game sprite on a transparent square canvas.
Input 1 is United States concept v9. Use its lower vehicle as the edit base, from the turret ring down. Input 2 is the high-resolution neutral FightLines tank. Use it as the reference for the new turret's visual mass, compactness, and barrel.

Keep the lower vehicle from input 1 closely matched: the raised rear engine deck at left, sloping front hull at right, segmented side skirts, wheel arrangement, track silhouette, color, scale and placement. Design a completely new turret from the ring upward. Borrow the neutral tank's taller, compact armored mass with an obvious setback from the rear of the hull, so the rear deck can be seen behind it. Retain a modern Abrams-inspired character with an angular wedge cheek toward the front and a short armored rear bustle that rises slightly above the ring. Build the height into the armor itself. Replace v9's long shallow row of rectangles with one coherent silhouette: a solid, taller main side plane with a distinct sloping rear shoulder and an oblique front cheek. Keep the gun-side portion of that cheek substantial above and below the collar so the barrel looks seated in the turret. Use two or three large readable armor planes and sparse seams. A single low but clearly readable beveled closed crew hatch should sit on top, with open roof around it. Skip optics towers, stacked boxes, handles, antennae, and other roof clutter.

Keep the neutral's very short, fat cylindrical barrel and thick muzzle collar, pointed horizontally to the right with only a tiny sliver of the muzzle lip and opening visible. Use the same almost side-on angle as both FightLines references. The near armor face should dominate, with just enough beveled depth to show the angle. Preserve the game's compact, broadly square, full-tile footprint and enough transparent space around the complete silhouette, including muzzle and tracks. Match the high-detail 1980s anime rendering with dark ink contours, warm desaturated olive armor, strong painted cel-shadow masses, and restrained khaki highlights that read at 64 px. Genuine alpha. No scenery, cast shadow, people, lettering, or effects.
```

## v11 taller turret and rear overhang

Built-in ImageGen edit of [United States tank v10](concept-v10.png) using transparent output.
Output [concept-v11.png](concept-v11.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v11, one static right-facing FightLines game sprite. The supplied United States tank v10 is the edit target.

Give v10's new compact turret more mass. Make its armored body about 20% taller by raising the roof and upper armor, keeping its ring seated on the same deck and keeping the barrel axis at the same height. Move the existing single closed hatch up with the roof. Keep the turret's angled front cheek and broad, coherent side plane. The added height should come from armor rather than from a taller hatch or additional equipment.

Rebuild the turret's rear shoulder into a short but distinct raised Abrams-style bustle at image left. Extend the rear armor a modest distance leftward over the visible engine deck, while keeping it well inside the back of the hull. Give this rear extension a broad armored side with an underside that visibly slopes upward as it runs toward the left rear tip. Leave a clear dark or transparent wedge of space between the raised overhang and the deck beneath it. The overhang should read as part of the turret itself, with a clean angular silhouette and a continuous upper shoulder. Keep its extension compact enough that the rear engine deck is still visible. This should look like a taller evolution of v10's turret with a distinct upswept rear, not a return to the full-length rectangular turret.

Keep the v10 hull, raised rear engine deck, segmented side skirts, wheels and tracks closely matched in place. Keep the front turret nose substantial around the short, very thick barrel. Preserve the barrel's length, level aim, collar and tiny sliver of visible muzzle lip. Preserve the near side-on right-facing camera, olive-drab and khaki colors, dark linework and 1980s anime painted cel shading. Keep the same square framing with the complete vehicle and real transparent alpha. No other roof fittings, scenery, people, lettering, ground shadow or effects.
```

## v12 increased turret height

Built-in ImageGen edit of [United States tank v11](concept-v11.png) using transparent output.
Output [concept-v12.png](concept-v12.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v12, one static right-facing FightLines game sprite. The supplied United States tank v11 is the edit target.

Make the main armored body of the turret conspicuously taller than v11. Raise the actual armor roof by roughly 7% of the whole canvas height, so the main armor body is about 28–30% taller, from the same turret ring at its base to the new roof. In v11 the armor roof immediately under the hatch is about 22% down from the top of the square. Bring it to around 15% down. Build this height into a tall, broad, solid side face with steeply sloping shoulders and a large front bevel. Keep one low closed hatch of the same size seated on the raised roof. Keep the right-facing barrel at its existing height, size, length and position, and carry the front armor up above it to meet the taller roof. Keep the underside and mounting height of the turret where they are.

Retain the upswept rear armor overhang above the rear engine deck, including the visible wedge of clear space under it. Keep the rear tip at roughly the same horizontal position. Its upper shoulder can rise more steeply to meet the new taller main turret. Keep the armored turret looking like one coherent shape. Do not fill the extra height with fittings, boxes, optics or a larger hatch.

Preserve the complete lower body from v11, from the turret ring down, including the raised rear deck, sloping front hull, side skirts, wheels and tracks. Preserve the near side-on viewing angle, short stout barrel and thin sliver of visible muzzle lip, warm olive-drab and khaki palette, crisp contours, and high-detail painted 1980s anime cel shading. Same scale, right-facing placement and square canvas. Leave clear space above the new hatch and around the complete muzzle and tracks. True transparent alpha, no scene, lettering, ground shadow or effects.
```

## v13 v10 turret height adjustment

Built-in ImageGen edit of [United States tank v10](concept-v10.png) using transparent output.
Output [concept-v13.png](concept-v13.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v13, a static right-facing FightLines game sprite. The single supplied image is United States tank v10. Work directly from this image.

Make one narrow edit: raise the existing v10 turret roof by a modest amount, about 3% of the square canvas height. This is about 35–40 pixels on a 1254 pixel image, or roughly 15% more height in the turret armor body. The existing closed hatch should move straight up the same distance with the roof and retain its exact shape and size. Extend the existing armor faces between the roof and their fixed lower edges to meet the raised roof. Keep the same number of armor planes and the same slopes and character of the existing v10 shoulders as closely as possible. The result should look unmistakably like v10 with a slightly taller turret.

Lock the rest of the image to v10. Keep the same horizontal extents of the turret, including the original compact left rear shoulder and its setback from the back of the hull. Do not extend the back of the turret leftward or add any rear overhang or attachment. Keep the bottom of the turret, ring, and all armor near the ring at their existing positions. Preserve the entire short, stout barrel, its collar and muzzle, its axis and the point where it meets the turret. Keep the lower vehicle, including the rear deck, hull, skirts, wheels and tracks, visually identical to v10. Keep its ink contours, painted olive and khaki cel shading, angle, placement, transparent square canvas and alpha. No new detail, color, scenery, or effects.
```

## v14 rear turret bustle

Built-in ImageGen edit of [United States tank v13](concept-v13.png) using transparent output.
Output [concept-v14.png](concept-v14.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v14, one static right-facing FightLines game sprite. The supplied United States tank v13 is the edit target.

At the user's mark around x=21%, y=30%, extend the existing rear of the turret to the LEFT into a substantial Abrams-style armored bustle over the raised engine deck. Rework only the left rear shoulder and adjoining empty space. The turret currently stops at about x=24%. Bring its rear end back to approximately x=9–11%, near the rear end of the chassis, with a clear gap above the engine deck below. The extension is a broad, mostly horizontal, solid armor overhang, with a slightly stepped upper edge, a nearly upright beveled rear end, and a shallow chamfer along the lower edge. Its upper edge should sit just below the main turret roof and its underside should be well above the deck so the overhang is obvious at tile scale. Integrate it into the same turret with one clean side plane and a simple diagonal join or bevel. Keep full armor depth at the rear end. Avoid a tapered tail, a point, a steep ramp, a basket, a suspended box, or added gear.

Keep the taller v13 main turret body, forward cheek, height, roof hatch, mount and short stout barrel in their current positions and proportions. Preserve the hull and its engine deck, skirts, wheels, tracks, near side-on angle, and clear margins. Match the olive and khaki color, ink contours, and 1980s anime painted cel shading. Keep the right-facing pose and square transparent PNG with genuine alpha. No background, cast shadow, text or effects.
```

## v15 level rear overhang and rail panel

Built-in ImageGen edit of [United States tank v14](concept-v14.png) using transparent output.
Output [concept-v15.png](concept-v15.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v15, a static right-facing FightLines game sprite. The supplied United States tank v14 is the edit target.

Redesign only the rear overhang of the turret, at the mark around x=22%, y=32%, to the LEFT of the large main turret side plate. It has an awkward stepped-down top in v14. Raise the top of the whole overhang to line up with the existing horizontal armor roof immediately below the hatch. The upper silhouette should be one straight, continuous horizontal line from the main turret roof back to a small chamfer at the left rear corner. No steps or dip in this roof line. Keep the hatch protruding above the shared roof line in its current location. Keep the rear tip about as far back as in v14 and keep the visible gap under it above the engine deck.

Differentiate this overhanging section from the solid main turret side. Give its near side a distinct framed panel with two stout, simple horizontal olive-metal rails and a single vertical support to divide it into two bays. Recess the area behind the rails in muted dark olive so the rails and the division are readable at 64 px. Put a crisp seam between the rail panel and the main turret armor. Keep this detail entirely on the side of the rear overhang below the shared roof line, with restrained highlights and enough simplicity to read at a glance. No loose stowage, fine mesh, antennas or new roof fittings.

Keep the central and forward turret armor, hatch, stout barrel, hull, skirts, wheels and tracks matched to v14. Preserve the slight right-facing viewing angle, colors, dark ink contours and painted 1980s anime cel shading. Preserve the full vehicle on the same square canvas with genuine transparent alpha. No scenery, ground shadow, lettering or effects.
```

## v16 integrated rear armor plates

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v15](concept-v15.png), the edit target.
2. [United States tank v9](concept-v9.png), for the rear armor plates and lower bevel.

Output [concept-v16.png](concept-v16.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v16, one static right-facing FightLines game sprite. Input 1 is United States tank v15, the edit target. Input 2 is United States tank v9, the reference for the rear turret armor only.

Redo the rear overhang on the left of input 1 using the visual language of input 2. In input 1 the dark rectangular recess and contrasting rails look like a separate rack bolted to the side. Remove the recessed rail panel and its frame entirely. Use two solid, contiguous olive armor plates with a narrow seam and restrained khaki edge highlights, like the left rear segments of input 2. The plates should share the side plane, lighting and material of the main turret. Give the rear end a small chamfer and a shallow upsweep along the underside toward the back, in the spirit of input 2. Continue that lower bevel forward into the main turret so it reads as one continuous mass. Retain a wedge of clear space above the rear engine deck. Keep the overhang reaching approximately as far back as input 1. Keep the top nearly level with the main turret armor roof, with just a small rear chamfer and no large step. Keep the overhang visibly segmented through the plate seam rather than contrast, a dark inset, or protruding hardware.

Use only the rear treatment from input 2. Keep input 1's taller main turret, angled front cheek, current single hatch, stout horizontal barrel with its tiny visible muzzle lip, and the hull, side skirts, wheels and tracks in place. Match the near side-on right-facing angle, warm olive and khaki palette, dark linework and hand-painted 1980s anime cel shading. Same square framing, whole silhouette and genuine transparent alpha. No background, shadows, effects or lettering.
```

## v17 turret clearance

Built-in ImageGen edit of [United States tank v16](concept-v16.png) using transparent output.
Output [concept-v17.png](concept-v17.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v17, a static right-facing FightLines game sprite. The supplied United States tank v16 is the edit target.

Make one subtle spacing edit where the whole turret meets the chassis. Move the complete turret and its attached barrel upward together by about 20–25 pixels on this 1254 px canvas, roughly one pixel when the sprite is displayed at 64 px. Reveal a slim, visible separation between the bottom of the turret armor and the top deck of the chassis, especially under the front and rear edges of the turret. Keep the gap as a shallow, dark horizontal break with small slivers of transparent negative space at the ends where appropriate. Keep a short, wide, dark mounting ring visible in the center as the turret's physical connection to the hull. It should feel seated on a slightly raised ring and integrated with the tank. Avoid a tall pedestal, oversized gap, or a floating turret.

Keep the exact v16 turret proportions, level roof line, single hatch, two rear armor plates, continuous lower bevel, front armor and short thick barrel. Move those features together without resizing or redesigning them. Keep the complete hull and track assembly in its existing position. Preserve the nearly side-on right-facing view, thin visible muzzle lip, olive and khaki paint, ink and painted 1980s anime cel shading, square framing, and genuine alpha transparency around the whole vehicle. No scenery, ground shadow, lettering or effects.
```

## v18 sight housing and spare track links

Built-in ImageGen edit of [United States tank v17](concept-v17.png) using transparent output.
Output [concept-v18.png](concept-v18.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v18, one static right-facing FightLines game sprite. The supplied United States tank v17 is the edit target.

Add two restrained exterior details to make the turret look like a working Abrams-inspired vehicle. Add one low rectangular sight housing just forward of the existing closed hatch, on the roof toward the right. Give it olive armor, a short beveled shoulder, and a small desaturated blue-gray glass slit. Keep it lower than the hatch and give the two objects a clear break in the silhouette. Add a small pair of spare track links on the near side of the left rear turret overhang. Use the charcoal and rubbed steel tones of the existing tracks, with two broad compact shapes on a small olive mounting plate. Keep the cluster small and confined to one rear armor plate so the seams, lower bevel and open space above the engine deck stay visible. These details should add character at 64 px while the rest of the turret reads as broad armor. Do not add a full-length rack, antenna, person, lettering, flags, or any other accessories.

Keep v17's hull, tracks, turret proportions, level roof line, single closed hatch, armor planes, short stout barrel, and narrow gap above the chassis with its dark mounting ring. Keep the slight right-facing angle and thin sliver of visible muzzle lip. Use the same high-detail 1980s anime ink outlines and painted cel shading, with warm olive armor and khaki highlights. Same transparent square PNG, whole vehicle and clear margins, genuine alpha, no background or ground shadow.
```

## v19 fresh run of the first prompt

Built-in ImageGen edit using transparent output. This is a fresh run of the exact
[v1 draft prompt](#v1-draft) and its two original inputs in the same order.
Output [concept-v19.png](concept-v19.png).

## v20 neutral barrel on v19

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v19](concept-v19.png), the edit target.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), for the exposed barrel.

Output [concept-v20.png](concept-v20.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v20, one static right-facing FightLines game sprite. Input 1 is United States tank v19, the edit target. Input 2 is the high-resolution neutral tank, the source for the exposed olive barrel only.

Replace v19's exposed tapered olive barrel with a faithful visual transplant of the neutral tank's barrel. Copy the neutral reference's entire short, very stout profile as closely as possible, including the wide cylindrical base collar, narrow dark seams between rings, short nearly parallel-sided middle, and especially the deep, oversized rounded muzzle collar. The neutral muzzle collar is nearly as tall as its base collar and shows only a very narrow vertical sliver of the dark bore at the extreme right. Match the silhouette, ring spacing, depth, rounded edges, and lighting of that barrel directly from input 2. Keep it aimed horizontally to the right. Preserve v19's nearly side-on angle, and keep the full muzzle just inside the right margin. Adapt only the join at v19's existing dark recessed mantlet and use v19's olive paint and khaki highlight tones at the seam. Do not reinterpret the barrel as a long or tapered tube.

Keep the rest of input 1 visually fixed, including the angular turret cheeks, low roof optics and hatches, recessed dark mantlet, turret ring, side skirts, lower hull and tracks, all at their current scale and positions. Keep the same high-detail 1980s anime ink and painted cel shading. Square PNG with genuine transparent alpha, full vehicle inside the canvas, no scenery, shadows, lettering or effects.
```

## v21 mostly side-on turret

Initially selected in visual review. Superseded by v24.

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v20](concept-v20.png), the edit target.
2. [High-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), for the turret viewing angle.

Output [concept-v21.png](concept-v21.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v21, one static right-facing FightLines game sprite. Input 1 is United States tank v20, the edit target. Input 2 is the original neutral FightLines tank, a reference only for the turret's slight, nearly side-on viewing angle.

Make one perspective correction to v20's turret armor, especially around its right-hand front. In v20 the large dark polygonal face with two visible bolts near the barrel, plus the broad receding roof facet immediately above it, reads as a turret looking partly toward the viewer. Bring the turret closer to the exact neutral reference angle. Show the near side and long angular cheek as the dominant plane, with the turret aiming down the same right-facing axis as the hull and the barrel. Bring the olive side cheek forward over most of the visible dark face, until the dark recessed mount is only a narrow, almost edge-on transition at the base of the barrel. Show just a slim angled bevel at the turret's leading edge and a shallow sliver of the roof, similar in depth to the neutral tank. Keep the distinctive wedge of the cheek and the existing general turret length, height, roof hatches and blue-gray optics. The turret should read nearly broadside at map scale, with a small amount of depth like input 2. Do not turn it into a perfectly flat side elevation or redesign the turret.

The barrel itself is locked to input 1. Preserve its exact horizontal aim, length, location, large base collar, short cylindrical middle, broad muzzle collar, narrow visible muzzle lip and shading. Make the perspective change to the turret armor and visible face around the barrel only. Preserve v20's chassis, segmented side skirts, wheels, tracks, framing, and olive and khaki 1980s anime cel shading. Keep the full right-facing vehicle on a square PNG with genuine alpha transparency. No scenery, lettering, shadows or effects.
```

## v22 raised rear deck experiment

Built-in ImageGen edit of [United States tank v21](concept-v21.png) using transparent output.
Output [concept-v22.png](concept-v22.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v22, a static right-facing FightLines game sprite. The supplied United States tank v21 is the edit target.

Try one silhouette experiment at the user's mark, around x=22%, y=46%, where the rear of the turret overhangs the left rear deck of the chassis. Raise the rear upper hull in that region by about 4% of the canvas height, creating a visibly higher armored engine deck over the back quarter of the tracks. Make it a broad, low rise integrated with the chassis side and use a short, clean sloping transition back down toward the middle of the hull. Keep the front deck, skirt panels, wheels and tracks at their current height. The rear rise should change the main hull contour and be readable at map scale.

Lift the entire turret and its short stout barrel upward together enough to clear the new raised rear deck, about the same amount as the deck rises. Keep the turret level, its nearly side-on perspective and the same shape and proportions. Show a slim dark band at the center mount and a narrow visible gap between the rear overhang and the new raised deck. Connect the turret naturally to the chassis through a low, wide dark mounting ring. Do not add a tall pedestal, a large floating gap, or new equipment. The result should read as one tank with a stepped-up rear hull and a turret seated slightly higher.

Keep v21's angular turret armor, low optics and hatches, neutral-style barrel with its tiny visible muzzle lip, olive and khaki palette, and high-detail 1980s anime ink and painted cel shading. Preserve the full right-facing vehicle at the same scale on the same square canvas with genuine alpha transparency. No scenery, lettering, cast shadows or effects.
```

## v23 raised rear deck and upswept turret

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v22](concept-v22.png), for the raised rear chassis deck.
2. [United States tank v21](concept-v21.png), for the original height of the forward turret, barrel, and mount.

Output [concept-v23.png](concept-v23.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v23, a static right-facing FightLines game sprite. Input 1 is United States tank v22 and supplies the raised rear chassis and lower vehicle. Input 2 is the approved United States tank v21 and supplies the fixed height and position of the forward turret, barrel and central mount.

Keep the raised left rear chassis deck from input 1. Change the turret shape, with the REAR higher and the FRONT at its original lower height. Restore the front half of the turret and its short stout barrel to the same vertical position as in input 2. Keep the barrel level and keep the original visible muzzle lip. Restore the thin central mount of input 2, so there is no tall exposed band under the whole turret.

Lift and reshape ONLY the left rear portion of the turret, above the raised deck at x=22% of the canvas. The lower silhouette of the turret should slope diagonally up toward the left rear tip, leaving a slim, visible wedge of clearance above the raised deck. Lift the rear shoulder and the rear part of the roof with it so the rear armor retains its depth. Give the side armor a smooth angular transition into the fixed central and forward turret. The front should remain seated low, while the back sweeps up over the higher hull. Make this slope visible at map scale. Do not move the entire turret upward or rotate the barrel. Do not add a separate rear box or extra fittings.

Keep the general v21 turret shape, armor planes and low optics, and keep the v22 chassis, side skirts, wheels and tracks in place. Match the slight right-facing side profile, olive and khaki paint, dark contours, and high-detail 1980s anime cel shading. Preserve the full silhouette on the same square canvas with genuine transparent alpha. No scenery, ground shadow, lettering or effects.
```

## v24 v21 turret and v22 rear chassis slope

Built-in ImageGen edit using transparent output. Inputs, in order:

1. [United States tank v21](concept-v21.png), the edit target.
2. [United States tank v22](concept-v22.png), for the rear chassis slope only.

Output [concept-v24.png](concept-v24.png).

```text
Use case: precise-object-edit
Asset: United States tank concept v24, one static right-facing FightLines game sprite. Input 1 is approved United States tank v21, the edit target. Input 2 is United States tank v22, the reference only for the small slope on the rear chassis deck.

Keep the entire turret assembly of input 1 exactly as it looks and sits in v21, including the rear armor, level side-profile shape, roof, optics, mount height, and short stout barrel. Do not lift, tilt, slope, or reshape any part of the turret. Replace only the upper rear chassis contour beneath it, on the left, with the small raised deck and gentle diagonal ramp from input 2. Match input 2's short elevated shoulder above the rear tracks and the sloping line that descends toward the middle of the hull, confined to the left upper chassis above the side skirts. Preserve a slim shadow or seam where the raised deck meets the turret silhouette. The larger, darker exposed turret ring in input 2 is not part of the chassis change. Keep input 1's slim olive mount and original turret position.

Keep v21's front hull, lower side skirts, wheels and tracks, placement and scale. Preserve its right-facing near side profile, olive and khaki colors, dark linework, and high-detail 1980s anime painted cel shading. Keep the complete silhouette on a square canvas with genuine alpha transparency. No scenery, ground shadow, lettering or effects.
```
