pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HalC2.Shell
import HalC2.Bricks

// t3code-tracker's settings: what it follows, and the agent that checks upstream and
// the one that implements, each with its model, access and prompt. The agents and
// their models come from the plugin's `settings` call; everything is saved
// together, and what the plugin refuses stays unsaved with its reason.
ColumnLayout {
    id: settings

    property var plugin
    // As the MC has them, and as the page shows them.
    property var saved: ({})
    property var values: ({})
    property var providers: []
    property bool loaded: false
    property bool dirty: false
    property bool saving: false
    property string refusal: ""
    property string problem: ""
    readonly property color foreground: Theme.palette.color("text", "#e4e4e7")
    readonly property color muted: Theme.palette.color("textMuted", "#a1a1aa")
    readonly property color border: Theme.palette.color("border", "#27272a")
    readonly property color errorColor: Theme.palette.color("error", "#ef4444")

    function load() {
        settings.plugin.call("settings", {}, (result, error) => {
            if (error) {
                settings.problem = error;
                return;
            }
            settings.problem = "";
            settings.saved = result.settings ?? {};
            settings.providers = result.providers ?? [];
            settings.loaded = true;
            settings.reset();
        });
    }

    function reset() {
        settings.values = Object.assign({}, settings.saved);
        settings.dirty = false;
        settings.refusal = "";
    }

    function set(key, value) {
        const next = Object.assign({}, settings.values);
        next[key] = value;
        settings.values = next;
        settings.dirty = true;
    }

    // Changes `field` of an agent setting (`checking` or `implementing`).
    function setAgent(role, field, value) {
        const agent = Object.assign({}, settings.values[role] ?? {});
        agent[field] = value;
        settings.set(role, agent);
    }

    function save() {
        settings.saving = true;
        settings.refusal = "";
        settings.plugin.saveSettings(settings.values, (result, error) => {
            settings.saving = false;
            if (error)
                settings.refusal = error;
            else
                settings.load();
        });
    }

    objectName: "t3codeTrackerSettings"
    width: parent ? parent.width : implicitWidth
    spacing: 22
    Component.onCompleted: load()

    component Heading: Label {
        Layout.fillWidth: true
        Layout.topMargin: 6
        color: settings.foreground
        font.pixelSize: Math.round(14 * Theme.fontScale)
        font.weight: Font.DemiBold
    }

    component Hint: Label {
        Layout.fillWidth: true
        visible: text.length > 0
        color: settings.muted
        wrapMode: Text.Wrap
        font.pixelSize: Math.round(12 * Theme.fontScale)
    }

    // A setting: its label, what it means, and its control below.
    component Field: ColumnLayout {
        id: field

        property string label
        property string hint
        default property alias content: controls.data

        Layout.fillWidth: true
        spacing: 6

        Label {
            text: field.label
            color: settings.foreground
            font.pixelSize: Math.round(13 * Theme.fontScale)
            font.weight: Font.Medium
        }

        Hint {
            text: field.hint
        }

        ColumnLayout {
            id: controls

            Layout.fillWidth: true
            spacing: 6
        }
    }

    // One of a few values, side by side.
    component Choice: Flow {
        id: choice

        property var options: []
        property var value
        signal picked(var value)

        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: choice.options

            delegate: Rectangle {
                id: option

                required property var modelData
                readonly property bool chosen: modelData.value === choice.value

                objectName: "choice:" + modelData.value
                implicitWidth: optionText.implicitWidth + 20
                implicitHeight: 28
                radius: Math.min(Theme.radius, 8)
                color: chosen ? Theme.palette.color("accentSurface", "#27272a") : "transparent"
                border.color: chosen || activeFocus ? Theme.palette.color("focus", "#3b82f6") : settings.border
                border.width: activeFocus ? 2 : 1
                activeFocusOnTab: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        choice.picked(modelData.value);
                        event.accepted = true;
                    }
                }
                Accessible.role: Accessible.RadioButton
                Accessible.name: optionText.text
                Accessible.checkable: true
                Accessible.checked: chosen
                Accessible.onPressAction: choice.picked(modelData.value)

                Text {
                    id: optionText

                    anchors.centerIn: parent
                    text: option.modelData.label
                    color: settings.foreground
                    font.pixelSize: Math.round(12 * Theme.fontScale)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: choice.picked(option.modelData.value)
                }
            }
        }
    }

    component Area: TextArea {
        Layout.fillWidth: true
        wrapMode: TextEdit.Wrap
        color: settings.foreground
        font.pixelSize: Math.round(13 * Theme.fontScale)
        background: Rectangle {
            radius: Math.min(Theme.radius, 8)
            color: Theme.palette.color("input", "#18181b")
            border.color: Theme.palette.color("border", "#27272a")
        }
    }

    // An agent setting and its prompt: which agent, which of its models, the model's
    // options, how much it may do on its own, and what it is asked.
    component Agent: ColumnLayout {
        id: section

        property string role
        property string promptKey
        property string title
        property string promptHint
        readonly property var agent: settings.values[role] ?? {}
        readonly property var provider: settings.providers.find(each => each.instanceId === agent.provider) ?? null
        readonly property var models: provider?.models ?? []
        // The model it will run on: the picked one, else the agent's default.
        readonly property var modelEntry: models.find(each => each.slug === agent.model) ?? models.find(each => each.isDefault) ?? models[0] ?? null

        objectName: "t3codeTrackerAgent:" + role
        Layout.fillWidth: true
        spacing: 16

        Heading {
            text: section.title
        }

        Field {
            label: qsTr("Agent and model")

            RowLayout {
                spacing: 8

                ShellComboBox {
                    objectName: "t3codeTrackerSetting:" + section.role + ":provider"
                    outline: true
                    implicitWidth: 200
                    model: settings.providers.map(each => each.name)
                    currentIndex: settings.providers.findIndex(each => each.instanceId === section.agent.provider)
                    displayText: currentIndex >= 0 ? currentText : (section.agent.provider ?? "")
                    Accessible.name: qsTr("Agent")
                    onActivated: index => {
                        const agent = Object.assign({}, section.agent, {
                            provider: settings.providers[index].instanceId,
                            model: "",
                            modelOptions: {}
                        });
                        settings.set(section.role, agent);
                    }
                }

                ShellComboBox {
                    objectName: "t3codeTrackerSetting:" + section.role + ":model"
                    outline: true
                    implicitWidth: 240
                    model: [qsTr("Its default model")].concat(section.models.map(each => each.name || each.slug))
                    currentIndex: (section.agent.model ?? "") === "" ? 0 : section.models.findIndex(each => each.slug === section.agent.model) + 1
                    displayText: currentIndex >= 0 ? currentText : section.agent.model
                    Accessible.name: qsTr("Model")
                    onActivated: index => {
                        const agent = Object.assign({}, section.agent, {
                            model: index === 0 ? "" : section.models[index - 1].slug,
                            modelOptions: {}
                        });
                        settings.set(section.role, agent);
                    }
                }
            }
        }

        // What the chosen model offers besides itself: its reasoning effort first of all.
        Repeater {
            model: section.modelEntry?.options ?? []

            delegate: Field {
                id: option

                required property var modelData
                readonly property var chosen: section.agent.modelOptions ?? {}

                function pick(value) {
                    const options = Object.assign({}, option.chosen);
                    if (value === undefined)
                        delete options[option.modelData.id];
                    else
                        options[option.modelData.id] = value;
                    settings.setAgent(section.role, "modelOptions", options);
                }

                objectName: "t3codeTrackerSetting:" + section.role + ":modelOption:" + modelData.id
                label: modelData.label ?? modelData.id

                Choice {
                    visible: option.modelData.type !== "boolean"
                    options: [
                        {
                            value: "",
                            label: qsTr("Its default")
                        }
                    ].concat((option.modelData.options ?? []).map(each => ({
                                value: each.id,
                                label: each.label ?? each.id
                            })))
                    value: option.chosen[option.modelData.id] ?? ""
                    onPicked: value => option.pick(value === "" ? undefined : value)
                }

                Switch {
                    visible: option.modelData.type === "boolean"
                    checked: option.chosen[option.modelData.id] === true
                    Accessible.name: option.label
                    onToggled: option.pick(checked)
                }
            }
        }

        Field {
            label: qsTr("Access")
            hint: qsTr("It works in a new worktree of the ledger's project.")

            Choice {
                objectName: "t3codeTrackerSetting:" + section.role + ":runtimeMode"
                options: [
                    {
                        value: "approval-required",
                        label: qsTr("Ask before acting")
                    },
                    {
                        value: "auto-accept-edits",
                        label: qsTr("Accept edits")
                    },
                    {
                        value: "auto",
                        label: qsTr("Auto")
                    },
                    {
                        value: "full-access",
                        label: qsTr("Full access")
                    }
                ]
                value: section.agent.runtimeMode ?? "auto-accept-edits"
                onPicked: value => settings.setAgent(section.role, "runtimeMode", value)
            }
        }

        Field {
            label: qsTr("Prompt")
            hint: section.promptHint

            Area {
                objectName: "t3codeTrackerSetting:" + section.promptKey
                Layout.preferredHeight: Math.max(120, implicitHeight)
                text: settings.values[section.promptKey] ?? ""
                Accessible.name: qsTr("%1 prompt").arg(section.title)
                onTextChanged: if (activeFocus)
                    settings.set(section.promptKey, text)
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !settings.loaded || settings.problem.length > 0
        text: settings.problem.length > 0 ? qsTr("The settings could not be read: %1").arg(settings.problem) : qsTr("Loading…")
        color: settings.problem.length > 0 ? settings.errorColor : settings.muted
        wrapMode: Text.Wrap
        font.pixelSize: Math.round(13 * Theme.fontScale)
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: settings.loaded
        spacing: 22

        Heading {
            text: qsTr("What it follows")
        }

        Field {
            label: qsTr("Ledger repository")
            hint: qsTr("owner/name of the repository whose features/ cite upstream. A checkout of it must be a project on this MC.")

            ShellTextField {
                objectName: "t3codeTrackerSetting:ledger"
                implicitWidth: 240
                text: settings.values.ledger ?? ""
                onTextEdited: settings.set("ledger", text)
            }
        }

        Field {
            label: qsTr("Upstream repository")
            hint: qsTr("owner/name on GitHub. Only its main branch is followed.")

            ShellTextField {
                objectName: "t3codeTrackerSetting:upstream"
                implicitWidth: 240
                text: settings.values.upstream ?? ""
                onTextEdited: settings.set("upstream", text)
            }
        }

        Field {
            label: qsTr("Look every (minutes)")

            ShellTextField {
                objectName: "t3codeTrackerSetting:pollMinutes"
                implicitWidth: 100
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator {
                    bottom: 1
                }
                text: String(settings.values.pollMinutes ?? "")
                onTextEdited: if (acceptableInput)
                    settings.set("pollMinutes", Number(text))
            }
        }

        Agent {
            role: "checking"
            promptKey: "checkPrompt"
            title: qsTr("Checking upstream")
            promptHint: qsTr("{{upstream}}, {{ledger}}, {{cursor}} and {{pending}} are filled in.")
        }

        Agent {
            role: "implementing"
            promptKey: "implementPrompt"
            title: qsTr("Implementing")
            promptHint: qsTr("{{file}}, {{working}}, {{blocked}}, {{upstream}} and {{pullRequests}} are filled in.")
        }

        Label {
            objectName: "t3codeTrackerRefusal"
            Layout.fillWidth: true
            visible: settings.refusal.length > 0
            text: qsTr("Not saved: %1").arg(settings.refusal)
            color: settings.errorColor
            wrapMode: Text.Wrap
            font.pixelSize: Math.round(12 * Theme.fontScale)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            ShellButton {
                subtle: true
                text: qsTr("Discard changes")
                enabled: settings.dirty && !settings.saving
                onClicked: settings.reset()
            }

            ShellButton {
                objectName: "t3codeTrackerSave"
                primary: true
                text: settings.saving ? qsTr("Saving…") : qsTr("Save")
                enabled: settings.dirty && !settings.saving
                onClicked: settings.save()
            }
        }
    }
}
