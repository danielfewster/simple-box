AddCSLuaFile()

/*	--------------------------------------------
	Coded by Daniel Fewster during April of 2019
	
	Developer Notes:
	I wrote this with the intention that someone, 
	somewhere, may or may not want this kind of 
	thing. I deeply appreciate whoever purchases 
	this and finds some use out of it. I enjoyed 
	writing this simple entity, and hope it gets 
	some use. Thank you!
	
	Contact Me:
	https://www.gmodstore.com/users/danno
*/	--------------------------------------------

ENT.PrintName 		= "Simple Box"
ENT.Author 			= "Daniel Fewster"
ENT.Information 	= "A simple box inventory that stores items dropped into it, and then vomits them back out on request."
ENT.Type			= "anim" 
ENT.Base			= "base_anim"

/*	-------------------------------------------------------------
	USER EDITABLE (feel free to change these to suit your ideals)
*/	-------------------------------------------------------------

ENT.Category 				= "Simple Box"
ENT.Model					= Model("models/props_junk/PlasticCrate01a.mdl")
ENT.Spawnable 				= true
ENT.AdminOnly 				= false
ENT.MaxItems 				= 9 -- Options are: 9, 16, 25, 36 (Or any square number)
ENT.GUIItemSpacing			= 25 -- Space between items on the menu grid
ENT.Force					= 500 -- Force applied to expelled items
ENT.ItemSize				= 125 -- Item Panel/Grid Segment Size
ENT.Correction			  	= 0 -- If the model you choose doesn't sit will with the 3D2D, you can edit it's height manually here
ENT.RenderBasedOnDistance 	= true -- Optional Optimization: doesn't render if RenderDistanceValue exceeded (player too far away)
ENT.RenderDistanceValue		= 1024 -- Determines how far the player can be before simple box doesn't render
ENT.BackgroundCol			= Color(33, 33, 33) -- Color of the background 
ENT.ItemColor				= Color(207, 216, 220) -- Color of the item panel background
ENT.ItemTextColor			= Color(33, 33, 33) -- Color of the text on the item panels
ENT.CanStoreNPCs			= true -- Block any ent with the prefix "npc_" from being stored
ENT.CanStoreProps			= true -- Block any ent with the prefix "prop_" from being stored
ENT.OwnerOnlyPhysgunPickup	= true -- Make it so only the owner can pick up their simple box

ENT.NotStorable = { -- Will block any ent listed in the table from being stored (ent class name must be exact)
	["simple_box"] = true,
	["info_player_start"] = true,
	["physgun_beam"] = true,
	["predicted_viewmodel"] = true,
	["env_rotorwash_emitter"] = true,
	["env_laserdot"] = true
}

/*	-----------------------------------------------------------
	DO NOT EDIT THE FOLLOWING UNLESS YOU KNOW WHAT YOU'RE DOING
*/	-----------------------------------------------------------

ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

DEFINE_BASECLASS(ENT.Base)

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "_Owner") -- Don't want to override Entity.SetOwner
	self:NetworkVar("Int", 0, "ItemCount")
end

