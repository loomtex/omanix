import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons

// The options browser (DESIGN §h.6, "What can I change?"): a search over
// the option catalogs (`omanix options`, which reads
// /run/current-system/catalog/options/*.json) with each option's
// description, type, origin and current value (catalog/config.json, for
// loom.* and omanix.*). Works offline and signed out. "Ask <agent> to
// change it" pre-fills the composer and sends nothing.
Item {
  id: root

  property var svc: null
  property color fg: "white"
  property string agentName: "ada"
  property bool canAsk: true

  signal asked()

  Column {
    id: head
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      color: root.fg
      font.pixelSize: Style.font.title
      font.bold: true
      text: "What can I change?"
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      color: Util.alpha(root.fg, 0.7)
      font.pixelSize: Style.font.bodySmall
      text: "Every setting of this computer is an option in its configuration. Search them here; "
        + (root.canAsk ? "ask " + root.agentName + " to change one, or " : "") + "edit your host repo yourself."
    }

    Rectangle {
      width: parent.width
      height: Style.space(34)
      radius: Style.cornerRadius
      color: Util.alpha(root.fg, 0.05)
      border.width: 1
      border.color: search.activeFocus ? Commons.Color.accent : Util.alpha(root.fg, 0.25)
      TextField {
        id: search
        anchors.fill: parent
        anchors.margins: Style.space(4)
        placeholderText: "Search options: gaps, theme, bluetooth, keyboard…"
        color: root.fg
        font.pixelSize: Style.font.body
        background: null
        text: root.svc ? root.svc.optionsQuery : ""
        onTextEdited: if (root.svc) root.svc.optionsQuery = text
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      color: Util.alpha(root.fg, 0.5)
      font.pixelSize: Style.font.caption
      text: !root.svc || root.svc.optionsQuery.trim().length < 2 ? "Type at least two letters."
        : root.svc.optionsBusy ? "Searching…"
        : root.svc.optionsTotal === 0 ? "No option matches."
        : root.svc.optionsTotal > root.svc.optionsResults.length ? root.svc.optionsResults.length + " of " + root.svc.optionsTotal + " options"
        : root.svc.optionsTotal + (root.svc.optionsTotal === 1 ? " option" : " options")
    }
  }

  ListView {
    id: list
    anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; topMargin: Style.space(8) }
    clip: true
    spacing: Style.space(6)
    model: root.svc ? root.svc.optionsResults : []

    delegate: Rectangle {
      id: opt
      required property var modelData
      required property int index
      width: list.width
      height: col.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(root.fg, 0.05)

      Column {
        id: col
        x: Style.space(6); y: Style.space(6)
        width: parent.width - Style.space(12)
        spacing: Style.space(3)

        Text {
          width: parent.width
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          text: opt.modelData.path
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.6)
          font.pixelSize: Style.font.caption
          text: opt.modelData.type + "  ·  " + opt.modelData.origin
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: root.fg
          font.pixelSize: Style.font.bodySmall
          text: opt.modelData.description
        }
        Text {
          width: parent.width
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: Util.alpha(root.fg, 0.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          text: opt.modelData.hasCurrent ? "Now: " + opt.modelData.current
            : (opt.modelData.def !== "" ? "Default: " + opt.modelData.def : "")
          visible: text !== ""
        }
        ChatButton {
          visible: root.canAsk && !opt.modelData.path.includes("<")
          text: "Ask " + root.agentName + " to change it"
          outlined: true
          onClicked: { if (root.svc) root.svc.askToChange(opt.modelData); root.asked() }
        }
      }
    }
  }
}
