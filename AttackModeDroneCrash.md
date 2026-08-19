# Attack Mode — Drone Crash (QGroundControl Customization)

This document is a **step-by-step guide to re-implement the Attack Mode feature from scratch** on
any QGroundControl checkout. Attack Mode lets the operator click a target on the Fly View map and
have the drone either:

1. **Drop a payload** on the target (release a gripper when the drone is inside a "drop cone"
   above the target), or
2. **Crash into the target** (kamikaze / dive-bomb mode): the drone cruises to the target, dives to
   ground level when within `attackDiveStartDistance`, and force-disarms at
   `attackCrashDisarmAltitude` to crash on top of the target.

Before either of those triggers, two pre-navigation gates make sure the drone only engages when it
is within range and heading roughly toward the target.

> **Prerequisite firmware behavior (forked `PX4FirmwarePlugin::guidedModeGotoLocation`).**
> This feature relies on the fork's PX4 guided goto, which sends `MAV_CMD_DO_REPOSITION` with
> `param2 = MAV_DO_REPOSITION_FLAGS_CHANGE_MODE` and **`param7 = vehicle altitude (AMSL)`, not the
> target altitude**. Stock QGC has different PX4 behavior, so reproduce that first if you start
> from an unmodified checkout. See [Step 8](#8-firmware-requirements-px4-guidedmodegotolocation).

---

## Table of Contents

- [1. Architecture Overview](#1-architecture-overview)
- [2. Files Changed](#2-files-changed)
- [3. Step 1 — Add configuration properties to `Vehicle.h`](#3-step-1--add-configuration-properties-to-vehicleh)
- [4. Step 2 — Add the private state and helper declarations](#4-step-2--add-the-private-state-and-helper-declarations)
- [5. Step 3 — Implement the property setters in `Vehicle.cc`](#5-step-3--implement-the-property-setters-in-vehiclecc)
- [6. Step 4 — The drop-cone elevation check](#6-step-4--the-drop-cone-elevation-check)
- [7. Step 5 — `beginAttackEngagement` and the engagement lifecycle](#7-step-5--beginattackengagement-and-the-engagement-lifecycle)
- [8. Step 6 — `_attackEvaluateEngagement` (drop release + crash mode)](#8-step-6--_attackevaluateengagement-drop-release--crash-mode)
- [9. Step 7 — The Fly View UI panel (`FlyViewMap.qml`)](#9-step-7--the-fly-view-ui-panel-flyviewmapqml)
- [10. Step 8 — Firmware requirements: PX4 `guidedModeGotoLocation`](#10-step-8--firmware-requirements-px4-guidedmodegotolocation)
- [11. Gotchas Discovered (read before testing)](#11-gotchas-discovered-read-before-testing)
- [12. Build & Test](#12-build--test)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  FlyViewMap.qml (mapClickDropPanel)                                          │
│   ├─ Attack config rows (checkboxes + fields) → Vehicle Q_PROPERTYs          │
│   ├─ "Enter Attack Mode"  → Vehicle::beginAttackEngagement(mapClickCoord)    │
│   ├─ "Cancel Attack Mode" → Vehicle::cancelAttackEngagement()                │
│   └─ Live status box + "Payload released" / "Drone crashed at target" banner │
└──────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Vehicle (Vehicle.h / Vehicle.cc)                                             │
│   beginAttackEngagement(target)                                               │
│    ├─ Pre-nav RANGE gate  (distance > attackMaxRange       → refuse)          │
│    ├─ Pre-nav HEADING gate(angular diff > attackMaxHeadingAngle → refuse)     │
│    ├─ If a DO_REPOSITION is still pending (MavCommandQueue duplicate guard)   │
│    │    → start engagement, defer reposition send until pending clears        │
│    ├─ guidedModeGotoLocation(target)   ← sends MAV_CMD_DO_REPOSITION          │
│    ├─ connect coordinateChanged / heading rawValueChanged → _attackEvaluate…  │
│   _attackEvaluateEngagement()   (every position/heading change)               │
│    ├─ CRASH MODE: within dive start distance → dive DO_REPOSITION to ground   │
│    │    → at crash disarm altitude → force-disarm (param2 = 21196)            │
│    └─ DROP MODE: inside drop cone → sendGripperAction(GRIPPER_ACTION_RELEASE) │
└──────────────────────────────────────────────────────────────────────────────┘
```

State machine (drop mode):

| State                          | Set where                                             | Transitions to |
|--------------------------------|-------------------------------------------------------|----------------|
| Idle (`_attackEngagementActive=false`) | init                                             | engaged (begin) |
| Engaged, cruising              | `beginAttackEngagement`                              | release / cancel |
| Released (`_attackReleaseExecuted=true`) | `_attackEvaluateEngagement` (drop cone met) | idle |

Crash mode adds an extra `_attackCrashDiving` flag (cruise → diving → crashed).

## 2. Files Changed

| File                                | What was added |
|-------------------------------------|----------------|
| `src/Vehicle/Vehicle.h`             | 11 config `Q_PROPERTY`s + 4 status `Q_PROPERTY`s, setters/getters, 5 signals, 4 private helpers, ~10 members |
| `src/Vehicle/Vehicle.cc`            | setters, drop-cone check, engagement lifecycle, crash/dive logic, pending-reposition retry |
| `src/FlyView/FlyViewMap.qml`        | "Attack Checks" section inside `mapClickDropPanel`: config rows, Enter/Cancel buttons, live status box, banners |
| `src/FirmwarePlugin/PX4/PX4FirmwarePlugin.cc` | *(pre-existing fork)* `guidedModeGotoLocation` sends `MAV_CMD_DO_REPOSITION` with CHANGE_MODE flag + vehicle altitude |

## 3. Step 1 — Add configuration properties to `Vehicle.h`

All attack parameters are plain `Q_PROPERTY`s on `Vehicle` (no Fact plumbing needed since these are
GCS-side settings, not vehicle parameters — but note the Golden Rule from AGENTS.md: *vehicle*
parameters must flow through Facts; these are UI configuration, so a `Q_PROPERTY` with a `NOTIFY`
signal is the right pattern). Insert a block like this (marked with `//FOR DOUBLE_TAP EXECUTE ACTION-ATTACK`):

```cpp
//FOR DOUBLE_TAP EXECUTE ACTION-ATTACK
Q_PROPERTY(bool attackRangeCheckEnabled
               READ attackRangeCheckEnabled
                   WRITE setAttackRangeCheckEnabled
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackMaxRange
               READ attackMaxRange
                   WRITE setAttackMaxRange
                       NOTIFY attackParametersChanged)
Q_PROPERTY(bool attackHeadingCheckEnabled
               READ attackHeadingCheckEnabled
                   WRITE setAttackHeadingCheckEnabled
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackMaxHeadingAngle
               READ attackMaxHeadingAngle
                   WRITE setAttackMaxHeadingAngle
                       NOTIFY attackParametersChanged)
Q_PROPERTY(bool attackElevationAngleCheckEnabled
               READ attackElevationAngleCheckEnabled
                   WRITE setAttackElevationAngleCheckEnabled
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackMaxElevationAngle
               READ attackMaxElevationAngle
                   WRITE setAttackMaxElevationAngle
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackDropRadius
               READ attackDropRadius
                   WRITE setAttackDropRadius
                       NOTIFY attackParametersChanged)
Q_PROPERTY(bool attackCrashModeEnabled
               READ attackCrashModeEnabled
                   WRITE setAttackCrashModeEnabled
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackDiveStartDistance
               READ attackDiveStartDistance
                   WRITE setAttackDiveStartDistance
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackCrashDisarmAltitude
               READ attackCrashDisarmAltitude
                   WRITE setAttackCrashDisarmAltitude
                       NOTIFY attackParametersChanged)
Q_PROPERTY(double attackCrashSpeed
               READ attackCrashSpeed
                   WRITE setAttackCrashSpeed
                       NOTIFY attackParametersChanged)

Q_PROPERTY(bool attackEngagementActive
               READ attackEngagementActive
                   NOTIFY attackEngagementActiveChanged)
Q_PROPERTY(double attackDistance
               READ attackDistance
                   NOTIFY attackEvaluationChanged)
Q_PROPERTY(bool attackRangeCheckPassed
               READ attackRangeCheckPassed
                   NOTIFY attackEvaluationChanged)
Q_PROPERTY(bool attackHeadingCheckPassed
               READ attackHeadingCheckPassed
                   NOTIFY attackEvaluationChanged)
Q_PROPERTY(bool attackElevationAngleCheckPassed
               READ attackElevationAngleCheckPassed
                   NOTIFY attackEvaluationChanged)
```

Inline getters:

```cpp
bool   attackRangeCheckEnabled() const { return _attackRangeCheckEnabled; }
double attackMaxRange() const { return _attackMaxRange; }
bool   attackHeadingCheckEnabled() const { return _attackHeadingCheckEnabled; }
double attackMaxHeadingAngle() const { return _attackMaxHeadingAngle; }
bool   attackElevationAngleCheckEnabled() const { return _attackElevationAngleCheckEnabled; }
double attackMaxElevationAngle() const { return _attackMaxElevationAngle; }
double attackDropRadius() const { return _attackDropRadius; }
bool   attackCrashModeEnabled() const { return _attackCrashModeEnabled; }
double attackDiveStartDistance() const { return _attackDiveStartDistance; }
double attackCrashDisarmAltitude() const { return _attackCrashDisarmAltitude; }
double attackCrashSpeed() const { return _attackCrashSpeed; }

bool   attackEngagementActive() const { return _attackEngagementActive; }
double attackDistance() const { return _attackDistance; }
bool   attackRangeCheckPassed() const { return _attackRangeCheckPassed; }
bool   attackHeadingCheckPassed() const { return _attackHeadingCheckPassed; }
bool   attackElevationAngleCheckPassed() const { return _attackElevationAngleCheckPassed; }
```

Setters (declarations):

```cpp
void setAttackRangeCheckEnabled(bool enabled);
void setAttackMaxRange(double range);
void setAttackHeadingCheckEnabled(bool enabled);
void setAttackMaxHeadingAngle(double angle);
void setAttackElevationAngleCheckEnabled(bool enabled);
void setAttackMaxElevationAngle(double angle);
void setAttackDropRadius(double radius);
void setAttackCrashModeEnabled(bool enabled);
void setAttackDiveStartDistance(double distance);
void setAttackCrashDisarmAltitude(double altitude);
void setAttackCrashSpeed(double speed);
```

QML-invokable lifecycle methods:

```cpp
Q_INVOKABLE bool beginAttackEngagement(const QGeoCoordinate& target);
Q_INVOKABLE void cancelAttackEngagement();
```

Signals:

```cpp
//DOUBLE TAP ATTACK SIGNAL
void attackParametersChanged();
void attackEngagementActiveChanged();
void attackEvaluationChanged();
void payloadReleased();
void attackCrashExecuted();
```

## 4. Step 2 — Add the private state and helper declarations

Members (with defaults — these are the parameter defaults you should document in the UI):

```cpp
bool   _attackRangeCheckEnabled           = true;
double _attackMaxRange                    = 500.0;
bool   _attackHeadingCheckEnabled         = true;
double _attackMaxHeadingAngle             = 15.0;
bool   _attackElevationAngleCheckEnabled  = true;
double _attackMaxElevationAngle           = 30.0;
double _attackDropRadius                  = 50.0;
bool   _attackCrashModeEnabled            = false;
double _attackDiveStartDistance           = 200.0;
double _attackCrashDisarmAltitude         = 3.0;
double _attackCrashSpeed                  = -1.0;   // -1 = leave groundspeed unchanged

bool   _attackCrashDiving                 = false;  // crash-mode dive in progress
QGeoCoordinate _attackTarget;
bool           _attackEngagementActive    = false;
bool           _attackReleaseExecuted     = false;
quint64        _attackLastLogMs           = 0;      // throttle the "holding" debug log
QMetaObject::Connection _attackHeadingConnection;   // stored so it can be disconnected

double _attackDistance                  = qQNaN();
bool   _attackRangeCheckPassed          = false;
bool   _attackHeadingCheckPassed        = false;
bool   _attackElevationAngleCheckPassed = false;
```

Private helpers:

```cpp
bool _attackElevationAngleCheck(const QGeoCoordinate& target);
void _attackStartEngagement(const QGeoCoordinate& target);
void _attackSendRepositionWithRetry(const QGeoCoordinate& target);
void _attackEvaluateEngagement();
void _attackDisconnectEngagementSignals();
```

## 5. Step 3 — Implement the property setters in `Vehicle.cc`

Every setter is the same shape: guard against no-op changes, then emit `attackParametersChanged`
so the QML bindings update.

```cpp
void Vehicle::setAttackRangeCheckEnabled(bool enabled)
{
    if (_attackRangeCheckEnabled != enabled) {
        _attackRangeCheckEnabled = enabled;
        emit attackParametersChanged();
    }
}

void Vehicle::setAttackMaxRange(double range)
{
    if (!qFuzzyCompare(_attackMaxRange, range)) {
        _attackMaxRange = range;
        emit attackParametersChanged();
    }
}
```

Apply the same pattern to the other 9 setters (`setAttackHeadingCheckEnabled`,
`setAttackMaxHeadingAngle`, `setAttackElevationAngleCheckEnabled`, `setAttackMaxElevationAngle`,
`setAttackDropRadius`, `setAttackCrashModeEnabled`, `setAttackDiveStartDistance`,
`setAttackCrashDisarmAltitude`, `setAttackCrashSpeed`).

> Add `#include <QtMath>` at the top of `Vehicle.cc` for `qAtan2`/`qRadiansToDegrees` used by the
> elevation check.

## 6. Step 4 — The drop-cone elevation check

The elevation check decides *when* the payload is released. Two modes:

- **Drop cone** (`attackElevationAngleCheckEnabled == true`): release when the target is within
  `attackMaxElevationAngle` of directly below the drone. The angle from the vertical is
  `atan2(horizontalDistance, |altitudeDifference|)` — `0°` means directly above the target. A larger
  altitude difference widens the usable cone at a given angle, so the drop point scales with
  flight altitude.
- **Fixed drop radius** (`attackElevationAngleCheckEnabled == false`, or when there is no usable
  altitude difference): release once `distance <= attackDropRadius`.

```cpp
bool Vehicle::_attackElevationAngleCheck(const QGeoCoordinate& target)
{
    if (!coordinate().isValid() || !target.isValid()) {
        return false;
    }
    const double distance = coordinate().distanceTo(target);
    if (qIsNaN(distance)) {
        return false;
    }
    if (!_attackElevationAngleCheckEnabled) {
        // Elevation check disabled: release once the vehicle reaches the fixed drop radius.
        return distance <= _attackDropRadius;
    }
    // Drop cone check
    double targetAltitude = target.altitude();
    if (qIsNaN(targetAltitude)) {
        targetAltitude = coordinate().altitude();      // fallback: vehicle altitude
    }
    const double vehicleAltitude = coordinate().altitude();
    if (qIsNaN(targetAltitude) || qIsNaN(vehicleAltitude)) {
        return false;
    }
    const double altitudeDifference = qAbs(vehicleAltitude - targetAltitude);
    if (qFuzzyIsNull(altitudeDifference)) {
        // No altitude difference (e.g. map-clicked target): the cone degenerates,
        // so fall back to the fixed drop radius.
        return distance <= _attackDropRadius;
    }
    const double verticalAngle = qRadiansToDegrees(qAtan2(distance, altitudeDifference));
    return verticalAngle <= _attackMaxElevationAngle;
}
```

## 7. Step 5 — `beginAttackEngagement` and the engagement lifecycle

### 7.1 Pre-navigation gates (range + heading)

These run **once**, synchronously, at the start of `beginAttackEngagement`. If a gate fails, show an
error and `return false` — the drone must not move.

```cpp
bool Vehicle::beginAttackEngagement(const QGeoCoordinate& target)
{
    if (!target.isValid()) {
        return false;
    }
    if (!coordinate().isValid()) {
        return false;
    }

    // Pre-navigation range gate
    if (_attackRangeCheckEnabled) {
        const double distance = coordinate().distanceTo(target);
        if (!qIsNaN(distance) && distance > _attackMaxRange) {
            QGC::showAppMessage(tr("Target is %1 m away, beyond the configured attack range of %2 m.")
                                .arg(qRound(distance)).arg(qRound(_attackMaxRange)));
            return false;
        }
    }

    // Pre-navigation heading gate
    if (_attackHeadingCheckEnabled) {
        const double headingValue = heading()->rawValue().toDouble();
        const double bearing = coordinate().azimuthTo(target);
        double angularDifference = qAbs(bearing - headingValue);
        if (angularDifference > 180.0) {
            angularDifference = 360.0 - angularDifference;
        }
        if (qIsNaN(headingValue) || qIsNaN(bearing) || angularDifference > _attackMaxHeadingAngle) {
            QGC::showAppMessage(tr("Vehicle heading (%1\u00B0) not aligned with target bearing (%2\u00B0), allowed within %3\u00B0.")
                                .arg(qRound(headingValue)).arg(qRound(bearing)).arg(qRound(_attackMaxHeadingAngle)));
            return false;
        }
    }
    // ... continued below
```

### 7.2 Handling a pending `MAV_CMD_DO_REPOSITION` (important!)

`MavCommandQueue` refuses to send a **second** `MAV_CMD_DO_REPOSITION` while a previous one is
still awaiting its ACK (see `MavCommandQueue.cc`, the "duplicate command" guard). Without handling
this, a quick retry (e.g. after changing a parameter) pops up
*"Unable to send command: Waiting on previous response to same command."* while the drone is still
being driven by the earlier command — an apparently contradictory "error but drone attacking".

The fix: detect the pending command with `isMavCommandPending(...)`; if it is pending, start the
engagement immediately and **defer the reposition send** until the pending command clears.

```cpp
    // MavCommandQueue refuses to send a second DO_REPOSITION while a previous one is
    // still awaiting its ack (e.g. from a prior attack, go-to-location or pause). Start
    // the engagement and defer sending the reposition until the pending command clears.
    if (isMavCommandPending(_defaultComponentId, MAV_CMD_DO_REPOSITION)) {
        _attackStartEngagement(target);
        _attackSendRepositionWithRetry(target);
        return true;
    }

    if (!guidedModeGotoLocation(target)) {
        return false;
    }

    _attackStartEngagement(target);

    // Evaluate immediately so an engagement which starts already within range can release
    // without waiting for the next coordinate or heading update.
    _attackEvaluateEngagement();
    return true;
}
```

### 7.3 `_attackStartEngagement`

Sets the state, connects the two evaluation triggers, and emits `attackEngagementActiveChanged`.
Note: the immediate `_attackEvaluateEngagement()` is **not** called here — callers decide when to
evaluate (the deferred-send path evaluates only after the reposition is actually sent).

```cpp
void Vehicle::_attackStartEngagement(const QGeoCoordinate& target)
{
    if (_attackEngagementActive) {
        _attackDisconnectEngagementSignals();
    }

    _attackTarget = target;
    _attackReleaseExecuted = false;
    _attackEngagementActive = true;
    _attackLastLogMs = 0;
    _attackDistance = qQNaN();
    _attackRangeCheckPassed = true;
    _attackHeadingCheckPassed = true;
    _attackElevationAngleCheckPassed = false;
    _attackCrashDiving = false;

    qCDebug(VehicleLog) << "beginAttackEngagement: navigating to target" << "target" << target
                        << "rangeCheckEnabled" << _attackRangeCheckEnabled << "maxRange" << _attackMaxRange
                        << "headingCheckEnabled" << _attackHeadingCheckEnabled << "maxHeadingAngle" << _attackMaxHeadingAngle
                        << "elevationCheckEnabled" << _attackElevationAngleCheckEnabled << "maxElevationAngle" << _attackMaxElevationAngle
                        << "dropRadius" << _attackDropRadius
                        << "crashModeEnabled" << _attackCrashModeEnabled
                        << "diveStartDistance" << _attackDiveStartDistance
                        << "crashDisarmAltitude" << _attackCrashDisarmAltitude
                        << "crashSpeed" << _attackCrashSpeed;

    connect(this, &Vehicle::coordinateChanged, this, &Vehicle::_attackEvaluateEngagement);
    _attackHeadingConnection = connect(heading(), &Fact::rawValueChanged, this,
                                       [this](const QVariant&) { _attackEvaluateEngagement(); });
    emit attackEngagementActiveChanged();
}
```

### 7.4 `_attackSendRepositionWithRetry`

Polls (every 100 ms, up to 1.5 s) until the pending `DO_REPOSITION` clears, then sends the real
reposition. It skips the send if the engagement was cancelled or re-targeted while waiting, and
rolls the engagement back if `guidedModeGotoLocation` fails. Uses `QTimer::singleShot` with a
`shared_ptr`-held `std::function` so the deferred lambda is kept alive across polls.

```cpp
void Vehicle::_attackSendRepositionWithRetry(const QGeoCoordinate& target)
{
    constexpr int kMaxWaitMs = 1500;
    constexpr int kPollMs = 100;

    auto waitedMs = std::make_shared<int>(0);
    auto waitAndSend = std::make_shared<std::function<void()>>();
    *waitAndSend = [this, target, waitedMs, waitAndSend]() {
        if (!isMavCommandPending(_defaultComponentId, MAV_CMD_DO_REPOSITION)) {
            // Skip sending if the engagement was cancelled or re-targeted while we waited.
            if (_attackEngagementActive && _attackTarget == target) {
                if (guidedModeGotoLocation(target)) {
                    _attackEvaluateEngagement();
                } else {
                    _attackEngagementActive = false;
                    _attackReleaseExecuted = false;
                    _attackCrashDiving = false;
                    _attackDisconnectEngagementSignals();
                    emit attackEngagementActiveChanged();
                }
            }
            return;
        }
        *waitedMs += kPollMs;
        if (*waitedMs >= kMaxWaitMs) {
            QGC::showAppMessage(
                tr("Unable to send attack reposition command: a previous command "
                   "is still being processed. Please try again."));
            return;
        }
        QTimer::singleShot(kPollMs, this, *waitAndSend);
    };
    (*waitAndSend)();
}
```

### 7.5 Cancel

```cpp
void Vehicle::cancelAttackEngagement()
{
    if (!_attackEngagementActive) {
        return;
    }
    _attackEngagementActive = false;
    _attackReleaseExecuted = false;
    _attackCrashDiving = false;
    _attackDisconnectEngagementSignals();
    if (_vehicleSupports->pauseVehicle()) {
        pauseVehicle();
        qCWarning(VehicleLog) << "cancelAttackEngagement: engagement cancelled, vehicle paused";
    } else {
        qCWarning(VehicleLog) << "cancelAttackEngagement: engagement cancelled (pause not supported)";
    }
    emit attackEngagementActiveChanged();
}
```

`pauseVehicle()` (PX4) sends `MAV_CMD_DO_REPOSITION` with NaN coords + `CHANGE_MODE`, which makes
PX4 hold position.

### 7.6 Signal cleanup

```cpp
void Vehicle::_attackDisconnectEngagementSignals()
{
    disconnect(this, &Vehicle::coordinateChanged, this, &Vehicle::_attackEvaluateEngagement);
    if (_attackHeadingConnection) {
        disconnect(_attackHeadingConnection);
        _attackHeadingConnection = {};
    }
}
```

## 8. Step 6 — `_attackEvaluateEngagement` (drop release + crash mode)

Called on every `coordinateChanged` / heading change while engaged. Recomputes the status
properties, then runs the **crash-mode branch first** (the drop cone shrinks during descent, so the
crash path must be evaluated independently), then the drop release.

```cpp
void Vehicle::_attackEvaluateEngagement()
{
    if (!_attackEngagementActive || _attackReleaseExecuted) {
        return;
    }
    if (!coordinate().isValid() || !_attackTarget.isValid()) {
        return;
    }

    const double distance = coordinate().distanceTo(_attackTarget);
    if (qIsNaN(distance)) {
        return;
    }

    _attackDistance = distance;
    _attackElevationAngleCheckPassed = _attackElevationAngleCheck(_attackTarget);
    emit attackEvaluationChanged();

    const quint64 nowMs = static_cast<quint64>(QDateTime::currentMSecsSinceEpoch());

    // ---- Crash (kamikaze) mode: the drone itself is the payload. ----
    if (_attackCrashModeEnabled) {
        if (_attackCrashDiving) {
            const double altRel = altitudeRelative()->rawValue().toDouble();
            if (!qIsNaN(altRel) && altRel <= _attackCrashDisarmAltitude) {
                _attackReleaseExecuted = true;
                _attackEngagementActive = false;
                _attackCrashDiving = false;
                _attackDisconnectEngagementSignals();
                sendMavCommand(_defaultComponentId, MAV_CMD_COMPONENT_ARM_DISARM, true, 0.0f, 21196.0f);
                // ^ 21196.0f = magic number for forced in-flight disarm (NOT 2989, which is
                //   the force-ARM value; PX4 only honours 21196 for in-flight disarming)
                qCWarning(VehicleLog) << "_attackEvaluateEngagement: drone crashed at target"
                                      << "target" << _attackTarget
                                      << "vehicle" << coordinate()
                                      << "altitudeRelative" << altRel
                                      << "crashDisarmAltitude" << _attackCrashDisarmAltitude;
                emit attackCrashExecuted();
                emit attackEngagementActiveChanged();
            }
            return;
        }

        if (distance <= _attackDiveStartDistance) {
            _attackCrashDiving = true;
            const double groundAMSL = homePosition().isValid() ? homePosition().altitude() : qQNaN();
            if (!qIsNaN(groundAMSL)) {
                sendMavCommand(_defaultComponentId,
                               MAV_CMD_DO_REPOSITION,
                               true,    // show error if fails
                               static_cast<float>(_attackCrashSpeed),
                               MAV_DO_REPOSITION_FLAGS_CHANGE_MODE,
                               0.0f,
                               qQNaN(),
                               static_cast<float>(_attackTarget.latitude()),
                               static_cast<float>(_attackTarget.longitude()),
                               static_cast<float>(groundAMSL));
                qCWarning(VehicleLog) << "_attackEvaluateEngagement: crash mode, diving to target at ground level"
                                      << "target" << _attackTarget
                                      << "distance" << distance
                                      << "diveStartDistance" << _attackDiveStartDistance
                                      << "groundAMSL" << groundAMSL
                                      << "crashSpeed" << _attackCrashSpeed;
            } else {
                qCWarning(VehicleLog) << "_attackEvaluateEngagement: crash mode, home altitude unknown, cannot dive";
            }
        }
        return;
    }

    // ---- Drop mode: release the payload when the drop cone is met. ----
    if (_attackElevationAngleCheckPassed) {
        _attackReleaseExecuted = true;
        _attackEngagementActive = false;
        _attackDisconnectEngagementSignals();
        qCWarning(VehicleLog) << "_attackEvaluateEngagement: drop conditions met, releasing payload"
                              << "target" << _attackTarget
                              << "vehicle" << coordinate()
                              << "distance" << distance
                              << "elevationCheckEnabled" << _attackElevationAngleCheckEnabled
                              << "maxElevationAngle" << _attackMaxElevationAngle
                              << "dropRadius" << _attackDropRadius;
        sendGripperAction(GRIPPER_ACTION_RELEASE);
        emit payloadReleased();
        emit attackEngagementActiveChanged();
    } else if (nowMs - _attackLastLogMs >= 2000) {
        _attackLastLogMs = nowMs;
        qCDebug(VehicleLog) << "_attackEvaluateEngagement: drop conditions not met, holding release"
                            << "target" << _attackTarget
                            << "vehicle" << coordinate()
                            << "distance" << distance;
    }
}
```

## 9. Step 7 — The Fly View UI panel (`FlyViewMap.qml`)

All UI lives in the existing `mapClickDropPanel` (`DropPanel` in `FlyViewMap.qml`). Add, after the
existing guided-action buttons (Go to location / Orbit / ROI / Set home / Set Estimator Origin):

### 9.1 Panel state + signal connections

```qml
property var mapClickCoord
property bool releaseShown: false
property bool droneCrashed: false

Connections {
    target: _activeVehicle
    function onPayloadReleased() {
        mapClickDropPanel.releaseShown = true
    }
    function onAttackCrashExecuted() {
        mapClickDropPanel.droneCrashed = true
    }
}
```

### 9.2 Configuration rows

A bold `"Attack Checks"` label, then one `RowLayout` per parameter: `QGCCheckBox` + `TextField`
(with `DoubleValidator`) + unit `QGCLabel`. For example:

```qml
QGCLabel {
    Layout.fillWidth: true
    text: qsTr("Attack Checks")
    visible: _activeVehicle !== null
    font.bold: true
}

RowLayout {
    Layout.fillWidth: true
    visible: _activeVehicle !== null
    QGCCheckBox {
        Layout.fillWidth: true
        text: qsTr("Range")
        checked: _activeVehicle.attackRangeCheckEnabled
        onClicked: _activeVehicle.attackRangeCheckEnabled = checked
    }
    TextField {
        Layout.preferredWidth: 90
        text: _activeVehicle.attackMaxRange
        validator: DoubleValidator { bottom: 0; notation: DoubleValidator.StandardNotation }
        onEditingFinished: if (acceptableInput) _activeVehicle.attackMaxRange = parseFloat(text)
    }
    QGCLabel {
        Layout.alignment: Qt.AlignVCenter
        text: qsTr("m")
    }
}
```

Repeat for: Heading (`attackMaxHeadingAngle`, `DoubleValidator { bottom: 0; top: 180 }`, unit `°`),
Elevation (`attackMaxElevationAngle`, unit `°`), Drop radius (`attackDropRadius`, unit `m`),
**Drone crash mode** (`attackCrashModeEnabled` checkbox + Crash height `attackCrashDisarmAltitude`
in m), Dive start distance (`attackDiveStartDistance`, m), and Dive speed (`attackCrashSpeed`, m/s,
`-1` = no change).

### 9.3 Enter / Cancel buttons

```qml
QGCButton {
    Layout.fillWidth: true
    text: qsTr("Enter Attack Mode")
    visible: _activeVehicle !== null
    enabled: !_activeVehicle.attackEngagementActive
    onClicked: {
        _activeVehicle.beginAttackEngagement(mapClickCoord)
    }
}

QGCButton {
    Layout.fillWidth: true
    text: qsTr("Cancel Attack Mode")
    visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
    onClicked: {
        mapClickDropPanel.close()
        _activeVehicle.cancelAttackEngagement()
    }
}
```

### 9.4 Live status box + banner

A `Rectangle` shown while engaged or after a release/crash, with ✓/✗ rows for Range, Heading and
Elevation, and a bold banner at the bottom. The banner color/text flips between release (lime,
"Payload released") and crash (red, "Drone crashed at target"):

```qml
Rectangle {
    id: attackStatusRect
    Layout.fillWidth: true
    visible: _activeVehicle !== null &&
             (_activeVehicle.attackEngagementActive || mapClickDropPanel.releaseShown || mapClickDropPanel.droneCrashed)
    color: mapClickDropPanel.droneCrashed ? "#20a03030" : (mapClickDropPanel.releaseShown ? "#2030a030" : "#20303030")
    radius: 4
    implicitHeight: attackStatusCol.implicitHeight + ScreenTools.defaultFontPixelWidth

    ColumnLayout {
        id: attackStatusCol
        anchors.fill: parent
        anchors.margins: ScreenTools.defaultFontPixelWidth / 2
        spacing: ScreenTools.defaultFontPixelHeight / 4

        QGCLabel { text: qsTr("Attack status"); font.bold: true }

        RowLayout {   // Range
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel { text: qsTr("Range") }
            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: _activeVehicle.attackRangeCheckPassed ? qsTr("\u2713") : qsTr("\u2717")
                color: _activeVehicle.attackRangeCheckPassed ? "lime" : "red"
            }
        }
        RowLayout {   // distance value
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel {
                Layout.fillWidth: true
                text: qsTr("%1 / %2 m").arg(_activeVehicle.attackDistance.toFixed(0)).arg(_activeVehicle.attackMaxRange.toFixed(0))
            }
        }
        RowLayout {   // Heading — same ✓/✗ pattern
            ...
        }
        RowLayout {   // Elevation — same ✓/✗ pattern
            ...
        }

        QGCLabel {
            Layout.fillWidth: true
            text: mapClickDropPanel.droneCrashed ? qsTr("Drone crashed at target") : qsTr("Payload released")
            visible: mapClickDropPanel.releaseShown || mapClickDropPanel.droneCrashed
            font.bold: true
            color: mapClickDropPanel.droneCrashed ? "red" : "lime"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
```

## 10. Step 8 — Firmware requirements: PX4 `guidedModeGotoLocation`

This feature depends on the fork's PX4 guided goto. If you start from stock QGC, apply this to
`PX4FirmwarePlugin::guidedModeGotoLocation`:

- Send `MAV_CMD_DO_REPOSITION` with:
  - `param1 = -1.0` (don't change groundspeed)
  - `param2 = MAV_DO_REPOSITION_FLAGS_CHANGE_MODE` (switch to Auto/Reposition)
  - `param3 = 0.0`, `param4 = NAN`
  - `param5/param6` = target lat/lon
  - **`param7 = vehicle->altitudeAMSL()` (the drone's CURRENT altitude, not the target's)** — PX4
    ignores the target altitude in param7 and flies at the current altitude when repositioning.
- Prefer `sendMavCommandInt` (`MAV_CMD_DO_REPOSITION`, frame `MAV_FRAME_GLOBAL`) when the vehicle
  reports `MAV_PROTOCOL_CAPABILITY_COMMAND_INT`, else `sendMavCommand`.

## 11. Gotchas Discovered (read before testing)

1. **"Reposition command not supported"** (`MavCommandQueue.cc` — `MAV_RESULT_UNSUPPORTED`):
   - **MockLink** ACKs *every* command as `MAV_RESULT_UNSUPPORTED` (and its position is static,
     heading sinusoidal), so this feature can never appear to work there. **Test against real
     PX4 SITL.**
   - Stock QGC's PX4 `guidedModeGotoLocation` has the same failure mode; the fork version (Step 8)
     fixes it.
2. **Force-disarm magic number:** `MAV_CMD_COMPONENT_ARM_DISARM` with `param2 = 21196` forces an
   in-flight disarm and bypasses PX4's "not landed" guard. `2989` is the force-**arm** value and is
   **ignored for disarm** — using it produces `Disarming denied: not landed` and QGC retries until
   "Giving up sending command after max retries". QGC's own `emergencyStop()` already uses `21196`.
3. **Duplicate-command guard:** MavCommandQueue drops a second `MAV_CMD_DO_REPOSITION` while one is
   pending and shows *"Unable to send command: Waiting on previous response to same command."* —
   handle it explicitly (Step 7.2) or retries after changing parameters will appear to fail while
   the drone keeps flying (because the *earlier* reposition is still driving it).
4. **Logging visibility:** QGC hides `qCDebug`/`qCInfo` for categories unless enabled
   (`-logging VehicleLog` on the command line, or Settings → Logging). Use `qCWarning(VehicleLog)`
   for one-shot lifecycle events you want visible by default (release, cancel, dive, crash) and
   keep the 2-second-rate-limited "holding release" loop at `qCDebug(VehicleLog)`.
5. **PX4 disarm in AUTO:** after the dive `DO_REPOSITION` with `CHANGE_MODE`, PX4 is in Auto/Reposition.
   A non-forced disarm is refused while airborne — this is why the crash uses the forced magic value.
6. **`guidedModeChangeAltitude` / pause require a valid home position** on PX4 — the crash dive
   uses `homePosition().altitude()` for the ground AMSL; if home is unknown the dive is skipped with
   a warning.

## 12. Build & Test

```bash
just configure          # first time
cmake --build build --target QGroundControl
# format/lint
clang-format --dry-run src/Vehicle/Vehicle.{h,cc} src/FlyView/FlyViewMap.qml
$QT/bin/qmllint --bare src/FlyView/FlyViewMap.qml
```

Test matrix (against a real PX4 SITL):

| Scenario | Setup | Expected |
|----------|-------|----------|
| Gate refuses | Target out of range / drone not facing it | Error popup, drone does **not** move, no engagement |
| Retry after gate fix | Change `attackMaxRange` / heading, click Enter again | Drone flies to target, **no** "same command running" popup |
| Drop release | Elevation check ON, no crash mode, fly over target | Gripper releases when inside the drop cone, green "Payload released" banner |
| Drop radius | Elevation check OFF | Releases when within `attackDropRadius` |
| Crash mode | Crash ON, dive distance 200 m | Dives to ground at `attackCrashSpeed`, force-disarms at `attackCrashDisarmAltitude`, red "Drone crashed at target" banner |
| Cancel | Cancel during cruise | Drone pauses (holds position), engagement ends |

Run with `-logging VehicleLog` to see the detailed hold/release loop in the debug log.
