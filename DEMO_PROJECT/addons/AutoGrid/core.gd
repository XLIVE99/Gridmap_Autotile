@tool
extends EditorPlugin

var popupMenu : PopupMenu
var activateButton : Control
var optionsButton : Control
var fileDialog : FileDialog

var autotileEnabled := true
var editMode := false: set = editmode_changed
var performanceMode := true
var currentGridmap : GridMap
var currentMeshInstance : MeshInstance3D

var getDraw := false
var erasing := false
var lastSize : int = 0
var lastVec := Vector3.ZERO

var bitmaskSize : float = 1.0
var editAxis : int = 0: set = axis_changed
var autoAxis : int = 0 #Check the AUTO_AXIS
var scanAxis : int = 1 #0=AxisX, 1=AxisY, 2=AxisZ

var autotileDictionary : Dictionary
var autogridId : int
var bitmaskMode : int = 0 #0=full 3x3, minimal 3x3
var emptyTileId : int

var editedCells : PackedVector3Array

const BITMASK_BOX = preload("res://addons/AutoGrid/bitmask_box.gd")

const AUTO_AXIS = [
	67108863, #All
	35791633, #Only X
	130560, #Only Y
	42502468 #Only Z
]

# This is called multiple times if multiple object selected
func _handles(object) -> bool:
	# Disable previous bitmask (if any)
	if is_instance_valid(currentMeshInstance) && currentMeshInstance.has_node("AutoGrid_Bitmask"):
		currentMeshInstance.get_node("AutoGrid_Bitmask").deactivate()
	
	var showActivateBtn := false
	var shouldHandle := false
	
	if object is GridMap:
		#activateButton.hide()
		shouldHandle = true
	elif object is Node3D and is_instance_valid(is_any_parent(object, "MeshInstance3D")):
		
		# Since bitmasks are meshInstance if we click on bitmask, AutoGrid
		# detect it as a tile. I have implemented a hacky solution for now
		# Need improvement!
		var meshInstance = is_any_parent(object, "MeshInstance3D")
		if meshInstance.name.begins_with("AutoGrid"):
			# WARNING: Parent is outside of the tree in AutoGrid_Bitmask.tscn
			meshInstance = meshInstance.get_parent()
		
		if meshInstance.is_inside_tree() and meshInstance is MeshInstance3D:
			# Always update current mesh instance
			# only used in edit mode
			currentMeshInstance = meshInstance
		
		if editMode:
			#activateButton.show()
			showActivateBtn = true
			shouldHandle = true
	
	if editMode:
		# Check if the user selected multiple nodes
		# Don't use object variable becuase "MultiNodeEdit" type used when multiple objects selected
		var selecteds = get_selection_list()
		if selecteds != null:
			for selected in selecteds:
				if selected is MeshInstance3D:
					#activateButton.show()
					showActivateBtn = true
					# DO NOT RETURN TRUE, Multiple edit is not supported yet due to AutoGrid
					# depends on currentMeshInstance variable
	
	activateButton.visible = showActivateBtn
	return shouldHandle

func _edit(object):
	# Try load autotile info
	if object is GridMap:
		currentGridmap = object
		currentMeshInstance = null
		lastSize = currentGridmap.get_used_cells().size()
		if autotileEnabled:
			load_autotile_info()
	# Check if current selected mesh instance has bitmask then activate it
	#elif is_instance_valid(is_any_parent(object, "MeshInstance3D")):
	elif currentMeshInstance is MeshInstance3D:
		#currentMeshInstance = is_any_parent(object, "MeshInstance3D")
		if currentMeshInstance.has_node("AutoGrid_Bitmask"):
			currentMeshInstance.get_node("AutoGrid_Bitmask").activate()
			currentMeshInstance.get_node("AutoGrid_Bitmask").set_axis(editAxis)
		currentGridmap = null

func load_autotile_info():
	if currentGridmap.mesh_library == null:
		print("--- AUTOGRID ERROR --- Mesh library is null. Please assign MeshLibrary on ", currentGridmap.name, " named GridMap node. Then re-select the GridMap node.")
		return
	
	autotileDictionary.clear()
	var fileDir : String
	for i in currentGridmap.mesh_library.get_item_list():
		if currentGridmap.mesh_library.get_item_name(i).ends_with("_agrid"):
			fileDir = currentGridmap.mesh_library.get_item_mesh(i).resource_name
			autogridId = i
	
	if fileDir.is_empty():
		print("--- AUTOGRID WARNING --- super.agrid file couldn't find for this GridMap node. Please create autotile or disable autotile from AutoGrid window")
		return
	
	if load_autotile_info_from(fileDir):
		print("--- AUTOGRID INFO --- AutoGrid is ready to use!")

