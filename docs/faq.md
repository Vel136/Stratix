---
sidebar_position: 4
---

# FAQ

Answers to the questions that come up most often.

---

## General

**What is Stratix?**

Stratix is a hierarchical state machine (HSM) for Roblox Luau. You register named states and transitions, start the machine, and dispatch string events. Stratix walks the active state's ancestor chain and fires the first matching transition whose guard passes.

---

**What does Stratix depend on?**

Stratix requires a Signal implementation at `ReplicatedStorage.Shared.Modules.Utilities.Signal`. Both are developed by Ve Development.

---

**Can I use Stratix on both server and client?**

Yes. Stratix has no service dependencies beyond Signal. Require it on the server, the client, or both.

---

**Is Stratix free to use?**

Yes. Stratix is open-source software released under the MIT License. See the LICENSE file for full terms.

---

## States

**What is a hierarchical state?**

States can be nested. A child state inherits transitions from its parent. When an event is dispatched, Stratix starts at the currently active leaf state and walks up the ancestor chain until it finds a matching transition with a passing guard.

---

**What is the Default region?**

If you call `AddState` without specifying a region or parent, Stratix automatically creates a region named `"Default"` and places the state there. You do not need to call `AddRegion` for a single-region machine.

---

**What does `Initial` do in `StateConfig`?**

When entering a parent state, Stratix needs to pick which child to enter. `Initial` names that child. Without it, Stratix picks the first registered child, which is non-deterministic if you have more than one.

---

## Transitions

**What is a guard?**

A guard is a function `(hsm) -> boolean` attached to a transition. The transition only fires if the guard returns `true`. Guards are tested in registration order; the first passing guard wins.

---

**What is an internal transition?**

An internal transition runs its `Action` without exiting or entering any state, so `OnExit` and `OnEntry` callbacks do not fire. Useful for reacting to events that affect behavior without changing state.

---

**Can multiple transitions share the same event?**

Yes. Register them in priority order. Stratix tests each guard and fires the first one that passes.

---

## Regions

**What are parallel regions?**

Regions let you run multiple independent state machines inside one HSM. Each region has its own active state. When you dispatch an event, every region processes it independently.

---

**When should I add a region vs. nesting states?**

Use regions when two concerns are truly independent (e.g., movement and weapon state). Use nested states when one concern has sub-states that share transitions (e.g., a `Moving` parent with `Walking` and `Sprinting` children that share a `STOP` transition).

---

**Can I add a region after `Start`?**

Yes. Call `AddRegion`, register all states and transitions for it, then call `StartRegion(name, initialState)`.

---

## History

**What is the difference between `"Shallow"` and `"Deep"` history?**

`"Shallow"` remembers the direct child last active when the parent was exited. `"Deep"` remembers the deepest active descendant.

---

**Does history apply on the first entry?**

No. History only applies on re-entry after the parent has been exited at least once. On the first entry, `Initial` (or the first registered child) is used.

---

## Events

**What happens if I dispatch an event while a transition is in progress?**

The event is queued. After the current transition finishes, Stratix drains the queue in order.

---

**What does `Dispatch` return?**

It returns `true` if at least one region handled the event, `false` otherwise.

---

## Lifecycle

**How do I clean up an HSM?**

Call `hsm:Destroy()`. It runs `OnExit` on all active states, disconnects signals, and clears all internal state. The HSM cannot be used after this call.

---

**Does `Destroy` fire `OnExit` on active states?**

Yes. It walks each region's active state up to the root and calls `OnExit` on every non-root ancestor in order.
