tool
extends EditorPlugin

var popupMenu : PopupMenu
var activateButton : Control
var fileDialog : FileDialog

var autotileEnabled := true
var editMode := false
var currentGridmap : GridMap
var currentMeshInstance : MeshInstance

var getDraw := false
var erasing := false
var lastSize : int = 0
var lastVec := Vector3.ZERO

var bitmaskSize : float = 1.0
var editAxis = 0 setget axis_changed#0=All, 1=AxisX, 2=AxisY, 3=AxisZ

var autotileDictionary : Dictionary
var autogridId : int

const BITMASK_BOX = preload("res://addons/AutoGrid/bitmask_box.gd")
const orthogonal_angles = [
	Vector3(0, 0, 0),
	Vector3(0, 0, PI/2),
	Vector3(0, 0, PI),
	Vector3(0, 0, -PI/2),
	Vector3(PI/2, 0, 0),
	Vector3(PI, -PI/2, -PI/2),
	Vector3(-PI/2, PI, 0),
	Vector3(0, -PI/2, -PI/2),
	Vector3(-PI, 0, 0),
	Vector3(PI, 0, -PI/2),
	Vector3(0, PI, 0),
	Vector3(0, PI, -PI/2),
	Vector3(-PI/2, 0, 0),
	Vector3(0, -PI/2, PI/2),
	Vector3(PI/2, 0, PI),
	Vector3(0, PI/2, -PI/2),
	Vector3(0, PI/2, 0),
	Vector3(-PI/2, PI/2, 0),
	Vector3(PI, PI/2, 0),
	Vector3(PI/2, PI/2, 0),
	Vector3(PI, -PI/2, 0),
	Vector3(-PI/2, -PI/2, 0),
	Vector3(0, -PI/2, 0),
	Vector3(PI/2, -PI/2, 0)
]

func handles(object) -> bool:
	if currentMeshInstance && currentMeshInstance.has_node("AutoGrid_Bitmask"):
		currentMeshInstance.get_node("AutoGrid_Bitmask").deactivate()
	if object is GridMap:
		return true
	elif editMode:
		if object is MeshInstance:
			activateButton.show()
			return true
		else:
			activateButton.hide()
			return false
	return false

func edit(object):
	if object is GridMap:
		currentGridmap = object
		currentMeshInstance = null
		if autotileEnabled:
			load_autotile_info()
	elif object is MeshInstance:
		currentMeshInstance = object
		if currentMeshInstance.has_node("AutoGrid_Bitmask"):
			currentMeshInstance.get_node("AutoGrid_Bitmask").activate()
			currentMeshInstance.get_node("AutoGrid_Bitmask").set_axis(editAxis)
		currentGridmap = null

func load_autotile_info():
	if currentGridmap.mesh_library == null:
		print("Mesh library is null.")
	
	autotileDictionary.clear()
	var fileDir : String
	for i in currentGridmap.mesh_library.get_item_list():
		if currentGridmap.mesh_library.get_item_name(i).ends_with("_agrid"):
			fileDir = currentGridmap.mesh_library.get_item_mesh(i).resource_name
			autogridId = i
	
	if fileDir.empty():
		print("Autotile is not available for this gridmap. Please create autotile or disable autotile from Project>Tools>AutoGrid")
		return
	
	var loadFile = File.new()
	if loadFile.open(fileDir, File.READ) != OK:
		print("File couldn't find at ", fileDir)
		loadFile.close()
		return
	var content = loadFile.get_as_text()
	loadFile.close()
	autotileDictionary = JSON.parse(content).result
	var keys = autotileDictionary.keys()
	var values = autotileDictionary.values()
	for i in currentGridmap.mesh_library.get_item_list():
		var itemName = currentGridmap.mesh_library.get_item_name(i)
		for j in values.size():
			if itemName == values[j]:
				autotileDictionary[keys[j]] = i

func axis_changed(val):
	editAxis = val
	var children = get_editor_interface().get_edited_scene_root().get_children()
	for child in children:
		if child.has_node("AutoGrid_Bitmask"):
			child.get_node("AutoGrid_Bitmask").set_axis(editAxis, child == currentMeshInstance)

func forward_spatial_gui_input(camera, event) -> bool:
	
	if autotileEnabled && currentGridmap:
		gridmap_inputs(event)
		return true
	if editMode && currentMeshInstance:
		return bitmask_inputs(camera, event)
	
	return false

