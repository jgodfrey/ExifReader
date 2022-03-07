extends Node2D

const FILE_START_MARKER = PoolByteArray([0xff, 0xd8])
const IMAGE_START_MARKER = PoolByteArray([0xff, 0xda])
const EXIF_MARKER = PoolByteArray([0xff, 0xe1])

const SIZE_LOOKUP = [1, 1, 2, 4, 8, 1, 1, 2, 4, 8]
var _tiff_header


# Called when the node enters the scene tree for the first time.
func _ready():
	var files = get_files_recursive('//nas1/media/Picture Frame Pics/ON1')
	for file in files:
		print('---------------------')
		print(file)
		#var file = "c:/users/jeff/desktop/2019-01-22_110256.jpg"
		#file = 'r:/Pictures/ON1/2008-07-08_20-44-58-70.jpg'
		var time1 = OS.get_system_time_msecs()
		var exif_section = get_exif_section(file)
		var exif = {}
		if exif_section.size() > 0:
			exif = parse_exif_section(exif_section)
		var time2 = OS.get_system_time_msecs()
		print("%d, %d, %d" % [time1, time2, time2 - time1])
		#print(exif)
		#break

func parse_exif_section(exif_section: PoolByteArray) -> Dictionary:
	var results = {}
	var stream = StreamPeerBuffer.new()
	stream.data_array = exif_section
	var sect = stream.get_string(4)
	var nulls = stream.get_u16()
	_tiff_header = stream.get_position()
	var endian = stream.get_string(2)
	stream.big_endian = endian != "II"
	var signature = stream.get_u16()
	var ifd_offset = stream.get_u32() # <-----
	var ifd0 = read_tags(stream, _tiff_header + ifd_offset, exif_tags)
	print(ifd0)

	if ifd0.has('ExifOffset') && ifd0['ExifOffset'] > 0:
		results['exif'] = read_tags(stream, _tiff_header + ifd0['ExifOffset'], exif_tags)
	if ifd0.has('GPSInfo') && ifd0['GPSInfo'] > 0:
		results['gps'] = read_tags(stream, _tiff_header + ifd0['GPSInfo'], gps_tags)
	return results

func read_tags(stream: StreamPeerBuffer, offset: int, tags_collection: Dictionary) -> Dictionary:
	var tags = {}
	# seek the ifd as "tiff_header + offset"
	stream.seek(offset)

	var num_entries = stream.get_u16()
	for i in range(num_entries):
		var tag = stream.get_u16()
		var type = stream.get_u16()
		var num_vals = stream.get_u32()
		var value_size = SIZE_LOOKUP[type - 1];
		var value_offset = 0 if value_size * num_vals <= 4 else stream.get_u32()

		var curr_pos = -1

		# if we have an offset for this value, remember this location so we can
		# return to it, then seek to the new offset (always from "tiff_header")
		if value_offset != 0:
			curr_pos = stream.get_position()
			stream.seek(_tiff_header + value_offset)

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

		if tags_collection.has(tag):
			tags[tags_collection[tag]] = value
		else:
			tags[tag] = value

		# special case - move past any unused (null-padded) bytes in this value
		if value_offset == 0:
			var extra_bytes = 4 - (num_vals * value_size)
			stream.seek(stream.get_position() + extra_bytes)

		# if we had to offet the buffer pointer to access the current value,
		# reset it to the stored location to continue normal parsing
		if curr_pos != -1: stream.seek(curr_pos)

	return tags

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

func get_exif_section(imageFile: String) -> PoolByteArray:
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