func load_autotile_info_from(fileDir : String, changeNameToId : bool = true) -> bool:
	var loadFile = FileAccess.open(fileDir, FileAccess.READ)
	if loadFile == null:
		print("--- AUTOGRID ERROR --- File couldn't find at ", fileDir)
		loadFile.close()
		return false
	var content = loadFile.get_as_text()
	loadFile.close()
	
	var test_json_conv = JSON.new()
	var jsonERR = test_json_conv.parse(content)
	if jsonERR != OK:
		print("--- AUTOGRID ERROR --- Error occured while parsing Json: ", test_json_conv.get_error_message(), " at ", test_json_conv.get_error_line())
		return false
	
	autotileDictionary = test_json_conv.data
	
	if changeNameToId:
		var keys = autotileDictionary.keys()
		var values = autotileDictionary.values()
		for i in currentGridmap.mesh_library.get_item_list():
			var itemName = currentGridmap.mesh_library.get_item_name(i)
			for j in values.size():
				if itemName == values[j]:
					autotileDictionary[keys[j]] = i
		if autotileDictionary[keys[0]] != autogridId:
			emptyTileId = autotileDictionary[keys[0]]
		else:
			emptyTileId = autotileDictionary[keys[1]]
	
	return true

func editmode_changed(val):
	editMode = val
	if !editMode:
		activateButton.hide()
		
		if is_instance_valid(currentMeshInstance) && currentMeshInstance.has_node("AutoGrid_Bitmask"):
			currentMeshInstance.get_node("AutoGrid_Bitmask").deactivate()
	elif is_instance_valid(currentMeshInstance):
		activateButton.show()
		
		if currentMeshInstance.has_node("AutoGrid_Bitmask"):
			currentMeshInstance.get_node("AutoGrid_Bitmask").activate()
	
	# Update every bitmasks visibility
	var children = get_editor_interface().get_edited_scene_root().get_children()
	for child in children:
		if child.has_node("AutoGrid_Bitmask"):
			var bitmask = child.get_node("AutoGrid_Bitmask")
			bitmask.visible = val

func axis_changed(val):
	editAxis = val
	var children = get_editor_interface().get_edited_scene_root().get_children()
	for child in children:
		if child.has_node("AutoGrid_Bitmask"):
			child.get_node("AutoGrid_Bitmask").set_axis(editAxis, child == currentMeshInstance)

func _forward_3d_gui_input(camera, event) -> int:
	
	if autotileEnabled && is_instance_valid(currentGridmap):
		gridmap_inputs(event)
	if editMode && is_instance_valid(currentMeshInstance):
		return bitmask_inputs(camera, event)
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func gridmap_inputs(event):
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				getDraw = true
				erasing = false
				#lastSize = max(lastSize - 1, 0)
				add_to_edited_cells()
			else:
				getDraw = false
				await get_tree().process_frame
				check_autotile()
		
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				getDraw = true
				erasing = true
				#lastSize = lastSize + 1
				add_to_edited_cells()
			else:
				getDraw = false
				await get_tree().process_frame
				check_autotile()
	
	if getDraw:
		if event is InputEventMouseMotion:
			add_to_edited_cells()

func bitmask_inputs(camera : Camera3D, event : InputEvent) -> int:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			var ray_origin = camera.project_ray_origin(event.position)
			var ray_dir = camera.project_ray_normal(event.position)
			var ray_distance = camera.far
			
			var space_state =  camera.get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * ray_distance, 524288)
			var hit = space_state.intersect_ray(query)
			if !hit.is_empty() and hit.collider is BITMASK_BOX and hit.collider.is_visible_in_tree():
				hit.collider.toggle_box()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func add_to_edited_cells():
	#Calling get_used_cells require lots of work, use it less!!
	var cells = currentGridmap.get_used_cells()
	var currentSize : int = cells.size()
	
	if currentSize == 0:
		return
	if currentSize != lastSize:
		var totalV = Vector3.ZERO
		for cell in cells:
			totalV += cell as Vector3
		var lastEditedV = get_last_edited_tile_fast(totalV)
		editedCells.append(lastEditedV)
		lastSize = currentSize
	elif !performanceMode:
		for cell in cells:
			var appendCell := true
			var cellID = currentGridmap.get_cell_item(cell)
			if cellID == autogridId:
				for editedCell in editedCells:
					if editedCell == (cell as Vector3):
						appendCell = false
						break
				if appendCell:
					editedCells.append(cell)

