-- Live Simulator: 2
-- High-performance LL!SIF Live Simulator

--[[---------------------------------------------------------------------------
-- Copyright (c) 2038 Dark Energy Processor Corporation
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.
--]]---------------------------------------------------------------------------

-- Version
DEPLS_VERSION = "2.0-20170701"
DEPLS_VERSION_NUMBER = 01010402	-- xxyyzzww. x = major, y = minor, z = patch, w = pre-release counter

----------------------
-- AquaShine loader --
----------------------
local AquaShine = assert(love.filesystem.load("AquaShine.lua"))({
	Entries = {
		livesim = {1, "livesim.lua"},
		settings = {0, "setting_view.lua"},
		main_menu = {0, "main_menu.lua"},
		beatmap_select = {0, "select_beatmap.lua"},
		unit_editor = {0, "unit_editor.lua"},
		about = {0, "about_screen.lua"},
		render = {3, "render_livesim.lua"},
		noteloader = {1, "invoke_noteloader.lua"},
		unit_create = {0, "unit_create.lua"},
		bsv2 = {0, "beatmap_select.lua"},
	},
	DefaultEntry = "main_menu",
	Width = 960,	-- Letterboxing
	Height = 640	-- Letterboxing
})

--------------------------------
-- Yohane Initialization Code --
--------------------------------
local Yohane = require("Yohane")

Yohane.Platform.ResolveImage = AquaShine.LoadImage
function Yohane.Platform.ResolveAudio(path)
	return love.audio.newSource(AquaShine.LoadAudio(path .. ".wav"))
end

function Yohane.Platform.CloneImage(image_handle)
	return image_handle
end

function Yohane.Platform.CloneAudio(audio)
	if audio then
		return audio:clone()
	end
	
	return nil
end

function Yohane.Platform.PlayAudio(audio)
	if audio then
		audio:stop()
		audio:play()
	end
end

function Yohane.Platform.Draw(drawdatalist)
	local r, g, b, a = love.graphics.getColor()
	
	for _, drawdata in ipairs(drawdatalist) do
		if drawdata.image then
			love.graphics.setColor(drawdata.r, drawdata.g, drawdata.b, drawdata.a)
			love.graphics.draw(drawdata.image, drawdata.x, drawdata.y, drawdata.rotation, drawdata.scaleX, drawdata.scaleY)
		end
	end
	
	love.graphics.setColor(r, g, b, a)
end

function Yohane.Platform.OpenReadFile(fn)
	return assert(love.filesystem.newFile(fn, "r"))
end

Yohane.Init(love.filesystem.load)

-- Touch Effect --
local ps = love.graphics.newParticleSystem(AquaShine.LoadImage("assets/flash/ui/live/img/ef_326_003.png"), 1000)
ps:setSpeed(4, 20)
ps:setParticleLifetime(0.25, 1)
ps:setLinearAcceleration(-30, -30, 30, 30)
ps:setAreaSpread("normal", 5, 5)
ps:setEmissionRate(25)
ps:setColors(255, 255, 255, 255, 255, 255, 255, 0)
ps:setRotation(0, math.pi * 2)
ps:setSpin(0, math.pi * 2)
ps:setSpinVariation(1)
ps:setSizes(0.25, 0.8)
ps:setSizeVariation(1)
ps:pause()

AquaShine.SetTouchEffectCallback {
	Start = function()
		ps:start()
	end,
	Pause = function()
		ps:pause()
	end,
	SetPosition = function(x, y)
		ps:setPosition(x, y)
	end,
	Update = function(deltaT)
		ps:update(deltaT)
	end,
	Draw = function()
		love.graphics.draw(ps)
	end
}

----------------------------
-- Force Create Directory --
----------------------------
assert(love.filesystem.createDirectory("audio"), "Failed to create directory")
assert(love.filesystem.createDirectory("beatmap"), "Failed to create directory")
assert(love.filesystem.createDirectory("screenshots"), "Failed to create directory")
assert(love.filesystem.createDirectory("unit_icon"), "Failed to create directory")
assert(love.filesystem.createDirectory("temp"), "Failed to create directory")
