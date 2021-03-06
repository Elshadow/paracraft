--[[
Title: Code Block Entity
Author(s): LiXizhi
Date: 2018/5/16
Desc: Code block 
use the lib:
------------------------------------------------------------
NPL.load("(gl)script/apps/Aries/Creator/Game/Entity/EntityCode.lua");
local EntityCode = commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityCode")
-------------------------------------------------------
]]
NPL.load("(gl)script/apps/Aries/Creator/Game/Code/CodeBlock.lua");
local CodeBlock = commonlib.gettable("MyCompany.Aries.Game.Code.CodeBlock");
local Direction = commonlib.gettable("MyCompany.Aries.Game.Common.Direction")
local BlockEngine = commonlib.gettable("MyCompany.Aries.Game.BlockEngine")
local block_types = commonlib.gettable("MyCompany.Aries.Game.block_types")
local names = commonlib.gettable("MyCompany.Aries.Game.block_types.names")
local GameLogic = commonlib.gettable("MyCompany.Aries.Game.GameLogic")
local EntityManager = commonlib.gettable("MyCompany.Aries.Game.EntityManager");
local Files = commonlib.gettable("MyCompany.Aries.Game.Common.Files");

local Entity = commonlib.inherit(commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityBlockBase"), commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityCode"));

Entity:Property({"languageConfigFile", "", "GetLanguageConfigFile", "SetLanguageConfigFile"})
Entity:Signal("beforeRemoved")
Entity:Signal("editModeChanged")

-- class name
Entity.class_name = "EntityCode";
EntityManager.RegisterEntityClass(Entity.class_name, Entity);
Entity.is_persistent = true;
-- always serialize to 512*512 regional entity file
Entity.is_regional = true;

-- we will only allow this number of connected code block to share the same movie entity
local maxConnectedCodeBlockCount = 255;

function Entity:ctor()
end

function Entity:Destroy()
	self:OnRemoved();
	Entity._super.Destroy(self);
end

function Entity:OnRemoved()
	self:beforeRemoved();
	if(self.codeBlock) then
		self.codeBlock:Destroy();
		self.codeBlock = nil;
	end
end

function Entity:OnNeighborChanged(x,y,z, from_block_id)
	if(not GameLogic.isRemote) then
		self:ScheduleRefresh(x,y,z);
	end
end


function Entity:SetBlocklyXMLCode(blockly_xmlcode)
	self.blockly_xmlcode = blockly_xmlcode;
end

function Entity:GetBlocklyXMLCode()
	return self.blockly_xmlcode;
end


function Entity:SetBlocklyNPLCode(blockly_nplcode)
	self.blockly_nplcode = blockly_nplcode;
	self:SetCommand(blockly_nplcode);
end

function Entity:GetBlocklyNPLCode()
	return self.blockly_nplcode;
end

function Entity:SetNPLCode(nplcode)
	self.nplcode = nplcode;
	self:SetCommand(nplcode);
end

function Entity:GetNPLCode()
	return self.nplcode or self:GetCommand();
end

function Entity:TextToXmlInnerNode(text)
	if(text and commonlib.Encoding.HasXMLEscapeChar(text)) then
		return {name="![CDATA[", [1] = text};
	else
		return text;
	end
end
	
function Entity:IsBlocklyEditMode()
	return self.isBlocklyEditMode;
end

function Entity:SetBlocklyEditMode(bEnabled)
	if(self.isBlocklyEditMode~=bEnabled) then
		self.isBlocklyEditMode = bEnabled;
		if(bEnabled)  then
			self:SetCommand(self:GetBlocklyNPLCode());
		else
			self:SetCommand(self:GetNPLCode());
		end
		self:editModeChanged();
	end
end

