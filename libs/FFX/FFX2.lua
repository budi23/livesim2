-- AquaShine FFmpeg extension
-- Part of AquaShine loader
-- See copyright notice in AquaShine.lua

-- Check if we're loading it using AquaShine or standalone
local isAqs = ...
local AquaShine, LOG
if type(isAqs) == "table" then
	AquaShine = isAqs
	LOG = AquaShine.Log
else
	function LOG() end
end

local jit = _G.jit
local love = require("love")
local ffi = require("ffi")
local bit = require("bit")
local osString = AquaShine and AquaShine.OperatingSystem or love._os
local stringstream
local load_ffmpeg_library

-- iOS, or using Lua 5.1 is not supported
if osString == "iOS" then
	LOG("AquaShineFFmpeg", "AquaShine FFX is not supported")
	return
elseif osString == "Android" then
	-- Just read /proc/self/cmdline then construct /data/data/package/lib
	-- FIXME: Probably not work in Android 6.0 or later!
	local f = io.open("/proc/self/cmdline", "r")
	local package = f:read("*a")
	local lib_dir = "/data/data/"..package.."/lib"
	f:close()

	function load_ffmpeg_library(libname, ver)
		LOG("AquaShineFFmpeg", "Loading library %s ver %d", libname, ver)

		local s, out = pcall(ffi.load, lib_dir.."/lib"..libname.."-"..ver..".so")
		if s then
			return out
		end

		s, out = pcall(ffi.load, libname.."-"..ver)
		if s then
			return out
		end

		return nil
	end
else
	-- For desktop, we just need "ffi.load" it
	function load_ffmpeg_library(libname, ver)
		LOG("AquaShineFFmpeg", "Loading library %s ver %d", libname, ver)
		local name = libname.."-"..ver
		local s, out = pcall(ffi.load, name)

		if s then
			return out
		end

		LOG("AquaShineFFmpeg", "Failed to load %s: %s", name, out)
		s, out = pcall(ffi.load, libname)

		if s then
			return out
		end

		LOG("AquaShineFFmpeg", "Failed to load %s: %s", libname, out)
		name = "lib"..libname..".so."..ver
		s, out = pcall(ffi.load, name)

		if s then
			return out
		end

		LOG("AquaShineFFmpeg", "Failed to load %s: %s", name, out)
		name = "lib"..libname..".dylib."..ver
		s, out = pcall(ffi.load, name)

		if s then
			return out
		end

		LOG("AquaShineFFmpeg", "Failed to load %s: %s", name, out)
		return nil
	end
end

