import QtQuick
import QtQuick.Controls
import qs.Ui.Singletons
import Quickshell
import Quickshell.Io

// The process table: every process, with CPU and memory, sortable by any
// column, searchable, and keyboard-driven. Ending a process always asks first.
//
// Keys: Up/Down select, Delete ends the selected process, Ctrl+F or "/"
// searches, Enter in the search box returns to the list, Esc backs out one
// step (confirmation, then search text, then selection).
Item {
    id: tab
    property var processes: []
    property var app

    property string filterText: ""
    property int selectedPID: -1
    property string selectedName: ""
    property string selectedCmdline: ""

    // Sorting: the column key and direction. CPU, highest first, by default.
    property string sortKey: "cpu"
    property bool sortDesc: true

    // The "End this process?" bar, and the outcome of the last attempt.
    property bool confirming: false
    property string statusMsg: ""
    property bool statusIsError: false

    readonly property string fontUi: Tokens.ui
    readonly property string fontMono: Tokens.mono
    readonly property color alertWash: Qt.rgba(Tokens.alert.r, Tokens.alert.g, Tokens.alert.b, 0.14)

    readonly property var columns: [
        { key: "name", label: "Name", width: -1 },
        { key: "pid", label: "PID", width: 72 },
        { key: "user", label: "User", width: 110 },
        { key: "cpu", label: "CPU", width: 72 },
        { key: "mem", label: "Memory", width: 96 },
        { key: "threads", label: "Threads", width: 70 },
        { key: "state", label: "State", width: 84 }
    ]
    readonly property int fixedColumnsWidth: 72 + 110 + 72 + 96 + 70 + 84

    function stateLabel(s) {
        switch (s) {
        case "R": return "Running";
        case "S": return "Sleeping";
        case "D": return "Disk wait";
        case "I": return "Idle";
        case "T": case "t": return "Stopped";
        case "Z": return "Zombie";
        case "X": return "Dead";
        default: return s || "";
        }
    }

    function fmtCpu(v) {
        if (!v || v < 0.05) return "0%";
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + "%";
    }

    function setSort(key) {
        if (tab.sortKey === key) {
            tab.sortDesc = !tab.sortDesc;
        } else {
            tab.sortKey = key;
            // Numbers read biggest first; text reads A to Z.
            tab.sortDesc = !(key === "name" || key === "user" || key === "state");
        }
        procListView.recompute();
    }

    function select(pid, name, cmdline) {
        tab.selectedPID = pid;
        tab.selectedName = name;
        tab.selectedCmdline = cmdline;
        tab.confirming = false;
    }

    function clearSelection() {
        tab.selectedPID = -1;
        tab.selectedName = "";
        tab.selectedCmdline = "";
        tab.confirming = false;
    }

    function askToEnd() {
        if (tab.selectedPID > 0) tab.confirming = true;
    }

    function endSelected(force) {
        if (tab.selectedPID <= 0 || killProc.running) return;
        killProc.targetPid = tab.selectedPID;
        killProc.targetName = tab.selectedName;
        killProc.force = force;
        killProc.running = true;
        tab.confirming = false;
    }

    function showStatus(msg, isError) {
        tab.statusMsg = msg;
        tab.statusIsError = isError;
        statusClear.restart();
    }

    function moveSelection(step) {
        var n = filteredModel.count;
        if (n === 0) return;
        var i = procListView.currentIndex;
        i = i < 0 ? (step > 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, i + step));
        procListView.currentIndex = i;
        procListView.positionViewAtIndex(i, ListView.Contain);
        var row = filteredModel.get(i);
        tab.select(row.pid, row.name, row.cmdline);
    }

    function handleEscape() {
        if (tab.confirming) tab.confirming = false;
        else if (searchInput.text !== "") searchInput.text = "";
        else tab.clearSelection();
    }

    // Shortcuts work only while this tab is the one on screen.
    Shortcut { enabled: tab.visible; sequences: ["Ctrl+F", "/"]; onActivated: searchInput.forceActiveFocus() }
    Shortcut { enabled: tab.visible && !searchInput.activeFocus; sequence: "Up"; onActivated: tab.moveSelection(-1) }
    Shortcut { enabled: tab.visible && !searchInput.activeFocus; sequence: "Down"; onActivated: tab.moveSelection(1) }
    Shortcut { enabled: tab.visible && !searchInput.activeFocus; sequence: "Delete"; onActivated: tab.askToEnd() }
    Shortcut { enabled: tab.visible && tab.confirming; sequence: "Return"; onActivated: tab.endSelected(false) }
    Shortcut { enabled: tab.visible; sequence: "Escape"; onActivated: tab.handleEscape() }

    Timer {
        id: statusClear
        interval: 6000
        onTriggered: tab.statusMsg = ""
    }

    Process {
        id: killProc
        property int targetPid: -1
        property string targetName: ""
        property bool force: false
        command: force ? ["asura-sysmon", "kill", String(targetPid), "--force"]
                       : ["asura-sysmon", "kill", String(targetPid)]
        stderr: StdioCollector { id: killErr }
        onExited: (code) => {
            if (code === 0) {
                tab.showStatus((killProc.force ? "Force quit " : "Ended ") + killProc.targetName
                    + " (PID " + killProc.targetPid + ")", false);
                tab.clearSelection();
                procRefreshProc.running = true;
            } else {
                // The backend explains itself, e.g. "permission denied: process
                // 812 belongs to another user". Show that, not a bare failure.
                var why = String(killErr.text || "").trim().replace(/^asura-sysmon kill: /, "");
                tab.showStatus("Couldn't end " + killProc.targetName + ": "
                    + (why !== "" ? why : "exit code " + code), true);
            }
        }
    }

    Process {
        id: procRefreshProc
        command: ["asura-sysmon", "proc", "--limit", "0", "--interval", "250"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed && parsed.processes) {
                        tab.app.processList = parsed.processes;
                    }
                } catch (e) {}
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        // ── Search, End task, count ──────────────────────────────────────
        Item {
            width: parent.width
            height: 36

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                spacing: 12

                Rectangle {
                    width: 280
                    height: 36
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.color: searchInput.activeFocus ? Tokens.line : Tokens.lineSoft
                    border.width: 1

                    Text {
                        id: searchGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        color: Tokens.inkFaint
                        font.pixelSize: 14
                    }

                    TextInput {
                        id: searchInput
                        anchors.left: searchGlyph.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Tokens.ink
                        selectionColor: Tokens.tint16
                        selectedTextColor: Tokens.ink
                        font.family: tab.fontUi
                        font.pixelSize: 12
                        clip: true
                        onTextChanged: tab.filterText = text.toLowerCase().trim()
                        Keys.onReturnPressed: procListView.forceActiveFocus()
                        Keys.onEscapePressed: {
                            if (text !== "") text = "";
                            else procListView.forceActiveFocus();
                        }

                        Text {
                            anchors.fill: parent
                            visible: !searchInput.text
                            text: searchInput.activeFocus ? "Name, PID, user or command" : "Search processes  (Ctrl+F)"
                            color: Tokens.inkFaint
                            font.family: tab.fontUi
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: endLabel.implicitWidth + 28
                    height: 36
                    radius: Tokens.radius
                    readonly property bool active: tab.selectedPID > 0
                    color: active ? (endMouse.containsMouse ? Qt.rgba(Tokens.alert.r, Tokens.alert.g, Tokens.alert.b, 0.22) : tab.alertWash) : "transparent"
                    border.color: active ? Tokens.alert : Tokens.lineSoft
                    border.width: 1
                    opacity: active ? 1.0 : 0.45

                    Text {
                        id: endLabel
                        anchors.centerIn: parent
                        text: "End task…"
                        color: parent.active ? Tokens.alert : Tokens.inkFaint
                        font.family: tab.fontUi
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: endMouse
                        anchors.fill: parent
                        enabled: parent.active
                        hoverEnabled: true
                        cursorShape: parent.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: tab.askToEnd()
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: filteredModel.count + (tab.filterText !== "" ? " of " + (tab.processes || []).length : "") + " processes"
                color: Tokens.inkFaint
                font.family: tab.fontMono
                font.pixelSize: 11
            }
        }

        // ── Confirmation, or the result of the last attempt ─────────────
        Rectangle {
            id: noticeBar
            width: parent.width
            height: visible ? 40 : 0
            visible: tab.confirming || tab.statusMsg !== ""
            radius: Tokens.radius
            color: tab.confirming || tab.statusIsError ? tab.alertWash : Tokens.tint5
            border.color: tab.confirming || tab.statusIsError ? Tokens.alert : Tokens.lineSoft
            border.width: 1

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: confirmButtons.visible ? confirmButtons.left : parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: tab.confirming
                    ? "End “" + tab.selectedName + "” (PID " + tab.selectedPID + ")? Unsaved work in it will be lost."
                    : tab.statusMsg
                color: tab.confirming || tab.statusIsError ? Tokens.alert : Tokens.inkDim
                font.family: tab.fontUi
                font.pixelSize: 12
            }

            Row {
                id: confirmButtons
                visible: tab.confirming
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: [
                        { label: "End", hint: "Ask it to close (Enter)", act: "end" },
                        { label: "Force quit", hint: "Stop it immediately", act: "force" },
                        { label: "Cancel", hint: "Esc", act: "cancel" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: btnText.implicitWidth + 22
                        height: 28
                        radius: Tokens.radius
                        readonly property bool danger: modelData.act !== "cancel"
                        color: btnMouse.containsMouse ? (danger ? Qt.rgba(Tokens.alert.r, Tokens.alert.g, Tokens.alert.b, 0.22) : Tokens.tint10) : "transparent"
                        border.color: danger ? Tokens.alert : Tokens.line
                        border.width: 1

                        Text {
                            id: btnText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.danger ? Tokens.alert : Tokens.ink
                            font.family: tab.fontUi
                            font.pixelSize: 12
                            font.weight: modelData.act === "end" ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: btnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.act === "end") tab.endSelected(false);
                                else if (modelData.act === "force") tab.endSelected(true);
                                else tab.confirming = false;
                            }
                        }
                    }
                }
            }
        }

        // ── Column headers: click to sort, click again to reverse ───────
        Rectangle {
            id: headerRow
            width: parent.width
            height: 30
            color: Tokens.paperLift
            radius: Tokens.radius

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Repeater {
                    model: tab.columns
                    delegate: Item {
                        required property var modelData
                        width: modelData.width > 0 ? modelData.width : Math.max(140, headerRow.width - 24 - tab.fixedColumnsWidth)
                        height: 30
                        readonly property bool sorted: tab.sortKey === modelData.key

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label + (parent.sorted ? (tab.sortDesc ? "  ▾" : "  ▴") : "")
                            color: parent.sorted ? Tokens.ink : (colMouse.containsMouse ? Tokens.inkMuted : Tokens.inkDim)
                            font.pixelSize: 11
                            font.family: tab.fontUi
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: colMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tab.setSort(modelData.key)
                        }
                    }
                }
            }
        }

        // ── The list ─────────────────────────────────────────────────────
        ListView {
            id: procListView
            width: parent.width
            height: parent.height - 36 - headerRow.height - detailStrip.height - noticeBar.height
                    - parent.spacing * (noticeBar.visible ? 4 : 3)
            clip: true
            spacing: 2
            focus: true
            currentIndex: -1
            highlightFollowsCurrentItem: false
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            model: ListModel {
                id: filteredModel
            }

            function sortValue(p) {
                switch (tab.sortKey) {
                case "pid": return p.pid;
                case "name": return (p.name || "").toLowerCase();
                case "user": return (p.user || "").toLowerCase();
                case "cpu": return p.cpuPercent || 0;
                case "mem": return p.memoryBytes || 0;
                case "threads": return p.threads || 0;
                case "state": return tab.stateLabel(p.state);
                default: return 0;
                }
            }

            // Rebuilds the rows from the latest list, keeping the scroll
            // position and the selected process across refreshes.
            function recompute() {
                var keepY = procListView.contentY;
                var f = tab.filterText;
                var rows = [];
                var list = tab.processes || [];
                for (var i = 0; i < list.length; i++) {
                    var p = list[i];
                    if (!f
                        || (p.name || "").toLowerCase().indexOf(f) >= 0
                        || String(p.pid).indexOf(f) >= 0
                        || (p.user || "").toLowerCase().indexOf(f) >= 0
                        || (p.cmdline || "").toLowerCase().indexOf(f) >= 0) {
                        rows.push(p);
                    }
                }
                var dir = tab.sortDesc ? -1 : 1;
                rows.sort(function (a, b) {
                    var va = procListView.sortValue(a), vb = procListView.sortValue(b);
                    if (va < vb) return -dir;
                    if (va > vb) return dir;
                    // Ties (most processes sit at 0% CPU) put the ones using
                    // memory first, so apps lead and idle kernel threads trail.
                    var ma = a.memoryBytes || 0, mb = b.memoryBytes || 0;
                    if (ma !== mb) return mb - ma;
                    return a.pid - b.pid;
                });

                filteredModel.clear();
                var selectedIndex = -1;
                var stillThere = false;
                for (var j = 0; j < rows.length; j++) {
                    var r = rows[j];
                    if (r.pid === tab.selectedPID) {
                        selectedIndex = j;
                        stillThere = true;
                    }
                    filteredModel.append({
                        pid: r.pid,
                        name: r.name || "",
                        cmdline: r.cmdline || "",
                        user: r.user || "",
                        cpuPercent: r.cpuPercent || 0,
                        memoryBytes: r.memoryBytes || 0,
                        threads: r.threads || 0,
                        state: r.state || ""
                    });
                }
                // A selected process that has exited is no longer selectable.
                if (tab.selectedPID > 0 && !stillThere && !tab.confirming) tab.clearSelection();
                procListView.currentIndex = selectedIndex;
                procListView.contentY = Math.min(keepY, Math.max(0, procListView.contentHeight - procListView.height));
            }

            Component.onCompleted: recompute()

            Connections {
                target: tab
                function onProcessesChanged() { procListView.recompute(); }
                function onFilterTextChanged() { procListView.recompute(); }
            }

            delegate: Rectangle {
                id: row
                required property int index
                required property int pid
                required property string name
                required property string cmdline
                required property string user
                required property real cpuPercent
                required property real memoryBytes
                required property int threads
                required property string state

                readonly property bool selected: tab.selectedPID === pid

                // The full command on hover, without having to select the row.
                ToolTip.visible: rowMouse.containsMouse && cmdline.length > 0
                ToolTip.text: cmdline
                ToolTip.delay: 500

                width: procListView.width
                height: 32
                radius: Tokens.radius
                color: selected ? Tokens.tint10 : (rowMouse.containsMouse ? Tokens.tint5 : "transparent")
                border.color: selected ? Tokens.line : "transparent"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text { width: Math.max(140, row.width - 24 - tab.fixedColumnsWidth) - 8; text: row.name; color: Tokens.ink; font.pixelSize: 12; font.family: tab.fontUi; font.weight: Font.Medium; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 8; height: 1 }
                    Text { width: 72; text: String(row.pid); color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontMono; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 110; text: row.user; color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontUi; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 72; text: tab.fmtCpu(row.cpuPercent); color: row.cpuPercent >= 25 ? Tokens.sun : (row.cpuPercent >= 1 ? Tokens.ink : Tokens.inkFaint); font.pixelSize: 11; font.family: tab.fontMono; font.weight: row.cpuPercent >= 25 ? Font.DemiBold : Font.Normal; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 96; text: tab.app.fmtBytes(row.memoryBytes); color: Tokens.ink; font.pixelSize: 11; font.family: tab.fontMono; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 70; text: String(row.threads); color: Tokens.inkDim; font.pixelSize: 11; font.family: tab.fontMono; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: 84; text: tab.stateLabel(row.state); color: row.state === "R" ? Tokens.ink : (row.state === "Z" || row.state === "D" ? Tokens.alert : Tokens.inkFaint); font.pixelSize: 11; font.family: tab.fontUi; font.weight: row.state === "R" ? Font.DemiBold : Font.Normal; anchors.verticalCenter: parent.verticalCenter }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        procListView.forceActiveFocus();
                        procListView.currentIndex = row.index;
                        tab.select(row.pid, row.name, row.cmdline);
                    }
                    onDoubleClicked: tab.askToEnd()
                }
            }

            Text {
                anchors.centerIn: parent
                visible: filteredModel.count === 0
                text: (tab.processes || []).length === 0 ? "Reading processes…"
                    : "No process matches “" + searchInput.text + "”"
                color: Tokens.inkFaint
                font.family: tab.fontUi
                font.pixelSize: 13
            }
        }

        // ── The selected process's full command ──────────────────────────
        Rectangle {
            id: detailStrip
            width: parent.width
            height: 30
            radius: Tokens.radius
            color: Tokens.paperLift

            Text {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                text: tab.selectedPID > 0 ? tab.selectedCmdline
                    : "Select a process to see its command. ↑/↓ select · Delete ends · / searches"
                color: tab.selectedPID > 0 ? Tokens.inkDim : Tokens.inkFaint
                font.family: tab.selectedPID > 0 ? tab.fontMono : tab.fontUi
                font.pixelSize: 11
            }
        }
    }
}
