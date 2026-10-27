import QtQuick
import QtQuick.Window

// CobaltX On-Screen Keyboard. Never takes focus: keys are typed into the app in front.
Window {
    id: win
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint
           | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    width: Screen.width
    height: Math.round(Math.min(Screen.height * 0.44, Screen.width * 0.36))
    x: 0
    y: Screen.height - height
    visible: kb.visible || panel.y < height        // stay mapped while sliding out

    readonly property real u: height / 40           // layout unit
    readonly property color cNavy: "#071022"
    readonly property color cPanel: "#0A1428"
    readonly property color cCobalt: "#0047AB"
    readonly property color cCyan: "#00E5FF"
    readonly property color cIce: "#E8F4FF"
    readonly property color cMuted: "#7A8FA8"

    // ------------------------------------------------------------- layouts
    // t = label, v = character to type, s = special action, w = width (row = 11 units)
    function ck(t, w) { return { t: t, v: t, w: w || 1 } }
    function sk(t, s, w) { return { t: t, s: s, w: w || 1 } }
    function chars(str) { return str.split("").map(function(c) { return ck(c) }) }

    readonly property var letters: [
        chars("1234567890").concat([sk("⌫", "backspace")]),
        [sk("Tab", "tab")].concat(chars("qwertyuiop")),
        [sk("", "gap", 0.5)].concat(chars("asdfghjkl")).concat([sk("Enter", "enter", 1.5)]),
        [sk("⇧", "shift")].concat(chars("zxcvbnm,.'")),
        [sk("?123", "sym", 1.5), sk("", "space", 5.5), sk("◀", "left"), sk("▶", "right"), sk("Hide", "hide", 2)]
    ]
    readonly property var symbols: [
        chars("1234567890").concat([sk("⌫", "backspace")]),
        [sk("Tab", "tab")].concat(chars("!@#$%^&*()")),
        [sk("", "gap", 0.5)].concat(chars("-_=+[]{};")).concat([sk("Enter", "enter", 1.5)]),
        [sk("Esc", "esc")].concat(chars(":\"<>?/\\|~`")),
        [sk("ABC", "sym", 1.5), sk("", "space", 5.5), sk("◀", "left"), sk("▶", "right"), sk("Hide", "hide", 2)]
    ]

    property bool sym: false
    property bool shift: false
    property bool caps: false
    property int row: 1
    property int col: 1
    readonly property var rows: sym ? symbols : letters

    function label(k) {
        if (k.v !== undefined && (shift || caps) && !sym) return k.v.toUpperCase()
        return k.t
    }
    function selectable(k) { return k.s !== "gap" }

    // ----------------------------------------------------- controller hints
    readonly property var glyphMap: ({
        "xbox":        { accept: ["A", "#3FB950"], back: ["B", "#F85149"], secondary: ["X", "#58A6FF"], tertiary: ["Y", "#E3B341"], tabPrev: ["LB", ""], tabNext: ["RB", ""], menu: ["☰", ""] },
        "generic":     { accept: ["A", ""],        back: ["B", ""],        secondary: ["X", ""],        tertiary: ["Y", ""],        tabPrev: ["LB", ""], tabNext: ["RB", ""], menu: ["☰", ""] },
        "steam":       { accept: ["A", "#3FB950"], back: ["B", "#F85149"], secondary: ["X", "#58A6FF"], tertiary: ["Y", "#E3B341"], tabPrev: ["L1", ""], tabNext: ["R1", ""], menu: ["☰", ""] },
        "playstation": { accept: ["✕", "#7FA7FF"], back: ["○", "#FF6B6B"], secondary: ["□", "#F778BA"], tertiary: ["△", "#3FD9A8"], tabPrev: ["L1", ""], tabNext: ["R1", ""], menu: ["OPTIONS", ""] },
        "nintendo":    { accept: ["A", ""],        back: ["B", ""],        secondary: ["Y", ""],        tertiary: ["X", ""],        tabPrev: ["L", ""],  tabNext: ["R", ""],  menu: ["+", ""] }
    })
    readonly property bool padHints: glyphMap[kb.family] !== undefined
    function glyph(a) {
        var m = glyphMap[kb.family] || glyphMap["xbox"]
        return m[a] || ["?", ""]
    }

    // ------------------------------------------------------------ actions
    function press(k) {
        flash.restart()
        if (k.v !== undefined) {
            kb.typeText(label(k))
            if (shift && !caps) shift = false
            kb.playSound("move")
            return
        }
        switch (k.s) {
        case "shift":
            if (caps) { caps = false; shift = false }
            else if (shift) caps = true
            else shift = true
            break
        case "sym": sym = !sym; shift = false; caps = false; fixCol(); break
        case "hide": kb.setVisible(false); return
        case "space": kb.typeSpecial("space"); break
        default: kb.typeSpecial(k.s)
        }
        kb.playSound("move")
    }

    function centers(r) {
        var out = [], x = 0
        for (var i = 0; i < rows[r].length; i++) { out.push(x + rows[r][i].w / 2); x += rows[r][i].w }
        return out
    }
    function fixCol() {
        col = Math.min(col, rows[row].length - 1)
        if (!selectable(rows[row][col])) col += 1
    }
    function moveH(step) {
        var n = rows[row].length
        do { col = (col + step + n) % n } while (!selectable(rows[row][col]))
    }
    function moveV(step) {
        var cx = centers(row)[col]
        row = (row + step + rows.length) % rows.length
        var cs = centers(row), best = -1, dist = 1e9
        for (var i = 0; i < cs.length; i++) {
            if (!selectable(rows[row][i])) continue
            var d = Math.abs(cs[i] - cx)
            if (d < dist) { dist = d; best = i }
        }
        col = best
    }

    Connections {
        target: kb
        function onInput(a) {
            switch (a) {
            case "left":  moveH(-1); kb.playSound("move"); break
            case "right": moveH(1);  kb.playSound("move"); break
            case "up":    moveV(-1); kb.playSound("move"); break
            case "down":  moveV(1);  kb.playSound("move"); break
            case "accept":    press(rows[row][col]); break
            case "back":      kb.setVisible(false); break
            case "secondary": kb.typeSpecial("backspace"); kb.playSound("move"); break
            case "tertiary":  kb.typeSpecial("space"); kb.playSound("move"); break
            case "menu":      kb.typeSpecial("enter"); kb.playSound("select"); break
            case "tabPrev":   press({ s: "shift" }); break
            case "tabNext":   press({ s: "sym" }); break
            case "taskview":
            case "qam":
            case "quick":     kb.setVisible(false); break
            }
        }
        function onVisibleChanged() { if (kb.visible) { row = 1; col = 1; shift = false; caps = false; sym = false } }
    }

    // --------------------------------------------------------------- panel
    Item {
        id: panel
        width: parent.width
        height: parent.height
        y: kb.visible ? 0 : height
        Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: -radius
            radius: u * 2.4
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0D1B36" }
                GradientStop { position: 1.0; color: cNavy }
            }
        }
        // glowing cyan top edge
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: u * 2; rightMargin: u * 2 }
            height: Math.max(1, u * 0.18)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: cCyan }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        MouseArea { anchors.fill: parent }         // clicks between keys don't fall through

        // ----------------------------------------------------------- header
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: u * 3; rightMargin: u * 3 }
            height: u * 5.5
            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - hintRow.width - u * 3
                clip: true
                spacing: u * 1.2
                Image {
                    source: kb.brand
                    width: u * 3; height: width
                    sourceSize: Qt.size(width * 2, height * 2)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "CobaltX Keyboard"
                    color: cIce; font.pixelSize: u * 1.8; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: parent.width - x
                    elide: Text.ElideRight
                    visible: kb.problem !== ""
                    text: "· can't type: " + kb.problem
                    color: "#FFB84D"; font.pixelSize: u * 1.4
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    visible: kb.problem === "" && (shift || caps)
                    text: caps ? "· CAPS" : "· Shift"
                    color: cCyan; font.pixelSize: u * 1.5; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Row {
                id: hintRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: u * 2.2
                visible: win.padHints
                Hint { action: "secondary"; label: "Delete" }
                Hint { action: "tertiary"; label: "Space" }
                Hint { action: "tabPrev"; label: "Shift"; visible: !sym }
                Hint { action: "tabNext"; label: sym ? "ABC" : "?123" }
                Hint { action: "menu"; label: "Enter" }
                Hint { action: "back"; label: "Close" }
            }
        }

        // ------------------------------------------------------------- keys
        Column {
            id: keys
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                      leftMargin: u * 3; rightMargin: u * 3; bottomMargin: u * 2.2; topMargin: u * 0.6 }
            spacing: u * 0.9
            readonly property real keyH: (height - spacing * 4) / 5
            readonly property real unit: (width - u * 0.9 * 10) / 11 + u * 0.9

            Repeater {
                model: win.rows.length
                delegate: Row {
                    id: rowItem
                    readonly property int r: index
                    spacing: 0
                    height: keys.keyH
                    Repeater {
                        model: win.rows[rowItem.r]
                        delegate: Item {
                            readonly property var k: modelData
                            readonly property bool sel: win.row === rowItem.r && win.col === index
                            readonly property bool special: k.v === undefined
                            width: keys.unit * k.w
                            height: keys.keyH
                            Rectangle {
                                id: cap
                                visible: k.s !== "gap"
                                anchors.fill: parent
                                anchors.rightMargin: u * 0.9
                                radius: u * 1.1
                                scale: sel ? 1.06 : (area.pressed ? 0.96 : 1)
                                Behavior on scale { NumberAnimation { duration: 90 } }
                                color: sel ? "#2400E5FF"
                                     : (k.s === "shift" && (win.shift || win.caps)) ? "#3300E5FF"
                                     : special ? "#0B2350" : "#132443"
                                border.color: sel ? cCyan : (special ? "#330047AB" : "#2200E5FF")
                                border.width: sel ? Math.max(2, u * 0.28) : 1
                                // soft top highlight
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                                    height: parent.height * 0.45
                                    radius: parent.radius
                                    color: "#0CFFFFFF"
                                }
                                // selection glow
                                Rectangle {
                                    visible: sel
                                    anchors.fill: parent
                                    anchors.margins: -u * 0.5
                                    radius: parent.radius + u * 0.5
                                    color: "transparent"
                                    border.color: "#4000E5FF"
                                    border.width: u * 0.4
                                }
                                Text {
                                    visible: k.s !== "space"
                                    anchors.centerIn: parent
                                    text: win.label(k)
                                    color: special ? "#9FD8FF" : cIce
                                    font.pixelSize: special ? u * 1.9 : u * 2.6
                                    font.bold: true
                                }
                                // space bar: CobaltX logo
                                Row {
                                    visible: k.s === "space"
                                    anchors.centerIn: parent
                                    spacing: u * 1
                                    opacity: 0.75
                                    Image {
                                        source: kb.brand
                                        width: u * 2.6; height: width
                                        sourceSize: Qt.size(width * 2, height * 2)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "CobaltX"
                                        color: "#9FD8FF"; font.pixelSize: u * 1.8; font.bold: true
                                        font.letterSpacing: u * 0.15
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                // caps lock dot
                                Rectangle {
                                    visible: k.s === "shift" && win.caps
                                    width: u * 0.8; height: width; radius: width / 2
                                    color: cCyan
                                    anchors { top: parent.top; right: parent.right; margins: u * 0.8 }
                                }
                            }
                            MouseArea {
                                id: area
                                anchors.fill: cap
                                enabled: k.s !== "gap"
                                onPressed: { win.row = rowItem.r; win.col = index }
                                onClicked: win.press(k)
                            }
                        }
                    }
                }
            }
        }

        // brief cyan flash on every key press
        Rectangle {
            id: flashRect
            anchors.fill: parent
            color: cCyan
            opacity: 0
            SequentialAnimation on opacity {
                id: flash
                running: false
                NumberAnimation { to: 0.05; duration: 40 }
                NumberAnimation { to: 0; duration: 140 }
            }
        }
    }

    component Hint: Row {
        property string action: ""
        property string label: ""
        spacing: u * 0.8
        readonly property var g: win.glyph(action)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: u * 2.8
            width: Math.max(height, gt.implicitWidth + u * 1.2)
            radius: height / 2
            color: "#1F00E5FF"
            border.color: parent.g[1] !== "" ? parent.g[1] : "#6600E5FF"
            Text {
                id: gt
                anchors.centerIn: parent
                text: parent.parent.g[0]
                color: parent.parent.g[1] !== "" ? parent.parent.g[1] : cIce
                font.pixelSize: text.length === 1 ? u * 1.6 : (text.length > 3 ? u * 1.05 : u * 1.35)
                font.bold: true
            }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: cIce; font.pixelSize: u * 1.6 }
    }
}