func check_autotile():
	for editedCell in editedCells:
		var lastEditedV = editedCell
		var lastEditedCell = currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z))
		var bitVal = 0
		
		var values = autotileDictionary.values()
		
		if lastEditedCell != -1 && lastEditedCell != autogridId && !values.has(lastEditedCell):
			#print("Its not autotile: ", currentGridmap.mesh_library.get_item_name(lastEditedCell))
			continue
		
		#Universal scans
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z)) != -1:
			bitVal |= 256 #2^8
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z))
		
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1)) != -1:
			bitVal |= 512 #2^9
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1))
		
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z)) != -1:
			bitVal |= 2048 #2^11
			update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z))
		
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1)) != -1:
			bitVal |= 8192 #2^13
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1))
		
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z)) != -1:
			bitVal |= 32768 #2^15
			update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z))
		
		if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z)) != -1:
			bitVal |= 33554432 #2^25
			update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z))
		
		#X axis scan
		if scanAxis == 0:
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
				bitVal |= 4 #2^2
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
				
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
				bitVal |= 64 #2^6
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
				bitVal |= 1024 #2^10
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
				bitVal |= 4096 #2^12
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
				bitVal |= 16384 #2^14
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
				bitVal |= 65536 #2^16
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
				bitVal |= 524288 #2^19
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
				bitVal |= 8388608 #2^23
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
		
		#Y axis scan
		elif scanAxis == 1:
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
				bitVal |= 1 #2^0
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
				
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
				bitVal |= 4 #2^2
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
				bitVal |= 16 #2^4
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
				bitVal |= 64 #2^6
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
				bitVal |= 131072 #2^17
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
				bitVal |= 524288 #2^19
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
				bitVal |= 2097152 #2^21
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
				bitVal |= 8388608 #2^23
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
		
		#Z scan axis
		elif scanAxis == 2:
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
				bitVal |= 1 #2^0
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
				
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
				bitVal |= 16 #2^4
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
				bitVal |= 1024 #2^10
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
				bitVal |= 4096 #2^12
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
				bitVal |= 16384 #2^14
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
				bitVal |= 65536 #2^16
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
				bitVal |= 131072 #2^17
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
				bitVal |= 2097152 #2^21
				update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
		
		if bitmaskMode == 0: #full 3x3
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
				bitVal |= 2 #2^1
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
				bitVal |= 8 #2^3
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
				bitVal |= 32 #2^5
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
				bitVal |= 128 #2^7
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
				bitVal |= 262144 #2^18
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
				bitVal |= 1048576 #2^20
				update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
				bitVal |= 4194304 #2^22
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1))
			
			if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
				bitVal |= 16777216 #2^24
				update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1))
			
			if scanAxis == 0: #X scan axis
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
					bitVal |= 1 #2^0
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
					bitVal |= 16 #2^4
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
					bitVal |= 131072 #2^17
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
					bitVal |= 2097152 #2^21
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
			
			elif scanAxis == 1: #Y scan axis
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 1024 #2^10
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 4096 #2^12
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 16384 #2^14
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 65536 #2^16
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
			
			elif scanAxis == 2: #Z scan axis
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 4 #2^2
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 64 #2^6
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 524288 #2^19
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 8388608 #2^23
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
		
		elif bitmaskMode == 1: #minimal 3x3
			if scanAxis == 0: #X scan axis
				#First ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 65728 #2^6 + 2^7 + 2^16
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 25231360 #2^16 + 2^24 + 2^23
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 12599296 #2^23 + 2^22 + 2^14
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 16480 #2^14 + 2^5 + 2^6
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
				#Second ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 769 #2^8 + 2^0 + 2^9
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 33686016 #2^9 + 2^17 + 2^25
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 35659776 #2^25 + 2^21 + 2^13
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 8464 #2^13 + 2^4 + 2^8
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z))
				#Third ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 1030 #2^2 + 2^1 + 2^10
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 787456 #2^10 + 2^18 + 2^19
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 1576960 #2^19 + 2^20 + 2^12
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 4108 #2^12 + 2^3 + 2^2
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
			
			elif scanAxis == 1: #Y scan axis
				#First ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 7 #2^0 + 2^1 + 2^2
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
					bitVal |= 28 #2^2 + 2^3 + 2^4
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 112 #2^4 + 2^5 + 2^6
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
					bitVal |= 193 #2^6 + 2^7 + 2^0
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
				#Second ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z)) != -1:
					bitVal |= 3584 #2^9 + 2^10 + 2^11
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 14336 #2^11 + 2^12 + 2^13
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z)) != -1:
					bitVal |= 57344 #2^13 + 2^14 + 2^15
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 98816 #2^15 + 2^16 + 2^9
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z + 1))
				#Third ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 917504 #2^17 + 2^18 + 2^19
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
					bitVal |= 3670016 #2^19 + 2^20 + 2^21
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 14680064 #2^21 + 2^22 + 2^23
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
					bitVal |= 25296896 #2^23 + 2^24 + 2^17
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
			
			elif scanAxis == 2: #Z scan axis
				#First ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 16432 #2^4 + 2^5 + 2^14
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1:
					bitVal |= 6307840 #2^14 + 2^22 + 2^21
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1:
					bitVal |= 3149824 #2^21 + 2^20 + 2^12
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1)) != -1:
					bitVal |= 4120 #2^12 + 2^3 + 2^4
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z - 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z - 1))
				#Second ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z)) != -1:
					bitVal |= 33088 #2^8 + 2^6 + 2^15
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z)) != -1:
					bitVal |= 41975808 #2^15 + 2^23 + 2^25
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z)) != -1:
					bitVal |= 34080768 #2^25 + 2^19 + 2^11
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z)) != -1:
					bitVal |= 2308 #2^11 + 2^2 + 2^8
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z))
				#Third ---------------
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 65665 #2^0 + 2^7 + 2^16
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1:
					bitVal |= 16973824 #2^16 + 2^24 + 2^17
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x - 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1:
					bitVal |= 394240 #2^17 + 2^18 + 2^10
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y + 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
				
				if currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1)) != -1\
				&& currentGridmap.get_cell_item(Vector3i(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1)) != -1:
					bitVal |= 1027 #2^10 + 2^1 + 2^0
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x + 1, lastEditedV.y - 1, lastEditedV.z + 1))
					update_autotile_from_corner(Vector3(lastEditedV.x, lastEditedV.y - 1, lastEditedV.z + 1))
		
		bitVal &= AUTO_AXIS[autoAxis]
		
		if lastEditedCell == autogridId:
			var orientation = currentGridmap.get_cell_item_orientation(Vector3i(lastEditedV.x, lastEditedV.y, lastEditedV.z))
			if !autotileDictionary.has(str(bitVal)):
				#print("Corresponding tile not found: ", bitVal)
				pass
			else:
				currentGridmap.set_cell_item(Vector3(lastEditedV.x, lastEditedV.y, lastEditedV.z), autotileDictionary.get(str(bitVal)), orientation)
				#print("setted: ", lastEditedV, " id: ", autotileDictionary.get(str(bitVal)))
	editedCells.resize(0)

