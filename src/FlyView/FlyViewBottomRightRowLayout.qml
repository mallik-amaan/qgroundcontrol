import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView

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
         showBackground:         _root.showBackground

     }
}
