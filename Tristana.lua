local tristana = GetLocalPlayer() 
if tristana:GetChampionName() ~= "Tristana" then return -1 end --Exit lua script if we are not playing tristana
dofile("lua/SDK.lua")	--SDK.lua is needed for some enums and instaces. 	

--Menu settings.
--Place Menu Functions only at the start of the program! dont place them inside any function.
tristanaMenu = CreateMenu("LuaTristana", "LUA Tristana")				--Create menu bar for tristana, note: 1st param config name, 2nd display name
combo = tristanaMenu:AddMenu("combosettings", "Combo Settings", 50) --Add another menu, 3rd param is extra width for our menu so text fits (OPTIONAL)
combo:AddInfo("qsettings", "--- Q Settings ---")
useQCombo = combo:AddCheckBox("useq", "Use Q", true)				--3rd param in AddCheckBox is default value (OPTIONAL)
combo:AddInfo("wsettings", "--- W Settings ---")					--Add info simply creates a box with text only
useW1v1 = combo:AddCheckBox("usew1v1", "Use W if killable 1v1", false)
combo:AddInfo("esettings", "--- E Settings ---")
useECombo = combo:AddCheckBox("usee", "Use E on orbwalker target")
combo:AddInfo("rsettings", "--- R Settings ---")
useRKS = combo:AddCheckBox("useRks", "Use R for killsteal", true)
autoRInterrupt = combo:AddCheckBox("userinterrupt", "Auto R to Interrupt", true)
autoREnemyTower = combo:AddCheckBox("usertoallytower", "Auto R enemy towards ally tower", true)
autoRMinHP = combo:AddSlider("usermelowhp", "Auto R melee when im Low HP%", 40, 0, 100 )  --3rd param default Value, 4th Minimum value, 5th maximum value
autoRDistance = combo:AddSlider("userenemyclose", "^- Minimum Distance to do it", 400, 0, 700 )
--test = combo:AddSliderFloat("floatthing", "^- this is a float ", 0, 0, 10 )
--Drawing settings
drawings = tristanaMenu:AddMenu("drawingsettings", "Drawing Settings")
drawQTimer = drawings:AddCheckBox("drawqtimer", "Draw Q Timer")
drawWRange = drawings:AddCheckBox("drawwRange", "Draw W Range")
drawERange = drawings:AddCheckBox("draweRange", "Draw E Range")
drawRRange = drawings:AddCheckBox("drawrRange", "Draw R Range")
drawQTimer:AddTooltip("This will show much time you have remaining")

local isQReady = false
local isWReady = false
local isEReady = false
local isRReady = false

--function to calculate both E and R range. LolWiki is your friend when making scripts!
function GetERRange()
	return 517 + tristana:GetLevel() * 8 + tristana:GetBoundingRadius()
end

function GetRDamage(target)
	--MAGIC DAMAGE: 300 / 400 / 500 (+ 100% AP) per level
	local rLevel = tristana:GetSpellLevel(_R)
	if rLevel < 1 then return 0 end
	local baseDmg = 200 + (100 * rLevel)
	local totalDmg = baseDmg + tristana:GetAbilityPower() 
	return CalculateMagicalDamage(tristana, target, totalDmg) --Calculates Post mitigation damage (after magic resists etc)
end			--Params: Source (sender champ), target (reciever champ), amount

-- Finds how many stacks Tristana E has on a target. and it uses 2 buffs
-- -1 means E is not present and 0 that it is but with no extra stacks (attacks)
function GetEStacks(target)
	local buff = target:GetBuffByName("tristanaecharge")

	if buff == nil then
		local soundBuff = target:GetBuffByName("tristanaechargesound")

		if soundBuff ~= nil then
			return 0
		else
			return -1
		end
	else
		return buff:GetCount()
	end
end

