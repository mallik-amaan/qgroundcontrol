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
