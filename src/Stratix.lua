-- Stratix.lua
--!native
--!optimize 2
--!strict

local Identity = "HSM"
local module   = {}
module.__index = module
module.__type  = Identity

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages          = ReplicatedStorage.Shared.Modules.Utilities
local Signal            = require(Packages.Signal)

local DEFAULT_REGION = "Default"

type GuardFn  = (hsm: SelfRef) -> boolean
type SelfRef  = any
type EntryFn  = (hsm: SelfRef) -> ()
type ExitFn   = (hsm: SelfRef) -> ()
type ActionFn = (hsm: SelfRef) -> ()

export type StateConfig = {
	OnEntry : EntryFn?,
	OnExit  : ExitFn?,
	History : ("Shallow" | "Deep")?,
	Initial : string?,
}

export type TransitionConfig = {
	Guard    : GuardFn?,
	Action   : ActionFn?,
	Internal : boolean?,
}

type StateNode = {
	Name        : string,
	Parent      : StateNode?,
	Children    : { [string]: StateNode },
	Transitions : { [string]: { TransitionNode } },
	Config      : StateConfig,
	History     : StateNode?,
	RegionName  : string,
	IsRoot      : boolean,
}

type TransitionNode = {
	Target   : StateNode,
	Guard    : GuardFn?,
	Action   : ActionFn?,
	Internal : boolean?,
}

type RegionData = {
	Name    : string,
	Root    : StateNode,
	Active  : StateNode?,
	Initial : string?,
}

export type HSM = typeof(setmetatable(
	{} :: {
		Signals: {
			OnStateChanged : any,
			OnTransition   : any,
		},
		_states      : { [string]: StateNode },
		_regions     : { [string]: RegionData },
		_regionOrder : { string },
		_started     : boolean,
		_destroyed   : boolean,
		_processing  : boolean,
		_queue       : { string },
	},
	{} :: { __index: typeof(module) }
	))

-- ─── Private Helpers ─────────────────────────────────────────────────────────

local function getAncestors(node: StateNode): { StateNode }
	local chain: { StateNode } = {}
	local cursor: StateNode?   = node
	while cursor do
		table.insert(chain, cursor)
		cursor = cursor.Parent
	end
	return chain
end

local function getLCA(a: StateNode, b: StateNode): StateNode?
	local visited: { [StateNode]: boolean } = {}
	local cursor: StateNode? = a
	while cursor do
		visited[cursor] = true
		cursor = cursor.Parent
	end
	cursor = b
	while cursor do
		if visited[cursor] then return cursor end
		cursor = cursor.Parent
	end
	return nil
end

local function resolveInitial(node: StateNode): StateNode
	if next(node.Children) == nil then return node end

	if node.Config.History == "Shallow" and node.History then
		return resolveInitial(node.History)
	end

	if node.Config.History == "Deep" and node.History then
		local cursor: StateNode = node.History
		while cursor.History do
			cursor = cursor.History
		end
		return resolveInitial(cursor)
	end

	if node.Config.Initial then
		local child = node.Children[node.Config.Initial]
		if child then
			return resolveInitial(child)
		end
		warn(string.format(
			"State '%s' declared Initial '%s' but that child does not exist; using first child.",
			node.Name, node.Config.Initial
			))
	end

	for _, child in node.Children do
		return resolveInitial(child)
	end

	return node
end

local function recordHistory(leaf: StateNode, boundary: StateNode?)
	local path: { StateNode } = {}
	local walker: StateNode? = leaf
	while walker and walker ~= boundary do
		table.insert(path, walker)
		walker = walker.Parent
	end

	local inDeepZone = false
	for i = #path, 1, -1 do
		local node   = path[i]
		local parent = node.Parent
		if not parent or parent.IsRoot then continue end

		local mode = parent.Config.History

		if mode == "Deep" then
			inDeepZone = true
		end

		if mode == "Shallow" or mode == "Deep" or inDeepZone then
			parent.History = node
		end
	end
