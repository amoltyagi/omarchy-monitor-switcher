import QtQuick
import QtTest
import "../.." as Plugin

Item {
  width: 900
  height: 650
  property var fixture: [
    {output: "DP-1", alias: "Main", num: 1, connected: true, enabled: true, usable: true,
      width: 1920, height: 1080, configuredWidth: 1920, configuredHeight: 1080, scale: 1,
      physicalWidth: 600, physicalHeight: 340, x: 0, y: 0, refreshRate: 60,
      availableModes: [{width: 1920, height: 1080, rate: 60, mode: "1920x1080@60.00"}]},
    {output: "DP-2", alias: "Side", num: 2, connected: true, enabled: true, usable: true,
      width: 2560, height: 1440, configuredWidth: 2560, configuredHeight: 1440, scale: 1,
      physicalWidth: 700, physicalHeight: 400, x: 1920, y: 0, refreshRate: 59.94,
      availableModes: [{width: 2560, height: 1440, rate: 59.94, mode: "2560x1440@59.94"},
        {width: 2560, height: 1440, rate: 120, mode: "2560x1440@120.00"}]}
  ]

  Plugin.ArrangementEditor { id: arrangement; width: 800; monitors: fixture }
  Plugin.DisplayGallery {
    id: gallery
    width: 800
    monitors: fixture
    focusedMonitor: "DP-1"
    enabledCount: 2
    visible: false
  }
  SignalSpy { id: settingSpy; target: gallery; signalName: "settingRequested" }
  SignalSpy { id: powerSpy; target: gallery; signalName: "toggleRequested" }

  TestCase {
    name: "MonitorControls"
    when: windowShown

    function init() {
      gallery.closeEditor()
      gallery.busy = false
      gallery.pendingPowerOutput = ""
      gallery.visible = false
      arrangement.visible = false
      arrangement.visible = true
      arrangement.reset()
      settingSpy.clear()
      powerSpy.clear()
      wait(200)
    }

    function test_drag_retains_pointer_and_updates_preview() {
      var display = findChild(arrangement, "arrangement-DP-2")
      verify(display !== null)
      var center = display.mapToItem(arrangement, display.width / 2, display.height / 2)
      mousePress(display, display.width / 2, display.height / 2, Qt.LeftButton)
      mouseMove(arrangement, center.x + 50, center.y + 10, 30)
      mouseRelease(arrangement, center.x + 50, center.y + 10, Qt.LeftButton)
      verify(arrangement.dirty)
      verify(arrangement.draft[1].x > 1920)
      compare(arrangement.draft.length, 2)
      compare(arrangement.dragging, false)
      compare(arrangement.original[1].x, 1920)
    }

    function test_click_setting_targets_its_card_not_focused_monitor() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var chip = findChild(gallery, "refresh-DP-2")
      verify(chip !== null)
      mouseClick(chip, chip.width / 2, chip.height / 2)
      compare(gallery.editorOutput, "DP-2")
      compare(gallery.editorField, "refresh")
      compare(gallery.editorInitialIndex, 0)
      gallery.moveEditor(1)
      gallery.applyEditor()
      compare(settingSpy.count, 1)
      compare(settingSpy.signalArguments[0][0], "mode")
      compare(settingSpy.signalArguments[0][1], "DP-2")
      compare(settingSpy.signalArguments[0][2], "2560x1440@120.00")
    }

    function test_wheel_over_setting_does_not_edit() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var chip = findChild(gallery, "scale-DP-2")
      mouseWheel(chip, chip.width / 2, chip.height / 2, 0, -120)
      compare(gallery.editorOutput, "")
      compare(settingSpy.count, 0)
    }

    function test_power_switch_waits_for_live_state_and_blocks_duplicate_clicks() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var toggle = findChild(gallery, "power-DP-1")
      verify(toggle !== null)
      mouseClick(toggle, toggle.width / 2, toggle.height / 2)
      compare(powerSpy.count, 1)
      compare(powerSpy.signalArguments[0][0], "DP-1")
      compare(powerSpy.signalArguments[0][1], true)
      compare(toggle.checked, true, "a click must not pretend the hardware has already switched")
      gallery.busy = true
      gallery.pendingPowerOutput = "DP-1"
      gallery.pendingPowerOn = false
      compare(toggle.pending, true)
      compare(toggle.enabled, false)
      mouseClick(toggle, toggle.width / 2, toggle.height / 2)
      compare(powerSpy.count, 1)
    }
  }
}
