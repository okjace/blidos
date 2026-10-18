import QtQuick
import QtQuick.Window
import BlidOS

FocusScope {
    id: home
    property var me: Window.window ? Window.window.me : null
    property bool android: Window.window ? Window.window.androidRunning : false
    property bool kids: !!(me && me.kids)
    // Kids profiles: what a parent allowed (Settings → Profiles → the kid → What they can do).
    // Reads the profile directly: this runs when the profile arrives, before "kids" updates.
    function may(rule) { return !(me && me.kids) || !!(me.rules && me.rules[rule]) }
    function kidAllowed(a) {
        var allowed = me && me.allowed ? me.allowed : []
        if (a.kind === "android") return true  // already filtered for them
        return allowed.indexOf("linux:" + a.id) >= 0 || allowed.indexOf("flatpak:" + a.id) >= 0
            || (a.source === "flatpak-user" && may("store"))  // their own App Store apps
    }
    property string connection: ""
    // A new install downloads Android first (a few minutes, once).
    property string setupLabel: "Android is starting"
    property string setupDetail: "Apps appear in a moment"
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true; running: !home.android
        onTriggered: Api.call("androidSetup", [], s => {
            if (!s) return
            var label = s.done ? "Android is starting" : "Getting Android"
            var detail = s.done ? "Apps appear in a moment" : (s.progress ? s.progress + " · first start only" : "Needs the internet, first start only")
            if (label !== home.setupLabel || detail !== home.setupDetail) { home.setupLabel = label; home.setupDetail = detail; home.refresh() }
        }, () => {})
    }

    ListModel { id: appsModel }
    ListModel { id: settingsModel }

    function refresh() {
        Api.call("apps", [], apps => {
            var focusedId = appsList.currentItem ? appsList.currentItem.appId : ""
            appsModel.clear()
            if (may("googlePlay")) {
                appsModel.append(android
                    ? { kind: "play", appId: "com.android.vending", label: "Google Play", subtitle: "Get Android and Android TV apps", icon: "", tile: Theme.play }
                    : { kind: "wait", appId: "", label: home.setupLabel, subtitle: home.setupDetail, icon: "", tile: Theme.surface })
            }
            if (may("store"))
                appsModel.append({ kind: "store", appId: "blidos.store", label: "App Store", subtitle: "Linux apps and games", icon: "", tile: Theme.accent })
            for (var i = 0; i < apps.length; i++) {
                var a = apps[i]
                if (kids && !kidAllowed(a)) continue  // Kids profiles only get the apps chosen for them
                appsModel.append({ kind: a.kind, appId: a.id, label: a.label, subtitle: a.kind === "linux" ? "Linux app" : (a.tv ? "Android TV app" : "Android app"),
                                   icon: a.icon, tile: Theme.surface, exec: a.exec || "" })
            }
            for (var j = 0; j < appsModel.count; j++)
                if (appsModel.get(j).appId === focusedId) appsList.currentIndex = j
        }, () => {})
        Api.call("connection", [], c => { home.connection = c }, () => {})
    }

    function buildSettings() {
        settingsModel.clear()
        if (may("settings")) {
            settingsModel.append({ key: "wifi", label: "Wi-Fi", icon: "wifi" })
            settingsModel.append({ key: "bluetooth", label: "Bluetooth", icon: "bluetooth" })
            settingsModel.append({ key: "settings", label: "Settings", icon: "tune" })
        }
        if (may("desktop"))
            settingsModel.append({ key: "desktop", label: "Desktop mode", icon: "desktop" })
        settingsModel.append({ key: "switch", label: "Switch profile", icon: "person" })
        settingsModel.append({ key: "power", label: "Power", icon: "power" })
    }

    function openSetting(key) {
        var w = Window.window
        if (key === "wifi") w.push("WifiPage.qml")
        else if (key === "bluetooth") w.push("BluetoothPage.qml")
        else if (key === "settings") w.push("SettingsPage.qml")
        else if (key === "switch") Api.call("switchProfile")
        else if (key === "desktop") w.dialog.open({ title: "Switch to Desktop mode?",
            message: "A full KDE Plasma desktop for mouse and keyboard, with your files and apps. Android stops until you come back. To return, open \"BlidOS TV mode\" on the desktop.",
            buttons: [{ text: "Switch", primary: true, action: () => { w.busy("Starting Desktop mode…"); Api.call("switchMode", ["desktop"]) } }, { text: "Cancel" }] })
        else if (key === "power") w.dialog.open({ title: "Power", buttons: may("power") ? [
            { text: "Switch profile", action: () => Api.call("switchProfile") },
            { text: "Restart", action: () => Api.call("restart") },
            { text: "Shut down", action: () => Api.call("shutDown") },
            { text: "Cancel" }] : [{ text: "Switch profile", action: () => Api.call("switchProfile") }, { text: "Cancel" }] })
    }

    function launch(item) {
        if (item.kind === "wait") return
        if (item.kind === "store") { Window.window.push("StorePage.qml"); return }
        var w = Window.window
        var androidApp = item.kind === "play" || item.kind === "android"
        if (androidApp)
            w.busy("Opening " + item.label + "…", android ? "" : "Android is still starting. The first start after setting up a profile can take a few minutes.")
        var done = () => w.busy("")
        Api.call("launch", item.kind === "play" ? ["android", "com.android.vending"] : [item.kind, item.appId, item.exec],
                 done, e => { done(); w.toast(e) })
    }

    onMeChanged: { buildSettings(); refresh() }
    onAndroidChanged: refresh()
    Component.onCompleted: { buildSettings(); refresh(); appsList.forceActiveFocus() }
    Connections {
        target: Window.window
        function onActiveChanged() { if (Window.window.active) home.refresh() }
    }
    Timer { interval: 20000; running: true; repeat: true; onTriggered: home.refresh() }

    // ---- Top bar ----
    Item {
        id: topBar
        x: Theme.px(56); y: Theme.px(40)
        width: parent.width - Theme.px(120); height: Theme.px(64)

        FocusScope {
            id: chip
            width: chipRow.width + Theme.px(32); height: parent.height
            activeFocusOnTab: true
            Rectangle {
                anchors.fill: parent; radius: height / 2
                color: "transparent"
                border.width: chip.activeFocus ? Theme.px(3) : 0; border.color: "white"
            }
            Row {
                id: chipRow
                x: Theme.px(8); anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(14)
                Avatar { width: Theme.px(48); name: home.me ? home.me.name : ""; colorIndex: home.me ? home.me.color : 0 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: home.me ? home.me.name : ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(24); font.bold: true
                }
            }
            Keys.onReturnPressed: Api.call("switchProfile")
            Keys.onDownPressed: appsList.forceActiveFocus()
            MouseArea { anchors.fill: parent; onClicked: Api.call("switchProfile") }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(28)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: home.connection
                color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(16)
            }
            Text {
                id: clock
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(30); font.bold: true
                function tick() { text = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") >= 0 ? "h:mm" : "HH:mm") }
                Component.onCompleted: tick()
                Timer { interval: 10000; running: true; repeat: true; onTriggered: clock.tick() }
            }
        }
    }

    // ---- Rows ----
    Column {
        anchors.top: topBar.bottom; anchors.topMargin: Theme.px(28)
        width: parent.width
        spacing: Theme.px(8)

        Text {
            x: Theme.px(64)
            text: "Apps"
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true
        }
        ListView {
            id: appsList
            width: parent.width; height: Theme.px(150)
            orientation: ListView.Horizontal
            leftMargin: Theme.px(60); rightMargin: Theme.px(60)
            spacing: Theme.px(20)
            model: appsModel
            clip: false
            keyNavigationEnabled: true
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: Theme.px(60); preferredHighlightEnd: width - Theme.px(280)
            delegate: Tile {
                required property var model
                required property int index
                property string appId: model.appId
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                title: model.label
                subtitle: model.subtitle
                fill: model.tile
                imageSource: model.icon
                iconSource: model.kind === "play" ? Theme.icon("play") : model.kind === "store" ? Theme.icon("store") : (model.icon ? "" : Theme.icon("apps"))
                dimmed: model.kind === "wait"
                focus: ListView.isCurrentItem
                onActiveFocusChanged: if (activeFocus) appsList.currentIndex = index
                onActivated: home.launch(model)
            }
            Keys.onDownPressed: settingsList.forceActiveFocus()
            Keys.onUpPressed: chip.forceActiveFocus()
        }
        Text {
            visible: home.kids && appsModel.count === 0
            x: Theme.px(64)
            text: "No apps yet. Ask a grown-up to choose apps for this profile."
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(18)
        }

        Item { width: 1; height: Theme.px(24) }
        Text {
            x: Theme.px(64)
            text: "Settings"
            color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true
        }
        ListView {
            id: settingsList
            width: parent.width; height: Theme.px(150)
            orientation: ListView.Horizontal
            leftMargin: Theme.px(60); rightMargin: Theme.px(60)
            spacing: Theme.px(20)
            model: settingsModel
            keyNavigationEnabled: true
            delegate: Tile {
                required property var model
                required property int index
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                title: model.label
                subtitle: model.key === "wifi" ? home.connection : (model.key === "switch" && home.me ? "Signed in as " + home.me.name : "")
                iconSource: Theme.icon(model.icon)
                focus: ListView.isCurrentItem
                onActiveFocusChanged: if (activeFocus) settingsList.currentIndex = index
                onActivated: home.openSetting(model.key)
            }
            Keys.onUpPressed: appsList.forceActiveFocus()
        }
    }
}
