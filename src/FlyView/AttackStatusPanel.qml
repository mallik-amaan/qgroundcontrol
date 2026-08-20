import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Standalone attack status window. Opens when the vehicle enters attack mode and
/// auto-closes a few seconds after the payload is released or the drone crashes.
Popup {
    id:             _root
    modal:          false
    focus:          false
    dim:            false
    closePolicy:    Popup.NoAutoClose
    padding:        ScreenTools.defaultFontPixelWidth

    QGCPalette {
        id: qgcPal
    }

    property var  _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool _finalShown:    false
    property bool _finalIsCrash:  false

    onOpened: {
        _root.x = Math.round((parent.width - _root.width) / 2)
        _root.y = ScreenTools.defaultFontPixelHeight
    }

    Connections {
        target: _activeVehicle

        function onAttackEngagementActiveChanged() {
            if (_activeVehicle && _activeVehicle.attackEngagementActive) {
                _finalShown = false
                _autoCloseTimer.stop()
                _root.open()
            } else if (!_finalShown) {
                // Engagement ended without release or crash (cancelled)
                _root.close()
            }
        }

        function onPayloadReleased() {
            _finalShown = true
            _finalIsCrash = false
            _autoCloseTimer.restart()
        }

        function onAttackCrashExecuted() {
            _finalShown = true
            _finalIsCrash = true
            _autoCloseTimer.restart()
        }
    }

    Timer {
        id: _autoCloseTimer
        interval: 4000
        onTriggered: _root.close()
    }

    background: Rectangle {
        radius: ScreenTools.defaultFontPixelHeight / 2
        color:  qgcPal.window
        border.color: qgcPal.text
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: ScreenTools.defaultFontPixelHeight / 4

        QGCLabel {
            text: qsTr("Attack status")
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel { text: qsTr("Range") }
            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: _activeVehicle.attackRangeCheckPassed ? qsTr("\u2713") : qsTr("\u2717")
                color: _activeVehicle.attackRangeCheckPassed ? "lime" : "red"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel {
                Layout.fillWidth: true
                text: qsTr("%1 / %2 m").arg(_activeVehicle.attackDistance.toFixed(0)).arg(_activeVehicle.attackMaxRange.toFixed(0))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel { text: qsTr("Heading") }
            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: _activeVehicle.attackHeadingCheckPassed ? qsTr("\u2713") : qsTr("\u2717")
                color: _activeVehicle.attackHeadingCheckPassed ? "lime" : "red"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: _activeVehicle !== null && _activeVehicle.attackEngagementActive
            QGCLabel { text: qsTr("Elevation") }
            QGCLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: _activeVehicle.attackElevationAngleCheckPassed ? qsTr("\u2713") : qsTr("\u2717")
                color: _activeVehicle.attackElevationAngleCheckPassed ? "lime" : "red"
            }
        }

        QGCLabel {
            Layout.fillWidth: true
            text: _finalIsCrash ? qsTr("Drone crashed at target") : qsTr("Payload released")
            visible: _finalShown
            font.bold: true
            color: _finalIsCrash ? "red" : "lime"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
