# Stageable

A lightweight UIKit navigation framework that replaces `UINavigationController` with a theatrical metaphor. Child view controllers are **actors** — their UI elements are **props** that animate on and off screen like set pieces entering from the wings.

View controllers declare *what* moves and *where from*. The framework handles all animation choreography.

## How It Works

**`StageVC`** is a container view controller that manages a stack of children. Each child conforms to the **`Stageable`** protocol and returns an array of **`Prop`** values describing its animated views.

When a transition occurs, the current screen's props animate off-screen, the view controller is swapped, and the incoming screen's props animate in — all with staggered spring timing.

```
┌─────────────────────────────┐
│          StageVC            │
│  ┌───────────────────────┐  │
│  │   Stageable Child VC  │  │
│  │                       │  │
│  │  prop ← slides from   │  │
│  │  prop ← slides from   │  │
│  │  prop ← slides from   │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

## Usage

### 1. Conform to `Stageable`

```swift
extension ProfileVC: Stageable {
    var props: [Prop] {
        [
            Prop(headerView,  from: .top),
            Prop(avatarView,  from: .left,   delay: 0.05),
            Prop(contentView, from: .bottom, delay: 0.1)
        ]
    }
}
```

Each `Prop` takes a view, a direction (or custom transform), and an optional delay for staggering.

### 2. Navigate

From any `Stageable` view controller:

```swift
push(DetailVC())   // push onto the stack
pop()              // return to previous
popToRoot()        // return to root
```

Or replace the entire stack:

```swift
stage?.setRoot(HomeVC())
```

### 3. Subclass `StageVC`

`StageVC` is intentionally minimal — it owns only the navigation stack and animation engine. Subclass it to add your app's chrome:

```swift
class AppStageVC: StageVC {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        setRoot(HomeVC())
    }
}
```

## Prop Options

Props support two kinds of off-screen placement:

**Direction-based** — the view slides fully off a screen edge:

```swift
Prop(view, from: .top)
Prop(view, from: .bottomRight, delay: 0.05)
```

Available directions: `.top`, `.bottom`, `.left`, `.right`, `.topLeft`, `.topRight`, `.bottomLeft`, `.bottomRight`

**Custom transform** — any `CGAffineTransform` for effects like scale-to-zero:

```swift
Prop(view, transform: .init(scaleX: 0, y: 0))
```

## Lifecycle Hooks

`Stageable` provides two optional hooks around transitions:

| Method | Timing |
|---|---|
| `prepareForEntrance()` | Called after layout, before animations begin. Configure initial state here. |
| `didFinishEntrance()` | Called after all entrance animations complete. Start post-transition work here. |

## Files

| File | Purpose |
|---|---|
| `StageVC.swift` | Container view controller — navigation stack and animation engine |
| `Prot+Stageable.swift` | `Stageable` protocol and navigation convenience methods |
| `Prop.swift` | Declarative description of an animated view element |