--Calculates E damage for Current stacks + one we provide
function CalculateEDamage(target, extraStacks, checkIfItExists) --can return 0 if the buff isnt there (we want current dmg), or not if we want to predict the damage
	--MINIMUM PHYSICAL DAMAGE: 70 / 80 / 90 / 100 / 110 (+50 / 75 / 100 / 125 / 150 % bonus AD) (+50 % AP)
	--BONUS DAMAGE PER STACK: 21 / 24 / 27 / 30 / 33 (+15 / 22.5 / 30 / 37.5 / 45 % bonus AD) (+15 % AP)
	--total damage is additionally increased by 0% - 33.3% (based on critical strike chance).
	local baseDmg = {70, 80, 90, 100, 110}
	local bonusDmg = {21, 24, 27, 30, 33}
	local adRatio = {0.5, 0.75, 1.0, 1.25, 1.5}
	local adRatioPerStack = {0.15, 0.225, 0.3, 0.375, 0.45}
	local critChance = tristana:GetCritDecimal()
	local level = tristana:GetSpellLevel(_E)
	local bonusAD = tristana:GetBonusAttackDamage()
	local ap = tristana:GetAbilityPower()

	local buffStacks = GetEStacks(target)
	if buffStacks == -1 and checkIfItExists then return 0.0 end

	local stacks = buffStacks + extraStacks
	if stacks > 4 then stacks = 4 end

	local critRatio = critChance * 0.333
	local totalBaseDmg = baseDmg[level] + bonusAD * adRatio[level] + ap * 0.5
	local totalBonusDmg = bonusDmg[level] + bonusAD * adRatioPerStack[level] + ap * 0.15
	local totalDmg = totalBaseDmg + totalBonusDmg * stacks
	totalDmg = totalDmg * (1 + critRatio)
	return CalculatePhysicalDamage(tristana, target, totalDmg)
end

function QComboLogic()
	if useQCombo:GetValue() then -- if useQ setting is enabled (its checkbox so boolean)
		if orbwalker:GetCurrentTarget() ~= nil and isQReady then --GetCurrentTarget returns nil if it doesnt have one
			CastSpell(_Q)
		end
	end
end

function GetComboDamage(target, autos) --calculate full current combo damage on target
	local aaDmg = GetAADamageAgainst(tristana, target) * autos --GetAADamageAgainst returns post mitigation dmg and takes into account
	local eDmg = 0.0										--items but NOT champion passive onhit bonus (eg kaisa passive)
	local rDmg = 0.0

	if isEReady then 
		eDmg = CalculateEDamage(target, 4, false)
	else
		eDmg = CalculateEDamage(target, 1, true)
	end

	if isRReady then
		rDmg = GetRDamage(target)
	end

	return aaDmg + eDmg + rDmg
end

function WComboLogic()--return if the setting is disabled, or W is on cd or we are in range to auto (no w needed to fight)
	if not useW1v1:GetValue() or not isWReady or orbwalker:GetCurrentTarget() ~= nil then return end
	--if its not a 1v1 then return
	if GetHeroCountAround(TEAM_ENEMY, 1500) > 1 then return end
								--View SDK.lua for all options
	local target = GetBestTarget(TSELECTOR_LOWHP, 900 + GetERRange())
	if target == nil then return end

	if GetComboDamage(target, 6) >= target:GetHealth() then
		local distance = tristana:GetDistanceTo(target)
		local extendBy = 900
	--	local distanceAfterW = distance - extendBy
		local castPos = tristana:GetPosition():ExtendTo(target:GetPosition(), extendBy)

		CastSpellWorld(_W, castPos)
	end
end

function EComboLogic()
	if useECombo:GetValue() then
		local currentTarget = orbwalker:GetCurrentTarget()	-- IMPORTANT! If a Spell is "edge range" then the player's HITBOX (bounding radius) is also counted on top of spell range! https://prnt.sc/XxTnYNgRFCXi
		if currentTarget ~= nil and currentTarget:GetDistanceTo(tristana) <= GetERRange() + currentTarget:GetBoundingRadius() and isEReady then
			local castingAA = orbwalker:IsCastingAA()
			CastSpellTargeted(_E, currentTarget)

			if castingAA then --incase we were casting AA when we casted E then reset the aa timer so orbwalker doesnt wait
				orbwalker:ResetAATimer()
			end

		end
	end
end
	
