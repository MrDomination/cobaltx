import QtQuick

// Battery + clock, shown in the headers of the menu and Quick Settings.
// Reads backend.battery (-1 = no battery) and backend.charging.
Row {
    id: status
    property real u: 8
    spacing: u * 2
    readonly property int level: backend.battery === undefined ? -1 : backend.battery
    readonly property bool charging: backend.charging === true

    Row {
        visible: status.level >= 0
        spacing: u * 0.7
        anchors.verticalCenter: parent.verticalCenter
        Item {
            width: u * 3.8; height: u * 1.9
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                id: body
                width: parent.width - u * 0.35; height: parent.height
                radius: u * 0.35
                color: "transparent"
                border.color: "#9FB3C8"; border.width: Math.max(1, u * 0.18)
                Rectangle {
                    x: u * 0.3; y: u * 0.3
                    height: parent.height - u * 0.6
                    width: Math.max(u * 0.2, (parent.width - u * 0.6) * status.level / 100)
                    radius: u * 0.15
                    color: status.charging ? "#00E5FF" : (status.level <= 20 ? "#F85149" : "#E8F4FF")
                }
            }
            Rectangle {
                anchors { left: body.right; verticalCenter: body.verticalCenter }
                width: u * 0.35; height: u * 0.8; radius: u * 0.1
                color: "#9FB3C8"
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: status.level + "%" + (status.charging ? " ⚡" : "")
            color: status.level <= 20 && !status.charging ? "#F85149" : "#E8F4FF"
            font.pixelSize: u * 1.8; font.bold: true
        }
    }

    Text {
        id: clock
        anchors.verticalCenter: parent.verticalCenter
        color: "#E8F4FF"
        font.pixelSize: u * 1.8; font.bold: true
        function tick() { text = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat)) }
        Component.onCompleted: tick()
        Timer { interval: 5000; running: status.visible; repeat: true; triggeredOnStart: true; onTriggered: clock.tick() }
    }
}
