import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested details panel for Encyclopedic (loaded by BarWidget — not a separate kind).
// KeyboardPanel shell (Compliantish/Rocketlauncher).
// LOOK UP + MATCH hero + RELATED. No vendor chrome.
Panel {
  id: root
  moduleName: "kenhara.encyclopedic"
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

  readonly property int panelBaseHeight: Style.space(680)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(root.panelBaseHeight)
    popoutSwitching: root.popoutSwitching
    popoutSwitchClosing: root.popoutSwitchClosing

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

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

            Row {
              spacing: Style.space(8)
              Text {
                text: "\uf002"
                color: root.fwAccent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "ENCYCLOPEDIC"
                color: root.fwAccent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 3.2
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              text: "look it up"
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
                font.pixelSize: Style.font.body
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
                  font.pixelSize: Style.font.body
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
              font.pixelSize: Style.font.body
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

          // Toast / error (+ one-tap retry when transient)
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: liveStore && liveStore.lastError && liveStore.lastError.length

            Text {
              width: parent.width
              text: liveStore ? liveStore.lastError : ""
              color: Color.urgent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: liveStore && liveStore.lastRetryable
                && !(liveStore && liveStore.loading)
              text: "Try again"
              color: root.fwAccent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.underline: retryMa.containsMouse
              opacity: retryMa.containsMouse ? 1.0 : 0.85

              MouseArea {
                id: retryMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (liveStore) liveStore.lookUp()
              }
            }
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
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  visible: {
                    if (liveStore && liveStore.articleIsPrimary && liveStore.articleBody)
                      return true
                    if (liveStore && liveStore.articleLoading && liveStore.articleIsPrimary)
                      return true
                    return !!(liveStore && liveStore.primary && liveStore.primary.snippet
                              && String(liveStore.primary.snippet).length)
                  }
                  text: {
                    if (liveStore && liveStore.articleIsPrimary && liveStore.articleBody)
                      return liveStore.articleBody
                    if (liveStore && liveStore.articleLoading && liveStore.articleIsPrimary)
                      return (liveStore.primary && liveStore.primary.snippet)
                        ? liveStore.primary.snippet
                        : "Loading article…"
                    return liveStore && liveStore.primary ? (liveStore.primary.snippet || "") : ""
                  }
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  opacity: 0.58
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: {
                    if (liveStore && liveStore.articleIsPrimary && liveStore.articleBody)
                      return liveStore.articleExpanded ? 0 : 16
                    return 3
                  }
                  elide: Text.ElideRight
                }

                // Expand / collapse the in-panel article (fetches if needed)
                Text {
                  text: {
                    if (liveStore && liveStore.articleLoading && liveStore.articleIsPrimary)
                      return "Loading…"
                    if (liveStore && liveStore.articleIsPrimary && liveStore.articleBody
                        && liveStore.articleExpanded)
                      return "▾ Show less"
                    return "▸ Show more"
                  }
                  color: showMoreMa.containsMouse ? Qt.lighter(root.fwAccent, 1.15) : root.fwAccent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true

                  MouseArea {
                    id: showMoreMa
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !(liveStore && liveStore.articleLoading && liveStore.articleIsPrimary)
                    onClicked: if (liveStore) liveStore.toggleHero()
                  }
                }

                ResultActions {
                  primary: true
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
                readonly property bool previewed: !!(liveStore && liveStore.selectedResult
                  && liveStore.sameResult(liveStore.selectedResult, modelData))
                width: contentCol.width
                height: relatedInner.implicitHeight + Style.space(20)
                radius: 12
                color: relatedCardMa.containsMouse
                  ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09)
                  : root.surfaceColor
                border.width: 1
                border.color: previewed
                  ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.45)
                  : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

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
                    font.pixelSize: Style.font.body
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

                  ResultActions {
                    result: modelData
                  }
                }

                MouseArea {
                  id: relatedCardMa
                  anchors.fill: parent
                  z: -1
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!liveStore) return
                    liveStore.previewObject(modelData)
                  }
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
                readonly property bool previewed: !!(liveStore && liveStore.selectedIndex === index)
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
                    font.pixelSize: Style.font.body
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

                  ResultActions {
                    result: modelData
                    resultIndex: index
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

          // WITNESS preview for selected related / flat result (not the MATCH hero)
          Rectangle {
            width: parent.width
            visible: liveStore && liveStore.showingWitness
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
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: {
                  var sel = liveStore ? liveStore.selectedResult : null
                  var slug = sel ? String(sel.slug || "") : ""
                  if (liveStore && liveStore.articleLoading && slug === liveStore.articleRequestSlug)
                    return "Loading article…"
                  if (liveStore && liveStore.articleBody && slug === liveStore.articleSlug)
                    return liveStore.articleBody
                  return sel ? (sel.snippet || "(no snippet)") : ""
                }
                textFormat: Text.PlainText
                color: root.contentForeground
                opacity: 0.6
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: {
                  var sel = liveStore ? liveStore.selectedResult : null
                  var slug = sel ? String(sel.slug || "") : ""
                  if (liveStore && liveStore.articleBody && slug === liveStore.articleSlug)
                    return liveStore.articleExpanded ? 0 : 16
                  return 16
                }
                elide: Text.ElideRight
              }

              Text {
                visible: {
                  var sel = liveStore ? liveStore.selectedResult : null
                  var slug = sel ? String(sel.slug || "") : ""
                  if (!(liveStore && liveStore.articleBody && slug === liveStore.articleSlug))
                    return false
                  return true
                }
                text: liveStore && liveStore.articleExpanded ? "▾ Show less" : "▸ Show more"
                color: witnessMoreMa.containsMouse ? Qt.lighter(root.fwAccent, 1.15) : root.fwAccent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true

                MouseArea {
                  id: witnessMoreMa
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!liveStore) return
                    liveStore.articleExpanded = !liveStore.articleExpanded
                    liveStore.heroExpanded = liveStore.articleExpanded
                  }
                }
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
            text: "Unofficial · Grokipedia"
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

  // Compact glyph+label chips (FA/Nerd, tintable). Always-visible Preview / Open / Copy Link.
  component ActionChip: Rectangle {
    id: chip
    property string glyph: ""
    property string label: ""
    property bool accent: false
    signal clicked()

    readonly property bool hovered: chipMa.containsMouse

    implicitWidth: chipRow.implicitWidth + Style.space(16)
    implicitHeight: Style.space(26)
    width: implicitWidth
    height: implicitHeight
    radius: 6
    color: chip.accent
      ? (chip.hovered
          ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.34)
          : Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.22))
      : (chip.hovered
          ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
          : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08))
    border.width: 1
    border.color: chip.accent
      ? Qt.rgba(root.fwAccent.r, root.fwAccent.g, root.fwAccent.b, 0.5)
      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text {
        text: chip.glyph
        color: chip.accent ? root.fwAccent : root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: chip.label
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: chip.accent
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    MouseArea {
      id: chipMa
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component ResultActions: Row {
    id: actions
    property var result: null
    property bool primary: false
    property int resultIndex: -1
    spacing: Style.space(8)

    ActionChip {
      glyph: "\uf06e"
      label: "Preview"
      accent: true
      onClicked: {
        if (!root.liveStore) return
        if (actions.primary)
          root.liveStore.previewPrimary()
        else if (actions.resultIndex >= 0)
          root.liveStore.previewResult(actions.resultIndex)
        else
          root.liveStore.previewObject(actions.result)
      }
    }
    ActionChip {
      glyph: "\uf08e"
      label: "Open"
      onClicked: {
        if (!root.liveStore) return
        if (actions.primary)
          root.liveStore.openPrimary()
        else if (actions.resultIndex >= 0)
          root.liveStore.openResult(actions.resultIndex)
        else if (actions.result)
          root.liveStore.openUrlExternal(actions.result.url || "", actions.result.slug || "")
      }
    }
    ActionChip {
      glyph: "\uf0c5"
      label: "Copy Link"
      onClicked: {
        if (!root.liveStore) return
        if (actions.primary)
          root.liveStore.copyPrimaryLink()
        else if (actions.resultIndex >= 0)
          root.liveStore.copyLink(actions.resultIndex)
        else if (actions.result)
          root.liveStore.copyText(actions.result.url || "")
      }
    }
  }
}
