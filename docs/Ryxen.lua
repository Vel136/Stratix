-- MIT License
--
-- Copyright (c) 2026 Ve Development

--[=[
	@class Stratix

	Hierarchical state machine for Roblox Luau.

	Stratix models behavior as a tree of named states connected by guarded
	transitions. Dispatching an event walks the active state's ancestor chain
	and fires the first transition whose guard passes. It supports nested
	states, parallel regions, shallow/deep history, internal transitions,
	entry/exit callbacks, guards, actions, and an event queue.

	Requires a Signal implementation at
	`ReplicatedStorage.Shared.Modules.Utilities.Signal`.

	```lua
	local Stratix = require(ReplicatedStorage.Stratix)

	local hsm = Stratix.new()

	hsm:AddState("Idle", nil, {
	    OnEntry = function(self) print("Idle") end,
	    OnExit  = function(self) print("Leaving Idle") end,
	})
	hsm:AddState("Running")

	hsm:AddTransition("Idle",    "RUN",  "Running")
	hsm:AddTransition("Running", "STOP", "Idle")

	hsm:Start("Idle")
	hsm:Dispatch("RUN")
	```
]=]
local Stratix = {}

--[=[
	@function new
	@within Stratix

	Creates a new hierarchical state machine.

	```lua
	local hsm = Stratix.new()
	```

	@return HSM
]=]
function Stratix.new() end

--[=[
	@prop Signals StoreSignals
	@within Stratix

	Top-level Signal connections for the HSM.

	| Signal | Parameters | Fires when |
	|--------|-----------|------------|
	| `OnStateChanged` | `prev: string?, next: string, region: string` | A state becomes active |
	| `OnTransition` | `from: string, event: string, to: string, region: string` | A transition completes (including internal) |

	```lua
	hsm.Signals.OnStateChanged:Connect(function(prev, next, region)
	    print(region, prev, "->", next)
	end)

	hsm.Signals.OnTransition:Connect(function(from, event, to, region)
	    print(event, from, "->", to)
	end)
	```
]=]
Stratix.Signals = nil

--[=[
	@method AddRegion
	@within Stratix

	Registers a parallel region. Each region runs its own active state
	independently. Must be called before `Start` unless you intend to boot it
	later with `StartRegion`.

	```lua
	hsm:AddRegion("Movement", "Idle")
	hsm:AddRegion("Weapon")
	```

	@param name string -- Unique region name.
	@param initialState string? -- Default initial state for this region.
]=]
function Stratix:AddRegion(name, initialState) end

--[=[
	@method AddState
	@within Stratix

	Registers a state. If `parentName` is provided the state is nested under
	that parent and inherits its region. If `regionName` is provided the state
	is placed in that region as a top-level state. If neither is given, Stratix
	creates and uses the implicit `"Default"` region.

	```lua
	hsm:AddState("Idle")

	hsm:AddState("Moving", nil, { Initial = "Walking" })
	hsm:AddState("Walking",  "Moving")
	hsm:AddState("Sprinting", "Moving")

	hsm:AddState("Unarmed", nil, nil, "Weapon")
	```

	@param name string -- Unique state name.
	@param parentName string? -- Parent state name, if nested.
	@param config StateConfig? -- Entry/exit callbacks and history settings.
	@param regionName string? -- Region to place the state in (top-level states only).
	@return string -- The state name, for convenience.
]=]
function Stratix:AddState(name, parentName, config, regionName) end

--[=[
	@method AddTransition
	@within Stratix

	Registers a transition from `fromName` to `toName` triggered by `event`.
	Both states must be in the same region. Multiple transitions can share the
	same event; guards are tested in registration order.

	```lua
	-- Basic
	hsm:AddTransition("Idle", "RUN", "Running")

	-- With guard
	hsm:AddTransition("Running", "JUMP", "Airborne", {
	    Guard = function(self) return self.Stamina > 0 end,
	})

	-- With action (runs between OnExit and OnEntry)
	hsm:AddTransition("Idle", "ATTACK", "Attacking", {
	    Action = function(self) self.AttackCount += 1 end,
	})

	-- Internal (action only, no exit/entry)
	hsm:AddTransition("Idle", "PING", "Idle", {
	    Internal = true,
	    Action   = function(self) print("ping") end,
	})
	```

	@param fromName string -- Source state.
	@param event string -- Event string that triggers this transition.
	@param toName string -- Target state.
	@param config TransitionConfig? -- Optional guard, action, and internal flag.
]=]
function Stratix:AddTransition(fromName, event, toName, config) end

