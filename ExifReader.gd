extends Node2D

const FILE_START_MARKER = PoolByteArray([0xff, 0xd8])
const IMAGE_START_MARKER = PoolByteArray([0xff, 0xda])
const EXIF_MARKER = PoolByteArray([0xff, 0xe1])

const SIZE_LOOKUP = [1, 1, 2, 4, 8, 1, 1, 2, 4, 8]


# Called when the node enters the scene tree for the first time.
func _ready():
	var files = get_files_recursive('//nas1/media/Picture Frame Pics/ON1')
	for file in files:
		print('---------------------')
		print(file)
		#var file = "c:/users/jeff/desktop/2019-01-22_110256.jpg"
		#file = 'r:/Pictures/ON1/2008-07-08_20-44-58-70.jpg'
		var time1 = OS.get_system_time_msecs()
		var exif_section = get_exif_from_jpeg(file)
		var exif = {}
		if exif_section.size() > 0:
			exif = parse_exif_data(exif_section)
		var time2 = OS.get_system_time_msecs()
		print("%d, %d, %d" % [time1, time2, time2 - time1])
		print(exif)
		#break

func parse_exif_data(exif_section: PoolByteArray) -> Dictionary:
	var results = {}
	var stream = StreamPeerBuffer.new()
	stream.data_array = exif_section
	var sect = stream.get_string(4)
	var nulls = stream.get_u16()
	var tiff_header = stream.get_position()
	var endian = stream.get_string(2)
	stream.big_endian = endian != "II"
	var signature = stream.get_u16()
	var ifd_offset = stream.get_u32() # <-----
	var ifd0 = read_tags(stream, tiff_header, ifd_offset, Globals.exif_tags)

	if ifd0.has('ExifOffset') && ifd0['ExifOffset'] > 0:
		results['exif'] = read_tags(stream, tiff_header, ifd0['ExifOffset'],
		Globals.exif_tags)
	if ifd0.has('GPSInfo') && ifd0['GPSInfo'] > 0:
		results['gps'] = read_tags(stream, tiff_header, ifd0['GPSInfo'], Globals.gps_tags)
	return results

func read_tags(stream: StreamPeerBuffer, tiff_header: int, offset: int, tags_collection: Dictionary) -> Dictionary:
	var tags = {}
	# seek the ifd as "tiff_header + offset"
	stream.seek(tiff_header + offset)

	var num_entries = stream.get_u16()
	for i in range(num_entries):
		var tag = stream.get_u16()
		var value = read_tag(stream, tiff_header)

		if tags_collection.has(tag):
			tags[tags_collection[tag]] = value
		else:
			tags[tag] = value

	return tags

func read_tag(stream: StreamPeerBuffer, tiff_header: int):
	var type = stream.get_u16()
	var num_vals = stream.get_u32()
	var value_size = SIZE_LOOKUP[type - 1];
	var value_offset = 0 if value_size * num_vals <= 4 else stream.get_u32()
	var stream_loc = -1

	# if we have an offset for this value, remember this location so we can
	# return to it, then seek to the new offset (always from "tiff_header")
	if value_offset != 0:
		stream_loc = stream.get_position()
		stream.seek(tiff_header + value_offset)

	var value = null
	if type == 2:
		value = stream.get_string(num_vals * value_size).strip_edges()
	elif type == 7:
		var t = stream.get_string(8) # type (ASCII,  JIS, Unicode, or Undefined)
		if t == 'ASCII':
			value = stream.get_string(num_vals * value_size - 8).strip_edges()
		else:
			stream.seek(stream.get_position() - 8)
			value = stream.get_partial_data(num_vals * value_size)
	else:
		var vals = []
		for v in range(num_vals):
			vals.append(read_value(stream, value_offset, type))
		value = vals if num_vals > 1 else vals[0]

	# special case - move past any unused (null-padded) bytes in this value
	if value_offset == 0:
		var extra_bytes = 4 - (num_vals * value_size)
		stream.seek(stream.get_position() + extra_bytes)

	# if we had to offet the stream pointer to access the current value,
	# reset it to the stored location prior to returning
	if stream_loc != -1: stream.seek(stream_loc)

	return value

func read_value(stream: StreamPeerBuffer, value_offset: int, type: int):
	#if value_offset != 0: stream.seek(stream.get_position() + value_offset)
	match(type):
		1: return stream.get_u8()
		3: return stream.get_u16()
		4: return stream.get_u32()
		5: return float(stream.get_u32()) / stream.get_u32()
		6: return stream.get_8()
		8: return stream.get_16()
		9: return stream.get_32()
		10: return float(stream.get_32()) / stream.get_32()

func get_exif_from_jpeg(imageFile: String) -> PoolByteArray:
	var exif_section = PoolByteArray([])
	var file = File.new()
	file.open(imageFile, File.READ)
	file.endian_swap = true # main JPG is ALWAYS big endian (EXIF data could vary)

	while file.get_position() < file.get_len():
		var marker = file.get_buffer(2)
		if marker == FILE_START_MARKER: continue
		var buf_len = file.get_16() - 2
		if marker == EXIF_MARKER:
			exif_section = file.get_buffer(buf_len)
			break
		else:
			file.seek(file.get_position() + buf_len)

	return exif_section

func get_files_recursive(scan_dir : String) -> Array:
	var my_files : Array = []
	var dir := Directory.new()
	if dir.open(scan_dir) != OK:
		printerr("Warning: could not open directory: ", scan_dir)
		return []

	if dir.list_dir_begin(true, true) != OK:
		printerr("Warning: could not list contents of: ", scan_dir)
		return []

	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			my_files += get_files_recursive(dir.get_current_dir() + "/" + file_name)
		else:
			my_files.append(dir.get_current_dir() + "/" + file_name)

		file_name = dir.get_next()

	randomize()
	my_files.shuffle()
	return my_files
