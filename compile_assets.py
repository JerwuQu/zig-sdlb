#!/usr/bin/env python3

# TODO: document output asset format

import os
import sys
import json
import struct
import tempfile
import subprocess
from PIL import Image

if len(sys.argv) < 3:
	print(f'{sys.argv[0]} <output.bin> [files...]')
	exit(1)

output_filename = sys.argv[1]
filenames = sys.argv[2:]

class Atlas:
	TX_SIZE = 512

	def __init__(self):
		self.x = 0
		self.y = 0
		self.largestY = 0
		self.img = Image.new('RGBA', (Atlas.TX_SIZE, Atlas.TX_SIZE))

	# mediocre packing, but works
	def pack(self, img):
		if self.x + img.width > Atlas.TX_SIZE:
			self.x = 0
			self.y = self.largestY

		if self.y + img.height > Atlas.TX_SIZE:
			return None

		if self.y + img.height > self.largestY:
			self.largestY = self.y + img.height

		rect = (self.x, self.y, img.width, img.height)
		self.img.paste(img, (self.x, self.y))
		self.x += img.width
		return rect

	def to_bytes(self):
		return struct.pack('>HH', Atlas.TX_SIZE, Atlas.TX_SIZE) + self.img.tobytes()

atlases = []
images = []
sheets = []
anims = []
sounds = [] # NOTE: sounds are just raw data with sugar
maps = []

def atlas_pack(img):
	if not atlases:
		atlases.append(Atlas())

	res = atlases[-1].pack(img)
	if not res:
		atlases.append(Atlas())
		res = atlases[-1].pack(img)
		if not res:
			print('atlas pack failed')
			exit(1)

	return (len(atlases) - 1, res)

for filename in filenames:
	name, ext = os.path.splitext(os.path.basename(filename))
	if ext == '.png':
		namesplit = name.split('@', 2)

		# Spritesheet
		if len(namesplit) == 2:
			counts = namesplit[1].split(',', 2)
			if len(counts) != 2:
				print('invalid spritesheet definition')
				exit(1)

			x_count = int(counts[0])
			y_count = int(counts[1])
			sheet_images = []
			with Image.open(filename) as img:
				pw = img.width / x_count
				ph = img.height / y_count
				for y in range(y_count):
					for x in range(x_count):
						sheet_images.append(atlas_pack(img.crop((x * pw, y * ph, (x + 1) * pw, (y + 1) * ph))))

			sheets.append((namesplit[0], sheet_images))

		# Regular image
		else:
			with Image.open(filename) as img:
				images.append((name, atlas_pack(img)))

	elif ext == '.aseprite':
		tmppng = tempfile.mktemp(suffix='.png')
		asejson = json.loads(subprocess.run(['aseprite', '-b', '--list-tags', '--format', 'json-array', '--sheet-pack', '--sheet', tmppng, filename], stdout=subprocess.PIPE).stdout.decode())
		with Image.open(tmppng) as img:
			frame_rects = []
			for frame in asejson['frames']:
				r = frame['frame']
				frame_rects.append(atlas_pack(img.crop((r['x'], r['y'], r['x'] + r['w'], r['y'] + r['h']))))

			for anim in asejson['meta']['frameTags']:
				frames = [(frame_rects[i], asejson['frames'][i]['duration']) for i in range(anim['from'], anim['to'] + 1)]
				anims.append((name + '_' + anim['name'], frames))

		os.remove(tmppng)

	elif ext == '.opus':
		with open(filename, 'rb') as f:
			sounds.append((name, f.read())) # NOTE: takes up a bit of RAM. Improve?

	elif ext == '.tmx':
		tmpjson = tempfile.mktemp(suffix='.json')
		subprocess.run(['tiled', '--export-map', '--embed-tilesets', filename, tmpjson])
		with open(tmpjson, 'r') as f:
			tiledinfo = json.loads(f.read())

		os.remove(tmpjson)

		# TODO: support sharing tilesets between multiple maps. currently they'd be duplicated.
		tileset = tiledinfo['tilesets'][0] # TODO: more than one tileset
		tw = tileset["tilewidth"] # NOTE: ÖL
		th = tileset["tileheight"]
		tiles = []
		if 'image' in tileset: # Spritesheet tileset
			imgpath = tileset['image']

			# NOTE: there's currently some kind of bug related to when resolving paths using Tiled from WSL
			#       try to fix :)
			if not os.path.isfile(imgpath):
				if imgpath.startswith('../'):
					imgpath = imgpath[2:]
				else:
					print('no clue what to do, quitting')
					exit(1)

			x_count = int(tileset['imagewidth'] / tw)
			y_count = int(tileset['imageheight'] / th)
			with Image.open(imgpath) as img:
				for y in range(y_count):
					for x in range(x_count):
						tiles.append(atlas_pack(img.crop((x * tw, y * th, (x + 1) * tw, (y + 1) * th))))

		else: # Multi-file tilesheet
			# paths = [os.path.join(os.path.dirname(tmpjson), tile['image']) for tile in tileset['tiles']]
			# print(paths)
			print('file based tilesheets not supported')
			exit(1)

		sheets.append((name + '_tiles', tiles))
		layers = []
		for l in tiledinfo['layers']:
			if l['width'] != tiledinfo['width'] or l['height'] != tiledinfo['height']:
				print('layer size not equal to map size')
				exit(1)
			layers.append(l['data'])

		maps.append((name, tiledinfo['width'], tiledinfo['height'], layers))

	else:
		print(f'unknown extension "{ext}"')
		exit(1)

def str_bytes(str):
	bs = str.encode()
	return struct.pack('>H', len(bs)) + bs

def sprite_bytes(rect):
	return struct.pack('>HHHHH', rect[0], rect[1][0], rect[1][1], rect[1][2], rect[1][3])

output = bytearray()

# Atlas count
output += struct.pack('>H', len(atlases))

# Image names
output += struct.pack('>H', len(images))
for image in images:
	output += str_bytes(image[0])

# Spritesheet names
output += struct.pack('>H', len(sheets))
for sheet in sheets:
	output += str_bytes(sheet[0])

# Anim names
output += struct.pack('>H', len(anims))
for anim in anims:
	output += str_bytes(anim[0])

# Sound names
output += struct.pack('>H', len(sounds))
for sound in sounds:
	output += str_bytes(sound[0])

# Map names
output += struct.pack('>H', len(maps))
for m in maps:
	output += str_bytes(m[0])

# Compressed section
compressed = bytearray()

# Atlas data
for atlas in atlases:
	compressed += atlas.to_bytes()

# Image rects
for image in images:
	compressed += sprite_bytes(image[1])

# Spritesheets
for sheet in sheets:
	compressed += struct.pack('>H', len(sheet[1]))
	for sprite in sheet[1]:
		compressed += sprite_bytes(sprite)

# Anim data
for anim in anims:
	compressed += struct.pack('>H', len(anim[1]))
	for frame in anim[1]:
		compressed += sprite_bytes(frame[0]) + struct.pack('>H', frame[1])

# Sound data
for sound in sounds:
	compressed += struct.pack('>I', len(sound[1])) + sound[1]

# Map data
for m in maps:
	compressed += struct.pack('>HHH', m[1], m[2], len(m[3]))
	for layer in m[3]:
		for i in range(m[1] * m[2]):
			compressed += struct.pack('>H', layer[i])

# Compress
compressed_data = subprocess.Popen(['zstd', '-19'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate(compressed)[0]
output += struct.pack('>II', len(compressed), len(compressed_data)) + compressed_data

# Write
with open(output_filename, 'wb') as f:
	f.write(output)
