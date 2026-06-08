---
sidebar_position: 1
---

# Getting Started

Stratix is a hierarchical state machine for Roblox Luau. Register states, add transitions, start the machine, and dispatch events.

---

## Installation

Get Stratix from the **[Roblox Creator Store](https://create.roblox.com/store/asset/71022374633308/Stratix)** and drop the module into `ReplicatedStorage`.

Stratix requires a Signal implementation at `ReplicatedStorage.Shared.Modules.Utilities.Signal`, or adjust the require path at the top of the module.

```lua
local Stratix = require(ReplicatedStorage.Stratix)
```

---

## Creating an HSM

```lua
local Stratix = require(ReplicatedStorage.Stratix)

local hsm = Stratix.new()
```

---

## Registering States

```lua
hsm:AddState("Idle", nil, {
    OnEntry = function(self) print("Entered Idle") end,
    OnExit  = function(self) print("Left Idle")    end,
})
hsm:AddState("Running")
hsm:AddState("Dead")
```

---

## Adding Transitions

```lua
hsm:AddTransition("Idle",    "RUN",  "Running")
hsm:AddTransition("Running", "STOP", "Idle")
hsm:AddTransition("Running", "DIE",  "Dead")
```

---

## Starting and Dispatching

```lua
hsm:Start("Idle")

hsm:Dispatch("RUN")
hsm:Dispatch("DIE")
```

---

## Listening to Changes

```lua
hsm.Signals.OnStateChanged:Connect(function(prev, next, region)
    print(region, prev, "->", next)
end)
```

---

## Quick Reference

| I want to... | Method |
|--------------|--------|
| Create an HSM | [`Stratix.new`](../api/Stratix#new) |
| Add a region | [`hsm:AddRegion`](../api/Stratix#AddRegion) |
| Register a state | [`hsm:AddState`](../api/Stratix#AddState) |
| Register a transition | [`hsm:AddTransition`](../api/Stratix#AddTransition) |
| Start the machine | [`hsm:Start`](../api/Stratix#Start) |
| Send an event | [`hsm:Dispatch`](../api/Stratix#Dispatch) |
| Query active state | [`hsm:GetActive`](../api/Stratix#GetActive) |
| Check if state is active | [`hsm:IsActive`](../api/Stratix#IsActive) |
| Observe transitions | [`hsm.Signals`](../api/Stratix#Signals) |
| See practical examples | [Use Cases](./guides/use-cases) |
