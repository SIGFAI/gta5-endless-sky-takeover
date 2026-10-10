-- Endless Sky Takeover: Sandy Shores becomes a spaceport. Spacesuit troopers fight alien pirates, every fighter has
-- recharging shields, kills pay credits, a shuttle lands, escort ships strafe with lasers and pirate raiders warp in.
local credits, kills, raidersDown = 1000, 0, 0
local sides = {}          -- ped -> 'a' (Free Worlds) | 'b' (pirate)
local shield = {}         -- ped -> { arm, hp, flash, hitAt }
local ships = {}          -- every spaceship in the sky
local bolts = {}          -- laser bolts in flight
local MAXSH = 60
local HEAD_OFFSET = { sigf_shuttle = 0.0, sigf_raider = 0.0, sigf_freighter = 0.0 }

local function now() return GetGameTimer() end
local function vlerp(a, b, t) return a + (b - a) * t end
local function headingOf(dx, dy) return math.deg(math.atan(-dx, dy)) end
local function me() return PlayerPedId() end
local function isDemo() return Sigf.Stage() == 'demo' end

local logLines = {}   -- the message log drawn natively (bottom right)
local function log(text, kind)
	logLines[#logLines + 1] = { text = text, kind = kind or 'info', at = GetGameTimer() }
	while #logLines > 4 do table.remove(logLines, 1) end
end
local function addCredits(n) credits = credits + n end

-- The point the sky show happens around: ahead of the player in the demo, the runway on the stream.
local function skyCenter()
	if isDemo() then
		local p = GetOffsetFromEntityInWorldCoords(me(), 0.0, 26.0, 0.0)
		return vector3(p.x, p.y, GetEntityCoords(me()).z - 1.0)
	end
	local a = Sigf.Arena()
	return vector3(a.x, a.y, a.z)
end

-- ---------- fighters: shields, names, hit flashes ----------
local function dress(ped, side)
	sides[ped] = side
	SetPedArmour(ped, MAXSH)
	shield[ped] = { arm = MAXSH, hp = GetEntityHealth(ped), flash = 0, hitAt = 0 }
end

Sigf.OnSpawn(function(ped, side)
	dress(ped, side or (GetPedRelationshipGroupHash(ped) == GetHashKey('SIGF_B') and 'b' or 'a'))
end)

Sigf.OnKill(function(ped)
	local side = sides[ped]
	sides[ped] = nil shield[ped] = nil
	local p = GetEntityCoords(ped)
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 0.8), { scale = 1.5 })
	if side == 'b' then
		local pay = 200 + math.random(0, 12) * 25
		addCredits(pay) kills = kills + 1
		Sigf.Text3D('+' .. pay .. ' cr', p + vector3(0, 0, 1.4), 2.2, { color = { 255, 215, 60 }, scale = 0.7, rise = 1.2 })
		Sigf.Sound('credits', p)
		Sigf.Fx(Sigf.FX.money[1], Sigf.FX.money[2], p + vector3(0, 0, 1.0), { scale = 1.0 })
		log('Pirate disabled. Bounty: ' .. pay .. ' credits.', 'good')
	else
		log('A Free Worlds trooper was lost.', 'bad')
	end
end)

Sigf.Every(0.1, function()
	local t = now()
	for ped, s in pairs(shield) do
		if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
			shield[ped] = nil sides[ped] = nil
		else
			local arm, hp = GetPedArmour(ped), GetEntityHealth(ped)
			if arm < s.arm or hp < s.hp then s.flash = t s.hitAt = t end
			if t - s.hitAt > 3000 and arm < MAXSH then arm = math.min(MAXSH, arm + 3) SetPedArmour(ped, arm) end
			s.arm, s.hp = arm, hp
		end
	end
end)

local function text2d(str, x, y, scale, r, g, b, a)
	SetTextFont(4) SetTextScale(0.0, scale) SetTextColour(r, g, b, a) SetTextOutline() SetTextCentre(true)
	BeginTextCommandDisplayText('STRING') AddTextComponentSubstringPlayerName(str) EndTextCommandDisplayText(x, y)
end

local function bar(x, y, w, frac, r, g, b)
	DrawRect(x, y, w + 0.002, 0.008, 0, 0, 0, 170)
	DrawRect(x - w / 2 + w * frac / 2, y, w * frac, 0.005, r, g, b, 230)
end