func gridmap_inputs(event):
	if event is InputEventMouseButton and (event.button_index == BUTTON_LEFT or event.button_index == BUTTON_RIGHT):
		if event.button_index == BUTTON_LEFT:
			if event.is_pressed():
				getDraw = true
				erasing = false
				lastSize = 0
				check_autotile()
			else:
				getDraw = false
		
		if event.button_index == BUTTON_RIGHT:
			if event.is_pressed():
				getDraw = true
				erasing = true
				lastSize = 0
				check_autotile()
			else:
				getDraw = false
	
	if getDraw:
		if event is InputEventMouseMotion:
			check_autotile()

func bitmask_inputs(camera : Camera, event : InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.is_pressed():
			var ray_origin = camera.project_ray_origin(event.position)
			var ray_dir = camera.project_ray_normal(event.position)
			var ray_distance = camera.far
			
			var space_state =  get_viewport().world.direct_space_state
			var hit = space_state.intersect_ray(ray_origin, ray_origin + ray_dir * ray_distance, [], 524288)
			if hit and hit.collider is BITMASK_BOX:
				hit.collider.toggle_box()
				return true
	
	return false

func check_autotile():
	#Calling get_used_cells require lots of work, use it less!!
	var cells = currentGridmap.get_used_cells()
	var currentSize = cells.size()
	if currentSize == 0:
		return
	if currentSize != lastSize:
		var totalV = Vector3.ZERO
		for cell in cells:
			totalV += cell
		var lastEditedV = get_last_edited_tile_fast(totalV)
		var lastEditedCell = currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y, lastEditedV.z)
		var bitVal = 0
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1) != -1:
			bitVal |= 1 #2^0
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1) != -1:
			bitVal |= 2 #2^1
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z) != -1:
			bitVal |= 4 #2^2
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1) != -1:
			bitVal |= 8 #2^3
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1) != -1:
			bitVal |= 16 #2^4
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1) != -1:
			bitVal |= 32 #2^5
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z) != -1:
			bitVal |= 64 #2^6
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1) != -1:
			bitVal |= 128 #2^7
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z) != -1:
			bitVal |= 256 #2^8
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1) != -1:
			bitVal |= 512 #2^9
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1) != -1:
			bitVal |= 1024 #2^10
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z) != -1:
			bitVal |= 2048 #2^11
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1) != -1:
			bitVal |= 4096 #2^12
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1) != -1:
			bitVal |= 8192 #2^13
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1) != -1:
			bitVal |= 16384 #2^14
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z) != -1:
			bitVal |= 32768 #2^15
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1) != -1:
			bitVal |= 65536 #2^16
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1) != -1:
			bitVal |= 131072 #2^17
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1) != -1:
			bitVal |= 262144 #2^18
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z) != -1:
			bitVal |= 524288 #2^19
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1) != -1:
			bitVal |= 1048576 #2^20
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1) != -1:
			bitVal |= 2097152 #2^21
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1) != -1:
			bitVal |= 4194304 #2^22
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z) != -1:
			bitVal |= 8388608 #2^23
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1) != -1:
			bitVal |= 16777216 #2^24
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1), lastEditedV, lastEditedCell == -1)
		
		if currentGridmap.get_cell_item(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z) != -1:
			bitVal |= 33554432 #2^25
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z), lastEditedV, lastEditedCell == -1)
		
		if lastEditedCell != -1:
			var orientation = currentGridmap.get_cell_item_orientation(lastEditedV.x, lastEditedV.y, lastEditedV.z)
			if currentGridmap.mesh_library.get_item_name(lastEditedCell).ends_with("_agrid"):
				if !autotileDictionary.has(str(bitVal)):
					print("Corresponding tile not found: ", bitVal)
				else:
					currentGridmap.set_cell_item(lastEditedV.x, lastEditedV.y, lastEditedV.z, autotileDictionary.get(str(bitVal)), orientation)
					print("setted: ", lastEditedV, " id: ", autotileDictionary.get(str(bitVal)))
		lastSize = currentSize

