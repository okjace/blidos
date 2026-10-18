import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import BlidOS

// The BlidOS home screen and settings, full screen in each profile's session.
Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "BlidOS"
    color: Theme.bgBottom

    property var me: null               // this profile: { user, name, color, owner, kids, allowed }
    property bool androidRunning: false
    property alias dialog: dialog
    property alias pin: pinPad
    function toast(message) { toastBox.show(message) }
    // A full-screen "please wait" card, e.g. while Android finishes starting. busy("") hides it.
    function busy(title, detail) { busyCard.title = title; busyCard.detail = detail || "" }
    // Leaving for the profile picker: a loading card first, which the screen keeps until
    // "Who's watching?" appears (never a black screen in between).
    function switchProfile() {
        busy("Switching profile…")
        switchTimer.start()
    }
    Timer { id: switchTimer; interval: 350; onTriggered: Api.call("switchProfile") }
    function stackPop() { if (stack.depth > 1) stack.pop() }
    function launchItem(item) { var home = stack.get(0); if (home && home.launch) home.launch(item, true) }
    function push(page, props) {
        var component = Qt.createComponent(Qt.resolvedUrl(page))
        if (component.status === Component.Error) { console.error(component.errorString()); return }
        stack.push(component, props || {})
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bgTop }
            GradientStop { position: 1; color: Theme.bgBottom }
        }
    }

    StackView {
        id: stack
        anchors.fill: parent
        focus: true
        // Pages slide in from the right as you go deeper, and back out to the right.
        pushEnter: Transition { ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "x"; from: Theme.px(90); to: 0; duration: 260; easing.type: Easing.OutCubic } } }
        pushExit: Transition { ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 180 }
            NumberAnimation { property: "x"; from: 0; to: -Theme.px(60); duration: 220; easing.type: Easing.OutCubic } } }
        popEnter: Transition { ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { property: "x"; from: -Theme.px(60); to: 0; duration: 260; easing.type: Easing.OutCubic } } }
        popExit: Transition { ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 180 }
            NumberAnimation { property: "x"; from: 0; to: Theme.px(90); duration: 220; easing.type: Easing.OutCubic } } }
        Keys.onPressed: (event) => {
            if ((event.key === Qt.Key_Escape || event.key === Qt.Key_Back) && stack.depth > 1) {
                stack.pop()
                event.accepted = true
            }
        }
    }

    Dialog { id: dialog }
    PinPad { id: pinPad }
    Toast { id: toastBox }
    Rectangle {
        id: busyCard
        property string title
        property string detail
        anchors.fill: parent
        opacity: title !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        color: "#E605070D"
        z: 450
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.px(160), Theme.px(800))
            spacing: Theme.px(18)
            Image { anchors.horizontalCenter: parent.horizontalCenter; source: Theme.icon("logo"); width: Theme.px(96); height: width; sourceSize.width: width
                    RotationAnimation on rotation { running: busyCard.visible; from: 0; to: 360; duration: 2400; loops: Animation.Infinite } }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: busyCard.title
                   color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(32); font.bold: true }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: busyCard.detail
                   visible: text !== ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(19) }
        }
    }
    Connections { target: Api; function onToast(message) { toastBox.show(message) } }

    function loadProfile() {
        Api.call("whoami", [], r => {
            win.me = r.profile
            // Owner: say so when a new BlidOS is out (Settings → Updates installs it).
            if (r.profile && r.profile.owner)
                Api.call("checkUpdates", [], s => { if (s.blidos) toast("BlidOS " + s.blidos.version + " is available: Settings → Updates") }, () => {})
        })
    }
    Component.onCompleted: { push("Home.qml"); loadProfile() }

    // Android starts in the background after login; check until it's up.
    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: Api.call("androidRunning", [], running => {
            if (running && !win.androidRunning) {
                Api.call("androidStarted", [], null, () => {})  // controllers plugged in earlier reach Android
                if (win.me && win.me.kids) Api.call("applyKids", [], null, () => {})
            }
            win.androidRunning = running
        }, () => {})
    }
}
