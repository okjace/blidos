import QtQuick
import BlidOS

Page {
    id: page
    title: "About BlidOS"
    property string version: ""
    property string ip: ""
    property var store: null
    function size(b) { return b > 1e12 ? (b / 1e12).toFixed(1) + " TB" : (b / 1e9).toFixed(1) + " GB" }
    Component.onCompleted: {
        Api.call("version", [], v => { version = v })
        Api.call("ipAddress", [], a => { ip = a || "Not connected" })
        Api.call("storage", [], s => { store = s })
    }
    ListRow { title: "Version"; detail: page.version }
    ListRow { title: "Based on"; detail: "Debian Linux, with Android apps by Waydroid" }
    ListRow { title: "IP address"; detail: page.ip }
    ListRow { title: "Storage"; detail: page.store ? page.size(page.store.free) + " free of " + page.size(page.store.total) : "" }
}
