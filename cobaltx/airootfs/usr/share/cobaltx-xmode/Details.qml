import QtQuick

// Game page: big artwork banner, Play button and stats - opened with A on a tile.
Item {
    id: page
    property var game: null
    property real u: 8
    property bool open: false
    property int focusIdx: 0

    signal sound(string name)

    readonly property var buttons: game && game.openLabel ? ["play", "open"] : ["play"]
    readonly property bool hasHero: heroImg.status === Image.Ready

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    function show(g) { game = g; focusIdx = 0; open = true }
    function close() { open = false; sound("back") }

    function handle(a) {
        if (a === "left" || a === "right") {
            var n = focusIdx + (a === "right" ? 1 : -1)
            if (n < 0 || n >= buttons.length) { sound("bump"); return }
            focusIdx = n; sound("move")
        } else if (a === "up" || a === "down" || a === "tabPrev" || a === "tabNext") {
            sound("bump")
        } else if (a === "accept") {
            activate()
        } else if (a === "back") {
            close()
        }
    }

    function activate() {
        if (!game) return
        if (buttons[focusIdx] === "play") backend.launch(game.key)
        else { sound("select"); backend.openInLauncher(game.key) }
    }

    function fmtDate(t) {
        if (!t) return "Never"
        var d = new Date(t * 1000), now = new Date()
        if (d.toDateString() === now.toDateString()) return "Today"
        var y = new Date(now); y.setDate(now.getDate() - 1)
        if (d.toDateString() === y.toDateString()) return "Yesterday"
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    function fmtTime(m) {
        if (m < 60) return m + " min"
        return (m / 60).toFixed(1).replace(".0", "") + " hours"
    }

    Rectangle { anchors.fill: parent; color: "#050a18" }

    // --------------------------------------------------------- banner
    Item {
        id: hero
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: parent.height * 0.5
        clip: true

        Rectangle {          // fallback when there's no artwork
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#0A1F4D" }
                GradientStop { position: 1.0; color: "#0047AB" }
            }
        }
        Image {              // big faded icon on the fallback banner
            anchors { right: parent.right; rightMargin: page.u * 10; verticalCenter: parent.verticalCenter }
            width: parent.height * 0.62; height: width
            source: page.game ? (page.game.icon || "") : ""
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectFit
            visible: !page.hasHero && status === Image.Ready
            opacity: 0.9
        }
        Image {
            id: heroImg
            anchors.fill: parent
            source: page.game ? (page.game.hero || page.game.cover || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 1920
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
        Rectangle {          // fade into the page
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00050a18" }
                GradientStop { position: 0.6; color: "#22050a18" }
                GradientStop { position: 1.0; color: "#ff050a18" }
            }
        }

        // Title: the game's own logo if the launcher has one, otherwise text
        Image {
            id: logo
            anchors { left: parent.left; leftMargin: page.u * 6; bottom: parent.bottom; bottomMargin: page.u * 4 }
            width: parent.width * 0.42
            height: parent.height * 0.42
            source: page.game ? (page.game.logo || "") : ""
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            verticalAlignment: Image.AlignBottom
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            visible: logo.status !== Image.Ready
            anchors { left: parent.left; leftMargin: page.u * 6; right: parent.right; rightMargin: page.u * 6
                      bottom: parent.bottom; bottomMargin: page.u * 4 }
            text: page.game ? page.game.title : ""
            color: "#E8F4FF"
            font.pixelSize: page.u * 6.5
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            style: Text.Raised
            styleColor: "#aa000000"
        }
    }

    // ----------------------------------------------------- action bar
    Item {
        id: bar
        anchors { left: parent.left; right: parent.right; top: hero.bottom; leftMargin: page.u * 6; rightMargin: page.u * 6 }
        height: page.u * 11

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.u * 4

            // Play
            Rectangle {
                id: playBtn
                readonly property bool sel: page.focusIdx === 0
                width: page.u * 30; height: page.u * 8
                radius: page.u * 1.2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: playBtn.sel ? "#0A6CF0" : "#0047AB" }
                    GradientStop { position: 1.0; color: playBtn.sel ? "#00C8F0" : "#0A5BC4" }
                }
                border.color: sel ? "#00E5FF" : "transparent"
                border.width: Math.max(2, page.u * 0.3)
                scale: sel ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                Rectangle {      // glow
                    anchors.centerIn: parent
                    width: parent.width + page.u * 1.6; height: parent.height + page.u * 1.6
                    radius: parent.radius + page.u * 0.8
                    color: "transparent"; border.color: "#00E5FF"; border.width: page.u * 0.5
                    opacity: playBtn.sel ? 0.3 : 0
                    z: -1
                }
                Row {
                    anchors.centerIn: parent
                    spacing: page.u * 1.6
                    Text { text: "▶"; color: "white"; font.pixelSize: page.u * 3; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: page.game && page.game.source === "launcher" ? "Open" : "Play"; color: "white"; font.pixelSize: page.u * 3; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { page.focusIdx = 0; page.activate() }
                }
            }

            Stat { label: page.game && page.game.source === "launcher" ? "LAST OPENED" : "LAST PLAYED"; value: page.game ? page.fmtDate(page.game.lastPlayed) : "" }
            Stat {
                visible: page.game && page.game.playtime >= 0
                label: "PLAY TIME"
                value: page.game && page.game.playtime >= 0 ? page.fmtTime(page.game.playtime) : ""
            }
            Stat {
                visible: page.game && page.game.playtime < 0
                label: page.game && page.game.source === "launcher" ? "OPENED IN X MODE" : "PLAYED IN X MODE"
                value: !page.game ? "" : (!page.game.plays ? "Not yet" : (page.game.plays === 1 ? "1 time" : page.game.plays + " times"))
            }
            Stat { label: "LIBRARY"; value: page.game ? page.game.sourceLabel : "" }
        }

        // Open in Steam / Heroic / Bottles
        Rectangle {
            id: openBtn
            visible: page.buttons.length > 1
            readonly property bool sel: page.focusIdx === 1
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: openText.implicitWidth + page.u * 5
            height: page.u * 7
            radius: page.u * 1.2
            color: sel ? "#2600E5FF" : "#1AFFFFFF"
            border.color: sel ? "#00E5FF" : "#33FFFFFF"
            border.width: sel ? Math.max(2, page.u * 0.3) : 1
            scale: sel ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            Text {
                id: openText
                anchors.centerIn: parent
                text: page.game ? (page.game.openLabel || "") : ""
                color: "#E8F4FF"
                font.pixelSize: page.u * 2.1
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { page.focusIdx = 1; page.activate() }
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; top: bar.bottom; leftMargin: page.u * 6; rightMargin: page.u * 6; topMargin: page.u * 1 }
        height: 1
        color: "#2200E5FF"
    }

    // --------------------------------------------------- info below
    Column {
        anchors { left: parent.left; right: parent.right; top: bar.bottom; leftMargin: page.u * 6; rightMargin: page.u * 6; topMargin: page.u * 4 }
        spacing: page.u * 1
        Text {
            text: page.game && page.game.source === "launcher" ? "ABOUT" : "ABOUT THIS GAME"
            color: "#00E5FF"
            font.pixelSize: page.u * 1.6
            font.bold: true
            font.letterSpacing: page.u * 0.2
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: "#B8D4E8"
            font.pixelSize: page.u * 2
            text: {
                if (!page.game) return ""
                var src = page.game.source
                if (src === "launcher") return page.game.about || ""
                if (src === "steam")   return "Installed through Steam. X Mode starts it with Steam in the background, so achievements, cloud saves and the Steam overlay all work."
                if (src === "heroic")  return "Installed through Heroic (" + page.game.sourceLabel + "). X Mode starts it with Heroic, which handles your account, updates and Proton."
                if (src === "bottles") return "A Windows program in Bottles. X Mode starts it inside its bottle."
                return "An app installed on this system. X Mode starts it directly."
            }
        }
    }

    component Stat: Column {
        property string label: ""
        property string value: ""
        spacing: page.u * 0.4
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Text { text: parent.label; color: "#7A8FA8"; font.pixelSize: page.u * 1.6; font.bold: true; font.letterSpacing: page.u * 0.1 }
        Text { text: parent.value; color: "#E8F4FF"; font.pixelSize: page.u * 2.6; font.bold: true }
    }
}
