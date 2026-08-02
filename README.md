# Stageable

A UIKit navigation container that replaces `UINavigationController` with a theatrical metaphor. Screens are **scenes**; their UI elements are **props** that animate on and off like set pieces entering from the wings.

Scenes declare *what* moves and *from where*. The stage decides *when*.

---

## What the stage is responsible for

| The stage owns | The scene owns |
|---|---|
| **The stack** — `push`, `pop`, `popToRoot`, `replaceTop`, `setRoot`. Nothing else adds or removes a scene. | **Its props** — which views move, from which edge, after what delay. Data, not code. |
| **Transition timing** — `inDuration`, `outDuration`, spring, stagger, ordering. | **Its own content and state**, for as long as it is on the stack. |
| **Chrome that outlives a scene** — the stage's own `props`, animated on every transition and kept in front. | **Its entrance/exit hooks** — the things a transform can't express: fades, layout changes, resets. |
| **Whether it is busy** — `isTransitioning`, and the rule that navigation during a transition is deferred or dropped. | |

**What the stage must not know:** what identity is, what a session is, or what ought to be on it. It is handed a scene and shows it. That ignorance is why the same container can carry a login screen and a document viewer — and why the root decision belongs in the app, not here.

---

## Usage

### 1. Conform to `Stageable`

```swift
extension ProfileVC: Stageable {
    var props: [Prop] {
        [Prop(headerView,  from: .top),
         Prop(avatarView,  from: .left,   delay: 0.05),
         Prop(contentView, from: .bottom, delay: 0.1)]
    }
}
```

`props` is evaluated at each transition, so it can vary with state.

### 2. Navigate

From any `Stageable`:

```swift
push(DetailVC())        // push onto the stack
pop()                   // back one
popToRoot()             // back to the stage root
replaceTop(NextVC())    // swap in place; the stack does not grow
```

Valid from **any** scene in the stack, not just the visible one — a covered scene keeps its parent, so `stage` resolves for it.

### 3. Subclass `StageVC` for your app's container

```swift
final class BaseVC: StageVC {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}
```

Override `vcWillTransition(from:)`, `vcWillTransition(to:)` and `vcDidTransition()` to keep chrome in sync. `vcDidTransition()` is the **settle event** — the correct place to consume anything that had to wait for the stage.

---

## Adopting it correctly

Seven apps run this. The steps below are what they converged on; **Smells** is what they each got wrong first.

### 1. The window root is the stage, and it never changes

Install it once and leave it. Login and Home are both *scenes on it* — not alternative window roots.

```swift
let base = BaseVC()
window.rootViewController = base
window.makeKeyAndVisible()
```

Everything that reaches through the window root — deep links, share-sheet handoffs, topmost-VC walks — keeps working across a login and a logout, because the root outlives both.

### 2. Install the first scene in `viewIsAppearing`

Not `viewDidLoad`. Props are measured against real geometry, and in `viewDidLoad` there isn't any.

```swift
private var pendingRoot: Stageable?
private var didInstallRoot = false

override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    guard !didInstallRoot, let root = pendingRoot else { return }
    didInstallRoot = true
    pendingRoot = nil
    setRoot(root)
}
```

### 3. One reconcile, deriving the destination from the session

The root's destination is a pure function of "who is signed in". Login success and logout **call the reconcile**; they never name a destination.

```swift
enum RootIntent { case content, login }
private var installedRoot: RootIntent?

func reconcileRoot() {
    let desired: RootIntent = hasPersistedIdentity ? .content : .login
    guard installedRoot != desired else { return }

    // Record only once a scene exists to install — see Smell 4.
    guard let scene = scene(for: desired) else { return }
    installedRoot = desired

    guard didInstallRoot else { pendingRoot = scene; return }
    setRoot(scene)
}
```

### 4. Compare a stored **intent**, never the view

`installedRoot != desired` — not `top is HomeVC`, not `children.contains { $0 is LoginVC }`. See Smell 1; this is the one that has actually shipped as a bug.

### 5. Use a synchronous identity predicate

`Session.storage.loggedInUser != nil` and friends are already in memory. Awaiting them before staging anything just delays first paint, and an `await` on the root decision invites a stash-and-defer dance that isn't needed.

### 6. Chrome goes on the container as props

```swift
props = [Prop(btnSettings, from: .bottom)]
```

Container props animate with every transition and are kept in front. Toggle their visibility from `vcWillTransition(to:)`.

### 7. Add a second stage only for a persistent **region**

If part of the screen must survive content navigation — a sidebar beside a detail pane — that content needs its own stage, because `push` replaces the whole of a stage's view. A host VC owns the inner stage and subclasses `StageVC` to observe it.

Not a reason for a second stage: app size, "these change on different schedules", or content that can't be chosen until a fetch returns (show a placeholder scene on the one stage instead).

---

## Smells

Each of these was found in shipped code, most in more than one app.

### 1. Asking the view hierarchy what the root is

```swift
// WRONG
guard hasUser == (top is LoginVC) else { return }
guard hasUser == children.contains(where: { $0 is LoginVC }) else { return }
```

