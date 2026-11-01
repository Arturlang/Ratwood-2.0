// fov_shadows.dm - DM API for the fov_shadows extension library.
//
// To override the library detection, define FOV_SHADOWS before this file is
// included:
//
// #define FOV_SHADOWS "path/to/fov_shadows"

#ifndef FOV_SHADOWS
// On Windows, looks in the standard places for `fov_shadows.dll`.
// On Linux, looks in `.` and then `$LD_LIBRARY_PATH` for `libfov_shadows.so`.

/* This comment bypasses grep checks */ /var/__fov_shadows

/proc/__detect_fov_shadows()
	if (world.system_type == UNIX)
		if (fexists("./libfov_shadows.so"))
			// No need for LD_LIBRARY_PATH badness.
			return __fov_shadows = "./libfov_shadows.so"
		else
			// It's not in the current directory, so try others
			return __fov_shadows = "libfov_shadows.so"
	else
		return __fov_shadows = "fov_shadows"

#define FOV_SHADOWS (__fov_shadows || __detect_fov_shadows())
#endif

/// Decodes a JSON list returned by the library. An empty string means the call failed inside the library.
/proc/__fov_shadows_decode(raw)
	return length(raw) ? json_decode(raw) : list()

/// Gets the version of the fov_shadows library.
#define fov_shadows_get_version() call_ext(FOV_SHADOWS, "get_version")()
/// Allocates the occluder grid for the whole world. Call once after all z-levels are loaded; it clears every cell and box.
#define fov_shadows_init_map_bounds(maxx, maxy, maxz) call_ext(FOV_SHADOWS, "init_map_bounds")("[maxx]", "[maxy]", "[maxz]")
/// Marks one tile as SHADOW_CELL_EMPTY, SHADOW_CELL_WALL or SHADOW_CELL_TREE.
#define fov_shadows_set_map_cell(x, y, z, cell_type) call_ext(FOV_SHADOWS, "set_map_cell")("[x]", "[y]", "[z]", "[cell_type]")
/// Marks many tiles at once from a flat list of x, y, z, cell_type quadruples.
#define fov_shadows_bulk_set_map_cells(cells) call_ext(FOV_SHADOWS, "bulk_set_map_cells")(jointext(cells, ","))
/// Registers or moves a pixel-space occluder box (px1, py1)-(px2, py2) anchored at world position (wx, wy) on z.
#define fov_shadows_set_box_world(id, z, wx, wy, px1, py1, px2, py2) call_ext(FOV_SHADOWS, "set_box_world")("[id]", "[z]", "[wx]", "[wy]", "[px1]", "[py1]", "[px2]", "[py2]")
/// Removes a box previously registered with fov_shadows_set_box_world.
#define fov_shadows_remove_box_by_id(id) call_ext(FOV_SHADOWS, "remove_box_by_id")("[id]")
/// Returns a flat list of 9 values per shadow triangle: anchor_x, anchor_y, matrix a, b, c, d, e, f, key.
#define fov_shadows_calculate_shadows_fast(px, py, z, radius) __fov_shadows_decode(call_ext(FOV_SHADOWS, "calculate_shadows_fast")("[px]", "[py]", "[z]", "[radius]"))
/// Returns the list of box ids visible from (px, py) on z within radius.
#define fov_shadows_get_visible_boxes(px, py, z, radius) __fov_shadows_decode(call_ext(FOV_SHADOWS, "get_visible_boxes")("[px]", "[py]", "[z]", "[radius]"))
