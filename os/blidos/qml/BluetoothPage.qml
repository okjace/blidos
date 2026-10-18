import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Bluetooth"
    property bool available: true
    property bool on: false
    property bool scanning: false
    property var devices: []
    subtitle: !available ? "This computer has no Bluetooth." : !on ? "Bluetooth is off"
        : "To add a remote, game controller or headphones, put it in pairing mode, then choose Pair new device."

    function refresh() {
        Api.call("bluetooth", [], s => {
            available = s.available; on = s.on
            if (on) Api.call("bluetoothDevices", [], d => { devices = d }); else devices = []
        })
    }
    function scan() {
        scanning = true
        Api.call("bluetoothScan", [12], () => { scanning = false; refresh() }, () => { scanning = false })
        Window.window.toast("Searching for 12 seconds…")
    }
    function choose(d) {
        var w = Window.window
        if (d.paired) {
            w.dialog.open({ title: d.name, message: (d.connected ? "Connected" : "Paired") + " · " + d.address, buttons: [
                { text: d.connected ? "Reconnect" : "Connect", primary: true, action: () => Api.call("bluetoothConnect", [d.address], ok => { w.toast(ok ? "Connected to " + d.name : "Couldn't connect"); refresh() }) },
                { text: "Forget device", action: () => Api.call("bluetoothForget", [d.address], () => { w.toast("Forgot " + d.name); refresh() }) },
                { text: "Close" }] })
        } else {
            w.toast("Pairing with " + d.name + "…")
            Api.call("bluetoothPair", [d.address], ok => { w.toast(ok ? "Paired with " + d.name : "Couldn't pair with " + d.name); refresh() })
        }
    }

    Component.onCompleted: refresh()

    Row {
        visible: page.available
        spacing: Theme.px(16)
        PillButton { text: page.on ? "Turn off" : "Turn on"; onActivated: Api.call("setBluetoothOn", [!page.on], () => page.refresh()) }
        PillButton { visible: page.on; text: page.scanning ? "Searching…" : "Pair new device"; onActivated: if (!page.scanning) page.scan() }
    }
    Repeater {
        model: page.devices
        ListRow {
            title: modelData.name
            detail: modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Select to pair"
            iconSource: Theme.icon("bluetooth")
            onActivated: page.choose(modelData)
        }
    }
}
