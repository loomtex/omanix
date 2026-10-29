import QtQuick
import qs.Commons
import qs.Commons as Commons

// A plain button for the approval surfaces: theme colors, no focus of its own
// (the card decides when it takes the keyboard, DESIGN §h.4, U13).
Rectangle {
  id: root

  property string text: ""
  property bool primary: false
  property bool warn: false
  property color foreground: Commons.Color.popups.text
  signal clicked()

  implicitWidth: label.implicitWidth + Style.space(24)
  implicitHeight: Math.max(Style.space(30), label.implicitHeight + Style.space(12))
  radius: Style.cornerRadius
  color: primary ? (mouse.containsMouse ? Qt.darker(Commons.Color.accent, 1.15) : Commons.Color.accent)
    : (mouse.containsMouse ? Util.alpha(foreground, 0.12) : Util.alpha(foreground, 0.05))
  border.width: 1
  border.color: warn ? Commons.Color.urgent : Util.alpha(foreground, primary ? 0 : 0.35)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.primary ? Commons.Color.background : (root.warn ? Commons.Color.urgent : root.foreground)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
