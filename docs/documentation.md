---
sidebar_position: 2
sidebar_label: "Overview"
---

# Stratix

*States. Transitions. Events.*

Hierarchical state machine for Roblox Luau.

Stratix models behavior as a tree of named states connected by guarded transitions. Dispatching an event walks the active state's ancestor chain and fires the first matching transition. It supports nested states, parallel regions, history, internal transitions, entry/exit callbacks, guards, and actions.

---

## One File. One Require.

Drop Stratix into `ReplicatedStorage` and require it from any script. Also requires a **[Signal](https://vel136.github.io/VeSignal/)** implementation.

```lua
local Stratix = require(ReplicatedStorage.Stratix)
```

---

## Creating an HSM

```lua
local hsm = Stratix.new()
```

---

## States

```lua
hsm:AddState("Idle", nil, {
    OnEntry = function(self) end,
    OnExit  = function(self) end,
})

-- Child state (nested under Idle)
hsm:AddState("IdleAlert", "Idle")
```

`StateConfig` fields:

| Field | Type | Description |
|-------|------|-------------|
| `OnEntry` | `(hsm) -> ()` | Called when the state is entered |
| `OnExit` | `(hsm) -> ()` | Called when the state is exited |
| `Initial` | `string` | Default child state to enter |
| `History` | `"Shallow" \| "Deep"` | Resume the last active child on re-entry |

---

## Transitions

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

-- Internal (action only, no state change, no exit/entry callbacks)
hsm:AddTransition("Idle", "PING", "Idle", {
    Internal = true,
    Action   = function(self) print("ping") end,
})
```

Multiple transitions can share the same event. Guards are tested in registration order; the first passing guard fires.

---

## Start and Dispatch

```lua
hsm:Start("Idle")

local handled = hsm:Dispatch("RUN")
-- returns true if at least one region handled the event
```

Events dispatched during a transition are queued and replayed in order.

---

## Parallel Regions

Regions run independent state machines simultaneously. Each region has its own active state and handles events independently.

```lua
hsm:AddRegion("Movement")
hsm:AddRegion("Combat")

hsm:AddState("Walking",  nil, nil, "Movement")
hsm:AddState("Sprinting", nil, nil, "Movement")
hsm:AddState("Unarmed",  nil, nil, "Combat")
hsm:AddState("Armed",    nil, nil, "Combat")

hsm:AddTransition("Walking", "SPRINT", "Sprinting")
hsm:AddTransition("Unarmed", "EQUIP",  "Armed")

hsm:Start({ Movement = "Walking", Combat = "Unarmed" })

hsm:Dispatch("EQUIP")   -- only the Combat region transitions
```

Add a region after `Start`:

```lua
hsm:AddRegion("Emote")
hsm:AddState("Idle_Emote", nil, nil, "Emote")
hsm:StartRegion("Emote", "Idle_Emote")
```

---

## Nested States

A child state inherits transitions from its parent. If a child has no handler for an event, Stratix walks up to the parent and tries its transitions.

```lua
hsm:AddState("Moving")
hsm:AddState("Walking", "Moving")
hsm:AddState("Sprinting", "Moving")

-- Transitions on Moving are available to Walking and Sprinting
hsm:AddTransition("Moving", "STOP", "Idle")
```

---

## History

```lua
hsm:AddState("Menu", nil, { History = "Shallow", Initial = "Main" })
hsm:AddState("Main",     "Menu")
hsm:AddState("Settings", "Menu")
hsm:AddState("Controls", "Settings")

-- "Shallow": re-entering Menu resumes the last direct child visited
-- "Deep": re-entering Menu resumes the deepest descendant visited
```

---

## Signals

```lua
hsm.Signals.OnStateChanged:Connect(function(prev, next, region)
    print(region, prev, "->", next)
end)

hsm.Signals.OnTransition:Connect(function(from, event, to, region)
    print(event, from, "->", to, "in", region)
end)
```

| Signal | Parameters | Fires when |
|--------|-----------|------------|
| `OnStateChanged` | `prev: string?, next: string, region: string` | A state becomes active |
| `OnTransition` | `from: string, event: string, to: string, region: string` | Any transition completes (including internal) |

---

## Querying State

```lua
-- All active states
local active = hsm:GetActive()
-- { Default = "Running", Combat = "Armed" }

-- One region
local state = hsm:GetActiveIn("Combat")

-- Is this state (or any ancestor) currently active?
hsm:IsActive("Running")
hsm:IsActiveIn("Running", "Default")

-- All registered state names
hsm:GetStateNames()
hsm:GetStateNames("Combat")
```

---

## Replacing Guards at Runtime

```lua
hsm:ReplaceTransitionGuard("Running", "JUMP", 1, function(self)
    return self.Stamina > 10
end)
```

The index is 1-based and matches registration order for that event on that state.

---

## Extend

Configure an HSM inline via a builder function:

```lua
hsm:Extend(function(h)
    h:AddState("Idle")
    h:AddTransition("Idle", "GO", "Active")
end)
```

---

## Destroy

```lua
hsm:Destroy()
```

Runs `OnExit` on all active states top-down, disconnects all signals, and clears internal state. The HSM cannot be used after this.
