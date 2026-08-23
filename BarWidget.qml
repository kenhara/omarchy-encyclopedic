import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Fair Witness bar entry — nested Panel.qml via Loader. kinds: ["bar-widget"] only.
BarWidget {
  id: root
  moduleName: "harris.fair-witness"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "monospace"

  // Cool ice accent — clinical Fair Witness observer vibe
  readonly property color fwAccent: Qt.rgba(0.43, 0.78, 0.91, 1.0)

  property int resultLimit: {
    try {
      if (root.settings && root.settings.resultLimit !== undefined)
        return witnessStore.clampLimit(root.settings.resultLimit)
      if (typeof root.setting === "function")
        return witnessStore.clampLimit(root.setting("resultLimit", 8))
    } catch (e) {}
    return 8
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // FW-13: local name — middle-click clears last search (+ cache)
  function clearLastSearch() {
    witnessStore.clearResult()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = witnessStore
  }

  function syncStoreSettings() {
    witnessStore.applySettings({
      resultLimit: root.resultLimit
    })
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    syncStoreSettings()
  }
  onResultLimitChanged: syncStoreSettings()

  WitnessStore {
    id: witnessStore
  }

  Component.onCompleted: {
    syncStoreSettings()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: witnessStore.barLabel || "● FW"
    horizontalMargin: 8.5
    tooltipText: {
      var tip = "Fair Witness — look it up · middle: clear"
      if (witnessStore.loading)
        tip = "Fair Witness — looking up… · middle: clear"
      return tip
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.clearLastSearch()
    }
  }
}
