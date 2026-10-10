-- Demo: a shuttle lands and a freighter crosses at once, then pirates fall to blue bolts and raiders are shot down.
local function pirate(caption, killAfter)
	local e = Sigf.BringPed(17, 's_m_m_movalien_01', { weapon = 'WEAPON_MICROSMG', health = 60 })
	if not e then return end
	Sigf.LookAt(e, 1)
	Sigf.Shoot(killAfter or 3.0, e)
	Sigf.After((killAfter or 3.0) + 0.5, function() if DoesEntityExist(e) then Sigf.KillByHost(e) end end)
	if caption then Sigf.Text(caption, 4, { y = 0.85, size = 40 }) end
end

local function raiderFight(angle, radius, dir)
	local s = ES.warpInRaider(angle, radius, dir)
	if not s then return end
	Sigf.Pilot(false)
	for i = 0, 8 do
		Sigf.After(3.0 + i * 1.3, function()
			if s.dead or s.dying or not s.pos then return end
			SetGameplayCamRelativeHeading(0.0) SetGameplayCamRelativePitch(6.0, 1.0)
			local aim = s.pos + vector3(0, 0, s.cz)
			Sigf.LookAt(aim, 1.3)
			Sigf.Shoot(1.3, aim)
		end)
	end
	Sigf.After(12, function() Sigf.Pilot(true) end)
end

Sigf.Demo(0.1, function()
	ES.landShuttle()
	ES.flyFreighter(true)
end)
Sigf.Demo(0.5, function() Sigf.Text('GTA V x ENDLESS SKY', 4, { y = 0.1, size = 72, color = '#7fd0ff' }) end)
Sigf.Demo(6, function() pirate('Alien pirates have shields: shoot them down for credits', 3.5) end)
Sigf.Demo(11, function()
	Sigf.Text('A pirate raider jumps in: shoot it down!', 4, { y = 0.85, size = 40 })
	raiderFight(1.6, 9.0, 1)
end)
Sigf.Demo(27, function() pirate('Escort shuttle lasers help out', 3.5) end)
Sigf.Demo(33, function()
	Sigf.Text('Second raider incoming!', 3, { y = 0.85, size = 40 })
	raiderFight(0.2, 9.0, -1)
end)
Sigf.Demo(50, function() pirate('Every pirate pays a bounty in credits', 3.0) end)
Sigf.Demo(56, function()
	Sigf.Text('Third raider: the biggest explosion yet', 3, { y = 0.85, size = 40 })
	raiderFight(2.5, 9.0, 1)
end)
