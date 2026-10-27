import QtQuick
import QtQuick.Window
import "../cobaltx-xmode"

// Open apps on the Plasma desktop (Armoury Crate button) - the same view as in X Mode.
Window {
    id: win
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint
           | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    readonly property real u: Math.min(Screen.width / 160, Screen.height / 90)
    x: 0; y: 0
    width: Screen.width
    height: Screen.height
    visible: kb.appsVisible || view.opacity > 0

    readonly property var glyphMap: ({
        "xbox":        { accept: ["A", "#3FB950"], back: ["B", "#F85149"], secondary: ["X", "#58A6FF"] },
        "steam":       { accept: ["A", "#3FB950"], back: ["B", "#F85149"], secondary: ["X", "#58A6FF"] },
        "playstation": { accept: ["✕", "#7FA7FF"], back: ["○", "#FF6B6B"], secondary: ["□", "#F778BA"] },
        "nintendo":    { accept: ["A", ""], back: ["B", ""], secondary: ["Y", ""] },
        "generic":     { accept: ["A", ""], back: ["B", ""], secondary: ["X", ""] }
    })
    function glyph(a) {
        var m = glyphMap[kb.family] || glyphMap["xbox"]
        return m[a] || ["?", ""]
    }

    TaskView {
        id: view
        anchors.fill: parent
        u: win.u
        glyph: win.glyph
        onOpenChanged: if (open !== kb.appsVisible) kb.setAppsVisible(open)
        onSound: function(name) { kb.playSound(name) }
    }

    Connections {
        target: kb
        function onAppsInput(a) { view.handle(a) }
        function onAppsVisibleChanged() { if (view.open !== kb.appsVisible) view.open = kb.appsVisible }
    }
}