const exif_tags = {
  0x0001: 'InteropIndex',
  0x0002: 'InteropVersion',
  0x000B: 'ProcessingSoftware',
  0x00FE: 'SubfileType',
  0x00FF: 'OldSubfileType',
  0x0100: 'ImageWidth',
  0x0101: 'ImageHeight',
  0x0102: 'BitsPerSample',
  0x0103: 'Compression',
  0x0106: 'PhotometricInterpretation',
  0x0107: 'Thresholding',
  0x0108: 'CellWidth',
  0x0109: 'CellLength',
  0x010A: 'FillOrder',
  0x010D: 'DocumentName',
  0x010E: 'ImageDescription',
  0x010F: 'Make',
  0x0110: 'Model',
  0x0111: 'StripOffsets',
  0x0112: 'Orientation',
  0x0115: 'SamplesPerPixel',
  0x0116: 'RowsPerStrip',
  0x0117: 'StripByteCounts',
  0x0118: 'MinSampleValue',
  0x0119: 'MaxSampleValue',
  0x011A: 'XResolution',
  0x011B: 'YResolution',
  0x011C: 'PlanarConfiguration',
  0x011D: 'PageName',
  0x011E: 'XPosition',
  0x011F: 'YPosition',
  0x0120: 'FreeOffsets',
  0x0121: 'FreeByteCounts',
  0x0122: 'GrayResponseUnit',
  0x0123: 'GrayResponseCurve',
  0x0124: 'T4Options',
  0x0125: 'T6Options',
  0x0128: 'ResolutionUnit',
  0x0129: 'PageNumber',
  0x012C: 'ColorResponseUnit',
  0x012D: 'TransferFunction',
  0x0131: 'Software',
  0x0132: 'ModifyDate',
  0x013B: 'Artist',
  0x013C: 'HostComputer',
  0x013D: 'Predictor',
  0x013E: 'WhitePoint',
  0x013F: 'PrimaryChromaticities',
  0x0140: 'ColorMap',
  0x0141: 'HalftoneHints',
  0x0142: 'TileWidth',
  0x0143: 'TileLength',
  0x0144: 'TileOffsets',
  0x0145: 'TileByteCounts',
  0x0146: 'BadFaxLines',
  0x0147: 'CleanFaxData',
  0x0148: 'ConsecutiveBadFaxLines',
  0x014A: 'SubIFD',
  0x014C: 'InkSet',
  0x014D: 'InkNames',
  0x014E: 'NumberofInks',
  0x0150: 'DotRange',
  0x0151: 'TargetPrinter',
  0x0152: 'ExtraSamples',
  0x0153: 'SampleFormat',
  0x0154: 'SMinSampleValue',
  0x0155: 'SMaxSampleValue',
  0x0156: 'TransferRange',
  0x0157: 'ClipPath',
  0x0158: 'XClipPathUnits',
  0x0159: 'YClipPathUnits',
  0x015A: 'Indexed',
  0x015B: 'JPEGTables',
  0x015F: 'OPIProxy',
  0x0190: 'GlobalParametersIFD',
  0x0191: 'ProfileType',
  0x0192: 'FaxProfile',
  0x0193: 'CodingMethods',
  0x0194: 'VersionYear',
  0x0195: 'ModeNumber',
  0x01B1: 'Decode',
  0x01B2: 'DefaultImageColor',
  0x01B3: 'T82Options',
  0x01B5: 'JPEGTables',
  0x0200: 'JPEGProc',
  0x0201: 'ThumbnailOffset',
  0x0202: 'ThumbnailLength',
  0x0203: 'JPEGRestartInterval',
  0x0205: 'JPEGLosslessPredictors',
  0x0206: 'JPEGPointTransforms',
  0x0207: 'JPEGQTables',
  0x0208: 'JPEGDCTables',
  0x0209: 'JPEGACTables',
  0x0211: 'YCbCrCoefficients',
  0x0212: 'YCbCrSubSampling',
  0x0213: 'YCbCrPositioning',
  0x0214: 'ReferenceBlackWhite',
  0x022F: 'StripRowCounts',
  0x02BC: 'ApplicationNotes',
  0x03E7: 'USPTOMiscellaneous',
  0x1000: 'RelatedImageFileFormat',
  0x1001: 'RelatedImageWidth',
  0x1002: 'RelatedImageHeight',
  0x4746: 'Rating',
  0x4747: 'XP_DIP_XML',
  0x4748: 'StitchInfo',
  0x4749: 'RatingPercent',
  0x800D: 'ImageID',
  0x80A3: 'WangTag1',
  0x80A4: 'WangAnnotation',
  0x80A5: 'WangTag3',
  0x80A6: 'WangTag4',
  0x80E3: 'Matteing',
  0x80E4: 'DataType',
  0x80E5: 'ImageDepth',
  0x80E6: 'TileDepth',
  0x827D: 'Model2',
  0x828D: 'CFARepeatPatternDim',
  0x828E: 'CFAPattern2',
  0x828F: 'BatteryLevel',
  0x8290: 'KodakIFD',
  0x8298: 'Copyright',
  0x829A: 'ExposureTime',
  0x829D: 'FNumber',
  0x82A5: 'MDFileTag',
  0x82A6: 'MDScalePixel',
  0x82A7: 'MDColorTable',
  0x82A8: 'MDLabName',
  0x82A9: 'MDSampleInfo',
  0x82AA: 'MDPrepDate',
  0x82AB: 'MDPrepTime',
  0x82AC: 'MDFileUnits',
  0x830E: 'PixelScale',
  0x8335: 'AdventScale',
  0x8336: 'AdventRevision',
  0x835C: 'UIC1Tag',
  0x835D: 'UIC2Tag',
  0x835E: 'UIC3Tag',
  0x835F: 'UIC4Tag',
  0x83BB: 'IPTC-NAA',
  0x847E: 'IntergraphPacketData',
  0x847F: 'IntergraphFlagRegisters',
  0x8480: 'IntergraphMatrix',
  0x8481: 'INGRReserved',
  0x8482: 'ModelTiePoint',
  0x84E0: 'Site',
  0x84E1: 'ColorSequence',
  0x84E2: 'IT8Header',
  0x84E3: 'RasterPadding',
  0x84E4: 'BitsPerRunLength',
  0x84E5: 'BitsPerExtendedRunLength',
  0x84E6: 'ColorTable',
  0x84E7: 'ImageColorIndicator',
  0x84E8: 'BackgroundColorIndicator',
  0x84E9: 'ImageColorValue',
  0x84EA: 'BackgroundColorValue',
  0x84EB: 'PixelIntensityRange',
  0x84EC: 'TransparencyIndicator',
  0x84ED: 'ColorCharacterization',
  0x84EE: 'HCUsage',
  0x84EF: 'TrapIndicator',
  0x84F0: 'CMYKEquivalent',
  0x8546: 'SEMInfo',
  0x8568: 'AFCP_IPTC',
  0x85B8: 'PixelMagicJBIGOptions',
  0x85D8: 'ModelTransform',
  0x8602: 'WB_GRGBLevels',
  0x8606: 'LeafData',
  0x8649: 'PhotoshopSettings',
  0x8769: 'ExifOffset',
  0x8773: 'ICC_Profile',
  0x877F: 'TIFF_FXExtensions',
  0x8780: 'MultiProfiles',
  0x8781: 'SharedData',
  0x8782: 'T88Options',
  0x87AC: 'ImageLayer',
  0x87AF: 'GeoTiffDirectory',
  0x87B0: 'GeoTiffDoubleParams',
  0x87B1: 'GeoTiffAsciiParams',
  0x8822: 'ExposureProgram',
  0x8824: 'SpectralSensitivity',
  0x8825: 'GPSInfo',
  0x8827: 'ISO',
  0x8828: 'Opto-ElectricConvFactor',
  0x8829: 'Interlace',
  0x882A: 'TimeZoneOffset',
  0x882B: 'SelfTimerMode',
  0x8830: 'SensitivityType',
  0x8831: 'StandardOutputSensitivity',
  0x8832: 'RecommendedExposureIndex',
  0x8833: 'ISOSpeed',
  0x8834: 'ISOSpeedLatitudeyyy',
  0x8835: 'ISOSpeedLatitudezzz',
  0x885C: 'FaxRecvParams',
  0x885D: 'FaxSubAddress',
  0x885E: 'FaxRecvTime',
  0x888A: 'LeafSubIFD',
  0x9000: 'ExifVersion',
  0x9003: 'DateTimeOriginal',
  0x9004: 'DateTimeDigitized',
  0x9101: 'ComponentsConfiguration',
  0x9102: 'CompressedBitsPerPixel',
  0x9201: 'ShutterSpeedValue',
  0x9202: 'ApertureValue',
  0x9203: 'BrightnessValue',
  0x9204: 'ExposureBiasValue',
  0x9205: 'MaxApertureValue',
  0x9206: 'SubjectDistance',
  0x9207: 'MeteringMode',
  0x9208: 'LightSource',
  0x9209: 'Flash',
  0x920A: 'FocalLength',
  0x920B: 'FlashEnergy',
  0x920C: 'SpatialFrequencyResponse',
  0x920D: 'Noise',
  0x920E: 'FocalPlaneXResolution',
  0x920F: 'FocalPlaneYResolution',
  0x9210: 'FocalPlaneResolutionUnit',
  0x9211: 'ImageNumber',
  0x9212: 'SecurityClassification',
  0x9213: 'ImageHistory',
  0x9214: 'SubjectArea',
  0x9215: 'ExposureIndex',
  0x9216: 'TIFF-EPStandardID',
  0x9217: 'SensingMethod',
  0x923A: 'CIP3DataFile',
  0x923B: 'CIP3Sheet',
  0x923C: 'CIP3Side',
  0x923F: 'StoNits',
  0x927C: 'MakerNote',
  0x9286: 'UserComment',
  0x9290: 'SubSecTime',
  0x9291: 'SubSecTimeOriginal',
  0x9292: 'SubSecTimeDigitized',
  0x932F: 'MSDocumentText',
  0x9330: 'MSPropertySetStorage',
  0x9331: 'MSDocumentTextPosition',
  0x935C: 'ImageSourceData',
  0x9C9B: 'XPTitle',
  0x9C9C: 'XPComment',
  0x9C9D: 'XPAuthor',
  0x9C9E: 'XPKeywords',
  0x9C9F: 'XPSubject',
  0xA000: 'FlashpixVersion',
  0xA001: 'ColorSpace',
  0xA002: 'PixelXDimension',
  0xA003: 'PixelYDimension',
  0xA004: 'RelatedSoundFile',
  0xA005: 'InteropOffset',
  0xA20B: 'FlashEnergy',
  0xA20C: 'SpatialFrequencyResponse',
  0xA20D: 'Noise',
  0xA20E: 'FocalPlaneXResolution',
  0xA20F: 'FocalPlaneYResolution',
  0xA210: 'FocalPlaneResolutionUnit',
  0xA211: 'ImageNumber',
  0xA212: 'SecurityClassification',
  0xA213: 'ImageHistory',
  0xA214: 'SubjectLocation',
  0xA215: 'ExposureIndex',
  0xA216: 'TIFF-EPStandardID',
  0xA217: 'SensingMethod',
  0xA300: 'FileSource',
  0xA301: 'SceneType',
  0xA302: 'CFAPattern',
  0xA401: 'CustomRendered',
  0xA402: 'ExposureMode',
  0xA403: 'WhiteBalance',
  0xA404: 'DigitalZoomRatio',
  0xA405: 'FocalLengthIn35mmFormat',
  0xA406: 'SceneCaptureType',
  0xA407: 'GainControl',
  0xA408: 'Contrast',
  0xA409: 'Saturation',
  0xA40A: 'Sharpness',
  0xA40B: 'DeviceSettingDescription',
  0xA40C: 'SubjectDistanceRange',
  0xA420: 'ImageUniqueID',
  0xA430: 'CameraOwnerName',
  0xA431: 'BodySerialNumber',
  0xA432: 'LensSpecification',
  0xA433: 'LensMake',
  0xA434: 'LensModel',
  0xA435: 'LensSerialNumber',
  0xA480: 'GDALMetadata',
  0xA481: 'GDALNoData',
  0xA500: 'Gamma',
  0xAFC0: 'ExpandSoftware',
  0xAFC1: 'ExpandLens',
  0xAFC2: 'ExpandFilm',
  0xAFC3: 'ExpandFilterLens',
  0xAFC4: 'ExpandScanner',
  0xAFC5: 'ExpandFlashLamp',
  0xBC01: 'PixelFormat',
  0xBC02: 'Transformation',
  0xBC03: 'Uncompressed',
  0xBC04: 'ImageType',
  0xBC80: 'ImageWidth',
  0xBC81: 'ImageHeight',
  0xBC82: 'WidthResolution',
  0xBC83: 'HeightResolution',
  0xBCC0: 'ImageOffset',
  0xBCC1: 'ImageByteCount',
  0xBCC2: 'AlphaOffset',
  0xBCC3: 'AlphaByteCount',
  0xBCC4: 'ImageDataDiscard',
  0xBCC5: 'AlphaDataDiscard',
  0xC427: 'OceScanjobDesc',
  0xC428: 'OceApplicationSelector',
  0xC429: 'OceIDNumber',
  0xC42A: 'OceImageLogic',
  0xC44F: 'Annotations',
  0xC4A5: 'PrintIM',
  0xC580: 'USPTOOriginalContentType',
  0xC612: 'DNGVersion',
  0xC613: 'DNGBackwardVersion',
  0xC614: 'UniqueCameraModel',
  0xC615: 'LocalizedCameraModel',
  0xC616: 'CFAPlaneColor',
  0xC617: 'CFALayout',
  0xC618: 'LinearizationTable',
  0xC619: 'BlackLevelRepeatDim',
  0xC61A: 'BlackLevel',
  0xC61B: 'BlackLevelDeltaH',
  0xC61C: 'BlackLevelDeltaV',
  0xC61D: 'WhiteLevel',
  0xC61E: 'DefaultScale',
  0xC61F: 'DefaultCropOrigin',
  0xC620: 'DefaultCropSize',
  0xC621: 'ColorMatrix1',
  0xC622: 'ColorMatrix2',
  0xC623: 'CameraCalibration1',
  0xC624: 'CameraCalibration2',
  0xC625: 'ReductionMatrix1',
  0xC626: 'ReductionMatrix2',
  0xC627: 'AnalogBalance',
  0xC628: 'AsShotNeutral',
  0xC629: 'AsShotWhiteXY',
  0xC62A: 'BaselineExposure',
  0xC62B: 'BaselineNoise',
  0xC62C: 'BaselineSharpness',
  0xC62D: 'BayerGreenSplit',
  0xC62E: 'LinearResponseLimit',
  0xC62F: 'CameraSerialNumber',
  0xC630: 'DNGLensInfo',
  0xC631: 'ChromaBlurRadius',
  0xC632: 'AntiAliasStrength',
  0xC633: 'ShadowScale',
  0xC634: 'DNGPrivateData',
  0xC635: 'MakerNoteSafety',
  0xC640: 'RawImageSegmentation',
  0xC65A: 'CalibrationIlluminant1',
  0xC65B: 'CalibrationIlluminant2',
  0xC65C: 'BestQualityScale',
  0xC65D: 'RawDataUniqueID',
  0xC660: 'AliasLayerMetadata',
  0xC68B: 'OriginalRawFileName',
  0xC68C: 'OriginalRawFileData',
  0xC68D: 'ActiveArea',
  0xC68E: 'MaskedAreas',
  0xC68F: 'AsShotICCProfile',
  0xC690: 'AsShotPreProfileMatrix',
  0xC691: 'CurrentICCProfile',
  0xC692: 'CurrentPreProfileMatrix',
  0xC6BF: 'ColorimetricReference',
  0xC6D2: 'PanasonicTitle',
  0xC6D3: 'PanasonicTitle2',
  0xC6F3: 'CameraCalibrationSig',
  0xC6F4: 'ProfileCalibrationSig',
  0xC6F5: 'ProfileIFD',
  0xC6F6: 'AsShotProfileName',
  0xC6F7: 'NoiseReductionApplied',
  0xC6F8: 'ProfileName',
  0xC6F9: 'ProfileHueSatMapDims',
  0xC6FA: 'ProfileHueSatMapData1',
  0xC6FB: 'ProfileHueSatMapData2',
  0xC6FC: 'ProfileToneCurve',
  0xC6FD: 'ProfileEmbedPolicy',
  0xC6FE: 'ProfileCopyright',
  0xC714: 'ForwardMatrix1',
  0xC715: 'ForwardMatrix2',
  0xC716: 'PreviewApplicationName',
  0xC717: 'PreviewApplicationVersion',
  0xC718: 'PreviewSettingsName',
  0xC719: 'PreviewSettingsDigest',
  0xC71A: 'PreviewColorSpace',
  0xC71B: 'PreviewDateTime',
  0xC71C: 'RawImageDigest',
  0xC71D: 'OriginalRawFileDigest',
  0xC71E: 'SubTileBlockSize',
  0xC71F: 'RowInterleaveFactor',
  0xC725: 'ProfileLookTableDims',
  0xC726: 'ProfileLookTableData',
  0xC740: 'OpcodeList1',
  0xC741: 'OpcodeList2',
  0xC74E: 'OpcodeList3',
  0xC761: 'NoiseProfile',
  0xC763: 'TimeCodes',
  0xC764: 'FrameRate',
  0xC772: 'TStop',
  0xC789: 'ReelName',
  0xC791: 'OriginalDefaultFinalSize',
  0xC792: 'OriginalBestQualitySize',
  0xC793: 'OriginalDefaultCropSize',
  0xC7A1: 'CameraLabel',
  0xC7A3: 'ProfileHueSatMapEncoding',
  0xC7A4: 'ProfileLookTableEncoding',
  0xC7A5: 'BaselineExposureOffset',
  0xC7A6: 'DefaultBlackRender',
  0xC7A7: 'NewRawImageDigest',
  0xC7A8: 'RawToPreviewGain',
  0xC7B5: 'DefaultUserCrop',
  0xEA1C: 'Padding',
  0xEA1D: 'OffsetSchema',
  0xFDE8: 'OwnerName',
  0xFDE9: 'SerialNumber',
  0xFDEA: 'Lens',
  0xFE00: 'KDC_IFD',
  0xFE4C: 'RawFile',
  0xFE4D: 'Converter',
  0xFE4E: 'WhiteBalance',
  0xFE51: 'Exposure',
  0xFE52: 'Shadows',
  0xFE53: 'Brightness',
  0xFE54: 'Contrast',
  0xFE55: 'Saturation',
  0xFE56: 'Sharpness',
  0xFE57: 'Smoothness',
  0xFE58: 'MoireFilter'
};