func update_autotile_from_corner(cell : Vector3):
	var cellId = currentGridmap.get_cell_item(Vector3i(cell.x, cell.y, cell.z))
	if cellId == -1:
		return
	var values = autotileDictionary.values()
	if cellId != autogridId && !values.has(cellId):
		#print("cell: ", cellId)
		return
	var result = cell
	var bitVal : int
	
	#Universal scans
	if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z)) != -1:
		bitVal |= 256 #2^8
	
	if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z + 1)) != -1:
		bitVal |= 512 #2^9
	
	if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z)) != -1:
		bitVal |= 2048 #2^11
	
	if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z - 1)) != -1:
		bitVal |= 8192 #2^13
	
	if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z)) != -1:
		bitVal |= 32768 #2^15
	
	if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z)) != -1:
		bitVal |= 33554432 #2^25
	
	#X axis scan
	if scanAxis == 0:
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1:
			bitVal |= 4 #2^2
			
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1:
			bitVal |= 64 #2^6
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1:
			bitVal |= 1024 #2^10
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1:
			bitVal |= 4096 #2^12
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1:
			bitVal |= 16384 #2^14
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1:
			bitVal |= 65536 #2^16
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1:
			bitVal |= 524288 #2^19
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1:
			bitVal |= 8388608 #2^23
	
	#Y axis scan
	elif scanAxis == 1:
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1:
			bitVal |= 1 #2^0
			
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1:
			bitVal |= 4 #2^2
		
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1:
			bitVal |= 16 #2^4
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1:
			bitVal |= 64 #2^6
		
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1:
			bitVal |= 131072 #2^17
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1:
			bitVal |= 524288 #2^19
		
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1:
			bitVal |= 2097152 #2^21
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1:
			bitVal |= 8388608 #2^23
	
	#Z scan axis
	elif scanAxis == 2:
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1:
			bitVal |= 1 #2^0
			
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1:
			bitVal |= 16 #2^4
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1:
			bitVal |= 1024 #2^10
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1:
			bitVal |= 4096 #2^12
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1:
			bitVal |= 16384 #2^14
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1:
			bitVal |= 65536 #2^16
		
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1:
			bitVal |= 131072 #2^17
		
		if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1:
			bitVal |= 2097152 #2^21
	
	if bitmaskMode == 0: #full 3x3
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z + 1)) != -1:
			bitVal |= 2 #2^1
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z - 1)) != -1:
			bitVal |= 8 #2^3
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z - 1)) != -1:
			bitVal |= 32 #2^5
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z + 1)) != -1:
			bitVal |= 128 #2^7
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z + 1)) != -1:
			bitVal |= 262144 #2^18
		
		if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z - 1)) != -1:
			bitVal |= 1048576 #2^20
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z - 1)) != -1:
			bitVal |= 4194304 #2^22
		
		if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z + 1)) != -1:
			bitVal |= 16777216 #2^24
		
		if scanAxis == 0: #X scan axis
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1:
				bitVal |= 1 #2^0
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1:
				bitVal |= 16 #2^4
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1:
				bitVal |= 131072 #2^17
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1:
				bitVal |= 2097152 #2^21
		
		elif scanAxis == 1: #Y scan axis
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1:
				bitVal |= 1024 #2^10
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1:
				bitVal |= 4096 #2^12
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1:
				bitVal |= 16384 #2^14
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1:
				bitVal |= 65536 #2^16
		
		elif scanAxis == 2: #Z scan axis
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1:
				bitVal |= 4 #2^2
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1:
				bitVal |= 64 #2^6
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1:
				bitVal |= 524288 #2^19
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1:
				bitVal |= 8388608 #2^23
	
	elif bitmaskMode == 1: #minimal 3x3
		if scanAxis == 0: #X scan axis
			#First ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1:
				bitVal |= 65728 #2^6 + 2^7 + 2^16
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1:
				bitVal |= 25231360 #2^16 + 2^24 + 2^23
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1:
				bitVal |= 12599296 #2^23 + 2^22 + 2^14
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1:
				bitVal |= 16480 #2^14 + 2^5 + 2^6
			#Second ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z + 1)) != -1:
				bitVal |= 769 #2^8 + 2^0 + 2^9
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z)) != -1:
				bitVal |= 33686016 #2^9 + 2^17 + 2^25
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z - 1)) != -1:
				bitVal |= 35659776 #2^25 + 2^21 + 2^13
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z)) != -1:
				bitVal |= 8464 #2^13 + 2^4 + 2^8
			#Third ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1:
				bitVal |= 1030 #2^2 + 2^1 + 2^10
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1:
				bitVal |= 787456 #2^10 + 2^18 + 2^19
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1:
				bitVal |= 1576960 #2^19 + 2^20 + 2^12
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1:
				bitVal |= 4108 #2^12 + 2^3 + 2^2
		
		elif scanAxis == 1: #Y scan axis
			#First ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1:
				bitVal |= 7 #2^0 + 2^1 + 2^2
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1:
				bitVal |= 28 #2^2 + 2^3 + 2^4
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1:
				bitVal |= 112 #2^4 + 2^5 + 2^6
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1:
				bitVal |= 193 #2^6 + 2^7 + 2^0
			#Second ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z)) != -1:
				bitVal |= 3584 #2^9 + 2^10 + 2^11
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z - 1)) != -1:
				bitVal |= 14336 #2^11 + 2^12 + 2^13
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z)) != -1:
				bitVal |= 57344 #2^13 + 2^14 + 2^15
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y, result.z + 1)) != -1:
				bitVal |= 98816 #2^15 + 2^16 + 2^9
			#Third ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1:
				bitVal |= 917504 #2^17 + 2^18 + 2^19
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1:
				bitVal |= 3670016 #2^19 + 2^20 + 2^21
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1:
				bitVal |= 14680064 #2^21 + 2^22 + 2^23
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1:
				bitVal |= 25296896 #2^23 + 2^24 + 2^17
		
		elif scanAxis == 2: #Z scan axis
			#First ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1:
				bitVal |= 16432 #2^4 + 2^5 + 2^14
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1:
				bitVal |= 6307840 #2^14 + 2^22 + 2^21
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1:
				bitVal |= 3149824 #2^21 + 2^20 + 2^12
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z - 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z - 1)) != -1:
				bitVal |= 4120 #2^12 + 2^3 + 2^4
			#Second ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z)) != -1:
				bitVal |= 33088 #2^8 + 2^6 + 2^15
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z)) != -1:
				bitVal |= 41975808 #2^15 + 2^23 + 2^25
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z)) != -1:
				bitVal |= 34080768 #2^25 + 2^19 + 2^11
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z)) != -1:
				bitVal |= 2308 #2^11 + 2^2 + 2^8
			#Third ---------------
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1:
				bitVal |= 65665 #2^0 + 2^7 + 2^16
			
			if currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x - 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1:
				bitVal |= 16973824 #2^16 + 2^24 + 2^17
			
			if currentGridmap.get_cell_item(Vector3i(result.x, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y + 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1:
				bitVal |= 394240 #2^17 + 2^18 + 2^10
			
			if currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x + 1, result.y - 1, result.z + 1)) != -1\
			&& currentGridmap.get_cell_item(Vector3i(result.x, result.y - 1, result.z + 1)) != -1:
				bitVal |= 1027 #2^10 + 2^1 + 2^0
	
	bitVal &= AUTO_AXIS[autoAxis]
	
	if autotileDictionary.has(str(bitVal)):
		var orientation = currentGridmap.get_cell_item_orientation(Vector3i(cell.x, cell.y, cell.z))
		currentGridmap.set_cell_item(Vector3(cell.x, cell.y, cell.z), autotileDictionary.get(str(bitVal)), orientation)
		#print("updated: ", cell, " id: ", autotileDictionary.get(str(bitVal)))
	else:
		pass
		#print("Corresponding tile not found: ", bitVal)
	