end

local function makeRoot(regionName: string): StateNode
	return {
		Name        = "__ROOT__[" .. regionName .. "]",
		Parent      = nil,
		Children    = {},
		Transitions = {},
		Config      = {},
		History     = nil,
		RegionName  = regionName,
		IsRoot      = true,
	}
end

local function ensureDefaultRegion(self: HSM)
	if self._regions[DEFAULT_REGION] then return end

	local root = makeRoot(DEFAULT_REGION)
	self._states[root.Name] = root
	self._regions[DEFAULT_REGION] = {
		Name    = DEFAULT_REGION,
		Root    = root,
		Active  = nil,
		Initial = nil,
	}
	table.insert(self._regionOrder, DEFAULT_REGION)
end

local function doTransition(
	self    : HSM,
	region  : RegionData,
	current : StateNode,
	handler : TransitionNode,
	event   : string
)
	local prevName   = current.Name
	local regionName = region.Name

	if handler.Internal then
		if handler.Action then handler.Action(self) end
		self.Signals.OnTransition:Fire(prevName, event, prevName, regionName)
		return
	end

	local target = resolveInitial(handler.Target)
	local lca    = getLCA(current, target)

	recordHistory(current, lca)

	local exitPath: { StateNode } = {}
	local walker: StateNode? = current
	while walker and walker ~= lca do
		if not walker.IsRoot and walker.Config.OnExit then
			table.insert(exitPath, walker)
		end
		walker = walker.Parent
	end

	if handler.Action then handler.Action(self) end

	local entryPath: { StateNode } = {}
	walker = target
	while walker and walker ~= lca do
		table.insert(entryPath, 1, walker)
		walker = walker.Parent
	end

	region.Active = target

	for _, node in exitPath do
		node.Config.OnExit(self)
	end

	for _, node in entryPath do
		if not node.IsRoot and node.Config.OnEntry then
			node.Config.OnEntry(self)
		end
	end

	self.Signals.OnTransition:Fire(prevName, event, target.Name, regionName)
	self.Signals.OnStateChanged:Fire(prevName, target.Name, regionName)
end

-- ─── Constructor ─────────────────────────────────────────────────────────────

function module.new(): HSM
	local self: HSM = setmetatable({} :: any, { __index = module })

	self._states      = {}
	self._regions     = {}
	self._regionOrder = {}
	self._started     = false
	self._destroyed   = false
	self._processing  = false
	self._queue       = {}

	self.Signals = {
		OnStateChanged = Signal.new(),
		OnTransition   = Signal.new(),
	}

	return self
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function module.AddRegion(self: HSM, name: string, initialState: string?): ()
	assert(not self._regions[name], string.format("Duplicate region name: '%s'", name))

	local root = makeRoot(name)
	self._states[root.Name] = root
	self._regions[name] = {
		Name    = name,
		Root    = root,
		Active  = nil,
		Initial = initialState,
	}
	table.insert(self._regionOrder, name)

	-- Intentionally does NOT auto-boot when already started.
	-- If the HSM is running, the caller must register all states/transitions
	-- for this region first, then call :StartRegion(name) explicitly.
end

function module.AddState(
	self       : HSM,
	name       : string,
	parentName : string?,
	config     : StateConfig?,
	regionName : string?
): string
	assert(not self._states[name], string.format("Duplicate state name: '%s'", name))

	local resolvedRegion: string

	if parentName then
		local parent = self._states[parentName]
		assert(parent, string.format(
			"AddState: parent '%s' not found. Register parents before children.",
			parentName
			))
		resolvedRegion = parent.RegionName
	elseif regionName then
		resolvedRegion = regionName
	else
		ensureDefaultRegion(self)
		resolvedRegion = DEFAULT_REGION
	end

	local region = self._regions[resolvedRegion]
	assert(region, string.format(
		"AddState: region '%s' not found. Call AddRegion before AddState.",
		resolvedRegion
		))

	local node: StateNode = {
		Name        = name,
		Parent      = nil,
		Children    = {},
		Transitions = {},
		Config      = config or {},
		History     = nil,
		RegionName  = resolvedRegion,
		IsRoot      = false,
	}

	if parentName then
		local parent = self._states[parentName]
		node.Parent           = parent
		parent.Children[name] = node
	else
		node.Parent                = region.Root
		region.Root.Children[name] = node
	end

	self._states[name] = node

	return name
