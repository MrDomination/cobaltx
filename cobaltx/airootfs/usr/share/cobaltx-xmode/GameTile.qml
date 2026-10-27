import QtQuick
import QtQuick.Effects

// One game card in the library grid - rounded corners like a phone app icon.
Item {
    id: tile
    property var game: ({})
    property bool selected: false
    property real u: 8

    readonly property bool hasCover: cover.status === Image.Ready
    readonly property real radius: width * 0.13

    // Soft cyan glow behind the selected tile
    Rectangle {
        anchors.centerIn: card
        width: card.width + u * 1.8
        height: card.height + u * 1.8
        radius: tile.radius + u * 0.9
        color: "transparent"
        border.color: "#00E5FF"
        border.width: u * 0.55
        opacity: tile.selected ? 0.32 : 0
        scale: card.scale
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Item {
        id: card
        anchors.fill: parent
        scale: tile.selected ? 1.07 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // Everything inside "content" gets clipped to the rounded shape
        Item {
            id: content
            visible: tile.game.key !== "__add__"
            anchors.fill: parent
            // Rounded clipping needs GPU rendering; on the (rare) software
            // renderer fall back to square corners instead of blank tiles.
            layer.enabled: tile.GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: roundMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // Fallback look for games without artwork: gradient + icon + title
            Rectangle {
                anchors.fill: parent
                visible: !tile.hasCover
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1A4FB0" }
                    GradientStop { position: 1.0; color: "#0A1428" }
                }
                Image {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: parent.height * 0.18
                    width: parent.width * 0.5
                    height: width
                    source: tile.game.icon || ""
                    sourceSize: Qt.size(256, 256)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    // Big "X" when there's no icon either
                    anchors.centerIn: icon
                    visible: icon.status !== Image.Ready
                    text: "✕"
                    color: "#00E5FF"
                    opacity: 0.25
                    font.pixelSize: tile.width * 0.4
                    font.bold: true
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: tile.u * 1.6 }
                    text: tile.game.title || ""
                    color: "#E8F4FF"
                    font.pixelSize: tile.u * 2.1
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Image {
                id: cover
                anchors.fill: parent
                source: tile.game.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.height: 600
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // Source badge (Steam / Epic / GOG / ...)
            Rectangle {
                anchors { left: parent.left; top: parent.top; leftMargin: tile.radius * 0.55; topMargin: tile.radius * 0.55 }
                radius: height / 2
                color: "#CC050A18"
                height: badge.implicitHeight + tile.u * 0.6
                width: badge.implicitWidth + tile.u * 1.6
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: tile.game.sourceLabel || ""
                    color: "#00E5FF"
                    font.pixelSize: tile.u * 1.4
                    font.bold: true
                }
            }
        }

        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: tile.radius
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        // Rounded outline on top
        Rectangle {
            anchors.fill: parent
            radius: tile.radius
            color: "transparent"
            border.color: tile.selected ? "#00E5FF" : "#2200E5FF"
            border.width: tile.selected ? Math.max(2, tile.u * 0.35) : 1
        }
        // "Add a game" tile in the Library tab
        Rectangle {
            visible: tile.game.key === "__add__"
            anchors.fill: parent
            radius: tile.radius
            color: "#0D1B36"
            border.color: tile.selected ? "#00E5FF" : "#5500E5FF"
            border.width: Math.max(2, u * 0.3)
            Column {
                anchors.centerIn: parent
                spacing: u * 1
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+"; color: "#00E5FF"
                       font.pixelSize: tile.width * 0.45; font.bold: true }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add a game"; color: "#E8F4FF"
                       font.pixelSize: u * 1.9; font.bold: true }
            }
        }
    }
}
