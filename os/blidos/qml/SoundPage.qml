import QtQuick
import BlidOS

Page {
    id: page
    title: "Sound"
    property var vol: ({ level: 0, muted: false })
    property var outputs: []
    subtitle: vol.muted ? "Muted" : "Volume " + vol.level + "%"

    function refresh() {
        Api.call("volume", [], v => { vol = v })
        Api.call("audioOutputs", [], o => { outputs = o })
    }
    function change(delta) { Api.call("setVolume", [Math.max(0, Math.min(100, vol.level + delta))], refresh) }
    Component.onCompleted: refresh()

    Row {
        spacing: Theme.px(16)
        PillButton { text: "Quieter"; onActivated: page.change(-5) }
        PillButton { text: "Louder"; onActivated: page.change(5) }
        PillButton { text: page.vol.muted ? "Unmute" : "Mute"; onActivated: Api.call("toggleMute", [], page.refresh) }
    }
    Text {
        visible: page.outputs.length > 1
        text: "Play sound on"
        color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(20); font.bold: true
        topPadding: Theme.px(16)
    }
    Repeater {
        model: page.outputs.length > 1 ? page.outputs : []
        ListRow {
            title: modelData.name
            detail: modelData.default ? "Selected" : ""
            iconSource: Theme.icon("sound")
            onActivated: Api.call("setAudioOutput", [modelData.id], page.refresh)
        }
    }
}