end

function module.Extend(self: HSM, builderFn: (hsm: HSM) -> ())
	builderFn(self)
end

function module.ReplaceTransitionGuard(self: HSM, fromName: string, event: string, index: number, newGuard: GuardFn)
	local from = self._states[fromName]
	assert(from, string.format(
		"ReplaceTransitionGuard: unknown state '%s'.", fromName
		))

	local transitions = from.Transitions[event]
	assert(transitions, string.format(
		"ReplaceTransitionGuard: no transitions found for event '%s' on state '%s'.",
		event, fromName
		))
	assert(transitions[index], string.format(
		"ReplaceTransitionGuard: no transition at index %d for event '%s' on state '%s'.",
		index, event, fromName
		))

	transitions[index].Guard = newGuard
end

function module.AddTransition(
	self     : HSM,
	fromName : string,
	event    : string,
	toName   : string,
	config   : TransitionConfig?
): ()
	local from = self._states[fromName]
	local to   = self._states[toName]
	assert(from, string.format("AddTransition: unknown source state '%s'",      fromName))
	assert(to,   string.format("AddTransition: unknown destination state '%s'", toName))
	assert(
		from.RegionName == to.RegionName,
		string.format(
			"AddTransition: '%s' (region '%s') and '%s' (region '%s') are in different regions.",
			fromName, from.RegionName, toName, to.RegionName
		)
	)

	if not from.Transitions[event] then
		from.Transitions[event] = {}
	end
	table.insert(from.Transitions[event], {
		Target   = to,
		Guard    = config and config.Guard    or nil,
		Action   = config and config.Action   or nil,
		Internal = config and config.Internal or nil,
	})
end

-- ─── Internal: region boot ───────────────────────────────────────────────────

--[[
	Boots a single region. Called by Start (for all regions) and by
	StartRegion (for regions added after the HSM is already running).
]]
function module._BootRegion(self: HSM, regionName: string, initialState: string?)
	local region   = self._regions[regionName]
	local override = initialState or region.Initial

	local seed: StateNode
	if override then
		local found = self._states[override]
		assert(found, string.format(
			"_BootRegion: unknown initial state '%s' for region '%s'.",
			override, regionName
			))
		assert(found.RegionName == regionName, string.format(
			"_BootRegion: initial state '%s' belongs to region '%s', not '%s'.",
			override, found.RegionName, regionName
			))
		seed = found
	else
		local topCount = 0
		for _ in region.Root.Children do topCount += 1 end
		if topCount > 1 then
			warn(string.format(
				"_BootRegion: no initialState for region '%s' and multiple top-level states exist. " ..
					"Resolution is non-deterministic.",
				regionName
				))
		end
		seed = region.Root
	end

	local target = resolveInitial(seed)
	local path   = getAncestors(target)

	region.Active = target

	for i = #path, 1, -1 do
		local node = path[i]
		if node.IsRoot then continue end
		if node.Config.OnEntry then
			node.Config.OnEntry(self)
		end
	end

	self.Signals.OnStateChanged:Fire(nil, target.Name, regionName)
end

--[[
	Boots a region that was added after :Start() was called.
	Must be called AFTER all states and transitions for the region
	have been registered via AddState / AddTransition.
]]
function module.StartRegion(self: HSM, regionName: string, initialState: string?)
	assert(self._started,   "HSM must be started before calling StartRegion.")
	assert(not self._destroyed, "HSM has been destroyed.")

	local region = self._regions[regionName]
	assert(region, string.format(
		"StartRegion: unknown region '%s'. Call AddRegion first.",
		regionName
		))
	assert(not region.Active, string.format(
		"StartRegion: region '%s' is already running.",
		regionName
		))

	self:_BootRegion(regionName, initialState)
