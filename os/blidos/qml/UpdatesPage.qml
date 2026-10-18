import QtQuick
import BlidOS

// One button installs everything: a newer BlidOS found on a USB drive, then system updates.
// Profiles, Android apps and files are never touched.
JobPage {
    id: page
    jobName: "updates"
    title: "Updates"
    property var state_: null   // from check-updates
    property bool checking: true
    readonly property int count: state_ ? state_.system.length + (state_.blidos ? 1 : 0) : 0

    function check() {
        checking = true
        Api.call("checkUpdates", [], s => { state_ = s; checking = false; if (s.refreshing) recheck.restart() },
                 e => { checking = false; Api.toast(e) })
    }
    // System updates appear once the package lists have refreshed in the background.
    Timer { id: recheck; interval: 15000; onTriggered: if (!page.job.running) Api.call("checkUpdates", [], s => {
        page.state_ = s; if (s.refreshing) recheck.restart() }, () => {}) }
    function size(b) { return b > 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.ceil(b / 1e3) + " KB" }
    Component.onCompleted: check()

    subtitle: job.running ? "Installing updates… keep the computer on. You can keep using it."
            : job.ok === true ? "Updates installed. Restart to finish."
            : job.ok === false ? "Updating stopped. Nothing was lost; check the internet connection and try again."
            : checking ? "Checking for updates…"
            : count ? "Your profiles, apps and files stay exactly as they are."
            : state_ && state_.refreshing ? "Looking for system updates…"
            : state_ && !state_.online ? "Couldn't reach the update servers. Check the internet connection. BlidOS updates on a USB drive still work."
            : "BlidOS is up to date."

    ListRow { title: "BlidOS"; detail: page.state_ ? page.state_.current : "" }
    ListRow {
        visible: !!(page.state_ && page.state_.blidos)
        title: page.state_ && page.state_.blidos ? "BlidOS " + page.state_.blidos.version : ""
        detail: !(page.state_ && page.state_.blidos) ? ""
              : page.state_.blidos.url ? "New version, download from GitHub (" + page.size(page.state_.blidos.size) + ")"
              : "New version, on " + page.state_.blidos.where
    }
    ListRow {
        visible: !!(page.state_ && page.state_.system.length)
        title: page.state_ ? page.state_.system.length + " system " + (page.state_.system.length === 1 ? "update" : "updates") : ""
        detail: page.state_ ? page.state_.system.slice(0, 4).join(", ") + (page.state_.system.length > 4 ? "…" : "") : ""
    }
    PillButton {
        visible: !page.job.running && !page.checking && page.count > 0 && page.job.ok !== true
        text: "Install updates"; primary: true
        onActivated: Api.call("installUpdates", [page.state_.blidos ? (page.state_.blidos.url || page.state_.blidos.path) : ""])
    }
    PillButton { visible: page.job.ok === true; text: "Restart now"; primary: true; onActivated: Api.call("restart") }
    PillButton { visible: !page.job.running && !page.checking; text: "Check again"; onActivated: page.check() }
}
