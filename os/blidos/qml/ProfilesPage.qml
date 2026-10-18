import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Profiles"
    subtitle: "Each profile has its own apps, Android data and Google account. Kids profiles only get the apps and permissions you choose."
    property var profiles: []

    function refresh() { Api.call("profiles", [], p => { profiles = p }) }
    Component.onCompleted: refresh()

    function setPin(p) {
        var pad = Window.window.pin
        var first = ""
        pad.open("New PIN", "Pick 4 digits for " + p.name, pin => {
            if (!first) { first = pin; pad.open("Confirm PIN", "Enter the same 4 digits again"); return }
            if (pin !== first) { pad.close(); Window.window.toast("Those didn't match. Try again."); return }
            Api.call("setPin", [p.user, pin], () => { pad.close(); Window.window.toast("PIN saved for " + p.name); refresh() },
                     e => { pad.fail(e) })
        })
    }

    function options(p) {
        var d = Window.window.dialog
        var buttons = [
            { text: "Rename", action: () => d.open({ title: "Rename " + p.name, input: true, text: p.name, buttons: [
                { text: "Save", primary: true, action: n => Api.call("updateProfile", [p.user, { name: n }], refresh) }, { text: "Cancel" }] }) },
            { text: p.hasPin ? "Change PIN" : "Set PIN", action: () => setPin(p) },
        ]
        if (p.hasPin) buttons.push({ text: "Remove PIN", action: () => Api.call("setPin", [p.user, ""], refresh) })
        if (!p.owner) {
            buttons.push({ text: p.kids ? "Turn off Kids mode" : "Turn on Kids mode", action: () => Api.call("updateProfile", [p.user, { kids: !p.kids }], refresh) })
            if (p.kids) buttons.push({ text: "Apps and permissions", action: () => Window.window.push("KidsAppsPage.qml", { profile: p }) })
            buttons.push({ text: "Delete", action: () => d.open({ title: "Delete " + p.name + "?",
                message: "This deletes " + p.name + "'s apps, files and Google account from this computer.",
                buttons: [{ text: "Delete", primary: true, action: () => Api.call("deleteProfile", [p.user], () => { Window.window.toast("Deleted " + p.name); refresh() }) }, { text: "Cancel" }] }) })
        }
        buttons.push({ text: "Close" })
        d.open({ title: p.name, buttons: buttons })
    }

    function add(kids) {
        Window.window.dialog.open({ title: kids ? "Kid's name" : "Their name", input: true, buttons: [
            { text: "Add", primary: true, action: n => { if (n.trim()) Api.call("createProfile", [n.trim(), "", kids], () => { Window.window.toast("Added " + n); refresh() }) } },
            { text: "Cancel" }] })
    }

    Repeater {
        model: page.profiles
        ListRow {
            title: modelData.name
            detail: [modelData.owner ? "Owner" : "", modelData.kids ? "Kids" : "", modelData.hasPin ? "PIN" : "No PIN"].filter(x => x).join(" · ")
            iconSource: Theme.icon("person")
            onActivated: page.options(modelData)
        }
    }
    Row {
        spacing: Theme.px(16)
        topPadding: Theme.px(8)
        PillButton { text: "Add a person"; onActivated: page.add(false) }
        PillButton { text: "Add a kid"; onActivated: page.add(true) }
    }
}