func update_autotile_from_corner(cell : Vector3, corner : Vector3, erase : bool):
	var cellId = currentGridmap.get_cell_item(cell.x, cell.y, cell.z)
	if cellId == -1:
		return
	var values = autotileDictionary.values()
	if cellId != autogridId && !values.has(cellId):
		print("cell: ", cellId)
		return
	var result = cell
	var bitVal : int
	if erase:
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z + 1) != -1:
			bitVal &= ~1 #2^0
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z + 1) != -1:
			bitVal &= ~2 #2^1
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z) != -1:
			bitVal &= ~4 #2^2
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z - 1) != -1:
			bitVal &= ~8 #2^3
			
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z - 1) != -1:
			bitVal &= ~16 #2^4
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z - 1) != -1:
			bitVal &= ~32 #2^5
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z) != -1:
			bitVal &= ~64 #2^6
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z + 1) != -1:
			bitVal &= ~128 #2^7
			
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z) != -1:
			bitVal &= ~256 #2^8
			
		if currentGridmap.get_cell_item(result.x, result.y, result.z + 1) != -1:
			bitVal &= ~512 #2^9
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z + 1) != -1:
			bitVal &= ~1024 #2^10
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z) != -1:
			bitVal &= ~2048 #2^11
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z - 1) != -1:
			bitVal &= ~4096 #2^12
			
		if currentGridmap.get_cell_item(result.x, result.y, result.z - 1) != -1:
			bitVal &= ~8192 #2^13
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z - 1) != -1:
			bitVal &= ~16384 #2^14
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z) != -1:
			bitVal &= ~32768 #2^15
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z + 1) != -1:
			bitVal &= ~65536 #2^16
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z + 1) != -1:
			bitVal &= ~131072 #2^17
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z + 1) != -1:
			bitVal &= ~262144 #2^18
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z) != -1:
			bitVal &= ~524288 #2^19
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z - 1) != -1:
			bitVal &= ~1048576 #2^20
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z - 1) != -1:
			bitVal &= ~2097152 #2^21
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z - 1) != -1:
			bitVal &= ~4194304 #2^22
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z) != -1:
			bitVal &= ~8388608 #2^23
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z + 1) != -1:
			bitVal &= ~16777216 #2^24
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z) != -1:
			bitVal &= ~33554432 #2^25
	else:
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z + 1) != -1:
			bitVal |= 1 #2^0
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z + 1) != -1:
			bitVal |= 2 #2^1
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z) != -1:
			bitVal |= 4 #2^2
			
		if currentGridmap.get_cell_item(result.x + 1, result.y - 1, result.z - 1) != -1:
			bitVal |= 8 #2^3
			
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z - 1) != -1:
			bitVal |= 16 #2^4
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z - 1) != -1:
			bitVal |= 32 #2^5
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z) != -1:
			bitVal |= 64 #2^6
			
		if currentGridmap.get_cell_item(result.x - 1, result.y - 1, result.z + 1) != -1:
			bitVal |= 128 #2^7
			
		if currentGridmap.get_cell_item(result.x, result.y - 1, result.z) != -1:
			bitVal |= 256 #2^8
			
		if currentGridmap.get_cell_item(result.x, result.y, result.z + 1) != -1:
			bitVal |= 512 #2^9
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z + 1) != -1:
			bitVal |= 1024 #2^10
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z) != -1:
			bitVal |= 2048 #2^11
			
		if currentGridmap.get_cell_item(result.x + 1, result.y, result.z - 1) != -1:
			bitVal |= 4096 #2^12
			
		if currentGridmap.get_cell_item(result.x, result.y, result.z - 1) != -1:
			bitVal |= 8192 #2^13
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z - 1) != -1:
			bitVal |= 16384 #2^14
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z) != -1:
			bitVal |= 32768 #2^15
			
		if currentGridmap.get_cell_item(result.x - 1, result.y, result.z + 1) != -1:
			bitVal |= 65536 #2^16
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z + 1) != -1:
			bitVal |= 131072 #2^17
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z + 1) != -1:
			bitVal |= 262144 #2^18
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z) != -1:
			bitVal |= 524288 #2^19
			
		if currentGridmap.get_cell_item(result.x + 1, result.y + 1, result.z - 1) != -1:
			bitVal |= 1048576 #2^20
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z - 1) != -1:
			bitVal |= 2097152 #2^21
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z - 1) != -1:
			bitVal |= 4194304 #2^22
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z) != -1:
			bitVal |= 8388608 #2^23
			
		if currentGridmap.get_cell_item(result.x - 1, result.y + 1, result.z + 1) != -1:
			bitVal |= 16777216 #2^24
			
		if currentGridmap.get_cell_item(result.x, result.y + 1, result.z) != -1:
			bitVal |= 33554432 #2^25
	
	if autotileDictionary.has(str(bitVal)):
		var orientation = currentGridmap.get_cell_item_orientation(cell.x, cell.y, cell.z)
		currentGridmap.set_cell_item(cell.x, cell.y, cell.z, autotileDictionary.get(str(bitVal)), orientation)
		print("updated: ", cell, " id: ", autotileDictionary.get(str(bitVal)))
	else:
		print("Corresponding tile not found: ", bitVal)
	

func get_last_edited_tile() -> Vector3:
	var currentVec = Vector3.ZERO
	var cells = currentGridmap.get_used_cells()
	for cell in cells:
		currentVec += cell
	var result = currentVec - lastVec
	lastVec = currentVec
	if erasing:
		result *= -1
	return result

func get_last_edited_tile_fast(total : Vector3) -> Vector3:
	var result = total - lastVec
	lastVec = total
	if erasing:
		result *= -1
	return result

