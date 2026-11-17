import QtQuick
import qs.Ui.Singletons
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    color: Tokens.paper

    readonly property color alertWash: Qt.rgba(Tokens.alert.r, Tokens.alert.g, Tokens.alert.b, 0.14)

    readonly property string fontUi: Tokens.ui
    readonly property string fontMono: Tokens.mono

    property string currentTab: "performance" // performance, processes, storage, system
    property var stats: ({
        cpu: { usagePercent: 0, cores: [], tempC: 0 },
        memory: { totalBytes: 0, usedBytes: 0, availableBytes: 0, usedPercent: 0, cachedBytes: 0 },
        swap: { totalBytes: 0, usedBytes: 0, usedPercent: 0 },
        network: { rxBytes: 0, txBytes: 0, rxRateSec: 0, txRateSec: 0, interfaces: [] },
        disks: [],
        diskIO: { readBytesSec: 0, writeBytesSec: 0, readIOPS: 0, writeIOPS: 0, devices: [] },
        gpus: [],
        batteries: [],
        uptimeSecs: 0,
        loadAvg: [0, 0, 0]
    })
    property var processList: []
    property bool isPolling: true

    // Polls since the last good stats reading. A few in a row means the
    // backend is not answering, and the window says so instead of showing
    // zeros that look like real readings.
    property int pollsSinceData: 0
    readonly property bool statsStale: pollsSinceData >= 4

    readonly property var tabs: [
        { id: "performance", label: "Performance" },
        { id: "processes", label: "Processes" },
        { id: "storage", label: "Storage" },
        { id: "system", label: "System" }
    ]
    function selectTab(i) {
        if (i >= 0 && i < tabs.length) root.currentTab = tabs[i].id;
    }
    function cycleTab(step) {
        var i = 0;
        for (var k = 0; k < tabs.length; k++) if (tabs[k].id === root.currentTab) i = k;
        selectTab((i + step + tabs.length) % tabs.length);
    }

    Shortcut { sequence: "Ctrl+1"; onActivated: root.selectTab(0) }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.selectTab(1) }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.selectTab(2) }
    Shortcut { sequence: "Ctrl+4"; onActivated: root.selectTab(3) }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: root.cycleTab(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: root.cycleTab(-1) }
    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; onActivated: Qt.quit() }

    // Rolling historical buffers for real-time waveform curves (last 48 data points)
    property var cpuHistory: []
    property var netRxHistory: []
    property var netTxHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []

    Component.onCompleted: {
        // Pre-fill histories with initial zeroes for instant smooth rendering
        var initZeros = [];
        for (var i = 0; i < 48; i++) initZeros.push(0);
        cpuHistory = initZeros.slice();
        netRxHistory = initZeros.slice();
        netTxHistory = initZeros.slice();
        diskReadHistory = initZeros.slice();
        diskWriteHistory = initZeros.slice();
    }

    function recordTelemetry(parsed) {
        if (!parsed) return;
        var maxPts = 48;

        // CPU utilization history (0.0 to 1.0)
        var c = (parsed.cpu && parsed.cpu.usagePercent !== undefined) ? (parsed.cpu.usagePercent / 100.0) : 0;
        var hCpu = root.cpuHistory.slice();
        hCpu.push(c);
        if (hCpu.length > maxPts) hCpu.shift();
        root.cpuHistory = hCpu;

        // Network rates
        var rx = (parsed.network && parsed.network.rxRateSec !== undefined) ? parsed.network.rxRateSec : 0;
        var tx = (parsed.network && parsed.network.txRateSec !== undefined) ? parsed.network.txRateSec : 0;
        var hRx = root.netRxHistory.slice();
        hRx.push(rx);
        if (hRx.length > maxPts) hRx.shift();
        root.netRxHistory = hRx;

        var hTx = root.netTxHistory.slice();
        hTx.push(tx);
        if (hTx.length > maxPts) hTx.shift();
        root.netTxHistory = hTx;

        // Disk I/O rates
        var dr = (parsed.diskIO && parsed.diskIO.readBytesSec !== undefined) ? parsed.diskIO.readBytesSec : 0;
        var dw = (parsed.diskIO && parsed.diskIO.writeBytesSec !== undefined) ? parsed.diskIO.writeBytesSec : 0;
        var hDr = root.diskReadHistory.slice();
        hDr.push(dr);
        if (hDr.length > maxPts) hDr.shift();
        root.diskReadHistory = hDr;

        var hDw = root.diskWriteHistory.slice();
        hDw.push(dw);
        if (hDw.length > maxPts) hDw.shift();
        root.diskWriteHistory = hDw;
    }

    function fmtBytes(b) {
        if (!b || b <= 0) return "0 B";
        var k = 1024;
        var sizes = ["B", "KB", "MB", "GB", "TB"];
        var i = Math.floor(Math.log(b) / Math.log(k));
        if (i < 0) i = 0;
        if (i >= sizes.length) i = sizes.length - 1;
        return (b / Math.pow(k, i)).toFixed(i > 1 ? 1 : 0) + " " + sizes[i];
    }

    function fmtRate(b) {
        if (!b || b <= 0) return "0 B/s";
        return fmtBytes(b) + "/s";
    }

    function fmtUptime(secs) {
        if (!secs || secs <= 0) return "0m";
        var h = Math.floor(secs / 3600);
        var m = Math.floor((secs % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // Polling for live system stats
    Process {
        id: statsProc
        command: ["asura-sysmon", "stats", "--interval", "150"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed && parsed.cpu) {
                        root.stats = parsed;
                        root.recordTelemetry(parsed);
                        root.pollsSinceData = 0;
                    }
                } catch(e) {}
            }
        }
    }

    // Polling for active processes
    Process {
        id: procProc
        // Every process (search must find small ones too), with CPU usage
        // measured over 250 ms.
        command: ["asura-sysmon", "proc", "--limit", "0", "--interval", "250"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed && parsed.processes) {
                        root.processList = parsed.processes;
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 1200
        repeat: true
        running: root.isPolling
        triggeredOnStart: true
        onTriggered: {
            root.pollsSinceData++;
            if (!statsProc.running) statsProc.running = true;
            if (root.currentTab === "processes" && !procProc.running) {
                procProc.running = true;
            }
        }
    }

    onCurrentTabChanged: {
        if (root.currentTab === "processes" && !procProc.running) {
            procProc.running = true;
        }
    }

    // ── Header Bar ──────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 52
        color: Tokens.paperLift
        border.color: Tokens.lineSoft
        border.width: 1

        Row {
            id: brand
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Image {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                source: "/usr/share/asura/branding/asura-logo-on-dark.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                // Fallback text if image not accessible
                Text {
                    visible: parent.status !== Image.Ready
                    anchors.centerIn: parent
                    text: "\u25c8"
                    color: Tokens.ink
                    font.pixelSize: 16
                }
            }

            Text {
                text: "Resource Monitor"
                color: Tokens.ink
                font.family: root.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 1
                height: 18
                color: Tokens.lineSoft
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "ASURA OS"
                color: Tokens.inkFaint
                font.family: root.fontMono
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 1.5
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Navigation Tabs: centred, but never over the title on a narrow window.
        Row {
            x: Math.max(brand.x + brand.width + 16, (parent.width - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: root.tabs

                delegate: Rectangle {
                    required property var modelData
                    width: tabText.implicitWidth + 24
                    height: 32
                    radius: 6
                    color: root.currentTab === modelData.id ? Tokens.tint10 : (tabMouse.containsMouse ? Tokens.tint5 : "transparent")
                    border.color: root.currentTab === modelData.id ? Tokens.line : "transparent"
                    border.width: 1

                    Text {
                        id: tabText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.currentTab === modelData.id ? Tokens.ink : Tokens.inkDim
                        font.family: root.fontUi
                        font.pixelSize: 12
                        font.weight: root.currentTab === modelData.id ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = modelData.id
                    }
                }
            }
        }

        // Window Controls, Telemetry & btop launcher
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // Live Uptime & Load indicator
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: root.width > 820

                Text {
                    text: "UPTIME " + root.fmtUptime(root.stats.uptimeSecs)
                    color: Tokens.inkFaint
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: 1; height: 12
                    color: Tokens.lineSoft
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "LOAD " + (root.stats && root.stats.loadAvg ? root.stats.loadAvg[0].toFixed(2) : "0.00")
                    color: Tokens.inkDim
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }



            Rectangle {
                width: 28
                height: 28
                radius: 6
                color: closeMouse.containsMouse ? root.alertWash : Tokens.tint5
                border.color: closeMouse.containsMouse ? Tokens.alert : Tokens.lineSoft
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    color: closeMouse.containsMouse ? Tokens.alert : Tokens.inkDim
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.quit()
                }
            }
        }
    }

    // ── Backend not answering ──────────────────────────────────────────────
    Rectangle {
        id: staleBanner
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.statsStale ? 34 : 0
        visible: root.statsStale
        color: root.alertWash

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            elide: Text.ElideRight
            text: "Can't read system statistics: asura-sysmon is not answering. The numbers below are out of date."
            color: Tokens.alert
            font.family: root.fontUi
            font.pixelSize: 12
        }
    }

    // ── Tab Views ───────────────────────────────────────────────────────────
    Item {
        id: viewHost
        anchors.top: staleBanner.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        OverviewTab {
            anchors.fill: parent
            visible: root.currentTab === "performance"
            stats: root.stats
            app: root
        }

        ProcessesTab {
            anchors.fill: parent
            visible: root.currentTab === "processes"
            processes: root.processList
            app: root
        }

        DisksTab {
            anchors.fill: parent
            visible: root.currentTab === "storage"
            disks: root.stats.disks || []
            diskIO: root.stats.diskIO || { readBytesSec: 0, writeBytesSec: 0, readIOPS: 0, writeIOPS: 0, devices: [] }
            app: root
        }

        SystemTab {
            anchors.fill: parent
            visible: root.currentTab === "system"
            stats: root.stats
            app: root
        }
    }
}
