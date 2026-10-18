import QtQuick

// A settings-style page: title, subtitle, then whatever it contains, scrollable.
// Arrow keys move between focusable items; the focused item is kept on screen.
FocusScope {
    id: page
    property string title
    property string subtitle
    default property alias content: column.data
    property alias column: column

    function focusFirst() {
        var item = page.nextItemInFocusChain(true)
        if (item && contains_(item)) item.forceActiveFocus()
    }
    function contains_(item) {
        for (var p = item; p; p = p.parent) if (p === page) return true
        return false
    }
    function move(forward) {
        var current = Window.activeFocusItem
        if (!current) return focusFirst()
        var next = current.nextItemInFocusChain(forward)
        if (next && contains_(next)) next.forceActiveFocus()
    }

    Component.onCompleted: Qt.callLater(focusFirst)

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: inner.height + Theme.px(120)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Behavior on contentY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: inner
            x: Theme.px(96); y: Theme.px(64)
            width: flick.width - 2 * Theme.px(96)
            spacing: Theme.px(14)
            Text {
                text: page.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: Theme.px(40); font.bold: true
            }
            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: page.subtitle
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.px(19)
            }
            Item { width: 1; height: Theme.px(12) }
            Column { id: column; width: parent.width; spacing: Theme.px(12) }
        }
    }

    Connections {
        target: page.Window.window
        function onActiveFocusItemChanged() {
            var item = page.Window.activeFocusItem
            if (!item || !page.contains_(item)) return
            var y = item.mapToItem(inner, 0, 0).y + inner.y
            var margin = Theme.px(140)
            if (y - margin < flick.contentY) flick.contentY = Math.max(0, y - margin)
            else if (y + item.height + margin > flick.contentY + flick.height)
                flick.contentY = Math.min(flick.contentHeight - flick.height, y + item.height + margin - flick.height)
        }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) { move(true); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) { move(false); event.accepted = true }
    }
}
