import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    
    Slide {
        Image {
            id: backgroundImage
            source: "logo.png"
            width: 200; height: 200
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        Text {
            anchors.horizontalCenter: backgroundImage.horizontalCenter
            anchors.top: backgroundImage.bottom
            text: "Welcome to CobaltX 0.3 — Fullscreened"
            wrapMode: Text.WordWrap
            width: 600
            horizontalAlignment: Text.Center
        }
    }
    
    function onActivate() { }
    function onLeave() { }
}
