import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Display"
    property var screens: []
    property var current: screens.length ? screens[0] : null
    subtitle: current ? current.description : "Looking for screens…"

    function refresh() { Api.call("displays", [], d => { screens = d }) }
    Component.onCompleted: refresh()

    Text {
        visible: !!page.current
        text: "Size of text and pictures"
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(20); font.bold: true
    }
    Repeater {
        model: page.current ? [1.0, 1.25, 1.5, 2.0] : []
        ListRow {
            title: modelData === 1.0 ? "Normal" : Math.round(modelData * 100) + "%"
            detail: Math.abs(page.current.scale - modelData) < 0.01 ? "Selected" : ""
            onActivated: Api.call("setDisplayScale", [page.current.name, modelData], page.refresh)
        }
    }
    Text {
        visible: !!page.current
        text: "Resolution"
        topPadding: Theme.px(16)
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(20); font.bold: true
    }
    Repeater {
        model: page.current ? page.current.modes.slice(0, 12) : []
        ListRow {
            title: modelData.label
            detail: modelData.current ? "Selected" : ""
            onActivated: Api.call("setDisplayMode", [page.current.name, modelData.width, modelData.height, modelData.refresh], () => {
                Window.window.toast("Changed to " + modelData.label)
                page.refresh()
            })
        }
    }
}
