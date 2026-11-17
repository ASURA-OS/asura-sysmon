import QtQuick
import qs.Ui.Singletons
import QtQuick.Controls

Item {
    id: tab
    property var stats
    property var app

    readonly property string fontUi: Tokens.ui
    readonly property string fontMono: Tokens.mono

    Flickable {
        anchors.fill: parent
        anchors.margins: 16
        contentWidth: width
        contentHeight: Math.max(col.implicitHeight + 20, height)
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: 16

            Rectangle {
                width: parent.width
                height: 110
                radius: 8
                color: Tokens.paperLift
                border.color: Tokens.lineSoft
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 20

                    Image {
                        width: 56
                        height: 56
                        source: "/usr/share/asura/branding/asura-logo-on-dark.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: "ASURA OS"
                            color: Tokens.ink
                            font.family: tab.fontUi
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "Pure Monochrome Desktop Operating System"
                            color: Tokens.inkDim
                            font.family: tab.fontUi
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 310
                radius: 8
                color: Tokens.paperLift
                border.color: Tokens.lineSoft
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "System Specifications"
                        color: Tokens.inkDim
                        font.family: tab.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    Rectangle { width: parent.width; height: 1; color: Tokens.lineSoft }

                    Grid {
                        width: parent.width
                        columns: 2
                        rowSpacing: 12
                        columnSpacing: 20

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Operating System"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: "ASURA OS"; color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontUi; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "System Uptime"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: tab.app.fmtUptime(tab.stats ? tab.stats.uptimeSecs : 0); color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontMono; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Total Memory"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: tab.app.fmtBytes(tab.stats && tab.stats.memory ? tab.stats.memory.totalBytes : 0); color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontMono; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Processor Cores"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: (tab.stats && tab.stats.cpu && tab.stats.cpu.cores ? tab.stats.cpu.cores.length : "0") + " Logical Cores"; color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontUi; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Window Compositor"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: "Hyprland (Wayland)"; color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontUi; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Load Average"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text { text: tab.stats && tab.stats.loadAvg ? tab.stats.loadAvg[0].toFixed(2) + " (1m), " + tab.stats.loadAvg[1].toFixed(2) + " (5m)" : "0.00"; color: Tokens.ink; font.pixelSize: 13; font.family: tab.fontMono; font.weight: Font.Medium }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Graphics Adapters"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text {
                                text: tab.stats && tab.stats.gpus && tab.stats.gpus.length > 0 ? tab.stats.gpus.map(function(g){ return g.name; }).join(" · ") : "Virtual / Host Framebuffer"
                                color: Tokens.ink
                                font.pixelSize: 12
                                font.family: tab.fontUi
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Column {
                            width: (parent.width - 20) / 2
                            spacing: 2
                            Text { text: "Power Source"; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi }
                            Text {
                                text: tab.stats && tab.stats.batteries && tab.stats.batteries.length > 0 ? tab.stats.batteries.map(function(b){ return b.name + " (" + Math.round(b.percentage) + "% · " + (b.healthPct > 0 ? Math.round(b.healthPct) + "% Health" : b.status) + ")"; }).join(", ") : "AC Mains Power"
                                color: Tokens.ink
                                font.pixelSize: 12
                                font.family: tab.fontUi
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }
                }
            }
        }
    }
}
