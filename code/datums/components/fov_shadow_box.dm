/// Shadow box components by id, so a viewer's visible-box list can be mapped back to the prop.
GLOBAL_LIST_EMPTY(fov_shadow_boxes)
GLOBAL_VAR_INIT(fov_shadow_box_next_id, 0)

/**
 * Gives a prop a pixel-precise occluder box in the fov_shadows library so it casts a dynamic shadow.
 *
 * With cutout enabled, a viewer who can see the prop also gets its sprite cut out of their shadow
 * layer, so the prop stands in front of the shadows it casts instead of being darkened by them.
 * The cutout is a per-client image built from the prop's appearance when first needed, so it is a
 * snapshot: props whose icon changes after creation should not use it.
 */
/datum/component/fov_shadow_box
	dupe_mode = COMPONENT_DUPE_UNIQUE
	/// Id shared with the library, also the key into GLOB.fov_shadow_boxes.
	var/box_id
	/// Pixel rectangle list(x1, y1, x2, y2) measured from the parent's turf corner, before pixel offsets.
	var/list/box
	/// Whether viewers who can see the parent get its sprite cut out of their shadow layer.
	var/cutout = TRUE
	/// Whether the box is currently registered with the library.
	var/registered = FALSE
	/// Where the box was last registered, for notifying viewers after the parent is gone.
	var/turf/last_turf

/datum/component/fov_shadow_box/Initialize(list/box, cutout = TRUE)
	if(!ismovable(parent) || length(box) != 4)
		return COMPONENT_INCOMPATIBLE
	src.box = box
	src.cutout = cutout
	box_id = ++GLOB.fov_shadow_box_next_id
	GLOB.fov_shadow_boxes["[box_id]"] = src
	register_box()

/datum/component/fov_shadow_box/RegisterWithParent()
	RegisterSignal(parent, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))

/datum/component/fov_shadow_box/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_MOVABLE_MOVED)

/datum/component/fov_shadow_box/Destroy()
	unregister_box()
	GLOB.fov_shadow_boxes -= "[box_id]"
	for(var/client/viewer as anything in GLOB.clients)
		viewer.drop_shadow_cutout("[box_id]")
	return ..()

/// Places the box at the parent's current position, or removes it while the parent is off the map.
/datum/component/fov_shadow_box/proc/register_box()
	var/atom/movable/owner = parent
	var/turf/anchor = get_turf(owner)
	if(!anchor)
		unregister_box()
		return
	// step_x and step_y only move under pixel movement; both are 0 for tile movement.
	var/world_x = anchor.x + (owner.step_x + owner.pixel_x) / world.icon_size
	var/world_y = anchor.y + (owner.step_y + owner.pixel_y) / world.icon_size
	fov_shadows_set_box_world(box_id, anchor.z, world_x, world_y, box[1], box[2], box[3], box[4])
	registered = TRUE
	last_turf = anchor
	notify_shadows_map_changed(anchor)

/datum/component/fov_shadow_box/proc/unregister_box()
	if(!registered)
		return
	fov_shadows_remove_box_by_id(box_id)
	registered = FALSE
	if(last_turf)
		notify_shadows_map_changed(last_turf)

/datum/component/fov_shadow_box/proc/on_moved(datum/source, atom/old_loc, dir, forced)
	SIGNAL_HANDLER
	register_box()

/// A fresh image of the parent's sprite on the cutout plane, hidden until the viewer can see the box.
/datum/component/fov_shadow_box/proc/build_cutout_image()
	var/atom/movable/owner = parent
	var/image/cutout_image = image(owner.icon, owner, owner.icon_state)
	cutout_image.appearance = owner.appearance
	// The image rides on the owner, which already applies its own pixel offsets and transform.
	cutout_image.pixel_x = 0
	cutout_image.pixel_y = 0
	cutout_image.transform = null
	cutout_image.plane = SHADOW_CUTOUT_PLANE
	cutout_image.layer = FLOAT_LAYER
	cutout_image.alpha = 0
	cutout_image.blend_mode = BLEND_DEFAULT
	cutout_image.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	return cutout_image
