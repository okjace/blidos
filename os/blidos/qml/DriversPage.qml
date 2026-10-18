import QtQuick
import QtQuick.Window
import BlidOS

JobPage {
    id: page
    jobName: "drivers"
    title: "Drivers"
    property var drivers: []
    subtitle: job.running ? "Installing… keep the computer on." : job.ok === true ? "Done. Restart to use the new driver."
            : job.ok === false ? "Installing failed. Check your internet connection and try again."
            : drivers.length ? "Drivers for this computer's hardware." : "No extra drivers are needed for this computer."
    Component.onCompleted: Api.call("drivers", [], d => { drivers = d })

    Repeater {
        model: page.drivers
        ListRow {
            title: modelData.name
            detail: modelData.installed ? "Installed" : "Install"
            onActivated: if (!modelData.installed && !page.job.running) Window.window.dialog.open({
                title: "Install " + modelData.name + "?", message: "For " + modelData.device + ". This downloads it from the internet.",
                buttons: [{ text: "Install", primary: true, action: () => Api.call("installDriver", [modelData.id]) }, { text: "Cancel" }] })
        }
    }
    PillButton { visible: page.job.ok === true; text: "Restart now"; onActivated: Api.call("restart") }
}
