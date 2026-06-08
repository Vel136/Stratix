# Stratix

A hierarchical state machine for Roblox Luau.

**Version:** v1.0.0

Stratix lets you model complex behavior as a tree of named states with guarded transitions, entry/exit callbacks, parallel regions, history, and an event queue. Send an event; Stratix walks the active state's ancestor chain, finds the first matching transition whose guard passes, and moves to the new state.

Requires **[Signal](https://vel136.github.io/VeSignal/)**.

---

## Install

Drop Stratix into `ReplicatedStorage` and require it:

```lua
local Stratix = require(ReplicatedStorage.Stratix)
```

Stratix requires a Signal implementation at `ReplicatedStorage.Shared.Modules.Utilities.Signal`, or adjust the require path at the top of the module.

---

## Quick Start

```lua
local Stratix = require(ReplicatedStorage.Stratix)

local hsm = Stratix.new()

hsm:AddState("Idle", nil, {
    OnEntry = function(self) print("Entered Idle") end,
    OnExit  = function(self) print("Left Idle")    end,
})
hsm:AddState("Running")
hsm:AddState("Dead")

hsm:AddTransition("Idle",    "RUN",  "Running")
hsm:AddTransition("Running", "STOP", "Idle")
hsm:AddTransition("Running", "DIE",  "Dead")

hsm:Start("Idle")

hsm:Dispatch("RUN")   -- Entered Idle fires, then Running's OnEntry
hsm:Dispatch("DIE")
```

---

## States

Add states before calling `Start`. A state with no parent is a top-level state in the Default region.

```lua
hsm:AddState("Parent")
hsm:AddState("Child", "Parent", {
    OnEntry = function(self) end,
    OnExit  = function(self) end,
})
```

`StateConfig` fields:

| Field | Type | Description |
|-------|------|-------------|
| `OnEntry` | `(hsm) -> ()` | Called when the state is entered |
| `OnExit` | `(hsm) -> ()` | Called when the state is exited |
| `Initial` | `string` | Default child to enter when this state is entered |
| `History` | `"Shallow" \| "Deep"` | Resume the last active child instead of `Initial` |

---

## Transitions

```lua
hsm:AddTransition("Idle", "RUN", "Running")

-- With a guard: transition only fires when the guard returns true
hsm:AddTransition("Running", "JUMP", "Airborne", {
    Guard = function(self) return self.Stamina > 0 end,
})

-- With an action: runs between exit and entry callbacks
hsm:AddTransition("Idle", "ATTACK", "Attacking", {
    Action = function(self) self.AttackCount += 1 end,
})

-- Internal: runs the action without exiting or entering any state
hsm:AddTransition("Idle", "PING", "Idle", {
    Internal = true,
    Action   = function(self) print("ping") end,
})
```

Multiple transitions can share the same event on the same state. Stratix tests each guard in registration order and fires the first one that passes.

---

## Dispatching Events

```lua
hsm:Start("Idle")

local handled = hsm:Dispatch("RUN")
-- returns true if any region handled the event
```

Events dispatched while a transition is in progress are queued and replayed in order after the current transition completes.

---

## Parallel Regions

Use regions to run independent state machines simultaneously.

```lua
hsm:AddRegion("Movement")
hsm:AddRegion("Combat")

hsm:AddState("Walking",  nil, nil, "Movement")
hsm:AddState("Sprinting", nil, nil, "Movement")
hsm:AddState("Unarmed",  nil, nil, "Combat")
hsm:AddState("Armed",    nil, nil, "Combat")

hsm:AddTransition("Walking",  "SPRINT", "Sprinting")
hsm:AddTransition("Unarmed",  "EQUIP",  "Armed")

hsm:Start({ Movement = "Walking", Combat = "Unarmed" })

hsm:Dispatch("EQUIP")   -- only the Combat region transitions
```

Add a region after `Start` by calling `AddRegion` then `StartRegion`:

```lua
hsm:AddRegion("Emote")
hsm:AddState("Idle_Emote", nil, nil, "Emote")
hsm:StartRegion("Emote", "Idle_Emote")
```

---

## History

```lua
hsm:AddState("Menu", nil, { History = "Shallow" })
hsm:AddState("Settings", "Menu")
hsm:AddState("Controls", "Menu")

-- After visiting Controls and leaving Menu,
-- re-entering Menu resumes Controls instead of the default child.
```

`"Shallow"` remembers the direct child last visited. `"Deep"` remembers the deepest active descendant.

---

## Querying State

```lua
-- Active state per region
local active = hsm:GetActive()
-- { Default = "Running", Combat = "Armed" }

-- Active state in one region
local state = hsm:GetActiveIn("Combat")   --> "Armed"

-- Is a state active (including ancestor states)?
hsm:IsActive("Running")              --> true/false
hsm:IsActiveIn("Running", "Default") --> true/false

-- All registered state names
hsm:GetStateNames()             -- all regions
hsm:GetStateNames("Movement")   -- one region
```

---

## Signals

```lua
hsm.Signals.OnStateChanged:Connect(function(prev, next, region)
    print(region, prev, "->", next)
end)

hsm.Signals.OnTransition:Connect(function(from, event, to, region)
    print(event, from, "->", to)
end)
```

| Signal | Parameters | Fires when |
|--------|-----------|------------|
| `OnStateChanged` | `prev: string?, next: string, region: string` | A state becomes active |
| `OnTransition` | `from: string, event: string, to: string, region: string` | A transition completes (including internal) |

---

## Replacing Guards at Runtime

```lua
hsm:ReplaceTransitionGuard("Running", "JUMP", 1, function(self)
    return self.Stamina > 10
end)
```

The third argument is the 1-based index of the transition in the event's list (registration order).

---

## Extend

Pass a builder function to configure an HSM inline:

```lua
hsm:Extend(function(h)
    h:AddState("Idle")
    h:AddState("Active")
    h:AddTransition("Idle", "ACTIVATE", "Active")
end)
```

---

## Destroy

```lua
hsm:Destroy()
```

Runs `OnExit` on all active states, disconnects signals, and clears all internal state.

---

## API

**Constructor**

| Method | Description |
|--------|-------------|
| `Stratix.new()` | Create a new HSM |

**Setup**

| Method | Description |
|--------|-------------|
| `hsm:AddRegion(name, initialState?)` | Add a parallel region |
| `hsm:AddState(name, parent?, config?, region?)` | Register a state |
| `hsm:AddTransition(from, event, to, config?)` | Register a transition |
| `hsm:ReplaceTransitionGuard(from, event, index, guard)` | Swap a guard at runtime |
| `hsm:Extend(fn)` | Configure the HSM via a builder function |

**Lifecycle**

| Method | Description |
|--------|-------------|
| `hsm:Start(initialState?)` | Boot all regions and begin processing events |
| `hsm:StartRegion(name, initialState?)` | Boot a region added after `Start` |
| `hsm:Destroy()` | Exit active states, disconnect signals, tear down |

**Events**

| Method | Description |
|--------|-------------|
| `hsm:Dispatch(event)` | Send an event; returns `true` if any region handled it |

**Querying**

| Method | Description |
|--------|-------------|
| `hsm:GetActive()` | `{ [region]: stateName }` for all regions |
| `hsm:GetActiveIn(region)` | Active state name in one region, or `nil` |
| `hsm:IsActive(name)` | `true` if the state (or any ancestor) is active in any region |
| `hsm:IsActiveIn(name, region)` | `true` if active (or ancestor) in the given region |
| `hsm:GetStateNames(region?)` | Sorted list of registered state names |

---

## License

MIT License. Copyright (c) 2026 Ve Development.