func get_last_edited_tile() -> Vector3:
	var currentVec = Vector3.ZERO
	var cells = currentGridmap.get_used_cells()
	for cell in cells:
		currentVec += cell as Vector3
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
	#Add activate button
	activateButton = preload("res://addons/AutoGrid/activate_button.tscn").instantiate()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, activateButton)
	activateButton.hide()
	activateButton.core = self
	
	#Add options button
	optionsButton = preload("res://addons/AutoGrid/gridmap_button.tscn").instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, optionsButton)
	optionsButton.hide()
	optionsButton.core = self
	
	#Create file dialog
	fileDialog = FileDialog.new()
	fileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fileDialog.access = FileDialog.ACCESS_RESOURCES
	fileDialog.title = "Create Autotile"
	fileDialog.filters = PackedStringArray( ["*.agrid ; AutoGrid files"])
	fileDialog.connect("file_selected", Callable(self, "create_autotile_info"))
	get_editor_interface().get_base_control().add_child(fileDialog)
	
	# Update current selected mesh
	if is_instance_valid(get_selection()):
		_handles(get_selection())
	
	var eds = get_editor_interface().get_selection()
	eds.selection_changed.connect(_selection_changed)
	
	scene_changed.connect(_scene_changed)

func _exit_tree():
	#Remove popup menu from Project>Tool section (It will free popupMenu automatically)
	remove_tool_menu_item("AutoGrid")
	
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, activateButton)
	if activateButton:
		activateButton.queue_free()
	
	remove_control_from_docks(optionsButton)
	if optionsButton:
		optionsButton.queue_free()
	
	get_editor_interface().get_base_control().remove_child(fileDialog)
	if fileDialog:
		fileDialog.queue_free()
	
	var eds = get_editor_interface().get_selection()
	eds.disconnect("selection_changed", _selection_changed)
	
	if editMode:
		# Update bitmask visibility (setget handles the rest)
		self.editMode = false
	
	disconnect("scene_changed", _scene_changed)