function RComboLogic()	
	--local rDmg = GetRDamage()
	if not useRKS:GetValue() or not isRReady then return end

	local Rrange = GetERRange()
	local enemies = GetHeroList(TEAM_ENEMY) --Get Hero List
	for i = 1, #enemies do					-- for every hero...
		local enemy = enemies[i]					-- check if he is inrange and he is alive..
		if enemy:GetDistanceTo(tristana) <= Rrange + enemy:GetBoundingRadius() and enemy:IsAlive() then
			local dmg = GetRDamage(enemy) + CalculateEDamage(enemy, 1, true) --If R + E dmg is bigger than his health. (ult applies +1 stack)
			if dmg >= enemy:GetHealth() then
				CastSpellTargeted(_R, enemy)				-- Cast R on him
			end
		end
	end
end

function GetRKnockbackDistance()
	return 400 + 200 * tristana:GetSpellLevel(_R)
end

function AutoRUnderTurret()
	if not autoREnemyTower:GetValue() or not isRReady then return end

	local enemies = GetHeroList(TEAM_ENEMY) --Get Hero List
	for i = 1, #enemies do					-- for every hero...
		local enemy = enemies[i]
		local distance = tristana:GetDistanceTo(enemy)
		if distance <= GetERRange() + enemy:GetBoundingRadius() and enemy:IsAlive() then --enemy flies back towards our direction when we cast R therefore
			local postRPos = tristana:GetPosition():ExtendTo(enemy:GetPosition(), distance + GetRKnockbackDistance()) --post r pos is our pos extended to the enemy + knockback distance
			if IsPosUnderTurret(TEAM_ALLY, postRPos) then -- if enemy pos after R is under ally tower range 
				CastSpellTargeted(_R, enemy)
			end
		end
	end
end

function AutoRMelee()
	if autoRMinHP:GetValue() == 0 or not isRReady then return end

	local enemies = GetHeroList(TEAM_ENEMY) --Get Hero List
	for i = 1, #enemies do					-- for every hero...
		local enemy = enemies[i]
		local distance = tristana:GetDistanceTo(enemy)
		local rRange = GetERRange()
		if distance <= rRange + enemy:GetBoundingRadius() and enemy:IsAlive() and enemy:IsMelee() then
			if distance <= autoRDistance:GetValue() and tristana:GetHealthPercent() <= autoRMinHP:GetValue() then
				CastSpellTargeted(_R, enemy)
			end
		end
	end
end

--Every Lua script needs to have OnTick and OnDraw callbacks otherwise it will fail!
function OnTick()   --This is our main loop. all script logic goes here.
	isQReady = tristana:IsSpellReady(_Q)-- Get spell state for each spell separately -- IsSpellReady function does some additional checks to make sure its both off cd and also
	isEReady = tristana:IsSpellReady(_E)-- player has enough mana and is not CCed, however this may not work for every champ spell (eg trynd R).
	isRReady = tristana:IsSpellReady(_R)-- If you just want to check if is off CD use IsSpellOffCD and do your own checks to make sure its castable

	isWReady = tristana:IsSpellReady(_W, true) -- 2nd param checks for if the spell is a dashing one (OPTIONAL)

	if orbwalker:IsInCombo() then
		QComboLogic()
		WComboLogic()
		EComboLogic()
		RComboLogic()
	end

	AutoRUnderTurret()
	AutoRMelee()
end

-- Place Drawing functions ONLY inside OnDraw callback!
function OnDraw()
	local tristanaPos = tristana:GetPosition()
	if drawQTimer:GetValue() then
		local qBuff = tristana:GetBuffByName("TristanaQ")
		if qBuff ~= nil then
			local screenPos = WorldToScreen(tristanaPos)
			local text = "Q " .. string.format("%.1f", qBuff:GetRemainingTime())
			DrawTextScreen(screenPos,text, false, ColorRGBA(0,255,0,255))
		end
	end

	if drawWRange:GetValue() then --Params: 1st worldposition, 2nd radius, 3rd line thickness, 4th line color (Red, green, blue, transparency)
		DrawCircleWorld(tristanaPos, 900, 1, ColorRGBA(255,255,255,120)) 
	end
	if drawERange:GetValue() then
		DrawCircleWorld(tristanaPos, GetERRange(), 1, ColorRGBA(255,255,255,120))
	end
	if drawRRange:GetValue() then
		DrawCircleWorld(tristanaPos,  GetERRange(), 1, ColorRGBA(255,255,255,120))
	end
end