Sigf.Frame(function()
	local cam = GetFinalRenderedCamCoord()
	local t = now()
	for ped, s in pairs(shield) do
		if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
			local p = GetEntityCoords(ped)
			if #(p - cam) < 55.0 then
				local nearCam = #(p - cam) < 5.0
				local age = t - s.flash
				if age < 380 and not nearCam then
					local a = math.floor(70 * (1 - age / 380))
					DrawMarker(28, p.x, p.y, p.z, 0, 0, 0, 0, 0, 0, 1.7, 1.7, 2.3, 90, 200, 255, a, false, false, 2, false, nil, nil, false)
					DrawLightWithRange(p.x, p.y, p.z, 90, 200, 255, 4.0, 1.5 * (1 - age / 380))
				end
				local ok, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 1.05)
				if ok then
					local side = sides[ped]
					if side == 'b' then text2d('PIRATE', sx, sy - 0.03, 0.26, 255, 90, 80, 230)
					else text2d('FREE WORLDS', sx, sy - 0.03, 0.26, 110, 190, 255, 230) end
					bar(sx, sy, 0.045, math.max(0, (s.arm or 0) / MAXSH), 90, 200, 255)
					bar(sx, sy + 0.009, 0.045, math.max(0, math.min(1, (s.hp - 100) / 100)), 255, 150, 40)
				end
			end
		end
	end
end)

-- ---------- lasers ----------
local function fireBolt(from, to, color, dur, onHit)
	bolts[#bolts + 1] = { from = from, to = to, color = color, dur = dur, t0 = now(), onHit = onHit }
end

Sigf.Frame(function()
	local t = now()
	for i = #bolts, 1, -1 do
		local b = bolts[i]
		local k = (t - b.t0) / (b.dur * 1000)
		if k >= 1.0 then
			if b.onHit then Sigf.Safe('bolt', b.onHit) end
			table.remove(bolts, i)
		else
			local head = vlerp(b.from, b.to, k)
			local tail = vlerp(b.from, b.to, math.max(0.0, k - 0.4))
			local c = b.color
			for _, o in ipairs({ { 0, 0 }, { 0.03, 0 }, { -0.03, 0 }, { 0, 0.03 }, { 0, -0.03 }, { 0.05, 0.05 }, { -0.05, -0.05 }, { 0.05, -0.05 }, { -0.05, 0.05 } }) do
				DrawLine(tail.x + o[1], tail.y + o[2], tail.z, head.x + o[1], head.y + o[2], head.z, c[1], c[2], c[3], 255)
			end
			if #(head - GetFinalRenderedCamCoord()) > 9.0 then DrawMarker(28, head.x, head.y, head.z, 0, 0, 0, 0, 0, 0, 0.05, 0.05, 0.05, c[1], c[2], c[3], 200, false, false, 2, false, nil, nil, false) end
			DrawLightWithRange(head.x, head.y, head.z, c[1], c[2], c[3], 9.0, 4.0)
		end
	end
end)

-- The player's own gun shoots blue energy bolts, and hurts raiders it hits.
local BLUE, RED = { 70, 170, 255 }, { 255, 60, 50 }
local damageShip

Sigf.Frame(function()
	local ped = me()
	if isDemo() and IsPedShooting(ped) then
		local from = GetPedBoneCoords(ped, 57005, 0.0, 0.0, 0.0)
		local fwd = GetEntityForwardVector(ped)
		for _, s in ipairs(ships) do
			if s.kind == 'raider' and not s.dying and not s.dead then
				local center = s.pos + vector3(0, 0, s.cz)
				local to = center - from
				local flat = math.sqrt(to.x * to.x + to.y * to.y)
				local cosA = (fwd.x * to.x + fwd.y * to.y) / math.max(flat, 0.01)
				-- the player is shooting toward the ship: the bolt flies to its hull
				if flat < 60.0 and cosA > 0.93 then
					local hit = center + vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.8) * 4.0
					fireBolt(from, hit, BLUE, 0.12)
					damageShip(s, 6, hit)
				end
			end
		end
		local ok, c = GetPedLastWeaponImpactCoord(ped)
		if ok then fireBolt(from, c, BLUE, 0.10) end
	end
end)

-- ---------- ships ----------
local function placeShip(s)
	local p = s.pos + (s.shake or vector3(0, 0, 0))
	SetEntityCoordsNoOffset(s.ent, p.x, p.y, p.z, false, false, false)
	SetEntityRotation(s.ent, s.pitch or 0.0, s.roll or 0.0, s.heading + (HEAD_OFFSET[s.model] or 0.0), 2, true)
