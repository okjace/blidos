import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    property var me: Window.window.me
    property bool owner: !!(me && me.owner)
    property bool kids: !!(me && me.kids)
    function may(rule) { return !(me && me.kids) || !!(me.rules && me.rules[rule]) }
    title: "Settings"
    subtitle: me ? "Signed in as " + me.name : ""

    ListRow { title: "Wi-Fi"; iconSource: Theme.icon("wifi"); onActivated: Window.window.push("WifiPage.qml") }
    ListRow { title: "Bluetooth"; iconSource: Theme.icon("bluetooth"); onActivated: Window.window.push("BluetoothPage.qml") }
    ListRow { title: "Controllers"; detail: "Xbox, PlayStation, Switch and more"; iconSource: Theme.icon("gamepad"); onActivated: Window.window.push("ControllersPage.qml") }
    ListRow { title: "Sound"; iconSource: Theme.icon("sound"); onActivated: Window.window.push("SoundPage.qml") }
    ListRow { title: "Display"; iconSource: Theme.icon("display"); onActivated: Window.window.push("DisplayPage.qml") }
    ListRow { title: "Date and time"; iconSource: Theme.icon("tune"); onActivated: Window.window.push("TimePage.qml") }
    ListRow { visible: !page.kids; title: "Android and Google Play"; iconSource: Theme.icon("play"); onActivated: Window.window.push("AndroidPage.qml") }
    ListRow { visible: page.may("store"); title: "App Store"; detail: "Linux apps and games"; iconSource: Theme.icon("store"); onActivated: Window.window.push("StorePage.qml") }
    ListRow { visible: page.may("desktop"); title: "Desktop mode"; detail: "KDE Plasma"; iconSource: Theme.icon("desktop"); onActivated: Window.window.dialog.open({ title: "Switch to Desktop mode?",
        message: "A full KDE Plasma desktop for mouse and keyboard. Android stops until you come back. To return, open \"BlidOS TV mode\" on the desktop.",
        buttons: [{ text: "Switch", primary: true, action: () => { Window.window.busy("Starting Desktop mode…"); Api.call("switchMode", ["desktop"]) } }, { text: "Cancel" }] }) }
    ListRow { visible: page.owner; title: "Profiles"; detail: "PINs and Kids mode"; iconSource: Theme.icon("person"); onActivated: Window.window.push("ProfilesPage.qml") }
    ListRow { visible: page.owner; title: "Drivers"; detail: "Graphics, Wi-Fi and firmware"; iconSource: Theme.icon("apps"); onActivated: Window.window.push("DriversPage.qml") }
    ListRow { visible: page.owner; title: "Updates"; detail: "BlidOS and system updates"; iconSource: Theme.icon("update"); onActivated: Window.window.push("UpdatesPage.qml") }
    ListRow { visible: page.owner; title: "Install a package"; detail: "Drivers and apps from .deb and .apk files"; iconSource: Theme.icon("apps"); onActivated: Window.window.push("PackagesPage.qml") }
    ListRow { id: terminalRow; visible: false; title: "Terminal"; detail: "For advanced users"; iconSource: Theme.icon("apps"); onActivated: Api.call("openTerminal") }
    ListRow { title: "About BlidOS"; iconSource: Theme.icon("logo"); onActivated: Window.window.push("AboutPage.qml") }
    ListRow { visible: page.may("power"); title: "Restart"; iconSource: Theme.icon("power"); onActivated: Window.window.dialog.open({ title: "Restart now?", buttons: [{ text: "Restart", primary: true, action: () => Api.call("restart") }, { text: "Cancel" }] }) }
    ListRow { visible: page.may("power"); title: "Shut down"; iconSource: Theme.icon("power"); onActivated: Window.window.dialog.open({ title: "Shut down now?", buttons: [{ text: "Shut down", primary: true, action: () => Api.call("shutDown") }, { text: "Cancel" }] }) }

    Component.onCompleted: Api.call("hasTerminal", [], has => { terminalRow.visible = has && page.owner })
}
