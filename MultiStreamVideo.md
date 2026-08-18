# Multi-Stream Video & Companion Features — QGroundControl Customization

This document describes, line by line, the customizations made to the **Stable_V5.1** branch of
QGroundControl to add:

1. **A second simultaneous video stream** (fully independent of the primary stream — own
   source, URL, receiver, pip/full-screen behavior).
2. **TCP click-to-target control** — a TCP client exposed to QML that sends click coordinates
   and custom messages from the video/plan view to an external server.
3. **AMAN sensor telemetry** — decoding of a custom MAVLink message
   (`MAVLINK_MSG_ID_AMAN_SENSOR_DATA`) and its live display in the Fly View.

It exists so that the same feature set can be reproduced on any other QGroundControl checkout,
and to explain *why* each file was touched.

---

## Table of Contents

- [1. Feature Overview & Architecture](#1-feature-overview--architecture)
- [2. Changed Files Summary](#2-changed-files-summary)
- [3. Feature A — Second Video Stream](#3-feature-a--second-video-stream)
  - [3.1 Settings (Video.SettingsGroup.json)](#31-settings-videosettingsgroupjson)
  - [3.2 Settings C++ (VideoSettings.h / VideoSettings.cc)](#32-settings-c-videosettingsh--videosettingscc)
  - [3.3 VideoManager Backend (VideoManager.h / VideoManager.cc)](#33-videomanager-backend-videomanagerh--videomanagercc)
  - [3.4 QML Display Components (new files)](#34-qml-display-components-new-files)
  - [3.5 FlyView Integration & Pip Coordination (FlyView.qml / PipView.qml)](#35-flyview-integration--pip-coordination-flyviewqml--pipviewqml)
  - [3.6 Primary Stream QML Adjustments](#36-primary-stream-qml-adjustments)
  - [3.7 Layout Adjustments (FlyViewWidgetLayer.qml)](#37-layout-adjustments-flyviewwidgetlayerqml)
- [4. Feature B — TCP Click-to-Target](#4-feature-b--tcp-click-to-target)
  - [4.1 TcpClient (new)](#41-tcpclient-new)
  - [4.2 TcpManager (new)](#42-tcpmanager-new)
  - [4.3 QML Integration (QGCCorePlugin.cc)](#43-qml-integration-qgccoreplugincpp)
  - [4.4 FlyView TCP UI & Click Handling (FlyView.qml)](#44-flyview-tcp-ui--click-handling-flyviewqml)
  - [4.5 Video Click Override (FlyViewVideo.qml)](#45-video-click-override-flyviewvideoqml)
- [5. Feature C — AMAN Sensor Telemetry](#5-feature-c--aman-sensor-telemetry)
  - [5.1 Vehicle MAVLink Decoding (Vehicle.h / Vehicle.cc)](#51-vehicle-mavlink-decoding-vehicleh--vehiclecc)
  - [5.2 Sensor Display UI (FlyView.qml)](#52-sensor-display-ui-flyviewqml)
- [6. Build Integration (CMake)](#6-build-integration-cmake)
- [7. Automated Tests](#7-automated-tests)
- [8. Replication Checklist](#8-replication-checklist)
- [9. Configuration & Usage Guide](#9-configuration--usage-guide)
- [10. Notes & Known Cosmetic Changes](#10-notes--known-cosmetic-changes)

---

## 1. Feature Overview & Architecture

QGroundControl already supports one primary video stream (`videoContent`) plus an optional
thermal overlay (`thermalVideo`). The change set adds a **third receiver slot**
(`secondContentVideo`) that behaves like an entirely separate "video" — configured via its own
settings, started/stopped independently, and rendered into its own QML `VideoOutput`.

```
 VideoSource1 ─┐                    ┌─ VideoReceiver "videoContent"      → FlightDisplayViewVideoOutput (FlyViewVideo)
               ├─ VideoManager ──── ┼─ VideoReceiver "secondContentVideo" → FlightDisplayViewVideoSecondOutput (FlyViewVideoSecond)
 VideoSource2 ─┘                    └─ VideoReceiver "thermalVideo"       → thermal overlay

 TcpManager (singleton, QML context property)
     └── TcpClient ── QTcpSocket ── external TCP server (click coords + custom actions)

 MAVLink AMAN_SENSOR_DATA ──► Vehicle::_mavlinkMessageReceived ──► amanGyroX/Y/Z, amanAccX/Y/Z (Q_PROPERTY)
     └── FlyView AMAN panel (live readout)
```

Key concept — **PipView boxes**: the Fly View uses `PipView` containers to manage
"pip" (small box) vs "full screen" states of map/video items.

- `_pipView` (bottom-left, two-item) — hosts `mapControl` + `videoControl` (stream 1); clicking
  it swaps which of the two is full-screen.
- `_pipView2` (bottom-right, single-item) — hosts `videoControl2` (stream 2); clicking it toggles
  stream 2 between pip and full screen.

While stream 2 is **full screen**, the map is moved into `_pipView2`'s pip box (bottom-right) so
the box previews what clicking it restores, and **stream 1 stays pip'd in the bottom-left box**
(`_pipView`). Both boxes are clickable: clicking the map box restores the map to full screen, and
clicking the stream-1 box restores stream 1 to full screen.

---

## 2. Changed Files Summary

| File | Status | Purpose |
|------|--------|---------|
| `src/Settings/Video.SettingsGroup.json` | modified | New stream-2 settings definitions |
| `src/Settings/VideoSettings.h` | modified | Stream-2 setting facts + `streamConfigured2` |
| `src/Settings/VideoSettings.cc` | modified | Stream-2 fact accessors, validation, signals, UVC check in `streamConfigured2` |
| `src/AppSettings/pages/Video.SettingsUI.json` | modified | Second-source settings UI ("Second Video Source" / "Second Connection"), generated into `VideoSettings.qml` at build time |
| `src/VideoManager/VideoManager.h` | modified | `hasVideo2`, `secondStreamDecoding`, `isUvc2`/`uvcVideoSourceID2`, stream helpers |
| `src/VideoManager/VideoManager.cc` | modified | Independent per-stream receiver lifecycle + URI routing + `_updateUVC2` |
| `src/FlyView/FlightDisplayViewVideoSecondOutput.qml` | **new** | Stream-2 `VideoOutput` component |
| `src/FlyView/FlyViewVideoSecond.qml` | **new** | Stream-2 pip wrapper (like `FlyViewVideo`) + UVC/webcam toggle |
| `src/FlyView/FlightDisplayViewUVC.qml` | modified | Parameterized `cameraSourceId`/`cameraActive` so the webcam view can serve stream 2 |
| `src/FlyView/FlyView.qml` | modified | Second video control, `_pipView2`, pip coordination, TCP UI, AMAN UI |
| `src/QmlControls/PipView.qml` | modified | Single-item mode, `showWhenItem1Full`, `pipMouseEnabled`, `onPipClick` |
| `src/FlyView/FlightDisplayViewVideo.qml` | modified | Refactor + stream-1 `objectName` tagging |
| `src/FlyView/FlyViewVideo.qml` | modified | Visibility fix + TCP click-to-target on video |
| `src/FlyView/FlyViewWidgetLayer.qml` | modified | Bottom-right layout re-centering to free pip space |
| `src/Toolbar/FlyViewToolBar.qml` | modified | Whitespace only (no functional change) |
| `src/TCP/TcpClient.h` | **new** | Low-level `QTcpSocket` wrapper |
| `src/TCP/TcpClient.cpp` | **new** | `TcpClient` implementation |
| `src/TCP/TcpManager.h` | **new** | QML-exposed TCP manager |
| `src/TCP/TcpManager.cpp` | **new** | `TcpManager` implementation |
| `src/API/QGCCorePlugin.cc` | modified | Instantiate `TcpManager` + expose to QML |
| `src/Vehicle/Vehicle.h` | modified | AMAN sensor properties |
| `src/Vehicle/Vehicle.cc` | modified | AMAN MAVLink message decoding |
| `src/CMakeLists.txt` | modified | Add TCP sources to QML module |
| `src/FlyView/CMakeLists.txt` | modified | Register new stream-2 QML files |
| `test/VideoManager/VideoManagerSecondStreamTest.h` | **new** | Stream-2 unit test header |
| `test/VideoManager/VideoManagerSecondStreamTest.cc` | **new** | Stream-2 unit tests |
| `test/VideoManager/CMakeLists.txt` | modified | Register stream-2 test |

---

## 3. Feature A — Second Video Stream

### 3.1 Settings (`Video.SettingsGroup.json`)

`src/Settings/Video.SettingsGroup.json` defines the settings UI. Four new settings were added
after the existing `tcpUrl` entry, mirroring the stream-1 entries (`videoSource`, `udpUrl`,
`rtspUrl`, `tcpUrl`) but suffixed with `2`:

```json
{
    "name": "videoSource2",
    "shortDesc": "Source for second video stream (UDP, TCP, RTSP, or connected USB camera).",
    "longDesc": "Source for the second video stream. UDP, TCP, RTSP and UVC Cameras may be supported depending on Vehicle and ground station version.",
    "type": "string",
    "default": "",
    "label": "Source",
    "keywords": "video source,camera,stream,second"
},
{
    "name": "udpUrl2",
    "shortDesc": "Network address and port for second UDP video stream (e.g. 0.0.0.0:5601).",
    "longDesc": "UDP url address and port to bind to for the second video stream. Example: 0.0.0.0:5601",
    "type": "string",
    "default": "0.0.0.0:5601",
    "label": "UDP URL",
    "keywords": "udp,mpegts,video url,stream url,second"
},
{
    "name": "rtspUrl2",
    "shortDesc": "Network address for second RTSP video stream (e.g. rtsp://192.168.42.1:554/live2).",
    "longDesc": "RTSP url address and port to bind to for the second video stream. Example: rtsp://192.168.42.1:554/live2",
    "type": "string",
    "default": "",
    "label": "RTSP URL",
    "keywords": "rtsp,video url,stream url,second"
},
{
    "name": "tcpUrl2",
    "shortDesc": "Network address and port for second TCP video stream (e.g. 192.168.143.200:3002).",
    "longDesc": "TCP url address and port to bind to for the second video stream. Example: 192.168.143.200:3002",
    "type": "string",
    "default": "",
    "label": "TCP URL",
    "keywords": "tcp,video url,stream url,second"
},
```

### 3.2 Settings C++ (`VideoSettings.h` / `VideoSettings.cc`)

The Fact System generates accessors from `DEFINE_SETTINGFACT`. Four new facts are declared in
`src/Settings/VideoSettings.h`, plus the `streamConfigured2` boolean property:

```cpp
//for secondVideoStream
DEFINE_SETTINGFACT(videoSource2)
DEFINE_SETTINGFACT(udpUrl2)
DEFINE_SETTINGFACT(tcpUrl2)
DEFINE_SETTINGFACT(rtspUrl2)

//secondStream Setup
Q_PROPERTY(bool streamConfigured2 READ streamConfigured2 NOTIFY streamConfigured2Changed)
//============================

bool streamConfigured2();
```

and the signal:

```cpp
void streamConfigured2Changed(bool configured);   // <-- add this
```

In `src/Settings/VideoSettings.cc`:

- **Enum info** — the stream-2 source fact reuses the same cooked list as stream 1 so the
  combo box shows the same options:

```cpp
_nameToMetaDataMap[videoSource2Name]->setEnumInfo(videoSourceCookedList, videoSourceList);
```

- **Defaults** — mirror the stream-1 defaults (disabled or no-video depending on build):

```cpp
if (_noVideo) {
    _nameToMetaDataMap[videoSourceName]->setRawDefaultValue(videoSourceNoVideo);
    _nameToMetaDataMap[videoSource2Name]->setRawDefaultValue(videoSourceNoVideo);
} else {
    _nameToMetaDataMap[videoSourceName]->setRawDefaultValue(videoDisabled);
    _nameToMetaDataMap[videoSource2Name]->setRawDefaultValue(videoDisabled);
}
```

- **Fact accessors** — one per new fact. They lazily create the `Fact`, validate the stored value
  against the current enum (falling back to a safe default), and hook `_configChanged` so the UI
  reacts live:

```cpp
DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, videoSource2)
{
    if (!_videoSource2Fact) {
        _videoSource2Fact = _createSettingsFact(videoSource2Name);
        if (!_videoSource2Fact->enumValues().contains(_videoSource2Fact->rawValue().toString())) {
            if (_noVideo) {
                _videoSource2Fact->setRawValue(videoSourceNoVideo);
            } else {
                _videoSource2Fact->setRawValue(videoDisabled);
            }
        }
        connect(_videoSource2Fact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _videoSource2Fact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, udpUrl2)
{
    if (!_udpUrl2Fact) {
        _udpUrl2Fact = _createSettingsFact(udpUrl2Name);
        connect(_udpUrl2Fact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _udpUrl2Fact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, rtspUrl2)
{
    if (!_rtspUrl2Fact) {
        _rtspUrl2Fact = _createSettingsFact(rtspUrl2Name);
        connect(_rtspUrl2Fact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _rtspUrl2Fact;
}

DECLARE_SETTINGSFACT_NO_FUNC(VideoSettings, tcpUrl2)
{
    if (!_tcpUrl2Fact) {
        _tcpUrl2Fact = _createSettingsFact(tcpUrl2Name);
        connect(_tcpUrl2Fact, &Fact::valueChanged, this, &VideoSettings::_configChanged);
    }
    return _tcpUrl2Fact;
}
```

- **Validation** — `streamConfigured2()` mirrors `streamConfigured()` but for stream 2. It returns
  `true` when a non-disabled source is selected **and** the required URL is non-empty — or when
  the selected source is an existing UVC (webcam) device, which needs no URL:

```cpp
bool VideoSettings::streamConfigured2(void)
{
    QString vSource = videoSource2()->rawValue().toString();
    if (vSource == videoSourceNoVideo || vSource == videoDisabled) {
        return false;
    }
    //-- If UDP, check for URL
    if (vSource == videoSourceUDPH264 || vSource == videoSourceUDPH265) {
        return !udpUrl2()->rawValue().toString().isEmpty();
    }
    //-- If RTSP, check for URL
    if (vSource == videoSourceRTSP) {
        return !rtspUrl2()->rawValue().toString().isEmpty();
    }
    //-- If TCP, check for URL
    if (vSource == videoSourceTCP) {
        return !tcpUrl2()->rawValue().toString().isEmpty();
    }
    //-- If MPEG-TS, check for URL
    if (vSource == videoSourceMPEGTS) {
        return !udpUrl2()->rawValue().toString().isEmpty();
    }
    //-- If Herelink Air unit, good to go
    if (vSource == videoSourceHerelinkAirUnit) {
        return true;
    }
    //-- If Herelink Hotspot, good to go
    if (vSource == videoSourceHerelinkHotspot) {
        return true;
    }
    //-- If 3DR Solo, good to go
    if (vSource == videoSource3DRSolo) {
        return true;
    }
    //-- If Parrot Discovery, good to go
    if (vSource == videoSourceParrotDiscovery) {
        return true;
    }
    //-- If Yuneec Mantis G, good to go
    if (vSource == videoSourceYuneecMantisG) {
        return true;
    }
    //-- If the source is an attached UVC (webcam) device, good to go
    if (UVCReceiver::enabled() && UVCReceiver::deviceExists(vSource)) {
        qCDebug(VideoSettingsLog) << "Stream configured for UVC";
        return true;
    }
    return false;
}
```

- **Change notification** — `_configChanged` now also emits the stream-2 flag:

```cpp
void VideoSettings::_configChanged(QVariant)
{
    emit streamConfiguredChanged(streamConfigured());
    emit streamConfigured2Changed(streamConfigured2());
}
```

#### Second-source settings UI (`src/AppSettings/pages/Video.SettingsUI.json`)

The Video settings page is **generated at build time** by
`tools/generators/settings_qml/generate_pages.py` from the `*.SettingsUI.json` page definitions
(combined with `src/Settings/*.SettingsGroup.json`); the generated `VideoSettings.qml` lands in
`build/src/AppSettings/generated/`. To make stream 2 configurable from the UI, the page JSON adds:

- a `videoSource2` fact **binding** on the page (and on the `VideoSettings` group) so the combo box
  and the URL fields can react to the selected source;
- a **"Second Video Source"** group with a `combobox` control for `videoSource2` (`"control":
  "combobox"` is required because the fact is a plain string type whose enum comes from
  `setEnumInfo` in C++ — it includes attached UVC device names);
- a **"Second Connection"** group with `rtspUrl2` / `tcpUrl2` / `udpUrl2`, each with a `showWhen`
  clause keyed on `videoSource2` so the right URL field appears for the selected source.

```json
{
    "bindings": {
        "videoSource":  "QGroundControl.settingsManager.videoSettings.videoSource.rawValue",
        "videoSource2": "QGroundControl.settingsManager.videoSettings.videoSource2.rawValue",
        ...
    },
    "groups": [
        {
            "heading": "Second Video Source",
            "controls": [
                { "setting": "videoSettings.videoSource2", "control": "combobox" }
            ]
        },
        {
            "heading": "Second Connection",
            "controls": [
                { "setting": "videoSettings.rtspUrl2",
                  "showWhen": "videoSource2 === QGroundControl.settingsManager.videoSettings.rtspVideoSource" },
                { "setting": "videoSettings.tcpUrl2",
                  "showWhen": "videoSource2 === QGroundControl.settingsManager.videoSettings.tcpVideoSource" },
                { "setting": "videoSettings.udpUrl2",
                  "showWhen": "videoSource2 === QGroundControl.settingsManager.videoSettings.udp264VideoSource || ... || mpegtsVideoSource" }
            ]
        }
    ]
}
```

Before this change the second source could only be configured by editing the `.ini`, because the
generated page had no stream-2 controls.

### 3.3 VideoManager Backend (`VideoManager.h` / `VideoManager.cc`)

`VideoManager` is the C++ heart of all video handling. Changes add a fully parallel second
stream with independent lifecycle.

**`VideoManager.h`** — new public API and state:

```cpp
Q_PROPERTY(bool     hasVideo2               READ hasVideo2                                  NOTIFY hasVideo2Changed)
Q_PROPERTY(bool     secondStreamDecoding    READ secondStreamDecoding                        NOTIFY secondStreamDecodingChanged)
...
friend class VideoManagerSecondStreamTest;

bool hasVideo2() const;
bool secondStreamDecoding() const { return _secondStreamDecoding; }

void hasVideo2Changed();
void secondStreamDecodingChanged();
```

and the private helpers plus bookkeeping state:

```cpp
bool _shouldStartReceiver(VideoReceiver *receiver) const;

static bool _isPrimaryStream(const VideoReceiver *receiver);
static bool _isSecondStream(const VideoReceiver *receiver);
static bool _isNetworkStreamSource(const QString &videoSource);

// Last notified state for change-emission and start/stop decisions in _videoSourceChanged.
bool _lastHasVideo = true;
bool _lastHasVideo2 = true;

QAtomicInteger<bool> _secondStreamDecoding = false;
```

**`VideoManager.cc`** — the substantive logic:

- **Receiver list** — a new receiver slot named `"secondContentVideo"` is added to the list
  created in `_createVideoReceivers()`:

```cpp
static const QStringList videoStreamList = {
    "videoContent",
    "secondContentVideo",
    "thermalVideo"
};
```

  (A debug/warning log line was also added there to aid diagnosis:
  `qCDebug(VideoManagerLog) << "===== _createVideoReceivers CALLED =====";` and a warning when a
  receiver fails to be created.)

- **`hasVideo2()`** — stream 2 is available when the master `streamEnabled` switch is on **and**
  the stream-2 config is valid:

```cpp
bool VideoManager::hasVideo2() const
{
    return (_videoSettings->streamEnabled()->rawValue().toBool() && _videoSettings->streamConfigured2());
}
```

- **`isStreamSource()` refactor** — split the single source check into a reusable helper so both
  streams can be checked. The new version returns true if *either* stream is a network source:

```cpp
bool VideoManager::isStreamSource() const
{
    const QString videoSource = _videoSettings->videoSource()->rawValue().toString();
    if (_isNetworkStreamSource(videoSource)) {
        return true;
    }
    const QString videoSource2 = _videoSettings->videoSource2()->rawValue().toString();
    return (_isNetworkStreamSource(videoSource2) || autoStreamConfigured());
}

bool VideoManager::_isNetworkStreamSource(const QString &videoSource)
{
    static const QStringList videoSourceList = {
        VideoSettings::videoSourceUDPH264,
        VideoSettings::videoSourceUDPH265,
        VideoSettings::videoSourceMPEGTS,
        VideoSettings::videoSourceRTSP,
        VideoSettings::videoSourceTCP,
        VideoSettings::videoSourceHerelinkAirUnit,
        VideoSettings::videoSourceHerelinkHotspot,
    };
    return videoSourceList.contains(videoSource);
}
```

- **Stream identification helpers** — used everywhere to route behavior per receiver:

```cpp
bool VideoManager::_isPrimaryStream(const VideoReceiver *receiver)
{
    return receiver && (receiver->name() == QStringLiteral("videoContent"));
}

bool VideoManager::_isSecondStream(const VideoReceiver *receiver)
{
    return receiver && (receiver->name() == QStringLiteral("secondContentVideo"));
}
```

- **Independent start gating** — `_shouldStartReceiver()` decides whether a receiver should run.
  Stream 2 is gated on its *own* configuration, stream 1 and thermal keep the historical gating:

```cpp
bool VideoManager::_shouldStartReceiver(VideoReceiver *receiver) const
{
    if (!receiver) {
        return false;
    }

    if (_isSecondStream(receiver)) {
        return (_videoSettings->streamEnabled()->rawValue().toBool() && _videoSettings->streamConfigured2());
    }

    // Primary video and thermal receivers keep the historical stream-1 gating.
    return hasVideo();
}
```

- **`_videoSourceChanged()` rewrite** — the stream-1-only logic was replaced with per-receiver
  handling. It tracks the previous `hasVideo`/`hasVideo2` values so each property's change signal
  fires only on an actual transition, and starts/stops each receiver independently:

```cpp
void VideoManager::_videoSourceChanged()
{
    bool changed = false;
    if (_activeVehicle) {
        QGCCameraManager* camMgr = _activeVehicle->cameraManager();
        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            // The second stream has its own configuration; never feed it the vehicle camera stream.
            if (!_isSecondStream(receiver)) {
                QGCVideoStreamInfo* info = nullptr;
                if (receiver->isThermal()) {
                    info = camMgr ? camMgr->thermalStreamInstance() : nullptr;
                } else {
                    info = camMgr ? camMgr->currentStreamInstance() : nullptr;
                }
                receiver->setVideoStreamInfo(info);
            }
            changed |= _updateSettings(receiver);
        }
    } else {
        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            if (!_isSecondStream(receiver)) {
                receiver->setVideoStreamInfo(nullptr);
            }
            changed |= _updateSettings(receiver);
        }
    }

    const bool hasVideo = this->hasVideo();
    const bool hasVideo2 = this->hasVideo2();
    const bool hasVideoChangedValue = (hasVideo != _lastHasVideo);
    const bool hasVideo2ChangedValue = (hasVideo2 != _lastHasVideo2);
    _lastHasVideo = hasVideo;
    _lastHasVideo2 = hasVideo2;

    if (changed || hasVideoChangedValue || hasVideo2ChangedValue) {
        if (hasVideoChangedValue) {
            emit hasVideoChanged();
        }
        if (hasVideo2ChangedValue) {
            emit hasVideo2Changed();
        }
        if (changed) {
            emit isStreamSourceChanged();
            emit isAutoStreamChanged();
        }

        for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
            if (_shouldStartReceiver(receiver)) {
                _restartVideo(receiver);
            } else {
                _stopReceiver(receiver);
            }
        }

        qCDebug(VideoManagerLog) << "Video source changed. stream1:" << _videoSettings->videoSource()->rawValue().toString()
                                 << "stream2:" << _videoSettings->videoSource2()->rawValue().toString();
    }
}
```

- **`_updateUVC()`** — now consults the stream-1 source only (so the second stream can never
  disable UVC detection for stream 1):

```cpp
if (!UVCReceiver::enabled() || !hasVideo() || _isNetworkStreamSource(_videoSettings->videoSource()->rawValue().toString())) {
    _uvcVideoSourceID = QString();
} else {
    _uvcVideoSourceID = UVCReceiver::getSourceId();
}
```

- **`_updateUVC2()`** — the stream-2 counterpart. It resolves `videoSource2()` through
  `UVCReceiver::findCameraDevice()` into `_uvcVideoSourceID2` (cleared when the source is a network
  stream, UVC is disabled, or the device is gone), and emits `uvcVideoSourceID2Changed` /
  `isUvc2Changed` on change:

```cpp
bool VideoManager::_updateUVC2(VideoReceiver * /*receiver*/)
{
    bool result = false;

    const QString oldUvcVideoSrcID = _uvcVideoSourceID2;

    const QString videoSource2 = _videoSettings->videoSource2()->rawValue().toString();
    if (!UVCReceiver::enabled() || !hasVideo2() || _isNetworkStreamSource(videoSource2)) {
        _uvcVideoSourceID2 = QString();
    } else {
        const QCameraDevice cameraDevice = UVCReceiver::findCameraDevice(videoSource2);
        _uvcVideoSourceID2 = cameraDevice.isNull() ? QString() : cameraDevice.description();
    }

    if (oldUvcVideoSrcID != _uvcVideoSourceID2) {
        qCDebug(VideoManagerLog) << "UVC stream2 changed from [" << oldUvcVideoSrcID << "] to [" << _uvcVideoSourceID2 << "]";
        if (!_uvcVideoSourceID2.isEmpty()) {
            UVCReceiver::checkPermission();
        }
        result = true;
        emit uvcVideoSourceID2Changed();
        emit isUvc2Changed();
    }

    return result;
}
```

`isUvc2()` is the stream-2 mirror of `isUvc()`: `!_uvcVideoSourceID2.isEmpty() &&
UVCReceiver::enabled() && hasVideo2()`. Exposed as QML properties `isUvc2` /
`uvcVideoSourceID2` on `VideoManager`.

- **`_updateAutoStream()`** — stream 2 must never mutate stream-1 settings:

```cpp
bool VideoManager::_updateAutoStream(VideoReceiver *receiver)
{
    // The second stream is configured manually and must not mutate stream-1 settings.
    if (_isSecondStream(receiver)) {
        return false;
    }
    ...
}
```

- **`_updateSettings()` stream-2 URI routing** — this is the key mapping from the selected
  "video source 2" option to a GStreamer URI (or to webcam state). It runs before the stream-1
  path and returns early for stream-2 receivers; `_updateUVC2()` is called unconditionally so the
  UVC state is cleared/updated for *any* source-2 value:

```cpp
if (_isSecondStream(receiver)) {
    const QString source2 = _videoSettings->videoSource2()->rawValue().toString();
    settingsChanged |= _updateUVC2(receiver);
    if (source2 == VideoSettings::videoSourceUDPH264) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://%1").arg(_videoSettings->udpUrl2()->rawValue().toString()));
    } else if (source2 == VideoSettings::videoSourceUDPH265) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp265://%1").arg(_videoSettings->udpUrl2()->rawValue().toString()));
    } else if (source2 == VideoSettings::videoSourceMPEGTS) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("mpegts://%1").arg(_videoSettings->udpUrl2()->rawValue().toString()));
    } else if (source2 == VideoSettings::videoSourceRTSP) {
        settingsChanged |= _updateVideoUri(receiver, _videoSettings->rtspUrl2()->rawValue().toString());
    } else if (source2 == VideoSettings::videoSourceTCP) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("tcp://%1").arg(_videoSettings->tcpUrl2()->rawValue().toString()));
    } else if (source2 == VideoSettings::videoSource3DRSolo) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://0.0.0.0:5600"));
    } else if (source2 == VideoSettings::videoSourceParrotDiscovery) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("udp://0.0.0.0:8888"));
    } else if (source2 == VideoSettings::videoSourceYuneecMantisG) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.42.1:554/live"));
    } else if (source2 == VideoSettings::videoSourceHerelinkAirUnit) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.0.10:8554/H264Video"));
    } else if (source2 == VideoSettings::videoSourceHerelinkHotspot) {
        settingsChanged |= _updateVideoUri(receiver, QStringLiteral("rtsp://192.168.43.1:8554/fpv_stream"));
    } else {
        settingsChanged |= _updateVideoUri(receiver, QString());
    }
    return settingsChanged;
}
```

- **`_setActiveVehicle()`** — stream 2 never receives a vehicle camera stream info:

```cpp
if (_isSecondStream(receiver)) {
    receiver->setVideoStreamInfo(nullptr);
} else if (receiver->isThermal()) {
    receiver->setVideoStreamInfo(_activeVehicle->cameraManager()->thermalStreamInstance());
} else {
    receiver->setVideoStreamInfo(_activeVehicle->cameraManager()->currentStreamInstance());
}
```

- **`_startReceiver()`** — stream 2 uses its own source setting (and default RTSP timeout logic):

```cpp
const QString source = _isSecondStream(receiver)
        ? _videoSettings->videoSource2()->rawValue().toString()
        : _videoSettings->videoSource()->rawValue().toString();
const uint32_t timeout = ((source == VideoSettings::videoSourceRTSP) ? _videoSettings->rtspTimeout()->rawValue().toUInt() : 3);

receiver->start(timeout);
```

- **`_initVideoReceiver()` signal routing** — streaming/decoding/recording/size signals now fire
  only for the stream they belong to. Stream 1 keeps the historical aggregate behavior; stream 2
  has its own `secondStreamDecoding`:

```cpp
// streaming: only the primary stream drives the aggregate _streaming flag
if (_isPrimaryStream(receiver)) {
    _streaming = active;
    emit streamingChanged();
}

// decoding
if (_isSecondStream(receiver)) {
    _secondStreamDecoding = active;
    emit secondStreamDecodingChanged();
} else if (_isPrimaryStream(receiver)) {
    _decoding = active;
    emit decodingChanged();
}

// recording
if (_isPrimaryStream(receiver)) {
    _recording = active;
    if (!active) {
        _subtitleWriter->stopCapturingTelemetry();
    }
}

// recordingStarted → subtitles only for primary
if (_isPrimaryStream(receiver)) {
    _subtitleWriter->startCapturingTelemetry(filename, videoSize());
}

// videoSizeChanged → size only from primary
if (_isPrimaryStream(receiver)) {
    _videoSize = size;
    emit videoSizeChanged();
    emit aspectRatioChanged();
}
```

  and the startup gating at the end of `_initVideoReceiver()`:

```cpp
if (_shouldStartReceiver(receiver)) {
    _startReceiver(receiver);
}
```

- **`startVideo()`** — starts every configured stream instead of only stream 1:

```cpp
void VideoManager::startVideo()
{
    qCDebug(VideoManagerLog) << "startVideo";

    if (!hasVideo() && !hasVideo2()) {
        qCDebug(VideoManagerLog) << "Stream not enabled/configured";
        return;
    }

    for (VideoReceiver *receiver : std::as_const(_videoReceivers)) {
        if (_shouldStartReceiver(receiver)) {
            _restartVideo(receiver);
        }
    }
}
```

- **Settings connections** — `init()` connects the four new stream-2 facts plus `streamEnabled`
  to `_videoSourceChanged()` so any change restarts the right stream:

```cpp
(void) connect(_videoSettings->videoSource2(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
(void) connect(_videoSettings->udpUrl2(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
(void) connect(_videoSettings->rtspUrl2(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
(void) connect(_videoSettings->tcpUrl2(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
(void) connect(_videoSettings->streamEnabled(), &Fact::rawValueChanged, this, &VideoManager::_videoSourceChanged);
```

### 3.4 QML Display Components (new files)

**`src/FlyView/FlightDisplayViewVideoSecondOutput.qml`** — the actual video surface for stream 2.
A plain `VideoOutput` tagged `objectName: "secondContentVideo"` (this name is what
`VideoManager::_isSecondStream()` matches on). It respects the shared `videoFit` setting for
fill/fit behavior and supports screenshot capture:

```qml
import QtQuick
import QtMultimedia

import QGroundControl

VideoOutput {
    objectName: "secondContentVideo"

    // Do NOT set `orientation` here — VideoOutput composes orientation on top of the
    // QVideoFrame's own rotation()/mirrored() metadata that qgcqvideosink forwards from
    // GstVideoOrientationMeta. Setting it would double-rotate any stream with orientation tags.

    // videoFit enum: 0=Fit Width, 1=Fit Height, 2=Fill, 3=No Crop. The container
    // handles fit-width/fit-height sizing; only Fill needs the cropping fillMode.
    fillMode: QGroundControl.settingsManager.videoSettings.videoFit.rawValue === 2
              ? VideoOutput.PreserveAspectCrop
              : VideoOutput.PreserveAspectFit

    Connections {
        target: QGroundControl.videoManager
        function onImageFileChanged(filename) {
            grabToImage(function(result) {
                if (!result.saveToFile(filename)) {
                    console.error('Error capturing video frame');
                }
            });
        }
    }
}
```

**`src/FlyView/FlyViewVideoSecond.qml`** — a wrapper identical in shape to `FlyViewVideo.qml` but
for stream 2. It owns a `PipState` so the stream participates in pip/full/window state
management. It hosts the `FlightDisplayViewVideoSecondOutput` (GStreamer) and, when a webcam is
selected for source 2, toggles in the parameterized `FlightDisplayViewUVC` instead:

```qml
import QtQuick

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

Item {
    id: _root

    property Item pipView
    property Item pipState: secondVideoPipState

    PipState {
        id:         secondVideoPipState
        pipView:    _root.pipView
        isDark:     true

        onWindowAboutToOpen: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onWindowAboutToClose: {
            QGroundControl.videoManager.stopVideo()
            videoStartDelay.start()
        }

        onStateChanged: {
            if (secondVideoPipState.state !== secondVideoPipState.fullState &&
                secondVideoPipState.state !== secondVideoPipState.windowState) {
                QGroundControl.videoManager.fullScreen = false
            }
        }
    }

    Timer {
        id:           videoStartDelay
        interval:     2000;
        running:      false
        repeat:       false
        onTriggered:  QGroundControl.videoManager.startVideo()
    }

    //-- Video Streaming
    FlightDisplayViewVideoSecondOutput {
        anchors.fill:   parent
        visible:        !QGroundControl.videoManager.isUvc2
    }

    //-- Integrated web cam (UVC)
    FlightDisplayViewUVC {
        cameraSourceId: QGroundControl.videoManager.uvcVideoSourceID2
        cameraActive:   QGroundControl.videoManager.isUvc2
        visible:        QGroundControl.videoManager.isUvc2
    }
}
```

### 3.5 FlyView Integration & Pip Coordination (`FlyView.qml` / `PipView.qml`)

#### PipView refactor (`src/QmlControls/PipView.qml`)

`PipView` originally only supported **two-item** operation (map + video1). It was extended to
support a **single-item** mode needed by the second stream box, plus two coordination flags.

New properties:

```qml
property bool   item1IsFullDefault:     true    // Default state of item1 when no saved setting exists
property string pipExpandedSettingsKey: "IsPIPVisible"
property bool   show:                   true
property bool   showWhenItem1Full:      false    // Single-item mode: keep the box visible while item1 is full (used to host another pip item)
property bool   pipMouseEnabled:        true     // Whether the pip box can be clicked to swap items
property var    onPipClick:             undefined // Optional custom click handler; overrides the default swap
```

Visibility now depends on whether the box hosts one or two items:

```qml
// Two-item mode: the PipView box is visible whenever the pip item isn't popped out to its own window.
// Single-item mode (item2 == null): the box is only visible while item1 is in pip mode (or pinned visible while full).
readonly property bool _pipViewVisible: item2
                                            ? item2.pipState.state !== item2.pipState.windowState
                                            : item1 && (item1.pipState.state === item1.pipState.pipState || showWhenItem1Full)

visible:    show && _pipViewVisible
```

`_initForItems()` honors the configurable default and, in single-item mode, starts item1 in pip
instead of always full:

```qml
function _initForItems() {
    var item1IsFull = QGroundControl.loadBoolGlobalSetting(item1IsFullSettingsKey, item1IsFullDefault)
    if (item1 && item2) {
        item1.pipState.state = item1IsFull ? item1.pipState.fullState : item1.pipState.pipState
        item2.pipState.state = item1IsFull ? item2.pipState.pipState : item2.pipState.fullState
        _fullItem = item1IsFull ? item1 : item2
        _pipOrWindowItem = item1IsFull ? item2 : item1
    } else {
        item1.pipState.state = item1IsFull ? item1.pipState.fullState : item1.pipState.pipState
        _fullItem = item1
        _pipOrWindowItem = item1
    }
    _setPipIsExpanded(QGroundControl.loadBoolGlobalSetting(pipExpandedSettingsKey, true))
}
```

`_swapPip()` gains a single-item branch — clicking the box toggles item1 between full and pip
(and persists the choice). This is what lets a single click on the second video box maximize it:

```qml
function _swapPip() {
    if (!item2) {
        var wasFull = item1.pipState.state === item1.pipState.fullState
        item1.pipState.state = wasFull ? item1.pipState.pipState : item1.pipState.fullState
        QGroundControl.saveBoolGlobalSetting(item1IsFullSettingsKey, !wasFull)
        return
    }
    var item1IsFull = false
    if (item1.pipState.state === item1.pipState.fullState) {
        item1.pipState.state = item1.pipState.pipState
        item2.pipState.state = item2.pipState.fullState
        _fullItem = item2
        _pipOrWindowItem = item1
        item1IsFull = false
    } else {
        item1.pipState.state = item1.pipState.fullState
        item2.pipState.state = item2.pipState.pipState
        _fullItem = item1
        _pipOrWindowItem = item2
        item1IsFull = true
    }
    QGroundControl.saveBoolGlobalSetting(item1IsFullSettingsKey, item1IsFull)
}
```

The `pipMouseArea` honors the new `pipMouseEnabled` flag and supports an optional custom click
handler via `onPipClick` (when set, it replaces the default `_swapPip`):

```qml
property bool pipMouseEnabled: true     // Whether the pip box can be clicked to swap items
property var  onPipClick:      undefined // Optional custom click handler; overrides the default swap
...
onClicked: {
    if (onPipClick) {
        onPipClick()
    } else {
        _swapPip()
    }
}
```

#### FlyView wiring (`src/FlyView/FlyView.qml`)

**Second video control** — added alongside the primary one, visible only when `hasVideo2`:

```qml
FlyViewVideo {
    id: videoControl
    pipView: _pipView
}

FlyViewVideoSecond {
    id: videoControl2
    pipView: _pipView2
    visible: QGroundControl.videoManager.hasVideo2
}
```

**`_pipView2`** — the bottom-right single-item box hosting stream 2:

```qml
PipView {
    id: _pipView2

    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: _toolsMargin

    item1IsFullSettingsKey: "SecondVideoIsFull"
    item1IsFullDefault: false
    pipExpandedSettingsKey: "SecondVideoIsExpanded"
    item1: videoControl2
    item2: null
    showWhenItem1Full: true

    show: QGroundControl.videoManager.hasVideo2 &&
          !QGroundControl.videoManager.fullScreen

    z: QGroundControl.zOrderWidgets
}
```

`showWhenItem1Full: true` keeps the box visible even while stream 2 is full — it is the box that
hosts the **map** during that time.

**Pip coordination handler** — the core of the map↔video2 behavior. When stream 2 enters full
screen the map is moved into `_pipView2`'s box (bottom-right) so the box previews what clicking it
restores, and stream 1 stays pip'd in the bottom-left box (`_pipView`); when stream 2 returns to
pip the map goes full again — unless the exit was triggered from the stream-1 box, which restores
stream 1 to full instead. Moving the map between boxes requires *bouncing its state* because QML's
`PipState` (a `ParentChange`/`AnchorChanges` state machine) only re-parents on an actual state
transition:

```qml
// Coordinate map <-> second video pip states. While video 2 is full the map is shown in
// the bottom-right pip box (_pipView2) so the box previews what clicking it restores;
// video 1 stays pip'd in the bottom-left box (_pipView). Clicking either box exits
// stream 2 full: the map box restores the map, the video-1 box restores stream 1.
// QML only re-applies a PipState's parent/anchors when the state changes, so after
// moving the map to a different pipView we bounce its state to force the re-parent.
Connections {
    target: videoControl2.pipState

    function onStateChanged() {
        if (videoControl2.pipState.state === videoControl2.pipState.fullState) {
            if (mapControl.pipView !== _pipView2) {
                mapControl.pipView = _pipView2
            }
            if (mapControl.pipState.state === mapControl.pipState.fullState) {
                mapControl.pipState.state = mapControl.pipState.pipState
            } else {
                mapControl.pipState.state = mapControl.pipState.fullState
                mapControl.pipState.state = mapControl.pipState.pipState
            }
            if (videoControl.pipView !== _pipView) {
                videoControl.pipView = _pipView
                videoControl.pipState.state = videoControl.pipState.fullState
                videoControl.pipState.state = videoControl.pipState.pipState
            } else if (videoControl.pipState.state === videoControl.pipState.fullState) {
                videoControl.pipState.state = videoControl.pipState.pipState
            }
        } else if (videoControl2.pipState.state === videoControl2.pipState.pipState) {
            if (_exitRestoreVideo1) {
                // Restore stream 1 to full screen; the map returns to the bottom-left box.
                _exitRestoreVideo1 = false
                if (mapControl.pipView !== _pipView) {
                    mapControl.pipView = _pipView
                }
                mapControl.pipState.state = mapControl.pipState.fullState
                mapControl.pipState.state = mapControl.pipState.pipState
                if (videoControl.pipView !== _pipView) {
                    videoControl.pipView = _pipView
                }
                videoControl.pipState.state = videoControl.pipState.fullState
            } else {
                // Restore the map to full screen; stream 1 stays pip'd bottom-left.
                if (mapControl.pipView !== _pipView) {
                    mapControl.pipView = _pipView
                }
                mapControl.pipState.state = mapControl.pipState.fullState
                if (videoControl.pipView !== _pipView) {
                    videoControl.pipView = _pipView
                    videoControl.pipState.state = videoControl.pipState.fullState
                    videoControl.pipState.state = videoControl.pipState.pipState
                }
            }
        }
    }
}
```

**Click behavior while stream 2 is full** — both pip boxes are clickable, and each restores its
own content. The map box (`_pipView2`) keeps the default single-item toggle (click → stream 2 pip →
map full). The stream-1 box (`_pipView`) sets the `_exitRestoreVideo1` flag before exiting stream 2
full so the handler restores stream 1 to full screen; at other times it keeps the default map↔video1
swap via `onPipClick`:

```qml
// While the second video is full this box holds stream 1; clicking it exits stream 2
// full and restores stream 1 to full screen (handled by onPipClick).
onPipClick: function() {
    if (videoControl2.pipState.state === videoControl2.pipState.fullState) {
        _exitRestoreVideo1 = true
        videoControl2.pipState.state = videoControl2.pipState.pipState
    } else {
        _pipView._swapPip()
    }
}
```

#### UVC (webcam) support for stream 2

Stream-2 UVC reuses the stream-1 QtMultimedia webcam view by parameterizing it. The wiring is:

- **`FlightDisplayViewUVC.qml`** (stream 1's webcam view) gains `cameraSourceId` /
  `cameraActive` properties defaulting to `uvcVideoSourceID` / `isUvc`, so stream 1 behaves
  exactly as before and stream 2 can point the same component at its own camera:

```qml
property var _videoManager: QGroundControl.videoManager
property string cameraSourceId: _videoManager.uvcVideoSourceID
property bool cameraActive: _videoManager.isUvc
...
Camera {
    cameraDevice: mediaDevices.findCameraDevice(cameraSourceId)
    active: cameraActive
}
```

- **`FlyViewVideoSecond.qml`** toggles between the GStreamer `VideoOutput` and the webcam view on
  `isUvc2`. Both are children of the pip wrapper, so they follow the pip/full/window states
  normally. The empty-URI GStreamer receiver is a no-op (`GstVideoReceiver::start()` returns early
  for an empty URI), matching how stream 1 already handles UVC:

```qml
//-- Video Streaming
FlightDisplayViewVideoSecondOutput {
    anchors.fill:   parent
    visible:        !QGroundControl.videoManager.isUvc2
}

//-- Integrated web cam (UVC)
FlightDisplayViewUVC {
    cameraSourceId: QGroundControl.videoManager.uvcVideoSourceID2
    cameraActive:   QGroundControl.videoManager.isUvc2
    visible:        QGroundControl.videoManager.isUvc2
}
```

- On the C++ side `streamConfigured2()` returns true for an attached UVC device (so `hasVideo2()`
  and thus the stream-2 box become active), `_updateSettings()` calls `_updateUVC2()` for the
  second receiver, and the webcam renderer is driven by the new `isUvc2` / `uvcVideoSourceID2`
  properties (see §3.2/§3.3). Both streams can use UVC simultaneously — each resolves its own
  device via `UVCReceiver::findCameraDevice()`.

### 3.6 Primary Stream QML Adjustments

**`src/FlyView/FlightDisplayViewVideo.qml`** — mostly a whitespace/readability refactor (comment
cleanup, compact grid-line rectangles, removed the no-longer-needed thermal `pipOrNot()` dynamic
anchor helper). The two functional changes are:

- The no-video background and the video container now use a combined `_anyStream` flag
  (`_showStreamLoader || _showUvcLoader`) instead of duplicating the condition:

```qml
property bool   _anyStream:         _showStreamLoader || _showUvcLoader
```

- The primary stream loader tags its content with `objectName: "videoContent"` so
  `VideoManager::_isPrimaryStream()` can identify it:

```qml
Loader {
    id:                 videoStreamLoader
    anchors.fill:       parent
    visible:            _showStreamLoader
    sourceComponent:    videoOutputComponent

    onLoaded: { if (item) item.objectName = "videoContent" }
}
```

**`src/FlyView/FlyViewVideo.qml`** — two changes:

1. **Visibility fix** — previously the primary video only showed when `isStreamSource` was true,
   which would hide it in UVC/autoconfigured cases. Now:

```qml
visible: QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.isUvc
```

2. **TCP click-to-target** — the mouse handlers that used to drive the gimbal/camera tracking
   controllers are now commented out and replaced by a `TcpManager.sendMessage()` call. The
   single-click timer sends `CLICK,x,y` and the release handler sends every click immediately:

```qml
onTriggered: {
    // console.log("VIDEO CLICK:", clickX, clickY)

    // onScreenGimbalController.mouseClicked(clickX, clickY)
    // cameraTrackingController.mouseClicked(clickX, clickY)

    TcpManager.sendMessage(
           "CLICK," + clickX + "," + clickY + "\n"
       )
}
```

and in `onReleased`:

```qml
} else {
    // Send every click immediately
    console.log("VIDEO TCP SEND:", mouse.x, mouse.y)

    TcpManager.sendMessage(
        "CLICK," + mouse.x + "," + mouse.y + "\n"
    )

    singleClickTimer.clickX = mouse.x
    singleClickTimer.clickY = mouse.y
    singleClickTimer.restart()
}
```

### 3.7 Layout Adjustments (`FlyViewWidgetLayer.qml`)

To make room for the new bottom-right pip box, the bottom-right widget row (telemetry/rssi row)
was re-centered and its right-edge inset removed so it no longer claims the corner:

```qml
FlyViewBottomRightRowLayout {
    id:                 bottomRightRowLayout
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom:     parent.bottom
    spacing:            _layoutSpacing

    property real bottomEdgeCenterInset:    height + _layoutMargin
}
```

and the corresponding inset bindings were dropped from the widget layer's insets:

```qml
// removed:
// rightEdgeBottomInset:   bottomRightRowLayout.rightEdgeBottomInset
// bottomEdgeRightInset:   virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeRightInset : bottomRightRowLayout.bottomEdgeRightInset
bottomEdgeRightInset:   virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeRightInset : 0
```

---

## 4. Feature B — TCP Click-to-Target

### 4.1 TcpClient (new)

**`src/TCP/TcpClient.h`** — thin `QTcpSocket` wrapper:

```cpp
#ifndef TCPCLIENT_H
#define TCPCLIENT_H

#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>

class QTcpSocket;

class TcpClient : public QObject
{
  Q_OBJECT

public:
  explicit TcpClient(QObject* parent = nullptr);
    ~TcpClient() override;

    bool connectToServer(const QString& hostAddress, quint16 port);
    void disconnectFromServer();

    bool sendMessage(const QString& message);
    bool isConnected() const;

signals:
    void connected();
    void disconnected();
    void messageReceived(const QString& message);
    void errorOccurred(const QString& error);

private slots:
    void _readBytes();

private:
    QTcpSocket* _socket = nullptr;
};

#endif  // TCPCLIENT_H
```

**`src/TCP/TcpClient.cpp`** — implementation. Wires up the socket signals, connects/reconnects,
sends UTF-8 messages, and reads incoming bytes:

```cpp
#include "TcpClient.h"

#include <QtNetwork/QTcpSocket>

TcpClient::TcpClient(QObject* parent)
    : QObject(parent)
      , _socket(new QTcpSocket(this))
{
    connect(_socket, &QTcpSocket::connected,
            this, &TcpClient::connected);

    connect(_socket, &QTcpSocket::disconnected,
            this, &TcpClient::disconnected);

    connect(_socket, &QTcpSocket::readyRead,
            this, &TcpClient::_readBytes);

    connect(_socket, &QTcpSocket::errorOccurred,
            this, [this](QAbstractSocket::SocketError) {
                emit errorOccurred(_socket->errorString());
            });
}

TcpClient::~TcpClient()
{
}

bool TcpClient::connectToServer(const QString& hostAddress, quint16 port)
{
    if (hostAddress.isEmpty()) {
        return false;
    }

    _socket->connectToHost(hostAddress, port);

    return true;
}

void TcpClient::disconnectFromServer()
{
    if (_socket) {
        _socket->disconnectFromHost();
    }
}

bool TcpClient::isConnected() const
{
    return _socket &&
           _socket->state() == QAbstractSocket::ConnectedState;
}

bool TcpClient::sendMessage(const QString& message)
{
    if (!_socket ||
        _socket->state() != QAbstractSocket::ConnectedState) {
        return false;
    }

    const QByteArray data = message.toUtf8();

    return _socket->write(data) == data.size();
}

void TcpClient::_readBytes()
{
    const QByteArray data = _socket->readAll();

    if (!data.isEmpty()) {
        emit messageReceived(QString::fromUtf8(data));
    }
}
```

### 4.2 TcpManager (new)

**`src/TCP/TcpManager.h`** — QML-friendly manager singleton with `Q_INVOKABLE` methods and
Qt/QML-friendly signals:

```cpp
#pragma once

#ifndef TCPMANAGER_H
#define TCPMANAGER_H

#include <QtCore/QObject>

class TcpClient;

class TcpManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit TcpManager(QObject* parent = nullptr);

    Q_INVOKABLE void connectToServer(const QString& host, quint16 port);
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void sendMessage(const QString& message);

    bool isConnected() const;

signals:
    void connected();
    void disconnected();
    void messageReceived(const QString& message);
    void errorOccurred(const QString& error);
    void connectedChanged();

private:
    TcpClient* _client = nullptr;
};

#endif  // TCPMANAGER_H
```

**`src/TCP/TcpManager.cpp`** — forwards everything to the `TcpClient`, re-emitting signals and
keeping the `connectedChanged` property notification in sync:

```cpp
#include "TcpManager.h"
#include "TcpClient.h"
#include <QtNetwork/QTcpSocket>

TcpManager::TcpManager(QObject* parent)
    : QObject(parent)
      , _client(new TcpClient(this))
{
    connect(_client, &TcpClient::connected,
            this, [this]() {
                emit connected();
                emit connectedChanged();
            });

    connect(_client, &TcpClient::disconnected,
            this, [this]() {
                emit disconnected();
                emit connectedChanged();
            });

    connect(_client, &TcpClient::messageReceived,
            this, &TcpManager::messageReceived);

    connect(_client, &TcpClient::errorOccurred,
            this, &TcpManager::errorOccurred);
}

void TcpManager::connectToServer(const QString& host, quint16 port)
{
    _client->connectToServer(host, port);
}

void TcpManager::disconnectFromServer()
{
    _client->disconnectFromServer();
}

void TcpManager::sendMessage(const QString& message)
{
    _client->sendMessage(message);
}

bool TcpManager::isConnected() const
{
    return _client->isConnected();
}
```

### 4.3 QML Integration (`QGCCorePlugin.cc`)

`src/API/QGCCorePlugin.cc` instantiates a `TcpManager` and exposes it to all QML as a context
property named `TcpManager` (so QML can call `TcpManager.sendMessage(...)` directly):

```cpp
#include "src/TCP/TcpManager.h"
...
QQmlApplicationEngine *QGCCorePlugin::createQmlApplicationEngine(QObject *parent)
{
    QQmlApplicationEngine *const qmlEngine = new QQmlApplicationEngine(parent);
    qmlEngine->addImportPath(QStringLiteral("qrc:/qml"));

    TcpManager* tcpManager = new TcpManager(qmlEngine);

    qmlEngine->rootContext()->setContextProperty(QStringLiteral("TcpManager"), tcpManager);
    qmlEngine->rootContext()->setContextProperty(QStringLiteral("joystickManager"), JoystickManager::instance());
    return qmlEngine;
}
```

### 4.4 FlyView TCP UI & Click Handling (`FlyView.qml`)

Three new root properties track connection state in QML:

```qml
property bool tcpConnecting: false
property string tcpConnectionState: "disconnected"
property string tcpErrorMessage: ""
```

**Click-to-target on the whole FlyView** — a full-canvas mouse area converts clicks into TCP
messages when connected (without swallowing the click for the map):

```qml
MouseArea {
    id: tcpClickArea

    anchors.fill: parent

    acceptedButtons: Qt.LeftButton

    propagateComposedEvents: true

    onClicked: function(mouse) {

        var x = Math.round(mouse.x)
        var y = Math.round(mouse.y)

        console.log(
            "TCP: FlyView clicked:",
            x,
            y
        )

        if (tcpConnectionState === "connected") {

            var clickMessage =
                "CLICK," +
                x +
                "," +
                y +
                "\n"

            console.log(
                "TCP: Sending:",
                clickMessage
            )

            TcpManager.sendMessage(
                clickMessage
            )
        }

        // Do not consume the click
        mouse.accepted = false
    }
}
```

**TCP control panel** — a toggleable panel (button "TCP Server" near the top-center) containing:

- **IP/Port fields** (`ipAddressField`, `portField`) — defaults `127.0.0.1` / `5000`, hidden once
  connected.
- **Connect button** — validates fields, sets `tcpConnecting`/`tcpConnectionState`, then calls
  `TcpManager.connectToServer(...)`.
- **Connecting state** — a `BusyIndicator` + label.
- **Error state** — "Connection Failed" box with the message and a "Try Again" button that
  re-attempts the connection.
- **Connected state** — three action buttons ("TCP Action A/B/C") that send fixed messages, a
  read-only `TextArea` (`serverMessageBox`) that logs incoming messages, and a **Disconnect**
  button.

```qml
QGCButton {
    id: connectButton
    visible: tcpConnectionState !== "connected"
    text: tcpConnecting ? qsTr("Connecting...") : qsTr("Connect")
    enabled: !tcpConnecting

    onClicked: {
        if (ipAddressField.text.length === 0 || portField.text.length === 0) {
            tcpErrorMessage = qsTr("IP address and port are required.")
            tcpConnectionState = "error"
            return
        }
        tcpConnecting = true
        tcpConnectionState = "connecting"
        tcpErrorMessage = ""
        TcpManager.connectToServer(ipAddressField.text, Number(portField.text))
    }
}
```

**TCP signal connections** — updates the QML state and sends the FlyView size once connected:

```qml
Connections {
    target: TcpManager

    function onConnected() {
        console.log("TCP: Connected to server")
        tcpConnecting = false
        tcpConnectionState = "connected"
        tcpErrorMessage = ""

        // Send FlyView coordinate-space dimensions
        var flyViewWidth = Math.round(width)
        var flyViewHeight = Math.round(height)
        var sizeMessage = "SIZE," + flyViewWidth + "," + flyViewHeight + "\n"
        TcpManager.sendMessage(sizeMessage)
    }

    function onDisconnected() {
        console.log("TCP: Disconnected from server")
        tcpConnecting = false
        if (tcpConnectionState !== "connected") {
            tcpConnectionState = "error"
            tcpErrorMessage = qsTr("Connection to the server was lost.")
        }
    }

    function onMessageReceived(message) {
        console.log("TCP message received:", message)
        serverMessageBox.text += message + "\n"
        serverMessageBox.cursorPosition = serverMessageBox.length
    }

    function onErrorOccurred(error) {
        console.log("TCP error:", error)
        tcpConnecting = false
        tcpConnectionState = "error"
        tcpErrorMessage = error.toString()
    }
}
```

### 4.5 Video Click Override (`FlyViewVideo.qml`)

See [3.6 Primary Stream QML Adjustments](#36-primary-stream-qml-adjustments) — the video's click
handlers now send `CLICK,x,y` via `TcpManager` instead of controlling the gimbal.

---

## 5. Feature C — AMAN Sensor Telemetry

### 5.1 Vehicle MAVLink Decoding (`Vehicle.h` / `Vehicle.cc`)

`Vehicle` gains six read-only properties (three-axis gyro + accelerometer) updated whenever the
custom `MAVLINK_MSG_ID_AMAN_SENSOR_DATA` message arrives.

**`Vehicle.h`** — declarations:

```cpp
//Aman Sensor Data Custom Property setup for reading the data from mavLink
Q_PROPERTY(double amanGyroX READ amanGyroX NOTIFY amanSensorDataChanged)
Q_PROPERTY(double amanGyroY READ amanGyroY NOTIFY amanSensorDataChanged)
Q_PROPERTY(double amanGyroZ READ amanGyroZ NOTIFY amanSensorDataChanged)

Q_PROPERTY(double amanAccX READ amanAccX NOTIFY amanSensorDataChanged)
Q_PROPERTY(double amanAccY READ amanAccY NOTIFY amanSensorDataChanged)
Q_PROPERTY(double amanAccZ READ amanAccZ NOTIFY amanSensorDataChanged)
```

accessors and backing storage:

```cpp
//Custom Data Objects
double amanGyroX() const { return _amanGyroX; }
double amanGyroY() const { return _amanGyroY; }
double amanGyroZ() const { return _amanGyroZ; }

double amanAccX() const { return _amanAccX; }
double amanAccY() const { return _amanAccY; }
double amanAccZ() const { return _amanAccZ; }
```

```cpp
double _amanGyroX = 0.0;     //Custom Public Variables for Aman Sensor Data - Gives Gyroscope X value
double _amanGyroY = 0.0;     //Custom Public Variables for Aman Sensor Data - Gives Gyroscope Y value
double _amanGyroZ = 0.0;     //Custom Public Variables for Aman Sensor Data - Gives Gyroscope Z value

double _amanAccX = 0.0;
double _amanAccY = 0.0;
double _amanAccZ = 0.0;
```

and the signal:

```cpp
signals:
    void amanSensorDataChanged();
```

**`Vehicle.cc`** — the message handler decodes the custom message and updates the values:

```cpp
case MAVLINK_MSG_ID_AMAN_SENSOR_DATA:
    {
        mavlink_aman_sensor_data_t sensorData;

        mavlink_msg_aman_sensor_data_decode(&message, &sensorData);

        _amanGyroX = sensorData.gyro_x;
        _amanGyroY = sensorData.gyro_y;
        _amanGyroZ = sensorData.gyro_z;

        _amanAccX = sensorData.acc_x;
        _amanAccY = sensorData.acc_y;
        _amanAccZ = sensorData.acc_z;

        emit amanSensorDataChanged();

        break;
    }
```

> Note: this requires `mavlink_aman_sensor_data_t` (and the `MAVLINK_MSG_ID_AMAN_SENSOR_DATA`
> enum) to exist in the generated MAVLink dialect used by the build. If the dialect doesn't
> define it, add the message definition to the custom message set before building.

### 5.2 Sensor Display UI (`FlyView.qml`)

A collapsible panel ("Show Sensor Data" button, top-right) renders the six values live, reading
from `_activeVehicle` and formatting to 6 decimals (with a safe `0.000000` fallback when no
vehicle is connected):

```qml
QGCLabel {
    text: qsTr("Gyro X: %1").arg(
        _activeVehicle
        ? _activeVehicle.amanGyroX.toFixed(6)
        : "0.000000"
    )
}
```

The same pattern is repeated for Gyro Y/Z and Acc X/Y/Z inside `amanSensorDataPanel`.

---

## 6. Build Integration (CMake)

**`src/CMakeLists.txt`** — add the new TCP sources to the QGC QML module:

```cmake
SOURCES TCP/TcpClient.cpp
SOURCES TCP/TcpClient.h
SOURCES TCP/TcpManager.h
SOURCES TCP/TcpManager.cpp
```

**`src/FlyView/CMakeLists.txt`** — register the two new stream-2 QML files:

```cmake
FlightDisplayViewVideoSecondOutput.qml
...
FlyViewVideoSecond.qml
```

**`test/VideoManager/CMakeLists.txt`** — register the stream-2 test:

```cmake
VideoManagerSecondStreamTest.cc
VideoManagerSecondStreamTest.h
...
add_qgc_test(VideoManagerSecondStreamTest LABELS Unit)
```

---

## 7. Automated Tests

`test/VideoManager/VideoManagerSecondStreamTest.{h,cc}` exercises the pure-layout logic without
needing a live GStreamer backend, using a `MockVideoReceiver` that stubs out all virtuals.

```cpp
class MockVideoReceiver : public VideoReceiver
{
public:
    MockVideoReceiver(const QString &name, QObject *parent = nullptr)
        : VideoReceiver(parent)
    {
        setName(name);
    }

    void start(uint32_t) override {}
    void stop() override {}
    void startDecoding(VideoSinkHandle) override {}
    void stopDecoding() override {}
    void startRecording(const QString &, FILE_FORMAT) override {}
    void stopRecording() override {}
    void takeScreenshot(const QString &) override {}
};
```

Four test cases (run with `ctest -R VideoManagerSecondStream` or
`build/Debug/QGroundControl --gtest_filter=VideoManagerSecondStreamTest.*`):

| Test | Verifies |
|------|----------|
| `_testStreamConfigured2` | `streamConfigured2()` is false for disabled sources and true once a source+URL is set (UDP/RTSP/TCP). |
| `_testHasVideo2` | `hasVideo2()` reflects the stream-2 configuration. |
| `_testShouldStartReceiver` | `_shouldStartReceiver()` gates primary/thermal on stream-1 config and stream-2 on its own config. |
| `_testUpdateSettingsRouting` | `_updateSettings()` builds the correct URI (`udp://`, `rtsp://`, or empty) for stream-2 receivers. |

The test class is a friend of `VideoManager` (added in `VideoManager.h`) so it can call the
private helpers:

```cpp
friend class VideoManagerSecondStreamTest;
```

---

## 8. Replication Checklist

To reproduce this exact feature set on another QGroundControl checkout (branch `Stable_V5.1` or
later):

1. **Settings**
   - Add `videoSource2`, `udpUrl2`, `rtspUrl2`, `tcpUrl2` to `src/Settings/Video.SettingsGroup.json`.
   - Add the `DEFINE_SETTINGFACT`s, `streamConfigured2` property/signal in `VideoSettings.h`.
   - Implement the four fact accessors, `streamConfigured2()` (incl. the UVC-device check), defaults,
     and `_configChanged` emission in `VideoSettings.cc`.
   - Add the `videoSource2` binding + "Second Video Source"/"Second Connection" groups to
     `src/AppSettings/pages/Video.SettingsUI.json` (re-generated into `VideoSettings.qml` on build).

2. **VideoManager**
   - Add `"secondContentVideo"` to the `videoStreamList` in `_createVideoReceivers()`.
   - Add `hasVideo2()`, `secondStreamDecoding`, `isUvc2`/`uvcVideoSourceID2` (Q_PROPERTYs +
     `_uvcVideoSourceID2`), `_isPrimaryStream/_isSecondStream/_isNetworkStreamSource`,
     `_shouldStartReceiver`, `_lastHasVideo/_lastHasVideo2` in `VideoManager.h`.
   - Rewrite `_videoSourceChanged()`, add the stream-2 branch (incl. `_updateUVC2()` call) in
     `_updateSettings()`, implement `_updateUVC2()`, guard `_updateUVC`/`_updateAutoStream`/
     `_setActiveVehicle`, and route the receiver signals by stream in `VideoManager.cc`.

3. **QML display**
   - Create `FlightDisplayViewVideoSecondOutput.qml` (tagged `secondContentVideo`).
   - Create `FlyViewVideoSecond.qml` (PipState wrapper); toggle between the GStreamer output and
     `FlightDisplayViewUVC` on `isUvc2` for webcam support.
   - Parameterize `FlightDisplayViewUVC.qml` with `cameraSourceId`/`cameraActive`.
   - Register the new files in `src/FlyView/CMakeLists.txt`.

4. **FlyView / PipView**
   - Add the single-item mode + `showWhenItem1Full` + `pipMouseEnabled` to `PipView.qml`.
   - Add `videoControl2`, `_pipView2`, the pip-coordination `Connections` (map into `_pipView2`
     while stream 2 is full; stream 1 stays bottom-left), `pipMouseEnabled` binding, and the
     TCP/AMAN UI to `FlyView.qml`.

5. **TCP**
   - Add `src/TCP/TcpClient.{h,cpp}` and `src/TCP/TcpManager.{h,cpp}`.
   - Register them in `src/CMakeLists.txt`.
   - Instantiate + expose `TcpManager` in `QGCCorePlugin::createQmlApplicationEngine`.
   - Add the TCP UI and click handlers in `FlyView.qml` / `FlyViewVideo.qml`.

6. **AMAN telemetry** (optional)
   - Ensure `mavlink_aman_sensor_data_t` exists in the MAVLink dialect.
   - Add the decode case + Q_PROPERTYs in `Vehicle.{h,cc}`.
   - Add the sensor panel in `FlyView.qml`.

7. **Tests** (optional)
   - Add `VideoManagerSecondStreamTest.{h,cc}` and register it in
     `test/VideoManager/CMakeLists.txt`; add `friend class VideoManagerSecondStreamTest;` to
     `VideoManager`.

8. **Verify**
   - `just build` (or `cmake --build build`).
   - `ctest -R VideoManagerSecondStream` for the unit tests.
   - Launch, go to **Settings → Video**, pick a source for the second stream, set its URL, and
     confirm the bottom-right pip box appears in the Fly View.

---

## 9. Configuration & Usage Guide

### Second video stream

1. Open **Settings → Video**.
2. Set **Source 2** (e.g. `UDP 264`, `UDP 265`, `RTSP`, `TCP`, `MPEG-TS`, or an attached webcam).
3. Fill in the matching **UDP URL 2 / RTSP URL 2 / TCP URL 2** (e.g. `0.0.0.0:5601`,
   `rtsp://192.168.42.1:554/live2`, `192.168.143.200:3002`). Webcam sources need no URL.
4. Ensure the master **stream enabled** toggle is on.
5. In the Fly View the stream appears in a **bottom-right pip box**.
   - Click the box → stream 2 goes full screen; the **map** drops into the bottom-right pip box
     and stream 1 stays pip'd bottom-left.
   - Click the map box (bottom-right) → stream 2 exits full screen and the map returns to full
     view.
   - Click the stream-1 box (bottom-left) → stream 2 exits full screen and **stream 1** returns
     to full view.
   - Picking an attached webcam as Source 2 shows the camera feed in the bottom-right box (no
     GStreamer needed); both streams can use webcams simultaneously.

### TCP click-to-target

1. Click **TCP Server** (top-center button in the Fly View).
2. Enter the server IP and port (defaults `127.0.0.1:5000`) and click **Connect**.
3. On success you get Action A/B/C buttons, an incoming-message log, and a Disconnect button.
4. Clicking the map or the primary video sends `CLICK,<x>,<y>\n`; on connect a `SIZE,WxH\n`
   message is sent first so the server knows the coordinate space.

### AMAN sensor data

Click **Show Sensor Data** (top-right) to display live gyro/accel values decoded from
`MAVLINK_MSG_ID_AMAN_SENSOR_DATA`.

---

## 10. Notes & Known Cosmetic Changes

- `src/FlyView/FlyView.qml` and `src/Toolbar/FlyViewToolBar.qml` also contain **whitespace-only
  reformatting** (blank lines collapsed) that has no functional effect — do not mistake it for
  feature work when diffing.
- `FlyViewToolBar.qml` has no functional changes at all.
- The `MavlinkCameraControlInterface.THERMAL_*` helpers (`pipOrNot`) were removed from
  `FlightDisplayViewVideo.qml` during the refactor; thermal pip positioning now relies on the
  standard anchor logic. Re-introduce if thermal pip placement regresses on your target firmware.
- The TCP manager is created as a child of the QML engine; it is a **per-engine singleton**, not
  a `QML_SINGLETON`, so it is accessed from QML via the `TcpManager` context property name.