A stage **covers** its root on `push`. Push anything over the login screen and the view query reports the login as gone, so the reconcile concludes the root already agrees and never restores it. This shipped: a device sat logged-out with no way back, and the fix at the time was to refuse deep links while logged out — a workaround at one call site, not a repair.

Compare a stored intent.

### 2. A private copy of the stage lookup

Three apps independently defined `enclosingStage` on `UIViewController` — the same parent-chain walk `Stageable.stage` already ships. If you are writing a loop over `parent`, stop; it exists.

### 3. Polling for the stage to settle

```swift
// WRONG
guard !isTransitioning else {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.reconcileRoot() }
    return
}
```

There were **ten** hand-rolled variants of this across four apps, in five different policies. Four used `0.6s` against a default transition of `0.45 + 0.35` — always firing early, always costing an extra hop, and both durations are overridable anyway.

`setRoot` queues itself and applies on settle. For anything else, use `vcDidTransition()` and a latest-wins desired-state field. Never sleep, never poll, never guess a constant.

### 4. Recording an intent before the scene exists

```swift
// WRONG
installedRoot = desired
guard let scene = makeScene(desired) else { return }
```

If the factory is failable — a storyboard lookup, an optional closure — this leaves the intent recorded with nothing installed. Every later reconcile then concludes the root already agrees, and the stage stays blank permanently.

### 5. Asymmetric pre-install handling

```swift
// WRONG
guard didInstallRoot else {
    if !hasUser { pendingRoot = LoginVC() }   // ...and if hasUser?
    return
}
```

`viewIsAppearing` bails when `pendingRoot` is nil **without** setting `didInstallRoot`, and it does not fire again. Set both branches.

### 6. Two spellings of identity

One app's `reconcileRoot` read `Session.storage.loggedInUser` while its `viewIsAppearing` read `AppSession.hasPersistedIdentity`. Same value that day. That is exactly how two root decisions drift apart later.

### 7. Blockers that discard instead of defer

A non-identity root — a launch-time takeover screen — may legitimately veto the reconcile. It must leave the need recorded and consume it when it clears; otherwise an identity change arriving during the veto is swallowed, and recovery depends on the user happening to tap the right thing.

### 8. Treating `setRoot` as a teardown mechanism

Replacing the root drops the *in-memory projections* a session built, if nothing else retains them. It does not reclaim `@Prefs`/UserDefaults, statics, singletons, keychain, SwiftData or files; it does not cancel in-flight `Task`s; and `removeFromParent` is not `deinit`. Teardown that has to be **correct** belongs in one explicit pipeline, ordered against in-flight work. The root swap is a UI transition that happens to release some memory.

### 9. Keeping a parallel copy of stage state

`top` and `isTransitioning` are exposed so you do not have to. A `currentTop` field assigned from `vcWillTransition(to:)` reports the *incoming* scene while the outgoing one is still on screen.

---

## Props

**Direction** — the view slides fully off an edge:

```swift
Prop(view, from: .top)
Prop(view, from: .bottomRight, delay: 0.05)
```

`.top`, `.bottom`, `.left`, `.right`, `.topLeft`, `.topRight`, `.bottomLeft`, `.bottomRight`

**Custom transform** — anything else:

```swift
Prop(view, transform: .init(scaleX: 0, y: 0))
```

Off-screen travel is measured in the **window's** coordinate space, so props inside inset containers, inner stages, and non-fullscreen windows (Split View, Stage Manager) all travel the correct distance.

> `Prop.overlay` is currently **not read** by `StageVC`. Passing `overlay: false` behaves identically to the default. It is kept because several apps already pass it and its intended behaviour is an open product question.

---

## Lifecycle hooks

`Stageable` — all optional:

| Method | Timing |
|---|---|
| `prepareForEntrance()` | After layout, before entrance animations. Configure initial state; `UIView.animate` here runs concurrently with the props. |
| `prepareForExit()` | Before exit animations. Kick off anything that cannot be a transform — a fade, a collapse. |
| `didFinishEntrance()` | After every entrance animation completes. |

`StageVC` — override to keep container chrome in sync:

| Method | Timing |
|---|---|
| `vcWillTransition(from:)` | The outgoing scene is about to animate off. |
| `vcWillTransition(to:)` | The incoming scene is about to animate on. Fires for the first scene too. |
| `vcDidTransition()` | The stage has settled. **The settle event** — consume deferred work here. |

---

## Container API

| Member | Notes |
|---|---|
| `top: Stageable?` | The scene on top, or nil while empty. Updated when the stack mutates, i.e. after the exit animation. |
| `isTransitioning: Bool` | True for the whole of any transition, including the first install. Navigation is deferred (`setRoot`) or dropped (`push`/`pop`) while true. |
| `props: [Prop]` | Container chrome. Stored, not computed — reassign it if the views change. |
| `inDuration` / `outDuration` | `0.45` / `0.35`. Overridable. |

---

## Files

| File | Purpose |
|---|---|
| `StageVC.swift` | The container — navigation stack and animation engine |
| `Stageable.swift` | The `Stageable` protocol, `stage` lookup, navigation conveniences |
| `Prop.swift` | Declarative description of an animated view element |
