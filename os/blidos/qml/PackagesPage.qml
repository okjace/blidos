import QtQuick
import QtQuick.Window
import BlidOS

// Installs packages from a USB drive or Downloads: .deb (drivers, Linux apps, with whatever they
// need) and .apk (Android apps, including Android TV apps Google Play doesn't offer here).
JobPage {
    id: page
    jobName: "packages"
    title: "Install a package"
    property var files: []
    property bool looking: true

    function look() {
        looking = true
        Api.call("debFiles", [], f => { files = f; looking = false }, e => { looking = false; Api.toast(e) })
    }
    function size(b) { return b > 1e9 ? (b / 1e9).toFixed(1) + " GB" : b > 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.ceil(b / 1e3) + " KB" }
    function choose(f) {
        var w = Window.window
        if (f.kind === "apk") {
            w.dialog.open({ title: "Install " + f.file + " in Android?",
                message: "An Android app from outside Google Play, for example an Android TV app. It's installed in this profile's Android and appears on the home screen. Only install apps from people you trust.",
                buttons: [{ text: "Install", primary: true, action: () => {
                    w.busy("Installing " + f.file + "…", "Android starts first if it isn't running.")
                    Api.call("installApk", [f.path], () => { w.busy(""); w.toast(f.file + " is installed") }, e => { w.busy(""); w.toast(e) })
                } }, { text: "Cancel" }] })
            return
        }
        Api.call("debDetails", [f.path], d => {
            if (d.problem) {
                Window.window.dialog.open({ title: "Can't install " + f.file, message: d.problem, buttons: [{ text: "OK", primary: true }] })
                return
            }
            var what = d.blidos ? "This is a BlidOS update. Your profiles, apps and files stay as they are."
                     : (d.summary ? d.summary + ". " : "") + "Only install packages from people you trust: a package can change anything on this computer."
            var verb = !d.installed ? "Install" : d.installed === d.version ? "Reinstall" : "Update"
            Window.window.dialog.open({
                title: verb + " " + d.package + " " + d.version + "?",
                message: what + (d.installed && d.installed !== d.version ? "\nReplaces version " + d.installed + "." : ""),
                buttons: [{ text: verb, primary: true, action: () => Api.call("installDeb", [d.key]) },
                          { text: "Cancel" }] })
        })
    }
    Component.onCompleted: look()

    subtitle: job.running ? "Installing… keep the computer on."
            : job.ok === true ? "Installed. Drivers start working after a restart."
            : job.ok === false ? "Installing failed. If it says something is missing, connect to the internet and try again: BlidOS downloads what the package needs."
            : looking ? "Looking on USB drives and in Downloads…"
            : files.length ? "Packages found on USB drives and in Downloads: .deb for Linux, .apk for Android."
            : "No packages found. Put a .deb (Linux) or .apk (Android) file on a USB drive or in a Downloads folder, then choose Look again."

    Repeater {
        model: page.files
        ListRow {
            title: modelData.file
            detail: (modelData.kind === "apk" ? "Android app · " : "") + modelData.where + " · " + page.size(modelData.size)
            onActivated: if (!page.job.running) page.choose(modelData)
        }
    }
    PillButton { visible: page.job.ok === true; text: "Restart now"; primary: true; onActivated: Api.call("restart") }
    PillButton { visible: !page.job.running && !page.looking; text: "Look again"; onActivated: page.look() }
}
