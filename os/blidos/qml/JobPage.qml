import QtQuick
import BlidOS

// Shared by Drivers and Updates: runs a root job in blidosd and shows its progress.
Page {
    id: page
    property string jobName
    property var job: ({ running: false, ok: null, log: [] })
    property alias log: logText.text
    function poll() { Api.call("job", [jobName], j => { job = j }, () => {}) }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.poll() }

    Text {
        id: logText
        width: parent.width
        visible: page.job.log.length > 0
        text: page.job.log.slice(-18).join("\n")  // the newest lines
        color: Theme.dim
        font.family: "monospace"; font.pixelSize: Theme.px(14)
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 18
    }
}
