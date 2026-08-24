import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested details panel for Encyclopedic (loaded by BarWidget — not a separate kind).
// 0.1.5 — discoverability keywords/aliases; LOOK UP + MATCH hero + RELATED. No vendor chrome.
Panel {
  id: root
  moduleName: "harris.encyclopedic"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : "monospace"
  readonly property color themeBackground: {
    try {
      if (typeof Color !== "undefined" && Color.popups && Color.popups.background)
        return Color.popups.background
      if (typeof Color !== "undefined" && Color.background)
        return Color.background
    } catch (e) {}
    return Qt.rgba(0.1, 0.1, 0.12, 1)
  }
  readonly property color surfaceColor: Qt.rgba(
    contentForeground.r, contentForeground.g, contentForeground.b, 0.06)
  readonly property color dimForeground: Qt.darker(contentForeground, 1.45)
  readonly property color fwAccent: Qt.rgba(0.43, 0.78, 0.91, 1.0)

  readonly property var liveStore: store

  // FW-19: focus query when panel opens (skip while a lookup is in flight)
  onOpenedChanged: {
    if (root.opened && !(liveStore && liveStore.loading))
      Qt.callLater(function() { if (queryEdit) queryEdit.forceActiveFocus() })
  }


  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }


  implicitWidth: Style.space(420)
  implicitHeight: Math.min(Style.space(720), contentCol.implicitHeight + Style.space(36))

  Rectangle {
    anchors.fill: parent
    color: root.themeBackground
    radius: Style.space(12)

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: Style.space(16)
      contentWidth: width
      contentHeight: contentCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: contentCol
        width: flick.width
        spacing: Style.space(14)
        opacity: liveStore && liveStore.loading ? 0.72 : 1.0

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // Header
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "FAIR WITNESS"
            color: root.fwAccent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 3.2
          }

          Text {
            text: "look it up · report what it says"
            color: root.contentForeground
            opacity: 0.5
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            width: parent.width
          }

          Text {
            visible: !!(liveStore && liveStore.lookedUpAt && String(liveStore.lookedUpAt).length)
            text: liveStore ? ("looked up " + liveStore.lastUpdatedText) : ""
            color: root.contentForeground
            opacity: 0.35
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
          }
        }

        // One search / paste field
        Column {
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            width: parent.width
            height: Math.max(Style.space(52), queryEdit.implicitHeight + Style.space(20))
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

            TextEdit {
              id: queryEdit
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              text: liveStore ? liveStore.queryInput : ""
              onTextChanged: if (liveStore) liveStore.queryInput = text
              Keys.onReturnPressed: function(event) {
                if (event.modifiers & Qt.ShiftModifier) {
                  event.accepted = false
                  return
                }
                event.accepted = true
                if (liveStore) liveStore.lookUp()
              }

              Text {
                anchors.fill: parent
                visible: !queryEdit.text.length
                text: "search or paste a topic…"
                color: root.contentForeground
                opacity: 0.32
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        // Big LOOK UP
        Rectangle {
          width: parent.width
          height: Style.space(48)
          radius: 10
          color: lookupMa.containsMouse
            ? Qt.lighter(root.fwAccent, 1.12)
            : root.fwAccent
          opacity: liveStore && liveStore.loading ? 0.7 : 1.0

          Text {
            anchors.centerIn: parent
            text: liveStore && liveStore.loading ? "LOOKING UP…" : "LOOK UP"
            color: Qt.rgba(0.06, 0.08, 0.1, 1)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            font.letterSpacing: 2.4
          }

          MouseArea {
            id: lookupMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !(liveStore && liveStore.loading)
            onClicked: if (liveStore) liveStore.lookUp()
          }
        }

        // Toast / error
        Text {
          width: parent.width
          visible: liveStore && liveStore.lastError && liveStore.lastError.length
          text: liveStore ? liveStore.lastError : ""
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: liveStore && liveStore.toastText && liveStore.toastText.length
          text: liveStore ? liveStore.toastText : ""
          color: root.fwAccent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Hero + related (when direct title/slug match) OR flat results
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: liveStore && liveStore.hasPrimary

          // Expandable MATCH hero
          Rectangle {
            width: parent.width
            height: heroInner.implicitHeight + Style.space(22)
            radius: 12
            color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.4)

            Column {
              id: heroInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(14)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "MATCH"
                  color: root.fwAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.8
                  anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                  width: parent.width - Style.space(100)
                  height: 1
                }
              }

              Text {
                width: parent.width
                text: liveStore && liveStore.primary
                  ? (liveStore.primary.title || liveStore.primary.slug || "Untitled")
                  : ""
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                visible: !!(liveStore && liveStore.primary && liveStore.primary.snippet
                            && String(liveStore.primary.snippet).length)
                text: liveStore && liveStore.primary ? (liveStore.primary.snippet || "") : ""
                textFormat: Text.PlainText
                color: root.contentForeground
                opacity: 0.58
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
                maximumLineCount: liveStore && liveStore.heroExpanded ? 24 : 3
                elide: Text.ElideRight
              }

              // Expand / collapse affordance
              Text {
                text: liveStore && liveStore.heroExpanded ? "▾ Show less" : "▸ Show more"
                color: showMoreMa.containsMouse ? Qt.lighter(root.fwAccent, 1.15) : root.fwAccent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true

                MouseArea {
                  id: showMoreMa
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (liveStore) liveStore.toggleHero()
                }
              }

              // Actions only when expanded
              Row {
                spacing: Style.space(8)
                visible: !!(liveStore && liveStore.heroExpanded)

                Rectangle {
                  width: Style.space(56)
                  height: Style.space(26)
                  radius: 6
                  color: heroOpenMa.containsMouse
                    ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.34)
                    : Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.22)
                  border.width: 1
                  border.color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.5)
                  Text {
                    anchors.centerIn: parent
                    text: "Open"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  MouseArea {
                    id: heroOpenMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (liveStore) liveStore.openPrimary()
                  }
                }

                Rectangle {
                  width: Style.space(72)
                  height: Style.space(26)
                  radius: 6
                  color: heroCopyTitleMa.containsMouse
                    ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                    : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                  Text {
                    anchors.centerIn: parent
                    text: "Copy title"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    id: heroCopyTitleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (liveStore) liveStore.copyPrimaryTitle()
                  }
                }

                Rectangle {
                  width: Style.space(68)
                  height: Style.space(26)
                  radius: 6
                  color: heroCopyLinkMa.containsMouse
                    ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                    : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                  Text {
                    anchors.centerIn: parent
                    text: "Copy link"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    id: heroCopyLinkMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (liveStore) liveStore.copyPrimaryLink()
                  }
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              z: -1
              cursorShape: Qt.PointingHandCursor
              onClicked: if (liveStore) liveStore.toggleHero()
            }
          }

          // RELATED header + cards
          Text {
            width: parent.width
            visible: liveStore && liveStore.related && liveStore.related.length > 0
            text: "RELATED"
            color: root.contentForeground
            opacity: 0.45
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.8
          }

          Repeater {
            model: liveStore ? liveStore.related : []
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: contentCol.width
              height: relatedInner.implicitHeight + Style.space(20)
              radius: 12
              color: relatedCardMa.containsMouse
                ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09)
                : root.surfaceColor
              border.width: 1
              border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

              Column {
                id: relatedInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  text: modelData.title || modelData.slug || "Untitled"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  visible: !!(modelData.snippet && String(modelData.snippet).length)
                  text: modelData.snippet || ""
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                }

                Row {
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(56)
                    height: Style.space(26)
                    radius: 6
                    color: relatedOpenMa.containsMouse
                      ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.30)
                      : Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.4)
                    Text {
                      anchors.centerIn: parent
                      text: "Open"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      id: relatedOpenMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (!liveStore) return
                        liveStore.openUrlExternal(modelData.url || "", modelData.slug || "")
                      }
                    }
                  }

                  Rectangle {
                    width: Style.space(72)
                    height: Style.space(26)
                    radius: 6
                    color: relatedCopyTitleMa.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy title"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: relatedCopyTitleMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.copyText(modelData.title || "")
                    }
                  }

                  Rectangle {
                    width: Style.space(68)
                    height: Style.space(26)
                    radius: 6
                    color: relatedCopyLinkMa.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy link"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: relatedCopyLinkMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.copyText(modelData.url || "")
                    }
                  }
                }
              }

              MouseArea {
                id: relatedCardMa
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }
        }

        // Flat results list (no direct match — no fake hero)
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: liveStore && liveStore.hasResults && !liveStore.hasPrimary

          Repeater {
            model: liveStore ? liveStore.results : []
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: contentCol.width
              height: cardInner.implicitHeight + Style.space(20)
              radius: 12
              color: flatCardMa.containsMouse
                ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09)
                : root.surfaceColor
              border.width: 1
              border.color: {
                var sel = liveStore && liveStore.selectedIndex === index
                if (sel)
                  return Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.45)
                return Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
              }

              Column {
                id: cardInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  text: modelData.title || modelData.slug || "Untitled"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  visible: !!(modelData.snippet && String(modelData.snippet).length)
                  text: modelData.snippet || ""
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                }

                Row {
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(56)
                    height: Style.space(26)
                    radius: 6
                    color: flatOpenMa.containsMouse
                      ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.30)
                      : Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.4)
                    Text {
                      anchors.centerIn: parent
                      text: "Open"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      id: flatOpenMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.openResult(index)
                    }
                  }

                  Rectangle {
                    width: Style.space(72)
                    height: Style.space(26)
                    radius: 6
                    color: flatCopyTitleMa.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy title"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: flatCopyTitleMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.copyTitle(index)
                    }
                  }

                  Rectangle {
                    width: Style.space(68)
                    height: Style.space(26)
                    radius: 6
                    color: flatCopyLinkMa.containsMouse
                      ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
                    Text {
                      anchors.centerIn: parent
                      text: "Copy link"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: flatCopyLinkMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (liveStore) liveStore.copyLink(index)
                    }
                  }
                }
              }

              MouseArea {
                id: flatCardMa
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!liveStore) return
                  liveStore.selectResult(index)
                }
                onDoubleClicked: {
                  if (!liveStore) return
                  liveStore.openResult(index)
                }
              }
            }
          }
        }

        // Optional short summary for selected result (flat mode only)
        Rectangle {
          width: parent.width
          visible: liveStore && liveStore.selectedResult && !liveStore.hasPrimary
          height: visible ? summaryInner.implicitHeight + Style.space(20) : 0
          radius: 12
          color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.22)

          Column {
            id: summaryInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(6)

            Text {
              text: "WITNESS"
              color: root.fwAccent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.6
            }

            Text {
              width: parent.width
              text: liveStore && liveStore.selectedResult
                ? (liveStore.selectedResult.title || "")
                : ""
              textFormat: Text.PlainText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: liveStore && liveStore.selectedResult
                ? (liveStore.selectedResult.snippet || "(no snippet)")
                : ""
              textFormat: Text.PlainText
              color: root.contentForeground
              opacity: 0.6
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }

        // Empty honesty
        Text {
          width: parent.width
          visible: liveStore && liveStore.lastPayload && liveStore.lastPayload.ok
                   && (!liveStore.results || !liveStore.results.length)
          text: "No matches. Try another query."
          color: root.contentForeground
          opacity: 0.5
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // Quiet footer
        Text {
          width: parent.width
          text: "unofficial · not affiliated with xAI / Grokipedia · Encyclopedic is Heinlein"
          color: root.contentForeground
          opacity: 0.22
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