end

local function newShip(model, kind, name, pos, opts)
	opts = opts or {}
	local ent = Sigf.Prop(model, pos, { life = opts.life or 0, alpha = opts.alpha })
	if not ent then return nil end
	local s = { ent = ent, model = model, kind = kind, name = name, pos = pos, heading = 0.0, hull = opts.hull or 100, maxHull = opts.hull or 100,
		nextFire = now() + 2000, born = now(), cz = (model == 'sigf_freighter') and 2.0 or 1.6 }
	ships[#ships + 1] = s
	placeShip(s)
	return s
end

local function removeShip(s)
	s.dead = true
	if s.fx then Sigf.StopFx(s.fx) s.fx = nil end
	if s.ent and DoesEntityExist(s.ent) then Sigf.Remove(s.ent) end
end

-- The same two soft lights on every ship (one toward the camera, one under) so all hulls read alike.
local function fillLight(s)
	local p = s.pos
	local toCam = GetFinalRenderedCamCoord() - p
	local len = #toCam
	if len > 1.0 then
		local kp = p + toCam / len * 6.0
		DrawLightWithRange(kp.x, kp.y, kp.z, 255, 248, 240, 24.0, 8.0)
		DrawLightWithRange(kp.x, kp.y, kp.z + 5.0, 255, 248, 240, 24.0, 2.0)
	end
	DrawLightWithRange(p.x, p.y, p.z - 3.0, 255, 245, 235, 22.0, 4.0)
end

-- A column of flickering fire under a ship while it lands or lifts off.
local function thrusterColumn(s, power)
	local p = s.pos
	for i = 0, 5 do
		local f = math.random() * 0.4 + 0.6
		local r = (1.6 - i * 0.22) * f * power
		DrawMarker(28, p.x, p.y, p.z - 0.4 - i * 0.9, 0, 0, 0, 0, 0, 0, r, r, r * 1.6,
			255, i < 2 and 230 or 130 - i * 8, i < 2 and 140 or 30, math.floor(150 - i * 18), false, false, 2, false, nil, nil, false)
	end
	DrawLightWithRange(p.x, p.y, p.z - 3.0, 255, 150, 50, 20.0, 8.0 * power)
end

local function engineGlow(s, color, behind)
	local fwd = vector3(-math.sin(math.rad(s.heading)), math.cos(math.rad(s.heading)), 0.0)
	local p = s.pos - fwd * behind
	DrawLightWithRange(p.x, p.y, p.z, color[1], color[2], color[3], 14.0, 5.0)
end

local function jumpFlash(pos)
	Sigf.Fx(Sigf.FX.flare[1], Sigf.FX.flare[2], pos, { scale = 6.0 })
	Sigf.Light(pos, { 200, 220, 255 }, 40.0, 12.0, 1.2)
	Sigf.Sound('thruster', pos)
end

local function warpInRaider(angle0, radius, dir)
	local c = skyCenter()
	local s = newShip('sigf_raider', 'raider', 'PIRATE RAIDER', c + vector3(radius, 0, 9), { hull = 200, alpha = 0 })
	if not s then return nil end
	s.ang, s.radius, s.dir, s.alt = angle0, radius, dir, isDemo() and 3.2 or 9.0
	s.spd = 0.45 * dir
	jumpFlash(s.pos)
	log('Pirate raider jumped into the system!', 'bad')
	return s
end

damageShip = function(s, dmg, at)
	if s.dying or s.dead then return end
	s.hull = s.hull - dmg
	s.hitAt = now()
	s.flash = now()
	s.shakeUntil = now() + 250
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], at or s.pos, { scale = 2.0 })
	DrawLightWithRange(s.pos.x, s.pos.y, s.pos.z, 120, 200, 255, 12.0, 6.0)
	if s.hull <= 0 then
		s.dying = true s.dyingAt = now() s.vz = 0.0
		s.fx = Sigf.Fx('core', 'ent_sht_flame', s.ent, { loop = true, life = 6, offset = vector3(0, 0, 0.5), scale = 2.0 })
		log('Pirate raider destroyed! +1000 credits', 'good')
	elseif s.hull < s.maxHull * 0.5 and not s.smoking then
		s.smoking = true
		s.smokeFx = Sigf.Fx(Sigf.FX.smoke[1], Sigf.FX.smoke[2], s.ent, { loop = true, life = 20, offset = vector3(0, 0, 0.3), scale = 2.0 })
	end
