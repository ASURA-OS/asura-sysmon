import QtQuick
import qs.Ui.Singletons
import QtQuick.Controls

Item {
    id: tab
    property var disks: []
    property var diskIO: ({ readBytesSec: 0, writeBytesSec: 0, readIOPS: 0, writeIOPS: 0, devices: [] })
    property var app

    readonly property string fontUi: Tokens.ui
    readonly property string fontMono: Tokens.mono

    Flickable {
        anchors.fill: parent
        anchors.margins: 16
        contentWidth: width
        contentHeight: Math.max(flow.implicitHeight + 20, height)
        clip: true

        Column {
            id: flow
            width: parent.width
            spacing: 14

            // ── Top Bar: Live Disk I/O Activity ──
            Rectangle {
                width: parent.width
                height: 80
                radius: 8
                color: Tokens.paperLift
                border.color: Tokens.lineSoft
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 16

                    Column {
                        width: (parent.width - 32) / 3
                        spacing: 3
                        Text { text: "Disk Read"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi; font.weight: Font.Medium }
                        Text { text: tab.app.fmtRate(tab.diskIO ? tab.diskIO.readBytesSec : 0); color: Tokens.ink; font.pixelSize: 16; font.weight: Font.Bold; font.family: tab.fontMono }
                        Text { text: tab.diskIO ? Math.round(tab.diskIO.readIOPS) + " IOPS" : "0 IOPS"; color: Tokens.inkFaint; font.pixelSize: 11; font.family: tab.fontMono }
                    }

                    Rectangle { width: 1; height: parent.height; color: Tokens.lineSoft }

                    Column {
                        width: (parent.width - 32) / 3
                        spacing: 3
                        Text { text: "Disk Write"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi; font.weight: Font.Medium }
                        Text { text: tab.app.fmtRate(tab.diskIO ? tab.diskIO.writeBytesSec : 0); color: Tokens.ink; font.pixelSize: 16; font.weight: Font.Bold; font.family: tab.fontMono }
                        Text { text: tab.diskIO ? Math.round(tab.diskIO.writeIOPS) + " IOPS" : "0 IOPS"; color: Tokens.inkFaint; font.pixelSize: 11; font.family: tab.fontMono }
                    }

                    Rectangle { width: 1; height: parent.height; color: Tokens.lineSoft }

                    Column {
                        width: (parent.width - 32) / 3
                        spacing: 3
                        Text { text: "Physical Storage Drives"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi; font.weight: Font.Medium }
                        Text { text: (tab.diskIO && tab.diskIO.devices ? tab.diskIO.devices.length : 0) + " Block Devices"; color: Tokens.ink; font.pixelSize: 16; font.weight: Font.Bold; font.family: tab.fontUi }
                        Text { text: tab.diskIO && tab.diskIO.devices ? tab.diskIO.devices.map(function(d){ return d.device; }).join(", ") : "None"; color: Tokens.inkFaint; font.pixelSize: 11; font.family: tab.fontMono; elide: Text.ElideRight }
                    }
                }
            }

            Text {
                text: "Storage Partitions & Mounts"
                color: Tokens.inkDim
                font.family: tab.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Repeater {
                model: tab.disks
                delegate: Rectangle {
                    required property var modelData
                    width: flow.width
                    height: 84
                    radius: 8
                    color: Tokens.paperLift
                    border.color: Tokens.lineSoft
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 20

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    text: modelData.mountPoint
                                    color: Tokens.ink
                                    font.family: tab.fontUi
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "(" + modelData.device + " · " + modelData.fsType + ")"
                                    color: Tokens.inkFaint
                                    font.family: tab.fontMono
                                    font.pixelSize: 11
                                    anchors.baseline: parent.children[0].baseline
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.app.fmtBytes(modelData.usedBytes) + " / " + tab.app.fmtBytes(modelData.totalBytes) + " (" + Math.round(modelData.usedPercent) + "%)"
                                color: Tokens.ink
                                font.family: tab.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 8
                            radius: 4
                            color: Tokens.lineSoft
                            Rectangle {
                                width: parent.width * Math.min(1.0, modelData.usedPercent / 100.0)
                                height: parent.height
                                radius: 4
                                // Red when nearly full, so a filling disk stands out. Read-only
                                // images (squashfs, ISO, EROFS) are always full by design.
                                color: modelData.usedPercent >= 90 && ["squashfs", "iso9660", "erofs"].indexOf(modelData.fsType) < 0 ? Tokens.alert : Tokens.ink
                            }
                        }

                        Row {
                            width: parent.width
                            Text {
                                text: "Free: " + tab.app.fmtBytes(modelData.freeBytes)
                                color: Tokens.inkDim
                                font.family: tab.fontUi
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Text {
                visible: tab.disks.length === 0
                text: "No mounted storage disks detected"
                color: Tokens.inkFaint
                font.family: tab.fontUi
                font.pixelSize: 12
            }
        }
    }
}
