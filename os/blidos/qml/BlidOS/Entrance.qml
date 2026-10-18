import QtQuick

// Makes its parent rise and fade in, after a short delay (for items appearing one after another).
// Usage: Entrance { delay: 40 * index }    Set enabled: false to show the parent at once.
Item {
    id: entrance
    property int delay: 0
    property Item item: parent
    Component.onCompleted: {
        if (!enabled || !item) return
        item.opacity = 0
        anim.start()
    }
    SequentialAnimation {
        id: anim
        PauseAnimation { duration: Math.max(0, entrance.delay) }
        ParallelAnimation {
            NumberAnimation { target: entrance.item; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: shift; property: "y"; from: Theme.px(28); to: 0; duration: 360; easing.type: Easing.OutCubic }
        }
    }
    Translate { id: shift }
    // The parent is moved by this translation while it rises in.
    Binding { target: entrance.item; property: "transform"; value: shift; when: entrance.enabled && entrance.item !== null }
}
