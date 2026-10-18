import QtQuick
import QtQuick.Window
import BlidOS

// Game controllers: what's connected, how to pair, and what the buttons do on BlidOS screens.
Page {
    id: page
    title: "Controllers"
    property var pads: []
    subtitle: pads.length ? "Connected controllers. Games and Android apps use them directly."
                          : "No controllers connected. Plug one in with a USB cable, or pair it over Bluetooth."
    function refresh() { Api.call("controllers", [], p => { pads = p }, () => {}) }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.refresh() }

    Repeater {
        model: page.pads
        ListRow {
            title: modelData.name
            iconSource: Theme.icon("gamepad")
            detail: [modelData.connection, modelData.battery !== null ? "Battery " + modelData.battery + "%" : ""].filter(s => s).join(" · ")
        }
    }
    PillButton { text: "Pair a Bluetooth controller"; primary: true; onActivated: Window.window.push("BluetoothPage.qml") }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(19)
        text: "<b>On BlidOS screens</b><br>" +
              "D-pad or left stick: move · A / Cross: select · B / Circle: back<br>" +
              "Xbox, PS or Home button: back to the home screen, from anywhere<br><br>" +
              "<b>Pairing over Bluetooth</b> (choose Pair a Bluetooth controller, then Search):<br>" +
              "Xbox Wireless / Series: hold the small pair button on top until the Xbox button flashes fast.<br>" +
              "PlayStation 4 and 5: hold Share (Create) and the PS button until the light flashes.<br>" +
              "Switch Pro and Joy-Con: hold the small sync button.<br>" +
              "8BitDo and others: see the controller's manual for its pairing (Android or Xinput) mode.<br><br>" +
              "<b>With a cable</b> (USB): just plug it in. Xbox controllers that only work with Microsoft's USB wireless adapter can use a USB cable or Bluetooth instead; the adapter itself isn't supported yet."
    }
}