-- Stringstream
do
	stringstream = {}
	function stringstream.create(str)
		local out = newproxy(true)
		local meta = getmetatable(out)

		meta.buffer = str or ""
		meta.pos = 0
		meta.__index = stringstream

		return out
	end

	function stringstream.read(ss, num)
		local meta = getmetatable(ss)

		if num == "*a" then
			if meta.pos == #meta.buffer then
				return nil
			end

			local out = meta.buffer:sub(meta.pos + 1)

			meta.pos = #meta.buffer
			return out
		elseif num <= 0 then
			return ""
		end

		local out = meta.buffer:sub(meta.pos + 1, meta.pos + num)

		if #out == 0 then return nil end

		meta.pos = meta.pos + num

		if meta.pos > #meta.buffer then
			meta.pos = #meta.buffer
		end

		return out
	end

	function stringstream.write(ss, ...)
		local meta = getmetatable(ss)
		local gap1 = meta.buffer:sub(1, meta.pos)
		local gap2 = meta.buffer:sub(meta.pos + 1)
		local con = {}

		for _, v in pairs({...}) do
			con[#con + 1] = tostring(v)
		end

		con = table.concat(con)
		meta.pos = meta.pos + #con
		meta.buffer = gap1..con..gap2

		return true
	end

	function stringstream.seek(ss, whence, offset)
		local meta = getmetatable(ss)
		whence = whence or "cur"

		if whence == "set" then
			meta.pos = offset or 0
		elseif whence == "cur" then
			meta.pos = meta.pos + (offset or 0)
		elseif whence == "end" then
			meta.pos = #meta.buffer + (offset or 0)
		else
			error("bad argument #1 to 'seek' (invalid option '"..tostring(whence).."')", 2)
		end

		if meta.pos < 0 then
			meta.pos = 0
		elseif meta.pos > #meta.buffer then
			meta.pos = #meta.buffer
		end

		return meta.pos
	end

	function stringstream.string(ss)
		return getmetatable(ss).buffer
	end
end

-------------------
-- AquaShine FFX --
-------------------

-- The order is important, especially in Android
local avutil = load_ffmpeg_library("avutil", 55)
local swresample = load_ffmpeg_library("swresample", 2)
local avcodec = load_ffmpeg_library("avcodec", 57)
local avformat = load_ffmpeg_library("avformat", 57)
local swscale = load_ffmpeg_library("swscale", 4)

if not(avutil and swresample and avcodec and avformat and swscale) then
	-- FFmpeg library not found/can't be loaded
	LOG("AquaShineFFmpeg", "FFmpeg library not found/can't be loaded")
	return
end

local function decompressHeader(file)
	local c = love.filesystem.read(file)
	if AquaShine or love._version >= "11.0" then
		return love.data.decompress("string", "zlib", c)
	else
		return love.math.decompress(c, "zlib")
	end
end

LOG("AquaShineFFmpeg", "Loading include files")
local include = decompressHeader("libs/FFX/ffmpeg_include_compressed")
local vidshader = love.graphics.newShader [[
vec4 effect(mediump vec4 vcolor, Image tex, vec2 texcoord, vec2 pixcoord) {
	return VideoTexel(texcoord) * vcolor;
}
]]

ffi.cdef(include)
ffi.cdef[[
int av_image_get_buffer_size(
    enum AVPixelFormat pix_fmt,
    int                width,
    int                height,
    int                align
);
int av_image_fill_arrays(uint8_t *dst_data[4], int dst_linesize[4],
                         const uint8_t *src,
                         enum AVPixelFormat pix_fmt, int width, int height, int align);
int av_opt_set_int     (void *obj, const char *name, int64_t     val, int search_flags);
int av_opt_set_sample_fmt(void *obj, const char *name, enum AVSampleFormat fmt, int search_flags);

typedef struct SwrContext SwrContext;
struct SwrContext *swr_alloc(void);
struct SwrContext *swr_alloc_set_opts(struct SwrContext *s,
                                      int64_t out_ch_layout, enum AVSampleFormat out_sample_fmt, int out_sample_rate,
                                      int64_t  in_ch_layout, enum AVSampleFormat  in_sample_fmt, int  in_sample_rate,
                                      int log_offset, void *log_ctx);
int swr_init(struct SwrContext *s);
void swr_free(struct SwrContext **s);
int swr_convert(struct SwrContext *s, uint8_t **out, int out_count,
                                const uint8_t **in , int in_count);
int64_t swr_get_delay(struct SwrContext *s, int64_t base);

typedef struct AquaShineFFX2
{
	AVIOContext* IOContext;
	AVFormatContext* FmtContext;
	AVCodecContext* CodecContext;
	AVFrame* FrameVideo;
	AVFrame* FrameYUV420P;
	struct SwsContext* SwsCtx;
} AquaShineFFX2;

typedef struct AquaShineMemoryStream
{
	const char* buffer;
	size_t bufsize;
	size_t pos;
} AquaShineMemoryStream;
]]

local function av_version(int)
	return bit.rshift(int, 16), bit.rshift(bit.band(int, 0xFF00), 8), bit.band(int, 0xFF)
end

-- Deletes AVFrame
local function FreeAVFrame(frame)
	local x = ffi.new("AVFrame*[1]")
	x[0] = frame

	avutil.av_frame_free(x)
end

-- Reading callback
local read_callback = ffi.typeof("int(*)(void *opaque, uint8_t *buf, int buf_size)")
local function make_read_callback(file)
	local x = function(_, buf, buf_size)
		jit.off(true)
		local readed = file:read(buf_size)

		ffi.copy(buf, readed, #readed)
		return #readed
	end
	local y = ffi.cast(read_callback, x)

	return y, x
end

-- Seeking callback
local seek_callback = ffi.typeof("int64_t(*)(void *opaque, int64_t offset, int whence)")
local function make_seek_callback(file)
	local filestreamsize = nil
	local x = function(_, pos, whence)
		jit.off(true)
		local success = false
		if whence == 0x10000 then
			-- AVSEEK_SIZE
			if not(filestreamsize) then
				filestreamsize = file:getSize()
			end

			return filestreamsize
		elseif whence == 0 then
			-- SEEK_SET
			success = file:seek(tonumber(pos))
		elseif whence == 1 then
			-- SEEK_CUR
			success = file:seek(tonumber(pos) + file:tell())
		elseif whence == 2 then
			-- SEEK_END
			if not(filestreamsize) then
				filestreamsize = file:getSize()
			end

			success = file:seek(tonumber(pos) + filestreamsize)
		end

		return success and file:tell() or -1
	end
	local y = ffi.cast(seek_callback, x)

	return y, x
end

-- Seeking callback (memory)
local function make_seek_callback_mem(file)
	local filestreamsize = nil
	local whence_str = {[0] = "set", [1] = "cur", [2] = "end"}
	local x = function(_, pos, whence)
		if whence == 0x10000 then
			-- AVSEEK_SIZE
			if not(filestreamsize) then
				filestreamsize = #file:string()
			end

			return filestreamsize
		else
			return file:seek(assert(whence_str[whence], "invalid seek position"), pos)
		end
	end
	local y = ffi.cast(seek_callback, x)

	jit.off(x)
	return y, x
end

-- Used to free associated resource
local function DeleteAquaShineFFXData(this)
	if this.SwsCtx ~= nil then
		swscale.sws_freeContext(this.SwsCtx)
	end

	if this.FrameVideo ~= nil then
		FreeAVFrame(this.FrameVideo)
	end

	if this.FrameYUV420P ~= nil then
		FreeAVFrame(this.FrameYUV420P)
	end

	if this.CodecContext ~= nil then
		avcodec.avcodec_close(this.CodecContext)
	end

	if this.FmtContext ~= nil then
		local x = ffi.new("AVFormatContext*[1]")
		x[0] = this.FmtContext

		avformat.avformat_close_input(x)
	end

	if this.IOContext ~= nil then
		avutil.av_free(this.IOContext)
	end
end

-- Function to create destructor
local function CreateFFXCleanupFunction(read, seek)
	return function(this)
		read:free()
		seek:free()
		return DeleteAquaShineFFXData(this)
	end
end

-- Verify version
if
	select(1, av_version(avcodec.avcodec_version())) >= 57 and
	select(1, av_version(avformat.avformat_version())) >= 57 and
	select(1, av_version(avutil.avutil_version())) >= 55
then
	avformat.av_register_all()
	avcodec.avcodec_register_all()
	LOG("AquaShineFFmpeg", "FFmpeg initialized")
else
	LOG("AquaShineFFmpeg", "FFmpeg version not supported")
	return
end

-- FFX table
local FFX = {
	_playing = setmetatable({}, {__mode = "v"}),
	avutil = avutil,
	swresample = swresample,
	avcodec = avcodec,
	avformat = avformat,
	swscale = swscale
}

-- Image refresh function
local function RefreshImage(image, imagedata)
	if AquaShine or love._version >= "0.11.0" then
		-- AquaShine uses replacePixels
		image:replacePixels(imagedata)
	else
		image:refresh()
	end
end

local class = AquaShine and AquaShine.Class or require("30log")
local AquaShineVideo = class("AquaShineVideo")
local AV_PIX_FMT_YUV420P = tonumber(ffi.cast("enum AVPixelFormat", "AV_PIX_FMT_YUV420P"))

function AquaShineVideo.init(this, path)
	-- Load the file with love.filesystem API
	this.FileStream = assert(love.filesystem.newFile(path, "r"))
	this.ReadType, this.ReadFunc = make_read_callback(this.FileStream)
	this.SeekType, this.SeekFunc = make_seek_callback(this.FileStream)

	this.FFXData = ffi.gc(
		ffi.new("AquaShineFFX2"),
		CreateFFXCleanupFunction(this.ReadType, this.SeekType)
	)

	-- Create AVIOContext
	this.FFXData.IOContext = avformat.avio_alloc_context(
		nil, 0, 0, nil,
		this.ReadType, nil, this.SeekType
	)

	-- Allocate AVFormatContext
	local tempfmtctx = ffi.new("AVFormatContext*[1]")
	tempfmtctx[0] = avformat.avformat_alloc_context()
	tempfmtctx[0].pb = this.FFXData.IOContext

	-- Open input
	if avformat.avformat_open_input(tempfmtctx, path, nil, nil) < 0 then
		this.ReadType:free()
		this.SeekType:free()
		assert(false, "Cannot open input file")
	end
	this.FFXData.FmtContext = tempfmtctx[0]

	-- Find video stream
	if avformat.avformat_find_stream_info(tempfmtctx[0], nil) < 0 then
		this.ReadType:free()
		this.SeekType:free()
		assert(false, "Failed to determine stream info")
	end
	for i = 1, tempfmtctx[0].nb_streams do
		local codec_type = tempfmtctx[0].streams[i - 1].codec.codec_type

		if codec_type == "AVMEDIA_TYPE_VIDEO" then
			this.VideoStreamIndex = i - 1
			break
		end
	end
	if not(this.VideoStreamIndex) then
		this.ReadType:free()
		this.SeekType:free()
		assert(false, "Video stream not found")
	end
	local videostream = tempfmtctx[0].streams[this.VideoStreamIndex]

	-- Find video decoder
	local codec = avcodec.avcodec_find_decoder(videostream.codec.codec_id)
	assert(codec ~= nil, "Codec not found")

	-- Create CodecContext
	this.FFXData.CodecContext = avcodec.avcodec_alloc_context3(codec)
	assert(avcodec.avcodec_copy_context(this.FFXData.CodecContext, videostream.codec) >= 0, "Failed to copy context")
	assert(avcodec.avcodec_open2(this.FFXData.CodecContext, codec, nil) >= 0, "Cannot open codec")

	-- Init frame
	this.FFXData.FrameVideo = avutil.av_frame_alloc()
	assert(this.FFXData.FrameVideo ~= nil, "Failed to initialize frame")
	this.FFXData.FrameYUV420P = avutil.av_frame_alloc()
	assert(this.FFXData.FrameYUV420P ~= nil, "Failed to initialize frame (2)")
	this.YUV420Image = ffi.new("uint8_t[?]", avutil.av_image_get_buffer_size(
		"AV_PIX_FMT_YUV420P",
		this.FFXData.CodecContext.width,
		this.FFXData.CodecContext.height,
		64
	))

	-- Create 3 ImageData consist of Y, U, and V channel
	this.ImageData = {}
	this.ImageData[1] = {love.image.newImageData(this.FFXData.CodecContext.width, this.FFXData.CodecContext.height)}
	this.ImageData[1][2] = love.graphics.newImage(this.ImageData[1][1])
	this.ImageData[1][3] = ffi.cast("uint8_t*", this.ImageData[1][1]:getPointer())
	for i = 2, 3 do
		local a = love.image.newImageData(this.FFXData.CodecContext.width * 0.5, this.FFXData.CodecContext.height * 0.5)
		local b = {}
		b[1] = a
		b[2] = love.graphics.newImage(a)
		b[3] = ffi.cast("uint8_t*", a:getPointer())
		this.ImageData[i] = b
	end

	-- Initialize image
	avutil.av_image_fill_arrays(
		this.FFXData.FrameYUV420P.data,
		this.FFXData.FrameYUV420P.linesize,
		this.YUV420Image,
		"AV_PIX_FMT_YUV420P",
		this.FFXData.CodecContext.width,
		this.FFXData.CodecContext.height, 32
	)

	-- Create our SwsContext
	this.FFXData.SwsCtx = swscale.sws_getContext(
		this.FFXData.CodecContext.width,
		this.FFXData.CodecContext.height,
		this.FFXData.CodecContext.pix_fmt,
		this.FFXData.CodecContext.width,
		this.FFXData.CodecContext.height,
		"AV_PIX_FMT_YUV420P",
		2, 						-- SWS_BILINEAR
		nil, nil, nil
	)

	-- Post init
	this.Packet = ffi.new("AVPacket[1]")
	this.GotFrame = ffi.new("int[1]")
	this.TimeBase = videostream.time_base
	this.PresentationTS = 0
	this.CurrentTime = 0
	this.EOS = false
	this.ImgRes = this.FFXData.CodecContext.width * this.FFXData.CodecContext.height
	this.HalfImgRes = this.ImgRes * 0.25
	--this.Shader = love.graphics.newShader(vidshader_code)
end

function AquaShineVideo._readPacket(this)
	while avformat.av_read_frame(this.FFXData.FmtContext, this.Packet) >= 0 do
		if this.Packet[0].stream_index == this.VideoStreamIndex then
			return true
		end
	end

	return false
end

function AquaShineVideo._readFrame(this)
	this.GotFrame[0] = 0
	local FFXData = this.FFXData

	while this.GotFrame[0] == 0 do
		if this:_readPacket() then
			if avcodec.avcodec_decode_video2(FFXData.CodecContext, FFXData.FrameVideo, this.GotFrame, this.Packet) < 0 then
				return false
			end
		else
			return false
		end
	end

	return true
end

function AquaShineVideo._translateTS(this, ts)
	return tonumber(ts * this.TimeBase.num) / tonumber(this.TimeBase.den)
end

function AquaShineVideo._tinySeek(this, target)
	while target > this:_translateTS(this.FFXData.FrameVideo.pkt_pts + this.FFXData.FrameVideo.pkt_duration) do
		this:_readFrame()
	end
end

function AquaShineVideo._selectUsedFrameData(this)
	if this.FFXData.FrameVideo.format == AV_PIX_FMT_YUV420P then
		return this.FFXData.FrameVideo
	else
		swscale.sws_scale(this.FFXData.SwsCtx,
			ffi.cast("const uint8_t *const *", this.FFXData.FrameVideo.data),
			this.FFXData.FrameVideo.linesize, 0, this.FFXData.CodecContext.height,
			this.FFXData.FrameYUV420P.data, this.FFXData.FrameYUV420P.linesize
		)
		return this.FFXData.FrameYUV420P
	end
end

function AquaShineVideo._stepVideo(this, dt)
	this.CurrentTime = this.CurrentTime + dt

	-- If we've drawn a frame past the current timestamp, we must have rewound
	if this.CurrentTime < this.PresentationTS then
		this:seek(this.CurrentTime)
		this:_readFrame()

		-- Now we're at the keyframe before our target, look for the actual frame
		this:_tinySeek(this.CurrentTime)
		this.EOS = false
	end

	if this.EOS then return end

	local pts = this:_translateTS(this.FFXData.FrameVideo.pkt_pts)

	if this.CurrentTime < pts then
		return
	end

	if this.CurrentTime > pts + 15 then
		-- We're far behind, do a large seek
		this:seek(this.CurrentTime)
		this:_readFrame()
	end

	if this.CurrentTime > pts + 0.2 then
		-- We're a bit behind, do a tiny seek
		this:_tinySeek(this.CurrentTime)
	end

	this.PresentationTS = pts

	-- Refresh the image buffer
	-- Don't forget to do sws_scale first
	local usedFrame = this:_selectUsedFrameData()
	local idx = 0
	local idx2 = 0
	local iy, iu, iv = this.ImageData[1][3], this.ImageData[2][3], this.ImageData[3][3]
	-- Y first
	for _ = 0, this.FFXData.CodecContext.height - 1 do
		for x = 0, usedFrame.linesize[0] - 1 do
			if x < this.FFXData.CodecContext.width then
				iy[idx2 * 4] = usedFrame.data[0][idx]
				idx2 = idx2 + 1
			end

			idx = idx + 1
		end
	end
	-- Same for U and V
	idx = 0
	idx2 = 0
	for _ = 0, this.FFXData.CodecContext.height * 0.5 - 1 do
		for x = 0, usedFrame.linesize[1] - 1 do
			if x < this.FFXData.CodecContext.width * 0.5 then
				iu[idx2 * 4] = usedFrame.data[1][idx]
				iv[idx2 * 4] = usedFrame.data[2][idx]
				idx2 = idx2 + 1
			end

			idx = idx + 1
		end
	end

	-- Reload Image object
	RefreshImage(this.ImageData[1][2], this.ImageData[1][1])
	RefreshImage(this.ImageData[2][2], this.ImageData[2][1])
	RefreshImage(this.ImageData[3][2], this.ImageData[3][1])

	if this:_readFrame() == false then
		this.EOS = true
	end
end

local shaderExistName = love._version >= "0.11.0" and "hasUniform" or "getExternVariable"
local function sendShaderSafe(shader, name, ...)
	if shader[shaderExistName](shader, name) then
		shader:send(name, select(1, ...))
	end
end

local graphics_draw = love.graphics.draw
function AquaShineVideo._draw(this, ...)
	local prevshdr = love.graphics.getShader()
	local curshader = prevshdr or vidshader

	if not(prevshdr) then
		love.graphics.setShader(vidshader)
	end

	-- Yes, that channel name is used for VideoTexel in LOVE 0.10.0 and later
	sendShaderSafe(curshader, "love_VideoYChannel", this.ImageData[1][2])
	sendShaderSafe(curshader, "love_VideoCbChannel", this.ImageData[2][2])
	sendShaderSafe(curshader, "love_VideoCrChannel", this.ImageData[3][2])
	graphics_draw(this.ImageData[1][2], select(1, ...))
	love.graphics.setShader(prevshdr)
end

--! @brief Play video
--! @param this AquaShineVideo object
function AquaShineVideo.play(this)
	if this.EOS or this:isPlaying() then return end

	-- Insert to playing queue
	FFX._playing[#FFX._playing + 1] = this
end

--! @brief Pause video
--! @param this AquaShineVideo object
function AquaShineVideo.pause(this)
	for i = 1, #FFX._playing do
		if FFX._playing[i] == this then
			table.remove(FFX._playing, i)

			return
		end
	end
end

--! @brief Seek video
--! @param this AquaShineVideo object
--! @param second Time in seconds
function AquaShineVideo.seek(this, sec)
	local ts = sec * this.TimeBase.den / this.TimeBase.num
	this.CurrentTime = sec
	avcodec.avcodec_flush_buffers(this.FFXData.CodecContext)
	assert(avformat.av_seek_frame(this.FFXData.FmtContext, this.VideoStreamIndex, ts, 1) >= 0, "Seek failed")
end

--! @brief Rewind video
--! @param this AquaShineVideo object
function AquaShineVideo.rewind(this)
	return this:seek(0)
end

function AquaShineVideo.isPlaying(this)
	for i = 1, #FFX._playing do
		if FFX._playing[i] == this then
			return true
		end
	end

	return false
end

-- Dimensions
function AquaShineVideo.getDimensions(this)
	return this.FFXData.CodecContext.width, this.FFXData.CodecContext.height
end

function AquaShineVideo.getWidth(this)
	return this.FFXData.CodecContext.width
end

function AquaShineVideo.getHeight(this)
	return this.FFXData.CodecContext.height
end

-- Filters
function AquaShineVideo.getFilter(this)
	return this.ImageData[1][2]:getFilter()
end

function AquaShineVideo.setFilter(this, min, mag, anis)
	return this.ImageData[1][2]:setFilter(min, mag, anis)
end

-- Utils
function AquaShineVideo.getSource()
	return nil
end

function AquaShineVideo.type()
	return "AquaShineVideo"
end

function AquaShineVideo.typeOf(_, type)
	return
		type == "AquaShineVideo" or
		type == "Video" or
		type == "Drawable" or
		type == "Object"
end

function FFX.LoadVideo(path)
	return AquaShineVideo(path)
end

function FFX.Update(deltaT)
	deltaT = deltaT * 0.001

	for i = #FFX._playing, 1, -1 do
		local obj = FFX._playing[i]
		obj:_stepVideo(deltaT)

		if obj.EOS then
			table.remove(FFX._playing, i)
		end
	end
end

local audioPacket = ffi.new("AVPacket[1]")
local audioFrameFinished = ffi.new("int[1]")
function FFX.LoadAudio(path, memstr)
	-- Load the file with love.filesystem API
	local filestream
	local seektype

	if memstr then
		filestream = stringstream.create(path)
		seektype = make_seek_callback_mem(filestream, true)
	else
		filestream = assert(love.filesystem.newFile(path, "r"))
		seektype = make_seek_callback(filestream, true)
	end

	local readtype = make_read_callback(filestream, true)

	-- Create AVIOContext
	local IOContext = avformat.avio_alloc_context(
		nil, 0, 0, nil,
		readtype, nil, seektype
	)

	-- Allocate AVFormatContext
	local tempfmtctx = ffi.new("AVFormatContext*[1]")
	tempfmtctx[0] = avformat.avformat_alloc_context()
	tempfmtctx[0].pb = IOContext

	-- Open input
	if avformat.avformat_open_input(tempfmtctx, path, nil, nil) < 0 then
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()
		assert(false, "Cannot open input file")
	end

	-- Find audio stream
	local audiostreamidx

	if avformat.avformat_find_stream_info(tempfmtctx[0], nil) < 0 then
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()
		assert(false, "Failed to determine stream info")
	end

	for i = 1, tempfmtctx[0].nb_streams do
		local codec_type = tempfmtctx[0].streams[i - 1].codec.codec_type

		if codec_type == "AVMEDIA_TYPE_AUDIO" then
			audiostreamidx = i - 1
			break
		end
	end

	if not(audiostreamidx) then
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()
		assert(false, "Audio stream not found")
	end

	local audiostream = tempfmtctx[0].streams[audiostreamidx]

	-- Find decoder
	local codec = avcodec.avcodec_find_decoder(audiostream.codec.codec_id)
	if codec == nil then
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()
		assert(false, "Codec not found")
	end

	-- Create CodecContext
	local CodecContext = avcodec.avcodec_alloc_context3(codec)

	if avcodec.avcodec_copy_context(CodecContext, audiostream.codec) < 0 then
		avcodec.avcodec_close(CodecContext)
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()

		assert(false, "Failed to copy context")
	end

	if avcodec.avcodec_open2(CodecContext, codec, nil) < 0 then
		avcodec.avcodec_close(CodecContext)
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()

		assert(false, "Cannot open codec")
	end

	-- Create SwrContext
	local SwrCtx = ffi.new("SwrContext*[1]")
	SwrCtx[0] = swresample.swr_alloc_set_opts(nil,
		3,
		"AV_SAMPLE_FMT_S16",
		44100,
		audiostream.codec.channel_layout,
		audiostream.codec.sample_fmt,
		audiostream.codec.sample_rate,
		0, nil
	)

	if swresample.swr_init(SwrCtx[0]) < 0 then
		avcodec.avcodec_close(CodecContext)
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()

		assert(false, "Failed to initialize swresample")
	end

	-- Create new SoundData
	local SampleCountLove2D = math.ceil((tonumber(tempfmtctx[0].duration) / 1000000 + 1) * 44100)
	local SoundData = love.sound.newSoundData(SampleCountLove2D, 44100, 16, 2)
	local SoundDataPointer = ffi.cast("uint8_t*", SoundData:getPointer())
	local AudioFrame = avutil.av_frame_alloc()

	if AudioFrame == nil then
		swresample.swr_free(SwrCtx)
		avcodec.avcodec_close(CodecContext)
		avformat.avformat_close_input(tempfmtctx)
		avutil.av_free(IOContext)
		readtype:free()
		seektype:free()
		filestream:close()

		assert(false, "Failed to initialize frame")
	end

	local outbuf = ffi.new("uint8_t*[2]")
	local out_size = SampleCountLove2D
	outbuf[0] = SoundDataPointer

	-- Decode audio
	local readframe = avformat.av_read_frame(tempfmtctx[0], audioPacket)
	while readframe >= 0 do
		if audioPacket[0].stream_index == audiostreamidx then
			local decodelen = avcodec.avcodec_decode_audio4(CodecContext, AudioFrame, audioFrameFinished, audioPacket)

			if decodelen < 0 then
				FreeAVFrame(AudioFrame)
				avcodec.av_free_packet(audioPacket)
				swresample.swr_free(SwrCtx)
				avcodec.avcodec_close(CodecContext)
				avformat.avformat_close_input(tempfmtctx)
				avutil.av_free(IOContext)
				readtype:free()
				seektype:free()
				filestream:close()

				assert(false, "Audio decoding error")
			end

			if audioFrameFinished[0] > 0 then
				local samples = swresample.swr_convert(SwrCtx[0],
					outbuf, AudioFrame.nb_samples,
					ffi.cast("const uint8_t**", AudioFrame.extended_data),
					AudioFrame.nb_samples
				)

				if samples < 0 then
					FreeAVFrame(AudioFrame)
					avcodec.av_free_packet(audioPacket)
					swresample.swr_free(SwrCtx)
					avcodec.avcodec_close(CodecContext)
					avformat.avformat_close_input(tempfmtctx)
					avutil.av_free(IOContext)
					readtype:free()
					seektype:free()
					filestream:close()

					assert(false, "Resample error")
				end

				outbuf[0] = outbuf[0] + samples * 4
				out_size = out_size - samples
			end
		end

		avcodec.av_free_packet(audioPacket)
		readframe = avformat.av_read_frame(tempfmtctx[0], audioPacket)
	end

	-- Flush buffer
	swresample.swr_convert(SwrCtx[0], outbuf, out_size, nil, 0)

	-- Free
	FreeAVFrame(AudioFrame)
	avcodec.av_free_packet(audioPacket)
	swresample.swr_free(SwrCtx)
	avcodec.avcodec_close(CodecContext)
	avformat.avformat_close_input(tempfmtctx)
	avutil.av_free(IOContext)
	readtype:free()
	seektype:free()
	filestream:close()

	return SoundData
end

-- Inject our proxy to love.graphics.draw
function love.graphics.draw(obj, ...)
	if type(obj) == "table" and obj.FFXData then
		return obj:_draw(select(1, ...))
	else
		graphics_draw(obj, select(1, ...))
	end
end

-- Set the AquaShine variable
if AquaShine then
	AquaShine.FFmpegExt = FFX
else
	-- Need to inject update code in `love.timer.step`
	if love.timer then
		local step = love.timer.step
		function love.timer.step()
			step()
			local dt = love.timer.getDelta()
			FFX.Update(dt * 1000)
			return dt
		end
	end
end

return FFX
