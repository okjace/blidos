import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Android and Google Play"
    property string gsfId: ""
    property bool running: Window.window.androidRunning
    subtitle: running ? "Android is running. Android and Android TV apps open full screen, and Back returns to BlidOS."
                      : "Android is starting. The first start after setting up a profile takes a few minutes."

    property string graphics: ""
    property bool tv: false
    function setTv(on) {
        var w = Window.window
        w.busy(on ? "Turning on Android TV mode…" : "Turning off Android TV mode…", "Android restarts. This takes about a minute.")
        Api.call("androidTv", [on], v => { tv = v; w.busy(""); Api.call("restartAndroid"); w.toast("Android is restarting") },
                 e => { w.busy(""); w.toast(e) })
    }
    readonly property var graphicsModes: [
        { id: "auto", name: "Automatic", detail: "Uses the graphics chip. Best when it works." },
        { id: "compatible", name: "Compatible", detail: "Try this if Android apps show a black screen." },
        { id: "software", name: "Software", detail: "Slowest, but works on any computer." }]
    function setGraphics(mode) {
        var w = Window.window
        w.busy("Changing Android graphics…", "Android restarts. This takes about a minute.")
        Api.call("androidGraphics", [mode], m => { graphics = m; w.busy(""); Api.call("restartAndroid"); w.toast("Android is restarting") },
                 e => { w.busy(""); w.toast(e) })
    }

    Component.onCompleted: {
        Api.call("gsfId", [], id => { gsfId = id || "" }, () => {})
        Api.call("androidGraphics", [], m => { graphics = m }, () => {})
        Api.call("androidTv", [], v => { tv = v }, () => {})
    }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(20)
        text: "<b>Signing in to Google Play</b><br>BlidOS isn't a Google-certified device, so Google asks you to register it once per profile:<br>" +
              "1. On a phone or computer, go to <b>google.com/android/uncertified</b> and sign in.<br>" +
              "2. Enter this device ID: <b>" + (page.gsfId || "(appears after Android has started once)") + "</b><br>" +
              "3. Wait a few minutes, then choose Restart Android below and open Google Play."
        textFormat: Text.StyledText
    }
    ListRow {
        visible: Window.window.me && Window.window.me.owner
        title: "Android TV mode" + (page.tv ? "  ✓" : "")
        detail: page.tv ? "On" : "Off"
        onActivated: Window.window.dialog.open(page.tv
            ? { title: "Turn off Android TV mode?", message: "Android goes back to tablet mode: Google Play works, and apps with a TV screen still open in it.",
                buttons: [{ text: "Turn off", primary: true, action: () => page.setTv(false) }, { text: "Cancel" }] }
            : { title: "Turn on Android TV mode?",
                message: "Android runs as an Android TV: TV-only apps install and run, with Android's TV screens. Google Play for phones (the one included) won't open in this mode; install the Google Play Store (Android TV) app file with Settings → Install a package. Android only accepts it if it's really from Google.",
                buttons: [{ text: "Turn on", primary: true, action: () => page.setTv(true) }, { text: "Cancel" }] })
    }
    Text {
        visible: Window.window.me && Window.window.me.owner
        text: "Graphics"
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true
    }
    Repeater {
        model: Window.window.me && Window.window.me.owner ? page.graphicsModes : []
        ListRow {
            title: modelData.name + (page.graphics === modelData.id ? "  ✓" : "")
            detail: modelData.detail
            onActivated: if (page.graphics !== modelData.id) page.setGraphics(modelData.id)
        }
    }
    Row {
        spacing: Theme.px(16)
        PillButton { text: "Save a problem report"; onActivated: {
            Window.window.busy("Collecting Android details…")
            Api.call("androidReport", [], path => { Window.window.busy(""); Window.window.dialog.open({ title: "Report saved",
                message: "Saved to " + path + ". It lists this computer's graphics chip and Android's errors, nothing personal." }) },
                e => { Window.window.busy(""); Window.window.toast(e) })
        } }
        PillButton { text: "Restart Android"; onActivated: { Api.call("restartAndroid"); Window.window.toast("Restarting Android…") } }
        PillButton { visible: Window.window.me && Window.window.me.owner; text: "Android settings"; onActivated: Api.call("openAndroidSettings") }
    }
}
