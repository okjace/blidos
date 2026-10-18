import QtQuick
import QtQuick.Window
import BlidOS

Page {
    id: page
    title: "Date and time"
    property string zone: ""
    property var zones: []
    property string filter: ""
    subtitle: "The time is set automatically from the internet. Time zone: " + zone.replace(/_/g, " ")

    Component.onCompleted: {
        Api.call("timezone", [], z => { zone = z })
        Api.call("timezones", [], z => { zones = z })
    }

    Field {
        id: search
        width: Math.min(parent.width, Theme.px(600))
        placeholderText: "Search for a city, like London or Chicago"
        onTextChanged: page.filter = text.toLowerCase().replace(/ /g, "_")
    }
    Repeater {
        model: page.filter.length >= 2 ? page.zones.filter(z => z.toLowerCase().indexOf(page.filter) >= 0).slice(0, 20) : []
        ListRow {
            title: modelData.replace(/_/g, " ")
            detail: modelData === page.zone ? "Selected" : ""
            onActivated: Api.call("setTimezone", [modelData], ok => {
                if (ok) { page.zone = modelData; Window.window.toast("Time zone set") }
                else Window.window.toast("Couldn't change the time zone")
            })
        }
    }
}