func _enter_tree():
	#Add popup menu to Project>Tool section
	popupMenu = PopupMenu.new()
	popupMenu.add_item("Create Autotile", 0)
	popupMenu.add_check_item("Autotile", 1)
	popupMenu.add_check_item("Edit Mode", 2)
	popupMenu.connect("id_pressed", self, "popup_pressed")
	add_tool_submenu_item("AutoGrid", popupMenu)
	popupMenu.toggle_item_checked(1)
	
	#Add activate button
	activateButton = preload("res://addons/AutoGrid/activate_button.tscn").instance()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, activateButton)
	activateButton.hide()
	activateButton.core = self
	
	#Create file dialog
	fileDialog = FileDialog.new()
	fileDialog.mode = FileDialog.MODE_SAVE_FILE
	fileDialog.access = FileDialog.ACCESS_RESOURCES
	fileDialog.window_title = "Create Autotile"
	fileDialog.filters = PoolStringArray( ["*.agrid ; AutoGrid files"])
	fileDialog.connect("file_selected", self, "create_autotile_info")
	get_editor_interface().get_base_control().add_child(fileDialog)

func _exit_tree():
	#Remove popup menu from Project>Tool section (It will free popupMenu automatically)
	remove_tool_menu_item("AutoGrid")
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, activateButton)
	if activateButton:
		activateButton.queue_free()
	get_editor_interface().get_base_control().remove_child(fileDialog)
	if fileDialog:
		fileDialog.queue_free()

func popup_pressed(id : int):
	if popupMenu.is_item_checkable(id):
		popupMenu.toggle_item_checked(id)
	if id == 0:
		fileDialog.popup_centered_ratio()
	if id == 1:
		autotileEnabled = popupMenu.is_item_checked(id)
	if id == 2:
		editMode = popupMenu.is_item_checked(id)
		if !editMode:
			activateButton.hide()

func get_selection():
	var nodes = get_editor_interface().get_selection().get_selected_nodes()
	if nodes.size() == 0:
		return null
	return nodes[0]

func set_owner(n : Node):
	n.owner = get_editor_interface().get_edited_scene_root()

func set_bitmask(bitmask : Node):
	set_owner(bitmask)
	bitmask.set_axis(editAxis)
	bitmask.set_size(bitmaskSize)

func increase_bitmasks_size():
	if bitmaskSize < 16:
		bitmaskSize *= 2
	
	set_bitmasks_size()

func decrease_bitmasks_size():
	if bitmaskSize > 0.1:
		bitmaskSize /= 2
	
	set_bitmasks_size()

func set_bitmasks_size():
	var children = get_editor_interface().get_edited_scene_root().get_children()
	for child in children:
		if child.has_node("AutoGrid_Bitmask"):
			var bitmask = child.get_node("AutoGrid_Bitmask")
			bitmask.set_size(bitmaskSize)

func change_icon(iconNode : Node):
	var children = get_editor_interface().get_edited_scene_root().get_children()
	for child in children:
		if child == iconNode:
			child.get_node("AutoGrid_Bitmask").set_for_icon()
			continue
		if child.has_node("AutoGrid_Bitmask"):
			var bitmask = child.get_node("AutoGrid_Bitmask")
			if bitmask.is_icon:
				bitmask.disable_icon()

func create_autotile_info(dir : String):
	var storeDict : Dictionary
	var sceneRoot = get_editor_interface().get_edited_scene_root()
	var children = sceneRoot.get_children()
	if children.size() == 0:
		print("Empty scene!")
		return
	var iconHolder = children[0]
	for child in children:
		if child.name.ends_with("_agrid"):
			child.free()
		if child.has_node("AutoGrid_Bitmask"):
			var bitmask = child.get_node("AutoGrid_Bitmask")
			var bitValue = bitmask.calculate_bit_value()
			storeDict[bitValue] = child.name
			print("name: ", child.name, " bit: ", bitValue)
			if bitmask.is_icon:
				iconHolder = child
	
	var agrid_node : Node = null
	agrid_node = iconHolder.duplicate(0)
	for child in agrid_node.get_children():
		child.queue_free()
	sceneRoot.add_child(agrid_node)
	agrid_node.owner = sceneRoot
	var splittedDir = dir.split("/")
	var fileN = splittedDir[splittedDir.size() - 1].split(".")[0]
	agrid_node.name = fileN + "_agrid"
	agrid_node.mesh.resource_name = dir
	
	var jsonDict = JSON.print(storeDict)
	var saveFile = File.new()
	saveFile.open(dir, File.WRITE)
	saveFile.store_string(jsonDict)
	saveFile.close()