--[=[
	@method ReplaceTransitionGuard
	@within Stratix

	Replaces the guard on an existing transition at runtime. `index` is
	1-based and matches registration order for that event on that state.

	```lua
	hsm:ReplaceTransitionGuard("Running", "JUMP", 1, function(self)
	    return self.Stamina > 10
	end)
	```

	@param fromName string
	@param event string
	@param index number -- 1-based index in the transition list for this event.
	@param newGuard (hsm: HSM) -> boolean
]=]
function Stratix:ReplaceTransitionGuard(fromName, event, index, newGuard) end

--[=[
	@method Extend
	@within Stratix

	Passes the HSM to `builderFn`, allowing you to modularize setup.

	```lua
	local function addMovement(h)
	    h:AddState("Idle")
	    h:AddState("Running")
	    h:AddTransition("Idle", "RUN", "Running")
	end

	hsm:Extend(addMovement)
	```

	@param builderFn (hsm: HSM) -> ()
]=]
function Stratix:Extend(builderFn) end

--[=[
	@method Start
	@within Stratix

	Boots all registered regions and begins processing events. Can only be
	called once. Pass a state name for single-region machines, or a table
	mapping region names to initial states for multi-region machines.

	```lua
	-- Single region
	hsm:Start("Idle")

	-- Multiple regions
	hsm:Start({ Movement = "Walking", Weapon = "Unarmed" })
	```

	@param initialStates ({ [string]: string } | string)? -- Initial state(s).
]=]
function Stratix:Start(initialStates) end

--[=[
	@method StartRegion
	@within Stratix

	Boots a region that was added after `Start`. All states and transitions for
	the region must be registered before calling this.

	```lua
	hsm:AddRegion("Emote")
	hsm:AddState("Idle_Emote", nil, nil, "Emote")
	hsm:StartRegion("Emote", "Idle_Emote")
	```

	@param regionName string
	@param initialState string? -- Overrides the region's registered initial state.
]=]
function Stratix:StartRegion(regionName, initialState) end

--[=[
	@method Dispatch
	@within Stratix

	Sends an event to all regions. Each region walks its active state's
	ancestor chain and fires the first matching transition whose guard passes.

	Events dispatched while a transition is in progress are queued and
	replayed in order after the current transition completes.

	```lua
	local handled = hsm:Dispatch("RUN")
	```

	@param event string
	@return boolean -- `true` if at least one region handled the event.
]=]
function Stratix:Dispatch(event) end

--[=[
	@method GetActive
	@within Stratix

	Returns the active state name for every region.

	```lua
	local active = hsm:GetActive()
	-- { Default = "Running", Weapon = "Armed" }
	```

	@return { [string]: string }
]=]
function Stratix:GetActive() end

--[=[
	@method GetActiveIn
	@within Stratix

	Returns the active state name in the given region, or `nil` if the region
	has not been started.

	```lua
	local state = hsm:GetActiveIn("Weapon")   --> "Armed"
	```

	@param regionName string
	@return string?
]=]
function Stratix:GetActiveIn(regionName) end

--[=[
	@method IsActive
	@within Stratix

	Returns `true` if `name` is the active state or an active ancestor state
	in any region.

	```lua
	hsm:IsActive("Moving")   --> true when Walking or Sprinting is active
	```

	@param name string
	@return boolean
]=]
function Stratix:IsActive(name) end

--[=[
	@method IsActiveIn
	@within Stratix

	Returns `true` if `name` is the active state or an active ancestor state
	in the specified region.

	```lua
	hsm:IsActiveIn("Moving", "Default")
	```

	@param name string
	@param regionName string
	@return boolean
]=]
function Stratix:IsActiveIn(name, regionName) end

--[=[
	@method GetStateNames
	@within Stratix

	Returns a sorted list of all registered state names, optionally filtered
	to one region. Root sentinel states are excluded.

	```lua
	hsm:GetStateNames()            -- all regions
	hsm:GetStateNames("Movement")  -- one region
	```

	@param regionName string? -- Filter to this region.
	@return { string }
]=]
function Stratix:GetStateNames(regionName) end

--[=[
	@method Destroy
	@within Stratix

	Destroys the HSM. Runs `OnExit` on all currently active states, then
	disconnects all signals and clears internal state. The HSM cannot be used
	after this call.

	```lua
	hsm:Destroy()
	```
]=]
function Stratix:Destroy() end

return Stratix
