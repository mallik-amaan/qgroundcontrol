import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Controls

Item {
    id:   root
    clip: true

    property bool useSmallFont: true

    property double _ar:                (cameraLoader.visible && cameraLoader.status === Loader.Ready)
                                            ? cameraLoader.item.implicitWidth / cameraLoader.item.implicitHeight
                                            : QGroundControl.videoManager.aspectRatio
    property bool   _showGrid:          QGroundControl.settingsManager.videoSettings.gridLines.rawValue
    property var    _dynamicCameras:    globals.activeVehicle ? globals.activeVehicle.cameraManager : null
    property bool   _connected:         globals.activeVehicle ? !globals.activeVehicle.communicationLost : false
    property int    _curCameraIndex:    _dynamicCameras ? _dynamicCameras.currentCamera : 0
    property bool   _isCamera:          _dynamicCameras ? _dynamicCameras.cameras.count > 0 : false
    property var    _camera:            _isCamera ? _dynamicCameras.cameras.get(_curCameraIndex) : null
    property bool   _hasZoom:           _camera && _camera.hasZoom
    property int    _fitMode:           QGroundControl.settingsManager.videoSettings.videoFit.rawValue
    property bool   _showStreamLoader:  QGroundControl.videoManager.decoding
    property bool   _showUvcLoader:     QGroundControl.videoManager.isUvc

    property bool   _isMode_FIT_WIDTH:  _fitMode === 0
    property bool   _isMode_FIT_HEIGHT: _fitMode === 1
    property bool   _isMode_FILL:       _fitMode === 2
    property bool   _isMode_NO_CROP:    _fitMode === 3

    property bool   _anyStream:         _showStreamLoader || _showUvcLoader

    function getWidth() {
        return videoBackground.getWidth()
    }
    function getHeight() {
        return videoBackground.getHeight()
    }

    property double _thermalHeightFactor: 0.85

    // No Video Background
    Image {
        id:             noVideo
        anchors.fill:   parent
        source:         "/res/NoVideoBackground.jpg"
        fillMode:       Image.PreserveAspectCrop
        visible:        !root._anyStream

        Rectangle {
            anchors.centerIn:   parent
            width:              noVideoLabel.contentWidth + ScreenTools.defaultFontPixelHeight
            height:             noVideoLabel.contentHeight + ScreenTools.defaultFontPixelHeight
            radius:             ScreenTools.defaultFontPixelWidth / 2
            color:              "black"
            opacity:            0.5
        }

        QGCLabel {
            id:                 noVideoLabel
            text:               QGroundControl.settingsManager.videoSettings.streamEnabled.rawValue ? qsTr("WAITING FOR VIDEO") : qsTr("VIDEO DISABLED")
            font.bold:          true
            color:              "white"
            font.pointSize:     useSmallFont ? ScreenTools.smallFontPointSize : ScreenTools.largeFontPointSize
            anchors.centerIn:   parent
        }
    }

    // Main Video Background Container
    Rectangle {
        id:             videoBackground
        anchors.fill:   parent
        color:          "black"
        visible:        root._anyStream

        function getWidth() {
            if (_ar != 0.0) {
                if (_isMode_FIT_HEIGHT || (_isMode_FILL && (root.width / root.height < _ar)) || (_isMode_NO_CROP && (root.width / root.height > _ar))) {
                    return root.height * _ar
                }
            }
            return root.width
        }

        function getHeight() {
            if (_ar != 0.0) {
                if (_isMode_FIT_WIDTH || (_isMode_FILL && (root.width / root.height > _ar)) || (_isMode_NO_CROP && (root.width / root.height < _ar))) {
                    return root.width * (1 / _ar)
                }
            }
            return root.height
        }

        // =========================================================================
        // STREAM 1: Primary Stream ("videoContent")
        // =========================================================================
        Loader {
            id:                 videoStreamLoader
            anchors.fill:       parent
            visible:            _showStreamLoader
            sourceComponent:    videoOutputComponent

            onLoaded: { if (item) item.objectName = "videoContent" }
        }

        Component {
            id: videoOutputComponent
            FlightDisplayViewVideoOutput {}
        }

        // =========================================================================
        // UVC Loader (USB Camera)
        // =========================================================================
        Loader {
            id:             cameraLoader
            anchors.fill:   parent
            visible:        _showUvcLoader
            source:         _showUvcLoader ? "qrc:/qml/QGroundControl/FlyView/FlightDisplayViewUVC.qml" : "qrc:/qml/QGroundControl/FlyView/FlightDisplayViewDummy.qml"
        }

        // On-Screen Grid Lines Overlay
        Item {
            id:                 videoContentArea
            height:             parent.getHeight()
            width:              parent.getWidth()
            anchors.centerIn:   parent
            visible:            root._anyStream

            Item {
                anchors.fill:   parent
                visible:        _showGrid && !QGroundControl.videoManager.fullScreen

                Rectangle { color: Qt.rgba(1,1,1,0.5); height: parent.height; width: 1; x: parent.width * 0.33 }
                Rectangle { color: Qt.rgba(1,1,1,0.5); height: parent.height; width: 1; x: parent.width * 0.66 }
                Rectangle { color: Qt.rgba(1,1,1,0.5); width: parent.width; height: 1; y: parent.height * 0.33 }
                Rectangle { color: Qt.rgba(1,1,1,0.5); width: parent.width; height: 1; y: parent.height * 0.66 }
            }
        }

        // Thermal Camera Overlay (Optional Stream 3)
        Item {
            id:                 thermalItem
            width:              height * QGroundControl.videoManager.thermalAspectRatio
            height:             _camera ? (_camera.thermalMode === MavlinkCameraControlInterface.THERMAL_FULL ? parent.height : (_camera.thermalMode === MavlinkCameraControlInterface.THERMAL_PIP ? ScreenTools.defaultFontPixelHeight * 12 : parent.height * _thermalHeightFactor)) : 0
            anchors.centerIn:   parent
            visible:            QGroundControl.videoManager.hasThermal && _camera && _camera.thermalMode !== MavlinkCameraControlInterface.THERMAL_OFF

            Loader {
                id:             thermalVideo
                anchors.fill:   parent
                opacity:        _camera ? (_camera.thermalMode === MavlinkCameraControlInterface.THERMAL_BLEND ? _camera.thermalOpacity / 100 : 1.0) : 0
                sourceComponent: thermalOutputComponent

                onLoaded: {
                    if (item) item.objectName = "thermalVideo"
                }

                Component {
                    id: thermalOutputComponent
                    FlightDisplayViewVideoOutput {}
                }
            }
        }

        // Pinch to Zoom Area
        PinchArea {
            id:             pinchZoom
            enabled:        _hasZoom
            anchors.fill:   parent
            onPinchStarted: pinchZoom.zoom = 0
            onPinchUpdated: {
                if (_hasZoom) {
                    var z = (pinch.scale < 1) ? Math.round(pinch.scale * -10) : Math.round(pinch.scale)
                    if (pinchZoom.zoom != z) {
                        _camera.stepZoom(z)
                    }
                }
            }
            property int zoom: 0
        }
    }
}