function Entity:SaveToXMLNode(node, bSort)
	node = Entity._super.SaveToXMLNode(self, node, bSort);
	node.attr.allowGameModeEdit = self:IsAllowGameModeEdit();
	node.attr.isPowered = self.isPowered;
	node.attr.isBlocklyEditMode = self:IsBlocklyEditMode();
	if(self:GetLanguageConfigFile()~="") then
		node.attr.languageConfigFile = self:GetLanguageConfigFile();
	end
	
	if(self:GetBlocklyXMLCode() and self:GetBlocklyXMLCode()~="") then
		local blocklyNode = {name="blockly", };
		node[#node+1] = blocklyNode;
		blocklyNode[#blocklyNode+1] = {name="xmlcode", self:TextToXmlInnerNode(self:GetBlocklyXMLCode())}
		blocklyNode[#blocklyNode+1] = {name="nplcode", self:TextToXmlInnerNode(self:GetBlocklyNPLCode()) }
		if(self:GetNPLCode()~=self:GetBlocklyNPLCode()) then
			blocklyNode[#blocklyNode+1] = {name="code", self:TextToXmlInnerNode(self:GetNPLCode())}
		end
	end
	if(self.includedFiles) then
		local includedFilesNode = {name="includedFiles", };
		node[#node+1] = includedFilesNode;
		for i, name in ipairs(self.includedFiles) do
			includedFilesNode[i] = {name="filename", name}
		end
	end
	return node;
end

function Entity:LoadFromXMLNode(node)
	Entity._super.LoadFromXMLNode(self, node);
	self:SetAllowGameModeEdit(node.attr.allowGameModeEdit == "true" or node.attr.allowGameModeEdit == true);
	self.isBlocklyEditMode = (node.attr.isBlocklyEditMode == "true" or node.attr.isBlocklyEditMode == true);
	self.languageConfigFile = node.attr.languageConfigFile;

	local isPowered = (node.attr.isPowered == "true" or node.attr.isPowered == true);
	if(isPowered) then
		self:ScheduleRefresh();
	end
	for i=1, #node do
		if(node[i].name == "blockly") then
			for j=1, #(node[i]) do
				local sub_node = node[i][j];
				local code = sub_node[1]
				if(code) then
					if(type(code) == "table" and type(code[1]) == "string") then
						-- just in case cmd.name == "![CDATA["
						code = code[1];
					end
				end
				if(type(code) == "string") then
					if(sub_node.name == "xmlcode") then
						self:SetBlocklyXMLCode(code);
					elseif(sub_node.name == "nplcode") then
						self:SetBlocklyNPLCode(code);
					elseif(sub_node.name == "code") then
						self:SetNPLCode(code);
					end
				end
			end
		elseif(node[i].name == "includedFiles") then
			self.includedFiles = {};
			for j=1, #(node[i]) do
				local sub_node = node[i][j];
				local filename = sub_node[1]
				self.includedFiles[j] = filename;
			end
		end
	end
	if(not self.isBlocklyEditMode and not self.nplcode) then
		self.nplcode = self:GetCommand();
	end
	if(self.isBlocklyEditMode) then
		self:SetCommand(self:GetBlocklyNPLCode());
	else
		self:SetCommand(self:GetNPLCode());
	end
end

function Entity:ScheduleRefresh(x,y,z)
	if(not x) then
		x,y,z = self:GetBlockPos();
	end
	GameLogic.GetSim():ScheduleBlockUpdate(x, y, z, self:GetBlockId(), 1);
end

-- Ticks the block if it's been scheduled
function Entity:updateTick(x,y,z)
	local isPowered = BlockEngine:GetBlockData(x,y,z) > 0;
	self:SetPowered(isPowered);	
end

function Entity:IsPowered()
	return self.isPowered;
end

-- turn code on and off
function Entity:SetPowered(isPowered)
	if(self.isPowered and not isPowered) then
		self.isPowered = isPowered;
		local codeBlock = self:GetCodeBlock()
		if(codeBlock and codeBlock:IsLoaded()) then
			self:Stop();
		end
	elseif(not self.isPowered and isPowered) then
		self.isPowered = isPowered;
		local codeBlock = self:GetCodeBlock(true)
		if(codeBlock and not codeBlock:IsLoaded()) then
			self:Restart();
		end
	end
end

function Entity:Refresh()
	local codeBlock = self:GetCodeBlock()
	if(codeBlock) then
		if(self.isPowered and not codeBlock:IsLoaded()) then
			self:Restart();
		elseif(not self.isPowered and codeBlock:IsLoaded()) then
			self:Stop();
		end
	end
end

-- only search in 4 horizontal directions for a maximum distance of 16
-- find nearby movie entity, multiple code block next to each other can share the same movie block.
function Entity:FindNearByMovieEntity()
	local movieEntity = self:GetNearByMovieEntity();
	if(not movieEntity) then
		local cx, cy, cz = self.bx, self.by, self.bz;
		local id = self:GetBlockId();
		local blocks;
		local totalCodeBlockCount = 0;
		for side = 0, 3 do
			local dx, dy, dz = Direction.GetOffsetBySide(side);
			local x,y,z = cx+dx, cy+dy, cz+dz;
			local blockTemplate = BlockEngine:GetBlock(x,y,z);
			if(blockTemplate and blockTemplate.id == id) then
				local codeEntity = BlockEngine:GetBlockEntity(x,y,z);
				if(codeEntity) then
					local idx = BlockEngine:GetSparseIndex(x,y,z);
					blocks = blocks or {};
					blocks[#blocks+1] = idx;
					totalCodeBlockCount = totalCodeBlockCount + 1;
				end
			end
		end
		if(blocks) then
			local entity_map = {};
			entity_map[BlockEngine:GetSparseIndex(cx,cy,cz)] = true;
			movieEntity = self:FindNearByMovieEntityImp(blocks, 1, entity_map, totalCodeBlockCount);
		end
	end
	return movieEntity;
end

-- return movieEntity, distance
function Entity:FindNearByMovieEntityImp(blocks, distance, entity_map, totalCodeBlockCount)
	local id = self:GetBlockId();
	local new_blocks;
	for _, idx in ipairs(blocks) do
		local cx, cy, cz = BlockEngine:FromSparseIndex(idx);
		local movieEntity = self:GetNearByMovieEntity(cx, cy, cz);
		if(movieEntity) then
			return movieEntity, distance;
		end
		if(distance < 16) then
			for side = 0, 3 do
				local dx, dy, dz = Direction.GetOffsetBySide(side);
				local x,y,z = cx+dx, cy+dy, cz+dz;

				local blockTemplate = BlockEngine:GetBlock(x,y,z);
				if(blockTemplate and blockTemplate.id == id) then
					local idx = BlockEngine:GetSparseIndex(x,y,z);
					if(not entity_map[idx] and totalCodeBlockCount<maxConnectedCodeBlockCount) then
						entity_map[idx] = true;
						new_blocks = new_blocks or {};
						new_blocks[#new_blocks+1] = idx;
						totalCodeBlockCount = totalCodeBlockCount + 1;
					end
				end
			end
		end
	end
	if(new_blocks) then
		return self:FindNearByMovieEntityImp(new_blocks, distance+1, entity_map, totalCodeBlockCount);
	end
end

-- only search in 4 horizontal directions
function Entity:GetNearByMovieEntity(cx, cy, cz)
	cx, cy, cz = cx or self.bx, cy or self.by, cz or self.bz;
	for side = 0, 3 do
		local dx, dy, dz = Direction.GetOffsetBySide(side);
		local x,y,z = cx+dx, cy+dy, cz+dz;
		local blockTemplate = BlockEngine:GetBlock(x,y,z);
		if(blockTemplate and blockTemplate.id == names.MovieClip) then
			local movieEntity = BlockEngine:GetBlockEntity(x,y,z);
			if(movieEntity) then
				return movieEntity;
			end
		end
	end
end

function Entity:GetCodeBlock(bCreateIfNotExist)
	if(not self.codeBlock and bCreateIfNotExist) then
		self.codeBlock = CodeBlock:new():Init(self);
	end
	return self.codeBlock;
end

function Entity:GetFilename()
	return self:GetDisplayName();
end

-- the title text to display (can be mcml)
function Entity:GetCommandTitle()
	return L"输入代码"
end

function Entity:HasBag()
	return false;
end

function Entity:SetAllowGameModeEdit(bAllow)
	self.allowGameModeEdit = bAllow;
end

function Entity:IsAllowGameModeEdit()
	return self.allowGameModeEdit;
end

-- called when the user clicks on the block
-- @return: return true if it is an action block and processed . 
function Entity:OnClick(x, y, z, mouse_button, entity, side)
	if(GameLogic.isRemote) then
		if(mouse_button == "left") then
			-- GameLogic.GetPlayer():AddToSendQueue(GameLogic.Packets.PacketClickEntity:new():Init(entity or GameLogic.GetPlayer(), self, mouse_button, x, y, z));
		end
		return true;
	else
		if(self:IsAllowGameModeEdit()) then
			self:OpenEditor("entity", entity);
		elseif(mouse_button=="right" and GameLogic.GameMode:CanEditBlock()) then
			self:OpenEditor("entity", entity);
		end
	end
	return true;
end

function Entity:OpenEditor(editor_name, entity)
	NPL.load("(gl)script/apps/Aries/Creator/Game/Code/CodeBlockWindow.lua");
	local CodeBlockWindow = commonlib.gettable("MyCompany.Aries.Game.Code.CodeBlockWindow");
    CodeBlockWindow.Show(true);
	CodeBlockWindow.SetCodeEntity(self);
end

-- get all nearby code entities that should be started as a group, include current one.
-- @return {idx to true} map
function Entity:GetAllNearbyCodeEntities()
	local id = self:GetBlockId();
	local x, y, z = self.bx, self.by, self.bz;
	local blockTemplate = BlockEngine:GetBlock(x,y,z);
	if(blockTemplate and blockTemplate.id == id) then
		local blocks = {};
		local entity_map = {};
		local idx = BlockEngine:GetSparseIndex(x,y,z);
		blocks[#blocks+1] = idx;
		entity_map[idx] = true;
		local all_blocks = {idx};
		return self:GetAllNearbyCodeEntitiesImp(blocks, entity_map, all_blocks, 1, 1)
	end
end

-- get all nearby code entities that should be started as a group, include current one.
-- @return array of idx from close to far
function Entity:GetAllNearbyCodeEntitiesImp(blocks, entity_map, all_blocks, distance, totalCodeBlockCount)
	local id = self:GetBlockId();
	if(distance>=16) then
		return entity_map;
	end
	local new_blocks;
	for _, idx in pairs(blocks) do
		local cx, cy, cz = BlockEngine:FromSparseIndex(idx);
		for side = 0, 3 do
			local dx, dy, dz = Direction.GetOffsetBySide(side);
			local x,y,z = cx+dx, cy+dy, cz+dz;

			local blockTemplate = BlockEngine:GetBlock(x,y,z);
			if(blockTemplate and blockTemplate.id == id) then
				local idx = BlockEngine:GetSparseIndex(x,y,z);
				if(not entity_map[idx] and totalCodeBlockCount<maxConnectedCodeBlockCount) then
					new_blocks = new_blocks or {};
					new_blocks[#new_blocks+1] = idx;
					entity_map[idx] = true;
					all_blocks[#all_blocks+1] = idx;
					totalCodeBlockCount = totalCodeBlockCount + 1;
				end
			end
		end
	end
	if(new_blocks) then
		self:GetAllNearbyCodeEntitiesImp(new_blocks, entity_map, all_blocks, distance+1, totalCodeBlockCount);
	end
	return all_blocks;
end

-- breadth first traversing.
-- @param callbackFunc: function if return true, it will stop iteration.
function Entity:ForEachNearbyCodeEntity(callbackFunc)
	local blocks = self:GetAllNearbyCodeEntities()
	if(blocks) then
		local id = self:GetBlockId();
		for _, idx in ipairs(blocks) do
			local x, y, z = BlockEngine:FromSparseIndex(idx);
			local codeEntity = BlockEngine:GetBlockEntity(x,y,z);
			if(codeEntity and codeEntity:GetBlockId() == id) then
				if(callbackFunc(codeEntity)) then
					break;
				end
			end
		end
	end
end

-- run regardless of whether it is powered. 
function Entity:Restart()
	self:Stop();

	local blocks = self:GetAllNearbyCodeEntities()
	if(blocks) then
		function restartCodeEntity_(codeEntity)
			local codeBlock = codeEntity:GetCodeBlock(true)
			if(codeBlock) then
				codeBlock:Run();
			end
		end
		local id = self:GetBlockId();
		local blocks2;
		for _, idx in ipairs(blocks) do
			local x, y, z = BlockEngine:FromSparseIndex(idx);
			local codeEntity = BlockEngine:GetBlockEntity(x,y,z);
			if(codeEntity and codeEntity:GetBlockId() == id) then
				-- blocks that are directly connected to a movie entity are restarted first.
				if(codeEntity:GetNearByMovieEntity(x, y, z)) then
					restartCodeEntity_(codeEntity);
				else
					blocks2 = blocks2 or {};
					blocks2[#blocks2+1] = idx;
				end
			end
		end
		if(blocks2) then
			for _, idx in ipairs(blocks2) do
				local x, y, z = BlockEngine:FromSparseIndex(idx);
				local codeEntity = BlockEngine:GetBlockEntity(x,y,z);
				if(codeEntity and codeEntity:GetBlockId() == id) then
					restartCodeEntity_(codeEntity);
				end
			end
		end
	end
end

-- stop regardless of whether it is powered. 
function Entity:Stop()
	self:ForEachNearbyCodeEntity(function(codeEntity)
		local codeBlock = codeEntity:GetCodeBlock()
		if(codeBlock) then
			codeBlock:Stop();
		end
	end);
end

function Entity:AutoCreateMovieEntity()
	local movieEntity = self:FindNearByMovieEntity();
	if(not movieEntity) then
		local cx, cy, cz = self:GetBlockPos();
		for side = 3, 0, -1 do
			local dx, dy, dz = Direction.GetOffsetBySide(side);
			local x,y,z = cx+dx, cy+dy, cz+dz;
			local blockTemplate = BlockEngine:GetBlock(x,y,z);
			if(not blockTemplate) then
				BlockEngine:SetBlock(x,y,z, names.MovieClip, 0, 3, nil);
				local movieEntity = BlockEngine:GetBlockEntity(x,y,z);
				if(movieEntity) then
					movieEntity:CreateNPC();
				end
				return true;
			end
		end
	end
end

-- get the last electric output result. 
function Entity:GetLastOutput()
	return self.last_output;
end

-- get output from result. if result is a value larger than 1. 
-- value larger than 15 is clipped. 
-- @return nil or a value between [1,15]
function Entity:ComputeElectricOutput(last_result)
	if(type(last_result) == "number" and last_result>=1) then
		return math.min(15, math.floor(last_result));
	end
end

-- set the last result. 
function Entity:SetLastCommandResult(last_result)
	local output = self:ComputeElectricOutput(last_result)
	if(self.last_output ~= output) then
		self.last_output = output;
		local x, y, z = self:GetBlockPos();
		BlockEngine:NotifyNeighborBlocksChange(x, y, z, BlockEngine:GetBlockId(x, y, z));
	end
end

function Entity:GetLanguageConfigFile()
	return self.languageConfigFile or "";
end

function Entity:SetLanguageConfigFile(filename)
	if(self:GetLanguageConfigFile() ~= filename) then
		self.languageConfigFile = filename;
		if(filename == "") then
			-- default NPL code block 
		elseif(filename == "npl_cad") then
			-- NPL cad v1
		else
			-- custom user defined under world directory
			filename = Files.GetWorldFilePath(filename)
			if(filename) then
				-- TODO
			end
		end
	end
end

function Entity:ClearIncludedFiles()
	self.includedFiles = nil;
end

function Entity:AddIncludedFile(filename)
	self.includedFiles = self.includedFiles or {};
	for _, name in ipairs(self.includedFiles) do
		if(name == filename) then
			return
		end
	end
	self.includedFiles[#(self.includedFiles)+1] = filename;
end

function Entity:GetAllIncludedFiles()
	return self.includedFiles;
end