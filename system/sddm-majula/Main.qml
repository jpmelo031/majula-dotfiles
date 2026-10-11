// Majula login screen for SDDM (Qt 6). Same look as hyprlock.
import QtQuick

Rectangle {
    id: root
    width: 1366
    height: 768
    color: "#0E1114"

    readonly property color cText: "#DDD6C6"
    readonly property color cMuted: "#A39B8C"
    readonly property color cAccent: "#D1A35C"
    readonly property color cEmber: "#E0783E"
    readonly property color cDanger: "#C06452"
    readonly property color cField: "#1E2428"

    property string userName: userModel.lastUser !== "" ? userModel.lastUser : config.defaultUser
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool failed: false

    function login() {
        if (password.text.length === 0)
            return
        failed = false
        sddm.login(userName, password.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.failed = true
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
    }

    Image {
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    // Invisible items, only used to read each session's name
    Repeater {
        id: sessions
        model: sessionModel
        delegate: Item { property string sessionName: model.name }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cText
            font.family: "Cormorant Garamond"
            font.weight: Font.Light
            font.pixelSize: 138
            font.features: { "lnum": 1 }
            text: Qt.formatTime(new Date(), "HH:mm")
        }

        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 10
            color: root.cMuted
            font.family: "Inter"
            font.pixelSize: 18
            font.letterSpacing: 0.5
            text: new Date().toLocaleDateString(Qt.locale("en_US"), "dddd, MMMM d")
        }

        Item { width: 1; height: 64 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.cAccent
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.letterSpacing: 2
            font.capitalization: Font.AllUppercase
            text: root.userName
        }

        Item { width: 1; height: 12 }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            height: 46
            radius: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.failed ? root.cDanger : root.cEmber }
                GradientStop { position: 1.0; color: root.failed ? root.cDanger : root.cAccent }
            }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
                NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 8
                color: root.cField

                TextInput {
                    id: password
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: root.cText
                    selectionColor: root.cAccent
                    selectedTextColor: "#0E1114"
                    font.family: "Inter"
                    font.pixelSize: 15
                    focus: true
                    clip: true
                    Keys.onReturnPressed: root.login()
                    Keys.onEnterPressed: root.login()
                    onTextChanged: if (text.length > 0) root.failed = false
                }

                Text {
                    anchors.centerIn: parent
                    visible: password.text.length === 0
                    color: root.cMuted
                    font.family: "Inter"
                    font.pixelSize: 15
                    text: "Password"
                }
            }
        }

        Item { width: 1; height: 14 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.failed ? root.cDanger : root.cEmber
            font.family: "Inter"
            font.pixelSize: 13
            opacity: (root.failed || keyboard.capsLock) ? 1 : 0
            text: root.failed ? "Wrong password" : "Caps Lock is on"
        }
    }

    // Session (click to cycle through the installed ones)
    MouseArea {
        id: sessionButton
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 32
        anchors.bottomMargin: 26
        width: sessionLabel.width
        height: 20
        cursorShape: Qt.PointingHandCursor
        onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.count

        Text {
            id: sessionLabel
            color: sessionButton.containsMouse ? root.cText : root.cMuted
            font.family: "Inter"
            font.pixelSize: 13
            text: sessions.count > root.sessionIndex ? sessions.itemAt(root.sessionIndex).sessionName : ""
        }
        hoverEnabled: true
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 28
        anchors.bottomMargin: 20
        spacing: 8

        Repeater {
            model: [
                { label: "Reboot", glyph: "\u{F0709}", action: "reboot", enabled: sddm.canReboot },
                { label: "Shut down", glyph: "\u{F0425}", action: "poweroff", enabled: sddm.canPowerOff }
            ]

            delegate: Rectangle {
                required property var modelData
                visible: modelData.enabled
                width: 44
                height: 44
                radius: 10
                color: hover.containsMouse ? "#B320272C" : "#B3171C20"
                border.color: "#99465056"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    color: modelData.action === "poweroff" ? root.cEmber : root.cMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    text: modelData.glyph
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.action === "reboot" ? sddm.reboot() : sddm.powerOff()
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            clock.text = Qt.formatTime(new Date(), "HH:mm")
            date.text = new Date().toLocaleDateString(Qt.locale("en_US"), "dddd, MMMM d")
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
