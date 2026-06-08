---
sidebar_position: 1
---

# Use Cases

Practical patterns for common Stratix scenarios.

---

## Basic Character States

Model a character with idle, running, and dead states.

```lua
local Stratix = require(ReplicatedStorage.Stratix)

local hsm = Stratix.new()

hsm:AddState("Idle", nil, {
    OnEntry = function(self) print("Idle") end,
})
hsm:AddState("Running", nil, {
    OnEntry = function(self) print("Running") end,
})
hsm:AddState("Dead")

hsm:AddTransition("Idle",    "RUN",  "Running")
hsm:AddTransition("Running", "STOP", "Idle")
hsm:AddTransition("Running", "DIE",  "Dead")
hsm:AddTransition("Idle",    "DIE",  "Dead")

hsm:Start("Idle")

hsm:Dispatch("RUN")
hsm:Dispatch("DIE")
```

---

## Guarded Transitions

Only allow a transition when a condition is met.

```lua
hsm:AddTransition("Running", "JUMP", "Airborne", {
    Guard = function(self) return self.Stamina > 0 end,
})

hsm:AddTransition("Running", "JUMP", "Airborne", {
    Guard = function(self) return self.OnGround end,
})
```

Multiple transitions on the same event are tested in registration order. The first passing guard fires.

---

## Entry and Exit Actions

Run logic when entering or leaving a state.

```lua
hsm:AddState("Combat", nil, {
    OnEntry = function(self)
        self.CombatMusic:Play()
    end,
    OnExit = function(self)
        self.CombatMusic:Stop()
    end,
})
```

---

## Transition Actions

Run logic between the exit and entry callbacks.

```lua
hsm:AddTransition("Idle", "ATTACK", "Attacking", {
    Action = function(self)
        self.AttackCount += 1
    end,
})
```

---

## Internal Transitions

Run an action on an event without changing state or triggering exit/entry callbacks.

```lua
hsm:AddTransition("Idle", "INTERACT", "Idle", {
    Internal = true,
    Action   = function(self) self:ShowPrompt() end,
})
```

---

## Nested States

Child states inherit parent transitions. If a child has no handler, Stratix walks up to the parent.

```lua
hsm:AddState("Moving")
hsm:AddState("Walking",  "Moving")
hsm:AddState("Sprinting", "Moving")

hsm:AddTransition("Walking",  "SPRINT", "Sprinting")
hsm:AddTransition("Sprinting","WALK",   "Walking")
hsm:AddTransition("Moving",   "STOP",   "Idle")  -- available to both children

hsm:Start("Walking")

hsm:Dispatch("STOP")   -- handled by Moving's transition
```

---

## Parallel Regions

Run two state machines simultaneously, each handling events independently.

```lua
hsm:AddRegion("Movement")
hsm:AddRegion("Weapon")

hsm:AddState("Grounded", nil, nil, "Movement")
hsm:AddState("Airborne", nil, nil, "Movement")
hsm:AddState("Unarmed",  nil, nil, "Weapon")
hsm:AddState("Armed",    nil, nil, "Weapon")

hsm:AddTransition("Grounded", "JUMP",  "Airborne")
hsm:AddTransition("Airborne", "LAND",  "Grounded")
hsm:AddTransition("Unarmed",  "EQUIP", "Armed")
hsm:AddTransition("Armed",    "STOW",  "Unarmed")

hsm:Start({ Movement = "Grounded", Weapon = "Unarmed" })

hsm:Dispatch("JUMP")   -- only Movement transitions
hsm:Dispatch("EQUIP")  -- only Weapon transitions
```

---

## History

Resume the last active child state instead of the default when re-entering a parent.

```lua
hsm:AddState("Menu", nil, { History = "Shallow", Initial = "Main" })
hsm:AddState("Main",     "Menu")
hsm:AddState("Settings", "Menu")

hsm:AddTransition("Menu",  "CLOSE", "HUD")
hsm:AddTransition("HUD",   "MENU",  "Menu")

hsm:Start("Main")

hsm:Dispatch("MENU")   -- enters Main (default)
-- navigate to Settings...
hsm:Dispatch("CLOSE")
hsm:Dispatch("MENU")   -- resumes Settings via Shallow history
```

---

## Querying Active State

Check which state is active before taking an action.

```lua
if hsm:IsActive("Combat") then
    self:SpawnEnemy()
end

local state = hsm:GetActiveIn("Weapon")
print("Weapon state:", state)
```

---

## Reacting to Transitions

Log or respond to every state change.

```lua
hsm.Signals.OnStateChanged:Connect(function(prev, next, region)
    print(string.format("[%s] %s -> %s", region, tostring(prev), next))
end)

hsm.Signals.OnTransition:Connect(function(from, event, to, region)
    print(string.format("[%s] %s fired %s -> %s", region, from, event, to))
end)
```

---

## Runtime Guard Replacement

Swap a guard condition without re-registering the transition.

```lua
hsm:AddTransition("Running", "JUMP", "Airborne", {
    Guard = function(self) return self.Stamina > 0 end,
})

-- Later, tighten the requirement
hsm:ReplaceTransitionGuard("Running", "JUMP", 1, function(self)
    return self.Stamina > 25
end)
```

---

## Extend for Composition

Break HSM setup into reusable builder functions.

```lua
local function addMovement(h)
    h:AddRegion("Movement")
    h:AddState("Idle",    nil, nil, "Movement")
    h:AddState("Running", nil, nil, "Movement")
    h:AddTransition("Idle", "RUN", "Running")
    h:AddTransition("Running", "STOP", "Idle")
end

local hsm = Stratix.new()
hsm:Extend(addMovement)
hsm:Start({ Movement = "Idle" })
```

---

## Cleanup

Always destroy the HSM when the owning entity is removed.

```lua
character.AncestryChanged:Connect(function()
    if not character:IsDescendantOf(workspace) then
        hsm:Destroy()
    end
end)
```