func _selection_changed():
	if !is_instance_valid(get_selection()):
		# If we clicked to nothing, then disable bitmask
		if is_instance_valid(currentMeshInstance) && currentMeshInstance.has_node("AutoGrid_Bitmask"):
			currentMeshInstance.get_node("AutoGrid_Bitmask").deactivate()

func _scene_changed(root : Node):
	
	# New scene, no need to reload autotile info
	if !is_instance_valid(root):
		return
	
	# WARNING! The user might lose progress if switch between tabs while editing the tiles
	# Only try to find autotile info if edit mode is enabled
	#if editMode:
		# Load autotile info automatically when tab changes
		#reload_autotile_info(false)
	
	# Update visibility
	self.editMode = editMode
	
	# Update bitmask sizes
	set_bitmasks_size()
	
	# Update edit axis
	self.editAxis = editAxis

func create_autotile_pressed():
	fileDialog.popup_centered_ratio()

func set_owner(n : Node):
	n.owner = get_editor_interface().get_edited_scene_root()

func set_bitmask(bitmask : Node):
	bitmask.set_axis(editAxis)
	bitmask.set_size(bitmaskSize)
	bitmask.activate()

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

func reload_autotile_info(verbose : bool):
	var children = get_editor_interface().get_edited_scene_root().get_children()
	if children.size() == 0:
		if verbose:
			print("--- AUTOGRID ERROR --- Empty scene!")
		return
	
	var fileDir : String
	for child in children:
		if child.name.ends_with("_agrid"):
			fileDir = child.mesh.resource_name
			break
	
	if fileDir.is_empty():
		if verbose:
			print("--- AUTOGRID ERROR --- autotile info couldn't find.")
		return
	
	load_autotile_info_from(fileDir, false)
	
	var keys = autotileDictionary.keys()
	var values = autotileDictionary.values()
	
	for child in children:
		if child.has_node("AutoGrid_Bitmask"):
			for i in values.size():
				if child.name == values[i]:
					child.get_node("AutoGrid_Bitmask").enable_from_bit(int(keys[i]))
	
	autotileDictionary.is_empty()

