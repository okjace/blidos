import QtQuick
import QtQuick.Window
import BlidOS

// A Kids profile, as its parent sets it up: what it may do, and which apps it gets.
Page {
    id: page
    property var profile
    property var android: []
    property var linux: []
    property var allowed: profile ? profile.allowed.slice() : []
    property var rules: profile && profile.rules ? Object.assign({}, profile.rules) : ({})
    property bool loading: true
    readonly property var ruleList: [
        { key: "googlePlay", title: "Google Play", detail: "Install their own Android apps" },
        { key: "store", title: "App Store", detail: "Install Linux apps and games" },
        { key: "desktop", title: "Desktop mode", detail: "The full KDE Plasma desktop" },
        { key: "settings", title: "Settings", detail: "Wi-Fi, Bluetooth, sound and display" },
        { key: "power", title: "Restart and shut down", detail: "Turn the computer off or restart it" }]
    title: profile ? profile.name : ""
    subtitle: "Choose what " + (profile ? profile.name : "they") + " can do and which apps they get. Changes apply the next time they sign in."

    Component.onCompleted: Api.call("kidsAppChoices", [], c => { android = c.android; linux = c.linux; loading = false },
                                    e => { loading = false; Window.window.toast(e) })

    function save(fields, done) { Api.call("updateProfile", [profile.user, fields], r => { if (done) done(r) }) }
    function toggleRule(key) {
        var copy = Object.assign({}, rules)
        copy[key] = !copy[key]
        rules = copy
        save({ rules: copy })
    }
    function toggleApp(id, label) {
        var list = allowed.slice()
        var i = list.indexOf(id)
        if (i >= 0) list.splice(i, 1); else list.push(id)
        allowed = list
        save({ allowed: list }, r => {
            if (r.installing && r.installing.length)
                Window.window.toast("Installing " + label + " for " + profile.name + "…")
        })
    }

    Text { text: "What " + (page.profile ? page.profile.name : "they") + " can do"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true }
    Repeater {
        model: page.ruleList
        ListRow {
            title: modelData.title
            detail: modelData.detail + " · " + (page.rules[modelData.key] ? "Allowed" : "Not allowed")
            onActivated: page.toggleRule(modelData.key)
        }
    }

    Text { text: "Android apps"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true }
    Text {
        visible: !page.loading && !page.android.length
        width: parent.width; wrapMode: Text.WordWrap
        text: page.rules.googlePlay ? "With Google Play allowed, they can install their own Android apps."
                                    : "Install Android apps from Google Play in your profile first. They show up here."
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(17)
    }
    Repeater {
        model: page.android
        ListRow {
            title: modelData.label
            detail: page.rules.googlePlay ? "Allowed (Google Play is on)" : page.allowed.indexOf(modelData.id) >= 0 ? "Allowed" : "Not allowed"
            onActivated: page.toggleApp(modelData.id, modelData.label)
        }
    }

    Text { text: "Linux apps"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true }
    Text {
        visible: !page.loading && !page.linux.length
        width: parent.width; wrapMode: Text.WordWrap
        text: "Install Linux apps and games from the App Store in your profile first. They show up here."
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(17)
    }
    Repeater {
        model: page.linux
        ListRow {
            title: modelData.label
            detail: page.allowed.indexOf(modelData.id) >= 0 ? "Allowed" : "Not allowed"
            onActivated: page.toggleApp(modelData.id, modelData.label)
        }
    }
}
