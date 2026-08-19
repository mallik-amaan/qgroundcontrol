# Fly View — Telemetry & Compass Show/Hide Toggle (QGroundControl Customization)

This document is a **step-by-step guide to re-implement the show/hide toggle for the Fly View
bottom-right widget row** from scratch on any QGroundControl checkout. The bottom-right row
contains the **telemetry value bar** (altitude / speed / etc.) and the **instrument panel**
(compass & attitude widget). A small clickable **eye icon** cycles the row through three states:

| State | `_showCompassAndTelemtery` | Behavior |
|-------|----------------------------|----------|
| 0 | `0` | Show **both** widgets, **with** their backgrounds |
| 1 | `1` | Show **both** widgets, **without** backgrounds (transparent) |
| 2 | `2` | **Hide** the whole row |

Clicking the icon cycles `0 -> 1 -> 2 -> 0`. The icon itself swaps between
`view-show.svg` / `view-hide.svg` to reflect the current visibility.

---

## Table of Contents

- [1. Architecture Overview](#1-architecture-overview)
- [2. Files Changed](#2-files-changed)
- [3. Step 1 — The 3-state toggle + eye icon (`FlyViewWidgetLayer.qml`)](#3-step-1--the-3-state-toggle--eye-icon-flyviewwidgetlayerqml)
- [4. Step 2 — Forward the flag through the row layout](#4-step-2--forward-the-flag-through-the-row-layout)
- [5. Step 3 — Telemetry bar background (`TelemetryValuesBar.qml`)](#5-step-3--telemetry-bar-background-telemetryvaluesbarqml)
- [6. Step 4 — Instrument panel background (3 compass widgets)](#6-step-4--instrument-panel-background-3-compass-widgets)
- [7. Step 5 — Push the flag into the loaded widget (`SelectableControl.qml`)](#7-step-5--push-the-flag-into-the-loaded-widget-selectablecontrolqml)
- [8. Gotchas Discovered (read before testing)](#8-gotchas-discovered-read-before-testing)
- [9. Build & Test](#9-build--test)

---

## 1. Architecture Overview

The bottom-right row is assembled from two reusable pieces:

- `FlyViewBottomRightRowLayout` (a `RowLayout`) holds:
  - `TelemetryValuesBar` — renders the `HorizontalFactValueGrid` (altitude/speed/etc. Facts).
  - `FlyViewInstrumentPanel` — a `SelectableControl` that **loads** the compass/attitude widget.
- The compass widget itself is loaded **dynamically** by `SelectableControl`'s `Loader` from a
  Fact, `QGroundControl.settingsManager.flyViewSettings.instrumentQmlFile2`. That Fact's enum
  *values* are QML file paths (`src/Settings/FlyView.SettingsGroup.json`):

  ```
  Integrated Compass & Attitude -> qrc:/qml/QGroundControl/FlightMap/Widgets/IntegratedCompassAttitude.qml
  Horizontal Compass & Attitude -> qrc:/qml/QGroundControl/FlightMap/Widgets/HorizontalCompassAttitude.qml
  Large Vertical                -> qrc:/qml/QGroundControl/FlightMap/Widgets/VerticalCompassAttitude.qml
  ```

  Right-click (desktop) / long-press (mobile) on the instrument panel opens the selection UI
  (`SelectableControl`'s `background` property) to switch between these variants.

A single integer property, `_showCompassAndTelemtery`, lives in `FlyViewWidgetLayer.qml` and drives
the whole feature. From there a boolean `showBackground` is plumbed down the widget tree:

```
FlyViewWidgetLayer
  └─ bottomRightRowLayout.showBackground = (_showCompassAndTelemtery === 0)
       ├─ TelemetryValuesBar.showBackground
       └─ FlyViewInstrumentPanel.showBackground   (SelectableControl)
            └─ innerControl.showBackground         (pushed via Loader.onLoaded)
                 ├─ IntegratedCompassAttitude.qml
                 ├─ HorizontalCompassAttitude.qml
                 └─ VerticalCompassAttitude.qml
```

When `showBackground == false`, each widget's background fill becomes transparent while the widget
content stays fully visible.

---

## 2. Files Changed

| File | Change |
|------|--------|
| `src/FlyView/FlyViewWidgetLayer.qml` | 3-state int, eye icon, `visible`/`showBackground` bindings, local `QGCPalette` |
| `src/FlyView/FlyViewBottomRightRowLayout.qml` | `showBackground` property; forward to telemetry bar + instrument panel |
| `src/FlyView/FlyViewInstrumentPanel.qml` | Forward `showBackground` to `SelectableControl` |
| `src/FlyView/TelemetryValuesBar.qml` | `showBackground` property; gate the background rect |
| `src/QmlControls/SelectableControl.qml` | `showBackground` property; push into `loader.item` on load |
| `src/FlightMap/Widgets/IntegratedCompassAttitude.qml` | `showBackground`; transparent compass-circle fill |
| `src/FlightMap/Widgets/HorizontalCompassAttitude.qml` | `showBackground`; transparent root fill |
| `src/FlightMap/Widgets/VerticalCompassAttitude.qml` | `showBackground`; transparent root fill |

No C++ changes and no new icon assets are required — `view-show.svg` / `view-hide.svg` already exist
in `resources/InstrumentValueIcons/` and are auto-registered by the CMake glob in
`src/QmlControls/CMakeLists.txt`.

---

## 3. Step 1 — The 3-state toggle + eye icon (`FlyViewWidgetLayer.qml`)

Add the state property and a local palette (so `qgcPal` always resolves):

```qml
property int    _showCompassAndTelemtery: 0
...
QGCPalette {
    id: qgcPal
}
```

Bind the bottom-right row to the state:

```qml
FlyViewBottomRightRowLayout {
    id:                 bottomRightRowLayout
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom:     parent.bottom
    spacing:            _layoutSpacing
    visible:            _showCompassAndTelemtery !== 2
    showBackground:     _showCompassAndTelemtery === 0
    property real bottomEdgeCenterInset:    height + _layoutMargin
}
```

Also free the bottom tool inset when the row is hidden (`_totalToolInsets`):

```qml
bottomEdgeCenterInset:  bottomRightRowLayout.visible ? bottomRightRowLayout.bottomEdgeCenterInset : 0
```

Add the clickable eye icon (anchored to the **top-right corner of the row widget**, not the screen
edge):

```qml
QGCColoredImage {
    id:                     bottomRightRowToggle
    anchors.bottom:         bottomRightRowLayout.top
    anchors.right:          bottomRightRowLayout.right
    anchors.bottomMargin:   _layoutMargin
    anchors.rightMargin:    _layoutMargin
    width:                  ScreenTools.minTouchPixels
    height:                 width
    mipmap:                 true
    sourceSize.width:       width
    fillMode:               Image.PreserveAspectFit
    color:                  qgcPal.text
    source:                 _showCompassAndTelemtery === 2
                              ? "qrc:/InstrumentValueIcons/view-hide.svg"
                              : "qrc:/InstrumentValueIcons/view-show.svg"

    QGCMouseArea {
        anchors.fill:   parent
        onClicked:      _showCompassAndTelemtery = _showCompassAndTelemtery >= 2 ? 0 : _showCompassAndTelemtery + 1
    }
}
```

> The `QGCColoredImage` is tinted through the `coloredsvg` image provider
> (`src/QmlControls/ColoredSvgImageProvider.cc`), which rasterizes the SVG and fills its alpha
> mask with `color`. The eye SVGs have a `viewBox` only (no `width`/`height`) — that is fine; the
> provider computes the display size from `requestedSize` and the intrinsic aspect ratio.

---

## 4. Step 2 — Forward the flag through the row layout

`src/FlyView/FlyViewBottomRightRowLayout.qml` — add a `showBackground` property and forward it to
**both** children:

```qml
RowLayout {
    id:                     _root
    property bool showBackground: true

    TelemetryValuesBar {
        Layout.alignment:       Qt.AlignBottom
        extraWidth:             instrumentPanel.extraValuesWidth
        settingsGroup:          factValueGrid.telemetryBarSettingsGroup
        specificVehicleForCard: null // Tracks active vehicle
        showBackground:         _root.showBackground
    }

    FlyViewInstrumentPanel {
        id:                 instrumentPanel
        Layout.alignment:   Qt.AlignBottom
        visible:            QGroundControl.corePlugin.options.flyView.showInstrumentPanel && _showSingleVehicleUI
        showBackground:     _root.showBackground
    }
}
```

`src/FlyView/FlyViewInstrumentPanel.qml` — forward into the `SelectableControl`:

```qml
SelectableControl {
    z:                      QGroundControl.zOrderWidgets
    selectionUIRightAnchor: true
    selectedControl:        QGroundControl.settingsManager.flyViewSettings.instrumentQmlFile2
    showBackground:         _root.showBackground
    property var  missionController:    _missionController
    property real extraInset:           innerControl.extraInset
    property real extraValuesWidth:     innerControl.extraValuesWidth
}
```

---

## 5. Step 3 — Telemetry bar background (`TelemetryValuesBar.qml`)

Add a `showBackground` property and gate the existing background `Rectangle`:

```qml
Item {
    id:             control
    ...
    property bool showBackground: true ///< Show the background rectangle
    ...
    Rectangle {
        id:         backgroundRect
        visible:    control.showBackground
        width:      control.width + extraWidth
        height:     control.height
        color:      qgcPal.window
        radius:     ScreenTools.defaultFontPixelWidth / 2
        opacity:    0.75
    }
}
```

---

## 6. Step 4 — Instrument panel background (3 compass widgets)

Add `property bool showBackground: true` to each widget and bind the fill color so it becomes
transparent when false. Geometry is preserved — only the visible fill is removed.

**`src/FlightMap/Widgets/IntegratedCompassAttitude.qml`** — the compass-circle `Rectangle`:

```qml
property bool showBackground: true
...
Rectangle {
    y:      _totalAttitudeSize
    width:  compassRadius * 2
    height: width
    radius: width / 2
    color:  showBackground ? qgcPal.window : "transparent"

    QGCCompassWidget {
        size:                       parent.width - compassBorder
        vehicle:                    control.vehicle
        usedByMultipleVehicleList:  control.usedByMultipleVehicleList
        anchors.centerIn:           parent
    }
}
```

**`src/FlightMap/Widgets/HorizontalCompassAttitude.qml`** — the root `Rectangle`:

```qml
Rectangle {
    ...
    color:  showBackground ? qgcPal.window : "transparent"
    ...
    property bool showBackground: true
}
```

**`src/FlightMap/Widgets/VerticalCompassAttitude.qml`** — the root `Rectangle`:

```qml
Rectangle {
    ...
    color:  showBackground ? QGroundControl.globalPalette.window : "transparent"
    ...
    property bool showBackground: true
}
```

---

## 7. Step 5 — Push the flag into the loaded widget (`SelectableControl.qml`)

`SelectableControl` must declare `showBackground` and forward it to the widget loaded by its
`Loader` (`innerControl`). The load is asynchronous, so push it in `onLoaded` as a live binding:

```qml
Control {
    id:             control
    ...
    property Fact selectedControl               ///< Fact whose values are the qml file for the control
    property bool selectionUIRightAnchor: false
    property var  innerControl:           loader.item
    property bool showBackground: true          ///< Forwarded to the loaded widget's background

    property bool _showSelectionUI: false
    ...
    contentItem: Item {
        implicitWidth:  loader.item.width
        implicitHeight: loader.item.height

        Loader {
            id:     loader
            source: selectedControl ? selectedControl.rawValue : ""
            onLoaded: {
                if (item && ("showBackground" in item)) {
                    item.showBackground = Qt.binding(function() { return control.showBackground })
                }
            }
        }
        ...
    }
}
```

The `"showBackground" in item` guard is defensive — all three instrument widgets declare it.

---

## 8. Gotchas Discovered (read before testing)

1. **`SelectableControl` MUST declare `property bool showBackground`.** If it is missing, the
   assignment in `FlyViewInstrumentPanel.qml` (`showBackground: _root.showBackground`) fails with
   *"Cannot assign to non-existent property"*, the `FlyViewInstrumentPanel` type becomes
   unavailable, and **the whole QGC app fails to start**:
   `FlyView -> FlyViewWidgetLayer -> FlyViewBottomRightRowLayout -> FlyViewInstrumentPanel`.
2. **Forward to BOTH children.** `FlyViewBottomRightRowLayout` must pass `showBackground` to
   `FlyViewInstrumentPanel` as well as `TelemetryValuesBar`, or the compass panel keeps its
   background in state 1.
3. **Icon placement uses the row widget, not the screen.** Anchor `anchors.right` to
   `bottomRightRowLayout.right` (the widget's right edge). Anchoring to `parent.right` puts the icon
   at the extreme right of the screen, far from the widget it controls.
4. **The eye SVGs already exist** (`resources/InstrumentValueIcons/view-show.svg` /
   `view-hide.svg`) and are auto-registered via the `*.svg` CMake glob in
   `src/QmlControls/CMakeLists.txt` — no `.qrc` edit or new asset is needed. Verify with
   `grep view-show build/.../src/QmlControls/.qt/rcc/instrument_value_icons.qrc`.
5. **The background is inside the loaded widgets, not `SelectableControl.background`.**
   `SelectableControl`'s `background` is only the right-click selection UI (lock button +
   `FactComboBox`). Removing it would delete the widget-switching feature, not the visual fill.
6. **Rebuild the target you actually launch.** `just build` / `cmake --build build` targets the
   `build/` tree; if you run a different build dir (e.g. `build/Desktop_Debug2`), rebuild that one,
   otherwise you run a stale binary with the old QML.

---

## 9. Build & Test

```bash
# Rebuild the target you actually launch (adjust to your build dir)
cmake --build build/Desktop_Debug2 --target QGroundControl

# Optional: lint the changed QML
just lint
```

Runtime check (Fly View):
- The eye icon sits at the **top-right corner of the bottom-right row**.
- Click it to cycle: **0** = both widgets with background → **1** = both widgets, no background →
  **2** = row hidden → back to **0**.
- Icon swaps between `view-show.svg` (visible) and `view-hide.svg` (hidden).