end

function module.Start(self: HSM, initialStates: ({ [string]: string } | string)?): ()
	assert(not self._started,          "HSM is already started.")
	assert(next(self._regions) ~= nil, "No regions or states have been registered.")

	self._started = true

	local perRegion: { [string]: string } = {}
	if type(initialStates) == "string" then
		if #self._regionOrder == 1 then
			perRegion[self._regionOrder[1]] = initialStates
		else
			warn("Start: plain string initialState provided but multiple regions exist.")
		end
	elseif type(initialStates) == "table" then
		perRegion = initialStates
	end

	for _, regionName in self._regionOrder do
		self:_BootRegion(regionName, perRegion[regionName])
	end
end

function module.Dispatch(self: HSM, event: string): boolean
	assert(self._started,       "HSM has not been started; call :Start() first.")
	assert(not self._destroyed, "HSM has been destroyed.")

	if self._processing then
		table.insert(self._queue, event)
		return false
	end

	self._processing = true
	local anyHandled = false

	for _, regionName in self._regionOrder do
		local region  = self._regions[regionName]
		local current = region.Active
		if not current then continue end

		local handler: TransitionNode? = nil
		local cursor:  StateNode?      = current

		while cursor and not cursor.IsRoot do
			local candidates = cursor.Transitions[event]
			if candidates then
				for _, candidate in candidates do
					if not candidate.Guard or candidate.Guard(self) then
						handler = candidate
						break
					end
				end
			end
			if handler then break end
			cursor = cursor.Parent
		end

		if handler then
			doTransition(self, region, current, handler, event)
			anyHandled = true
		end
	end

	self._processing = false
	self:_DrainQueue()
	return anyHandled
end

function module._DrainQueue(self: HSM)
	while #self._queue > 0 and not self._destroyed do
		local nextEvent = table.remove(self._queue, 1)
		self:Dispatch(nextEvent)
	end
	if self._destroyed then
		table.clear(self._queue)
	end
end

function module.GetActive(self: HSM): { [string]: string }
	local result: { [string]: string } = {}
	for regionName, region in self._regions do
		if region.Active then
			result[regionName] = region.Active.Name
		end
	end
	return result
end

function module.GetActiveIn(self: HSM, regionName: string): string?
	local region = self._regions[regionName]
	if not region or not region.Active then return nil end
	return region.Active.Name
end

function module.IsActive(self: HSM, name: string): boolean
	for _, region in self._regions do
		local cursor: StateNode? = region.Active
		while cursor do
			if cursor.Name == name then return true end
			cursor = cursor.Parent
		end
	end
	return false
end

function module.IsActiveIn(self: HSM, name: string, regionName: string): boolean
	local region = self._regions[regionName]
	if not region then return false end
	local cursor: StateNode? = region.Active
	while cursor do
		if cursor.Name == name then return true end
		cursor = cursor.Parent
	end
	return false
end

function module.GetStateNames(self: HSM, regionName: string?): { string }
	local names: { string } = {}
	for name, node in self._states do
		if node.IsRoot then continue end
		if regionName and node.RegionName ~= regionName then continue end
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function module.Destroy(self: HSM)
	if self._destroyed then return end
	self._destroyed = true

	for _, regionName in self._regionOrder do
		local region = self._regions[regionName]
		if region.Active then
			local walker: StateNode? = region.Active
			while walker and not walker.IsRoot do
				if walker.Config.OnExit then
					walker.Config.OnExit(self)
				end
				walker = walker.Parent
			end
		end
	end

	for _, signal in self.Signals do
		signal:Destroy()
	end

	self._states      = {}
	self._regions     = {}
	self._regionOrder = {}
	self._started     = false
	self._processing  = false
	self._queue       = {}
end

return table.freeze(module)