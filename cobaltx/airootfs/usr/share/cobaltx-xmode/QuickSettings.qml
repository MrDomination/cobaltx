import QtQuick

// Quick Settings: performance mode, power limit (TDP), brightness, volume, keyboard.
// X Mode: opened from the menu (Xbox button). Desktop: Xbox button or right back button.
Item {
    id: qsPanel
    property real u: 8
    property bool open: false
    property int idx: 0
    property var glyph: function(a) { return ["?", ""] }
    signal sound(string name)

    readonly property var st: qs.state
    readonly property bool hasProfiles: st.profiles && st.profiles.length > 0
    readonly property bool hasTdp: st.tdp !== null && st.tdp !== undefined
    readonly property var rows: {
        var r = []
        if (backend.desktopMode === true) r.push("xmode")      // desktop only
        if (hasProfiles) r.push("profile")
        if (hasTdp) r.push("tdp")
        if (st.brightness !== null && st.brightness !== undefined) r.push("brightness")
        if (st.volume !== null && st.volume !== undefined) r.push("volume")
        r.push("keyboard")
        if (backend.cursorAvailable === true) r.push("cursor")
        if (backend.handheld === true) r.push("rightback")
        if (backend.desktopMode === true) r.push("sleep", "restart", "poweroff")   // desktop only
        return r
    }
    readonly property string cur: rows[Math.min(idx, rows.length - 1)]

    readonly property var backChoices: ["nothing", "quick", "apps", "keyboard", "cursor"]
    readonly property var backLabel: ({ nothing: "Nothing", quick: "Quick Settings", apps: "Open apps",
                                        keyboard: "Keyboard", cursor: "Cursor on/off" })
    function cycleBack(dir) {
        var i = backChoices.indexOf(backend.rightBack)
        i = (Math.max(0, i) + dir + backChoices.length) % backChoices.length
        backend.setRightBack(backChoices[i]); sound("tab")
    }
    readonly property var profileLabel: ({ quiet: "Silent", balanced: "Balanced", performance: "Performance" })
    // the watt value the slider shows
    property int tdpShown: 0
    function tdpFromState() {
        return st.mode === "custom" && st.custom ? st.custom
             : (hasTdp && st.tdp.current ? st.tdp.current : (hasTdp ? st.tdp.min : 0))
    }
    Component.onCompleted: tdpShown = Qt.binding(tdpFromState)

    visible: x < parent.width
    width: u * 52
    height: parent.height
    x: open ? parent.width - width : parent.width
    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    property string confirm: ""          // Restart / Power off need a second press
    onCurChanged: { confirm = ""; Qt.callLater(reveal) }
    onOpenChanged: {
        if (open) { idx = 0; confirm = ""; flick.contentY = 0; qs.refresh(); tdpShown = Qt.binding(tdpFromState) }
        sound(open ? "menu_open" : "menu_close")
    }

    // slider changes are applied a moment after you stop moving
    Timer { id: tdpApply; interval: 600; onTriggered: qs.setTdp(qsPanel.tdpShown) }

    function step(dir) {
        if (cur === "profile") {
            var p = st.profiles, i = p.indexOf(st.profile)
            var n = Math.max(0, Math.min(p.length - 1, (i < 0 ? 1 : i) + dir))
            if (p[n] !== st.profile) { qs.setProfile(p[n]); sound("tab") } else sound("bump")
        } else if (cur === "tdp") {
            var w = Math.max(st.tdp.min, Math.min(st.tdp.max, tdpShown + dir))
            if (w !== tdpShown) { tdpShown = w; tdpApply.restart(); sound("move") } else sound("bump")
        } else if (cur === "brightness") {
            var b = Math.max(5, Math.min(100, Math.round((st.brightness + dir * 5) / 5) * 5))
            qs.setBrightness(b); sound("move")
        } else if (cur === "volume") {
            var v = Math.max(0, Math.min(100, Math.round((st.volume + dir * 5) / 5) * 5))
            qs.setVolume(v); sound("move")
        } else if (cur === "rightback") {
            cycleBack(dir)
        } else if (cur === "cursor") {
            if ((dir > 0) !== (backend.cursorOn === true)) { backend.toggleCursor(); sound("tab") } else sound("bump")
        } else sound("bump")
    }
    // keep the selected card on screen: scroll when the selection reaches an edge
    function reveal() {
        var kids = col.children
        for (var i = 0; i < kids.length; i++) {
            var c = kids[i]
            if (c.row !== cur || !c.visible) continue
            var top = col.y + c.y - u * 2, bottom = col.y + c.y + c.height + u * 2
            if (top < flick.contentY) flick.contentY = Math.max(0, top)
            else if (bottom > flick.contentY + flick.height)
                flick.contentY = Math.min(flick.contentHeight - flick.height, bottom - flick.height)
            return
        }
    }
    function power(action) {
        if (action !== "sleep" && confirm !== action) { confirm = action; sound("warn"); return }
        sound("select"); open = false
        backend.power(action)
    }
    function accept() {
        if (cur === "rightback") { cycleBack(1); return }
        if (cur === "xmode") { sound("select"); open = false; backend.switchToXMode(); return }
        if (cur === "sleep" || cur === "restart" || cur === "poweroff") { power(cur); return }
        if (cur === "cursor") { backend.toggleCursor(); sound("select"); return }
        if (cur === "keyboard") { sound("select"); open = false; backend.toggleKeyboard() }
        else if (cur === "volume") { qs.toggleMute(); sound("select") }
        else sound("bump")
    }
    function handle(a) {
        if (a === "up")    { idx = (idx - 1 + rows.length) % rows.length; sound("move") }
        else if (a === "down")  { idx = (idx + 1) % rows.length; sound("move") }
        else if (a === "left")  step(-1)
        else if (a === "right") step(1)
        else if (a === "accept") accept()
        else if (a === "back" || a === "quick" || a === "menu" || a === "taskview") open = false
        else sound("bump")
    }

    Rectangle { anchors.fill: parent; color: "#0A1428" }
    Rectangle { width: 1; height: parent.height; color: "#5500E5FF" }
    MouseArea { anchors.fill: parent }

    Flickable {
        id: flick
        anchors { fill: parent; leftMargin: u * 4; rightMargin: u * 4 }
        contentHeight: col.height + u * 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Behavior on contentY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Column {
        id: col
        y: u * 4
        width: flick.width
        spacing: u * 1.4

        Item {
            width: parent.width; height: u * 4.6
            Text { text: "Quick Settings"; color: "#E8F4FF"; font.pixelSize: u * 3.4; font.bold: true
                   anchors.verticalCenter: parent.verticalCenter }
            Status { u: qsPanel.u; anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
        }
        Item { width: 1; height: u * 0.5 }

        // ------------------------------------------ switch to X Mode (desktop)
        Card {
            row: "xmode"
            title: "Switch to X Mode"
            sub: "Full-screen controller mode for your games"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("xmode"); qsPanel.accept() }
        }

        // ---------------------------------------------- performance mode
        Card {
            row: "profile"
            title: "Performance mode"
            sub: st.mode === "custom" && hasTdp ? "Custom power limit active" : "Pick how hard the device works"
            Row {
                spacing: u * 1
                Repeater {
                    model: qsPanel.st.profiles || []
                    delegate: Rectangle {
                        readonly property bool on: modelData === qsPanel.st.profile && qsPanel.st.mode !== "custom"
                        width: (qsPanel.width - u * 8 - u * 4.8 - u * 2) / Math.max(1, qsPanel.st.profiles.length)
                        height: u * 4.6
                        radius: height / 2
                        color: on ? "#3300E5FF" : "#140047AB"
                        border.color: on ? "#00E5FF" : "#3300E5FF"
                        border.width: on ? Math.max(2, u * 0.25) : 1
                        Text {
                            anchors.centerIn: parent
                            text: qsPanel.profileLabel[modelData] || modelData
                            color: on ? "#E8F4FF" : "#9FB3C8"
                            font.pixelSize: u * 1.8; font.bold: on
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("profile"); qs.setProfile(modelData); qsPanel.sound("tab") }
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------- power limit
        Card {
            row: "tdp"
            title: "Power limit (TDP)"
            value: qsPanel.tdpShown + " W"
            sub: qsPanel.st.mode === "custom" ? "Custom · lower = longer battery, higher = more FPS"
                                              : "Following the performance mode · move to set your own"
            Slider {
                from: qsPanel.hasTdp ? qsPanel.st.tdp.min : 0
                to: qsPanel.hasTdp ? qsPanel.st.tdp.max : 1
                value: qsPanel.tdpShown
                onMoved: function(v) { qsPanel.tdpShown = Math.round(v); tdpApply.restart() }
            }
        }

        // ------------------------------------------------------ brightness
        Card {
            row: "brightness"
            title: "Brightness"
            value: (qsPanel.st.brightness || 0) + "%"
            Slider {
                from: 5; to: 100
                value: qsPanel.st.brightness || 0
                onMoved: function(v) { qs.setBrightness(Math.round(v)) }
            }
        }

        // ---------------------------------------------------------- volume
        Card {
            row: "volume"
            title: "Volume"
            value: qsPanel.st.muted ? "Muted" : (qsPanel.st.volume || 0) + "%"
            sub: "Press " + qsPanel.glyph("accept")[0] + " to mute"
            Slider {
                from: 0; to: 100
                dim: qsPanel.st.muted
                value: qsPanel.st.volume || 0
                onMoved: function(v) { qs.setVolume(Math.round(v)) }
            }
        }

        // -------------------------------------------------------- keyboard
        Card {
            row: "keyboard"
            title: "On-screen keyboard"
            sub: backend.inputMode === "keyboard" ? "Type with touch or a controller"
                 : "Left back button, or hold " + qsPanel.glyph("taskview")[0] + " and press " + qsPanel.glyph("secondary")[0]
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("keyboard"); qsPanel.accept() }
        }

        // ------------------------------------------- controller cursor (desktop)
        Card {
            row: "cursor"
            title: "Controller cursor"
            value: backend.cursorOn === true ? "On" : "Off"
            sub: backend.desktopMode === true ? "Stick moves · A click · ☰ right-click · right stick scrolls"
                 : "Mouse for apps opened from X Mode · A click · ☰ right-click · turn off for games"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("cursor"); qsPanel.accept() }
        }

        // ------------------------------------------- right back button (handhelds)
        Card {
            row: "rightback"
            title: "Right back button"
            value: "◀  " + (qsPanel.backLabel[backend.rightBack] || "Nothing") + "  ▶"
            sub: "Pick what it does - in X Mode and on the desktop"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("rightback"); qsPanel.accept() }
        }

        // ------------------------------------------------ power (desktop)
        Text {
            visible: qsPanel.rows.indexOf("sleep") >= 0
            topPadding: u * 1.5
            text: "Power"; color: "#7A8FA8"; font.pixelSize: u * 1.7; font.bold: true
        }
        Card {
            row: "sleep"; title: "Sleep"; sub: "Suspend the device"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("sleep"); qsPanel.accept() }
        }
        Card {
            row: "restart"; title: "Restart"
            warn: qsPanel.confirm === "restart"
            sub: warn ? "Press " + qsPanel.glyph("accept")[0] + " again to restart" : "Restart the device"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("restart"); qsPanel.accept() }
        }
        Card {
            row: "poweroff"; title: "Power off"
            warn: qsPanel.confirm === "poweroff"
            sub: warn ? "Press " + qsPanel.glyph("accept")[0] + " again to power off" : "Shut down the device"
            clickable: true
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf("poweroff"); qsPanel.accept() }
        }

        Text {
            visible: !qsPanel.hasTdp
            width: parent.width
            topPadding: u * 1.5
            wrapMode: Text.Wrap
            text: "Power limit controls are available on supported handhelds (ROG Ally, Steam Deck)."
            color: "#7A8FA8"; font.pixelSize: u * 1.5
        }
    }
    }

    // ------------------------------------------------------------ pieces
    component Card: Rectangle {
        id: card
        property string row: ""
        property string title: ""
        property string value: ""
        property string sub: ""
        property bool clickable: false
        property bool warn: false
        signal clicked()
        default property alias content: slot.data
        readonly property bool sel: qsPanel.cur === row
        visible: qsPanel.rows.indexOf(row) >= 0
        width: parent.width
        height: body.implicitHeight + u * 3.6
        radius: u * 1.2
        color: sel ? "#2600E5FF" : "#140047AB"
        border.color: sel ? "#00E5FF" : "#2200E5FF"
        border.width: sel ? Math.max(2, u * 0.3) : 1
        MouseArea {
            anchors.fill: parent
            onClicked: { qsPanel.idx = qsPanel.rows.indexOf(card.row); if (card.clickable) card.clicked() }
        }
        Column {
            id: body
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: u * 2.4; rightMargin: u * 2.4 }
            spacing: u * 1
            Item {
                width: parent.width; height: u * 3
                Text { text: card.title; color: card.warn ? "#FFB84D" : "#E8F4FF"; font.pixelSize: u * 2.2; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Text { text: card.value; color: "#00E5FF"; font.pixelSize: u * 2.2; font.bold: true
                       anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
            }
            Item { id: slot; width: parent.width; height: childrenRect.height; visible: children.length > 0 }
            Text { visible: card.sub !== ""; text: card.sub; color: card.warn ? "#FFB84D" : "#7A8FA8"
                   font.pixelSize: u * 1.5; width: parent.width; wrapMode: Text.Wrap }
        }
    }

    component Slider: Item {
        id: sl
        property real from: 0
        property real to: 100
        property real value: 0
        property bool dim: false
        signal moved(real v)
        width: qsPanel.width - u * 8 - u * 4.8
        height: u * 3.2
        readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: u * 0.9; radius: height / 2
            color: "#1E2D4A"
            Rectangle {
                width: parent.width * sl.frac; height: parent.height; radius: height / 2
                color: sl.dim ? "#4A5A75" : "#00E5FF"
                Behavior on width { NumberAnimation { duration: 90 } }
            }
        }
        Rectangle {
            x: (sl.width - width) * sl.frac
            anchors.verticalCenter: parent.verticalCenter
            width: u * 2.8; height: width; radius: width / 2
            color: "#E8F4FF"
            border.color: sl.dim ? "#4A5A75" : "#00E5FF"; border.width: Math.max(2, u * 0.3)
            Behavior on x { NumberAnimation { duration: 90 } }
        }
        MouseArea {
            anchors.fill: parent
            function at(mx) { return sl.from + Math.max(0, Math.min(1, mx / sl.width)) * (sl.to - sl.from) }
            onPressed: function(m) { sl.moved(at(m.x)) }
            onPositionChanged: function(m) { if (pressed) sl.moved(at(m.x)) }
        }
    }
}
