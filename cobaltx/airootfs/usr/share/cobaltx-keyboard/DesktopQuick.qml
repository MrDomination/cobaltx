import QtQuick
import QtQuick.Window
import "../cobaltx-xmode"

// Quick Settings on the Plasma desktop (X Mode shows its own copy).
// Floats on the right edge without taking focus, like the keyboard.
Window {
    id: win
    flags: Qt.X11BypassWindowManagerHint | Qt.FramelessWindowHint
           | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    readonly property real u: Math.min(Screen.width / 160, Screen.height / 90)
    width: Math.round(u * 52)
    height: Screen.height
    x: Screen.width - width
    y: 0
    visible: kb.quickVisible || panel.x < width

    readonly property var glyphMap: ({
        "xbox":        { accept: ["A", ""], taskview: ["XBOX", ""], secondary: ["X", ""] },
        "steam":       { accept: ["A", ""], taskview: ["STEAM", ""], secondary: ["X", ""] },
        "playstation": { accept: ["✕", ""], taskview: ["PS", ""], secondary: ["□", ""] },
        "nintendo":    { accept: ["A", ""], taskview: ["HOME", ""], secondary: ["Y", ""] },
        "generic":     { accept: ["A", ""], taskview: ["HOME", ""], secondary: ["X", ""] }
    })
    function glyph(a) {
        var m = glyphMap[kb.family] || glyphMap["xbox"]
        return m[a] || ["?", ""]
    }

    Item {
        anchors.fill: parent
        QuickSettings {
            id: panel
            u: win.u
            glyph: win.glyph
            onOpenChanged: if (open !== kb.quickVisible) kb.setQuickVisible(open)
            onSound: function(name) { kb.playSound(name) }
        }
    }

    Connections {
        target: kb
        function onQuickInput(a) { panel.handle(a) }
        function onQuickVisibleChanged() { if (panel.open !== kb.quickVisible) panel.open = kb.quickVisible }
    }
}