func create_autotile_info(dir : String):
	var storeDict : Dictionary
	var sceneRoot = get_editor_interface().get_edited_scene_root()
	var children = sceneRoot.get_children()
	if children.size() == 0:
		print("--- AUTOGRID ERROR --- Empty scene!")
		return
	var iconHolder = children[0]
	var waitAFrame = false
	for child in children:
		if child.name.ends_with("_agrid"):
			child.free()
			waitAFrame = true
			continue
		if child.has_node("AutoGrid_Bitmask"):
			var bitmask = child.get_node("AutoGrid_Bitmask")
			var bitValue = bitmask.calculate_bit_value()
			storeDict[bitValue] = child.name
			#print("name: ", child.name, " bit: ", bitValue)
			if bitmask.is_icon:
				iconHolder = child
	
	if waitAFrame:
		await get_tree().idle_frame
	
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
	
	var jsonDict = JSON.stringify(storeDict)
	var saveFile = FileAccess.open(dir, FileAccess.WRITE)
	#saveFile.open(dir, File.WRITE) (Godot 3.x method)
	saveFile.store_string(jsonDict)
	saveFile.close()

# ========= HELPER METHODS =========

func get_selection():
	var nodes = get_editor_interface().get_selection().get_selected_nodes()
	if nodes.size() == 0:
		return null
	return nodes[0]

func get_selection_list():
	var nodes = get_editor_interface().get_selection().get_selected_nodes()
	if nodes.size() == 0:
		return null
	return nodes

func is_any_parent(node : Node, type : String) -> Node:
	
	if !is_instance_valid(node):
		return null
	
	if node.is_class(type):
		return node
	
	# Otherwise continue search parents recursively
	if is_instance_valid(node.get_parent()):
		return is_any_parent(node.get_parent(), type)
	# There is no more parent left
	else:
		return null
