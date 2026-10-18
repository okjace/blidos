import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Wi-Fi"
    property bool enabled_: true
    property bool scanning: false
    property var networks: []
    subtitle: !enabled_ ? "Wi-Fi is off" : (scanning && networks.length === 0 ? "Looking for networks…" : "")

    function refresh(rescan) {
        Api.call("wifiEnabled", [], on => {
            enabled_ = on
            if (!on) { networks = []; return }
            scanning = true
            Api.call("wifiNetworks", [!!rescan], list => { networks = list; scanning = false }, () => { scanning = false })
        })
    }
    function signal(n) { return n.signal >= 70 ? "Excellent" : n.signal >= 50 ? "Good" : n.signal >= 30 ? "Fair" : "Weak" }
    function choose(n) {
        var d = Window.window.dialog
        if (n.active) {
            d.open({ title: n.ssid, message: "Connected · " + signal(n) + " signal", buttons: [
                { text: "Forget network", action: () => Api.call("wifiForget", [n.ssid], () => { Window.window.toast("Forgot " + n.ssid); refresh(false) }) },
                { text: "Close", primary: true }] })
        } else if (n.enterprise) {
            d.open({ title: n.ssid, message: "This is a work or school network. BlidOS can't join this kind of network yet." })
        } else if (n.secure) {
            d.open({ title: "Join " + n.ssid, input: true, password: true, placeholder: "Password", buttons: [
                { text: "Connect", primary: true, action: pw => connect(n.ssid, pw) }, { text: "Cancel" }] })
        } else {
            connect(n.ssid, "")
        }
    }
    function connect(ssid, password) {
        Window.window.toast("Connecting to " + ssid + "…")
        Api.call("wifiConnect", [ssid, password], r => {
            Window.window.toast(r.ok ? "Connected to " + ssid : (password ? "Couldn't connect. Check the password." : "Couldn't connect"))
            refresh(false)
        })
    }

    Component.onCompleted: refresh(true)
    Timer { interval: 15000; running: page.enabled_; repeat: true; onTriggered: page.refresh(false) }

    Row {
        spacing: Theme.px(16)
        PillButton { text: page.enabled_ ? "Turn off" : "Turn on"; onActivated: Api.call("setWifiEnabled", [!page.enabled_], () => page.refresh(true)) }
        PillButton { visible: page.enabled_; text: "Scan again"; onActivated: page.refresh(true) }
    }
    Repeater {
        model: page.networks
        ListRow {
            title: modelData.ssid
            detail: (modelData.active ? "Connected · " : "") + page.signal(modelData) + (modelData.secure ? " · Secured" : " · Open")
            iconSource: Theme.icon("wifi")
            onActivated: page.choose(modelData)
        }
    }
}
