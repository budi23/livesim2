-- Base Live UI class
-- Part of Live Simulator: 2
-- See copyright notice in main.lua

-- Live UI handles almost everything.
-- Combo counter, score display, stamina display, ...

local Luaoop = require("libs.Luaoop")
local uibase = Luaoop.class("livesim2.LiveUI")

-- luacheck: no unused args

-----------------
-- Base system --
-----------------

function uibase.__construct()
	-- constructor must run in async manner!
	error("attempt to construct abstract class 'UI'", 2)
end

function uibase:update(dt)
	error("pure virtual method 'update'", 2)
end

--------------------
-- Scoring System --
--------------------

function uibase:setScoreRange(cs, bs, as, ss)
	error("pure virtual method 'setScoreRange'", 2)
end

function uibase:addScore(amount)
	error("pure virtual method 'addScore'", 2)
end

function uibase:getScore()
	error("pure virtual method 'getScore'", 2)
	return 0
end

function uibase:setScore(score)
	error("pure virtual method 'setScore'", 2)
end

------------------
-- Combo System --
------------------

function uibase:comboJudgement(judgement)
	-- handle whetevr to increment combo or break
	error("pure virtual method 'comboJudgement'", 2)
end

function uibase:getCurrentCombo()
	error("pure virtual method 'getCurrentCombo'", 2)
end

function uibase:getMaxCombo()
	error("pure virtual method 'getMaxCombo'", 2)
end

-------------
-- Stamina --
-------------

function uibase:setMaxStamina(stamina)
	error("pure virtual method 'setMaxStamina'", 2)
end

function uibase:getMaxStamina()
	error("pure virtual method 'getMaxStamina'", 2)
	return 45
end

function uibase:getStamina()
	error("pure virtual method 'getStamina'", 2)
	return 32
end

function uibase:addStamina(amount)
	-- amount can be positive or negative
	error("pure virtual method 'addStamina'", 2)
	return 32+5
end

------------------
-- Pause button --
------------------

function uibase:enablePause()
	error("pure virtual method 'enablePause'", 2)
end

function uibase:disablePause()
	error("pure virtual method 'disablePause'", 2)
end

function uibase:checkPause(x, y)
	error("pure virtual method 'checkPause'", 2)
	return true or false
end

------------------
-- Other things --
------------------

function uibase:addTapEffect(x, y, r, g, b, a)
	error("pure virtual method 'addTapEffect'", 2)
end

function uibase:setTextScaling(scale)
	error("pure virtual method 'setTextScaling'", 2)
end

function uibase:setOpacity(opacity)
	error("pure virtual method 'setOpacity'", 2)
end

-------------
-- Drawing --
-------------

function uibase:drawHeader()
	error("pure virtual method 'drawHeader'", 2)
end

function uibase:drawStatus()
	error("pure virtual method 'drawStatus'", 2)
end

return uibase