if SERVER then
	util.AddNetworkString("SimpleBox.SendInventory")
	util.AddNetworkString("SimpleBox.RequestItem")
	
	net.Receive("SimpleBox.RequestItem", function(len, ply)		
		local ent = ents.GetByIndex(net.ReadUInt(32))
		
		if IsValid(ent) then
			ent:GetItem(
				net.ReadUInt(16), 
				net.ReadUInt(16)
			)
		end
	end)
	
	function ENT:Initialize()
		self:SetModel(self.Model)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self.Inventory = {entIndex = self:EntIndex()}	
		self.LastCheck = RealTime()
	end
	
	function ENT:Use(ply)
		if (self:Get_Owner() == NULL) then
			self:Set_Owner(ply)
			ply:ChatPrint("You now own this Box! Entity #" .. self:EntIndex())
			return
		end
		
		if self:Get_Owner() == ply then
			ply:SendLua("vgui.Create('SimpleBoxMenu')")
		end
	end
	
	function ENT:Think()
		if RealTime() >= self.LastCheck + 1 then
			if (self:Get_Owner() ~= NULL) then		
				local _ents = ents.FindInBox(
					self:LocalToWorld(self:OBBMins()), 
					self:LocalToWorld(self:OBBMaxs())
				)
				
				for _, ent in pairs(_ents) do
					if (not self:CannotStore(ent)) then
						self:AddItem(ent)
						break
					end
				end
			end
			self.LastCheck = RealTime()
		end
	end
	
	function ENT:AddItem(ent)
		if (not self.CanStoreProps) then
			if ent:GetClass():StartWith("prop_") then
				return
			end
		end
	
		if (not self.CanStoreNPCs) then
			if ent:GetClass():StartWith("npc_") then
				return 
			end
		end
		
		if self:IsFull() then
			return 
		end
	
		for i = 1, self.MaxItems do
			if (not self.Inventory[i]) then
				table.insert(self.Inventory, i, {
					class = ent:GetClass(),
					model = ent:GetModel()
				})
				break
			end
		end
		
		local max = math.sqrt(self.MaxItems)	
		local k = 1
		
		for i = 1, max do
			for j = 1, max do
				if self.Inventory[k] then
					self.Inventory[k].coords = {x = i, y = j}
				end
				k = k + 1
			end
		end
		
		self:SetItemCount(table.Count(self.Inventory) - 1)
		self:Sync()
		ent:Remove()
	end
	
	function ENT:GetItem(x, y)
		if self:IsEmpty() then
			return
		end
	
		local max = math.sqrt(self.MaxItems)
		local k = 1
		
		for i = 1, max do
			for j = 1, max do
				if self.Inventory[k] then
					local coords = self.Inventory[k].coords
					if coords.x == x and coords.y == y then
						local item = self.Inventory[k]
						
						local ent = ents.Create(item.class)
						ent:SetModel(item.model)
						ent:SetPos(self:LocalToWorld(self:OBBCenter()))
						ent:Spawn()
						ent:Activate()
						
						local phys = ent:GetPhysicsObject()
						if IsValid(phys) then
							local mass = phys:GetMassCenter()
							phys:ApplyForceCenter(Vector(
								(math.random(0, 1) == 0) and -self.Force or self.Force, 
								(math.random(0, 1) == 0) and -self.Force or self.Force,
								self.Force
							) * (mass == Vector() and 0.5 or mass))
						end
						
						self.Inventory[k] = nil
					end
				end
				k = k + 1
			end
		end
		
		self:SetItemCount(table.Count(self.Inventory) - 1)
		self:Sync()
		self.LastCheck = RealTime() + 5
	end

	function ENT:Sync()
		local data = util.Compress(util.TableToJSON(self.Inventory))
		net.Start("SimpleBox.SendInventory")
		net.WriteUInt(data:len(), 32)
		net.WriteData(data, data:len())
		net.Send(self:Get_Owner())
	end
	
	function ENT:CannotStore(ent)	
		return self.NotStorable[ent:GetClass()] 
			or ent:IsPlayer() 
				or false
	end
	
	function ENT:GetSize()
		return table.Count(self.Inventory)
	end
	
	function ENT:IsEmpty()
		return table.Count(self.Inventory) == 0
	end
	
	function ENT:IsFull()
		return table.Count(self.Inventory) > self.MaxItems
	end
	
	hook.Add("PhysgunPickup", "SimpleBox.PhysgunPickup", function(ply, ent)
		if ent.OwnerOnlyPhysgunPickup 
				and (ent:GetClass() == "simple_box")
					and (ent:Get_Owner() ~= NULL) then
			if ply:IsAdmin() then
				return
			end
			
			return ent:Get_Owner() == ply
		end
	end)
