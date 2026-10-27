import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 1280
    height: 800
    visible: true
    title: "X Mode"
    color: "#050a18"
    property bool fullscreen: backend.fullscreen          // F11 toggles
    visibility: fullscreen ? Window.FullScreen : Window.Windowed

    // One "unit" scales the whole UI with the screen (Ally 1080p, Deck 800p, ...)
    readonly property real u: Math.min(width / 160, height / 90)

    readonly property color cCobalt: "#0047AB"
    readonly property color cCyan: "#00E5FF"
    readonly property color cIce: "#E8F4FF"
    readonly property color cMuted: "#7A8FA8"

    // --------------------------------------------------------------- state
    property int tabIndex: 0
    property var tabs: []
    property var shown: []
    property bool firstLoad: true
    readonly property var current: grid.currentIndex >= 0 && grid.currentIndex < shown.length
                                   ? shown[grid.currentIndex] : null

    readonly property var tabDefs: [
        { id: "recent",  label: "Recent" },
        { id: "library", label: "Library" },
        { id: "all",     label: "All Games" },
        { id: "launcher", label: "Launchers" },
        { id: "steam",   label: "Steam" },
        { id: "heroic",  label: "Heroic" },
        { id: "bottles", label: "Bottles" },
        { id: "other",   label: "Other" }
    ]

    // ---------------------------------------------- controller glyphs
    // Whatever was used last (keyboard/mouse, Xbox, DualSense, Switch, Steam)
    // decides which button names the hints show - like Steam does.
    readonly property var glyphMap: ({
        "xbox":        { accept: ["A", "#3FB950"], back: ["B", "#F85149"], tabPrev: ["LB", ""], tabNext: ["RB", ""], menu: ["☰", ""], taskview: ["XBOX", ""], secondary: ["X", "#58A6FF"] },
        "generic":     { accept: ["A", ""],        back: ["B", ""],        tabPrev: ["LB", ""], tabNext: ["RB", ""], menu: ["☰", ""], taskview: ["HOME", ""], secondary: ["X", ""] },
        "steam":       { accept: ["A", "#3FB950"], back: ["B", "#F85149"], tabPrev: ["L1", ""], tabNext: ["R1", ""], menu: ["☰", ""], taskview: ["STEAM", ""], secondary: ["X", "#58A6FF"] },
        "playstation": { accept: ["✕", "#7FA7FF"], back: ["○", "#FF6B6B"], tabPrev: ["L1", ""], tabNext: ["R1", ""], menu: ["OPTIONS", ""], taskview: ["PS", ""], secondary: ["□", "#F778BA"] },
        "nintendo":    { accept: ["A", ""],        back: ["B", ""],        tabPrev: ["L", ""],  tabNext: ["R", ""],  menu: ["+", ""], taskview: ["HOME", ""], secondary: ["Y", ""] },
        "keyboard":    { accept: ["Enter", ""],    back: ["Esc", ""],      tabPrev: ["Q", ""],  tabNext: ["E", ""],  menu: ["Tab", ""], taskview: ["Alt+F12", ""], secondary: ["Del", ""] }
    })
    function glyph(action) {
        var m = glyphMap[backend.inputMode] || glyphMap["generic"]
        return m[action] || ["?", ""]
    }

    function byTitle(a, b) { return a.title.toLowerCase().localeCompare(b.title.toLowerCase()) }

    readonly property var addTile: ({ key: "__add__", title: "Add a game", source: "add", sourceLabel: "",
                                      cover: "", icon: "", lastPlayed: 0 })

    function gamesFor(tabId) {
        var all = backend.games
        if (tabId === "library") {               // everything: launchers first, then games, + "Add a game"
            var l = all.filter(function(g) { return g.source === "launcher" }).sort(byTitle)
            var g = all.filter(function(g) { return g.source !== "launcher" }).sort(byTitle)
            return [addTile].concat(l).concat(g)
        }
        if (tabId === "all") return all.filter(function(g) { return g.source !== "launcher" }).sort(byTitle)
        if (tabId === "recent")
            return all.filter(function(g) { return g.lastPlayed > 0 })
                      .sort(function(a, b) { return b.lastPlayed - a.lastPlayed })
        return all.filter(function(g) { return g.source === tabId }).sort(byTitle)
    }

    function rebuild() {
        var keepKey = current ? current.key : ""
        var keepTab = tabs.length ? tabs[tabIndex].id : ""
        // Only show tabs that have something in them ("All Games" always)
        var t = tabDefs.filter(function(d) { return d.id === "all" || d.id === "library" || gamesFor(d.id).length > 0 })
        tabs = t
        var idx = t.findIndex(function(d) { return d.id === keepTab })
        if (firstLoad || idx < 0) idx = 0                 // Recent first if there is any history
        if (firstLoad && backend.games.length) firstLoad = false
        tabIndex = idx
        showTab(keepKey)
    }

    function showTab(keepKey) {
        shown = gamesFor(tabs[tabIndex].id)
        var i = keepKey ? shown.findIndex(function(g) { return g.key === keepKey }) : -1
        grid.currentIndex = shown.length ? Math.max(0, i) : -1
        grid.positionViewAtIndex(Math.max(0, grid.currentIndex), GridView.Beginning)
    }

    function sfx(name) { backend.playSound(name) }

    function switchTab(step) {
        if (tabs.length < 2) { sfx("bump"); return }
        sfx("tab")
        tabIndex = (tabIndex + step + tabs.length) % tabs.length
        showTab("")
    }

    // A on a tile opens its game page (Play lives there, like Steam)
    function openDetails() {
        if (!current) { sfx("bump"); return }
        if (current.key === "__add__") { fileBrowser.show(); return }
        sfx("select")
        details.show(current)
    }

    function move(fn) {
        var before = grid.currentIndex
        fn()
        sfx(grid.currentIndex !== before ? "move" : "bump")   // "bump" at the edges
    }

    // One place where keyboard + controller input ends up
    function handle(a) {
        if (a === "taskview") {                    // Xbox / PS / Steam button (keyboard: Alt+F12)
            fileBrowser.open = false
            if (quickPanel.open || taskView.open) {    // those are opened from the menu: go back to it
                quickPanel.open = false; taskView.open = false; menu.open = true
            } else menu.open = !menu.open
            return
        }
        if (a === "quickpanel") {                  // right back button, if set to Quick Settings
            fileBrowser.open = false
            if (quickPanel.open) { quickPanel.open = false; return }
            menu.open = false; taskView.open = false
            quickPanel.open = true
            return
        }
        if (a === "apps") {                        // Armoury Crate button (handhelds) / Alt+F12
            if (taskView.open) { taskView.open = false; return }
            if (!backend.apps.length) { toast.show("No apps are open"); sfx("bump"); return }
            menu.open = false; quickPanel.open = false
            taskView.open = true
            return
        }
        if (fileBrowser.open) { fileBrowser.handle(a); return }
        if (quickPanel.open) { quickPanel.handle(a); return }
        if (menu.open) { menu.handle(a); return }
        if (taskView.open) { taskView.handle(a); return }
        if (details.open && a !== "menu") { details.handle(a); return }
        switch (a) {
        case "left":    move(grid.moveCurrentIndexLeft); break
        case "right":   move(grid.moveCurrentIndexRight); break
        case "up":      move(grid.moveCurrentIndexUp); break
        case "down":    move(grid.moveCurrentIndexDown); break
        case "accept":  openDetails(); break
        case "tabPrev": switchTab(-1); break
        case "tabNext": switchTab(1); break
        case "menu":    menu.open = true; break
        }
    }

    Connections {
        target: backend
        function onGamesChanged() {
            win.rebuild()
            if (details.game) {         // keep the open game page up to date (last played etc.)
                var k = details.game.key
                var g = backend.games.find(function(x) { return x.key === k })
                if (g) details.game = g
            }
        }
        function onAction(a) { win.handle(a) }
        function onToast(msg) { toast.show(msg) }
        function onLaunched() { win.sfx("launch") }
        function onRemoved() { details.open = false }
    }

    Component.onCompleted: rebuild()


    // ---------------------------------------------------------- background
    Image {
        id: heroBg
        anchors.fill: parent
        source: current ? (current.hero || current.cover || "") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1280
        opacity: status === Image.Ready ? 0.28 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#99050a18" }
            GradientStop { position: 0.45; color: "#dd050a18" }
            GradientStop { position: 1.0; color: "#ff050a18" }
        }
    }
    // Subtle grid pattern (same as the Welcome App / website)
    Canvas {
        anchors.fill: parent
        opacity: 0.05
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#00E5FF"
            ctx.lineWidth = 1
            var step = Math.round(u * 5)
            for (var x = 0; x < width; x += step) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke() }
            for (var y = 0; y < height; y += step) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // ----------------------------------------------------------- key input
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(e) {
            // keys typed by the on-screen keyboard are meant for another app
            if (backend.keyboardVisible) { e.accepted = true; return }
            var map = {}
            map[Qt.Key_Left] = "left"; map[Qt.Key_Right] = "right"
            map[Qt.Key_Up] = "up"; map[Qt.Key_Down] = "down"
            map[Qt.Key_Return] = "accept"; map[Qt.Key_Enter] = "accept"; map[Qt.Key_Space] = "accept"
            map[Qt.Key_Backspace] = "back"
            map[Qt.Key_Q] = "tabPrev"; map[Qt.Key_PageUp] = "tabPrev"
            map[Qt.Key_E] = "tabNext"; map[Qt.Key_PageDown] = "tabNext"
            map[Qt.Key_Tab] = "menu"
            map[Qt.Key_Delete] = "secondary"
            var known = map[e.key] !== undefined || e.key === Qt.Key_Escape || e.key === Qt.Key_F5 || e.key === Qt.Key_F11
            if (known) backend.useKeyboard()      // stray keys (e.g. from handheld buttons) don't count
            if (e.key === Qt.Key_Escape) { handle(menu.open || details.open || taskView.open || quickPanel.open ? "back" : "menu"); e.accepted = true; return }
            if (e.key === Qt.Key_F5) { backend.refresh(); e.accepted = true; return }
            if (e.key === Qt.Key_F11) { win.fullscreen = !win.fullscreen; e.accepted = true; return }
            if (map[e.key] !== undefined) { handle(map[e.key]); e.accepted = true }
        }
    }

    // ------------------------------------------------------------- top bar
    Item {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: u * 9

        Row {
            anchors { left: parent.left; leftMargin: u * 5; verticalCenter: parent.verticalCenter }
            spacing: u * 1.4
            Image {
                source: "xmode-icon.svg"
                width: u * 4.6; height: width
                sourceSize: Qt.size(128, 128)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "X MODE"
                color: cIce
                font.pixelSize: u * 2.8
                font.bold: true
                font.letterSpacing: u * 0.3
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {          // apps running -> click to open the task view
                anchors.leftMargin: u * 1
                visible: backend.apps.length > 0
                anchors.verticalCenter: parent.verticalCenter
                height: u * 3.2
                width: openText.implicitWidth + u * 2.6
                radius: height / 2
                color: "#2600E5FF"
                border.color: cCyan
                border.width: 1
                Text {
                    id: openText
                    anchors.centerIn: parent
                    text: backend.apps.length + " open"
                    color: cIce; font.pixelSize: u * 1.5; font.bold: true
                }
                MouseArea { anchors.fill: parent; onClicked: taskView.open = true }
            }
        }

        // Tabs, switched with LB / RB
        Row {
            anchors.centerIn: parent
            spacing: u * 2.2
            Glyph { action: "tabPrev"; anchors.verticalCenter: parent.verticalCenter; visible: tabs.length > 1 }
            Repeater {
                model: tabs
                delegate: Column {
                    spacing: u * 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: modelData.label
                        color: index === tabIndex ? cIce : cMuted
                        font.pixelSize: u * 2.1
                        font.bold: index === tabIndex
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (index !== tabIndex) { sfx("tab"); tabIndex = index; showTab("") } }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: u * 0.4; radius: height / 2
                        color: cCyan
                        opacity: index === tabIndex ? 1 : 0
                    }
                }
            }
            Glyph { action: "tabNext"; anchors.verticalCenter: parent.verticalCenter; visible: tabs.length > 1 }
        }

        Row {
            anchors { right: parent.right; rightMargin: u * 5; verticalCenter: parent.verticalCenter }
            spacing: u * 2.4
            Rectangle {          // which input method X Mode is showing controls for
                anchors.verticalCenter: parent.verticalCenter
                height: u * 3.2
                width: inputText.implicitWidth + u * 2.6
                radius: height / 2
                color: "#1400E5FF"
                border.color: "#3300E5FF"
                border.width: 1
                Text {
                    id: inputText
                    anchors.centerIn: parent
                    text: backend.inputName
                    color: cMuted
                    font.pixelSize: u * 1.5
                    font.bold: true
                }
            }
            Row {
                visible: backend.battery >= 0
                spacing: u * 0.8
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {   // battery icon
                    width: u * 3.6; height: u * 1.8; radius: u * 0.3
                    color: "transparent"; border.color: cIce; border.width: Math.max(1, u * 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        x: u * 0.35; y: u * 0.35
                        height: parent.height - u * 0.7
                        width: (parent.width - u * 0.7) * Math.max(0, backend.battery) / 100
                        radius: u * 0.15
                        color: backend.charging ? cCyan : (backend.battery <= 15 ? "#FF5C5C" : cIce)
                    }
                }
                Text {
                    text: backend.battery + "%" + (backend.charging ? " ⚡" : "")
                    color: cIce; font.pixelSize: u * 1.9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                id: clock
                color: cIce
                font.pixelSize: u * 2.2
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatTime(new Date(), "hh:mm")
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm")
    }
    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: backend.updateBattery()
    }

    // --------------------------------------------- selected game info area
    Item {
        id: info
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; leftMargin: u * 6; rightMargin: u * 6 }
        height: u * 13

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: u * 0.6
            Text {
                width: parent.width
                text: current ? current.title : (backend.scanning ? "Scanning your library…" : "No games yet")
                color: cIce
                font.pixelSize: u * 4.6
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: {
                    if (!current)
                        return backend.scanning ? "Looking in Steam, Heroic, Bottles and your installed games"
                                                : "Install games with Steam or Heroic and they'll show up here"
                    var s = current.sourceLabel
                    if (current.lastPlayed > 0) {
                        var d = new Date(current.lastPlayed * 1000)
                        s += "  ·  Last played " + Qt.formatDate(d, "d MMM yyyy")
                    }
                    return s
                }
                color: cCyan
                font.pixelSize: u * 2
            }
        }
    }

    // --------------------------------------------------------- game grid
    GridView {
        id: grid
        anchors { left: parent.left; right: parent.right; top: info.bottom; bottom: hints.top; leftMargin: u * 4; rightMargin: u * 4 }
        clip: true
        topMargin: u * 2
        bottomMargin: u * 2
        readonly property real tileW: u * 22
        readonly property int columns: Math.max(1, Math.floor(width / (tileW + u * 3.5)))
        cellWidth: width / columns
        cellHeight: tileW * 1.5 + u * 4.5
        model: shown
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Beginning)

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight
            z: GridView.isCurrentItem ? 2 : 1
            GameTile {
                anchors.centerIn: parent
                width: grid.tileW
                height: grid.tileW * 1.5
                u: win.u
                game: modelData
                selected: parent.GridView.isCurrentItem
            }
            MouseArea {   // touchscreen / mouse: tap to select, tap again to open
                anchors.fill: parent
                onClicked: {
                    if (grid.currentIndex === index) win.openDetails()
                    else { grid.currentIndex = index; win.sfx("move") }
                }
            }
        }
    }

    // Spinner while the first scan runs
    Item {
        id: spinner
        anchors.centerIn: grid
        visible: backend.scanning && shown.length === 0
        width: u * 8; height: width
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#2200E5FF"
            border.width: u * 0.8
        }
        Rectangle {
            width: u * 1.6; height: width; radius: width / 2
            color: cCyan
            x: parent.width / 2 - width / 2; y: -width / 2 + u * 0.4
            transformOrigin: Item.Center
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: spinner.visible }
    }

    // ----------------------------------------------------- game page
    Details {
        id: details
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: hints.top }
        u: win.u
        onSound: function(name) { win.sfx(name) }
    }

    // -------------------------------------------------------- button hints
    Item {
        id: hints
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: u * 7
        Rectangle { anchors.fill: parent; color: "#aa050a18" }
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#2200E5FF" }

        Text {
            anchors { left: parent.left; leftMargin: u * 5; verticalCenter: parent.verticalCenter }
            text: "CobaltX " + backend.version + "  ·  Forged for play"
            color: cMuted
            font.pixelSize: u * 1.6
        }
        Row {
            anchors { right: parent.right; rightMargin: u * 5; verticalCenter: parent.verticalCenter }
            spacing: u * 3.2
            Hint {
                action: "accept"
                label: menu.open ? "Select" : (details.open ? (details.focusIdx === 0 ? "Play" : "Open")
                       : (current && current.key === "__add__" ? "Add a game" : "Details"))
                visible: menu.open || details.open || current !== null
            }
            Hint { action: "back"; label: "Back"; visible: menu.open || details.open }
            Hint { action: backend.inputMode === "keyboard" ? "menu" : "taskview"; label: "Menu"; visible: !menu.open }
        }
    }

    // While an app is open and X Mode is in the background, show a plain
    // background instead of the launcher (small windows like Steam's login
    // would otherwise float over the game grid).
    Rectangle {
        id: backdrop
        anchors.fill: parent
        visible: backend.apps.length > 0 && !win.active && !taskView.open && !menu.open && !quickPanel.open
        color: "#050a18"
        Column {
            anchors.centerIn: parent
            spacing: u * 2
            opacity: 0.55
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "xmode-icon.svg"
                width: u * 10; height: width
                sourceSize: Qt.size(256, 256)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: u * 1
                visible: backend.taskViewAvailable
                Text { text: "Press"; color: cMuted; font.pixelSize: u * 1.9; anchors.verticalCenter: parent.verticalCenter }
                Glyph { action: "taskview"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "to return to X Mode"; color: cMuted; font.pixelSize: u * 1.9; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ------------------------------------------------------- side menu
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: menu.open ? 0.55 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: menu.open = false }
    }

    Rectangle {
        id: menu
        property bool open: false
        property int idx: 0
        property string confirm: ""
        readonly property var items: (backend.apps.length ? [
            { id: "apps", label: "Open Apps (" + backend.apps.length + ")", desc: "Resume or close what's running" }
        ] : []).concat(base).concat(backend.inSession ? [] : [
            { id: "close", label: "Close X Mode", desc: "Back to the desktop" }
        ]).concat(tail)
        readonly property var base: [
            backend.inSession
                ? { id: "desktop", label: "Switch to Desktop", desc: "Go to the KDE Plasma desktop" }
                : { id: "session", label: "Start X Mode Session", desc: "Leave the desktop and start X Mode" }
        ]
        readonly property var tail: [
            { id: "quick",    label: "Quick Settings",  desc: "Performance mode, power limit, brightness, volume" },
            { id: "startup",  label: "Start in X Mode at login: " + (backend.startAtLogin ? "On" : "Off"),
                              desc: backend.startAtLogin ? "CobaltX boots straight into X Mode" : "CobaltX boots into the desktop" },
            { id: "refresh",  label: "Refresh Library", desc: "Look for newly installed games" },
            { id: "sounds",   label: "UI Sounds: " + (backend.soundsOn ? "On" : "Off"),
                              desc: "Menu and navigation sound effects" },
            { id: "suspend",  label: "Sleep",           desc: "Suspend the device" },
            { id: "reboot",   label: "Restart",         desc: "Restart the device" },
            { id: "poweroff", label: "Power Off",       desc: "Shut down the device" }
        ]

        width: u * 44
        height: parent.height
        x: open ? parent.width - width : parent.width
        visible: x < parent.width
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        color: "#0A1428"
        Rectangle { width: 1; height: parent.height; color: "#5500E5FF" }

        onOpenChanged: { idx = 0; confirm = ""; menuFlick.contentY = 0; win.sfx(open ? "menu_open" : "menu_close") }

        function handle(a) {
            if (a === "up")   { idx = (idx - 1 + items.length) % items.length; confirm = ""; win.sfx("move") }
            if (a === "down") { idx = (idx + 1) % items.length; confirm = ""; win.sfx("move") }
            if (a === "back" || a === "menu") open = false
            if (a === "accept") activate()
        }
        function activate() {
            var it = items[idx]
            // Restart / Power Off need a second press so nobody shuts down by accident
            if ((it.id === "reboot" || it.id === "poweroff") && confirm !== it.id) {
                confirm = it.id; win.sfx("warn"); return
            }
            confirm = ""
            if (it.id === "sounds") {                 // toggle in place, keep the menu open
                backend.toggleSounds(); win.sfx("select"); return
            }
            if (it.id === "startup") {
                backend.toggleStartAtLogin(); win.sfx("select"); return
            }
            win.sfx("select")
            open = false
            if (it.id === "quick") { quickPanel.open = true; return }
            if (it.id === "apps") { taskView.open = true; return }
            backend.menuAction(it.id)
        }

        // scrolls when the selection reaches the edge (long menus on small screens)
        function reveal() {
            var it = menuRepeater.itemAt(idx)
            if (!it) return
            var top = menuCol.y + it.y - u * 2, bottom = menuCol.y + it.y + it.height + u * 2
            if (top < menuFlick.contentY) menuFlick.contentY = Math.max(0, top)
            else if (bottom > menuFlick.contentY + menuFlick.height)
                menuFlick.contentY = Math.min(menuFlick.contentHeight - menuFlick.height, bottom - menuFlick.height)
        }
        onIdxChanged: Qt.callLater(reveal)

        Flickable {
            id: menuFlick
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: menuFooter.top
                      leftMargin: u * 4; rightMargin: u * 4; bottomMargin: u * 1 }
            contentHeight: menuCol.height + u * 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Behavior on contentY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: menuCol
            y: u * 4
            width: menuFlick.width
            spacing: u * 1.2

            Item {
                width: parent.width; height: u * 4.6
                Text { text: "Menu"; color: cIce; font.pixelSize: u * 3.4; font.bold: true
                       anchors.verticalCenter: parent.verticalCenter }
                Status { u: win.u; anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
            }
            Item { width: 1; height: u * 1.5 }

            Repeater {
                id: menuRepeater
                model: menu.items
                delegate: Rectangle {
                    width: parent.width
                    height: u * 7
                    radius: u * 1.2
                    readonly property bool sel: index === menu.idx
                    readonly property bool asking: menu.confirm === modelData.id
                    color: sel ? "#2600E5FF" : "#140047AB"
                    border.color: sel ? cCyan : "#2200E5FF"
                    border.width: sel ? Math.max(2, u * 0.3) : 1
                    Column {
                        anchors { left: parent.left; leftMargin: u * 2.4; verticalCenter: parent.verticalCenter }
                        spacing: u * 0.3
                        Text {
                            text: modelData.label
                            color: asking ? "#FFB84D" : cIce
                            font.pixelSize: u * 2.3
                            font.bold: true
                        }
                        Text {
                            width: menu.width - u * 13
                            elide: Text.ElideRight
                            text: asking ? "Press A again to confirm" : modelData.desc
                            color: asking ? "#FFB84D" : cMuted
                            font.pixelSize: u * 1.6
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { menu.idx = index; menu.activate() }
                    }
                }
            }
        }

        }

        Column {
            id: menuFooter
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: u * 4 }
            spacing: u * 0.6
            Text { text: "X Mode · CobaltX " + backend.version; color: cMuted; font.pixelSize: u * 1.5 }
        }
    }

    // ----------------------------------------------- add a game (file browser)
    FileBrowser {
        id: fileBrowser
        anchors.fill: parent
        u: win.u
        glyph: win.glyph
        onSound: function(name) { win.sfx(name) }
    }

    // ----------------------------------------------------- quick settings
    QuickSettings {
        id: quickPanel
        u: win.u
        glyph: win.glyph
        onSound: function(name) { win.sfx(name) }
    }

    // ---------------------------------------------------------- task view
    TaskView {
        id: taskView
        anchors.fill: parent
        u: win.u
        glyph: win.glyph
        onSound: function(name) { win.sfx(name) }
    }

    // --------------------------------------------------------------- toast
    Rectangle {
        id: toast
        property string msg: ""
        function show(m) { msg = m; opacity = 1; hideTimer.restart() }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: hints.top; bottomMargin: u * 3 }
        width: toastText.implicitWidth + u * 6
        height: u * 6
        radius: height / 2
        color: "#0A1428"
        border.color: cCyan
        border.width: Math.max(1, u * 0.2)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text { id: toastText; anchors.centerIn: parent; text: toast.msg; color: cIce; font.pixelSize: u * 2.1 }
        Timer { id: hideTimer; interval: 3500; onTriggered: toast.opacity = 0 }
    }

    // Real mouse movement switches the hints to keyboard & mouse
    MouseArea {
        id: mouseWatch
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        property real travelled: 0
        property int moves: 0
        Timer { id: moveWindow; interval: 400; onTriggered: { mouseWatch.travelled = 0; mouseWatch.moves = 0 } }
        onPositionChanged: function(m) {
            if (m.source !== Qt.MouseEventNotSynthesized) return        // finger on the touchscreen
            if (last.x >= 0) {
                if (!moveWindow.running) moveWindow.start()
                travelled += Math.abs(m.x - last.x) + Math.abs(m.y - last.y)
                moves += 1
                // several real moves covering some distance = someone is using a mouse
                if (moves >= 4 && travelled > 60) { backend.useKeyboard(); travelled = 0; moves = 0 }
            }
            last = Qt.point(m.x, m.y)
        }
    }

    // ------------------------------------------------- small components
    component Glyph: Rectangle {
        id: gl
        property string action: ""
        readonly property var g: win.glyph(action)
        readonly property string shown: g[0]
        width: Math.max(height, glyphText.implicitWidth + u * 1.4)
        height: u * 3.2
        radius: height / 2
        color: "#1F00E5FF"
        border.color: g[1] !== "" ? g[1] : "#6600E5FF"
        border.width: g[1] !== "" ? Math.max(1, u * 0.2) : 1
        Text {
            id: glyphText
            anchors.centerIn: parent
            text: gl.shown
            color: gl.g[1] !== "" ? gl.g[1] : cIce
            font.pixelSize: gl.shown.length === 1 ? u * 1.9 : (gl.shown.length > 3 ? u * 1.25 : u * 1.6)
            font.bold: true
        }
    }

    component Hint: Row {
        property string action: ""
        property string label: ""
        spacing: u * 1
        Glyph { action: parent.action; anchors.verticalCenter: parent.verticalCenter }
        Text { text: parent.label; color: cIce; font.pixelSize: u * 1.9; anchors.verticalCenter: parent.verticalCenter }
    }
}
