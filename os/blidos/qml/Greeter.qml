import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import BlidOS

// Runs before anyone is signed in (under greetd): first-boot setup, then "Who's watching?".
Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "BlidOS"
    color: Theme.bgBottom

    property var me: null
    property bool androidRunning: false
    property alias dialog: dialog
    property alias pin: pinPad
    function toast(message) { toastBox.show(message) }
    function push(page, props) {
        var component = Qt.createComponent(Qt.resolvedUrl(page))
        if (component.status === Component.Error) { console.error(component.errorString()); return }
        stack.push(component, props || {})
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bgTop }
            GradientStop { position: 1; color: Theme.bgBottom }
        }
    }

    StackView {
        id: stack
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            if ((event.key === Qt.Key_Escape || event.key === Qt.Key_Back) && stack.depth > 1) { stack.pop(); event.accepted = true }
        }
    }

    Component.onCompleted: Api.call("setupState", [], s => {
        if (s.done) stack.push(picker)
        else stack.push(setup)
    }, e => { stack.push(picker); toast(e) })

    // ---------- Who's watching? ----------
    Component {
        id: picker
        FocusScope {
            id: pickerPage
            property var profiles: []
            Component.onCompleted: Api.call("profiles", [], p => { profiles = p; Qt.callLater(() => { if (cards.count) cards.itemAt(0).forceActiveFocus() }) })

            function choose(p) {
                if (!p.hasPin) return login(p, "")
                win.pin.open("Enter PIN", p.name, code => login(p, code))
            }
            function login(p, code) {
                Api.call("login", [p.user, code], () => {}, e => {
                    if (win.pin.visible) win.pin.fail(e === "Wrong PIN" ? "Wrong PIN. After 5 tries it locks for a minute." : e)
                    else win.toast(e)
                })
            }

            Column {
                anchors.centerIn: parent
                spacing: Theme.px(16)
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Who's watching?"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(48); font.bold: true }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Choose your profile"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(20) }
                Item { width: 1; height: Theme.px(32) }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.px(24)
                    Repeater {
                        id: cards
                        model: pickerPage.profiles
                        FocusScope {
                            id: card
                            width: Theme.px(190); height: Theme.px(240)
                            activeFocusOnTab: true
                            scale: activeFocus ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: 140 } }
                            Rectangle {
                                anchors.fill: parent; radius: Theme.px(20)
                                color: "transparent"
                                border.width: card.activeFocus ? Theme.px(3) : 0; border.color: "white"
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.px(12)
                                Avatar { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.name; colorIndex: modelData.color }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(22); font.bold: true }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.kids ? "Kids" : (modelData.hasPin ? "PIN locked" : " ")
                                    color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(15)
                                }
                            }
                            Keys.onReturnPressed: pickerPage.choose(modelData)
                            Keys.onEnterPressed: pickerPage.choose(modelData)
                            Keys.onLeftPressed: if (index > 0) cards.itemAt(index - 1).forceActiveFocus()
                            Keys.onRightPressed: if (index < cards.count - 1) cards.itemAt(index + 1).forceActiveFocus()
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: card.forceActiveFocus(); onClicked: pickerPage.choose(modelData) }
                        }
                    }
                }
            }
            Row {
                anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.px(48)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.px(16)
                PillButton { text: "Restart"; onActivated: Api.call("restartComputer") }
                PillButton { text: "Shut down"; onActivated: Api.call("shutDownComputer") }
            }
        }
    }

    // ---------- First-boot setup ----------
    Component {
        id: setup
        FocusScope {
            id: setupPage
            property int step: 0
            property string ownerName: ""
            property string ownerUser: ""
            property var others: []
            property string network: ""

            function next() { step++ }
            Component.onCompleted: refreshNetwork()
            function refreshNetwork() { Api.call("connection", [], c => { network = c }, () => {}) }
            StackView.onActivated: refreshNetwork()

            onStepChanged: Qt.callLater(() => { var b = buttons.children[0]; if (step === 2) nameField.forceActiveFocus(); else if (b) b.forceActiveFocus() })

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.px(200), Theme.px(1100))
                spacing: Theme.px(18)

                Image {
                    visible: setupPage.step === 0 || setupPage.step === 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: Theme.icon("logo"); width: Theme.px(120); height: width
                    sourceSize: Qt.size(width, height)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(46); font.bold: true
                    text: ["Welcome to BlidOS", "Connect to the internet", "Your profile", "Who else watches?", "You're all set"][setupPage.step]
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(21)
                    text: [
                        "Let's get your TV ready. It only takes a minute.",
                        setupPage.network !== "Not connected" && setupPage.network ? setupPage.network + "." : "You need internet for Google Play, streaming and updates.",
                        "This is the main profile. It can add people, set PINs, install drivers and manage BlidOS.",
                        "Each person gets their own apps, Google account and settings. Kids profiles only get apps you pick." +
                            (setupPage.others.length ? "\n\nAdded: " + setupPage.others.join(", ") : ""),
                        "Sign in to your profile to start. Google Play setup is in Settings, Android and Google Play.",
                    ][setupPage.step]
                }
                Field {
                    id: nameField
                    visible: setupPage.step === 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    placeholderText: "Your name"
                    Keys.onDownPressed: buttons.children[0].forceActiveFocus()
                }
                Row {
                    id: buttons
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.px(16)
                    topPadding: Theme.px(24)

                    PillButton {
                        primary: true
                        text: ["Get started", "Continue", "Continue", setupPage.others.length ? "Continue" : "Done for now", "Start watching"][setupPage.step]
                        KeyNavigation.right: buttons.children[1]
                        onActivated: {
                            if (setupPage.step === 2) setupPage.createOwner()
                            else if (setupPage.step === 4) Api.call("finishSetup", [], () => { stack.replace(picker) })
                            else setupPage.next()
                        }
                    }
                    PillButton {
                        visible: setupPage.step === 1
                        text: "Choose Wi-Fi"
                        KeyNavigation.left: buttons.children[0]
                        onActivated: win.push("WifiPage.qml")
                    }
                    PillButton {
                        visible: setupPage.step === 3
                        text: "Add a person"
                        KeyNavigation.left: buttons.children[0]; KeyNavigation.right: buttons.children[3]
                        onActivated: setupPage.addPerson(false)
                    }
                    PillButton {
                        visible: setupPage.step === 3
                        text: "Add a kid"
                        KeyNavigation.left: buttons.children[2]
                        onActivated: setupPage.addPerson(true)
                    }
                }
            }

            function createOwner() {
                var name = nameField.text.trim() || "Owner"
                if (ownerUser) return askPin()
                Api.call("createProfile", [name, "", false], p => { ownerUser = p.user; ownerName = p.name; askPin() })
            }
            function askPin() {
                win.dialog.open({ title: "Add a PIN?", message: "A 4-digit PIN stops others from opening your profile, changing settings or installing drivers.",
                    buttons: [{ text: "Add a PIN", primary: true, action: () => pinTwice() }, { text: "Skip", action: () => next() }] })
            }
            function pinTwice() {
                var pad = win.pin
                var first = ""
                pad.open("New PIN", "Pick 4 digits", code => {
                    if (!first) { first = code; pad.open("Confirm PIN", "Enter the same 4 digits again"); return }
                    if (code !== first) { pad.close(); win.toast("Those didn't match. Try again."); return }
                    Api.call("setPin", [ownerUser, code], () => { pad.close(); next() }, e => pad.fail(e))
                })
            }
            function addPerson(kids) {
                win.dialog.open({ title: kids ? "Kid's name" : "Their name", input: true, buttons: [
                    { text: "Add", primary: true, action: n => { if (n.trim()) Api.call("createProfile", [n.trim(), "", kids], p => { others = others.concat([p.name + (kids ? " (Kids)" : "")]) }) } },
                    { text: "Cancel" }] })
            }
        }
    }

    Dialog { id: dialog }
    PinPad { id: pinPad }
    Toast { id: toastBox }
    Connections { target: Api; function onToast(message) { toastBox.show(message) } }
}
