import QtQuick

// Pick any file to add to the library: games, AppImages, Windows .exe, scripts,
// app shortcuts, ROMs (opened with their default app). Controller + touch.
Item {
    id: fb
    property real u: 8
    property bool open: false
    property string path: ""
    property var entries: []
    property int idx: 0
    property string home: ""
    property var glyph: function(a) { return ["?", ""] }
    signal sound(string name)

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    function load(p, selectPath) {
        path = p
        entries = backend.listDir(p)
        var i = selectPath ? entries.findIndex(function(e) { return e.path === selectPath && e.kind !== "place" }) : -1
        if (i < 0) {   // first real entry (skip the places row)
            i = entries.findIndex(function(e) { return e.kind !== "place" })
            if (i < 0) i = 0
        }
        idx = i
        list.positionViewAtIndex(idx, ListView.Center)
    }
    function show() { home = backend.homeDir(); load(home, ""); open = true; sound("menu_open") }
    function close() { open = false; sound("menu_close") }
    function up() {
        if (path === "/") { close(); return }
        var from = path
        load(backend.parentDir(path), from)
        sound("back")
    }
    function choose() {
        var e = entries[idx]
        if (!e) { sound("bump"); return }
        if (e.isDir) { load(e.path, ""); sound("select"); return }
        sound("select")
        backend.addCustom(e.path)
        close()
    }
    function handle(a) {
        var n = entries.length
        if (a === "up" && n)        { idx = (idx - 1 + n) % n; sound("move") }
        else if (a === "down" && n) { idx = (idx + 1) % n; sound("move") }
        else if (a === "tabPrev" && n) { idx = Math.max(0, idx - 8); sound("move") }
        else if (a === "tabNext" && n) { idx = Math.min(n - 1, idx + 8); sound("move") }
        else if (a === "accept" || a === "right") choose()
        else if (a === "back" || a === "left") up()
        else if (a === "secondary" || a === "taskview" || a === "menu") close()
        else sound("bump")
    }
    onIdxChanged: list.positionViewAtIndex(idx, ListView.Contain)

    Rectangle { anchors.fill: parent; color: "#E6050a18" }
    MouseArea { anchors.fill: parent }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - u * 10, u * 110)
        height: parent.height - u * 12
        radius: u * 2
        color: "#0A1428"
        border.color: "#5500E5FF"; border.width: 1

        Column {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: u * 4 }
            spacing: u * 0.6
            Text { text: "Add a game"; color: "#E8F4FF"; font.pixelSize: u * 3.4; font.bold: true }
            Text {
                width: parent.width; elide: Text.ElideMiddle
                text: fb.home && fb.path.indexOf(fb.home) === 0 ? "~" + fb.path.slice(fb.home.length) : fb.path
                color: "#00E5FF"; font.pixelSize: u * 1.7
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: "Pick the game's program, an AppImage, a Windows .exe, a script or a ROM. X Mode starts it the right way."
                color: "#7A8FA8"; font.pixelSize: u * 1.5
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top
                      leftMargin: u * 4; rightMargin: u * 4; topMargin: u * 2; bottomMargin: u * 1 }
            clip: true
            spacing: u * 0.6
            model: fb.entries
            currentIndex: fb.idx
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                width: list.width
                height: u * 5.6
                radius: u * 1
                readonly property bool sel: index === fb.idx
                readonly property bool place: modelData.kind === "place"
                color: sel ? "#2600E5FF" : (place ? "#0F1E3A" : "#140047AB")
                border.color: sel ? "#00E5FF" : "#1A00E5FF"
                border.width: sel ? Math.max(2, u * 0.28) : 1
                Row {
                    anchors { left: parent.left; leftMargin: u * 2; verticalCenter: parent.verticalCenter }
                    spacing: u * 1.6
                    Text {
                        width: u * 3
                        horizontalAlignment: Text.AlignHCenter
                        text: place ? "★" : (modelData.isDir ? "▸" : "◆")
                        color: place ? "#E3B341" : (modelData.isDir ? "#58A6FF" : "#00E5FF")
                        font.pixelSize: u * 2.1
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        width: list.width - u * 26
                        elide: Text.ElideRight
                        text: modelData.name
                        color: "#E8F4FF"; font.pixelSize: u * 2; font.bold: sel
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: u * 2; verticalCenter: parent.verticalCenter }
                    text: place ? "Go to" : (modelData.isDir ? "Folder" : modelData.kind)
                    color: "#7A8FA8"; font.pixelSize: u * 1.5
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { if (fb.idx === index) fb.choose(); else { fb.idx = index; fb.sound("move") } }
                }
            }
        }

        Row {
            id: foot
            anchors { right: parent.right; bottom: parent.bottom; margins: u * 3 }
            height: u * 4
            spacing: u * 3
            Hint { action: "accept"; label: fb.entries[fb.idx] && !fb.entries[fb.idx].isDir ? "Add" : "Open" }
            Hint { action: "back"; label: "Up a folder" }
            Hint { action: "secondary"; label: "Cancel" }
        }
    }

    component Hint: Row {
        property string action: ""
        property string label: ""
        spacing: u * 1
        readonly property var g: fb.glyph(action)
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