const gps_tags = {
  0x0000: 'GPSVersionID',
  0x0001: 'GPSLatitudeRef',
  0x0002: 'GPSLatitude',
  0x0003: 'GPSLongitudeRef',
  0x0004: 'GPSLongitude',
  0x0005: 'GPSAltitudeRef',
  0x0006: 'GPSAltitude',
  0x0007: 'GPSTimeStamp',
  0x0008: 'GPSSatellites',
  0x0009: 'GPSStatus',
  0x000A: 'GPSMeasureMode',
  0x000B: 'GPSDOP',
  0x000C: 'GPSSpeedRef',
  0x000D: 'GPSSpeed',
  0x000E: 'GPSTrackRef',
  0x000F: 'GPSTrack',
  0x0010: 'GPSImgDirectionRef',
  0x0011: 'GPSImgDirection',
  0x0012: 'GPSMapDatum',
  0x0013: 'GPSDestLatitudeRef',
  0x0014: 'GPSDestLatitude',
  0x0015: 'GPSDestLongitudeRef',
  0x0016: 'GPSDestLongitude',
  0x0017: 'GPSDestBearingRef',
  0x0018: 'GPSDestBearing',
  0x0019: 'GPSDestDistanceRef',
  0x001A: 'GPSDestDistance',
  0x001B: 'GPSProcessingMethod',
  0x001C: 'GPSAreaInformation',
  0x001D: 'GPSDateStamp',
  0x001E: 'GPSDifferential',
  0x001F: 'GPSHPositioningError'
};
