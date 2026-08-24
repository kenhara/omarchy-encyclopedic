import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Encyclopedic bar entry — nested Panel.qml via Loader. kinds: ["bar-widget"] only.
BarWidget {
  id: root
  moduleName: "kenhara.encyclopedic"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "monospace"

  // Cool ice accent — clinical Encyclopedic observer vibe
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
    if (panelLoader.item) {
      panelLoader.item.toggle()
      return
    }
    var detail = root.panelLoadError && root.panelLoadError.length
      ? (" load error: " + root.panelLoadError)
      : (" Loader.status=" + panelLoader.status)
    console.warn(moduleName + " toggle ignored — panelLoader.item is null;" + detail)
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

  property string panelLoadError: ""

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.panelLoadError = ""
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        var err = ""
        try {
          if (sourceComponent)
            err = String(sourceComponent.errorString || "")
        } catch (e) {}
        root.panelLoadError = err.length ? err : "Panel.qml failed to load"
        console.warn(moduleName + " panel load failed: " + root.panelLoadError)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: witnessStore.barLabel || "📖"
    horizontalMargin: 8.5
    tooltipText: {
      var tip = "Encyclopedic — look it up · middle: clear"
      if (witnessStore.loading)
        tip = "Encyclopedic — looking up… · middle: clear"
      if (root.panelLoadError && root.panelLoadError.length) {
        var pe = root.panelLoadError
        if (pe.length > 120)
          pe = pe.substring(0, 117) + "…"
        tip += " · panel load error — " + pe
      }
      return tip
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.clearLastSearch()
    }
  }
}
