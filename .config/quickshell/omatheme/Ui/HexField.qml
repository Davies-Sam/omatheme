import QtQuick
import qs.Ui

// Hex entry that only reports colors Qt can actually parse, so a half-typed
// value never reaches the compositor.
Field {
  id: root

  property string value: "#000000"
  signal edited(string hex)

  maximumLength: 7
  text: root.value

  onTextChanged: {
    if (/^#[0-9a-fA-F]{6}$/.test(text) && text.toLowerCase() !== root.value.toLowerCase())
      root.edited(text.toLowerCase())
  }

  // Only overwrite while the user is elsewhere; retyping shouldn't fight
  // the sync.
  onValueChanged: if (!input.activeFocus) text = root.value
  onEditingFinished: text = root.value
}
