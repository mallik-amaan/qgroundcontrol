import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

Item {
    id: _root

    readonly property bool _is3DMode: QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // These should only be used by MainRootWindow
    property var planController: _planController
    property var guidedController: _guidedController


    property bool tcpConnecting: false
    property string tcpConnectionState: "disconnected"
    property string tcpErrorMessage: ""


    QGCPalette {
        id: qgcPal
    }

    PlanMasterController {
        id: _planController
        flyView: true
        Component.onCompleted: start()
    }

    property bool _mainWindowIsMap: mapControl.pipState.state === mapControl.pipState.fullState
    property bool _isFullWindowItemDark: _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property var _missionController: _planController.missionController
    property var _geoFenceController: _planController.geoFenceController
    property var _rallyPointController: _planController.rallyPointController
    property real _margins: ScreenTools.defaultFontPixelWidth / 2
    property var _guidedController: guidedActionsController
    property var _guidedValueSlider: guidedValueSlider
    property var _widgetLayer: widgetLayer
    property real _toolsMargin: ScreenTools.defaultFontPixelWidth * 0.75
    property rect _centerViewport: Qt.rect(0, 0, width, height)
    property real _rightPanelWidth: ScreenTools.defaultFontPixelWidth * 30
    property var _mapControl: mapControl
    property real _widgetMargin: ScreenTools.defaultFontPixelWidth * 0.75

    property real _fullItemZorder: 0
    property real _pipItemZorder: QGroundControl.zOrderWidgets

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool()
    }

    QGCToolInsets {
        id: _toolInsets

        topEdgeLeftInset: toolbar.height
        topEdgeCenterInset: topEdgeLeftInset
        topEdgeRightInset: topEdgeLeftInset

        leftEdgeBottomInset: _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset: _pipView.bottomEdgeLeftInset
    }

    Item {
        id: mapHolder
        anchors.fill: parent

        FlyViewMap {
            id: mapControl

            planMasterController: _planController
            rightPanelWidth: ScreenTools.defaultFontPixelHeight * 9
            pipView: _pipView
            pipMode: !_mainWindowIsMap
            toolInsets: customOverlay.totalToolInsets
            mapName: "FlightDisplayView"

            enabled: !_is3DMode
            visible: !_is3DMode
        }

        FlyViewVideo {
            id: videoControl
            pipView: _pipView
        }

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
        PipView {
            id: _pipView

            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: _toolsMargin

            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1: mapControl
            item2: QGroundControl.videoManager.hasVideo ? videoControl : null

            show: QGroundControl.videoManager.hasVideo &&
                  !QGroundControl.videoManager.fullScreen &&
                  (
                      videoControl.pipState.state === videoControl.pipState.pipState ||
                      mapControl.pipState.state === mapControl.pipState.pipState
                  )


            z: QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + anchors.margins : 0
            property real bottomEdgeLeftInset: visible ? height + anchors.margins : 0
        }



        FlyViewWidgetLayer {
            id: widgetLayer

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: guidedValueSlider.visible ? guidedValueSlider.left : parent.right

            anchors.margins: _widgetMargin
            anchors.topMargin: toolbar.height + _widgetMargin

            z: _fullItemZorder + 2

            parentToolInsets: _toolInsets
            mapControl: _mapControl
            viewer3DCameraController: viewer3DLoader.item
                                        ? viewer3DLoader.item.cameraController
                                        : null

            visible: !QGroundControl.videoManager.fullScreen
        }

        FlyViewCustomLayer {
            id: customOverlay

            anchors.fill: widgetLayer

            z: _fullItemZorder + 2

            parentToolInsets: widgetLayer.totalToolInsets
            mapControl: _mapControl

            visible: !QGroundControl.videoManager.fullScreen
        }


        // ============================================================
        // TCP CONTROL
        // ============================================================

        Item {
            id: tcpControl

            width: 600

            height: tcpServerPanel.visible
                    ? tcpServerPanel.height + customTCPServerButton.height + 5
                    : customTCPServerButton.height

            anchors.top: parent.top
            anchors.topMargin: toolbar.height + 20
            anchors.horizontalCenter: parent.horizontalCenter

            z: QGroundControl.zOrderWidgets


            // --------------------------------------------------------
            // TCP SERVER BUTTON
            // --------------------------------------------------------

            QGCButton {
                id: customTCPServerButton

                width: 160
                height: 40

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                property bool showTcpServerDetails: false

                text: qsTr("TCP Server")

                onClicked: {
                    showTcpServerDetails = !showTcpServerDetails
                }
            }


            // --------------------------------------------------------
            // TCP SERVER PANEL
            // --------------------------------------------------------

            Rectangle {
                id: tcpServerPanel

                width: 600
                height: 400

                anchors.top: customTCPServerButton.bottom
                anchors.topMargin: 5
                anchors.horizontalCenter: parent.horizontalCenter

                visible: customTCPServerButton.showTcpServerDetails

                color: qgcPal.window

                border.color: qgcPal.text
                border.width: 1

                radius: ScreenTools.defaultBorderRadius


                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15

                    spacing: 10


                    // ====================================================
                    // TITLE
                    // ====================================================

                    QGCLabel {
                        text: qsTr("TCP Connection")

                        font.bold: true

                        Layout.alignment: Qt.AlignHCenter
                    }


                    Rectangle {
                        Layout.fillWidth: true

                        height: 1

                        color: qgcPal.text
                    }


                    // ====================================================
                    // IP ADDRESS
                    // ====================================================

                    RowLayout {
                        Layout.fillWidth: true
                        visible: tcpConnectionState !== "connected"
                        spacing: 10

                        QGCLabel {
                            text: qsTr("IP Address:")

                            Layout.preferredWidth: 100
                        }

                        QGCTextField {
                            id: ipAddressField
                            Layout.fillWidth: true

                            text: "127.0.0.1"

                            placeholderText: qsTr("Enter IP address")
                        }
                    }


                    // ====================================================
                    // PORT
                    // ====================================================

                    RowLayout {
                        Layout.fillWidth: true
                        visible: tcpConnectionState !== "connected"
                        spacing: 10

                        QGCLabel {
                            text: qsTr("Port:")

                            Layout.preferredWidth: 100
                        }

                        QGCTextField {
                            id: portField

                            Layout.fillWidth: true

                            text: "5000"

                            placeholderText: qsTr("Enter port")

                            inputMethodHints: Qt.ImhDigitsOnly
                        }
                    }


                    // ====================================================
                    // CONNECT BUTTON
                    // ====================================================

                    QGCButton {
                        id: connectButton
                        visible: tcpConnectionState !== "connected"
                        width: 160
                        height: 40

                        Layout.alignment: Qt.AlignHCenter

                        text: tcpConnecting
                              ? qsTr("Connecting...")
                              : qsTr("Connect")

                        enabled: !tcpConnecting

                        onClicked: {

                            if (ipAddressField.text.length === 0 ||
                                portField.text.length === 0) {

                                tcpErrorMessage =
                                    qsTr("IP address and port are required.")

                                tcpConnectionState = "error"

                                return
                            }


                            tcpConnecting = true

                            tcpConnectionState = "connecting"

                            tcpErrorMessage = ""


                            console.log(
                                "Connecting to:",
                                ipAddressField.text,
                                portField.text
                            )


                            TcpManager.connectToServer(
                                ipAddressField.text,
                                Number(portField.text)
                            )
                        }
                    }


                    // ====================================================
                    // CONNECTION STATUS
                    // ====================================================

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true


                        // ------------------------------------------------
                        // LOADING
                        // ------------------------------------------------

                        Column {
                            anchors.centerIn: parent

                            spacing: 10

                            visible: tcpConnectionState === "connecting"


                            BusyIndicator {
                                anchors.horizontalCenter: parent.horizontalCenter

                                running: true

                                width: 50
                                height: 50
                            }


                            QGCLabel {
                                text: qsTr("Connecting to server...")

                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }


                        // ------------------------------------------------
                        // ERROR
                        // ------------------------------------------------

                        Rectangle {
                            anchors.fill: parent

                            visible: tcpConnectionState === "error"

                            color: qgcPal.window

                            border.color: qgcPal.text

                            border.width: 1

                            radius: ScreenTools.defaultBorderRadius


                            Column {
                                anchors.centerIn: parent

                                spacing: 10

                                width: parent.width - 40


                                QGCLabel {
                                    text: qsTr("Connection Failed")

                                    font.bold: true

                                    anchors.horizontalCenter: parent.horizontalCenter
                                }


                                QGCLabel {
                                    text: tcpErrorMessage

                                    wrapMode: Text.Wrap

                                    horizontalAlignment: Text.AlignHCenter

                                    width: parent.width
                                }


                                QGCButton {
                                    text: qsTr("Try Again")

                                    anchors.horizontalCenter: parent.horizontalCenter

                                    onClicked: {
                                        tcpConnectionState = "connecting"
                                        console.log("Attempting TCP connection:", ipAddressField.text, portField.text)
                                        tcpConnecting = true

                                        TcpManager.connectToServer(
                                            ipAddressField.text,
                                            Number(portField.text)
                                        )
                                    }
                                }
                            }
                        }


                        // ------------------------------------------------
                        // CONNECTED WINDOW
                        // ------------------------------------------------

                        ColumnLayout {
                            anchors.fill: parent

                            spacing: 8

                            visible: tcpConnectionState === "connected"


                            RowLayout {
                                Layout.fillWidth: true

                                Layout.alignment: Qt.AlignHCenter

                                spacing: 10


                                QGCButton {
                                    width: 160
                                    height: 40

                                    text: qsTr("TCP Action A")

                                    onClicked: {
                                        TcpManager.sendMessage(
                                            "Button A Clicked"
                                        )
                                    }
                                }


                                QGCButton {
                                    width: 160
                                    height: 40

                                    text: qsTr("TCP Action B")

                                    onClicked: {
                                        TcpManager.sendMessage(
                                            "Button B Clicked"
                                        )
                                    }
                                }


                                QGCButton {
                                    width: 160
                                    height: 40

                                    text: qsTr("TCP Action C")

                                    onClicked: {
                                        TcpManager.sendMessage(
                                            "Button C Clicked"
                                        )
                                    }
                                }
                            }


                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                color: qgcPal.window

                                border.color: qgcPal.text

                                border.width: 1

                                radius: ScreenTools.defaultBorderRadius

                                clip: true


                                ScrollView {
                                    anchors.fill: parent

                                    anchors.margins: 4


                                    TextArea {
                                        id: serverMessageBox

                                        readOnly: true

                                        wrapMode: TextArea.Wrap

                                        text: ""

                                        selectByMouse: true
                                    }
                                }
                            }
                                QGCButton {
                                    width: 160
                                    height: 40

                                    Layout.alignment: Qt.AlignHCenter

                                    visible: tcpConnectionState === "connected"

                                    text: qsTr("Disconnect")

                                    onClicked: {
                                        console.log("TCP: Disconnecting from server")

                                        tcpConnectionState = "disconnected"
                                        TcpManager.disconnectFromServer()
                                    }
                                }

                        }
                    }
                }
            }
        }

        // ============================================================
        // SENSOR CONTROL
        // ============================================================

        Item {
            id: amanSensorControl

            width: 220

            height: amanSensorDataButton.height +
                    (
                        amanSensorDataButton.showData
                        ? amanSensorDataPanel.height + 5
                        : 0
                    )

            anchors.top: parent.top
            anchors.topMargin: toolbar.height + 20

            anchors.right: parent.right
            anchors.rightMargin: 20

            z: QGroundControl.zOrderWidgets


            QGCButton {
                id: amanSensorDataButton

                width: 160
                height: 40

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                property bool showData: false

                text: showData
                      ? qsTr("Hide Sensor Data")
                      : qsTr("Show Sensor Data")

                onClicked: {
                    showData = !showData
                }
            }


            // --------------------------------------------------------
            // SENSOR DATA PANEL
            // --------------------------------------------------------

            Rectangle {
                id: amanSensorDataPanel

                width: 220
                height: 190

                anchors.top: amanSensorDataButton.bottom
                anchors.topMargin: 5

                anchors.horizontalCenter:
                    amanSensorDataButton.horizontalCenter

                visible: amanSensorDataButton.showData

                color: qgcPal.window

                border.color: qgcPal.text
                border.width: 1

                radius: ScreenTools.defaultBorderRadius


                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10

                    spacing: 4


                    QGCLabel {
                        text: qsTr("AMAN Sensor Data")

                        font.bold: true

                        Layout.alignment: Qt.AlignHCenter
                    }


                    Rectangle {
                        Layout.fillWidth: true

                        height: 1

                        color: qgcPal.text
                    }


                    QGCLabel {
                        text: qsTr("Gyro X: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanGyroX.toFixed(6)
                            : "0.000000"
                        )
                    }


                    QGCLabel {
                        text: qsTr("Gyro Y: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanGyroY.toFixed(6)
                            : "0.000000"
                        )
                    }


                    QGCLabel {
                        text: qsTr("Gyro Z: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanGyroZ.toFixed(6)
                            : "0.000000"
                        )
                    }


                    QGCLabel {
                        text: qsTr("Acc X: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanAccX.toFixed(6)
                            : "0.000000"
                        )
                    }


                    QGCLabel {
                        text: qsTr("Acc Y: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanAccY.toFixed(6)
                            : "0.000000"
                        )
                    }


                    QGCLabel {
                        text: qsTr("Acc Z: %1").arg(
                            _activeVehicle
                            ? _activeVehicle.amanAccZ.toFixed(6)
                            : "0.000000"
                        )
                    }
                }
            }
        }


        // ============================================================
        // DEVELOPMENT TOOL
        // ============================================================

        FlyViewInsetViewer {
            id: widgetLayerInsetViewer

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: guidedValueSlider.visible
                            ? guidedValueSlider.left
                            : parent.right

            z: widgetLayer.z + 1

            insetsToView: widgetLayer.totalToolInsets

            visible: false
        }


        // ============================================================
        // GUIDED ACTIONS
        // ============================================================

        GuidedActionsController {
            id: guidedActionsController

            missionController: _missionController
            guidedValueSlider: _guidedValueSlider
        }


        // ============================================================
        // GUIDED VALUE SLIDER
        // ============================================================

        GuidedValueSlider {
            id: guidedValueSlider

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            anchors.topMargin: toolbar.height

            z: QGroundControl.zOrderTopMost

            visible: false
        }


        // ============================================================
        // 3D VIEWER
        // ============================================================

        Loader {
            id: viewer3DLoader

            z: 1

            anchors.fill: parent

            visible: _is3DMode
        }


        Connections {
            target: QGCViewer3DManager

            function onDisplayModeChanged() {

                if (QGCViewer3DManager.displayMode ===
                        QGCViewer3DManager.View3D) {

                    if (!viewer3DLoader.item) {

                        viewer3DLoader.setSource(
                            "qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml"
                        )
                    }

                } else if (!_keepSceneAlive) {

                    viewer3DLoader.source = ""
                }
            }
        }


        // ============================================================
        // TCP SIGNAL CONNECTIONS
        // ============================================================

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

                var sizeMessage =
                    "SIZE," +
                    flyViewWidth +
                    "," +
                    flyViewHeight +
                    "\n"

                console.log(
                    "TCP: Sending FlyView size:",
                    flyViewWidth,
                    "x",
                    flyViewHeight
                )

                TcpManager.sendMessage(sizeMessage)
            }

            function onDisconnected() {
                console.log("TCP: Disconnected from server")

                tcpConnecting = false

                if (tcpConnectionState !== "connected") {
                    tcpConnectionState = "error"
                    tcpErrorMessage =
                        qsTr("Connection to the server was lost.")
                }
            }

            function onMessageReceived(message) {
                console.log("TCP message received:", message)

                serverMessageBox.text += message + "\n"

                serverMessageBox.cursorPosition =
                    serverMessageBox.length
            }

            function onErrorOccurred(error) {
                console.log("TCP error:", error)

                tcpConnecting = false
                tcpConnectionState = "error"
                tcpErrorMessage = error.toString()
            }
        }
    }


    // ================================================================
    // FLY VIEW TOOLBAR
    // ================================================================

    FlyViewToolBar {
        id: toolbar

        guidedValueSlider: _guidedValueSlider

        visible: !QGroundControl.videoManager.fullScreen
    }
}


