/**
 * Dynamic field-of-view shadows.
 *
 * The fov_shadows library keeps a grid of occluders (closed opaque turfs, trees) plus the boxes
 * registered by /datum/component/fov_shadow_box. For a viewer position it returns shadow triangles,
 * keyed by the wall edge, tree or box that casts each one, and the ids of boxes the viewer can see.
 * Each client keeps one pooled image per key, so a shadow that persists between updates animates
 * into its new shape instead of being recreated, and one cutout image per box it has seen.
 */

/// Living mobs waiting for a shadow refresh because an occluder changed near them, flushed once per tick.
GLOBAL_LIST_EMPTY(pending_shadow_updates)

/// What the shadow grid should hold for this turf. Anything opaque blocks sight like a wall, except
/// a tree, which the library treats as a round occluder. Follows the lighting system's notion of
/// opacity, so whatever updates lighting also updates shadows.
/turf/proc/shadow_cell_type()
	if(opacity)
		return SHADOW_CELL_WALL
	var/cell = SHADOW_CELL_EMPTY
	for(var/atom/movable/occupant as anything in contents)
		if(!occupant.opacity)
			continue
		if(istype(occupant, /obj/structure/flora/newtree))
			return SHADOW_CELL_TREE
		cell = SHADOW_CELL_WALL
	return cell

/// Writes this turf's cell to the shadow grid and refreshes anyone who can see it. Called wherever
/// the lighting system learns that opacity on the turf changed.
/turf/proc/update_shadow_cell()
	fov_shadows_set_map_cell(x, y, z, shadow_cell_type())
	notify_shadows_map_changed(src)

/// Recomputes this mob's shadows from its current position. Existing shadows animate into their new
/// shape over glide deciseconds; 0 snaps them.
/mob/living/proc/update_dynamic_shadows(glide = 0)
	if(!client)
		return
	var/turf/my_turf = get_turf(src)
	if(!my_turf)
		return
	// Viewer position in tile units: tile centre plus the sprite's pixel offset.
	var/viewer_x = my_turf.x + 0.5 + (step_x + pixel_x) / world.icon_size
	var/viewer_y = my_turf.y + 0.5 + (step_y + pixel_y) / world.icon_size
	// Looking afar moves the camera up to a screen away, so the window has to cover that as well.
	var/radius = is_looking_afar ? 18 : 8
	var/list/view = fov_shadows_calculate_view(viewer_x, viewer_y, my_turf.z, radius)
	client.apply_shadow_view(view["shadows"], view["visible"], my_turf.z, glide)

/// Queues a refresh for every player who can see a changed occluder. Calls in the same tick merge,
/// so a turf change, which destroys one turf and creates another, costs each viewer one refresh.
/proc/notify_shadows_map_changed(atom/changed)
	if(!SSatoms.initialized) // the map is still loading and nobody is on it yet
		return
	var/turf/changed_turf = get_turf(changed)
	if(!changed_turf)
		return
	for(var/mob/living/viewer in GLOB.player_list)
		var/turf/viewer_turf = get_turf(viewer)
		// 18 is the widest shadow window a viewer uses, see update_dynamic_shadows().
		if(!viewer_turf || viewer_turf.z != changed_turf.z || get_dist(viewer_turf, changed_turf) > 18)
			continue
		GLOB.pending_shadow_updates |= viewer
	if(length(GLOB.pending_shadow_updates))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(flush_pending_shadow_updates)), 0, TIMER_UNIQUE)

/proc/flush_pending_shadow_updates()
	var/list/viewers = GLOB.pending_shadow_updates
	GLOB.pending_shadow_updates = list()
	for(var/mob/living/viewer as anything in viewers)
		if(!QDELETED(viewer))
			viewer.update_dynamic_shadows()

