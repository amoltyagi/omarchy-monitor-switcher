import QtQuick
import QtTest
import "../.." as Plugin

Item {
  width: 900
  height: 650
  property var fixture: [
    {output: "DP-1", alias: "Main", num: 1, connected: true, enabled: true, usable: true,
      width: 1920, height: 1080, configuredWidth: 1920, configuredHeight: 1080, scale: 1,
      nightLight: {enabled: false, active: false, available: true, temperature: 4000},
      physicalWidth: 600, physicalHeight: 340, x: 0, y: 0, refreshRate: 60,
      availableModes: [{width: 1920, height: 1080, rate: 60, mode: "1920x1080@60.00"}]},
    {output: "DP-2", alias: "Side", num: 2, connected: true, enabled: true, usable: true,
      width: 2560, height: 1440, configuredWidth: 2560, configuredHeight: 1440, scale: 1,
      nightLight: {enabled: false, active: false, available: true, temperature: 4000},
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
  SignalSpy { id: nightLightSpy; target: gallery; signalName: "nightLightRequested" }
  SignalSpy { id: powerSpy; target: gallery; signalName: "toggleRequested" }

  TestCase {
    name: "MonitorControls"
    when: windowShown

    function init() {
      gallery.closeEditor()
      gallery.monitors = fixture
      gallery.width = 800
      gallery.y = 0
      gallery.busy = false
      gallery.pendingPowerOutput = ""
      gallery.visible = false
      arrangement.visible = false
      arrangement.visible = true
      arrangement.reset()
      settingSpy.clear()
      powerSpy.clear()
      nightLightSpy.clear()
      wait(200)
    }

    function test_apply_is_distinct_and_only_submits_a_valid_draft() {
      var apply = findChild(arrangement, "apply-arrangement")
      verify(apply !== null)
      compare(apply.primary, true)
      compare(apply.width, arrangement.width)
      verify(apply.height >= 42)
      compare(apply.enabled, false)
      arrangement.place("above")
      compare(arrangement.problem, "")
      compare(apply.enabled, true)
      arrangement.busy = true
      compare(apply.enabled, false)
      arrangement.busy = false
    }

    function test_night_light_targets_its_own_display() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var chip = findChild(gallery, "nightlight-DP-2")
      mouseClick(chip, chip.width / 2, chip.height / 2)
      compare(gallery.editorOutput, "DP-2")
      compare(gallery.editorField, "nightlight")
      var popup = chip.popup
      verify(popup.visible)
      verify(findChild(gallery, "specifications-DP-2").visible,
        "Night Light must leave the monitor specifications visible")
      compare(popup.parent, chip)
      verify(popup.y >= chip.height)
      gallery.moveEditor(2)
      gallery.applyEditor()
      compare(nightLightSpy.count, 1)
      compare(nightLightSpy.signalArguments[0][0], "DP-2")
      compare(nightLightSpy.signalArguments[0][1], "4000")
      compare(settingSpy.count, 0)
    }

    function test_controls_do_not_overlap_at_different_panel_widths() {
      arrangement.visible = false
      gallery.visible = true
      gallery.monitors = [
        Object.assign({}, fixture[0], {physicalWidth: 590, physicalHeight: 330, enabled: false}),
        Object.assign({}, fixture[1], {physicalWidth: 890, physicalHeight: 390}),
        Object.assign({}, fixture[0], {output: "HDMI-A-1", physicalWidth: 600, physicalHeight: 340, enabled: false})
      ]
      for (var w of [480, 760, 1060]) {
        gallery.width = w
        wait(50)
        for (var m of gallery.monitors) {
          var resolution = findChild(gallery, "resolution-group-" + m.output)
          var row = findChild(gallery, "specification-row-" + m.output)
          verify(resolution.y + resolution.height + 4 <= row.y,
            "Status/resolution must not overlap refresh/scale at width " + w)
        }
      }
    }

    function test_night_light_opens_upward_near_window_bottom() {
      arrangement.visible = false
      gallery.visible = true
      gallery.y = 200
      gallery.openEditor(1, "nightlight")
      wait(100)
      var chip = findChild(gallery, "nightlight-DP-2")
      verify(chip.popup.visible)
      verify(chip.popup.y < 0, "Open above the toggle when there is no room below")
      var point = chip.popup.contentItem.mapToItem(null, 0, 0)
      verify(point.y >= 0)
      verify(point.y + chip.popup.contentItem.height <= 650)
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

    function test_selecting_current_value_does_not_create_a_confirmation() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var chip = findChild(gallery, "refresh-DP-2")
      mouseClick(chip, chip.width / 2, chip.height / 2)
      compare(gallery.editorIndex, 0)
      gallery.applyEditor()
      compare(settingSpy.count, 0)
      compare(gallery.editorOutput, "")
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

    function test_rotation_opens_from_the_chin_and_targets_its_own_display() {
      arrangement.visible = false
      gallery.visible = true
      wait(100)
      var button = findChild(gallery, "rotation-DP-2")
      verify(button !== null)
      mouseClick(button, button.width / 2, button.height / 2)
      compare(gallery.editorOutput, "DP-2")
      compare(gallery.editorField, "rotation")
      verify(button.popup.visible)
      compare(button.popup.parent, button)
      verify(findChild(gallery, "specifications-DP-2").visible, "rotation keeps the screen specifications visible")
      compare(gallery.choices.length, 4)
      compare(gallery.editorInitialIndex, 0, "current landscape rotation is marked")
      gallery.applyEditor()
      compare(settingSpy.count, 0, "choosing the current rotation is a no-op")
      mouseClick(button, button.width / 2, button.height / 2)
      wait(50) // let the previous opening's delegates be destroyed
      var option = findChild(button.popup.contentItem, "rotation-option-90")
      compare(option.modelData.value, "90")
      verify(option !== null)
      mouseClick(option, option.width / 2, option.height / 2)
      compare(settingSpy.count, 1)
      compare(settingSpy.signalArguments[0][0], "rotate")
      compare(settingSpy.signalArguments[0][1], "DP-2")
      compare(settingSpy.signalArguments[0][2], "90")
      compare(gallery.editorOutput, "")
    }

    function test_rotation_is_unavailable_for_an_unusable_display() {
      arrangement.visible = false
      gallery.visible = true
      gallery.monitors = [fixture[0], Object.assign({}, fixture[1], {usable: false, enabled: false})]
      wait(50)
      var button = findChild(gallery, "rotation-DP-2")
      compare(button.enabled, false)
      gallery.openEditor(1, "rotation")
      compare(gallery.editorOutput, "")
    }

    function test_portrait_card_keeps_readable_non_overlapping_controls() {
      arrangement.visible = false
      gallery.visible = true
      gallery.monitors = [
        Object.assign({}, fixture[0], {physicalWidth: 590, physicalHeight: 330}),
        Object.assign({}, fixture[1], {physicalWidth: 600, physicalHeight: 340, liveTransform: 1, transform: 1}),
        Object.assign({}, fixture[0], {output: "HDMI-A-1", physicalWidth: 890, physicalHeight: 390})
      ]
      for (var w of [480, 760, 1060]) {
        gallery.width = w
        wait(450)
        var bezel = findChild(gallery, "bezel-DP-2")
        verify(bezel.height > bezel.width, "portrait art is taller than wide at " + w)
        var resolution = findChild(gallery, "resolution-group-DP-2")
        var row = findChild(gallery, "specification-row-DP-2")
        verify(resolution.y + resolution.height + 4 <= row.y, "portrait specs do not overlap at " + w)
        var power = findChild(gallery, "power-DP-2")
        var night = findChild(gallery, "nightlight-DP-2")
        verify(night.width >= night.implicitWidth - 0.5 || night.width >= 150, "Night Light label stays readable at " + w)
        verify(power.width <= power.parent.width + 0.5)
        var rotate = findChild(gallery, "rotation-DP-2")
        var r = rotate.mapToItem(bezel, 0, 0)
        verify(r.x >= 0 && r.x + rotate.width <= bezel.width + 0.5, "rotate button stays on the chin at " + w)
        for (var m of gallery.monitors) {
          var a = findChild(gallery, "bezel-" + m.output).parent
          for (var n of gallery.monitors) {
            if (n.output <= m.output) continue
            var b = findChild(gallery, "bezel-" + n.output).parent
            verify(a.x + a.width <= b.x + 0.5 || b.x + b.width <= a.x + 0.5 || a.y + a.height <= b.y + 0.5 || b.y + b.height <= a.y + 0.5,
              "cards " + m.output + " and " + n.output + " overlap at " + w)
          }
        }
      }
    }

    function test_rotation_popup_opens_upward_near_window_bottom() {
      arrangement.visible = false
      gallery.visible = true
      gallery.y = 260
      gallery.openEditor(1, "rotation")
      wait(100)
      var button = findChild(gallery, "rotation-DP-2")
      verify(button.popup.visible)
      verify(button.popup.y < 0, "open above the chin when there is no room below")
      var point = button.popup.contentItem.mapToItem(null, 0, 0)
      verify(point.y >= 0)
      verify(point.y + button.popup.contentItem.height <= 650)
    }
  }
}
