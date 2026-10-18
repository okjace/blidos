import QtQuick

// Desktop mode's loading screen (KDE Plasma's splash), in BlidOS's look: it continues the BlidOS
// loading screen instead of a black screen.
Rectangle {
    id: root
    property int stage
    gradient: Gradient {
        GradientStop { position: 0; color: "#16203A" }
        GradientStop { position: 1; color: "#05070D" }
    }
    Column {
        anchors.centerIn: parent
        spacing: 20
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/logo.svg"
            width: 120; height: 120; sourceSize.width: 120
            RotationAnimation on rotation { from: 0; to: 360; duration: 2400; loops: Animation.Infinite }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Starting Desktop mode…"; color: "white"
               font.pixelSize: 36; font.bold: true; font.family: "Noto Sans" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "This takes a few seconds"; color: "#B3FFFFFF"
               font.pixelSize: 22; font.family: "Noto Sans" }
    }
}