end

local function pickTarget(wantSide)
	local list = {}
	for ped, sd in pairs(sides) do
		if sd == wantSide and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then list[#list + 1] = ped end
	end
	if #list == 0 then return nil end
	return list[math.random(#list)]
end

local function shipFire(s, wantSide, color, dmg)
	-- blue escorts sometimes strafe a raider instead
	if color == BLUE and math.random() < 0.3 then
		for _, o in ipairs(ships) do
			if o.kind == 'raider' and not o.dying and not o.dead and o.ent and (o.alpha or 255) > 200 then
				local from = s.pos + vector3(0, 0, -0.8)
				fireBolt(from, o.pos, color, 0.35, function() damageShip(o, 18, o.pos) end)
				Sigf.Sound('laser', from)
				return
			end
		end
	end
	local tgt = pickTarget(wantSide)
	if not tgt then return end
	local from = s.pos + vector3(0, 0, -0.8)
	local to = GetEntityCoords(tgt) + vector3(0, 0, 0.3)
	fireBolt(from, to, color, 0.28, function()
		if not DoesEntityExist(tgt) or IsPedDeadOrDying(tgt, true) then return end
		local p = GetEntityCoords(tgt)
		Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 0.4), { scale = 1.6 })
		local arm = GetPedArmour(tgt)
		if arm > 0 then SetPedArmour(tgt, math.max(0, arm - dmg))
		else ApplyDamageToPed(tgt, dmg, false) end
		if arm <= dmg and arm > 0 then ApplyDamageToPed(tgt, dmg - arm, false) end
	end)
	Sigf.Sound('laser', from)
end

local function nextRaiderDelay() return 9000 + math.random(0, 4000) end

local function updateShips(dt)
	local t = now()
	local c = skyCenter()
	for i = #ships, 1, -1 do
		local s = ships[i]
		if s.dead or not DoesEntityExist(s.ent) then
			table.remove(ships, i)
		else
			fillLight(s)
			if s.flash and t - s.flash < 300 then
				local c0 = s.pos + vector3(0, 0, s.cz)
				DrawMarker(28, c0.x, c0.y, c0.z, 0, 0, 0, 0, 0, 0, 6.5, 6.5, 3.6, 110, 200, 255, math.floor(50 * (1 - (t - s.flash) / 300)), false, false, 2, false, nil, nil, false)
			end
			if s.kind == 'raider' then
				if s.dying then
					s.vz = s.vz + 14.0 * dt
					s.pos = s.pos - vector3(0, 0, s.vz * dt)
					s.roll = (s.roll or 0) + 140 * dt
					s.pitch = (s.pitch or 0) + 40 * dt
					local gz = c.z
					if s.pos.z < gz + 1.5 or t - s.dyingAt > 2600 then
						Sigf.Explode(s.pos, 4, { scale = 1.6, owner = me(), shake = 1.0 })
						Sigf.Explode(s.pos + vector3(2, 1, 0), 2, { scale = 1.0 })
						addCredits(1000) raidersDown = raidersDown + 1
						Sigf.Text3D('+1000 cr', s.pos + vector3(0, 0, 3.0), 3.0, { color = { 255, 215, 60 }, scale = 1.0, rise = 1.0 })
						Sigf.Sound('credits', s.pos)
						removeShip(s)
						Sigf.After(nextRaiderDelay() / 1000, function() warpInRaider(math.random() * 6.28, s.radius, s.dir) end)
					else placeShip(s) end
				else
					s.ang = s.ang + s.spd * dt
					local bob = math.sin(t / 700 + s.ang * 3) * 0.7
					s.pos = vector3(c.x + math.cos(s.ang) * s.radius, c.y + math.sin(s.ang) * s.radius, c.z + s.alt + bob)
					local tx, ty = -math.sin(s.ang) * s.dir, math.cos(s.ang) * s.dir
					s.heading = headingOf(tx, ty)
					s.roll = -14.0 * s.dir
					s.shake = (t < (s.shakeUntil or 0)) and vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.9 or nil
					local alpha = math.min(255, math.floor((t - s.born) / 900 * 255))
					if alpha ~= s.alpha then s.alpha = alpha SetEntityAlpha(s.ent, alpha, false) end
					engineGlow(s, { 255, 70, 40 }, 2.5)
					if t >= s.nextFire and alpha > 200 then
						s.nextFire = t + 1100 + math.random(0, 700)
						shipFire(s, 'a', RED, 40)
					end
					placeShip(s)
					-- nameplate
					local ok, sx, sy = World3dToScreen2d(s.pos.x, s.pos.y, s.pos.z + 3.2)
					if ok and #(s.pos - GetFinalRenderedCamCoord()) < 120 then
						text2d(s.name, sx, sy - 0.02, 0.32, 255, 90, 80, 240)
						bar(sx, sy + 0.008, 0.07, math.max(0, s.hull / s.maxHull), 255, 150, 40)
					end
				end
			elseif s.kind == 'shuttle' then
				local ph = s.phase
				if ph == 'land' then
					local k = math.min(1.0, (t - s.phaseAt) / 5000)
					local e = 1.0 - (1.0 - k) * (1.0 - k)
					s.pos = vlerp(s.from, s.spot, e)
					s.heading = s.spotHeading
					s.pitch = (1.0 - k) * -8.0
					thrusterColumn(s, 1.0 - k * 0.5)
					DrawLightWithRange(s.pos.x, s.pos.y, s.pos.z - 2.0, 255, 170, 80, 18.0, 6.0 * (1.0 - k * 0.6))
					if k >= 1.0 then
						s.phase = 'rest' s.phaseAt = t
						if s.fx then Sigf.StopFx(s.fx) s.fx = nil end
						Sigf.Shake(0.4)
						log('Shuttle "Blue Jay" has landed at Sandy Shores Spaceport.', 'info')
					end
				elseif ph == 'rest' then
					s.pitch = 0.0
					if t - s.phaseAt > s.restMs then
						s.phase = 'lift' s.phaseAt = t
						s.fx = Sigf.Fx('core', 'ent_sht_flame', s.ent, { loop = true, life = 9, offset = vector3(0, 0, -1.2), scale = 1.6 })
						Sigf.Sound('thruster', s.pos)
						log('Shuttle "Blue Jay" taking off to escort the spaceport.', 'info')
					end
				elseif ph == 'lift' then
					local k = math.min(1.0, (t - s.phaseAt) / 4500)
					local e = k * k
					s.pos = vlerp(s.spot, vector3(c.x + 18, c.y, c.z + 10), e)
					s.pitch = k * 10.0
					thrusterColumn(s, 0.6 + k * 0.4)
					if k >= 1.0 then
						s.phase = 'orbit' s.ang = 0.0
						if s.fx then Sigf.StopFx(s.fx) s.fx = nil end
					end
				elseif ph == 'orbit' then
					s.ang = s.ang - 0.35 * dt
					local R = 11.0
					s.pos = vector3(c.x + math.cos(s.ang) * R, c.y + math.sin(s.ang) * R, c.z + 10.0 + math.sin(t / 900) * 0.6)
					s.heading = headingOf(math.sin(s.ang), -math.cos(s.ang))
					s.roll = 12.0
					s.pitch = 0.0
					engineGlow(s, { 80, 170, 255 }, 1.5)
					if t >= s.nextFire then
						s.nextFire = t + 900 + math.random(0, 500)
						shipFire(s, 'b', BLUE, 45)
					end
					local ok, sx, sy = World3dToScreen2d(s.pos.x, s.pos.y, s.pos.z + 2.6)
					if ok then text2d('SHUTTLE "BLUE JAY"', sx, sy, 0.3, 110, 190, 255, 240) end
				end
				placeShip(s)
				if ph == 'land' or ph == 'rest' then
					local ok, sx, sy = World3dToScreen2d(s.pos.x, s.pos.y, s.pos.z + 3.0)
					if ok then text2d('SHUTTLE "BLUE JAY"', sx, sy, 0.3, 110, 190, 255, 240) end
				end
			elseif s.kind == 'freighter' then
				local k = (t - s.born) / s.durMs
				if k >= 1.0 then removeShip(s)
				else
					s.pos = vlerp(s.a, s.b, k)
					s.heading = s.h
					s.roll = 0.0
					engineGlow(s, { 255, 190, 90 }, 4.0)
					placeShip(s)
					local ok, sx, sy = World3dToScreen2d(s.pos.x, s.pos.y, s.pos.z + 5.0)
					if ok then text2d('ARGOSY FREIGHTER', sx, sy, 0.34, 255, 200, 110, 240) end
				end
			end
		end
	end
end

Sigf.Frame(function(dt) updateShips(dt or GetFrameTime()) end)

-- ---------- spawners ----------
local function landShuttle()
	local c = skyCenter()
	local spot = isDemo() and GetOffsetFromEntityInWorldCoords(me(), 0.0, 20.0, 0.0) or (c + vector3(14, 6, 0))
	if not spot then return end
	spot = Sigf.Ground(spot, 0)
	local s = newShip('sigf_shuttle', 'shuttle', 'SHUTTLE', spot + vector3(0, 0, 26), { })
	if not s then return end
	s.phase, s.phaseAt = 'land', now()
	s.from, s.spot, s.spotHeading = spot + vector3(0, 0, 26), spot + vector3(0, 0, 1.0), 20.0
	s.restMs = isDemo() and 9000 or 14000
	s.nextFire = now() + 1500
	s.fx = Sigf.Fx('core', 'ent_sht_flame', s.ent, { loop = true, life = 12, offset = vector3(0, 0, -1.2), scale = 1.6 })
	Sigf.Sound('thruster', spot)
	Sigf.Text('SANDY SHORES SPACEPORT', 4, { y = 0.24, size = 54, color = '#7fd0ff' })
	log('Free Worlds Navy: "Sandy Shores Spaceport, you are cleared to land."', 'info')
	-- dust kicked up on touchdown
	Sigf.After(4.2, function() Sigf.Fx(Sigf.FX.smoke[1], Sigf.FX.smoke[2], spot, { scale = 5.0 }) end)
end

local function flyFreighter(hover)
	local c = skyCenter()
	local a, b, dur
	if hover then
		-- demo: crosses right in front of the camera, big and low
		local f = GetOffsetFromEntityInWorldCoords(me(), -32.0, 34.0, 0.0)
		a = vector3(f.x, f.y, c.z + 8.0)
		local r = GetOffsetFromEntityInWorldCoords(me(), 32.0, 34.0, 0.0)
		b = vector3(r.x, r.y, c.z + 8.0)
		dur = 40000
	else
		local ang = math.random() * 6.28
		a = c + vector3(math.cos(ang) * 60.0, math.sin(ang) * 60.0, 16)
		b = c + vector3(-math.cos(ang) * 60.0, -math.sin(ang) * 60.0, 16)
		dur = 26000
	end
	local s = newShip('sigf_freighter', 'freighter', 'ARGOSY', a, {})
	if not s then return end
	s.a, s.b, s.durMs = a, b, dur
	s.h = headingOf(b.x - a.x, b.y - a.y)
	log('Argosy freighter passing overhead, bound for the outer rim.', 'info')
end

-- ---------- hails ----------
local HAILS = {
	{ 'Pirate Raider: "Nice ship. Hand over your cargo or we open fire!"', 'bad' },
	{ 'Free Worlds Navy: "All ships, hold formation over the runway."', 'info' },
	{ 'Merchant: "Is it safe to land in Sandy Shores?" Navy: "Define safe."', 'info' },
	{ 'Hai trader: "Quick! Sell me ten tons of Industrial Goods!"', 'info' },
	{ 'Pirate Raider: "Your credits are our credits now."', 'bad' },
}
Sigf.Every(14, function()
	local h = HAILS[math.random(#HAILS)]
	log(h[1], h[2])
end)

-- ---------- HUD (drawn natively, every frame) ----------
local blips = {}
Sigf.Every(0.25, function()
	local c = isDemo() and GetEntityCoords(me()) or Sigf.Action()
	blips = {}
	for ped, sd in pairs(sides) do
		if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
			local p = GetEntityCoords(ped) - c
			blips[#blips + 1] = { p.x, p.y, sd == 'b', false }
		end
	end
	for _, sh in ipairs(ships) do
		if not sh.dead then
			local p = sh.pos - c
			blips[#blips + 1] = { p.x, p.y, sh.kind == 'raider', true }
		end
	end
end)

local function textL(str, x, y, scale, r, g, b)
	SetTextFont(4) SetTextScale(0.0, scale) SetTextColour(r, g, b, 255) SetTextOutline()
	BeginTextCommandDisplayText('STRING') AddTextComponentSubstringPlayerName(str) EndTextCommandDisplayText(x, y)
end

Sigf.Frame(function()
	-- credits panel
	DrawRect(0.095, 0.075, 0.18, 0.11, 6, 14, 28, 200)
	DrawRect(0.095, 0.0205, 0.18, 0.003, 74, 168, 232, 255)
	textL(string.format('%d CREDITS', credits), 0.015, 0.03, 0.75, 255, 210, 74)
	textL('PIRATES ' .. kills .. '   RAIDERS ' .. raidersDown, 0.015, 0.075, 0.38, 207, 233, 255)
	local pe = me()
	local sh = isDemo() and math.min(100, GetPedArmour(pe)) or 100
	local hu = isDemo() and math.max(0, math.min(100, GetEntityHealth(pe) - 100)) or 100
	DrawRect(0.095, 0.103, 0.165, 0.008, 255, 255, 255, 40)
	DrawRect(0.0125 + 0.165 * sh / 200, 0.103, 0.165 * sh / 100, 0.008, 92, 200, 255, 255)
	DrawRect(0.095, 0.113, 0.165, 0.008, 255, 255, 255, 40)
	DrawRect(0.0125 + 0.165 * hu / 200, 0.113, 0.165 * hu / 100, 0.008, 255, 154, 46, 255)
	-- radar scope, 60 m range
	local cx, cy, w, h = 0.075, 0.84, 0.115, 0.205
	DrawRect(cx, cy, w, h, 6, 14, 28, 190)
	DrawRect(cx, cy, w, 0.002, 74, 168, 232, 120)
	DrawRect(cx, cy, 0.0015, h, 74, 168, 232, 120)
	DrawRect(cx, cy - h / 2, w, 0.003, 74, 168, 232, 255)
	DrawRect(cx, cy + h / 2, w, 0.003, 74, 168, 232, 255)
	DrawRect(cx - w / 2, cy, 0.0017, h, 74, 168, 232, 255)
	DrawRect(cx + w / 2, cy, 0.0017, h, 74, 168, 232, 255)
	for _, b in ipairs(blips) do
		local bx, by = cx + b[1] / 60.0 * (w / 2), cy - b[2] / 60.0 * (h / 2)
		if math.abs(bx - cx) < w / 2 - 0.004 and math.abs(by - cy) < h / 2 - 0.006 then
			local sz = b[4] and 0.009 or 0.005
			if b[3] then DrawRect(bx, by, sz, sz * 1.78, 255, 74, 58, 255) else DrawRect(bx, by, sz, sz * 1.78, 92, 200, 255, 255) end
		end
	end
	DrawRect(cx, cy, 0.004, 0.007, 255, 255, 255, 255)
	-- message log
	local t = GetGameTimer()
	for i = #logLines, 1, -1 do
		if t - logLines[i].at > 9000 then table.remove(logLines, i) end
	end
	for i, l in ipairs(logLines) do
		local y = 0.93 - (#logLines - i) * 0.04
		local r, g, b = 207, 233, 255
		if l.kind == 'good' then r, g, b = 255, 226, 140 elseif l.kind == 'bad' then r, g, b = 255, 150, 140 end
		DrawRect(0.795, y + 0.014, 0.40, 0.034, 6, 14, 28, 200)
		DrawRect(0.595, y + 0.014, 0.003, 0.034, r, g, b, 255)
		textL(l.text, 0.6, y, 0.32, r, g, b)
	end
end)

-- ---------- start ----------
Sigf.After(1, function()
	Sigf.Battle({ a = 5, b = 5, modelA = 's_m_m_movspace_01', modelB = 's_m_m_movalien_01',
		weaponA = 'WEAPON_SPECIALCARBINE', weaponB = 'WEAPON_MICROSMG' })
	local pe = me()
	if isDemo() then SetPedArmour(pe, 100) TriggerEvent('sigf:campitch', 9.0) end
	Sigf.Text('ENDLESS SKY TAKEOVER', 4, { y = 0.1, size = 72, color = '#7fd0ff' })
	log('Welcome to Sandy Shores Spaceport. Credits: ' .. credits, 'info')
end)
ES = { landShuttle = landShuttle, flyFreighter = flyFreighter, warpInRaider = warpInRaider, ships = ships }
if not isDemo() then
	Sigf.After(3, landShuttle)
	Sigf.After(8, function() warpInRaider(0.0, 10.0, 1) end)
	Sigf.After(16, function() warpInRaider(3.1, 12.5, -1) end)
	Sigf.After(20, function() flyFreighter(false) end)
	Sigf.Every(75, function() flyFreighter(false) end)
end

