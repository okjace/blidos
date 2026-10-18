import QtQuick
import QtQuick.Window
import BlidOS

// The App Store: Linux apps and games from Flathub, installed for this profile only.
Page {
    id: page
    title: "App Store"
    property var categories: []
    property string category: ""
    property string query: ""
    property var apps: []
    property var installed: []
    property var jobs: ({})        // app id -> { running, ok, message }
    property bool loading: true
    property string problem: ""

    subtitle: problem ? problem
            : loading ? "Loading…"
            : query && !apps.length ? "Nothing found for \"" + query + "\"."
            : "Apps and games from Flathub, just for this profile. Android apps are in Google Play."

    function load() {
        loading = true; problem = ""
        var ok = list => { apps = list; loading = false }
        var err = e => { apps = []; loading = false; problem = e }
        if (query) Api.call("storeSearch", [query], ok, err)
        else Api.call("storeBrowse", [category], ok, err)
    }
    function refreshInstalled() { Api.call("storeInstalled", [], list => { installed = list }, () => {}) }
    function isInstalled(id) { return installed.indexOf(id) >= 0 }
    function state(id) {
        var j = jobs[id]
        if (j && j.running) return j.message
        return isInstalled(id) ? "Installed" : ""
    }
    function setJob(id, j) { var copy = Object.assign({}, jobs); copy[id] = j; jobs = copy }

    function choose(app) {
        var w = Window.window
        var about = app.summary + (app.developer ? "\nBy " + app.developer + (app.verified ? " (verified)" : "") : "")
        if (jobs[app.id] && jobs[app.id].running) { w.toast(jobs[app.id].message); return }
        if (isInstalled(app.id)) {
            w.dialog.open({ title: app.name, message: about, buttons: [
                { text: "Open", primary: true, action: () => Api.call("storeOpen", [app.id]) },
                { text: "Remove", action: () => w.dialog.open({ title: "Remove " + app.name + "?", message: "Its settings and files in this profile are removed too.", buttons: [
                    { text: "Remove", primary: true, action: () => Api.call("storeRemove", [app.id], () => { w.toast(app.name + " removed"); refreshInstalled() }) },
                    { text: "Cancel" }] }) },
                { text: "Cancel" }] })
        } else {
            w.dialog.open({ title: app.name, message: about, buttons: [
                { text: "Install", primary: true, action: () => install(app) },
                { text: "Cancel" }] })
        }
    }
    function install(app) {
        Api.call("storeInstall", [app.id], () => {
            setJob(app.id, { running: true, ok: null, message: "Installing…" })
            Window.window.toast("Installing " + app.name + "…")
        })
    }
    function pollJobs() {
        for (var id in jobs) {
            if (!jobs[id].running) continue
            (function (appId) {
                Api.call("storeJob", [appId], j => {
                    setJob(appId, j)
                    if (!j.running) {
                        var app = apps.find(a => a.id === appId)
                        var name = app ? app.name : appId
                        Window.window.toast(j.ok ? name + " is installed. It's on the home screen." : "Couldn't install " + name + ": " + j.message)
                        refreshInstalled()
                    }
                }, () => {})
            })(id)
        }
    }
    Timer {
        interval: 1000; repeat: true
        running: Object.keys(page.jobs).some(id => page.jobs[id].running)
        onTriggered: page.pollJobs()
    }
    Component.onCompleted: {
        Api.call("storeCategories", [], c => { categories = c })
        refreshInstalled()
        load()
    }

    Field {
        id: search
        width: Math.min(parent.width, Theme.px(640))
        placeholderText: "Search apps and games"
        onAccepted: { page.query = text.trim(); page.load() }
        KeyNavigation.down: categoryRow.children.length ? categoryRow.children[0] : null
    }
    Flow {
        id: categoryRow
        width: parent.width
        spacing: Theme.px(12)
        Repeater {
            model: page.categories
            PillButton {
                text: modelData.name
                primary: !page.query && page.category === modelData.id
                onActivated: { page.query = ""; search.text = ""; page.category = modelData.id; page.load() }
            }
        }
    }
    Flow {
        width: parent.width
        spacing: Theme.px(16)
        Repeater {
            model: page.apps
            FocusScope {
                id: card
                width: Theme.px(400); height: Theme.px(108)
                Entrance { delay: 25 * Math.min(index, 16) }
                activeFocusOnTab: true
                scale: activeFocus ? 1.04 : 1
                z: activeFocus ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 120 } }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.px(14)
                    color: Theme.surface
                    border.width: card.activeFocus ? Theme.px(3) : 0
                    border.color: "white"
                    Image {
                        id: icon
                        x: Theme.px(16); anchors.verticalCenter: parent.verticalCenter
                        width: Theme.px(72); height: width
                        source: modelData.icon
                        sourceSize: Qt.size(width, height)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    Column {
                        anchors.left: icon.right; anchors.leftMargin: Theme.px(16)
                        anchors.right: parent.right; anchors.rightMargin: Theme.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.px(4)
                        Text { width: parent.width; text: modelData.name; elide: Text.ElideRight
                               color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(19); font.bold: true }
                        Text { width: parent.width; text: page.state(modelData.id) || modelData.summary; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                               color: page.state(modelData.id) ? Theme.accent : Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(15) }
                    }
                }
                Keys.onReturnPressed: page.choose(modelData)
                Keys.onEnterPressed: page.choose(modelData)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: card.forceActiveFocus()
                    onClicked: { card.forceActiveFocus(); page.choose(modelData) }
                }
            }
        }
    }
    PillButton { visible: !!page.problem; text: "Try again"; onActivated: page.load() }
}
