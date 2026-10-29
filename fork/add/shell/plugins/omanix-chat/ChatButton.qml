import QtQuick
import qs.Commons
import qs.Commons as Commons

// A small text button for the chat panel (theme colors; no focus of its own,
// so clicking it never moves the keyboard away from the composer).
Rectangle {
  id: root

  property string text: ""
  property string tooltip: ""
  property bool primary: false
  property bool outlined: false
  property color foreground: Commons.Color.popups.text
  signal clicked()

  implicitWidth: label.implicitWidth + Style.space(18)
  implicitHeight: Math.max(Style.space(26), label.implicitHeight + Style.space(10))
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.4
  color: primary ? Commons.Color.accent : (mouse.containsMouse ? Util.alpha(foreground, 0.12) : (outlined ? "transparent" : Util.alpha(foreground, 0.05)))
  border.width: outlined ? 1 : 0
  border.color: Util.alpha(foreground, 0.4)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.primary ? Commons.Color.background : root.foreground
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