/// Places the triangles the library returned, nine values each: anchor x, anchor y, matrix a to f, key.
/client/proc/apply_shadow_view(list/triangles, list/visible_box_ids, z, glide)
	var/list/used_keys = list()
	var/turf/anchor
	var/anchor_x
	var/anchor_y
	for(var/index = 1, index <= length(triangles), index += 9)
		var/key = triangles[index + 8]
		used_keys[key] = TRUE
		if(triangles[index] != anchor_x || triangles[index + 1] != anchor_y)
			anchor_x = triangles[index]
			anchor_y = triangles[index + 1]
			anchor = locate(anchor_x, anchor_y, z)
		var/matrix/shape = matrix(triangles[index + 2], triangles[index + 3], triangles[index + 4], triangles[index + 5], triangles[index + 6], triangles[index + 7])
		var/image/shadow = active_shadows[key]
		if(!shadow)
			shadow = take_shadow_image()
			active_shadows[key] = shadow
			shadow.loc = anchor
			shadow.transform = shape
			continue
		var/animate_time = glide
		if(shadow.loc != anchor)
			shadow.loc = anchor
			animate_time = 0 // the matrix is relative to the anchor, so interpolating across a jump would smear
		// Linear interpolation keeps the vertices two triangles share coincident while they move;
		// the default decomposes the matrix into rotation and scale and bends them apart.
		animate(shadow, transform = shape, time = animate_time, flags = ANIMATION_END_NOW | ANIMATION_LINEAR_TRANSFORM)
	release_unused_shadows(used_keys)
	update_shadow_cutouts(visible_box_ids)

/client/proc/take_shadow_image()
	var/pooled = length(shadow_image_pool)
	if(pooled)
		var/image/shadow = shadow_image_pool[pooled]
		shadow_image_pool.len--
		return shadow
	var/image/shadow = image('icons/effects/shadow_geom.dmi', icon_state = "triangle")
	shadow.plane = RAW_WALL_SHADOW_PLANE
	shadow.blend_mode = BLEND_ADD
	// PIXEL_SCALE: a 32px sprite stretched over hundreds of pixels would otherwise have its edges
	// smoothed across many screen pixels, leaving light seams where two triangles meet.
	shadow.appearance_flags = NO_CLIENT_COLOR | RESET_COLOR | PIXEL_SCALE
	images += shadow
	return shadow

/// Returns every active shadow whose key is not in used_keys to the pool; null releases them all.
/client/proc/release_unused_shadows(list/used_keys)
	var/list/released_keys = list()
	for(var/key in active_shadows)
		if(used_keys && used_keys[key])
			continue
		var/image/shadow = active_shadows[key]
		shadow.loc = null
		animate(shadow)
		shadow.transform = null
		shadow_image_pool += shadow
		released_keys += key
	active_shadows -= released_keys

/// Shows the cutouts of the boxes this client can now see and hides the ones it no longer can.
/client/proc/update_shadow_cutouts(list/visible_box_ids)
	var/list/now_visible = list()
	for(var/box_id in visible_box_ids)
		now_visible["[box_id]"] = TRUE
	for(var/box_id in visible_cutouts)
		if(now_visible[box_id])
			continue
		var/image/cutout = shadow_cutouts[box_id]
		if(cutout)
			cutout.alpha = 0
	for(var/box_id in now_visible)
		if(visible_cutouts[box_id])
			continue
		var/image/cutout = shadow_cutouts[box_id]
		if(!cutout)
			var/datum/component/fov_shadow_box/box = GLOB.fov_shadow_boxes[box_id]
			if(!box?.cutout)
				continue
			cutout = box.build_cutout_image()
			shadow_cutouts[box_id] = cutout
			images += cutout
		cutout.alpha = 255
	visible_cutouts = now_visible

/client/proc/drop_shadow_cutout(box_id)
	var/image/cutout = shadow_cutouts[box_id]
	if(!cutout)
		return
	images -= cutout
	shadow_cutouts -= box_id
	visible_cutouts -= box_id

/// Hides everything but keeps the images for reuse, for when the client changes mob.
/client/proc/reset_shadow_pool()
	release_unused_shadows(null)
	update_shadow_cutouts(null)

/// Frees every shadow image, for when the client leaves the living world.
/client/proc/destroy_shadow_pool()
	release_unused_shadows(null)
	for(var/image/shadow as anything in shadow_image_pool)
		images -= shadow
	shadow_image_pool.Cut()
	for(var/box_id in shadow_cutouts)
		images -= shadow_cutouts[box_id]
	shadow_cutouts.Cut()
	visible_cutouts.Cut()
