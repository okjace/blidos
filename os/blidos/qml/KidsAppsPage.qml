import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    property var profile
    property var apps: []
    property var allowed: profile ? profile.allowed.slice() : []
    title: "Apps for " + (profile ? profile.name : "")
    subtitle: apps.length ? "Choose the apps they can open. They're copied from your Android apps the next time they sign in."
                          : "Install apps from Google Play in your profile first. They'll show up here."

    Component.onCompleted: Api.call("androidInstalled", [], a => { apps = a })
    function toggle(pkg) {
        var list = allowed.slice()
        var i = list.indexOf(pkg)
        if (i >= 0) list.splice(i, 1); else list.push(pkg)
        allowed = list
        Api.call("updateProfile", [profile.user, { allowed: list }])
    }

    Repeater {
        model: page.apps
        ListRow {
            title: modelData.label
            detail: page.allowed.indexOf(modelData.package) >= 0 ? "Allowed" : "Not allowed"
            onActivated: page.toggle(modelData.package)
        }
    }
}