else	
	local inv = {}
	net.Receive("SimpleBox.SendInventory", function()
		local temp = util.JSONToTable(
			util.Decompress(
				net.ReadData(net.ReadUInt(32))
			)
		)

		inv[temp.entIndex] = temp
	end)

	local ITEM = {}
	ITEM.Size = ENT.ItemSize
	ITEM.Color = ENT.ItemColor
	ITEM.TextColor = ENT.ItemTextColor
	
	function ITEM:Init()
		self:SetSize(ITEM.Size, ITEM.Size)
		self:DockPadding(5, 5, 5, 20)
		
		self.Text = Label("", self)
		self.Text:SetFont("GModNotify")
		self.Text:AlignBottom()
		self.Text:SetColor(self.TextColor)
		
		self.Icon = vgui.Create("DModelPanel", self)
		self.Icon:SetModel("models/error.mdl")
		self.Icon:Dock(FILL)
		self.Icon:SetVisible(false)
		
		local mins, maxs = self.Icon.Entity:GetRenderBounds()
		self.Icon:SetCamPos(mins:Distance(maxs) * Vector(0.5, 0.5, 0.5))
		self.Icon:SetLookAt((maxs + mins) / 2)
	end
	
	function ITEM:Paint(w, h)
		draw.RoundedBox(20, 0, 0, w, h, self.Color)
	end
	
	function ITEM:SetText(text)
		local tbl = {
			["weapon"] = "Weapon",
			["npc"] = "NPC"
		}
		
		if tbl[text:match("%w+")] then
			local info = list.Get(tbl[text:match("%w+")])[text]
			text = info.PrintName or info.Name
		end
		
		self.Text:SetText(text)
		self.Text:SizeToContents()
		self.Text:CenterHorizontal()
	end
	
	function ITEM:SetModel(path)
		self.Icon:SetModel(path)
	end
	vgui.Register("SimpleBoxItem", ITEM)

	local MAIN = {}
	MAIN.MaxItems = ENT.MaxItems
	MAIN.Spacing = ENT.GUIItemSpacing
	MAIN.Color = ENT.BackgroundCol
	
	function MAIN:Init()
		local max = math.sqrt(self.MaxItems)
		
		self:SetSize(
			(ITEM.Size * max) + (self.Spacing * (max + 1)), 
			(ITEM.Size * max) + (self.Spacing * (max + 1))
		)
		self:MakePopup()
		self:Center()
		
		self.Close = vgui.Create("DButton", self)
		self.Close:SetFont("marlett")
		self.Close:SetText("r")
		self.Close:CenterHorizontal()
		self.Close:AlignBottom(2)
		self.Close:SetColor(Color(213, 0, 0))
		self.Close.Paint = function(self) end
		self.Close.DoClick = function()
			self:Remove()
		end

		local k = 1

		for i = 1, max do
			for j = 1, max do
				local panel = vgui.Create("SimpleBoxItem", self)
				
				local trace = LocalPlayer():GetEyeTraceNoCursor()
				local ent = trace.Entity -- Get Unique Box!
				
				if ent:GetClass() == "simple_box" then
					local item = inv[ent:EntIndex()]
					if item then item = item[k] end

					if type(item) == "table" then
						local coords = item.coords
						if coords.x == i and coords.y == j then
							panel:SetText(item.class)
							panel:SetModel(item.model)
							panel.Icon:SetVisible(true)
							panel.Icon.DoClick = function()
								net.Start("SimpleBox.RequestItem")
								net.WriteUInt(ent:EntIndex(), 32)
								net.WriteUInt(i, 16)
								net.WriteUInt(j, 16)
								net.SendToServer()
								self:Remove()
							end
						end
					end
				end
				
				panel:SetPos(
					self.Spacing + (i - 1) * (panel:GetWide() + self.Spacing), 
					self.Spacing + (j - 1) * (panel:GetTall() + self.Spacing)
				)	
					
				k = k + 1
			end
		end
	end
	
	function MAIN:Paint(w, h)
		draw.RoundedBox(35, 0, 0, w, h, self.Color)
	end
	vgui.Register("SimpleBoxMenu", MAIN)

	function ENT:Initialize()
		local mins, maxs = self:OBBMins(), self:OBBMaxs()
		self.OffSet = mins:Distance(maxs) + self.Correction
	end
	
	function ENT:Draw()
		self:DrawModel()
		
		local pos = self:GetPos()
		local ang = LocalPlayer():EyeAngles()
		
		ang.p = self:GetAngles().p
		ang:RotateAroundAxis(ang:Right(), 90)
		ang:RotateAroundAxis(ang:Up(), 270)
		
		pos:Add(Vector(0, 0, self.OffSet))

		cam.Start3D2D(pos, ang, 0.1)
			draw.RoundedBox(25, -150, 0, 300, 100, self.BackgroundCol)
			
			surface.SetFont("ScoreboardDefaultTitle")
			surface.SetTextColor(self.ItemColor)
			
			local text = (self:Get_Owner() == NULL) 
				and "No Owner" 
					or self:Get_Owner():Nick()
			local w, h = surface.GetTextSize(text)
			
			surface.SetTextPos(-(w / 2), 15)
			surface.DrawText(text)
			
			surface.SetFont("ScoreboardDefault")
			
			text = (self:GetItemCount() == 0) 
				and "Press [E] to own/use me!" 
					or string.format(
						"%d/%d Current Items", 
						self:GetItemCount(), 
						self.MaxItems
					)
			w, h = surface.GetTextSize(text)
			
			surface.SetTextPos(-(w / 2), 100 - 40)
			surface.DrawText(text)
		cam.End3D2D()
	end
	
	function ENT:Think()
		if self.RenderBasedOnDistance then
			self:SetNoDraw(not tobool(
				(LocalPlayer():GetPos() - self:GetPos()):LengthSqr() < self.RenderDistanceValue^2
			))
		end
	end
	
	function ENT:OnRemove()
		inv[self:EntIndex()] = nil
	end
end
