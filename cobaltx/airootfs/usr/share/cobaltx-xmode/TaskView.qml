import QtQuick

// Open apps: resume or close what's running. Opened with the Guide/PS button.
Item {
    id: tv
    property real u: 8
    property bool open: false
    property int idx: 0
    property var apps: backend.apps
    property var glyph: function(a) { return ["?", ""] }

    signal sound(string name)

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    onOpenChanged: { idx = 0; if (open) sound("menu_open"); else sound("menu_close") }
    onAppsChanged: { if (idx >= apps.length) idx = Math.max(0, apps.length - 1) }

    function handle(a) {
        if (a === "up" && apps.length)   { idx = (idx - 1 + apps.length) % apps.length; sound("move") }
        else if (a === "down" && apps.length) { idx = (idx + 1) % apps.length; sound("move") }
        else if (a === "accept" && apps.length) resume(idx)
        else if (a === "secondary" && apps.length) closeApp(idx)
        else if (a === "back" || a === "taskview" || a === "menu" || a === "apps") open = false
        else sound("bump")
    }
    function resume(i) {
        sound("select")
        backend.activateApp(apps[i].id)
        open = false
    }
    function closeApp(i) {
        sound("warn")
        backend.closeApp(apps[i].id)
    }

    Rectangle { anchors.fill: parent; color: "#E0050a18" }
    MouseArea { anchors.fill: parent; onClicked: tv.open = false }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - u * 12, u * 90)
        height: Math.min(parent.height - u * 16,
                         u * 4 + header.height + u * 2.5 + Math.max(1, tv.apps.length) * u * 9.2 + u * 9)
        radius: u * 2
        color: "#0A1428"
        border.color: "#5500E5FF"
        border.width: 1
        MouseArea { anchors.fill: parent }        // don't close when clicking inside

        Column {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: u * 4 }
            spacing: u * 0.5
            Text { text: "Open apps"; color: "#E8F4FF"; font.pixelSize: u * 3.4; font.bold: true }
            Text {
                text: tv.apps.length ? "Resume a game or close it" : "Nothing is running right now"
                color: "#7A8FA8"; font.pixelSize: u * 1.8
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top
                      leftMargin: u * 4; rightMargin: u * 4; topMargin: u * 2.5; bottomMargin: u * 1 }
            clip: true
            spacing: u * 1.2
            model: tv.apps
            currentIndex: tv.idx
            delegate: Rectangle {
                width: list.width
                height: u * 8
                radius: u * 1.2
                readonly property bool sel: index === tv.idx
                color: sel ? "#2600E5FF" : "#140047AB"
                border.color: sel ? "#00E5FF" : "#2200E5FF"
                border.width: sel ? Math.max(2, u * 0.3) : 1
                Text {
                    anchors { left: parent.left; leftMargin: u * 2.4; right: closeBtn.left; rightMargin: u * 2
                              verticalCenter: parent.verticalCenter }
                    text: modelData.title
                    color: "#E8F4FF"
                    font.pixelSize: u * 2.3
                    font.bold: true
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: closeBtn
                    anchors { right: parent.right; rightMargin: u * 1.6; verticalCenter: parent.verticalCenter }
                    width: modelData.stuck ? u * 15 : u * 11; height: u * 4.4; radius: height / 2
                    color: closeArea.containsMouse ? "#40FF5C5C" : "#22FF5C5C"
                    border.color: "#88FF5C5C"; border.width: 1
                    Text { anchors.centerIn: parent; text: modelData.stuck ? "Force close" : "Close"; color: "#FFB0B0"; font.pixelSize: u * 1.8; font.bold: true }
                    MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: { tv.idx = index; tv.closeApp(index) } }
                }
                MouseArea {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: closeBtn.left }
                    onClicked: { tv.idx = index; tv.resume(index) }
                }
            }
        }

        Row {
            id: footer
            anchors { right: parent.right; bottom: parent.bottom; margins: u * 3 }
            height: u * 4
            spacing: u * 3
            HintRow { action: "accept"; label: "Resume"; visible: tv.apps.length > 0 }
            HintRow { action: "secondary"; visible: tv.apps.length > 0
                      label: tv.apps.length && tv.apps[Math.min(tv.idx, tv.apps.length - 1)].stuck ? "Force close" : "Close" }
            HintRow { action: "back"; label: "Back" }
        }
    }

    component HintRow: Row {
        property string action: ""
        property string label: ""
        spacing: u * 1
        readonly property var g: tv.glyph(action)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: u * 3.2
            width: Math.max(height, gt.implicitWidth + u * 1.4)
            radius: height / 2
            color: "#1F00E5FF"
            border.color: parent.g[1] !== "" ? parent.g[1] : "#6600E5FF"
            Text {
                id: gt
                anchors.centerIn: parent
                text: parent.parent.g[0]
                color: parent.parent.g[1] !== "" ? parent.parent.g[1] : "#E8F4FF"
                font.pixelSize: text.length === 1 ? u * 1.9 : (text.length > 3 ? u * 1.25 : u * 1.6)
                font.bold: true
            }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: "#E8F4FF"; font.pixelSize: u * 1.9 }
    }
}
