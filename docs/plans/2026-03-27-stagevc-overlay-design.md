# StageVC Overlay Support

## Goal

Allow StageVC to participate in transitions with its own animated props, and provide lifecycle hooks so subclasses can manage persistent overlay elements (e.g., a Settings button that lives above all child VCs).

## Context

Apps using Stageable subclass StageVC as their root container. Currently, only child VCs declare `props` and participate in animations. There is no mechanism for StageVC itself to own animated elements or for subclasses to react to transitions.

## Design

### StageVC Props

StageVC gets a public `props: [Prop]` property, defaulting to an empty array. Subclasses populate this with views that should animate alongside every transition.

During transitions, StageVC's props follow the same animation rules as child VC props:

- **Animate out:** StageVC's props animate off-screen alongside the outgoing VC's props (0.35s spring, no bounce)
- **Animate in:** StageVC's props animate back on-screen alongside the incoming VC's props (0.45s spring, 0.1 bounce)
- **Install first:** StageVC's props animate in alongside the initial root VC's props

StageVC's props are included in the same animation pass as child props — no separate animation cycle.

### Lifecycle Hooks

Two `open` methods with empty default implementations:

- **`vcWillTransition()`** — called before any animations begin
- **`vcDidTransition()`** — called after all animations complete

Called in all VC management methods: `push`, `pop`, `popToRoot`, and `setRoot` (including the `installFirst` path when the stack is empty).

Subclasses override these to perform overlay management such as `bringSubviewToFront`, updating visibility, or other bookkeeping.

### How It Fits Together

A typical subclass workflow:

1. Subclass sets up overlay views in `viewDidLoad` and populates `props` with them
2. On every transition, the overlay views animate out and back in with the rest of the scene
3. In `vcDidTransition`, the subclass calls `bringSubviewToFront` on its overlay views to ensure they sit above the newly installed child VC

### What This Does Not Do

- No overlay container view or automatic z-ordering — subclasses manage their own view hierarchy
- No scoped per-VC overlay modifications — subclasses handle this if needed
- No parameters on the hooks (incoming/outgoing VC, transition type) — subclasses inspect their own state

## Implementation Tasks

1. **Add `props: [Prop]` property to StageVC** — public, defaults to empty array
2. **Add `vcWillTransition()` and `vcDidTransition()` hooks** — open, empty defaults
3. **Integrate StageVC props into animation engine** — update `animateOut`, `animateIn`, `installFirst` to include StageVC's props in the same animation pass (blocked by #1)
4. **Wire hooks into all VC management methods** — call `vcWillTransition` before animations, `vcDidTransition` after completion in `push`, `pop`, `popToRoot`, `setRoot` (blocked by #2, #3)
