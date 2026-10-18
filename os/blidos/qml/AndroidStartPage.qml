import QtQuick
import QtQuick.Window
import BlidOS

// Android on its way: downloading (first start), setting up, booting. Shows what's happening
// (with Android's own messages) instead of a tile that just says "starting". Optionally opens an
// app as soon as Android is ready.
Page {
    id: page
    property var openWhenReady: null   // a home screen item to open once Android is up
    property var s: ({ stage: "", title: "Android", detail: "", lines: [], progress: null })
    title: s.title
    subtitle: s.detail + (s.elapsed ? "  (" + Math.floor(s.elapsed / 60) + ":" + ("0" + s.elapsed % 60).slice(-2) + ")" : "")

    function poll() {
        Api.call("androidStatus", [], st => {
            s = st
            if (st.stage === "running") {
                if (openWhenReady) { var item = openWhenReady; openWhenReady = null; Window.window.stackPop(); Window.window.launchItem(item) }
            }
        }, () => {})
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.poll() }

    // Progress: a bar while downloading, a moving strip while it can't tell how far along it is.
    Rectangle {
        width: parent.width; height: Theme.px(10); radius: height / 2
        color: Theme.surface
        clip: true
        Rectangle {
            visible: page.s.progress !== null && page.s.progress !== undefined
            height: parent.height; radius: parent.radius; color: Theme.accent
            width: parent.width * (page.s.progress || 0) / 100
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            id: strip
            visible: page.s.progress === null || page.s.progress === undefined
            height: parent.height; radius: parent.radius; color: Theme.accent
            width: parent.width * 0.25
            NumberAnimation on x { from: -strip.width; to: strip.parent.width; duration: 1400; loops: Animation.Infinite; running: strip.visible }
        }
    }
    Text {
        visible: page.s.progress !== null && page.s.progress !== undefined && page.s.stage !== "running"
        text: (page.s.progress || 0) + "%"
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true
    }
    Rectangle {
        visible: page.s.lines && page.s.lines.length > 0
        width: parent.width; height: logText.implicitHeight + Theme.px(32)
        radius: Theme.px(12); color: "#0A0E18"
        Text {
            id: logText
            x: Theme.px(16); y: Theme.px(16); width: parent.width - Theme.px(32)
            text: (page.s.lines || []).join("\n")
            color: Theme.dim; font.family: "monospace"; font.pixelSize: Theme.px(13)
            wrapMode: Text.WrapAnywhere; maximumLineCount: 14
        }
    }
    Text {
        visible: page.s.stage === "starting" && !!page.s.graphicsName
        text: "Graphics: " + page.s.graphicsName
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(15)
    }
    Row {
        spacing: Theme.px(16)
        PillButton { text: "Restart Android"; onActivated: { Api.call("restartAndroid"); Window.window.toast("Restarting Android…") } }
        // Stuck on the boot animation is usually graphics: try the next setting now instead of waiting.
        PillButton {
            visible: page.s.stage === "starting" && !!page.s.nextGraphics && Window.window.me && Window.window.me.owner
            text: "Try " + page.s.nextGraphicsName + " graphics"
            onActivated: {
                var w = Window.window
                w.busy("Switching to " + page.s.nextGraphicsName + " graphics…", "Android starts again. This takes about a minute.")
                Api.call("androidGraphics", [page.s.nextGraphics], () => { w.busy(""); w.toast("Android is starting again") },
                         e => { w.busy(""); w.toast(e) })
            }
        }
        PillButton { visible: Window.window.me && !Window.window.me.kids; text: "Android settings"; onActivated: Window.window.push("AndroidPage.qml") }
    }
}
